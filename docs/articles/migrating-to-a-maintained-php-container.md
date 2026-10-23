# Migrating from richarvey/nginx-php-fpm to a maintained rootless PHP container

Published 2026-10-23 by CodeOpsMS, maintainer of
[CodeOpsMS/nginx-php-fpm](https://github.com/CodeOpsMS/nginx-php-fpm).

An nginx/PHP-FPM container often stays in a Compose file for years. Moving to a current
runtime is easier when the replacement documents both its maintenance process and the
configuration changes an existing application needs. This walkthrough uses a small PHP
application to explain that move. It is a reproducible reference example, not a report
about a third-party production deployment.

CodeOpsMS/nginx-php-fpm is an independent implementation. Release
[0.5.0](https://github.com/CodeOpsMS/nginx-php-fpm/releases/tag/0.5.0) combines PHP 8.5.12,
nginx 1.30.6, and Alpine 3.24.3 for amd64 and arm64. The runtime runs as an unprivileged
user, supports a read-only root filesystem, and includes release SBOMs and provenance.
Applications migrating from richarvey/nginx-php-fpm need to adapt their configuration.

## Start with a working example

From a checkout of this repository:

```console
docker compose --file examples/compose/compose.yaml up --detach --wait
curl --fail http://localhost:8080/healthz
curl --fail http://localhost:8080/hello
curl --fail http://localhost:8080/example.txt
```

The first request checks nginx and PHP-FPM together. The second reaches the PHP front
controller; the final request serves a static file. The example binds to localhost,
mounts its application read-only, drops Linux capabilities, and provides writable
temporary storage. Its [Compose file](../../examples/compose/compose.yaml) and
[instructions](../../examples/compose/README.md) are part of the repository.

Maintainers run this example in native amd64 and arm64 CI. The runtime contract suite
also exercises alternate non-root identities, PHP temporary/session storage,
configuration drop-ins, missing PHP scripts, health semantics, and SIGTERM propagation.
Your application's own tests are the next layer of validation.

## Change the port and environment names

For an existing service exposing `8080:80`, change the container side to `8080:8080`.
Point `DOCUMENT_ROOT` to the application's public directory inside the container.
Rename `WEBROOT` to `DOCUMENT_ROOT` and `PHP_MEM_LIMIT` to `PHP_MEMORY_LIMIT`.

For example:

```yaml
ports:
  - "127.0.0.1:8080:8080"
environment:
  DOCUMENT_ROOT: /srv/app/public
  PHP_MEMORY_LIMIT: 256M
volumes:
  - ./app:/srv/app:ro
```

These are the application-specific fields of a service. Use the
[complete migration example](../migrating-from-richarvey.md#convert-a-compose-service)
for the image, temporary filesystem, and runtime restrictions. Check every old flag:
some have new names, some are defaults, and some belong in your deployment pipeline.

## Decide where application preparation belongs

The CodeOpsMS runtime starts nginx and PHP-FPM. It does not clone application code,
install Composer dependencies, execute arbitrary startup hooks, or obtain certificates.
Prepare application code and dependencies before deployment, and terminate TLS at a
reverse proxy or ingress.

This changes deployments that depended on `GIT_REPO`, startup Composer installation,
`RUN_SCRIPTS`, or the bundled Let's Encrypt helpers. Move those operations to explicit
build or deployment steps. Keep database migrations and background workers in the
application's deployment design rather than assuming that the web container runs them.

Also review PHP compatibility. A move from PHP 8.2 to 8.5 affects the application and its
dependencies independently of the container. Run application tests, check Composer
platform requirements in a matching environment, and inventory extensions before switching.
The image includes a documented production extension set; it does not provide the legacy
image's complete collection of tools and modules.

## Make writable paths explicit

The default runtime identity is UID/GID `82:82`. Every parent directory of a mounted
application must be searchable and its files readable by that identity. Application
uploads, caches, or other mutable data need their own writable volumes and suitable
permissions.

For existing data owned by another non-root identity, Compose `user: "1000:101"` selects
that identity without recursively changing the volume's ownership. Keep `/tmp` writable
and test application-specific writable directories under the chosen identity. If sessions
must survive replacement, configure a persistent application session store; the default
temporary filesystem is ephemeral.

## Check a candidate before moving traffic

Start the new service on a separate localhost port and exercise real application paths:
authentication, uploads, sessions, database and Redis access, background work, and any
custom nginx configuration. Check both successful and missing routes. Keep the old
configuration and an application-compatible rollback plan while switching the reverse proxy.

Each release contains `digests.txt` and separate SPDX SBOMs for amd64 and arm64. Verify
the release provenance:

```console
gh attestation verify \
  oci://ghcr.io/codeopsms/nginx-php-fpm:0.5.0 \
  --repo CodeOpsMS/nginx-php-fpm
```

Use the tested manifest digest in the deployment. Stable full-version tags are immutable;
security fixes arrive as new patch releases. Daily tested `main` rebuilds are a preview
channel and do not refresh an already pinned stable image.

## Share what the migration needed

The [migration guide](../migrating-from-richarvey.md) includes the detailed flag mapping,
extension differences, custom configuration paths, and cutover checks. For a concrete
problem, open a
[migration-help request](https://github.com/CodeOpsMS/nginx-php-fpm/issues/new?template=migration-help.yml).
Questions and ideas are welcome in
[Discussions](https://github.com/CodeOpsMS/nginx-php-fpm/discussions).

An [adoption report](https://github.com/CodeOpsMS/nginx-php-fpm/issues/new?template=adoption-report.yml)
with the release, architecture, application type, and configuration changes helps the
next user. Reports distinguish experiments, staging, and production use. With the
reporter's permission, successful migrations can become attributable case studies.
