[CmdletBinding()]
param([string]$Jdk = 'D:\jdk-25.0.3+9',
    [ValidateSet('mobile','gl_compatibility')][string]$Renderer='mobile',
    [switch]$Runtime)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$savedJdk = $env:GODOT_JFX_JDK
$savedSync = $env:GODOT_JFX_CLIPBOARD_SYNC
$syncPath = Join-Path $root ('artifacts/native-tests/clipboard-' + [Guid]::NewGuid().ToString('N') + '.ready')
$backupPath = $syncPath + '.backup.clixml'
$exchangePending = $false
$clipRunspace = [runspacefactory]::CreateRunspace()
$clipRunspace.ApartmentState = 'STA'
$clipRunspace.ThreadOptions = 'ReuseThread'
$clipRunspace.Open()
$clipShell = [powershell]::Create()
$clipShell.Runspace = $clipRunspace
$snapshotReady = $false
Push-Location $root
try {
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED -encoding UTF-8 -d artifacts/reference tests/reference/ClipboardProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'Clipboard probe compilation failed' }
    # Materialize all advertised data before the test changes global state.
    # Unknown registered/private metadata is refused before any test writes.
    [void]$clipShell.AddScript({
        param($snapshotSource,$backupPath)
        $ErrorActionPreference = 'Stop'
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -Path $snapshotSource
        $global:clipboardSnapshot = [ClipboardSnapshot]::Capture()
        $global:clipboardExpectedSequence = [ClipboardSnapshot]::CapturedSequence
        $global:clipboardBackupPath = $backupPath
        New-Item -ItemType Directory -Force (Split-Path $backupPath -Parent) | Out-Null
        [pscustomobject]@{
            Version=1
            Formats=$global:clipboardSnapshot
            RegisteredNames=[ClipboardSnapshot]::RegisteredFormatNames()
        } | Export-Clixml -LiteralPath $backupPath -Depth 8
        $global:clipboardOwner = [System.Windows.Forms.Control]::new()
        [void]$global:clipboardOwner.Handle
    }).AddArgument((Join-Path $root 'tests/reference/ClipboardSnapshot.cs')).AddArgument($backupPath)
    [void]$clipShell.Invoke()
    if ($clipShell.HadErrors) { throw "Clipboard backup failed; test did not run: $($clipShell.Streams.Error)" }
    $snapshotReady = $true
    $env:GODOT_JFX_JDK = $Jdk
    New-Item -ItemType Directory -Force (Split-Path $syncPath -Parent) | Out-Null
    $env:GODOT_JFX_CLIPBOARD_SYNC = $syncPath
    $clipShell.Commands.Clear(); $clipShell.Streams.Error.Clear()
    [void]$clipShell.AddScript({
        param($readyPath)
        $ErrorActionPreference='Stop'
        $deadline=[DateTime]::UtcNow.AddSeconds(35)
        while(!(Test-Path -LiteralPath $readyPath)) {
            if([DateTime]::UtcNow -gt $deadline){throw 'Clipboard Java publication timeout'}
            Start-Sleep -Milliseconds 20
        }
        $data=$null
        for($i=0;$i -lt 100 -and $null -eq $data;$i++) {
            $data=[System.Windows.Forms.Clipboard]::GetDataObject()
            if($null -eq $data){Start-Sleep -Milliseconds 20}
        }
        if($null -eq $data){throw 'Clipboard data object unavailable'}
        if(!$data.GetDataPresent('HTML Format',$false) -or !$data.GetDataPresent('Rich Text Format',$false)){throw 'Missing native rich clipboard formats'}
        $html=$data.GetData('HTML Format',$false)
        if($html -is [System.IO.MemoryStream]){$bytes=$html.ToArray()}
        elseif($html -is [string]){$bytes=[Text.Encoding]::UTF8.GetBytes($html)}
        else{throw "Unexpected HTML clipboard representation: $($html.GetType().FullName)"}
        $header=[Text.Encoding]::UTF8.GetString($bytes)
        $start=[int]([regex]::Match($header,'StartFragment:(\d+)').Groups[1].Value)
        $end=[int]([regex]::Match($header,'EndFragment:(\d+)').Groups[1].Value)
        if($start -lt 1 -or $end -lt $start -or $end -gt $bytes.Length){throw 'Invalid CF_HTML fragment byte offsets'}
        if([Text.Encoding]::UTF8.GetString($bytes,$start,$end-$start) -cne '<b>Godot 中文 🙂</b>'){throw 'Native CF_HTML Unicode fragment differs'}
        if([System.Windows.Forms.Clipboard]::GetText([System.Windows.Forms.TextDataFormat]::Rtf) -cne '{\rtf1\ansi Godot \b rich\b0}'){throw 'Native RTF differs'}
        $url=$data.GetData('UniformResourceLocatorW',$false)
        if($url -is [IO.MemoryStream]){$url=[Text.Encoding]::Unicode.GetString($url.ToArray()).TrimEnd([char]0)}
        if($url -cne 'https://example.invalid/中文?q=🙂'){throw "Native URL Unicode value differs: [$url] ($($url.GetType().FullName))"}
        $hdrop=[ClipboardSnapshot]::ReadFormat(15)
        if($null -eq $hdrop -or $hdrop.Length -lt 22){throw 'Missing native CF_HDROP'}
        if([BitConverter]::ToUInt32($hdrop,0) -ne 20 -or [BitConverter]::ToInt32($hdrop,16) -ne 1){throw 'CF_HDROP header differs'}
        $hdPaths=[Text.Encoding]::Unicode.GetString($hdrop,20,$hdrop.Length-20).TrimEnd([char]0) -split "`0"
        if($hdPaths.Count -ne 2 -or $hdPaths[0] -cne 'C:\godot-jfx测试\报告 🙂.txt' -or $hdPaths[1] -cne 'D:\wsl-workspace\opensource\godot-jfx\README.md'){throw 'CF_HDROP paths differ'}
        $dib=[ClipboardSnapshot]::ReadFormat(8)
        if($null -eq $dib -or $dib.Length -ne 64){throw 'Missing native CF_DIB'}
        if([BitConverter]::ToUInt32($dib,0) -ne 40 -or [BitConverter]::ToInt32($dib,4) -ne 3 -or [BitConverter]::ToInt32($dib,8) -ne 2 -or [BitConverter]::ToUInt16($dib,12) -ne 1 -or [BitConverter]::ToUInt16($dib,14) -ne 32 -or [BitConverter]::ToUInt32($dib,16) -ne 0){throw 'CF_DIB header differs'}
        $dibExpected=[byte[]](120,110,100,255,150,140,130,255,0,0,0,0,30,20,10,255,60,50,40,255,90,80,70,255)
        for($i=0;$i -lt 24;$i++){if($dib[40+$i] -ne $dibExpected[$i]){throw 'CF_DIB pixels differ'}}
        $customBytes=[ClipboardSnapshot]::ReadFormat([ClipboardSnapshot]::RegisterFormat('application/x-godot-custom-token'))
        if($null -eq $customBytes){throw 'Missing custom clipboard format'}
        $customText=[Text.Encoding]::UTF8.GetString($customBytes).TrimEnd([char]0)
        if($customText -cne '剪贴板自定义负载 🙂'){throw 'Custom clipboard payload differs'}
        # Independently construct CF_HTML offsets to verify reads from another API.
        $prefix='<html><body><!--StartFragment-->'
        $fragment='<i>External 中文 🙂</i>'
        $suffix='<!--EndFragment--></body></html>'
        $format="Version:1.0`r`nStartHTML:{0:D10}`r`nEndHTML:{1:D10}`r`nStartFragment:{2:D10}`r`nEndFragment:{3:D10}`r`n"
        $startHtml=[Text.Encoding]::UTF8.GetByteCount(($format -f 0,0,0,0))
        $startFragment=$startHtml+[Text.Encoding]::UTF8.GetByteCount($prefix)
        $endFragment=$startFragment+[Text.Encoding]::UTF8.GetByteCount($fragment)
        $endHtml=$endFragment+[Text.Encoding]::UTF8.GetByteCount($suffix)
        $external=[System.Windows.Forms.DataObject]::new()
        $external.SetData('UniformResourceLocatorW',$false,[IO.MemoryStream]::new([Text.Encoding]::Unicode.GetBytes("https://external.invalid/目录#🙂`0")))
        $external.SetData('UnicodeText',$false,'Godot external 中文 🙂')
        $external.SetData('HTML Format',$false,($format -f $startHtml,$endHtml,$startFragment,$endFragment)+$prefix+$fragment+$suffix)
        $external.SetData('Rich Text Format',$false,'{\rtf1\ansi External \i rich\i0}')
        [System.Windows.Forms.Clipboard]::SetDataObject($external,$true,10,100)
        [IO.File]::WriteAllText($readyPath+'.external','ready')
        $ackDeadline=[DateTime]::UtcNow.AddSeconds(35)
        while(!(Test-Path -LiteralPath ($readyPath+'.ack'))) {
            if([DateTime]::UtcNow -gt $ackDeadline){throw 'Clipboard Java acknowledgement timeout'}
            Start-Sleep -Milliseconds 20
        }
        # Second exchange: CF_HDROP + 24bpp CF_DIB + ANSI-only URL, no text format.
        $extPaths=@("D:\外部\文件 甲.txt","C:\外部\乙🙂.png")
        $hdText=(($extPaths | ForEach-Object { $_+"`0" }) -join '')+"`0"
        $hdBytes=[Text.Encoding]::Unicode.GetBytes($hdText)
        $hd=[byte[]]::new(20+$hdBytes.Length)
        [BitConverter]::GetBytes([uint32]20).CopyTo($hd,0)
        [BitConverter]::GetBytes([int32]1).CopyTo($hd,16)
        $hdBytes.CopyTo($hd,20)
        $dib24=[byte[]]::new(56)
        [BitConverter]::GetBytes([uint32]40).CopyTo($dib24,0)
        [BitConverter]::GetBytes([int32]2).CopyTo($dib24,4)
        [BitConverter]::GetBytes([int32]2).CopyTo($dib24,8)
        [BitConverter]::GetBytes([uint16]1).CopyTo($dib24,12)
        [BitConverter]::GetBytes([uint16]24).CopyTo($dib24,14)
        [BitConverter]::GetBytes([uint32]16).CopyTo($dib24,20)
        ([byte[]](255,0,0,255,255,255,0,0,0,0,255,0,255,0,0,0)).CopyTo($dib24,40)
        $blocks=New-Object 'System.Collections.Generic.Dictionary[uint32,byte[]]'
        $blocks[[uint32]15]=$hd
        $blocks[[uint32]8]=$dib24
        $blocks[[ClipboardSnapshot]::RegisterFormat('UniformResourceLocator')]=[ClipboardSnapshot]::AnsiBytes("https://ansi.invalid/中文路径`0")
        $blocks[[ClipboardSnapshot]::RegisterFormat('application/x-godot-custom-token')]=[Text.Encoding]::UTF8.GetBytes("外部剪贴板负载 🙂`0")
        $global:clipboardExpectedSequence = [ClipboardSnapshot]::WriteRaw($blocks,$global:clipboardOwner.Handle)
        [IO.File]::WriteAllText($readyPath+'.external2','ready')
        'CLIPBOARD_EXTERNAL_RICH_PASS'
    }).AddArgument($syncPath)
    $exchange=$clipShell.BeginInvoke(); $exchangePending=$true
    $suffix=if($Runtime){'-runtime'}else{''}
    $log = Join-Path $root "artifacts/logs/clipboard-$Renderer$suffix.log"
    if($Runtime){
        $fixture=Join-Path $root 'artifacts/runtime-clipboard'
        New-Item -ItemType Directory -Force $fixture | Out-Null
        Copy-Item -LiteralPath (Join-Path $root 'godot/bin/godot.windows.template_release.x86_64.console.exe'),(Join-Path $root 'godot/bin/godot.windows.template_release.x86_64.exe'),(Join-Path $root 'tests/godot/clipboard_test.gd'),(Join-Path $root 'tests/godot/clipboard.tscn') -Destination $fixture -Force
        $project=[IO.File]::ReadAllText((Join-Path $root 'tests/godot/project.godot')).Replace('res://main.tscn','res://clipboard.tscn')
        [IO.File]::WriteAllText((Join-Path $fixture 'project.godot'),$project)
        & ./godot/bin/godot.windows.editor.x86_64.console.exe --headless --path $fixture --editor --import *> "$log.import"
        if($LASTEXITCODE -ne 0){throw "Clipboard runtime import failed: $log.import"}
        Push-Location $fixture
        try { & (Join-Path $fixture 'godot.windows.template_release.x86_64.console.exe') --rendering-method $Renderer --render-thread safe --quit-after 3000 *> $log }
        finally { Pop-Location }
    }else{
        & .\godot\bin\godot.windows.editor.x86_64.console.exe --path tests/godot res://clipboard.tscn --rendering-method $Renderer --render-thread safe --quit-after 3000 *> $log
    }
    $result = $LASTEXITCODE
    try { $exchangeOutput=$clipShell.EndInvoke($exchange) } finally { $exchangePending=$false }
    if($clipShell.HadErrors -or $exchangeOutput -notcontains 'CLIPBOARD_EXTERNAL_RICH_PASS'){throw "External clipboard validation failed: $($clipShell.Streams.Error)"}
    $output = Get-Content $log -Raw
    if ($result -ne 0 -or $output -notmatch 'GODOT_CLIPBOARD_PASS' -or $output -notmatch 'CLIPBOARD_PROBE_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|Exception|java\.[a-z].*Exception)') { throw "Clipboard probe failed: $log" }
    $probePassed = $true
} catch {
    Write-Output "Clipboard test failure before restoration: $_"
    throw
} finally {
    try {
        if($exchangePending){$clipShell.Stop();$exchangePending=$false}
        if ($snapshotReady) {
            $clipShell.Commands.Clear(); $clipShell.Streams.Error.Clear()
            [void]$clipShell.AddScript({
                try {
                    [ClipboardSnapshot]::Restore($global:clipboardSnapshot,$global:clipboardOwner.Handle,$global:clipboardExpectedSequence)
                    Remove-Item -LiteralPath $global:clipboardBackupPath
                } finally { $global:clipboardOwner.Dispose() }
            })
            try { [void]$clipShell.Invoke() }
            catch { throw "Clipboard restoration failed; original backup retained at $backupPath : $($_.Exception.Message)" }
            if ($clipShell.HadErrors) { throw "Clipboard restoration failed; original backup retained at $backupPath : $($clipShell.Streams.Error)" }
        }
    } finally {
        $clipShell.Dispose(); $clipRunspace.Dispose()
        $env:GODOT_JFX_JDK = $savedJdk; $env:GODOT_JFX_CLIPBOARD_SYNC=$savedSync
        if(Test-Path -LiteralPath $syncPath){Remove-Item -LiteralPath $syncPath}
        if(Test-Path -LiteralPath ($syncPath+'.external')){Remove-Item -LiteralPath ($syncPath+'.external')}
        if(Test-Path -LiteralPath ($syncPath+'.external2')){Remove-Item -LiteralPath ($syncPath+'.external2')}
        if(Test-Path -LiteralPath ($syncPath+'.ack')){Remove-Item -LiteralPath ($syncPath+'.ack')}
        Pop-Location
    }
}

if($probePassed){ Write-Output "Clipboard probe and exact restoration passed: $log" }
