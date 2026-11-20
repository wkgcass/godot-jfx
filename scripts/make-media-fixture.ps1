#Requires -Version 7.4.1
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$names=@('PATH','INCLUDE','LIB')
$saved=@{};foreach($name in $names){$saved[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
Push-Location $root
try {
    $config=@{}
    Get-Content jfx/build/windows_tools.properties | ForEach-Object {
        $pair=$_ -split '=',2
        if($pair.Count -eq 2){$config[$pair[0]]=$pair[1]}
    }
    foreach($name in $names){
        $value=$config["WINDOWS_VS_$name"]
        if(!$value){throw "Missing source-build toolchain setting: $name"}
        [Environment]::SetEnvironmentVariable($name,$value,'Process')
    }
    $target=Join-Path $root 'agentdir/artifacts/media-fixture'
    New-Item -ItemType Directory -Force $target,agentdir/logs,agentdir/media | Out-Null
    $exe=Join-Path $target 'make_media_fixture.exe'
    $obj=Join-Path $target 'make_media_fixture.obj'
    & cl.exe /nologo /std:c++17 /EHsc /O2 /W4 tests/native/make_media_fixture.cpp "/Fe:$exe" "/Fo:$obj" /link mfplat.lib mfreadwrite.lib mfuuid.lib ole32.lib *> agentdir/logs/media-fixture-build.log
    if($LASTEXITCODE -ne 0){throw 'Media fixture compiler failed: agentdir/logs/media-fixture-build.log'}
    $video=Join-Path $root 'agentdir/media/media-1080p60.mp4'
    & $exe $video *> agentdir/logs/media-fixture-1080p60.log
    if($LASTEXITCODE -ne 0){throw 'Media fixture generation failed: agentdir/logs/media-fixture-1080p60.log'}
    $output=Get-Content agentdir/logs/media-fixture-1080p60.log -Raw
    if($output -notmatch 'MEDIA_FIXTURE_PASS width=1920 height=1080 fps=60/1 frames=960 seconds=16 codec=H264'){throw 'Encoded fixture verification incomplete'}
    @{width=1920;height=1080;fps=60;frames=960;seconds=16;codec='H264';sha256=(Get-FileHash $video -Algorithm SHA256).Hash;source_sha256=(Get-FileHash tests/native/make_media_fixture.cpp -Algorithm SHA256).Hash} | ConvertTo-Json | Set-Content agentdir/media/media-1080p60.json
    Write-Output "Verified locally encoded 1080p60 fixture: $video"
}finally{
    foreach($name in $names){if ($null -eq $saved[$name]) { Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue } else { [Environment]::SetEnvironmentVariable($name,$saved[$name],'Process') }}
    Pop-Location
}
