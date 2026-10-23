# Maintenance and security updates

## Supported stable release

The stable release is [0.5.0](https://github.com/CodeOpsMS/nginx-php-fpm/releases/tag/0.5.0),
published on 2026-10-23. It contains PHP 8.5.12, nginx 1.30.6, and Alpine 3.24.3.
The [security policy](../SECURITY.md) defines the supported release line.

| Channel | How it changes | Intended use |
| --- | --- | --- |
| Full version, for example `0.5.0` | Immutable; never rebuilt or overwritten | Pin a tested stable release |
| Release manifest digest | Immutable content address | Reproducible deployment |
| `0.5`, `0`, `latest` | Advance when a new matching stable release is published | Discover a new release; validate it before deployment |
| `main` | Successful main CI and daily tested rebuilds | Evaluate upcoming changes and Alpine package updates |

## Maintenance cadence

- Dependabot checks Docker, build-only extension, and GitHub Actions dependencies daily.
- CI rebuilds and verifies `main` daily, using the current packages in the pinned Alpine
  stable branch. A failing build, integration test, or security scan blocks publication.
- Stable publication is a deliberate maintainer operation. Supported security fixes are
  delivered in new patch releases after the same native checks and application validation.
  A successful daily `main` build does not replace a published stable image.
- Patch/digest version updates normally wait three days and minor updates seven days;
  security updates bypass the configured Dependabot cooldown. PHP minor and major changes
  require maintainer review.

Applications must move to the fixed release or digest to receive a stable security fix.
There is no automatic refresh of a pinned deployment. Read the
[changelog](../CHANGELOG.md) and [release notes](https://github.com/CodeOpsMS/nginx-php-fpm/releases)
when evaluating an update.

## What a published release proves

Native `linux/amd64` and `linux/arm64` jobs test the exact platform digests for runtime
metadata, extensions, rootless/read-only operation, configuration, PHP routing, health,
and shutdown. Source CI enforces 100% line coverage for the instrumentable configuration
library. The checked-in Compose application is also run against the candidate in both
architectures.

The release scan blocks fixable HIGH/CRITICAL findings according to repository policy.
Scan results reflect the vulnerability database at scan time; evaluate new advisories
against deployed releases as they become available. Each release includes platform SPDX
SBOMs, platform and manifest digests, and verifiable GitHub provenance.

Follow [supply-chain verification](../README.md#supply-chain-verification) and report
suspected vulnerabilities using the [private reporting procedure](../SECURITY.md#reporting-a-vulnerability).
The exact preparation/promotion process is documented in
[CONTRIBUTING.md](../CONTRIBUTING.md#releases).
