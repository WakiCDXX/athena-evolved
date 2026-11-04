#!/usr/bin/bash
# athena_to_spec.sh - /to-spec skill: Specification Extraction and Formalization
# Extracts and formalizes specifications from code artifacts into structured reports.
# Based on Matt Pocock's /to-spec workflow skill.
#
# Usage:
#   athena_to_spec.sh auto <input_file> [spec_type] [output_format] [validation_level] [extraction_depth] [target_domain] [quality_threshold]
#   athena_to_spec.sh analyze <input_file> [spec_type] [output_format] [validation_level] [extraction_depth] [target_domain] [quality_threshold]
#   athena_to_spec.sh export <input_file> [spec_type] [output_format] [validation_level] [extraction_depth] [target_domain] [output_path]
#   athena_to_spec.sh validate <input_file> [validation_level] [output_format]
#   athena_to_spec.sh domain <input_file> [target_domain] [output_format]
#   athena_to_spec.sh full <input_file>

set -o pipefail

BASE_DIR="/root"
BIN_DIR="$BASE_DIR/.local/bin"
source "$BIN_DIR/athena_env.sh" 2>/dev/null

DATA_DIR="${DATA_DIR:-/sdcard/Android/data/com/termux/files/athena_data}"
SPEC_DIR="$DATA_DIR/specs"
LOG_DIR="$DATA_DIR/workflow_logs"
EVIDENCE_DIR="$DATA_DIR/evidence"

mkdir -p "$SPEC_DIR" "$LOG_DIR" "$EVIDENCE_DIR" 2>/dev/null || {
  DATA_DIR="$HOME/.local/share/athena"
  # Remove broken symlink if it exists — phantom filesystem issue
  [[ -L "$DATA_DIR" && ! -e "$DATA_DIR" ]] && rm -f "$DATA_DIR"
  SPEC_DIR="$DATA_DIR/specs"
  LOG_DIR="$DATA_DIR/workflow_logs"
  EVIDENCE_DIR="$DATA_DIR/evidence"
  mkdir -p "$SPEC_DIR" "$LOG_DIR" "$EVIDENCE_DIR" 2>/dev/null
}

now() { date +%s; }
now_iso() { date -Iseconds; }

# Security: validate paths stay within allowed directories
validate_path() {
    local path="$1"
    local base="$HOME"
    local abs_path
    if [[ "$path" = /* ]]; then abs_path="$path"; else abs_path=$(realpath -m "$base/$path" 2>/dev/null || echo "$base"); fi
    local canonical=$(realpath "$abs_path" 2>/dev/null || echo "$abs_path")
    local allowed_prefixes=( "$base" "$base/.local/share/athena_workflows" "$DATA_DIR" "$HOME" "/data/data/com/termux/files/usr" "/storage/emulated/0/" "/data/app/" "/data/local/tmp/" )
    local allowed=0
    for prefix in "${allowed_prefixes[@]}"; do [[ "$canonical" == "$prefix"* ]] && { allowed=1; break; }; done
    local blocked_prefixes=("/system/" "/sbin/" "/proc/" "/dev/" "/vendor/" "/etc/" "/boot/")
    for prefix in "${blocked_prefixes[@]}"; do [[ "$canonical" == "$prefix"* ]] && { echo "Security violation: Access to $prefix is blocked" >&2; return 1; }; done
    [[ $allowed -eq 0 ]] && { echo "Security violation: Path outside allowed directories" >&2; return 1; }
    echo "$canonical"
    return 0
}

# Validate specification structure
validate_structure() {
    local content="$1"
    local spec_type="$2"
    local validation_level="$3"

    echo "=== Specification Structure Validation ==="
    echo "Spec Type: $spec_type"
    echo "Validation Level: $validation_level"

    local structure_issues
    structure_issues=$(echo "$content" | grep -c "error\|Error\|ERROR\|invalid\|Invalid\|INVALID" 2>/dev/null)
    structure_issues=$(echo "$structure_issues" | head -1)
    structure_issues=${structure_issues:-0}

    if [[ "$structure_issues" -eq 0 ]]; then
        echo "  ✓ No structural issues detected"
        echo "  ✓ Specification structure is valid"
        return 0
    else
        echo "  ✗ Found $structure_issues structural issues"
        if [[ "$validation_level" == "strict" ]]; then
            echo "  ✗ Strict validation failed — issues must be resolved"
            return 1
        else
            echo "  ⚠ Non-strict validation — proceeding with warnings"
            return 0
        fi
    fi
}

# Validate specification documentation completeness
validate_documentation() {
    local content="$1"
    local validation_level="$2"

    echo "=== Specification Documentation Validation ==="
    echo "Validation Level: $validation_level"

    local doc_lines
    doc_lines=$(echo "$content" | grep -c "doc\|Doc\|DOC\|documentation\|Documentation\|DOCUMENTATION" 2>/dev/null)
    doc_lines=$(echo "$doc_lines" | head -1)
    doc_lines=${doc_lines:-0}

    local total_lines
    total_lines=$(echo "$content" | wc -l)
    local doc_ratio=$((doc_lines * 100 / (total_lines + 1)))

    if [[ "$doc_lines" -gt 0 ]]; then
        echo "  ✓ Documentation found: $doc_lines documentation references"
        echo "  ✓ Documentation ratio: $doc_ratio%"
        if [[ "$doc_ratio" -lt 10 ]] && [[ "$validation_level" == "strict" ]]; then
            echo "  ⚠ Low documentation ratio (${doc_ratio}%) — strict mode requires >=10%"
        fi
        return 0
    else
        echo "  ✗ No documentation detected"
        if [[ "$validation_level" == "strict" ]]; then
            echo "  ✗ Strict validation failed — documentation required"
            return 1
        else
            echo "  ⚠ Proceeding without documentation"
            return 0
        fi
    fi
}

# Analyze specification from input file
analyze_spec() {
    local input_file="$1"
    local spec_type="${2:-technical}"
    local output_format="${3:-json}"
    local validation_level="${4:-strict}"
    local extraction_depth="${5:-deep}"
    local target_domain="${6:-general}"
    local quality_threshold="${7:-85}"

    local spec_id="spec_$(now)"
    local out_dir="$SPEC_DIR/$spec_id"
    mkdir -p "$out_dir"

    echo "=== Athena To-Spec: Analyze Specification ==="
    echo "Spec ID: $spec_id"
    echo "Input: $input_file"
    echo "Spec Type: $spec_type"
    echo "Output Format: $output_format"
    echo "Validation Level: $validation_level"
    echo "Extraction Depth: $extraction_depth"
    echo "Target Domain: $target_domain"
    echo "Quality Threshold: ${quality_threshold}%"
    echo "Output: $out_dir"
    echo "Started: $(now_iso)"
    echo

    local validated_input
    validated_input=$(validate_path "$input_file") || return 1
    [[ ! -e "$validated_input" ]] && { echo "ERROR: Input file does not exist: $validated_input" >&2; return 1; }

    local content
    content=$(cat "$validated_input" 2>/dev/null) || { echo "ERROR: Cannot read input file" >&2; return 1; }

    local file_type
    file_type=$(file --mime-type -b "$validated_input" 2>/dev/null || echo "unknown")
    echo "File Type: $file_type"
    echo

    local filename
    filename=$(basename "$validated_input")
    local ext="${filename##*.}"
    local language="unknown"
    case "$ext" in
        py)  language="python" ;;
        sh)  language="bash" ;;
        js|jsx|mjs|cjs) language="javascript" ;;
        ts|tsx) language="typescript" ;;
        json) language="json" ;;
        md)  language="markdown" ;;
        yaml|yml) language="yaml" ;;
        *)   language="text" ;;
    esac

    echo "Language: $language"
    echo

    echo "--- Structure Validation ---"
    if validate_structure "$content" "$spec_type" "$validation_level"; then
        echo "Structure validation: PASSED"
    else
        echo "Structure validation: FAILED"
    fi
    echo

    echo "--- Documentation Validation ---"
    if validate_documentation "$content" "$validation_level"; then
        echo "Documentation validation: PASSED"
    else
        echo "Documentation validation: FAILED"
    fi
    echo

    local total_lines
    total_lines=$(echo "$content" | wc -l)
    local total_words
    total_words=$(echo "$content" | wc -w)
    local function_count
    function_count=$(echo "$content" | grep -c "function\|def " 2>/dev/null)
    function_count=$(echo "$function_count" | head -1)
    function_count=${function_count:-0}
    local class_count
    class_count=$(echo "$content" | grep -c "class " 2>/dev/null)
    class_count=$(echo "$class_count" | head -1)
    class_count=${class_count:-0}
    local comment_count
    comment_count=$(echo "$content" | grep -c "#\|//\|#\*\|/\*" 2>/dev/null)
    comment_count=$(echo "$comment_count" | head -1)
    comment_count=${comment_count:-0}

    echo "--- Specification Metrics ---"
    echo "Total Lines: $total_lines"
    echo "Total Words: $total_words"
    echo "Functions: $function_count"
    echo "Classes: $class_count"
    echo "Comments: $comment_count"
    echo

    local report_file="$out_dir/report.$ext"
    local result_file="$out_dir/result.json"

    if [[ "$output_format" == "json" ]]; then
        python3 -c "
import json

report = {
    'spec_id': '$spec_id',
    'input_file': '$validated_input',
    'filename': '$filename',
    'spec_type': '$spec_type',
    'output_format': 'json',
    'validation_level': '$validation_level',
    'extraction_depth': '$extraction_depth',
    'target_domain': '$target_domain',
    'quality_threshold': $quality_threshold,
    'language': '$language',
    'file_type': '$file_type',
    'metrics': {
        'total_lines': $total_lines,
        'total_words': $total_words,
        'functions': $function_count,
        'classes': $class_count,
        'comments': $comment_count
    },
    'started': '$(now_iso)',
    'tool': 'athena_to_spec.sh',
    'status': 'completed'
}
with open('$result_file', 'w') as f:
    json.dump(report, f, indent=2)
print(json.dumps(report, indent=2))
" 2>/dev/null || echo "{\"spec_id\": \"$spec_id\", \"status\": \"completed\"}" > "$result_file"
    elif [[ "$output_format" == "detailed" ]]; then
        cat > "$out_dir/report.md" <<EOF
# Specification Report

**Spec ID:** $spec_id
**Input:** $validated_input
**Type:** $spec_type
**Validation:** $validation_level
**Depth:** $extraction_depth
**Domain:** $target_domain

## Summary
- **Language:** $language
- **File Type:** $file_type
- **Total Lines:** $total_lines
- **Functions:** $function_count
- **Classes:** $class_count
- **Comments:** $comment_count
EOF
    else
        echo "$content" > "$out_dir/report.txt"
    fi

    echo "Report saved: $out_dir"
    echo "$out_dir"
}

# Export specification to a specific output path
export_spec() {
    local input_file="$1"
    local spec_type="${2:-technical}"
    local output_format="${3:-json}"
    local validation_level="${4:-strict}"
    local extraction_depth="${5:-deep}"
    local target_domain="${6:-general}"
    local output_path="${7:-$HOME/.local/share/athena_specs/specification_report.json}"

    local spec_id="spec_export_$(now)"
    local tmp_dir="$SPEC_DIR/$spec_id"
    mkdir -p "$tmp_dir"

    echo "=== Athena To-Spec: Export Specification ==="
    echo "Spec ID: $spec_id"
    echo "Input: $input_file"
    echo "Output Path: $output_path"
    echo

    local result_dir
    result_dir=$(analyze_spec "$input_file" "$spec_type" "$output_format" "$validation_level" "$extraction_depth" "$target_domain" | tail -1) || return 1

    mkdir -p "$result_dir" 2>/dev/null
    local result_file="$result_dir/result.json"
    if [[ -f "$result_file" ]]; then
        local out_dir
        out_dir=$(dirname "$output_path" 2>/dev/null || echo "$HOME/.local/share/athena_specs")
        mkdir -p "$out_dir" 2>/dev/null
        cp "$result_file" "$output_path"
        echo "Specification exported to: $output_path"
    else
        echo "{\"spec_id\": \"$spec_id\", \"input_file\": \"$input_file\", \"status\": \"exported\"}" > "$output_path"
        echo "Specification exported to: $output_path (minimal)"
    fi
    echo "$output_path"
}

cmd_auto() {
    local input_file="$1"
    local spec_type="${2:-technical}"
    local output_format="${3:-json}"
    local validation_level="${4:-strict}"
    local extraction_depth="${5:-deep}"
    local target_domain="${6:-general}"
    local quality_threshold="${7:-85}"

    analyze_spec "$input_file" "$spec_type" "$output_format" "$validation_level" "$extraction_depth" "$target_domain" "$quality_threshold"
}

cmd_analyze() {
    local input_file="$1"
    local spec_type="${2:-technical}"
    local output_format="${3:-json}"
    local validation_level="${4:-strict}"
    local extraction_depth="${5:-deep}"
    local target_domain="${6:-general}"
    local quality_threshold="${7:-85}"

    analyze_spec "$input_file" "$spec_type" "$output_format" "$validation_level" "$extraction_depth" "$target_domain" "$quality_threshold"
}

cmd_export() {
    local input_file="$1"
    local spec_type="${2:-technical}"
    local output_format="${3:-json}"
    local validation_level="${4:-strict}"
    local extraction_depth="${5:-deep}"
    local target_domain="${6:-general}"
    local output_path="${7:-$HOME/.local/share/athena_specs/specification_report.json}"

    export_spec "$input_file" "$spec_type" "$output_format" "$validation_level" "$extraction_depth" "$target_domain" "$output_path"
}

cmd_validate() {
    local input_file="$1"
    local validation_level="${2:-strict}"
    local output_format="${3:-json}"

    echo "=== Athena To-Spec: Validate Specification ==="
    echo "Input: $input_file"
    echo "Validation Level: $validation_level"

    local validated_input
    validated_input=$(validate_path "$input_file") || return 1
    [[ ! -e "$validated_input" ]] && { echo "ERROR: File does not exist: $validated_input" >&2; return 1; }

    local content
    content=$(cat "$validated_input" 2>/dev/null) || { echo "ERROR: Cannot read file" >&2; return 1; }

    echo
    echo "--- Structure Validation ---"
    validate_structure "$content" "technical" "$validation_level"
    local struct_rc=$?

    echo
    echo "--- Documentation Validation ---"
    validate_documentation "$content" "$validation_level"
    local doc_rc=$?

    echo
    if [[ $struct_rc -eq 0 ]] && [[ $doc_rc -eq 0 ]]; then
        echo "Overall: PASSED"
        return 0
    else
        echo "Overall: FAILED (structure=$struct_rc, doc=$doc_rc)"
        return 1
    fi
}

cmd_domain() {
    local input_file="$1"
    local target_domain="${2:-technical}"
    local output_format="${3:-json}"

    echo "=== Athena To-Spec: Domain Analysis ==="
    echo "Input: $input_file"
    echo "Target Domain: $target_domain"

    local validated_input
    validated_input=$(validate_path "$input_file") || return 1
    [[ ! -e "$validated_input" ]] && { echo "ERROR: File does not exist: $validated_input" >&2; return 1; }

    local content
    content=$(cat "$validated_input" 2>/dev/null) || { echo "ERROR: Cannot read file" >&2; return 1; }

    local domain_keywords=""
    case "$target_domain" in
        business) domain_keywords="business requirement stakeholder customer value ROI revenue" ;;
        technical) domain_keywords="technical architecture implementation design API endpoint interface" ;;
        functional) domain_keywords="function feature capability behavior use case input output process" ;;
        *) domain_keywords="$target_domain" ;;
    esac

    local domain_matches=0
    for kw in $domain_keywords; do
        local matches
        matches=$(echo "$content" | grep -ci "$kw" 2>/dev/null)
        matches=$(echo "$matches" | head -1)
        domain_matches=$((domain_matches + ${matches:-0}))
    done

    echo "Domain keyword matches: $domain_matches"
    echo "Domain focus: $target_domain"
    echo "Domain analysis complete."
}

cmd_full() {
    local input_file="$1"

    echo "=== Athena To-Spec: Full Specification Extraction ==="
    local spec_id="spec_full_$(now)"
    local out_dir="$SPEC_DIR/$spec_id"
    mkdir -p "$out_dir"

    echo "Spec ID: $spec_id"
    echo "Input: $input_file"
    echo

    echo "--- Step 1: Auto Extraction ---"
    cmd_auto "$input_file" "technical" "json" "strict" "deep" "general" 85

    echo
    echo "--- Step 2: Analysis ---"
    cmd_analyze "$input_file" "technical" "detailed" "standard" "deep" "technical" 80

    echo
    echo "--- Step 3: Domain Analysis ---"
    cmd_domain "$input_file" "technical" "json"

    echo
    echo "Full specification extraction complete."
    echo "Output: $out_dir"
}

cmd_status() {
    echo "=== Athena To-Spec Integration Status ==="
    echo "Script: $BIN_DIR/athena_to_spec.sh"
    echo "Spec Dir: $SPEC_DIR"
    echo "Log Dir: $LOG_DIR"
    echo "Evidence Dir: $EVIDENCE_DIR"
    echo "Available modes: auto, analyze, export, validate, domain, full"
}

case "${1:-help}" in
    auto)       cmd_auto "$2" "$3" "$4" "$5" "$6" "$7" "$8" ;;
    analyze)    cmd_analyze "$2" "$3" "$4" "$5" "$6" "$7" "$8" ;;
    export)     cmd_export "$2" "$3" "$4" "$5" "$6" "$7" "$8" ;;
    validate)   cmd_validate "$2" "$3" "$4" ;;
    domain)     cmd_domain "$2" "$3" "$4" ;;
    full)       cmd_full "$2" ;;
    status)     cmd_status ;;
    help|--help)
        echo "Usage: $0 <mode> <input_file> [args...]"
        echo ""
        echo "Modes:"
        echo "  auto <input_file> [spec_type] [format] [level] [depth] [domain] [threshold]"
        echo "    Auto-extract specification from input source"
        echo "  analyze <input_file> [spec_type] [format] [level] [depth] [domain] [threshold]"
        echo "    Analyze and validate specification"
        echo "  export <input_file> [spec_type] [format] [level] [depth] [domain] <output_path>"
        echo "    Export complete specification report"
        echo "  validate <input_file> [level] [format]"
        echo "    Validate specification content"
        echo "  domain <input_file> [target_domain] [format]"
        echo "    Analyze specification domain"
        echo "  full <input_file>"
        echo "    Complete specification extraction process"
        ;;
    *)
        echo "Unknown command: $1" >&2
        echo "Run '$0 help' for usage." >&2
        exit 1
        ;;
esac
