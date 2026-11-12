@echo off
setlocal
set "helper_test_flags="
if "%~1"=="--asan" set "helper_test_flags=/fsanitize=address /Zi /MD /Fdartifacts\native-tests\dnd_helper_lifetime_test.pdb"
if not defined VSINSTALLDIR set "VSINSTALLDIR=%ProgramFiles%\Microsoft Visual Studio\2022\Community"
set "VSINSTALLDIR=%VSINSTALLDIR:/=\%"
if not "%VSINSTALLDIR:~-1%"=="\" set "VSINSTALLDIR=%VSINSTALLDIR%\"
call "%VSINSTALLDIR%\VC\Auxiliary\Build\vcvars64.bat" >nul
if errorlevel 1 exit /b 1
pushd "%~dp0.."
if not exist artifacts\native-tests mkdir artifacts\native-tests
cl %helper_test_flags% /nologo /std:c++17 /EHsc /W4 /O2 /I native\godot_modules\javafx tests\native\dnd_helper_lifetime_test.cpp /Foartifacts\native-tests\dnd_helper_lifetime_test.obj /Feartifacts\native-tests\dnd_helper_lifetime_test.exe /link ole32.lib shell32.lib user32.lib gdi32.lib
if errorlevel 1 (popd & exit /b 1)
artifacts\native-tests\dnd_helper_lifetime_test.exe
set result=%errorlevel%
popd
exit /b %result%
