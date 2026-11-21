#Requires -Version 7.4.1
[CmdletBinding()]
param([string]$Jdk = $env:JAVA_HOME, [ValidateSet('d3d12','vulkan','opengl')][string]$Driver = 'd3d12', [ValidateSet('safe')][string]$RenderThread = 'safe', [switch]$Runtime, [string]$VisualStudio=$(if ($env:VSINSTALLDIR) { $env:VSINSTALLDIR } else { Join-Path $env:ProgramFiles 'Microsoft Visual Studio/2022/Community' }))
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$savedJdk = $env:GODOT_JFX_JDK
$savedHelperEnvironment = @{}
foreach ($name in @('VSINSTALLDIR','GODOT_JFX_HELPER_X','GODOT_JFX_HELPER_Y','GODOT_JFX_HELPER_SRC_X','GODOT_JFX_HELPER_SRC_Y')) {
    $savedHelperEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
Push-Location $root
$helpers = @()
try {
    New-Item -ItemType Directory -Force artifacts/reference,agentdir/logs,artifacts/native-tests | Out-Null
    # External endpoint: a plain Win32 OLE drop target / drag source process.
    $helper = Join-Path $root 'artifacts/native-tests/dnd_helper.exe'
    $buildLog = Join-Path $root 'agentdir/logs/dnd-helper-build.log'
    $env:VSINSTALLDIR = $VisualStudio.Replace('/', '\').TrimEnd('\') + '\'
    $vcvars = (Join-Path $VisualStudio 'VC/Auxiliary/Build/vcvars64.bat')
    & cmd.exe /c "call `"$vcvars`" >nul && cl /nologo /std:c++17 /EHsc /W4 /O2 tests\native\dnd_helper.cpp /Foartifacts\native-tests\dnd_helper.obj /Feartifacts\native-tests\dnd_helper.exe /link ole32.lib shell32.lib user32.lib gdi32.lib > `"$buildLog`" 2>&1"
    if ($LASTEXITCODE -ne 0) { throw "dnd_helper build failed: $buildLog" }
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls -encoding UTF-8 -d artifacts/reference tests/reference/ExternalDragProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'ExternalDragProbe compilation failed' }

    $targetLog = Join-Path $root 'agentdir/logs/dnd-helper-target.log'
    $sourceLog = Join-Path $root 'agentdir/logs/dnd-helper-source.log'
    Remove-Item $targetLog,$sourceLog -ErrorAction SilentlyContinue
    # Chromeless topmost helper windows, right of the 400x160 stage at FX (300,300).
    # The probe drives the mouse in JavaFX logical coordinates; our Glass platform
    # applies the OS display scale (e.g. 200% -> x2), so the native helper windows
    # must be placed at the corresponding *physical* pixels.
    Add-Type -Namespace GodotJfxDpi -Name User32 -MemberDefinition '[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(System.IntPtr ctx); [System.Runtime.InteropServices.DllImport("user32.dll")] public static extern uint GetDpiForSystem();'
    [void][GodotJfxDpi.User32]::SetProcessDpiAwarenessContext([System.IntPtr]::Zero - 4)
    $dpi = [GodotJfxDpi.User32]::GetDpiForSystem()
    if ($dpi -le 96) {
        # Awareness already locked in this process; fall back to the system setting.
        $applied = (Get-ItemProperty 'HKCU:\Control Panel\Desktop\WindowMetrics' -Name AppliedDPI -ErrorAction SilentlyContinue).AppliedDPI
        if ($applied) { $dpi = [uint32]$applied }
    }
    $scale = $dpi / 96.0
    if ($scale -lt 1) { $scale = 1 }
    $tx = [int](780 * $scale); $ty = [int](300 * $scale); $tw = [int](320 * $scale); $th = [int](200 * $scale)
    $sx = [int](1140 * $scale); $sy = $ty
    $helpers += Start-Process -PassThru $helper -ArgumentList 'target',"$tx","$ty","$tw","$th","`"$targetLog`""
    $helpers += Start-Process -PassThru $helper -ArgumentList 'source',"$sx","$sy","$tw","$th","`"$sourceLog`"",'"外部拖入 text"','https://example.org/inbound','C:/helper-source.txt','"外部自定义负载 🙂"'
    $deadline = (Get-Date).AddSeconds(10)
    while ((Get-Date) -lt $deadline) {
        $ready = (Test-Path $targetLog) -and (Select-String -Path $targetLog -Pattern 'DND_HELPER_READY' -Quiet) -and
                 (Test-Path $sourceLog) -and (Select-String -Path $sourceLog -Pattern 'DND_HELPER_READY' -Quiet)
        if ($ready) { break }
        Start-Sleep -Milliseconds 100
    }
    if (-not $ready) { throw "dnd_helper windows did not initialize: $targetLog / $sourceLog" }

    $env:GODOT_JFX_JDK = $Jdk
    $env:GODOT_JFX_HELPER_X = '940'; $env:GODOT_JFX_HELPER_Y = '400'
    $env:GODOT_JFX_HELPER_SRC_X = '1300'; $env:GODOT_JFX_HELPER_SRC_Y = '400'
    $suffix = if($Runtime){'-runtime'}else{''}
    $log = Join-Path $root "agentdir/logs/drag-drop-external-$Driver-$RenderThread$suffix.log"
    if ($Runtime) {
        $fixture = Join-Path $root 'artifacts/runtime-dnd-external'
        New-Item -ItemType Directory -Force $fixture | Out-Null
        Copy-Item -LiteralPath (Join-Path $root 'tests/godot/drag_drop_external.gd'),(Join-Path $root 'tests/godot/drag_drop_external.tscn') -Destination $fixture -Force
        $project = [IO.File]::ReadAllText((Join-Path $root 'tests/godot/project.godot')).Replace('res://main.tscn','res://drag_drop_external.tscn')
        [IO.File]::WriteAllText((Join-Path $fixture 'project.godot'),$project)
        & ./godot/bin/godot.windows.editor.x86_64.console.exe --headless --path $fixture --editor --import *> "$log.import"
        if ($LASTEXITCODE -ne 0) { throw "External drag runtime import failed: $log.import" }
        Push-Location $fixture
        try { Invoke-GodotFixture -Driver $Driver --render-thread $RenderThread --quit-after 30000 *> $log }
        finally { Pop-Location }
    } else {
        Invoke-GodotFixture -Driver $Driver --path tests/godot res://drag_drop_external.tscn --render-thread $RenderThread --quit-after 30000 *> $log
    }
    $result = $LASTEXITCODE
    $output = Get-Content -LiteralPath $log -Raw
    if ($result -ne 0 -or $output -notmatch 'GODOT_EXTERNAL_DRAG_PASS' -or $output -notmatch 'EXTERNAL_DRAG_PROBE_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|Exception)') {
        throw "External drag/drop test failed or incomplete (exit $result). See $log"
    }
    $dropped = Get-Content -LiteralPath $targetLog -Raw -Encoding UTF8
    if ($dropped -notmatch 'DND_HELPER_DROP text=\[外部 OLE 拖放 text\] url=\[https://example\.org/ole\] files=1 first=\[C:\\drag-test\.txt\] custom=\[出站自定义负载 🙂\]') {
        throw "Helper drop payload mismatch: $targetLog"
    }
    # Dragboard.setDragView(8x6, offset 5,3) must reach the shell drag-image
    # helper: the external endpoint observes its DragImageBits during DragEnter.
    if ($dropped -notmatch 'DND_HELPER_ENTER .*image=8x6@5,3 bytes=\d+') {
        throw "Helper did not observe the shell drag image (8x6@5,3): $targetLog"
    }
    $sourced = Get-Content -LiteralPath $sourceLog -Raw -Encoding UTF8
    if ($sourced -notmatch 'DND_HELPER_SOURCE_DONE effect=1') {
        throw "Helper drag source did not complete with COPY: $sourceLog"
    }
    Write-Output "External drag/drop passed: $log"
} finally {
    foreach ($helperProcess in $helpers) { if ($helperProcess -and -not $helperProcess.HasExited) { Stop-Process -Id $helperProcess.Id -Force -ErrorAction SilentlyContinue } }
    foreach ($entry in $savedHelperEnvironment.GetEnumerator()) {
        if ($null -eq $entry.Value) { Remove-Item -LiteralPath "Env:$($entry.Key)" -ErrorAction SilentlyContinue } else { [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process') }
    }
    $env:GODOT_JFX_JDK = $savedJdk
    Pop-Location
}
