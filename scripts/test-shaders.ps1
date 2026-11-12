[CmdletBinding()]
param([ValidateSet('gl_compatibility', 'mobile')][string]$Renderer = 'gl_compatibility')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$log = Join-Path $root "artifacts/logs/godot-shaders-$Renderer.log"
Push-Location $root
try {
    $generated = Join-Path $root 'jfx/modules/javafx.graphics/build/gensrc'
    $groups = @(
        @('jsl-prism', 'com/sun/prism/godot/shaders', 'com/sun/prism/d3d/hlsl'),
        @('jsl-decora', 'com/sun/scenario/effect/impl/godot/shaders', 'com/sun/scenario/effect/impl/hw/d3d/hlsl')
    )
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $sdk = [IO.Compression.ZipFile]::OpenRead((Join-Path $root 'jfx/build/sdk/lib/javafx.graphics.jar'))
    try {
        foreach ($group in $groups) {
            $sources = @(Get-ChildItem -LiteralPath (Join-Path $generated "$($group[0])/$($group[1])") -Filter '*.gdshader' -File)
            $reference = @(Get-ChildItem -LiteralPath (Join-Path $generated "$($group[0])/$($group[2])") -Filter '*.hlsl' -File)
            if ($sources.Count -eq 0 -or $reference.Count -eq 0 -or (Compare-Object ($sources.BaseName | Sort-Object) ($reference.BaseName | Sort-Object))) {
                throw "Godot shader variant coverage differs from existing D3D generation: $($group[0])"
            }
            foreach ($source in $sources) {
                $entry = $sdk.GetEntry("$($group[1])/$($source.Name)")
                if (!$entry) { throw "Generated shader missing from SDK: $($source.Name)" }
                $reader = [IO.StreamReader]::new($entry.Open())
                try { $packaged = $reader.ReadToEnd() } finally { $reader.Dispose() }
                if ($packaged -cne [IO.File]::ReadAllText($source.FullName)) { throw "Stale SDK shader: $($source.Name)" }
            }
        }
    } finally { $sdk.Dispose() }
    & .\godot\bin\godot.windows.editor.x86_64.console.exe --path tests/godot res://shaders.tscn --rendering-method $Renderer --quit-after 3000 *> $log
    $result = $LASTEXITCODE
    $output = Get-Content -LiteralPath $log -Raw
    if ($result -ne 0 -or $output -notmatch 'GODOT_SHADER_PASS count=' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:)') {
        throw "Generated shader validation failed. See $log"
    }
    Copy-Item artifacts/reference/godot-generated-shader.png "artifacts/reference/godot-generated-shader-$Renderer.png"
    Copy-Item artifacts/reference/godot-shader-states.png "artifacts/reference/godot-shader-states-$Renderer.png"
    Write-Output "Generated shader validation passed on $Renderer. Log: $log"
} finally { Pop-Location }
