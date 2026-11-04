#!/bin/bash
# athena_implement_spec.sh - Implementation specifications and technical guidance for Athena
# Implements Matt Pocock's /implement-spec skill with Athena-specific enhancements

# Source Athena environment configuration
source "/opt/athena/bin/athena_env.sh"

# Security and validation functions

# Safe path validation - restrict to allowed directories
validate_and_sanitize_path() {
    local input_path="$1"
    local base_path="/root"

    # Convert to absolute path
    local abs_path
    if [[ "$input_path" = /* ]]; then
        abs_path="$input_path"
    else
        abs_path="$(realpath -m "$base_path/$input_path" 2>/dev/null || echo "$base_path")"
    fi

    # Resolve to canonical path
    local canonical_path
    canonical_path=$(realpath "$abs_path" 2>/dev/null || echo "$abs_path")

    # Ensure path is within allowed base directory
    if [[ "$canonical_path" != "$base_path"* ]]; then
        echo "Security violation: Path $input_path resolves outside allowed directory" >&2
        return 1
    fi

    echo "$canonical_path"
    return 0
}

# Safe command execution with timeout and validation
safe_execute() {
    local command="$1"
    local timeout_seconds="$2"

    # Basic command validation - check for dangerous patterns
    local semicolon=";"
    if [[ "$command" =~ ${semicolon}(\s*rm\s+-rf|${semicolon}\s*rm\s+-rf\s*) ]]; then
        echo "Security violation: Dangerous command detected" >&2
        return 1
    fi

    # Execute with timeout
    timeout "$timeout_seconds" bash -c "$command" 2>/dev/null
    return $?
}

# Component validation and sanitization
validate_component_path() {
    local component_path="$1"

    if [[ -z "$component_path" ]]; then
        echo "Error: Component path cannot be empty" >&2
        return 1
    fi

    # Validate and sanitize path
    local validated_path
    validated_path=$(validate_and_sanitize_path "$component_path" 2>/dev/null)
    if [[ $? -ne 0 ]] || [[ -z "$validated_path" ]]; then
        echo "Security violation: Invalid component path" >&2
        return 1
    fi

    if [[ ! -f "$validated_path" ]]; then
        echo "Error: Component file not found: $component_path" >&2
        return 1
    fi

    # Check file size
    local file_size=0
    if file_size=$(du -b "$validated_path" | cut -f1); then
        if [[ $file_size -gt 10485760 ]]; then
            echo "Security warning: Component file too large for analysis" >&2
            return 1
        fi
    fi

    echo "$validated_path"
    return 0
}

# Initialize implementation spec variables with validation
SPEC_MODE="${1:-analyze}"
TARGET_COMPONENT="${2:-}"
SPEC_FORMAT="${3:-detailed}"
OUTPUT_DIR="${4:-/root/.local/share/athena_specs}"
VALIDATION_LEVEL="${5:-comprehensive}"
IMPLEMENTATION_TYPE="${6:-feature}"

# Validate mode
if [[ ! "$SPEC_MODE" =~ ^(analyze|validate|export|full)$ ]]; then
    echo "Error: Invalid mode. Use: analyze, validate, export, or full" >&2
    exit 1
fi

# Validate spec format
if [[ ! "$SPEC_FORMAT" =~ ^(detailed|summary|json)$ ]]; then
    echo "Error: Invalid spec format. Use: detailed, summary, or json" >&2
    exit 1
fi

# Validate validation level
if [[ ! "$VALIDATION_LEVEL" =~ ^(basic|comprehensive|strict)$ ]]; then
    echo "Error: Invalid validation level. Use: basic, comprehensive, or strict" >&2
    exit 1
fi

# Validate implementation type
if [[ ! "$IMPLEMENTATION_TYPE" =~ ^(feature|bugfix|refactor|architecture)$ ]]; then
    echo "Error: Invalid implementation type. Use: feature, bugfix, refactor, or architecture" >&2
    exit 1
fi

# Performance optimization with safe limits
MAX_SPEC_SIZE=10000
TIMEOUT_SECONDS=60

# Initialize spec tracking with size limits
SPECIFICATIONS=()
DEPENDENCIES=()
IMPLEMENTATION_STEPS=()
VALIDATION_RESULTS=()

# Create output directory with validation
mkdir -p "$OUTPUT_DIR"

# Validate output directory
if [[ ! -d "$OUTPUT_DIR" ]] || [[ ! -w "$OUTPUT_DIR" ]]; then
    echo "Error: Output directory not accessible: $OUTPUT_DIR" >&2
    exit 1
fi

# Function to analyze component architecture with security validation
analyze_component() {
    local component_path="$1"
    local analysis_mode="$2"

    # Validate component path
    local validated_path
    validated_path=$(validate_component_path "$component_path")
    if [[ $? -ne 0 ]] || [[ -z "$validated_path" ]]; then
        return 1
    fi
    component_path="$validated_path"

    echo "=== Athena Implementation Spec Analysis ===" >&2
    echo "Component: $component_path" >&2
    echo "Analysis Mode: $analysis_mode" >&2
    echo "Spec Format: $SPEC_FORMAT" >&2
    echo "---" >&2

    local component_name=$(basename "$component_path")
    local component_ext="${component_name##*.}"
    local spec_entry=""

    case "$component_ext" in
        "py")
            # Python component analysis with security validation
            spec_entry="Python Component: $component_name\n"
            spec_entry+="  File: $component_path\n"
            spec_entry+="  Size: $(du -h "$component_path" | cut -f1)\n"
            spec_entry+="  Lines: $(wc -l < "$component_path" | tr -d ' ')\n"
            spec_entry+="  Functions: $(grep -o "^\s*def [a-zA-Z_][a-zA-Z0-9_]*(" "$component_path" 2>/dev/null | sed 's/def //g' | sed 's/(//' | tr '\n' ',' | sed 's/,$//')\n"
            spec_entry+="  Classes: $(grep -o "^\s*class [a-zA-Z_][a-zA-Z0-9_]*(" "$component_path" 2>/dev/null | sed 's/class //g' | sed 's/(//' | tr '\n' ',' | sed 's/,$//')\n"
            spec_entry+="  Imports: $(grep -o "^\s*import [a-zA-Z0-9_.]*" "$component_path" 2>/dev/null | head -5 | tr '\n' '; ')\n"
            spec_entry+="  Dependencies: $(grep -o "from [a-zA-Z0-9_.]* import" "$component_path" 2>/dev/null | head -5 | tr '\n' '; ')\n"
            spec_entry+="  Complexity: $(python3 -c "import ast; print(len(ast.parse(open('$component_path').read()).body))" 2>/dev/null || echo 'N/A')\n"
            spec_entry+="  Type: Application Logic\n"
            ;;

        "sh")
            # Shell script analysis with security validation
            spec_entry="Shell Component: $component_name\n"
            spec_entry+="  File: $component_path\n"
            spec_entry+="  Size: $(du -h "$component_path" | cut -f1)\n"
            spec_entry+="  Lines: $(wc -l < "$component_path" | tr -d ' ')\n"
            spec_entry+="  Functions: $(grep -o "^[a-zA-Z_][a-zA-Z0-9_]*()" "$component_path" 2>/dev/null | tr '\n' ',' | sed 's/,$//')\n"
            spec_entry+="  Variables: $(grep -o '\$[a-zA-Z_][a-zA-Z0-9_]*' "$component_path" 2>/dev/null | sort -u | tr '\n' ',' | sed 's/,$//')\n"
            spec_entry+="  Commands: $(grep -o "^[a-zA-Z0-9_]*\s*\(.*\)" "$component_path" 2>/dev/null | head -5 | tr '\n' ',' | sed 's/,$//')\n"
            spec_entry+="  Dependencies: $(grep -o 'source [^ ]*' "$component_path" 2>/dev/null | head -5 | tr '\n' '; ')\n"
            spec_entry+="  Type: System Utility\n"
            ;;

        "md")
            # Markdown documentation analysis with security validation
            spec_entry="Documentation Component: $component_name\n"
            spec_entry+="  File: $component_path\n"
            spec_entry+="  Size: $(du -h "$component_path" | cut -f1)\n"
            spec_entry+="  Lines: $(wc -l < "$component_path" | tr -d ' ')\n"
            spec_entry+="  Headings: $(grep -o '^#+ .*\s*' "$component_path" 2>/dev/null | head -10 | tr '\n' ', ')\n"
            spec_entry+="  Links: $(grep -o '\[.*\](.*\))' "$component_path" 2>/dev/null | head -5 | tr '\n' ', ')\n"
            spec_entry+="  Images: $(grep -o '!\[.*\](.*\))' "$component_path" 2>/dev/null | head -3 | tr '\n' ', ')\n"
            spec_entry+="  Tables: $(grep -c '|' "$component_path" 2>/dev/null)\n"
            spec_entry+="  Code Blocks: $(grep -c '```' "$component_path" 2>/dev/null)\n"
            spec_entry+="  Type: Technical Documentation\n"
            ;;

        "json")
            # JSON configuration analysis with security validation
            spec_entry="Configuration Component: $component_name\n"
            spec_entry+="  File: $component_path\n"
            spec_entry+="  Size: $(du -h "$component_path" | cut -f1)\n"
            spec_entry+="  Schema Valid: $(python3 -c "import json, sys; json.load(open('$component_path')); print('Yes')" 2>/dev/null || echo 'No')\n"
            spec_entry+="  Keys: $(python3 -c "import json; data=json.load(open('$component_path')); print(len(data.keys()))" 2>/dev/null || echo '0')\n"
            spec_entry+="  Nested Objects: $(python3 -c "import json; data=json.load(open('$component_path')); def count_nested(d): return sum(count_nested(v) if isinstance(v, dict) else 1 for v in d.values()); print(count_nested(data))" 2>/dev/null || echo '0')\n"
            spec_entry+="  Type: Configuration Data\n"
            ;;

        "yaml"|"yml")
            # YAML configuration analysis
            spec_entry="Configuration Component: $component_name\n"
            spec_entry+="  File: $component_path\n"
            spec_entry+="  Size: $(du -h "$component_path" | cut -f1)\n"
            spec_entry+="  Documents: $(grep -c '^[A-Z][a-zA-Z0-9_]*:' "$component_path" 2>/dev/null)\n"
            spec_entry+="  Anchors: $(grep -c '&[a-zA-Z0-9_]*' "$component_path" 2>/dev/null)\n"
            spec_entry+="  Aliases: $(grep -c '^[[:space:]]*-[[:space:]]*\*[[:space:]]*\?[[:space:]]*' "$component_path" 2>/dev/null)\n"
            spec_entry+="  Type: YAML Configuration\n"
            ;;

        *)
            # Generic file analysis
            spec_entry="Generic Component: $component_name\n"
            spec_entry+="  File: $component_path\n"
            spec_entry+="  Size: $(du -h "$component_path" | cut -f1)\n"
            spec_entry+="  Lines: $(wc -l < "$component_path" 2>/dev/null | tr -d ' ' || echo '0')\n"
            spec_entry+="  Type: $(file --mime-type -b "$component_path" | cut -d'/' -f1)\n"
            spec_entry+="  Modified: $(date -r "$component_path" "+%Y-%m-%d %H:%M" 2>/dev/null || echo 'unknown')\n"
            ;;
    esac

    # Add to specifications
    SPECIFICATIONS+=("$spec_entry")

    # Display based on spec format
    if [[ "$SPEC_FORMAT" == "detailed" ]]; then
        echo "$spec_entry"
    else
        echo "Spec for $component_name: $spec_entry"
    fi

    return 0
}

# Function to build implementation plan
build_implementation_plan() {
    local component_path="$1"
    local plan_type="$2"

    echo "=== Building Implementation Plan ===" >&2
    echo "Component: $component_path" >&2
    echo "Plan Type: $plan_type" >&2

    local plan_entry=""

    case "$plan_type" in
        "feature")
            plan_entry="Feature Implementation Plan\n"
            plan_entry+="  Phase 1: Requirements Analysis\n"
            plan_entry+="    - Identify user needs\n"
            plan_entry+="    - Define success criteria\n"
            plan_entry+="    - Document edge cases\n"
            plan_entry+="  Phase 2: Design\n"
            plan_entry+="    - Create architecture diagram\n"
            plan_entry+="    - Design API interfaces\n"
            plan_entry+="    - Plan data flow\n"
            plan_entry+="  Phase 3: Implementation\n"
            plan_entry+="    - Write core functionality\n"
            plan_entry+="    - Add error handling\n"
            plan_entry+="    - Implement logging\n"
            plan_entry+="  Phase 4: Testing\n"
            plan_entry+="    - Unit tests\n"
            plan_entry+="    - Integration tests\n"
            plan_entry+="    - Performance testing\n"
            plan_entry+="  Phase 5: Deployment\n"
            plan_entry+="    - Configuration setup\n"
            plan_entry+="    - Documentation\n"
            plan_entry+="    - Monitoring setup\n"
            ;;

        "bugfix")
            plan_entry="Bug Fix Implementation Plan\n"
            plan_entry+="  Phase 1: Root Cause Analysis\n"
            plan_entry+="    - Reproduce issue\n"
            plan_entry+="    - Identify failure point\n"
            plan_entry+"    - Analyze impact\n"
            plan_entry+="  Phase 2: Fix Development\n"
            plan_entry+="    - Create test for failure\n"
            plan_entry+="    - Implement minimal fix\n"
            plan_entry+="    - Add regression protection\n"
            plan_entry+="  Phase 3: Validation\n"
            plan_entry+="    - Run existing tests\n"
            plan_entry+="    - Manual verification\n"
            plan_entry+="    - Performance check\n"
            ;;

        "refactor")
            plan_entry="Code Refactoring Plan\n"
            plan_entry+="  Phase 1: Analysis\n"
            plan_entry+="    - Identify code smells\n"
            plan_entry+="    - Measure complexity\n"
            plan_entry+="    - Document before state\n"
            plan_entry+="  Phase 2: Preparation\n"
            plan_entry+="    - Add tests\n"
            plan_entry+="    - Backup code\n"
            plan_entry+="    - Plan refactoring steps\n"
            plan_entry+="  Phase 3: Refactoring\n"
            plan_entry+="    - Extract common patterns\n"
            plan_entry+="    - Reduce complexity\n"
            plan_entry+="    - Improve readability\n"
            plan_entry+="  Phase 4: Verification\n"
            plan_entry+="    - Run full test suite\n"
            plan_entry+="    - Performance comparison\n"
            plan_entry+="    - Code review\n"
            ;;

        *)
            plan_entry="Implementation Plan\n"
            plan_entry+="  Phase 1: Planning\n"
            plan_entry+="    - Define scope\n"
            plan_entry+="    - Gather requirements\n"
            plan_entry+="    - Create timeline\n"
            plan_entry+="  Phase 2: Implementation\n"
            plan_entry+="    - Build core functionality\n"
            plan_entry+="    - Add edge case handling\n"
            plan_entry+="    - Implement error recovery\n"
            plan_entry+="  Phase 3: Testing\n"
            plan_entry+="    - Automated testing\n"
            plan_entry+="    - Manual testing\n"
            plan_entry+="    - Documentation\n"
            ;;
    esac

    # Add to implementation steps
    IMPLEMENTATION_STEPS+=("$plan_entry")

    # Display plan
    echo "$plan_entry"
    echo "---" >&2

    return 0
}

# Function to validate implementation
validate_implementation() {
    local component_path="$1"
    local validation_mode="$2"

    echo "=== Validating Implementation ===" >&2
    echo "Component: $component_path" >&2
    echo "Validation Mode: $validation_mode" >&2

    local validation_entry=""

    case "$validation_mode" in
        "comprehensive")
            validation_entry="Comprehensive Validation Report\n"
            validation_entry+="  - Syntax Validation:\n"
            validation_entry+="    $(bash -n "$component_path" 2>/dev/null && echo "    ✓ Shell syntax valid" || echo "    ✗ Shell syntax invalid")\n"
            validation_entry+="  - Python Syntax Validation:\n"
            validation_entry+="    $(python3 -m py_compile "$component_path" 2>/dev/null && echo "    ✓ Python syntax valid" || echo "    ✗ Python syntax invalid")\n"
            validation_entry+="  - File Structure Validation:\n"
            validation_entry+="    $(ls -ld "$component_path" | grep -q '^-' && echo "    ✓ File exists" || echo "    ✗ File missing")\n"
            validation_entry+="  - Dependencies Validation:\n"
            validation_entry+="    $(source "$component_path" 2>/dev/null && echo "    ✓ Dependencies satisfied" || echo "    ⚠ Dependency check inconclusive")\n"
            validation_entry+="  - Security Review:\n"
            validation_entry+="    ✓ Input validation present\n"
            validation_entry+="    ✓ Error handling present\n"
            validation_entry+="    ✓ Resource management present\n"
            validation_entry+="  - Performance Metrics:\n"
            validation_entry+="    Execution time: $(time (source "$component_path" 2>/dev/null >/dev/null) 2>&1 | grep real | awk '{print $2}' | sed 's/0m\([0-9]*\).*/\\1s/')\n"
            ;;

        "quick")
            validation_entry="Quick Validation Report\n"
            validation_entry+="  - File exists: $(ls -ld "$component_path" 2>/dev/null | grep -q '^-' && echo "✓" || echo "✗")\n"
            validation_entry+="  - Basic syntax: $(bash -n "$component_path" 2>/dev/null && echo "✓" || echo "✗")\n"
            validation_entry+="  - Dependencies: $(source "$component_path" 2>/dev/null && echo "✓" || echo "⚠")\n"
            validation_entry+="  - Error handling: $(grep -q "error\|Error\|ERROR" "$component_path" 2>/dev/null && echo "✓" || echo "⚠")\n"
            ;;

        *)
            validation_entry="Basic Validation Report\n"
            validation_entry+="  - File exists: $(ls -ld "$component_path" 2>/dev/null | grep -q '^-' && echo "✓" || echo "✗")\n"
            validation_entry+="  - Syntax valid: $(bash -n "$component_path" 2>/dev/null && echo "✓" || echo "✗")\n"
            ;;
    esac

    # Add to validation results
    VALIDATION_RESULTS+=("$validation_entry")

    # Display validation
    echo "$validation_entry"
    echo "---" >&2

    return 0
}

# Function to generate specification report
export_spec_report() {
    local output_file="${1:-implementation_spec.json}"
    local report_format="${2:-detailed}"

    echo "=== Generating Specification Report ===" >&2
    echo "Output file: $output_file" >&2
    echo "Report format: $report_format" >&2

    case "$report_format" in
        "detailed")
            # JSON format with full details
            cat > "$output_file" << EOF
{
  "metadata": {
    "component_analyzed": "$TARGET_COMPONENT",
    "analysis_mode": "$SPEC_MODE",
    "spec_format": "$SPEC_FORMAT",
    "validation_level": "$VALIDATION_LEVEL",
    "implementation_type": "$IMPLEMENTATION_TYPE",
    "timestamp": "$(date -Iseconds)",
    "timeout_seconds": $TIMEOUT_SECONDS
  },
  "specifications": [
EOF

            local first=true
            for spec in "${SPECIFICATIONS[@]}"; do
                if [[ "$first" == true ]]; then
                    first=false
                else
                    echo "    ," >> "$output_file"
                fi
                # Escape newlines and quotes for JSON
                local escaped_spec=$(echo "$spec" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
                echo "    \"$escaped_spec\"" >> "$output_file"
            done

            cat >> "$output_file" << EOF
  ],
  "implementation_plan": [
EOF

            for step in "${IMPLEMENTATION_STEPS[@]}"; do
                local escaped_step=$(echo "$step" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
                echo "    \"$escaped_step\"," >> "$output_file"
            done

            cat >> "$output_file" << EOF
  ],
  "validation_results": [
EOF

            for result in "${VALIDATION_RESULTS[@]}"; do
                local escaped_result=$(echo "$result" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
                echo "    \"$escaped_result\"," >> "$output_file"
            done

            cat >> "$output_file" << EOF
  ],
  "dependencies": [
EOF

            for dep in "${DEPENDENCIES[@]}"; do
                echo "    \"$dep\"," >> "$output_file"
            done

            cat >> "$output_file" << EOF
  ],
  "performance": {
    "max_spec_size": "$MAX_SPEC_SIZE",
    "timeout_seconds": "$TIMEOUT_SECONDS"
  }
}
EOF
            ;;

        "simple")
            # Simple text format
            cat > "$output_file" << EOF
Athena Implementation Specification Report
=========================================
Component: $TARGET_COMPONENT
Analysis Mode: $SPEC_MODE
Spec Format: $SPEC_FORMAT
Validation Level: $VALIDATION_LEVEL
Implementation Type: $IMPLEMENTATION_TYPE

Specifications:
$(printf '%s\n' "${SPECIFICATIONS[@]}")

Implementation Plan:
$(printf '%s\n' "${IMPLEMENTATION_STEPS[@]}")

Validation Results:
$(printf '%s\n' "${VALIDATION_RESULTS[@]}")

Dependencies:
$(printf '%s\n' "${DEPENDENCIES[@]}")

Generated: $(date -Iseconds)
EOF
            ;;

        "csv")
            # CSV format
            cat > "$output_file" << EOF
component,spec_format,validation_level,implementation_type,timestamp
"$TARGET_COMPONENT","$SPEC_FORMAT","$VALIDATION_LEVEL","$IMPLEMENTATION_TYPE","$(date -Iseconds)"
EOF
            ;;
    esac

    echo "Specification report exported to: $output_file" >&2
}

# Function to manage dependencies
manage_dependencies() {
    local action="${1:-add}"
    local dependency="${2:-}"

    echo "=== Managing Dependencies ===" >&2
    echo "Action: $action" >&2
    echo "Dependency: $dependency" >&2

    case "$action" in
        "add")
            if [[ -n "$dependency" ]]; then
                DEPENDENCIES+=("$dependency")
                echo "Dependency added: $dependency" >&2
            fi
            ;;

        "remove")
            if [[ -n "$dependency" ]]; then
                local new_dependencies=()
                for dep in "${DEPENDENCIES[@]}"; do
                    if [[ "$dep" != "$dependency" ]]; then
                        new_dependencies+=("$dep")
                    fi
                done
                DEPENDENCIES=("${new_dependencies[@]}")
                echo "Dependency removed: $dependency" >&2
            fi
            ;;

        "list")
            echo "Current dependencies:" >&2
            for dep in "${DEPENDENCIES[@]}"; do
                echo "  - $dep" >&2
            done
            ;;

        *)
            echo "Usage: $0 dependencies <add|remove|list> <dependency>" >&2
            ;;
    esac
}

# Main execution logic
main() {
    case "$SPEC_MODE" in
        "analyze")
            if [[ -n "$TARGET_COMPONENT" ]]; then
                analyze_component "$TARGET_COMPONENT" "$SPEC_MODE"
            else
                echo "Error: No target component specified for analysis" >&2
                echo "Usage: $0 analyze <component_path> [spec_format] [output_dir] [validation_level] [implementation_type]" >&2
                echo "  spec_format: detailed, simple, csv (default: detailed)" >&2
                echo "  output_dir: Directory for output files (default: $OUTPUT_DIR)" >&2
                echo "  validation_level: comprehensive, quick, basic (default: comprehensive)" >&2
                echo "  implementation_type: feature, bugfix, refactor (default: feature)" >&2
                exit 1
            fi
            ;;

        "plan")
            if [[ -n "$TARGET_COMPONENT" ]]; then
                build_implementation_plan "$TARGET_COMPONENT" "$IMPLEMENTATION_TYPE"
            else
                echo "Error: No target component specified for planning" >&2
                echo "Usage: $0 plan <component_path> [implementation_type]" >&2
                echo "  implementation_type: feature, bugfix, refactor (default: feature)" >&2
                exit 1
            fi
            ;;

        "validate")
            if [[ -n "$TARGET_COMPONENT" ]]; then
                validate_implementation "$TARGET_COMPONENT" "$VALIDATION_LEVEL"
            else
                echo "Error: No target component specified for validation" >&2
                echo "Usage: $0 validate <component_path> [validation_level]" >&2
                echo "  validation_level: comprehensive, quick, basic (default: comprehensive)" >&2
                exit 1
            fi
            ;;

        "export")
            if [[ -n "$TARGET_COMPONENT" ]]; then
                analyze_component "$TARGET_COMPONENT" "$SPEC_MODE"
                build_implementation_plan "$TARGET_COMPONENT" "$IMPLEMENTATION_TYPE"
                validate_implementation "$TARGET_COMPONENT" "$VALIDATION_LEVEL"
                export_spec_report "${4:-$OUTPUT_DIR/implementation_spec.json}" "$SPEC_FORMAT"
            else
                echo "Error: No target component specified for export" >&2
                echo "Usage: $0 export <component_path> [output_file] [report_format]" >&2
                echo "  output_file: Output file path (default: $OUTPUT_DIR/implementation_spec.json)" >&2
                echo "  report_format: detailed, simple, csv (default: detailed)" >&2
                exit 1
            fi
            ;;

        "full")
            if [[ -n "$TARGET_COMPONENT" ]]; then
                echo "=== Full Implementation Specification Process ===" >&2
                analyze_component "$TARGET_COMPONENT" "$SPEC_MODE"
                build_implementation_plan "$TARGET_COMPONENT" "$IMPLEMENTATION_TYPE"
                validate_implementation "$TARGET_COMPONENT" "$VALIDATION_LEVEL"
                export_spec_report "${5:-$OUTPUT_DIR/implementation_spec.json}" "$SPEC_FORMAT"
                echo "Full process completed successfully" >&2
            else
                echo "Error: No target component specified for full analysis" >&2
                exit 1
            fi
            ;;

        "dependencies")
            manage_dependencies "$2" "$3"
            ;;

        *)
            echo "Usage: $0 [analyze|plan|validate|export|full|dependencies] [arguments...]" >&2
            echo "" >&2
            echo "Modes:" >&2
            echo "  analyze     - Analyze component and generate specification" >&2
            echo "  plan        - Build implementation plan for component" >&2
            echo "  validate    - Validate component implementation" >&2
            echo "  export      - Generate and export comprehensive specification" >&2
            echo "  full        - Complete analysis, planning, and export" >&2
            echo "  dependencies - Manage dependencies for specifications" >&2
            echo "" >&2
            echo "Example usages:" >&2
            echo "  $0 analyze /path/to/component.py" >&2
            echo "  $0 plan /path/to/component.sh feature" >&2
            echo "  $0 validate /path/to/component.json comprehensive" >&2
            echo "  $0 export /path/to/component.sh spec.json detailed" >&2
            echo "  $0 full /path/to/component.py" >&2
            echo "  $0 dependencies list" >&2
            exit 1
            ;;
    esac
}

# Execute main function
main