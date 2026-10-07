#!/bin/sh
# ChemDraw one-line installer (macOS + Linux)
#
#   curl -fsSL https://raw.githubusercontent.com/abdelrahmanabany/chemdraw-installer/main/install.sh | sh -s -- "S3_PACK_URL"
#
# macOS:  installs Homebrew (if missing) + wine + winetricks, creates ~/.chemdraw-wine,
#         installs .NET 4.8, installs the suite from the S3 pack, applies patches, launches.
# Linux:  uses the distro's wine/winetricks (apt / dnf / pacman / zypper).
set -eu

PACK_URL="${1:-${CHEMDRAW_URL:-}}"
if [ -z "$PACK_URL" ]; then
  cat >&2 <<EOF
Usage:
  curl -fsSL <this file's raw URL> | sh -s -- "<S3_PACK_URL>"

CHEMDRAW_URL env var also works. The URL points to the pack zip on S3.
EOF
  exit 1
fi

WINEPREFIX="${WINEPREFIX:-$HOME/.chemdraw-wine}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/chemdraw.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

say() { printf '\n==> %s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

cygw() { # wine path for a posix path
  case "$(uname -s)" in
    Darwin) echo "z:$1" ;;
    *) echo "$1" ;;
  esac
}

 # ---------- platform bootstrap ----------
OS="$(uname -s)"
case "$OS" in
  Darwin)
    if ! command -v brew >/dev/null 2>&1; then
      say "Homebrew not found — installing it (asks for your macOS password)"
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
        || die "Homebrew install failed"
    fi
    command -v brew >/dev/null 2>&1 || export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
    say "Installing wine + winetricks via Homebrew (this can take a while)"
    brew install --cask wine-stable || die "brew install wine-stable failed"
    wine_bin="$(command -v wine || command -v wine64 || command -v "/Applications/Wine Stable.app/Contents/Resources/wine/bin/wine" || true)"
    [ -n "$wine_bin" ] || die "wine binary still not found after brew"
    WINETRICKS=""
    command -v winetricks >/dev/null && WINETRICKS="winetricks" || WINETRICKS=""
    ;;
  Linux)
    say "Installing wine + winetricks via package manager"
    if command -v apt-get >/dev/null 2>&1; then
      pacman_flag=""; sudo apt-get update && sudo apt-get install -y wine wine64 winetricks unzip cabextract || die "apt install failed"
    elif command -v dnf >/dev/null 2>&1; then
      sudo dnf install -y wine winetricks unzip cabextract || die "dnf install failed"
    elif command -v pacman >/dev/null 2>&1; then
      sudo pacman -S --needed --noconfirm wine winetricks unzip cabextract || die "pacman install failed"
    elif command -v zypper >/dev/null 2>&1; then
      sudo zypper install -y wine winetricks unzip cabextract || die "zypper install failed"
    else
      die "no supported package manager found (apt/dnf/pacman/zypper)"
    fi
    ;;
  *) die "Win/macOS/Linux only. On Windows use scripts/windows.ps1 (see README)." ;;
esac

WINE=""
for c in "$wine_bin" wine wine64; do command -v "$c" >/dev/null && WINE="$c" && break; done
[ -n "$WINE" ] || die "wine not found"
command -v unzip >/dev/null || warn "unzip missing — pack may be a zip"

say "Downloading ChemDraw pack from S3"
if command -v curl >/dev/null 2>&1; then
  curl -fL --progress-bar "$PACK_URL" -o "$WORK/pack" || die "download failed"
else
  wget -q -O "$WORK/pack" "$PACK_URL" || die "download failed"
fi

say "Unpacking"
mkdir -p "$WORK/packdir"
if head -c2 "$WORK/pack" | grep -q "$(printf 'PK')"; then
  unzip -qo "$WORK/pack" -d "$WORK/packdir"
else
  tar xf "$WORK/pack" -C "$WORK/packdir"
fi

# ---------- prefix + dotnet ----------
say "Preparing Wine prefix at $WINEPREFIX"
if [ ! -e "$WINEPREFIX/system.reg" ]; then
  WINEPREFIX="$WINEPREFIX" "$WINE" wineboot -i >/dev/null 2>&1 || true
fi

if command -v winetricks >/dev/null; then
  say "Checking .NET Framework 4.8"
  if ! "$WINE" reg query 'HKLM\\Software\\Microsoft\\NET Framework Setup\\NDP\\v4\\Full' /v Release >/dev/null 2>&1; then
    say "Installing .NET 4.8 — 10-20 minutes, don't cancel"
    winetricks -q dotnet48 || warn "dotnet48 failed — ChemDraw's licensing window will likely crash on Wine Mono"
  else
    say ".NET 4.8 present, skipping"
  fi
else
  warn "winetricks not available; skipping .NET — likely crash"
fi

# ---------- install ----------
cd "$WORK/packdir"
MSI="$(find . -iname '*.msi' | LC_ALL=C grep -iv 32 | head -1 || true)"
SETUP_EXE="$(find . -iname 'Install.exe' -o -iname 'setup.exe' 2>/dev/null | head -1 || true)"

if [ -n "$MSI" ]; then
  say "Silent-installing $MSI (few minutes, no progress bar)"
  WINEPREFIX="$WINEPREFIX" "$WINE" msiexec /i "$(cygw "$(cd "$(dirname "$MSI")" && pwd)/$(basename "$MSI")")" /qn \
    || { say "Silent install failed — running interactive installer"; WINEPREFIX="$WINEPREFIX" "$WINE" msiexec /i "$(cygw "$MSI")"; }
elif [ -n "$SETUP_EXE" ]; then
  say "Running $SETUP_EXE — click through the installer (choose x64, untick ChemDraw Collections)"
  WINEPREFIX="$WINEPREFIX" "$WINE" "$(cygw "$SETUP_EXE")"
else
  die "no .msi or Install.exe found in the pack"
fi

# ---------- locate install dir ----------
APP_DIR=""
for cand in "$WINEPREFIX/drive_c/users/crossover/AppData/Roaming/RevvitySignalsSoftware/ChemDrawApplications_x64" \
            "$WINEPREFIX/drive_c/Program Files/RevvitySignalsSoftware/ChemDrawApplications" \
            "$WINEPREFIX/drive_c/Program Files/RevvitySignalsSoftware/ChemDrawApplications_x64"; do
  [ -f "$cand/ChemDraw.exe" ] && APP_DIR="$cand" && break
done
if [ -z "$APP_DIR" ]; then
  found="$(find "$WINEPREFIX/drive_c" -iname ChemDraw.exe -path '*ChemDrawApplications*' 2>/dev/null | head -1)"
  [ -n "$found" ] && APP_DIR="$(dirname "$found")"
fi
[ -n "$APP_DIR" ] || die "ChemDraw applications dir not found after install"

say "ChemDraw installed at: ${APP_DIR#$WINEPREFIX/drive_c}"

# ---------- apply pack extras ----------
say "Applying reg entries, DLLs and OCXs found in the pack"
for reg in $(find . -iname '*.reg'); do
  WINEPREFIX="$WINEPREFIX" "$WINE" regedit /s "$(cygw "$(cd "$(dirname "$reg")" && pwd)/$(basename "$reg")")" >/dev/null 2>&1 || true
done
for top in */; do
  case "$top" in
    */ChemDraw*/|*/Chem3D*/|*/ChemFinder*/|*/ChemScript*/)
      cp -R "$top". "$APP_DIR"/ 2>/dev/null || true ;;
  esac
done
for f in FlxComm64 FlxCore64; do
  [ -f "$APP_DIR/$f.dll" ] && mv -n "$APP_DIR/$f.dll" "$APP_DIR/$f.dll.bak" || true
done
for ocx in $(find . -iname '*.ocx'); do
  WINEPREFIX="$WINEPREFIX" "$WINE" regsvr32 /s "$(cygw "$ocx")" >/dev/null 2>&1 || true
done

say "Launching ChemDraw"
LOG="$(mktemp).chemdraw.log"
cd "$APP_DIR"
WINEPREFIX="$WINEPREFIX" "$WINE" ChemDraw.exe > "$LOG" 2>&1 &

say "Done. If a licensing window appears, choose 'Activation code' (pack's keys were merged into the registry)."
say "Logs if anything goes wrong: $LOG"
