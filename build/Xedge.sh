#!/bin/bash

export PATH=$PWD/../tools/linux:$PATH
chmod +x ../tools/linux/*
executables="zip curl SharkSSLParseCAList bin2c"
for i in $executables; do
    if ! command -v $i &> /dev/null; then
        echo "$i not found in the path."
        exit 1
    fi
done

if [ -f "xedge.zip" ]; then rm xedge.zip; fi
if [ -d "XedgeBuild" ]; then rm -rf XedgeBuild; fi

mkdir XedgeBuild || exit 1
cd XedgeBuild || exit 1

#We must also include hidden files/directories
shopt -s dotglob

cp -R ../../src/core/* . || exit 1
cp -R ../../src/xedge/* . || exit 1
cp -R ../../src/mako/.lua/acme/* .lua/acme || exit 1

read -p "Do you want to include OPC-UA (y/n)? " userResponse
if [ "$userResponse" = "y" ]; then
    cp -R ../../src/opcua .lua/ || exit 1
fi

read -p "Do you want to use the large cacert.shark or do you want to create a new with minimal certs: large/small (l/s)? " userResponse
if [ "$userResponse" = "s" ]; then
    cd .certificate || exit 1
    rm cacert.shark || exit 1
    curl https://letsencrypt.org/certs/isrgrootx1.pem > cacert.pem
    curl https://letsencrypt.org/certs/isrg-root-x2.pem >> cacert.pem
    curl https://letsencrypt.org/certs/trustid-x3-root.pem.txt >> cacert.pem
    curl https://cacerts.digicert.com/DigiCertGlobalRootCA.crt.pem >> cacert.pem
    curl https://cacerts.digicert.com/DigiCertHighAssuranceEVRootCA.crt.pem >> cacert.pem
    curl https://cacerts.digicert.com/DigiCertTrustedRootG4.crt.pem >> cacert.pem
    curl https://www.entrust.com/get-support/ssl-certificate-support/root-certificate-downloads/entrust_net_certification_authority_2048.pem >> cacert.pem
    curl https://secure.globalsign.com/cacert/Root-R1.crt.pem >> cacert.pem
    SharkSSLParseCAList -b cacert.shark cacert.pem
    rm cacert.pem
    cd ..
fi

rm README.md
rm .preload
rm .gitignore
rm .lua/Xedge4Mako.lua


if [ -d "../../../lua-protobuf" ]; then
    echo "Including lua-protobuf and Sparkplug lib"
    cp ../../../lua-protobuf/protoc.lua .lua || exit 1
    cp ../../../lua-protobuf/serpent.lua .lua || exit 1
    cp ../../src/sparkplug/* .lua || exit 1
else
    echo "../../../lua-protobuf not found; Not Including lua-protobuf and Sparkplug"
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
    bin2c -z getLspZipReader Xedge.zip XedgeZip.c
    echo "Copy XedgeZip.c to your build directory"
fi
