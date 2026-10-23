#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/test/common.sh
source "$SCRIPT_DIR/common.sh"

ROOT=$(project_root)
IMAGE=${1:-${IMAGE:-}}
DOCKER_BIN=${DOCKER_BIN:-docker}
CURL_BIN=${CURL_BIN:-curl}
[[ -n $IMAGE ]] || fail "usage: $0 IMAGE (or set IMAGE)"
require_command "$DOCKER_BIN"
require_command "$CURL_BIN"
require_command python3
"$DOCKER_BIN" compose version >/dev/null

PROJECT="nginx-php-fpm-example-${PPID}-${RANDOM}"
export IMAGE HTTP_PORT=0

compose() {
  "$DOCKER_BIN" compose \
    --file "$ROOT/examples/compose/compose.yaml" \
    --project-name "$PROJECT" "$@"
}

cleanup() {
  local exit_status=$?
  if ((exit_status != 0)); then
    compose logs >&2 || true
  fi
  compose down --remove-orphans >/dev/null 2>&1 || true
  return "$exit_status"
}
trap cleanup EXIT

log "starting the checked-in Compose example against $IMAGE"
compose config --quiet
compose up --detach --wait --wait-timeout 60
address=$(compose port web 8080)
[[ $address == 127.0.0.1:* ]] || fail "example must bind only to localhost: $address"
url="http://${address}"

log "checking PHP health, front-controller routing, and static content"
"$CURL_BIN" --fail --silent --show-error "$url/healthz" | grep -Fq ok
body=$("$CURL_BIN" --fail --silent --show-error "$url/hello?example=1")
python3 -c 'import json, sys; data = json.load(sys.stdin); assert data["path"] == "/hello"; assert data["message"] == "Your PHP application is running."' <<<"$body"
static=$("$CURL_BIN" --fail --silent --show-error "$url/example.txt")
[[ $static == 'Static files are served by nginx.' ]] || fail "static example was not served"

log "checking the example's rootless identity and read-only filesystems"
container=$(compose ps --quiet web)
[[ $("$DOCKER_BIN" exec "$container" id -u) == 82 ]] || fail "example must run as UID 82"
[[ $("$DOCKER_BIN" exec "$container" id -g) == 82 ]] || fail "example must run as GID 82"
[[ $("$DOCKER_BIN" inspect --format '{{.HostConfig.ReadonlyRootfs}}' "$container") == true ]] || fail "example root filesystem must be read-only"
mount_rw=$("$DOCKER_BIN" inspect --format '{{range .Mounts}}{{if eq .Destination "/srv/app/public"}}{{.RW}}{{end}}{{end}}' "$container")
[[ $mount_rw == false ]] || fail "example application mount must be read-only"
log "Compose application example passed"
