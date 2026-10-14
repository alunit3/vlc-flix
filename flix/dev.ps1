# Fast edit loop: incremental rebuild, then replace ONLY the Qt plugin and libvlccore in D:\vlc-fork\run.
# (The build is unstripped; the Qt plugin is ~1.3 GB, so we strip both while copying out.)
#   ./flix/dev.ps1            rebuild + install plugin and core
#   ./flix/dev.ps1 -Launch    ...and start VLCFlix in portable mode (-I qt)
#   ./flix/dev.ps1 -ResetLayout   forget the saved control bar layout (needed after changing the default layout)
#   ./flix/dev.ps1 -NoMigrate     do not carry the old portable\vlc settings over
#   ./flix/dev.ps1 -RunDir run-new   install into another run tree next to the source
param([switch]$Launch, [switch]$ResetLayout, [switch]$NoMigrate, [int]$Jobs = 2, [string]$Media = "", [string]$RunDir = "run")
$ErrorActionPreference = "Stop"

$image = "registry.videolan.org/vlc-debian-win64-posix:20260611225331"
$src   = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$root  = Split-Path $src -Parent
$run   = Join-Path $root $RunDir

# The program was renamed to vlcflix, so its settings folder moved with it:
# run\portable\vlc -> run\portable\VLCFlix, and vlc-qt-interface.ini ->
# vlcflix-qt-interface.ini. Carry the old one across once, so the first run after the
# rename still has the settings, the media library and the resume points in it. Only
# fires when the new folder is not there yet, so it cannot overwrite anything later.
if (-not $NoMigrate) {
    $oldDir = Join-Path $run "portable\vlc"
    $newDir = Join-Path $run "portable\VLCFlix"
    if ((Test-Path $oldDir) -and -not (Test-Path $newDir)) {
        New-Item -ItemType Directory -Force (Split-Path $newDir) | Out-Null
        Copy-Item $oldDir $newDir -Recurse -Force
        $oldIni = Join-Path $newDir "vlc-qt-interface.ini"
        if (Test-Path $oldIni) {
            Rename-Item $oldIni "vlcflix-qt-interface.ini" -Force
        }
        Write-Host "carried the old portable settings over to portable\VLCFlix"
    }
}

# Close any previous instance from the run tree (a stale window would otherwise be mistaken
# for the new build, and it keeps the old plugin DLL open).
# Every vlcflix.exe is closed, not only the ones with a window: an instance that lost the race for
# the media library blocks in libvlc init, before Qt exists, and has no window at all. Skipping
# those is how they pile up, and one of them holding ml.lock leaves every later launch without
# a media library.
Get-Process vlcflix -ErrorAction SilentlyContinue | ForEach-Object { $_.CloseMainWindow() | Out-Null }
Start-Sleep -Seconds 3
Get-Process vlcflix -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

# Stop-Process and taskkill both report "no running instance" and leave the process in place
# for some vlcflix.exe that are stuck before Qt starts up; WMI still terminates them. Without this
# the leftovers survive every build, and the next VLCFlix to start finds the media library locked.
Start-Sleep -Seconds 2
Get-CimInstance Win32_Process -Filter "Name='vlcflix.exe'" -ErrorAction SilentlyContinue |
    ForEach-Object { try { Invoke-CimMethod -InputObject $_ -MethodName Terminate | Out-Null } catch {} }
Start-Sleep -Seconds 1
$left = @(Get-Process vlcflix -ErrorAction SilentlyContinue)
if ($left.Count -gt 0) { Write-Host "warning: $($left.Count) vlcflix.exe could not be stopped; close them before testing" }

# The control bar layout is saved in the portable settings and then wins over the defaults in the code.
if ($ResetLayout) {
    $ini = Join-Path $run ("portable" + [IO.Path]::DirectorySeparatorChar + "VLCFlix" + [IO.Path]::DirectorySeparatorChar + "vlcflix-qt-interface.ini")
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

P=modules/gui/qt/.libs/libqt_plugin.dll
[ -f "`$P" ] || P=`$(find . -name libqt_plugin.dll -not -path "./vlc-*" -not -path "./_win32/*" | head -1)
[ -n "`$P" ] || { echo "no Qt plugin was built"; exit 1; }
LP=modules/.libs/liblua_plugin.dll
[ -f "`$LP" ] || LP=`$(find . -name liblua_plugin.dll -not -path "./vlc-*" -not -path "./_win32/*" | head -1)
[ -f "`$LP" ] || LP=`$(find . -name liblua_plugin.dll | head -1)
[ -n "`$LP" ] || { echo "no lua plugin was built"; exit 1; }
echo "qt: `$P"
echo "lua: `$LP"
# Take everything from the real build output (.libs), never from _win32/.
# _win32/ is a snapshot that only "make install" writes, so a plain "make" leaves it
# behind: the Qt plugin copied from there was weeks stale, which is how a change to the
# interface could be rebuilt and still not appear.
x86_64-w64-mingw32-strip --strip-unneeded -o /out/libqt_plugin.dll.new "`$P"
x86_64-w64-mingw32-strip --strip-unneeded -o /out/libvlccore.dll.new src/.libs/libvlccore.dll
x86_64-w64-mingw32-strip --strip-unneeded -o /out/liblua_plugin.dll.new "`$LP"
# the Windows audio output (flix fixes the 5.1 channel reorder on partial writes in wasapi)
MM=modules/.libs/libmmdevice_plugin.dll
[ -f "`$MM" ] || MM=`$(find . -name libmmdevice_plugin.dll -not -path "./vlc-*" -not -path "./_win32/*" | head -1)
[ -n "`$MM" ] && x86_64-w64-mingw32-strip --strip-unneeded -o /out/libmmdevice_plugin.dll.new "`$MM"
WA=modules/.libs/libwasapi_plugin.dll
[ -f "`$WA" ] || WA=`$(find . -name libwasapi_plugin.dll -not -path "./vlc-*" -not -path "./_win32/*" | head -1)
[ -n "`$WA" ] && x86_64-w64-mingw32-strip --strip-unneeded -o /out/libwasapi_plugin.dll.new "`$WA"
# the media library (network discovery off the startup path, folders listed in-process)
# and the one-instance IPC window (raise on relaunch, retired on quit)
ML=modules/.libs/libmedialibrary_plugin.dll
[ -f "`$ML" ] || ML=`$(find . -name libmedialibrary_plugin.dll -not -path "./vlc-*" -not -path "./_win32/*" | head -1)
[ -n "`$ML" ] && x86_64-w64-mingw32-strip --strip-unneeded -o /out/libmedialibrary_plugin.dll.new "`$ML"
WM=modules/.libs/libwin_msg_plugin.dll
[ -f "`$WM" ] || WM=`$(find . -name libwin_msg_plugin.dll -not -path "./vlc-*" -not -path "./_win32/*" | head -1)
[ -n "`$WM" ] && x86_64-w64-mingw32-strip --strip-unneeded -o /out/libwin_msg_plugin.dll.new "`$WM"

# The exe carries the icon and the version resource, so it has to come across too.
# The one to ship is bin/vlcflix-static.exe: the top level vlcflix is a symlink to it,
# and that is what "make install" puts in bindir. (bin/vlcflix.exe is the small
# uninstalled stub, and _win32/bin only gets populated by a full install, so the copy
# there goes stale - which is how an old vlc.exe used to be picked up here.)
# It has to land as .new: the swap below renames the destination out of the way first
# and then moves the .new file over it. Copying straight to the final name used to work
# by accident for a moment and then failed - every build renamed the good exe aside and
# threw on the move that followed, so run\ kept a stale copy and a pile of .old files.
rm -f _win32/bin/vlc.exe
cp -f bin/vlcflix-static.exe /out/vlcflix.exe.new
# the helpers the player starts. bin/*.exe are 60 KB libtool wrappers; the programs
# themselves are in bin/.libs. vlc-preparser.exe parses and thumbnails library files.
x86_64-w64-mingw32-strip --strip-unneeded -o /out/vlc-preparser.exe.new bin/.libs/vlc-preparser.exe
x86_64-w64-mingw32-strip --strip-unneeded -o /out/vlc-cache-gen.exe.new bin/.libs/vlc-cache-gen.exe
# the installer and the desktop shortcuts read the icon out of the run tree.
# Absolute: the shell is sitting in /build/win64 at this point.
cp -f /vlc/share/icons/vlc.ico /out/vlc.ico
ls -la /out/libqt_plugin.dll.new /out/libvlccore.dll.new /out/liblua_plugin.dll.new /out/vlcflix.exe.new
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
if (Test-Path (Join-Path $run "libwasapi_plugin.dll.new")) {
    Install-Built (Join-Path $run "libwasapi_plugin.dll.new") (Join-Path $run ("plugins" + [IO.Path]::DirectorySeparatorChar + "audio_output" + [IO.Path]::DirectorySeparatorChar + "libwasapi_plugin.dll"))
}
if (Test-Path (Join-Path $run "libmmdevice_plugin.dll.new")) {
    Install-Built (Join-Path $run "libmmdevice_plugin.dll.new") (Join-Path $run ("plugins" + [IO.Path]::DirectorySeparatorChar + "audio_output" + [IO.Path]::DirectorySeparatorChar + "libmmdevice_plugin.dll"))
}
foreach ($p in @(@("libmedialibrary_plugin.dll", "misc"), @("libwin_msg_plugin.dll", "control"))) {
    $new = Join-Path $run ($p[0] + ".new")
    if (Test-Path $new) {
        Install-Built $new (Join-Path $run ("plugins" + [IO.Path]::DirectorySeparatorChar + $p[1] + [IO.Path]::DirectorySeparatorChar + $p[0]))
    }
}
Install-Built (Join-Path $run "liblua_plugin.dll.new") (Join-Path $run ("plugins" + [IO.Path]::DirectorySeparatorChar + "lua" + [IO.Path]::DirectorySeparatorChar + "liblua_plugin.dll"))
foreach ($exe in @("vlc-preparser.exe", "vlc-cache-gen.exe")) {
    $new = Join-Path $run ($exe + ".new")
    if (Test-Path $new) { Install-Built $new (Join-Path $run $exe) }
}
# and the executable, which holds the window/exe icon
if (Test-Path (Join-Path $run "vlcflix.exe.new")) {
    try { Install-Built (Join-Path $run "vlcflix.exe.new") (Join-Path $run "vlcflix.exe") }
    catch { Write-Warning "could not swap vlcflix.exe (is it running?): $($_.Exception.Message)" }
}
# the first build after the rename leaves the old binary behind, and two files with the
# same icon in the same folder is exactly the confusion this rename was meant to end.
# Best effort: an older instance may still be running and holding it open.
foreach ($stale in @("vlc.exe", "vlc.exe.old.*")) {
    Get-ChildItem $run -Filter $stale -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            Remove-Item $_.FullName -Force -ErrorAction Stop
            Write-Host "removed the old $($_.Name)"
        } catch {
            Write-Host "could not remove $($_.Name) (still running?): $($_.Exception.Message)"
        }
    }
}

# Lua scripts are loaded as plain source in the run tree
foreach ($rel in @("intf/flixsubs.lua", "modules/flix_opensubtitles.lua", "modules/flix_tmdb.lua", "extensions/FlixSubs.lua")) {
    $to = Join-Path $run ("lua/" + $rel)
    New-Item -ItemType Directory -Force (Split-Path $to) | Out-Null
    Copy-Item (Join-Path $src ("share/lua/" + $rel)) $to -Force
    # VLC loads X.luac before X.lua, so a compiled copy left from a packaged build silently
    # wins over the fresh source copied above (and for an extension, both were listed)
    Remove-Item ($to + "c") -Force -ErrorAction SilentlyContinue
}
# VLSub is the old VLC extension (retired opensubtitles.org API), no longer part of VLCFlix.
foreach ($stale in @("VLSub.luac", "VLSub.lua")) {
    Remove-Item (Join-Path $run ("lua/extensions/" + $stale)) -Force -ErrorAction SilentlyContinue
}

# the torrent helper (Go): rebuilt when its sources are newer than the installed exe
$helper = Join-Path $run "flix\flixtorrent.exe"
$newest = Get-ChildItem (Join-Path $PSScriptRoot "torrent") -Include *.go,go.mod -Recurse | Sort-Object LastWriteTime | Select-Object -Last 1
if ((Get-Command go -ErrorAction SilentlyContinue) -and ((-not (Test-Path $helper)) -or ($newest.LastWriteTime -gt (Get-Item $helper).LastWriteTime))) {
    & (Join-Path $PSScriptRoot "build-torrent.ps1") -Out (Join-Path $run "flix")
}

# the web player helper (Go + Edge WebView2), same rule
$webHelper = Join-Path $run "flix\flixweb.exe"
$webNewest = Get-ChildItem (Join-Path $PSScriptRoot "web") -Include *.go,go.mod -Recurse | Sort-Object LastWriteTime | Select-Object -Last 1
if ((Get-Command go -ErrorAction SilentlyContinue) -and ((-not (Test-Path $webHelper)) -or ($webNewest.LastWriteTime -gt (Get-Item $webHelper).LastWriteTime))) {
    & (Join-Path $PSScriptRoot "build-web.ps1") -Out (Join-Path $run "flix")
}

if ($Launch) {
    New-Item -ItemType Directory -Force (Join-Path $run "portable") | Out-Null
    # One-instance stays on, as in a real install: every vlcflix.exe was closed above, and
    # a launch while an old one is still closing now waits for it (src/win32/specific.c).
    # --no-one-instance here is what let a test launch and a double-click run side by side.
    $a = @("-I", "qt", "--no-qt-privacy-ask", "--no-qt-updates-notif")
    if ($Media) { $a += "`"$Media`"" }
    Start-Process (Join-Path $run "vlcflix.exe") -ArgumentList $a -WorkingDirectory $run
}
