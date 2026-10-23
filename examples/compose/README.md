# Run a PHP application with Docker Compose

This self-contained example serves the checked-in `public/` directory through nginx and
PHP-FPM. It uses the stable 0.5.0 image, runs as UID/GID 82, keeps the root filesystem and
application mount read-only, and gives the services a writable `/tmp`.

Requirements: Docker Engine or Docker Desktop with Docker Compose v2 supporting `--wait`.
The host directories must be searchable and the files readable by UID 82.

## Start and check the application

From the repository root:

```console
docker compose --file examples/compose/compose.yaml up --detach --wait
curl --fail http://localhost:8080/healthz
curl --fail http://localhost:8080/hello
curl --fail http://localhost:8080/example.txt
```

The health endpoint returns `ok`. `/hello` is routed to the PHP front controller:

```json
{"message":"Your PHP application is running.","path":"/hello"}
```

`/example.txt` is served directly as a static file. HTTP is bound to `127.0.0.1`;
place a reverse proxy in front of the application for public access and TLS.

If port 8080 is already in use, keep the same environment when starting and stopping:

```console
HTTP_PORT=8081 docker compose --file examples/compose/compose.yaml up --detach --wait
curl --fail http://localhost:8081/hello
```

## Use your own application

Replace the bind source with your application's public directory. Build dependencies
before deployment and keep them in the application tree where the application expects
them. `DOCUMENT_ROOT` is the container path, not the host path. Mount application-specific
writable directories separately and grant only the runtime UID/GID the required access.

For reproducible deployments, set `IMAGE` to the manifest digest in the
[release](https://github.com/CodeOpsMS/nginx-php-fpm/releases/tag/0.5.0):

```console
IMAGE=ghcr.io/codeopsms/nginx-php-fpm@sha256:51ed3a90780c217cb39d747e8e7b406c2563c1352866212a7953439a5c769f65 docker compose --file examples/compose/compose.yaml up --detach --wait
```

See the [migration guide](../../docs/migrating-from-richarvey.md) for legacy environment
settings, identity changes, TLS, and startup hooks.

## Logs, shutdown, and verification

```console
docker compose --file examples/compose/compose.yaml logs web
docker compose --file examples/compose/compose.yaml down
```

Maintainers test this exact Compose file on native amd64 and arm64 using
`make examples IMAGE=<image-under-test>`. The test uses an isolated project and a random
localhost port, then removes its own containers and network.
