#!/usr/bin/env bash
# M1: lexes every .emel file of an emela checkout and checks that the tokens concatenate back to
# the file, on each target that has Std.FileSystem.
# usage: scripts/roundtrip.sh <path to emela-lang/emela>
set -euo pipefail
emela_repo=${1:?usage: scripts/roundtrip.sh <path to emela-lang/emela>}
mapfile -t files < <(find "$emela_repo" -name '*.emel' -not -path '*/target/*' | sort)
for target in js native; do
  echo "== $target"
  emela run --target "$target" . -- roundtrip "${files[@]}" 2>/dev/null
done
