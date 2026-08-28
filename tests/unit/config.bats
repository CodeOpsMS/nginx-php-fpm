#!/usr/bin/env bats

# Bats wraps each @test body in its own function/subshell.
# shellcheck disable=SC2030,SC2031

load '../helpers/test_helper'

setup() {
  setup_config_test
}

teardown() {
  teardown_config_test
}

set_valid_environment() {
  export DOCUMENT_ROOT="$TEST_TMPDIR/document root"
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

@test "validate_config applies production defaults" {
  # The image default exists only inside the container, so isolate the path check
  # while testing assignment of all defaults on the host.
  validate_document_root() { return 0; }

  validate_config

  [[ $DOCUMENT_ROOT == /var/www/html ]]
  [[ $TZ == UTC ]]
  [[ $PHP_MEMORY_LIMIT == 256M ]]
  [[ $PHP_UPLOAD_MAX_FILESIZE == 64M ]]
  [[ $PHP_POST_MAX_SIZE == 64M ]]
  [[ $PHP_MAX_EXECUTION_TIME == 30 ]]
  [[ $PHP_DISPLAY_ERRORS == 0 ]]
  [[ $PHP_OPCACHE_ENABLE == 1 ]]
  [[ $PHP_OPCACHE_VALIDATE_TIMESTAMPS == 0 ]]
  [[ $NGINX_CLIENT_MAX_BODY_SIZE == 64m ]]
}

@test "validate_config preserves valid overrides" {
  set_valid_environment
  validate_config

  [[ $DOCUMENT_ROOT == "$TEST_TMPDIR/document root" ]]
  [[ $TZ == Europe/Berlin ]]
  [[ $PHP_MEMORY_LIMIT == 512M ]]
  [[ $PHP_UPLOAD_MAX_FILESIZE == 128M ]]
  [[ $PHP_POST_MAX_SIZE == 192M ]]
  [[ $PHP_MAX_EXECUTION_TIME == 90 ]]
  [[ $PHP_DISPLAY_ERRORS == 1 ]]
  [[ $PHP_OPCACHE_ENABLE == 0 ]]
  [[ $PHP_OPCACHE_VALIDATE_TIMESTAMPS == 1 ]]
  [[ $NGINX_CLIENT_MAX_BODY_SIZE == 192m ]]
}

@test "validate_config reports the invalid variable" {
  local name value
  local -a invalid_pairs=(
    'DOCUMENT_ROOT=relative'
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
    clear_contract_environment
    export DOCUMENT_ROOT="$TEST_TMPDIR/document root"
    name=${pair%%=*}
    value=${pair#*=}
    export "$name=$value"

    run validate_config
    assert_failure
    assert_output_contains "$name"
  done
}

@test "validate_config is idempotent" {
  set_valid_environment
  validate_config
  local first
  first=$(printf '%s\0' \
    "$DOCUMENT_ROOT" "$TZ" "$PHP_MEMORY_LIMIT" "$PHP_UPLOAD_MAX_FILESIZE" \
    "$PHP_POST_MAX_SIZE" "$PHP_MAX_EXECUTION_TIME" "$PHP_DISPLAY_ERRORS" \
    "$PHP_OPCACHE_ENABLE" "$PHP_OPCACHE_VALIDATE_TIMESTAMPS" \
    "$NGINX_CLIENT_MAX_BODY_SIZE" | cksum)

  validate_config
  local second
  second=$(printf '%s\0' \
    "$DOCUMENT_ROOT" "$TZ" "$PHP_MEMORY_LIMIT" "$PHP_UPLOAD_MAX_FILESIZE" \
    "$PHP_POST_MAX_SIZE" "$PHP_MAX_EXECUTION_TIME" "$PHP_DISPLAY_ERRORS" \
    "$PHP_OPCACHE_ENABLE" "$PHP_OPCACHE_VALIDATE_TIMESTAMPS" \
    "$NGINX_CLIENT_MAX_BODY_SIZE" | cksum)

  [[ $first == "$second" ]]
}
