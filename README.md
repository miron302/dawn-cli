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
- **Process viewer** (like a mini htop): CPU and memory gauges, a CPU history graph and the busiest programs
- Finds your location automatically, or pick any city
- Celsius or Fahrenheit, 12-hour or 24-hour clock
- No account, no API key, no extra packages

---

## Install (Arch Linux)

Copy and paste these into a terminal, one at a time.

**1. Install the tools you need**

```bash
sudo pacman -S --needed python-pipx git
```

**2. Install dawn**

```bash
pipx install git+https://github.com/miron302/dawn-cli.git
```

**3. (Optional) Turn on the audio visualiser**

```bash
sudo pacman -S --needed libpulse
```

This works with both PipeWire (the Arch default) and PulseAudio. Without it, everything else still works. dawn will just show a small hint at the bottom of the screen.

**4. Make sure your terminal can find it**

```bash
pipx ensurepath
```

Now **close the terminal and open a new one**, then type:

```bash
dawn
```

That's it. Press `q` to quit.

### Prefer a one-liner?

```bash
curl -fsSL https://raw.githubusercontent.com/miron302/dawn-cli/main/install.sh | bash
```

---

## Using dawn

| Key | What it does |
| --- | --- |
| `q` | Quit |
| `u` | Switch between °C and °F |
| `t` | Switch between 12-hour and 24-hour clock |
| `v` | Show or hide the audio visualiser |
| `p` | Show or hide the process viewer |
| `s` | Sort processes by CPU or memory |
| `r` | Refresh the weather now |

### Options

```bash
dawn                      # auto-detect your location
dawn --city "Tokyo"       # show a specific place
dawn --units f            # Fahrenheit
dawn --12h                # 12-hour clock
dawn --procs              # start with the process viewer open
dawn --no-viz             # start without the audio visualiser
dawn --city Paris --units c --24h --save   # remember these choices
```

Your saved choices live in `~/.config/dawn/config.json`.

---

## The audio visualiser

Play some music (Spotify, YouTube, mpv, anything) and bars rise from the bottom of the screen, coloured to match the sky. When it's quiet they settle down. dawn only listens to the sound your computer is **playing**, never your microphone.

If the bars stay flat while music is playing, run `parec --version` to check that `libpulse` is installed, and make sure PipeWire or PulseAudio is running.

## The process viewer

Press `p` to open a frosted-glass panel next to the clock. It shows CPU and memory use, a short CPU history graph, load and uptime, and the busiest programs with their CPU and memory use. The percentages work like htop's, so a program using two cores can show 200%. It's a quick glance, not a replacement for htop (you can't kill processes from here).

On a narrow terminal the process viewer takes over the screen, so make the window wider to see both panels together.

---

## Update and uninstall

```bash
pipx upgrade dawn-cli      # update to the latest version
pipx uninstall dawn-cli    # remove it
```

---

## Troubleshooting

**`dawn: command not found`**
Run `pipx ensurepath`, then close and reopen your terminal.

**The colours look flat or strange**
dawn needs a terminal with "true colour" support. Most modern terminals have it: Alacritty, kitty, foot, WezTerm, GNOME Terminal, Konsole, Terminator, Ghostty and others. It will not look right on the plain Linux text console (the one you get with Ctrl+Alt+F3).

**It says "Weather unavailable"**
Check your internet connection. dawn keeps retrying every 20 seconds on its own.

**It shows the wrong city**
Automatic location is based on your internet connection and can be off by a city or two. Use `dawn --city "Your City" --save` to fix it for good.

**The visualiser says "install libpulse"**
Run `sudo pacman -S libpulse`, then restart dawn.

**Some symbols look like empty boxes**
Install a font with good symbol coverage, for example `sudo pacman -S ttf-dejavu`, and make sure your terminal uses it.

**It looks cramped**
Make the terminal window bigger. dawn adapts to any size, and a larger window shows more (including the 5-day forecast).

---

## Privacy

dawn does not collect anything and has no tracking. To work, it talks to two free public services:

- [Open-Meteo](https://open-meteo.com/) for the weather (and to look up a city name)
- [ipwho.is](https://ipwho.is/) to guess your city from your IP address (skipped when you use `--city`)

The audio visualiser and process viewer run entirely on your computer and send nothing anywhere.

---

## For developers

```bash
git clone https://github.com/miron302/dawn-cli.git
cd dawn-cli
python -m dawn            # run straight from the source
dawn --once               # print a single frame, handy for screenshots
```

Pure Python 3.9+, standard library only. If `numpy` is installed, the visualiser uses it automatically to use a bit less CPU. Without it, a small built-in FFT does the job.

## License

MIT, see [LICENSE](LICENSE).
