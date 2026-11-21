#Requires -Version 7.4.1
[CmdletBinding()]
param([string]$Jdk=$env:JAVA_HOME,[ValidateSet('d3d12','vulkan','opengl')][string]$Driver = 'd3d12',[ValidateSet('safe')][string]$RenderThread='safe')
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference='Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
$saved=@{}
try {
    foreach($key in @('GODOT_JFX_JDK','GODOT_JFX_STARTUP','GODOT_JFX_STARTUP_CANCEL')) { $saved[$key]=[Environment]::GetEnvironmentVariable($key,'Process') }
    $env:GODOT_JFX_JDK=$Jdk
    New-Item -ItemType Directory -Force artifacts/reference,agentdir/logs | Out-Null
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls -d artifacts/reference tests/reference/StartupProbe.java
    if($LASTEXITCODE -ne 0){throw 'Startup probe compilation failed'}
    if(-not ('StartupWindows' -as [type])) {
        Add-Type @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class StartupWindows {
    delegate bool Callback(IntPtr hwnd, IntPtr param);
    [DllImport("user32.dll")] static extern bool EnumWindows(Callback cb, IntPtr param);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr hwnd, StringBuilder text, int size);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr hwnd, StringBuilder text, int size);
    public static string[] VisibleTitles(int processId) {
        var titles = new List<string>();
        EnumWindows((hwnd, param) => {
            uint pid; GetWindowThreadProcessId(hwnd, out pid);
            if(pid == processId && IsWindowVisible(hwnd)) {
                var text = new StringBuilder(512); GetWindowText(hwnd, text, text.Capacity);
                var cls = new StringBuilder(512); GetClassName(hwnd, cls, cls.Capacity);
                if(cls.ToString() == "Engine") titles.Add(text.ToString());
                else Console.WriteLine("Startup auxiliary window class=" + cls + " title=" + text);
            }
            return true;
        }, IntPtr.Zero);
        return titles.ToArray();
    }
}
"@
    }
    foreach($case in @('logo','hidden','logo-cancel','hidden-cancel')) {
        $mode=$case.Split('-')[0]
        $env:GODOT_JFX_STARTUP_CANCEL=$(if($case.EndsWith('-cancel')){'1'}else{'0'})
        $env:GODOT_JFX_STARTUP=$mode
        $prefix="agentdir/logs/startup-$case-$Driver-$RenderThread"
        $process=Start-GodotFixture -Driver $Driver -WorkingDirectory (Get-Location).Path -ArgumentList @('--path','tests/godot','res://startup.tscn','--render-thread',$RenderThread) -Log "$prefix.log" -ErrorLog "$prefix.err.log"
        $watch=[Diagnostics.Stopwatch]::StartNew()
        $visible=$false
        try {
            while(-not $process.HasExited) {
                foreach($title in [StartupWindows]::VisibleTitles($process.Id)) {
                    $visible=$true
                    if($title -notmatch '^Startup(Probe|Secondary)( \(DEBUG\))?$'){throw "Unexpected startup window at $($watch.ElapsedMilliseconds) ms: $title"}
                    if($watch.ElapsedMilliseconds -lt 1200){throw 'Window visible before application show'}
                }
                if($watch.Elapsed.TotalSeconds -gt 30){throw 'Startup test timed out'}
                Start-Sleep -Milliseconds 20
            }
            $process.WaitForExit()
            $output=(Get-Content "$prefix.log" -Raw)+(Get-Content "$prefix.err.log" -Raw)
            if($process.ExitCode -ne 0 -or -not $visible -or $output -notmatch "STARTUP_PASS mode=$mode" -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|Exception)'){throw "Startup test failed: $prefix.log"}
            Write-Output "STARTUP_PASS $case $Driver $RenderThread (native visibility sampled every 20 ms)"
        } finally {
            if(-not $process.HasExited){Stop-Process -Id $process.Id -Force}
            $process.Dispose()
        }
    }
} finally {
    foreach($key in $saved.Keys){[Environment]::SetEnvironmentVariable($key,$saved[$key],'Process')}
    Pop-Location
}
