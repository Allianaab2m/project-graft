#!/usr/bin/env bash
# Compares what Graft and the reference implementation (tools/oracle) make of every .emel file of
# an emela checkout, and lists the files that differ.
# usage: scripts/compare.sh <tokens|tree> <path to emela-lang/emela>
set -euo pipefail
mode=${1:?usage: scripts/compare.sh <tokens|tree> <path to emela-lang/emela>}
emela_repo=${2:?usage: scripts/compare.sh <tokens|tree> <path to emela-lang/emela>}
root=$(cd "$(dirname "$0")/.." && pwd)
oracle="$root/tools/oracle/target/release/graft-oracle"
graft="$root/target/emela/native/main"
(cd "$root/tools/oracle" && cargo build --release --quiet)
(cd "$root" && emela build --target native . 2>/dev/null)
total=0
failed=0
while IFS= read -r file; do
  total=$((total + 1))
  if ! diff -q <("$graft" "$mode" "$file") <("$oracle" "$mode" "$file") >/dev/null; then
    failed=$((failed + 1))
    echo "DIFFERS $file"
  fi
done < <(find "$emela_repo" -name '*.emel' -not -path '*/target/*' | sort)
echo "$((total - failed))/$total files match the reference ($mode)"
[ "$failed" -eq 0 ]
