[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
Add-Type -Path (Join-Path $root 'tests/reference/ClipboardSnapshot.cs')
foreach($name in @('HTML Format','Rich Text Format','UniformResourceLocator','UniformResourceLocatorW','application/x-godot-custom-probe')) {
    if(![ClipboardSnapshot]::IsPortableRegisteredFormat($name)){throw "Portable format refused: $name"}
}
foreach($name in @('Ole Private Data','DataObject','My application pointers','html format','', $null)) {
    if([ClipboardSnapshot]::IsPortableRegisteredFormat($name)){throw "Unverified format accepted: $name"}
}
$blocks=[Collections.Generic.Dictionary[uint32,byte[]]]::new()
$rejected=$false
try { [ClipboardSnapshot]::WriteRaw($blocks,[IntPtr]::Zero) }
catch {
    if($_.Exception.InnerException -isnot [ArgumentException]){throw}
    $rejected=$true
}
if(!$rejected){throw 'Missing owner was accepted'}
[ClipboardSnapshot]::RequireUnchanged(42,42)
foreach($pair in @(@(42,43),@(0,0),@(42,0),@(0,42))) {
    $rejected=$false
    try { [ClipboardSnapshot]::RequireUnchanged([uint32]$pair[0],[uint32]$pair[1]) }
    catch {
        if($_.Exception.InnerException -isnot [InvalidOperationException]){throw}
        $rejected=$true
    }
    if(!$rejected){throw 'Changed or unavailable clipboard sequence accepted'}
}
$limit=[ClipboardSnapshot]::MaxSnapshotBytes
if ([ClipboardSnapshot]::AddSnapshotBytes(0,1) -ne 1) { throw 'Small snapshot accounting differs' }
if ([ClipboardSnapshot]::AddSnapshotBytes($limit-1,1) -ne $limit) { throw 'Exact snapshot budget refused' }
foreach($pair in @(@(0,0),@($limit,1),@(($limit-1),2),@([uint64]::MaxValue,1),@(0,[uint64]::MaxValue))) {
    $rejected=$false
    try { [ClipboardSnapshot]::AddSnapshotBytes([uint64]$pair[0],[uint64]$pair[1]) | Out-Null }
    catch {
        if($_.Exception.InnerException -isnot [InvalidOperationException]){throw}
        $rejected=$true
    }
    if(!$rejected){throw 'Invalid aggregate clipboard size accepted'}
}
# A nonzero dummy owner is safe here: invalid input must fail before any Win32 call.
$blocks=[Collections.Generic.Dictionary[uint32,byte[]]]::new()
$blocks.Add(13,[byte[]]::new(0))
foreach($operation in @('write','restore')) {
    $rejected=$false
    try {
        if($operation -eq 'write'){[ClipboardSnapshot]::WriteRaw($blocks,[IntPtr]1) | Out-Null}
        else {[ClipboardSnapshot]::Restore($blocks,[IntPtr]1,42)}
    } catch {
        if($_.Exception.InnerException -isnot [InvalidOperationException]){throw}
        $rejected=$true
    }
    if(!$rejected){throw "Empty block reached clipboard $operation"}
}
# Native allocation ownership only: no user32/clipboard API is called.
Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class SnapshotMemoryFault {
    public static void CheckEnumeration(System.Reflection.MethodInfo method) {
        Func<int> success=()=>0;
        Func<uint,uint> empty=previous=>0;
        var result=(List<uint>)method.Invoke(null,new object[]{empty,success});
        if(result.Count!=0) throw new Exception("Empty enumeration differs");
        Func<uint,uint> complete=previous=>previous==0 ? 13u : previous==13 ? 8u : 0u;
        result=(List<uint>)method.Invoke(null,new object[]{complete,success});
        if(result.Count!=2 || result[0]!=13 || result[1]!=8) throw new Exception("Enumeration order differs");
        foreach(bool partial in new[]{false,true}) {
            Func<uint,uint> failed=previous=>partial && previous==0 ? 13u : 0u;
            try {
                method.Invoke(null,new object[]{failed,(Func<int>)(()=>5)});
                throw new Exception("Failed enumeration accepted as a backup");
            } catch(System.Reflection.TargetInvocationException error) {
                if(!(error.InnerException is InvalidOperationException) || !error.InnerException.Message.Contains("Windows error 5")) throw;
            }
        }
    }
    [DllImport("kernel32.dll")] public static extern IntPtr GlobalAlloc(uint flags, UIntPtr bytes);
    [DllImport("kernel32.dll")] public static extern UIntPtr GlobalSize(IntPtr handle);
    [DllImport("kernel32.dll")] public static extern IntPtr GlobalFree(IntPtr handle);
    sealed class FailHash : IEqualityComparer<uint> {
        public bool Equals(uint a,uint b) { return a==b; }
        public int GetHashCode(uint value) { throw new InvalidOperationException("injected tracking failure"); }
    }
    public static Dictionary<uint,IntPtr> FailingDictionary() { return new Dictionary<uint,IntPtr>(1,new FailHash()); }
}
"@
$enumerator=[ClipboardSnapshot].GetMethod('EnumerateFormats',[Reflection.BindingFlags]'NonPublic,Static')
[SnapshotMemoryFault]::CheckEnumeration($enumerator)
$nativeEnumerator=[ClipboardSnapshot].GetMethod('EnumClipboardFormats',[Reflection.BindingFlags]'NonPublic,Static')
$pinvoke=[Attribute]::GetCustomAttribute($nativeEnumerator,[Runtime.InteropServices.DllImportAttribute])
if(!$pinvoke.SetLastError){throw 'Native enumeration does not preserve its error code'}
Write-Output 'CLIPBOARD_SNAPSHOT_ENUMERATION_FAILURE_PASS (no clipboard access)'
$handle=[SnapshotMemoryFault]::GlobalAlloc(0x42,[UIntPtr]::new([uint32]4096))
if($handle -eq [IntPtr]::Zero){throw 'Native memory fault fixture allocation failed'}
try {
    $method=[ClipboardSnapshot].GetMethod('TrackBlock',[Reflection.BindingFlags]'NonPublic,Static')
    $rejected=$false
    try { $method.Invoke($null,@([SnapshotMemoryFault]::FailingDictionary(),[uint32]13,$handle)) | Out-Null }
    catch {
        if($_.Exception.ToString() -notmatch 'injected tracking failure'){throw}
        $rejected=$true
    }
    if(!$rejected -or [SnapshotMemoryFault]::GlobalSize($handle).ToUInt64() -ne 0){throw 'Untracked native block was not released'}
} finally {
    if([SnapshotMemoryFault]::GlobalSize($handle).ToUInt64() -ne 0){[SnapshotMemoryFault]::GlobalFree($handle) | Out-Null}
}
Write-Output 'CLIPBOARD_SNAPSHOT_ALLOCATION_FAILURE_PASS (no clipboard access)'
Write-Output 'CLIPBOARD_SNAPSHOT_BUDGET_PASS (no clipboard access)'
Write-Output 'CLIPBOARD_SNAPSHOT_GUARD_PASS (no clipboard access)'
