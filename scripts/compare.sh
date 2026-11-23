#!/usr/bin/env bash
# Compares what Graft and the reference implementation (tools/oracle) make of every .emel file of
# an emela checkout, and lists the files that differ. Files listed in scripts/known-differences.txt
# for the mode are reported apart and do not fail the comparison.
# usage: scripts/compare.sh <tokens|tree|fmt> <path to emela-lang/emela>
set -euo pipefail
mode=${1:?usage: scripts/compare.sh <tokens|tree|fmt> <path to emela-lang/emela>}
emela_repo=${2:?usage: scripts/compare.sh <tokens|tree|fmt> <path to emela-lang/emela>}
root=$(cd "$(dirname "$0")/.." && pwd)
oracle="$root/tools/oracle/target/release/graft-oracle"
graft="$root/target/emela/native/main"
(cd "$root/tools/oracle" && cargo build --release --quiet)
(cd "$root" && emela build --target native . 2>/dev/null)
known=$(sed -n "s/^$mode \([^ ]*\).*/\1/p" "$root/scripts/known-differences.txt")
total=0
failed=0
expected=0
while IFS= read -r file; do
  total=$((total + 1))
  if ! diff -q <("$graft" "$mode" "$file") <("$oracle" "$mode" "$file" 2>/dev/null) >/dev/null; then
    if grep -qxF "${file#"$emela_repo"/}" <<<"$known"; then
      expected=$((expected + 1))
      echo "KNOWN   $file"
    else
      failed=$((failed + 1))
      echo "DIFFERS $file"
    fi
  fi
done < <(find "$emela_repo" -name '*.emel' -not -path '*/target/*' | sort)
echo "$((total - failed - expected))/$total files match the reference ($mode), $expected known differences"
[ "$failed" -eq 0 ]
