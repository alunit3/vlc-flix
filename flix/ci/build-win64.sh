#!/usr/bin/env bash
# Builds and packages VLCFlix for Windows x64. Runs inside VideoLAN's win64 build image
# (see flix/UPSTREAM for the tag), the same way in CI and on a desktop:
#
#   docker run --rm -v <src>:/vlc -v <build volume>:/build -v <helpers>:/helpers \
#              -v <dist>:/dist -e JOBS=4 <image> bash /vlc/flix/ci/build-win64.sh
#
#   /helpers  flixtorrent.exe and flixweb.exe, already built (Go, see the workflow)
#   /dist     receives VLCFlix-<version>-win64-setup.exe, VLCFlix-<version>-win64.zip
#             and SHA256SUMS
set -euo pipefail

git config --global --add safe.directory /vlc
cd /vlc

VERSION=$(sed -n 's/^FLIX_VERSION=//p' configure.ac)
[ -n "$VERSION" ] || { echo "FLIX_VERSION not found in configure.ac" >&2; exit 1; }
for helper in flixtorrent.exe flixweb.exe; do
    [ -f "/helpers/$helper" ] || { echo "missing /helpers/$helper" >&2; exit 1; }
done

# Prebuilt contribs are published under the last upstream commit that changed them. The
# fork changed extras/package/win32 (one of the paths get-contrib-sha.sh looks at), so
# asking from HEAD names a fork commit VideoLAN never built. Ask from the pinned upstream.
UPSTREAM=$(grep -oE '^commit: *[0-9a-f]{40}' flix/UPSTREAM | grep -oE '[0-9a-f]{40}')
export VLC_CONTRIB_SHA=$(git rev-list -1 "$UPSTREAM" -- extras/tools contrib extras/ci extras/package/win32)
export VLC_PREBUILT_CONTRIBS_URL="https://artifacts.videolan.org/vlc/win64/vlc-contrib-x86_64-w64-mingw32-$VLC_CONTRIB_SHA.tar.zst"
export JOBS=${JOBS:-$(nproc)}
echo "VLCFlix $VERSION, contribs $VLC_CONTRIB_SHA, $JOBS jobs"

mkdir -p /build && cd /build
# -r is a release build, and on its own it also runs VideoLAN's packaging (make package-win32)
# before the Go helpers are in place; "-i none" keeps the release build and leaves the
# packaging to the steps below
/vlc/extras/package/win32/build.sh -a x86_64 -p -r -i none

cd /build/win64
# install, strip, and lay out the installer scripts next to the files
make package-win32-src
PKG=$(sed -n 's/^win32_destdir *= *//p' Makefile)
[ -d "$PKG" ] || { echo "package dir not found: $PKG" >&2; exit 1; }

# The Go helpers go in after the strip step on purpose: it rewrites every exe with
# objcopy, which has no business touching a Go binary.
mkdir -p "$PKG/flix"
cp /helpers/flixtorrent.exe /helpers/flixweb.exe "$PKG/flix/"

# The installer. make package-win32-exe would run the strip again over the helpers, so the
# two steps it adds are done here.
make "$PKG/NSIS/nsProcess.dll"
makensis -V2 "$PKG/spad.nsi"
makensis -V2 "$PKG/vlc.win32.nsi"

mkdir -p /dist
SETUP="VLCFlix-$VERSION-win64-setup.exe"
ZIP="VLCFlix-$VERSION-win64.zip"
cp "$(dirname "$PKG")/vlcflix-$VERSION-win64.exe" "/dist/$SETUP"

# The zip unpacks to a folder named after the release, without the installer's own files.
STAGE=$(mktemp -d)
cp -r "$PKG" "$STAGE/VLCFlix-$VERSION"
(cd "$STAGE" && rm -f "/dist/$ZIP" && zip -q -r -9 "/dist/$ZIP" "VLCFlix-$VERSION" \
    --exclude '*.nsi' '*/NSIS/*' '*/languages/*' '*/sdk/*' '*/helpers/*' '*/spad*')
rm -rf "$STAGE"

(cd /dist && sha256sum "$SETUP" "$ZIP" > SHA256SUMS && cat SHA256SUMS)
