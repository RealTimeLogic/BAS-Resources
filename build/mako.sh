#!/bin/bash
executables="zip"

for i in $executables; do
    if ! command -v $i &> /dev/null; then
        echo "$i not found in the path."
        exit 1
    fi
done

if [ -f "mako.zip" ]; then rm mako.zip; fi
if [ -d "MakoBuild" ]; then rm -rf MakoBuild; fi

mkdir MakoBuild || exit 1
cd MakoBuild || exit 1

#We must also include hidden files/directories
shopt -s dotglob

cp -R ../../src/core/* . || exit 1
cp -R ../../src/mako/* . || exit 1
cp -R ../../src/opcua .lua/ || exit 1

if [ -d "../../../lua-protobuf" ]; then
    echo "Including lua-protobuf and Sparkplug lib"
    cp ../../../lua-protobuf/protoc.lua .lua/ || exit 1
    cp ../../../lua-protobuf/serpent.lua .lua/ || exit 1
    cp ../../src/sparkplug/* .lua || exit 1
else
    echo "../../../lua-protobuf not found; Not Including lua-protobuf and Sparkplug"
fi

if [ -d "../../../LPeg" ]; then
    echo "Including LPeg"
    cp ../../../LPeg/re.lua .lua/ || exit 1
else
    echo "../../../LPeg not found; Not Including LPeg"
fi

read -p "Do you want minify the js and css files (require node and npm) (y/n)? "  userResponse
if [ "$userResponse" = "y" ]; then
   if ! command -v npm> /dev/null 2>&1; then
       echo "npm not found in the path. Skipping minification."
   else
    cd ..
    npm --prefix $(pwd) install --silent
    npm --prefix $(pwd) run minify-mako
    cd MakoBuild
   fi
fi

echo "Create zip file"
zip -D -q -u -r -9 ../mako.zip .
cd ..

echo "Done"

