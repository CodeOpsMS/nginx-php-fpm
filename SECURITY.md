# Security policy

## Supported versions

Only the latest release line receives security updates.

| Version | Supported |
| --- | --- |
| `0.4.x` | Yes |

The moving `main` image is a preview of the current default branch and is not a supported
release channel. Production deployments should pin a released image digest.

## Reporting a vulnerability

Do not open a public issue for a suspected vulnerability. Use the repository's
[private vulnerability reporting form](https://github.com/CodeOpsMS/nginx-php-fpm/security/advisories/new)
and include:

- the affected image tag or manifest digest and architecture;
- a minimal reproduction or proof of concept;
- the impact and any known mitigations; and
- whether the report may be shared with an upstream project.

Maintainers will acknowledge the report through the private advisory, investigate it, and
coordinate disclosure and a fixed release when appropriate. Please keep details private until
the advisory is published.

## Release integrity

Published images include SPDX SBOMs and GitHub artifact attestations. Verify a release before
deployment as described in the README. CI rejects fixable `HIGH` and `CRITICAL` findings. Any
temporary vulnerability exception must identify the CVE, document the rationale and mitigation,
link a tracking issue, and specify an expiration date.
