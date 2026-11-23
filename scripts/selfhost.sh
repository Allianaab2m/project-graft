#!/usr/bin/env bash
# M5: builds Graft itself to JS with `graft build` into target/js, and writes target/js/graft, a
# command that runs it with Node through the launcher of `emela run`. The comparison scripts use
# it in place of the native build with `GRAFT=target/js/graft`.
# The JS runtime and the launcher are read from the checkout, as in scripts/run.sh.
# usage: scripts/selfhost.sh <path to emela-lang/emela>
set -euo pipefail
emela_repo=${1:?usage: scripts/selfhost.sh <path to emela-lang/emela>}
emela_repo=$(cd "$emela_repo" && pwd)
root=$(cd "$(dirname "$0")/.." && pwd)
out="$root/target/js"
(cd "$root" && emela build --target native . 2>/dev/null)
mkdir -p "$out"
"$root/target/emela/native/main" build "$root" "$emela_repo/crates/emela-core/lib" \
  "$emela_repo/crates/emela-codegen-js/src/runtime.mjs" "$out"
# The launcher is the raw string `LAUNCHER` of emela-driver's run.rs.
sed -n '/^const LAUNCHER: &str = r#"$/,/^"#;$/p' "$emela_repo/crates/emela-driver/src/run.rs" \
  | sed '1d;$d' >"$out/launcher.mjs"
cat >"$out/graft" <<EOF
#!/usr/bin/env bash
# Graft recurses deeply (lists are folded recursively): the stack is raised to what macOS allows.
ulimit -s 65520 2>/dev/null || ulimit -s unlimited 2>/dev/null || true
exec node --stack-size=60000 --input-type=module -e "\$(cat "$out/launcher.mjs")" -- "$out/main.mjs" "\$@"
EOF
chmod +x "$out/graft"
echo "built $out/graft"
