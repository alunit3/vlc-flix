# Turns the cone artwork (modules/gui/qt/pixmaps/misc/cone.svg) into every icon surface:
# the Qt window/tray icons, the exe and installer icon, and the installer banner.
# Re-run this after editing the artwork.
#   ./flix/build-icons.ps1
# Needs Python with Pillow, and Chrome or Edge to rasterise the SVG.
$ErrorActionPreference = "Stop"

$script = Join-Path $PSScriptRoot "build-icons.py"
if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    throw "Python is not installed (https://www.python.org/downloads/): needed to build the icons."
}

python $script
if ($LASTEXITCODE -ne 0) { throw "icon build failed" }

$src = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
foreach ($rel in @("share\icons\16x16\vlc.png", "share\icons\32x32\vlc.png",
                    "share\icons\48x48\vlc.png", "share\icons\128x128\vlc.png",
                    "share\icons\256x256\vlc.png", "share\icons\vlc.ico",
                    "extras\package\win32\NSIS\vlc_branding.bmp")) {
    $p = Join-Path $src $rel
    if (Test-Path $p) {
        Write-Host ("  {0,10:N0} bytes  {1}" -f (Get-Item $p).Length, $rel)
    } else {
        Write-Warning "not written: $rel"
    }
}
Write-Host ""
Write-Host "Rebuild before looking for a change: neither build system notices icon files on its own."