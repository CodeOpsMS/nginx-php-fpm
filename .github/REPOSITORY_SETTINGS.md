# Repository settings checklist

These controls cannot be represented entirely in the repository. Repository administrators
should verify them when changing repository, package, or organization settings.

## General and pull requests

- Keep `ghcr.io/codeopsms/nginx-php-fpm` public and linked through the OCI source label.
- Enable squash merging and auto-merge; disable merge commits and rebase merging if a linear
  squash-only history is desired.
- Automatically delete head branches after merge.
- Enable immutable GitHub Releases.

## Rulesets

Protect `main` with a branch ruleset that:

- requires changes through pull requests;
- requires the branch to be current before merge;
- requires the status check `CI / gate`;
- blocks force pushes and branch deletion; and
- applies to administrators unless an audited emergency bypass is required.

Protect tags matching `*.*.*` from update and deletion. Full SemVer tags must
remain immutable; only the container aliases `0`, `0.4`, `latest`, and `main` may move.

## Security and Actions

- Enable Dependency Graph, Dependabot Alerts, Dependabot Security Updates, and grouped version
  updates from `.github/dependabot.yml`.
- Enable Secret Scanning, push protection, and private vulnerability reporting.
- Restrict Actions to GitHub-authored actions and the explicitly used allowlist. Require actions
  to be pinned to full commit SHAs.
- Give the default `GITHUB_TOKEN` read-only contents access. Workflow files grant write scopes
  only to package publication, attestation, release, and Dependabot merge jobs.
- Do not enable “Send write tokens to workflows from pull requests.”

After changing a ruleset, use a pull request to confirm that `CI / gate` is the exact required
status context and that an eligible Dependabot patch can enable squash auto-merge only after
CI succeeds.
