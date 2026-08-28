#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/test/common.sh
source "$SCRIPT_DIR/../test/common.sh"

ROOT=$(project_root)
REQUIRE_LINT_TOOLS=${REQUIRE_LINT_TOOLS:-1}

tool_available() {
  local tool=$1
  if command -v "$tool" >/dev/null 2>&1; then
    return 0
  fi
  if [[ $REQUIRE_LINT_TOOLS == 1 ]]; then
    fail "required lint tool not found: $tool"
  fi
  log "skipping unavailable lint tool: $tool"
  return 1
}

shell_files=()
while IFS= read -r file; do
  shell_files+=("$file")
done < <(
  find "$ROOT/scripts" "$ROOT/rootfs" \
    -type f \( -name '*.sh' -o -path '*/usr/local/bin/*' \) \
    -not -path '*/build/*' \
    -print 2>/dev/null | sort
)

test_shell_files=()
while IFS= read -r file; do
  test_shell_files+=("$file")
done < <(
  find "$ROOT/tests" -type f \( -name '*.sh' -o -name '*.bash' -o -name '*.bats' \) \
    -print 2>/dev/null | sort
)

bats_files=()
while IFS= read -r file; do
  bats_files+=("$file")
done < <(find "$ROOT/tests" -type f -name '*.bats' -print 2>/dev/null | sort)

test_helper_files=()
while IFS= read -r file; do
  test_helper_files+=("$file")
done < <(
  find "$ROOT/tests" -type f \( -name '*.sh' -o -name '*.bash' \) \
    -print 2>/dev/null | sort
)

dockerfiles=()
while IFS= read -r file; do
  dockerfiles+=("$file")
done < <(
  find "$ROOT" -type f -name Dockerfile \
    -not -path '*/.git/*' \
    -not -path '*/build/*' \
    -print 2>/dev/null | sort
)

if ((${#shell_files[@]} == 0)); then
  fail "no shell sources found"
fi

log "checking shell syntax"
for file in "${shell_files[@]}"; do
  bash -n "$file"
done
for file in "${test_helper_files[@]}"; do
  bash -n "$file"
done

if tool_available shellcheck; then
  log "running ShellCheck"
  shellcheck -x "${shell_files[@]}"
  if ((${#test_shell_files[@]} > 0)); then
    shellcheck -x -s bash "${test_shell_files[@]}"
  fi
fi

if tool_available shfmt; then
  log "checking shell formatting"
  shfmt -d -i 2 -ci "${shell_files[@]}"
  if ((${#test_helper_files[@]} > 0)); then
    shfmt -d -i 2 -ci -ln bash "${test_helper_files[@]}"
  fi
  if ((${#bats_files[@]} > 0)); then
    shfmt -d -i 2 -ci -ln bats "${bats_files[@]}"
  fi
fi

if ((${#dockerfiles[@]} > 0)) && tool_available hadolint; then
  log "running Hadolint"
  hadolint "${dockerfiles[@]}"
fi

if [[ -d $ROOT/.github/workflows ]] && tool_available actionlint; then
  log "running actionlint"
  (cd -- "$ROOT" && actionlint)
fi

log "checking whitespace errors"
git -C "$ROOT" diff --check
