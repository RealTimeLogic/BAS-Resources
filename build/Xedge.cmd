@echo off

where /q SharkSSLParseCAList.exe
if ERRORLEVEL 1 (
   echo Adding ..\tools\windows to path.
   set "PATH=%CD%\..\tools\windows;%PATH%"
)

set "executables=zip.exe curl.exe SharkSSLParseCAList.exe bin2c.exe"
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
xcopy ..\..\src\core . /eq || exit /b 4
xcopy ..\..\src\xedge . /eq || exit /b 5
xcopy ..\..\src\mako\.lua\acme .lua\acme  /eq || exit /b 6
set /p "userResponse=Do you want to include OPC-UA (y/n)? "
if /i "%userResponse%"=="y" (
   xcopy ..\..\src\opcua .lua\opcua\ /eq || exit /b 7
)

set /p "userResponse=Do you want to use the large cacert.shark or do you want to create a new with minimal certs: large/small (l/s)? "
if /i "%userResponse%"=="s" (
   cd .certificate || exit /b 8
   del cacert.shark || exit /b 9
   rem List from asking AI for the most common root certs
   curl https://letsencrypt.org/certs/isrgrootx1.pem > cacert.pem
   curl https://letsencrypt.org/certs/isrg-root-x2.pem >> cacert.pem
   curl https://letsencrypt.org/certs/trustid-x3-root.pem.txt >> cacert.pem
   curl https://cacerts.digicert.com/DigiCertGlobalRootCA.crt.pem >> cacert.pem
   curl https://cacerts.digicert.com/DigiCertHighAssuranceEVRootCA.crt.pem >> cacert.pem
   curl https://cacerts.digicert.com/DigiCertTrustedRootG4.crt.pem >> cacert.pem
   curl https://www.entrust.com/get-support/ssl-certificate-support/root-certificate-downloads/entrust_net_certification_authority_2048.pem >> cacert.pem
   curl https://secure.globalsign.com/cacert/Root-R1.crt.pem >> cacert.pem
   SharkSSLParseCAList -b cacert.shark cacert.pem
   del cacert.pem
   cd ..
)

del README.md
del .preload
del .gitignore

if exist "..\..\..\lua-protobuf" (
   echo Including lua-protobuf and Sparkplug lib
   copy ..\..\..\lua-protobuf\protoc.lua .lua > nul || exit /b 10
   copy ..\..\..\lua-protobuf\serpent.lua .lua > nul || exit /b 11
   copy ..\..\src\sparkplug\* .lua > nul || exit /b 12
) else (
   echo ..\..\..\lua-protobuf not found; Not Including lua-protobuf and Sparkplug
)


zip -D -q -u -r -9 ../Xedge.zip .
cd ..
IF NOT DEFINED NO_BIN2C (
   bin2c -z getLspZipReader Xedge.zip XedgeZip.c
   echo Done!
   echo Copy the produced XedgeZip.c resource file to your build directory
)
