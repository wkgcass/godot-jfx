[CmdletBinding()]
param([string]$Jdk=$env:JAVA_HOME,[ValidateSet('d3d','safe')][string]$Backend='safe',[ValidateSet(1,2)][int]$Rate=1,[ValidateRange(0,20)][int]$Sample=0,[switch]$ClockSkew,[switch]$Native60,[switch]$NoVSync,[switch]$FramePhases,[switch]$Runtime)
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$savedJdk=$env:GODOT_JFX_JDK;$savedMedia=$env:GODOT_JFX_MEDIA_FILE;$savedOptions=$env:JAVA_TOOL_OPTIONS
$savedRate=$env:GODOT_JFX_MEDIA_RATE
$savedClock=$env:GODOT_JFX_MEDIA_CLOCK
$savedFixture=$env:GODOT_JFX_MEDIA_FIXTURE
$savedPhases=$env:GODOT_JFX_MEDIA_FRAME_PHASES
Push-Location $root
try {
    if($Runtime -and $Backend -eq 'd3d'){throw 'Runtime requires a Godot backend'}
    $backendName=if($Backend -eq 'd3d'){'Native JavaFX / Windows Glass / D3D (comparison only)'}elseif($Runtime){"Godot DLL (isolated project) / Glass-Godot / Prism-Godot / Vulkan / $Backend"}else{"Godot DLL / Glass-Godot / Prism-Godot / Vulkan / $Backend"}
    Write-Output "Media frame backend: $backendName"
    $env:GODOT_JFX_MEDIA_FRAME_PHASES=if($FramePhases){'1'}else{'0'}
    $env:GODOT_JFX_MEDIA_RATE="$Rate"
    $env:GODOT_JFX_MEDIA_CLOCK=if($ClockSkew){'1'}else{'0'}
    $env:GODOT_JFX_MEDIA_FIXTURE=if($Native60){'1080p60'}else{'oracle30'}
    if($Native60){
        $env:GODOT_JFX_MEDIA_FILE=Join-Path $root 'artifacts/reference/media-1080p60.mp4'
        $fixture=Get-Content artifacts/reference/media-1080p60.json -Raw | ConvertFrom-Json
        if($fixture.width -ne 1920 -or $fixture.height -ne 1080 -or $fixture.fps -ne 60 -or $fixture.frames -ne 960 -or $fixture.codec -ne 'H264' -or $fixture.sha256 -ne (Get-FileHash $env:GODOT_JFX_MEDIA_FILE -Algorithm SHA256).Hash -or $fixture.source_sha256 -ne (Get-FileHash tests/native/make_media_fixture.cpp -Algorithm SHA256).Hash){throw 'Regenerate and verify fixture using make-media-fixture.ps1'}
    }else{
        $relative = & python "$PSScriptRoot/setup-env.py" --sample-path oracle
        if ($LASTEXITCODE) { throw "Invalid Oracle playback sample" }
        $env:GODOT_JFX_MEDIA_FILE = Join-Path $root $relative
    }
    $exports=@('--add-exports=javafx.media/com.sun.media.jfxmedia=ALL-UNNAMED','--add-exports=javafx.media/com.sun.media.jfxmedia.control=ALL-UNNAMED','--add-exports=javafx.media/com.sun.media.jfxmedia.events=ALL-UNNAMED','--add-exports=javafx.graphics/com.sun.prism=ALL-UNNAMED','--add-exports=javafx.graphics/com.sun.glass.ui=ALL-UNNAMED')
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls,javafx.media @exports -d artifacts/reference tests/reference/MediaFrameBenchmark.java
    if($LASTEXITCODE -ne 0){throw 'Media frame benchmark compilation failed'}
    $env:JAVA_TOOL_OPTIONS="$savedOptions --add-opens=javafx.media/javafx.scene.media=ALL-UNNAMED $($exports -join ' ')"
    $suffix=if($Rate -eq 1){''}else{"-rate$Rate"}
    if($Native60){$suffix+='-1080p60'}
    if($Sample){$suffix+="-sample$Sample"}
    if($ClockSkew){$suffix+='-clock'}
    if($NoVSync){$suffix+='-novsync'}
    if($FramePhases){$suffix+='-phases'}
    if($Runtime){$suffix+='-runtime'}
    $log=Join-Path $root "artifacts/logs/media-frame-benchmark-$Backend$suffix.log"
    if($Backend -eq 'd3d'){
        [string[]]$javaArgs=if($NoVSync){@('-Dprism.vsync=false')}else{@()}
        & "$Jdk/bin/java.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls,javafx.media --enable-native-access=javafx.graphics,javafx.media '-Dprism.order=d3d' @javaArgs -cp artifacts/reference MediaFrameBenchmark *> $log
    }else{
        $env:GODOT_JFX_JDK=$Jdk
        $hostArgs=if($NoVSync){@('--disable-vsync')}else{@()}
        if($Runtime){
            $fixture=Join-Path $root 'artifacts/runtime-media-frames'
            New-Item -ItemType Directory -Force $fixture | Out-Null
            Copy-Item -LiteralPath (Join-Path $root 'tests/godot/media_frame_benchmark.gd'),(Join-Path $root 'tests/godot/media_frame_benchmark.tscn') -Destination $fixture -Force
            $project=[IO.File]::ReadAllText((Join-Path $root 'tests/godot/project.godot')).Replace('res://main.tscn','res://media_frame_benchmark.tscn')
            [IO.File]::WriteAllText((Join-Path $fixture 'project.godot'),$project)
            & ./godot/bin/godot.windows.editor.x86_64.console.exe --headless --path $fixture --editor --import *> "$log.import"
            if($LASTEXITCODE -ne 0){throw "Media benchmark Runtime import failed: $log.import"}
            Push-Location $fixture
            try { Invoke-GodotFixture --rendering-method mobile --render-thread $Backend @hostArgs *> $log }
            finally {Pop-Location}
        }else{
            Invoke-GodotFixture --path tests/godot res://media_frame_benchmark.tscn --rendering-method mobile --render-thread $Backend @hostArgs *> $log
        }
    }
    $code=$LASTEXITCODE;$output=Get-Content $log -Raw
    if($code -ne 0 -or $output -notmatch 'MEDIA_FRAME_BENCHMARK_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)|uncaught:'){throw "Media benchmark failed: $log"}
    if($Backend -ne 'd3d' -and $output -notmatch 'GODOT_MEDIA_FRAME_PASS'){throw 'Missing host measurement'}
    if($output -notmatch '(?m)^MEDIA_FRAME_JAVA .* unfocused=0\s*$'){throw "Measurement lost window focus; do not compare FPS: $log"}
    if($Backend -ne 'd3d' -and $output -notmatch '"unfocused_ticks":0'){throw "Host measurement lost window focus: $log"}
    $expected=if($Backend -eq 'd3d'){'MEDIA_FRAME_BACKEND glass=com.sun.glass.ui.win.WinApplication prism=com.sun.prism.d3d.D3DPipeline'}else{'MEDIA_FRAME_BACKEND glass=com.sun.glass.ui.godot.GodotApplication prism=com.sun.prism.godot.GODOTPipeline'}
    if(!$output.Contains($expected)){throw "Unexpected Glass/Prism backend: $log"}
    if($Native60 -and $Rate -eq 1){
        $fps=[regex]::Match($output,'(?m)^MEDIA_FRAME_JAVA .* rendered_fps=([0-9.]+) ')
        if(!$fps.Success -or [double]::Parse($fps.Groups[1].Value,[Globalization.CultureInfo]::InvariantCulture) -lt 55){throw "1080p60 throughput below 55 FPS: $log"}
        if($Backend -ne 'd3d'){
            $hostSample=[regex]::Match($output,'(?m)^MEDIA_FRAME_HOST (\{[^\r\n]+\})')
            if(!$hostSample.Success){throw "Missing host counters: $log"}
            $counters=$hostSample.Groups[1].Value | ConvertFrom-Json
            if($counters.elapsed_ms -le 0 -or $counters.presentations*1000.0/$counters.elapsed_ms -lt 55 -or $counters.backpressure -ne 0){throw "1080p60 host throughput/backpressure check failed: $log"}
        }
        Write-Output 'MEDIA_FRAME_60FPS_ACCEPTANCE_PASS minimum_fps=55'
    }
    Write-Output $output
}finally{$env:GODOT_JFX_MEDIA_FRAME_PHASES=$savedPhases;$env:GODOT_JFX_MEDIA_FIXTURE=$savedFixture;$env:GODOT_JFX_MEDIA_CLOCK=$savedClock;$env:GODOT_JFX_MEDIA_RATE=$savedRate;$env:GODOT_JFX_JDK=$savedJdk;$env:GODOT_JFX_MEDIA_FILE=$savedMedia;$env:JAVA_TOOL_OPTIONS=$savedOptions;Pop-Location}
