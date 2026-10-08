# Three original "alien funk" tracks for Corny's UFO event, to pick from:
#   alien_funk_1_saucer_slap.mp3     108 BPM slap-bass funk, wah clav, theremin
#   alien_funk_2_disco_invasion.mp3  120 BPM disco funk, octave bass, robot lead
#   alien_funk_3_mothership.mp3      94 BPM G-funk, sub bass slides, whistle lead
# Each loops cleanly. Run: python3 compose_alien_funk.py
import numpy as np, subprocess
from funk_lib import *

def swing(step, beat, amount=0.09):
    # 16th-note position with a little swing on the off-16ths
    return step * beat / 4 + (amount * beat if step % 2 == 1 else 0)

def to_mp3(name):
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', name + '.wav', '-b:a', '160k', name + '.mp3'], check=True)
    subprocess.run(['rm', name + '.wav'])

# 1. SAUCER SLAP ---------------------------------------------------------------
def saucer_slap():
    bpm = 108; beat = 60 / bpm; bars = 24
    m = Mix(bars * 4 * beat + 1.5, seed=3)
    rng = m.rng
    roots = ['E2', 'E2', 'A2', 'A2', 'E2', 'E2', 'C2', 'B1']
    chords = {
        'E2': ['E4', 'G4', 'B4', 'D5'], 'A2': ['A3', 'C#4', 'E4', 'G4'],
        'C2': ['C4', 'E4', 'G4', 'B4'], 'B1': ['B3', 'D#4', 'F#4', 'A4'],
    }
    # (16th step, semitones above root, pop?)
    bass_pat = [(0, 0, False), (3, 0, False), (6, 12, True), (8, 0, False), (10, 10, False), (11, 12, True), (14, 7, False)]
    lead = [
        [('E5', 1.5), ('G5', 0.5), ('A5', 1), ('B5', 1)],
        [('D6', 1), ('B5', 1), ('A5', 2)],
        [('C#6', 1.5), ('A5', 0.5), ('E5', 1), ('G5', 1)],
        [('A5', 3), ('R', 1)],
        [('B5', 1), ('D6', 1), ('E6', 1.5), ('D6', 0.5)],
        [('B5', 2), ('G5', 1), ('A5', 1)],
        [('G5', 1), ('E5', 1), ('C5', 1), ('E5', 1)],
        [('D#5', 2), ('F#5', 1), ('B5', 1)],
    ]
    for b in range(bars):
        start = b * 4 * beat
        i = b % 8
        root = freq(roots[i])
        section = 0 if b < 4 else (1 if b < 12 else (2 if b < 20 else 3))
        # drums
        for s in range(16):
            at = start + swing(s, beat)
            if s in (0, 10) or (s == 7 and b % 2):
                m.add(kick(rng), at, 0, 0.55)
            if s in (4, 12) and section >= 1:
                m.add(snare(rng), at, 0.05, 0.3)
            if s in (7, 15, 9) and section >= 1:
                m.add(snare(rng, ghost=True), at, 0.1, 0.3)
            m.add(hat(rng, open_=(s == 14)), at, 0.35, (0.09 if s % 2 else 0.06) * (1 if section else 0.7))
        # slap bass
        if section >= 1:
            for s, semi, pop in bass_pat:
                f = root * 2 ** (semi / 12)
                m.add(slap_bass(f, beat / 4 * (2 if s in (0, 8) else 1.4), pop), start + swing(s, beat), 0, 0.42)
        # wah clav stabs
        voicing = [freq(n) for n in chords[roots[i]]]
        for s in (2, 6, 10, 13):
            m.add(wah_clav(voicing, beat / 4 * 1.6, sweep_up=(s != 13)), start + swing(s, beat), -0.35, 0.16)
        # theremin lead in the B section
        if section == 2:
            m.add(glide_voice(lead[i], beat, 'theremin'), start, 0.15, 0.2)
        if section == 3:
            m.add(glide_voice([(n[:-1] + str(int(n[-1]) - 1) if n != 'R' else 'R', d) for n, d in lead[i]], beat, 'robot'), start, 0.15, 0.14)
        # alien FX
        if b % 4 == 3:
            m.add(zap(), start + 3.5 * beat, 0.6 if b % 8 == 3 else -0.6, 0.16)
        if b % 2 == 0 and section >= 1:
            m.add(chirp(rng), start + 1.75 * beat, rng.uniform(-0.7, 0.7), 0.05)
        if b in (3, 11, 19):
            m.add(ufo_wobble(4 * beat), start, 0, 0.06)
    m.save('alien_funk_1_saucer_slap.wav')
    to_mp3('alien_funk_1_saucer_slap')

# 2. DISCO INVASION ------------------------------------------------------------
def disco_invasion():
    bpm = 120; beat = 60 / bpm; bars = 24
    m = Mix(bars * 4 * beat + 1.5, seed=5)
    rng = m.rng
    prog = ['A2', 'A2', 'F2', 'F2', 'G2', 'G2', 'E2', 'E2']
    chords = {
        'A2': ['A3', 'C4', 'E4', 'G4'], 'F2': ['F3', 'A3', 'C4', 'E4'],
        'G2': ['G3', 'B3', 'D4', 'F4'], 'E2': ['E3', 'G#3', 'B3', 'D4'],
    }
    lead = [
        [('E5', 1), ('A5', 1), ('C6', 1), ('B5', 1)],
        [('A5', 2), ('G5', 1), ('E5', 1)],
        [('F5', 1), ('A5', 1), ('C6', 1.5), ('A5', 0.5)],
        [('G5', 3), ('R', 1)],
        [('G5', 1), ('B5', 1), ('D6', 1), ('F6', 1)],
        [('E6', 2), ('D6', 1), ('B5', 1)],
        [('G#5', 1), ('B5', 1), ('E6', 1), ('D6', 1)],
        [('B5', 2), ('G#5', 2)],
    ]
    for b in range(bars):
        start = b * 4 * beat
        i = b % 8
        root = freq(prog[i])
        section = 0 if b < 4 else (1 if b < 12 else (2 if b < 20 else 3))
        for q in range(4):
            m.add(kick(rng, 1.1), start + q * beat, 0, 0.55)
            if q in (1, 3) and section >= 1:
                m.add(clap(rng), start + q * beat, 0, 0.22)
            m.add(hat(rng, open_=True), start + q * beat + beat / 2, 0.3, 0.07)
        for s in range(16):
            if s % 2 == 1:
                m.add(hat(rng), start + s * beat / 4, -0.3, 0.05)
        # octave bass in 8ths
        if section >= 1:
            for e in range(8):
                f = root * (2 if e % 2 else 1)
                m.add(octave_bass(f, beat / 2 * 0.9), start + e * beat / 2, 0, 0.36)
        # string pad + brass stabs
        voicing = [freq(n) for n in chords[prog[i]]]
        if i % 2 == 0:
            m.add(string_pad([f * 2 for f in voicing], 8 * beat + 0.3), start, 0, 0.12)
        if section >= 1:
            for s in (0, 6, 10):
                if s == 0 and i % 2 == 1:
                    continue
                m.add(brass_stab([f * 2 for f in voicing[:3]], beat * 0.45), start + s * beat / 4, 0.25, 0.14)
        if section >= 2:
            m.add(glide_voice(lead[i], beat, 'robot', glide=0.03, vibrato=0.004), start, -0.1, 0.17)
        if section == 3:
            m.add(glide_voice(lead[i], beat, 'theremin'), start, 0.2, 0.08)
        if b % 8 == 7:
            m.add(ufo_wobble(4 * beat, 350), start, 0, 0.08)
            m.add(zap(3000, 120, 0.6), start + 3 * beat, -0.5, 0.16)
        if b % 2 == 1:
            m.add(chirp(rng), start + 3.25 * beat, 0.6, 0.05)
    m.save('alien_funk_2_disco_invasion.wav')
    to_mp3('alien_funk_2_disco_invasion')

# 3. MOTHERSHIP G-FUNK -------------------------------------------------------
def mothership():
    bpm = 94; beat = 60 / bpm; bars = 20
    m = Mix(bars * 4 * beat + 1.5, seed=9)
    rng = m.rng
    prog = ['G1', 'G1', 'C2', 'C2', 'Eb2', 'Eb2', 'D2', 'D2']
    chords = {
        'G1': ['G3', 'Bb3', 'D4', 'F4'], 'C2': ['C4', 'Eb4', 'G4', 'Bb4'],
        'Eb2': ['Eb3', 'G3', 'Bb3', 'D4'], 'D2': ['D3', 'F#3', 'A3', 'C4'],
    }
    # sub bass: (16th step, semitones, length in 16ths, slide from semitones)
    bass = [(0, 0, 3, 0), (3, 0, 2, 0), (6, 12, 2, 0), (8, 0, 4, -5), (13, 3, 1, 0), (14, 5, 2, 3)]
    whistle = [
        [('D6', 2), ('Bb5', 1), ('G5', 1)],
        [('F5', 3), ('R', 1)],
        [('G5', 1), ('Bb5', 1), ('C6', 1.5), ('Eb6', 0.5)],
        [('D6', 3), ('R', 1)],
        [('Bb5', 2), ('G5', 1), ('Eb5', 1)],
        [('F5', 2), ('G5', 2)],
        [('A5', 1.5), ('C6', 0.5), ('D6', 1), ('F#5', 1)],
        [('G5', 3), ('R', 1)],
    ]
    for b in range(bars):
        start = b * 4 * beat
        i = b % 8
        root = freq(prog[i])
        section = 0 if b < 4 else (1 if b < 12 else 2)
        for s in range(16):
            at = start + swing(s, beat, 0.12)
            if s in (0, 6, 10) or (s == 11 and b % 2):
                m.add(kick(rng, 1.15), at, 0, 0.6)
            if s in (4, 12):
                m.add(clap(rng), at, 0, 0.24)
                m.add(snare(rng), at, 0.05, 0.12)
            if s % 2 == 0 or section >= 1:
                m.add(hat(rng), at, 0.3, 0.06 if s % 2 else 0.08)
        if section >= 1 or b >= 2:
            for s, semi, length, slide in bass:
                f = root * 2 ** (semi / 12)
                f0 = root * 2 ** ((semi + slide) / 12)
                m.add(sub_bass(f0, f, length * beat / 4), start + swing(s, beat, 0.12), 0, 0.5)
        voicing = [freq(n) for n in chords[prog[i]]]
        if i % 2 == 0:
            m.add(string_pad(voicing, 8 * beat + 0.3), start, 0, 0.13)
        for s in (2, 10):
            m.add(wah_clav([f * 2 for f in voicing[:3]], beat * 0.35, sweep_up=False), start + swing(s, beat, 0.12), -0.3, 0.1)
        if section >= 1:
            m.add(glide_voice(whistle[i], beat, 'whistle', glide=0.12, vibrato=0.018), start, 0.1, 0.17)
        if b % 4 == 3:
            m.add(ufo_wobble(4 * beat, 300), start, -0.2, 0.06)
        if b % 2 == 1:
            m.add(zap(1800, 200, 0.5), start + 3.5 * beat, 0.5, 0.1)
            m.add(chirp(rng, 0.2), start + 1.5 * beat, -0.5, 0.05)
    m.save('alien_funk_3_mothership.wav')
    to_mp3('alien_funk_3_mothership')

if __name__ == '__main__':
    saucer_slap()
    disco_invasion()
    mothership()
    print('done')
