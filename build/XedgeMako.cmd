@echo off

set "executables=zip.exe"
for %%i in (%executables%) do (
    where /q %%i
    if ERRORLEVEL 1 (
        echo %%i not found in the path.
        exit /b 1
    )
)
if exist "xedge.zip" (del xedge.zip)
if exist "XedgeBuild" (rmdir /s /q XedgeBuild)
mkdir XedgeBuild || exit /b 2
cd XedgeBuild || exit /b 3
xcopy ..\..\src\xedge . /eq || exit /b 5

del README.md
del .config
rmdir /s /q .certificate

set /p "userResponse=Do you want minify the Lua, js and css files (require node and npm) (y/n)? "
if /i "%userResponse%"=="y" (
   where /q npm
    if ERRORLEVEL 1 (
        echo npm not found in the path. Skipping minification.
    ) else (
      call npm install --silent
      call npm run minify-xedge
    )
)

echo Create zip file
zip -D -q -u -r -9 ../Xedge.zip .
cd ..
echo Done
