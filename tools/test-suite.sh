#!/bin/bash
set -euo pipefail

# Arkavo Node Test Suite
# Automated testing for node, runtime, and smart contracts
# Usage: ./tools/test-suite.sh

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test results tracking
declare -a TEST_RESULTS=()
declare -a TEST_NAMES=()
declare -a TEST_ERRORS=()
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPORT_FILE="$PROJECT_ROOT/tools/test-results.md"

# Node process tracking
NODE_PID=""
NODE_LOG="$PROJECT_ROOT/tools/node-test.log"

# Cleanup handler
cleanup() {
    echo -e "\n${YELLOW}⚠ Cleaning up...${NC}"

    if [ -n "$NODE_PID" ] && kill -0 "$NODE_PID" 2>/dev/null; then
        echo "Stopping node (PID: $NODE_PID)..."
        kill -TERM "$NODE_PID" 2>/dev/null || true
        sleep 2
        if kill -0 "$NODE_PID" 2>/dev/null; then
            kill -KILL "$NODE_PID" 2>/dev/null || true
        fi
    fi

    rm -f "$NODE_LOG"
}

trap cleanup EXIT INT TERM

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_header() {
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}\n"
}

# Test result recording
record_test() {
    local name="$1"
    local result="$2"  # "PASS", "FAIL", "SKIP"
    local error_msg="${3:-}"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    TEST_NAMES+=("$name")
    TEST_RESULTS+=("$result")
    TEST_ERRORS+=("$error_msg")

    case "$result" in
        PASS)
            PASSED_TESTS=$((PASSED_TESTS + 1))
            log_success "$name"
            ;;
        FAIL)
            FAILED_TESTS=$((FAILED_TESTS + 1))
            log_error "$name"
            [ -n "$error_msg" ] && echo -e "  ${RED}Error: $error_msg${NC}"
            ;;
        SKIP)
            SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
            log_warning "$name (skipped)"
            ;;
    esac
}

# Generate markdown report
generate_report() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    cat > "$REPORT_FILE" <<EOF
# Arkavo Node Test Results

**Generated:** $timestamp
**Total Tests:** $TOTAL_TESTS
**Passed:** $PASSED_TESTS
**Failed:** $FAILED_TESTS
**Skipped:** $SKIPPED_TESTS

## Summary

EOF

    if [ $FAILED_TESTS -eq 0 ]; then
        echo "✅ **All tests passed!**" >> "$REPORT_FILE"
    else
        echo "❌ **Some tests failed. See details below.**" >> "$REPORT_FILE"
    fi

    cat >> "$REPORT_FILE" <<EOF

## Test Results

| # | Test Name | Result | Error |
|---|-----------|--------|-------|
EOF

    for i in "${!TEST_NAMES[@]}"; do
        local result="${TEST_RESULTS[$i]}"
        local icon="❓"
        case "$result" in
            PASS) icon="✅" ;;
            FAIL) icon="❌" ;;
            SKIP) icon="⏭️" ;;
        esac

        local error_msg="${TEST_ERRORS[$i]}"
        [ -z "$error_msg" ] && error_msg="-"

        echo "| $((i + 1)) | ${TEST_NAMES[$i]} | $icon $result | $error_msg |" >> "$REPORT_FILE"
    done

    cat >> "$REPORT_FILE" <<EOF

## Environment

- **Platform:** $(uname -s) $(uname -r)
- **Rust:** $(rustc --version 2>/dev/null || echo "Not available")
- **Cargo:** $(cargo --version 2>/dev/null || echo "Not available")
- **Working Directory:** $PROJECT_ROOT

EOF

    log_info "Report generated: $REPORT_FILE"
}

# Print final summary
print_summary() {
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  TEST SUMMARY${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "Total:   $TOTAL_TESTS"
    echo -e "${GREEN}Passed:  $PASSED_TESTS${NC}"
    echo -e "${RED}Failed:  $FAILED_TESTS${NC}"
    echo -e "${YELLOW}Skipped: $SKIPPED_TESTS${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}\n"

    if [ $FAILED_TESTS -eq 0 ]; then
        echo -e "${GREEN}✓ All tests passed!${NC}\n"
        return 0
    else
        echo -e "${RED}✗ Some tests failed. See $REPORT_FILE for details.${NC}\n"
        return 1
    fi
}

# Change to project root
cd "$PROJECT_ROOT"

echo -e "${BLUE}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       Arkavo Node - Automated Test Suite             ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════╝${NC}\n"

log_info "Project root: $PROJECT_ROOT"
log_info "Report will be saved to: $REPORT_FILE"

#==============================================================================
# PHASE 1: Environment Validation
#==============================================================================
log_header "Phase 1: Environment Validation"

# Test 1.1: Rust toolchain
if rustc --version &>/dev/null; then
    RUST_VERSION=$(rustc --version)
    record_test "Rust toolchain available" "PASS"
    log_info "  Version: $RUST_VERSION"
else
    record_test "Rust toolchain available" "FAIL" "rustc not found in PATH"
fi

# Test 1.2: WASM target
if rustup target list --installed 2>/dev/null | grep -q "wasm32-unknown-unknown"; then
    record_test "WebAssembly target installed" "PASS"
else
    record_test "WebAssembly target installed" "FAIL" "wasm32-unknown-unknown not installed"
fi

# Test 1.3: cargo-contract
if cargo-contract --version &>/dev/null; then
    CONTRACT_VERSION=$(cargo-contract --version)
    record_test "Ink! cargo-contract available" "PASS"
    log_info "  Version: $CONTRACT_VERSION"
else
    record_test "Ink! cargo-contract available" "FAIL" "cargo-contract not found"
fi

# Test 1.4: Git connectivity (for dependencies)
if git ls-remote https://github.com/paritytech/polkadot-sdk.git HEAD &>/dev/null; then
    record_test "Git dependency access" "PASS"
else
    record_test "Git dependency access" "FAIL" "Cannot reach GitHub (network issue?)"
fi

#==============================================================================
# PHASE 2: Build Verification
#==============================================================================
log_header "Phase 2: Build Verification"

# Test 2.1: Build node
log_info "Building node (this may take a while)..."
if cargo build --quiet --package arkavo-node 2>&1; then
    record_test "Node binary compilation" "PASS"
else
    record_test "Node binary compilation" "FAIL" "Compilation failed"
fi

# Test 2.2: Build runtime
log_info "Building runtime..."
if cargo build --quiet --package arkavo-runtime 2>&1; then
    record_test "Runtime compilation" "PASS"
else
    record_test "Runtime compilation" "FAIL" "Compilation failed"
fi

# Test 2.3: Verify runtime WASM
WASM_FILE="$PROJECT_ROOT/target/debug/wbuild/arkavo-runtime/arkavo_runtime.wasm"
if [ -f "$WASM_FILE" ]; then
    WASM_SIZE=$(du -h "$WASM_FILE" | cut -f1)
    record_test "Runtime WASM artifact exists" "PASS"
    log_info "  WASM size: $WASM_SIZE"
else
    record_test "Runtime WASM artifact exists" "FAIL" "WASM file not found at $WASM_FILE"
fi

# Test 2.4: Node version check
if [ -f "$PROJECT_ROOT/target/debug/arkavo-node" ]; then
    NODE_VERSION=$("$PROJECT_ROOT/target/debug/arkavo-node" --version 2>&1)
    if echo "$NODE_VERSION" | grep -q "arkavo-node"; then
        record_test "Node version reports correctly" "PASS"
        log_info "  Version: $NODE_VERSION"
    else
        record_test "Node version reports correctly" "FAIL" "Unexpected version output: $NODE_VERSION"
    fi
else
    record_test "Node version reports correctly" "SKIP" "Node binary not available"
fi

# Test 2.5-2.8: Build contracts
log_info "Building smart contracts..."

for contract in access_registry attribute_store policy_engine payment_integration; do
    CONTRACT_DIR="$PROJECT_ROOT/contracts/$contract"

    if [ -d "$CONTRACT_DIR" ]; then
        log_info "  Building $contract..."
        if cargo contract build --quiet --release --manifest-path "$CONTRACT_DIR/Cargo.toml" 2>&1 >/dev/null; then
            record_test "Contract: $contract compilation" "PASS"

            # Verify artifacts (contracts workspace builds to shared target directory)
            CONTRACT_FILE="$PROJECT_ROOT/contracts/target/ink/$contract/$contract.contract"
            METADATA_FILE="$PROJECT_ROOT/contracts/target/ink/$contract/$contract.json"

            if [ -f "$CONTRACT_FILE" ] && [ -f "$METADATA_FILE" ]; then
                record_test "Contract: $contract artifacts" "PASS"
            else
                record_test "Contract: $contract artifacts" "FAIL" "Missing .contract or .json file"
            fi
        else
            record_test "Contract: $contract compilation" "FAIL" "Compilation failed"
            record_test "Contract: $contract artifacts" "SKIP" "Compilation failed"
        fi
    else
        record_test "Contract: $contract compilation" "SKIP" "Directory not found"
        record_test "Contract: $contract artifacts" "SKIP" "Directory not found"
    fi
done

#==============================================================================
# PHASE 3: Runtime Testing
#==============================================================================
log_header "Phase 3: Runtime Testing"

# Test 3.1: Node startup
log_info "Starting node in dev mode..."
if [ -f "$PROJECT_ROOT/target/debug/arkavo-node" ]; then
    "$PROJECT_ROOT/target/debug/arkavo-node" --dev --tmp &> "$NODE_LOG" &
    NODE_PID=$!
    sleep 3

    if kill -0 "$NODE_PID" 2>/dev/null; then
        record_test "Node process starts" "PASS"
        log_info "  Node PID: $NODE_PID"
    else
        record_test "Node process starts" "FAIL" "Process died immediately"
        NODE_PID=""
    fi
else
    record_test "Node process starts" "SKIP" "Node binary not available"
fi

# Test 3.2: Health check
if [ -n "$NODE_PID" ]; then
    log_info "Waiting for node to be ready..."
    READY=false
    for i in {1..30}; do
        if curl -s http://localhost:9944/health &>/dev/null; then
            READY=true
            break
        fi
        sleep 1
    done

    if [ "$READY" = true ]; then
        HEALTH=$(curl -s http://localhost:9944/health)
        record_test "Node health endpoint responsive" "PASS"
        log_info "  Health: $HEALTH"
    else
        record_test "Node health endpoint responsive" "FAIL" "Timeout waiting for health endpoint"
    fi
else
    record_test "Node health endpoint responsive" "SKIP" "Node not running"
fi

# Test 3.3: Block production
if [ -n "$NODE_PID" ] && [ "$READY" = true ]; then
    log_info "Monitoring block production..."

    # Get initial block number
    BLOCK1=$(curl -s -H "Content-Type: application/json" -d '{"id":1, "jsonrpc":"2.0", "method": "chain_getBlock"}' http://localhost:9944 2>/dev/null | grep -o '"number":"0x[0-9a-f]*"' | head -1 | cut -d'"' -f4)

    sleep 15

    # Get block number after waiting
    BLOCK2=$(curl -s -H "Content-Type: application/json" -d '{"id":1, "jsonrpc":"2.0", "method": "chain_getBlock"}' http://localhost:9944 2>/dev/null | grep -o '"number":"0x[0-9a-f]*"' | head -1 | cut -d'"' -f4)

    if [ -n "$BLOCK1" ] && [ -n "$BLOCK2" ] && [ "$BLOCK2" != "$BLOCK1" ]; then
        BLOCK1_DEC=$((16#${BLOCK1#0x}))
        BLOCK2_DEC=$((16#${BLOCK2#0x}))
        record_test "Block production active" "PASS"
        log_info "  Block height: $BLOCK1_DEC → $BLOCK2_DEC"
    else
        record_test "Block production active" "FAIL" "No new blocks produced in 15 seconds"
    fi
else
    record_test "Block production active" "SKIP" "Node not ready"
fi

#==============================================================================
# PHASE 4: Integration Testing
#==============================================================================
log_header "Phase 4: Integration Testing"

# Test 4.1: Build deployer
log_info "Building deployer tool..."
if cargo build --quiet --manifest-path "$PROJECT_ROOT/tools/deployer/Cargo.toml" 2>&1 >/dev/null; then
    record_test "Deployer tool compilation" "PASS"
else
    record_test "Deployer tool compilation" "FAIL" "Compilation failed"
fi

# Test 4.2: Deploy contracts
if [ -f "$PROJECT_ROOT/tools/deployer/target/debug/deployer" ] && [ -n "$NODE_PID" ] && [ "$READY" = true ]; then
    log_info "Deploying contracts with deployer tool..."

    DEPLOY_OUTPUT=$("$PROJECT_ROOT/tools/deployer/target/debug/deployer" --endpoint ws://127.0.0.1:9944 deploy-all --account alice 2>&1)
    DEPLOY_EXIT=$?

    if [ $DEPLOY_EXIT -eq 0 ]; then
        record_test "Contract deployment (all contracts)" "PASS"

        # Extract contract addresses if present
        if echo "$DEPLOY_OUTPUT" | grep -q "Contract address"; then
            log_info "  Deployment successful, contracts instantiated"
        fi
    else
        record_test "Contract deployment (all contracts)" "FAIL" "Deployer exited with code $DEPLOY_EXIT"
        echo "$DEPLOY_OUTPUT" | head -20
    fi
else
    if [ ! -f "$PROJECT_ROOT/tools/deployer/target/debug/deployer" ]; then
        record_test "Contract deployment (all contracts)" "SKIP" "Deployer not available"
    elif [ -z "$NODE_PID" ] || [ "$READY" != true ]; then
        record_test "Contract deployment (all contracts)" "SKIP" "Node not running"
    fi
fi

# Test 4.3-4.7: Access Registry CRUD Cycle
if [ -n "$NODE_PID" ] && [ "$READY" = true ]; then
    CRUD_CONTRACT_FILE="$PROJECT_ROOT/contracts/target/ink/access_registry/access_registry.contract"

    if [ -f "$CRUD_CONTRACT_FILE" ]; then
        log_info "Starting Access Registry CRUD test cycle..."

        # 4.3: Deploy contract (Alice becomes owner)
        log_info "Deploying access_registry contract..."
        INSTANTIATE_OUTPUT=$(cargo contract instantiate \
            --suri //Alice \
            --url ws://127.0.0.1:9944 \
            --constructor new \
            --output-json \
            -x \
            -y \
            "$CRUD_CONTRACT_FILE" 2>&1) || true

        CONTRACT_ADDR=$(echo "$INSTANTIATE_OUTPUT" | grep -o '"contract":"[^"]*"' | head -1 | cut -d'"' -f4 || true)

        # Check for pallet-revive compatibility error (ink! 6.0 requires pallet-revive, not pallet-contracts)
        if echo "$INSTANTIATE_OUTPUT" | grep -q "ReviveApi_instantiate is not found"; then
            log_warning "Runtime uses pallet-contracts but cargo-contract 6.0 requires pallet-revive"
            log_warning "See GitHub issue: https://github.com/arkavo-org/arkavo-node/issues/11"
            record_test "CRUD: Deploy access_registry" "SKIP" "pallet-revive not available (runtime uses pallet-contracts)"
            record_test "CRUD: Grant entitlement" "SKIP" "pallet-revive not available"
            record_test "CRUD: Get entitlement" "SKIP" "pallet-revive not available"
            record_test "CRUD: Has entitlement check" "SKIP" "pallet-revive not available"
            record_test "CRUD: Revoke entitlement" "SKIP" "pallet-revive not available"
        elif [ -n "$CONTRACT_ADDR" ]; then
            record_test "CRUD: Deploy access_registry" "PASS"
            log_info "  Contract address: $CONTRACT_ADDR"

            # Use Bob as target account (20-byte hex address)
            BOB_ADDR="0x8eaf04151687736326c9fea17e25fc5287613693"

            # 4.4: Grant entitlement (Alice grants Bob Premium level)
            log_info "Granting Premium entitlement to Bob..."
            GRANT_OUTPUT=$(cargo contract call \
                --suri //Alice \
                --url ws://127.0.0.1:9944 \
                --contract "$CONTRACT_ADDR" \
                --message grant_entitlement \
                --args "$BOB_ADDR" "Premium" \
                --output-json \
                -x \
                -y \
                "$CRUD_CONTRACT_FILE" 2>&1)
            GRANT_EXIT=$?

            if [ $GRANT_EXIT -eq 0 ] && echo "$GRANT_OUTPUT" | grep -qE '"Ok"|"success"'; then
                record_test "CRUD: Grant entitlement" "PASS"
            else
                record_test "CRUD: Grant entitlement" "FAIL" "Grant failed"
            fi

            # 4.5: Get entitlement (verify Bob has Premium)
            log_info "Querying Bob's entitlement..."
            GET_OUTPUT=$(cargo contract call \
                --suri //Alice \
                --url ws://127.0.0.1:9944 \
                --contract "$CONTRACT_ADDR" \
                --message get_entitlement \
                --args "$BOB_ADDR" \
                --output-json \
                "$CRUD_CONTRACT_FILE" 2>&1)

            if echo "$GET_OUTPUT" | grep -qi "Premium"; then
                record_test "CRUD: Get entitlement" "PASS"
                log_info "  Result: Premium (as expected)"
            else
                record_test "CRUD: Get entitlement" "FAIL" "Expected Premium"
            fi

            # 4.6: Has entitlement (verify Bob has at least Basic)
            log_info "Checking has_entitlement(Bob, Basic)..."
            HAS_OUTPUT=$(cargo contract call \
                --suri //Alice \
                --url ws://127.0.0.1:9944 \
                --contract "$CONTRACT_ADDR" \
                --message has_entitlement \
                --args "$BOB_ADDR" "Basic" \
                --output-json \
                "$CRUD_CONTRACT_FILE" 2>&1)

            if echo "$HAS_OUTPUT" | grep -qi "true"; then
                record_test "CRUD: Has entitlement check" "PASS"
                log_info "  Result: true (Premium >= Basic)"
            else
                record_test "CRUD: Has entitlement check" "FAIL" "Expected true"
            fi

            # 4.7: Revoke entitlement
            log_info "Revoking Bob's entitlement..."
            REVOKE_OUTPUT=$(cargo contract call \
                --suri //Alice \
                --url ws://127.0.0.1:9944 \
                --contract "$CONTRACT_ADDR" \
                --message revoke_entitlement \
                --args "$BOB_ADDR" \
                --output-json \
                -x \
                -y \
                "$CRUD_CONTRACT_FILE" 2>&1)
            REVOKE_EXIT=$?

            if [ $REVOKE_EXIT -eq 0 ]; then
                # Verify revocation by querying again
                VERIFY_OUTPUT=$(cargo contract call \
                    --suri //Alice \
                    --url ws://127.0.0.1:9944 \
                    --contract "$CONTRACT_ADDR" \
                    --message get_entitlement \
                    --args "$BOB_ADDR" \
                    --output-json \
                    "$CRUD_CONTRACT_FILE" 2>&1)

                if echo "$VERIFY_OUTPUT" | grep -qi "None"; then
                    record_test "CRUD: Revoke entitlement" "PASS"
                    log_info "  Bob's entitlement revoked successfully"
                else
                    record_test "CRUD: Revoke entitlement" "FAIL" "Entitlement not cleared"
                fi
            else
                record_test "CRUD: Revoke entitlement" "FAIL" "Revoke call failed"
            fi
        else
            record_test "CRUD: Deploy access_registry" "FAIL" "No contract address"
            record_test "CRUD: Grant entitlement" "SKIP" "Deploy failed"
            record_test "CRUD: Get entitlement" "SKIP" "Deploy failed"
            record_test "CRUD: Has entitlement check" "SKIP" "Deploy failed"
            record_test "CRUD: Revoke entitlement" "SKIP" "Deploy failed"
        fi
    else
        record_test "CRUD: Deploy access_registry" "SKIP" "Contract not built"
        record_test "CRUD: Grant entitlement" "SKIP" "Contract not built"
        record_test "CRUD: Get entitlement" "SKIP" "Contract not built"
        record_test "CRUD: Has entitlement check" "SKIP" "Contract not built"
        record_test "CRUD: Revoke entitlement" "SKIP" "Contract not built"
    fi
else
    record_test "CRUD: Deploy access_registry" "SKIP" "Node not running"
    record_test "CRUD: Grant entitlement" "SKIP" "Node not running"
    record_test "CRUD: Get entitlement" "SKIP" "Node not running"
    record_test "CRUD: Has entitlement check" "SKIP" "Node not running"
    record_test "CRUD: Revoke entitlement" "SKIP" "Node not running"
fi

#==============================================================================
# PHASE 5: Cleanup & Reporting
#==============================================================================
log_header "Phase 5: Cleanup & Reporting"

# Generate report
generate_report

# Print summary
print_summary
EXIT_CODE=$?

exit $EXIT_CODE
