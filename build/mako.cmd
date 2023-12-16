@echo off

where /q zip.exe
if ERRORLEVEL 1 (
   echo Adding ..\tools\windows to path.
   set "PATH=%CD%\..\tools\windows;%PATH%"
)


set "executables=zip.exe"
for %%i in (%executables%) do (
    where /q %%i
    if ERRORLEVEL 1 (
        echo %%i not found in the path.
        exit /b 1
    )
)
if exist "mako.zip" (del mako.zip)
if exist "MakoBuild" (rmdir /s /q MakoBuild)
mkdir MakoBuild || exit /b 2
cd MakoBuild || exit /b 3
xcopy ..\..\src\core . /eq || exit /b 4
xcopy ..\..\src\mako . /eq || exit /b 5
xcopy ..\..\src\opcua .lua\opcua\ /eq || exit /b 6

if exist "..\..\..\lua-protobuf" (
   echo Including lua-protobuf and Sparkplug lib
   copy ..\..\..\lua-protobuf\protoc.lua .lua > nul || exit /b 7
   copy ..\..\..\lua-protobuf\serpent.lua .lua > nul || exit /b 8
   copy ..\..\src\sparkplug\* .lua > nul || exit /b 9
) else (
   echo ..\..\..\lua-protobuf not found; Not Including lua-protobuf and Sparkplug
)

if exist "..\..\..\LPeg" (
   echo Including LPeg
   copy ..\..\..\LPeg\re.lua .lua > nul || exit /b 10
) else (
   echo ..\..\..\LPeg not found; Not Including LPeg
)

set /p "userResponse=Do you want minify the js and css files (require node and npm) (y/n)? "
if /i "%userResponse%"=="y" (
   where /q npm
    if ERRORLEVEL 1 (
        echo npm not found in the path. Skipping minification.
    ) else (
      call npm install --silent
      call npm run minify-mako
    )
)

echo Create zip file
zip -D -q -u -r -9 ../mako.zip .
cd ..
echo Done
