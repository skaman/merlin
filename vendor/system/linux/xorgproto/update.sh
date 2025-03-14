#!/bin/sh
set -e

rm -rf tmp
mkdir tmp
pushd tmp

git clone https://gitlab.freedesktop.org/xorg/proto/xorgproto.git

pushd xorgproto
git checkout tags/xorgproto-2024.1
mkdir out
./autogen.sh
./configure --prefix=$PWD/out
make install
popd # xorgproto

popd # tmp

rm -rf include
cp -rp tmp/xorgproto/out/include .
rm -rf tmp
