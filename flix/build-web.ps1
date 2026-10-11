# Builds the web player helper (flix/web, Go + Microsoft Edge WebView2) into <run>\flix\flixweb.exe.
#   ./flix/build-web.ps1
# Needs Go 1.22+. At run time Windows needs the WebView2 runtime (part of Windows 11 / Edge).
$ErrorActionPreference = "Stop"

$src  = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$root = Split-Path $src -Parent
$out  = Join-Path $root "run\flix"
New-Item -ItemType Directory -Force $out | Out-Null

if (-not (Get-Command go -ErrorAction SilentlyContinue)) {
    throw "Go is not installed (https://go.dev/dl/): needed to build the web player helper."
}

Push-Location (Join-Path $PSScriptRoot "web")
try {
    $env:GOOS = "windows"; $env:GOARCH = "amd64"; $env:CGO_ENABLED = "0"
    go build -trimpath -ldflags "-s -w -H=windowsgui" -o (Join-Path $out "flixweb.exe") .
    if ($LASTEXITCODE -ne 0) { throw "go build failed" }
} finally {
    Pop-Location
}
Write-Host "built" (Join-Path $out "flixweb.exe")
