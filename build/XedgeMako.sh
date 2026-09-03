#!/bin/bash

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
cd "$script_dir" || exit 1

executables="zip"
for i in $executables; do
    if ! command -v $i &> /dev/null; then
        echo "$i not found in the path."
        exit 1
    fi
done

if [ -f "Xedge.zip" ]; then rm -f Xedge.zip; fi
if [ -d "XedgeBuild" ]; then rm -rf XedgeBuild; fi

mkdir XedgeBuild || exit 1
cd XedgeBuild || exit 1

cp -R ../../src/xedge/. . || exit 1 
mkdir -p .lua/acme || exit 1
cp -R ../../src/core/.lua/acme/. .lua/acme/ || exit 1
for required in .lua/acmeconfig.lua .lua/acme/runtime.lua .lua/acme/sharktrust.lua .lua/acme/_server.lua; do
    if [ ! -f "$required" ]; then
        echo "Required ACME module $required was not packaged."
        exit 1
    fi
done
rm -f README.md
rm -f .config
rm -rf .certificate

read -p "Do you want to minify the JS and CSS files (requires Node and npm) (y/n)? "  userResponse
if [ "$userResponse" = "y" ]; then
   if ! command -v npm> /dev/null 2>&1; then
       echo "npm not found in the path. Skipping minification."
   else
    cd ..
    npm --prefix $(pwd) install --silent
    npm --prefix $(pwd) run minify-xedge
    cd XedgeBuild
   fi
fi

echo "Creating the zip file"
zip -D -q -u -r -9 ../Xedge.zip .
cd ..
