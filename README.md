# nginx-php-fpm

[![CI](https://github.com/CodeOpsMS/nginx-php-fpm/actions/workflows/ci.yml/badge.svg)](https://github.com/CodeOpsMS/nginx-php-fpm/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/CodeOpsMS/nginx-php-fpm?display_name=tag)](https://github.com/CodeOpsMS/nginx-php-fpm/releases)
[![Package](https://img.shields.io/badge/GHCR-nginx--php--fpm-blue)](https://github.com/CodeOpsMS/nginx-php-fpm/pkgs/container/nginx-php-fpm)

A production-focused, rootless nginx and PHP-FPM container for `linux/amd64` and `linux/arm64`.

The upcoming `0.4.0` release is a clean implementation inspired by
[`richarvey/nginx-php-fpm`](https://github.com/richarvey/nginx-php-fpm). It does not copy the
legacy implementation and is intentionally not configuration-compatible with it.

> **Release status:** `0.4.0` is intentionally not published yet. The tested `main` preview
> bootstraps from the current official PHP 8.5.9 image; the release workflow requires the
> official stable PHP 8.5.10 image before it can publish `0.4.0`.

## What is included

- PHP 8.5 FPM on Alpine 3.24 (`0.4.0` is gated on PHP 8.5.10)
- nginx from Alpine's stable 1.30.x line (1.30.4 at the initial release)
- Tini as PID 1 and a small supervisor for nginx and PHP-FPM
- PHP extensions: OPcache, bcmath, exif, GD (FreeType, JPEG, and WebP), intl, mbstring,
  mysqli, PDO MySQL, PDO PostgreSQL, Redis 6.3, soap, and zip
- A PHP-backed `/healthz` endpoint that verifies both nginx and PHP-FPM
- A fixed, unprivileged `www-data` user and group with UID/GID 82
- SBOMs, build provenance, and GitHub artifact attestations for published images

The runtime intentionally excludes Composer, Git, Certbot, Xdebug, MongoDB, compilers, build
headers, arbitrary startup hooks, and source synchronization. Terminate TLS and ACME at a
reverse proxy or ingress.

## Quick start

Until `0.4.0` is published, use the rolling `main` preview for evaluation:

```console
docker run --rm \
  --read-only \
  --tmpfs /tmp:rw,noexec,nosuid,nodev,mode=1777 \
  --cap-drop ALL \
  --security-opt no-new-privileges \
  -p 8080:8080 \
  ghcr.io/codeopsms/nginx-php-fpm:main
```

Open <http://localhost:8080> or check readiness with:

```console
curl --fail http://localhost:8080/healthz
```

To serve an application, mount it read-only and set its absolute document root:

```console
docker run --rm \
  --read-only \
  --tmpfs /tmp:rw,noexec,nosuid,nodev,mode=1777 \
  --cap-drop ALL \
  --security-opt no-new-privileges \
  --mount type=bind,src="$PWD/public",dst=/srv/app,readonly \
  -e DOCUMENT_ROOT=/srv/app \
  -p 8080:8080 \
  ghcr.io/codeopsms/nginx-php-fpm:main
```

Every directory in the mounted path must be searchable by UID 82, and files must be readable
by UID 82. If the application writes data, give UID/GID 82 access only to dedicated writable
volumes; do not make the application tree broadly writable.

## Runtime contract

The image listens on `8080/tcp`, serves `/var/www/html` by default, and writes nginx access
logs to stdout and nginx/PHP errors to stderr. Requests that do not resolve to a static file
or directory are sent to `index.php` as a front controller. Dotfiles, including `.git`, are
denied. nginx and PHP version headers are disabled, and the default page never exposes
`phpinfo()`.

Configuration is validated before either service starts. Invalid values produce a diagnostic
on stderr and a non-zero container exit. The generated configuration is written atomically
beneath `/tmp/nginx-php-fpm`, then checked with `nginx -t` and `php-fpm -tt`.

### Environment variables

| Variable | Default | Accepted values |
| --- | --- | --- |
| `DOCUMENT_ROOT` | `/var/www/html` | Existing absolute directory, readable and searchable by UID 82 |
| `TZ` | `UTC` | Installed IANA timezone name, for example `Europe/Berlin` |
| `PHP_MEMORY_LIMIT` | `256M` | `-1`, `0`, or a positive integer with optional `K`, `M`, or `G` suffix |
| `PHP_UPLOAD_MAX_FILESIZE` | `64M` | `0` or a positive integer with optional `K`, `M`, or `G` suffix |
| `PHP_POST_MAX_SIZE` | `64M` | `0` or a positive integer with optional `K`, `M`, or `G` suffix |
| `PHP_MAX_EXECUTION_TIME` | `30` | Integer from `0` through `86400` |
| `PHP_DISPLAY_ERRORS` | `0` | `0` or `1` |
| `PHP_OPCACHE_ENABLE` | `1` | `0` or `1` |
| `PHP_OPCACHE_VALIDATE_TIMESTAMPS` | `0` | `0` or `1` |
| `NGINX_CLIENT_MAX_BODY_SIZE` | `64m` | `0` or a positive integer with optional `k`/`K`, `m`/`M`, or `g`/`G` suffix |

`PHP_POST_MAX_SIZE` and `NGINX_CLIENT_MAX_BODY_SIZE` should normally be at least as large as
`PHP_UPLOAD_MAX_FILESIZE`.

### Configuration drop-ins

For settings beyond the environment contract, mount read-only `*.conf` or `*.ini` files into:

| Directory | Scope |
| --- | --- |
| `/etc/nginx/conf.d` | Additions in the nginx `http` context |
| `/etc/nginx/server.d` | Additions in the default nginx `server` context |
| `/etc/php/conf.d` | PHP INI overrides, loaded after generated values |
| `/etc/php-fpm.d` | PHP-FPM fragments, loaded after the generated pool |

PHP INI and PHP-FPM drop-ins use their normal last-value-wins behavior. nginx `conf.d` is for
HTTP-context additions; `server.d` can add server directives and override inherited HTTP
defaults where nginx permits it. Repeating a singleton nginx directive in the same context is
an error, not an override. Use a late lexical name such as `90-application.conf` or
`zz-application.ini` when ordering between files matters. Any malformed or conflicting drop-in
prevents startup. `/healthz` is reserved by the image and must remain reachable.

Example PHP override:

```ini
; zz-application.ini
memory_limit = 512M
date.timezone = Europe/Berlin
```

Example server override:

```nginx
# 90-application.conf
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
```

## Image tags

| Tag | Movement policy |
| --- | --- |
| `0.4.0` | Immutable release |
| `0.4`, `0`, `latest` | Move to the newest compatible release |
| `sha-<full-commit>` | Immutable image built from a successful push to `main` |
| `main` | Moves after successful pushes and daily fully tested rebuilds |

Release tags are assembled only from platform digests that completed the same native contract
suite and vulnerability scan. The release index contains exactly `linux/amd64` and
`linux/arm64`; 32-bit x86 is not supported.

For production, pin the manifest digest shown in the GitHub release:

```console
docker pull ghcr.io/codeopsms/nginx-php-fpm@sha256:<manifest-digest>
```

## Supply-chain verification

After `0.4.0` is published, install the [GitHub CLI](https://cli.github.com/) and verify the
image's GitHub artifact attestation against this repository:

```console
gh attestation verify \
  oci://ghcr.io/codeopsms/nginx-php-fpm:0.4.0 \
  --repo CodeOpsMS/nginx-php-fpm
```

Each GitHub release also contains SPDX JSON SBOMs for both platform images. CI blocks fixable
`HIGH` and `CRITICAL` vulnerabilities. A temporary exception must name the CVE, explain the risk
decision, link a tracking issue, and include an expiration date.

## Development

The local entry points mirror CI:

```console
make lint
make test
make coverage
docker build --tag nginx-php-fpm:test .
make integration IMAGE=nginx-php-fpm:test
```

`make coverage` enforces 100% line coverage for the instrumentable first-party configuration
logic. See [CONTRIBUTING.md](CONTRIBUTING.md) for tool requirements and pull-request policy.

## Automated maintenance

Dependabot checks the production and coverage-runner Dockerfiles, every GitHub Action pin, and
the build-only Composer pin for the phpredis extension daily. Composer and its metadata are never
copied into the runtime.
Patch and digest updates wait three days, minor updates wait seven days, and security updates
bypass cooldown. Patch and minor updates are squash-merged only after the full `CI / gate`
check succeeds. PHP 8.6 or newer and all major updates require maintainer review.

The scheduled CI rebuild updates only `main`, allowing Alpine security updates to reach the
rolling image after the same amd64/arm64 test matrix. Versioned release tags are never rebuilt
or overwritten.

## License

Copyright © 2026 CodeOpsMS contributors. This project is licensed under
[GPL-3.0-or-later](LICENSE).
