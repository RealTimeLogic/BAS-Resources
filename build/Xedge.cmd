@echo off
set "executables=zip.exe curl.exe SharkSSLParseCAList.exe bin2c.exe"
for %%i in (%executables%) do (
    where /q %%i
    if ERRORLEVEL 1 (
        echo %%i not found in the path.
        exit /b
    )
)
if exist "xedge.zip" (del xedge.zip)
if exist "XedgeBuild" (rmdir /s /q XedgeBuild)
mkdir XedgeBuild || exit /b
cd XedgeBuild || exit /b
xcopy ..\..\src\core . /eq || exit /b
xcopy ..\..\src\xedge . /eq || exit /b
xcopy ..\..\src\mako\.lua\acme .lua\acme  /eq || exit /b
set /p "userResponse=Do you want to include OPC-UA (y/n)? "
if /i "%userResponse%"=="y" (
    xcopy ..\..\src\opcua\* .lua /eq || exit /b
)

set /p "userResponse=Do you want to use the large cacert.shark or do you want to create a new with minimal certs large/small (l/s)? "
if /i "%userResponse%"=="s" (
   cd .certificate || exit /b
   del cacert.shark || exit /b
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

if exist "..\..\..\lua-protobuf" (
   echo Including lua-protobuf and Sparkplug lib
   copy ..\..\..\lua-protobuf\protoc.lua .lua > nul || exit /b
   copy ..\..\..\lua-protobuf\serpent.lua .lua > nul || exit /b
   copy ..\..\src\sparkplug\* .lua > nul || exit /b
) else (
   echo ..\..\..\lua-protobuf not found; Not Including lua-protobuf and Sparkplug
)


zip -D -q -u -r -9 ../Xedge.zip .
cd ..
bin2c -z getLspZipReader Xedge.zip XedgeZip.c
echo Copy XedgeZip.c to your build directory

