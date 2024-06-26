SHELL := /bin/bash
.ONESHELL:
.SHELLFLAGS := -eu -o pipefail -c
.DELETE_ON_ERROR:
MAKEFLAGS += --warn-undefined-variables
MAKEFLAGS += --no-builtin-rules
MAKEFLAGS += --silent
include .env

GROUP_C_DEV := "C Development Tools and Libraries"
GROUP_OCAML := "OCaml"

default: tbx

latest/luarocks.name:
	mkdir -p $(dir $@)
	wget -q -O - 'https://api.github.com/repos/luarocks/luarocks/tags' | jq  -r '.[0].name' | tee $@

luarocks: latest/luarocks.name
	echo '##[ $@ ]##'
	CONTAINER=$$(buildah from cgr.dev/chainguard/wolfi-base:latest)
	buildah config --workingdir /home/nonroot $${CONTAINER}
	buildah run $${CONTAINER} sh -c 'mkdir /app && apk add \
	build-base \
	readline-dev \
	autoconf \
	luajit \
	luajit-dev \
	wget' &>/dev/null
	buildah run $${CONTAINER} sh -c 'lua -v'
	buildah run $${CONTAINER} sh -c 'which lua'
	buildah run $${CONTAINER} sh -c 'ls -al /usr/bin' | grep lua
	echo '##[ ----------include----------------- ]##'
	buildah run $${CONTAINER} sh -c 'ls -al /usr/include' | grep lua
	echo '##[ -----------lib ------------------- ]##'
	buildah run $${CONTAINER} sh -c 'ls -alR /usr/lib' | grep lua
	VERSION=$(shell cat $< | cut -c 2-)
	echo "luarocks version: $${VERSION}"
	URL=https://github.com/luarocks/luarocks/archive/refs/tags/v$${VERSION}.tar.gz
	echo "luarocks URL: $${URL}"
	buildah run $${CONTAINER} sh -c "wget -qO- $${URL} | tar xvz" &>/dev/null
	buildah config --workingdir /home/nonroot/luarocks-$${VERSION} $${CONTAINER}
	buildah run $${CONTAINER} sh -c './configure \
		--with-lua=/usr/bin \
		--with-lua-bin=/usr/bin \
		--with-lua-lib=/usr/lib \
		--with-lua-include=/usr/include/lua'
	buildah run $${CONTAINER} sh -c 'make & make install'
	buildah run $${CONTAINER} sh -c 'which luarocks'
	buildah run $${CONTAINER} sh -c 'luarocks'
	buildah run $${CONTAINER} sh -c 'ls -alR /usr/local'
	buildah commit --rm $${CONTAINER} $@ &>/dev/null
	echo '-------------------------------'



latest/neovim-nightly.json:
	mkdir -p $(dir $@)
	wget -q -O - 'https://api.github.com/repos/neovim/neovim/releases/tags/nightly' > $@

latest/neovim.download: latest/neovim-nightly.json
	mkdir -p $(dir $@)
	jq -r '.assets[].browser_download_url' $< | grep nvim-linux64.tar.gz  | head -1 | tee $@

neovim: latest/neovim.download
	jq -r '.tag_name' latest/neovim-nightly.json
	jq -r '.name' latest/neovim-nightly.json
	CONTAINER=$$(buildah from cgr.dev/chainguard/wolfi-base)
	buildah run $${CONTAINER} sh -c 'apk add wget'
	echo -n 'download: ' && cat $<
	cat $< | buildah run $${CONTAINER} sh -c 'cat - | wget -q -O- -i- | tar xvz -C /usr/local' &>/dev/null
	buildah run $${CONTAINER} sh -c 'ls -al /usr/local' || true
	buildah commit --rm $${CONTAINER} $@

bldr-rust: ## a ephemeral localhost container which builds rust executables
	echo '##[ $@ ]##'
	CONTAINER=$$(buildah from cgr.dev/chainguard/rust:latest)
	buildah run $${CONTAINER} rustc --version
	buildah run $${CONTAINER} cargo --version
	buildah run $${CONTAINER} cargo install cargo-binstall &>/dev/null
	# only install stuff not in  wolfi apk registry
	buildah run $${CONTAINER} /home/nonroot/.cargo/bin/cargo-binstall --no-confirm --no-symlinks \
		stylua \
		silicon \
		tree-sitter-cli &>/dev/null
	buildah run $${CONTAINER} rm /home/nonroot/.cargo/bin/cargo-binstall
	buildah run $${CONTAINER} ls /home/nonroot/.cargo/bin/
	buildah commit --rm $${CONTAINER} $@
	echo '##[ ------------------------------- ]##'


tbx: neovim luarocks
	CONTAINER=$$(buildah from registry.fedoraproject.org/fedora-toolbox:$(FEDORA_VER))
	# buildah run $${CONTAINER} sh -c 'dnf group list --hidden'
	# buildah run $${CONTAINER} sh -c 'dnf group info $(GROUP_C_DEV)' || true
	buildah run $${CONTAINER} sh -c 'dnf -y group install $(GROUP_C_DEV)' &>/dev/null
	buildah run $${CONTAINER} sh -c 'which make' || true
	buildah run $${CONTAINER} sh -c 'which bash' || true
	echo ' - from: bldr neovim'
	buildah add --from localhost/neovim $${CONTAINER} '/usr/local/nvim-linux64' '/usr/local/'
	buildah run $${CONTAINER} sh -c 'which nvim && nvim --version' || true
	echo ' - from: bldr luarocks'
	buildah add --from localhost/luarocks $${CONTAINER} '/usr/local/bin' '/usr/local/bin'
	buildah add --from localhost/luarocks $${CONTAINER} '/usr/local/share/lua' '/usr/local/share/lua'
	buildah add --from localhost/luarocks $${CONTAINER} '/usr/local/etc' '/usr/local/etc'
	buildah add --from localhost/luarocks $${CONTAINER} '/usr/local/lib' '/usr/local/lib'
	buildah add --from localhost/luarocks $${CONTAINER} '/usr/include/lua' '/usr/include/lua'
	buildah add --from localhost/luarocks $${CONTAINER} '/usr/bin/lua*' '/usr/bin/'
	buildah run $${CONTAINER} sh -c 'lua -v'
	buildah run $${CONTAINER} sh -c 'which lua'
	echo '##[ ----------bin----------------- ]##'
	buildah run $${CONTAINER} sh -c 'ls -al /usr/bin' | grep lua
	echo '##[ ----------include----------------- ]##'
	buildah run $${CONTAINER} sh -c 'ls -al /usr/include' | grep lua
	echo '##[ -----------lib ------------------- ]##'
	buildah run $${CONTAINER} sh -c 'ls -alR /usr/lib' | grep lua
	buildah run $${CONTAINER} sh -c 'which luarocks'
	buildah run $${CONTAINER} sh -c 'luarocks'
	buildah run $${CONTAINER} sh -c 'ls -alR /usr/local'



sssss:
	# buildah run $${CONTAINER} sh -c 'dnf group info $(GROUP_OCAML)' || true
	buildah run $${CONTAINER} sh -c 'dnf -y install luajit' || true
	buildah run $${CONTAINER} /bin/bash -c 'ln -s /usr/bin/luajit /usr/bin/lua'
	buildah run $${CONTAINER} sh -c 'which lua' || true
	buildah run $${CONTAINER} sh -c 'lua -v'
	VERSION=$(shell cat latest/luarocks.name | cut -c 2-)
	echo "luarocks version: $${VERSION}"
	URL=https://github.com/luarocks/luarocks/archive/refs/tags/v$${VERSION}.tar.gz
	echo "luarocks URL: $${URL}"
	buildah config --workingdir /tmp $${CONTAINER}
	buildah run $${CONTAINER} sh -c "wget -qO- $${URL} | tar xvz" &>/dev/null
	buildah config --workingdir /tmp/luarocks-$${VERSION} $${CONTAINER}
	buildah run $${CONTAINER} sh -c 'ls -al .'
	buildah run $${CONTAINER} sh -c './configure \
		--with-lua=/usr/bin \
		--with-lua-bin=/usr/bin \
		--with-lua-lib=/usr/lib \
		--with-lua-include=/usr/include/lua'
	buildah run $${CONTAINER} sh -c 'make & make install'
	# buildah run $${CONTAINER} sh -c 'which luarocks'
	buildah run $${CONTAINER} sh -c 'luarocks'
	buildah run $${CONTAINER} sh -c 'ls -alR /usr/local'
	echo ' - reset working dir'
	buildah config --workingdir / $${CONTAINER}
	echo '##[ ----------include----------------- ]##'
	buildah run $${CONTAINER} sh -c 'ls -al /usr/include' | grep lua
	echo '##[ -----------lib ------------------- ]##'
	buildah run $${CONTAINER} sh -c 'ls /usr/lib' | grep lua
	echo ' - clean up'
	buildah run $${CONTAINER} sh -c "rm -vR /tmp/*" || true

xxx:
	buildah run $${CONTAINER} sh -c 'rm /etc/rpm/macros.image-language-conf' &>/dev/null
	buildah run $${CONTAINER} sh -c "sed -i '/tsflags=nodocs/d' /etc/dnf/dnf.conf" &>/dev/null
	buildah run $${CONTAINER} sh -c 'dnf -y upgrade && dnf -y swap coreutils-single coreutils-full && dnf -y swap glibc-minimal-langpack glibc-all-langpacks' &>/dev/null
	buildah run $${CONTAINER} sh -c 'dnf -y reinstall acl bash coreutils-common curl findutils gawk gnupg2 grep gzip libcap openssl p11-kit pam python3 rpm sed sudo systemd tar util-linux-core' &>/dev/null
	buildah run $${CONTAINER} sh -c 'dnf -y install bash-completion bc bzip2 diffutils dnf-plugins-core findutils flatpak-spawn fpaste git gnupg2 gnupg2-smime gvfs-client hostname iproute iputils keyutils krb5-libs less lsof man-db man-pages mesa-dri-drivers mesa-vulkan-drivers mtr nano-default-editor nss-mdns openssh-clients passwd pigz procps-ng rsync shadow-utils sudo tcpdump time traceroute tree unzip util-linux vte-profile vulkan-loader wget which whois words xorg-x11-xauth xz zip' &>/dev/null
	buildah run $${CONTAINER} sh -c 'dnf -y install ninja-build cmake gcc make unzip gettext' &>/dev/null ## for neovim
	buildah run $${CONTAINER} sh -c 'dnf clean all' &>/dev/null
	buildah commit --rm $${CONTAINER} localhost/$@:$(FEDORA_VER)
ifdef GITHUB_ACTIONS
	podman push ghcr.io/$(REPO_OWNER)/$@:$(VERSION)
	podman push ghcr.io/$(REPO_OWNER)/$@:latest
endif
	podman images
	echo '-----------------------------------------------'


# RUSTARCH := x86_64-unknown-linux-musl
RUSTARCH := x86_64-unknown-linux-gnu
# RUSTUP_TAG @see https://github.com/rust-lang/rustup/tags

rustup:
	echo 'Building $@ tooling'
	CONTAINER=$$(buildah from localhost/fedora:$(FEDORA_VER))
	buildah config \
		--env RUSTUP_HOME=/usr/local/rustup \
		--env CARGO_HOME=/usr/local/cargo \
		$${CONTAINER} 
	buildah run $${CONTAINER} sh -c "wget -q https://static.rust-lang.org/rustup/archive/$(RUSTUP_TAG)/$(RUSTARCH)/rustup-init"
	buildah run $${CONTAINER} sh -c "chmod +x rustup-init" || true
	buildah run $${CONTAINER} sh -c './rustup-init -y --no-modify-path --profile minimal --default-toolchain $(RUST_VER) --default-host $(RUSTARCH)' &>/dev/null
	# buildah run $${CONTAINER} sh -c "rustup component add rustfmt clippy rust-analyzer"
	# buildah run $${CONTAINER} sh -c 'rustc --print target-list'
	buildah run $${CONTAINER} sh -c 'chmod -R a+w /usr/local/rustup /usr/local/cargo && ln -s /usr/local/cargo/bin/* /usr/local/bin/'
	##[[ rustup
	# buildah run $${CONTAINER} sh -c "rustup component add rustfmt clippy rust-analyzer" &>/dev/null
	# buildah run $${CONTAINER} sh -c "rustup target add wasm32-wasi" &>/dev/null
	# buildah run $${CONTAINER} sh -c "rustup target add wasm32-unknown-unknown"&>/dev/null # to compile our example Wasm/WASI files for testing
	# buildah run $${CONTAINER} sh -c "rustup show" # to compile our example Wasm/WASI files for testing
	# ##[[ cargo and cargo wasi
	# buildah run $${CONTAINER} sh -c "cargo --version" &>/dev/null
	# buildah run $${CONTAINER} sh -c "cargo --help" &>/dev/null
	# buildah run $${CONTAINER} sh -c "cargo install -v cargo-wasi"
	# buildah run $${CONTAINER} sh -c "cargo wasi --version"
	buildah commit --rm $${CONTAINER} localhost/$@:$(FEDORA_VER)
	podman images
	podman run localhost/$@:$(FEDORA_VER) sh -c 'rustup --version && cargo --version && rustc --version'

rust-tooling:
	CONTAINER=$$(buildah from localhost/rustup:$(FEDORA_VER))
	buildah run $${CONTAINER} sh -c 'rustup --version && cargo --version && rustc --version'
	# 'Add components for neovim LSP and formatter' 
	buildah run $${CONTAINER} sh -c "rustup component add rustfmt clippy rust-analyzer" &>/dev/null
	buildah run $${CONTAINER} sh -c "rustup target add wasm32-wasi" &>/dev/null
	buildah run $${CONTAINER} sh -c "rustup target add wasm32-unknown-unknown"&>/dev/null # to compile our example Wasm/WASI files for testing
	buildah run $${CONTAINER} sh -c "rustup show" # to compile our example Wasm/WASI files for testing
	buildah run $${CONTAINER} sh -c "cargo --version" &>/dev/null
	buildah run $${CONTAINER} sh -c "cargo --help" &>/dev/null
	buildah run $${CONTAINER} sh -c "cargo install -v cargo-wasi"
	buildah run $${CONTAINER} sh -c "cargo wasi --version"
	buildah commit --rm $${CONTAINER} localhost/$@:$(FEDORA_VER)


cargo:
	CONTAINER=$$(buildah from localhost/rustup:$(FEDORA_VER))
	# CLI utilities https://github.com/cargo-bins/cargo-binstall
	buildah run $${CONTAINER} sh -c "cargo install cargo-binstall"
	buildah run $${CONTAINER} sh -c 'ln -sf /usr/local/cargo/bin/cargo-binstall /usr/local/bin/cargo-binstall' || true
	buildah run $${CONTAINER} sh -c "cargo-binstall --no-confirm --no-symlinks ripgrep stylua just wasm-pack"
	buildah run $${CONTAINER} sh -c 'ln -sf /usr/local/cargo/bin/* /usr/local/bin/' || true
	buildah run $${CONTAINER} sh -c 'which rg'
	buildah commit --rm $${CONTAINER} $@:$(ALPINE_VER)

spin:
	CONTAINER=$$(buildah from localhost/fedora:$(FEDORA_VER))
	buildah config --workingdir /home $${CONTAINER}
	buildah run $${CONTAINER} sh -c 'mkdir -p /usr/local/spin'
	buildah config --workingdir /usr/local/spin $${CONTAINER}
	buildah run $${CONTAINER} sh -c 'curl -fsSL https://developer.fermyon.com/downloads/install.sh | bash' &>/dev/null
	buildah run $${CONTAINER} sh -c 'pwd && ls -al .'
	buildah run $${CONTAINER} sh -c 'ln -s /usr/local/spin/spin /usr/local/bin/'
	buildah commit --rm $${CONTAINER} localhost/$@:$(FEDORA_VER)
	podman images
	podman run localhost/$@:$(FEDORA_VER) sh -c 'which spin' || true
	podman run localhost/$@:$(FEDORA_VER) sh -c 'spin --version' || true
	podman run localhost/$@:$(FEDORA_VER)  sh -c 'spin --help' || true

wasmtime:
	echo 'Building $@g'
	CONTAINER=$$(buildah from localhost/fedora:$(FEDORA_VER))
	buildah config --env WASMTIME_HOME=/usr/local/wasmtime $${CONTAINER} 
	buildah run $${CONTAINER} sh -c "touch ~/.profile && curl https://wasmtime.dev/install.sh -sSf | bash"
	buildah run $${CONTAINER} sh -c 'ln -sf /usr/local/wasmtime/bin/* /usr/local/bin/' || true
	buildah commit --rm $${CONTAINER} $@:$(FEDORA_VER)
	podman images
	podman run localhost/$@:$(FEDORA_VER)  sh -c 'wasmtime --help' || true

# DEPENDENCIES := "bc bzip2 chpasswd curl diff find findmnt gpg hostname less lsof man mount passwd pigz pinentry ping ps rsync script ssh sudo time tree umount unzip useradd wc wget xauth zip"

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



# https://doc.rust-lang.org/cargo/reference/environment-variables.html
#

#buildah run $${CONTAINER} sh -c "rustup target add wasm32-wasi && rustup target add wasm32-wasi-preview1-threads && rustup target add wasm32-unknown-unknown"

golang:
	echo 'Building $@ tooling'
	CONTAINER=$$(buildah from localhost/fedora:$(FEDORA_VER))
	buildah run $${CONTAINER} sh -c 'wget -q -O go.tgz https://go.dev/dl/$(GO_VER).linux-amd64.tar.gz && tar -C /usr/local -xzf go.tgz'
	buildah run $${CONTAINER} sh -c 'chmod -R a+w /usr/local/go && ln -s /usr/local/go/bin/* /usr/local/bin/'
	buildah run $${CONTAINER} sh -c 'which go'
	buildah commit --rm $${CONTAINER} $@:$(FEDORA_VER)
	podman images
	podman run localhost/$@:$(FEDORA_VER) sh -c 'which go && go version'
	podman run localhost/$@:$(FEDORA_VER) sh -c 'go env'
	podman run localhost/$@:$(FEDORA_VER) sh -c 'go help gopath'

	## CHECK! To test if all packages requirements are met just run this in the container:
	## https://distrobox.it/posts/distrobox_custom/

xtbx:
	CONTAINER=$$(buildah from localhost/fedora:$(FEDORA_VER))
	buildah config \
		--label com.github.containers.toolbox="true" \
		--label com.redhat.component="$(NAME)" \
		--label version="$(VERSION)" \
		--label usage="This image is meant to be used with the toolbox command" \
		--label summary="wasi developer toolbx based on fedora image" \
		--label maintainer="Grant MacKenzie <grantmacken@gmail.com>" \
		--env RUSTUP_HOME=/usr/local/rustup \
		--env CARGO_HOME=/usr/local/cargo \
		--env WASMTIME_HOME=/usr/local/wasmtime \
		$${CONTAINER}
	echo '##[[ NEOVIM ]]##'
	buildah run $${CONTAINER} sh -c 'git clone https://github.com/neovim/neovim && cd neovim && make CMAKE_BUILD_TYPE=RelWithDebInfo && make install' &>/dev/null
	echo '##[[ WASMTIME ]]##'
	buildah  copy --from localhost/wasmtime:$(FEDORA_VER) $${CONTAINER} '/usr/local/wasmtime' '/usr/local/wasmtime'
	buildah run $${CONTAINER} sh -c 'chmod -R a+w /usr/local/wasmtime && ln -s /usr/local/wasmtime/bin/* /usr/local/bin/'
	buildah run $${CONTAINER} sh -c 'which wasmtime && wasmtime --version'
	echo '##[[ SPIN ]]##'
	buildah  copy --from localhost/spin:$(FEDORA_VER)  $${CONTAINER} '/usr/local/spin' '/usr/local/spin'
	buildah run $${CONTAINER} sh -c 'chmod -R a+w /usr/local/spin && ln -s /usr/local/spin/spin /usr/local/bin/'
	buildah run $${CONTAINER} sh -c 'which spin && spin --version'
	echo '##[[ RUSTUP ]]##'
	buildah  copy --from localhost/rustup:$(FEDORA_VER)  $${CONTAINER} '/usr/local/rustup' '/usr/local/rustup'
	buildah  copy --from localhost/rustup:$(FEDORA_VER)  $${CONTAINER} '/usr/local/cargo' '/usr/local/cargo'
	buildah run $${CONTAINER} sh -c 'chmod -R a+w /usr/local/rustup /usr/local/cargo && ln -s /usr/local/cargo/bin/* /usr/local/bin/'
	buildah run $${CONTAINER} sh -c 'which cargo && cargo --version'
	echo '##[[ GOLANG ]]##'
	buildah  copy --from localhost/golang:$(FEDORA_VER)  $${CONTAINER} '/usr/local/go' '/usr/local/go'
	buildah run $${CONTAINER} sh -c 'chmod -R a+w /usr/local/go && ln -s /usr/local/go/bin/* /usr/local/bin/'
	echo '##[[ sudo ]]##'
	buildah run $${CONTAINER} sh -c 'echo "%wheel ALL=(ALL) NOPASSWD: ALL" | tee /etc/sudoers.d/toolbox' || true
	# buildah run $${CONTAINER} sh -c 'cp -v -p /etc/os-release /usr/lib/os-release'
	# @see https://distrobox.it/useful_tips/#using-hosts-podman-or-docker-inside-a-distrobox
	# buildah run $${CONTAINER} sh -c 'ln -fs /usr/bin/distrobox-host-exec /usr/local/bin/podman && ln -fs /usr/bin/distrobox-host-exec /usr/local/bin/buildah'
	buildah commit --rm $${CONTAINER} ghcr.io/$(REPO_OWNER)/$@:$(VERSION)
	buildah tag ghcr.io/$(REPO_OWNER)/$@:$(VERSION) ghcr.io/$(REPO_OWNER)/$@:latest
	#buildah run $${CONTAINER} sh -c 'ln -fs /bin/sh /usr/bin/sh' || true
	#buildah tag ghcr.io/$(REPO_OWNER)/$@:$(FEDORA_VER) ghcr.io/$(REPO_OWNER)/$@:latest
	podman run ghcr.io/$(REPO_OWNER)/$@:$(VERSION) which nvim
	podman run ghcr.io/$(REPO_OWNER)/$@:$(VERSION) nvim --version
	podman run ghcr.io/$(REPO_OWNER)/$@:$(VERSION) printenv
ifdef GITHUB_ACTIONS
	podman push ghcr.io/$(REPO_OWNER)/$@:$(VERSION)
	podman push ghcr.io/$(REPO_OWNER)/$@:latest
endif
	

xxxxaa:
	# buildah run $${CONTAINER} sh -c 'apk add --no-cache alpine-base bash-completion bc bzip2 coreutils diffutils docs findutils gcompat gnupg iproute2 iputils keyutils less libcap man-pages mandoc musl-utils ncurses-terminfo net-tools openssh-client procps rsync shadow sudo tar tcpdump unzip util-linux wget which xz' &>/dev/null
	# install build-base so we can use make and build with neovim Mason
	# build tools: python and pip
	# buildah run $${CONTAINER} sh -c 'apk add --no-cache python3 py3-pip' &>/dev/null
	# @see https://github.com/ublue-os/boxkit
	# install some boxkit suggested apk packages 
	# 
	# buildah run $${CONTAINER} sh -c 'apk add --no-cache 
	# btop age atuin bat chezmoi clipboard cosign dbus-x11 
	# github-cli grep ncurses plocate ripgrep gzip tzdata zstd wl-clipboard' 
	# &>/dev/null
	# install node neovim provider
	# @see https://pnpm.io/
	# buildah run $${CONTAINER} wget -qO- https://get.pnpm.io/install.sh | ENV="$$HOME/.bashrc" SHELL="$$(which bash)" bash -
	# install node neovim provider
	# buildah run $${CONTAINER} sh -c 'pnpm install -g neovim'
	# @ copy over neovim build
	buildah  copy --from localhost/neovim:$(FEDORA_VER) $${CONTAINER} '/usr/local/bin/nvim' '/usr/local/bin'
	buildah  copy --from localhost/neovim:$(FEDORA_VER)  $${CONTAINER} '/usr/local/share' '/usr/local/share'
	# buildah  copy --from localhost/neovim:$(ALPINE_VER)  $${CONTAINER} '/usr/local/lib' '/usr/local/lib'
	buildah  copy --from localhost/rustup:$(FEDORA_VER)  $${CONTAINER} '/usr/local/rustup' '/usr/local/rustup'
	buildah  copy --from localhost/rustup:$(FEDORA_VER)  $${CONTAINER} '/usr/local/cargo' '/usr/local/cargo'
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
