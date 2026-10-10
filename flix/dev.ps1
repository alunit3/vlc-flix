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

# Close any previous instance from the run tree (a stale window would otherwise be mistaken
# for the new build, and it keeps the old plugin DLL open).
Get-Process vlc -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } |
    ForEach-Object { $_.CloseMainWindow() | Out-Null }
Start-Sleep -Seconds 3
Get-Process vlc -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } |
    Stop-Process -Force -ErrorAction SilentlyContinue

$script = @"
set -e
git config --global --add safe.directory /vlc
cd /build/win64
make -j$Jobs
make -C modules/gui/qt install-pluginLTLIBRARIES >/dev/null 2>&1 || make install >/dev/null
P=`$(find _win32/lib/vlc/plugins/gui -name libqt_plugin.dll | head -1)
echo "plugin: `$P"
x86_64-w64-mingw32-strip --strip-unneeded -o /out/libqt_plugin.dll.new "`$P"
ls -la /out/libqt_plugin.dll.new
"@ -replace "`r", ""

docker run --rm -v "${src}:/vlc" -v "vlcbuild:/build" -v "${run}:/out" $image bash -c $script
if ($LASTEXITCODE) { throw "dev build failed ($LASTEXITCODE)" }

# Swap the new plugin in. A running (or hung) VLC keeps the old DLL open, but Windows still
# lets us rename it out of the way, so give any existing file a unique name first.
$new = Join-Path $run "libqt_plugin.dll.new"
$dst = Join-Path $run "plugins\gui\libqt_plugin.dll"
if (Test-Path $dst) { Rename-Item $dst ("libqt_plugin.dll.old." + (Get-Date -Format yyyyMMddHHmmss)) }
Move-Item $new $dst
Get-ChildItem (Split-Path $dst) -Filter "*.old*" | ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }

if ($Launch) {
    New-Item -ItemType Directory -Force (Join-Path $run "portable") | Out-Null
    $a = @("-I", "qt", "--no-one-instance", "--no-qt-privacy-ask", "--no-qt-updates-notif")
    if ($Media) { $a += "`"$Media`"" }
    Start-Process (Join-Path $run "vlc.exe") -ArgumentList $a -WorkingDirectory $run
}
