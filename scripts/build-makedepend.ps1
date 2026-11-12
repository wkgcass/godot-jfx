[CmdletBinding()]
param([string]$Msys=$(if ($env:MSYS2_ROOT) { $env:MSYS2_ROOT } else { 'D:\msys64' }))
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$folder=Join-Path $root '.tools/makedepend'
$archive=Join-Path $folder 'source.tar.gz'
$gcc=Join-Path $Msys 'ucrt64/bin/gcc.exe'
if(!(Test-Path -LiteralPath $gcc)){throw 'Existing MSYS UCRT64 GCC is required; no system installation is performed'}
New-Item -ItemType Directory -Force $folder,(Join-Path $folder 'bin'),(Join-Path $folder 'probe') | Out-Null
if(!(Test-Path -LiteralPath $archive)){
    Invoke-WebRequest -Uri 'https://xorg.freedesktop.org/releases/individual/util/makedepend-1.0.10.tar.gz' -OutFile $archive
}
if((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne 'BAF742FB6C76C15FEBF5181E5CD814066205D8BE9AEF4ABFDC2C54B235E14917'){throw 'makedepend source checksum differs'}
& python -c 'import sys,tarfile; tarfile.open(sys.argv[1]).extractall(sys.argv[2],filter="data")' $archive $folder
if($LASTEXITCODE -ne 0){throw 'makedepend source extraction failed'}
# MinGW has rename/_fullpath, but no POSIX realpath. The upstream scanner first
# resolves existing includes; preserve its failure for missing paths as well.
$header=@'
#include <stdlib.h>
#include <sys/stat.h>
static char *godot_makedepend_realpath(const char *path, char *resolved) {
    struct stat info;
    if (stat(path, &info) != 0) return NULL;
    return _fullpath(resolved, path, 4096);
}
#define realpath godot_makedepend_realpath
'@
[IO.File]::WriteAllText((Join-Path $folder 'wincompat.h'),$header)
$savedPath=$env:PATH
try {
    $env:PATH=(Join-Path $Msys 'ucrt64/bin')+';'+(Join-Path $Msys 'usr/bin')+';'+$savedPath
    Push-Location (Join-Path $folder 'makedepend-1.0.10')
    try {
        & $gcc -O2 -DHAVE_RENAME=1 '-DINCLUDEDIR="/usr/include"' '-DOBJSUFFIX=".obj"' -include ../wincompat.h -o ../makedepend.exe include.c main.c parse.c pr.c cppsetup.c ifparser.c
        if($LASTEXITCODE -ne 0){throw 'makedepend compilation failed'}
    } finally {Pop-Location}
    $wrapper=@'
#!/usr/bin/env bash
# The native dependency scanner needs MSYS argument conversion, unlike MSVC.
export MSYS2_ARG_CONV_EXCL=
exec "$(dirname "$0")/../makedepend.exe" "$@"
'@
    [IO.File]::WriteAllText((Join-Path $folder 'bin/makedepend'),$wrapper.Replace("`r`n","`n")+"`n")
    [IO.File]::WriteAllText((Join-Path $folder 'probe/sample.c'),"#include `"nested.h`"`n")
    [IO.File]::WriteAllText((Join-Path $folder 'probe/nested.h'),"#define VALUE 1`n")
    [IO.File]::WriteAllText((Join-Path $folder 'probe/Depend.mak'),"# makedepend`n")
    Push-Location (Join-Path $folder 'probe')
    try {
        & (Join-Path $Msys 'usr/bin/bash.exe') ../bin/makedepend '-Y' '-o.obj' '-fDepend.mak' 'sample.c'
        if($LASTEXITCODE -ne 0 -or (Get-Content Depend.mak -Raw) -notmatch 'sample\.obj: nested\.h'){throw 'makedepend dependency probe failed'}
    } finally {Pop-Location}
    Write-Output "Workspace makedepend built and verified: $folder"
} finally {$env:PATH=$savedPath}
