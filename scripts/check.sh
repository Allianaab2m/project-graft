#!/usr/bin/env bash
# M3: compares the diagnostics of `graft check` and `emela check` (tools/oracle check) on what
# the emela checkout writes to be checked (the test programs of emela-codegen-c and emela-cli, and
# the projects of examples/ and tests/laws), and on the cases with errors in test_data/check and
# test_data/resolve.
# usage: scripts/check.sh <path to emela-lang/emela>
set -euo pipefail
emela_repo=${1:?usage: scripts/check.sh <path to emela-lang/emela>}
root=$(cd "$(dirname "$0")/.." && pwd)
oracle="$root/tools/oracle/target/release/graft-oracle"
# `GRAFT` replaces the native build of Graft with another command (the JS build of M5).
graft=${GRAFT:-"$root/target/emela/native/main"}
core="$emela_repo/crates/emela-core/lib"
# Every diagnostic is compared. `emela check` also reports a few codes that come from the driver
# rather than from type checking and that the corpus never shows (`@test`, `@internal`, `@key` and
# `@tag`: E0226 to E0229, E0337, E0338); Graft does not report them yet.
implemented='.'
# `IMPLEMENTED` limits the comparison to the lines it matches (a regular expression).
implemented=${IMPLEMENTED:-$implemented}
# Paths are printed as given (Graft) or relative to the current directory (the oracle), so the
# cases of this repository are passed relative to its root.
cd "$root"
(cd "$root/tools/oracle" && cargo build --release --quiet)
[ -n "${GRAFT:-}" ] || (cd "$root" && emela build --target native . 2>/dev/null)
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
