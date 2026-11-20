#Requires -Version 7.4.1
[CmdletBinding()]
param(
    [string]$Destination,
    [string]$Jdk = $env:JAVA_HOME
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if (!$Destination) { $Destination = Join-Path $root 'artifacts/godot-library' }
$Destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Destination)
$sdk = Join-Path $root 'jfx/build/sdk'
$engine = Join-Path $root 'godot/bin/godot.windows.template_release.x86_64.library.dll'
foreach ($file in @($engine, "$Jdk/bin/jar.exe", "$sdk/bin/fxplugins.dll", "$sdk/bin/jfxmedia.dll")) {
    if (!(Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing build product: $file" }
}
New-Item -ItemType Directory -Force $Destination | Out-Null
Copy-Item -LiteralPath "$sdk/legal" -Destination $Destination -Recurse -Force
Copy-Item -LiteralPath "$root/godot/LICENSE.txt","$root/godot/COPYRIGHT.txt","$root/LICENSE" -Destination $Destination
& python "$PSScriptRoot/publish-godot-modules.py" $Destination "$Jdk/bin/jar.exe" --engine $engine
if ($LASTEXITCODE -ne 0) { throw 'Maven module publication failed' }
Write-Output "Published Windows Maven artifacts in $Destination"
