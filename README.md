# Project Graft

An Emela implementation of Emela, written to find out where the language is hard to write and slow
to run, and to send those findings back to Emela.

The name is from grafting, the way apple trees (pomes) are propagated: a scion is joined onto a
rootstock. The reference implementation in Rust is the rootstock; Graft is the scion.

## Goals

- Write the front end and a back end of Emela in Emela.
- Record every place where the language, std or Brix got in the way, in `FRICTION.md`.
- Measure how fast Graft processes its corpus on each target, release by release.

Replacing the Rust implementation is not a goal. It stays the reference that Graft's output is
compared with.

## Rules

- Depend only on a released `emela` and its bundled core and std. Brix
  (`github.com/emela-lang/brix`) is the only other Pome, as a test dependency.
- Read the specification at the tag of the release in `Pome.toml` (`emela = ...`), not at `main`.
  Features on `main` that are not released do not exist for Graft.
- Do not enable `[experimental]` features. If one is needed, record why in `FRICTION.md`.
- When Emela releases a new version, raise `emela` in `Pome.toml` and rebuild. What breaks is a
  compatibility report.
- Code and comments are in English. `FRICTION.md` may be in Japanese.

## Milestones

Each milestone is done when Graft's output matches the reference implementation on the corpus.

| | Contents | Done when |
|---|---|---|
| M1 | lexer | Every `.emel` of the corpus lexes into tokens that concatenate back to the file |
| M2 | parser + fmt | `graft fmt` gives byte for byte the output of `emela fmt` on the corpus |
| M3 | resolve + type checking | The positions and codes of diagnostics match `emela check` |
| M4 | lowering + JS codegen | The generated JS runs with the same result as `emela run` |

The corpus is every `.emel` file in the `emela-lang/emela` repository at the release tag.

## Usage

```console
$ emela test                                         # unit and property tests (Brix)
$ scripts/roundtrip.sh <emela-lang/emela checkout>   # M1 on the corpus, on js and native
$ scripts/compare.sh tokens <emela-lang/emela checkout>  # tokens against the reference
$ scripts/compare.sh tree <emela-lang/emela checkout>    # syntax trees against the reference
$ scripts/compare.sh fmt <emela-lang/emela checkout>     # formatted output against the reference
$ scripts/fuzz.py tree <emela-lang/emela checkout> <out dir> # trees of broken corpus files
$ scripts/fuzz.py fmt <emela-lang/emela checkout> <out dir>  # fmt of reflowed files, any width
$ emela run . -- parse <file>...                     # parses the files, to time the parser
```

`tools/oracle` is a small Rust program that prints what the reference implementation
(`emela-syntax` and `emela-fmt` at the tag of the release in `Pome.toml`) makes of a file, in the
format of `graft tokens`, `graft tree` and `graft fmt`. `scripts/compare.sh` builds it with cargo.

The scripts run the `emela` on `PATH`. Put the release in `Pome.toml` first if another version
is installed as the default (`PATH=~/.emela/versions/v0.28.2:$PATH`).

## Status

- M1: done. All 297 files of the corpus at v0.28.2 round-trip on js and native (wasm has no
  `Std.FileSystem` yet).
- M2, parser: the tokens and the syntax trees, with the parser's diagnostics, of all 297 files
  equal the reference's. So do those of 4,394 inputs made by breaking corpus files at random.
  Lexing and parsing the corpus (441 KB) takes 0.29 s on native.
- M2, fmt: `graft fmt` gives byte for byte the output of `emela fmt` on every file the reference
  formats (254 of 297), and refuses the same files for syntax errors, except 4 that only the
  reference's validation rejects (`scripts/known-differences.txt`). So do 3,158 inputs made by
  moving whitespace in corpus files, formatted at random widths from 10 to 140. Formatting the
  largest file (18 KB) takes 54 ms on native.
