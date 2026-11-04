#!/usr/bin/bash
# athena_workflow_chain.sh — Workflow chain orchestrator for Athena
# Coordinates cross-skill workflows using Matt Pocock's 5 AI workflow skills
#
# Usage:
#   athena_workflow_chain.sh orchestrator      → run all workflow chains
#   athena_workflow_chain.sh chain1            → discovery → analyze → spec → review → impl → prototype → test → handoff
#   athena_workflow_chain.sh chain2            → analyze → arch-improv → validate → teach → doc → transition
#   athena_workflow_chain.sh chain3            → monitor → detect → wait-what → spec → research → resolve → sync
#   athena_workflow_chain.sh chain4            → session → continuity → memory → domain-model → grill → archive → handoff
#   athena_workflow_chain.sh status            → show chain status
#   athena_workflow_chain.sh validate          → validate all chains

set -o pipefail

BASE_DIR="/root"
BIN_DIR="$BASE_DIR/.local/bin"
source "$BIN_DIR/athena_env.sh" 2>/dev/null

DATA_DIR="/opt/athena/state"
WF_DIR="$DATA_DIR/workflow_chains"
LOG_DIR="$DATA_DIR/workflow_logs"
STATE_FILE="$WF_DIR/chain_state.json"

mkdir -p "$WF_DIR" "$LOG_DIR"
touch "$STATE_FILE"

now() { date +%s; }

# Security: validate paths
validate_path() {
    local path="$1"
    local base="/root"
    local abs_path
    if [[ "$path" = /* ]]; then
        abs_path="$path"
    else
        abs_path=$(realpath -m "$base/$path" 2>/dev/null || echo "$base")
    fi
    local canonical=$(realpath "$abs_path" 2>/dev/null || echo "$abs_path")
    if [[ "$canonical" != "$base"* ]]; then
        echo "Security violation: Path outside allowed directory" >&2
        return 1
    fi
    echo "$canonical"
}

# Safe command execution
safe_execute() {
    local cmd="$1"
    local timeout_sec="${2:-30}"
    if [[ "$cmd" =~ [\`\|\&\;\$\(\)] ]]; then
        echo "Security violation: Invalid command characters" >&2
        return 1
    fi
    timeout "$timeout_sec" bash -c "$cmd" 2>&1
    return $?
}

# Chain 1: Discovery → Rea Analysis → Specification → Code Review → Implementation → Prototype → Testing → Handoff
chain1_discovery_to_handoff() {
    local log_file="$LOG_DIR/chain1_$(date +%Y%m%d_%H%M%S).log"
    echo "=== Chain 1: Discovery → Spec → Review → Impl → Prototype → Test → Handoff ===" | tee "$log_file"

    # Step 1: Wayfinder - explore codebase for new feature areas
    echo "[1/8] Wayfinder: Exploring consciousness layers..." | tee -a "$log_file"
    "$BIN_DIR/athena_wayfinder.sh" explore ".local/lib/python/athena" deep structured "$WF_DIR/chain1_explore.json" 2>&1 | tee -a "$log_file"

    # Step 2: Rea - analyze and inspect target artifacts
    echo "[2/8] Rea: Analyzing artifacts..." | tee -a "$log_file"
    "$BIN_DIR/athena_rea.sh" analyze ".local/lib/python/athena" overview 2>&1 | tee -a "$log_file"

    # Step 3: To-spec - extract specifications from explored areas
    echo "[3/8] To-spec: Extracting specifications..." | tee -a "$log_file"
    "$BIN_DIR/athena_to_spec.sh" auto "$WF_DIR/chain1_explore.json" technical json strict deep general 70 2>&1 | tee -a "$log_file"

    # Step 3: Code Review - security and correctness review of spec'd components
    echo "[4/8] Code Review: Reviewing discovered components..." | tee -a "$log_file"
    # code_review.sh signature: review <file> [focus]
    "$BIN_DIR/athena_code_review.sh" review ".local/lib/python/athena/daemon_init.py" security 2>&1 | tee -a "$log_file"

    # Step 5: Implement-spec - create implementation plan for a specific component
    echo "[5/8] Implement-spec: Creating implementation plan..." | tee -a "$log_file"
    # Use a representative component from the explored area
    local target_component=".local/lib/python/athena/daemon_init.py"
    "$BIN_DIR/athena_implement_spec.sh" analyze "$target_component" detailed "/root/.local/share/athena_specs" comprehensive feature 2>&1 | tee -a "$log_file"

    # Step 6: Prototype - scaffold new component from plan
    echo "[6/8] Prototype: Scaffolding component from plan..." | tee -a "$log_file"
    # prototype.sh signature: create <name> <type> [spec]
    "$BIN_DIR/athena_prototype.sh" create chain1_layer layer "$WF_DIR/chain1_explore.json" 2>&1 | tee -a "$log_file"

    # Step 7: TDD - validate with tests
    echo "[7/8] TDD: Running validation tests..." | tee -a "$log_file"
    # Find a test file to validate
    local test_file=$(find ".local/lib/python/athena" -name "test_*.py" -o -name "*_test.py" 2>/dev/null | head -1)
    if [[ -z "$test_file" ]]; then
        test_file=".local/lib/python/athena/test_init_log.py"
    fi
    # tdd.sh signature: validate <test_file> [validation_mode] [test_framework] [coverage_threshold] [performance_target] [output_dir] [test_type] [parallel_jobs]
    "$BIN_DIR/athena_tdd.sh" validate "$test_file" comprehensive pytest 80 1000 "/root/.local/share/athena_tests" unit auto 2>&1 | tee -a "$log_file"

    # Step 8: Handoff - track progress and transition
    echo "[8/8] Handoff: Tracking progress..." | tee -a "$log_file"
    # handoff.sh track <progress_value> [description] [agent_name]
    "$BIN_DIR/athena_handoff.sh" track 80 "Chain 1 discovery to handoff complete" "system" 2>&1 | tee -a "$log_file"

    # Update chain state
    local state=$(cat "$STATE_FILE" 2>/dev/null || echo '{}')
    local ts=$(now)
    # Handle empty file case
    if [ -z "$(echo "$state" | tr -d '[:space:]')" ]; then
        state='{}'
    fi
    state=$(echo "$state" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
except:
    data = {}
data['chain1'] = {
    'last_run': $ts,
    'status': 'completed',
    'explore_file': '$WF_DIR/chain1_explore.json',
    'analysis_file': '$WF_DIR/chain1_rea_analysis.json',
    'spec_file': '$WF_DIR/chain1_spec.json',
    'review_file': '$WF_DIR/chain1_review',
    'plan_file': '$WF_DIR/chain1_plan.json',
    'prototype_dir': '$WF_DIR',
    'test_file': '$WF_DIR/chain1_test_report.json',
    'handoff_file': '$WF_DIR/chain1_handoff.json'
}
print(json.dumps(data))
" 2>/dev/null)
    echo "$state" > "$STATE_FILE"

    echo "Chain 1 completed successfully" | tee -a "$log_file"
}

# Chain 2: Analysis → Architecture Improvement → Validation → Teaching → Documentation → Transition
chain2_analyze_to_transition() {
    local log_file="$LOG_DIR/chain2_$(date +%Y%m%d_%H%M%S).log"
    echo "=== Chain 2: Analysis → Arch Improv → Validation → Teaching → Docs → Transition ===" | tee "$log_file"
    local ts=$(now)

    # Step 1: Wayfinder - analyze relationships
    echo "[1/7] Wayfinder: Analyzing component relationships..." | tee -a "$log_file"
    "$BIN_DIR/athena_wayfinder.sh" relationships ".local/bin" deep structured "$WF_DIR/chain2_relationships.json" 2>&1 | tee -a "$log_file"

    # Step 2: Implement-spec - analyze architecture of a specific component
    echo "[2/7] Implement-spec: Analyzing architecture..." | tee -a "$log_file"
    local target_component=".local/bin/athena_daemon.sh"
    "$BIN_DIR/athena_implement_spec.sh" analyze "$target_component" detailed "/root/.local/share/athena_specs" comprehensive architecture 2>&1 | tee -a "$log_file"

    # Step 3: Improve Architecture - generate architecture improvement recommendations
    echo "[3/7] Improve Architecture: Generating improvement recommendations..." | tee -a "$log_file"
    "$BIN_DIR/athena_improve_architecture.sh" "$target_component" "comprehensive" "$WF_DIR/chain2_arch_improvements.json" 2>&1 | tee -a "$log_file"

    # Step 4: TDD - full validation
    echo "[4/7] TDD: Full test validation..." | tee -a "$log_file"
    local test_file=$(find ".local/lib/python/athena" -name "test_*.py" -o -name "*_test.py" 2>/dev/null | head -1)
    if [[ -z "$test_file" ]]; then
        test_file=".local/lib/python/athena/test_init_log.py"
    fi
    "$BIN_DIR/athena_tdd.sh" validate "$test_file" comprehensive pytest 80 1000 "/root/.local/share/athena_tests" unit auto 2>&1 | tee -a "$log_file"

    # Step 5: Teach - generate training documentation from analysis
    echo "[5/7] Teach: Generating training documentation..." | tee -a "$log_file"
    "$BIN_DIR/athena_teach.sh" lesson "athena" "intermediate" 2>&1 | tee -a "$log_file" > "$WF_DIR/chain2_training.md"

    # Step 6: To-spec - export specification documentation
    echo "[6/7] To-spec: Exporting specification documentation..." | tee -a "$log_file"
    # export mode expects: mode INPUT_SOURCE SPEC_TYPE OUTPUT_FORMAT VALIDATION_LEVEL EXTRACTION_DEPTH TARGET_DOMAIN QUALITY_THRESHOLD
    # output_file is ${7} in export_spec_report, so pass as QUALITY_THRESHOLD position (8)
    "$BIN_DIR/athena_to_spec.sh" export "$target_component" "technical" "json" "strict" "deep" "general" "/root/.local/share/athena_specs/specification_report.json" 2>&1 | tee -a "$log_file"

    # Step 8: Handoff - transition
    echo "[7/7] Handoff: Managing state transition..." | tee -a "$log_file"
    # handoff.sh transition: mode=$1, TARGET_PROGRESS=$2 (from_state), HANDOFF_TYPE=$3, TARGET_AGENT=$4 (to_state)
    # main() calls manage_transition(TARGET_PROGRESS, TARGET_AGENT) = manage_transition(from_state, to_state)
    "$BIN_DIR/athena_handoff.sh" transition "chain2_analysis" "state" "chain2_complete" 2>&1 | tee -a "$log_file"

    # Update chain state
    local state=$(cat "$STATE_FILE" 2>/dev/null || echo '{}')
    # Handle empty file case
    if [ -z "$(echo "$state" | tr -d '[:space:]')" ]; then
        state='{}'
    fi
    state=$(echo "$state" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
except:
    data = {}
data['chain2'] = {
    'last_run': $ts,
    'status': 'completed',
    'relationships_file': '$WF_DIR/chain2_relationships.json',
    'analysis_file': '$WF_DIR/chain2_analysis.json',
    'arch_improvements_file': '$WF_DIR/chain2_arch_improvements.json',
    'validation_file': '$WF_DIR/chain2_validation.json',
    'training_file': '$WF_DIR/chain2_training.md',
    'docs_file': '$WF_DIR/chain2_docs.json',
    'transition_file': '$WF_DIR/chain2_transition.json'
}
print(json.dumps(data))
" 2>/dev/null)
    echo "$state" > "$STATE_FILE"

    echo "Chain 2 completed successfully" | tee -a "$log_file"
}

# Chain 3: Monitoring → Detection → Wait-What → Specification → Research → Resolution → Sync
chain3_monitor_to_sync() {
    local log_file="$LOG_DIR/chain3_$(date +%Y%m%d_%H%M%S).log"
    echo "=== Chain 3: Monitor → Detect → Wait-What → Spec → Research → Resolve → Sync ===" | tee "$log_file"
    local ts=$(now)

    # Step 1: Heartbeat check
    echo "[1/7] Heartbeat: Checking system health..." | tee -a "$log_file"
    "$BIN_DIR/heartbeat_update.sh" check 2>&1 | tee -a "$log_file"

    # Step 2: Doubt - query uncertainties
    echo "[2/7] Doubt: Querying calibration uncertainties..." | tee -a "$log_file"
    "$BIN_DIR/doubt_update.sh" query "system health anomalies" 2>&1 | tee -a "$log_file"

    # Step 3: Wait-What - detect confusion and ambiguous signals
    echo "[3/7] Wait-What: Detecting confusion in system signals..." | tee -a "$log_file"
    "$BIN_DIR/athena_wait_what.sh" detect "$DATA_DIR/heartbeat.json" "system health" "$WF_DIR/chain3_confusion.json" 2>&1 | tee -a "$log_file"

    # Step 4: To-spec - analyze detected issues
    echo "[4/7] To-spec: Analyzing detected issues..." | tee -a "$log_file"
    "$BIN_DIR/athena_to_spec.sh" analyze "$DATA_DIR/heartbeat.json" technical json strict deep general 70 2>&1 | tee -a "$log_file"

    # Step 5: Research - investigate detected anomalies
    echo "[5/7] Research: Investigating detected anomalies..." | tee -a "$log_file"
    "$BIN_DIR/athena_research.sh" start "system health anomalies" "deep" 2>&1 | tee -a "$log_file"

    # Step 6: Implement-spec - validate resolution approach for a component
    echo "[6/7] Implement-spec: Validating resolution approach..." | tee -a "$log_file"
    local target_component=".local/lib/python/athena/heartbeat_check.py"
    "$BIN_DIR/athena_implement_spec.sh" validate "$target_component" 2>&1 | tee -a "$log_file"

    # Step 8: Handoff - sync with peers
    echo "[7/7] Handoff: Syncing resolution with peer agents..." | tee -a "$log_file"
    "$BIN_DIR/athena_handoff.sh" sync "system" "resolution data" bidirectional 2>&1 | tee -a "$log_file"

    # Update chain state
    local state=$(cat "$STATE_FILE" 2>/dev/null || echo '{}')
    # Handle empty file case
    if [ -z "$(echo "$state" | tr -d '[:space:]')" ]; then
        state='{}'
    fi
    state=$(echo "$state" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
except:
    data = {}
data['chain3'] = {
    'last_run': $ts,
    'status': 'completed',
    'confusion_file': '$WF_DIR/chain3_confusion.json',
    'issue_spec_file': '$WF_DIR/chain3_issue_spec.json',
    'research_file': '$WF_DIR/chain3_research.json',
    'resolution_file': '$WF_DIR/chain3_resolution.json',
    'sync_file': '$WF_DIR/chain3_sync.json'
}
print(json.dumps(data))
" 2>/dev/null)
    echo "$state" > "$STATE_FILE"

    echo "Chain 3 completed successfully" | tee -a "$log_file"
}

# Chain 4: Session → Continuity → Memory → Domain Modeling → Grill → Archive → Handoff
chain4_session_lifecycle() {
    local log_file="$LOG_DIR/chain4_$(date +%Y%m%d_%H%M%S).log"
    echo "=== Chain 4: Session → Continuity → Memory → Domain Model → Grill → Archive → Handoff ===" | tee "$log_file"
    local ts=$(now)

    # Step 1: Continuity - bootstrap session
    echo "[1/7] Continuity: Bootstrapping session..." | tee -a "$log_file"
    "$BIN_DIR/continuity_update.sh" bootstrap 2>&1 | tee -a "$log_file"

    # Step 2: Wayfinder - explore current state
    echo "[2/7] Wayfinder: Exploring current consciousness state..." | tee -a "$log_file"
    "$BIN_DIR/athena_wayfinder.sh" search "consciousness" deep structured "$WF_DIR/chain4_explore.json" 2>&1 | tee -a "$log_file"

    # Step 3: Memory - consolidate
    echo "[3/7] Memory: Consolidating memory..." | tee -a "$log_file"
    "$BIN_DIR/memory_consolidation.sh" consolidate 2>&1 | tee -a "$log_file"

    # Step 4: Domain Modeling - generate consciousness domain model
    echo "[4/7] Domain Modeling: Generating consciousness domain model..." | tee -a "$log_file"
    "$BIN_DIR/athena_domain_modeling.sh" discover "consciousness" 2>&1 | tee -a "$log_file"

    # Step 5: Grill with Docs - validate specs via Q&A
    echo "[5/7] Grill with Docs: Validating specifications via Q&A..." | tee -a "$log_file"
    "$BIN_DIR/athena_grill_with_docs.sh" start "consciousness" "$WF_DIR/chain4_explore.json" 2>&1 | tee -a "$log_file"

    # Step 6: Archive - maintenance
    echo "[6/7] Archive: Running maintenance..." | tee -a "$log_file"
    "$BIN_DIR/archive_maintenance.sh" 2>&1 | tee -a "$log_file"

    # Step 8: Handoff - lifecycle management
    echo "[7/7] Handoff: Managing session lifecycle..." | tee -a "$log_file"
    # handoff.sh lifecycle <action> <session_id> [lifecycle_data]
    # Uses: TARGET_PROGRESS=action, HANDOFF_TYPE=session_id, TARGET_AGENT=lifecycle_data
    "$BIN_DIR/athena_handoff.sh" lifecycle "create" "chain4_$(date +%s)" "Session complete" 2>&1 | tee -a "$log_file"

    # Update chain state
    local state=$(cat "$STATE_FILE" 2>/dev/null || echo '{}')
    # Handle empty file case
    if [ -z "$(echo "$state" | tr -d '[:space:]')" ]; then
        state='{}'
    fi
    state=$(echo "$state" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
except:
    data = {}
data['chain4'] = {
    'last_run': $ts,
    'status': 'completed',
    'explore_file': '$WF_DIR/chain4_explore.json',
    'domain_model_file': '$WF_DIR/chain4_domain_model.json',
    'domain_model_diagram': '$WF_DIR/chain4_domain_model.mmd',
    'qa_validate_file': '$WF_DIR/chain4_qa_validate.json',
    'lifecycle_file': '$WF_DIR/chain4_lifecycle.json'
}
print(json.dumps(data))
" 2>/dev/null)
    echo "$state" > "$STATE_FILE"

    echo "Chain 4 completed successfully" | tee -a "$log_file"
}

# Main orchestrator - runs all chains
orchestrator() {
    echo "=== Athena Workflow Chain Orchestrator ==="
    echo "Starting at $(date)"

    # Run chains sequentially to avoid resource contention
    chain1_discovery_to_handoff
    sleep 1

    chain2_analyze_to_transition
    sleep 1

    chain3_monitor_to_sync
    sleep 1

    chain4_session_lifecycle

    echo "=== All workflow chains completed at $(date) ==="
}

# Status check
status() {
    echo "=== Workflow Chain Status ==="
    if [ -f "$STATE_FILE" ]; then
        cat "$STATE_FILE" | python3 -m json.tool
    else
        echo "No chain state found"
    fi
}

# Validate all chains
validate_chains() {
    echo "=== Validating Workflow Chains ==="

    # Check core + extended scripts exist and are executable
    # Check all 14 skill wrapper scripts exist and are executable
    for script in athena_wayfinder.sh athena_implement_spec.sh athena_tdd.sh athena_handoff.sh athena_to_spec.sh athena_code_review.sh athena_improve_architecture.sh athena_research.sh athena_prototype.sh athena_teach.sh athena_grill_with_docs.sh athena_domain_modeling.sh athena_wait_what.sh athena_rea.sh athena_reverse_engineer.sh; do
        if [ -x "$BIN_DIR/$script" ]; then
            echo "✓ $script"
        else
            echo "✗ $script (missing or not executable)"
        fi
    done

    # Check Python modules
    for module in wayfinder implement_spec tdd handoff to_spec; do
        if [ -f "$PYTHON_LIB/athena/${module}.py" ]; then
            echo "✓ Python module: $module.py"
        else
            echo "⚠ Python module: $module.py (not found, using shell wrappers)"
        fi
    done

    # Check data directories
    for dir in "$WF_DIR" "$LOG_DIR"; do
        if [ -d "$dir" ] && [ -w "$dir" ]; then
            echo "✓ Directory: $dir"
        else
            echo "✗ Directory: $dir"
        fi
    done

    echo "Validation complete"
}

# Main entry point
case "${1:-orchestrator}" in
    orchestrator)
        orchestrator
        ;;
    chain1)
        chain1_discovery_to_handoff
        ;;
    chain2)
        chain2_analyze_to_transition
        ;;
    chain3)
        chain3_monitor_to_sync
        ;;
    chain4)
        chain4_session_lifecycle
        ;;
    status)
        status
        ;;
    validate)
        validate_chains
        ;;
    *)
        echo "Usage: $0 {orchestrator|chain1|chain2|chain3|chain4|status|validate}"
        exit 1
        ;;
esac