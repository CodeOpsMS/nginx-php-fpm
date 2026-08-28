#!/usr/bin/env bats

load '../helpers/test_helper'

@test "runtime source layout contains every contract entrypoint" {
  local -a paths=(
    container/extensions/composer.json
    rootfs/usr/local/bin/container-entrypoint
    rootfs/usr/local/bin/healthcheck
    rootfs/usr/local/bin/supervise
    rootfs/usr/local/lib/nginx-php-fpm/config.sh
    rootfs/usr/local/lib/nginx-php-fpm/healthz.php
    rootfs/usr/local/share/nginx-php-fpm/templates/nginx.conf.tpl
    rootfs/usr/local/share/nginx-php-fpm/templates/php.ini.tpl
    rootfs/usr/local/share/nginx-php-fpm/templates/php-fpm.conf.tpl
    rootfs/usr/local/share/nginx-php-fpm/templates/php-fpm-pool.conf.tpl
    rootfs/var/www/html/index.php
  )
  local path
  for path in "${paths[@]}"; do
    [[ -s $PROJECT_ROOT/$path ]]
  done
}

@test "default public files do not expose phpinfo" {
  run grep -R -n -E 'phpinfo[[:space:]]*\(' "$PROJECT_ROOT/rootfs"
  [[ $status -eq 1 ]]
}

@test "entrypoint and supervisor have valid Bash syntax" {
  run bash -n "$PROJECT_ROOT/rootfs/usr/local/bin/container-entrypoint"
  assert_success
  run bash -n "$PROJECT_ROOT/rootfs/usr/local/bin/supervise"
  assert_success
  run bash -n "$CONFIG_LIB"
  assert_success
}

@test "all public environment variables are represented in configuration logic" {
  local variable
  for variable in "${CONTRACT_VARIABLES[@]}"; do
    run grep -q -- "$variable" "$CONFIG_LIB"
    assert_success
  done
}
