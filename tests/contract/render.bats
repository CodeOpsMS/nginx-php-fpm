#!/usr/bin/env bats

# Bats wraps each @test body in its own function/subshell.
# shellcheck disable=SC2030,SC2031

load '../helpers/test_helper'

setup() {
  setup_config_test
  export DOCUMENT_ROOT="$TEST_TMPDIR/document root"
}

teardown() {
  teardown_config_test
}

normalize_rendered_file() {
  local source=$1
  local destination=$2
  sed \
    -e "s|$TEST_TMPDIR/document root|@@DOCUMENT_ROOT@@|g" \
    -e "s|$TEST_TMPDIR/rendered|@@CONFIG_DIR@@|g" \
    "$source" >"$destination"
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

@test "render_config writes every expected file and resolves placeholders" {
  render_config "$TEST_TMPDIR/rendered"

  local -a rendered_files=(
    nginx.conf
    php.ini
    php-fpm.conf
    php-fpm-pool.conf
  )
  local -a actual_files=(
    nginx.conf
    php/conf.d/50-runtime.ini
    php-fpm.conf
    php-fpm-pool.conf
  )
  local index normalized
  for index in 0 1 2 3; do
    normalized="$TEST_TMPDIR/normalized-${rendered_files[$index]}"
    normalize_rendered_file \
      "$TEST_TMPDIR/rendered/${actual_files[$index]}" \
      "$normalized"
    run diff -u \
      "$PROJECT_ROOT/tests/fixtures/rendered-default/${rendered_files[$index]}" \
      "$normalized"
    assert_success
  done

  run grep -R -F '{{' "$TEST_TMPDIR/rendered"
  [[ $status -eq 1 ]]
}

@test "render_config is deterministic and idempotent for identical input" {
  render_config "$TEST_TMPDIR/rendered"
  local first
  first=$(rendered_checksum "$TEST_TMPDIR/rendered")

  render_config "$TEST_TMPDIR/rendered"
  local second
  second=$(rendered_checksum "$TEST_TMPDIR/rendered")

  [[ $first == "$second" ]]
}

@test "render_config escapes a document root with nginx metacharacters" {
  mkdir -p "$TEST_TMPDIR/path with \\$ and \"quote\""
  export DOCUMENT_ROOT="$TEST_TMPDIR/path with \\$ and \"quote\""

  render_config "$TEST_TMPDIR/rendered"

  local escaped_document_root
  escaped_document_root=$(escape_nginx_string "$DOCUMENT_ROOT")
  run grep -F "root \"$escaped_document_root\";" "$TEST_TMPDIR/rendered/nginx.conf"
  assert_success
}

@test "render_config rejects unsafe output paths and missing templates" {
  run render_config relative/output
  assert_failure
  assert_output_contains 'absolute path'

  run render_config "$TEST_TMPDIR/"$'line\nbreak'
  assert_failure
  assert_output_contains 'control characters'

  TEMPLATE_DIR="$TEST_TMPDIR/missing-templates"
  run render_config "$TEST_TMPDIR/rendered"
  assert_failure
  assert_output_contains 'template directory'
}

@test "render_config stops when validation fails" {
  export PHP_DISPLAY_ERRORS=yes
  run render_config "$TEST_TMPDIR/rendered"
  assert_failure
  assert_output_contains PHP_DISPLAY_ERRORS
}

@test "render_template reports unreadable sources and destinations" {
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

  run render_template "$TEST_TMPDIR/missing.tpl" "$TEST_TMPDIR/output"
  assert_failure

  run render_template "$TEMPLATE_DIR/php.ini.tpl" "$TEST_TMPDIR"
  assert_failure
}
