@echo off
setlocal
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" >nul
if errorlevel 1 exit /b 1
pushd "%~dp0.."
if not exist artifacts\native-tests mkdir artifacts\native-tests
cl /nologo /std:c++17 /EHsc /W4 /WX /O2 /I native\godot_modules\javafx tests\native\tabtip_test.cpp /Foartifacts\native-tests\tabtip_test.obj /Feartifacts\native-tests\tabtip_test.exe
if errorlevel 1 (popd & exit /b 1)
artifacts\native-tests\tabtip_test.exe
set result=%errorlevel%
popd
exit /b %result%
