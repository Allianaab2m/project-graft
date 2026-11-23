#!/usr/bin/env python3
"""Changes .emel files of an emela checkout at random and compares what Graft and the reference
(tools/oracle) make of each result. Mutants that differ are kept in <out dir>.

usage: scripts/fuzz.py <tree|fmt> <path to emela-lang/emela> <out dir> [count] [seed]

- tree: breaks files (deletes and swaps lines, deletes characters, inserts tokens) and compares
  the syntax trees.
- fmt: moves whitespace and line breaks (mostly keeping the program valid) and compares the
  formatted output at a random width.

Build both first (scripts/compare.sh does). A mutant on which the reference crashes, or that
only the reference refuses to format (it checks rules Graft does not check yet), is counted
apart.
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
          "..", ":", "\"", "#{", "derive ", "fails ", "uses ", "pub ", "if ", "else ",
          # Pieces that break strings, escapes and names (lexer diagnostics).
          "\\", "\\u{", "\\u{D800}", "\\q", "\"\"\"", "\"\"\"\n", "&", "$", "0x", "1e", "Ab_c", "\r"]


def reflow(rng, text):
    """Moves whitespace: a line break after a comma or an opening bracket, a joined line, a
    changed indentation or doubled spaces."""
    kind = rng.randrange(4)
    lines = text.split("\n")
    i = rng.randrange(len(lines))
    if kind == 0:
        line = lines[i]
        spots = [k for k, c in enumerate(line) if c in ",([{"]
        if spots:
            k = rng.choice(spots) + 1
            lines[i] = line[:k] + "\n" + " " * rng.randrange(8) + line[k:].lstrip()
    elif kind == 1 and i + 1 < len(lines):
        lines[i] = lines[i] + " " + lines.pop(i + 1).lstrip()
    elif kind == 2:
        lines[i] = " " * rng.randrange(12) + lines[i].lstrip()
    else:
        lines[i] = lines[i].replace(" ", "  ", 1)
    return "\n".join(lines)


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
    if len(sys.argv) < 4 or sys.argv[1] not in ("tree", "fmt"):
        sys.exit(__doc__)
    mode = sys.argv[1]
    corpus, out = pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3])
    count = int(sys.argv[4]) if len(sys.argv) > 4 else 500
    seed = int(sys.argv[5]) if len(sys.argv) > 5 else 1
    out.mkdir(parents=True, exist_ok=True)
    files = sorted(p for p in corpus.rglob("*.emel") if "target" not in p.parts)
    rng = random.Random(seed)
    differ = crashes = refused = 0
    for k in range(count):
        original = rng.choice(files)
        text = original.read_text()
        for _ in range(rng.randrange(1, 4)):
            text = mutate(rng, text) if mode == "tree" else reflow(rng, text)
        path = out / f"m{mode}{seed}_{k}.emel"
        path.write_text(text)
        args = [mode, str(path)]
        if mode == "fmt":
            args.append(str(rng.randrange(10, 141)))
        try:
            graft = subprocess.run([GRAFT, *args], capture_output=True, timeout=20).stdout
        except subprocess.TimeoutExpired:
            graft = b"timeout"
        reference = subprocess.run([ORACLE, *args], capture_output=True)
        if reference.returncode != 0:
            crashes += 1
            print(f"REFERENCE CRASH {path} (from {original})")
        elif mode == "fmt" and reference.stdout == b"error\n" and graft != b"error\n":
            refused += 1
            path.unlink()
        elif graft != reference.stdout:
            differ += 1
            print(f"DIFFERS {path} (from {original}) {' '.join(args[2:])}")
        else:
            path.unlink()
    compared = count - crashes - refused
    print(f"{compared - differ}/{compared} mutants match, {crashes} reference crashes, "
          f"{refused} refused only by the reference")
    sys.exit(1 if differ else 0)


if __name__ == "__main__":
    main()
