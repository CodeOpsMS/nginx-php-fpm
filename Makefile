SHELL := /bin/bash

IMAGE ?= nginx-php-fpm:test
COVERAGE_THRESHOLD ?= 100

.DEFAULT_GOAL := test

.PHONY: lint contract test test-unit coverage integration examples adoption-report verify

lint: contract
	@./scripts/ci/lint.sh

contract:
	@./scripts/ci/check-contract.sh

test: test-unit

test-unit:
	@./scripts/test/unit.sh

coverage:
	@COVERAGE_THRESHOLD="$(COVERAGE_THRESHOLD)" ./scripts/test/coverage.sh

integration:
	@./scripts/test/integration.sh "$(IMAGE)"

examples:
	@./scripts/test/examples.sh "$(IMAGE)"

adoption-report:
	@python3 ./scripts/maintenance/adoption-report.py

verify: lint test coverage integration examples
