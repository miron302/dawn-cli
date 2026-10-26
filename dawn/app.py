"""dawn - a beautiful weather, time & date dashboard for your terminal."""

import argparse
import cmath
import json
import math
import os
import random
import select
import shutil
import signal
import subprocess
import sys
import termios
import threading
import time
import tty
import unicodedata
import urllib.parse
import urllib.request
from array import array
from collections import deque
from datetime import datetime, timedelta, timezone
from pathlib import Path

from . import __version__

FRAME_TIME = 1 / 30  # smooth 30 frames per second, with or without the visualiser

# --------------------------------------------------------------------------
# Colour helpers
# --------------------------------------------------------------------------

WHITE = (240, 243, 250)
DIM = (150, 160, 182)
BORDER = (120, 132, 160)
YELLOW = (255, 214, 102)
GRAY = (208, 215, 230)
BLUE = (125, 185, 255)
RAIN_C = (170, 195, 238)


def mix(a, b, t):
    t = 0.0 if t < 0 else 1.0 if t > 1 else t
    return (
        int(a[0] + (b[0] - a[0]) * t),
        int(a[1] + (b[1] - a[1]) * t),
        int(a[2] + (b[2] - a[2]) * t),
    )


def lum(c):
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


def sat(c, k):
    g = lum(c)
    return tuple(max(0, min(255, int(g + (v - g) * k))) for v in c)


def desat(c, k):
    g = lum(c) * 0.9 + 10
    return mix(c, (g, g, g), k)


# (hour, top colour, bottom colour) - the sky through the day
SKY = [
    (0.0, (5, 8, 24), (14, 18, 48)),
    (4.5, (8, 12, 36), (34, 30, 76)),
    (6.0, (58, 52, 116), (238, 140, 104)),
    (7.5, (92, 152, 222), (250, 204, 156)),
    (10.0, (66, 138, 230), (150, 206, 250)),
    (15.0, (60, 130, 224), (142, 202, 250)),
    (17.5, (80, 112, 202), (250, 182, 112)),
    (19.0, (50, 42, 102), (238, 110, 92)),
    (20.5, (14, 14, 46), (58, 40, 90)),
    (22.0, (6, 9, 28), (18, 24, 56)),
    (24.0, (5, 8, 24), (14, 18, 48)),
]


def sky_colors(hour):
    for i in range(len(SKY) - 1):
        h0, t0, b0 = SKY[i]
        h1, t1, b1 = SKY[i + 1]
        if h0 <= hour <= h1:
            f = (hour - h0) / (h1 - h0)
            return mix(t0, t1, f), mix(b0, b1, f)
    return SKY[0][1], SKY[0][2]


TEMP_STOPS = [
    (-10, (120, 160, 255)),
    (0, (130, 200, 255)),
    (10, (140, 230, 220)),
    (18, (170, 235, 150)),
    (25, (255, 225, 120)),
    (32, (255, 160, 90)),
    (40, (255, 100, 90)),
]


def temp_color(c):
    if c <= TEMP_STOPS[0][0]:
        return TEMP_STOPS[0][1]
    for i in range(len(TEMP_STOPS) - 1):
        a, ca = TEMP_STOPS[i]
        b, cb = TEMP_STOPS[i + 1]
        if a <= c <= b:
            return mix(ca, cb, (c - a) / (b - a))
    return TEMP_STOPS[-1][1]


# --------------------------------------------------------------------------
# Text width helpers (song titles can contain emoji or CJK, which are 2 cells wide)
# --------------------------------------------------------------------------


def cw(ch):
    """How many terminal cells a character takes: 0, 1 or 2."""
    if ord(ch) < 0x300:
        return 1
    if unicodedata.combining(ch) or unicodedata.category(ch) in ("Mn", "Me", "Cf"):
        return 0
    return 2 if unicodedata.east_asian_width(ch) in ("W", "F") else 1


def str_width(s):
    return sum(cw(c) for c in s)


def clip(s, width):
    """Cut s to fit in width cells, adding an ellipsis when it was shortened."""
    if str_width(s) <= width:
        return s
    out, w = [], 0
    for ch in s:
        c = cw(ch)
        if w + c > width - 1:
            break
        out.append(ch)
        w += c
    return "".join(out) + "\u2026"


def pad(s, width, align="<"):
    gap = max(0, width - str_width(s))
    if align == ">":
        return " " * gap + s
    if align == "^":
        return " " * (gap // 2) + s + " " * (gap - gap // 2)
    return s + " " * gap


# --------------------------------------------------------------------------
# Weather codes, icons and the big clock font
# --------------------------------------------------------------------------

# WMO code -> (label, kind, intensity)
WMO = {
    0: ("Clear sky", "clear", 0),
    1: ("Mostly clear", "clear", 0),
    2: ("Partly cloudy", "partly", 0),
    3: ("Overcast", "cloud", 0),
    45: ("Fog", "fog", 0),
    48: ("Freezing fog", "fog", 0),
    51: ("Light drizzle", "rain", 0.5),
    53: ("Drizzle", "rain", 0.6),
    55: ("Heavy drizzle", "rain", 0.8),
    56: ("Freezing drizzle", "rain", 0.6),
    57: ("Freezing drizzle", "rain", 0.8),
    61: ("Light rain", "rain", 0.5),
    63: ("Rain", "rain", 0.8),
    65: ("Heavy rain", "rain", 1.2),
    66: ("Freezing rain", "rain", 0.8),
    67: ("Freezing rain", "rain", 1.1),
    71: ("Light snow", "snow", 0.5),
    73: ("Snow", "snow", 0.8),
    75: ("Heavy snow", "snow", 1.2),
    77: ("Snow grains", "snow", 0.6),
    80: ("Light showers", "rain", 0.5),
    81: ("Showers", "rain", 0.9),
    82: ("Violent showers", "rain", 1.3),
    85: ("Snow showers", "snow", 0.7),
    86: ("Heavy snow showers", "snow", 1.2),
    95: ("Thunderstorm", "storm", 1.3),
    96: ("Thunderstorm, hail", "storm", 1.3),
    99: ("Severe thunderstorm", "storm", 1.3),
}

TINT = {"partly": 0.15, "cloud": 0.45, "fog": 0.5, "rain": 0.5, "snow": 0.35, "storm": 0.65}

_CLOUD = [
    "             ",
    "    .--.     ",
    " .-(    ).   ",
    "(___.__)__)  ",
]

ICONS = {
    "clear": [
        ("   \\  |  /   ", YELLOW),
        ("    .---.    ", YELLOW),
        ("-- (     ) --", YELLOW),
        ("    `---'    ", YELLOW),
        ("   /  |  \\   ", YELLOW),
    ],
    "night": [
        ("    _.._     ", (225, 232, 255)),
        ("  .'  .-'    ", (225, 232, 255)),
        (" /   /       ", (225, 232, 255)),
        (" \\   \\       ", (225, 232, 255)),
        ("  '._'-._    ", (225, 232, 255)),
    ],
    "partly": [
        ("   \\  /      ", YELLOW),
        (' _ /"".--.   ', YELLOW),
        ("   \\_(    ).  ", GRAY),
        ("   /(___(__) ", GRAY),
        ("             ", GRAY),
    ],
    "cloud": [(l, GRAY) for l in _CLOUD] + [("             ", GRAY)],
    "fog": [
        ("             ", GRAY),
        (" _ - _ - _ - ", GRAY),
        ("  _ - _ - _  ", GRAY),
        (" _ - _ - _ - ", GRAY),
        ("             ", GRAY),
    ],
    "rain": [(l, GRAY) for l in _CLOUD]
    + [("   / / / /   ", BLUE)],
    "snow": [(l, GRAY) for l in _CLOUD]
    + [("   * * * *   ", (240, 246, 255))],
    "storm": [(l, GRAY) for l in _CLOUD]
    + [("  _/ _/ _/   ", YELLOW)],
}

SMALL = {
    "clear": ("\u263c", YELLOW),
    "night": ("\u263e", (225, 232, 255)),
    "partly": ("\u2601", YELLOW),
    "cloud": ("\u2601", GRAY),
    "fog": ("\u2261", GRAY),
    "rain": ("\u2602", BLUE),
    "snow": ("\u2744", (240, 246, 255)),
    "storm": ("\u03df", YELLOW),
}

FONT = {
    "0": ["###", "# #", "# #", "# #", "###"],
    "1": [" # ", "## ", " # ", " # ", "###"],
    "2": ["###", "  #", "###", "#  ", "###"],
    "3": ["###", "  #", "###", "  #", "###"],
    "4": ["# #", "# #", "###", "  #", "  #"],
    "5": ["###", "#  ", "###", "  #", "###"],
    "6": ["###", "#  ", "###", "# #", "###"],
    "7": ["###", "  #", "  #", "  #", "  #"],
    "8": ["###", "# #", "###", "# #", "###"],
    "9": ["###", "# #", "###", "  #", "###"],
    ":": [" ", "#", " ", "#", " "],
}


def big_text(s, scale):
    rows = [[] for _ in range(5)]
    for ch in s:
        glyph = FONT[ch]
        for r in range(5):
            row = glyph[r].replace("#", "\u2588")
            if scale == 2:
                row = "".join(c * 2 for c in row)
            rows[r].append(row)
    gap = " " * scale
    return [gap.join(r) for r in rows]


# --------------------------------------------------------------------------
# Network: location + weather (Open-Meteo, no API key needed)
# --------------------------------------------------------------------------


def http_json(url, timeout=10):
    req = urllib.request.Request(url, headers={"User-Agent": f"dawn/{__version__}"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r)


def locate(city):
    if city:
        q = urllib.parse.urlencode({"name": city, "count": 1, "language": "en", "format": "json"})
        d = http_json("https://geocoding-api.open-meteo.com/v1/search?" + q)
        res = d.get("results")
        if not res:
            raise ValueError(f"Couldn't find a place called '{city}'")
        r = res[0]
        name = ", ".join(x for x in (r.get("name"), r.get("country_code")) if x)
        return r["latitude"], r["longitude"], name
    d = http_json("https://ipwho.is/")
    if not d.get("success", True):
        raise ValueError("Couldn't detect your location (try: dawn --city London)")
    name = ", ".join(x for x in (d.get("city"), d.get("country_code")) if x)
    return d["latitude"], d["longitude"], name


def fetch_weather(lat, lon):
    q = urllib.parse.urlencode(
        {
            "latitude": lat,
            "longitude": lon,
            "current": "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,is_day",
            "daily": "weather_code,temperature_2m_max,temperature_2m_min",
            "timezone": "auto",
            "forecast_days": 5,
        }
    )
    return http_json("https://api.open-meteo.com/v1/forecast?" + q)


# --------------------------------------------------------------------------
# Audio visualiser (reads what your speakers are playing, like cava)
# --------------------------------------------------------------------------


def make_fft(N):
    """Tiny pure-Python FFT so we need no extra packages."""
    bits = N.bit_length() - 1
    rev = [int(format(i, "0%db" % bits)[::-1], 2) for i in range(N)]
    tw = [cmath.exp(-2j * cmath.pi * k / N) for k in range(N // 2)]

    def fft(x):
        a = [complex(x[r]) for r in rev]
        size = 2
        while size <= N:
            half, step = size // 2, N // size
            for start in range(0, N, size):
                k = 0
                for j in range(start, start + half):
                    t = a[j + half] * tw[k]
                    u = a[j]
                    a[j] = u + t
                    a[j + half] = u - t
                    k += step
            size *= 2
        return a

    return fft


class Audio:
    RATE, N = 22050, 1024

    def __init__(self):
        self.proc = None
        self.err = None
        self.demo = False
        self.lock = threading.Lock()
        self.buf = bytearray()
        self.h = []
        self.peak = 0.4
        self.edges = None
        self.win = [0.5 - 0.5 * math.cos(2 * math.pi * i / (self.N - 1)) for i in range(self.N)]
        try:  # numpy is optional, it just makes things lighter on the CPU
            import numpy

            self.np = numpy
            self.npwin = numpy.array(self.win, dtype=numpy.float32)
        except Exception:
            self.np = None
            self.fft = make_fft(self.N)

    def start(self):
        if self.proc is not None:
            return
        exe = shutil.which("parec")
        if not exe:
            self.err = "install libpulse to enable the audio visualiser"
            return
        try:
            self.proc = subprocess.Popen(
                [exe, "-d", "@DEFAULT_MONITOR@", "--format=s16le", f"--rate={self.RATE}",
                 "--channels=1", "--latency-msec=20"],
                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, bufsize=0,
            )
        except OSError as e:
            self.err = f"couldn't start audio capture: {e}"
            return
        self.err = None
        threading.Thread(target=self._read, args=(self.proc,), daemon=True).start()

    def stop(self):
        p, self.proc = self.proc, None
        if p:
            try:
                p.terminate()
            except OSError:
                pass

    def _read(self, proc):
        try:
            while True:
                chunk = proc.stdout.read(2048)
                if not chunk:
                    break
                with self.lock:
                    self.buf += chunk
                    del self.buf[:-4096]
        except (OSError, ValueError):
            pass
        if self.proc is proc:  # it died on its own
            self.proc = None
            self.err = "audio capture stopped (is PipeWire or PulseAudio running?)"

    def _mags(self, data):
        N = self.N
        if self.np is not None:
            x = self.np.frombuffer(data, dtype="<i2").astype(self.np.float32) / 32768.0 * self.npwin
            return (self.np.abs(self.np.fft.rfft(x))[: N // 2] * (4.0 / N)).tolist()
        a = array("h")
        a.frombytes(data)
        if sys.byteorder == "big":
            a.byteswap()
        c = self.fft([v / 32768.0 * w for v, w in zip(a, self.win)])
        return [abs(v) * (4.0 / N) for v in c[: N // 2]]

    def _edges(self, n):
        if self.edges is None or len(self.edges) != n + 1:
            bw = self.RATE / self.N
            lo, hi = 45.0, 9000.0
            self.edges = [lo * (hi / lo) ** (i / n) / bw for i in range(n + 1)]
        return self.edges

    def bars(self, n):
        """Return n bar heights between 0 and 1 (smoothed, with falling gravity)."""
        if self.demo:
            return [
                max(0.04, min(1.0, 0.12 + 0.8 * (0.5 + 0.5 * math.sin(i * 0.5)) * (1 - i / (n * 1.3))
                              * (0.6 + 0.4 * math.sin(i * 1.7 + 2))))
                for i in range(n)
            ]
        mags = None
        if self.proc is not None:
            with self.lock:
                data = bytes(self.buf[-2 * self.N:])
            if len(data) >= 2 * self.N:
                mags = self._mags(data)
        new = [0.0] * n
        if mags is not None:
            e, bw, raw = self._edges(n), self.RATE / self.N, []
            for i in range(n):
                b0, b1 = e[i], e[i + 1]
                if b1 - b0 < 1.0:
                    bc = (b0 + b1) / 2
                    i0 = int(bc)
                    f = bc - i0
                    v = mags[i0] * (1 - f) + mags[i0 + 1] * f
                else:
                    v = max(mags[int(b0): int(b1) + 1])
                v *= ((b0 + b1) / 2 * bw / 300.0) ** 0.45  # even out the treble
                raw.append(max(0.0, math.log10(1 + v * 150) / 2.18 - 0.1))
            self.peak = max(self.peak * 0.998, max(raw), 0.4)
            raw = [v / self.peak for v in raw]
            new = [min(1.0, (raw[max(0, i - 1)] + 2 * raw[i] + raw[min(n - 1, i + 1)]) / 4) for i in range(n)]
        if len(self.h) != n:
            self.h = [0.0] * n
        self.h = [a if a > b else max(a, b * 0.88 - 0.004) for a, b in zip(new, self.h)]
        return self.h


# --------------------------------------------------------------------------
# Process viewer (reads /proc directly, like a tiny htop)
# --------------------------------------------------------------------------


class SysMon:
    def __init__(self):
        self.enabled = threading.Event()
        self.stop = threading.Event()
        self.hz = os.sysconf("SC_CLK_TCK")
        self.page = os.sysconf("SC_PAGE_SIZE")
        self.reset()
        self.hist = deque(maxlen=40)
        self.cpu, self.mem, self.procs, self.load, self.uptime = 0.0, (0, 1), [], (0, 0, 0), 0

    def reset(self):
        self.prev_cpu, self.prev_proc, self.prev_t = None, {}, None

    def update(self):
        now = time.monotonic()
        with open("/proc/stat") as f:
            v = [int(x) for x in f.readline().split()[1:9]]
        total, idle = sum(v), v[3] + v[4]
        if self.prev_cpu and total > self.prev_cpu[0]:
            self.cpu = 100.0 * (1 - (idle - self.prev_cpu[1]) / (total - self.prev_cpu[0]))
            self.hist.append(self.cpu)
        self.prev_cpu = (total, idle)

        info = {}
        with open("/proc/meminfo") as f:
            for line in f:
                k, _, rest = line.partition(":")
                if k in ("MemTotal", "MemAvailable"):
                    info[k] = int(rest.split()[0]) * 1024
        total_mem = info.get("MemTotal", 1)
        self.mem = (total_mem - info.get("MemAvailable", 0), total_mem)

        elapsed = now - self.prev_t if self.prev_t else None
        cur, rows = {}, []
        for d in os.listdir("/proc"):
            if not d.isdigit():
                continue
            try:
                with open(f"/proc/{d}/stat") as f:
                    s = f.read()
                i = s.rfind(")")
                name = "".join(c if c.isprintable() else "?" for c in s[s.find("(") + 1: i])
                rest = s[i + 2:].split()
                ticks = int(rest[11]) + int(rest[12])
                rss = int(rest[21]) * self.page
            except (OSError, ValueError, IndexError):
                continue
            pid = int(d)
            cur[pid] = ticks
            cpu = 0.0
            if elapsed and pid in self.prev_proc:
                cpu = 100.0 * (ticks - self.prev_proc[pid]) / (self.hz * elapsed)
            rows.append((name, max(0.0, cpu), rss, pid))
        self.prev_proc, self.prev_t = cur, now
        self.procs = rows
        try:
            self.load = os.getloadavg()
            with open("/proc/uptime") as f:
                self.uptime = float(f.read().split()[0])
        except (OSError, ValueError):
            pass

    def loop(self):
        while not self.stop.is_set():
            if self.enabled.is_set():
                try:
                    self.update()
                except Exception:
                    pass
                self.stop.wait(1.0)
            else:
                self.reset()
                self.stop.wait(0.2)



# --------------------------------------------------------------------------
# Now Playing (asks playerctl what any MPRIS media player is doing)
# --------------------------------------------------------------------------

_SEP = "\x1f"
MEDIA_FMT = _SEP.join("{{%s}}" % k for k in ("playerName", "status", "artist", "title", "album", "position", "mpris:length"))

APP_NAMES = {
    "spotify": "Spotify", "spotifyd": "Spotifyd", "spotify_player": "spotify-player", "ncspot": "ncspot",
    "firefox": "Firefox", "librewolf": "LibreWolf", "zen": "Zen Browser", "chromium": "Chromium",
    "chrome": "Google Chrome", "brave": "Brave", "vivaldi": "Vivaldi", "opera": "Opera", "edge": "Microsoft Edge",
    "plasma-browser-integration": "Browser", "vlc": "VLC", "mpv": "mpv", "celluloid": "Celluloid",
    "rhythmbox": "Rhythmbox", "strawberry": "Strawberry", "elisa": "Elisa", "amarok": "Amarok",
    "clementine": "Clementine", "audacious": "Audacious", "cmus": "cmus", "mpd": "MPD", "mpdris2": "MPD",
    "lollypop": "Lollypop", "quodlibet": "Quod Libet", "deadbeef": "DeaDBeeF", "kdeconnect": "KDE Connect",
    "tidal-hifi": "TIDAL", "youtube-music": "YouTube Music", "yesplaymusic": "YesPlayMusic",
    "amberol": "Amberol", "gnome-music": "GNOME Music", "totem": "Videos", "haruna": "Haruna",
}


def app_name(raw):
    base = raw.split(".")[0]
    return APP_NAMES.get(base.lower()) or base.replace("_", " ").replace("-", " ").title() or "Unknown player"


def clean_text(s):
    return "".join(c if c.isprintable() else " " for c in s).strip()


class MediaMon:
    def __init__(self):
        self.enabled = threading.Event()
        self.stop = threading.Event()
        self.players = []
        self.missing = False  # playerctl isn't installed
        self.ready = False  # have we asked at least once?

    def poll(self):
        exe = shutil.which("playerctl")
        self.missing = exe is None
        if exe is None:
            self.players, self.ready = [], True
            return
        try:
            r = subprocess.run([exe, "-a", "metadata", "--format", MEDIA_FMT],
                               capture_output=True, text=True, timeout=3)
        except (OSError, subprocess.SubprocessError):
            return
        now, found = time.monotonic(), []
        for line in r.stdout.split("\n"):
            parts = line.split(_SEP)
            if len(parts) != 7:
                continue
            name, status, artist, title, album = (clean_text(x) for x in parts[:5])
            try:
                pos = int(float(parts[5]))
            except ValueError:
                pos = None
            try:
                length = int(float(parts[6])) or None
            except ValueError:
                length = None
            if not (title or artist) and status != "Playing":
                continue  # an idle player with nothing loaded
            found.append({"name": name, "status": status, "artist": artist, "title": title,
                          "album": album, "pos": pos, "len": length, "at": now})
        self.players, self.ready = found, True

    def current(self):
        """The player to show (one that's playing wins) and how many others there are."""
        for want in ("Playing", "Paused"):
            for p in self.players:
                if p["status"] == want:
                    return p, len(self.players) - 1
        if self.players:
            return self.players[0], len(self.players) - 1
        return None, 0

    @staticmethod
    def position(p):
        """Seconds into the track, kept moving between polls while it's playing."""
        if p["pos"] is None:
            return None
        pos = p["pos"]
        if p["status"] == "Playing":
            pos += int((time.monotonic() - p["at"]) * 1e6)
        if p["len"]:
            pos = min(pos, p["len"])
        return max(0, pos) / 1e6

    def loop(self):
        while not self.stop.is_set():
            if self.enabled.is_set():
                try:
                    self.poll()
                except Exception:
                    pass
                self.stop.wait(1.0)
            else:
                self.ready = False
                self.stop.wait(0.2)


class State:
    def __init__(self):
        self.place = None
        self.weather = None
        self.offset = None
        self.error = None
        self.refresh = threading.Event()
        self.stop = threading.Event()
        self.audio = Audio()
        self.sysmon = SysMon()
        self.media = MediaMon()


def worker(st, city):
    loc = None
    while not st.stop.is_set():
        try:
            if loc is None:
                loc = locate(city)
                st.place = loc[2]
            d = fetch_weather(loc[0], loc[1])
            st.offset = d.get("utc_offset_seconds")
            st.weather = d
            st.error = None
            wait = 600
        except Exception as e:  # network down, bad city, etc.
            st.error = str(e) or e.__class__.__name__
            wait = 20
        st.refresh.wait(wait)
        st.refresh.clear()


def local_now(st):
    if st.offset is None:
        return datetime.now()
    return datetime.now(timezone.utc).replace(tzinfo=None) + timedelta(seconds=st.offset)


# --------------------------------------------------------------------------
# Frame buffer: half-block "pixels" with a text overlay
# --------------------------------------------------------------------------


class Frame:
    def __init__(self, W, H):
        self.W, self.H, self.PH = W, H, H * 2
        self.px = [None] * self.PH
        self.txt = {}

    def put(self, x, y, c, a):
        if 0 <= x < self.W and 0 <= y < self.PH and a > 0:
            p = self.px[y][x]
            self.px[y][x] = (
                int(p[0] + (c[0] - p[0]) * a),
                int(p[1] + (c[1] - p[1]) * a),
                int(p[2] + (c[2] - p[2]) * a),
            )

    def text(self, x, y, s, fg, bold=False):
        if not 0 <= y < self.H:
            return
        for ch in s:
            w = cw(ch)
            if w == 0:
                continue
            if ch != " " and 0 <= x and x + w <= self.W:
                self.txt[(x, y)] = (ch, fg, bold)
                if w == 2:  # the second cell is covered by the wide character
                    self.txt[(x + 1, y)] = ("", fg, bold)
            x += w

    def rows(self, absolute=True):
        out = []
        px, W = self.px, self.W
        for y in range(self.H):
            row = [f"\x1b[{y + 1};1H"] if absolute else []
            last = None
            top_row, bot_row = px[2 * y], px[2 * y + 1]
            for x in range(W):
                t = self.txt.get((x, y))
                top, bot = top_row[x], bot_row[x]
                if t:
                    ch, fg, bold = t
                    key = (fg, mix(top, bot, 0.5), bold)
                else:
                    ch = "\u2580"
                    key = (top, bot, False)
                if key != last:
                    f, b, bold = key
                    row.append(
                        "\x1b[0%s;38;2;%d;%d;%d;48;2;%d;%d;%dm"
                        % (";1" if bold else "", f[0], f[1], f[2], b[0], b[1], b[2])
                    )
                    last = key
                row.append(ch)
            out.append("".join(row))
        return out


# --------------------------------------------------------------------------
# The animated sky
# --------------------------------------------------------------------------


class Scene:
    def __init__(self, W, H):
        self.W, self.PH = W, H * 2
        PH = self.PH
        rng = random.Random(42)
        self.stars = [
            (rng.randrange(W), rng.randrange(max(1, int(PH * 0.7))), rng.uniform(0, 6.28), rng.uniform(0.6, 2.4))
            for _ in range(max(20, W * H // 35))
        ]
        self.clouds = [
            (rng.uniform(0.04, 0.5), rng.randint(max(6, W // 12), max(8, W // 6)), rng.randint(2, 4),
             rng.uniform(0.6, 2.2), rng.uniform(0, W * 2))
            for _ in range(8)
        ]
        n = min(450, max(40, W * H // 14))
        self.rain = [(rng.uniform(0, W), rng.uniform(0, PH), rng.uniform(45, 80), rng.randint(2, 4)) for _ in range(n)]
        self.snow = [(rng.uniform(0, W), rng.uniform(0, PH), rng.uniform(4, 11), rng.uniform(0, 6.28)) for _ in range(n)]
        self.hills = [
            (rng.uniform(0, 6), rng.uniform(0, 6), rng.uniform(0.04, 0.07), rng.uniform(0.11, 0.17)) for _ in range(2)
        ]

    def draw(self, fr, hour, kind, inten, t, bars=None, pulse=0.0):
        W, PH = self.W, self.PH
        top, bot = sky_colors(hour)
        dark = max(0.0, min(1.0, (70 - lum(top)) / 50))

        ttop, tbot = top, bot
        k = TINT.get(kind, 0)
        if k:
            ttop, tbot = desat(top, k), desat(bot, k)
        if kind == "storm":
            ph = t % 7.0
            if ph < 0.3:
                f = (1 - ph / 0.3) * 0.35
                ttop, tbot = mix(ttop, (225, 228, 255), f), mix(tbot, (225, 228, 255), f)

        px = fr.px
        for r in range(PH):
            f = r / (PH - 1) if PH > 1 else 0.0
            c = mix(ttop, tbot, f ** 1.3)
            if kind == "fog":
                c = mix(c, (205, 210, 220), 0.30 + 0.25 * f)
            px[r] = [c] * W

        # stars
        cover = {"clear": 1.0, "partly": 0.6, "cloud": 0.15, "fog": 0.1, "rain": 0.1, "snow": 0.1}.get(kind, 0.0)
        if dark * cover > 0.02:
            for x, y, ph, sp in self.stars:
                b = 0.55 + 0.45 * math.sin(t * sp + ph)
                fr.put(x, y, (255, 255, 255), min(1.0, dark * cover * (b + pulse * 0.4)))

        # sun / moon
        if kind in ("clear", "partly"):
            body = None
            if 6 <= hour <= 18:
                p = (hour - 6) / 12
                body, glow, r, gr = (255, 236, 170), (255, 200, 120), 3, 11
            elif hour >= 18.5 or hour <= 5.5:
                p = ((hour - 18.5) % 24) / 11.0
                body, glow, r, gr = (232, 238, 255), (150, 170, 230), 3, 8
            if body:
                cx = int(p * (W - 1))
                cy = int(PH * 0.78 - math.sin(math.pi * p) * PH * 0.55)
                for dy in range(-gr, gr + 1):
                    for dx in range(-gr, gr + 1):
                        d = math.hypot(dx, dy)
                        if d <= r:
                            fr.put(cx + dx, cy + dy, body, 1.0)
                        elif d <= gr:
                            fr.put(cx + dx, cy + dy, glow, ((1 - (d - r) / (gr - r)) ** 2) * 0.45)

        # clouds
        ncl = {"clear": 1, "partly": 4, "cloud": 7, "rain": 7, "storm": 8, "snow": 6}.get(kind, 0)
        if ncl:
            ccol = mix(mix(tbot, (255, 255, 255), 0.6), (22, 26, 44), dark * 0.8)
            if kind in ("rain", "storm"):
                ccol = mix(ccol, (90, 95, 110), 0.5)
            for yf, w, h, sp, x0 in self.clouds[:ncl]:
                cx = int((x0 + t * sp) % (W + 2 * w)) - w
                cy = int(yf * PH * 0.6) + 4
                for ox, oy, bw, bh in ((0, 0, w, h), (-w * 0.5, h * 0.3, w * 0.6, h * 0.8), (w * 0.55, h * 0.25, w * 0.65, h * 0.85)):
                    bw, bh = max(2, int(bw)), max(1, int(bh))
                    for dy in range(-bh, bh + 1):
                        for dx in range(-bw, bw + 1):
                            d = (dx / bw) ** 2 + (dy / bh) ** 2
                            if d < 1:
                                fr.put(cx + int(ox) + dx, cy + int(oy) + dy, ccol, min(1.0, (1 - d) * 2.2) * 0.5)

        # rolling hills
        gt = (200, 212, 232) if kind == "snow" else (6, 10, 22)
        cols = (mix(tbot, gt, 0.5), mix(tbot, gt, 0.75)) if kind == "snow" else (mix(tbot, gt, 0.55), mix(tbot, gt, 0.82))
        for layer, (p1, p2, f1, f2) in enumerate(self.hills):
            base = PH * (0.17 - 0.07 * layer)
            for x in range(W):
                yt = int(PH - (base + PH * 0.03 * math.sin(x * f1 + p1) + PH * 0.02 * math.sin(x * f2 + p2)))
                for y in range(max(0, yt), PH):
                    px[y][x] = cols[layer]

        if bars:
            self._bars(fr, bars, tbot, dark)

        # precipitation
        if kind in ("rain", "storm"):
            n = int(len(self.rain) * min(inten, 1.3) / 1.3)
            for x0, y0, sp, ln in self.rain[:n]:
                y = (y0 + t * sp) % PH
                x = (x0 - t * sp * 0.2) % W
                for i in range(ln):
                    fr.put(int(x + i * 0.2), int(y - i), RAIN_C, 0.5 * (1 - i / ln) + 0.15)
        elif kind == "snow":
            n = int(len(self.snow) * min(inten, 1.3) / 1.3)
            for x0, y0, sp, ph in self.snow[:n]:
                y = (y0 + t * sp) % PH
                x = (x0 + 2.5 * math.sin(t * 0.7 + ph)) % W
                fr.put(int(x), int(y), (245, 248, 255), 0.85)

    def _bars(self, fr, bars, tbot, dark):
        """Equaliser bars rising from the bottom edge, coloured by the sky."""
        W, PH, px = self.W, self.PH, fr.px
        n = len(bars)
        slot = max(1, W // n)
        bw = max(1, slot - 1) if slot >= 2 else 1
        margin = (W - n * slot) // 2
        maxh = max(4, int(PH * 0.42))
        base = sat(tbot, 1.8)
        if dark > 0.4:
            base = mix(base, (140, 170, 255), 0.4 * dark)
        tip = mix(base, (255, 255, 255), 0.7)
        cols = [mix(base, tip, y / maxh) for y in range(maxh + 1)]
        for i, h in enumerate(bars):
            hp = int(h * maxh)
            x0 = margin + i * slot
            for y in range(hp):
                row, c = px[PH - 1 - y], cols[y]
                for dx in range(bw):
                    if 0 <= x0 + dx < W:
                        row[x0 + dx] = c
            for dx in range(bw):
                if hp > 0:
                    fr.put(x0 + dx, PH - 1 - hp, (255, 255, 255), 0.8)
                    fr.put(x0 + dx, PH - 2 - hp, tip, 0.3)
                else:
                    fr.put(x0 + dx, PH - 1, tip, 0.35)


# --------------------------------------------------------------------------
# The info panel
# --------------------------------------------------------------------------


def seg(text, fg=WHITE, bold=False):
    return (text, fg, bold)


def width_of(segs):
    return sum(str_width(s[0]) for s in segs)


def fmt_temp(c, units, unit_label=False):
    v = c if units == "c" else c * 9 / 5 + 32
    s = f"{round(v)}\u00b0"
    return s + units.upper() if unit_label else s


def fmt_wind(kmh, units):
    return f"{round(kmh)} km/h" if units == "c" else f"{round(kmh * 0.621371)} mph"


def build_lines(st, now, W, cfg, big, days, footer, icon):
    units = cfg["units"]
    w = st.weather
    inner = min(W - 8, 64)
    L = [[]]

    if st.place:
        L.append([seg(st.place, WHITE, True)])
    else:
        L.append([seg("Finding you\u2026", DIM)])
    L.append([])

    hhmm = now.strftime("%I:%M").lstrip("0") if cfg["h12"] else now.strftime("%H:%M")
    ampm = now.strftime("%p") if cfg["h12"] else ""
    if big:
        scale = 2 if inner >= 36 else 1
        rows = big_text(hhmm, scale)
        for i, r in enumerate(rows):
            tail = ("  " + ampm) if (i == 4 and ampm) else ("    " if ampm else "")
            L.append([seg(r, WHITE, True), seg(tail, DIM, True)])
    else:
        L.append([seg(" ".join(hhmm) + (" " + ampm if ampm else ""), WHITE, True)])
    L.append([])
    L.append([seg(f"{now:%A}, {now.day} {now:%B} {now.year}", BLUE)])
    L.append([])

    if w:
        cur = w["current"]
        label, kind, _ = WMO.get(cur["weather_code"], ("Unknown", "cloud", 0))
        ikind = "night" if (kind in ("clear",) and not cur.get("is_day", 1)) else kind
        tc = cur["temperature_2m"]
        d = w["daily"]
        right = [
            [seg(fmt_temp(tc, units, True), temp_color(tc), True)],
            [seg(label, WHITE)],
            [seg(f"\u2191 {fmt_temp(d['temperature_2m_max'][0], units)}  \u2193 {fmt_temp(d['temperature_2m_min'][0], units)}", DIM)],
            [seg(f"feels {fmt_temp(cur['apparent_temperature'], units)} \u00b7 humidity {round(cur['relative_humidity_2m'])}%", DIM)],
            [seg(f"wind {fmt_wind(cur['wind_speed_10m'], units)}", DIM)],
        ]
        rw = max(width_of(r) for r in right)
        for r in right:
            r.append(seg(" " * (rw - width_of(r))))
        if icon:
            art = ICONS.get(ikind, ICONS["cloud"])
            for (a, col), r in zip(art, right):
                L.append([seg(a, col), seg("   ")] + r)
        else:
            L.extend(right[:2] + right[3:4])
    elif st.error:
        L.append([seg("Weather unavailable \u2014 retrying\u2026", DIM)])
        L.append([seg(st.error[:max(10, inner)], (200, 120, 120))])
    else:
        L.append([seg("Fetching weather\u2026", DIM)])

    if w and days:
        d = w["daily"]
        n = max(0, min(days, len(d["time"]), inner // 11))
        if n:
            L.append([])
            L.append([seg("\u2500" * (n * 11), BORDER)])
            r1, r2, r3 = [], [], []
            for i in range(n):
                dt = datetime.strptime(d["time"][i], "%Y-%m-%d")
                name = "Today" if i == 0 else dt.strftime("%a")
                _, k, _ = WMO.get(d["weather_code"][i], ("", "cloud", 0))
                g, gc = SMALL.get(k, SMALL["cloud"])
                r1.append(seg(name.center(11), DIM))
                r2.append(seg(g.center(11), gc, True))
                r3.append(seg(f"{fmt_temp(d['temperature_2m_max'][i], units)} {fmt_temp(d['temperature_2m_min'][i], units)}".center(11), WHITE))
            L.extend([r1, r2, r3])

    if footer:
        L.append([])
        if inner >= 40:
            L.append([seg("q quit \u00b7 u units \u00b7 t clock \u00b7 r refresh", (110, 120, 145))])
            L.append([seg("p processes \u00b7 m now playing \u00b7 v visualiser", (110, 120, 145))])
        else:
            L.append([seg("q quit \u00b7 p procs \u00b7 m music", (110, 120, 145))])
    L.append([])
    return L


# ---- process viewer panel

TW = 37  # inner width of the process panel


def ramp(f):
    """green -> yellow -> red"""
    if f < 0.5:
        return mix((110, 230, 160), (255, 220, 110), f * 2)
    return mix((255, 220, 110), (255, 110, 100), (f - 0.5) * 2)


def gauge(label, frac, text, width=27):
    n = int(round(max(0.0, min(1.0, frac)) * width))
    segs = [seg(f"{label:<4}", DIM)]
    for i in range(width):
        segs.append(seg("\u2588", ramp(i / (width - 1))) if i < n else seg("\u2591", (64, 72, 96)))
    segs.append(seg(f" {text:>5}", WHITE, True))
    return segs


def human(b):
    for unit in "BKMGT":
        if b < 1024 or unit == "T":
            return f"{b:.0f}{unit}" if unit in "BK" or b >= 100 else f"{b:.1f}{unit}"
        b /= 1024


def fmt_up(sec):
    m = int(sec // 60)
    d, h, m = m // 1440, m // 60 % 24, m % 60
    return f"{d}d {h}h" if d else f"{h}h {m}m" if h else f"{m}m"


TABS = (("procs", "PROCESSES"), ("media", "NOW PLAYING"))
DARK = (64, 72, 96)
HINT = (110, 120, 145)


def tab_bar(active):
    top, under = [], []
    for i, (key, label) in enumerate(TABS):
        if i:
            top.append(seg("   "))
            under.append(seg("   "))
        on = key == active
        top.append(seg(label, WHITE if on else DIM, on))
        under.append(seg(("\u2501" if on else "\u2500") * len(label), BLUE if on else DARK))
    return [top, under]


def shrink(lines, H):
    """Drop blank spacer lines from the middle until the panel fits the window."""
    lines = list(lines)
    while len(lines) + 2 > H:
        for i in range(len(lines) - 2, 0, -1):
            if not lines[i]:
                del lines[i]
                break
        else:
            break
    return lines


def build_proc_lines(sm, H, cfg):
    mem_used, mem_total = sm.mem
    n = min(8, H - 16)
    L = [[]] + tab_bar("procs")
    L.append([seg(f"load {sm.load[0]:.2f} \u00b7 up {fmt_up(sm.uptime)}".center(TW), DIM)])
    L.append([])
    L.append(gauge("CPU", sm.cpu / 100, f"{sm.cpu:.0f}%"))
    if n >= 2:
        hist = list(sm.hist)[-(TW - 4):]
        spark = [seg("    ", DIM)] + [seg(" " * (TW - 4 - len(hist)))]
        spark += [seg("\u2581\u2582\u2583\u2584\u2585\u2586\u2587\u2588"[min(7, int(v / 12.5))], ramp(v / 100)) for v in hist]
        L.append(spark)
    L.append(gauge("MEM", mem_used / max(1, mem_total), f"{100 * mem_used / max(1, mem_total):.0f}%"))
    if n >= 2:
        L.append([seg(f"    {human(mem_used)} of {human(mem_total)} used".ljust(TW), DIM)])
        L.append([])
        L.append([seg(f"{'PROCESS':<14} {'':<8} {'CPU%':>5} {'MEM':>7}", DIM)])
        by_mem = cfg.get("sort") == "mem"
        rows = sorted(sm.procs, key=(lambda r: (r[2], r[1])) if by_mem else (lambda r: (r[1], r[2])), reverse=True)
        for name, cpu, rss, _pid in rows[:n]:
            f = min(1.0, cpu / 100)
            fill = int(round(f * 8))
            L.append([
                seg(pad(clip(name, 14), 14) + " ", WHITE),
                seg("\u2588" * fill, ramp(f)),
                seg("\u00b7" * (8 - fill), DARK),
                seg(f" {cpu:5.1f}", ramp(f) if cpu >= 0.1 else DIM),
                seg(f" {human(rss):>7}", DIM),
            ])
        for _ in range(n - len(rows[:n])):
            L.append([seg(" " * TW)])
        L.append([])
        L.append([seg(f"sort: {'memory' if by_mem else 'cpu'} \u00b7 s change \u00b7 tab: switch".center(TW), HINT)])
    L.append([])
    return L


def fmt_time(sec):
    sec = int(sec)
    h, m, s_ = sec // 3600, sec // 60 % 60, sec % 60
    return f"{h}:{m:02d}:{s_:02d}" if h else f"{m}:{s_:02d}"


def scroll(text, width, t, animate):
    """Centre text that fits; scroll it (like a car stereo) when it's too long."""
    if str_width(text) <= width:
        return pad(text, width, "^")
    if not animate:
        return pad(clip(text, width), width, "^")
    loop = text + "   \u2022   "
    off = int(t * 5) % len(loop)
    out, w = [], 0
    for ch in (loop + loop)[off:]:
        c = cw(ch)
        if w + c > width:
            break
        out.append(ch)
        w += c
    return pad("".join(out), width)


def build_media_lines(mm, H, t):
    L = [[]] + tab_bar("media") + [[]]
    p, others = mm.current() if mm.ready and not mm.missing else (None, 0)
    if mm.missing:
        L += [[seg("playerctl isn't installed", WHITE, True)], [],
              [seg("Install it to see what's playing:", DIM)], [],
              [seg("pacman -S playerctl", WHITE)], [seg("dnf install playerctl", WHITE)]]
    elif not mm.ready:
        L += [[seg("Looking for a player\u2026", DIM)]]
    elif p is None:
        L += [[seg("Nothing is playing", WHITE, True)], [],
              [seg("Start music in Spotify, a browser,", DIM)],
              [seg("VLC, mpv or any media player.", DIM)]]
    else:
        playing = p["status"] == "Playing"
        icon = "\u25b6" if playing else "\u25ae\u25ae" if p["status"] == "Paused" else "\u25a0"
        col = BLUE if playing else DIM
        bars = "\u2581\u2582\u2583\u2584\u2585\u2586\u2587\u2588"
        eq = "".join(bars[int((math.sin(t * 5 + i * 1.9) * 0.5 + 0.5) * 7)] if playing else bars[0] for i in range(4))
        L.append([seg(f"{icon} ", col, True), seg(app_name(p["name"]), WHITE, True), seg("  "), seg(eq, col)])
        L.append([])
        L.append([seg(scroll(p["title"] or "Unknown title", TW, t, playing), WHITE, True)])
        if p["artist"]:
            L.append([seg(pad(clip(p["artist"], TW), TW, "^"), BLUE)])
        if p["album"]:
            L.append([seg(pad(clip(p["album"], TW), TW, "^"), DIM)])
        pos = mm.position(p)
        if pos is not None:
            L.append([])
            if p["len"]:
                total = p["len"] / 1e6
                fill = int(max(0.0, min(1.0, pos / total)) * (TW - 1))
                L.append([seg("\u2501" * fill, col), seg("\u25cf", WHITE), seg("\u2500" * (TW - 1 - fill), DARK)])
                right = fmt_time(total)
                L.append([seg(fmt_time(pos) + " " * (TW - len(fmt_time(pos)) - len(right)) + right, DIM)])
            else:
                L.append([seg(fmt_time(pos).center(TW), DIM)])
        if others:
            L.append([])
            L.append([seg(f"+{others} other player{'s' if others > 1 else ''}".center(TW), HINT)])
    L.append([])
    L.append([seg("tab: switch \u00b7 m close".center(TW), HINT)])
    L.append([])
    return shrink(L, H)


# ---- glass panels

OPTIONS = (
    (True, 5, True, True),
    (True, 0, True, True),
    (True, 0, False, True),
    (True, 0, True, False),
    (False, 0, True, False),
    (False, 0, False, False),
)


def draw_glass(fr, lines, x0, y0, pw, ph, border):
    W, H = fr.W, fr.H
    for r in range(2 * y0, 2 * (y0 + ph)):
        for x in range(max(0, x0), min(W, x0 + pw)):
            fr.put(x, r, (8, 10, 20), 0.55)
    fr.text(x0, y0, "\u256d" + "\u2500" * (pw - 2) + "\u256e", border)
    fr.text(x0, y0 + ph - 1, "\u2570" + "\u2500" * (pw - 2) + "\u256f", border)
    for y in range(y0 + 1, y0 + ph - 1):
        fr.text(x0, y, "\u2502", border)
        fr.text(x0 + pw - 1, y, "\u2502", border)
    for i, segs in enumerate(lines[: ph - 2]):
        x = x0 + (pw - width_of(segs)) // 2
        for text, fg, bold in segs:
            fr.text(x, y0 + 1 + i, text, fg, bold)
            x += str_width(text)


def draw_panels(fr, st, now, cfg, pulse, t=0.0):
    W, H = fr.W, fr.H
    border = mix(BORDER, (255, 255, 255), min(1.0, pulse) * 0.7)
    panels = []

    panel = cfg.get("panel")
    side = None
    if panel == "procs":
        side = build_proc_lines(st.sysmon, H, cfg)
    elif panel == "media":
        side = build_media_lines(st.media, H, t)
    avail = W - (TW + 8 + 2) if side else W

    main = None
    for opts in OPTIONS:
        lines = build_lines(st, now, avail, cfg, *opts)
        if len(lines) + 2 <= H and max(width_of(l) for l in lines) + 8 <= avail:
            main = lines
            break
    if main is None and not side:
        main = lines  # nothing fits: show the smallest layout and let it clip
    if main:
        panels.append(main)
    if side:
        panels.append(side)

    sizes = [(min(W, max(width_of(l) for l in p) + 8), min(H, len(p) + 2)) for p in panels]
    x = (W - (sum(w for w, _ in sizes) + 2 * (len(sizes) - 1))) // 2
    for p, (pw, ph) in zip(panels, sizes):
        draw_glass(fr, p, x, (H - ph) // 2, pw, ph, border)
        x += pw + 2


def compose(W, H, st, cfg, scene, t):
    now = local_now(st)
    hour = now.hour + now.minute / 60 + now.second / 3600
    kind, inten = "clear", 0
    if st.weather:
        _, kind, inten = WMO.get(st.weather["current"]["weather_code"], ("", "cloud", 0))

    bars, pulse = None, 0.0
    if cfg.get("viz") and (st.audio.demo or st.audio.proc is not None):
        bars = st.audio.bars(min(64, max(8, W // 3)))
        k = max(2, len(bars) // 8)
        pulse = sum(bars[:k]) / k

    fr = Frame(W, H)
    scene.draw(fr, hour, kind, inten, t, bars, pulse)
    draw_panels(fr, st, now, cfg, pulse, t)
    if cfg.get("viz") and st.audio.err and not st.audio.demo:
        msg = "\u266a " + st.audio.err
        fr.text((W - len(msg)) // 2, H - 1, msg, DIM)
    return fr


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------

CONF = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "dawn" / "config.json"


def load_config():
    cfg = {"city": None, "units": "c", "h12": False, "viz": True, "panel": "none", "sort": "cpu"}
    try:
        saved = json.loads(CONF.read_text())
        if "panel" not in saved and saved.get("procs"):  # settings saved by dawn 1.1
            saved["panel"] = "procs"
        saved.pop("procs", None)
        cfg.update(saved)
    except Exception:
        pass
    return cfg


def run(cfg):
    st = State()
    threading.Thread(target=worker, args=(st, cfg["city"]), daemon=True).start()
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    out = sys.stdout
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    threading.Thread(target=st.sysmon.loop, daemon=True).start()
    threading.Thread(target=st.media.loop, daemon=True).start()

    def apply():
        if cfg["panel"] == "procs":
            st.sysmon.enabled.set()
        else:
            st.sysmon.enabled.clear()
        if cfg["panel"] == "media":
            st.media.enabled.set()
        else:
            st.media.enabled.clear()
        if cfg["viz"]:
            st.audio.start()
        else:
            st.audio.stop()

    try:
        apply()
        tty.setcbreak(fd)
        out.write("\x1b[?1049h\x1b[?25l\x1b[?7l\x1b[2J")
        out.flush()
        size, scene, prev = None, None, None
        t0 = time.time()
        while True:
            frame_start = time.time()
            sz = shutil.get_terminal_size((80, 24))
            W, H = max(20, sz.columns), max(8, sz.lines)
            if (W, H) != size:
                size, scene, prev = (W, H), Scene(W, H), None
                out.write("\x1b[0m\x1b[2J")
            rows = compose(W, H, st, cfg, scene, time.time() - t0).rows()
            out.write("".join(r for i, r in enumerate(rows) if prev is None or prev[i] != r) + "\x1b[0m")
            out.flush()
            prev = rows
            wait = max(0.0, frame_start + FRAME_TIME - time.time())  # keep a steady pace
            if select.select([fd], [], [], wait)[0]:
                data = os.read(fd, 64)
                if data in (b"q", b"Q", b"\x1b"):
                    break
                if data == b"u":
                    cfg["units"] = "f" if cfg["units"] == "c" else "c"
                elif data == b"t":
                    cfg["h12"] = not cfg["h12"]
                elif data == b"r":
                    st.refresh.set()
                elif data == b"p":
                    cfg["panel"] = "none" if cfg["panel"] == "procs" else "procs"
                    apply()
                elif data == b"m":
                    cfg["panel"] = "none" if cfg["panel"] == "media" else "media"
                    apply()
                elif data == b"\t" and cfg["panel"] != "none":
                    cfg["panel"] = "media" if cfg["panel"] == "procs" else "procs"
                    apply()
                elif data == b"v":
                    cfg["viz"] = not cfg["viz"]
                    apply()
                elif data == b"s":
                    cfg["sort"] = "mem" if cfg.get("sort") != "mem" else "cpu"
    except KeyboardInterrupt:
        pass
    finally:
        st.stop.set()
        st.sysmon.stop.set()
        st.media.stop.set()
        st.audio.stop()
        termios.tcsetattr(fd, termios.TCSADRAIN, old)
        out.write("\x1b[0m\x1b[?7h\x1b[?25h\x1b[?1049l")
        out.flush()


def once(cfg):
    st = State()
    try:
        lat, lon, st.place = locate(cfg["city"])
        st.weather = fetch_weather(lat, lon)
        st.offset = st.weather.get("utc_offset_seconds")
    except Exception as e:
        st.error = str(e)
    if cfg["viz"]:
        st.audio.demo = True  # no sound in a still frame, so show a sample spectrum
    if cfg["panel"] == "procs":
        st.sysmon.update()
        time.sleep(0.5)
        st.sysmon.update()
    elif cfg["panel"] == "media":
        st.media.poll()
        if not st.media.players:  # nothing playing, so show a sample track
            st.media.missing = False
            st.media.players = [{"name": "spotify", "status": "Playing", "artist": "M83", "title": "Midnight City",
                                 "album": "Hurry Up, We're Dreaming", "pos": 83_000_000, "len": 243_000_000,
                                 "at": time.monotonic()}]
        st.media.ready = True
    sz = shutil.get_terminal_size((100, 32))
    scene = Scene(sz.columns, sz.lines)
    fr = compose(sz.columns, sz.lines, st, cfg, scene, 3.0)
    sys.stdout.write("\x1b[0m\n".join(fr.rows(absolute=False)) + "\x1b[0m\n")


def main(argv=None):
    p = argparse.ArgumentParser(
        prog="dawn",
        description="A beautiful weather, time & date dashboard for your terminal.",
        epilog="Keys: q quit \u00b7 u switch \u00b0C/\u00b0F \u00b7 t 12h/24h \u00b7 p processes \u00b7 m now playing \u00b7 tab switch \u00b7 v visualiser \u00b7 s sort \u00b7 r refresh",
    )
    p.add_argument("-c", "--city", help='show this place instead of auto-detecting, e.g. --city "Tokyo"')
    p.add_argument("-u", "--units", choices=["c", "f"], help="temperature units: c (Celsius) or f (Fahrenheit)")
    p.add_argument("--12h", dest="h12", action="store_const", const=True, help="use a 12-hour clock")
    p.add_argument("--24h", dest="h12", action="store_const", const=False, help="use a 24-hour clock")
    p.add_argument("--panel", choices=["procs", "media", "none"], help="side panel to open at start")
    p.add_argument("--procs", dest="panel", action="store_const", const="procs", help="open the process viewer at start")
    p.add_argument("--media", dest="panel", action="store_const", const="media", help="open the Now Playing tab at start")
    p.add_argument("--no-procs", dest="panel", action="store_const", const="none", help=argparse.SUPPRESS)
    p.add_argument("--viz", action=argparse.BooleanOptionalAction, help="show the audio visualiser")
    p.add_argument("--save", action="store_true", help="remember these options for next time")
    p.add_argument("--once", action="store_true", help="print one frame and exit (handy for screenshots)")
    p.add_argument("-v", "--version", action="version", version=f"dawn {__version__}")
    a = p.parse_args(argv)

    cfg = load_config()
    for k in ("city", "units", "h12", "panel", "viz"):
        if getattr(a, k) is not None:
            cfg[k] = getattr(a, k)

    if a.save:
        CONF.parent.mkdir(parents=True, exist_ok=True)
        CONF.write_text(json.dumps(cfg, indent=2))
        print(f"Saved your settings to {CONF}")

    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass

    if a.once:
        once(cfg)
        return 0
    if not (sys.stdin.isatty() and sys.stdout.isatty()):
        print("dawn needs to run in a terminal window.", file=sys.stderr)
        return 1
    run(cfg)
    return 0


if __name__ == "__main__":
    sys.exit(main())
