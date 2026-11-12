@echo off
setlocal
if not defined JAVA_HOME (echo Set JAVA_HOME to JDK 25 before running this test. & exit /b 1)
if not exist "%JAVA_HOME%\include\jni.h" (echo JAVA_HOME is missing JNI headers. & exit /b 1)
if not defined VSINSTALLDIR set "VSINSTALLDIR=%ProgramFiles%\Microsoft Visual Studio\2022\Community"
set "VSINSTALLDIR=%VSINSTALLDIR:/=\%"
if not "%VSINSTALLDIR:~-1%"=="\" set "VSINSTALLDIR=%VSINSTALLDIR%\"
call "%VSINSTALLDIR%\VC\Auxiliary\Build\vcvars64.bat" >nul
if errorlevel 1 exit /b 1
pushd "%~dp0.."
if not exist artifacts\native-tests mkdir artifacts\native-tests
cl /nologo /std:c++17 /EHsc /W4 /WX /O2 /I native\godot_modules\javafx /I "%JAVA_HOME%\include" /I "%JAVA_HOME%\include\win32" tests\native\clipboard_ownership_test.cpp /Foartifacts\native-tests\clipboard_ownership_test.obj /Feartifacts\native-tests\clipboard_ownership_test.exe /link ole32.lib user32.lib gdi32.lib shell32.lib
if errorlevel 1 (popd & exit /b 1)
artifacts\native-tests\clipboard_ownership_test.exe
set result=%errorlevel%
popd
exit /b %result%
