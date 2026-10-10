# Fast edit loop: incremental rebuild, then replace ONLY the Qt plugin in D:\vlc-fork\run.
# (The build is unstripped; the Qt plugin is ~1.3 GB, so we strip it while copying out.)
#   ./flix/dev.ps1            rebuild + install plugin
#   ./flix/dev.ps1 -Launch    ...and start VLC in portable mode (-I qt)
param([switch]$Launch, [int]$Jobs = 2, [string]$Media = "")
$ErrorActionPreference = "Stop"

$image = "registry.videolan.org/vlc-debian-win64-posix:20260611225331"
$src   = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$root  = Split-Path $src -Parent
$run   = Join-Path $root "run"

$script = @"
set -e
git config --global --add safe.directory /vlc
cd /build/win64
make -j$Jobs
make -C modules/gui/qt install-pluginLTLIBRARIES >/dev/null 2>&1 || make install >/dev/null
P=`$(find _win32/lib/vlc/plugins/gui -name libqt_plugin.dll | head -1)
echo "plugin: `$P"
x86_64-w64-mingw32-strip --strip-unneeded -o /out/plugins/gui/libqt_plugin.dll "`$P"
ls -la /out/plugins/gui/libqt_plugin.dll
"@ -replace "`r", ""

docker run --rm -v "${src}:/vlc" -v "vlcbuild:/build" -v "${run}:/out" $image bash -c $script
if ($LASTEXITCODE) { throw "dev build failed ($LASTEXITCODE)" }

if ($Launch) {
    New-Item -ItemType Directory -Force (Join-Path $run "portable") | Out-Null
    $a = @("-I", "qt", "--no-one-instance", "--no-qt-privacy-ask", "--no-qt-updates-notif", "--no-media-library")
    if ($Media) { $a += "`"$Media`"" }
    Start-Process (Join-Path $run "vlc.exe") -ArgumentList $a -WorkingDirectory $run
}
