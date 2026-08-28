#!/usr/bin/env bats

# Dollar signs below are intentional literal validator inputs and outputs.
# shellcheck disable=SC2016

load '../helpers/test_helper'

setup() {
  setup_config_test
}

teardown() {
  teardown_config_test
}

@test "boolean validator accepts only zero and one" {
  run validate_bool TEST_BOOL 0
  assert_success
  run validate_bool TEST_BOOL 1
  assert_success

  for invalid in '' true false yes -1 2 '1 '; do
    run validate_bool TEST_BOOL "$invalid"
    assert_failure
    assert_output_contains TEST_BOOL
  done
}

@test "unsigned range validator handles boundaries" {
  run validate_uint_range TEST_UINT 0 0 86400
  assert_success
  run validate_uint_range TEST_UINT 86400 0 86400
  assert_success
  run validate_uint_range TEST_UINT 30 0 86400
  assert_success
  run validate_uint_range TEST_UINT 00030 0 86400
  assert_success

  for invalid in '' -1 86401 000000 1.5 1e3 nope ' 1'; do
    run validate_uint_range TEST_UINT "$invalid" 0 86400
    assert_failure
    assert_output_contains TEST_UINT
  done

  run validate_uint_range TEST_UINT 0 1 9
  assert_failure
}

@test "PHP size validator accepts canonical byte sizes" {
  for valid in -1 0 1 1024 64K 64M 2G 12k 12m 12g; do
    run validate_php_size TEST_SIZE "$valid"
    assert_success
  done

  for invalid in '' -2 1KB 1.5M M64 '64 M' unlimited; do
    run validate_php_size TEST_SIZE "$invalid"
    assert_failure
    assert_output_contains TEST_SIZE
  done
}

@test "nonnegative PHP size validator rejects only negative or malformed sizes" {
  for valid in 0 1 64K 64M 2G 12m; do
    run validate_nonnegative_php_size TEST_SIZE "$valid"
    assert_success
  done

  run validate_nonnegative_php_size TEST_SIZE -1
  assert_failure
  assert_output_contains TEST_SIZE
  run validate_nonnegative_php_size TEST_SIZE invalid
  assert_failure
  assert_output_contains TEST_SIZE
}

@test "nginx size validator accepts canonical nginx sizes" {
  for valid in 0 1 1024 64k 64m 2g 64K 64M 2G; do
    run validate_nginx_size TEST_SIZE "$valid"
    assert_success
  done

  for invalid in '' -1 1mb 1.5m m64 '64 m' unlimited; do
    run validate_nginx_size TEST_SIZE "$invalid"
    assert_failure
    assert_output_contains TEST_SIZE
  done
}

@test "document root must be an absolute readable directory" {
  run validate_document_root "$TEST_TMPDIR/document root"
  assert_success

  run validate_document_root relative/path
  assert_failure
  run validate_document_root "$TEST_TMPDIR/missing"
  assert_failure
  run validate_document_root "$TEST_TMPDIR/document root/file"
  assert_failure

  run validate_document_root "$TEST_TMPDIR/"$'control\ncharacter'
  assert_failure

  mkdir "$TEST_TMPDIR/unreadable"
  chmod 000 "$TEST_TMPDIR/unreadable"
  run validate_document_root "$TEST_TMPDIR/unreadable"
  chmod 700 "$TEST_TMPDIR/unreadable"
  assert_failure
}

@test "timezone validator accepts installed IANA zones and rejects traversal" {
  run validate_timezone UTC
  assert_success
  run validate_timezone Europe/Berlin
  assert_success

  for invalid in '' ../etc/passwd /etc/passwd Not/AZone 'Europe/Berlin '; do
    run validate_timezone "$invalid"
    assert_failure
  done
}

@test "nginx string escaping protects interpolation metacharacters" {
  run escape_nginx_string 'plain/path with spaces'
  assert_success
  [[ $output == 'plain/path with spaces' ]]

  run escape_nginx_string 'a\\b"c$d'
  assert_success
  [[ $output == 'a\\\\b\"c\$d' ]]
}

@test "INI string escaping protects interpolation metacharacters" {
  run escape_ini_string 'a\\b"c$d'
  assert_success
  [[ $output == 'a\\\\b\"c\$d' ]]
}

@test "literal token replacement handles repeats and shell metacharacters" {
  run replace_literal_token \
    'before {{TOKEN}} middle {{TOKEN}} after' \
    '{{TOKEN}}' \
    '\\&/$"'
  assert_success
  [[ $output == 'before \\&/$" middle \\&/$" after' ]]

  run replace_literal_token 'unchanged text' '{{TOKEN}}' replacement
  assert_success
  [[ $output == 'unchanged text' ]]
}
