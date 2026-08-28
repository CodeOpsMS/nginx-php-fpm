[www]
listen = /tmp/nginx-php-fpm/run/php-fpm.sock
listen.mode = 0600
clear_env = no
catch_workers_output = yes
decorate_workers_output = no
access.log = /proc/self/fd/2
access.format = "%R - %u %t \"%m %r\" %s"
security.limit_extensions = .php

pm = dynamic
pm.max_children = 10
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
pm.max_requests = 500
