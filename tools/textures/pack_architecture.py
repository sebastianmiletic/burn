"""Packs the CC0 Poly Haven sets into the architecture texture arrays.

albedo: 4x3 grid of 1024 px layers (sRGB jpg)
normal: 4x3 grid of 512 px layers (webp RGBA: R,G = GL normal xy, B = AO, A = roughness)
Prints each layer's (u, v) world tile size in metres for ArchMaterials.

Usage (sources are CC0 Poly Haven sets, see CREDITS.md):
  python3 fetch_polyhaven.py DL patterned_clay_plaster rough_wood old_planks_02 rustic_stone_wall_02 \\
      rustic_stone_wall reed_roof_04 rust_coarse_01 rough_linen stone_pathway_02 brown_planks_09
  RES=2k python3 fetch_polyhaven.py DL2K roof_slates_03 roof_slates_02
  python3 pack_architecture.py DL DL2K assets/architecture
"""
import sys, os
import numpy as np
from PIL import Image

DL = sys.argv[1]
DL2 = sys.argv[2]
OUT = sys.argv[3]
S = 1024
N = 512


def load(path, mode):
    return np.asarray(Image.open(path).convert(mode), dtype=np.float32) / 255.0


def seamless_v(a, band=0.18):
    """Vertically tileable by blending the edges with a half-rolled copy."""
    h = a.shape[0]
    b = np.roll(a, h // 2, axis=0)
    y = np.arange(h) / (h - 1)
    d = np.minimum(y, 1.0 - y)  # distance to the nearest edge
    w = np.clip(1.0 - d / band, 0.0, 1.0)
    w = w * w * (3 - 2 * w)
    shape = (h,) + (1,) * (a.ndim - 1)
    return a * (1 - w.reshape(shape)) + b * w.reshape(shape)


def row_crop(path_diff, start_min):
    """Rows of a roof texture between two dark row seams, so it tiles vertically."""
    lum = load(path_diff, "L")
    prof = lum.mean(axis=1)
    h = len(prof)
    thresh = np.percentile(prof, 30)
    mins = [y for y in range(2, h - 2) if prof[y] < prof[y - 1] and prof[y] <= prof[y + 1] and prof[y] < thresh]
    # merge minima closer than 8% of a typical period
    merged = []
    for m in mins:
        if merged and m - merged[-1] < h * 0.012:
            if prof[m] < prof[merged[-1]]:
                merged[-1] = m
            continue
        merged.append(m)
    mins = [m for m in merged if m > h * start_min]
    period = np.median(np.diff(mins))
    # keep a run of regular rows
    run = [mins[0]]
    for m in mins[1:]:
        if abs((m - run[-1]) - period) < period * 0.18:
            run.append(m)
        elif len(run) < 6:
            run = [m]
        else:
            break
    return run[0], run[-1], len(run) - 1, period


def fit(a, size):
    img = Image.fromarray(np.clip(a * 255.0 + 0.5, 0, 255).astype(np.uint8))
    return np.asarray(img.resize((size, size), Image.LANCZOS), dtype=np.float32) / 255.0


layers = [
    # name, source id, tile metres, treatment
    ("plaster", "patterned_clay_plaster", 2.0, "neutral"),
    ("timber", "rough_wood", 0.5, ""),
    ("boards", "old_planks_02", 2.0, ""),
    ("rubble", "rustic_stone_wall_02", 1.5, ""),
    ("ashlar", "rustic_stone_wall", 1.52, ""),
    ("thatch", "reed_roof_04", 2.5, "thatch"),
    ("slate", "roof_slates_03", 3.0, "rows"),
    ("shingle", "roof_slates_02", 3.0, "rows"),
    ("iron", "rust_coarse_01", 1.0, "iron"),
    ("linen", "rough_linen", 0.6, "grey"),
    ("cobble", "stone_pathway_02", 1.95, ""),
    ("floor", "brown_planks_09", 1.0, ""),
]

alb_atlas = np.zeros((S * 3, S * 4, 3), np.float32)
nor_atlas = np.zeros((N * 3, N * 4, 4), np.float32)
for i, (name, src, tile, how) in enumerate(layers):
    d = DL
    if how == "rows":
        d = DL2
    diff = load(os.path.join(d, src + "_diff.jpg"), "RGB")
    nor = load(os.path.join(d, src + "_nor.jpg"), "RGB")
    ao = load(os.path.join(d, src + "_ao.jpg"), "L")
    rough = load(os.path.join(d, src + "_rough.jpg"), "L")
    tile_u = tile
    tile_v = tile
    if how == "rows":
        y0, y1, count, period = row_crop(os.path.join(d, src + "_diff.jpg"), 0.06)
        diff, nor, ao, rough = diff[y0:y1], nor[y0:y1], ao[y0:y1], rough[y0:y1]
        tile_v = tile * (y1 - y0) / float(diff.shape[1])
        print("  %s rows %d..%d: %d rows (period %.1f px), course %.3f m" % (name, y0, y1, count, period, tile_v / count))
    if how == "thatch":
        h = diff.shape[0]
        cut = int(h * 0.075)
        diff, nor, ao, rough = diff[cut:], nor[cut:], ao[cut:], rough[cut:]
        diff, nor, ao, rough = seamless_v(diff), seamless_v(nor), seamless_v(ao), seamless_v(rough)
        tile_v = tile * diff.shape[0] / float(diff.shape[1])
    if how == "neutral":
        lum = diff.mean(axis=2, keepdims=True)
        diff = lum + (diff - lum) * 0.35
        diff = diff * (0.72 / diff.mean())
    if how == "grey":
        lum = diff.mean(axis=2, keepdims=True)
        diff = np.repeat(lum * (0.78 / lum.mean()), 3, axis=2)
    if how == "iron":
        lum = diff.mean(axis=2, keepdims=True)
        dark = lum * np.array([0.5, 0.5, 0.53]) * 0.75
        diff = dark * 0.65 + diff * 0.35 * 0.6
    diff = np.clip(diff, 0, 1)
    gx, gy = i % 4, i // 4
    alb_atlas[gy * S:(gy + 1) * S, gx * S:(gx + 1) * S] = fit(diff, S)
    packed = np.dstack([fit(nor, N)[..., 0], fit(nor, N)[..., 1], fit(ao, N), fit(rough, N)])
    nor_atlas[gy * N:(gy + 1) * N, gx * N:(gx + 1) * N] = packed
    print("%2d %-8s %-24s tile %.3f x %.3f m" % (i, name, src, tile_u, tile_v))

os.makedirs(OUT, exist_ok=True)
Image.fromarray(np.clip(alb_atlas * 255 + 0.5, 0, 255).astype(np.uint8)).save(os.path.join(OUT, "arch_albedo.jpg"), quality=86, optimize=True)
Image.fromarray(np.clip(nor_atlas * 255 + 0.5, 0, 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, "arch_normal.webp"), quality=88, alpha_quality=90, method=6)
for f in ("arch_albedo.jpg", "arch_normal.webp"):
    print(f, os.path.getsize(os.path.join(OUT, f)) // 1024, "KB")
