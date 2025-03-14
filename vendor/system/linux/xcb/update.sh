#!/bin/sh
set -e

rm -rf tmp
mkdir tmp
pushd tmp

git clone https://gitlab.freedesktop.org/xorg/lib/libxcb.git

pushd libxcb
git checkout tags/libxcb-1.17.0
mkdir out
./autogen.sh
./configure --prefix=$PWD/out
make install
popd # libxcb

popd # tmp

rm -rf include
cp -rp tmp/libxcb/out/include .
rm -rf tmp
