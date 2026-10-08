# Shared synth + mixing helpers for the original "alien funk" tracks.
import numpy as np, wave

SR = 44100
NOTES = {'C':0,'C#':1,'Db':1,'D':2,'D#':3,'Eb':3,'E':4,'F':5,'F#':6,'Gb':6,'G':7,'G#':8,'Ab':8,'A':9,'A#':10,'Bb':10,'B':11}

def freq(name):
    n, o = name[:-1], int(name[-1])
    return 440 * 2 ** ((12 * (o + 1) + NOTES[n] - 69) / 12)

class Mix:
    def __init__(self, seconds, seed=1):
        self.N = int(seconds * SR)
        self.L = np.zeros(self.N); self.R = np.zeros(self.N)
        self.rng = np.random.default_rng(seed)
    def add(self, sig, start, pan=0.0, gain=1.0):
        i = int(start * SR); j = min(self.N, i + len(sig))
        if j <= i or i < 0: return
        s = sig[: j - i] * gain
        self.L[i:j] += s * (1 - max(0, pan)); self.R[i:j] += s * (1 + min(0, pan))
    def save(self, path, fade=1.2):
        mix = np.stack([self.L, self.R], axis=1)
        f = int(fade * SR)
        mix[-f:] *= np.linspace(1, 0, f)[:, None]
        mix[:int(0.01 * SR)] *= np.linspace(0, 1, int(0.01 * SR))[:, None]
        # gentle glue: soft clip, then normalize
        mix = np.tanh(mix / (np.max(np.abs(mix)) * 0.55)) 
        mix /= np.max(np.abs(mix)) * 1.06
        with wave.open(path, 'wb') as w:
            w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
            w.writeframes((mix * 32767).astype(np.int16).tobytes())

def t_of(dur):
    return np.arange(int(dur * SR)) / SR

def onepole(x, cutoff):
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.empty_like(x); prev = 0.0
    for k in range(len(x)):
        prev = (1 - a) * x[k] + a * prev
        y[k] = prev
    return y

def svf(x, cutoffs, q=0.25, mode='lp'):
    # State-variable filter with a per-sample cutoff (for wah / sweeps).
    low = band = 0.0
    y = np.empty_like(x)
    cut = np.broadcast_to(cutoffs, x.shape)
    for k in range(len(x)):
        f = 2 * np.sin(np.pi * min(cut[k], SR / 6) / SR)
        high = x[k] - low - q * band
        band += f * high
        low += f * band
        y[k] = low if mode == 'lp' else band
    return y

def saw(f, t, harmonics=14):
    out = np.zeros_like(t)
    for h in range(1, harmonics + 1):
        if f * h > SR / 2.2: break
        out += np.sin(2 * np.pi * f * h * t) / h
    return out

def square(f, t, harmonics=13):
    out = np.zeros_like(t)
    for h in range(1, harmonics + 1, 2):
        if f * h > SR / 2.2: break
        out += np.sin(2 * np.pi * f * h * t) / h
    return out

# Drums --------------------------------------------------------------------
def kick(rng, punch=1.0):
    t = t_of(0.35)
    f = 140 * np.exp(-t * 30) + 45
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 9)
    click = rng.uniform(-1, 1, len(t)) * np.exp(-t * 400) * 0.3
    return (body + click) * punch

def snare(rng, ghost=False):
    t = t_of(0.22)
    noise = onepole(rng.uniform(-1, 1, len(t)), 7000)
    tone = np.sin(2 * np.pi * 185 * t) * np.exp(-t * 30)
    s = (noise * 0.9 * np.exp(-t * 16) + tone * 0.6)
    return s * (0.25 if ghost else 1.0)

def clap(rng):
    t = t_of(0.25)
    noise = rng.uniform(-1, 1, len(t))
    env = np.zeros_like(t)
    for d in (0, 0.011, 0.022):
        env += (t >= d) * np.exp(-np.maximum(0, t - d) * 60)
    env += (t >= 0.03) * np.exp(-np.maximum(0, t - 0.03) * 14) * 0.6
    return svf(noise, 1500, 0.6, 'bp') * env * 2.2

def hat(rng, open_=False):
    n = int((0.25 if open_ else 0.05) * SR)
    noise = np.diff(np.concatenate([[0], rng.uniform(-1, 1, n)]))
    return noise * np.exp(-np.arange(n) / SR * (12 if open_ else 75))

# Instruments ----------------------------------------------------------------
_cache = {}
def cached(key, make):
    if key not in _cache:
        _cache[key] = make()
    return _cache[key]

def slap_bass(f, dur, pop=False):
    def make():
        t = t_of(dur)
        sig = saw(f, t, 10) + 0.6 * np.sin(2 * np.pi * f * t)
        env = np.minimum(1, t / 0.003) * np.exp(-t * (9 if not pop else 14))
        cut = 300 + 2600 * np.exp(-t * (25 if not pop else 12))
        out = svf(sig * env, cut, 0.5)
        if pop:
            out += np.sin(2 * np.pi * f * 2 * t) * np.exp(-t * 30) * 0.6
        rel = np.minimum(1, (dur - t) / 0.02)
        return out * np.maximum(rel, 0)
    return cached(('slap', round(f, 2), round(dur, 3), pop), make)

def sub_bass(f_from, f_to, dur):
    def make():
        t = t_of(dur)
        glide = f_to + (f_from - f_to) * np.exp(-t * 18)
        ph = 2 * np.pi * np.cumsum(glide) / SR
        sig = np.sin(ph) + 0.25 * np.sin(2 * ph)
        env = np.minimum(1, t / 0.01) * np.minimum(1, (dur - t) / 0.04)
        return np.tanh(sig * 1.4) * np.maximum(env, 0)
    return cached(('sub', round(f_from, 2), round(f_to, 2), round(dur, 3)), make)

def octave_bass(f, dur):
    def make():
        t = t_of(dur)
        sig = saw(f, t, 12)
        env = np.minimum(1, t / 0.004) * np.exp(-t * 5)
        rel = np.minimum(1, (dur - t) / 0.02)
        return onepole(sig * env, 1200) * np.maximum(rel, 0)
    return cached(('oct', round(f, 2), round(dur, 3)), make)

def wah_clav(freqs, dur, sweep_up=True):
    def make():
        t = t_of(dur)
        sig = np.zeros_like(t)
        for f in freqs:
            sig += square(f, t, 15) * 0.6 + saw(f, t, 8) * 0.4
        env = np.minimum(1, t / 0.002) * np.exp(-t * 11)
        cut = (500 + 2400 * (1 - np.exp(-t * 14))) if sweep_up else (2800 * np.exp(-t * 10) + 400)
        return svf(sig * env / len(freqs), cut, 0.18, 'bp') * 2.2
    return cached(('clav', tuple(round(f, 1) for f in freqs), round(dur, 3), sweep_up), make)

def brass_stab(freqs, dur):
    def make():
        t = t_of(dur)
        sig = np.zeros_like(t)
        for f in freqs:
            for d in (-0.004, 0.004):
                sig += saw(f * (1 + d), t, 12)
        env = np.minimum(1, t / 0.015) * np.exp(-t * 6)
        cut = 900 + 3000 * np.exp(-t * 8)
        return svf(sig * env / (2 * len(freqs)), cut, 0.6)
    return cached(('brass', tuple(round(f, 1) for f in freqs), round(dur, 3)), make)

def string_pad(freqs, dur):
    t = t_of(dur)
    sig = np.zeros_like(t)
    for f in freqs:
        for d in (-0.007, 0.0, 0.007):
            sig += saw(f * (1 + d), t, 6)
    env = np.minimum(1, t / 0.25) * np.minimum(1, (dur - t) / 0.3)
    return onepole(sig * np.maximum(env, 0) / (3 * len(freqs)), 2200)

def glide_voice(segs, beat, kind='theremin', glide=0.07, vibrato=0.012):
    # One continuous voice gliding between notes. segs = [(note or 'R', beats)]
    parts = [(None if n == 'R' else freq(n), d * beat) for n, d in segs]
    total = sum(d for _, d in parts)
    n = int((total + 0.3) * SR)
    t = np.arange(n) / SR
    fc = np.zeros(n); amp = np.zeros(n)
    k = 0; last = None
    for f, d in parts:
        m = int(d * SR)
        if f is None:
            fc[k:k + m] = last or 440
        else:
            g = min(int(glide * SR), m)
            seg = np.full(m, f)
            seg[:g] = np.linspace(last or f, f, g)
            fc[k:k + m] = seg; amp[k:k + m] = 1; last = f
        k += m
    fc[k:] = last or 440
    vib = 1 + vibrato * np.sin(2 * np.pi * 5.6 * t) * np.minimum(1, t / 0.3)
    ph = 2 * np.pi * np.cumsum(fc * vib) / SR
    w = int(0.03 * SR)
    smooth = np.convolve(amp, np.ones(w) / w, mode='same')
    if kind == 'theremin':
        sig = np.sin(ph) + 0.15 * np.sin(2 * ph)
    elif kind == 'whistle':  # G-funk style "Moog whistle"
        sig = np.sin(ph) + 0.04 * np.sin(3 * ph)
    else:  # 'robot': buzzy square through a talk-box-ish band
        raw = np.sign(np.sin(ph)) * 0.5 + np.sin(ph) * 0.5
        sig = svf(raw, 900 + 700 * np.sin(2 * np.pi * 3 * t) ** 2, 0.3, 'bp') * 0.5
    return sig * smooth

def zap(start_f=2600, end_f=150, dur=0.4):
    t = t_of(dur)
    f = end_f + (start_f - end_f) * np.exp(-t * 10)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 5)

def ufo_wobble(dur, base=420):
    t = t_of(dur)
    f = base + 160 * np.sin(2 * np.pi * 7 * t) + 300 * t / dur
    sig = np.sin(2 * np.pi * np.cumsum(f) / SR)
    env = np.minimum(1, t / 0.4) * np.minimum(1, (dur - t) / 0.4)
    return sig * env

def chirp(rng, dur=0.12):
    t = t_of(dur)
    f0 = rng.uniform(900, 2200); f1 = rng.uniform(600, 3000)
    f = f0 + (f1 - f0) * t / dur
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * t / dur)

# Sci-fi / abduction sounds ---------------------------------------------------
def fm_bell(f, dur, ratio=3.5, index=2.5):
    # Glassy alien bell (FM synthesis).
    def make():
        t = t_of(dur)
        mod = np.sin(2 * np.pi * f * ratio * t) * index * np.exp(-t * 4)
        return np.sin(2 * np.pi * f * t + mod) * np.exp(-t * 3.5) * np.minimum(1, t / 0.002)
    return cached(('bell', round(f, 2), round(dur, 3), ratio, index), make)

def drone(f, dur, wobble=0.3):
    # Deep tractor-beam hum: detuned saws through a slowly breathing filter.
    t = t_of(dur)
    sig = np.zeros_like(t)
    for d in (-0.01, 0.0, 0.01):
        sig += saw(f * (1 + d), t, 8)
    breathe = 350 + 250 * (0.5 + 0.5 * np.sin(2 * np.pi * wobble * t))
    env = np.minimum(1, t / 1.0) * np.minimum(1, (dur - t) / 1.0)
    out = svf(sig / 3, breathe, 0.35)
    return out * np.maximum(env, 0)

def riser(rng, dur, f_from=300, f_to=6000):
    # Noise sweep that rises into a drop (the beam powering up).
    t = t_of(dur)
    noise = rng.uniform(-1, 1, len(t))
    cut = f_from * (f_to / f_from) ** (t / dur)
    env = (t / dur) ** 2
    tone = np.sin(2 * np.pi * np.cumsum(cut * 0.25) / SR) * 0.3
    return (svf(noise, cut, 0.3, 'bp') * 1.5 + tone) * env

def siren(dur, low=500, high=1100, rate=1.2):
    t = t_of(dur)
    f = low + (high - low) * (0.5 + 0.5 * np.sin(2 * np.pi * rate * t - np.pi / 2))
    ph = 2 * np.pi * np.cumsum(f) / SR
    sig = np.sign(np.sin(ph)) * 0.4 + np.sin(ph) * 0.6
    env = np.minimum(1, t / 0.05) * np.minimum(1, (dur - t) / 0.1)
    return onepole(sig, 2500) * np.maximum(env, 0)

def alien_voice(rng, dur):
    # Garbled alien "chatter": a buzz through jumping vowel formants.
    t = t_of(dur)
    pitch = 180 + 90 * np.sin(2 * np.pi * 3.3 * t) + rng.uniform(-30, 30)
    ph = 2 * np.pi * np.cumsum(pitch) / SR
    buzz = np.sign(np.sin(ph)) * 0.5 + np.sin(ph) * 0.5
    steps = max(1, int(dur / 0.07))
    f1 = np.repeat(rng.uniform(300, 900, steps), int(np.ceil(len(t) / steps)))[: len(t)]
    f2 = np.repeat(rng.uniform(1000, 2600, steps), int(np.ceil(len(t) / steps)))[: len(t)]
    out = svf(buzz, f1, 0.2, 'bp') + 0.6 * svf(buzz, f2, 0.2, 'bp')
    return out * np.sin(np.pi * t / dur) * 0.6

def pulse_bass(f, dur):
    # Tight, dark 16th-note synth bass (synthwave ostinato).
    def make():
        t = t_of(dur)
        sig = saw(f, t, 10) + square(f * 0.5, t, 5) * 0.5
        env = np.minimum(1, t / 0.003) * np.exp(-t * 14)
        cut = 250 + 1500 * np.exp(-t * 30)
        return svf(sig * env, cut, 0.45)
    return cached(('pulse', round(f, 2), round(dur, 3)), make)
