.PHONY: multiarch push build run

# Default values for variables
OWNER = mastrogeppetto
IMAGE  ?= nglab-desktop_multiarch
TAG   ?= latest
# you can choose other base image versions
IMAGE ?= ubuntu:jammy-20220531
# IMAGE ?= nvidia/cuda:10.1-cudnn7-devel-ubuntu18.04
# choose from supported flavors (see available ones in ./flavors/*.yml)
FLAVOR ?= lxde
# arm64 or amd64
ARCH ?= amd64
# apt source
LOCALBUILD ?= 0

# These files will be generated from teh Jinja templates (.j2 sources)
templates = Dockerfile rootfs/etc/supervisor/conf.d/supervisord.conf

multiarch:
	if docker manifest inspect $(OWNER)/$(IMAGE):$(TAG) ; then docker manifest rm $(OWNER)/$(IMAGE):$(TAG) ; fi
	ARCH=arm64 make push
	ARCH=amd64 make push
	docker manifest create \
		$(OWNER)/$(IMAGE):$(TAG) \
		--amend $(OWNER)/$(IMAGE)_amd64:$(TAG) \
		--amend $(OWNER)/$(IMAGE)_arm64:$(TAG)
	docker manifest push $(OWNER)/$(IMAGE):$(TAG)

push:
	ARCH=$(ARCH) make build
	docker tag $(IMAGE)_$(ARCH):$(TAG) $(OWNER)/$(IMAGE)_$(ARCH):$(TAG)
	docker push $(OWNER)/$(IMAGE)_$(ARCH):$(TAG)

# Rebuild the container image
build: $(templates)
	cp Dockerfile Dockerfile.$(ARCH)
	docker buildx build --load --platform linux/$(ARCH) -t $(IMAGE)_$(ARCH):$(TAG) -f Dockerfile.$(ARCH) .
#	docker build -t $(IMAGE):$(TAG) -f Dockerfile.$(ARCH) .

# Test run the container
# the local dir will be mounted under /src read-only
run:
	docker run --privileged --rm \
		-p 6080:80 \
		-v ${PWD}:/src:ro \
		-e USER=user -e PASSWORD=user \
		-e ALSADEV=hw:2,0 \
		-e SSL_PORT=443 \
		-e RELATIVE_URL_ROOT=approot \
		-e OPENBOX_ARGS="--startup '/usr/bin/wireshark -ki eth0'" \
		-v ${PWD}/ssl:/etc/nginx/ssl \
		--device /dev/snd \
		--name ubuntu-desktop-lxde-test \
		$(IMAGE)_$(ARCH):$(TAG)

# Connect inside the running container for debugging
shell:
	docker exec -it ubuntu-desktop-lxde-test bash

# Generate the SSL/TLS config for HTTPS
gen-ssl:
	mkdir -p ssl
	openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
		-keyout ssl/nginx.key -out ssl/nginx.crt

clean:
	rm -f $(templates)

extra-clean:
	docker rmi $(IMAGE):$(TAG)
	docker image prune -f

# Run jinja2cli to parse Jinja template applying rules defined in the flavors definitions
%: %.j2 flavors/$(FLAVOR).yml
	docker run --rm -v $(shell pwd):/data vikingco/jinja2cli \
		-D flavor=$(FLAVOR) \
		-D image=$(IMAGE) \
		-D localbuild=$(LOCALBUILD) \
		-D arch=$(ARCH) \
		$< flavors/$(FLAVOR).yml > $@ || rm $@
