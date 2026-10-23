# Community and adoption

## Get help or share a result

- Ask general questions or suggest improvements in
  [Discussions](https://github.com/CodeOpsMS/nginx-php-fpm/discussions).
- Open a [migration-help request](https://github.com/CodeOpsMS/nginx-php-fpm/issues/new?template=migration-help.yml)
  for a reproducible deployment problem.
- Share an [adoption report](https://github.com/CodeOpsMS/nginx-php-fpm/issues/new?template=adoption-report.yml)
  after trying the image. Reports can cover a local experiment, staging, or production.
- Report suspected vulnerabilities through the [private security process](../SECURITY.md).

The first adoption milestone is five independent reports and two documented migrations.
These are goals, not claims of existing users. The bundled PHP application is a reference
example and is not counted as independent adoption.

## How maintainers turn feedback into documentation

For each report, record the exact image tag/digest, CPU architecture, application or
framework, deployment environment, and any changes needed. Ask for a minimal public
reproduction when an issue cannot be reproduced from the report. Preserve the distinction
between an evaluated image and a production deployment.

When a migration succeeds, ask the reporter whether its public report may be linked as
a case study. A case study should name its source report, state what was actually tested,
show the configuration changes, and link the reporter's confirmation. Do not infer a
company endorsement from a GitHub issue or present the reference example as a customer.

Close resolved help requests with the tested fix and update the migration guide when the
same problem is likely to affect others. Leave unsupported application requirements
visible so future adopters can judge compatibility before switching.

## Measure interest with GitHub data

Maintainers can collect an aggregate snapshot with their existing GitHub CLI login:

```console
make adoption-report
```

Or choose the destination explicitly:

```console
python3 scripts/maintenance/adoption-report.py --repo CodeOpsMS/nginx-php-fpm --output build/adoption
```

The command writes timestamped JSON and Markdown reports under the ignored `build/`
directory. It collects stars, forks, watchers, GitHub views/clones, and the number of
public adoption reports. It does not include referrer URLs or visitor identities.
Traffic endpoints require appropriate maintainer access; unavailable traffic is marked
unavailable instead of being reported as zero.

GitHub traffic data covers a rolling 14-day window. Review snapshots weekly while the
window is available. Overlapping snapshots must not be added together, and daily unique
visitor counts must not be summed to invent a period-wide unique-user count. CI checkouts,
bots, and maintainer visits can contribute to the numbers. Stars, clones, and image pulls
are indicators of interest, not active-installation counts. A public adoption report is
self-reported feedback and also does not prove an ongoing installation.

The reporter runs locally with the maintainer's existing CLI authentication. It does not
copy that authentication into GitHub Actions or introduce a tracking service.

## GitHub launch and follow-up

Publish the [migration article](articles/migrating-to-a-maintained-php-container.md) and
link it from the README and a project announcement. Keep announcements explicit about
the maintainer's affiliation, required migration changes, supported PHP version, and
where users can ask for help.

For the first month, review reports and the aggregate snapshot once a week. Track the
following in the project's adoption follow-up issue:

1. New migration questions and their resolution.
2. Independently reported trials, staging deployments, and production deployments.
3. Documentation fixes prompted by those reports.
4. Case-study permission and reporter confirmation for each published migration.
5. Which GitHub links or announcements were published and when.

This launch uses GitHub for documentation, discussion, feedback, and distribution through
GHCR. External registries and social platforms are outside this launch's scope.
