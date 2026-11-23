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

## Layout

The repository holds four Pomes. Each is used from its directory (`[replace]` in `Pome.toml`).

| Pome | Root name | Contents |
|---|---|---|
| `syntax/` | `Syntax` | Lexer, parser, syntax tree (`Tree`), validation and navigation (`Cst`) |
| `fmt/` | `Fmt` | The formatter: documents (`Doc`), the printer and `Format` |
| `check/` | `Check` | Modules, HIR, name resolution and types (`Pipeline` runs them) |
| `core/` | `Core` | The Core IR and lowering from the typed HIR |
| `js/` | `Js` | The JS output of the Core IR |
| `.` | | The command line, `src/main.emel` |

`fmt` and `check` depend on `syntax`, `core` on `check`, `js` on `core`; the root depends on all
of them. Tests live in the Pome they
test.

## Usage

```console
$ (cd syntax && emela test)                          # unit and property tests (Brix), per Pome
$ scripts/roundtrip.sh <emela-lang/emela checkout>   # M1 on the corpus, on js and native
$ scripts/compare.sh tokens <emela-lang/emela checkout>  # tokens against the reference
$ scripts/compare.sh tree <emela-lang/emela checkout>    # syntax trees against the reference
$ scripts/compare.sh fmt <emela-lang/emela checkout>     # formatted output against the reference
$ scripts/fuzz.py tree <emela-lang/emela checkout> <out dir> # trees of broken corpus files
$ scripts/fuzz.py fmt <emela-lang/emela checkout> <out dir>  # fmt of reflowed files, any width
$ scripts/check.sh <emela-lang/emela checkout>      # check diagnostics against the reference
$ scripts/run.sh <emela-lang/emela checkout> [name...]  # run the JS of `graft build` on Node
$ emela run . -- parse <file>...                     # parses the files, to time the parser
```

`tools/oracle` is a small Rust program that prints what the reference implementation
(`emela-syntax` and `emela-fmt` at the tag of the release in `Pome.toml`) makes of a file, in the
format of `graft tokens`, `graft tree` (with every syntax diagnostic) and `graft fmt`. `scripts/compare.sh` builds it with cargo.

The scripts run the `emela` on `PATH`. Put the release in `Pome.toml` first if another version
is installed as the default (`PATH=~/.emela/versions/v0.28.2:$PATH`).

## Status

- M1: done. All 297 files of the corpus at v0.28.2 round-trip on js and native (wasm has no
  `Std.FileSystem` yet).
- M2: done. On all 297 files of the corpus at v0.28.2, the tokens, the syntax trees and the
  diagnostics of the lexer, the parser and validation equal the reference's, and `graft fmt`
  gives byte for byte the output of `emela fmt` (or refuses the same files). So do 1,998 inputs
  made by breaking corpus files (`scripts/fuzz.py tree`) and 1,600 made by moving their whitespace,
  formatted at random widths from 10 to 140 (`scripts/fuzz.py fmt`). Lexing, parsing and validating the corpus (441 KB) takes 0.31 s on native;
  formatting its largest file (18 KB) takes 50 ms.
- M3: done. `graft check <path> <emela-core lib>` prints the same diagnostics (codes and
  positions) as `emela check` on every unit of the corpus (`scripts/check.sh`, 355 units, and
  Graft itself); `tools/oracle check <path>` prints those of `emela check`. It was built in three
  steps:
  1. Modules: collecting the files of a single file or a project, the bundled core and std
     modules, and the import graph (E0201 to E0210).
  2. Name resolution: lowering the tree to HIR, where every name points to its definition
     (E0211 to E0225, W0201, W0202, E0328, E0334), on the corpus and the 39 inputs of the name
     resolution tests of emela-resolve (`test_data/resolve`).
  3. Type checking (E03xx, E04xx), on the corpus and the 214 inputs of the tests of emela-types
     (`test_data/types`): declared signatures, the types of bodies, traits and impls, match
     coverage, error and effect sets, suspension, fiber scopes, `with` items and layers, exports
     and capture sets.

  Not ported, as the corpus never shows them: the checks of `@test`, `@internal`, `@key` and
  `@tag` that the driver of `emela check` adds (E0226 to E0229, E0337, E0338).

  The corpus for M3 is what is written to be checked: the 87 programs of
  `crates/emela-codegen-c/tests/programs` and `crates/emela-cli/tests`, the 11 projects of
  `examples/` and `tests/laws` (all check without errors), Graft itself, and the inputs embedded in
  the tests of emela-resolve and emela-types, which do have errors.
- M4: started. `scripts/run.sh` builds the 73 test programs of
  `crates/emela-codegen-c/tests/programs` with `graft build` and runs the JS with Node through the
  launcher of `emela run`; each must give the exit code, stdout and stderr in its `.expected` (the
  output of `emela run`). The JS runtime (`emela-codegen-js/src/runtime.mjs`) and the launcher are
  read from the checkout, so Graft's JS runs on the reference's runtime. The plan follows
  emela-core and emela-codegen-js:
  1. Keeping what type checking learns about bodies: the types of expressions, patterns and
     locals, call arguments by parameter, type arguments at references, methods and operations.
  2. The Core IR and the lowering of pure code: fns, literals, operators, strings, records and
     enums, match, lists, closures and local fns, self tail calls as loops; monomorphization; the
     JS output.
  3. Traits and derived impls, `dbg` and `inspect`.
  4. Errors (`fail`, `escape`) and effects (evidence passing, handlers, `with`, layers).
  5. Suspension (generators) and fibers.

  Unlike the reference, Graft monomorphizes while lowering (each instance of a definition is
  lowered with its type arguments), and every function and closure takes the evidence table as
  its last parameter. 38 of the 73 programs behave as on `emela run`: what remains is labels and
  handler members in `with`, suspend fn implementations, fibers, `State.run`, and the derived
  `ObjectKey` and `Encode`.
