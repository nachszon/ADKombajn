param(
    [string]$Version = "2.15.1.0",
    [string]$InputFile = ".\ADKombajn.ps1",
    [string]$IconFile = ".\kombajn.ico",
    [string]$OutputDirectory = ".",
    [switch]$AssembleOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-ReleaseVersion {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version
    )

    $v = [System.Version]$Version

    if ($v.Revision -eq 0) {
        return "{0}.{1}.{2}" -f $v.Major, $v.Minor, $v.Build
    }

    return $Version
}

function Test-Utf8Bom {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "File not found: $Path"
    }

    $fullPath = (Resolve-Path -LiteralPath $Path).Path
    $bytes = [System.IO.File]::ReadAllBytes($fullPath)

    if ($bytes.Length -lt 3) {
        return $false
    }

    return (
        $bytes[0] -eq 0xEF -and
        $bytes[1] -eq 0xBB -and
        $bytes[2] -eq 0xBF
    )
}

function Show-BomInfo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $fullPath = (Resolve-Path -LiteralPath $Path).Path
    $bytes = [System.IO.File]::ReadAllBytes($fullPath)

    if ($bytes.Length -ge 3) {
        Write-Host ("BOM bytes: {0:X2} {1:X2} {2:X2}" -f $bytes[0], $bytes[1], $bytes[2])
    }
    else {
        Write-Host "BOM bytes: file is shorter than 3 bytes"
    }
}

function Join-ApplicationSource {
    param([string]$Root, [string]$Destination)

    $manifest = Join-Path $Root "src\order.txt"
    if (-not (Test-Path -LiteralPath $manifest)) { throw "Source manifest not found: $manifest" }
    $parts = @(Get-Content -LiteralPath $manifest | Where-Object { $_.Trim() -ne "" })
    if ($parts.Count -eq 0) { throw "Source manifest is empty: $manifest" }

    $builder = New-Object System.Text.StringBuilder
    $strictUtf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false, $true
    foreach ($part in $parts) {
        if ($part -notmatch '^[0-9]{2}-[a-z-]+\.ps1$') { throw "Invalid source entry: $part" }
        $source = Join-Path (Join-Path $Root "src") $part
        if (-not (Test-Path -LiteralPath $source)) { throw "Source file not found: $source" }
        $bytes = [System.IO.File]::ReadAllBytes($source)
        if ($bytes.Length -lt 3 -or $bytes[0] -ne 0xEF -or $bytes[1] -ne 0xBB -or $bytes[2] -ne 0xBF) {
            throw "Source must use UTF-8 with BOM: $source"
        }
        [void]$builder.Append($strictUtf8.GetString($bytes, 3, $bytes.Length - 3))
    }
    $target = [System.IO.Path]::GetFullPath($Destination)
    $directory = [System.IO.Path]::GetDirectoryName($target)
    if (-not (Test-Path -LiteralPath $directory)) { [void][System.IO.Directory]::CreateDirectory($directory) }
    $encoding = New-Object System.Text.UTF8Encoding -ArgumentList $true
    [System.IO.File]::WriteAllText($target, $builder.ToString(), $encoding)
    Write-Host "Standalone script ready: $target" -ForegroundColor Green
}

$projectRoot = $PSScriptRoot
if ($InputFile -eq ".\ADKombajn.ps1") { $InputFile = Join-Path $projectRoot "ADKombajn.ps1" }
Join-ApplicationSource -Root $projectRoot -Destination $InputFile
if ($AssembleOnly) { return }

$ReleaseVersion = Get-ReleaseVersion -Version $Version

if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}

$OutputFile = Join-Path $OutputDirectory ("ADKombajn-{0}-win-x64.exe" -f $ReleaseVersion)

Write-Host "ADKombajn build"
Write-Host "Version:         $Version"
Write-Host "Release version: $ReleaseVersion"
Write-Host "Input:           $InputFile"
Write-Host "Output:          $OutputFile"
Write-Host ""

if (-not (Test-Path -LiteralPath $InputFile)) {
    throw "Input script not found: $InputFile"
}

if (-not (Test-Utf8Bom -Path $InputFile)) {
    Write-Host ""
    Write-Host "ERROR: ADKombajn.ps1 must be saved as UTF-8 with BOM." -ForegroundColor Red
    Write-Host ""
    Show-BomInfo -Path $InputFile
    Write-Host ""
    Write-Host "Windows PowerShell 5.1 / PS2EXE may throw misleading parser errors when the file is UTF-8 without BOM." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "To convert the file to UTF-8 with BOM, run:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host '$path = ".\ADKombajn.ps1"'
    Write-Host '$fullPath = (Resolve-Path -LiteralPath $path).Path'
    Write-Host '$text = [System.IO.File]::ReadAllText($fullPath)'
    Write-Host '$utf8Bom = New-Object System.Text.UTF8Encoding -ArgumentList $true'
    Write-Host '[System.IO.File]::WriteAllText($fullPath, $text, $utf8Bom)'
    Write-Host ""

    throw "Build stopped because the input script is not UTF-8 with BOM."
}

Write-Host "Encoding check: OK - UTF-8 with BOM detected." -ForegroundColor Green

if (-not (Get-Command Invoke-PS2EXE -ErrorAction SilentlyContinue)) {
    throw "Invoke-PS2EXE was not found. Import PS2EXE first or install the module."
}

$ps2exeArgs = @{
    InputFile   = $InputFile
    OutputFile  = $OutputFile
    NoConsole   = $true
    x64         = $true
    Title       = "ADKombajn"
    Description = "Active Directory support helper"
    Product     = "ADKombajn"
    Company     = "Krzysztof Lipa-Izdebski"
    Copyright   = "Copyright (c) 2026 Krzysztof Lipa-Izdebski"
    Version     = $Version
}

if (Test-Path -LiteralPath $IconFile) {
    $ps2exeArgs.IconFile = $IconFile
}
else {
    Write-Host "Icon not found: $IconFile" -ForegroundColor Yellow
    Write-Host "Build will continue without a custom icon." -ForegroundColor Yellow
}

if (Test-Path -LiteralPath $OutputFile) {
    Remove-Item -LiteralPath $OutputFile -Force
}

Invoke-PS2EXE @ps2exeArgs

Write-Host ""
Write-Host "Release asset ready: $OutputFile" -ForegroundColor Green
