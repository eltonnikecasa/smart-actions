#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if grep -nE '\[https?://.*\]\(https?://' "$ROOT/smart-actions-governor.sh"; then
    printf 'FAIL: Markdown URL in Governor runtime\n' >&2
    exit 1
fi
printf 'PASS: Governor runtime contains no Markdown URLs\n'
TMP="$(mktemp -d)"
export HOME="$TMP/home" XDG_DATA_HOME="$TMP/data" XDG_CONFIG_HOME="$TMP/config" XDG_STATE_HOME="$TMP/state" XDG_BIN_HOME="$TMP/bin" SMART_ACTIONS_TESTING=1
mkdir -p "$HOME"
SMART_ACTIONS_GOVERNOR_LIBRARY_ONLY=1 source "$ROOT/smart-actions-governor.sh"
trap 'rm -rf -- "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
for mock_arch in x86_64 amd64; do
    uname() { if [[ "$1" == -s ]]; then echo Linux; else echo "$mock_arch"; fi; }
    detect_platform
    [[ "$PLATFORM" == linux-x86_64 ]] || fail 'architecture normalization'
done
mock_arch=aarch64
if (detect_platform) > "$TMP/error" 2>&1; then fail 'unsupported architecture accepted'; fi
grep -q 'Não existe build' "$TMP/error"
unset -f uname
printf 'PASS: Linux x86_64/amd64 supported; aarch64 explicitly rejected\n'

TMP_DIR="$TMP/transaction"
mkdir -p "$TMP_DIR" "$BIN_DIR" "$STATE_DIR"
printf old-cli > "$BIN_DIR/smart-actions"
printf old-manager > "$BIN_DIR/smart-actions-manager"
chmod +x "$BIN_DIR/"*
sha=1234567890123456789012345678901234567890
printf '%s\n' "$sha" > "$STATE_DIR/installed-sha"
OLD_MAP=([bin/smart-actions]="$(sha256_file "$BIN_DIR/smart-actions")" [bin/smart-actions-manager]="$(sha256_file "$BIN_DIR/smart-actions-manager")")
for path in "${!OLD_MAP[@]}"; do printf '%s  %s\n' "${OLD_MAP[$path]}" "$path"; done > "$INSTALLED_MANIFEST"
cp "$INSTALLED_MANIFEST" "$TMP/previous"
REMOTE_MAP=([bin/smart-actions]="$(printf new-cli | sha256sum | cut -d ' ' -f1)" [bin/smart-actions-manager]="${OLD_MAP[bin/smart-actions-manager]}")
fetch_raw() { printf corrupt > "$3"; }
manifest_plan 0
if (download_paths "$sha") > "$TMP/error" 2>&1; then fail 'bad hash accepted'; fi
grep -q 'SHA-256 mismatch' "$TMP/error"
[[ $(cat "$BIN_DIR/smart-actions") == old-cli ]] || fail 'bad binary applied'
cmp "$INSTALLED_MANIFEST" "$TMP/previous"
echo 'PASS: invalid binary hash aborts before applying; prior installation preserved'
fetch_raw() { printf '%s\n' "$2" >> "$TMP/transfers"; printf new-cli > "$3"; }
download_paths "$sha"
[[ $(cat "$TMP/transfers") == bin/smart-actions ]] || fail 'unchanged binary transferred'
before="$(stat -c '%i:%Y' "$BIN_DIR/smart-actions-manager")"
for path in "${!REMOTE_MAP[@]}"; do printf '%s  %s\n' "${REMOTE_MAP[$path]}" "$path"; done > "$TMP_DIR/remote-manifest.sha256"
desktop_hint=KDE
regenerate_kde_menu() { return 1; }
if (apply_package "$sha" "$TMP_DIR/remote-manifest.sha256"); then fail 'integration failure accepted'; fi
[[ $(cat "$BIN_DIR/smart-actions") == old-cli ]] || fail 'binary rollback failed'
[[ $(stat -c '%i:%Y' "$BIN_DIR/smart-actions-manager") == "$before" ]] || fail 'unchanged binary replaced'
cmp "$INSTALLED_MANIFEST" "$TMP/previous"
echo 'PASS: binary rollback and unchanged binary transfer/inode preservation'
desktop_hint=''
apply_package "$sha" "$TMP_DIR/remote-manifest.sha256"
[[ $(cat "$BIN_DIR/smart-actions") == new-cli && -x "$BIN_DIR/smart-actions" ]] || fail 'binary update failed'
[[ $(stat -c '%i:%Y' "$BIN_DIR/smart-actions-manager") == "$before" ]] || fail 'unchanged binary replaced'
echo 'PASS: successful binary update preserves unchanged binary'
