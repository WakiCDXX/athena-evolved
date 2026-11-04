#!/usr/bin/env python3
"""
LLM Gateway Abstraction for Athena

Portkey-inspired gateway with:
- Fallback routing across providers/models
- Retry with exponential backoff
- Request timeouts
- Declarative guardrails (input/output)
- Semantic + simple caching
- Observability logging (cost, latency, tokens)
- Config-driven via llm_gateway.json
"""

import json
import os
import sys
import time
import hashlib
import uuid
from pathlib import Path
from typing import Any, Dict, List, Optional, Callable
from dataclasses import dataclass, asdict, field
from datetime import datetime
from abc import ABC, abstractmethod
import threading


@dataclass
class LLMRequest:
    messages: List[Dict[str, str]]
    model_preference: str = "default"
    temperature: float = 0.7
    max_tokens: int = 4096
    tools: Optional[List[Dict]] = None
    tool_choice: Optional[str] = None
    metadata: Dict[str, Any] = field(default_factory=dict)


@dataclass
class LLMResponse:
    content: str
    model: str
    provider: str
    tokens_in: int
    tokens_out: int
    latency_ms: int
    cost_usd: float
    cached: bool = False
    guardrail_results: Dict[str, Any] = field(default_factory=dict)
    error: Optional[str] = None


@dataclass
class GuardrailRule:
    type: str  # "input" or "output"
    name: str
    config: Dict[str, Any]
    on_fail: str  # "deny", "retry_with_feedback", "redact", "log_only"


class CacheBackend(ABC):
    @abstractmethod
    def get(self, key: str) -> Optional[LLMResponse]:
        pass

    @abstractmethod
    def set(self, key: str, response: LLMResponse, ttl: int):
        pass

    @abstractmethod
    def semantic_get(self, messages: List[Dict], threshold: float) -> Optional[LLMResponse]:
        pass

    @abstractmethod
    def semantic_set(self, messages: List[Dict], response: LLMResponse, ttl: int):
        pass


class SimpleCache(CacheBackend):
    """In-memory simple cache with TTL"""

    def __init__(self):
        self._cache: Dict[str, tuple] = {}  # key -> (response, expiry)
        self._lock = threading.Lock()

    def _make_key(self, messages: List[Dict], model: str, params: Dict) -> str:
        content = json.dumps({
            "messages": messages,
            "model": model,
            "params": params
        }, sort_keys=True, separators=(",", ":"))
        return hashlib.sha256(content.encode()).hexdigest()[:32]

    def get(self, key: str) -> Optional[LLMResponse]:
        with self._lock:
            if key in self._cache:
                response, expiry = self._cache[key]
                if time.time() < expiry:
                    response.cached = True
                    print(f"RAW_LLM_RESPONSE: {response.content}"); return response
                else:
                    del self._cache[key]
        return None

    def set(self, key: str, response: LLMResponse, ttl: int):
        with self._lock:
            self._cache[key] = (response, time.time() + ttl)

    def semantic_get(self, messages: List[Dict], threshold: float) -> Optional[LLMResponse]:
        # Simple cache doesn't support semantic search
        return None

    def semantic_set(self, messages: List[Dict], response: LLMResponse, ttl: int):
        pass


class SemanticCache(CacheBackend):
    """Semantic cache using embeddings for similarity search"""

    def __init__(self, embed_fn: Optional[Callable] = None):
        self._cache: List[tuple] = []  # (messages, embedding, response, expiry)
        self._lock = threading.Lock()
        self._embed_fn = embed_fn

    def _embed(self, messages: List[Dict]) -> List[float]:
        if self._embed_fn:
            return self._embed_fn(messages)
        # Fallback: hash-based pseudo-embedding
        content = json.dumps(messages, sort_keys=True)
        hash_bytes = hashlib.sha256(content.encode()).digest()
        return [b / 255.0 for b in hash_bytes[:32]]

    def _cosine_sim(self, a: List[float], b: List[float]) -> float:
        dot = sum(x * y for x, y in zip(a, b))
        norm_a = sum(x * x for x in a) ** 0.5
        norm_b = sum(y * y for y in b) ** 0.5
        if norm_a == 0 or norm_b == 0:
            return 0.0
        return dot / (norm_a * norm_b)

    def get(self, key: str) -> Optional[LLMResponse]:
        # Not used for semantic cache
        return None

    def set(self, key: str, response: LLMResponse, ttl: int):
        pass

    def semantic_get(self, messages: List[Dict], threshold: float) -> Optional[LLMResponse]:
        with self._lock:
            query_emb = self._embed(messages)
            now = time.time()

            # Clean expired
            self._cache = [(m, e, r, ex) for m, e, r, ex in self._cache if ex > now]

            best_match = None
            best_score = 0.0

            for cached_messages, cached_emb, response, expiry in self._cache:
                score = self._cosine_sim(query_emb, cached_emb)
                if score >= threshold and score > best_score:
                    best_score = score
                    best_match = response

            if best_match:
                best_match.cached = True
                return best_match

        return None

    def semantic_set(self, messages: List[Dict], response: LLMResponse, ttl: int):
        with self._lock:
            emb = self._embed(messages)
            self._cache.append((messages, emb, response, time.time() + ttl))


class Provider(ABC):
    """Abstract LLM provider"""

    @abstractmethod
    def call(self, request: LLMRequest) -> LLMResponse:
        pass

    @abstractmethod
    def get_name(self) -> str:
        pass

    @abstractmethod
    def supports_model(self, model: str) -> bool:
        pass


class AnthropicProvider(Provider):
    def __init__(self, api_key: str = None):
        self.api_key = api_key or os.environ.get("ANTHROPIC_API_KEY")
        self._client = None

    def _get_client(self):
        if self._client is None:
            try:
                import anthropic
                self._client = anthropic.Anthropic(api_key=self.api_key)
            except ImportError:
                raise RuntimeError("anthropic package not installed")
        return self._client

    def get_name(self) -> str:
        return "anthropic"

    def supports_model(self, model: str) -> bool:
        return model.startswith("claude-") or "claude" in model.lower()

    def call(self, request: LLMRequest) -> LLMResponse:
        client = self._get_client()
        start = time.time()

        # Convert messages format
        system = None
        messages = []
        for m in request.messages:
            if m["role"] == "system":
                system = m["content"]
            else:
                messages.append({"role": m["role"], "content": m["content"]})

        kwargs = {
            "model": request.model_preference,
            "messages": messages,
            "max_tokens": request.max_tokens,
            "temperature": request.temperature,
        }
        if system:
            kwargs["system"] = system
        if request.tools:
            kwargs["tools"] = request.tools
        if request.tool_choice:
            kwargs["tool_choice"] = request.tool_choice

        response = client.messages.create(**kwargs)

        latency_ms = int((time.time() - start) * 1000)

        # Extract content
        content = ""
        for block in response.content:
            if block.type == "text":
                content += block.text

        # Calculate cost (approximate)
        tokens_in = response.usage.input_tokens
        tokens_out = response.usage.output_tokens
        cost_usd = self._estimate_cost(request.model_preference, tokens_in, tokens_out)

        return LLMResponse(
            content=content,
            model=request.model_preference,
            provider="anthropic",
            tokens_in=tokens_in,
            tokens_out=tokens_out,
            latency_ms=latency_ms,
            cost_usd=cost_usd
        )

    def _estimate_cost(self, model: str, tokens_in: int, tokens_out: int) -> float:
        # Approximate pricing (update as needed)
        pricing = {
            "claude-opus-4": (15.0, 75.0),      # per 1M tokens
            "claude-sonnet-4": (3.0, 15.0),
            "claude-haiku-3.5": (0.25, 1.25),
            "claude-3-5-sonnet": (3.0, 15.0),
            "claude-3-5-haiku": (0.25, 1.25),
        }
        model_key = model.lower().replace("anthropic/", "")
        in_price, out_price = pricing.get(model_key, (3.0, 15.0))
        return (tokens_in * in_price + tokens_out * out_price) / 1_000_000


class OpenAIProvider(Provider):
    def __init__(self, api_key: str = None):
        self.api_key = api_key or os.environ.get("OPENAI_API_KEY")
        self.base_url = os.environ.get("OPENAI_BASE_URL", "https://api.openai.com/v1")
        self._client = None

    def _get_client(self):
        return self # We will handle the calls manually using requests to avoid the dependency hell

    def get_name(self) -> str:
        return "openai"

    def supports_model(self, model: str) -> bool:
        return True # Support all models via OpenRouter

    def call(self, request: LLMRequest) -> LLMResponse:
        import requests
        start = time.time()

        # Use OPENAI_MODEL env var if provided, otherwise the requested model
        model = os.environ.get("OPENAI_MODEL", request.model_preference)

        payload = {
            "model": model,
            "messages": request.messages,
            "temperature": request.temperature,
            "max_tokens": request.max_tokens,
        }

        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json"
        }

        try:
            response = requests.post(
                f"{self.base_url}/chat/completions",
                json=payload,
                headers=headers,
                timeout=60
            )
            response.raise_for_status()
            data = response.json()

            latency_ms = int((time.time() - start) * 1000)
            content = data["choices"][0]["message"]["content"]

            # Extract usage if available
            tokens_in = data.get("usage", {}).get("prompt_tokens", 0)
            tokens_out = data.get("usage", {}).get("completion_tokens", 0)
            cost_usd = self._estimate_cost(model, tokens_in, tokens_out)

            return LLMResponse(
                content=content,
                model=model,
                provider="openai",
                tokens_in=tokens_in,
                tokens_out=tokens_out,
                latency_ms=latency_ms,
                cost_usd=cost_usd
            )
        except Exception as e:
            raise RuntimeError(f"OpenRouter API call failed: {e}")

    def _estimate_cost(self, model: str, tokens_in: int, tokens_out: int) -> float:
        pricing = {
            "gpt-4o": (2.5, 10.0),
            "gpt-4o-mini": (0.15, 0.6),
            "o1-preview": (15.0, 60.0),
            "o1-mini": (3.0, 12.0),
        }
        model_key = model.lower().replace("openai/", "")
        in_price, out_price = pricing.get(model_key, (2.5, 10.0))
        return (tokens_in * in_price + tokens_out * out_price) / 1_000_000


class GuardrailsEngine:
    """Declarative guardrails validation"""

    def __init__(self, config_dir: str):
        self.config_dir = Path(config_dir)
        self.input_guardrails: List[GuardrailRule] = []
        self.output_guardrails: List[GuardrailRule] = []
        self._load_guardrails()

    def _load_guardrails(self):
        # Load from config directory
        for f in self.config_dir.glob("*.json"):
            try:
                with open(f) as fh:
                    config = json.load(fh)
                rule = GuardrailRule(
                    type=config.get("type", "output"),
                    name=f.stem,
                    config=config.get("config", {}),
                    on_fail=config.get("on_fail", "deny")
                )
                if rule.type == "input":
                    self.input_guardrails.append(rule)
                else:
                    self.output_guardrails.append(rule)
            except Exception as e:
                print(f"Failed to load guardrail {f}: {e}", file=sys.stderr)

    def validate_input(self, messages: List[Dict]) -> Dict[str, Any]:
        results = {}
        for rule in self.input_guardrails:
            result = self._check_rule(rule, messages)
            results[rule.name] = result
            if not result.get("passed", True) and rule.on_fail == "deny":
                return {"passed": False, "results": results, "blocked_by": rule.name}
        return {"passed": True, "results": results}

    def validate_output(self, content: str, schema: Dict = None) -> Dict[str, Any]:
        results = {}
        for rule in self.output_guardrails:
            result = self._check_rule(rule, content, schema)
            results[rule.name] = result
            if not result.get("passed", True):
                if rule.on_fail == "deny":
                    return {"passed": False, "results": results, "blocked_by": rule.name}
                elif rule.on_fail == "retry_with_feedback":
                    result["retry_feedback"] = result.get("feedback", "Output validation failed")
        return {"passed": True, "results": results}

    def _check_rule(self, rule: GuardrailRule, content: Any, schema: Dict = None) -> Dict[str, Any]:
        config = rule.config

        if rule.name == "json_schema" and schema:
            return self._validate_json_schema(content, schema)

        if rule.name == "contains":
            words = config.get("words", [])
            operator = config.get("operator", "any")  # any, all, none
            content_str = str(content).lower()

            if operator == "none":
                found = [w for w in words if w.lower() in content_str]
                return {"passed": len(found) == 0, "found": found}
            elif operator == "any":
                found = [w for w in words if w.lower() in content_str]
                return {"passed": len(found) > 0, "found": found}
            elif operator == "all":
                found = [w for w in words if w.lower() in content_str]
                return {"passed": len(found) == len(words), "found": found}

        if rule.name == "pii_detection":
            # Basic PII patterns
            import re
            patterns = {
                "email": r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b',
                "phone": r'\b\d{3}[-.]?\d{3}[-.]?\d{4}\b',
                "ssn": r'\b\d{3}-\d{2}-\d{4}\b',
                "api_key": r'\bsk-[A-Za-z0-9]{32,}\b',
            }
            found = []
            content_str = str(content)
            for name, pattern in patterns.items():
                if re.search(pattern, content_str):
                    found.append(name)
            action = config.get("action", "redact")
            return {"passed": len(found) == 0, "found": found, "action": action}

        if rule.name == "length":
            min_len = config.get("min", 0)
            max_len = config.get("max", 100000)
            content_len = len(str(content))
            return {"passed": min_len <= content_len <= max_len, "length": content_len}

        return {"passed": True, "note": f"Unknown guardrail: {rule.name}"}

    def _validate_json_schema(self, content: str, schema: Dict) -> Dict[str, Any]:
        try:
            import jsonschema
            data = json.loads(content)
            jsonschema.validate(data, schema)
            return {"passed": True}
        except json.JSONDecodeError as e:
            return {"passed": False, "error": f"Invalid JSON: {e}", "feedback": "Response must be valid JSON"}
        except jsonschema.ValidationError as e:
            return {"passed": False, "error": str(e), "feedback": f"Schema validation failed: {e.message}"}
        except ImportError:
            return {"passed": True, "note": "jsonschema not installed, skipping"}


class LLMGateway:
    def __init__(self, config_path: str = None):
        self.config_path = Path(config_path) if config_path else Path(__file__).parent.parent / "share" / "athena" / "llm_gateway.json"
        self.config = self._load_config()
        self.providers = self._init_providers()
        self.cache = self._init_cache()
        self.guardrails = GuardrailsEngine(str(self.config_path.parent / "guardrails"))
        self.observability_log: List[Dict] = []
        self._lock = threading.Lock()

    def _load_config(self) -> Dict:
        if self.config_path.exists():
            with open(self.config_path) as f:
                return json.load(f)
        return self._default_config()

    def _default_config(self) -> Dict:
        return {
            "routing": {
                "default": "claude-sonnet-4",
                "fallback_chain": ["claude-sonnet-4", "claude-haiku-3.5", "gpt-4o-mini"]
            },
            "retry": {"attempts": 3, "backoff": "exponential", "base_delay": 1, "max_delay": 60},
            "timeouts": {"connect": 10, "read": 60},
            "guardrails": {"input": [], "output": []},
            "cache": {"enabled": True, "ttl": 3600, "semantic_threshold": 0.95},
            "observability": {"enabled": True, "log_path": "llm_gateway_log.jsonl"}
        }

    def _init_providers(self) -> Dict[str, Provider]:
        providers = {}
        # Anthropic
        if os.environ.get("ANTHROPIC_API_KEY"):
            providers["anthropic"] = AnthropicProvider()
        # OpenAI
        if os.environ.get("OPENAI_API_KEY"):
            providers["openai"] = OpenAIProvider()
        return providers

    def _init_cache(self) -> CacheBackend:
        if not self.config.get("cache", {}).get("enabled", True):
            return SimpleCache()  # No-op effectively
        return SemanticCache()

    def _resolve_model(self, model_preference: str) -> List[tuple]:
        """Return list of (provider_name, model) to try in order"""
        routing = self.config.get("routing", {})
        default = routing.get("default", "claude-sonnet-4")
        fallback = routing.get("fallback_chain", [default])

        models_to_try = []
        if model_preference != "default":
            models_to_try.append(model_preference)
        for m in fallback:
            if m not in models_to_try:
                models_to_try.append(m)

        result = []
        for model in models_to_try:
            for provider_name, provider in self.providers.items():
                if provider.supports_model(model):
                    result.append((provider_name, model))
                    break
        return result

    def call(self, request: LLMRequest) -> LLMResponse:
        """Main entry point with fallback, retry, guardrails, caching"""

        # 1. Input guardrails
        input_check = self.guardrails.validate_input(request.messages)
        if not input_check["passed"]:
            return LLMResponse(
                content="",
                model=request.model_preference,
                provider="guardrail",
                tokens_in=0,
                tokens_out=0,
                latency_ms=0,
                cost_usd=0,
                error=f"Input guardrail failed: {input_check.get('blocked_by')}",
                guardrail_results=input_check["results"]
            )

        # 2. Check cache
        cache_key = self._make_cache_key(request)
        cached = self.cache.get(cache_key)
        if cached:
            self._log_observability(request, cached, from_cache=True)
            return cached

        # 3. Try models in fallback order
        models_to_try = self._resolve_model(request.model_preference)
        last_error = None

        for provider_name, model in models_to_try:
            provider = self.providers.get(provider_name)
            if not provider:
                continue

            # Retry loop
            retry_config = self.config.get("retry", {"attempts": 3})
            attempts = retry_config.get("attempts", 3)
            backoff = retry_config.get("backoff", "exponential")
            base_delay = retry_config.get("base_delay", 1)
            max_delay = retry_config.get("max_delay", 60)

            for attempt in range(attempts):
                try:
                    # Create request with resolved model
                    attempt_request = LLMRequest(
                        messages=request.messages,
                        model_preference=model,
                        temperature=request.temperature,
                        max_tokens=request.max_tokens,
                        tools=request.tools,
                        tool_choice=request.tool_choice,
                        metadata={**request.metadata, "attempt": attempt + 1, "provider": provider_name}
                    )

                    response = provider.call(attempt_request)

                    # 4. Output guardrails
                    output_check = self.guardrails.validate_output(response.content)
                    if not output_check["passed"]:
                        blocked = output_check.get("blocked_by")
                        feedback = output_check["results"].get(blocked, {}).get("retry_feedback")
                        if feedback and attempt < attempts - 1:
                            # Add feedback and retry
                            request.messages.append({
                                "role": "user",
                                "content": f"Previous response failed validation: {feedback}. Please try again."
                            })
                            continue
                        else:
                            response.error = f"Output guardrail failed: {blocked}"
                            response.guardrail_results = output_check["results"]
                            self._log_observability(request, response)
                            print(f"RAW_LLM_RESPONSE: {response.content}"); return response

                    response.guardrail_results = output_check["results"]
                    response.metadata = {"attempt": attempt + 1, "provider": provider_name}

                    # 5. Cache successful response
                    self.cache.set(cache_key, response, self.config.get("cache", {}).get("ttl", 3600))
                    # Semantic cache
                    if self.config.get("cache", {}).get("semantic_threshold"):
                        self.cache.semantic_set(request.messages, response,
                            self.config.get("cache", {}).get("ttl", 3600))

                    # 6. Log observability
                    self._log_observability(request, response)

                    print(f"RAW_LLM_RESPONSE: {response.content}"); return response

                except Exception as e:
                    last_error = e
                    delay = self._calculate_backoff(attempt, base_delay, max_delay, backoff)
                    time.sleep(delay)

        # All models exhausted
        return LLMResponse(
            content="",
            model=request.model_preference,
            provider="none",
            tokens_in=0,
            tokens_out=0,
            latency_ms=0,
            cost_usd=0,
            error=f"All models failed. Last error: {last_error}"
        )

    def _calculate_backoff(self, attempt: int, base: float, max_delay: float, strategy: str) -> float:
        if strategy == "exponential":
            delay = base * (2 ** attempt)
        elif strategy == "linear":
            delay = base * (attempt + 1)
        else:
            delay = base
        return min(delay, max_delay)

    def _make_cache_key(self, request: LLMRequest) -> str:
        content = json.dumps({
            "messages": request.messages,
            "model": request.model_preference,
            "temperature": request.temperature,
            "max_tokens": request.max_tokens,
            "tools": request.tools
        }, sort_keys=True, separators=(",", ":"))
        return hashlib.sha256(content.encode()).hexdigest()[:32]

    def _log_observability(self, request: LLMRequest, response: LLMResponse, from_cache: bool = False):
        if not self.config.get("observability", {}).get("enabled", True):
            return

        entry = {
            "timestamp": int(time.time()),
            "request_id": str(uuid.uuid4())[:12],
            "model": response.model,
            "provider": response.provider,
            "tokens_in": response.tokens_in,
            "tokens_out": response.tokens_out,
            "latency_ms": response.latency_ms,
            "cost_usd": response.cost_usd,
            "cached": from_cache or response.cached,
            "success": response.error is None,
            "error": response.error,
            "metadata": request.metadata
        }

        with self._lock:
            self.observability_log.append(entry)
            # Also write to file
            log_path = self.config.get("observability", {}).get("log_path")
            if log_path:
                log_file = Path(log_path)
                log_file.parent.mkdir(parents=True, exist_ok=True)
                with open(log_file, "a") as f:
                    f.write(json.dumps(entry, separators=(",", ":")) + "\n")

    def get_stats(self) -> Dict:
        with self._lock:
            if not self.observability_log:
                return {"total_requests": 0}

            total = len(self.observability_log)
            successful = sum(1 for e in self.observability_log if e["success"])
            cached = sum(1 for e in self.observability_log if e["cached"])
            total_cost = sum(e["cost_usd"] for e in self.observability_log)
            total_tokens_in = sum(e["tokens_in"] for e in self.observability_log)
            total_tokens_out = sum(e["tokens_out"] for e in self.observability_log)
            avg_latency = sum(e["latency_ms"] for e in self.observability_log) / total if total > 0 else 0

            by_provider = {}
            for e in self.observability_log:
                p = e["provider"]
                by_provider.setdefault(p, {"count": 0, "cost": 0, "errors": 0})
                by_provider[p]["count"] += 1
                by_provider[p]["cost"] += e["cost_usd"]
                if not e["success"]:
                    by_provider[p]["errors"] += 1

            return {
                "total_requests": total,
                "successful": successful,
                "success_rate": successful / total if total > 0 else 0,
                "cached": cached,
                "cache_hit_rate": cached / total if total > 0 else 0,
                "total_cost_usd": total_cost,
                "total_tokens_in": total_tokens_in,
                "total_tokens_out": total_tokens_out,
                "avg_latency_ms": avg_latency,
                "by_provider": by_provider
            }


def main():
    """CLI for testing"""
    if len(sys.argv) < 2:
        print("Usage: llm_gateway.py <command> [args]")
        print("Commands: call, stats, config")
        sys.exit(1)

    gateway = LLMGateway()
    cmd = sys.argv[1]

    if cmd == "call":
        if len(sys.argv) < 3:
            print("Usage: llm_gateway.py call '<messages_json>' [model]")
            sys.exit(1)
        messages = json.loads(sys.argv[2])
        model = sys.argv[3] if len(sys.argv) > 3 else "default"
        request = LLMRequest(messages=messages, model_preference=model)
        response = gateway.call(request)
        print(json.dumps(asdict(response), indent=2))

    elif cmd == "stats":
        print(json.dumps(gateway.get_stats(), indent=2))

    elif cmd == "config":
        print(json.dumps(gateway.config, indent=2))

    else:
        print(f"Unknown command: {cmd}")


if __name__ == "__main__":
    main()