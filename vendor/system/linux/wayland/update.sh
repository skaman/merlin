#!/bin/sh
set -e

rm -rf tmp
mkdir tmp
pushd tmp

git clone https://gitlab.freedesktop.org/wayland/wayland.git
git clone https://gitlab.freedesktop.org/wayland/wayland-protocols.git

pushd wayland
git checkout tags/1.23.1
mkdir out
meson build/ --prefix=$PWD/out -Dtests=false -Ddocumentation=false -Ddtd_validation=false
ninja -C build/ install
popd # wayland

pushd wayland-protocols
git checkout tags/1.41
mkdir out
#meson build/ --prefix=$PWD/out -Dtests=false
#ninja -C build/ install
popd # wayland-protocols

popd # tmp

rm -rf include
cp -rp tmp/wayland/out/include .

# Wayland
tmp/wayland/out/bin/wayland-scanner client-header tmp/wayland/protocol/wayland.xml include/wayland-client-protocol.h
tmp/wayland/out/bin/wayland-scanner public-code tmp/wayland/protocol/wayland.xml include/wayland-client-protocol-code.h

# XDG Shell
tmp/wayland/out/bin/wayland-scanner client-header tmp/wayland-protocols/stable/xdg-shell/xdg-shell.xml include/xdg-shell-client-protocol.h
tmp/wayland/out/bin/wayland-scanner public-code tmp/wayland-protocols/stable/xdg-shell/xdg-shell.xml include/xdg-shell-client-protocol-code.h

# XDG Decoration
tmp/wayland/out/bin/wayland-scanner client-header tmp/wayland-protocols/unstable/xdg-decoration/xdg-decoration-unstable-v1.xml include/xdg-decoration-unstable-v1-client-protocol.h
tmp/wayland/out/bin/wayland-scanner public-code tmp/wayland-protocols/unstable/xdg-decoration/xdg-decoration-unstable-v1.xml include/xdg-decoration-unstable-v1-client-protocol-code.h

# Viewporter
tmp/wayland/out/bin/wayland-scanner client-header tmp/wayland-protocols/stable/viewporter/viewporter.xml include/viewporter-client-protocol.h
tmp/wayland/out/bin/wayland-scanner public-code tmp/wayland-protocols/stable/viewporter/viewporter.xml include/viewporter-client-protocol-code.h

# Relative Pointer
tmp/wayland/out/bin/wayland-scanner client-header tmp/wayland-protocols/unstable/relative-pointer/relative-pointer-unstable-v1.xml include/relative-pointer-unstable-v1-client-protocol.h
tmp/wayland/out/bin/wayland-scanner public-code tmp/wayland-protocols/unstable/relative-pointer/relative-pointer-unstable-v1.xml include/relative-pointer-unstable-v1-client-protocol-code.h

# Pointer Constraints
tmp/wayland/out/bin/wayland-scanner client-header tmp/wayland-protocols/unstable/pointer-constraints/pointer-constraints-unstable-v1.xml include/pointer-constraints-unstable-v1-client-protocol.h
tmp/wayland/out/bin/wayland-scanner public-code tmp/wayland-protocols/unstable/pointer-constraints/pointer-constraints-unstable-v1.xml include/pointer-constraints-unstable-v1-client-protocol-code.h

# Fractional Scale
tmp/wayland/out/bin/wayland-scanner client-header tmp/wayland-protocols/staging/fractional-scale/fractional-scale-v1.xml include/fractional-scale-v1-client-protocol.h
tmp/wayland/out/bin/wayland-scanner public-code tmp/wayland-protocols/staging/fractional-scale/fractional-scale-v1.xml include/fractional-scale-v1-client-protocol-code.h

# XDG Activation
tmp/wayland/out/bin/wayland-scanner client-header tmp/wayland-protocols/staging/xdg-activation/xdg-activation-v1.xml include/xdg-activation-v1-client-protocol.h
tmp/wayland/out/bin/wayland-scanner public-code tmp/wayland-protocols/staging/xdg-activation/xdg-activation-v1.xml include/xdg-activation-v1-client-protocol-code.h

# Idle Inhibit
tmp/wayland/out/bin/wayland-scanner client-header tmp/wayland-protocols/unstable/idle-inhibit/idle-inhibit-unstable-v1.xml include/idle-inhibit-unstable-v1-client-protocol.h
tmp/wayland/out/bin/wayland-scanner public-code tmp/wayland-protocols/unstable/idle-inhibit/idle-inhibit-unstable-v1.xml include/idle-inhibit-unstable-v1-client-protocol-code.h

rm -rf tmp
