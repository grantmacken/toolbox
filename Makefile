SHELL := /bin/bash
.ONESHELL:
.SHELLFLAGS := -eu -o pipefail -c
.DELETE_ON_ERROR:
MAKEFLAGS += --warn-undefined-variables
MAKEFLAGS += --no-builtin-rules
MAKEFLAGS += --silent
# https://github.com/toolbx-images/images/blob/main/alpine/edge/extra-packages

include .env

help: ## show this help	
	@cat $(MAKEFILE_LIST) | 
	grep -oP '^[a-zA-Z_-]+:.*?## .*$$' |
	sort |
	awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

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
	buildah config --workingdir /home $${CONTAINER}
	buildah run $${CONTAINER} sh -c 'apk update && apk upgrade && apk add build-base bash zip curl git tree' &>/dev/null
	buildah commit --rm $${CONTAINER} localhost/$@:$(ALPINE_VER)
	podman save --quiet -o build-base.tar localhost/$@:$(ALPINE_VER)
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
# podman run localhost/$@:$(ALPINE_VER) sh -c 'for dep in $(DEPENDENCIES); do ! command -v "$${dep}" && echo "missing $${dep}";done'
# @see https://pkgs.alpinelinux.org/packages
# @see https://github.com/toolbx-images/images/blob/main/alpine/edge/Containerfile'

RUSTARCH := x86_64-unknown-linux-musl

rustup:
	echo 'Building $@ tooling'
	echo " - from alpine version: $(ALPINE_VER)"
	CONTAINER=$$(buildah from localhost/build-base:$(ALPINE_VER))
	buildah config \
		--env RUSTUP_HOME=/usr/local/rustup \
		--env CARGO_HOME=/usr/local/cargo \
		$${CONTAINER} 
	# buildah run $${CONTAINER} sh -c "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y"
	# https://github.com/rust-lang/rustup/tags
	buildah run $${CONTAINER} sh -c "wget https://static.rust-lang.org/rustup/archive/$(RUSTUP_TAG)/$(RUSTARCH)/rustup-init "
	buildah run $${CONTAINER} sh -c "chmod +x rustup-init" || true
	buildah run $${CONTAINER} sh -c './rustup-init -y --no-modify-path --profile minimal --default-toolchain $(RUST_VER) --default-host $(RUSTARCH)'
	buildah run $${CONTAINER} sh -c 'chmod -R a+w /usr/local/rustup /usr/local/cargo && ln -s /usr/local/cargo/bin/* /usr/local/bin/'
	buildah run $${CONTAINER} sh -c 'echo " --[[ CHECKS ]]--"'
	buildah run $${CONTAINER} sh -c 'rustup --version && cargo --version && rustc --version'
	# 'Add components for neovim LSP and formatter' 
	buildah run $${CONTAINER} sh -c "rustup component add rustfmt clippy rust-analyzer"
	buildah run $${CONTAINER} sh -c "rustup target add wasm32-wasi"
	buildah run $${CONTAINER} sh -c "rustup target add wasm32-unknown-unknown" # to compile our example Wasm/WASI files for testing
	echo '==================================================='
	buildah run $${CONTAINER} sh -c "ls /usr/local/cargo/bin"
	echo '==================================================='
	# Spin https://github.com/fermyon/spin

	# CLI utilities https://github.com/cargo-bins/cargo-binstall
	buildah run $${CONTAINER} sh -c "cargo install cargo-binstall"
	buildah run $${CONTAINER} sh -c 'ln -sf /usr/local/cargo/bin/cargo-binstall /usr/local/bin/cargo-binstall' || true
	buildah run $${CONTAINER} sh -c "cargo-binstall --no-confirm --no-symlinks ripgrep stylua just wasm-pack"
	buildah run $${CONTAINER} sh -c 'ln -sf /usr/local/cargo/bin/* /usr/local/bin/' || true
	buildah run $${CONTAINER} sh -c 'which rg'
	buildah run $${CONTAINER	buildah run $${CONTAINER} sh -c "cargo install cargo-wasi" &>/dev/null
	buildah run $${CONTAINER} sh -c "cargo wasi --version" &>/dev/null
	buildah commit --rm $${CONTAINER} $@:$(ALPINE_VER)

spin:
	CONTAINER=$$(buildah from localhost/build-base:$(ALPINE_VER))
	buildah run $${CONTAINER} sh -c 'git clone https://github.com/fermyon/spin'
	buildah run $${CONTAINER} sh -c 'cd spin && make build'
	buildah run $${CONTAINER} sh -c './target/release/spin --help'
	buildah commit --rm $${CONTAINER} $@:$(ALPINE_VER)


xxx:
	buildah run $${CONTAINER} sh -c 'chmod +x /usr/local/spin/spin && ln -s -v /usr/local/spin/spin /usr/local/bin/spin' || true
	buildah run $${CONTAINER} sh -c 'which spin' || true
	buildah commit --rm $${CONTAINER} $@:$(ALPINE_VER)
	podman run localhost/$@:$(ALPINE_VER) sh -c 'tree /usr/local'
	podman run localhost/$@:$(ALPINE_VER) spin || true
	podman run localhost/$@:$(ALPINE_VER) sh -c 'spin --help' || true
# podman run $${CONTAINER} sh -c 'spin templates install --git https://github.com/fermyon/spin' || true
# podman run $${CONTAINER} sh -c 'spin templates list --verbose' || true
# podman run $${CONTAINER} sh -c 'spin plugins update' || true
# podman run $${CONTAINER} sh -c 'spin plugins list --installed --verbose' || true

#
# https://github.com/uutils/coreutils
# https://zaiste.net/posts/shell-commands-rust/
# bat exa fd procs sd dust starship ripgrep tokei ytop 

wasmtime:
	CONTAINER=$$(buildah from localhost/build-base:$(ALPINE_VER))
	buildah config --env WASMTIME_HOME=/usr/local/wasmtime $${CONTAINER} 
	buildah run $${CONTAINER} sh -c "touch ~/.profile && curl https://wasmtime.dev/install.sh -sSf | bash"
	buildah run $${CONTAINER} sh -c "tree /usr/local/wasmtime"
	buildah run $${CONTAINER} sh -c "cat ~/.profile "
	buildah commit --rm $${CONTAINER} $@:$(ALPINE_VER)
	
golang:
	echo 'Building $@ tooling'
	CONTAINER=$$(buildah from localhost/build-base:$(ALPINE_VER))
	buildah config \
		--env GOROOT_BOOTSTRAP='/usr/lib/go'\
		--env GOAMD64='v1' \
		--env GOARCH='amd64' \
		--env GOOS='linux' \
		--env GOCACHE='/tmp/gocache' $${CONTAINER}
	buildah run $${CONTAINER} sh -c 'apk add --no-cache go'
	buildah run $${CONTAINER} sh -c 'wget -O go.tgz https://dl.google.com/go/$(GO_VER).src.tar.gz && tar -C /usr/local -xzf go.tgz && rm go.tgz'
	buildah run $${CONTAINER} sh -c 'echo "$$(go env GOROOT)"'
	buildah run $${CONTAINER} sh -c 'cd /usr/local/go/src && ./make.bash'
	buildah run $${CONTAINER} sh -c 'rm -rf /usr/local/go/pkg/*/cmd /usr/local/go/pkg/bootstrap /usr/local/go/pkg/obj /usr/local/go/pkg/tool/*/api /usr/local/go/pkg/tool/*/go_bootstrap /usr/local/go/src/cmd/dist/dist "$$GOCACHE"'
	# remove a few intermediate / bootstrapping files the official binary release tarballs do not contain
	buildah commit --rm --squash $${CONTAINER} $@:$(ALPINE_VER)
	podman run localhost/$@:$(ALPINE_VER) sh -c 'tree /usr/local'
	# podman run localhost/$@:$(ALPINE_VER) bin/sh -c 'ldd /usr/local/bin/go'

neovim: 
	echo 'Building container localhost/$@:$(ALPINE_VER)'
	CONTAINER=$$(buildah from localhost/build-base:$(ALPINE_VER))
	buildah run $${CONTAINER} sh -c 'apk add --no-cache cmake coreutils gettext-tiny-dev' &>/dev/null
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

	## CHECK! To test if all packages requirements are met just run this in the container:
	## https://distrobox.it/posts/distrobox_custom/


tbx:
	CONTAINER=$$(buildah from localhost/build-base:$(ALPINE_VER))
	buildah run $${CONTAINER} sh -c 'echo $$PATH'
	buildah config \
		--label com.github.containers.toolbox="true" \
		--label version="$(ALPINE_VER)" \
		--label usage="Use with toolbox or distrobox command" \
		--label summary="base dev toolbx alpine image" \
		--label maintainer="Grant MacKenzie <grantmacken@gmail.com>" \
		--env RUSTUP_HOME=/usr/local/rustup \
		--env CARGO_HOME=/usr/local/cargo \
		--env WASMTIME_HOME=/usr/local/wasmtime \
		--workingdir /home \
		$${CONTAINER}
	buildah run $${CONTAINER} sh -c 'apk add --no-cache alpine-base bash-completion bc bzip2 coreutils diffutils docs findutils gcompat gnupg iproute2 iputils keyutils less libcap man-pages mandoc musl-utils ncurses-terminfo net-tools openssh-client procps rsync shadow sudo tar tcpdump unzip util-linux wget which xz' &>/dev/null
	# install build-base so we can use make and build with neovim Mason
	# build tools: python and pip
	buildah run $${CONTAINER} sh -c 'apk add --no-cache python3 py3-pip' &>/dev/null
	# @see https://github.com/ublue-os/boxkit
	# install some boxkit suggested apk packages 
	buildah run $${CONTAINER} sh -c 'apk add --no-cache btop age atuin bat chezmoi clipboard cosign dbus-x11 github-cli grep ncurses plocate ripgrep gzip tzdata zstd wl-clipboard' &>/dev/null
	# install node neovim provider
	# @see https://pnpm.io/
	# buildah run $${CONTAINER} wget -qO- https://get.pnpm.io/install.sh | ENV="$$HOME/.bashrc" SHELL="$$(which bash)" bash -
	# install node neovim provider
	# buildah run $${CONTAINER} sh -c 'pnpm install -g neovim'
	# @ copy over neovim build
	buildah  copy --from localhost/neovim:$(ALPINE_VER) $${CONTAINER} '/usr/local/bin/nvim' '/usr/local/bin'
	buildah  copy --from localhost/neovim:$(ALPINE_VER)  $${CONTAINER} '/usr/local/share' '/usr/local/share'
	buildah  copy --from localhost/neovim:$(ALPINE_VER)  $${CONTAINER} '/usr/local/lib' '/usr/local/lib'
	buildah  copy --from localhost/rustup:$(ALPINE_VER)  $${CONTAINER} '/usr/local/rustup' '/usr/local/rustup'
	buildah  copy --from localhost/rustup:$(ALPINE_VER)  $${CONTAINER} '/usr/local/cargo' '/usr/local/cargo'
	buildah run $${CONTAINER} sh -c 'chmod -R a+w /usr/local/rustup /usr/local/cargo && ln -s /usr/local/cargo/bin/* /usr/local/bin/'
	buildah run $${CONTAINER} sh -c 'which cargo'
	buildah  copy --from localhost/wasmtime:$(ALPINE_VER)  $${CONTAINER} '/usr/local/wasmtime' '/usr/local/wasmtime'
	buildah run $${CONTAINER} sh -c 'chmod -R a+w /usr/local/wasmtime && ln -s /usr/local/wasmtime/bin/* /usr/local/bin/'
	buildah run $${CONTAINER} sh -c 'which wasmtime && wasmtime --version'
	#copy over golang build
	buildah  copy --from localhost/golang:$(ALPINE_VER) $${CONTAINER} '/usr/local/go' '/usr/local/go'
	buildah run $${CONTAINER} sh -c 'chmod -R a+w /usr/local/go && ln -s /usr/local/go/bin/* /usr/local/bin/'
	buildah run $${CONTAINER} sh -c 'which go'
	buildah run $${CONTAINER} sh -c 'which gofmt'
	buildah run $${CONTAINER} sh -c 'cat /usr/local/go/go.env'
	buildah run $${CONTAINER} sh -c  'go install golang.org/x/tools/gopls@latest'
	# --------------------------------------------------------
	buildah run $${CONTAINER} sh -c 'echo "%wheel ALL=(ALL) NOPASSWD: ALL" | tee /etc/sudoers.d/toolbox'
	buildah run $${CONTAINER} sh -c 'cp -v -p /etc/os-release /usr/lib/os-release'
	buildah run $${CONTAINER} sh -c 'ln -fs /bin/sh /usr/bin/sh'
	# Host Management
	# distrobox-host-exec lets one execute command on the host, while inside of a container.
	# @see https://distrobox.it/useful_tips/#using-hosts-podman-or-docker-inside-a-distrobox
	buildah run $${CONTAINER} sh -c 'ln -fs /usr/bin/distrobox-host-exec /usr/local/bin/podman && ln -fs /usr/bin/distrobox-host-exec /usr/local/bin/buildah'
	buildah run $${CONTAINER} sh -c "echo $$PATH"
	buildah commit --rm $${CONTAINER} ghcr.io/$(REPO_OWNER)/$@:$(ALPINE_VER)
	buildah tag ghcr.io/$(REPO_OWNER)/$@:$(ALPINE_VER) ghcr.io/$(REPO_OWNER)/$@:latest
ifdef GITHUB_ACTIONS
	buildah push ghcr.io/$(REPO_OWNER)/$@:$(ALPINE_VER)
	buildah push ghcr.io/$(REPO_OWNER)/$@:latest
endif

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

# buildah run $${CONTAINER} sh -c 'wget -O spin.tgz https://dl.google.com/go/$(GO_VER).src.tar.gz && tar -C /usr/local -xzf go.tgz && rm go.tgz'
# buildah run $${CONTAINER} sh -c 'git clone https://github.com/fermyon/spin -b v$(SPIN_VER) && cd spin'
# buildah run $${CONTAINER} sh -c 'cargo install --locked --path .'
# buildah run $${CONTAINER} sh -c 'spin --help'
# buildah run $${CONTAINER} sh -c 'spin --version'
# buildah run $${CONTAINER} sh -c 'which spin'
