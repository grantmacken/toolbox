# a toolbox container with cli tools for [wasi development](https://wasi.dev/)

The toolbox image built from the
[community maintained toolbox container images repo](https://github.com/toolbx-images/images)
The base image used is `quay.io/toolbx-images/fedora-toolbox:40`

Buildah is used to kit out to our toolbox for [wasi development](https://wasi.dev/)

## TOOLS

Installed in this image is  the latest version of neovim
[built from source](https://github.com/neovim/neovim/wiki/Building-Neovim)
For Languages

 - [x] rust
 - [ ] golang
 - [ ] grain
 - [ ] ocaml

## How to use

### Create Box

If you use distrobox:

    distrobox create -i ghcr.io/grantmacken/tbx:v3.18.4 -n tbx
    distrobox enter tbx
    
If you use toolbx:

    toolbox create -i ghcr.io/ublue-os/boxkit -c boxkit
    toolbox enter boxkit

 



## rust

