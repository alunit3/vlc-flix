# Audio A/B: plays the same stretch of one file in several audio configurations of VLCFlix, so the
# one that stops the crackling can be named. Run it from a normal PowerShell window:
#   .\flix\tests\audio_ab.ps1 -File "C:\path\movie.mp4"
# Listen for ~20 seconds per variant, answer with c (clean), b (bad) or Enter (skip). The result
# list at the end is what to send back.
param(
    [Parameter(Mandatory = $true)][string]$File,
    [int]$Start = 600,
    [string]$Exe = (Join-Path $PSScriptRoot "..\..\..\run\vlcflix.exe")
)
$ErrorActionPreference = "Stop"
$Exe = (Resolve-Path $Exe).Path

$variants = [ordered]@{
    "baseline"                  = @()
    "speex resampler"           = @("--audio-resampler=speex_resampler")
    "ugly resampler"            = @("--audio-resampler=ugly_resampler")
    "samplerate resampler"      = @("--audio-resampler=samplerate")
    "soxr resampler (default)"  = @("--audio-resampler=soxr")
    "no time stretch"           = @("--no-audio-time-stretch")
    "waveout output"            = @("--aout=waveout")
    "VLC stereo downmix (--mix-mode=1)" = @("--mix-mode=1")
    "multimedia clock (VLC 3)"  = @("--clock-source=multimedia")
    "software video decoding"   = @("--no-hw-dec")
    "all of: speex+no stretch+multimedia clock" = @("--audio-resampler=speex_resampler", "--no-audio-time-stretch", "--clock-source=multimedia")
}

$results = [ordered]@{}
foreach ($name in $variants.Keys) {
    Get-Process vlcflix -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    Write-Host ""
    Write-Host "=== $name  ($($variants[$name] -join ' '))" -ForegroundColor Cyan
    $a = @("--no-one-instance", "--no-video-title-show", "--start-time=$Start") + $variants[$name] + "`"$File`""
    $p = Start-Process $Exe -ArgumentList $a -WorkingDirectory (Split-Path $Exe) -PassThru
    Start-Sleep -Seconds 22
    $answer = Read-Host "sound: c = clean, b = bad, Enter = skip"
    $results[$name] = if ($answer -eq "c") { "clean" } elseif ($answer -eq "b") { "bad" } else { "skipped" }
    if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
}

Write-Host ""
Write-Host "Result:" -ForegroundColor Green
$results.GetEnumerator() | ForEach-Object { "{0,-45} {1}" -f $_.Key, $_.Value }
