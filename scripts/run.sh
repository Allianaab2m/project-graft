#!/usr/bin/env bash
# M4: builds the test programs of emela-codegen-c with `graft build` and runs the JS with Node,
# through the launcher of `emela run`. Each `tests/programs/NAME.emel` has in `NAME.expected` the
# exit code, stdout and stderr of `emela run`; the output of Graft's JS must be the same.
# The JS runtime and the launcher are read from the checkout, at the tag of the release in
# Pome.toml, so that Graft's output runs on the same runtime as the reference's.
# usage: scripts/run.sh <path to emela-lang/emela> [name...]
set -uo pipefail
emela_repo=${1:?usage: scripts/run.sh <path to emela-lang/emela> [name...]}
shift
root=$(cd "$(dirname "$0")/.." && pwd)
graft="$root/target/emela/native/main"
core="$emela_repo/crates/emela-core/lib"
runtime="$emela_repo/crates/emela-codegen-js/src/runtime.mjs"
programs="$emela_repo/crates/emela-codegen-c/tests/programs"
(cd "$root" && emela build --target native . 2>/dev/null)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
# The launcher is the raw string `LAUNCHER` of emela-driver's run.rs.
launcher=$(sed -n '/^const LAUNCHER: &str = r#"$/,/^"#;$/p' "$emela_repo/crates/emela-driver/src/run.rs" | sed '1d;$d')
if [ "$#" -gt 0 ]; then
  names=("$@")
else
  names=()
  for expected in "$programs"/*.expected; do names+=("$(basename "$expected" .expected)"); done
fi
total=0
passed=0
for name in "${names[@]}"; do
  total=$((total + 1))
  out="$work/$name"
  if ! "$graft" build "$programs/$name.emel" "$core" "$runtime" "$out" >"$work/$name.build" 2>&1; then
    echo "BUILD FAILS $name: $(head -1 "$work/$name.build")"
    continue
  fi
  # At most 20 seconds per program (perl's alarm, as macOS has no `timeout`).
  (cd "$out" && perl -e 'alarm 20; exec @ARGV' node --input-type=module -e "$launcher" -- "$out/main.mjs" \
    >"$work/$name.stdout" 2>"$work/$name.stderr")
  code=$?
  {
    printf 'exit: %s\n--- stdout\n' "$code"
    cat "$work/$name.stdout"
    printf -- '--- stderr\n'
    cat "$work/$name.stderr"
  } >"$work/$name.actual"
  if cmp -s "$work/$name.actual" "$programs/$name.expected"; then
    passed=$((passed + 1))
  else
    echo "DIFFERS $name"
  fi
done
echo "$passed/$total programs behave as on emela run"
[ "$passed" -eq "$total" ]
