# An original "alien UFO invasion" track: eerie theremin-style lead, pulsing
# synth bass, dark pad, 16th-note arpeggio, drums and laser zaps.
# D minor with a Phrygian (Eb) twist, 120 BPM, 4/4, 32 bars (~64 s), loops.
import numpy as np, wave
SR = 44100
BPM = 120
BEAT = 60 / BPM
rng = np.random.default_rng(11)
NOTES = {'C':0,'C#':1,'Db':1,'D':2,'D#':3,'Eb':3,'E':4,'F':5,'F#':6,'Gb':6,'G':7,'G#':8,'Ab':8,'A':9,'A#':10,'Bb':10,'B':11}
def freq(name):
    n, o = name[:-1], int(name[-1])
    return 440 * 2 ** ((12 * (o + 1) + NOTES[n] - 69) / 12)

# 8-bar progression, played 4 times (the lead joins on the 2nd pass)
PROG = [['D3','F3','A3'], ['D3','F3','A3'], ['Eb3','G3','Bb3'], ['Eb3','G3','Bb3'],
        ['Bb2','D3','F3'], ['C3','Eb3','G3'], ['A2','C#3','E3'], ['A2','C#3','E3']]
BASS = ['D2','D2','Eb2','Eb2','Bb1','C2','A1','A1']
# Theremin melody, (note, beats) per bar
LEAD = [
 [('A4',2),('D5',1),('F5',1)],
 [('E5',3),('R',1)],
 [('G4',2),('Bb4',1),('Eb5',1)],
 [('D5',3),('R',1)],
 [('F5',1.5),('D5',0.5),('Bb4',2)],
 [('C5',1),('Eb5',1),('G5',2)],
 [('A5',2),('G5',1),('E5',1)],
 [('C#5',2),('A4',2)],
]
bars = 32
total = bars * 4 * BEAT + 2
N = int(total * SR)
L = np.zeros(N); R = np.zeros(N)
def add(sig, start, pan=0.0, gain=1.0):
    i = int(start * SR); j = min(N, i + len(sig))
    if j <= i: return
    s = sig[: j - i] * gain
    L[i:j] += s * (1 - max(0, pan)); R[i:j] += s * (1 + min(0, pan))

def lowpass(x, cutoff):
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.zeros_like(x); prev = 0.0
    for k in range(len(x)):
        prev = (1 - a) * x[k] + a * prev
        y[k] = prev
    return y

def saw(f, t, harmonics=12):
    out = np.zeros_like(t)
    for h in range(1, harmonics + 1):
        out += np.sin(2 * np.pi * f * h * t) / h
    return out

bass_cache = {}
def bass_note(f, dur):
    key = (round(f, 2), round(dur, 3))
    if key not in bass_cache:
        t = np.arange(int(dur * SR)) / SR
        sig = saw(f, t, 10) + 0.5 * np.sin(2 * np.pi * f / 2 * t)
        env = np.minimum(1, t / 0.005) * np.exp(-t * 6)
        bass_cache[key] = lowpass(sig * env, 900)
    return bass_cache[key]

def pad(freqs, dur):
    t = np.arange(int(dur * SR)) / SR
    sig = np.zeros_like(t)
    for f in freqs:
        for d in (-0.006, 0.0, 0.006):
            sig += np.sin(2 * np.pi * f * (1 + d) * t) + 0.25 * np.sin(2 * np.pi * 2 * f * (1 + d) * t)
    tremolo = 0.75 + 0.25 * np.sin(2 * np.pi * 0.5 * t)
    env = np.minimum(1, t / 0.8) * np.minimum(1, (dur - t) / 0.5)
    return sig * tremolo * env / (len(freqs) * 3)

def blip(f, dur=0.11):
    t = np.arange(int(dur * SR)) / SR
    sq = np.sign(np.sin(2 * np.pi * f * t)) * 0.6 + np.sin(2 * np.pi * f * t) * 0.4
    return sq * np.exp(-t * 28)

def kick():
    t = np.arange(int(0.3 * SR)) / SR
    f = 120 * np.exp(-t * 25) + 42
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 10)

def snare():
    t = np.arange(int(0.2 * SR)) / SR
    noise = rng.uniform(-1, 1, len(t))
    return (noise * 0.8 + np.sin(2 * np.pi * 190 * t) * 0.4) * np.exp(-t * 18)

def hat():
    n = int(0.05 * SR)
    noise = np.diff(np.concatenate([[0], rng.uniform(-1, 1, n)]))
    return noise * np.exp(-np.arange(n) / SR * 70)

def zap(start_f=2400, end_f=180, dur=0.45):
    t = np.arange(int(dur * SR)) / SR
    f = end_f + (start_f - end_f) * np.exp(-t * 9)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 5)

def theremin(notes, start):
    # one continuous voice gliding between notes, with vibrato
    pos = start
    segs = []
    for name, d in notes:
        segs.append((None if name == 'R' else freq(name), d * BEAT))
    total_len = sum(d for _, d in segs)
    n = int((total_len + 0.3) * SR)
    t = np.arange(n) / SR
    fcurve = np.zeros(n); amp = np.zeros(n)
    k = 0; last = None
    for f, d in segs:
        m = int(d * SR)
        if f is None:
            amp[k:k + m] = 0
            fcurve[k:k + m] = last or 440
        else:
            glide = int(0.07 * SR)
            start_f = last if last else f
            seg = np.full(m, f)
            g = min(glide, m)
            seg[:g] = np.linspace(start_f, f, g)
            fcurve[k:k + m] = seg
            amp[k:k + m] = 1
            last = f
        k += m
    fcurve[k:] = last or 440
    vib = 1 + 0.012 * np.sin(2 * np.pi * 5.5 * t) * np.minimum(1, t / 0.4)
    phase = 2 * np.pi * np.cumsum(fcurve * vib) / SR
    # smooth the amplitude so notes swell in and out
    smooth = np.convolve(amp, np.ones(int(0.04 * SR)) / int(0.04 * SR), mode='same')
    sig = (np.sin(phase) + 0.15 * np.sin(2 * phase)) * smooth
    add(sig, start, -0.1, 0.22)

for b in range(bars):
    i = b % 8
    bar_start = b * 4 * BEAT
    section = b // 8  # 0 intro, 1 lead, 2 lead + full drums, 3 lead + octave
    add(pad([freq(n) * 2 for n in PROG[i]], 4 * BEAT + 0.4), bar_start, 0, 0.16)
    # Pulsing bass in 8ths
    for e in range(8):
        f = freq(BASS[i]) * (2 if e in (3, 7) else 1)
        add(bass_note(f, BEAT / 2), bar_start + e * BEAT / 2, 0, 0.32 if section else 0.22)
    # Spooky arpeggio in 16ths
    chord = [freq(n) * 4 for n in PROG[i]]
    for s in range(16):
        f = chord[[0, 1, 2, 1][s % 4]] * (2 if s % 8 == 7 else 1)
        add(blip(f), bar_start + s * BEAT / 4, 0.45 if s % 2 else -0.45, 0.07 if section else 0.05)
    # Drums: building up after the intro
    for beat in range(4):
        if section >= 1 or beat in (0, 2):
            add(kick(), bar_start + beat * BEAT, 0, 0.5)
        if section >= 1 and beat in (1, 3):
            add(snare(), bar_start + beat * BEAT, 0.05, 0.22)
    if section >= 2:
        for e in range(8):
            add(hat(), bar_start + e * BEAT / 2, 0.3, 0.1 if e % 2 else 0.06)
    # Laser zaps at the end of every 2 bars
    if b % 2 == 1:
        add(zap(), bar_start + 3.5 * BEAT, 0.6 if b % 4 == 1 else -0.6, 0.18)
    # Theremin lead from the second pass on
    if section >= 1 and b % 1 == 0:
        theremin(LEAD[i], bar_start)
        if section == 3:
            theremin([(n[:-1] + str(int(n[-1]) + 1) if n != 'R' else 'R', d) for n, d in LEAD[i]], bar_start + 0.01)

mix = np.stack([L, R], axis=1)
fade = int(1.5 * SR)
mix[-fade:] *= np.linspace(1, 0, fade)[:, None]
mix /= np.max(np.abs(mix)) * 1.08
with wave.open('alien_invasion.wav', 'wb') as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((mix * 32767).astype(np.int16).tobytes())
print('seconds', total)
