# Migrate from richarvey/nginx-php-fpm

This guide moves an existing nginx/PHP-FPM deployment to the maintained CodeOpsMS image.
CodeOpsMS/nginx-php-fpm is an independent implementation with a smaller runtime contract.
It is not an official continuation of richarvey/nginx-php-fpm and requires configuration
changes. Review the differences before changing a production deployment.

The legacy settings below refer to the
[richarvey configuration reference](https://github.com/richarvey/nginx-php-fpm/blob/15f577b1877c27b5830cb9c23ddff00fa2289ba3/docs/config_flags.md).
The examples target CodeOpsMS release
[0.5.0](https://github.com/CodeOpsMS/nginx-php-fpm/releases/tag/0.5.0).

## Map the runtime settings

| Existing setting or behavior | CodeOpsMS equivalent or migration step |
| --- | --- |
| HTTP on container port `80` | HTTP on container port `8080`; update port mappings, Services, reverse proxies, and probes |
| HTTPS on container port `443`, `DOMAIN`, Let's Encrypt helpers | Terminate TLS and renew certificates at a reverse proxy or ingress |
| `WEBROOT` | `DOCUMENT_ROOT`, set to the absolute path inside the container |
| `PHP_MEM_LIMIT` | `PHP_MEMORY_LIMIT` |
| `PHP_UPLOAD_MAX_FILESIZE`, `PHP_POST_MAX_SIZE` | Same names; review defaults and validation in the runtime reference |
| `ERRORS=1` | `PHP_DISPLAY_ERRORS=1`; leave `0` in production |
| `OPcache` | `PHP_OPCACHE_ENABLE=1` enables OPcache; `0` disables it |
| `PHP_CATCHALL` | Requests that are not existing files/directories use `index.php` by default; test your application's routes |
| `HIDE_NGINX_HEADERS` | nginx/PHP version headers are disabled by default |
| `PHP_ERRORS_STDERR` | Error logs go to stderr; nginx access logs go to stdout |
| `PUID`, `PGID` | Docker `--user UID:GID`, Compose `user: "UID:GID"`, or Kubernetes `runAsUser`/`runAsGroup`; default is `82:82` |
| Startup `chown`, `chmod`, `SKIP_CHOWN`, `SKIP_CHMOD` | Prepare permissions before startup; the image does not change ownership of mounted data |
| `GIT_*`, `SSH_KEY`, `pull`, `push` | Build or check out application code before deployment; mount it read-only or copy it into your application image |
| Startup Composer install, `SKIP_COMPOSER`, `APPLICATION_ENV` | Install application dependencies in CI or a separate build stage |
| `RUN_SCRIPTS`, `SCRIPTS_DIR` | Move initialization to a deployment step or separate one-shot service |
| `REMOVE_FILES` | Mount the application explicitly; the image does not synchronize or clear your application tree |
| `REAL_IP_HEADER`, `REAL_IP_FROM` | Add explicit nginx `real_ip_header` and trusted `set_real_ip_from` directives in a read-only configuration drop-in |
| nginx `sites-enabled` files | Port the relevant HTTP/server directives to the documented drop-in directories; do not mount an old complete nginx configuration unchanged |
| Default startup script or Supervisor override | Keep the image's built-in entrypoint and command so configuration validation and signal forwarding run |

Inspect the legacy OPcache flag carefully: its documentation describes `OPcache=1` as
disabling OPcache. The new flag has direct enable/disable semantics.

## Review PHP compatibility and extensions

Release 0.5.0 uses PHP 8.5.12. Upgrading a PHP 8.2 application also requires checking its
framework, Composer requirements, and PHP migration notes. Run the application's own tests
and `composer check-platform-reqs` against a matching PHP environment before deployment.

Included extensions are OPcache, bcmath, exif, GD (FreeType/JPEG/WebP), intl, mbstring,
mysqli, PDO MySQL, PDO PostgreSQL, Redis, soap, and zip. See the
[runtime reference](../README.md#what-is-included) for the current list.

Composer, Git, Certbot, Xdebug, MongoDB, xsl, the non-PDO pgsql extension, and nginx Lua
modules are outside the supported image contract. If your application needs another
extension or nginx module, establish that requirement before migrating. An application's
existing use of a bundled legacy feature is not covered by changing the image name.

## Convert a Compose service

For an application that already has a populated `public/` directory and installed
dependencies, a typical legacy service might look like this:

```yaml
services:
  web:
    image: richarvey/nginx-php-fpm:3.1.6
    ports:
      - "127.0.0.1:8080:80"
    environment:
      WEBROOT: /srv/app/public
      PHP_MEM_LIMIT: 256M
    volumes:
      - ./app:/srv/app
```

Convert it to:

```yaml
services:
  web:
    image: ghcr.io/codeopsms/nginx-php-fpm:0.5.0
    read_only: true
    tmpfs:
      - /tmp:rw,noexec,nosuid,nodev,mode=1777
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true
    ports:
      - "127.0.0.1:8080:8080"
    environment:
      DOCUMENT_ROOT: /srv/app/public
      PHP_MEMORY_LIMIT: 256M
    volumes:
      - ./app:/srv/app:ro
```

The example is a configuration conversion, not a claim that every application works
unchanged. The [self-contained Compose example](../examples/compose/README.md) includes a
small PHP application and is exercised on both native architectures in CI.

Keep the application mount read-only and give UID/GID 82 access to any separate writable
data directories. For a different existing data owner, add `user: "1000:101"` and provision
permissions for that identity. Keep `/tmp` writable. Default PHP temporary files and
sessions live there and are ephemeral; choose an application-specific persistent session
store if sessions must survive container replacement.

## Move custom configuration

Use read-only files in these directories:

| Directory | Configuration scope |
| --- | --- |
| `/etc/nginx/conf.d` | nginx `http` context |
| `/etc/nginx/server.d` | Default nginx `server` context |
| `/etc/php/conf.d` | PHP INI overrides |
| `/etc/php-fpm.d` | PHP-FPM fragments |

For example, migrate a PHP setting to `zz-application.ini` and mount it under
`/etc/php/conf.d/`. Match nginx directives to the correct scope; repeating a singleton
directive in the same context causes startup to fail. Reserve `/healthz` for the built-in
PHP-backed healthcheck. See [drop-in precedence](../README.md#configuration-drop-ins).

## Validate and switch traffic

1. Preserve your existing deployment configuration and back up application data. Confirm
   that any application/database migration remains compatible with your rollback plan.
2. Start the new service on a different localhost port, for example `8081:8080`.
3. Check `/healthz`, representative application routes, static assets, uploads, sessions,
   database/Redis connections, and background jobs using your application's own tests.
4. Confirm access to writable volumes using the selected UID/GID, and inspect container
   logs. Verify the image's [provenance](../README.md#supply-chain-verification).
5. Pin the tested release digest and switch the reverse proxy to the new service. Keep
   the old image and configuration available for an application-compatible rollback.

For help, open a
[migration request](https://github.com/CodeOpsMS/nginx-php-fpm/issues/new?template=migration-help.yml).
After a successful test or deployment, an
[adoption report](https://github.com/CodeOpsMS/nginx-php-fpm/issues/new?template=adoption-report.yml)
helps improve this guide. The [worked migration article](articles/migrating-to-a-maintained-php-container.md)
explains the same process from a deployment perspective.
