"""Promo video (1920x1080, 30 fps, H.264) from thumbnail art: Corny Games logo intro, each
scene with a slow push-in, smooth transitions, logo outro.

Usage: python3 marketing/make_video.py [--outro "Play X now on Roblox"] OUT.mp4 IMG1.png IMG2.png ...
"""
import os
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
LOGO = os.path.join(HERE, "..", "studio-loading-screen", "corny_games_logo.png")
FPS = 30
SCENE = 3.2       # seconds per scene
XFADE = 0.6       # transition length
CARD = 2.2        # logo intro / outro length
TRANSITIONS = ["smoothleft", "circleopen", "smoothright", "fadewhite", "slideup", "circlecrop", "smoothup"]


def logo_card(path, caption):
    w, h = 1920, 1080
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    d = np.clip(np.hypot(xs - w / 2, ys - (h / 2 - 60)) / 620.0, 0, 1)
    k = (1 - d) ** 2.2
    base = np.array([8, 9, 14], np.float32)
    warm = np.array([58, 44, 16], np.float32)
    arr = base + (warm - base) * k[..., None]
    img = Image.fromarray(arr.astype(np.uint8), "RGB")
    logo = Image.open(LOGO).convert("RGBA").resize((720, 720), Image.LANCZOS)
    img.paste(logo, ((w - 720) // 2, (h - 720) // 2 - 70), logo)
    if caption:
        f = ImageFont.truetype("/usr/share/fonts/opentype/inter/Inter-SemiBold.otf", 44)
        tw = ImageDraw.Draw(img).textlength(caption, font=f)
        ImageDraw.Draw(img).text(((w - tw) / 2, h - 170), caption, font=f, fill=(170, 178, 198))
    img.save(path)


def main(argv):
    outro_text = "Play now on Roblox"
    if argv[:1] == ["--outro"]:
        outro_text, argv = argv[1], argv[2:]
    out, images = argv[0], argv[1:]
    tmp = tempfile.mkdtemp()
    intro, outro = os.path.join(tmp, "intro.png"), os.path.join(tmp, "outro.png")
    logo_card(intro, "presents")
    logo_card(outro, outro_text)
    clips = [(intro, CARD, False)] + [(p, SCENE, True) for p in images] + [(outro, CARD, False)]

    cmd = ["ffmpeg", "-y", "-loglevel", "error"]
    for path, dur, _ in clips:
        cmd += ["-loop", "1", "-framerate", str(FPS), "-t", f"{dur + XFADE:.2f}", "-i", path]
    parts = []
    for i, (_, dur, push) in enumerate(clips):
        frames = int((dur + XFADE) * FPS)
        if push:
            zoom = "1+0.10*on/%d" % frames if i % 2 else "1.10-0.10*on/%d" % frames
            parts.append(
                f"[{i}:v]scale=3840:2160,zoompan=z='{zoom}':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)'"
                f":d={frames}:s=1920x1080:fps={FPS},setsar=1,format=yuv420p[v{i}]"
            )
        else:
            parts.append(f"[{i}:v]scale=1920:1080,fps={FPS},setsar=1,format=yuv420p[v{i}]")
    prev, t = "v0", clips[0][1]
    for i in range(1, len(clips)):
        trans = "fade" if i in (1, len(clips) - 1) else TRANSITIONS[(i - 1) % len(TRANSITIONS)]
        label = f"x{i}"
        parts.append(f"[{prev}][v{i}]xfade=transition={trans}:duration={XFADE}:offset={t:.2f}[{label}]")
        prev = label
        t += clips[i][1]
    parts.append(f"[{prev}]fade=t=out:st={t - 0.6:.2f}:d=0.6[outv]")
    cmd += ["-filter_complex", ";".join(parts), "-map", "[outv]", "-c:v", "libx264", "-preset", "medium",
            "-crf", "18", "-pix_fmt", "yuv420p", "-movflags", "+faststart", "-r", str(FPS), out]
    subprocess.run(cmd, check=True)
    print(out)


if __name__ == "__main__":
    main(sys.argv[1:])
