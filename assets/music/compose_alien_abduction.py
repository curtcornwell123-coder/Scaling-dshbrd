# Three original eerie "alien abduction" tracks for Corny's UFO event:
#   alien_abduction_1_tractor_beam.mp3     100 BPM dark synth pulse, beam hum, theremin
#   alien_abduction_2_close_encounter.mp3   88 BPM mysterious signal tones, glass bells, chatter
#   alien_abduction_3_red_alert.mp3        130 BPM intense: sirens, driving bass, zaps
# Each loops cleanly. Run: python3 compose_alien_abduction.py
import numpy as np, subprocess
from funk_lib import *

def to_mp3(name):
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', name + '.wav', '-b:a', '160k', name + '.mp3'], check=True)
    subprocess.run(['rm', name + '.wav'])

def up(name, octaves):
    return name[:-1] + str(int(name[-1]) + octaves)

# 1. TRACTOR BEAM ---------------------------------------------------------------
def tractor_beam():
    bpm = 100; beat = 60 / bpm; bars = 24
    m = Mix(bars * 4 * beat + 2, seed=21)
    rng = m.rng
    roots = ['D2', 'D2', 'Bb1', 'Bb1', 'G1', 'G1', 'A1', 'A1']
    # 16th ostinato: semitones above the root
    ost = [0, 12, 7, 12, 0, 12, 3, 12, 0, 12, 7, 12, 10, 12, 7, 3]
    melody = [
        [('A5', 2), ('D6', 1), ('F6', 1)],
        [('E6', 4)],
        [('D6', 2), ('Bb5', 1), ('F5', 1)],
        [('A5', 4)],
        [('G5', 1.5), ('Bb5', 0.5), ('D6', 2)],
        [('Eb6', 3), ('D6', 1)],
        [('C#6', 2), ('E6', 2)],
        [('A5', 4)],
    ]
    for b in range(bars):
        start = b * 4 * beat; i = b % 8
        root = freq(roots[i])
        section = 0 if b < 4 else (1 if b < 12 else (2 if b < 20 else 3))
        if i % 2 == 0:
            m.add(drone(root * 2, 8 * beat + 0.5, 0.25), start, 0, 0.28)
        if section >= 1 or b >= 2:
            for s, semi in enumerate(ost):
                m.add(pulse_bass(root * 2 ** (semi / 12), beat / 4 * 0.9), start + s * beat / 4, 0, 0.3)
        for q in range(4):
            if section >= 1:
                m.add(kick(rng), start + q * beat, 0, 0.45 if q % 2 == 0 else 0.3)
            if section >= 2 and q in (1, 3):
                m.add(snare(rng), start + q * beat, 0.05, 0.22)
        if section >= 2:
            for s in range(8):
                m.add(hat(rng), start + s * beat / 2 + beat / 4, 0.3, 0.05)
        if section >= 2:
            m.add(glide_voice(melody[i], beat, 'theremin', glide=0.15, vibrato=0.02), start, -0.1, 0.17)
        # glassy signal blips
        for k in (0, 3, 6):
            if rng.uniform() < 0.6:
                m.add(fm_bell(root * 8 * 2 ** (rng.choice([0, 7, 12, 15]) / 12), 1.2), start + k * beat / 2 * 2.5, rng.uniform(-0.7, 0.7), 0.05)
        if b % 4 == 3:
            m.add(riser(rng, 4 * beat), start, 0, 0.12)
        if b % 8 == 7:
            m.add(zap(3000, 90, 0.8), start + 3.6 * beat, 0, 0.18)
        if b in (2, 13, 21):
            m.add(alien_voice(rng, 1.6), start + beat, 0.5, 0.12)
    m.save('alien_abduction_1_tractor_beam.wav')
    to_mp3('alien_abduction_1_tractor_beam')

# 2. CLOSE ENCOUNTER ------------------------------------------------------------
def close_encounter():
    bpm = 88; beat = 60 / bpm; bars = 20
    m = Mix(bars * 4 * beat + 2, seed=33)
    rng = m.rng
    roots = ['F#1', 'F#1', 'D2', 'D2', 'B1', 'B1', 'C#2', 'C#2']
    pads = {
        'F#1': ['F#3', 'A3', 'C#4', 'E4'], 'D2': ['D3', 'F#3', 'A3', 'C#4'],
        'B1': ['B2', 'D3', 'F#3', 'A3'], 'C#2': ['C#3', 'F3', 'G#3', 'B3'],
    }
    # The ship's call sign: an original five-tone signal, answered back.
    signal = ['C#6', 'E6', 'B5', 'F#5', 'A5']
    answer = ['A5', 'B5', 'F#5', 'C#5', 'E5']
    for b in range(bars):
        start = b * 4 * beat; i = b % 8
        root = freq(roots[i])
        section = 0 if b < 4 else (1 if b < 12 else 2)
        if i % 2 == 0:
            m.add(string_pad([freq(n) for n in pads[roots[i]]], 8 * beat + 0.4), start, 0, 0.16)
            m.add(drone(root, 8 * beat + 0.5, 0.15), start, 0, 0.3)
        # signal call on even bars, answer on odd bars
        tones = signal if b % 2 == 0 else answer
        for k, n in enumerate(tones):
            m.add(fm_bell(freq(n), 1.6, 2.0, 1.6), start + k * beat * 0.75, -0.4 if b % 2 == 0 else 0.4, 0.12)
        if section >= 1:
            for s in range(16):
                if s in (0, 7, 10):
                    m.add(kick(rng), start + s * beat / 4, 0, 0.45)
                if s in (4, 12):
                    m.add(clap(rng), start + s * beat / 4, 0, 0.16)
                if s % 2 == 0:
                    m.add(hat(rng), start + s * beat / 4, 0.3, 0.045)
            for s in (0, 3, 8, 11, 14):
                m.add(sub_bass(root * 1.06, root, beat / 4 * 2.5), start + s * beat / 4, 0, 0.35)
        if section == 2:
            arp = [freq(up(n, 1)) for n in pads[roots[i]]]
            for s in range(16):
                m.add(fm_bell(arp[[0, 2, 1, 3][s % 4]], 0.3, 3.0, 1.0), start + s * beat / 4, 0.5 if s % 2 else -0.5, 0.04)
        if b % 3 == 1:
            m.add(alien_voice(rng, 1.4), start + 2 * beat, rng.uniform(-0.6, 0.6), 0.1)
        if b % 4 == 3:
            m.add(ufo_wobble(4 * beat, 260), start, 0, 0.07)
    m.save('alien_abduction_2_close_encounter.wav')
    to_mp3('alien_abduction_2_close_encounter')

# 3. RED ALERT -----------------------------------------------------------------
def red_alert():
    bpm = 130; beat = 60 / bpm; bars = 28
    m = Mix(bars * 4 * beat + 2, seed=44)
    rng = m.rng
    roots = ['E2', 'E2', 'F2', 'F2', 'E2', 'E2', 'G2', 'F#2']
    lead = [
        [('B5', 1), ('C6', 1), ('B5', 1), ('E5', 1)],
        [('G5', 2), ('F#5', 2)],
        [('C6', 1), ('D6', 1), ('C6', 1), ('F5', 1)],
        [('A5', 2), ('G#5', 2)],
        [('B5', 1), ('E6', 1), ('D#6', 1), ('B5', 1)],
        [('G5', 2), ('E5', 2)],
        [('D6', 1), ('B5', 1), ('G5', 1), ('D6', 1)],
        [('C#6', 2), ('A#5', 2)],
    ]
    for b in range(bars):
        start = b * 4 * beat; i = b % 8
        root = freq(roots[i])
        section = 0 if b < 4 else (1 if b < 12 else (2 if b < 24 else 3))
        if b < 4 or b % 8 == 0:
            m.add(siren(4 * beat, 450, 900, 0.5), start, 0, 0.1 if b < 4 else 0.06)
        if section >= 1:
            for q in range(4):
                m.add(kick(rng, 1.15), start + q * beat, 0, 0.55)
                if q in (1, 3):
                    m.add(snare(rng), start + q * beat, 0.05, 0.25)
                m.add(hat(rng, open_=True), start + q * beat + beat / 2, 0.3, 0.06)
            for s in range(16):
                semi = [0, 0, 12, 0, 0, 7, 0, 12, 0, 0, 12, 0, 1, 0, 12, 7][s]
                m.add(pulse_bass(root * 2 ** (semi / 12), beat / 4 * 0.85), start + s * beat / 4, 0, 0.32)
        else:
            m.add(drone(root, 4 * beat + 0.4, 0.5), start, 0, 0.3)
        if section >= 2:
            m.add(glide_voice(lead[i], beat, 'robot', glide=0.02, vibrato=0.003), start, -0.15, 0.17)
            m.add(glide_voice([(up(n, -1) if n != 'R' else 'R', d) for n, d in lead[i]], beat, 'theremin', glide=0.04), start, 0.2, 0.08)
        if section >= 1 and b % 2 == 1:
            m.add(zap(2800, 140, 0.4), start + 3.5 * beat, rng.uniform(-0.7, 0.7), 0.14)
            m.add(zap(2200, 200, 0.3), start + 3.75 * beat, rng.uniform(-0.7, 0.7), 0.1)
        if b % 4 == 3:
            m.add(riser(rng, 4 * beat), start, 0, 0.14)
        if b in (5, 17):
            m.add(alien_voice(rng, 1.5), start + 2 * beat, 0.4, 0.1)
    m.save('alien_abduction_3_red_alert.wav')
    to_mp3('alien_abduction_3_red_alert')

if __name__ == '__main__':
    tractor_beam()
    close_encounter()
    red_alert()
    print('done')
