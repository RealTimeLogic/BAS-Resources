#!/bin/bash

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
cd "$script_dir" || exit 1
export PATH="$script_dir/../tools/linux:$PATH"
chmod +x ../tools/linux/*
executables="zip bin2c"
for i in $executables; do
    if ! command -v $i &> /dev/null; then
        echo "$i not found in the path."
        exit 1
    fi
done

if [ -f "Xedge.zip" ]; then rm Xedge.zip; fi
if [ -d "XedgeBuild" ]; then rm -rf XedgeBuild; fi

mkdir XedgeBuild || exit 1
cd XedgeBuild || exit 1

#We must also include hidden files/directories
shopt -s dotglob

cp -R ../../src/core/* . || exit 1
cp -R ../../src/xedge/* . || exit 1
# Select the TPM at build time, matching the native consumer setting.
if [ "$SHARKSSL_PSA_CONSUMER" = "1" ]; then
    cp ../../src/mako/.lua/psatpm.lua .lua/tpm.lua || exit 1
fi

for required in .lua/acme/runtime.lua .lua/acme/dns.lua .lua/acme/http.lua .lua/acme/_server.lua; do
    if [ ! -f "$required" ]; then
        echo "Required ACME module $required was not packaged."
        exit 1
    fi
done

if [ -z "$USE_OPCUA" ] ; then
    read -p "Do you want to include OPC-UA (y/n)? " userResponse
    if [ "$userResponse" = "y" ] ; then
        USE_OPCUA=1
    else
        USE_OPCUA=0
    fi
fi

if [ "$USE_OPCUA" != "0" ] ; then
    echo "Including OPCUA"
    cp -R ../../src/opcua .lua/ || exit 1
else
    echo "Excluding OPCUA"
fi

# Standalone Xedge uses the CA array compiled into BAS.
rm -f .certificate/cacert.shark || exit 1

rm -f README.md .preload .gitignore


if [ -d "../../../lua-protobuf" ]; then
    echo "Including lua-protobuf and Sparkplug lib"
    cp ../../../lua-protobuf/protoc.lua .lua || exit 1
    cp ../../../lua-protobuf/serpent.lua .lua || exit 1
    cp ../../src/sparkplug/* .lua || exit 1
else
    echo "../../../lua-protobuf not found; Not Including lua-protobuf and Sparkplug"
fi

if [ -d "../../../LPeg" ]; then
    echo "Including LPeg"
    cp ../../../LPeg/re.lua .lua/ || exit 1
    if [ -d "../../../CBOR" ]; then
        echo "Including CBOR 'cbor_s.lua'"
        mkdir -p .lua/org/conman
        cp ../../../CBOR/cbor_s.lua .lua/org/conman || exit 1
    else
        echo "../../../CBOR not found; Not Including CBOR"
    fi
else
    echo "../../../LPeg not found; Not Including LPeg"
fi

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
if [ -z "$NO_BIN2C" ]; then
    echo "Running bin2c..."
    if ! bin2c -z getLspZipReader Xedge.zip XedgeZip.c; then
        echo "bin2c failed - attempting to compile it..."
        gcc -o ../tools/linux/bin2c ../../BAS/tools/bin2c.c || {
            echo "Compilation of bin2c failed."
            exit 1
        }
        echo "Retrying bin2c..."
        if ! ../tools/linux/bin2c -z getLspZipReader Xedge.zip XedgeZip.c; then
            echo "bin2c failed again after recompiling. Exiting."
            exit 1
        fi
    fi
    echo "Copy XedgeZip.c to your build directory"
fi
