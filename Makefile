R_VERSION ?= 4.6.0
BASE_IMAGE ?= debian:13-slim
BASE_LABEL ?= debian13
CAPSULE_NAME ?= chatgpt-r-capsule

IMAGE := $(CAPSULE_NAME):r-$(R_VERSION)-$(BASE_LABEL)
DIST := dist
PKG_DIST := $(DIST)/packages
TARBALL := $(DIST)/$(CAPSULE_NAME)-$(R_VERSION)-$(BASE_LABEL)-x86_64.tar.gz

.PHONY: build capsule test-image test-capsule package clean shell

build:
	docker build \
		--build-arg R_VERSION=$(R_VERSION) \
		--build-arg BASE_IMAGE=$(BASE_IMAGE) \
		--build-arg BASE_LABEL=$(BASE_LABEL) \
		--build-arg CAPSULE_NAME=$(CAPSULE_NAME) \
		-t $(IMAGE) .

capsule: build
	mkdir -p $(DIST)
	cid=$$(docker create $(IMAGE)); \
	docker cp $$cid:/out/$$(basename $(TARBALL)) $(TARBALL); \
	docker rm $$cid
	@echo "Wrote $(TARBALL)"

test-image: build
	docker run --rm $(IMAGE) \
		/opt/$(CAPSULE_NAME)/Rscript-capsule -e 'library(remotes); library(bench); library(microbenchmark); library(ggplot2); cat("image test OK\n")'

test-capsule: capsule
	docker run --rm \
		-v "$(PWD)/$(DIST):/dist:ro" \
		$(BASE_IMAGE) \
		bash -c 'tar -xzf /dist/$$(basename $(TARBALL)) -C /opt && /opt/$(CAPSULE_NAME)/Rscript-capsule -e "library(remotes); library(bench); library(microbenchmark); library(ggplot2); cat(\"extracted capsule test OK\\n\")"'

package: build
	@test -n "$(PKG)" || { echo "usage: make package PKG=cran::dplyr|bioc::Biostrings|/path/to/pkg"; exit 2; }
	mkdir -p $(PKG_DIST)
	if [ -e "$(PKG)" ]; then \
		pkg_abs=$$(realpath "$(PKG)"); \
		pkg_base=$$(basename "$$pkg_abs"); \
		pkg_dir=$$(dirname "$$pkg_abs"); \
		docker run --rm \
			-e PKG="local::/pkg-src/$$pkg_base" \
			-e R_VERSION="$(R_VERSION)" \
			-e CAPSULE_NAME="$(CAPSULE_NAME)" \
			-e BASE_LABEL="$(BASE_LABEL)" \
			-v "$(PWD):/work:ro" \
			-v "$(PWD)/$(PKG_DIST):/out" \
			-v "$$pkg_dir:/pkg-src:ro" \
			$(IMAGE) \
			bash /work/scripts/build-package.sh; \
	else \
		docker run --rm \
			-e PKG="$(PKG)" \
			-e R_VERSION="$(R_VERSION)" \
			-e CAPSULE_NAME="$(CAPSULE_NAME)" \
			-e BASE_LABEL="$(BASE_LABEL)" \
			-v "$(PWD):/work:ro" \
			-v "$(PWD)/$(PKG_DIST):/out" \
			$(IMAGE) \
			bash /work/scripts/build-package.sh; \
	fi

shell: build
	docker run --rm -it $(IMAGE) bash

clean:
	rm -rf $(DIST)/*.tar.gz $(PKG_DIST)/*.tar.gz