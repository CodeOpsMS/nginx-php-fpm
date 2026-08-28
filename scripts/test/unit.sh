#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/test/common.sh
source "$SCRIPT_DIR/common.sh"

ROOT=$(project_root)
RESULT_DIR=${TEST_RESULT_DIR:-"$ROOT/build/test-results"}
BATS_BIN=${BATS_BIN:-bats}
BATS_JUNIT=${BATS_JUNIT:-0}

require_command "$BATS_BIN"
mkdir -p -- "$RESULT_DIR"

test_paths=("$ROOT/tests/unit" "$ROOT/tests/contract")
bats_args=(--formatter tap)

if [[ $BATS_JUNIT == 1 ]] && "$BATS_BIN" --help 2>&1 | grep -q -- '--report-formatter'; then
  bats_args+=(--report-formatter junit --output "$RESULT_DIR")
fi

log "running Bats unit and source-contract tests"
set -o pipefail
"$BATS_BIN" "${bats_args[@]}" "${test_paths[@]}" | tee "$RESULT_DIR/bats.tap"
