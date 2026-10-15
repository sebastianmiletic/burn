"""CPU-time profile of sound rendering, robust to a busy machine (user CPU, not wall).

    python3 tests/audio/cpu_profile.py [sound ...]      # default: every sound, variant 0
    python3 tests/audio/cpu_profile.py --amb [bed ...]  # ambience beds

Runs the render tool once per item and subtracts the cost of an empty run.
"""
import os, re, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def cpu(args):
    out = tempfile.mkdtemp()
    cmd = ["/usr/bin/time", "-p", "godot", "--headless", "--path", ROOT, "-s", "res://tests/audio/render_sounds.gd",
           "--", "out=" + out] + args
    p = subprocess.run(cmd, capture_output=True, text=True)
    m = re.search(r"user ([0-9.]+)", p.stderr + p.stdout)
    return float(m.group(1)) if m else float("nan")


def names(amb):
    src = open(os.path.join(ROOT, "audio", "ambience_library.gd" if amb else "sfx_library.gd")).read()
    if amb:
        block = src[src.index("const BEDS"):]
        block = block[:block.index("]")]
        return re.findall(r'"([a-z_]+)"', block)
    block = src[src.index("const SOUNDS"):]
    block = block[:block.index("\n}")]
    return re.findall(r'"([a-z_]+)":', block)


def main():
    args = sys.argv[1:]
    amb = "--amb" in args
    args = [a for a in args if a != "--amb"]
    items = args or names(amb)
    base = min(cpu(["only=__none__", "first"]) for _ in range(2))
    print(f"empty run {base:.2f} s CPU")
    total = 0.0
    rows = []
    for it in items:
        c = cpu(["only=" + it] + (["nosfx"] if amb else ["first", "noamb"])) - base
        rows.append((c, it))
        total += c
        print(f"{it:18s} {c:6.2f} s", flush=True)
    print(f"total {total:.2f} s CPU")
    for c, it in sorted(rows, reverse=True)[:15]:
        print(f"  {it:18s} {c:6.2f}")


if __name__ == "__main__":
    main()
