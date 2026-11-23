#!/usr/bin/env python3
"""Breaks .emel files of an emela checkout at random and compares Graft's syntax tree of each
result with the reference's (tools/oracle). Mutants that differ are kept in <out dir>.

usage: scripts/fuzz.py <path to emela-lang/emela> <out dir> [count] [seed]

Build both first (scripts/compare.sh tree does). A mutant on which the reference crashes is
counted apart: there is no reference tree to compare with.
"""
import pathlib
import random
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
GRAFT = ROOT / "target/emela/native/main"
ORACLE = ROOT / "tools/oracle/target/release/graft-oracle"
# Tokens that open and close constructs, inserted at random.
PIECES = ["{", "}", "(", ")", "[", "]", "|", "||", ",", "\n", "=", "->", "fn ", "match ", "@",
          "..", ":", "\"", "#{", "derive ", "fails ", "uses ", "pub ", "if ", "else "]


def mutate(rng, text):
    kind = rng.randrange(4)
    if kind == 0 and "\n" in text:
        lines = text.split("\n")
        del lines[rng.randrange(len(lines))]
        return "\n".join(lines)
    if kind == 1:
        i = rng.randrange(len(text) + 1)
        return text[:i] + text[min(len(text), i + rng.randrange(1, 12)):]
    if kind == 2:
        i = rng.randrange(len(text) + 1)
        return text[:i] + rng.choice(PIECES) + text[i:]
    lines = text.split("\n")
    if len(lines) > 2:
        i = rng.randrange(len(lines) - 1)
        lines[i], lines[i + 1] = lines[i + 1], lines[i]
    return "\n".join(lines)


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    corpus, out = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
    count = int(sys.argv[3]) if len(sys.argv) > 3 else 500
    seed = int(sys.argv[4]) if len(sys.argv) > 4 else 1
    out.mkdir(parents=True, exist_ok=True)
    files = sorted(p for p in corpus.rglob("*.emel") if "target" not in p.parts)
    rng = random.Random(seed)
    differ = crashes = 0
    for k in range(count):
        original = rng.choice(files)
        text = original.read_text()
        for _ in range(rng.randrange(1, 4)):
            text = mutate(rng, text)
        path = out / f"m{seed}_{k}.emel"
        path.write_text(text)
        try:
            graft = subprocess.run([GRAFT, "tree", path], capture_output=True, timeout=20).stdout
        except subprocess.TimeoutExpired:
            graft = b"timeout"
        reference = subprocess.run([ORACLE, "tree", path], capture_output=True)
        if reference.returncode != 0:
            crashes += 1
            print(f"REFERENCE CRASH {path} (from {original})")
        elif graft != reference.stdout:
            differ += 1
            print(f"DIFFERS {path} (from {original})")
        else:
            path.unlink()
    compared = count - crashes
    print(f"{compared - differ}/{compared} mutants match, {crashes} reference crashes")
    sys.exit(1 if differ else 0)


if __name__ == "__main__":
    main()
