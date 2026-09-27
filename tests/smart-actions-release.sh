#!/usr/bin/env bash
# End-to-end consumer of package.sh output; only HTTPS transport is simulated.
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export RELEASE_ASSETS="$(realpath "${1:?Usage: tests/smart-actions-release.sh dist/sa-COMMIT}")"
export RELEASE_TAG="${RELEASE_ASSETS##*/}"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
export HOME="$TMP/home" XDG_DATA_HOME="$TMP/data" XDG_CONFIG_HOME="$TMP/config" XDG_STATE_HOME="$TMP/state" XDG_BIN_HOME="$TMP/bin" TMPDIR="$TMP/tmp" SMART_ACTIONS_TESTING=1 XDG_CURRENT_DESKTOP=KDE
mkdir -p "$HOME" "$TMPDIR" "$TMP/path"
for executable in /usr/bin/*; do
    case "${executable##*/}" in cargo*|rustc*|rustup*|curl) continue ;; esac
    [[ ! -x "$executable" || -d "$executable" ]] || ln -s "$executable" "$TMP/path/"
done
cat > "$TMP/path/curl" <<'MOCK'
#!/bin/bash
set -eu
url='' output=''
while (($#)); do
    if [[ "$1" == -o ]]; then output="$2"; shift 2
    else [[ "$1" != https://* ]] || url="$1"; shift; fi
done
case "$url" in
    https://github.com/eltonnikecasa/smart-actions/releases/latest)
        printf 'https://github.com/eltonnikecasa/smart-actions/releases/tag/%s' "$RELEASE_TAG" ;;
    "https://api.github.com/repos/eltonnikecasa/smart-actions/releases/tags/$RELEASE_TAG")
        printf '{\n  "immutable": true\n}\n' ;;
    "https://github.com/eltonnikecasa/smart-actions/releases/download/$RELEASE_TAG/"*)
        cp "$RELEASE_ASSETS/${url##*/}" "$output" ;;
    *) echo "Unexpected URL: $url" >&2; exit 1 ;;
esac
MOCK
chmod +x "$TMP/path/curl"
export PATH="$TMP/path"
! command -v cargo && ! command -v rustc
bash "$ROOT/smart-actions-governor.sh" install
cli="$XDG_DATA_HOME/smart-actions/bin/smart-actions"
"$cli" --help >/dev/null
before="$(stat -c '%i:%Y' "$cli")"
bash "$ROOT/smart-actions-governor.sh" update
[[ $(stat -c '%i:%Y' "$cli") == "$before" ]]
printf corruption > "$cli"
bash "$ROOT/smart-actions-governor.sh" repair
"$cli" --help >/dev/null
bash "$ROOT/smart-actions-governor.sh" doctor
printf 'PASS: real package install/update/repair/doctor without Cargo/rustc\n'
