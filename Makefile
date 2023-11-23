SHELL := /bin/bash
.ONESHELL:
.SHELLFLAGS := -eu -o pipefail -c
.DELETE_ON_ERROR:
MAKEFLAGS += --warn-undefined-variables
MAKEFLAGS += --no-builtin-rules
MAKEFLAGS += --silent
# https://github.com/toolbx-images/images/blob/main/alpine/edge/extra-packages

include .env
default: neovim

.PHONY: version
version:
	VERSION=$$(podman run --rm docker.io/alpine:latest /bin/ash -c 'cat /etc/os-release' | grep -oP 'VERSION_ID=\K.+')
	echo " - alpine version: $$VERSION"
	sed -i "s/ALPINE_VER=.*/ALPINE_VER=$${VERSION}/" .env
	echo '-----------------------------------------------'

# DEPENDENCIES := "bc bzip2 chpasswd curl diff find findmnt gpg hostname less lsof man mount passwd pigz pinentry ping ps rsync script ssh sudo time tree umount unzip useradd wc wget xauth zip"

build-base:
	echo 'Building $@'
	echo ' - from alpine version: $(ALPINE_VER)'
	CONTAINER=$$(buildah from docker.io/alpine:$(ALPINE_VER))
	# @see https://pkgs.alpinelinux.org/packages
	buildah run $${CONTAINER} sh -c 'apk update && apk upgrade && apk add build-base curl'
	buildah commit --rm $${CONTAINER} $@:v$(ALPINE_VER)

# libgcc
# libstdc++
# zstd-libs
# binutils
# libmagic
# file
# libgomp
# libatomic
# gmp
# isl26
# mpfr4
# mpc1
# gcc
# libstdc++-dev
# musl-dev
# libc-dev
# g++
# make
# fortify-headers
# patch
# build-base
	# buildah run $${CONTAINER} sh -c 'apk add --no-cache bash bash-completion build-base cmake coreutils curl diffutils docs findutils gettext-tiny-dev git gpg iputils keyutils ncurses-terminfo net-tools openssh-client pigz pinentry rsync sudo util-linux xauth zip'
# 

base:
	echo 'Building $@'
	echo ' - from alpine version: $(ALPINE_VER)'
	CONTAINER=$$(buildah from localhost/build-base:$(ALPINE_VER))
	# @see https://pkgs.alpinelinux.org/packages
	buildah run $${CONTAINER} sh -c 'apk update && apk upgrade'
	buildah run $${CONTAINER} sh -c 'apk add --no-cache alpine-base bash bash-completion bc bzip2 coreutils diffutils docs findutils gcompat git gnupg iproute2 iputils keyutils less libcap man-pages mandoc musl-utils ncurses-terminfo net-tools openssh-client procps rsync shadow sudo tar tcpdump tree unzip util-linux wget which xz zip' &>/dev/null
	buildah run $${CONTAINER} sh -c 'echo "%wheel ALL=(ALL) NOPASSWD: ALL" | tee /etc/sudoers.d/toolbox'
	buildah run $${CONTAINER} sh -c 'cp -v -p /etc/os-release /usr/lib/os-release'
	buildah commit --rm $${CONTAINER} $@:v$(ALPINE_VER)
	## CHECK! To test if all packages requirements are met just run this in the container:
	## @ https://distrobox.it/posts/distrobox_custom/
	# podman run localhost/$@:$(ALPINE_VER) sh -c 'for dep in $(DEPENDENCIES); do ! command -v "$${dep}" && echo "missing $${dep}";done'
	podman images

# ifdef GITHUB_ACTIONS
# 	buildah push ghcr.io/$(REPO_OWNER)/$@:v$(ALPINE_VER)
# endif

rustup:
	echo 'Building $@ tooling'
	echo " - from alpine version: $(ALPINE_VER)"
	CONTAINER=$$(buildah from localhost/build-base:$(ALPINE_VER))
	buildah run $${CONTAINER} sh -c "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y"
	buildah run $${CONTAINER} sh -c "source /home/.cargo/env" || true
	buildah run $${CONTAINER} sh -c "which cargo" || true
	buildah run $${CONTAINER} sh -c "rustup component add rustfmt clippy" || true
	buildah run $${CONTAINER} sh -c "rustup target add wasm32-unknown-unknown" || true # to compile our example Wasm/WASI files for testing
	buildah commit --rm $${CONTAINER} $@:$(ALPINE_VER)

golang:
	echo 'Building $@ tooling'
	echo " - from alpine version: $(ALPINE_VER)"
	CONTAINER=$$(buildah from localhost/build-base:$(ALPINE_VER))
	buildah run $${CONTAINER} sh -c 'wget -q https://go.dev/dl/$(GO_VER).linux-amd64.tar.gz \
		&& mkdir -p /usr/local/go \
		&& tar -C /usr/local/go --strip-components=1 -xzf $(GO_VER).linux-amd64.tar.gz \
		&& cd /usr/local/bin && ln -s /usr/local/go/bin/go'
		buildah commit --rm $${CONTAINER} $@:$(ALPINE_VER)
	# podman run localhost/$@:$(ALPINE_VER) sh -c 'tree /usr/local'
	podman run localhost/$@:$(ALPINE_VER) sh -c 'which go'
	podman run localhost/$@:$(ALPINE_VER) bin/sh -c 'ldd /usr/local/bin/go'

neovim: 
	echo 'Building container localhost/$@:v$(ALPINE_VER)'
	CONTAINER=$$(buildah from localhost/build-base:$(ALPINE_VER))
	buildah run $${CONTAINER} sh -c 'apk add --no-cache cmake coreutils curl unzip gettext-tiny-dev git' &>/dev/null
	# @see https://github.com/neovim/neovim/wiki/Building-Neovim
	# TODO install stuff from a checkhealth and Mason build tool required for LSP
	buildah run $${CONTAINER} sh -c 'git clone https://github.com/neovim/neovim && cd neovim && make CMAKE_BUILD_TYPE=RelWithDebInfo && make install' &>/dev/null
	buildah commit --rm --squash $${CONTAINER} $@:$(ALPINE_VER)
	podman images
	podman run localhost/$@:$(ALPINE_VER) sh -c 'which nvim'
	podman run localhost/$@:$(ALPINE_VER) sh -c 'ls -l /usr/local/share'
	podman run localhost/$@:$(ALPINE_VER) sh -c 'ls -l /usr/local/bin'
	podman run localhost/$@:$(ALPINE_VER) sh -c 'ls -l /usr/local/lib/nvim'
	podman run localhost/$@:$(ALPINE_VER) sh -c 'ldd /usr/local/bin/nvim'

tbx: neovim
	CONTAINER=$$(buildah from localhost/build-base:v$(ALPINE_VER))
	# @see https://github.com/toolbx-images/images/blob/main/alpine/edge/Containerfile
	buildah config \
		--label com.github.containers.toolbox="true" \
		--label version="v$(ALPINE_VER)" \
		--label usage="Use with toolbox or distrobox command" \
		--label summary="base dev toolbx alpine image" \
		--label maintainer="Grant MacKenzie <grantmacken@gmail.com>" \
		--workingdir /home \
		$${CONTAINER}
	# install build-base so we can use make and build with neovim Mason
	# build tools: python and pip
	buildah run $${CONTAINER} sh -c 'apk add --no-cache python3 py3-pip' &>/dev/null
	buildah run $${CONTAINER} sh -c 'apk add --no-cache rustup' &>/dev/null
	buildah run $${CONTAINER} sh -c 'which rustup-init'
	buildah run $${CONTAINER} sh -c 'rustup-init'
	# @see https://github.com/ublue-os/boxkit
	# install some boxkit suggested apk packages 
	buildah run $${CONTAINER} sh -c 'apk add --no-cache btop age atuin bat chezmoi clipboard cosign dbus-x11 github-cli grep just ncurses plocate ripgrep gzip tzdata zstd wl-clipboard' &>/dev/null
	# install node neovim provider
	# @see https://pnpm.io/
	# buildah run $${CONTAINER} wget -qO- https://get.pnpm.io/install.sh | ENV="$$HOME/.bashrc" SHELL="$$(which bash)" bash -
	# install node neovim provider
	# buildah run $${CONTAINER} sh -c 'pnpm install -g neovim'
	# @ copy over neovim build
	buildah  copy --from localhost/$(<):$(ALPINE_VER) $${CONTAINER} '/usr/local/bin/nvim' '/usr/local/bin'
	buildah  copy --from localhost/$(<):$(ALPINE_VER)  $${CONTAINER} '/usr/local/share' '/usr/local/share'
	buildah  copy --from localhost/$(<):$(ALPINE_VER)  $${CONTAINER} '/usr/local/lib' '/usr/local/lib'
	buildah run $${CONTAINER} sh -c 'ln -fs /bin/sh /usr/bin/sh'
	# Host Management
	# distrobox-host-exec lets one execute command on the host, while inside of a container.
	# @see https://distrobox.it/useful_tips/#using-hosts-podman-or-docker-inside-a-distrobox
	buildah run $${CONTAINER} sh -c 'ln -fs /usr/bin/distrobox-host-exec /usr/local/bin/podman && ln -fs /usr/bin/distrobox-host-exec /usr/local/bin/buildah'
	buildah run $${CONTAINER} sh -c "echo $$PATH"
	buildah commit --rm $${CONTAINER} ghcr.io/$(REPO_OWNER)/$@:v$(ALPINE_VER)
ifdef GITHUB_ACTIONS
	buildah push ghcr.io/$(REPO_OWNER)/$@:v$(ALPINE_VER)
	buildah push ghcr.io/$(REPO_OWNER)/$@:latest
endif

# ln -fs /bin/sh /usr/bin/sh && \
# ln -fs /usr/bin/distrobox-host-exec /usr/local/bin/flatpak && \ 
# ln -fs /usr/bin/distrobox-host-exec /usr/local/bin/podman && \
# ln -fs /usr/bin/distrobox-host-exec /usr/local/bin/rpm-ostree && \
# ln -fs /usr/bin/distrobox-host-exec /usr/local/bin/transactional-update

.PHONY: xxxdefault
xxxdefault:
	CONTAINER=$$(buildah from $(FROM):$(VERSION))
	buildah run $${CONTAINER} apk add --no-cache neovim
	buildah config --label com.github.containers.toolbox=true $${CONTAINER}	
	buildah config --label usage="This image is meant to be used with the toolbox command" $${CONTAINER}	
	buildah config --label summary="A cloud-native terminal experience" $${CONTAINER}	
	buildah config --label smaintainer="grantmacken@gmail.com" $${CONTAINER}	
	buildah commit --rm --squash $${CONTAINER} $(NAME):$(VERSION)
# buildah config --label com.github.containers.toolbox="true" $${CONTAINER}	
# buildah config --label org.opencontainers.image.base.name="$(FROM):$(VERSION)" $${CONTAINER}
# buildah config --label org.opencontainers.image.title='dev toolbx container' $${CONTAINER} # title
# buildah config --label org.opencontainers.image.descriptiion='This image is meant to be used with the toolbox command' $${CONTAINER} # description
# buildah config --label org.opencontainers.image.authors='Grant Mackenzie <grantmacken@gmail.com>' $${CONTAINER} # author
# buildah config --label usage="This image is meant to be used with the toolbox command" $${CONTAINER}	
# buildah config --label summary="A cloud-native terminal experience" $${CONTAINER}	
# buildah config --label maintainer="grantmacken@gmail.com" $${CONTAINER}	
# buildah commit --rm --squash $${CONTAINER} $(NAME):$(VERSION)
# ifdef GITHUB_ACTIONS
# 	echo 'GITHUB_ACTIONS'
# 	#buildah push ghcr.io/$(REPO_OWNER)/$(call Build,$@):v$${VERSION}
# endif

.PHONY: help
help: ## show this help	
	@cat $(MAKEFILE_LIST) | 
	grep -oP '^[a-zA-Z_-]+:.*?## .*$$' |
	sort |
	awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'



# btop
# age
# atuin
# bat
# chezmoi
# clipboard
# cosign
# dbus-x11
# github-cli
# grep
# just
# ncurses
# plocate
# ripgrep
# gzip
# tzdata
# zstd
# wl-clipboard

