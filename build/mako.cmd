@echo off

pushd "%~dp0" || exit /b 1

where /q zip.exe
if ERRORLEVEL 1 (
   echo Adding ..\tools\windows to path.
   set "PATH=%~dp0..\tools\windows;%PATH%"
)


set "executables=zip.exe"
for %%i in (%executables%) do (
    where /q %%i
    if ERRORLEVEL 1 (
        echo %%i not found in the path.
        popd
        exit /b 1
    )
)
if exist "mako.zip" (del mako.zip)
if exist "MakoBuild" (rmdir /s /q MakoBuild)
mkdir MakoBuild || goto BuildFailed
cd MakoBuild || goto BuildFailed
xcopy ..\..\src\core . /eq || goto BuildFailed
xcopy ..\..\src\mako . /eq || goto BuildFailed
xcopy ..\..\src\opcua .lua\opcua\ /eq || goto BuildFailed
for %%i in (.lua\acme\runtime.lua .lua\acme\sharktrust.lua .lua\acme\_server.lua) do (
   if not exist "%%i" (
      echo Required ACME module %%i was not packaged.
      goto BuildFailed
   )
)

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

if /i "%MinifyMakoZip%"=="yes" (
   set "userResponse=y"
) else if /i "%MinifyMakoZip%"=="no" (
   set "userResponse=n"
) else (
   set /p "userResponse=Do you want to minify the JS and CSS files (requires Node and npm) (y/n)? "
)
if /i "%userResponse%"=="y" (
   where /q npm
    if ERRORLEVEL 1 (
        echo npm not found in the path. Skipping minification.
    ) else (
      call npm install --silent
      call npm run minify-mako
    )
)

echo Creating the zip file
zip -D -q -u -r -9 ../mako.zip .
if ERRORLEVEL 1 goto BuildFailed
cd ..

set "MAKO_ZIP=%~dp0..\tests\MakoZip"
powershell.exe -NoProfile -Command "$root=[IO.Path]::GetFullPath('%~dp0..\tests');$target=[IO.Path]::GetFullPath((Join-Path $root 'MakoZip'));if([IO.Path]::GetDirectoryName($target) -ne $root -or [IO.Path]::GetFileName($target) -ne 'MakoZip'){throw 'Invalid MakoZip target'};if(Test-Path -LiteralPath $target){Get-ChildItem -Force -LiteralPath $target|Remove-Item -Recurse -Force}else{New-Item -ItemType Directory -Path $target|Out-Null}"
if ERRORLEVEL 1 goto BuildFailed
tar.exe -xf "%~dp0mako.zip" -C "%MAKO_ZIP%"
if ERRORLEVEL 1 goto BuildFailed

for %%i in ("%MAKO_ZIP%") do set "MAKO_ZIP=%%~fi"
echo Created %~dp0mako.zip
echo Refreshed %MAKO_ZIP%
echo Use call build\mako.cmd to retain MAKO_ZIP in the current cmd.exe session.
popd
exit /b 0

:BuildFailed
echo Mako package build failed.
popd
exit /b 1
