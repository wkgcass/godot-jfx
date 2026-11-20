#Requires -Version 7.4.1
[CmdletBinding()]
param([string]$Jdk, [string]$Msys, [ValidateRange(1,32)][int]$Jobs, [string]$VisualStudio)
& "$PSScriptRoot/build-windows.ps1" -Target jfx-media @PSBoundParameters
