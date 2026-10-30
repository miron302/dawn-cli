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
  - **Now Playing** (on the left): the song, artist and progress of whatever is playing, and which app it's playing from
  - **Processes** (on the right, like a mini htop): CPU and memory gauges, a CPU history graph and the busiest programs
- **Halloween mode** (press `b`): the clock turns into a glowing orange "BOO?", pumpkins light up along the bottom, and the visualiser goes black and orange
- Finds your location automatically, or pick any city
- Celsius or Fahrenheit, 12-hour or 24-hour clock
- No account and no API key

---

## Supported systems

| Your system | Works? |
| --- | --- |
| **Arch-based distros** (Arch Linux, EndeavourOS, Manjaro, CachyOS and others) | Yes |
| **Fedora-based distros** (Fedora, Nobara and others) | Yes |
| Other Linux distros | May work if you install Python 3.9+, `pipx` and `git` yourself. Not officially supported. |
| macOS, Windows | No |

The installer handles Arch-based systems (`pacman`) and Fedora-based systems (`dnf`). It asks for admin rights using whichever of `sudo`, `doas`, `run0`, `pkexec` or `su` you have. On immutable Fedora variants (Silverblue, Kinoite, Bazzite) it can't add system packages, so install `git` and `pipx` your usual way and then run the `pipx install` command below.

dawn needs a terminal with "true colour" support. Most modern ones have it: Alacritty, kitty, foot, WezTerm, GNOME Terminal, Konsole, Ghostty and others.

---

## Install

### The easy way

Copy and paste this into a terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/miron302/dawn-cli/main/install.sh | bash
```

It installs what's missing (it will ask for your password), then installs dawn. Want only dawn, without the audio visualiser and Now Playing helpers? Add `-s -- --minimal` after `bash`.

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

Use `doas` (or your tool of choice) in place of `sudo` if you prefer.

Then open a new terminal and type `dawn`.

### Optional extras

These make the two music features work. Everything else works without them.

| Feature | Arch-based | Fedora-based |
| --- | --- | --- |
| Audio visualiser | `sudo pacman -S libpulse` | `sudo dnf install pulseaudio-utils` |
| Now Playing panel | `sudo pacman -S playerctl` | `sudo dnf install playerctl` |

---

## Using dawn

| Key | What it does |
| --- | --- |
| `q` | Quit |
| `u` | Switch between °C and °F |
| `t` | Switch between 12-hour and 24-hour clock |
| `b` | Halloween mode on or off ("BOO?", orange, pumpkins) |
| `v` | Show or hide the audio visualiser |
| `p` | Open or close the **Processes** panel (right) |
| `m` | Open or close the **Now Playing** panel (left) |
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
dawn --no-viz             # start without the audio visualiser
dawn --halloween          # start in Halloween mode
dawn --city Paris --units c --24h --save   # remember these choices
```

Your saved choices live in `~/.config/dawn/config.json`.

---

## The audio visualiser

Play some music (Spotify, YouTube, mpv, anything) and bars rise from the bottom of the screen, coloured to match the sky. When it's quiet they settle down. dawn only listens to the sound your computer is **playing**, never your microphone.

If the bars stay flat while music is playing, make sure the helper from "Optional extras" is installed (`parec --version` should print something) and that PipeWire or PulseAudio is running.

## The process viewer

Press `p` to open a frosted-glass panel on the right of the clock. It shows CPU and memory use, a short CPU history graph, load and uptime, and the busiest programs with their CPU and memory use. The percentages work like htop's, so a program using two cores can show 200%. It's a quick glance, not a replacement for htop (you can't kill processes from here).

## Now Playing

Press `m` to open a panel on the left of the clock showing what's playing right now: the song title (long titles scroll), the artist, the album, a progress bar, and **which app it's playing from** (Spotify, Firefox, VLC and so on). If several players are open it shows the one that's playing, and tells you how many others there are.

It works with any player that reports what it's playing to your desktop. That includes Spotify, Firefox, Chromium-based browsers (Chrome, Brave and others), VLC, Rhythmbox and many more. mpv needs the `mpv-mpris` add-on to report anything. It needs the `playerctl` helper from "Optional extras".

## Halloween mode

Press `b` and dawn gets spooky:

- The big clock turns into a flickering **BOO?** (the real time moves to a line just below it)
- All the text turns orange
- A patch of glowing jack-o'-lanterns sits along the bottom of the screen, their faces flickering like candles
- The audio visualiser turns black and orange

Press `b` again to go back to normal. Use `dawn --halloween` to start in Halloween mode, and add `--save` to keep it that way.

## Window size

The panels open independently, so you can have just the clock, the clock with either panel, or all three together. All three need a window about 130 columns wide, and about 160 columns to also fit the 5-day forecast. If the window is too narrow, dawn keeps the panel you opened most recently and shows a small hint at the bottom telling you what's hidden. Widen the window and it all comes back.

---

## Update and uninstall

```bash
pipx upgrade dawn-cli      # update to the latest version
pipx uninstall dawn-cli    # remove it
```

---

## Troubleshooting

**`pipx` crashes with "No module named 'filelock'"**
That's a missing piece in `pipx` itself, not dawn. Install it and try again: `sudo pacman -S python-filelock` (Arch-based) or `sudo dnf install python3-filelock` (Fedora-based). The installer script does this for you on Arch-based systems.

**`dawn: command not found`**
Run `pipx ensurepath`, then close and reopen your terminal.

**The colours look flat or strange**
dawn needs a terminal with "true colour" support (see "Supported systems"). It will not look right on the plain Linux text console (the one you get with Ctrl+Alt+F3).

**It says "Weather unavailable"**
Check your internet connection. dawn keeps retrying every 20 seconds on its own.

**It shows the wrong city**
Automatic location is based on your internet connection and can be off by a city or two. Use `dawn --city "Your City" --save` to fix it for good.

**The visualiser says "install libpulse"**
Install the audio helper from "Optional extras", then restart dawn.

**Now Playing says "playerctl isn't installed"**
Install it from "Optional extras", then restart dawn.

**Now Playing says "Nothing is playing" but music is on**
The app has to report what it's playing. Most do. If yours doesn't, `playerctl -l` lists the players dawn can see, and an empty list means your app isn't reporting. A player that has nothing loaded is skipped.

**Some symbols look like empty boxes**
Install a font with good symbol coverage (for example DejaVu: `ttf-dejavu` on Arch, `dejavu-sans-fonts` on Fedora) and make sure your terminal uses it.

**A panel disappeared**
The window is probably too narrow for everything that's open. Look for the "Widen the window" hint at the bottom, and make the window wider.

**It looks cramped**
Make the terminal window bigger. dawn adapts to any size, and a larger window shows more (including the 5-day forecast).

---

## Privacy

dawn does not collect anything and has no tracking. To work, it talks to two free public services:

- [Open-Meteo](https://open-meteo.com/) for the weather (and to look up a city name)
- [ipwho.is](https://ipwho.is/) to guess your city from your IP address (skipped when you use `--city`)

The audio visualiser, process viewer and Now Playing panel run entirely on your computer and send nothing anywhere.

---

## For developers

```bash
git clone https://github.com/miron302/dawn-cli.git
cd dawn-cli
python -m dawn            # run straight from the source
dawn --once               # print a single frame, handy for screenshots
dawn --once --media       # same, with a sample track if nothing is playing
```

Pure Python 3.9+, standard library only. If `numpy` is installed, the visualiser uses it automatically to use a bit less CPU. Without it, a small built-in FFT does the job.

## License

MIT, see [LICENSE](LICENSE).
