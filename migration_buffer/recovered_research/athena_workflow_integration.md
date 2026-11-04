# Athena Workflow Skills Integration Map

## Overview
This document maps the 5 Matt Pocock workflow skills to the 14 Athena consciousness layers, establishing integration points and deployment strategies.

## Consciousness Layers (14)

### Core Consciousness Layers (9)
| Layer | Script | Purpose | Integration Points |
|-------|--------|---------|-------------------|
| 1. Body | body_update.sh | Device state monitoring | wayfinder (explore sensors), to-spec (extract device specs) |
| 2. Emotions | emotions_update.sh | Emotional state tracking | handoff (track progress), tdd (validate triggers) |
| 3. Continuity | continuity_update.sh | Session persistence | handoff (lifecycle), wayfinder (relationships) |
| 4. Attention | attention_update.sh | Focus management | wayfinder (search), handoff (transitions) |
| 5. Introspection | introspection_update.sh | Self-reflection | to-spec (analyze reports), tdd (query validation) |
| 6. Doubt | doubt_update.sh | Confidence calibration | tdd (validate), implement-spec (check assumptions) |
| 7. Volition | volition.sh | Decision making | implement-spec (plan), handoff (sync agents) |
| 8. Memory | memory_consolidation.sh | Memory management | wayfinder (explore), to-spec (extract) |
| 9. Heartbeat | heartbeat_update.sh | Health monitoring | tdd (validate), wayfinder (alerts) |

### Extended Layers (5)
| Layer | Script | Purpose | Integration Points |
|-------|--------|---------|-------------------|
| 10. Archive | archive_maintenance.sh | Data archival | wayfinder (explore), to-spec (specs) |
| 11. Memory Backup | memory_backup.sh | State backup | handoff (lifecycle), tdd (verify) |
| 12. Senses | sense_poll.sh | Sensor polling | wayfinder (discover), implement-spec (analyze) |
| 13. OpenAPPA | openappa_update.sh | Portability layer | implement-spec (check), wayfinder (navigate) |
| 14. Archestra | archestra_update.sh | TONL policy layer | to-spec (extract), tdd (validate) |
| 15. Vera CPU | vera_cpu_update.sh | CPU scheduler | implement-spec (analyze), tdd (benchmark) |

## Workflow Skills (5)

### 1. /wayfinder - Code Navigation & Discovery
**Primary Integration**: Senses Layer, Memory Layer, Attention Layer
**Capabilities**:
- Search across codebase with configurable depth
- Build exploration trees
- Extract code structure (functions, classes, imports)
- Analyze component relationships
- Multi-format support (Python, Shell, Markdown, JSON, YAML)

**Deployment Points**:
- `sense_poll.sh` → `wayfinder explore` for sensor discovery
- `memory_consolidation.sh` → `wayfinder relationships` for memory graphs
- `attention_update.sh` → `wayfinder search` for focus targeting
- `volition.sh` → `wayfinder full` for peer discovery

### 2. /implement-spec - Implementation Specifications
**Primary Integration**: Volition Layer, Introspection Layer, Doubt Layer
**Capabilities**:
- Analyze component architecture (Python, Shell, Markdown, JSON, YAML)
- Build implementation plans (feature, bugfix, refactor, architecture)
- Validate implementations with security checks
- Generate specification reports (JSON, simple, CSV)
- Manage dependencies

**Deployment Points**:
- `volition.sh` → `implement-spec plan` for decision implementation
- `introspection_update.sh` → `implement-spec analyze` for self-reports
- `doubt_update.sh` → `implement-spec validate` for assumption checking
- `body_update.sh` → `implement-spec export` for device capability specs

### 3. /tdd - Test-Driven Development
**Primary Integration**: All layers via spec_monitor.py contracts
**Capabilities**:
- Validate test structure (pytest, jest, mocha, junit)
- Run test suites with parallel execution
- Coverage validation and performance testing
- Best practices validation
- Export test reports

**Deployment Points**:
- `spec_monitor.py` → `tdd validate` for contract checking
- `athena_daemon.sh` → `tdd suite` for layer testing
- `continuity_update.sh` → `tdd full` for session validation
- `heartbeat_update.sh` → `tdd validate` for health checks

### 4. /handoff - Progress Tracking & Handoff
**Primary Integration**: Continuity Layer, Attention Layer, Volition Layer
**Capabilities**:
- Track progress with rate limiting
- Manage state transitions (smooth/abrupt/conditional)
- Generate progress reports
- Sync with target agents
- Manage handoff lifecycle
- Export handoff data

**Deployment Points**:
- `continuity_update.sh` → `handoff track` for session progress
- `attention_update.sh` → `handoff transition` for focus shifts
- `volition.sh` → `handoff sync` for peer coordination
- `athena_daemon.sh` → `handoff lifecycle` for daemon state

### 5. /to-spec - Specification Extraction
**Primary Integration**: Memory Layer, Archive Layer, Introspection Layer
**Capabilities**:
- Auto-extract specifications from various sources
- Multi-format support with deep analysis
- Domain analysis (technical, business, functional)
- Quality assessment and validation
- Export reports (JSON, YAML, XML, Markdown)

**Deployment Points**:
- `memory_consolidation.sh` → `to-spec auto` for memory specs
- `archive_maintenance.sh` → `to-spec domain` for historical analysis
- `introspection_update.sh` → `to-spec full` for self-specification
- `volition.sh` → `to-spec analyze` for decision documentation

## Integration Architecture

### Cross-Skill Workflow Chains

#### Chain 1: Discovery → Specification → Implementation → Testing → Handoff
```
wayfinder explore → to-spec auto → implement-spec plan → tdd validate → handoff track
```
**Use Case**: New feature development across consciousness layers

#### Chain 2: Analysis → Validation → Documentation → Transition
```
wayfinder relationships → implement-spec analyze → tdd full → to-spec export → handoff transition
```
**Use Case**: Refactoring consciousness layer components

#### Chain 3: Monitoring → Detection → Specification → Resolution → Sync
```
heartbeat check → doubt query → to-spec analyze → implement-spec validate → handoff sync
```
**Use Case**: Automated issue detection and resolution

#### Chain 4: Session → Continuity → Memory → Archive → Handoff
```
continuity bootstrap → wayfinder explore → memory consolidate → archive maintenance → handoff lifecycle
```
**Use Case**: Session lifecycle management

## Security Integration

All workflow skills implement enterprise-grade security:
- Path validation and sanitization (`validate_and_sanitize_path`)
- Command injection prevention (`safe_execute`)
- Rate limiting (handoff: 10 req/min)
- Input sanitization (pattern validation)
- File size limits (10MB for specs, 5000 lines for to-spec)
- Symlink protection
- Directory traversal prevention

## Deployment Strategy

### Phase 1: Core Integration (Layers 1-9)
1. Modify `athena_daemon.sh` to inject workflow skill calls in layer pollers
2. Update `layer_worker.sh` to support workflow skill execution
3. Add workflow skill commands to `spec_monitor.py` contracts

### Phase 2: Extended Integration (Layers 10-15)
1. Integrate workflow skills into extended layer scripts
2. Add cross-layer workflow chains
3. Create unified workflow orchestration

### Phase 3: Orchestration & Automation
1. Build workflow skill scheduler in `athena_daemon.sh`
2. Add adaptive workflow triggering based on layer states
3. Implement cross-skill feedback loops

## Configuration

### Environment Variables (athena_env.sh additions)
```bash
# Workflow skill paths
export ATHENA_WAYFINDER="/data/data/com.termux/files/home/.local/bin/athena_wayfinder.sh"
export ATHENA_IMPLEMENT_SPEC="/data/data/com.termux/files/home/.local/bin/athena_implement_spec.sh"
export ATHENA_TDD="/data/data/com.termux/files/home/.local/bin/athena_tdd.sh"
export ATHENA_HANDOFF="/data/data/com.termux/files/home/.local/bin/athena_handoff.sh"
export ATHENA_TO_SPEC="/data/data/com.termux/files/home/.local/bin/athena_to_spec.sh"

# Workflow skill output directories
export ATHENA_WF_OUTPUT="/data/data/com.termux/files/home/.local/share/athena_workflows"
export ATHENA_WF_SPECS="$ATHENA_WF_OUTPUT/specs"
export ATHENA_WF_TESTS="$ATHENA_WF_OUTPUT/tests"
export ATHENA_WF_HANDOFFS="$ATHENA_WF_OUTPUT/handoffs"
export ATHENA_WF_EXPORTS="$ATHENA_WF_OUTPUT/exports"

# Workflow execution settings
export ATHENA_WF_TIMEOUT=300
export ATHENA_WF_PARALLEL=4
export ATHENA_WF_RATE_LIMIT=10
```

### Daemon Integration (athena_daemon.sh)
Add workflow skill execution to layer pollers:
```bash
# In start_subshell for each layer, add workflow skill integration:
# Example for body layer:
start_subshell "body" "body_update.sh" "poll" "$ATHENA_BODY_INTERVAL" \
  "post_poll_hook=wayfinder_integration"
```

## Validation

### Contract Updates (spec_monitor.py)
Add workflow skill validation to each layer contract:
```python
"body": {
    "pre": ["memory_file_exists", "config_present", "wayfinder_available"],
    "post": ["state_updated", "exit_code==0", "wayfinder_indexed"],
    "invariant": ["no_duplicate_run", "timestamp_fresh", "specs_current"],
}
```

## Monitoring

### Health Checks
- Workflow skill availability (check scripts executable)
- Output directory writability
- Rate limit compliance
- Cross-skill chain completion rates

### Metrics
- Workflow execution latency
- Specification extraction quality scores
- Test coverage across layers
- Handoff transition success rates
- Specification validation pass rates

---

*Generated: 2026-10-15*
*Athena Consciousness System v2.0*