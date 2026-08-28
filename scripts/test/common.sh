#!/usr/bin/env bash

set -Eeuo pipefail

log() {
  printf '[test] %s\n' "$*" >&2
}

fail() {
  printf '[test] ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  local command_name=$1
  command -v "$command_name" >/dev/null 2>&1 || fail "required command not found: $command_name"
}

project_root() {
  local source_dir
  source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
  cd -- "$source_dir/../.." && pwd
}

wait_until() {
  local timeout_seconds=$1
  local description=$2
  shift 2

  local deadline=$((SECONDS + timeout_seconds))
  until "$@"; do
    if ((SECONDS >= deadline)); then
      printf '[test] ERROR: timed out waiting for %s\n' "$description" >&2
      return 1
    fi
    sleep 0.25
  done
}
