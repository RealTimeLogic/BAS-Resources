@echo off
setlocal
pushd "%~dp0" || exit /b 1

where /q zip.exe
if ERRORLEVEL 1 (
   echo Adding ..\tools\windows to path.
   set "PATH=%~dp0..\tools\windows;%PATH%"
)

for %%i in (zip.exe bin2c.exe) do (
   where /q %%i
   if ERRORLEVEL 1 (
      echo %%i not found in the path.
      goto BuildFailed
   )
)

if exist "Xedge.zip" del /q "Xedge.zip"
if exist "XedgeBuild" rmdir /s /q "XedgeBuild"
mkdir "XedgeBuild" || goto BuildFailed
cd "XedgeBuild" || goto BuildFailed
xcopy ..\..\src\core . /eq || goto BuildFailed
xcopy ..\..\src\xedge . /eq || goto BuildFailed
rem Select the TPM at build time, matching the native consumer setting.
if "%SHARKSSL_PSA_CONSUMER%"=="1" (
   copy /y ..\..\src\mako\.lua\psatpm.lua .lua\tpm.lua >nul || goto BuildFailed
)
for %%i in (.lua\seed.lua .lua\acme\runtime.lua .lua\acme\dns.lua .lua\acme\http.lua .lua\acme\_server.lua) do (
   if not exist "%%i" (
      echo Required ACME module %%i was not packaged.
      goto BuildFailed
   )
)

if defined BA_ENABLE_LUA_OPCUA (
   if "%BA_ENABLE_LUA_OPCUA%" == "1" (
      goto YesOPCUA
   ) else (
      goto NoOPCUA
   )
)
if /i "%IncludeOpcUa%"=="yes" goto YesOPCUA
if /i "%IncludeOpcUa%"=="no" goto NoOPCUA
choice /C YN /M "Do you want to include OPC-UA "
if errorlevel 2 goto NoOPCUA

:YesOPCUA
echo Including OPC-UA.
xcopy ..\..\src\opcua .lua\opcua\ /eq || goto BuildFailed
goto ContinueAfterOPCUA

:NoOPCUA
echo OPC-UA inclusion skipped.

:ContinueAfterOPCUA
rem Standalone Xedge uses the CA array compiled into BAS.
if exist ".certificate\cacert.shark" del /q ".certificate\cacert.shark"
if exist ".certificate\cacert.shark" goto BuildFailed
del /q README.md .preload .gitignore

if exist "..\..\..\lua-protobuf" (
   echo Including lua-protobuf and Sparkplug lib
   copy ..\..\..\lua-protobuf\protoc.lua .lua > nul || goto BuildFailed
   copy ..\..\..\lua-protobuf\serpent.lua .lua > nul || goto BuildFailed
   copy ..\..\src\sparkplug\* .lua > nul || goto BuildFailed
) else (
   echo ..\..\..\lua-protobuf not found; Not Including lua-protobuf and Sparkplug
)

if exist "..\..\..\LPeg" (
   echo Including LPeg
   copy ..\..\..\LPeg\re.lua .lua > nul || goto BuildFailed
   if exist "..\..\..\CBOR" (
      echo Including CBOR 'cbor_s.lua'
      mkdir .lua\org\conman
      copy ..\..\..\CBOR\cbor_s.lua .lua\org\conman > nul || goto BuildFailed
   ) else (
      echo ..\..\..\CBOR not found; Not Including CBOR
   )
) else (
   echo ..\..\..\LPeg not found; Not Including LPeg
)

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
if not defined NO_BIN2C (
   bin2c.exe -z getLspZipReader Xedge.zip XedgeZip.c || goto BuildFailed
   echo Copy the produced XedgeZip.c resource file to your build directory
)
echo Created %~dp0Xedge.zip
popd
endlocal
exit /b 0

:BuildFailed
echo Xedge package build failed.
popd
endlocal
exit /b 1
