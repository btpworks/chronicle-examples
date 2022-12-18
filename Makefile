MAKEFILE_DIR := $(dir $(lastword $(MAKEFILE_LIST)))
include $(MAKEFILE_DIR)/standard_defs.mk

export OPENSSL_STATIC=1

ARCH_TYPE ?= $(shell uname -m | sed -e 's/x86_64/amd64/' -e 's/aarch64/arm64/')

CHRONICLE_BUILDER_IMAGE ?= blockchaintp/chronicle-builder-$(ARCH_TYPE)
CHRONICLE_TP_IMAGE ?= blockchaintp/chronicle-tp-$(ARCH_TYPE)
CHRONICLE_VERSION ?= BTP2.1.0-0.4.0

export DOCKER_BUILDKIT=1
export COMPOSE_DOCKER_CLI_BUILD=1

CLEAN_DIRS := $(CLEAN_DIRS)

DOMAINS := $(shell find . -mindepth 3 -maxdepth 3 -name domain.yaml \
	-exec dirname {} \; | awk -F/ '{print $$NF}')

clean: clean_containers

distclean: clean_docker clean_markers

build: all-domains

clean_containers:
	docker-compose -f docker/docker-compose.yaml rm -f || true

clean_docker:
	docker-compose -f docker/docker-compose.yaml down -v --rmi all || true

$(MARKERS):
	mkdir $(MARKERS)

DOCKER_COMPOSE := docker-compose
DOCKER_TAG := docker tag

define domain_tmpl =
.PHONY: all-domains
all-domains: $(1)

.PHONY: inmem
inmem: $(1)-inmem

.PHONY: stl
stl: $(1)-stl

$(1): $(1)-inmem $(1)-stl $(1)-sdl $(1)-diagrams

$(1)-inmem: $(MARKERS)/$(1)-inmem $(MARKERS)/$(1)-inmem-release

$(1)-stl: $(MARKERS)/$(1)-stl $(MARKERS)/$(1)-stl-release

$(1)-diagrams:
ifeq (,$(shell command -v plantuml))
	@echo "Skipping $(1) diagrams, no plantuml"
else
	@echo "Building $(1) diagrams"
	$(foreach DIAGRAM,$(wildcard domains/$(1)/diagrams/*.puml),plantuml -tsvg -nometadata "$(DIAGRAM)";)
endif

$(MARKERS)/$(1)-inmem: $(MARKERS)
	@echo "Building $(1) debug inmem as docker image chronicle-$(1)-inmem:$(ISOLATION_ID)"
	@$(DOCKER_COMPOSE) -f docker/docker-compose.yaml build -q \
		--build-arg CHRONICLE_VERSION=$(CHRONICLE_VERSION) \
		--build-arg CHRONICLE_BUILDER_IMAGE=$(CHRONICLE_BUILDER_IMAGE) \
		--build-arg RELEASE=no \
		--build-arg FEATURES=inmem \
		--build-arg DOMAIN=$(1)
	@$(DOCKER_TAG) chronicle-domain:$(ISOLATION_ID) \
		chronicle-$(1)-inmem:$(ISOLATION_ID)
	@touch $(MARKERS)/$@

$(MARKERS)/$(1)-stl: $(MARKERS)
	@echo "Building $(1) debug stl as docker image as docker image chronicle-$(1)-stl:$(ISOLATION_ID)"
	@$(DOCKER_COMPOSE) -f docker/docker-compose.yaml build -q \
		--build-arg CHRONICLE_VERSION=$(CHRONICLE_VERSION) \
		--build-arg CHRONICLE_BUILDER_IMAGE=$(CHRONICLE_BUILDER_IMAGE) \
		--build-arg RELEASE=no \
		--build-arg FEATURES="" \
		--build-arg DOMAIN=$(1)
	@$(DOCKER_TAG) chronicle-domain:$(ISOLATION_ID) \
		chronicle-$(1)-stl:$(ISOLATION_ID)
	@touch $(MARKERS)/$@

$(MARKERS)/$(1)-inmem-release: $(MARKERS)
	@echo "Building $(1) release inmem as docker image chronicle-$(1)-inmem-release:$(ISOLATION_ID)"
	@$(DOCKER_COMPOSE) -f docker/docker-compose.yaml build -q \
		--build-arg CHRONICLE_VERSION=$(CHRONICLE_VERSION) \
		--build-arg CHRONICLE_BUILDER_IMAGE=$(CHRONICLE_BUILDER_IMAGE) \
		--build-arg RELEASE=yes \
		--build-arg FEATURES="inmem" \
		--build-arg DOMAIN=$(1)
	@$(DOCKER_TAG) chronicle-domain:$(ISOLATION_ID) \
		chronicle-$(1)-inmem-release:$(ISOLATION_ID)
	@touch $(MARKERS)/$@

$(MARKERS)/$(1)-stl-release: $(MARKERS)
	@echo "Building $(1) release stl as docker image chronicle-$(1)-stl-release:$(ISOLATION_ID)"
	@$(DOCKER_COMPOSE) -f docker/docker-compose.yaml build -q \
		--build-arg CHRONICLE_VERSION=$(CHRONICLE_VERSION) \
		--build-arg CHRONICLE_BUILDER_IMAGE=$(CHRONICLE_BUILDER_IMAGE) \
		--build-arg RELEASE=yes \
		--build-arg FEATURES="" \
		--build-arg DOMAIN=$(1)
	@$(DOCKER_TAG) chronicle-domain:$(ISOLATION_ID) \
		chronicle-$(1)-stl-release:$(ISOLATION_ID)
	@touch $(MARKERS)/$@

$(1)/chronicle.graphql: $(MARKERS)/$(1)-inmem
	@echo "Generating $(1) GraphQL schema in file: domains/$(1)/chronicle.graphql"
	@docker run --env RUST_LOG=debug chronicle-$(1)-inmem:$(ISOLATION_ID) \
		export-schema > domains/$(1)/chronicle.graphql

clean-graphql-$(1):
	rm -f $(1)/chronicle.graphql

.PHONY: $(1)-sdl
$(1)-sdl: $(1)/chronicle.graphql

.PHONY: sdl
sdl: $(1)-sdl

.PHONY: run-$(1)
run-$(1): $(MARKERS)/$(1)-inmem
	docker run -it -e RUST_LOG=debug -p 9982:9982 --rm \
		chronicle-$(1)-inmem:$(ISOLATION_ID) \
			--console-logging pretty serve-graphql --interface 0.0.0.0:9982 \
			--open

run-stl-$(1): $(MARKERS)/$(1)-stl
	export CHRONICLE_IMAGE=chronicle-$(1)-stl; \
	$(DOCKER_COMPOSE) -f docker/stl-domain.yaml up -d

stop-stl-$(1): $(MARKERS)/$(1)-stl
	export CHRONICLE_IMAGE=chronicle-$(1)-stl; \
	$(DOCKER_COMPOSE) -f docker/stl-domain.yaml down


PHONY: build-end-to-end-test
build-end-to-end-test:
	docker build -t chronicle-test:$(ISOLATION_ID) -f docker/chronicle-test/chronicle-test.dockerfile .

.ONESHELL:
SHELL = /bin/bash
.SHELLOPTS = $(if $(SHELLOPTS),$(SHELLOPTS):)pipefail:errexit
.PHONY: test-e2e-$(1)
test-e2e-$(1): $(MARKERS)/$(1)-stl-release build-end-to-end-test
	$(MAKE) run-stl-$(1)
	function stopStack {
		docker logs docker-chronicle-sawtooth-tp-1
		docker logs docker-chronicle-sawtooth-api-1
		docker logs docker-validator-1
		docker-compose -f docker/chronicle.yaml down || true
	}
	trap stopStack EXIT
	docker run --network docker_default chronicle-test:$(ISOLATION_ID)


.PHONY: clean-images-$(1)
clean-images-$(1): $(MARKERS)
	docker rmi chronicle-$(1)-inmem:$(ISOLATION_ID) || true
	docker rmi chronicle-$(1)-inmem-release:$(ISOLATION_ID) || true
	docker rmi chronicle-$(1)-stl:$(ISOLATION_ID) || true
	docker rmi chronicle-$(1)-stl-release:$(ISOLATION_ID) || true
	docker rmi chronicle-test$(ISOLATION_ID) || true
	rm -f $(MARKERS)/*-$(1)

clean-$(1): clean-images-$(1) clean-graphql-$(1)

clean: clean-$(1)

endef

$(foreach domain,$(DOMAINS),$(eval $(call domain_tmpl,$(domain))))
