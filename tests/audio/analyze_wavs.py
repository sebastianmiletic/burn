"""Loudness / sanity report for rendered sounds (needs numpy + ffmpeg).

    python3 tests/audio/analyze_wavs.py '/path/to/render/*.wav'

Columns: duration, peak dBFS, overall RMS dB, loudest 50 ms RMS dB, spectral
centroid Hz, DC offset, |first sample|, |last sample|, clipped samples.
"""
import sys, subprocess, os, glob
import numpy as np


def rate(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries", "stream=sample_rate",
                          "-of", "csv=p=0", path], capture_output=True, text=True).stdout.strip()
    return int(out) if out else 44100


def load(path):
    out = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ac", "1", "-"],
                         capture_output=True).stdout
    return np.frombuffer(out, dtype=np.float32), rate(path)


def stats(x, sr):
    if len(x) == 0:
        return None
    peak = float(np.max(np.abs(x)))
    rms = float(np.sqrt(np.mean(x.astype(np.float64) ** 2)))
    w = int(0.05 * sr)
    if len(x) > w:
        c = np.cumsum(np.concatenate([[0.0], x.astype(np.float64) ** 2]))
        sq = (c[w:] - c[:-w]) / w
        strms = float(np.sqrt(max(sq.max(), 0)))
    else:
        strms = rms
    X = np.abs(np.fft.rfft(x * np.hanning(len(x))))
    f = np.fft.rfftfreq(len(x), 1 / sr)
    cent = float((X * f).sum() / max(X.sum(), 1e-9))
    return dict(dur=len(x) / sr, peak_db=20 * np.log10(peak + 1e-12), rms_db=20 * np.log10(rms + 1e-12),
                st_db=20 * np.log10(strms + 1e-12), cent=cent, dc=float(np.mean(x)),
                head=float(np.abs(x[:2]).max()), tail=float(np.abs(x[-2:]).max()), clip=int(np.sum(np.abs(x) > 0.999)))


def main():
    files = []
    for a in sys.argv[1:]:
        files += sorted(glob.glob(a)) if any(ch in a for ch in "*?") else [a]
    print(f"{'file':40s} {'dur':>6s} {'pk_db':>6s} {'rms':>6s} {'st50':>6s} {'cent':>6s} {'dc':>7s} {'head':>6s} {'tail':>6s} clip")
    for p in files:
        x, sr = load(p)
        s = stats(x, sr)
        if s is None:
            print(p, "EMPTY")
            continue
        print(f"{os.path.basename(p)[:40]:40s} {s['dur']:6.2f} {s['peak_db']:6.1f} {s['rms_db']:6.1f} {s['st_db']:6.1f} "
              f"{s['cent']:6.0f} {s['dc']:7.4f} {s['head']:6.3f} {s['tail']:6.3f} {s['clip']}")


if __name__ == "__main__":
    main()
