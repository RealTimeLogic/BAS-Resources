executables="zip"
for i in $executables; do
    if ! command -v $i &> /dev/null; then
        echo "$i not found in the path."
        exit 1
    fi
done

if [ -f "xedge.zip" ]; then rm -f xedge.zip; fi
if [ -d "XedgeBuild" ]; then rm -rf XedgeBuild; fi

mkdir XedgeBuild || exit 1
cd XedgeBuild || exit 1

cp -R ../../src/xedge/. . || exit 1 
rm -f README.md
rm -f .config
rm -rf /s /q .certificate

zip -D -q -u -r -9 ../Xedge.zip .
cd ..
