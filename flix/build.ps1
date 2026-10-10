# Build VLC (Windows x64) inside the official VideoLAN container, using prebuilt contribs.
#   ./flix/build.ps1            full build (first run) / incremental build (later runs)
#   ./flix/build.ps1 -Package   also package a runnable tree into D:\vlc-fork\run
# D:\vlc-fork\run\portable keeps the fork's settings/media-library out of %APPDATA%\vlc (VLC portable mode).
# Source is bind-mounted from D:; the build dir lives in the named volume "vlcbuild" (fast I/O).
param([switch]$Package, [int]$Jobs = 6)
$ErrorActionPreference = "Stop"

$image = "registry.videolan.org/vlc-debian-win64-posix:20260611225331"
$src   = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$run   = Join-Path (Split-Path $src -Parent) "run"
New-Item -ItemType Directory -Force $run | Out-Null

$pkg = if ($Package) { "cd /build/win64 && make package-win-common && find /out -mindepth 1 -maxdepth 1 ! -name portable -exec rm -rf {} + && cp -r vlc-*/. /out/" } else { "true" }

$script = @"
set -e
git config --global --add safe.directory /vlc
mkdir -p /build && cd /build
export JOBS=$Jobs
export VLC_CONTRIB_SHA=`$(cd /vlc && extras/ci/get-contrib-sha.sh win32)
export VLC_PREBUILT_CONTRIBS_URL=https://artifacts.videolan.org/vlc/win64/vlc-contrib-x86_64-w64-mingw32-`$VLC_CONTRIB_SHA.tar.zst
echo "contribs: `$VLC_PREBUILT_CONTRIBS_URL"
/vlc/extras/package/win32/build.sh -a x86_64 -p
$pkg
"@ -replace "`r", ""

docker run --rm -v "${src}:/vlc" -v "vlcbuild:/build" -v "${run}:/out" $image bash -c $script
if ($LASTEXITCODE) { throw "build failed ($LASTEXITCODE)" }
