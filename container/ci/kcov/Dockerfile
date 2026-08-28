# Kcov is a build-only test dependency. The moving tag makes digest updates
# discoverable by Dependabot while the digest keeps every CI run reproducible.
# hadolint ignore=DL3007
FROM kcov/kcov:latest@sha256:481289ae32e55e5b733019515acd10948a4f76dfed381765577db909664fc603

# This image is a one-shot CLI helper, not a service.
HEALTHCHECK NONE
USER 65532:65532
