SHELL := /bin/bash

IMAGE ?= nginx-php-fpm:test
COVERAGE_THRESHOLD ?= 100

.DEFAULT_GOAL := test

.PHONY: lint contract test test-unit coverage integration verify

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

verify: lint test coverage integration
