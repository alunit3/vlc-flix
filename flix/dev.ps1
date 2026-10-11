# Fast edit loop: incremental rebuild, then replace ONLY the Qt plugin and libvlccore in D:\vlc-fork\run.
# (The build is unstripped; the Qt plugin is ~1.3 GB, so we strip both while copying out.)
#   ./flix/dev.ps1            rebuild + install plugin and core
#   ./flix/dev.ps1 -Launch    ...and start VLC in portable mode (-I qt)
#   ./flix/dev.ps1 -ResetLayout   forget the saved control bar layout (needed after changing the default layout)
param([switch]$Launch, [switch]$ResetLayout, [int]$Jobs = 2, [string]$Media = "")
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

# The control bar layout is saved in the portable settings and then wins over the defaults in the code.
if ($ResetLayout) {
    $ini = Join-Path $run ("portable" + [IO.Path]::DirectorySeparatorChar + "vlc" + [IO.Path]::DirectorySeparatorChar + "vlc-qt-interface.ini")
    if (Test-Path $ini) {
        $keep = New-Object System.Collections.Generic.List[string]
        $skip = $false
        foreach ($l in [IO.File]::ReadAllLines($ini)) {
            if ($l -match '^\[ControlbarProfileModel\]') { $skip = $true; continue }
            if ($skip -and $l -match '^\[') { $skip = $false }
            if (-not $skip) { $keep.Add($l) }
        }
        [IO.File]::WriteAllLines($ini, $keep)
    }
}

$script = @"
set -e
git config --global --add safe.directory /vlc
cd /build/win64
make -j$Jobs
make -C modules/gui/qt install-pluginLTLIBRARIES >/dev/null 2>&1 || make install >/dev/null
P=`$(find _win32/lib/vlc/plugins/gui -name libqt_plugin.dll | head -1)
echo "plugin: `$P"
x86_64-w64-mingw32-strip --strip-unneeded -o /out/libqt_plugin.dll.new "`$P"
x86_64-w64-mingw32-strip --strip-unneeded -o /out/libvlccore.dll.new src/.libs/libvlccore.dll
LP=`$(find . -name liblua_plugin.dll -not -path "./vlc-*" -not -path "./_win32/*" | xargs ls -t | head -1)
echo "lua plugin: `$LP"
x86_64-w64-mingw32-strip --strip-unneeded -o /out/liblua_plugin.dll.new "`$LP"
ls -la /out/libqt_plugin.dll.new /out/libvlccore.dll.new /out/liblua_plugin.dll.new
"@ -replace "`r", ""

docker run --rm -v "${src}:/vlc" -v "vlcbuild:/build" -v "${run}:/out" $image bash -c $script
if ($LASTEXITCODE) { throw "dev build failed ($LASTEXITCODE)" }

# Swap a freshly built file in. A running (or hung) VLC keeps the old DLL open, but Windows
# still lets us rename it out of the way, so give any existing file a unique name first.
function Install-Built([string]$New, [string]$Dst) {
    $leaf = Split-Path $Dst -Leaf
    if (Test-Path $Dst) { Rename-Item $Dst ($leaf + ".old." + (Get-Date -Format yyyyMMddHHmmssfff)) }
    Move-Item $New $Dst
    Get-ChildItem (Split-Path $Dst) -Filter ($leaf + ".old*") |
        ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }
}
Install-Built (Join-Path $run "libqt_plugin.dll.new") (Join-Path $run "plugins\gui\libqt_plugin.dll")
Install-Built (Join-Path $run "libvlccore.dll.new")   (Join-Path $run "libvlccore.dll")
Install-Built (Join-Path $run "liblua_plugin.dll.new") (Join-Path $run ("plugins" + [IO.Path]::DirectorySeparatorChar + "lua" + [IO.Path]::DirectorySeparatorChar + "liblua_plugin.dll"))

# Lua scripts are loaded as plain source in the run tree
foreach ($rel in @("intf/flixsubs.lua", "modules/flix_opensubtitles.lua", "modules/flix_tmdb.lua", "extensions/FlixSubs.lua")) {
    $to = Join-Path $run ("lua/" + $rel)
    New-Item -ItemType Directory -Force (Split-Path $to) | Out-Null
    Copy-Item (Join-Path $src ("share/lua/" + $rel)) $to -Force
}

# the torrent helper (Go): rebuilt when its sources are newer than the installed exe
$helper = Join-Path $run "flix\flixtorrent.exe"
$newest = Get-ChildItem (Join-Path $PSScriptRoot "torrent") -Include *.go,go.mod -Recurse | Sort-Object LastWriteTime | Select-Object -Last 1
if ((Get-Command go -ErrorAction SilentlyContinue) -and ((-not (Test-Path $helper)) -or ($newest.LastWriteTime -gt (Get-Item $helper).LastWriteTime))) {
    & (Join-Path $PSScriptRoot "build-torrent.ps1")
}

if ($Launch) {
    New-Item -ItemType Directory -Force (Join-Path $run "portable") | Out-Null
    $a = @("-I", "qt", "--no-one-instance", "--no-qt-privacy-ask", "--no-qt-updates-notif")
    if ($Media) { $a += "`"$Media`"" }
    Start-Process (Join-Path $run "vlc.exe") -ArgumentList $a -WorkingDirectory $run
}
