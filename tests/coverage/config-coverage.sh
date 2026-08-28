#!/usr/bin/env bash

# Dollar signs below are intentional literal validator inputs and outputs.
# shellcheck disable=SC2016

set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
CONFIG_LIB=${CONFIG_LIB:-"$ROOT/rootfs/usr/local/lib/nginx-php-fpm/config.sh"}
TEMPLATE_DIR=${TEMPLATE_DIR:-"$ROOT/rootfs/usr/local/share/nginx-php-fpm/templates"}
HARNESS_TMP=$(mktemp -d "${TMPDIR:-/tmp}/nginx-php-fpm-coverage.XXXXXX")
CAPTURE_FILE="$HARNESS_TMP/capture"

cleanup() {
  chmod -R u+rwX "$HARNESS_TMP" 2>/dev/null || true
  rm -rf -- "$HARNESS_TMP"
}
trap cleanup EXIT INT TERM

coverage_fail() {
  printf '[coverage] ERROR: %s\n' "$*" >&2
  exit 1
}

expect_success() {
  local description=$1
  shift
  if ! "$@" >"$CAPTURE_FILE" 2>&1; then
    printf '[coverage] %s failed:\n' "$description" >&2
    sed 's/^/[coverage]   /' "$CAPTURE_FILE" >&2
    exit 1
  fi
}

expect_failure() {
  local description=$1
  local diagnostic=$2
  shift 2
  if "$@" >"$CAPTURE_FILE" 2>&1; then
    coverage_fail "$description unexpectedly succeeded"
  fi
  if [[ -n $diagnostic ]] && ! grep -Fq -- "$diagnostic" "$CAPTURE_FILE"; then
    printf '[coverage] %s returned the wrong diagnostic:\n' "$description" >&2
    sed 's/^/[coverage]   /' "$CAPTURE_FILE" >&2
    exit 1
  fi
}

expect_output() {
  local description=$1
  local expected=$2
  shift 2
  expect_success "$description" "$@"
  local actual
  actual=$(<"$CAPTURE_FILE")
  [[ $actual == "$expected" ]] || coverage_fail \
    "$description: expected <$expected>, got <$actual>"
}

assert_equal() {
  local description=$1
  local expected=$2
  local actual=$3
  [[ $actual == "$expected" ]] || coverage_fail \
    "$description: expected <$expected>, got <$actual>"
}

clear_contract_environment() {
  unset DOCUMENT_ROOT TZ PHP_MEMORY_LIMIT PHP_UPLOAD_MAX_FILESIZE
  unset PHP_POST_MAX_SIZE PHP_MAX_EXECUTION_TIME PHP_DISPLAY_ERRORS
  unset PHP_OPCACHE_ENABLE PHP_OPCACHE_VALIDATE_TIMESTAMPS
  unset NGINX_CLIENT_MAX_BODY_SIZE
}

set_valid_environment() {
  export DOCUMENT_ROOT="$HARNESS_TMP/document root"
  export TZ=Europe/Berlin
  export PHP_MEMORY_LIMIT=512M
  export PHP_UPLOAD_MAX_FILESIZE=128M
  export PHP_POST_MAX_SIZE=192M
  export PHP_MAX_EXECUTION_TIME=90
  export PHP_DISPLAY_ERRORS=1
  export PHP_OPCACHE_ENABLE=0
  export PHP_OPCACHE_VALIDATE_TIMESTAMPS=1
  export NGINX_CLIENT_MAX_BODY_SIZE=192m
}

rendered_checksum() {
  local directory=$1
  (
    cd "$directory" || exit 1
    find . -type f -print | LC_ALL=C sort | while IFS= read -r file; do
      cksum "$file"
    done
  )
}

[[ -f $CONFIG_LIB ]] || coverage_fail "config library not found: $CONFIG_LIB"
mkdir -p \
  "$HARNESS_TMP/document root" \
  "$HARNESS_TMP/zoneinfo/Europe"
: >"$HARNESS_TMP/zoneinfo/UTC"
: >"$HARNESS_TMP/zoneinfo/Europe/Berlin"
export TEMPLATE_DIR ZONEINFO_DIR="$HARNESS_TMP/zoneinfo"

# shellcheck source=rootfs/usr/local/lib/nginx-php-fpm/config.sh
source "$CONFIG_LIB"

expect_success 'boolean zero' validate_bool TEST_BOOL 0
expect_success 'boolean one' validate_bool TEST_BOOL 1
expect_failure 'invalid boolean' TEST_BOOL validate_bool TEST_BOOL yes

for size in -1 0 1 64K 64m 2G; do
  expect_success "PHP size $size" validate_php_size TEST_SIZE "$size"
done
expect_failure 'invalid PHP size' TEST_SIZE validate_php_size TEST_SIZE 1MB
expect_success 'nonnegative PHP size' validate_nonnegative_php_size TEST_SIZE 64M
expect_failure 'negative nonnegative PHP size' TEST_SIZE \
  validate_nonnegative_php_size TEST_SIZE -1
expect_failure 'malformed nonnegative PHP size' TEST_SIZE \
  validate_nonnegative_php_size TEST_SIZE invalid

for size in 0 1 64k 64M 2g; do
  expect_success "nginx size $size" validate_nginx_size TEST_SIZE "$size"
done
expect_failure 'invalid nginx size' TEST_SIZE validate_nginx_size TEST_SIZE -1

expect_success 'integer lower boundary' validate_uint_range TEST_UINT 0 0 86400
expect_success 'integer upper boundary' validate_uint_range TEST_UINT 86400 0 86400
expect_success 'integer with leading zeroes' validate_uint_range TEST_UINT 00030 0 86400
expect_failure 'non-integer' TEST_UINT validate_uint_range TEST_UINT 1.5 0 86400
expect_failure 'overlong integer' TEST_UINT validate_uint_range TEST_UINT 000000 0 86400
expect_failure 'integer above maximum' TEST_UINT validate_uint_range TEST_UINT 86401 0 86400
expect_failure 'integer below minimum' TEST_UINT validate_uint_range TEST_UINT 0 1 9

expect_success 'valid document root' validate_document_root "$HARNESS_TMP/document root"
expect_failure 'relative document root' DOCUMENT_ROOT validate_document_root relative/path
expect_failure 'control character in document root' DOCUMENT_ROOT \
  validate_document_root "$HARNESS_TMP/"$'line\nbreak'
expect_failure 'missing document root' DOCUMENT_ROOT \
  validate_document_root "$HARNESS_TMP/missing"
: >"$HARNESS_TMP/not-a-directory"
expect_failure 'document root file' DOCUMENT_ROOT \
  validate_document_root "$HARNESS_TMP/not-a-directory"
mkdir "$HARNESS_TMP/unreadable"
chmod 000 "$HARNESS_TMP/unreadable"
expect_failure 'unreadable document root' DOCUMENT_ROOT \
  validate_document_root "$HARNESS_TMP/unreadable"
chmod 700 "$HARNESS_TMP/unreadable"

expect_success 'UTC timezone' validate_timezone UTC
expect_success 'IANA timezone' validate_timezone Europe/Berlin
expect_failure 'timezone traversal' TZ validate_timezone ../etc/passwd
expect_failure 'missing timezone' TZ validate_timezone Not/AZone

expect_output 'nginx escaping' 'a\\\\b\"c\$d' \
  escape_nginx_string 'a\\b"c$d'
expect_output 'INI escaping' 'a\\\\b\"c\$d' \
  escape_ini_string 'a\\b"c$d'
expect_output 'repeated literal replacement' \
  'before \\&/$" middle \\&/$" after' \
  replace_literal_token \
  'before {{TOKEN}} middle {{TOKEN}} after' \
  '{{TOKEN}}' \
  '\\&/$"'
expect_output 'absent literal replacement' 'unchanged text' \
  replace_literal_token 'unchanged text' '{{TOKEN}}' replacement

saved_document_validator=$(declare -f validate_document_root)
validate_document_root() { return 0; }
clear_contract_environment
expect_success 'default configuration' validate_config
assert_equal 'default document root' /var/www/html "$DOCUMENT_ROOT"
assert_equal 'default timezone' UTC "$TZ"
assert_equal 'default memory limit' 256M "$PHP_MEMORY_LIMIT"
assert_equal 'default upload size' 64M "$PHP_UPLOAD_MAX_FILESIZE"
assert_equal 'default post size' 64M "$PHP_POST_MAX_SIZE"
assert_equal 'default execution time' 30 "$PHP_MAX_EXECUTION_TIME"
assert_equal 'default display errors' 0 "$PHP_DISPLAY_ERRORS"
assert_equal 'default opcache' 1 "$PHP_OPCACHE_ENABLE"
assert_equal 'default opcache timestamps' 0 "$PHP_OPCACHE_VALIDATE_TIMESTAMPS"
assert_equal 'default nginx body size' 64m "$NGINX_CLIENT_MAX_BODY_SIZE"
eval "$saved_document_validator"

clear_contract_environment
set_valid_environment
expect_success 'valid configuration overrides' validate_config
assert_equal 'memory override' 512M "$PHP_MEMORY_LIMIT"
assert_equal 'nginx override' 192m "$NGINX_CLIENT_MAX_BODY_SIZE"
export -p | grep -q 'PHP_MEMORY_LIMIT' || coverage_fail 'validated variables were not exported'

invalid_pairs=(
  'DOCUMENT_ROOT=relative'
  'TZ=Not/AZone'
  'PHP_MEMORY_LIMIT=lots'
  'PHP_UPLOAD_MAX_FILESIZE=-1'
  'PHP_POST_MAX_SIZE=-1'
  'PHP_MAX_EXECUTION_TIME=86401'
  'PHP_DISPLAY_ERRORS=yes'
  'PHP_OPCACHE_ENABLE=2'
  'PHP_OPCACHE_VALIDATE_TIMESTAMPS=-1'
  'NGINX_CLIENT_MAX_BODY_SIZE=many'
)
for pair in "${invalid_pairs[@]}"; do
  clear_contract_environment
  export DOCUMENT_ROOT="$HARNESS_TMP/document root"
  variable=${pair%%=*}
  value=${pair#*=}
  printf -v "$variable" '%s' "$value"
  export "${variable?}"
  expect_failure "invalid $variable configuration" "$variable" validate_config
done

clear_contract_environment
export DOCUMENT_ROOT="$HARNESS_TMP/document root"
expect_success 'rendered configuration' render_config "$HARNESS_TMP/rendered"
rendered_files=(
  nginx.conf
  php/conf.d/50-runtime.ini
  php-fpm.conf
  php-fpm-pool.conf
)
for rendered_file in "${rendered_files[@]}"; do
  [[ -s $HARNESS_TMP/rendered/$rendered_file ]] || coverage_fail \
    "rendered file is missing: $rendered_file"
done
if grep -R -Fq '{{' "$HARNESS_TMP/rendered"; then
  coverage_fail 'rendered configuration contains unresolved template tokens'
fi
first_checksum=$(rendered_checksum "$HARNESS_TMP/rendered")
expect_success 'idempotent render' render_config "$HARNESS_TMP/rendered"
second_checksum=$(rendered_checksum "$HARNESS_TMP/rendered")
assert_equal 'rendered checksum' "$first_checksum" "$second_checksum"

mkdir -p "$HARNESS_TMP/path with \\$ and \"quote\""
export DOCUMENT_ROOT="$HARNESS_TMP/path with \\$ and \"quote\""
expect_success 'metacharacter document root render' render_config "$HARNESS_TMP/special-render"
expect_output 'escaped special document root' \
  "$HARNESS_TMP/path with \\\\\\$ and \\\"quote\\\"" \
  escape_nginx_string "$DOCUMENT_ROOT"
escaped_document_root=$(<"$CAPTURE_FILE")
grep -Fq "root \"$escaped_document_root\";" "$HARNESS_TMP/special-render/nginx.conf" ||
  coverage_fail 'escaped document root was not rendered literally'

export DOCUMENT_ROOT="$HARNESS_TMP/document root"
expect_failure 'relative render output' 'absolute path' render_config relative/output
expect_failure 'control character render output' 'control characters' \
  render_config "$HARNESS_TMP/"$'line\nbreak'
saved_template_dir=$TEMPLATE_DIR
TEMPLATE_DIR="$HARNESS_TMP/missing-templates"
expect_failure 'missing template directory' 'template directory' \
  render_config "$HARNESS_TMP/missing-render"
TEMPLATE_DIR=$saved_template_dir
export PHP_DISPLAY_ERRORS=yes
expect_failure 'render validation failure' PHP_DISPLAY_ERRORS \
  render_config "$HARNESS_TMP/invalid-render"

export RENDER_DOCUMENT_ROOT=/srv/app
export RENDER_TZ=UTC
export RENDER_CONFIG_DIR=/tmp/config
export PHP_MEMORY_LIMIT=256M
export PHP_UPLOAD_MAX_FILESIZE=64M
export PHP_POST_MAX_SIZE=64M
export PHP_MAX_EXECUTION_TIME=30
export PHP_DISPLAY_ERRORS=0
export PHP_OPCACHE_ENABLE=1
export PHP_OPCACHE_VALIDATE_TIMESTAMPS=0
export NGINX_CLIENT_MAX_BODY_SIZE=64m
expect_failure 'missing template source' '' \
  render_template "$HARNESS_TMP/missing.tpl" "$HARNESS_TMP/output"
expect_failure 'invalid template destination' '' \
  render_template "$TEMPLATE_DIR/php.ini.tpl" "$HARNESS_TMP"

printf '[coverage] configuration behavior harness passed\n'
