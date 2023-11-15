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

.PHONY: base
base:
	echo 'Building base'
	echo " - from alpine version: $(ALPINE_VER)"
	CONTAINER=$$(buildah from docker.io/alpine:$(ALPINE_VER))
	buildah run $${CONTAINER} bin/sh -c 'apk add --no-cache \
build-base \
cmake \
coreutils \
curl \
unzip \
gettext-tiny-dev \
tree \
git' &>/dev/null
	buildah commit --rm $${CONTAINER} base:$(ALPINE_VER)

 
rust:
	echo 'Building rust tooling'
	echo " - from alpine version: $(ALPINE_VER)"
	CONTAINER=$$(buildah from localhost/base:$(ALPINE_VER))
	buildah run $${CONTAINER} bin/sh -c "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y"
	buildah run $${CONTAINER} bin/sh -c "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y"
	buildah run $${CONTAINER} bin/sh -c "source ~/.cargo/env" || true
	buildah run $${CONTAINER} bin/sh -c "ls -al ~/" || true
	buildah run $${CONTAINER} bin/sh -c "which cargo" || true
	buildah run $${CONTAINER} bin/sh -c "rustup component add rustfmt clippy" || true
	buildah run $${CONTAINER} bin/sh -c "rustup target add wasm32-unknown-unknown" || true # to compile our example Wasm/WASI files for testing
	buildah commit --rm $${CONTAINER} rust:$(ALPINE_VER)

golang:
	echo 'Building $@ tooling'
	echo " - from alpine version: $(ALPINE_VER)"
	CONTAINER=$$(buildah from localhost/base:$(ALPINE_VER))
	buildah run $${CONTAINER} bin/sh -c 'wget -q https://go.dev/dl/$(GO_VER).linux-amd64.tar.gz'
	buildah run $${CONTAINER} bin/sh -c 'tar -C ~/.local -xzf $(GO_VER).linux-amd64.tar.gz'
	buildah commit --rm $${CONTAINER} $@:$(ALPINE_VER)
	# sudo rm -rf $(HOME)/.local/go
		# tar -C $(HOME)/.local -xzf $(VERSION).linux-amd64.tar.gz

.PHONY: neovim
neovim:
	echo 'Building nevim'
	echo " - from alpine version: $(ALPINE_VER)"
	CONTAINER=$$(buildah from docker.io/alpine:$(ALPINE_VER))
	buildah run $${CONTAINER} bin/sh -c 'apk add --no-cache \
build-base \
cmake \
coreutils \
curl \
unzip \
gettext-tiny-dev \
git'
	buildah run $${CONTAINER} bin/sh -c 'git clone https://github.com/neovim/neovim \
&& cd neovim && make CMAKE_BUILD_TYPE=RelWithDebInfo && make install' &>/dev/null
	buildah commit --rm $${CONTAINER} base:$(ALPINE_VER)
	podman images
	# podman run localhost/base:$(ALPINE_VER) bin/sh -c 'which nvim'
	# nvim --version

.PHONY: inspect
inspect:
	podman run localhost/base:$(ALPINE_VER) bin/sh -c 'which nvim'
	echo
	podman run localhost/base:$(ALPINE_VER) bin/sh -c 'ls -l /usr/local/share'
	echo
	podman run localhost/base:$(ALPINE_VER) bin/sh -c 'ls -l /usr/local/bin'
	echo
	podman run localhost/base:$(ALPINE_VER) bin/sh -c 'ls -l /usr/local/lib/nvim'
	echo
	podman run localhost/base:$(ALPINE_VER) bin/sh -c 'ldd /usr/local/bin/nvim'


.PHONY: alpine_rust
alpine_rust:  ## buildah build alpine
	CONTAINER=$$(buildah from quay.io/toolbx-images/alpine-toolbox:3.18)
	buildah run $${CONTAINER} bin/sh -c 'apk add --no-cache \


.PHONY: alpine_toolbox
alpine_toolbox:  ## buildah build alpine
	CONTAINER=$$(buildah from quay.io/toolbx-images/alpine-toolbox:3.18)
	buildah run $${CONTAINER} bin/sh -c 'apk add --no-cache \
build-base \
clipboard \
chezmoi \
cosign \
ncurses-libs \
python3 \
gzip \
tzdata \
grep \
ripgrep \
github-cli \
wl-clipboard'
	buildah  copy --from localhost/base:$(ALPINE_VER) $${CONTAINER} '/usr/local/bin/nvim' '/usr/local/bin'
	buildah  copy --from localhost/base:$(ALPINE_VER)  $${CONTAINER}  '/usr/local/share' '/usr/local/share'
	buildah  copy --from localhost/base:$(ALPINE_VER)  $${CONTAINER}  '/usr/local/lib' '/usr/local/lib'
	buildah run $${CONTAINER} /bin/sh -c 'ls -l /usr/local/bin' || true
	buildah run $${CONTAINER} /bin/sh -c 'ln -vfs /bin/sh /usr/bin/sh' || true
	# buildah inspect $${CONTAINER}
	buildah commit --rm $${CONTAINER} tbx:$(ALPINE_VER)
	# toolbox create --image localhost/tbx:$${VERSION} --container tbx
	# toolbox enter tbx

.PHONY: clean
clean:
	podman stop tbx || true
	toolbox rm tbx || true

.PHONY: x2default
x2default:    ## buildah build alpine
	VERSION=$$(podman run --rm docker.io/alpine:latest /bin/ash -c 'cat /etc/os-release' | grep -oP 'VERSION_ID=\K.+')
	echo " - alpine version: $$VERSION"
	CONTAINER=$$(buildah from docker.io/alpine:$${VERSION})
	buildah config --label com.github.containers.toolbox="true" $${CONTAINER}	
	buildah config --author 'Grant Mackenzie <grantmacken@gmail.com>' $${CONTAINER}	
	#echo 'Enable password less sudo'
	buildah run $${CONTAINER} /bin/sh -c 'mkdir -p /etc/sudoers.d'
	buildah run $${CONTAINER} /bin/sh -c 'echo "%wheel ALL=(ALL) NOPASSWD: ALL" | tee /etc/sudoers.d/toolbox'
	echo 'Copy the os-release file'
	buildah run $${CONTAINER} /bin/sh -c 'cat etc/os-release | tee /usr/lib/os-release'
	#buildah run $${CONTAINER} ls .
	buildah inspect $${CONTAINER} 	
	buildah commit --rm $${CONTAINER} tbx:$${VERSION}

.PHONY: list
list:
	toolbox list

.PHONY: create
create:
	VERSION=$$(podman run --rm docker.io/alpine:latest /bin/ash -c 'cat /etc/os-release' | grep -oP 'VERSION_ID=\K.+')
	echo " - alpine version: $$VERSION"
	toolbox create --image localhost/tbx:3.18.4 




.PHONY: versions
versions:
	podman pull docker.io/alpine:latest
	VERSION=$$(podman run --rm docker.io/alpine:latest /bin/ash -c 'cat /etc/os-release' | grep -oP 'VERSION_ID=\K.+')
	sed -i "s/ALPINE_VER=.*/ALPINE_VER=v$${VERSION}/" .env
	echo " - alpine version: $$VERSION"



	.PHONY: alpine
alpine:    ## buildah build alpine
	VERSION=$$(podman run --rm docker.io/alpine:latest /bin/ash -c 'cat /etc/os-release' | grep -oP 'VERSION_ID=\K.+')
	echo " - alpine version: $$VERSION"
	CONTAINER=$$(buildah from docker.io/alpine:$${VERSION})
	buildah config --label com.github.containers.toolbox="true" $${CONTAINER}	
	buildah config --author 'Grant Mackenzie <grantmacken@gmail.com>' $${CONTAINER}	
	#echo 'Enable password less sudo'
	#buildah run $${CONTAINER} echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/toolbox
	#echo 'Copy the os-release file'
	#buildah run $${CONTAINER} cp -p /etc/os-release /usr/lib/os-release
	buildah run $${CONTAINER} ls .
	buildah inspect $${CONTAINER} 	
	buildah commit --rm $${CONTAINER} tbx:$${VERSION}


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

.PHONY: create


.PHONY: xxdefault
xxdefault:
	CONTAINER=$$(buildah from $(FROM):$(VERSION))
	buildah run $${CONTAINER} apk add --no-cache neovim
	buildah config --label com.github.containers.toolbox=true $${CONTAINER}	
	buildah config --label usage="This image is meant to be used with the toolbox command" $${CONTAINER}	
	buildah config --label summary="A cloud-native terminal experience" $${CONTAINER}	
	buildah config --label smaintainer="grantmacken@gmail.com" $${CONTAINER}	
	buildah commit --rm --squash $${CONTAINER} $(NAME):$(VERSION)

	

.PHONY: xdefault
xdefault:
	#podman pull quay.io/toolbx-images/alpine-toolbox:edge
	#VERSION=$$(podman run --rm quay.io/toolbx-images/alpine-toolbox:edge /bin/ash -c 'cat /etc/os-release' | grep -oP 'VERSION_ID=\K.+')
	#sed -i "s/ALPINE_VER=.*/ALPINE_VER=v$${VERSION}/" .env
	# echo " - alpine version: $$VERSION"
	CONTAINER=$$(buildah from $(FROM):$(VERSION))
		buildah run $${CONTAINER} apk add --no-cache \
		build-base \
		clipboard \
		cosign \
		github-cli \
		just \
		libstdc++ \
		ncurses-libs \
		neovim \
		openssl \
		ripgrep \
		tzdata \
		vimdiff \
		wl-clipboard \
		zellij
	buildah config --label com.github.containers.toolbox="true" $${CONTAINER}	
	buildah config --label org.opencontainers.image.base.name="$(FROM):$(VERSION)" $${CONTAINER}
	buildah config --label org.opencontainers.image.title='dev toolbx container' $${CONTAINER} # title
	buildah config --label org.opencontainers.image.descriptiion='This image is meant to be used with the toolbox command' $${CONTAINER} # description
	buildah config --label org.opencontainers.image.authors='Grant Mackenzie <grantmacken@gmail.com>' $${CONTAINER} # author
	buildah config --label usage="This image is meant to be used with the toolbox command" $${CONTAINER}	
	buildah config --label summary="A cloud-native terminal experience" $${CONTAINER}	
	buildah config --label smaintainer="grantmacken@gmail.com" $${CONTAINER}	
	buildah commit --rm --squash $${CONTAINER} $(NAME):$(VERSION)
# ifdef GITHUB_ACTIONS
# 	echo 'GITHUB_ACTIONS'
# 	#buildah push ghcr.io/$(REPO_OWNER)/$(call Build,$@):v$${VERSION}
# endif

.PHONY: help
help: ## show this help	
	@cat $(MAKEFILE_LIST) | 
	grep -oP '^[a-zA-Z_-]+:.*?## .*$$' |
	sort |
	awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
