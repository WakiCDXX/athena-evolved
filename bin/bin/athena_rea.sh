#!/usr/bin/bash
# athena_rea.sh - Reverse Engineer Anything skill wrapper for Athena
# Integrates morluto/rea (Rea v6.5.0) CLI capabilities into the Athena workflow system
#
# Rea provides: analyze, inspect, decompile, trace, search, capture, compare,
#   android APK analysis, web bundle analysis, JavaScript application analysis,
#   native binary diagnostics, WASM analysis, EVM analysis, SQLite inspection,
#   ADB integration, signal recording, and Evidence-backed reconstruction.
#
# Usage:
#   athena_rea.sh analyze <target> [mode]           → Analyze an app/binary/target
#   athena_rea.sh inspect <artifact> [format]      → Inspect artifact structure
#   athena_rea.sh decompile <binary> [tool]         → Decompile native binary
#   athena_rea.sh trace <symbol> <target>          → Trace code flow through references
#   athena_rea.sh search <query> <source>          → Search analyzed symbols/strings
#   athena_rea.sh android-inspect <apk>            → Analyze Android APK
#   athena_rea.sh web-analyze <url>                → Analyze web bundle from URL
#   athena_rea.sh js-analyze <dir>                 → Statically reconstruct JS/Electron app
#   athena_rea.sh wasm-inspect <file>              → Inspect WASM artifact
#   athena_rea.sh sqlite-inspect <db>              → Inspect SQLite database
#   athena_rea.sh capture-scenario <target>        → Capture one scenario as Evidence
#   athena_rea.sh compare <bundle_a> <bundle_b>   → Compare two Evidence bundles
#   athena_rea.sh capabilities                     → List rea provider capabilities
#   athena_rea.sh doctor                           → Run setup diagnostics

set -o pipefail

BASE_DIR="/root"
BIN_DIR="$BASE_DIR/.local/bin"
source "$BIN_DIR/athena_env.sh" 2>/dev/null

DATA_DIR="${DATA_DIR:-/sdcard/Android/data/com.termux/files/athena_data}"
REA_DIR="$DATA_DIR/rea_analyses"
LOG_DIR="$DATA_DIR/workflow_logs"
REA_BIN="$(which rea 2>/dev/null || echo rea)"

mkdir -p "$REA_DIR" "$LOG_DIR"

now() { date +%s; }
now_iso() { date -Iseconds; }

# Security: validate paths stay within allowed directories for reverse engineering
# We allow analysis of files under: home dir, storage/shared, data/app, data/data/com.termux
# while blocking sensitive system paths like /system, /sbin, /proc, /dev, etc.
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

    # Allowed target prefixes for reverse engineering
    local allowed_prefixes=(
        "$base"
        "$base/.local/share/athena_workflows"
        "/opt/athena/state"
        "/root"
        "/data/data/com/termux/files/usr"
        "/storage/emulated/0/"
        "$HOME"
        "/sdcard/"
        "/data/app/"
        "/data/misc/"
        "/data/local/tmp/"
    )

    local allowed=0
    for prefix in "${allowed_prefixes[@]}"; do
        if [[ "$canonical" == "$prefix"* ]]; then
            allowed=1
            break
        fi
    done

    # Block dangerous system paths
    local blocked_prefixes=(
        "/system/"
        "/sbin/"
        "/proc/"
        "/dev/"
        "/vendor/"
        "/etc/"
        "/boot/"
    )
    for prefix in "${blocked_prefixes[@]}"; do
        if [[ "$canonical" == "$prefix"* ]]; then
            echo "Security violation: Access to $prefix is blocked" >&2
            return 1
        fi
    done

    if [[ $allowed -eq 0 ]]; then
        echo "Security violation: Path outside allowed directories" >&2
        return 1
    fi

    echo "$canonical"
}

# Check that rea CLI is available
check_rea() {
    if ! command -v "$REA_BIN" >/dev/null 2>&1; then
        echo "Error: rea CLI not found at $REA_BIN" >&2
        echo "Install with: npm install -g rea-agents" >&2
        return 1
    fi
    return 0
}

cmd_analyze() {
    local target="$1"
    local mode="${2:-overview}"
    local analysis_id="anly_$(now)"
    local out_dir="$REA_DIR/$analysis_id"
    local log_file="$LOG_DIR/rea_${analysis_id}.log"

    mkdir -p "$out_dir"

    echo "=== Athena Rea: Analyze ===" | tee "$log_file"
    echo "Target: $target" | tee -a "$log_file"
    echo "Mode: $mode" | tee -a "$log_file"
    echo "Analysis ID: $analysis_id" | tee -a "$log_file"
    echo "Output: $out_dir" | tee -a "$log_file"
    echo "Started: $(now_iso)" | tee -a "$log_file"
    echo

    "$REA_BIN" analyze "$target" 2>&1 | tee -a "$log_file" | tee "$out_dir/analysis_output.json"
    # Note: rea analyze does NOT support --mode flag; omitted intentionally
    local rc=$?

    # Write result metadata
    python3 -c "
import json
result = {
    'analysis_id': '$analysis_id',
    'target': '$target',
    'mode': '$mode',
    'output_dir': '$out_dir',
    'status': 'completed' if $rc == 0 else 'failed',
    'exit_code': $rc,
    'started': '$(now_iso)',
    'tool': 'rea v6.5.0'
}
with open('$out_dir/result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

    echo "Analysis $analysis_id complete (exit: $rc)" | tee -a "$log_file"
    echo "$out_dir"
}

cmd_inspect() {
    local artifact="$1"
    local format="${2:-json}"

    check_rea || return 1
    echo "=== Athena Rea: Inspect Artifact ==="
    echo "Artifact: $artifact"
    echo "Format: $format"

    "$REA_BIN" inspect-artifact "$artifact" --format "$format" 2>&1
}

cmd_decompile() {
    local binary="$1"
    local tool="${2:-auto}"

    check_rea || return 1
    echo "=== Athena Rea: Decompile ==="
    echo "Binary: $binary"
    echo "Tool: $tool"

    "$REA_BIN" decompile "$binary" --decompiler "$tool" 2>&1
}

cmd_trace() {
    local symbol="$1"
    local target="$2"

    check_rea || return 1
    echo "=== Athena Rea: Trace ==="
    echo "Symbol: $symbol"
    echo "Target: $target"

    "$REA_BIN" trace "$symbol" --target "$target" 2>&1
}

cmd_search() {
    local query="$1"
    local source="$2"

    check_rea || return 1
    echo "=== Athena Rea: Search ==="
    echo "Query: $query"
    echo "Source: $source"

    "$REA_BIN" search "$query" --scope "$source" 2>&1
}

cmd_android_inspect() {
    local apk="$1"

    check_rea || return 1
    echo "=== Athena Rea: Android APK Inspection ==="
    echo "APK: $apk"

    "$REA_BIN" inspect-android-package "$apk" 2>&1
}

cmd_web_analyze() {
    local url="$1"

    check_rea || return 1
    echo "=== Athena Rea: Web Bundle Analysis ==="
    echo "URL: $url"

    "$REA_BIN" analyze-web-bundle "$url" 2>&1
}

cmd_js_analyze() {
    local dir="$1"

    check_rea || return 1
    echo "=== Athena Rea: JavaScript Application Analysis ==="
    echo "Directory: $dir"

    "$REA_BIN" analyze-javascript-application "$dir" 2>&1
}

cmd_wasm_inspect() {
    local file="$1"

    check_rea || return 1
    echo "=== Athena Rea: WASM Artifact Inspection ==="
    echo "File: $file"

    "$REA_BIN" inspect-wasm-artifact "$file" 2>&1
}

cmd_sqlite_inspect() {
    local db="$1"

    check_rea || return 1
    echo "=== Athena Rea: SQLite Database Inspection ==="
    echo "Database: $db"

    "$REA_BIN" inspect-sqlite-database "$db" 2>&1
}

cmd_capture_scenario() {
    local target="$1"

    check_rea || return 1
    echo "=== Athena Rea: Capture Scenario ==="
    echo "Target: $target"

    "$REA_BIN" capture-process "$target" 2>&1
}

cmd_compare() {
    local bundle_a="$1"
    local bundle_b="$2"

    check_rea || return 1
    echo "=== Athena Rea: Compare Evidence Bundles ==="
    echo "Bundle A: $bundle_a"
    echo "Bundle B: $bundle_b"

    "$REA_BIN" compare "$bundle_a" "$bundle_b" 2>&1
}

cmd_capabilities() {
    check_rea || return 1
    echo "=== Athena Rea: Capabilities ==="
    "$REA_BIN" capabilities 2>&1
}

cmd_doctor() {
    check_rea || return 1
    echo "=== Athena Rea: Doctor Diagnostics ==="
    "$REA_BIN" doctor 2>&1
}

# Main entry point
case "${1:-help}" in
    analyze)        cmd_analyze "$2" "$3" ;;
    inspect)        cmd_inspect "$2" "$3" ;;
    decompile)      cmd_decompile "$2" "$3" ;;
    trace)          cmd_trace "$2" "$3" ;;
    search)         cmd_search "$2" "$3" ;;
    android-inspect) cmd_android_inspect "$2" ;;
    web-analyze)    cmd_web_analyze "$2" ;;
    js-analyze)     cmd_js_analyze "$2" ;;
    wasm-inspect)   cmd_wasm_inspect "$2" ;;
    sqlite-inspect) cmd_sqlite_inspect "$2" ;;
    capture-scenario) cmd_capture_scenario "$2" ;;
    compare)        cmd_compare "$2" "$3" ;;
    capabilities)   cmd_capabilities ;;
    doctor)         cmd_doctor ;;
    help|--help)
        echo "Usage: $0 <command> [args]"
        echo ""
        echo "Commands:"
        echo "  analyze <target> [mode]         Analyze an app/binary/target"
        echo "  inspect <artifact> [format]     Inspect artifact structure"
        echo "  decompile <binary> [tool]       Decompile native binary"
        echo "  trace <symbol> <target>         Trace code flow"
        echo "  search <query> <source>         Search analyzed symbols/strings"
        echo "  android-inspect <apk>           Analyze Android APK"
        echo "  web-analyze <url>               Analyze web bundle from URL"
        echo "  js-analyze <dir>                Reconstruct JS/Electron app"
        echo "  wasm-inspect <file>             Inspect WASM artifact"
        echo "  sqlite-inspect <db>             Inspect SQLite database"
        echo "  capture-scenario <target>       Capture one scenario as Evidence"
        echo "  compare <bundle_a> <bundle_b>   Compare two Evidence bundles"
        echo "  capabilities                    List rea provider capabilities"
        echo "  doctor                          Run setup diagnostics"
        ;;
    *)
        echo "Unknown command: $1" >&2
        echo "Run '$0 help' for usage." >&2
        exit 1
        ;;
esac
