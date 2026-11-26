# dawn

**A beautiful weather, clock and calendar for your terminal.**

Open a terminal, type `dawn`, and get a living sky behind a big clock, today's date and the weather where you are. The background changes with the time of day (sunrise, blue sky, sunset, starry night) and with the weather (clouds, rain, snow, thunderstorms).

<!-- Add a screenshot here after you upload the project:
![dawn screenshot](screenshot.png)
-->

- Big clock, date, temperature, "feels like", humidity and wind
- 5-day forecast
- Animated sky: sun, moon, twinkling stars, drifting clouds, rain, snow and lightning
- **Audio visualiser** (like cava): glowing bars rise out of the scene and dance to whatever you're playing
- **Two optional side panels**, which you can open at the same time as the clock:
  - **Now Playing** (on the left): the song, artist and progress of whatever is playing, which app it's playing from, and **synced lyrics** that follow along line by line
  - **Processes** (on the right, like a mini htop): CPU and memory bars, a CPU history graph and the busiest programs, grouped by app
- **Halloween mode** (start it with `dawn --halloween`): the clock turns into a glowing orange "BOO?", pumpkins light up along the bottom, and the visualiser goes black and orange
- **Christmas mode** (press `c`, or start it with `dawn --christmas`): falling snow, a garland with holly and twinkling lights, a rare visit from Santa's sleigh, presents in the snow, and a red and green visualiser
- Runs on **Arch-based Linux, Fedora-based Linux and macOS**
- Finds your location automatically, or pick any city
- Celsius or Fahrenheit, 12-hour or 24-hour clock
- No account and no API key

---

## Supported systems

| Your system | Works? |
| --- | --- |
| **Arch-based distros** (Arch Linux, EndeavourOS, Manjaro, CachyOS and others) | Yes |
| **Fedora-based distros** (Fedora, Nobara and others) | Yes |
| **macOS** (Apple Silicon and Intel) | Yes. Needs Python 3.9+, which Apple's Command Line Tools include, so no package manager is needed. Without it, Apple Silicon uses [Homebrew](https://brew.sh) and Intel uses [MacPorts](https://www.macports.org) |
| Other Linux distros | May work if you install Python 3.9+, `pipx` and `git` yourself. Not officially supported. |
| Windows | No |

The macOS visualiser needs macOS 14.2 or newer. Everything else in dawn works on older versions too.

The installer handles Arch-based systems (`pacman`), Fedora-based systems (`dnf`) and macOS (Homebrew on Apple Silicon, MacPorts on Intel). On Linux it asks for admin rights using whichever of `sudo`, `doas`, `run0`, `pkexec` or `su` you have. On immutable Fedora variants (Silverblue, Kinoite, Bazzite) it can't add system packages, so install `git` and `pipx` your usual way and then run the `pipx install` command below.

dawn needs a terminal with "true colour" support. Most modern ones have it: Alacritty, kitty, foot, WezTerm, GNOME Terminal, Konsole, Ghostty, iTerm2 and others. **The built-in macOS Terminal.app is the exception** (it only has 256 colours), so on a Mac use iTerm2, Ghostty, kitty, WezTerm or Alacritty.

---

## Install

### The easy way

Copy and paste this into a terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/miron302/dawn-cli/main/install.sh | bash
```

It installs what's missing (on Linux it will ask for your password), then installs dawn. On a Mac it first looks for a Python 3.9+ that is already there (Apple's Command Line Tools include one). If it finds one, it needs **no package manager at all**: it puts dawn in a private environment in `~/.local/share/dawn/venv` and adds the `dawn` command to `~/.local/bin`. Otherwise it picks the package manager by itself: **Homebrew on Apple Silicon (arm64)** and **MacPorts on Intel (x86_64)**. If the one it needs isn't installed it tells you where to get it ([brew.sh](https://brew.sh) or [macports.org](https://www.macports.org/install.php)), and you run the same command again. MacPorts asks for your password, Homebrew must be run without `sudo`.

You can choose on a Mac by adding `-s -- --light` (use the Mac's own Python, no package manager), `-s -- --macports` or `-s -- --brew` after `bash`. The light route doesn't even need `git`.

Want the other one? Add `-s -- --macports` or `-s -- --brew` after `bash`, for example:

```bash
curl -fsSL https://raw.githubusercontent.com/miron302/dawn-cli/main/install.sh | bash -s -- --macports
```

On a Mac with macOS 14.2 or newer the installer also downloads dawn's small built-in audio helper for the visualiser (see [Visualiser on macOS](#visualiser-on-macos-the-built-in-helper)). Nothing gets compiled and no extra tools are needed.

Want only dawn, without the audio visualiser and Now Playing helpers? Add `-s -- --minimal` after `bash`.

Using `doas` or something else instead of `sudo`? It works out which one you have. To choose yourself, put `PRIV_CMD=doas` at the start of the line (`curl ... | PRIV_CMD=doas bash`).

Now **open a new terminal window** and type:

```bash
dawn
```

Press `q` to quit.

### Step by step

**Arch-based**

```bash
sudo pacman -S --needed python-pipx python-filelock git
pipx install git+https://github.com/miron302/dawn-cli.git
pipx ensurepath
```

**Fedora-based**

```bash
sudo dnf install pipx git
pipx install git+https://github.com/miron302/dawn-cli.git
pipx ensurepath
```

**macOS, no package manager** (needs Python 3.9+; Apple's Command Line Tools include it, install them with `xcode-select --install`)

```bash
python3 -m venv ~/.local/share/dawn/venv
~/.local/share/dawn/venv/bin/pip install git+https://github.com/miron302/dawn-cli.git
mkdir -p ~/.local/bin && ln -sf ~/.local/share/dawn/venv/bin/dawn ~/.local/bin/dawn
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zprofile   # then open a new terminal
dawn --setup-helper   # optional: downloads the audio helper for the visualiser (macOS 14.2+)
```

**macOS, Apple Silicon** (needs [Homebrew](https://brew.sh))

```bash
brew install pipx git
pipx install git+https://github.com/miron302/dawn-cli.git
pipx ensurepath
dawn --setup-helper   # optional: downloads the audio helper for the visualiser (macOS 14.2+)
```

**macOS, Intel** (needs [MacPorts](https://www.macports.org/install.php))

```bash
sudo port install pipx git
pipx install git+https://github.com/miron302/dawn-cli.git
pipx ensurepath
dawn --setup-helper   # optional: downloads the audio helper for the visualiser (macOS 14.2+)
```

Use `doas` (or your tool of choice) in place of `sudo` on Linux if you prefer.

Then open a new terminal and type `dawn`.

### Optional extras

These make the two music features work. Everything else works without them.

| Feature | Arch-based | Fedora-based | macOS |
| --- | --- | --- | --- |
| Audio visualiser | `sudo pacman -S libpulse` | `sudo dnf install pulseaudio-utils` | Built in (macOS 14.2+): the installer downloads it, or run `dawn --setup-helper`. Nothing to compile. See [below](#visualiser-on-macos-the-built-in-helper). |
| Now Playing panel | `sudo pacman -S playerctl` | `sudo dnf install playerctl` | Nothing for Spotify and Apple Music. For other apps you can add `nowplaying-cli` yourself (`brew install nowplaying-cli`); the installer doesn't. |

---

## Using dawn

| Key | What it does |
| --- | --- |
| `q` | Quit |
| `u` | Switch between °C and °F |
| `t` | Switch between 12-hour and 24-hour clock |
| `v` | Show or hide the audio visualiser |
| `p` | Open or close the **Processes** panel (right) |
| `m` | Open or close the **Now Playing** panel (left) |
| `l` | Show or hide the lyrics in the Now Playing panel |
| `c` | Christmas mode on or off |
| `s` | Sort processes by CPU or memory |
| `r` | Refresh the weather now |

### Options

```bash
dawn                      # auto-detect your location
dawn --city "Tokyo"       # show a specific place
dawn --units f            # Fahrenheit
dawn --12h                # 12-hour clock
dawn --media              # start with the Now Playing panel open
dawn --procs              # start with the process viewer open
dawn --media --procs      # start with both open
dawn --no-lyrics          # no lyrics (and no lyrics lookups at all)
dawn --no-viz             # start without the audio visualiser
dawn --halloween          # start in Halloween mode
dawn --christmas          # start in Christmas mode (or just press c)
dawn --city Paris --units c --24h --save   # remember these choices
```

Your saved choices live in `~/.config/dawn/config.json`.

---

## The audio visualiser

Play some music (Spotify, YouTube, mpv, anything) and bars rise from the bottom of the screen, coloured to match the sky. When it's quiet they settle down. dawn only listens to the sound your computer is **playing**, never your microphone.

If the bars stay flat while music is playing, make sure the helper from "Optional extras" is installed (`parec --version` should print something) and that PipeWire or PulseAudio is running.

### Visualiser on macOS: the built-in helper

macOS doesn't let ordinary programs listen to the sound it is playing, so a Python program like dawn can't do it by itself. On a Mac the visualiser therefore **needs dawn's built-in helper**, a tiny program called `dawn-audiotap` that ships inside dawn. You don't have to install anything else: no virtual audio device, no paid software, no changing your sound output.

**What the helper does**

1. When the visualiser is on, dawn starts the helper in the background.
2. The helper asks macOS for a copy of the sound going to your speakers or headphones. It uses a feature Apple added in macOS 14.2 called a Core Audio *process tap*, which is exactly meant for this.
3. It turns that sound into a plain stream of numbers (one channel, 22,050 samples a second) and passes them to dawn through a pipe.
4. dawn turns the numbers into the bars you see. When you quit dawn or turn the visualiser off, the helper stops and cleans up after itself.

**What it does not do:** it doesn't record anything to disk, doesn't send anything over the network, never touches your microphone, doesn't mute or change your sound, and doesn't affect other apps. Your volume keys and output device keep working normally.

**What you need**

- **macOS 14.2 or newer.** (On older versions see "Older macOS" below.)
- **A one-time download** of the helper, which is a small ready-made file. You do **not** need Xcode, the Command Line Tools or any other developer software for this.
- **One permission** (below).

**Setting it up**

The installer script does this for you on macOS 14.2+. To do it yourself, or to redo it:

```bash
dawn --setup-helper
```

That downloads the ready-made helper for your version of dawn from dawn's [GitHub releases](https://github.com/miron302/dawn-cli/releases), checks its SHA-256 checksum, makes sure it runs on your Mac, and installs it as `~/.local/share/dawn/dawn-audiotap` (no `sudo` needed). Then it runs a quick test. The test is what makes macOS ask for permission, so keep an eye out for the pop-up and choose **Allow**.

If the download isn't possible (you're offline, or that version's helper hasn't been published yet), dawn falls back to **building the helper from its source** on your Mac. That route needs Apple's Command Line Tools (`xcode-select --install`). You can also choose it on purpose, for example if you'd rather not run a downloaded file and want to read the code first (it's one file, `dawn/helper/dawn-audiotap.swift`):

```bash
dawn --setup-helper --from-source
```

**The permission**

macOS wants you to approve any app that records system audio. Because dawn runs inside your terminal, the permission is given to your **terminal app** (Terminal, iTerm2, Ghostty, kitty and so on), once:

1. Open **System Settings → Privacy & Security → Screen & System Audio Recording**.
2. Find the **System Audio Recording Only** section (the wording differs a little between macOS versions) and switch your terminal app on. If it isn't in the list, click **+** and add it from your Applications folder.
3. Quit your terminal completely and open it again, then start `dawn`.

Some terminals, iTerm2 in particular, don't always show the pop-up, so you may have to add them by hand like this. If the permission is missing, macOS doesn't give an error: it simply hands over silence, so the bars stay flat while music plays.

**Turning it off or removing it**

- Don't want the visualiser? `dawn --no-viz --save` turns it off for good and the note at the bottom goes away.
- To remove the helper, delete the file: `rm ~/.local/share/dawn/dawn-audiotap`. (`pipx uninstall dawn-cli` removes dawn itself but leaves this file.)
- To keep it somewhere else, set `DAWN_HELPER_DIR` to another folder when you run `dawn --setup-helper` and when you run `dawn`.

**Older macOS (13 and earlier)**

The helper can't work there, so the visualiser can only run if you route your sound through a virtual audio device such as [BlackHole](https://github.com/ExistentialAudio/BlackHole), which dawn will find by itself. You also need `ffmpeg` (`brew install ffmpeg` or `sudo port install ffmpeg`). Set it up like this:

1. Install BlackHole 2ch. It's open source (GPL-3), but its website has asked some people to pay before handing out the installer. If that happens to you, run `brew install --cask blackhole-2ch`, or build it yourself from its [GitHub repository](https://github.com/ExistentialAudio/BlackHole) (you need Xcode).
2. Open **Audio MIDI Setup**, click **+** and choose **Create Multi-Output Device**. Tick your speakers or headphones **and** BlackHole 2ch.
3. In **System Settings → Sound**, choose that Multi-Output Device as the output. (While it's selected the keyboard volume keys don't work.)
4. Run `dawn`.

To use a different device, set `DAWN_AUDIO_DEVICE` to part of its name or its number, for example `DAWN_AUDIO_DEVICE="My Device" dawn`. dawn also finds Loopback (paid, from Rogue Amoeba) and Soundflower (free, unmaintained, often broken on recent macOS) by name.

**Credits:** the helper follows the way [AudioTee](https://github.com/makeusabrew/audiotee) (MIT licence, by Nick Payne) sets up the audio tap. The licence text is in the helper's source file.

## The process viewer

Press `p` to open a frosted-glass panel on the right of the clock. From top to bottom it shows:

- **A summary line** with the load average, how long the machine has been up and how many tasks are running
- **CPU and memory bars** that shift from green to yellow to red as they fill, with the percentage on the right. A short graph of recent CPU use sits under the CPU bar, and "used of total" sits under the memory bar
- **The busiest programs**, one row each, with their CPU and memory use. The column you're sorting by is highlighted in the header, and `s` switches between CPU and memory

Programs that run as many processes (a browser and all its helpers, for example) are **grouped into one row**, marked with `×` and the number of processes, so one busy app doesn't take up the whole list. Their memory is added up. On Linux, kernel threads are left out, since they aren't programs you can do anything about.

Every CPU percentage is a share of the whole machine: the process list and the big CPU bar use the same scale, so the busiest programs add up to roughly the total shown there. It's a quick glance, not a replacement for htop (you can't kill processes from here). It works the same way on Linux and macOS.

## Now Playing

Press `m` to open a panel on the left of the clock showing what's playing right now: the song title (long titles scroll), the artist, the album, a progress bar, and **which app it's playing from** (Spotify, Firefox, VLC and so on). If several players are open it shows the one that's playing, and tells you how many others there are.

### Lyrics

When a song has synced lyrics, they show under the progress bar, with the line being sung right now in bold in the middle, the lines just before it and after it dimmed, and a ♪ during instrumental breaks. They move along with the song, and freeze when you pause. Long lines scroll. On a short window you see fewer lines, and below a certain height they're hidden to make room.

- Lyrics come from [LRCLIB](https://lrclib.net), a free community database, so not every song has them. Newer and more popular songs are the most likely to. Songs without time-stamped lyrics show "No synced lyrics found".
- Matching is by the song's title, artist, album and length. Videos and tracks from a browser often have messy titles, so those match less often.
- Press `l` to hide the lyrics. While they're hidden, dawn doesn't look anything up. `dawn --no-lyrics --save` turns them off for good.
- Lyrics you've seen are remembered in `~/.cache/dawn/lyrics.json` (the last 300 songs), so a song is only looked up once. You can delete that file at any time.

It works with any player that reports what it's playing to your desktop. That includes Spotify, Firefox, Chromium-based browsers (Chrome, Brave and others), VLC, Rhythmbox and many more. mpv needs the `mpv-mpris` add-on to report anything. It needs the `playerctl` helper from "Optional extras".

**On macOS** it works with **Spotify** and **Apple Music** out of the box (dawn only asks an app what it's playing if that app is already open, so it never launches one). Other apps, such as browsers, are picked up through `nowplaying-cli` if you installed it. Apple restricted that kind of access in macOS 15.4, so on newer versions it may only see some apps.

## Halloween mode

For a spooky screen, start dawn with:

```bash
dawn --halloween
```

- The big clock turns into a flickering **BOO?** (the real time moves to a line just below it)
- All the text turns orange
- A patch of glowing jack-o'-lanterns sits along the bottom of the screen, their faces flickering like candles
- The audio visualiser turns black and orange

It's off unless you ask for it, and there's no key for it, so it never switches on by accident. To make it your default, add `--save`: `dawn --halloween --save`. To turn it back off for good: `dawn --no-halloween --save`.

## Christmas mode

For a festive screen, press `c` while dawn is running. Press it again to go back to normal. You can also start dawn in Christmas mode:

```bash
dawn --christmas
```

- **Snow** falls over the whole window all the time, in four kinds of flake (`.`, `*`, `❄` and `❅`) at different speeds for depth. It takes over from every weather effect: rain, storms, fog, clouds, the sun and moon and the tinted sky are all switched off. The weather in the panels is still the real weather, so you still see the real temperature and forecast.
- **Decorations**: a garland with holly, red bows and berries across the top, strings of lights down both sides, and every panel's border turns into a string of twinkling Christmas lights. The lights pulse a little with the music.
- **Presents** of different sizes, colours and ribbons sit in the snow along the bottom. They get more numerous as the window gets wider.
- **Santa** flies across the top of the screen in his sleigh with two reindeer (the front one has a red nose), leaving a trail of sparkles. He turns up at random, a first time 30 to 90 seconds after Christmas mode goes on and after that about once every four minutes, never twice within a minute. Each flight takes about seven seconds. Nothing else stops while he flies, and he leaves nothing behind. Want to see him right away? Start dawn with `--santa-now` and he visits about a second and a half after Christmas mode goes on, whether you used the flag or the key.
- **The visualiser** turns into alternating red and green bars, each fading from deep to bright. It reacts to the music exactly as before, and the bars rise from behind the presents so none of the movement is hidden.

Christmas mode is off when dawn starts, unless you use `dawn --christmas`. To start in it every time, add `--save`: `dawn --christmas --save`. To undo that: `dawn --no-christmas --save`. If Christmas mode and Halloween mode are both on, Christmas wins, and Halloween comes back when you press `c` again.

## Window size

The panels open independently, so you can have just the clock, the clock with either panel, or all three together. All three need a window about 130 columns wide, and about 160 columns to also fit the 5-day forecast. If the window is too narrow, dawn keeps the panel you opened most recently and shows a small hint at the bottom telling you what's hidden. Widen the window and it all comes back.

---

## Update and uninstall

```bash
pipx upgrade dawn-cli      # update to the latest version
pipx uninstall dawn-cli    # remove it
```

If you installed on macOS without a package manager (the light install), run the installer again to update, and remove dawn with `rm -r ~/.local/share/dawn ~/.local/bin/dawn`. That also deletes the audio helper.

On macOS, updating dawn doesn't rebuild the audio helper. If a release's notes say the helper changed, run `dawn --setup-helper` again. Uninstalling dawn leaves the helper behind; delete it with `rm -r ~/.local/share/dawn`.

---

## Troubleshooting

**`pipx` crashes with "No module named 'filelock'"**
That's a missing piece in `pipx` itself, not dawn. Install it and try again: `sudo pacman -S python-filelock` (Arch-based) or `sudo dnf install python3-filelock` (Fedora-based). The installer script does this for you on Arch-based systems.

**`dawn: command not found`**
Run `pipx ensurepath`, then close and reopen your terminal. If you installed on macOS without a package manager, `~/.local/bin` has to be on your PATH: the installer adds it to `~/.zprofile` (or `~/.bash_profile`), so open a new terminal window, or add it yourself with `export PATH="$HOME/.local/bin:$PATH"`.

**The colours look flat or strange**
dawn needs a terminal with "true colour" support (see "Supported systems"). It will not look right on the plain Linux text console (the one you get with Ctrl+Alt+F3), or in macOS Terminal.app. On a Mac, switch to iTerm2, Ghostty, kitty, WezTerm or Alacritty.

**It says "Weather unavailable"**
Check your internet connection. dawn keeps retrying every 20 seconds on its own.

**It shows the wrong city**
Automatic location is based on your internet connection and can be off by a city or two. Use `dawn --city "Your City" --save` to fix it for good.

**The visualiser says "install libpulse"**
Install the audio helper from "Optional extras", then restart dawn.

**On a Mac the visualiser says "run: dawn --setup-helper"**
The built-in audio helper hasn't been set up yet. Run `dawn --setup-helper`; it only needs an internet connection. If it says it couldn't download the helper and needs the Command Line Tools, either try again when you're online or run `xcode-select --install`, wait for it to finish, then run `dawn --setup-helper` again. On macOS older than 14.2 the helper can't be used: see "Older macOS" in the visualiser section.

**On a Mac the bars stay flat while music plays**
Almost always the permission: add your terminal app under **System Settings → Privacy & Security → Screen & System Audio Recording → System Audio Recording Only**, then quit and reopen the terminal. You can test the helper on its own with `~/.local/share/dawn/dawn-audiotap --check`, which prints `ok` when it works. Also make sure the sound really is playing on this Mac's speakers or headphones, because that is what the helper listens to.

**On a Mac the visualiser says "audio capture stopped"**
The helper quit on its own. Run `dawn --setup-helper` to set it up again and test it, which also shows any error message. If you just updated macOS, running it again often fixes it.

**`dawn --setup-helper` says the helper didn't build, with "unable to load standard library"**
This only happens when the helper is built from source (because it couldn't be downloaded, or you used `--from-source`). It means the Swift compiler can't use your macOS SDK. It almost always means Apple's Command Line Tools are damaged or older than your macOS (it often happens right after a macOS update). The script prints some details about your setup and the steps below:

1. Open **System Settings → General → Software Update** and install any "Command Line Tools for Xcode" update that is offered.
2. If there isn't one, reinstall them: `sudo rm -rf /Library/Developer/CommandLineTools`, then `xcode-select --install` and wait for it to finish.
3. If you use the full Xcode app, make it the active one: `sudo xcode-select -s /Applications/Xcode.app`.
4. Run `dawn --setup-helper` again. (Once you're online and that version's helper is published, a plain `dawn --setup-helper` downloads it and skips the compiler completely.)

If it still fails, open an issue and paste everything the script printed. For any other build error, the same applies: the message comes from the Swift compiler, not from dawn. To use a different Swift compiler, run `SWIFTC=/path/to/swiftc dawn --setup-helper`.

**Now Playing says "playerctl isn't installed"**
Install it from "Optional extras", then restart dawn.

**Lyrics say "No synced lyrics found"**
LRCLIB doesn't have time-stamped lyrics for that song, or the title in your player doesn't match closely enough (common for YouTube and other videos). Try a song from a normal music app to check that lyrics work.

**Lyrics say "Couldn't reach the lyrics service"**
Check your internet connection. dawn tries again by itself after half a minute.

**Now Playing says "Nothing is playing" but music is on**
On a Mac, only Spotify and Apple Music are supported out of the box (see "Now Playing"). On Linux, the app has to report what it's playing. Most do. If yours doesn't, `playerctl -l` lists the players dawn can see, and an empty list means your app isn't reporting. A player that has nothing loaded is skipped.

**Some symbols look like empty boxes**
(This includes the snowflakes `❄` and `❅` in Christmas mode.) Install a font with good symbol coverage (for example DejaVu: `ttf-dejavu` on Arch, `dejavu-sans-fonts` on Fedora) and make sure your terminal uses it.

**A panel disappeared**
The window is probably too narrow for everything that's open. Look for the "Widen the window" hint at the bottom, and make the window wider.

**It looks cramped**
Make the terminal window bigger. dawn adapts to any size, and a larger window shows more (including the 5-day forecast).

---

## Privacy

dawn does not collect anything and has no tracking. To work, it talks to these free public services:

- [Open-Meteo](https://open-meteo.com/) for the weather (and to look up a city name)
- [ipwho.is](https://ipwho.is/) to guess your city from your IP address (skipped when you use `--city`)
- [LRCLIB](https://lrclib.net) for lyrics, **only while the Now Playing panel is open and lyrics are on**. To find lyrics it sends the current song's title, artist, album and length (plus the usual details any web request carries, like your IP address). Press `l` or use `--no-lyrics` and it sends nothing.

The audio visualiser and process viewer run entirely on your computer and send nothing anywhere. (On macOS the built-in helper only takes a copy of the sound your Mac is playing, never your microphone, and keeps it in memory just long enough to draw the bars.) The Now Playing panel itself does too, apart from the lyrics lookups above.

---

## For developers

```bash
git clone https://github.com/miron302/dawn-cli.git
cd dawn-cli
python -m dawn            # run straight from the source
dawn --once               # print a single frame, handy for screenshots
dawn --once --media       # same, with a sample track if nothing is playing
dawn --once --christmas --santa-now   # one frame of Christmas mode with Santa on screen
```

The macOS audio helper is a single Swift file, `dawn/helper/dawn-audiotap.swift`. `dawn/helper/install-helper.sh` (run it with `dawn --setup-helper`) downloads the prebuilt helper from the GitHub release, or builds the Swift file when that isn't possible. `dawn-audiotap --check` starts the audio tap for a moment and prints `ok`; with no arguments it streams 16-bit mono audio to stdout, which is how dawn reads it.

Pure Python 3.9+, standard library only (the macOS audio helper is the one small piece of Swift). If `numpy` is installed, the visualiser uses it automatically to use a bit less CPU. Without it, a small built-in FFT does the job.

### Publishing the macOS helper with a release

The prebuilt helper is one file that runs on Apple Silicon and Intel Macs. It has to be attached to **every** GitHub release, named exactly `dawn-audiotap-macos-universal`, together with `dawn-audiotap-macos-universal.sha256` (users of version 1.8.1 download it from the `v1.8.1` release).

- **Automatic:** push a version tag (`git tag v1.8.1 && git push origin v1.8.1`). The GitHub Action in `.github/workflows/helper.yml` builds it on a Mac runner and attaches both files, creating the release if it doesn't exist yet. You can also start it by hand from the Actions tab.
- **By hand:** on a Mac with the Command Line Tools run `packaging/build-helper-release.sh`, then upload the two files in `dist/` to the release (`gh release upload v1.8.1 dist/dawn-audiotap-macos-universal dist/dawn-audiotap-macos-universal.sha256`).

Until a version's helper is published, `dawn --setup-helper` falls back to building from source, so nothing breaks, it just needs the Command Line Tools.

## License

MIT, see [LICENSE](LICENSE).
