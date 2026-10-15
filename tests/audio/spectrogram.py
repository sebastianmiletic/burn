"""Render log-frequency spectrograms (and the waveform envelope) of audio files to PNGs.

    python3 tests/audio/spectrogram.py OUT_DIR file1.wav [file2.ogg ...] [--max-sec 30] [--grid]

With --grid all files go into one contact sheet (OUT_DIR/grid.png). Needs numpy, matplotlib, ffmpeg.
"""
import sys, os, subprocess
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

SR = 32000


def load(path, max_sec):
    out = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-t", str(max_sec), "-f", "f32le", "-ac", "1",
                          "-ar", str(SR), "-"], capture_output=True).stdout
    return np.frombuffer(out, dtype=np.float32)


def spec(x):
    n = 1024 if len(x) > 32000 * 3 else 512
    hop = n // 4
    if len(x) < n:
        x = np.pad(x, (0, n - len(x)))
    frames = np.lib.stride_tricks.sliding_window_view(x, n)[::hop] * np.hanning(n)
    S = np.abs(np.fft.rfft(frames, axis=1)) + 1e-9
    return 20 * np.log10(S).T, n, hop


def draw(ax_s, ax_w, x, title):
    S, n, hop = spec(x)
    f = np.fft.rfftfreq(n, 1 / SR)
    t = np.arange(S.shape[1]) * hop / SR
    ax_s.pcolormesh(t, f[1:], S[1:], vmin=S.max() - 80, vmax=S.max(), shading="auto", cmap="magma")
    ax_s.set_yscale("log")
    ax_s.set_ylim(40, SR / 2)
    ax_s.set_title(title, fontsize=8)
    ax_s.tick_params(labelsize=6)
    tt = np.arange(len(x)) / SR
    ax_w.plot(tt, x, lw=0.3)
    ax_w.set_ylim(-1, 1)
    ax_w.set_xlim(0, len(x) / SR)
    ax_w.tick_params(labelsize=6)


def main():
    args = sys.argv[1:]
    max_sec = 30.0
    grid = False
    if "--max-sec" in args:
        i = args.index("--max-sec")
        max_sec = float(args[i + 1])
        del args[i:i + 2]
    if "--grid" in args:
        args.remove("--grid")
        grid = True
    out_dir, files = args[0], args[1:]
    os.makedirs(out_dir, exist_ok=True)
    if grid:
        cols = 4
        rows = (len(files) + cols - 1) // cols
        fig, axes = plt.subplots(rows * 2, cols, figsize=(cols * 4, rows * 3.2),
                                 gridspec_kw={"height_ratios": [3, 1] * rows}, squeeze=False)
        for k, p in enumerate(files):
            r, c = divmod(k, cols)
            draw(axes[r * 2][c], axes[r * 2 + 1][c], load(p, max_sec), os.path.basename(p))
        for k in range(len(files), rows * cols):
            r, c = divmod(k, cols)
            axes[r * 2][c].axis("off")
            axes[r * 2 + 1][c].axis("off")
        fig.tight_layout()
        fig.savefig(os.path.join(out_dir, "grid.png"), dpi=70)
        return
    for p in files:
        fig, (a, b) = plt.subplots(2, 1, figsize=(12, 5), gridspec_kw={"height_ratios": [3, 1]})
        draw(a, b, load(p, max_sec), os.path.basename(p))
        fig.tight_layout()
        fig.savefig(os.path.join(out_dir, os.path.splitext(os.path.basename(p))[0] + ".png"), dpi=80)
        plt.close(fig)


if __name__ == "__main__":
    main()
