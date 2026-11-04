#!/bin/bash
# athena_wayfinder.sh - Code navigation and discovery for Athena
# Implements Matt Pocock's /wayfinder skill with Athena-specific enhancements

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

# Safe pattern validation for search patterns
safe_pattern() {
    local pattern="$1"

    # Remove potentially dangerous characters
    pattern=${pattern//\;/ }
    pattern=${pattern//\&/ }
    pattern=${pattern//\|/ }
    pattern=${pattern//\&/ }
    pattern=${pattern//\`/ }
    pattern=${pattern//\"/ }
    pattern=${pattern//\'/ }

    # Limit pattern length
    if [[ ${#pattern} -gt 100 ]]; then
        echo "Security warning: Pattern too long, truncating" >&2
        pattern="${pattern:0:100}"
    fi

    # Escape regex special characters for safety
    local escaped_pattern=""
    for (( i=0; i<${#pattern}; i++ )); do
        local char="${pattern:$i:1}"
        # Check if character is alphanumeric or underscore
        if [[ "$char" =~ ^[a-zA-Z0-9_]$ ]]; then
            escaped_pattern+="$char"
        else
            escaped_pattern+="\\\\$char"
        fi
    done

    echo "$escaped_pattern"
}

# Rate limiting - track search frequency
RATE_LIMIT_WINDOW=300  # 5 minutes
RATE_LIMIT_COUNT=5
RATE_LIMIT_START_TIME=0
RATE_LIMIT_COUNTER=0

check_rate_limit() {
    local current_time=$(date +%s)

    if [[ $RATE_LIMIT_START_TIME -eq 0 ]]; then
        RATE_LIMIT_START_TIME=$current_time
        RATE_LIMIT_COUNTER=1
        return 0
    fi

    # Reset window if needed
    if [[ $((current_time - RATE_LIMIT_START_TIME)) -ge $RATE_LIMIT_WINDOW ]]; then
        RATE_LIMIT_START_TIME=$current_time
        RATE_LIMIT_COUNTER=1
        return 0
    fi

    RATE_LIMIT_COUNTER=$((RATE_LIMIT_COUNTER + 1))
    if [[ $RATE_LIMIT_COUNTER -gt $RATE_LIMIT_COUNT ]]; then
        echo "Rate limit exceeded. Please wait ${RATE_LIMIT_WINDOW} seconds before next search." >&2
        return 1
    fi
    return 0
}

# Safe command execution with timeouts
safe_grep() {
    local pattern="$1"
    local file_path="$2"

    # Validate inputs
    if [[ -z "$pattern" || -z "$file_path" ]]; then
        return 1
    fi

    # Check file exists and is readable
    if [[ ! -f "$file_path" ]] || [[ ! -r "$file_path" ]]; then
        return 1
    fi

    # Use timeout for grep execution
    timeout 10 grep -q "$pattern" "$file_path" 2>/dev/null
    return $?
}

# Safe export with path validation
safe_export_results() {
    local output_file="$1"
    local format="$2"

    # Validate output file path
    local validated_output_file
    validated_output_file=$(validate_and_sanitize_path "$output_file" 2>/dev/null)
    if [[ $? -ne 0 ]]; then
        echo "Security violation: Invalid output file path" >&2
        return 1
    fi

    # Ensure parent directory is writable
    local parent_dir="$(dirname "$validated_output_file")"
    if [[ ! -d "$parent_dir" ]] || [[ ! -w "$parent_dir" ]]; then
        echo "Security violation: Output directory not writable" >&2
        return 1
    fi

    # Create export with safe file writing
    if ! tail -n +1 ">" "$validated_output_file" 2>/dev/null; then
        echo "Error: Cannot write to output file $validated_output_file" >&2
        return 1
    fi

    echo "Results exported to: $validated_output_file" >&2
    return 0
}

# Initialize Athena-specific variables with validation
WAYFINDER_MODE="${1:-search}"
TARGET="${2:-}"
SEARCH_DEPTH="${3:-deep}"
OUTPUT_FORMAT="${4:-structured}"
OUTPUT_FILE="${5:-wayfinder_results.json}"

# Validate mode
if [[ ! "$WAYFINDER_MODE" =~ ^(search|explore|relationships|export|full|validate)$ ]]; then
    echo "Error: Invalid mode. Use: search, explore, relationships, export, full, or validate" >&2
    exit 1
fi

# Validate search depth
if [[ ! "$SEARCH_DEPTH" =~ ^(shallow|deep)$ ]]; then
    echo "Error: Invalid search depth. Use: shallow or deep" >&2
    exit 1
fi

# Validate output format
if [[ ! "$OUTPUT_FORMAT" =~ ^(structured|simple|csv)$ ]]; then
    echo "Error: Invalid output format. Use: structured, simple, or csv" >&2
    exit 1
fi

# Set safe defaults
EXCLUDE_PATTERNS="*.pyc,*.log,*.tmp,build/,dist/,*.swp,.git/"

# Performance optimization with safe limits
MAX_RESULTS=100
TIMEOUT_SECONDS=30

# Initialize result tracking with size limits
SEARCH_RESULTS=()
EXPLORATION_TREE=()
RELATIONSHIP_MAP=()

# Parse exclude patterns into array
IFS=',' read -ra EXCLUDE_ARRAY <<< "$EXCLUDE_PATTERNS"

# Validate exclude patterns
for pattern in "${EXCLUDE_ARRAY[@]}"; do
    # Remove shell metacharacters
    pattern=${pattern//\; }
    pattern=${pattern//\& }
    pattern=${pattern//\| }
    pattern=${pattern//\& }
    pattern=${pattern//\` }
    pattern=${pattern//\" }
    pattern=${pattern//\' }
    # Ensure pattern doesn't contain dangerous commands
    if [[ "$pattern" == *"*"* ]] || [[ "$pattern" == *"||"* ]] || [[ "$pattern" == *";"* ]]; then
        echo "Security warning: Suspicious exclude pattern detected: $pattern" >&2
    fi
done

# Parse exclude patterns into array
IFS=',' read -ra EXCLUDE_ARRAY <<< "$EXCLUDE_PATTERNS"

# Function to check if file should be excluded with security validation
is_excluded() {
    local file_path="$1"

    # Validate file path
    if [[ -z "$file_path" ]]; then
        return 1
    fi

    # Prevent path traversal attempts
    if [[ "$file_path" == *".."* ]]; then
        echo "Security warning: Potential path traversal detected: $file_path" >&2
        return 0
    fi

    # Check against safe exclude patterns
    for pattern in "${EXCLUDE_ARRAY[@]}"; do
        if [[ -z "$pattern" ]]; then
            continue
        fi

        # Sanitize pattern before comparison
        local safe_pattern="${pattern//\;* /}"
        safe_pattern="${safe_pattern//\&* /}"

        if [[ "$file_path" == *"$safe_pattern"* ]]; then
            return 0
        fi
    done
    return 1
}

# Function to extract code structure with security validation
extract_code_structure() {
    local file_path="$1"
    local structure=""

    # Validate file path before processing
    if [[ -z "$file_path" ]]; then
        echo "Security error: Empty file path" >&2
        return 1
    fi

    # Safe path validation
    local validated_path=""
    if validated_path=$(validate_and_sanitize_path "$file_path" 2>/dev/null); then
        file_path="$validated_path"
    else
        echo "Security violation: Invalid file path: $file_path" >&2
        return 1
    fi

    if [[ ! -f "$file_path" ]] || [[ ! -r "$file_path" ]]; then
        return 1
    fi

    # Set file-specific limits based on size
    local file_size=0
    if file_size=$(du -b "$file_path" | cut -f1); then
        # Skip files larger than 10MB for safety
        if [[ $file_size -gt 10485760 ]]; then
            echo "Security warning: File too large for analysis: $file_path" >&2
            return 1
        fi
    fi

    if [[ "$file_path" == *.py ]]; then
        # Python structure extraction with safe parsing
        local functions_only=true
        structure+="functions:" && safe_grep -q "def [a-zA-Z_][a-zA-Z0-9_]*(" "$file_path" 2>/dev/null | sed 's/def //g' | sed 's/(//' | tr '\n' ',' | sed 's/,$//' && structure+=", "
        structure+="classes:" && safe_grep -q "class [a-zA-Z_][a-zA-Z0-9_]*(" "$file_path" 2>/dev/null | sed 's/class //g' | sed 's/(//' | tr '\n' ',' | sed 's/,$//' && structure+=", "
        structure+="imports:" && safe_grep -q "^\s*import [a-zA-Z0-9_.]*" "$file_path" 2>/dev/null | head -5 | tr '\n' ',' | sed 's/,$//' && structure+=", "
        structure+="lines:" && wc -l < "$file_path" 2>/dev/null | tr -d ' ' && structure+=", "
        structure+="size:" && du -h "$file_path" | cut -f1

    elif [[ "$file_path" == *.sh ]]; then
        # Shell script structure with validation
        structure+="functions:" && grep -o "^[a-zA-Z_][a-zA-Z0-9_]*()" "$file_path" 2>/dev/null | tr '\n' ',' | sed 's/,$//' && structure+=", "
        structure+="variables:" && grep -o '\$[a-zA-Z_][a-zA-Z0-9_]*' "$file_path" 2>/dev/null | sort -u | tr '\n' ',' | sed 's/,$//' && structure+=", "
        structure+="commands:" && grep -o "^[a-zA-Z0-9_]*\s*\(.*\)" "$file_path" 2>/dev/null | head -5 | tr '\n' ',' | sed 's/,$//' && structure+=", "
        structure+="lines:" && wc -l < "$file_path" | tr -d ' ' && structure+=", "
        structure+="size:" && du -h "$file_path" | cut -f1

    elif [[ "$file_path" == *.md ]]; then
        # Markdown document structure with validation
        structure+="headings:" && grep -o '^#+ .*\s*' "$file_path" 2>/dev/null | head -10 | tr '\n' ',' | sed 's/,$//' && structure+=", "
        structure+="links:" && grep -o '\[.*\](.*\))' "$file_path" 2>/dev/null | head -5 | tr '\n' ',' | sed 's/,$//' && structure+=", "
        structure+="tables:" && grep -c '|' "$file_path" 2>/dev/null && structure+=", "
        structure+="lines:" && wc -l < "$file_path" | tr -d ' ' && structure+=", "
        structure+="size:" && du -h "$file_path" | cut -f1

    else
        # Generic file analysis with validation
        structure+="type:" && file --mime-type -b "$file_path" 2>/dev/null | cut -d'/' -f1 && structure+=", "
        structure+="size:" && du -h "$file_path" | cut -f1 && structure+=", "
        structure+="lines:" && wc -l < "$file_path" 2>/dev/null | tr -d ' ' || echo "0" && structure+=", "
        structure+="modified:" && date -r "$file_path" "+%Y-%m-%d" 2>/dev/null || echo "unknown"
    fi

    echo "$structure"
}

# Function to search for target in files with security validation
perform_search() {
    local target_pattern="$1"
    local current_dir="$2"

    # Input validation
    if [[ -z "$target_pattern" ]]; then
        echo "Error: Target pattern cannot be empty" >&2
        return 1
    fi

    if [[ -z "$current_dir" ]]; then
        echo "Error: Current directory cannot be empty" >&2
        return 1
    fi

    # Validate inputs for security
    local sanitized_pattern
    sanitized_pattern=$(safe_pattern "$target_pattern")
    local validated_dir
    validated_dir=$(validate_and_sanitize_path "$current_dir" 2>/dev/null)

    if [[ $? -ne 0 ]] || [[ -z "$validated_dir" ]]; then
        echo "Security violation: Invalid directory or pattern" >&2
        return 1
    fi

    # Rate limiting check
    if ! check_rate_limit; then
        return 1
    fi

    echo "=== Athena Wayfinder Search Results ===" >&2
    echo "Target: $target_pattern" >&2
    echo "Directory: $current_dir" >&2
    echo "Mode: $SEARCH_DEPTH" >&2
    echo "---" >&2

    # Use find with exclusion patterns - validate current_dir
    if [[ "$validated_dir" != "$current_dir" ]]; then
        current_dir="$validated_dir"
    fi

    # Validate find command to prevent command injection
    if [[ "$current_dir" =~ [^[:alnum:]/._-] ]]; then
        echo "Security violation: Invalid directory path" >&2
        return 1
    fi

    # Execute find with safe patterns
    find "$current_dir" -type f \( -name "*.py" -o -name "*.sh" -o -name "*.md" -o -name "*.json" -o -name "*.yaml" -o -name "*.yml" -o -name "*.txt" \) 2>/dev/null | while IFS= read -r file_path; do
        # Check if file should be excluded
        if is_excluded "$file_path"; then
            continue
        fi

        # Check if file contains target
        if grep -q "$target_pattern" "$file_path" 2>/dev/null; then
            local file_info=""
            local file_structure=""

            # Get basic file info
            local file_size=$(du -h "$file_path" | cut -f1)
            local file_mod_time=$(date -r "$file_path" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "unknown")
            # Use python for MIME type detection since 'file' command not available in Termux
            local file_type=$(python3 -c "
import mimetypes
mime, _ = mimetypes.guess_type('$file_path')
if mime:
    print(mime.split('/')[0])
else:
    ext = '$file_path'.split('.')[-1] if '.' in '$file_path' else 'unknown'
    type_map = {'py': 'text', 'sh': 'text', 'md': 'text', 'json': 'application', 'txt': 'text', 'js': 'text', 'html': 'text', 'css': 'text', 'yaml': 'text', 'yml': 'text', 'xml': 'application', 'conf': 'text', 'cfg': 'text', 'ini': 'text', 'toml': 'text', 'lock': 'application', 'log': 'text'}
    print(type_map.get(ext, 'unknown'))
" 2>/dev/null || echo "unknown")

            # Get line count
            local line_count=$(wc -l < "$file_path" 2>/dev/null | tr -d ' ')

            # Extract code structure based on file type
            file_structure=$(extract_code_structure "$file_path")

            # Format based on output format
            if [[ "$OUTPUT_FORMAT" == "structured" ]]; then
                file_info="{\"path\": \"$file_path\", \"size\": \"$file_size\", \"modified\": \"$file_mod_time\", \"type\": \"$file_type\", \"lines\": $line_count, \"structure\": \"$file_structure\"}"
            else
                file_info="$file_path ($file_size, $file_mod_time, $file_type, $line_count lines)"
                file_info+=" [$file_structure]"
            fi

            # Add to results
            SEARCH_RESULTS+=("$file_info")

            # Display result
            if [[ "$OUTPUT_FORMAT" == "structured" ]]; then
                echo "File: $file_path" >&2
                echo "  Size: $file_size, Modified: $file_mod_time" >&2
                echo "  Type: $file_type, Lines: $line_count" >&2
                echo "  Structure: $file_structure" >&2
            else
                echo "$file_info" >&2
            fi
        fi

        # If deep mode, also search for related patterns
        if [[ "$SEARCH_DEPTH" == "deep" ]]; then
            # Extract function names/classes for related searches
            local patterns_to_search="$target_pattern"

            # Add common patterns based on file type with safe validation
            if [[ "$file_path" == *.py ]]; then
                patterns_to_search+="|def |class |import |from "
            elif [[ "$file_path" == *.sh ]]; then
                patterns_to_search+="|function |() { | case | esac "
            fi

            # Additional related searches with security validation
            if [[ "$file_path" == *.py ]]; then
                local function_pattern="def $target_pattern"
                if safe_grep "$function_pattern" "$file_path"; then
                    # Found function definition, search for usages
                    local safe_dir_pattern="$current_dir"
                    if [[ "$safe_dir_pattern" =~ [^[:alnum:]/._-] ]]; then
                        echo "Security violation: Invalid directory pattern" >&2
                        continue
                    fi
                    # Use safe command execution for related file searches
                    local temp_results
                    if temp_results=$(safe_execute "find '$current_dir' -type f -name '*.py' 2>/dev/null | xargs -0 grep -l '$target_pattern' 2>/dev/null || true" "$TIMEOUT_SECONDS"); then
                        while IFS= read -r related_file; do
                            if [[ "$related_file" != "$file_path" ]] && ! is_excluded "$related_file"; then
                                local related_structure=$(extract_code_structure "$related_file")
                                SEARCH_RESULTS+=("RELATED: $related_file (uses $target_pattern) [$related_structure]")
                                echo "RELATED: $related_file (uses $target_pattern)" >&2
                            fi
                        done <<< "$temp_results"
                    fi
                fi
            fi
        fi

        # Limit results
        if [[ ${#SEARCH_RESULTS[@]} -gt $MAX_RESULTS ]]; then
            break
        fi
    done

    # Display summary
    echo "---" >&2
    echo "Summary:" >&2
    echo "Total files found: ${#SEARCH_RESULTS[@]}" >&2
    echo "Search completed in ~${TIMEOUT_SECONDS} seconds" >&2
}

# Function to build exploration tree
build_exploration_tree() {
    local start_path="${1:-/root}"
    local current_depth="0"
    local max_depth="${2:-3}"

    echo "Building exploration tree from: $start_path" >&2

    # Build tree recursively
    build_tree_recursive "$start_path" "$current_depth" "$max_depth" ""
}

# Recursive tree building function
build_tree_recursive() {
    local current_path="$1"
    local current_depth="$2"
    local max_depth="$3"
    local indent="$4"

    if [[ "$current_depth" -gt "$max_depth" ]]; then
        return
    fi

    # List directory contents
    local items
    items=$(find "$current_path" -maxdepth 1 -type f -name "*" 2>/dev/null | sort)
    for item in $items; do
        local item_name=$(basename "$item")

        # Skip excluded items
        if is_excluded "$item_name"; then
            continue
        fi

        # Get item info
        local item_info=""
        if [[ -d "$item" ]]; then
            local sub_count=$(find "$item" -type f 2>/dev/null | wc -l)
            item_info="[DIR: $sub_count files]"
        else
            local item_size=$(du -h "$item" | cut -f1)
            local item_type="file"
            if command -v file >/dev/null 2>&1; then
                item_type=$(file --mime-type -b "$item" 2>/dev/null | cut -d'/' -f1 || echo "file")
            fi
            item_info="[$item_type: $item_size]"
        fi

        # Add to tree
        EXPLORATION_TREE+=("$indent├── $item_name $item_info")

        # Recursively explore subdirectories
        if [[ -d "$item" ]] && [[ "$current_depth" -lt "$max_depth" ]]; then
            build_tree_recursive "$item" $((current_depth + 1)) "$max_depth" "$indent│   "
        fi
    done

    # Display tree
    for tree_entry in "${EXPLORATION_TREE[@]}"; do
        echo "$tree_entry" >&2
    done
}

# Function to analyze relationships
analyze_relationships() {
    local target="$1"
    local search_dir="${2:-/root}"

    echo "Analyzing relationships for: $target" >&2

    # Find all files containing the target
    local related_files
    related_files=$(find "$search_dir" -type f \( -name "*.py" -o -name "*.sh" \) 2>/dev/null | xargs grep -l "$target" 2>/dev/null)

    # Analyze relationships
    while IFS= read -r file_path; do
        if is_excluded "$file_path"; then
            continue
        fi

        # Extract context around target
        local context_lines=$(grep -n -B3 -A3 "$target" "$file_path" 2>/dev/null | head -20)

        # Analyze imports/requires for file_path
        local imports=""
        if [[ "$file_path" == *.py ]]; then
            imports=$(grep -o "^\s*import [a-zA-Z0-9_.]*" "$file_path" 2>/dev/null | head -5 | tr '\n' '; ')
        elif [[ "$file_path" == *.sh ]]; then
            imports=$(grep -o '\$[a-zA-Z_][a-zA-Z0-9_]*' "$file_path" 2>/dev/null | sort -u | head -5 | tr '\n' '; ')
        fi

        # Add to relationship map
        RELATIONSHIP_MAP+=("$file_path: context=[$context_lines], imports=[$imports]")

        echo "File: $file_path" >&2
        echo "  Context: $context_lines" >&2
        echo "  Imports: $imports" >&2

    done <<< "$related_files"
}

# Function to export results
export_results() {
    local output_file="${1:-wayfinder_results.json}"
    local format="${2:-structured}"

    echo "Exporting results to: $output_file" >&2

    case "$format" in
        "structured")
            # JSON format
            cat > "$output_file" << EOF
{
  "search_mode": "$WAYFINDER_MODE",
  "target": "$TARGET",
  "search_depth": "$SEARCH_DEPTH",
  "output_format": "$OUTPUT_FORMAT",
  "results": [
EOF

            local first=true
            for result in "${SEARCH_RESULTS[@]}"; do
                if [[ "$first" == true ]]; then
                    first=false
                else
                    echo "," >> "$output_file"
                fi
                echo "    $result" >> "$output_file"
            done

            cat >> "$output_file" << EOF
  ],
  "exploration_tree": [
EOF

            for tree_entry in "${EXPLORATION_TREE[@]}"; do
                echo "    \"$tree_entry\"," >> "$output_file"
            done

            cat >> "$output_file" << EOF
  ],
  "relationships": [
EOF

            for rel_entry in "${RELATIONSHIP_MAP[@]}"; do
                echo "    \"$rel_entry\"," >> "$output_file"
            done

            cat >> "$output_file" << EOF
  ],
  "metadata": {
    "timestamp": "$(date -Iseconds)",
    "search_time_seconds": $TIMEOUT_SECONDS,
    "max_results": $MAX_RESULTS
  }
}
EOF
            ;;

        "simple")
            # Simple text format
            cat > "$output_file" << EOF
Athena Wayfinder Results
=========================
Target: $TARGET
Mode: $WAYFINDER_MODE
Search Depth: $SEARCH_DEPTH

Search Results:
$(printf '%s\n' "${SEARCH_RESULTS[@]}")

Exploration Tree:
$(printf '%s\n' "${EXPLORATION_TREE[@]}")

Relationships:
$(printf '%s\n' "${RELATIONSHIP_MAP[@]}")
EOF
            ;;

        "csv")
            # CSV format
            cat > "$output_file" << EOF
path,size,modified,type,lines,structure,category
$(for result in "${SEARCH_RESULTS[@]}"; do echo "$result"; done)
EOF
            ;;
    esac

    echo "Results exported to: $output_file" >&2
}

# Main execution logic
main() {
    case "$WAYFINDER_MODE" in
        "search")
            if [[ -n "$TARGET" ]]; then
                perform_search "$TARGET" "/root"
            else
                echo "Error: No target specified for search mode" >&2
                exit 1
            fi
            ;;

        "explore")
            local start_path="${TARGET:-/root}"
            build_exploration_tree "$start_path" "${SEARCH_DEPTH:-deep}"
            export_results "${OUTPUT_FILE:-wayfinder_results.json}" "$OUTPUT_FORMAT"
            ;;

        "relationships")
            if [[ -n "$TARGET" ]]; then
                analyze_relationships "$TARGET"
            else
                echo "Error: No target specified for relationship analysis" >&2
                exit 1
            fi
            ;;

        "export")
            if [[ -n "$TARGET" ]]; then
                perform_search "$TARGET" "/root"
            fi
            export_results "${3:-wayfinder_results.json}" "$OUTPUT_FORMAT"
            ;;

        "full")
            if [[ -n "$TARGET" ]]; then
                perform_search "$TARGET" "/root"
                analyze_relationships "$TARGET"
                build_exploration_tree
                export_results "${5:-wayfinder_results.json}" "$OUTPUT_FORMAT"
            else
                echo "Error: No target specified for full analysis" >&2
                exit 1
            fi
            ;;

        *)
            echo "Usage: $0 [search|explore|relationships|export|full] [target] [depth] [format] [output_file]" >&2
            echo "  Modes:" >&2
            echo "    search     - Search for target in codebase" >&2
            echo "    explore    - Build exploration tree of directory structure" >&2
            echo "    relationships - Analyze relationships around target" >&2
            echo "    export     - Search and export results" >&2
            echo "    full       - Complete analysis (search + relationships + tree + export)" >&2
            echo "" >&2
            echo "Arguments:" >&2
            echo "  target        - Search target pattern" >&2
            echo "  depth         - Search depth (deep or shallow) [default: deep]" >&2
            echo "  format        - Output format (structured, simple, csv) [default: structured]" >&2
            echo "  output_file   - Output file for export mode" >&2
            exit 1
            ;;
    esac
}

# Execute main function
main