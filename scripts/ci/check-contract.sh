#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/test/common.sh
source "$SCRIPT_DIR/../test/common.sh"

ROOT=$(project_root)
CONFIG_LIB="$ROOT/rootfs/usr/local/lib/nginx-php-fpm/config.sh"

required_files=(
  Dockerfile
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
  README.md
)

contract_variables=(
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

for relative_path in "${required_files[@]}"; do
  [[ -f $ROOT/$relative_path ]] || fail "required source file is missing: $relative_path"
done

for variable in "${contract_variables[@]}"; do
  grep -q -- "$variable" "$CONFIG_LIB" || fail "$variable is missing from config.sh"
  grep -q -- "$variable" "$ROOT/README.md" || fail "$variable is missing from README.md"
done

grep -Eq '^EXPOSE[[:space:]]+8080([[:space:]]|$)' "$ROOT/Dockerfile" || fail "Dockerfile must expose port 8080"
grep -Eq '^USER[[:space:]]+(82(:82)?|www-data)([[:space:]]|$)' "$ROOT/Dockerfile" || fail "Dockerfile must set the runtime user"

if grep -R -n -E 'phpinfo[[:space:]]*\(' "$ROOT/rootfs"; then
  fail "phpinfo() must not be present in the runtime filesystem"
fi

if grep -R -n -E 'BEGIN (RSA |EC |OPENSSH |DSA )?PRIVATE KEY' \
  "$ROOT" \
  --exclude-dir=.git \
  --exclude-dir=build; then
  fail "a private key marker is present in the repository"
fi

log "source contract is complete"
