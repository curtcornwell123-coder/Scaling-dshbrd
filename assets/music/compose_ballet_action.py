# An original ballet-style "action" waltz: celesta/music-box melody,
# pizzicato strings, soft string pad, light percussion. E minor, 3/4.
import numpy as np, wave
SR = 44100
BPM = 168
BEAT = 60 / BPM
rng = np.random.default_rng(7)

NOTES = {'C':0,'C#':1,'D':2,'D#':3,'E':4,'F':5,'F#':6,'G':7,'G#':8,'A':9,'A#':10,'B':11}
def freq(name):
    n, o = name[:-1], int(name[-1])
    midi = 12 * (o + 1) + NOTES[n]
    return 440 * 2 ** ((midi - 69) / 12)

melody_A = [
 [('B4',1),('E5',.5),('D#5',.5),('E5',1)],
 [('G5',1),('F#5',.5),('E5',.5),('B4',1)],
 [('C5',1),('E5',.5),('D#5',.5),('E5',1)],
 [('A5',1.5),('G5',.5),('E5',1)],
 [('F#5',1),('D#5',.5),('E5',.5),('F#5',1)],
 [('A5',1),('G5',.5),('F#5',.5),('D#5',1)],
 [('E5',.5),('F#5',.5),('G5',.5),('A5',.5),('B5',1)],
 [('E6',1.5),('R',1.5)],
 [('E5',1),('G5',.5),('F#5',.5),('G5',1)],
 [('C6',1),('B5',.5),('A5',.5),('G5',1)],
 [('A5',1),('C6',.5),('B5',.5),('A5',1)],
 [('E5',1.5),('F#5',.5),('G5',1)],
 [('A5',1),('F#5',.5),('E5',.5),('C5',1)],
 [('D#5',1),('F#5',1),('A5',1)],
 [('G5',.5),('F#5',.5),('E5',.5),('D#5',.5),('E5',1)],
 [('E5',1),('B4',1),('E4',1)],
]
chords_A = ['Em','Em','Am','Am','B7','B7','Em','Em','C','C','Am','Am','F#m7b5','B7','Em','Em']
melody_B = [
 [('D5',.5),('G5',.5),('B5',1),('G5',1)],
 [('A5',.5),('B5',.5),('C6',1),('B5',1)],
 [('A5',1),('F#5',.5),('A5',.5),('D6',1)],
 [('C6',1),('B5',1),('A5',1)],
 [('G5',.5),('E5',.5),('G5',1),('C6',1)],
 [('B5',.5),('A5',.5),('G5',1),('E5',1)],
 [('F#5',.5),('G5',.5),('A5',.5),('B5',.5),('C6',.5),('D#6',.5)],
 [('B5',2),('R',1)],
]
chords_B = ['G','G','D','D','C','C','B7','B7']
CHORDS = {
 'Em':['E3','G3','B3'], 'Am':['A2','C4','E4'], 'B7':['B2','D#4','A3'], 'C':['C3','E3','G3'],
 'F#m7b5':['F#2','A3','C4'], 'G':['G2','B3','D4'], 'D':['D3','F#3','A3'],
}
song = []  # (melody bar, chord, octave_up)
for i in range(16): song.append((melody_A[i], chords_A[i], False))
for i in range(8): song.append((melody_B[i], chords_B[i], False))
for i in range(16): song.append((melody_A[i], chords_A[i], True))
bars = len(song)
total = bars * 3 * BEAT + 1.5
N = int(total * SR)
L = np.zeros(N); R = np.zeros(N)

def add(sig, start, pan=0.0, gain=1.0):
    i = int(start * SR)
    j = min(N, i + len(sig))
    if j <= i: return
    s = sig[: j - i] * gain
    L[i:j] += s * (1 - max(0, pan))
    R[i:j] += s * (1 + min(0, pan))

def celesta(f, dur):
    t = np.arange(int((dur + 1.2) * SR)) / SR
    env = np.exp(-t * 3.2) * np.minimum(1, t / 0.003)
    sig = (np.sin(2*np.pi*f*t) + 0.45*np.sin(2*np.pi*2*f*t)*np.exp(-t*6) + 0.18*np.sin(2*np.pi*3*f*t)*np.exp(-t*9)
           + 0.12*np.sin(2*np.pi*4.17*f*t)*np.exp(-t*12))
    return sig * env

def pluck(f, dur, bright=0.5):
    # Karplus-Strong plucked string
    n = int((dur + 0.4) * SR)
    period = int(SR / f)
    buf = rng.uniform(-1, 1, period)
    out = np.zeros(n)
    for k in range(n):
        out[k] = buf[k % period]
        nxt = buf[(k + 1) % period]
        buf[k % period] = 0.5 * (buf[k % period] + nxt) * (0.994 - 0.01 * (1 - bright))
    env = np.minimum(1, np.arange(n) / (0.002 * SR)) * np.exp(-np.arange(n) / SR * 5)
    return out * env

def pad(freqs, dur):
    t = np.arange(int(dur * SR)) / SR
    sig = np.zeros_like(t)
    for f in freqs:
        for d in (-0.003, 0.003):
            ff = f * (1 + d)
            sig += np.sin(2*np.pi*ff*t) + 0.3*np.sin(2*np.pi*2*ff*t)
    env = np.minimum(1, t / 0.4) * np.minimum(1, (dur - t) / 0.4)
    return sig * env / (len(freqs) * 2)

def kick(dur=0.35):
    t = np.arange(int(dur * SR)) / SR
    f = 110 * np.exp(-t * 18) + 45
    return np.sin(2*np.pi*np.cumsum(f)/SR) * np.exp(-t * 9)

def shaker(dur=0.08):
    n = int(dur * SR)
    noise = rng.uniform(-1, 1, n)
    noise = np.diff(np.concatenate([[0], noise]))  # crude high-pass
    return noise * np.exp(-np.arange(n) / SR * 45)

pluck_cache = {}
def cached_pluck(name, dur, bright):
    key = (name, round(dur, 3), bright)
    if key not in pluck_cache:
        pluck_cache[key] = pluck(freq(name), dur, bright)
    return pluck_cache[key]

for b, (mel, chord, up) in enumerate(song):
    bar_start = b * 3 * BEAT
    notes = CHORDS[chord]
    # Pizzicato: bass on 1, chord on 2 and 3 (a waltz "oom-pah-pah")
    add(cached_pluck(notes[0], BEAT, 0.6), bar_start, -0.2, 0.55)
    for beat in (1, 2):
        for k, nn in enumerate(notes[1:]):
            add(cached_pluck(nn, BEAT * 0.8, 0.8), bar_start + beat * BEAT + k * 0.006, 0.25, 0.22)
    # Soft string pad under it all
    add(pad([freq(n) * 2 for n in notes], 3 * BEAT + 0.3), bar_start, 0.0, 0.10)
    # Percussion for drive: kick on 1, shaker on every eighth
    add(kick(), bar_start, 0, 0.45)
    for e in range(6):
        add(shaker(), bar_start + e * BEAT / 2, 0.4 if e % 2 else -0.4, 0.10 if e % 2 else 0.06)
    # Celesta melody (an octave of sparkle added in the last section)
    pos = bar_start
    for name, d in mel:
        dur = d * BEAT
        if name != 'R':
            f = freq(name)
            add(celesta(f, dur), pos, 0.1, 0.32)
            if up:
                add(celesta(f * 2, dur), pos + 0.004, -0.15, 0.14)
        pos += dur

mix = np.stack([L, R], axis=1)
# gentle tail fade so it loops cleanly
fade = int(1.2 * SR)
mix[-fade:] *= np.linspace(1, 0, fade)[:, None]
mix /= np.max(np.abs(mix)) * 1.08
pcm = (mix * 32767).astype(np.int16)
with wave.open('ballet_action.wav', 'wb') as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes(pcm.tobytes())
print('seconds', total)
