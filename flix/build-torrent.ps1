# Builds the torrent helper (flix/torrent, Go) into <run>\flix\flixtorrent.exe.
#   ./flix/build-torrent.ps1 [-Out <run tree>\flix]
# Needs Go 1.24+. The helper is a separate small program: the player starts it to look up torrent
# sources for a title and to stream the chosen torrent over http://127.0.0.1. It has to be in
# flix\ next to vlcflix.exe; dev.ps1 passes -Out for its -RunDir.
param([string]$Out = "")
$ErrorActionPreference = "Stop"

$src  = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$root = Split-Path $src -Parent
$out  = if ($Out) { $Out } else { Join-Path $root "run\flix" }
New-Item -ItemType Directory -Force $out | Out-Null

if (-not (Get-Command go -ErrorAction SilentlyContinue)) {
    throw "Go is not installed (https://go.dev/dl/): needed to build the torrent helper."
}

Push-Location (Join-Path $PSScriptRoot "torrent")
try {
    $env:GOOS = "windows"; $env:GOARCH = "amd64"; $env:CGO_ENABLED = "0"
    go build -trimpath -ldflags "-s -w" -o (Join-Path $out "flixtorrent.exe") .
    if ($LASTEXITCODE -ne 0) { throw "go build failed" }
} finally {
    Pop-Location
}
Write-Host "built" (Join-Path $out "flixtorrent.exe")
