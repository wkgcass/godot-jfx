@echo off
setlocal
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" >nul
if errorlevel 1 exit /b 1
pushd "%~dp0.."
if not exist artifacts\native-tests mkdir artifacts\native-tests
cl /nologo /std:c++17 /EHsc /W4 /WX /O2 /I native\godot_modules\javafx /I "D:\jdk-25.0.3+9\include" /I "D:\jdk-25.0.3+9\include\win32" tests\native\dnd_drag_image_test.cpp /Foartifacts\native-tests\dnd_drag_image_test.obj /Feartifacts\native-tests\dnd_drag_image_test.exe /link ole32.lib user32.lib gdi32.lib shell32.lib
if errorlevel 1 (popd & exit /b 1)
artifacts\native-tests\dnd_drag_image_test.exe
set result=%errorlevel%
popd
exit /b %result%
