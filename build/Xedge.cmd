@echo off
setlocal
pushd "%~dp0" || exit /b 1

where /q SharkSSLParseCAList.exe
if ERRORLEVEL 1 (
   echo Adding ..\tools\windows to path.
   set "PATH=%~dp0..\tools\windows;%PATH%"
)

for %%i in (zip.exe curl.exe SharkSSLParseCAList.exe bin2c.exe) do (
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
for %%i in (.lua\acmeconfig.lua .lua\acme\runtime.lua .lua\acme\sharktrust.lua .lua\acme\_server.lua) do (
   if not exist "%%i" (
      echo Required ACME module %%i was not packaged.
      goto BuildFailed
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
if /i "%XedgeCaStore%"=="large" goto LargeCerts
if /i "%XedgeCaStore%"=="small" goto SmallCerts
choice /C LS /M "Do you want to use the large cacert.shark or create a new with minimal certs: large/small (l/s)? "
if errorlevel 2 goto SmallCerts

:LargeCerts
echo Using large CA certificate list (cacert.shark)
goto ContinueAfterCerts

:SmallCerts
cd .certificate || goto BuildFailed
if exist cacert.shark del /q cacert.shark
curl.exe -fL https://letsencrypt.org/certs/isrgrootx1.pem > cacert.pem || goto BuildFailed
curl.exe -fL https://letsencrypt.org/certs/isrg-root-x2.pem >> cacert.pem || goto BuildFailed
curl.exe -fL https://letsencrypt.org/certs/trustid-x3-root.pem.txt >> cacert.pem || goto BuildFailed
curl.exe -fL https://cacerts.digicert.com/DigiCertGlobalRootCA.crt.pem >> cacert.pem || goto BuildFailed
curl.exe -fL https://cacerts.digicert.com/DigiCertHighAssuranceEVRootCA.crt.pem >> cacert.pem || goto BuildFailed
curl.exe -fL https://cacerts.digicert.com/DigiCertTrustedRootG4.crt.pem >> cacert.pem || goto BuildFailed
curl.exe -fL https://www.entrust.com/get-support/ssl-certificate-support/root-certificate-downloads/entrust_net_certification_authority_2048.pem >> cacert.pem || goto BuildFailed
curl.exe -fL https://secure.globalsign.com/cacert/Root-R1.crt.pem >> cacert.pem || goto BuildFailed
SharkSSLParseCAList.exe -b cacert.shark cacert.pem || goto BuildFailed
del /q cacert.pem
cd .. || goto BuildFailed

:ContinueAfterCerts
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
