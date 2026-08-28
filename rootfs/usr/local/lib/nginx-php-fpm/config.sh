#!/usr/bin/env bash

# Sourceable configuration validation and rendering library.

config_error() {
  printf 'configuration error: %s\n' "$*" >&2
}

validate_bool() {
  local name=${1:?name is required}
  local value=${2-}

  if [[ $value != "0" && $value != "1" ]]; then
    config_error "${name} must be 0 or 1"
    return 1
  fi
}

validate_php_size() {
  local name=${1:?name is required}
  local value=${2-}

  if [[ ! $value =~ ^(-1|0|[1-9][0-9]*[KMGkmg]?)$ ]]; then
    config_error "${name} must be -1, 0, or a positive integer with an optional K, M, or G suffix"
    return 1
  fi
}

validate_nonnegative_php_size() {
  local name=${1:?name is required}
  local value=${2-}

  validate_php_size "$name" "$value" || return 1
  if [[ $value == "-1" ]]; then
    config_error "${name} must not be negative"
    return 1
  fi
}

validate_nginx_size() {
  local name=${1:?name is required}
  local value=${2-}

  if [[ ! $value =~ ^(0|[1-9][0-9]*[KMGkmg]?)$ ]]; then
    config_error "${name} must be 0 or a positive integer with an optional k, m, or g suffix"
    return 1
  fi
}

validate_uint_range() {
  local name=${1:?name is required}
  local value=${2-}
  local minimum=${3:?minimum is required}
  local maximum=${4:?maximum is required}
  local numeric_value

  if [[ ! $value =~ ^[0-9]+$ || ${#value} -gt ${#maximum} ]]; then
    config_error "${name} must be an integer from ${minimum} through ${maximum}"
    return 1
  fi

  numeric_value=$((10#$value))
  if ((numeric_value < minimum || numeric_value > maximum)); then
    config_error "${name} must be an integer from ${minimum} through ${maximum}"
    return 1
  fi
}

validate_document_root() {
  local value=${1-}

  if [[ $value != /* ]]; then
    config_error "DOCUMENT_ROOT must be an absolute path"
    return 1
  fi
  if [[ $value =~ [[:cntrl:]] ]]; then
    config_error "DOCUMENT_ROOT must not contain control characters"
    return 1
  fi
  if [[ ! -d $value ]]; then
    config_error "DOCUMENT_ROOT does not exist or is not a directory: ${value}"
    return 1
  fi
  if [[ ! -r $value || ! -x $value ]]; then
    config_error "DOCUMENT_ROOT must be readable and searchable: ${value}"
    return 1
  fi
}

validate_timezone() {
  local value=${1-}
  local zoneinfo_dir=${ZONEINFO_DIR:-/usr/share/zoneinfo}

  if [[ ! $value =~ ^[A-Za-z0-9._+-]+(/[A-Za-z0-9._+-]+)*$ ]] ||
    [[ $value =~ (^|/)\.{1,2}(/|$) ]]; then
    config_error "TZ must be an IANA timezone name"
    return 1
  fi
  if [[ ! -f ${zoneinfo_dir}/${value} || ! -r ${zoneinfo_dir}/${value} ]]; then
    config_error "TZ is not installed: ${value}"
    return 1
  fi
}

escape_nginx_string() {
  local value=${1-}

  value=${value//\\/\\\\}
  value=${value//\$/\\\$}
  value=${value//\"/\\\"}
  printf '%s' "$value"
}

escape_ini_string() {
  local value=${1-}

  value=${value//\\/\\\\}
  value=${value//\$/\\\$}
  value=${value//\"/\\\"}
  printf '%s' "$value"
}

validate_config() {
  DOCUMENT_ROOT=${DOCUMENT_ROOT-/var/www/html}
  TZ=${TZ-UTC}
  PHP_MEMORY_LIMIT=${PHP_MEMORY_LIMIT-256M}
  PHP_UPLOAD_MAX_FILESIZE=${PHP_UPLOAD_MAX_FILESIZE-64M}
  PHP_POST_MAX_SIZE=${PHP_POST_MAX_SIZE-64M}
  PHP_MAX_EXECUTION_TIME=${PHP_MAX_EXECUTION_TIME-30}
  PHP_DISPLAY_ERRORS=${PHP_DISPLAY_ERRORS-0}
  PHP_OPCACHE_ENABLE=${PHP_OPCACHE_ENABLE-1}
  PHP_OPCACHE_VALIDATE_TIMESTAMPS=${PHP_OPCACHE_VALIDATE_TIMESTAMPS-0}
  NGINX_CLIENT_MAX_BODY_SIZE=${NGINX_CLIENT_MAX_BODY_SIZE-64m}

  validate_document_root "$DOCUMENT_ROOT" || return 1
  validate_timezone "$TZ" || return 1
  validate_php_size PHP_MEMORY_LIMIT "$PHP_MEMORY_LIMIT" || return 1
  validate_nonnegative_php_size PHP_UPLOAD_MAX_FILESIZE "$PHP_UPLOAD_MAX_FILESIZE" || return 1
  validate_nonnegative_php_size PHP_POST_MAX_SIZE "$PHP_POST_MAX_SIZE" || return 1
  validate_uint_range PHP_MAX_EXECUTION_TIME "$PHP_MAX_EXECUTION_TIME" 0 86400 || return 1
  validate_bool PHP_DISPLAY_ERRORS "$PHP_DISPLAY_ERRORS" || return 1
  validate_bool PHP_OPCACHE_ENABLE "$PHP_OPCACHE_ENABLE" || return 1
  validate_bool PHP_OPCACHE_VALIDATE_TIMESTAMPS "$PHP_OPCACHE_VALIDATE_TIMESTAMPS" || return 1
  validate_nginx_size NGINX_CLIENT_MAX_BODY_SIZE "$NGINX_CLIENT_MAX_BODY_SIZE" || return 1

  export DOCUMENT_ROOT TZ PHP_MEMORY_LIMIT PHP_UPLOAD_MAX_FILESIZE
  export PHP_POST_MAX_SIZE PHP_MAX_EXECUTION_TIME PHP_DISPLAY_ERRORS
  export PHP_OPCACHE_ENABLE PHP_OPCACHE_VALIDATE_TIMESTAMPS
  export NGINX_CLIENT_MAX_BODY_SIZE
}

render_template() {
  local source_file=${1:?source template is required}
  local destination_file=${2:?destination path is required}
  local content

  content=$(<"$source_file") || return 1
  content=$(replace_literal_token "$content" '{{TZ}}' "$RENDER_TZ")
  content=$(replace_literal_token "$content" '{{PHP_MEMORY_LIMIT}}' "$PHP_MEMORY_LIMIT")
  content=$(replace_literal_token "$content" '{{PHP_UPLOAD_MAX_FILESIZE}}' "$PHP_UPLOAD_MAX_FILESIZE")
  content=$(replace_literal_token "$content" '{{PHP_POST_MAX_SIZE}}' "$PHP_POST_MAX_SIZE")
  content=$(replace_literal_token "$content" '{{PHP_MAX_EXECUTION_TIME}}' "$PHP_MAX_EXECUTION_TIME")
  content=$(replace_literal_token "$content" '{{PHP_DISPLAY_ERRORS}}' "$PHP_DISPLAY_ERRORS")
  content=$(replace_literal_token "$content" '{{PHP_OPCACHE_ENABLE}}' "$PHP_OPCACHE_ENABLE")
  content=$(replace_literal_token "$content" '{{PHP_OPCACHE_VALIDATE_TIMESTAMPS}}' "$PHP_OPCACHE_VALIDATE_TIMESTAMPS")
  content=$(replace_literal_token "$content" '{{NGINX_CLIENT_MAX_BODY_SIZE}}' "$NGINX_CLIENT_MAX_BODY_SIZE")
  content=$(replace_literal_token "$content" '{{CONFIG_DIR}}' "$RENDER_CONFIG_DIR")
  # DOCUMENT_ROOT is the only public string that can contain template-like
  # text. Render it last so its contents are never interpreted as tokens.
  content=$(replace_literal_token "$content" '{{DOCUMENT_ROOT}}' "$RENDER_DOCUMENT_ROOT")

  printf '%s\n' "$content" >"$destination_file"
}

replace_literal_token() {
  local remaining=${1-}
  local token=${2:?template token is required}
  local replacement=${3-}
  local result=''
  local prefix

  while [[ $remaining == *"$token"* ]]; do
    prefix=${remaining%%"$token"*}
    remaining=${remaining#*"$token"}
    result=${result}${prefix}${replacement}
  done
  printf '%s%s' "$result" "$remaining"
}

render_config() {
  local output_dir=${1:?output directory is required}
  local template_dir=${TEMPLATE_DIR:-/usr/local/share/nginx-php-fpm/templates}

  if [[ $output_dir != /* || $output_dir =~ [[:cntrl:]] ]]; then
    config_error "render output directory must be an absolute path without control characters"
    return 1
  fi
  if [[ ! -d $template_dir ]]; then
    config_error "template directory does not exist: ${template_dir}"
    return 1
  fi

  validate_config || return 1

  RENDER_DOCUMENT_ROOT=$(escape_nginx_string "$DOCUMENT_ROOT")
  RENDER_TZ=$(escape_ini_string "$TZ")
  RENDER_CONFIG_DIR=$(escape_ini_string "$output_dir")

  umask 027
  mkdir -p "$output_dir/php/conf.d"
  render_template "$template_dir/nginx.conf.tpl" "$output_dir/nginx.conf" || return 1
  render_template "$template_dir/php.ini.tpl" "$output_dir/php/conf.d/50-runtime.ini" || return 1
  render_template "$template_dir/php-fpm.conf.tpl" "$output_dir/php-fpm.conf" || return 1
  render_template "$template_dir/php-fpm-pool.conf.tpl" "$output_dir/php-fpm-pool.conf" || return 1

  unset RENDER_DOCUMENT_ROOT RENDER_TZ RENDER_CONFIG_DIR
}
