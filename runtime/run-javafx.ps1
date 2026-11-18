# Invoke from any directory. Pass application/module options and the Java entry point.
$ErrorActionPreference = 'Stop'
if (!$env:JAVA_HOME) { throw 'Set JAVA_HOME to JDK 25' }
& (Join-Path $env:JAVA_HOME 'bin/java.exe') "--module-path" (Join-Path $PSScriptRoot 'modules') '--add-modules=javafx.controls,javafx.fxml,javafx.media,javafx.swing' '--enable-native-access=javafx.graphics,javafx.media' "-Djavafx.godot.runtime=$PSScriptRoot" @args
exit $LASTEXITCODE
