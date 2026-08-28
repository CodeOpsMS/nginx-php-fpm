#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/test/common.sh
source "$SCRIPT_DIR/common.sh"

ROOT=$(project_root)
IMAGE=${1:-${IMAGE:-}}
DOCKER_BIN=${DOCKER_BIN:-docker}
CURL_BIN=${CURL_BIN:-curl}
EXPECTED_ARCH=${EXPECTED_ARCH:-}
EXPECTED_REVISION=${EXPECTED_REVISION:-}
REQUIRE_BUILD_METADATA=${REQUIRE_BUILD_METADATA:-0}

dockerfile_arg() {
  local name=$1
  local fallback=$2
  local value
  value=$(sed -n "s/^ARG ${name}=//p" "$ROOT/Dockerfile" | head -n 1)
  printf '%s\n' "${value:-$fallback}"
}

php_base_tag=$(
  sed -n 's/^FROM php:\([^@[:space:]]*\)@[^[:space:]]* AS php-base$/\1/p' \
    "$ROOT/Dockerfile" | head -n 1
)
detected_php_version=${php_base_tag%%-fpm-alpine*}
detected_alpine_series=${php_base_tag##*-fpm-alpine}
redis_pin=$(
  sed -n 's/.*"phpredis\/phpredis"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    "$ROOT/container/extensions/composer.json" | head -n 1
)

EXPECTED_PHP_VERSION=${EXPECTED_PHP_VERSION:-${detected_php_version:-8.5.10}}
EXPECTED_NGINX_VERSION=${EXPECTED_NGINX_VERSION:-$(dockerfile_arg NGINX_VERSION 1.30.4)}
EXPECTED_ALPINE_SERIES=${EXPECTED_ALPINE_SERIES:-${detected_alpine_series:-3.24}}
EXPECTED_REDIS_SERIES=${EXPECTED_REDIS_SERIES:-${redis_pin:-6.3.0}}

[[ -n $IMAGE ]] || fail "usage: $0 IMAGE (or set IMAGE)"
require_command "$DOCKER_BIN"
require_command "$CURL_BIN"

WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/nginx-php-fpm-integration.XXXXXX")
CONTAINERS=()
RUN_PREFIX="nginx-php-fpm-test-${PPID}-${RANDOM}"

cleanup() {
  local container
  for container in "${CONTAINERS[@]}"; do
    "$DOCKER_BIN" rm -f "$container" >/dev/null 2>&1 || true
  done
  rm -rf -- "$WORK_DIR"
}
trap cleanup EXIT INT TERM

assert_equal() {
  local expected=$1
  local actual=$2
  local description=$3
  [[ $actual == "$expected" ]] || fail "$description: expected <$expected>, got <$actual>"
}

assert_contains() {
  local value=$1
  local expected=$2
  local description=$3
  [[ $value == *"$expected"* ]] || fail "$description: expected output to contain <$expected>"
}

image_label() {
  local label_name=$1
  "$DOCKER_BIN" image inspect \
    --format "{{index .Config.Labels \"$label_name\"}}" \
    "$IMAGE"
}

http_is_ready() {
  local url=$1
  "$CURL_BIN" --fail --silent --show-error --max-time 2 "$url/healthz" >/dev/null 2>&1
}

container_url() {
  local container=$1
  local binding
  binding=$("$DOCKER_BIN" port "$container" 8080/tcp | head -n 1)
  [[ -n $binding ]] || fail "container $container has no published port 8080"
  printf 'http://127.0.0.1:%s\n' "${binding##*:}"
}

start_container() {
  local name=$1
  shift
  CONTAINERS+=("$name")
  "$DOCKER_BIN" run -d \
    --name "$name" \
    --read-only \
    --tmpfs /tmp:rw,noexec,nosuid,nodev,mode=1777 \
    --cap-drop ALL \
    --security-opt no-new-privileges \
    -p 127.0.0.1::8080 \
    "$@" \
    "$IMAGE" >/dev/null
}

container_has_stopped() {
  local container=$1
  local running

  if ! running=$("$DOCKER_BIN" inspect --format '{{.State.Running}}' "$container" 2>/dev/null); then
    return 0
  fi
  [[ $running != true ]]
}

assert_managed_service_failure() {
  local service=$1
  local signal=$2
  shift 2

  local container="$RUN_PREFIX-failure-$service"
  local exit_status

  log "checking supervisor failure propagation for $service ($signal)"
  start_container "$container"
  wait_for_container_http "$container" >/dev/null

  # Positional parameters and command substitution are intentionally evaluated
  # by the container shell.
  # shellcheck disable=SC2016
  "$DOCKER_BIN" exec "$container" sh -ec '
    signal=$1
    shift
    set -- $(pidof "$@" 2>/dev/null)
    [ "$#" -gt 0 ]
    kill "-${signal}" "$@"
  ' sh "$signal" "$@" || true

  wait_until 15 "container exit after $service failure" container_has_stopped "$container"
  exit_status=$("$DOCKER_BIN" inspect --format '{{.State.ExitCode}}' "$container")
  [[ $exit_status -ne 0 ]] || fail "supervisor returned success after $service died unexpectedly"
}

wait_for_container_http() {
  local container=$1
  local url
  url=$(container_url "$container")
  if ! wait_until 30 "healthy HTTP endpoint for $container" http_is_ready "$url"; then
    "$DOCKER_BIN" logs "$container" >&2 || true
    return 1
  fi
  printf '%s\n' "$url"
}

log "checking image metadata and native architecture"
image_arch=$("$DOCKER_BIN" image inspect --format '{{.Architecture}}' "$IMAGE")
case "$image_arch" in
  amd64 | arm64) ;;
  *) fail "unsupported image architecture: $image_arch" ;;
esac
if [[ -n $EXPECTED_ARCH ]]; then
  assert_equal "$EXPECTED_ARCH" "$image_arch" "native image architecture"
fi

image_user=$("$DOCKER_BIN" image inspect --format '{{.Config.User}}' "$IMAGE")
case "$image_user" in
  82 | 82:82 | www-data) ;;
  *) fail "image must declare fixed www-data/82 runtime user, got <$image_user>" ;;
esac

exposed_ports=$("$DOCKER_BIN" image inspect --format '{{json .Config.ExposedPorts}}' "$IMAGE")
assert_equal '{"8080/tcp":{}}' "$exposed_ports" "exclusive exposed port metadata"

healthcheck=$("$DOCKER_BIN" image inspect --format '{{json .Config.Healthcheck.Test}}' "$IMAGE")
assert_contains "$healthcheck" '/usr/local/bin/healthcheck' "image healthcheck"

log "checking required OCI image labels"
expected_image_version=$(tr -d '[:space:]' <"$ROOT/VERSION")
assert_equal 'nginx-php-fpm' "$(image_label org.opencontainers.image.title)" "OCI title label"
assert_equal \
  'https://github.com/CodeOpsMS/nginx-php-fpm' \
  "$(image_label org.opencontainers.image.source)" \
  "OCI source label"
assert_equal \
  'https://github.com/CodeOpsMS/nginx-php-fpm#readme' \
  "$(image_label org.opencontainers.image.documentation)" \
  "OCI documentation label"
assert_equal \
  'GPL-3.0-or-later' \
  "$(image_label org.opencontainers.image.licenses)" \
  "OCI license label"
assert_equal \
  "$expected_image_version" \
  "$(image_label org.opencontainers.image.version)" \
  "OCI version label"

image_revision=$(image_label org.opencontainers.image.revision)
if [[ $image_revision != unknown && ! $image_revision =~ ^[0-9a-f]{40,64}$ ]]; then
  fail "OCI revision label must be a Git commit or 'unknown', got <$image_revision>"
fi
image_created=$(image_label org.opencontainers.image.created)
if [[ $image_created != unknown && ! $image_created =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
  fail "OCI created label must be UTC RFC 3339 or 'unknown', got <$image_created>"
fi
if [[ -n $EXPECTED_REVISION ]]; then
  assert_equal "$EXPECTED_REVISION" "$image_revision" "OCI revision label"
fi
case "$REQUIRE_BUILD_METADATA" in
  0) ;;
  1)
    [[ $image_revision != unknown ]] || fail "OCI revision label must not be 'unknown'"
    [[ $image_created != unknown ]] || fail "OCI created label must not be 'unknown'"
    ;;
  *) fail "REQUIRE_BUILD_METADATA must be 0 or 1, got <$REQUIRE_BUILD_METADATA>" ;;
esac

log "checking runtime versions and PHP extensions"
php_version=$("$DOCKER_BIN" run --rm --entrypoint php "$IMAGE" -r 'echo PHP_VERSION;')
assert_equal "$EXPECTED_PHP_VERSION" "$php_version" "PHP version"
php_version_id=$("$DOCKER_BIN" run --rm --entrypoint php "$IMAGE" -r 'echo PHP_VERSION_ID;')
[[ $php_version_id =~ ^805[0-9]{2}$ ]] || fail "expected PHP 8.5.x, got PHP_VERSION_ID=$php_version_id"

nginx_version=$("$DOCKER_BIN" run --rm --entrypoint nginx "$IMAGE" -v 2>&1)
assert_contains "$nginx_version" "nginx/$EXPECTED_NGINX_VERSION" "nginx version"

alpine_version=$("$DOCKER_BIN" run --rm --entrypoint cat "$IMAGE" /etc/alpine-release)
case "$alpine_version" in
  "$EXPECTED_ALPINE_SERIES".*) ;;
  *) fail "expected Alpine $EXPECTED_ALPINE_SERIES.x, got $alpine_version" ;;
esac

modules=$("$DOCKER_BIN" run --rm --entrypoint php "$IMAGE" -m)
expected_modules=(
  bcmath
  exif
  gd
  intl
  mbstring
  mysqli
  pdo_mysql
  pdo_pgsql
  redis
  soap
  'Zend OPcache'
  zip
)
for module in "${expected_modules[@]}"; do
  if ! grep -Fxiq -- "$module" <<<"$modules"; then
    fail "required PHP module is missing: $module"
  fi
done
if grep -Eiq '^(xdebug|mongodb)$' <<<"$modules"; then
  fail "development-only PHP module found"
fi

redis_info=$("$DOCKER_BIN" run --rm --entrypoint php "$IMAGE" --ri redis)
assert_contains "$redis_info" "$EXPECTED_REDIS_SERIES" "Redis extension version"

log "checking minimal runtime contents"
# The single-quoted program is intentionally evaluated by the container shell.
# shellcheck disable=SC2016
"$DOCKER_BIN" run --rm --user 0:0 --entrypoint sh "$IMAGE" -ec '
  for command_name in cc gcc g++ make autoconf automake phpize php-config git composer certbot; do
    if command -v "$command_name" >/dev/null 2>&1; then
      echo "unexpected runtime command: $command_name" >&2
      exit 1
    fi
  done
  if [ -e /usr/local/include/php ]; then
    echo "unexpected PHP build headers: /usr/local/include/php" >&2
    exit 1
  fi
  unexpected=$(find / -xdev \( -perm -4000 -o -perm -2000 \) -type f -print 2>/dev/null || true)
  if [ -n "$unexpected" ]; then
    echo "unexpected SUID/SGID files:" >&2
    echo "$unexpected" >&2
    exit 1
  fi
'

log "checking default rootless, read-only startup and PHP-backed health"
default_container="$RUN_PREFIX-default"
start_container "$default_container"
default_url=$(wait_for_container_http "$default_container")

runtime_uid=$("$DOCKER_BIN" exec "$default_container" id -u)
runtime_gid=$("$DOCKER_BIN" exec "$default_container" id -g)
assert_equal 82 "$runtime_uid" "runtime uid"
assert_equal 82 "$runtime_gid" "runtime gid"

readonly_root=$("$DOCKER_BIN" inspect --format '{{.HostConfig.ReadonlyRootfs}}' "$default_container")
assert_equal true "$readonly_root" "read-only root filesystem"
"$DOCKER_BIN" exec "$default_container" sh -ec 'test -w /tmp; test -S /tmp/nginx-php-fpm/run/php-fpm.sock'

health_body=$("$CURL_BIN" --fail --silent --show-error "$default_url/healthz")
assert_contains "$health_body" 'ok' "PHP-backed health response"
"$CURL_BIN" --fail --silent --show-error "$default_url/" >/dev/null

default_headers=$("$CURL_BIN" --silent --show-error --dump-header - --output /dev/null "$default_url/healthz")
if grep -Eiq '^Server:[[:space:]]+nginx/[0-9]' <<<"$default_headers"; then
  fail "nginx version is exposed in HTTP headers"
fi
if grep -Eiq '^X-Powered-By:' <<<"$default_headers"; then
  fail "PHP version header is exposed"
fi

log "checking document root, front controller, environment and drop-in precedence"
mkdir -p "$WORK_DIR/app" "$WORK_DIR/dropins"
chmod 0755 "$WORK_DIR" "$WORK_DIR/app" "$WORK_DIR/dropins"
# PHP variables must remain literal while this fixture is generated.
# shellcheck disable=SC2016
printf '%s\n' \
  '<?php' \
  'header("Content-Type: text/plain");' \
  'echo "php-ok\n";' \
  'echo "uri=" . $_SERVER["REQUEST_URI"] . "\n";' \
  'echo "memory=" . ini_get("memory_limit") . "\n";' \
  'echo "upload=" . ini_get("upload_max_filesize") . "\n";' \
  'echo "post=" . ini_get("post_max_size") . "\n";' \
  'echo "execution=" . ini_get("max_execution_time") . "\n";' \
  'echo "display=" . ini_get("display_errors") . "\n";' \
  'echo "opcache=" . ini_get("opcache.enable") . "\n";' \
  'echo "timestamps=" . ini_get("opcache.validate_timestamps") . "\n";' \
  'echo "sentinel=" . getenv("CONTRACT_SENTINEL") . "\n";' \
  'echo "fpm-dropin=" . getenv("CONTRACT_FPM_DROPIN") . "\n";' \
  >"$WORK_DIR/app/index.php"
printf '%s\n' 'never-public' >"$WORK_DIR/app/.env"
printf '%s\n' '<?php echo "hidden-php-executed";' >"$WORK_DIR/app/.hidden.php"
printf '%s\n' 'static-contract-ok' >"$WORK_DIR/app/asset.txt"
mkdir -p "$WORK_DIR/app/.git"
printf '%s\n' 'never-public' >"$WORK_DIR/app/.git/config"
# nginx variables in these fixtures are evaluated by nginx, not this shell.
# shellcheck disable=SC2016
printf '%s\n' \
  'map $http_x_contract $contract_http_value {' \
  '  default missing;' \
  '  contract http-dropin;' \
  '}' \
  >"$WORK_DIR/dropins/10-contract-http.conf"
# shellcheck disable=SC2016
printf '%s\n' \
  'add_header X-Contract-Dropin "loaded" always;' \
  'add_header X-Contract-Http $contract_http_value always;' \
  >"$WORK_DIR/dropins/90-contract-server.conf"
printf '%s\n' 'memory_limit=111M' >"$WORK_DIR/dropins/zz-contract.ini"
printf '%s\n' \
  '[www]' \
  'env[CONTRACT_FPM_DROPIN] = fpm-dropin' \
  >"$WORK_DIR/dropins/zz-contract-fpm.conf"
chmod -R a+rX "$WORK_DIR/app" "$WORK_DIR/dropins"

contract_container="$RUN_PREFIX-contract"
start_container "$contract_container" \
  --mount "type=bind,src=$WORK_DIR/app,dst=/srv/contract-app,readonly" \
  --mount "type=bind,src=$WORK_DIR/dropins/10-contract-http.conf,dst=/etc/nginx/conf.d/10-contract-http.conf,readonly" \
  --mount "type=bind,src=$WORK_DIR/dropins/90-contract-server.conf,dst=/etc/nginx/server.d/90-contract-server.conf,readonly" \
  --mount "type=bind,src=$WORK_DIR/dropins/zz-contract.ini,dst=/etc/php/conf.d/zz-contract.ini,readonly" \
  --mount "type=bind,src=$WORK_DIR/dropins/zz-contract-fpm.conf,dst=/etc/php-fpm.d/zz-contract-fpm.conf,readonly" \
  -e DOCUMENT_ROOT=/srv/contract-app \
  -e TZ=Europe/Berlin \
  -e PHP_MEMORY_LIMIT=96M \
  -e PHP_UPLOAD_MAX_FILESIZE=12M \
  -e PHP_POST_MAX_SIZE=16M \
  -e PHP_MAX_EXECUTION_TIME=9 \
  -e PHP_DISPLAY_ERRORS=1 \
  -e PHP_OPCACHE_ENABLE=0 \
  -e PHP_OPCACHE_VALIDATE_TIMESTAMPS=1 \
  -e NGINX_CLIENT_MAX_BODY_SIZE=17m \
  -e CONTRACT_SENTINEL=visible-to-php
contract_url=$(wait_for_container_http "$contract_container")

contract_headers="$WORK_DIR/contract.headers"
contract_body="$WORK_DIR/contract.body"
"$CURL_BIN" --fail --silent --show-error \
  --header 'X-Contract: contract' \
  --dump-header "$contract_headers" \
  --output "$contract_body" \
  "$contract_url/deep/front-controller?answer=42"

body=$(<"$contract_body")
assert_contains "$body" 'php-ok' "PHP execution"
assert_contains "$body" 'uri=/deep/front-controller?answer=42' "front controller request URI"
assert_contains "$body" 'memory=111M' "PHP drop-in precedence over environment"
assert_contains "$body" 'upload=12M' "upload_max_filesize override"
assert_contains "$body" 'post=16M' "post_max_size override"
assert_contains "$body" 'execution=9' "max_execution_time override"
assert_contains "$body" 'display=1' "display_errors override"
assert_contains "$body" 'opcache=0' "opcache.enable override"
assert_contains "$body" 'timestamps=1' "opcache.validate_timestamps override"
assert_contains "$body" 'sentinel=visible-to-php' "environment passthrough to PHP"
assert_contains "$body" 'fpm-dropin=fpm-dropin' "PHP-FPM drop-in"
grep -Eiq '^X-Contract-Dropin:[[:space:]]*loaded' "$contract_headers" || fail "nginx server drop-in was not applied"
grep -Eiq '^X-Contract-Http:[[:space:]]*http-dropin' "$contract_headers" || fail "nginx HTTP drop-in was not applied"

static_body=$("$CURL_BIN" --fail --silent --show-error "$contract_url/asset.txt")
assert_equal 'static-contract-ok' "$static_body" "static file response"
missing_php_status=$(
  "$CURL_BIN" --silent --show-error --output /dev/null \
    --write-out '%{http_code}' "$contract_url/missing.php"
)
assert_equal 404 "$missing_php_status" "missing PHP script response"

nginx_config=$(
  "$DOCKER_BIN" exec "$contract_container" nginx \
    -T -c /tmp/nginx-php-fpm/current/nginx.conf 2>&1
)
assert_contains "$nginx_config" 'client_max_body_size 17m;' "nginx body-size override"

for protected_path in /.env /.git/config /.hidden.php; do
  protected_status=$("$CURL_BIN" --silent --show-error --output /dev/null --write-out '%{http_code}' "$contract_url$protected_path")
  case "$protected_status" in
    403 | 404) ;;
    *) fail "protected path $protected_path returned HTTP $protected_status" ;;
  esac
done

log "checking invalid configuration fails before service startup"
invalid_pairs=(
  'DOCUMENT_ROOT=relative/path'
  'TZ=Not/AZone'
  'PHP_MEMORY_LIMIT=lots'
  'PHP_UPLOAD_MAX_FILESIZE=-1'
  'PHP_POST_MAX_SIZE=1MB'
  'PHP_MAX_EXECUTION_TIME=86401'
  'PHP_DISPLAY_ERRORS=yes'
  'PHP_OPCACHE_ENABLE=2'
  'PHP_OPCACHE_VALIDATE_TIMESTAMPS=-1'
  'NGINX_CLIENT_MAX_BODY_SIZE=many'
)
for pair in "${invalid_pairs[@]}"; do
  variable=${pair%%=*}
  if invalid_output=$("$DOCKER_BIN" run --rm -e "$pair" "$IMAGE" true 2>&1); then
    fail "invalid $variable unexpectedly started successfully"
  fi
  assert_contains "$invalid_output" "$variable" "invalid configuration diagnostic"
done

printf '%s\n' 'this is not valid nginx syntax;' >"$WORK_DIR/dropins/invalid-nginx.conf"
if invalid_output=$(
  "$DOCKER_BIN" run --rm \
    --mount "type=bind,src=$WORK_DIR/dropins/invalid-nginx.conf,dst=/etc/nginx/server.d/invalid-nginx.conf,readonly" \
    "$IMAGE" true 2>&1
); then
  fail "malformed nginx drop-in unexpectedly started successfully"
fi
assert_contains "$invalid_output" 'invalid-nginx.conf' "malformed drop-in diagnostic"

log "checking graceful SIGTERM propagation"
signal_container="$RUN_PREFIX-signal"
start_container "$signal_container"
wait_for_container_http "$signal_container" >/dev/null
signal_start=$SECONDS
"$DOCKER_BIN" stop --time 10 "$signal_container" >/dev/null
signal_elapsed=$((SECONDS - signal_start))
((signal_elapsed <= 12)) || fail "graceful shutdown took ${signal_elapsed}s"
signal_exit=$("$DOCKER_BIN" inspect --format '{{.State.ExitCode}}' "$signal_container")
assert_equal 0 "$signal_exit" "graceful SIGTERM exit status"

assert_managed_service_failure php-fpm TERM php-fpm php-fpm8
assert_managed_service_failure nginx KILL nginx

logs=$("$DOCKER_BIN" logs "$contract_container" 2>&1)
assert_contains "$logs" '/healthz' "HTTP access log on stdout/stderr"

log "all integration checks passed for $IMAGE ($image_arch)"
