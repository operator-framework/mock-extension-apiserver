##########################
#  MEA - Build and Test  #
##########################

SHELL := /bin/bash
PKG   := github.com/operator-framework/mock-extension-apiserver
CMDS  := $(addprefix bin/, $(shell go list ./cmd/... | xargs -I{} basename {}))
CODEGEN := ./vendor/k8s.io/code-generator/generate_groups.sh
IMAGE_REPO := quay.io/coreos/olm
IMAGE_TAG ?= "dev"
KUBE_DEPS := api apiextensions-apiserver apimachinery code-generator kube-aggregator kubernetes
KUBE_RELEASE := release-1.11
MOD_FLAGS := $(shell (go version | grep -q 1.11) && echo -mod=vendor)

.PHONY: build test run clean vendor vendor-update \
	coverage coverage-html e2e .FORCE

all: test build

test: clean cover.out

unit:
	go test $(MOD_FLAGS) -v -race ./pkg/...

cover.out: schema-check
	go test $(MOD_FLAGS) -v -race -coverprofile=cover.out -covermode=atomic \
		-coverpkg ./pkg/... ./pkg/...

coverage: cover.out
	go tool cover -func=cover.out

coverage-html: cover.out
	go tool cover -html=cover.out

build: build_cmd=build
build: clean $(CMDS)

# build versions of the binaries with coverage enabled
build-coverage: build_cmd=test -c -covermode=count -coverpkg ./pkg/...
build-coverage: clean $(CMDS)

$(CMDS):
	CGO_ENABLED=0 go $(build_cmd) $(MOD_FLAGS) $(version_flags) -o $@ $(PKG)/cmd/$(shell basename $@);

# kube dependencies all should be at the same release and should match up with client go
# go.mod currently doesn't support specifying a branch name to track, and kube isn't publishing good version tags
$(KUBE_DEPS):
	go get -m k8s.io/$@@$(KUBE_RELEASE)

vendor: $(KUBE_DEPS)
	go get -m github.com/docker/docker@v0.0.0-20180422163414-57142e89befe
	go mod tidy
	go mod vendor

clean:
	@rm -rf cover.out
	@rm -rf bin

# Must be run in gopath: https://github.com/kubernetes/kubernetes/issues/67566
# use container-codegen
codegen:
	cp scripts/generate_groups.sh vendor/k8s.io/code-generator/generate_groups.sh
	mkdir -p vendor/k8s.io/code-generator/hack
	cp boilerplate.go.txt vendor/k8s.io/code-generator/hack/boilerplate.go.txt
	go run vendor/k8s.io/kube-openapi/cmd/openapi-gen/openapi-gen.go --logtostderr -i ./vendor/k8s.io/apimachinery/pkg/runtime,./vendor/k8s.io/apimachinery/pkg/apis/meta/v1,./vendor/k8s.io/apimachinery/pkg/version,./pkg/apis/anything/v1alpha1 -p $(PKG)/pkg/apis/openapi -O zz_generated.openapi -h boilerplate.go.txt -r /dev/null
	$(CODEGEN) all $(PKG)/pkg/client $(PKG)/pkg/apis "anything:v1alpha1"

container-codegen:
	docker build -t mea:codegen -f codegen.Dockerfile .
	docker run --name temp-codegen mea:codegen /bin/true
	docker cp temp-codegen:/go/src/github.com/operator-framework/mock-extension-apiserver/pkg/apis/. ./pkg/apis
	docker rm temp-codegen

# Must be run in gopath: https://github.com/kubernetes/kubernetes/issues/67566
verify-codegen: codegen
	git diff --exit-code
