# Changelog

All notable changes to this project are documented in this file. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and releases use
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.5.0] - 2026-10-23

### Changed

- Upgrade the official PHP image from 8.5.10 to 8.5.12 on Alpine 3.24, retaining
  native amd64 and arm64 support and refreshing Alpine runtime security updates.
- Consume nginx 1.30.6 from Alpine's stable 1.30 package line.
- Refresh the build-only PHP PIE image to 1.5.3 and the Dockerfile frontend to 1.28.0,
  with immutable manifest digests.
- Update Buildx setup to 4.4.1, Docker build/push to 7.4.0, artifact upload/download
  to 7.0.2/8.0.2, and SBOM generation to 0.24.3, retaining full commit pins.
- Update shfmt to 3.14.1 with its verified checksum, Trivy to 0.76.1, and zizmor
  to 1.31.1 with zizmor-action 0.7.1.
- Refresh release defaults, validation, integration expectations, and usage examples
  for version 0.5.0. Redis remains at the current stable extension release 6.3.0.
- Describe the CodeOpsMS runtime directly and refresh the repository maintenance checklist
  for ongoing operation after the first stable release.

### Removed

- References to the predecessor project, its startup settings, and unreleased version lines
  from the project documentation.

## [0.4.0] - 2026-09-07

### Added

- Clean, rootless nginx and PHP-FPM implementation based on PHP 8.5.10 and Alpine 3.24.
- Fixed UID/GID 82 runtime, port 8080, PHP-backed health endpoint, validated environment
  configuration, and read-only configuration drop-ins.
- PHP production extension set for common MySQL, PostgreSQL, Redis, internationalization,
  image, archive, and SOAP workloads.
- Native amd64 and arm64 CI, integration tests, 100% first-party configuration coverage,
  vulnerability scanning, SPDX SBOMs, provenance, and attestations.
- Tested-digest GHCR publication, deliberate SemVer releases, and guarded Dependabot
  auto-merge automation.

### Changed

- Pin the available official PHP 8.5.10 multi-architecture image for release validation.
- Verify alternate non-root UID/GID execution and PHP temporary file/session persistence.
- Allow explicit CI candidate publication for external application validation before merge.
- Separate release preparation from publication so application-tested digests are promoted
  without a rebuild.
- Use the image entrypoint, container runtime user settings, dedicated writable volumes,
  and port 8080 when deploying applications.

### Fixed

- Preserve `PATH_INFO` for existing PHP scripts while retaining HTTP 404 for missing scripts.
- Validate PHP-FPM configuration without exposing configured environment values in logs.

[Unreleased]: https://github.com/CodeOpsMS/nginx-php-fpm/compare/0.5.0...HEAD
[0.5.0]: https://github.com/CodeOpsMS/nginx-php-fpm/releases/tag/0.5.0
[0.4.0]: https://github.com/CodeOpsMS/nginx-php-fpm/releases/tag/0.4.0
