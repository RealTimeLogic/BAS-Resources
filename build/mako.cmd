@echo off
set "executables=zip.exe"
for %%i in (%executables%) do (
    where /q %%i
    if ERRORLEVEL 1 (
        echo %%i not found in the path.
        exit /b
    )
)
if exist "mako.zip" (del mako.zip)
if exist "MakoBuild" (rmdir /s /q MakoBuild)
mkdir MakoBuild || exit /b
cd MakoBuild || exit /b
xcopy ..\..\src\core . /eq || exit /b
xcopy ..\..\src\mako . /eq || exit /b
xcopy ..\..\src\opcua\* .lua /eq || exit /b

if exist "..\..\..\lua-protobuf" (
   echo Including lua-protobuf and Sparkplug lib
   copy ..\..\..\lua-protobuf\protoc.lua .lua > nul || exit /b
   copy ..\..\..\lua-protobuf\serpent.lua .lua > nul || exit /b
   copy ..\..\src\sparkplug\* .lua > nul || exit /b
) else (
   echo ..\..\..\lua-protobuf not found; Not Including lua-protobuf and Sparkplug
)


zip -D -q -u -r -9 ../mako.zip .
cd ..
