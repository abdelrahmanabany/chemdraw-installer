#!/bin/sh
# ChemDraw under Wine — debugging helper
# Reproduces the launch in the exact environment the installer set up, with logs.
# Run: ./scripts/debug.sh [WINEPREFIX]
set -eu
WINEPREFIX="${1:-${WINEPREFIX:-$HOME/.chemdraw-wine}}"
WINE="$(command -v wine || command -v wine64 || true)"
[ -n "$WINE" ] || for c in "$HOME/.wine" ; do :; done
[ -n "$WINE" ] || WINE="/Applications/Wine Stable.app/Contents/Resources/wine/bin/wine"
EXE="$(find "$WINEPREFIX/drive_c" -name ChemDraw.exe -path '*ChemDrawApplications*' 2>/dev/null | head -1)"
[ -n "${EXE:-}" ] || { echo "ChemDraw.exe not found under $WINEPREFIX"; exit 1; }
LOG="${LOG:-/tmp/chemdraw-debug.log}"
echo "prefix:   $WINEPREFIX"
echo "binary:   $WINE"
echo "target:   $EXE"
echo "log:      $LOG"
export WINEPREFIX
export WINEDEBUG="${WINEDEBUG:-+err,+seh}"
cd "$(dirname "$EXE")"
"$WINE" "$(basename "$EXE")" 2>&1 | tee "$LOG"
