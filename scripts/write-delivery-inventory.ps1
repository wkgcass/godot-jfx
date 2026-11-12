[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$repositories=@()
foreach ($relative in @('.', 'godot', 'jfx', 'vfx')) {
    $directory=Join-Path $root $relative
    $revision=(& git -C $directory rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw "Cannot read revision: $relative" }
    $files=@(& git -C $directory -c core.quotepath=false ls-files --modified --deleted --others --exclude-standard)
    if ($LASTEXITCODE -ne 0) { throw "Cannot list changes: $relative" }
    $staged=@(& git -C $directory -c core.quotepath=false diff --cached --name-only)
    if ($LASTEXITCODE -ne 0) { throw "Cannot list staged changes: $relative" }
    $repositories+=@{path=$relative;head=$revision;changed_paths=@(($files+$staged) | Sort-Object -Unique)}
}
$artifacts=@()
foreach ($relative in @('godot/bin/godot.windows.editor.x86_64.exe',
    'godot/bin/godot.windows.template_release.x86_64.exe',
    'jfx/build/sdk/lib/javafx.graphics.jar','jfx/build/sdk/lib/javafx.controls.jar',
    'jfx/build/sdk/lib/javafx.fxml.jar','jfx/build/sdk/bin/glass.dll',
    'jfx/build/sdk/bin/prism_d3d.dll','jfx/build/sdk/bin/javafx_font.dll',
    'jfx/build/sdk/bin/javafx_iio.dll','jfx/build/sdk/bin/jfxmedia.dll',
    'jfx/build/sdk/bin/glib-lite.dll','jfx/build/sdk/bin/gstreamer-lite.dll','jfx/build/sdk/bin/fxplugins.dll',
    'jfx/build/sdk/bin/jfxwebkit.dll')) {
    $path=Join-Path $root $relative
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $item=Get-Item -LiteralPath $path
        $artifacts+=@{path=$relative;exists=$true;bytes=$item.Length;modified_utc=$item.LastWriteTimeUtc.ToString('o');sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash}
    } else { $artifacts+=@{path=$relative;exists=$false} }
}
$report=@{generated_utc=[DateTime]::UtcNow.ToString('o');workspace=$root;repositories=$repositories;artifacts=$artifacts;note='Working-tree inventory and file presence/hash only; not a build or acceptance certificate. Regenerate after further changes.'}
$destination=Join-Path $root 'artifacts/change-inventory.json'
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $destination -Encoding utf8
Write-Output "Wrote $destination"
foreach ($repository in $repositories) { Write-Output "$($repository.path): $($repository.changed_paths.Count) changed paths" }
