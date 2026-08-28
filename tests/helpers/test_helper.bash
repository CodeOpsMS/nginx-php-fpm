# Bats provides status and output after `run`.
# shellcheck disable=SC2154

PROJECT_ROOT=$(cd -- "$(dirname -- "${BATS_TEST_FILENAME}")/../.." && pwd)
CONFIG_LIB=${CONFIG_LIB:-"$PROJECT_ROOT/rootfs/usr/local/lib/nginx-php-fpm/config.sh"}
TEMPLATE_DIR=${TEMPLATE_DIR:-"$PROJECT_ROOT/rootfs/usr/local/share/nginx-php-fpm/templates"}

CONTRACT_VARIABLES=(
  DOCUMENT_ROOT
  TZ
  PHP_MEMORY_LIMIT
  PHP_UPLOAD_MAX_FILESIZE
  PHP_POST_MAX_SIZE
  PHP_MAX_EXECUTION_TIME
  PHP_DISPLAY_ERRORS
  PHP_OPCACHE_ENABLE
  PHP_OPCACHE_VALIDATE_TIMESTAMPS
  NGINX_CLIENT_MAX_BODY_SIZE
)

clear_contract_environment() {
  local variable
  for variable in "${CONTRACT_VARIABLES[@]}"; do
    unset "$variable"
  done
}

load_config_library() {
  [[ -f $CONFIG_LIB ]] || {
    printf 'config library not found: %s\n' "$CONFIG_LIB" >&2
    return 1
  }
  # shellcheck disable=SC1090
  source "$CONFIG_LIB"
}

assert_success() {
  if [[ $status -ne 0 ]]; then
    printf 'expected success, got status %s\noutput:\n%s\n' "$status" "$output" >&2
    return 1
  fi
}

assert_failure() {
  if [[ $status -eq 0 ]]; then
    printf 'expected failure, got status 0\noutput:\n%s\n' "$output" >&2
    return 1
  fi
}

assert_output_contains() {
  local expected=$1
  if [[ $output != *"$expected"* ]]; then
    printf 'expected output to contain <%s>, got:\n%s\n' "$expected" "$output" >&2
    return 1
  fi
}

setup_config_test() {
  TEST_TMPDIR=$(mktemp -d "${BATS_TEST_TMPDIR:-${TMPDIR:-/tmp}}/nginx-php-fpm.XXXXXX")
  mkdir -p "$TEST_TMPDIR/document root" "$TEST_TMPDIR/zoneinfo/Europe"
  : >"$TEST_TMPDIR/zoneinfo/UTC"
  : >"$TEST_TMPDIR/zoneinfo/Europe/Berlin"
  clear_contract_environment
  export TEMPLATE_DIR ZONEINFO_DIR="$TEST_TMPDIR/zoneinfo"
  load_config_library
}

teardown_config_test() {
  rm -rf -- "$TEST_TMPDIR"
}
