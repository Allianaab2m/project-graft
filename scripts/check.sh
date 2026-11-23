#!/usr/bin/env bash
# M3: compares the diagnostics of `graft check` and `emela check` (tools/oracle check) on what
# the emela checkout writes to be checked (the test programs of emela-codegen-c and emela-cli, and
# the projects of examples/ and tests/laws), and on the cases with errors in test_data/check.
# Only the codes Graft reports so far are compared.
# usage: scripts/check.sh <path to emela-lang/emela>
set -euo pipefail
emela_repo=${1:?usage: scripts/check.sh <path to emela-lang/emela>}
root=$(cd "$(dirname "$0")/.." && pwd)
oracle="$root/tools/oracle/target/release/graft-oracle"
graft="$root/target/emela/native/main"
core="$emela_repo/crates/emela-core/lib"
# The codes Graft reports: syntax (E01xx), modules and the import graph (E0201 to E0210), files.
implemented='^[a-z]*\[(E01[0-9][0-9]|E020[0-9]|E0210|E09[0-9][0-9])\]'
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
)
total=0
failed=0
for unit in "${units[@]}"; do
  total=$((total + 1))
  if ! diff -q <("$graft" check "$unit" "$core") \
    <("$oracle" check "$unit" | grep -E "$implemented" || true) >/dev/null; then
    failed=$((failed + 1))
    echo "DIFFERS $unit"
  fi
done
echo "$((total - failed))/$total units match the reference (check)"
[ "$failed" -eq 0 ]
