# Changelog

All notable changes to this project are documented in this file. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and releases use
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

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

[Unreleased]: https://github.com/CodeOpsMS/nginx-php-fpm/compare/0.4.0...HEAD
[0.4.0]: https://github.com/CodeOpsMS/nginx-php-fpm/releases/tag/0.4.0
