#!/bin/sh
set -e

rm -rf tmp
mkdir tmp
pushd tmp

git clone https://gitlab.freedesktop.org/xorg/lib/libxrender.git

pushd libxrender
git checkout tags/libXrender-0.9.12
mkdir out
./autogen.sh
./configure --prefix=$PWD/out
make install
popd # libxrender

popd # tmp

rm -rf include
cp -rp tmp/libxrender/out/include .
rm -rf tmp
