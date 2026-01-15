#!/usr/bin/env bash
# tests/run_tests.sh - Test runner for claude-jail
# Usage: ./tests/run_tests.sh [unit|integration|all] [test_file.bats]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BATS="$SCRIPT_DIR/test_helper/bats-core/bin/bats"

# Ensure bats is available
if [[ ! -x "$BATS" ]]; then
    echo "Error: bats-core not found. Run: git submodule update --init --recursive" >&2
    exit 1
fi

# Parse arguments
suite="${1:-all}"
specific_test="${2:-}"

run_unit_tests() {
    echo "Running unit tests..."
    "$BATS" "$SCRIPT_DIR/unit/"*.bats
}

run_integration_tests() {
    echo "Running integration tests..."
    "$BATS" "$SCRIPT_DIR/integration/"*.bats
}

run_specific_test() {
    echo "Running test: $1"
    "$BATS" "$1"
}

case "$suite" in
    unit)
        if [[ -n "$specific_test" ]]; then
            run_specific_test "$SCRIPT_DIR/unit/$specific_test"
        else
            run_unit_tests
        fi
        ;;
    integration)
        if [[ -n "$specific_test" ]]; then
            run_specific_test "$SCRIPT_DIR/integration/$specific_test"
        else
            run_integration_tests
        fi
        ;;
    all)
        run_unit_tests
        echo ""
        run_integration_tests
        ;;
    *.bats)
        # Allow running a specific test file directly
        run_specific_test "$suite"
        ;;
    *)
        echo "Usage: $0 [unit|integration|all] [test_file.bats]"
        echo ""
        echo "Examples:"
        echo "  $0              # Run all tests"
        echo "  $0 unit         # Run only unit tests"
        echo "  $0 integration  # Run only integration tests"
        echo "  $0 unit bwrap.bats  # Run specific unit test file"
        exit 1
        ;;
esac

echo ""
echo "All tests passed!"
