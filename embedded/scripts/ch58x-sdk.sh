#!/usr/bin/env bash
# Fetch WCH's official CH58x EVT SDK (openwch/ch583, Apache-2.0) on demand.
#
# Not baked into the image: it is vendor code and ships the BLE stack as a binary
# (libCH58xBLE). Only needed for BLE or WCH's StdPeriphDriver; plain GPIO/UART/USB
# firmware is better served by ch32fun (no vendor code).
#
#   ch58x-sdk [dest]     default dest: ${CH58X_SDK:-/workspace/.ch58x-sdk}
#
# Result: <dest>/EVT/EXAM/{SRC,BLE,USB,...} and <dest>/Application. Add the dest
# to .gitignore. Prints the key paths when done.
set -euo pipefail

DEST="${1:-${CH58X_SDK:-/workspace/.ch58x-sdk}}"
URL="https://github.com/openwch/ch583"

if [ -d "$DEST/.git" ]; then
    git -C "$DEST" pull --ff-only --depth=1 -q || true
else
    mkdir -p "$DEST"
    git clone -q --depth=1 --filter=blob:none --sparse "$URL" "$DEST"
    git -C "$DEST" sparse-checkout set --no-cone \
        /EVT/EXAM /EVT/PUB /Datasheet /LICENSE /README.md
fi

echo "CH58x SDK at $DEST"
echo "  drivers + startup + linker : $DEST/EVT/EXAM/SRC  (StdPeriphDriver, RVMSIS, Startup, Ld/Link.ld)"
echo "  BLE stack headers/library  : $DEST/EVT/EXAM/BLE/LIB"
echo "  BLE examples               : $DEST/EVT/EXAM/BLE/{Peripheral,Central,Broadcaster,...}"
echo "  datasheet + BLE reference  : $DEST/Datasheet"
