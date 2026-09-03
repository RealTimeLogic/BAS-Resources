@echo off
setlocal
pushd "%~dp0" || exit /b 1

where /q zip.exe
if ERRORLEVEL 1 (
   echo Adding ..\tools\windows to path.
   set "PATH=%~dp0..\tools\windows;%PATH%"
)
where /q zip.exe
if ERRORLEVEL 1 (
   echo zip.exe not found in the path.
   goto BuildFailed
)

if exist "Xedge.zip" del /q "Xedge.zip"
if exist "XedgeBuild" rmdir /s /q "XedgeBuild"
mkdir "XedgeBuild" || goto BuildFailed
cd "XedgeBuild" || goto BuildFailed
xcopy ..\..\src\xedge . /eq || goto BuildFailed
xcopy ..\..\src\core\.lua\acme .lua\acme\ /eq || goto BuildFailed
for %%i in (.lua\acmeconfig.lua .lua\acme\runtime.lua .lua\acme\sharktrust.lua .lua\acme\_server.lua) do (
   if not exist "%%i" (
      echo Required ACME module %%i was not packaged.
      goto BuildFailed
   )
)

del /q README.md .config
rmdir /s /q .certificate

if /i "%MinifyXedgeZip%"=="yes" set "userResponse=y"
if /i "%MinifyXedgeZip%"=="no" set "userResponse=n"
if not defined userResponse set /p "userResponse=Do you want to minify the JS and CSS files (requires Node and npm) (y/n)? "
if /i "%userResponse%"=="y" (
   where /q npm
   if ERRORLEVEL 1 (
      echo npm not found in the path. Skipping minification.
   ) else (
      call npm install --silent || goto BuildFailed
      call npm run minify-xedge || goto BuildFailed
   )
) else (
   echo Minification skipped.
)

echo Creating the zip file
zip.exe -D -q -u -r -9 ../Xedge.zip . || goto BuildFailed
cd .. || goto BuildFailed
echo Created %~dp0Xedge.zip
popd
endlocal
exit /b 0

:BuildFailed
echo Xedge Mako package build failed.
popd
endlocal
exit /b 1
