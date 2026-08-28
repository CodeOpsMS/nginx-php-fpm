[global]
pid = /tmp/nginx-php-fpm/run/php-fpm.pid
error_log = /proc/self/fd/2
log_limit = 8192
daemonize = no

include = "{{CONFIG_DIR}}/php-fpm-pool.conf"
include = /etc/php-fpm.d/*.conf
