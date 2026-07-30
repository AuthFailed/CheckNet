#!/bin/sh
# Fetches the prebuilt Xray core (LibXray.xcframework) used by the VPN tab's
# "Xray inbound availability" tool (#71). The framework is large and not checked
# into git; run this once after cloning (and after bumping LIBXRAY_VERSION).
#
#   Scripts/fetch-libxray.sh
#
set -eu

LIBXRAY_VERSION="${LIBXRAY_VERSION:-v26.7.11}"
REPO="XTLS/libXray"
ASSET="libxray-apple-cgo.zip"
DEST="Frameworks"

cd "$(dirname "$0")/.."

if [ -d "$DEST/LibXray.xcframework" ]; then
  echo "LibXray.xcframework already present — delete it to re-fetch."
  exit 0
fi

url="https://github.com/$REPO/releases/download/$LIBXRAY_VERSION/$ASSET"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "Downloading $ASSET ($LIBXRAY_VERSION)…"
curl -fSL -o "$tmp/x.zip" "$url"
unzip -q "$tmp/x.zip" -d "$tmp/x"

mkdir -p "$DEST"
cp -R "$tmp/x/libxray-apple-cgo/LibXray.xcframework" "$DEST/LibXray.xcframework"
echo "Installed $DEST/LibXray.xcframework"
