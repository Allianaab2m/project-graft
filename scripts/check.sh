#!/usr/bin/env bash
# M3: compares the diagnostics of `graft check` and `emela check` (tools/oracle check) on what
# the emela checkout writes to be checked (the test programs of emela-codegen-c and emela-cli, and
# the projects of examples/ and tests/laws), and on the cases with errors in test_data/check and
# test_data/resolve.
# Only the codes Graft reports so far are compared, on both sides.
# usage: scripts/check.sh <path to emela-lang/emela>
set -euo pipefail
emela_repo=${1:?usage: scripts/check.sh <path to emela-lang/emela>}
root=$(cd "$(dirname "$0")/.." && pwd)
oracle="$root/tools/oracle/target/release/graft-oracle"
graft="$root/target/emela/native/main"
core="$emela_repo/crates/emela-core/lib"
# The codes Graft reports: syntax (E01xx), modules and the import graph (E0201 to E0210), name
# resolution (E0211 to E0225, W0201, W0202, E0328, E0334), files (E09xx).
# Of types, the declarations: the codes only signature collection reports (E0322, E0424, E0426,
# E0429, E0433, E0445, E0446, E0450, E0451). Of bodies, the types of expressions and patterns
# (E0301, E0302, E0304 to E0316, E0320, E0323, E0324), match coverage (E0303, E0317, W0301), traits
# and impls (E0326, E0329 to E0333, E0335, E0336, E0339, W0303), const cycles (E0231), the value of
# `main` (W0304), and the parts of handlers and `with` items checked with them (E0401, E0404 to
# E0407, E0413 to E0415, E0418, E0419, E0434, E0435, E0447, E0448, E0452). Of error sets, the
# errors not handled (E0318, E0420), not errors (E0319), set mismatches (E0321) and errors never
# raised (W0302). Of effect sets, the effects not handled (E0402) and set mismatches (E0403),
# Immediate sets and fn operation bodies that may suspend (E0416, E0417), values leaving a fiber
# scope (E0425), and of `with` items and layers, dependency cycles (E0411), duplicate effects
# (E0421), layer cycles (E0422), type arguments right of `by` (E0423), labels (E0430 to E0432)
# and unused label providers (W0401).
implemented='^[a-z]*\[(E01[0-9][0-9]|E02[01][0-9]|E022[0-5]|E0231|W020[12]|E0328|E0334|E09[0-9][0-9]|E032[2]|E042[469]|E0433|E044[56]|E045[01]|E030[1-9]|E031[0-7]|E0320|E032[3469]|E033[0-35-69]|W030[134]|E0401|E040[4-7]|E041[3-589]|E043[45]|E044[78]|E0452|E031[89]|E0321|E0420|E040[23]|W0302|E041[167]|E042[1235]|E043[0-2]|W0401)\]'
# `IMPLEMENTED` replaces the list, to try codes before adding them.
implemented=${IMPLEMENTED:-$implemented}
# Paths are printed as given (Graft) or relative to the current directory (the oracle), so the
# cases of this repository are passed relative to its root.
cd "$root"
(cd "$root/tools/oracle" && cargo build --release --quiet)
(cd "$root" && emela build --target native . 2>/dev/null)
units=()
while IFS= read -r unit; do units+=("$unit"); done < <(
  find "$emela_repo/crates/emela-codegen-c/tests/programs" "$emela_repo/crates/emela-cli/tests" \
    -name '*.emel' | sort
  for dir in "$emela_repo"/examples/*/ "$emela_repo/tests/laws/"; do echo "${dir%/}"; done
  # The projects of test_data/check, whole and from one of their files, and a directory outside
  # any source root (E0208).
  echo test_data/check/cycle
  echo test_data/check/cycle/src/cee.emel
  echo test_data/check/proj
  echo test_data/check
  # The inputs of the name resolution tests of emela-resolve (tests/resolve.rs).
  for dir in test_data/resolve/*/; do echo "${dir%/}"; done
  # The inputs of the type checking tests of emela-types (tests/*.rs).
  for dir in test_data/types/*/; do echo "${dir%/}"; done
)
# Units listed as `check <unit> <reason>` in scripts/known-differences.txt may differ.
known=$(sed -n "s/^check \([^ ]*\).*/\1/p" "$root/scripts/known-differences.txt")
total=0
failed=0
expected=0
for unit in "${units[@]}"; do
  total=$((total + 1))
  if grep -qxF "$unit" <<<"$known"; then
    expected=$((expected + 1))
    continue
  fi
  if ! diff -q <("$graft" check "$unit" "$core" | grep -E "$implemented" || true) \
    <("$oracle" check "$unit" | grep -E "$implemented" || true) >/dev/null; then
    failed=$((failed + 1))
    echo "DIFFERS $unit"
  fi
done
echo "$((total - failed - expected))/$total units match the reference (check), $expected known differences"
[ "$failed" -eq 0 ]
