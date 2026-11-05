.PHONY: help build-env build validate test clean

REGISTRY  ?= ghcr.io
IMAGE_ORG ?= binmgr
IMAGE     ?= $(REGISTRY)/$(IMAGE_ORG)/icecast

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*## "}; {printf "  %-20s %s\n", $$1, $$2}'

build-env: ## Build the build environment image (docker/Dockerfile.build)
	docker build --file docker/Dockerfile.build --tag $(IMAGE):build .

build: ## Build Icecast for one arch: make build ARCH=amd64
ifndef ARCH
	$(error ARCH is required, e.g. make build ARCH=amd64)
endif
	@mkdir -p binaries
	docker run --rm \
	  --name icecast-build-$$(tr -dc 'a-z0-9' </dev/urandom | head -c8) \
	  --platform linux/$(ARCH) \
	  -v "$(PWD)/binaries:/output" \
	  $(IMAGE):build \
	  build-icecast $(ARCH)

clean: ## Remove local build artifacts
	@rm -rf binaries/

validate: ## Validate all workflow files with act --list
	@for f in .github/workflows/*.yml .gitea/workflows/*.yml .forgejo/workflows/*.yml; do \
	  [ -f "$$f" ] || continue; \
	  echo "==> $$f"; \
	  act --list -W "$$f" || exit 1; \
	done
	@echo "All workflows valid."

test: validate ## Alias for validate (workflow lint; binary builds run in CI)
