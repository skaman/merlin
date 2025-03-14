#!/bin/sh
set -e

rm -rf tmp
mkdir tmp
pushd tmp

git clone https://gitlab.freedesktop.org/xorg/lib/libx11.git

pushd libx11
git checkout tags/libX11-1.8.12
mkdir out
./autogen.sh
./configure --prefix=$PWD/out
make install
popd # libx11

popd # tmp

rm -rf include
cp -rp tmp/libx11/out/include .
rm -rf tmp
