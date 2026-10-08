# Three original lobby / background tracks: friendly, mid-energy, loop-safe.
#   lobby_1_sunny_heist.mp3     100 BPM sunny pop: e-piano, plucks, light drums
#   lobby_2_brainrot_bounce.mp3 112 BPM playful: marimba, bouncy bass, claps, whistle
#   lobby_3_chill_plaza.mp3      86 BPM chillhop: lazy e-piano chords, soft beat, bells
# Run: python3 compose_lobby.py
import numpy as np, subprocess
from funk_lib import *

def to_mp3(name):
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', name + '.wav', '-b:a', '160k', name + '.mp3'], check=True)
    subprocess.run(['rm', name + '.wav'])

def chord(names):
    return [freq(n) for n in names]

# 1. SUNNY HEIST -----------------------------------------------------------------
def sunny_heist():
    bpm = 100; beat = 60 / bpm
    prog = [('F2', ['A3', 'C4', 'E4', 'F4']), ('D2', ['A3', 'C4', 'D4', 'F4']),
            ('Bb1', ['A3', 'D4', 'F4', 'Bb4']), ('C2', ['G3', 'C4', 'E4', 'Bb4'])]
    melody_a = [
        [('C5', 1), ('F5', 1), ('A5', 1.5), ('G5', 0.5)],
        [('F5', 1), ('D5', 1), ('C5', 2)],
        [('D5', 1), ('F5', 1), ('Bb5', 1), ('A5', 1)],
        [('G5', 3), ('R', 1)],
        [('A5', 1), ('C6', 1), ('A5', 1), ('G5', 1)],
        [('F5', 1.5), ('E5', 0.5), ('D5', 2)],
        [('Bb4', 1), ('D5', 1), ('F5', 1), ('G5', 1)],
        [('E5', 2), ('G5', 2)],
    ]
    bars = 32
    m = Mix(bars * 4 * beat + 2, seed=51)
    rng = m.rng
    for b in range(bars):
        start = b * 4 * beat
        root, voicing = prog[b % 4]
        section = 0 if b < 2 else (1 if b < 10 else (2 if b < 26 else 3))
        cf = chord(voicing)
        # e-piano comping: on 1 and the "and" of 2
        m.add(epiano(cf, beat * 1.4, 0.9), start, -0.15, 0.3)
        m.add(epiano(cf, beat * 1.2, 0.6), start + 1.5 * beat, -0.15, 0.24)
        if b % 2 == 1:
            m.add(epiano(cf, beat * 0.9, 0.5), start + 3 * beat, -0.15, 0.14)
        # bass
        if section >= 1:
            r = freq(root)
            for at, f, d in ((0, r, 1.4), (1.5, r, 0.5), (2, r * 1.5, 1), (3, r * 2, 0.9)):
                m.add(soft_bass(f, d * beat), start + at * beat, 0, 0.2)
        # drums: soft kick, rim, shaker
        if section >= 1:
            for q in range(4):
                if q in (0, 2):
                    m.add(kick(rng, 0.8), start + q * beat, 0, 0.24)
                if q in (1, 3):
                    m.add(rim(rng), start + q * beat, 0.1, 0.12)
            for e in range(8):
                m.add(shaker(rng), start + e * beat / 2, 0.35, 0.05 if e % 2 else 0.035)
        # melody on plucks in the main section
        if section == 2:
            t = 0.0
            for n, d in melody_a[b % 8]:
                if n != 'R':
                    m.add(pluck(freq(n), min(1.2, d * beat + 0.3), 0.55), start + t * beat, 0.2, 0.2)
                t += d
        # sparkle arpeggio in the outro and intro
        if section in (0, 3):
            for s in range(8):
                f = cf[[0, 1, 2, 3, 2, 1, 0, 1][s]] * 2
                m.add(marimba(f, 0.5), start + s * beat / 2, 0.3 if s % 2 else -0.3, 0.1)
    m.save('lobby_1_sunny_heist.wav')
    to_mp3('lobby_1_sunny_heist')

# 2. BRAINROT BOUNCE ---------------------------------------------------------------
def brainrot_bounce():
    bpm = 112; beat = 60 / bpm
    prog = [('C2', ['E4', 'G4', 'C5']), ('A1', ['E4', 'A4', 'C5']), ('D2', ['F4', 'A4', 'D5']), ('G1', ['F4', 'B4', 'D5'])]
    whistle = [
        [('G5', 0.5), ('A5', 0.5), ('G5', 0.5), ('E5', 0.5), ('C5', 2)],
        [('E5', 0.5), ('G5', 0.5), ('A5', 1), ('C6', 2)],
        [('D6', 0.5), ('C6', 0.5), ('A5', 1), ('F5', 1), ('A5', 1)],
        [('G5', 2), ('R', 2)],
        [('C6', 0.5), ('B5', 0.5), ('A5', 0.5), ('G5', 0.5), ('E5', 2)],
        [('A5', 1), ('G5', 1), ('E5', 1), ('C5', 1)],
        [('D5', 0.5), ('F5', 0.5), ('A5', 1), ('D6', 1), ('C6', 1)],
        [('B5', 2), ('D6', 2)],
    ]
    bars = 32
    m = Mix(bars * 4 * beat + 2, seed=62)
    rng = m.rng
    for b in range(bars):
        start = b * 4 * beat
        root, voicing = prog[b % 4]
        section = 0 if b < 2 else (1 if b < 10 else (2 if b < 26 else 3))
        cf = chord(voicing)
        # bouncy marimba off-beats
        for e in range(8):
            if e % 2 == 1:
                for f in cf:
                    m.add(marimba(f, 0.35), start + e * beat / 2, -0.2, 0.09)
        # bass: root - octave hops
        r = freq(root)
        if True:
            for at, f in ((0, r), (1, r * 2), (1.5, r * 1.5), (2, r), (3, r * 2), (3.5, r * 1.5)):
                m.add(soft_bass(f, beat * 0.45), start + at * beat, 0, 0.2)
        if section >= 1:
            for q in range(4):
                m.add(kick(rng, 0.8), start + q * beat, 0, 0.22 if q % 2 == 0 else 0.15)
                if q in (1, 3):
                    m.add(clap(rng), start + q * beat, 0, 0.1)
            for s in range(16):
                if s % 2 == 0:
                    m.add(hat(rng), start + s * beat / 4, 0.3, 0.035)
        if section == 2:
            m.add(glide_voice(whistle[b % 8], beat, 'whistle', glide=0.04, vibrato=0.01), start, 0.15, 0.13)
        if section == 3:
            t = 0.0
            for n, d in whistle[b % 8]:
                if n != 'R':
                    m.add(marimba(freq(n), 0.5), start + t * beat, 0.2, 0.12)
                t += d
        if b % 8 == 7:
            m.add(chirp(rng, 0.15), start + 3.5 * beat, 0.5, 0.03)
    m.save('lobby_2_brainrot_bounce.wav')
    to_mp3('lobby_2_brainrot_bounce')

# 3. CHILL PLAZA -------------------------------------------------------------------
def chill_plaza():
    bpm = 86; beat = 60 / bpm
    prog = [('Eb2', ['G3', 'Bb3', 'D4', 'F4']), ('C2', ['G3', 'Bb3', 'Eb4', 'F4']),
            ('Ab1', ['G3', 'C4', 'Eb4', 'Bb4']), ('Bb1', ['F3', 'Ab3', 'D4', 'G4'])]
    bells = ['Bb5', 'G5', 'F5', 'Eb5', 'D5', 'F5', 'G5', 'Bb5']
    bars = 24
    m = Mix(bars * 4 * beat + 2, seed=73)
    rng = m.rng
    sw = 0.13
    for b in range(bars):
        start = b * 4 * beat
        root, voicing = prog[b % 4]
        section = 0 if b < 1 else (1 if b < 22 else 2)
        cf = chord(voicing)
        m.add(epiano(cf, beat * 2.6, 0.8), start, -0.1, 0.32)
        m.add(epiano(cf[1:], beat * 1.3, 0.5), start + 2.75 * beat, -0.1, 0.22)
        if section >= 1:
            r = freq(root)
            for at, f, d in ((0, r, 1.6), (1.75, r, 0.6), (2.5, r * 1.5, 1.2)):
                m.add(soft_bass(f, d * beat), start + at * beat, 0, 0.22)
            for s in range(16):
                at = start + s * beat / 4 + (sw * beat if s % 2 else 0)
                if s in (0, 9) or (s == 7 and b % 2):
                    m.add(kick(rng, 0.75), at, 0, 0.24)
                if s in (4, 12):
                    m.add(snare(rng), at, 0.05, 0.1)
                    m.add(rim(rng), at, -0.1, 0.06)
                if s % 2 == 0:
                    m.add(hat(rng), at, 0.3, 0.03)
            # lazy bell line every other bar
            if b % 2 == 0:
                for k in range(4):
                    n = bells[(b // 2 * 4 + k) % len(bells)]
                    m.add(fm_bell(freq(n), 1.4, 2.0, 0.8), start + k * beat + (0.5 * beat if k % 2 else 0), 0.3, 0.1)
    # soft vinyl crackle bed
    crackle = (rng.uniform(0, 1, m.N) > 0.9993) * rng.uniform(-1, 1, m.N)
    m.add(onepole(crackle, 3000), 0, 0, 0.08)
    m.save('lobby_3_chill_plaza.wav')
    to_mp3('lobby_3_chill_plaza')

if __name__ == '__main__':
    sunny_heist()
    brainrot_bounce()
    chill_plaza()
    print('done')
