#!/bin/bash

# Usage: ./run_tests.sh [path to nanotekspice]

BINARY="${1:-../nanotekspice}"
TEST_DIR="$(dirname "$0")"
PASSED=0
FAILED=0
TOTAL=0
CURRENT=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Store failed tests for summary
FAILED_TESTS=()

if [ ! -f "$BINARY" ]; then
    echo -e "${RED}Error: Binary not found: $BINARY${NC}"
    exit 1
fi

# Progress bar function
show_progress() {
    local current=$1
    local total=$2
    local filename=$3
    local width=50
    local percentage=$((current * 100 / total))
    local filled=$((width * current / total))
    local empty=$((width - filled))

    printf "\r["
    printf "%${filled}s" | tr ' ' '#'
    printf "%${empty}s" | tr ' ' '-'
    printf "] %3d%% (%d/%d) Currently at \"%s\"%-50s" "$percentage" "$current" "$total" "$filename"
}

# Run test expecting error (exit 84)
run_error_test() {
    local file="$1"
    local name=$(basename "$file" .nts)

    timeout 2 "$BINARY" "$file" > /dev/null 2>&1
    if [ $? -eq 84 ]; then
        PASSED=$((PASSED + 1))
    else
        FAILED=$((FAILED + 1))
        FAILED_TESTS+=("$name (expected error 84)")
    fi

    CURRENT=$((CURRENT + 1))
    show_progress $CURRENT $TOTAL "$name"
}

# Run tests
run_test() {
    local file="$1"
    local commands="$2"
    local line_num="$3"
    shift 3
    local expected_outputs=("$@")
    local name=$(basename "$file" .nts)
    local line_info=""

    if [ -n "$line_num" ]; then
        line_info=" (line $line_num)"
    fi

    output=$(echo -e "$commands" | timeout 5 "$BINARY" "$file" 2>&1)
    exit_code=$?

    if [ $exit_code -eq 124 ]; then
        FAILED=$((FAILED + 1))
        FAILED_TESTS+=("$name$line_info (timeout)")
    elif [ $exit_code -ne 0 ]; then
        FAILED=$((FAILED + 1))
        FAILED_TESTS+=("$name$line_info (exit code $exit_code)")
    elif [ ${#expected_outputs[@]} -gt 0 ]; then
        local all_matched=true
        local failed_patterns=()

        for pattern in "${expected_outputs[@]}"; do
            if ! echo "$output" | grep -q "$pattern"; then
                all_matched=false
                failed_patterns+=("$pattern")
            fi
        done

        if $all_matched; then
            PASSED=$((PASSED + 1))
        else
            FAILED=$((FAILED + 1))
            FAILED_TESTS+=("$name$line_info - missing: ${failed_patterns[*]}")
        fi
    else
        PASSED=$((PASSED + 1))
    fi

    CURRENT=$((CURRENT + 1))
    show_progress $CURRENT $TOTAL "$name$line_info"
}

# Count total tests first
echo -e "${BLUE}Counting tests...${NC}"
for f in "$TEST_DIR"/error_*.nts; do
    [ -f "$f" ] && TOTAL=$((TOTAL + 1))
done

for f in "$TEST_DIR"/*.test; do
    [ -f "$f" ] || continue
    line_num=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        line_num=$((line_num + 1))
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        if [[ $line =~ ^\"([^\"]*)\"[[:space:]]+(.+)$ ]]; then
            TOTAL=$((TOTAL + 1))
        fi
    done < "$f"
done

echo -e "${BLUE}Running $TOTAL tests...${NC}\n"
printf "\e[?25l"


# Run error tests
for f in "$TEST_DIR"/error_*.nts; do
    [ -f "$f" ] && run_error_test "$f"
done

# Run regular tests
for f in "$TEST_DIR"/*.test; do
    [ -f "$f" ] || continue
    filename="$(basename "$f" .test)"
    line_num=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        line_num=$((line_num + 1))
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        if [[ $line =~ ^\"([^\"]*)\"[[:space:]]+(.+)$ ]]; then
            input="${BASH_REMATCH[1]}"
            expected_args="${BASH_REMATCH[2]}"

            expected_outputs=()
            while [[ $expected_args =~ \"([^\"]*)\"[[:space:]]* ]]; do
                expected_outputs+=("${BASH_REMATCH[1]}")
                expected_args="${expected_args#*\"${BASH_REMATCH[1]}\"}"
            done

            run_test "$TEST_DIR/$filename.nts" "${input}\nsimulate\ndisplay\nexit" "$line_num" "${expected_outputs[@]}"
        fi
    done < "$f"
done

local exit_value=0

if [ $FAILED -gt 0 ]; then
    echo -e "\n${RED}Failed tests:${NC}"
    for test in "${FAILED_TESTS[@]}"; do
        echo -e "  ${RED}✗${NC} $test"
    done
    exit_value=1
else
    echo -e "\n${GREEN}All tests passed! ${NC}"
fi

echo -e "\n${BLUE}========== TEST SUMMARY ==========${NC}"
echo -e "Total:  $TOTAL"
echo -e "${GREEN}Passed: $PASSED${NC}"
echo -e "${RED}Failed: $FAILED${NC}"
echo -e "${BLUE}==================================${NC}"
printf "\e[?25h"

exit $exit_value
