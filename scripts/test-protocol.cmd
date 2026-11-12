@echo off
setlocal
if not defined VSINSTALLDIR set "VSINSTALLDIR=%ProgramFiles%\Microsoft Visual Studio\2022\Community"
set "VSINSTALLDIR=%VSINSTALLDIR:/=\%"
if not "%VSINSTALLDIR:~-1%"=="\" set "VSINSTALLDIR=%VSINSTALLDIR%\"
call "%VSINSTALLDIR%\VC\Auxiliary\Build\vcvars64.bat" >nul
if errorlevel 1 exit /b 1
pushd "%~dp0.."
if not exist artifacts\native-tests mkdir artifacts\native-tests
cl /nologo /std:c++17 /EHsc /W4 /WX /O2 /I native\godot_modules\javafx tests\native\frame_protocol_test.cpp /Foartifacts\native-tests\frame_protocol_test.obj /Feartifacts\native-tests\frame_protocol_test.exe
if errorlevel 1 (popd & exit /b 1)
artifacts\native-tests\frame_protocol_test.exe
set result=%errorlevel%
popd
exit /b %result%
