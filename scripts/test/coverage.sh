#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/test/common.sh
source "$SCRIPT_DIR/common.sh"

ROOT=$(project_root)
KCOV_BIN=${KCOV_BIN:-kcov}
# Legacy macOS Bash needs DEBUG to keep trace output separate; the Linux CI
# runner explicitly selects Kcov's PS4 method with modern BASH_XTRACEFD support.
KCOV_BASH_METHOD=${KCOV_BASH_METHOD:-DEBUG}
COVERAGE_DIR=${COVERAGE_DIR:-"$ROOT/build/coverage"}
COVERAGE_THRESHOLD=${COVERAGE_THRESHOLD:-100}
INCLUDE_PATH=${COVERAGE_INCLUDE_PATH:-"$ROOT/rootfs/usr/local/lib/nginx-php-fpm"}
COVERAGE_HARNESS=${COVERAGE_HARNESS:-"$ROOT/tests/coverage/config-coverage.sh"}

require_command "$KCOV_BIN"

case "$KCOV_BASH_METHOD" in
  DEBUG | PS4) ;;
  *) fail "KCOV_BASH_METHOD must be DEBUG or PS4" ;;
esac

if [[ ! $COVERAGE_THRESHOLD =~ ^[0-9]+(\.[0-9]+)?$ ]] ||
  ! awk -v threshold="$COVERAGE_THRESHOLD" 'BEGIN { exit !(threshold >= 0 && threshold <= 100) }'; then
  fail "COVERAGE_THRESHOLD must be a number between 0 and 100"
fi
[[ -d $INCLUDE_PATH ]] || fail "coverage include path does not exist: $INCLUDE_PATH"
[[ -x $COVERAGE_HARNESS ]] || fail "coverage harness is missing or not executable: $COVERAGE_HARNESS"

mkdir -p -- "$COVERAGE_DIR"
KCOV_OUTPUT=$(mktemp -d "${TMPDIR:-/tmp}/nginx-php-fpm-kcov.XXXXXX")
cleanup_coverage_output() {
  rm -rf -- "$KCOV_OUTPUT"
}
trap cleanup_coverage_output EXIT INT TERM

log "collecting coverage for first-party configuration logic"
"$KCOV_BIN" \
  --clean \
  --bash-method="$KCOV_BASH_METHOD" \
  --include-path="$INCLUDE_PATH" \
  --exclude-pattern=/tests/,/templates/ \
  "$KCOV_OUTPUT" \
  "$COVERAGE_HARNESS"

coverage_xml=$(find "$KCOV_OUTPUT" -type f -name cobertura.xml -print | head -n 1)
coverage_html=$(find "$KCOV_OUTPUT" -type f -name index.html -print | head -n 1)
[[ -n $coverage_xml ]] || fail "kcov did not produce cobertura.xml"
[[ -n $coverage_html ]] || fail "kcov did not produce an HTML report"
grep -q 'config\.sh' "$coverage_xml" || fail "coverage report does not contain config.sh"

cp -- "$coverage_xml" "$COVERAGE_DIR/cobertura.xml"
mkdir -p -- "$COVERAGE_DIR/html"
cp -R -- "$(dirname -- "$coverage_html")/." "$COVERAGE_DIR/html/"

line_rate=$(sed -n 's/.*line-rate="\([0-9.]*\)".*/\1/p' "$coverage_xml" | head -n 1)
[[ -n $line_rate ]] || fail "could not read line-rate from cobertura.xml"

if ! awk -v rate="$line_rate" -v threshold="$COVERAGE_THRESHOLD" \
  'BEGIN { exit !((rate * 100) + 0.000001 >= threshold) }'; then
  fail "line coverage $(awk -v rate="$line_rate" 'BEGIN { printf "%.2f", rate * 100 }')% is below ${COVERAGE_THRESHOLD}%"
fi

log "line coverage: $(awk -v rate="$line_rate" 'BEGIN { printf "%.2f", rate * 100 }')%"
log "Cobertura: $COVERAGE_DIR/cobertura.xml"
log "HTML: $COVERAGE_DIR/html/index.html"
