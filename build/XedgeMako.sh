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

read -p "Do you want to minify the js and css files (require node and npm) (y/n)? "  userResponse
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


zip -D -q -u -r -9 ../Xedge.zip .
cd ..
