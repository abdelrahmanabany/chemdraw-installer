# chemdraw-installer

> One command = ChemDraw installed and running, on macOS, Linux, or Windows.

## The one command

**macOS / Linux**
```sh
curl -fsSL https://raw.githubusercontent.com/buildn-dev/chemdraw-installer/main/install.sh | sh -s -- "https://<S3-PACK-URL>"
```

**Windows (PowerShell)**
```pwsh
iwr https://raw.githubusercontent.com/buildn-dev/chemdraw-installer/main/scripts/windows.ps1 -OutFile $env:TEMP\cdinstall.ps1
powershell -c "& $env:TEMP\cdinstall.ps1 'https://<S3-PACK-URL>'"
```

Replace `https://<S3-PACK-URL>` with the pack URL (ask in the group chat / see pinned message).

## What happens on each platform

| Platform | Wine? | Notes |
|---|---|---|
| Windows | No — native | MSI + reg + DLL patch, done |
| macOS | Homebrew `wine-stable` (no Whisky needed) | Fresh prefix `~/.chemdraw-wine`, .NET 4.8 via winetricks |
| Linux | distro wine (apt/dnf/pacman/zypper) | Same prefix + .NET flow |

## The S3 pack

The pack is a single zip fetched from S3 containing:

```
pack.zip
├── Revvity/ChemDrawSuite/*.msi       (the official ChemDraw 23.1.1 suite MSIs)
├── Crack/ChemDraw|Chem3D|ChemScript/ (patched DLLs)
├── Reg*.reg                          (licensing registry entries)
├── *.ocx                             (MSCOMCTL, RICHTX32, QProGIF)
└── Install.exe / Install.ini         (fallback launcher)
```

The installer auto-detects: downloads → unzips → finds the `.msi` → silent-installs into a
fresh Wine prefix (or natively on Windows) → merges the `.reg` files → copies patch DLLs →
renames the two `Flx*64.dll` → registers OCXs → launches ChemDraw.

## Requirement baked in

ChemDraw 23.1's licensing step crashes under Wine-Mono (`InvalidProgramException` in
`GetApplicationMainWindowHandle`). Because of that, real **.NET Framework 4.8** is installed
via winetricks into the prefix before the suite. That's the 10–20 min part of the install —
don't cancel it.

## Help debug with opencode (free tier)

If something breaks, opencode can read Wine logs and fix the flow live:

1. Install (one command): `curl -fsSL https://opencode.ai/install | bash`
2. In a terminal at a folder where you reproduced the issue:
   ```sh
   WINEDEBUG=+err,+seh cd ~/.chemdraw-wine >/dev/null 2>&1 # nothing here
   export WINEPREFIX=~/.chemdraw-wine WINEDEBUG=+err,+seh
   "$(brew --prefix)/bin/wine64" "$(find ~/.chemdraw-wine/drive_c -name ChemDraw.exe | head -1)" 2>/tmp/chemdraw.log
   opencode /tmp/chemdraw.log   # then: "help me debug this wine launch"
   ```

Nothing on this repo needs a paid plan — free tier is fine for reading logs and editing these scripts.

## Repo layout

```
install.sh            # macOS + Linux: everything, single pipe-safe POSIX script
scripts/windows.ps1   # Windows: native MSI flow
```

### For maintainers
- Change the default pack URL?edit `README.md` instructions only — the URL is always passed as arg 1.
- Regenerate a pack: upload the zip to S3, update the pinned single-command snippet.

## Known finicky bits (as identified in live debugging, 2026)

1. **No `Program Files\RevvitySignalsSoftware` after install → the MSI installs per-user** into
   `drive_c/users/<user>/AppData/Roaming/RevvitySignalsSoftware/ChemDrawApplications_x64`. So the
   registry's per-user path is the right one — install.sh checks that path first.
2. **Crack folder alone does NOT run** — you'll see missing `ChemDrawBase.dll`,
   `CoreChemistryCommon.dll`, `WinSparkle.dll`, `ChemDrawUI.dll`. The real app tree must come from
   the MSI first, then cracked DLLs get copied on top of it.
3. **.NET 4.8 required for licensing/activation steps** (Wine Mono chokes on the mixed-mode code).
4. **`FlxComm64.dll` + `FlxCore64.dll` must be renamed to `.bak`** or activation fails.

## License

Scripts: MIT. ChemDraw itself is licensed per-seat by Revvity Signals — a pack is only for
students with the API-keyed/free-cademic access sitting behind S3 auth, not for redistribution.
