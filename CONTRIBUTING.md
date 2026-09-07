# Contributing

Thank you for helping improve nginx-php-fpm. Changes should preserve the small, rootless,
production-oriented runtime and its documented public contract.

## Development requirements

- Bash 5 or later
- Docker with Buildx
- Bats Core
- Kcov
- ShellCheck
- shfmt
- Hadolint
- actionlint

Use the versions pinned in `.github/workflows/ci.yml` when reproducing CI. On macOS, Kcov is
most reliably run in a Linux development environment or CI.

## Local checks

Run source validation and tests:

```console
make lint
make contract
make test
make coverage
```

Build and exercise the actual container:

```console
docker build --tag nginx-php-fpm:test .
make integration IMAGE=nginx-php-fpm:test
```

`make verify IMAGE=nginx-php-fpm:test` runs the complete local suite. Coverage for the
instrumentable first-party configuration library must remain at 100%.

## Pull requests

- Base changes on `main` and keep each pull request focused.
- Update tests and English documentation whenever behavior or the runtime contract changes.
- Do not weaken rootless execution, read-only-root support, configuration validation, health
  semantics, supply-chain checks, or vulnerability gates without a documented security review.
- Pin GitHub Actions to full commit SHAs and annotate each pin with its release tag.
- Do not add runtime compilers, package managers, arbitrary startup hooks, TLS automation, or
  source synchronization without prior design discussion.
- Ensure the required `CI / gate` check succeeds on the current pull-request head.

Maintainers squash-merge pull requests. Dependabot patch, digest, and minor updates are eligible
for automatic squash merge after CI; PHP 8.6 or newer and major updates require review.

## Releases

Releases are created only through the manual `Release` workflow on the current `main` commit.
First dispatch it with `publish_release=false` (the default). The workflow validates prior CI,
builds each architecture once, tests and scans the exact digests, and publishes candidate
attestations and SBOMs. Download the `release-amd64` and `release-arm64` artifacts from that
successful run and test the `digest-*` image references with the consuming application.

After application validation, dispatch the same workflow on the same main commit with that
`candidate_run_id` and `publish_release=true`. It verifies the preparation run and signed
provenance, retests and rescans the same digests without rebuilding, creates the
multi-architecture index, and publishes the matching Git tag and GitHub release. A changed
main commit requires a new preparation and application test. Never move a full SemVer image
or Git tag.
