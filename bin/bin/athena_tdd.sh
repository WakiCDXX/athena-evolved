#!/bin/bash
# athena_tdd.sh - Test-driven development integration for Athena
# Implements Matt Pocock's /tdd skill with Athena-specific enhancements

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

# Initialize TDD variables with validation
TDD_MODE="${1:-validate}"
TARGET_TEST="${2:-}"
TEST_FRAMEWORK="${3:-pytest}"
COVERAGE_THRESHOLD="${4:-80}"
PERFORMANCE_TARGET="${5:-1000}"
OUTPUT_DIR="${6:-/root/.local/share/athena_tests}"
TEST_TYPE="${7:-unit}"
PARALLEL_JOBS="${8:-auto}"

# Validate mode
if [[ ! "$TDD_MODE" =~ ^(validate|execute|analyze|full)$ ]]; then
    echo "Error: Invalid mode. Use: validate, execute, analyze, or full" >&2
    exit 1
fi

# In validate mode, TEST_FRAMEWORK is at position $4 (after validation_mode at $3)
if [[ "$TDD_MODE" == "validate" ]]; then
    val_mode="${3:-comprehensive}"
    tf="${4:-pytest}"
    TEST_FRAMEWORK="$tf"
    COVERAGE_THRESHOLD="${5:-80}"
    PERFORMANCE_TARGET="${6:-1000}"
    OUTPUT_DIR="${7:-/root/.local/share/athena_tests}"
    TEST_TYPE="${8:-unit}"
    PARALLEL_JOBS="${9:-auto}"
fi

# Validate test framework
if [[ ! "$TEST_FRAMEWORK" =~ ^(pytest|jest|mocha|junit)$ ]]; then
    echo "Error: Invalid test framework. Use: pytest, jest, mocha, or junit" >&2
    exit 1
fi

# Validate test type
if [[ ! "$TEST_TYPE" =~ ^(unit|integration|functional|acceptance)$ ]]; then
    echo "Error: Invalid test type. Use: unit, integration, functional, or acceptance" >&2
    exit 1
fi

# Performance optimization with safe limits
MAX_TESTS=1000
TIMEOUT_SECONDS=300

# Initialize test tracking with size limits
TEST_RESULTS=()
TEST_SUMMARY=()
COVERAGE_DATA=()
PERFORMANCE_METRICS=()

# Create output directory with validation
mkdir -p "$OUTPUT_DIR"

# Validate output directory
if [[ ! -d "$OUTPUT_DIR" ]] || [[ ! -w "$OUTPUT_DIR" ]]; then
    echo "Error: Output directory not accessible: $OUTPUT_DIR" >&2
    exit 1
fi

# Function to validate test structure
test_validation() {
    local test_file="$1"
    local validation_mode="$2"

    echo "=== Athena TDD Test Validation ===" >&2
    echo "Test File: $test_file" >&2
    echo "Validation Mode: $validation_mode" >&2
    echo "Test Framework: $TEST_FRAMEWORK" >&2
    echo "---" >&2

    if [[ ! -f "$test_file" ]]; then
        echo "Error: Test file not found: $test_file" >&2
        return 1
    fi

    local file_name=$(basename "$test_file")
    local file_ext="${file_name##*.}"
    local validation_entry=""

    case "$validation_mode" in
        "comprehensive")
            validation_entry="Comprehensive Test Validation Report\n"
            validation_entry+="  File Metadata:\n"
            validation_entry+="    Name: $file_name\n"
            validation_entry+="    Size: $(du -h "$test_file" | cut -f1)\n"
            validation_entry+="    Lines: $(wc -l < "$test_file" | tr -d ' ')\n"
            validation_entry+="    Type: $file_ext\n"
            validation_entry+="  Framework Validation:\n"
            validation_entry+="    $(test_framework_check "$test_file")\n"
            validation_entry+="  Structure Validation:\n"
            validation_entry+="    $(structure_validation "$test_file")\n"
            validation_entry+="  Coverage Validation:\n"
            validation_entry+="    $(coverage_validation "$test_file")\n"
            validation_entry+="  Performance Validation:\n"
            validation_entry+="    $(performance_validation "$test_file")\n"
            validation_entry+="  Best Practices:\n"
            validation_entry+="    $(best_practices_validation "$test_file")\n"
            ;;

        "quick")
            validation_entry="Quick Test Validation Report\n"
            validation_entry+"  Basic Checks:\n"
            validation_entry+"    File exists: $(ls -ld "$test_file" 2>/dev/null | grep -q '^-' && echo "✓" || echo "✗")\n"
            validation_entry+"    Structure: $(structure_validation "$test_file")\n"
            validation_entry+"    Framework: $(test_framework_check "$test_file")\n"
            validation_entry+"  Summary: $(quick_test_summary "$test_file")\n"
            ;;

        *)
            validation_entry="Basic Test Validation Report\n"
            validation_entry+"  File exists: $(ls -ld "$test_file" 2>/dev/null | grep -q '^-' && echo "✓" || echo "✗")\n"
            validation_entry+"  Framework check: $(test_framework_check "$test_file")\n"
            validation_entry+"  Structure: $(structure_validation "$test_file")\n"
            ;;
    esac

    # Add to test results
    TEST_RESULTS+=("$validation_entry")

    # Display validation
    echo "$validation_entry"
    echo "---" >&2

    return 0
}

# Function to check test framework compatibility
test_framework_check() {
    local test_file="$1"

    case "$TEST_FRAMEWORK" in
        "pytest")
            if [[ "$file_ext" == "py" ]]; then
                if grep -q "import pytest" "$test_file" 2>/dev/null; then
                    echo "✓ pytest configuration present"
                    return 0
                else
                    echo "✗ pytest configuration missing"
                    return 1
                fi
            else
                echo "⚠ Not a Python file for pytest"
                return 0
            fi
            ;;

        "jest")
            if [[ "$file_ext" == "js" ]] || [[ "$file_ext" == "ts" ]]; then
                if grep -q "describe\|it\|test" "$test_file" 2>/dev/null; then
                    echo "✓ Jest test structure present"
                    return 0
                else
                    echo "✗ Jest test structure missing"
                    return 1
                fi
            else
                echo "⚠ Not a JavaScript/TypeScript file for Jest"
                return 0
            fi
            ;;

        "mocha")
            if [[ "$file_ext" == "js" ]]; then
                if grep -q "describe\|it\|suite" "$test_file" 2>/dev/null; then
                    echo "✓ Mocha test structure present"
                    return 0
                else
                    echo "✗ Mocha test structure missing"
                    return 1
                fi
            else
                echo "⚠ Not a JavaScript file for Mocha"
                return 0
            fi
            ;;

        "junit")
            if [[ "$file_ext" == "java" ]]; then
                if grep -q "@Test\|public void test" "$test_file" 2>/dev/null; then
                    echo "✓ JUnit test structure present"
                    return 0
                else
                    echo "✗ JUnit test structure missing"
                    return 1
                fi
            else
                echo "⚠ Not a Java file for JUnit"
                return 0
            fi
            ;;

        *)
            echo "⚠ Unknown test framework: $TEST_FRAMEWORK"
            return 0
            ;;
    esac
}

# Function to validate test structure
structure_validation() {
    local test_file="$1"

    local structure_score=0
    local total_score=5

    # Check for test naming convention
    if grep -q -E "test_[a-zA-Z0-9_]+\(|def test_[a-zA-Z0-9_]+\(|it\('[^']*'\)" "$test_file" 2>/dev/null; then
        structure_score=$((structure_score + 1))
    fi

    # Check for test assertions
    local assertion_patterns=0
    case "$TEST_FRAMEWORK" in
        "pytest") assertion_patterns="assert |assert_eq |assert_contains" ;;
        "jest") assertion_patterns="expect.*toBe|expect.*toContain|expect.*toEqual" ;;
        "mocha") assertion_patterns="expect.*toBe|assert\." ;;
        "junit") assertion_patterns="assert|assertEquals|assertTrue" ;;
        *) assertion_patterns=".*" ;;
    esac

    if grep -qE "$assertion_patterns" "$test_file" 2>/dev/null; then
        structure_score=$((structure_score + 1))
    fi

    # Check for test fixtures/setup
    if grep -q -E "@BeforeEach|@BeforeAll|beforeEach|beforeAll|setup" "$test_file" 2>/dev/null; then
        structure_score=$((structure_score + 1))
    fi

    # Check for test dependencies
    if grep -q -E "import.*@Mock|from.*mock|jest.*mock" "$test_file" 2>/dev/null; then
        structure_score=$((structure_score + 1))
    fi

    # Check for test categories/groups
    if grep -q -E "@TestClass|@TestCategory|describe.*\(.*\)" "$test_file" 2>/dev/null; then
        structure_score=$((structure_score + 1))
    fi

    if [[ $structure_score -eq $total_score ]]; then
        echo "✓ Excellent structure ($structure_score/$total_score)"
    elif [[ $structure_score -ge $((total_score / 2)) ]]; then
        echo "⚠ Good structure ($structure_score/$total_score)"
    else
        echo "✗ Poor structure ($structure_score/$total_score)"
    fi
}

# Function to validate coverage
coverage_validation() {
    local test_file="$1"

    case "$TEST_FRAMEWORK" in
        "pytest")
            # Generate coverage if pytest-cov available
            if command -v pytest >/dev/null 2>&1; then
                local coverage_output=$(pytest --cov="$test_file" --cov-report="term-missing" "$test_file" 2>/dev/null | grep -A 5 "Missing" | head -10)
                if [[ -n "$coverage_output" ]]; then
                    echo "✓ Coverage analysis completed"
                    echo "  $coverage_output"
                    return 0
                else
                    echo "⚠ Coverage analysis inconclusive"
                    return 0
                fi
            else
                echo "⚠ pytest not available for coverage analysis"
                return 0
            fi
            ;;

        *)
            echo "⚠ Coverage validation not implemented for $TEST_FRAMEWORK"
            return 0
            ;;
    esac
}

# Function to validate performance
performance_validation() {
    local test_file="$1"

    case "$TEST_FRAMEWORK" in
        "pytest")
            if command -v pytest >/dev/null 2>&1; then
                local start_time=$(date +%s)
                pytest "$test_file" -v 2>/dev/null
                local end_time=$(date +%s)
                local execution_time=$((end_time - start_time))

                if [[ $execution_time -le $PERFORMANCE_TARGET ]]; then
                    echo "✓ Performance acceptable (${execution_time}s)"
                else
                    echo "⚠ Performance slow (${execution_time}s > ${PERFORMANCE_TARGET}s)"
                fi

                # Store performance metric
                PERFORMANCE_METRICS+=("$(basename "$test_file"):${execution_time}s")
                return 0
            else
                echo "⚠ pytest not available for performance testing"
                return 0
            fi
            ;;

        *)
            echo "⚠ Performance validation not implemented for $TEST_FRAMEWORK"
            return 0
            ;;
    esac
}

# Function to validate best practices
best_practices_validation() {
    local test_file="$1"

    local practices_score=0
    local total_practices=6

    # Check for error handling
    if grep -q -E "try\s*\{.*catch\|try\s*\{.*except" "$test_file" 2>/dev/null; then
        practices_score=$((practices_score + 1))
    fi

    # Check for logging
    if grep -q -E "logger\|log\|println" "$test_file" 2>/dev/null; then
        practices_score=$((practices_score + 1))
    fi

    # Check for resource cleanup
    if grep -q -E "finally\s*\{|cleanup\|tearDown\|afterEach" "$test_file" 2>/dev/null; then
        practices_score=$((practices_score + 1))
    fi

    # Check for test isolation
    if grep -q -E "@Isolated|isolated|beforeEach.*reset" "$test_file" 2>/dev/null; then
        practices_score=$((practices_score + 1))
    fi

    # Check for parameterized tests
    if grep -q -E "@Parameterized|parametrize|dataProvider" "$test_file" 2>/dev/null; then
        practices_score=$((practices_score + 1))
    fi

    # Check for test descriptions
    if grep -q -E "@Description|test.*description|it\('[^']*'\)" "$test_file" 2>/dev/null; then
        practices_score=$((practices_score + 1))
    fi

    local score_str="$practices_score/$total_practices"
    local half_practices=$(( total_practices / 2 ))
    if [[ $practices_score -eq $total_practices ]]; then
        echo "All best practices followed [$score_str]"
    elif [[ $practices_score -ge $half_practices ]]; then
        echo "Most best practices followed [$score_str]"
    else
        echo "Few best practices followed [$score_str]"
    fi
}

# Function to run quick test summary
quick_test_summary() {
    local test_file="$1"

    local test_count=$(grep -c -E "test_[a-zA-Z0-9_]+\(|def test_[a-zA-Z0-9_]+\(|it\('[^']*'\)" "$test_file" 2>/dev/null || echo "0")
    local assert_count=$(grep -c -E "assert |expect.*to|assertEquals" "$test_file" 2>/dev/null || echo "0")
    local line_count=$(wc -l < "$test_file" 2>/dev/null | tr -d ' ')

    echo "  Tests found: $test_count"
    echo "  Assertions: $assert_count"
    echo "  Total lines: $line_count"
    echo "  Framework: $TEST_FRAMEWORK"
}

# Function to run test suite
test_suite() {
    local test_directory="$1"
    local suite_mode="$2"

    echo "=== Athena TDD Test Suite ===" >&2
    echo "Test Directory: $test_directory" >&2
    echo "Suite Mode: $suite_mode" >&2
    echo "Framework: $TEST_FRAMEWORK" >&2
    echo "Parallel Jobs: $PARALLEL_JOBS" >&2
    echo "---" >&2

    if [[ ! -d "$test_directory" ]]; then
        echo "Error: Test directory not found: $test_directory" >&2
        return 1
    fi

    # Discover test files
    local test_files
    case "$TEST_FRAMEWORK" in
        "pytest")
            test_files=$(find "$test_directory" -name "test_*.py" -o -name "*_test.py" 2>/dev/null)
            ;;

        "jest")
            test_files=$(find "$test_directory" -name "*.spec.js" -o -name "*.test.js" 2>/dev/null)
            ;;

        "mocha")
            test_files=$(find "$test_directory" -name "*.spec.js" -o -name "*.test.js" 2>/dev/null)
            ;;

        "junit")
            test_files=$(find "$test_directory" -name "Test*.java" 2>/dev/null)
            ;;

        *)
            test_files=$(find "$test_directory" -type f -name "*.py" -o -name "*.js" -o -name "*.java" 2>/dev/null)
            ;;
    esac

    echo "Found test files:" >&2
    for test_file in $test_files; do
        echo "  - $(basename "$test_file")" >&2
    done

    # Run tests based on framework with security validation
    case "$TEST_FRAMEWORK" in
        "pytest")
            if command -v pytest >/dev/null 2>&1; then
                local parallel_args=""
                if [[ "$PARALLEL_JOBS" != "auto" ]]; then
                    parallel_args="-n $PARALLEL_JOBS"
                fi

                echo "Running pytest with args: $parallel_args" >&2
                local safe_test_dir
                safe_test_dir=$(validate_and_sanitize_path "$test_directory" 2>/dev/null)
                if [[ $? -ne 0 ]] || [[ -z "$safe_test_dir" ]]; then
                    echo "Security violation: Invalid test directory" >&2
                    return 1
                fi
                safe_execute "pytest $parallel_args '$safe_test_dir' -v" "$TIMEOUT_SECONDS"
            else
                echo "Error: pytest not installed" >&2
                return 1
            fi
            ;;

        "jest")
            if command -v node >/dev/null 2>&1; then
                local jest_path=$(command -v jest)
                if [[ -n "$jest_path" ]]; then
                    echo "Running Jest" >&2
                    local safe_test_dir
                    safe_test_dir=$(validate_and_sanitize_path "$test_directory" 2>/dev/null)
                    if [[ $? -ne 0 ]] || [[ -z "$safe_test_dir" ]]; then
                        echo "Security violation: Invalid test directory" >&2
                        return 1
                    fi
                    safe_execute "node '$jest_path' '$safe_test_dir' --verbose" "$TIMEOUT_SECONDS"
                else
                    echo "Error: Jest not installed" >&2
                    return 1
                fi
            else
                echo "Error: Node.js not available" >&2
                return 1
            fi
            ;;

        "mocha")
            if command -v mocha >/dev/null 2>&1; then
                echo "Running Mocha" >&2
                mocha "$test_directory" --reporter=spec 2>/dev/null
            else
                echo "Error: Mocha not installed" >&2
                return 1
            fi
            ;;

        "junit")
            if command -v mvn >/dev/null 2>&1; then
                echo "Running Maven JUnit" >&2
                mvn test -Dtest="*$test_directory*" 2>/dev/null
            else
                echo "Error: Maven not available" >&2
                return 1
            fi
            ;;

        *)
            echo "Error: Unsupported test framework: $TEST_FRAMEWORK" >&2
            return 1
            ;;
    esac

    # Collect results
    collect_test_results "$test_directory"
}

# Function to collect test results
collect_test_results() {
    local test_directory="$1"

    echo "=== Collecting Test Results ===" >&2

    # Create summary file
    local summary_file="$OUTPUT_DIR/test_summary_$(date +%Y%m%d_%H%M%S).txt"

    # Generate summary
    cat > "$summary_file" << EOF
Athena TDD Test Summary
=======================
Generated: $(date -Iseconds)
Test Framework: $TEST_FRAMEWORK
Test Directory: $test_directory
Parallel Jobs: $PARALLEL_JOBS

Performance Metrics:
EOF

    for metric in "${PERFORMANCE_METRICS[@]}"; do
        echo "  $metric" >> "$summary_file"
    done

    cat >> "$summary_file" << EOF

Test Results:
EOF

    # Run quick validation on each test file
    local test_files
    case "$TEST_FRAMEWORK" in
        "pytest")
            test_files=$(find "$test_directory" -name "test_*.py" -o -name "*_test.py" 2>/dev/null)
            ;;

        "jest")
            test_files=$(find "$test_directory" -name "*.spec.js" -o -name "*.test.js" 2>/dev/null)
            ;;

        "mocha")
            test_files=$(find "$test_directory" -name "*.spec.js" -o -name "*.test.js" 2>/dev/null)
            ;;

        *)
            test_files=$(find "$test_directory" -type f \( -name "*.py" -o -name "*.js" -o -name "*.java" \) 2>/dev/null)
            ;;
    esac

    for test_file in $test_files; do
        if test_validation "$test_file" "quick" >/dev/null 2>&1; then
            echo "✓ $(basename "$test_file")" >> "$summary_file"
        else
            echo "✗ $(basename "$test_file")" >> "$summary_file"
        fi
    done

    echo "Test summary saved to: $summary_file" >&2
    TEST_SUMMARY+=("$summary_file")
}

# Function to export test report
export_test_report() {
    local output_file="${1:-tdd_test_report.json}"
    local report_format="${2:-detailed}"

    echo "=== Exporting Test Report ===" >&2
    echo "Output file: $output_file" >&2
    echo "Report format: $report_format" >&2

    case "$report_format" in
        "detailed")
            # JSON format with full details
            cat > "$output_file" << EOF
{
  "metadata": {
    "test_mode": "$TDD_MODE",
    "target_test": "$TARGET_TEST",
    "test_framework": "$TEST_FRAMEWORK",
    "coverage_threshold": $COVERAGE_THRESHOLD,
    "performance_target": $PERFORMANCE_TARGET,
    "test_type": "$TEST_TYPE",
    "parallel_jobs": "$PARALLEL_JOBS",
    "timestamp": "$(date -Iseconds)",
    "timeout_seconds": $TIMEOUT_SECONDS
  },
  "test_results": [
EOF

            local first=true
            for result in "${TEST_RESULTS[@]}"; do
                if [[ "$first" == true ]]; then
                    first=false
                else
                    echo "    ," >> "$output_file"
                fi
                local escaped_result=$(echo "$result" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
                echo "    \"$escaped_result\"" >> "$output_file"
            done

            cat >> "$output_file" << EOF
  ],
  "test_summary": [
EOF

            for summary in "${TEST_SUMMARY[@]}"; do
                echo "    \"$summary\"," >> "$output_file"
            done

            cat >> "$output_file" << EOF
  ],
  "performance_metrics": [
EOF

            for metric in "${PERFORMANCE_METRICS[@]}"; do
                echo "    \"$metric\"," >> "$output_file"
            done

            cat >> "$output_file" << EOF
  ],
  "coverage_data": [
EOF

            for coverage in "${COVERAGE_DATA[@]}"; do
                echo "    \"$coverage\"," >> "$output_file"
            done

            cat >> "$output_file" << EOF
  ],
  "configuration": {
    "max_tests": $MAX_TESTS,
    "timeout_seconds": "$TIMEOUT_SECONDS"
  }
}
EOF
            ;;

        "simple")
            # Simple text format
            cat > "$output_file" << EOF
Athena TDD Test Report
=====================
Test Mode: $TDD_MODE
Target Test: $TARGET_TEST
Test Framework: $TEST_FRAMEWORK
Coverage Threshold: $COVERAGE_THRESHOLD%
Performance Target: ${PERFORMANCE_TARGET}s
Test Type: $TEST_TYPE
Parallel Jobs: $PARALLEL_JOBS

Generated: $(date -Iseconds)

Test Results:
$(printf '%s\n' "${TEST_RESULTS[@]}")

Test Summary Files:
$(printf '%s\n' "${TEST_SUMMARY[@]}")

Performance Metrics:
$(printf '%s\n' "${PERFORMANCE_METRICS[@]}")
EOF
            ;;

        "csv")
            # CSV format
            cat > "$output_file" << EOF
mode,target,framework,type,coverage_target,performance_target,parallel_jobs,timestamp
"$TDD_MODE","$TARGET_TEST","$TEST_FRAMEWORK","$TEST_TYPE","$COVERAGE_THRESHOLD","$PERFORMANCE_TARGET","$PARALLEL_JOBS","$(date -Iseconds)"
EOF
            ;;
    esac

    echo "Test report exported to: $output_file" >&2
}

# Function to manage test environment
manage_test_environment() {
    local action="${1:-setup}"
    local environment="${2:-default}"

    echo "=== Managing Test Environment ===" >&2
    echo "Action: $action" >&2
    echo "Environment: $environment" >&2

    case "$action" in
        "setup")
            # Create test environment directory
            local env_dir="$OUTPUT_DIR/environments/$environment"
            mkdir -p "$env_dir"

            # Copy framework-specific configuration
            case "$TEST_FRAMEWORK" in
                "pytest")
                    if [[ ! -f "$env_dir/pytest.ini" ]]; then
                        cat > "$env_dir/pytest.ini" << EOF
[pytest]
testpaths = tests
test_file = test_*.py
addopts = -v --tb=short
EOF
                    fi
                    ;;

                "jest")
                    if [[ ! -f "$env_dir/jest.config.js" ]]; then
                        cat > "$env_dir/jest.config.js" << EOF
module.exports = {
  testEnvironment: 'node',
  collectCoverageFrom: ['src/**/*.js'],
  coverageThreshold: {
    global: { branches: 80, functions: 80, lines: 80, statements: 80 }
  }
};
EOF
                    fi
                    ;;

                "mocha")
                    if [[ ! -f "$env_dir/.mocharc.js" ]]; then
                        cat > "$env_dir/.mocharc.js" << EOF
module.exports = {
  reporter: 'spec',
  timeout: 10000,
  require: ['@babel/register']
};
EOF
                    fi
                    ;;

                "junit")
                    if [[ ! -d "$env_dir/src/test/java" ]]; then
                        mkdir -p "$env_dir/src/test/java"
                    fi
                    ;;
            esac

            echo "Test environment setup complete: $env_dir" >&2
            ;;

        "list")
            # List available environments
            if [[ -d "$OUTPUT_DIR/environments" ]]; then
                echo "Available test environments:" >&2
                ls -la "$OUTPUT_DIR/environments/" >&2
            else
                echo "No test environments found" >&2
            fi
            ;;

        *)
            echo "Usage: $0 test_environment <setup|list> [environment]" >&2
            ;;
    esac
}

# Main execution logic
main() {
    case "$TDD_MODE" in
        "validate")
            if [[ -n "$TARGET_TEST" ]]; then
                # VALIDATION_MODE is the 2nd positional arg, stored in $2
                VALIDATION_MODE=${2:-comprehensive}
                test_validation "$TARGET_TEST" "$VALIDATION_MODE"
            else
                echo "Error: No target test specified for validation" >&2
                echo "Usage: $0 validate <test_file> [validation_mode] [test_framework] [coverage_threshold] [performance_target] [output_dir] [test_type] [parallel_jobs]" >&2
                echo "  validation_mode: comprehensive, quick, basic [default: comprehensive]" >&2
                echo "  test_framework: pytest, jest, mocha, junit [default: pytest]" >&2
                echo "  coverage_threshold: Percentage [default: 80]" >&2
                echo "  performance_target: Seconds [default: 1000]" >&2
                echo "  output_dir: Output directory [default: $OUTPUT_DIR]" >&2
                echo "  test_type: unit, integration, e2e [default: unit]" >&2
                echo "  parallel_jobs: auto or number [default: auto]" >&2
                exit 1
            fi
            ;;

        "suite")
            if [[ -n "$TARGET_TEST" ]]; then
                test_suite "$TARGET_TEST" "$TEST_TYPE"
            else
                echo "Error: No target directory specified for test suite" >&2
                echo "Usage: $0 suite <test_directory> [test_type] [test_framework] [parallel_jobs]" >&2
                echo "  test_type: unit, integration, e2e [default: unit]" >&2
                echo "  test_framework: pytest, jest, mocha, junit [default: pytest]" >&2
                echo "  parallel_jobs: auto or number [default: auto]" >&2
                exit 1
            fi
            ;;

        "export")
            if [[ -n "$TARGET_TEST" ]]; then
                test_validation "$TARGET_TEST" "quick"
                export_test_report "${7:-$OUTPUT_DIR/tdd_test_report.json}" "$SPEC_FORMAT"
            else
                echo "Error: No target test specified for export" >&2
                echo "Usage: $0 export <test_file> [output_file] [report_format] [test_framework] [coverage_threshold] [performance_target] [output_dir] [test_type] [parallel_jobs]" >&2
                echo "  output_file: Output file path [default: $OUTPUT_DIR/tdd_test_report.json]" >&2
                echo "  report_format: detailed, simple, csv [default: detailed]" >&2
                echo "  test_framework: pytest, jest, mocha, junit [default: pytest]" >&2
                echo "  coverage_threshold: Percentage [default: 80]" >&2
                echo "  performance_target: Seconds [default: 1000]" >&2
                echo "  output_dir: Output directory [default: $OUTPUT_DIR]" >&2
                echo "  test_type: unit, integration, e2e [default: unit]" >&2
                echo "  parallel_jobs: auto or number [default: auto]" >&2
                exit 1
            fi
            ;;

        "full")
            if [[ -n "$TARGET_TEST" ]]; then
                echo "=== Full TDD Test Process ===" >&2
                test_validation "$TARGET_TEST" "comprehensive"
                test_suite "$TARGET_TEST" "$TEST_TYPE"
                export_test_report "${8:-$OUTPUT_DIR/tdd_test_report.json}" "$SPEC_FORMAT"
                echo "Full TDD process completed successfully" >&2
            else
                echo "Error: No target test specified for full analysis" >&2
                exit 1
            fi
            ;;

        "environment")
            manage_test_environment "$2" "$3"
            ;;

        *)
            echo "Usage: $0 [validate|suite|export|full|environment] [arguments...]" >&2
            echo "" >&2
            echo "Modes:" >&2
            echo "  validate   - Validate single test file" >&2
            echo "  suite      - Run test suite on directory" >&2
            echo "  export     - Export test report" >&2
            echo "  full       - Complete TDD process" >&2
            echo "  environment - Manage test environment" >&2
            echo "" >&2
            echo "Example usages:" >&2
            echo "  $0 validate tests/test_example.py" >&2
            echo "  $0 suite tests/ unit pytest" >&2
            echo "  $0 export tests/test_example.py report.json detailed" >&2
            echo "  $0 full tests/" >&2
            echo "  $0 environment setup pytest" >&2
            exit 1
            ;;
    esac
}

# Execute main function
main