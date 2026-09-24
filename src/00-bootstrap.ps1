#requires -Version 5.1
# Build: 2.15.1-public
# ADKombajn - rewritten from scratch
# Author: Krzysztof Lipa-Izdebski
# Requirements: Windows PowerShell 5.1 / .NET Framework, no RSAT or ActiveDirectory module.

param(
    [ValidateSet("pl", "en")]
    [string]$Language
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.DirectoryServices
Add-Type -AssemblyName System.DirectoryServices.Protocols
Add-Type -AssemblyName System.Data
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

[System.Windows.Forms.Application]::EnableVisualStyles()
try { [System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false) } catch { }
try { [System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException) } catch { }


