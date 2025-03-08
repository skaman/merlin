#!/bin/bash

set -e

echo "----------------------------------------------------------------------------------------------------"
echo "Copying ktx-software"
echo "----------------------------------------------------------------------------------------------------"
rm -rf tmp
mkdir tmp
cp -r upstream tmp
pushd tmp/upstream

echo "----------------------------------------------------------------------------------------------------"
echo "Generating build files"
echo "----------------------------------------------------------------------------------------------------"
mkdir -p build && pushd build
cmake -GNinja ..
ninja
popd

echo "----------------------------------------------------------------------------------------------------"
echo "Copying generated headers"
echo "----------------------------------------------------------------------------------------------------"
rm -rf ../../generated
mkdir -p ../../generated
cp lib/version.h ../../generated

echo "----------------------------------------------------------------------------------------------------"
echo "Cleaning up"
echo "----------------------------------------------------------------------------------------------------"
popd
rm -rf tmp
