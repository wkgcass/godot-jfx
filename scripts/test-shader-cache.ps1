[CmdletBinding()]
param([ValidateSet('gl_compatibility','mobile')][string]$Renderer = 'gl_compatibility', [ValidateSet('safe','separate')][string]$RenderThread = 'safe', [switch]$QueuedNotifications)
$ErrorActionPreference = 'Stop'
if ($QueuedNotifications -and $RenderThread -ne 'separate') { throw 'QueuedNotifications requires -RenderThread separate' }
$root = Split-Path $PSScriptRoot -Parent
$savedInstanceUniforms = $env:GODOT_JFX_INSTANCE_UNIFORMS
$savedQueuedNotices = $env:GODOT_JFX_TEST_QUEUED_NOTICES
$env:GODOT_JFX_INSTANCE_UNIFORMS = "1"
$env:GODOT_JFX_TEST_QUEUED_NOTICES = if ($QueuedNotifications) { '1' } else { '0' }
Push-Location $root
try {
    $suffix = if ($QueuedNotifications) { '-queued-notifications' } else { '' }
    $log = "artifacts/logs/shader-cache-$Renderer-$RenderThread$suffix.log"
    & .\godot\bin\godot.windows.editor.x86_64.console.exe --path tests/godot res://shader_cache.tscn --rendering-method $Renderer --render-thread $RenderThread --quit-after 3000 *> $log
    $result = $LASTEXITCODE
    $output = Get-Content $log -Raw
    if ($result -ne 0 -or $output -notmatch 'SHADER_CACHE_PASS' -or $output -notmatch 'SAMPLER_MATERIAL_COLLISION_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:)') { throw "Shader cache test failed. See $log" }
    if ($QueuedNotifications -and $output -notmatch 'QUEUED_NOTICE_INJECTION cycle=274') { throw "Queued notification injection was not reached. See $log" }
    Write-Output "Shader cache test passed: $log"
} finally { $env:GODOT_JFX_INSTANCE_UNIFORMS = $savedInstanceUniforms; $env:GODOT_JFX_TEST_QUEUED_NOTICES = $savedQueuedNotices; Pop-Location }
