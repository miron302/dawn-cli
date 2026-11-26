# Changelog

## 1.8.1

- **The macOS audio visualiser no longer needs BlackHole (or any virtual audio device).** dawn now ships its own small helper, `dawn-audiotap`, that listens to the sound your Mac is playing through Apple's Core Audio tap (macOS 14.2 and newer). No paid software, no Multi-Output Device, and your volume keys keep working.
- **macOS no longer needs a package manager** when the Mac already has Python 3.9+ (Apple's Command Line Tools include it). `install.sh` then installs dawn into a private environment (`~/.local/share/dawn/venv`) and links `dawn` into `~/.local/bin`, with no Homebrew, MacPorts, `pipx` or even `git` (it downloads the GitHub archive instead). `--light` forces this, `--brew` / `--macports` force the package-manager route, and without a usable Python it falls back to Homebrew (Apple Silicon) or MacPorts (Intel) as before.
- **Nothing to compile.** `install.sh` (and the new `dawn --setup-helper`) downloads a small ready-made helper from the GitHub release, checks its SHA-256 checksum and installs it, so Apple's Command Line Tools are not needed. Only if the download isn't possible does it build the helper from source, which does need them (`dawn --setup-helper --from-source` does that on purpose).
- A GitHub Action (`.github/workflows/helper.yml`) and `packaging/build-helper-release.sh` build the helper for each release as one file for both Apple Silicon and Intel.
- `install.sh` no longer installs `nowplaying-cli` by default: Spotify and Apple Music need nothing extra, and Apple broke that tool on macOS 15.4+.
- On macOS older than 14.2 the visualiser still works through a virtual audio device as before, and `install.sh` only installs `ffmpeg` there.
- README: new section explaining the helper, the one-time permission and troubleshooting; fixed a formatting slip in the install section.
- When building from source, `dawn --setup-helper` builds against the macOS SDK explicitly, tries a few fallback settings if the first build fails, and prints your setup details plus fix steps if the Swift compiler can't use the SDK (the "unable to load standard library" error).

## 1.8.0

- **macOS support.** `install.sh` now installs dawn on macOS: it picks MacPorts on Intel Macs (x86_64) and Homebrew on Apple Silicon (arm64) by itself, tells you how to install the one you're missing, and takes `--macports` / `--brew` if you want to choose. dawn runs the same way it does on Linux: weather, clock, all the modes, the process viewer, Now Playing (Spotify and Apple Music, plus other apps through `nowplaying-cli`) and an optional audio visualiser (through ffmpeg and a virtual audio device such as BlackHole; everything else works without it).
- **Redesigned Processes tab**, same size as before:
  - slim bars that change colour with load, replacing the rainbow bars
  - a cleaner summary line (load, uptime, tasks) and an aligned CPU history graph
  - a proper table header that highlights the column you're sorting by
  - processes with the same name are grouped into one row (`Chrome ×14`), and Linux kernel threads are hidden
  - clearer footer hints
- A heads-up when dawn is started in macOS Terminal.app, which can't show true colour.

## 1.7.0

Previous release.
