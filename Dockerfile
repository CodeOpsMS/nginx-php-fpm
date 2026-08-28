# syntax=docker/dockerfile:1.26.0@sha256:ecfaec9ed6d810b56388c508f4121597bfbba70d41a6dfeee4d8cad5f295fc32

# PHP 8.5.10 is not available from the official image registry yet. The
# release workflow refuses to publish 0.4.0 until this literal bootstrap pin
# has been updated. Literal references keep both images visible to Dependabot.
FROM ghcr.io/php/pie:bin@sha256:edb7cf2c03e26a2afc91fc4abdafdf7d7528ca4674ccb532310d81f1adc949c5 AS pie
FROM php:8.5.9-fpm-alpine3.24@sha256:9dc81f4086ea5402227a6bcc489b04b4baba12394624d9621faa92ed812fb8ee AS php-base

FROM php-base AS extension-builder

COPY container/extensions/composer.json /tmp/extensions/composer.json

# This stage is discarded. No compiler, headers, PIE, or extension source is
# copied into the runtime stage.
# hadolint ignore=DL3018,SC2086
RUN set -eux; \
    apk add --no-cache --virtual .php-build-deps \
        $PHPIZE_DEPS \
        freetype-dev \
        icu-dev \
        libjpeg-turbo-dev \
        libpng-dev \
        libwebp-dev \
        libxml2-dev \
        libzip-dev \
        linux-headers \
        oniguruma-dev \
        postgresql-dev; \
    docker-php-ext-configure gd \
        --with-freetype \
        --with-jpeg \
        --with-webp; \
    docker-php-ext-install -j"$(nproc)" \
        bcmath \
        exif \
        gd \
        intl \
        mbstring \
        mysqli \
        opcache \
        pdo_mysql \
        pdo_pgsql \
        soap \
        zip

# The dollar-prefixed variables in the PHP snippets belong to PHP, not sh.
# hadolint ignore=SC2016
RUN --mount=type=bind,from=pie,source=/pie,target=/usr/local/bin/pie \
    set -eux; \
    redis_version="$(php -r '$config = json_decode(file_get_contents("/tmp/extensions/composer.json"), true, flags: JSON_THROW_ON_ERROR); echo $config["require"]["phpredis/phpredis"];')"; \
    pie install \
        --no-interaction \
        --no-system-dependencies-check \
        --skip-enable-extension \
        "phpredis/phpredis:${redis_version}"; \
    docker-php-ext-enable redis; \
    php -r '$required = ["bcmath", "exif", "gd", "intl", "mbstring", "mysqli", "opcache", "pdo_mysql", "pdo_pgsql", "redis", "soap", "zip"]; foreach ($required as $extension) { if (!extension_loaded($extension)) { fwrite(STDERR, "missing extension: {$extension}\n"); exit(1); } }'

FROM php-base AS runtime-rootfs

ARG NGINX_VERSION=1.30

# Alpine package revisions intentionally float inside the pinned stable branch,
# so daily rebuilds receive security fixes. nginx tracks the stable 1.30 line.
# hadolint ignore=DL3018
RUN set -eux; \
    apk add --no-cache \
        bash \
        freetype \
        icu-libs \
        libjpeg-turbo \
        libpng \
        libpq \
        libwebp \
        libxml2 \
        libzip \
        "nginx~${NGINX_VERSION}" \
        oniguruma \
        tini \
        tzdata

COPY --from=extension-builder /usr/local/lib/php/extensions/ /usr/local/lib/php/extensions/
COPY --from=extension-builder /usr/local/etc/php/conf.d/ /usr/local/etc/php/conf.d/

# The dollar-prefixed variables in the PHP snippet belong to PHP, not sh.
# hadolint ignore=SC2016
RUN set -eux; \
    cp "${PHP_INI_DIR}/php.ini-production" "${PHP_INI_DIR}/php.ini"; \
    rm -rf \
        /tmp/* \
        /usr/local/include/php \
        /usr/local/lib/php/build \
        /var/cache/apk/* \
        /var/lib/nginx/html; \
    rm -f \
        /usr/local/bin/docker-php-ext-configure \
        /usr/local/bin/docker-php-ext-enable \
        /usr/local/bin/docker-php-ext-install \
        /usr/local/bin/docker-php-source \
        /usr/local/bin/php-config \
        /usr/local/bin/phpize; \
    php -r '$required = ["bcmath", "exif", "gd", "intl", "mbstring", "mysqli", "opcache", "pdo_mysql", "pdo_pgsql", "redis", "soap", "zip"]; foreach ($required as $extension) { if (!extension_loaded($extension)) { fwrite(STDERR, "missing extension: {$extension}\n"); exit(1); } }'; \
    test ! -e /usr/local/bin/pie; \
    for unexpected_command in composer git certbot; do \
        if command -v "${unexpected_command}" >/dev/null 2>&1; then \
            echo "unexpected runtime command: ${unexpected_command}" >&2; \
            exit 1; \
        fi; \
    done

COPY rootfs/ /
COPY --chmod=0644 LICENSE /usr/share/licenses/nginx-php-fpm/LICENSE

RUN set -eux; \
    chmod 0755 \
        /usr/local/bin/container-entrypoint \
        /usr/local/bin/healthcheck \
        /usr/local/bin/supervise; \
    chmod 0644 \
        /usr/local/lib/nginx-php-fpm/config.sh \
        /usr/local/lib/nginx-php-fpm/healthz.php \
        /usr/local/share/nginx-php-fpm/templates/*.tpl; \
    mkdir -p \
        /etc/nginx/conf.d \
        /etc/nginx/server.d \
        /etc/php/conf.d \
        /etc/php-fpm.d; \
    chown -R www-data:www-data /var/www/html; \
    find /var/www/html -type d -exec chmod 0755 '{}' +; \
    find /var/www/html -type f -exec chmod 0644 '{}' +

FROM scratch AS final

ARG VERSION=0.4.0
ARG VCS_REF=unknown
ARG BUILD_DATE=unknown

LABEL org.opencontainers.image.title="nginx-php-fpm" \
      org.opencontainers.image.description="Rootless nginx and PHP-FPM application container" \
      org.opencontainers.image.url="https://github.com/CodeOpsMS/nginx-php-fpm" \
      org.opencontainers.image.source="https://github.com/CodeOpsMS/nginx-php-fpm" \
      org.opencontainers.image.documentation="https://github.com/CodeOpsMS/nginx-php-fpm#readme" \
      org.opencontainers.image.vendor="CodeOpsMS" \
      org.opencontainers.image.licenses="GPL-3.0-or-later" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.created="${BUILD_DATE}"

# Re-root the cleaned filesystem so the final image does not inherit the PHP
# base image's EXPOSE 9000 or other runtime metadata.
# hadolint ignore=DL3067
COPY --from=runtime-rootfs / /

ENV PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    PHP_INI_DIR="/usr/local/etc/php" \
    DOCUMENT_ROOT="/var/www/html" \
    TZ="UTC" \
    PHP_MEMORY_LIMIT="256M" \
    PHP_UPLOAD_MAX_FILESIZE="64M" \
    PHP_POST_MAX_SIZE="64M" \
    PHP_MAX_EXECUTION_TIME="30" \
    PHP_DISPLAY_ERRORS="0" \
    PHP_OPCACHE_ENABLE="1" \
    PHP_OPCACHE_VALIDATE_TIMESTAMPS="0" \
    NGINX_CLIENT_MAX_BODY_SIZE="64m" \
    PHP_INI_SCAN_DIR="/usr/local/etc/php/conf.d:/tmp/nginx-php-fpm/current/php/conf.d:/etc/php/conf.d"

USER 82:82
WORKDIR /var/www/html

EXPOSE 8080
STOPSIGNAL SIGTERM

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD ["/usr/local/bin/healthcheck"]

ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/container-entrypoint"]
CMD ["/usr/local/bin/supervise"]
