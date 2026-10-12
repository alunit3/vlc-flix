# Objective WASAPI check: plays a 5.1 clip that has a 1 kHz tone in the centre channel only, records
# what the speakers actually get (WASAPI loopback), and counts the moments where that tone leaves the
# right channel or the left/right balance jumps. With a correct 5.1 -> stereo downmix the centre lands
# in both channels at the same level all the time, so a clean output has no such moments.
#   python flix\tests\loopback_center.py                  baseline
#   python flix\tests\loopback_center.py -- --mix-mode=1  extra VLCFlix options after "--"
# Needs: pip install soundcard numpy, and ffmpeg on PATH (only to create the clip the first time).
# It does not change the volume or any setting; a muted or zero volume is reported as "no signal".
import argparse
import os
import subprocess
import sys
import tempfile
import time

import numpy as np
import soundcard as sc

RATE = 48000
WINDOW = RATE // 500  # 2 ms


def make_clip(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
                    "-f", "lavfi", "-i", f"sine=frequency=1000:sample_rate={RATE}:duration=60",
                    "-af", "pan=5.1|FC=c0", "-c:a", "aac", "-b:a", "384k", path], check=True)


def window_rms(x):
    n = len(x) // WINDOW
    return np.sqrt(np.mean(x[:n * WINDOW].reshape(n, WINDOW) ** 2, axis=1))


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser()
    ap.add_argument("--exe", default=os.path.join(here, "..", "..", "..", "run", "vlcflix.exe"))
    ap.add_argument("--clip", default=os.path.join(tempfile.gettempdir(), "vlcflix-tests", "center51.mp4"))
    ap.add_argument("--seconds", type=float, default=15)
    ap.add_argument("--settle", type=float, default=4, help="seconds to wait before recording")
    ap.add_argument("vlc_args", nargs="*")
    a = ap.parse_args()

    if not os.path.exists(a.clip):
        make_clip(a.clip)

    exe = os.path.abspath(a.exe)
    cmd = [exe, "--no-one-instance", "--no-video-title-show"] + a.vlc_args + [a.clip]
    print("running:", " ".join(cmd))
    proc = subprocess.Popen(cmd, cwd=os.path.dirname(exe))
    try:
        time.sleep(a.settle)
        speaker = sc.default_speaker()
        mic = sc.get_microphone(id=str(speaker.name), include_loopback=True)
        with mic.recorder(samplerate=RATE, channels=2) as rec:
            data = rec.record(numframes=int(a.seconds * RATE))
    finally:
        proc.kill()

    trim = RATE // 2
    data = data[trim:-trim]
    left, right = window_rms(data[:, 0]), window_rms(data[:, 1])
    ref_l, ref_r = np.median(left), np.median(right)
    print(f"device: {speaker.name}")
    print(f"windows: {len(right)} x 2 ms, median rms L {ref_l:.4f} R {ref_r:.4f}")
    if ref_l < 1e-4 or ref_r < 1e-4:
        print("RESULT: no signal (muted, volume at 0, or the tone did not reach this device)")
        return 2

    floor = 10 ** (-12 / 20)
    drop_r = int(np.sum(right < ref_r * floor))
    drop_l = int(np.sum(left < ref_l * floor))
    balance = 20 * np.log10(np.maximum(left, 1e-9) / np.maximum(right, 1e-9))
    jumps = int(np.sum(np.abs(balance - np.median(balance)) > 3))
    n = len(right)
    print(f"right channel dropouts (>12 dB down): {drop_r} ({100 * drop_r / n:.2f} %)")
    print(f"left channel dropouts  (>12 dB down): {drop_l} ({100 * drop_l / n:.2f} %)")
    print(f"balance jumps (>3 dB off median):     {jumps} ({100 * jumps / n:.2f} %)")
    bad = max(drop_r, drop_l, jumps) > n * 0.005
    print("RESULT:", "FAIL" if bad else "PASS")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
