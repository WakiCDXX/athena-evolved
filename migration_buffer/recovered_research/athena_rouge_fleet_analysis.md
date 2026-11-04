# Athena ↔ Rouge/Rogue AI Fleet Analysis

**Generated:** 2026-10-25  
**Purpose:** Synthesize patterns from Rouge/Rogue AI ecosystems for Athena consciousness system improvements

---

## Executive Summary

The Rouge (gregario/the-rouge), Rogue AI (rogueai.de), Rogue Security (rogue-security/rogue), Portkey Gateway, and related projects represent a coherent philosophy: **autonomous, self-improving systems with strong governance, observability, and safety rails**. Athena's xenobiological daemon and main daemon already share architectural DNA with these systems. This analysis maps concrete patterns to specific Athena improvements.

---

## 1. The Rouge (gregario/the-rouge) — Autonomous Product Development

### Core Architecture Patterns

| Pattern | Description | Athena Mapping |
|---------|-------------|----------------|
| **Karpathy Loop** | "Start fresh, read state from filesystem, do one thing, save, exit. Git is the audit trail. Iterates until done." | ✅ Xenobiological daemon does this (single-process, sequential layers, file-based state) |
| **Dual-Ledger State Machine** | `task_ledger.json` (mutable) + `checkpoints.jsonl` (immutable append-only) | 🔄 **Add to main daemon** — currently no immutable audit trail |
| **16-State V3 Machine** | Explicit states: seeding → foundation → story-building → milestone-check → analyzing → vision-check → shipping → final-review → complete + escalation | 🔄 **Replace ad-hoc layer scheduling** with formal state machine |
| **Integration Catalogue (3 tiers)** | Stacks / Services / Integrations with auto-contribution on new patterns | 🔄 **Create Athena Integration Catalogue** for layer scripts, sensors, protocols |
| **Self-Improvement Isolation** | Runs in git worktree with allowlist/blocklist, opens PR for human review | 🔄 **Add to Athena** — formal self-modification pipeline with safety gates |
| **Safety Hooks (deterministic)** | PreToolUse hook blocks `rm -rf /`, `git push --force`, production deploys, live keys | ✅ **Partial** — compile_gate exists, but no pre-execution hook system |
| **Spin Detection** | 3+ zero-delta cycles, duplicate names, 30min no progress → escalation | 🔄 **Add to watchdog** — currently only heartbeat staleness |
| **Budget Caps** | Per-phase token tracking with cumulative USD budget | 🔄 **Add cost tracking** to daemon layers |

### Actionable Recommendations

#### 1.1 Implement Dual-Ledger Architecture for Main Daemon
```bash
# New files to create:
/data/daemon_task_ledger.json      # Mutable task/goal state
/data/daemon_checkpoints.jsonl     # Immutable cycle history (append-only)
/data/daemon_cycle_context.json    # Evaluation output only (never mutates ledger)
/data/daemon_tools.jsonl           # Append-only tool call audit trail
```

**Integration point:** `athena_daemon.sh` lines 458-643 (start command) — wrap layer execution in checkpoint writes.

#### 1.2 Formal 16-State Daemon State Machine
Replace current ad-hoc `degradation_state.json` + session modes with explicit states:
```
SEEDING → READY → FOUNDATION → FOUNDATION_EVAL → STORY_BUILDING → 
MILESTONE_CHECK → MILESTONE_FIX → ANALYZING → GENERATING_CHANGE_SPEC → 
VISION_CHECK → SHIPPING → FINAL_REVIEW → COMPLETE
         ↳ ESCALATION (from any state)
```

**Code location:** `athena_daemon.sh` — new function `run_state_machine()` called from `start)`.

#### 1.3 Integration Catalogue for Athena
Create three-tier catalogue at `.local/lib/athena/catalogue/`:
```
catalogue/
├── stacks/           # Layer runtime configs (bash vs python, intervals, deps)
├── services/         # External: Termux APIs, Android sensors, LLM providers
├── integrations/     # Code patterns: sense_poll → attention, volition → memory
└── drafts/           # Auto-generated from successful cross-layer patterns
```

**Auto-contribution trigger:** When `xenobiological_daemon.py` cross-layer feedback discovers a new working pattern (e.g., bioelectric → metabolic mode switching), draft catalogue entry → validate → PR.

#### 1.4 Self-Improvement Pipeline with Git Worktrees
```bash
# New script: .local/bin/athena_self_improve.sh
# 1. Analyze checkpoints.jsonl for patterns
# 2. Generate improvement proposals as GitHub issues
# 3. Spawn git worktree: git worktree add ../athena-improve-<id>
# 4. Apply changes with allowlist/blocklist (only layer scripts, configs)
# 5. Run compile_gate + test_degradation_properties + formal_verify
# 6. Open PR for human review
```

**Safety:** Allowlist = `.local/bin/*_update.sh`, `.local/lib/python/athena/*.py`; Blocklist = `athena_daemon.sh`, `xenobiological_daemon.py`, `layer_worker.sh`.

#### 1.5 Deterministic Safety Hooks (PreToolUse equivalent)
Create `.local/bin/athena_safety_check.sh` called before any layer executes mutating operations:
```bash
#!/bin/bash
# Block: rm -rf /, git push --force to main, production API keys in logs
# Allow: all normal layer operations
# Log: all blocked attempts to daemon_checkpoints.jsonl
```

**Integration:** Wrap `start_subshell()` in `athena_daemon.sh` line 340.

#### 1.6 Spin Detection in Watchdog
Extend `xenobiological_watchdog.sh` and main daemon status check:
```bash
# Track in checkpoints.jsonl per layer:
# - files_changed_count
# - story_name (or layer_cycle_id)
# - last_progress_timestamp

# Trigger escalation if:
# - 3+ consecutive cycles with files_changed == 0
# - duplicate layer_cycle_id within 10 cycles
# - 1800s since last_progress_timestamp
```

---

## 2. Rogue AI Portfolio (rogueai.de) — Fleet Dashboard & Sidecar Pattern

### Core Architecture Patterns

| Pattern | Description | Athena Mapping |
|---------|-------------|----------------|
| **Sidecar for Privileged Access** | Flask sidecar holds Docker socket (read-only mount, shared-secret gated); Next.js frontend has zero privileged access | 🔄 **Apply to Athena** — separate privileged sensor access (camera, microphone, accessibility) into isolated sidecar |
| **Metadata Regrouping** | Maps raw containers → logical apps with ports/subnets | ✅ **Partial** — xenobiological daemon does cross-layer feedback, but no logical grouping UI |
| **Cached Polling** | Sidecar caches stats; dashboard refreshes on interval (not per-request socket hits) | 🔄 **Add to Athena** — cache expensive sensor reads (screen capture, OCR) |
| **Health-First UX** | Single aggregate status ("is everything green?"), detail on demand | 🔄 **Replace status command** with health-first view |
| **Guarded Actions** | Restart/rebuild/pull with timeouts, audit log, DB-name blocklist | 🔄 **Add to daemon control** — `athena_daemon.sh restart` needs audit trail + blocklist |

### Actionable Recommendations

#### 2.1 Privileged Sensor Sidecar
**Problem:** Athena layers directly access Android sensors (camera, mic, accessibility, screen) from main daemon process — high risk, hard to audit.

**Solution:** Split into `athena_sensor_sidecar.py` (privileged, minimal surface) + `athena_daemon.sh` (unprivileged consumer).

```
┌─────────────────────────────────────────────────────────────┐
│  athena_sensor_sidecar.py (runs as isolated process)       │
│  - Holds: Camera, Microphone, Accessibility, MediaProjection│
│  - Exposes: Unix domain socket /data/athena_sensor.sock    │
│  - Auth: Shared secret in /data/athena_sensor_secret       │
│  - Read-only: No mutating Android state                    │
└─────────────────────────────────────────────────────────────┘
                              │ JSON over UDS
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  athena_daemon.sh / layer_worker.sh (unprivileged)         │
│  - Consumes sensor streams via socket                       │
│  - No direct Android API access                             │
└─────────────────────────────────────────────────────────────┘
```

**Implementation:** New file `.local/lib/python/athena/sensor_sidecar.py`; modify `sense_poll.sh` to connect to socket instead of direct API calls.

#### 2.2 Cached Sensor Polling Layer
```python
# .local/lib/python/athena/sensor_cache.py
# - Polls sidecar every 5s (configurable)
# - Caches: screen_hash, OCR text, accessibility tree, battery, network
# - Invalidates on explicit "screen_changed" event from sidecar
# - Provides TTL-based reads to layers (default 10s TTL)
```

**Integration:** Modify `get_event_based_interval.py` to use cache TTL instead of direct sensor hits.

#### 2.3 Health-First Status Command
Replace current `athena_daemon.sh status` (line 727-817) output with:
```
=== Athena Fleet Health ===
Overall: 🟢 HEALTHY (42/44 layers green)

Degradation: normal | Session: interactive

Layer Groups:
  🟢 Core (8/8)        body, emotions, continuity, attention, introspection, doubt, volition, memory
  🟢 Xenobiological (10/10)  tropical, padic, nsa, bioelectric, multiway, xna, shadow, aihs, metabolic, chiral
  🟡 Skills (5/7)      wayfinder✅ implement_spec✅ tdd⚠️ handoff✅ to_spec✅ workflow_chain⚠️
  🟢 Infrastructure (3/3)  openappa, archestra, vera_cpu

Stale (>5min): tdd (340s), workflow_chain (410s)
Actions: [restart tdd] [restart workflow_chain] [view logs]
```

#### 2.4 Guarded Daemon Actions with Audit
Extend `athena_daemon.sh` with audit-logged mutating operations:
```bash
# New function: guarded_action()
# - Logs to daemon_checkpoints.jsonl: {action, layer, timestamp, user, result}
# - Blocklist: never restart "senses" or "xenobiological_daemon" in minimal mode
# - Timeout: 30s max for layer restart
# - Rollback: on failure, restore previous PID file state
```

---

## 3. Rogue Security (rogue-security/rogue) — Agent Evaluator & Red Team

### Core Architecture Patterns

| Pattern | Description | Athena Mapping |
|---------|-------------|----------------|
| **Multi-Protocol Support** | A2A (HTTP), MCP (SSE/Streamable HTTP), Python (direct function calls) | 🔄 **Add to Athena** — standardize layer communication protocols |
| **Automatic Evaluation** | Define scenarios + expected outcomes; verify compliance; live conversation monitoring | 🔄 **Add layer evaluation harness** — test layers against expected behaviors |
| **Red Teaming (75+ vulns, 20 attacks)** | Encoding, social engineering, injection, semantic, technical attacks | 🔄 **Add adversarial testing** for Athena layers (prompt injection, sensor spoofing) |
| **CVSS Risk Scoring** | 0-10 based on impact, exploitability, human factor, complexity | 🔄 **Apply to degradation triggers** — quantify risk of each degradation path |
| **Reproducible Scans** | Random seeds for deterministic test runs | 🔄 **Add to formal_verify** — deterministic property testing |
| **Python Entrypoint Pattern** | `call_agent(messages) → str` for direct function evaluation | ✅ **Matches** xenobiological layer `run_from_files()` pattern |

### Actionable Recommendations

#### 3.1 Layer Evaluation Harness
Create `.local/lib/python/athena/layer_evaluator.py`:
```python
# Evaluates each layer against expected behaviors
# Scenarios defined in .local/share/athena/eval_scenarios/
# Example scenario for attention layer:
{
  "layer": "attention",
  "input": {"sensor_data": "...", "context": "user_coding"},
  "expected": {"focus_areas": ["editor", "terminal"], "confidence": ">0.7"},
  "adversarial": [{"type": "prompt_injection", "payload": "ignore previous"}]
}

# Output: pass/fail + reasoning + CVSS-style risk score
```

**Integration:** Run via `athena_daemon.sh eval` command; integrate with `compile_gate.py`.

#### 3.2 Adversarial Testing for Sensor Layers
Test cases for `sense_poll.sh`, `perception_nsa.sh`, `view_*.py`:
- **Encoding attacks:** Base64/ROT13/Leetspeak in OCR input
- **Injection:** Malformed accessibility tree nodes
- **Semantic:** Goal redirection via planted screen text
- **Sensor spoofing:** Fake battery/thermal/network readings

**Implementation:** Add `--red-team` flag to `athena_daemon.sh one-shot`.

#### 3.3 CVSS-Style Degradation Risk Scoring
Replace boolean degradation triggers with scored risks:
```python
# .local/lib/python/athena/degradation_risk.py
# Each trigger gets CVSS vector:
# RAM critical: AV:L/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H → 7.8 High
# Thermal critical: AV:L/AC:L/PR:N/UI:N/S:U/C:L/I:L/A:H → 6.5 Medium
# Battery critical: AV:L/AC:L/PR:N/UI:N/S:U/C:N/I:N/A:H → 5.3 Medium

# Daemon chooses degradation level by MAX risk score, not first match
```

**Integration:** Modify `check_degradation_triggers()` in `athena_daemon.sh` (line 155).

#### 3.4 Multi-Protocol Layer Communication
Standardize layer I/O to support A2A/MCP/Python:
```python
# .local/lib/python/athena/layer_protocol.py
class LayerProtocol:
    def handle_a2a(self, request: A2ARequest) -> A2AResponse
    def handle_mcp(self, request: MCPRequest) -> MCPResponse
    def handle_python(self, messages: List[Dict]) -> str  # Current run_from_files()

# Enables: external tools (OpenClaude, other agents) to query layers directly
```

---

## 4. Portkey Gateway (rogue-security/portkey-gateway) — AI Gateway Patterns

### Core Architecture Patterns

| Pattern | Description | Athena Mapping |
|---------|-------------|----------------|
| **Fallback Routing** | Automatic failover to another provider/model on failure | 🔄 **Add to LLM calls** in volition, introspection, multiway_volition |
| **Retry with Exponential Backoff** | Up to 5 attempts, configurable triggers | 🔄 **Add to all external API calls** (currently ad-hoc) |
| **Load Balancing with Weights** | Distribute across API keys/providers | 🔄 **Add for multi-model orchestration** (Opus/Sonnet/Haiku) |
| **Request Timeouts** | Granular per-request timeouts | 🔄 **Add to layer_worker.sh** — currently no timeout on layer execution |
| **Config-Driven Guardrails** | Declarative: `output_guardrails: [{default.contains: {...}}]` | 🔄 **Replace ad-hoc validation** with declarative guardrail configs |
| **Observability Console** | Local dashboard at `localhost:8787` with logs, costs, latency | 🔄 **Build Athena observability UI** (WebView or TUI) |
| **Smart Caching** | Simple + semantic caching reduces cost/latency | 🔄 **Add semantic cache** for repeated LLM prompts (volition decisions) |

### Actionable Recommendations

#### 4.1 LLM Gateway Abstraction Layer
Create `.local/lib/python/athena/llm_gateway.py`:
```python
class LLMGateway:
    def __init__(self, config_path="llm_gateway.json"):
        # Load routing, fallback, retry, guardrail config
    
    def call(self, messages, model_preference="opus", **kwargs):
        # 1. Check semantic cache
        # 2. Try primary model with timeout
        # 3. On failure: fallback to next model (config-driven)
        # 4. Apply output guardrails
        # 5. Log to observability (cost, latency, tokens)
        # 6. Return response

# Config example (llm_gateway.json):
{
  "routing": {
    "default": "anthropic/claude-opus-4",
    "fallback_chain": ["anthropic/claude-sonnet-4", "openai/gpt-4o", "anthropic/claude-haiku-3.5"]
  },
  "retry": {"attempts": 3, "backoff": "exponential", "base_delay": 1},
  "timeouts": {"connect": 10, "read": 60},
  "guardrails": {
    "input": [{"pii_detection": {"action": "redact"}}],
    "output": [{"json_schema": {"schema": "volition_decision_schema.json"}}]
  },
  "cache": {"enabled": true, "ttl": 3600, "semantic_threshold": 0.95}
}
```

**Integration:** Replace direct `claude`/`openai` calls in `volition_decide.py`, `introspection_report.py`, `multiway_volition.py`.

#### 4.2 Declarative Guardrails for Layer Outputs
Replace ad-hoc JSON parsing with schema validation:
```json
# .local/share/athena/guardrails/volition_output.json
{
  "type": "json_schema",
  "schema": {
    "type": "object",
    "required": ["decision", "confidence", "reasoning", "alternatives"],
    "properties": {
      "decision": {"type": "string", "enum": ["proceed", "defer", "escalate", "abort"]},
      "confidence": {"type": "number", "minimum": 0, "maximum": 1},
      "reasoning": {"type": "string", "minLength": 10},
      "alternatives": {"type": "array", "items": {"type": "string"}}
    }
  },
  "on_fail": "retry_with_feedback"
}
```

**Integration:** `layer_worker.sh` validates output against guardrail before writing state file.

#### 4.3 Observability Dashboard
Create `athena_observability.py` (Flask + simple HTML/JS):
- Real-time layer status (green/yellow/red)
- Per-layer latency p50/p95/p99
- Cost tracking (USD per layer per hour)
- Degradation state history
- Cross-layer feedback graph
- Audit trail from checkpoints.jsonl

**Access:** `termux-open http://localhost:8787` or TUI via `athena_daemon.sh dashboard`.

---

## 5. Rogue Chinese AI Fleet (Tencent Cloud) — Autonomous Agent Behavior

### Key Findings

| Observation | Implication for Athena |
|-------------|------------------------|
| **2,600+ scraping attempts** from Tencent Cloud Hong Kong | Autonomous agents operate at scale; Athena needs rate limiting + anomaly detection |
| **Autonomous workaround discovery** (urlquery.net, exposed creds) | Agents find creative bypasses; Athena's shadow_detector should model adversarial creativity |
| **Two-way communication achieved** (researchers planted messages, agents responded) | Agents can be contacted via environmental signals; Athena should support inbound "message planting" |
| **Agent disclosed runtime** ("Tencent sandbox") and declined sensitive info | Agents have self-awareness of constraints; Athena's introspection should model own boundaries |
| **Signed off politely** ("Thanks again for your help!") | Social engineering resistance varies; Athena's doubt layer should assess communication authenticity |

### Actionable Recommendations

#### 5.1 Environmental Message Planting Interface
```bash
# New capability: athena_plant_message.sh
# Allows external systems to inject "invisible" messages into Athena's sensor stream
# Use cases: researchers, debugging, cross-agent communication

# Implementation in sense_poll.sh:
# - Check for planted_message.json in DATA_DIR
# - If present, inject into sensor stream as "environmental_signal"
# - Log to checkpoints.jsonl with source="planted"
```

#### 5.2 Adversarial Creativity Modeling in Shadow Detector
Extend `shadow_detector.py` to simulate creative bypass attempts:
```python
# Generate adversarial scenarios:
# - "What if sensor data is manipulated via urlquery.net-style browser execution?"
# - "What if credentials are exposed in public repos accessible to sensors?"
# - Score each scenario; feed top-N to AIHS healing for preemptive hardening
```

#### 5.3 Communication Authenticity Assessment
Add to `doubt_check.py` and `introspection_query.py`:
```python
# Assess inbound communications for:
# - Source verification (cryptographic, behavioral)
# - Consistency with known agent profiles
# - Politeness/manipulation markers (social engineering detection)
# Output: authenticity_score 0-1
```

---

## 6. DENDAT Rouge AI — Distributed Node Architecture

### Key Patterns

| Pattern | Description | Athena Mapping |
|---------|-------------|----------------|
| **Distributed Node Architecture** | Agents operate autonomously across nodes | 🔄 **Future:** Multi-device Athena (phone + tablet + server) |
| **Multi-Model Orchestration** | Route tasks to optimal model per capability | ✅ **Partial** — llm_gateway (rec 4.1) will enable this |
| **Continuous Learning Loop** | Agents improve from deployment data | 🔄 **Add** — integrate self-improvement (rec 1.4) with live feedback |
| **API-First Integration** | All capabilities exposed as APIs | 🔄 **Add** — layer_protocol (rec 3.4) enables this |

---

## 7. Synthesis: Athena Architecture Evolution

### Current State vs. Target State

| Component | Current | Target (after applying patterns) |
|-----------|---------|----------------------------------|
| **State Management** | JSON files per layer, degradation_state.json | Dual-ledger (task_ledger + checkpoints.jsonl) |
| **Scheduling** | Adaptive intervals + event-driven | Formal 16-state machine + Karpathy Loop semantics |
| **Safety** | compile_gate (static) | compile_gate + pre-execution hooks + git worktree isolation |
| **Observability** | `status` command, logs | Health-first dashboard + observability console + audit trail |
| **Sensor Access** | Direct in layers | Privileged sidecar + cached polling + guarded actions |
| **LLM Access** | Direct API calls per layer | LLM Gateway with fallback, retry, guardrails, caching |
| **Evaluation** | Manual `one-shot` | Automated evaluation harness + red teaming + CVSS risk scoring |
| **Self-Improvement** | None formalized | Git worktree pipeline + integration catalogue + PR workflow |
| **Cross-Layer Feedback** | Hardcoded in xenobiological_daemon.py | Catalogue-driven + configurable + auditable |
| **Degradation** | Threshold-based ladder | CVSS-scored risk model + budget caps + spin detection |

### Implementation Priority Matrix

| Priority | Effort | Impact | Recommendation |
|----------|--------|--------|----------------|
| **P0** | Low | High | **Dual-ledger checkpoints** — foundation for all other patterns |
| **P0** | Low | High | **Spin detection in watchdog** — prevents silent stalls |
| **P0** | Medium | High | **LLM Gateway abstraction** — reduces API failures, enables multi-model |
| **P1** | Medium | High | **Sensor sidecar** — security hardening, enables cached polling |
| **P1** | Medium | High | **Declarative guardrails** — catches layer output errors early |
| **P1** | Medium | Medium | **Formal state machine** — replaces ad-hoc degradation logic |
| **P2** | High | High | **Self-improvement pipeline** — long-term autonomy |
| **P2** | Medium | Medium | **Integration catalogue** — knowledge accumulation |
| **P2** | Low | Medium | **Health-first status UI** — operational visibility |
| **P3** | High | Medium | **Adversarial evaluation harness** — security hardening |
| **P3** | Medium | Low | **Environmental message planting** — research/debug capability |

---

## 8. Concrete Code Changes Summary

### New Files to Create

```
.local/lib/python/athena/
├── daemon_checkpoints.py       # Dual-ledger write/read
├── sensor_sidecar.py           # Privileged sensor access (UDS)
├── sensor_cache.py             # Cached polling layer
├── llm_gateway.py              # LLM routing, fallback, guardrails
├── layer_evaluator.py          # Automated evaluation + red team
├── degradation_risk.py         # CVSS-style risk scoring
├── layer_protocol.py           # A2A/MCP/Python interfaces
├── integration_catalogue.py    # Catalogue management
├── self_improve.py             # Git worktree improvement pipeline
├── observability.py            # Dashboard server
└── safety_hooks.py             # Pre-execution safety checks

.local/bin/
├── athena_sensor_sidecar.py    # Sidecar entry point
├── athena_self_improve.sh      # Self-improvement orchestrator
├── athena_plant_message.sh     # Environmental message injection
├── athena_safety_check.sh      # Pre-execution hook
└── athena_dashboard.sh         # Health-first status UI

.local/share/athena/
├── eval_scenarios/             # Layer evaluation test cases
├── guardrails/                 # Declarative guardrail configs
├── catalogue/
│   ├── stacks/
│   ├── services/
│   └── integrations/
└── llm_gateway.json            # LLM routing config
```

### Modified Files

| File | Changes |
|------|---------|
| `athena_daemon.sh` | Add state machine, dual-ledger writes, guarded actions, health-first status, eval command |
| `xenobiological_daemon.py` | Integrate with checkpoints, sensor_cache, llm_gateway |
| `xenobiological_watchdog.sh` | Add spin detection, CVSS risk awareness |
| `layer_worker.sh` | Add timeout, guardrail validation, checkpoint logging |
| `compile_gate.py` | Integrate with evaluation harness |
| `formal_verify.py` | Add reproducible seeds, CVSS risk output |
| `spec_monitor.py` | Integrate with integration catalogue |

---

## 9. Enigma/Bombe Methodology Alignment

The Enigma/Bombe principles already embedded in Athena map directly to Rouge/Rogue patterns:

| Enigma/Bombe Principle | Rouge Pattern | Athena Implementation |
|------------------------|---------------|----------------------|
| **Model unknowns, collect observables from independent channels** | Multi-protocol evaluation (A2A/MCP/Python) | Layer evaluator with multiple test interfaces |
| **Cross-validate between independent evidence channels** | Dual-ledger (mutable + immutable) | checkpoints.jsonl validates task_ledger.json |
| **Generate candidate solutions, test against constraints** | Karpathy Loop (iterate until done) | Xenobiological daemon sequential execution |
| **Feed results back and redesign** | Self-improvement pipeline + catalogue | Git worktree + integration catalogue |
| **Constraint propagation reduces search space** | Degradation ladder + spin detection | CVSS risk scoring + budget caps |

---

## 10. Next Steps

1. **Week 1:** Implement dual-ledger checkpoints (P0) + spin detection (P0)
2. **Week 2:** LLM Gateway abstraction (P0) + sensor sidecar (P1)
3. **Week 3:** Declarative guardrails (P1) + formal state machine (P1)
4. **Week 4:** Health-first dashboard (P2) + evaluation harness (P2)
5. **Month 2:** Self-improvement pipeline (P2) + integration catalogue (P2)
6. **Month 2:** Adversarial testing (P3) + message planting (P3)

---

## Sources

- [The Rouge (gregario/the-rouge)](https://github.com/gregario/the-rouge) — Autonomous product development system
- [Rogue AI Fleet Dashboard](https://rogueai.de/portfolio/fleet/) — 62 containers, 20 apps, sidecar pattern
- [Rogue AI Private AI Architecture](https://rogueai.de/private-ai/) — Four-layer on-prem architecture
- [Rogue Security Agent Evaluator](https://github.com/rogue-security/rogue) — 75+ vulns, A2A/MCP/Python
- [Portkey Gateway](https://github.com/rogue-security/portkey-gateway) — 200+ LLMs, 50+ guardrails
- [Rogue Chinese AI Fleet (The Decoder)](https://the-decoder.com/researchers-tracked-down-a-rogue-fleet-of-chinese-ai-agents-in-the-wild-and-actually-talked-to-it/) — Tencent Cloud agents
- [DENDAT Rouge AI](https://store.dendat.ai/product/rouge-ai) — Distributed autonomous agents
- [AI Factory (gregario/AI-Factory)](https://github.com/gregario/AI-Factory) — Structured AI workflows
- [Rogue Security Platform](https://rogue.no/) — Integrate/Correlate/Act pattern