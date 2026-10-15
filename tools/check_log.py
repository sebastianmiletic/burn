#!/usr/bin/env python3
"""Godot can return zero after script errors. Fail CI on those diagnostics."""
import pathlib
import sys

bad = False
for name in sys.argv[1:]:
    path = pathlib.Path(name)
    if not path.is_file():
        print(f"Missing test log: {path}", file=sys.stderr)
        bad = True
        continue
    for line in path.read_text(errors="replace").splitlines():
        if any(marker in line for marker in ("SCRIPT ERROR:", "SHADER ERROR:", "Parse Error:", "Compile Error:", "FAIL  ", "FAIL:", " FAILED", "handle_crash:", "Fatal error")):
            print(f"{path}: {line}", file=sys.stderr)
            bad = True
        # Existing Godot teardown resource diagnostics are not test assertions.
        if line.startswith("ERROR:") and "resources still in use at exit" not in line:
            print(f"{path}: {line}", file=sys.stderr)
            bad = True
sys.exit(1 if bad else 0)
