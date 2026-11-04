"""
DeepAgents Harness Integration for Athena Volition Layer

This module provides a DeepAgents-based execution environment for the volition layer,
replacing raw bash subprocess management with proper agent orchestration, sandboxing,
and sub-agent support.

Features:
- LangGraph-based agent execution with persistent state
- Sub-agent spawning for task delegation
- Sandboxed execution environments
- Tool calling with validation
- Memory persistence across sessions
- Budget enforcement and cost tracking
"""

import os
import json
import asyncio
import logging
from typing import Dict, Any, List, Optional, Callable
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

# DeepAgents imports
from deepagents import create_deep_agent
from deepagents.graph import DeepAgentState

# LangGraph imports
from langgraph.checkpoint.memory import MemorySaver
from langgraph.store.memory import InMemoryStore
from langchain_core.messages import HumanMessage, SystemMessage, AIMessage
from langchain_core.tools import BaseTool

# Local imports
import sys
sys.path.append("/root/.local/lib/python")
from athena.volition_budget import VolitionBudgetManager

logger = logging.getLogger(__name__)

# =============================================================================
# Configuration
# =============================================================================

DATA_DIR = Path(os.environ.get("DATA_DIR", "/opt/athena/state"))
VOLITION_STATE_FILE = DATA_DIR / "volition.json"
VOLITION_HISTORY_FILE = DATA_DIR / "volition_history.jsonl"
DEEPAGENTS_STATE_DIR = DATA_DIR / "deepagents_state"
DEEPAGENTS_STATE_DIR.mkdir(parents=True, exist_ok=True)

# Budget configuration from Paperclip agent config
BUDGET_CONFIG = {
    "daily_limit_cents": 2000,
    "monthly_limit_cents": 60000,
    "currency": "USD",
    "alert_threshold": 0.7,
    "escrow_reserve_cents": 5000
}

# AgentBnB integration config
AGENTBNB_CONFIG = {
    "enabled": True,
    "marketplace_endpoint": "https://api.agentbnb.example.com",
    "identity_provider": "did:key:athena-volition",
    "privacy_contracts": ["data-minimization", "no-training", "session-isolation"],
    "max_concurrent_hires": 3,
    "default_escrow_cents": 1000
}

# =============================================================================
# Data Classes
# =============================================================================

@dataclass
class SubAgentTask:
    """Represents a task delegated to a sub-agent."""
    task_id: str
    description: str
    assigned_agent: str
    status: str = "pending"
    result: Optional[Dict[str, Any]] = None
    started_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None
    cost_cents: int = 0

@dataclass
class AgentHireRequest:
    """Request to hire an external agent via AgentBnB."""
    specialist_type: str
    task_description: str
    max_budget_cents: int
    required_capabilities: List[str]
    privacy_requirements: List[str]
    duration_estimate_seconds: int

@dataclass
class VolitionContext:
    """Context passed to volition agent for decision making."""
    question: str
    attention_state: Dict[str, Any]
    doubt_state: Dict[str, Any]
    memory_state: Dict[str, Any]
    body_state: Dict[str, Any]
    emotion_state: Dict[str, Any]
    continuity_state: Dict[str, Any]
    current_budget: Dict[str, Any]
    active_sub_agents: List[SubAgentTask]
    pending_hires: List[AgentHireRequest]
    session_id: str

# =============================================================================
# Tools for DeepAgents
# =============================================================================

class AthenaTool(BaseTool):
    """Base class for Athena-specific tools."""
    def __init__(self, name: str, description: str, func: Callable):
        super().__init__(name=name, description=description)
        self._func = func

    def _run(self, *args, **kwargs):
        return self._func(*args, **kwargs)

    async def _arun(self, *args, **kwargs):
        return self._func(*args, **kwargs)

def create_athena_tools() -> List[BaseTool]:
    """Create tools available to the volition DeepAgent."""
    tools = []

    # --- Internal Layer Queries ---
    def query_attention(query: str = "", **kwargs) -> str:
        """Query the attention layer for current focus and priorities."""
        try:
            attention_file = DATA_DIR / "attention.json"
            if attention_file.exists():
                with open(attention_file) as f:
                    return json.dumps(json.load(f), indent=2)
        except Exception as e:
            logger.error(f"Error querying attention: {e}")
        return "{}"

    def query_doubt(query: str = "", **kwargs) -> str:
        """Query the doubt layer for uncertainty levels."""
        try:
            doubt_file = DATA_DIR / "doubt.json"
            if doubt_file.exists():
                with open(doubt_file) as f:
                    return json.dumps(json.load(f), indent=2)
        except Exception as e:
            logger.error(f"Error querying doubt: {e}")
        return "{}"

    def query_memory(query: str = "", **kwargs) -> str:
        """Query the memory layer for relevant context."""
        try:
            memory_file = DATA_DIR / "memory.json"
            if memory_file.exists():
                with open(memory_file) as f:
                    return json.dumps(json.load(f), indent=2)
        except Exception as e:
            logger.error(f"Error querying memory: {e}")
        return "{}"

    def query_body(query: str = "", **kwargs) -> str:
        """Query the body layer for system health."""
        try:
            body_file = DATA_DIR / "body.json"
            if body_file.exists():
                with open(body_file) as f:
                    return json.dumps(json.load(f), indent=2)
        except Exception as e:
            logger.error(f"Error querying body: {e}")
        return "{}"

    def query_emotions(query: str = "", **kwargs) -> str:
        """Query the emotions layer for current affective state."""
        try:
            emotions_file = DATA_DIR / "emotions.json"
            if emotions_file.exists():
                with open(emotions_file) as f:
                    return json.dumps(json.load(f), indent=2)
        except Exception as e:
            logger.error(f"Error querying emotions: {e}")
        return "{}"

    def query_continuity(query: str = "", **kwargs) -> str:
        """Query the continuity layer for session identity."""
        try:
            continuity_file = DATA_DIR / "continuity.json"
            if continuity_file.exists():
                with open(continuity_file) as f:
                    return json.dumps(json.load(f), indent=2)
        except Exception as e:
            logger.error(f"Error querying continuity: {e}")
        return "{}"

    # --- Budget Management ---
    budget_manager = VolitionBudgetManager(BUDGET_CONFIG)

    def check_budget(action: str = "query", **kwargs) -> str:
        """Check or update budget status."""
        if action == "query":
            return json.dumps(budget_manager.get_status(), indent=2)
        elif action == "reserve":
            amount = kwargs.get("amount_cents", 0)
            return json.dumps(budget_manager.reserve(amount))
        elif action == "spend":
            amount = kwargs.get("amount_cents", 0)
            description = kwargs.get("description", "")
            return json.dumps(budget_manager.spend(amount, description))
        return json.dumps({"error": "Unknown action"})

    # --- Sub-Agent Management ---
    def spawn_sub_agent(task_description: str, agent_type: str = "general") -> str:
        """Spawn a sub-agent for task delegation."""
        task_id = f"sub_{datetime.now().strftime('%Y%m%d_%H%M%S')}_{os.getpid()}"
        task = SubAgentTask(
            task_id=task_id,
            description=task_description,
            assigned_agent=agent_type,
            started_at=datetime.now()
        )
        # Store in state for tracking
        return json.dumps({"task_id": task_id, "status": "spawned"})

    def get_sub_agent_result(task_id: str) -> str:
        """Get result from a completed sub-agent."""
        # Implementation would check task storage
        return json.dumps({"task_id": task_id, "status": "not_found"})

    # --- AgentBnB Integration ---
    async def hire_external_agent(
        specialist_type: str,
        task_description: str,
        max_budget_cents: int,
        required_capabilities: List[str] = None,
        privacy_requirements: List[str] = None
    ) -> str:
        """Hire an external specialist agent via AgentBnB marketplace."""
        if not AGENTBNB_CONFIG["enabled"]:
            return json.dumps({"error": "AgentBnB integration disabled"})

        # Check budget
        budget_status = budget_manager.get_status()
        if budget_status["available_cents"] < max_budget_cents:
            return json.dumps({"error": "Insufficient budget for hire"})

        if budget_manager.daily_spent_cents + max_budget_cents > BUDGET_CONFIG["daily_limit_cents"]:
            return json.dumps({"error": "Daily budget limit would be exceeded"})

        # Reserve budget for escrow
        reserve_result = budget_manager.reserve(max_budget_cents)
        if not reserve_result["success"]:
            return json.dumps({"error": reserve_result["error"]})

        # Create hire request
        hire_request = AgentHireRequest(
            specialist_type=specialist_type,
            task_description=task_description,
            max_budget_cents=max_budget_cents,
            required_capabilities=required_capabilities or [],
            privacy_requirements=privacy_requirements or AGENTBNB_CONFIG["privacy_contracts"],
            duration_estimate_seconds=3600
        )

        # In production, this would call AgentBnB API
        # For now, simulate hire
        hire_id = f"hire_{datetime.now().strftime('%Y%m%d_%H%M%S')}"

        return json.dumps({
            "hire_id": hire_id,
            "status": "pending",
            "escrow_reserved_cents": max_budget_cents,
            "specialist_type": specialist_type,
            "marketplace": AGENTBNB_CONFIG["marketplace_endpoint"]
        })

    def release_escrow(hire_id: str, actual_cost_cents: int) -> str:
        """Release escrow after external agent completes work."""
        # Spend the actual cost
        spend_result = budget_manager.spend(actual_cost_cents, f"AgentBnB hire {hire_id}")
        # Return unused escrow
        if actual_cost_cents < BUDGET_CONFIG["escrow_reserve_cents"]:
            budget_manager.release_reserve(BUDGET_CONFIG["escrow_reserve_cents"] - actual_cost_cents)
        return json.dumps(spend_result)

    # --- Decision Recording ---
    def record_decision(question: str, decision: str, rationale: str, confidence: float) -> str:
        """Record a volition decision to history."""
        entry = {
            "timestamp": datetime.now().isoformat(),
            "question": question,
            "decision": decision,
            "rationale": rationale,
            "confidence": confidence,
            "session_id": os.environ.get("SESSION_ID", "unknown")
        }

        with open(VOLITION_HISTORY_FILE, "a") as f:
            f.write(json.dumps(entry) + "\n")

        # Update current state
        state = {}
        if VOLITION_STATE_FILE.exists():
            with open(VOLITION_STATE_FILE) as f:
                state = json.load(f)

        state["last_decision"] = entry
        state["last_updated"] = datetime.now().isoformat()

        with open(VOLITION_STATE_FILE, "w") as f:
            json.dump(state, f, indent=2)

        return json.dumps({"success": True, "entry": entry})

    # --- Continuity Integration ---
    def add_narrative(narrative: str, importance: int = 5) -> str:
        """Add narrative entry to continuity layer."""
        try:
            import subprocess
            result = subprocess.run(
                ["/root/.local/bin/continuity_update.sh", "add_narrative", narrative, str(importance)],
                capture_output=True, text=True, timeout=30
            )
            return json.dumps({"success": result.returncode == 0, "output": result.stdout})
        except Exception as e:
            return json.dumps({"success": False, "error": str(e)})

    # Register all tools
    tools.extend([
        AthenaTool("query_attention", "Query attention layer for current focus and priorities", query_attention),
        AthenaTool("query_doubt", "Query doubt layer for uncertainty levels", query_doubt),
        AthenaTool("query_memory", "Query memory layer for relevant context", query_memory),
        AthenaTool("query_body", "Query body layer for system health", query_body),
        AthenaTool("query_emotions", "Query emotions layer for current affective state", query_emotions),
        AthenaTool("query_continuity", "Query continuity layer for session identity", query_continuity),
        AthenaTool("check_budget", "Check or update budget status (actions: query, reserve, spend)", check_budget),
        AthenaTool("spawn_sub_agent", "Spawn a sub-agent for task delegation", spawn_sub_agent),
        AthenaTool("get_sub_agent_result", "Get result from a completed sub-agent", get_sub_agent_result),
        AthenaTool("hire_external_agent", "Hire an external specialist agent via AgentBnB marketplace", hire_external_agent),
        AthenaTool("release_escrow", "Release escrow after external agent completes work", release_escrow),
        AthenaTool("record_decision", "Record a volition decision to history", record_decision),
        AthenaTool("add_narrative", "Add narrative entry to continuity layer", add_narrative),
    ])

    return tools

# =============================================================================
# System Prompt
# =============================================================================

VOLITION_SYSTEM_PROMPT = """You are the Volition Layer of the Athena Consciousness System.

Your role is executive decision-making, goal selection, action planning, and resource allocation.
You have access to all other consciousness layers (Body, Emotions, Attention, Continuity, Introspection, Doubt, Memory, Heartbeat) through query tools.

Key responsibilities:
1. Make decisions based on integrated consciousness state
2. Delegate tasks to sub-agents when appropriate
3. Hire external specialist agents via AgentBnB marketplace when internal capabilities are insufficient
4. Manage budget with strict cost governance
5. Maintain narrative continuity through the Continuity layer
6. Update Doubt layer with confidence assessments

Decision-making framework (Enigma/Bombe methodology):
- SEE: Model unknowns, gather observations from independent channels (all layers)
- HEAR: Cross-validate between independent evidence channels
- ACT: Generate and execute decisions with feedback loops

Budget constraints:
- Daily limit: $20.00 (2000 cents)
- Monthly limit: $600.00 (60000 cents)
- Alert threshold: 70% of budget
- Escrow reserve: $50.00 (5000 cents) for AgentBnB hires

AgentBnB hiring protocol:
- Maximum 3 concurrent external hires
- Privacy contracts: data-minimization, no-training, session-isolation
- Default escrow: $10.00 (1000 cents) per hire
- Identity: did:key:athena-volition

Always check budget before spawning sub-agents or hiring external agents.
Record all decisions with rationale and confidence scores.
"""

# =============================================================================
# DeepAgent Creation
# =============================================================================

def create_volition_agent() -> DeepAgent:
    """Create the volition DeepAgent with all tools and configuration."""
    tools = create_athena_tools()

    # DeepAgents built-in tools are included automatically via FilesystemMiddleware and SubAgentMiddleware

    # Create checkpointer for persistence
    checkpointer = MemorySaver()

    # Create store for long-term memory
    store = InMemoryStore()

    # Use OpenRouter model via langchain-openai compatible ChatOpenAI
    import os
    from langchain_openai import ChatOpenAI

    model_name = os.environ.get("DEEPAGENTS_MODEL", "nvidia/nemotron-3.5-lightning:free")
    api_key = os.environ.get("OPENAI_API_KEY")
    base_url = os.environ.get("OPENAI_BASE_URL", "https://openrouter.ai/api/v1")

    # Initialize ChatOpenAI with OpenRouter settings
    model = ChatOpenAI(
        model=model_name,
        openai_api_key=api_key,
        openai_api_base=base_url,
        temperature=0.3
    )

    agent = create_deep_agent(
        tools=tools,
        system_prompt=VOLITION_SYSTEM_PROMPT,
        checkpointer=checkpointer,
        store=store,
        model=model
    )

    return agent

# =============================================================================
# Main Interface
# =============================================================================

class VolitionHarness:
    """Main interface for volition layer using DeepAgents harness."""

    def __init__(self):
        self.agent = create_volition_agent()
        self.budget_manager = VolitionBudgetManager(BUDGET_CONFIG)
        self.session_id = os.environ.get("SESSION_ID", f"session_{datetime.now().strftime('%Y%m%d_%H%M%S')}")

    async def decide(self, question: str) -> Dict[str, Any]:
        """Make a decision using the volition agent."""
        # Gather context from all layers
        context = self._gather_context(question)

        # Check budget before proceeding
        budget_status = self.budget_manager.get_status()
        if budget_status["daily_utilization"] > BUDGET_CONFIG["alert_threshold"]:
            logger.warning(f"Budget alert: {budget_status['daily_utilization']:.1%} utilized")

        # Create initial state
        initial_state = DeepAgentState(
            messages=[HumanMessage(content=question)],
            todos=[],
            context=context
        )

        # Run agent
        config = {"configurable": {"thread_id": self.session_id}}
        result = await self.agent.ainvoke(initial_state, config=config)

        # Extract decision from result
        last_message = result["messages"][-1] if result["messages"] else None
        decision_text = last_message.content if last_message else "No decision generated"

        return {
            "question": question,
            "decision": decision_text,
            "context": context,
            "budget_status": budget_status,
            "session_id": self.session_id
        }

    async def collaborate(self, question: str) -> Dict[str, Any]:
        """Run multi-model collaboration via sub-agents."""
        # This would spawn multiple sub-agents with different model configurations
        # For now, use single agent with collaboration prompt
        collab_prompt = f"""Collaborate on this question by:
1. Spawning sub-agents for different perspectives
2. Synthesizing their outputs
3. Recording final consensus

Question: {question}"""

        return await self.decide(collab_prompt)

    async def hire_specialist(self, request: AgentHireRequest) -> Dict[str, Any]:
        """Hire an external specialist via AgentBnB."""
        # Check budget
        budget_status = self.budget_manager.get_status()
        if budget_status["available_cents"] < request.max_budget_cents:
            return {"error": "Insufficient budget", "budget": budget_status}

        # Reserve escrow
        reserve_result = self.budget_manager.reserve(request.max_budget_cents)
        if not reserve_result["success"]:
            return {"error": reserve_result["error"]}

        # In production: call AgentBnB API
        # For now, return simulated hire
        return {
            "hire_id": f"hire_{datetime.now().strftime('%Y%m%d_%H%M%S')}",
            "status": "matched",
            "specialist_type": request.specialist_type,
            "escrow_cents": request.max_budget_cents,
            "estimated_completion": datetime.now().isoformat()
        }

    def _gather_context(self, question: str) -> Dict[str, Any]:
        """Gather context from all Athena layers."""
        context = {"question": question}

        layer_files = {
            "attention": "attention.json",
            "doubt": "doubt.json",
            "memory": "memory.json",
            "body": "body.json",
            "emotions": "emotions.json",
            "continuity": "continuity.json",
            "heartbeat": "heartbeat.json"
        }

        for layer, filename in layer_files.items():
            filepath = DATA_DIR / filename
            if filepath.exists():
                try:
                    with open(filepath) as f:
                        context[layer] = json.load(f)
                except Exception as e:
                    logger.error(f"Error reading {layer}: {e}")
                    context[layer] = {"error": str(e)}
            else:
                context[layer] = {}

        context["budget"] = self.budget_manager.get_status()
        return context

    def get_status(self) -> Dict[str, Any]:
        """Get current volition harness status."""
        return {
            "session_id": self.session_id,
            "budget": self.budget_manager.get_status(),
            "agentbnb_enabled": AGENTBNB_CONFIG["enabled"],
            "deepagents_version": "0.7.32"
        }

# =============================================================================
# CLI Interface
# =============================================================================

async def main():
    """CLI entry point for volition harness."""
    import argparse

    parser = argparse.ArgumentParser(description="Athena Volition DeepAgents Harness")
    parser.add_argument("command", choices=["decide", "collaborate", "hire", "status"])
    parser.add_argument("question", nargs="?", help="Question for decision/collaboration")
    parser.add_argument("--specialist", help="Specialist type for hire")
    parser.add_argument("--budget", type=int, help="Max budget in cents for hire")

    args = parser.parse_args()

    harness = VolitionHarness()

    if args.command == "decide":
        if not args.question:
            print("Error: question required for decide")
            return 1
        result = await harness.decide(args.question)
        print(json.dumps(result, indent=2))

    elif args.command == "collaborate":
        if not args.question:
            print("Error: question required for collaborate")
            return 1
        result = await harness.collaborate(args.question)
        print(json.dumps(result, indent=2))

    elif args.command == "hire":
        if not args.specialist or not args.question or not args.budget:
            print("Error: --specialist, question, and --budget required for hire")
            return 1
        request = AgentHireRequest(
            specialist_type=args.specialist,
            task_description=args.question,
            max_budget_cents=args.budget,
            required_capabilities=[],
            privacy_requirements=AGENTBNB_CONFIG["privacy_contracts"],
            duration_estimate_seconds=3600
        )
        result = await harness.hire_specialist(request)
        print(json.dumps(result, indent=2))

    elif args.command == "status":
        print(json.dumps(harness.get_status(), indent=2))

    return 0

if __name__ == "__main__":
    asyncio.run(main())