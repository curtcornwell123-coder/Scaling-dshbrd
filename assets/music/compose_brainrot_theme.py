# "Brainrot Heist" main theme: an original, upbeat, bouncy track for normal
# play. Marimba-style lead, plucky chords, bouncy bass, claps and hats.
# F major, 116 BPM, 4/4, 32 bars (~66 s), loops.
import numpy as np, wave
SR = 44100
BPM = 116
BEAT = 60 / BPM
rng = np.random.default_rng(23)
NOTES = {'C':0,'C#':1,'Db':1,'D':2,'D#':3,'Eb':3,'E':4,'F':5,'F#':6,'G':7,'G#':8,'A':9,'Bb':10,'B':11}
def freq(name):
    n, o = name[:-1], int(name[-1])
    return 440 * 2 ** ((12 * (o + 1) + NOTES[n] - 69) / 12)

# I - vi - IV - V style progression with a cheeky bVII
PROG_A = [['F3','A3','C4'], ['D3','F3','A3'], ['Bb2','D3','F3'], ['C3','E3','G3']]
PROG_B = [['Bb2','D3','F3'], ['C3','E3','G3'], ['A2','C3','E3'], ['D3','F3','A3'],
          ['Bb2','D3','F3'], ['C3','E3','G3'], ['Eb3','G3','Bb3'], ['C3','E3','G3']]
BASS_A = ['F2','D2','Bb1','C2']
BASS_B = ['Bb1','C2','A1','D2','Bb1','C2','Eb2','C2']
MEL_A = [
 [('C5',.5),('A4',.5),('C5',.5),('F5',1),('E5',.5),('D5',.5),('C5',.5)],
 [('D5',.5),('F5',.5),('A5',1),('G5',.5),('F5',.5),('D5',1)],
 [('Bb4',.5),('D5',.5),('F5',.5),('Bb5',1),('A5',.5),('G5',.5),('F5',.5)],
 [('E5',.5),('G5',.5),('C6',1.5),('R',.5),('C5',.5),('E5',.5)],
 [('F5',.5),('E5',.5),('F5',.5),('A5',1),('G5',.5),('F5',.5),('E5',.5)],
 [('D5',1),('F5',.5),('D5',.5),('A4',1),('C5',1)],
 [('D5',.5),('F5',.5),('Bb5',.5),('A5',.5),('G5',.5),('F5',.5),('D5',1)],
 [('E5',.5),('D5',.5),('C5',.5),('E5',.5),('F5',2)],
]
MEL_B = [
 [('D5',1),('F5',1),('Bb5',1),('A5',1)],
 [('G5',1.5),('E5',.5),('C5',2)],
 [('A5',.5),('G5',.5),('E5',.5),('C5',.5),('E5',1),('A5',1)],
 [('F5',1.5),('D5',.5),('A4',2)],
 [('Bb4',.5),('D5',.5),('F5',.5),('D5',.5),('Bb5',1),('A5',1)],
 [('G5',.5),('A5',.5),('G5',.5),('E5',.5),('C5',2)],
 [('Eb5',.5),('G5',.5),('Bb5',1),('G5',.5),('Eb5',.5),('Bb4',1)],
 [('C5',.5),('E5',.5),('G5',.5),('Bb5',.5),('C6',2)],
]
song = []
for rep in range(2):
    for i in range(8):
        song.append(('A', PROG_A[i % 4], BASS_A[i % 4], MEL_A[i], rep))
for i in range(8):
    song.append(('B', PROG_B[i], BASS_B[i], MEL_B[i], 2))
for i in range(8):
    song.append(('A', PROG_A[i % 4], BASS_A[i % 4], MEL_A[i], 3))
bars = len(song)
total = bars * 4 * BEAT + 1.5
N = int(total * SR)
L = np.zeros(N); R = np.zeros(N)
def add(sig, start, pan=0.0, gain=1.0):
    i = int(start * SR); j = min(N, i + len(sig))
    if j <= i: return
    s = sig[: j - i] * gain
    L[i:j] += s * (1 - max(0, pan)); R[i:j] += s * (1 + min(0, pan))

cache = {}
def marimba(f, dur):
    key = ('m', round(f, 2))
    if key not in cache:
        t = np.arange(int(0.9 * SR)) / SR
        sig = np.sin(2*np.pi*f*t) + 0.35*np.sin(2*np.pi*4*f*t)*np.exp(-t*25) + 0.12*np.sin(2*np.pi*10*f*t)*np.exp(-t*60)
        cache[key] = sig * np.exp(-t * 7) * np.minimum(1, t / 0.002)
    return cache[key]

def pluck_chord(freqs):
    key = ('c', tuple(round(f, 2) for f in freqs))
    if key not in cache:
        t = np.arange(int(0.3 * SR)) / SR
        sig = np.zeros_like(t)
        for f in freqs:
            sig += np.sign(np.sin(2*np.pi*f*t)) * 0.3 + np.sin(2*np.pi*f*t) * 0.7
        cache[key] = sig * np.exp(-t * 14) / len(freqs)
    return cache[key]

def bass(f):
    key = ('b', round(f, 2))
    if key not in cache:
        t = np.arange(int(0.45 * SR)) / SR
        sig = np.sin(2*np.pi*f*t) + 0.4*np.sin(2*np.pi*2*f*t) + 0.15*np.sin(2*np.pi*3*f*t)
        cache[key] = sig * np.exp(-t * 6) * np.minimum(1, t / 0.004)
    return cache[key]

def kick():
    t = np.arange(int(0.3 * SR)) / SR
    f = 130 * np.exp(-t * 28) + 48
    return np.sin(2*np.pi*np.cumsum(f)/SR) * np.exp(-t * 11)

def clap():
    t = np.arange(int(0.18 * SR)) / SR
    noise = rng.uniform(-1, 1, len(t))
    env = np.exp(-t * 22) + 0.6 * np.exp(-np.maximum(0, t - 0.012) * 30) * (t > 0.012)
    return noise * env * 0.7

def hat(open_=False):
    n = int((0.12 if open_ else 0.04) * SR)
    noise = np.diff(np.concatenate([[0], rng.uniform(-1, 1, n)]))
    return noise * np.exp(-np.arange(n) / SR * (25 if open_ else 80))

for b, (section, chord, bass_note, mel, part) in enumerate(song):
    start = b * 4 * BEAT
    # Bouncy bass: root on the beat, octave jump on the "and" of 2 and 4
    for e, (mult, g) in enumerate([(1, .5), (0, 0), (1, .35), (2, .3), (1, .45), (0, 0), (1, .35), (2, .3)]):
        if mult:
            add(bass(freq(bass_note) * mult), start + e * BEAT / 2, -0.1, g * 0.9)
    # Plucky offbeat chords
    chord_f = [freq(n) * 2 for n in chord]
    for e in (1, 3, 5, 7):
        add(pluck_chord(chord_f), start + e * BEAT / 2, 0.3, 0.16)
    # Drums: lighter in the first pass, full after
    for beat in range(4):
        add(kick(), start + beat * BEAT, 0, 0.5 if beat in (0, 2) or part >= 1 else 0)
        if beat in (1, 3):
            add(clap(), start + beat * BEAT, 0.05, 0.22 if part >= 1 else 0.12)
    for e in range(8):
        add(hat(open_=(e == 7 and b % 2 == 1)), start + e * BEAT / 2, -0.35, 0.09 if e % 2 else 0.05)
    # Marimba lead (doubled an octave up in the final section)
    pos = start
    for name, d in mel:
        if name != 'R':
            add(marimba(freq(name), d * BEAT), pos, 0.15, 0.30)
            if part == 3:
                add(marimba(freq(name) * 2, d * BEAT), pos + 0.003, -0.2, 0.10)
        pos += d * BEAT

mix = np.stack([L, R], axis=1)
fade = int(1.2 * SR)
mix[-fade:] *= np.linspace(1, 0, fade)[:, None]
mix /= np.max(np.abs(mix)) * 1.08
with wave.open('brainrot_theme.wav', 'wb') as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((mix * 32767).astype(np.int16).tobytes())
print('seconds', total)
