#!/usr/bin/env bash
# athena_reverse_engineer.sh - Reverse Engineer Anything skill wrapper for Athena
# Integrates morluto/rea (Rea v6.5.0) CLI capabilities into the Athena workflow system
set -o pipefail

BASE_DIR="/root"
BIN_DIR="$BASE_DIR/.local/bin"
source "$BIN_DIR/athena_env.sh" 2>/dev/null

DATA_DIR="${DATA_DIR:-/sdcard/Android/data/com/termux/files/athena_data}"
REA_DIR="$DATA_DIR/rea_analyses"
LOG_DIR="$DATA_DIR/workflow_logs"
EVIDENCE_DIR="$DATA_DIR/evidence"
REA_BIN="$(which rea 2>/dev/null || echo "$HOME/.local/bin/rea")"
REA_LOG_LEVEL="${REA_LOG_LEVEL:-info}"

mkdir -p "$REA_DIR" "$LOG_DIR" "$EVIDENCE_DIR" 2>/dev/null || {
  DATA_DIR="$HOME/.local/share/athena"
  REA_DIR="$DATA_DIR/rea_analyses"
  LOG_DIR="$DATA_DIR/workflow_logs"
  EVIDENCE_DIR="$DATA_DIR/evidence"
  mkdir -p "$REA_DIR" "$LOG_DIR" "$EVIDENCE_DIR" 2>/dev/null
}

now() { date +%s; }
now_iso() { date -Iseconds; }

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

check_rea() { command -v "$REA_BIN" >/dev/null 2>&1 || { echo "Error: rea CLI not found at $REA_BIN" >&2; return 1; }; }

# Select rea CLI command based on file type/category
select_rea_command() {
    local target="$1"
    local category="$2"

    if [[ "$category" != "auto" && -n "$category" ]]; then
        case "$category" in
            android)   echo "inspect-android-package" ;;
            binary)    echo "inspect-artifact" ;;
            javascript) echo "analyze-javascript-application" ;;
            sqlite)    echo "inspect-sqlite-database" ;;
            wasm)      echo "inspect-wasm-artifact" ;;
            *)         echo "analyze" ;;
        esac
    else
        # Auto-detect based on file extension and type
        local ext="${target##*.}"
        local mime_type
        mime_type=$(file --mime-type -b "$target" 2>/dev/null || echo "unknown")
        local is_dir=""
        [[ -d "$target" ]] && is_dir="yes"

        if [[ -n "$is_dir" ]]; then
            # Directories: check for JS app markers
            if [[ -f "$target/package.json" ]]; then
                echo "analyze-javascript-application"
            else
                echo "analyze"
            fi
        elif [[ "$mime_type" == "application/zip" || "$mime_type" == "application/x-apk" || "$mime_type" == "application/vnd.android"* ]]; then
            echo "inspect-android-package"
        elif [[ "$mime_type" == application/wasm ]]; then
            echo "inspect-wasm-artifact"
        elif [[ "$mime_type" == "application/x-sqlite3" ]]; then
            echo "inspect-sqlite-database"
        elif [[ "$mime_type" == "application/"* ]] && [[ "$mime_type" != "application/zip" && "$mime_type" != "application/json" && "$mime_type" != "application/javascript" && "$mime_type" != "application/x-executable" && "$mime_type" != "application/x-pie-executable" && "$mime_type" != "application/x-sharedlib" && "$mime_type" != "application/x-object" && "$mime_type" != "application/x-mach-binary" && "$mime_type" != "application/x-dosexec" ]]; then
            # Unknown binary type
            echo "inspect-artifact"
        else
            # Text files, scripts, JS, TS, JSON, unknown - use analyze or inspect-artifact
            case "$ext" in
                apk) echo "inspect-android-package" ;;
                wasm) echo "inspect-wasm-artifact" ;;
                sqlite|db) echo "inspect-sqlite-database" ;;
                js|jsx|mjs|cjs) if [[ -f "$target" ]]; then echo "inspect-artifact"; else echo "analyze-javascript-application"; fi ;;
                *) echo "analyze" ;;
            esac
        fi
    fi
}

cmd_inspect() {
    local target="${1:-}"
    local category="${2:-auto}"
    [[ -z "$target" ]] && { echo "Usage: $0 inspect <target> [category]"; echo "  category: auto|binary|android|javascript|sqlite|wasm"; return 1; }
    local validated_target; validated_target=$(validate_path "$target") || return 1
    [[ ! -e "$validated_target" ]] && { echo "ERROR: Target does not exist: $validated_target" >&2; return 1; }

    local session_id="re_inspect_$(now)"
    local log_file="$LOG_DIR/rea_inspect_${session_id}.log"
    echo "=== REA Inspection ==="
    echo "Target: $validated_target"
    echo "Category: $category"
    echo "Session: $session_id"

    local mime_type
    mime_type=$(file --mime-type -b "$validated_target" 2>/dev/null || echo "unknown")
    local is_dir=""
    [[ -d "$validated_target" ]] && is_dir=" (directory)"
    echo "Detected MIME: $mime_type$is_dir"

    local rea_cmd
    rea_cmd=$(select_rea_command "$validated_target" "$category")
    echo "REA Command: $rea_cmd"

    local result
    result=$(REA_LOG_LEVEL="$REA_LOG_LEVEL" "$REA_BIN" "$rea_cmd" "$validated_target" --format json 2>&1)
    local exit_code=$?

    if ! echo "$result" | tee "$log_file" 2>/dev/null; then
      echo "$result"
    fi

    if [[ $exit_code -ne 0 ]]; then
        echo "Inspection failed (exit $exit_code):" >&2
        echo "$result" >&2
        return $exit_code
    fi

    echo ""
    if [[ -f "$log_file" ]]; then
        echo "Log: $log_file"
    fi
}

cmd_analyze() {
    local target="$1"
    local mode="${2:-overview}"
    local analysis_id="anly_$(now)"
    local out_dir="$REA_DIR/$analysis_id"
    local log_file="$LOG_DIR/rea_${analysis_id}.log"
    mkdir -p "$out_dir"
    echo "=== REA Analysis ===" | tee "$log_file"
    echo "Target: $target" | tee -a "$log_file"
    echo "Mode: $mode" | tee -a "$log_file"
    echo "Analysis ID: $analysis_id" | tee -a "$log_file"
    echo "Started: $(now_iso)" | tee -a "$log_file"
    echo
    local validated_target; validated_target=$(validate_path "$target") || return 1
    REA_LOG_LEVEL="$REA_LOG_LEVEL" "$REA_BIN" analyze "$validated_target" --format json 2>&1 | tee -a "$log_file" 2>/dev/null | tee "$out_dir/analysis_output.json" 2>/dev/null || true
    # Note: --mode is not a rea CLI flag; mode is informational only
    local rc=$?
    python3 -c "
import json
result = {'analysis_id': '$analysis_id', 'target': '$target', 'mode': '$mode', 'output_dir': '$out_dir', 'status': 'completed' if $rc == 0 else 'failed', 'exit_code': $rc, 'started': '$(now_iso)', 'tool': 'rea v6.5.0'}
with open('$out_dir/result.json', 'w') as f:
    json.dump(result, f, indent=2)
"
    echo "Analysis $analysis_id complete (exit: $rc)" | tee -a "$log_file" 2>/dev/null || echo "Analysis $analysis_id complete (exit: $rc)"
    echo "$out_dir"
}

cmd_decompile()   { echo "=== REA Decompile ===" && REA_LOG_LEVEL="$REA_LOG_LEVEL" "$REA_BIN" decompile "$1" --decompiler "${2:-auto}" 2>&1; }
cmd_trace()       { echo "=== REA Trace ===" && REA_LOG_LEVEL="$REA_LOG_LEVEL" "$REA_BIN" trace "$1" --target "$2" 2>&1; }
cmd_search()      { echo "=== REA Search ===" && REA_LOG_LEVEL="$REA_LOG_LEVEL" "$REA_BIN" search "$1" --scope "$2" 2>&1; }
cmd_android_inspect() { echo "=== REA Android APK Inspection ===" && REA_LOG_LEVEL="$REA_LOG_LEVEL" "$REA_BIN" inspect-android-package "$1" --format json 2>&1; }
cmd_web_analyze() { echo "=== REA Web Bundle Analysis ===" && REA_LOG_LEVEL="$REA_LOG_LEVEL" "$REA_BIN" analyze-web-bundle "$1" --format json 2>&1; }
cmd_js_analyze()  { echo "=== REA JavaScript Application Analysis ===" && REA_LOG_LEVEL="$REA_LOG_LEVEL" "$REA_BIN" analyze-javascript-application "$1" --format json 2>&1; }
cmd_wasm_inspect() { echo "=== REA WASM Artifact Inspection ===" && REA_LOG_LEVEL="$REA_LOG_LEVEL" "$REA_BIN" inspect-wasm-artifact "$1" --format json 2>&1; }
cmd_sqlite_inspect() { echo "=== REA SQLite Database Inspection ===" && REA_LOG_LEVEL="$REA_LOG_LEVEL" "$REA_BIN" inspect-sqlite-database "$1" --format json 2>&1; }
cmd_capture_scenario() { echo "=== REA Capture Scenario ===" && REA_LOG_LEVEL="$REA_LOG_LEVEL" "$REA_BIN" capture-process "$1" --format json 2>&1; }
cmd_compare() { echo "=== REA Compare Evidence Bundles ===" && REA_LOG_LEVEL="$REA_LOG_LEVEL" "$REA_BIN" compare "$1" "$2" --format json 2>&1; }
cmd_list_tools() { echo "=== REA Capabilities ===" && "$REA_BIN" capabilities 2>&1; }
cmd_status() { echo "=== REA Integration Status ===" && echo "Binary: $REA_BIN" && "$REA_BIN" --version 2>&1; }
cmd_doctor() { echo "=== REA Doctor ===" && "$REA_BIN" doctor 2>&1; }

case "${1:-help}" in
    inspect)         cmd_inspect "$2" "$3" ;;
    analyze)         cmd_analyze "$2" "$3" ;;
    decompile)       cmd_decompile "$2" "$3" ;;
    trace)           cmd_trace "$2" "$3" ;;
    search)          cmd_search "$2" "$3" ;;
    android-inspect) cmd_android_inspect "$2" ;;
    web-analyze)     cmd_web_analyze "$2" ;;
    js-analyze)      cmd_js_analyze "$2" ;;
    wasm-inspect)    cmd_wasm_inspect "$2" ;;
    sqlite-inspect)  cmd_sqlite_inspect "$2" ;;
    capture-scenario) cmd_capture_scenario "$2" ;;
    compare)         cmd_compare "$2" "$3" ;;
    list-tools)      cmd_list_tools ;;
    status)          cmd_status ;;
    doctor)          cmd_doctor ;;
    help|--help)
        echo "Usage: $0 <command> [args]"
        echo ""
        echo "Commands:"
        echo "  inspect <target> [category]    Inspect a file or directory"
        echo "  analyze <target> [mode]        Analyze an app/binary/target"
        echo "  decompile <binary> [tool]      Decompile native binary"
        echo "  trace <symbol> <target>        Trace code flow"
        echo "  search <query> <source>       Search analyzed symbols"
        echo "  android-inspect <apk>          Analyze Android APK"
        echo "  web-analyze <url>              Analyze web bundle"
        echo "  js-analyze <dir>               Reconstruct JS/Electron app"
        echo "  wasm-inspect <file>            Inspect WASM artifact"
        echo "  sqlite-inspect <db>            Inspect SQLite database"
        echo "  capture-scenario <target>      Capture scenario as Evidence"
        echo "  compare <bundle_a> <bundle_b>  Compare Evidence bundles"
        echo "  list-tools                     List rea provider capabilities"
        echo "  status                         Show REA integration status"
        echo "  doctor                         Run setup diagnostics"
        ;;
    *)
        echo "Unknown command: $1" >&2
        echo "Run '$0 help' for usage." >&2
        exit 1
        ;;
esac
