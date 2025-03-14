#!/bin/sh
set -e

rm -rf tmp
mkdir tmp
pushd tmp

git clone https://gitlab.freedesktop.org/xorg/lib/libxrandr.git

pushd libxrandr
git checkout tags/libXrandr-1.5.4
mkdir out
./autogen.sh
./configure --prefix=$PWD/out
make install
popd # libxrandr

popd # tmp

rm -rf include
cp -rp tmp/libxrandr/out/include .
rm -rf tmp
