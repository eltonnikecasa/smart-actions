#!/usr/bin/env bash
# Consume package.sh output, or a temporary shell fixture when no package is given.
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
fixture=0
if (($#)); then
    RELEASE_ASSETS="$(realpath "$1")"
else
    fixture=1
    RELEASE_ASSETS="$TMP/sa-1234567890123456789012345678901234567890"
    mkdir -p "$RELEASE_ASSETS" "$TMP/payload/bin" "$TMP/payload/scripts"
    for rel in bin/smart-actions bin/smart-actions-manager scripts/smart-actions-launcher; do
        printf '#!/bin/sh\nexit 0\n' > "$TMP/payload/$rel"
    done
    cp "$ROOT/smart-actions-governor.sh" "$TMP/payload/"
    printf 'commit=%s\nplatform=linux-x86_64\n' "${RELEASE_ASSETS##*/sa-}" > "$TMP/payload/release.txt"
    for rel in bin/smart-actions bin/smart-actions-manager scripts/smart-actions-launcher smart-actions-governor.sh release.txt; do
        hash="$(sha256sum "$TMP/payload/$rel" | cut -d ' ' -f1)"
        printf '%s  %s\n' "$hash" "$rel" >> "$RELEASE_ASSETS/manifest-linux-x86_64.sha256"
        cp "$TMP/payload/$rel" "$RELEASE_ASSETS/sha256-$hash"
    done
fi
export RELEASE_ASSETS RELEASE_TAG="${RELEASE_ASSETS##*/}" REQUEST_LOG="$TMP/requests"
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
printf '%s\n' "$url" >> "$REQUEST_LOG"
case "$url" in
    https://github.com/eltonnikecasa/smart-actions/releases/latest)
        printf 'https://github.com/eltonnikecasa/smart-actions/releases/tag/%s' "$RELEASE_TAG" ;;
    "https://api.github.com/repos/eltonnikecasa/smart-actions/releases/tags/$RELEASE_TAG")
        printf '{\n  "immutable": true\n}\n' ;;
    "https://github.com/eltonnikecasa/smart-actions/releases/download/$RELEASE_TAG/manifest-linux-x86_64.sha256")
        cp "$RELEASE_ASSETS/${url##*/}" "$output" ;;
    "https://github.com/eltonnikecasa/smart-actions/releases/download/$RELEASE_TAG/sha256-"*)
        [[ "${url##*/}" =~ ^sha256-[0-9a-f]{64}$ ]] || exit 1
        cp "$RELEASE_ASSETS/${url##*/}" "$output" ;;
    *) echo "Unexpected URL: $url" >&2; exit 1 ;;
esac
MOCK
chmod +x "$TMP/path/curl"
export PATH="$TMP/path"
! command -v cargo && ! command -v rustc
bash "$ROOT/smart-actions-governor.sh" install
{
    printf '%s\n' 'https://github.com/eltonnikecasa/smart-actions/releases/latest'
    printf 'https://api.github.com/repos/eltonnikecasa/smart-actions/releases/tags/%s\n' "$RELEASE_TAG"
    printf 'https://github.com/eltonnikecasa/smart-actions/releases/download/%s/manifest-linux-x86_64.sha256\n' "$RELEASE_TAG"
    while read -r hash rel; do
        printf 'https://github.com/eltonnikecasa/smart-actions/releases/download/%s/sha256-%s\n' "$RELEASE_TAG" "$hash"
    done < "$RELEASE_ASSETS/manifest-linux-x86_64.sha256"
} | LC_ALL=C sort > "$TMP/expected-urls"
LC_ALL=C sort "$REQUEST_LOG" > "$TMP/actual-urls"
diff -u "$TMP/expected-urls" "$TMP/actual-urls"
printf 'PASS: exact latest, release API, platform manifest and sha256 asset URLs\n'
cli="$XDG_DATA_HOME/smart-actions/bin/smart-actions"
"$cli" --help >/dev/null
before="$(stat -c '%i:%Y' "$cli")"
bash "$ROOT/smart-actions-governor.sh" update
[[ $(stat -c '%i:%Y' "$cli") == "$before" ]]
printf corruption > "$cli"
bash "$ROOT/smart-actions-governor.sh" repair
"$cli" --help >/dev/null
bash "$ROOT/smart-actions-governor.sh" doctor
if ((fixture)); then
    printf 'PASS: simulated distribution install/update/repair/doctor without Cargo/rustc\n'
else
    printf 'PASS: real package install/update/repair/doctor without Cargo/rustc\n'
fi
