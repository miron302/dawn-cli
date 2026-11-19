# Changelog

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
