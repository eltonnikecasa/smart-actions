#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/smart-actions-manifest-test.XXXXXXXX")"
trap 'rm -rf -- "$TMP"' EXIT
export HOME="$TMP/home" XDG_DATA_HOME="$TMP/data" XDG_CONFIG_HOME="$TMP/config" XDG_STATE_HOME="$TMP/state" XDG_BIN_HOME="$TMP/bin" TMPDIR="$TMP/tmp" SMART_ACTIONS_TESTING=1
mkdir -p "$HOME" "$TMPDIR"
SMART_ACTIONS_GOVERNOR_LIBRARY_ONLY=1 source "$ROOT/smart-actions-governor.sh"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$*"; }
hash_text() { printf '%s' "$1" | sha256sum | cut -d ' ' -f1; }

# Deterministic allowlisted generation excludes personal state, target, and itself.
FIXTURE="$TMP/project"
mkdir -p "$FIXTURE/scripts" "$FIXTURE/crates/cli/src" "$FIXTURE/presets/video" "$FIXTURE/lang" "$FIXTURE/assets/icons" "$FIXTURE/target" "$FIXTURE/.config/smart-actions/presets"
printf '# lock fixture\n' > "$FIXTURE/Cargo.lock"
printf '[workspace]\n' > "$FIXTURE/Cargo.toml"
printf '[package]\n' > "$FIXTURE/crates/cli/Cargo.toml"
printf 'fn main() {}\n' > "$FIXTURE/crates/cli/src/main.rs"
printf 'data\n' > "$FIXTURE/presets/video/a.yaml"
printf 'language\n' > "$FIXTURE/lang/en_US.yaml"
printf 'icon\n' > "$FIXTURE/assets/icons/a.svg"
printf '#!/bin/sh\n' > "$FIXTURE/scripts/smart-actions-launcher"
printf '#!/bin/sh\n' > "$FIXTURE/smart-actions-governor.sh"
printf 'personal\n' > "$FIXTURE/.config/smart-actions/presets/private.yaml"
printf 'artifact\n' > "$FIXTURE/target/output"
git -C "$FIXTURE" init -q
git -C "$FIXTURE" add .
manifest_generate "$FIXTURE" >/dev/null
cp "$FIXTURE/smart-actions-manifest.sha256" "$TMP/first"
mkdir -p "$FIXTURE/presets/custom"
printf personal > "$FIXTURE/presets/custom/private.yaml"
printf personal > "$FIXTURE/presets/video/untracked.yaml"
git -C "$FIXTURE" add presets/custom

manifest_generate "$FIXTURE" >/dev/null
cmp -s "$TMP/first" "$FIXTURE/smart-actions-manifest.sha256" || fail 'manifest generation is nondeterministic'
! rg -q 'private.yaml|target/|smart-actions-manifest' "$FIXTURE/smart-actions-manifest.sha256" || fail 'personal/build/self file was included'
(cd "$FIXTURE" && sha256sum -c smart-actions-manifest.sha256) >/dev/null
rg -q '  Cargo.lock$' "$FIXTURE/smart-actions-manifest.sha256" || fail 'Cargo.lock absent'
pass 'manifest generation is deterministic and excludes private/build files'

# Reject traversal, absolute, malformed, and duplicate entries.
declare -A PARSED=()
for path in '../arquivo' '../../etc/passwd' '/etc/passwd' 'foo/../../../tmp/x' '/home/user/file' 'presets/x/../../escape'; do
    printf '%s  %s\n' "$(printf a%.0s {1..64})" "$path" > "$TMP/bad"
    if manifest_load "$TMP/bad" PARSED; then fail "accepted unsafe path $path"; fi
done
pass 'manifest parsing rejects path traversal and absolute paths'

# Change classes for distribution files.
mkdir -p "$BIN_DIR"
printf '#!/bin/sh\n' > "$BIN_DIR/smart-actions"
printf '#!/bin/sh\n' > "$BIN_DIR/smart-actions-manager"
chmod +x "$BIN_DIR/smart-actions" "$BIN_DIR/smart-actions-manager"
OLD_MAP=([assets/icons/a.svg]="$(hash_text same)" [presets/video/change.yaml]="$(hash_text old)" [presets/video/remove.yaml]="$(hash_text remove)" [bin/smart-actions]="$(hash_text binary)")
REMOTE_MAP=([assets/icons/a.svg]="$(hash_text same)" [presets/video/change.yaml]="$(hash_text new)" [presets/video/add.yaml]="$(hash_text add)" [bin/smart-actions]="$(hash_text binary)")
manifest_plan 0
[[ ${#NEW_PATHS[@]} == 1 && ${#CHANGED_PATHS[@]} == 1 && ${#UNCHANGED_PATHS[@]} == 2 && ${#REMOVED_PATHS[@]} == 1 ]] || fail 'change classification is incorrect'
pass 'NEW CHANGED UNCHANGED REMOVED distribution classification'

# Repair checks actual bytes on disk, not only recorded manifest values.
repair_path=presets/video/repair.yaml
repair_target="$(install_path "$repair_path")"
mkdir -p "$(dirname -- "$repair_target")"
printf 'modified\n' > "$repair_target"
expected="$(hash_text official)"
OLD_MAP=([$repair_path]="$expected") REMOTE_MAP=([$repair_path]="$expected")
manifest_plan 1
[[ ${#CORRUPT_PATHS[@]} == 1 ]] || fail 'repair missed a locally modified file'
pass 'repair detects local hash corruption'

# Pin metadata and all resource downloads to one immutable commit.
TEST_COMMIT=1234567890123456789012345678901234567890
MOCK_BODY='verified bytes'
declare -a REQUESTS=()
curl() {
    local url='' output=''
    while (($#)); do
        if [[ "$1" == -o ]]; then output="$2"; shift 2
        else [[ "$1" == https://* ]] && url="$1"; shift; fi
    done
    REQUESTS+=("$url")
    if [[ "$url" == */releases/latest ]]; then
        printf 'https://github.com/eltonnikecasa/smart-actions/releases/tag/sa-%s' "$TEST_COMMIT"
    elif [[ "$url" == *api.github.com* ]]; then
        printf '  "immutable": %s,\n' "${MOCK_IMMUTABLE:-true}"
    elif [[ "$url" == *manifest-linux-x86_64.sha256 ]]; then
        {
            for rel in assets/icons/pinned.svg bin/smart-actions bin/smart-actions-manager smart-actions-governor.sh scripts/smart-actions-launcher; do
                printf '%s  %s\n' "$(hash_text "$MOCK_BODY")" "$rel"
            done
            printf '%s  release.txt\n' "$(printf 'commit=%s\nplatform=linux-x86_64\n' "$TEST_COMMIT" | sha256sum | cut -d ' ' -f1)"
        } > "$output"
    else printf '%s' "$MOCK_BODY" > "$output"; fi
}
TMP_DIR="$TMP/pin"
mkdir -p "$TMP_DIR"
prepare_remote_plan 0
FETCH_PATHS=(assets/icons/pinned.svg)
download_paths "$REMOTE_SHA"
[[ "$REMOTE_SHA" == "$TEST_COMMIT" ]] || fail 'resolver selected a parent SHA'
for url in "${REQUESTS[@]}"; do [[ "$url" == */releases/latest || "$url" == *"/sa-$TEST_COMMIT/"* || "$url" == *"/sa-$TEST_COMMIT" ]] || fail 'mixed commits in download URLs'; done
[[ -f "$TMP_DIR/download/assets/icons/pinned.svg" ]] || fail 'pinned file was not downloaded'
pass 'manifest and files are fetched from the same resolved commit'
MOCK_IMMUTABLE=false
if (load_remote_manifest "$TEST_COMMIT" "$TMP/rejected-manifest") 2>/dev/null; then fail 'mutable release accepted'; fi
unset MOCK_IMMUTABLE
pass 'mutable releases rejected before manifest download'

# An unchanged file is not fetched; a bad digest fails before apply.
unchanged_path=assets/icons/local.svg
unchanged_target="$(install_path "$unchanged_path")"
mkdir -p "$(dirname -- "$unchanged_target")"
printf '%s' "$MOCK_BODY" > "$unchanged_target"
REMOTE_MAP=([$unchanged_path]="$(hash_text "$MOCK_BODY")")
FETCH_PATHS=("$unchanged_path")
request_count=${#REQUESTS[@]}
download_paths "$TEST_COMMIT"
[[ ${#REQUESTS[@]} == "$request_count" ]] || fail 'unchanged bytes were fetched'
MOCK_BODY='wrong bytes'
REMOTE_MAP=([assets/icons/bad.svg]="$(hash_text official-bytes)")
FETCH_PATHS=(assets/icons/bad.svg)
if (download_paths "$TEST_COMMIT") 2>/dev/null; then fail 'bad SHA-256 transfer passed validation'; fi
pass 'unchanged files are skipped and checksum mismatch blocks staging'


# Apply a data-only update and preserve unchanged bytes, unknown files and user data.
TMP_DIR="$TMP/apply"
mkdir -p "$TMP_DIR" "$STATE_DIR" "$CONFIG_DIR"
MOCK_BODY='updated official'
keep=assets/icons/local.svg
changed=presets/video/repair.yaml
removed=presets/video/removed.yaml
unknown=presets/video/unknown.yaml
printf obsolete > "$(install_path "$removed")"
printf unknown > "$(install_path "$unknown")"
printf personal > "$CONFIG_DIR/personal.yaml"
printf '%s\n' "$TEST_COMMIT" > "$STATE_DIR/installed-sha"
OLD_MAP=([$keep]="$(sha256_file "$(install_path "$keep")")" [$changed]="$(hash_text old)" [$removed]="$(hash_text obsolete)")
REMOTE_MAP=([$keep]="${OLD_MAP[$keep]}" [$changed]="$(hash_text "$MOCK_BODY")")
for path in "${!REMOTE_MAP[@]}"; do printf '%s  %s\n' "${REMOTE_MAP[$path]}" "$path"; done > "$TMP_DIR/remote-manifest.sha256"
manifest_plan 0
before=$(stat -c '%i:%Y' "$(install_path "$keep")")
download_paths "$TEST_COMMIT"
apply_package "$TEST_COMMIT" "$TMP_DIR/remote-manifest.sha256"
[[ $(stat -c '%i:%Y' "$(install_path "$keep")") == "$before" ]] || fail 'unchanged file was replaced'
[[ ! -e "$(install_path "$removed")" && -f "$(install_path "$unknown")" ]] || fail 'removal ownership failed'
[[ $(cat "$CONFIG_DIR/personal.yaml") == personal ]] || fail 'personal data changed'
cmp "$INSTALLED_MANIFEST" "$TMP_DIR/remote-manifest.sha256" || fail 'manifest was not committed'
pass 'application preserves unchanged files and personal data; only owned removals are deleted'

# Repair resolves the installed commit without consulting moving main.
resolve_remote_sha() { fail 'repair consulted main'; }
TMP_DIR="$TMP/repair-plan"
mkdir -p "$TMP_DIR"
prepare_remote_plan 1
[[ "$REMOTE_SHA" == "$TEST_COMMIT" ]] || fail 'repair did not pin installed version'
pass 'repair pins installed commit'

# A failure during integration must roll back applied resources and leave metadata intact.
TMP_DIR="$TMP/rollback"
mkdir -p "$TMP_DIR/download/presets/video"
printf replacement > "$TMP_DIR/download/$changed"
FETCH_PATHS=("$changed"); REMOVED_PATHS=(); MENU_REQUIRED=1
desktop_hint=KDE
regenerate_kde_menu() { return 1; }
cp "$INSTALLED_MANIFEST" "$TMP/prior-manifest"
if (apply_package "$TEST_COMMIT" "$TMP/prior-manifest"); then fail 'integration failure accepted'; fi
[[ $(cat "$(install_path "$changed")") == 'updated official' ]] || fail 'resources were not rolled back'
[[ -x "$BIN_DIR/smart-actions" ]] || fail 'data-only rollback deleted binary'
cmp "$INSTALLED_MANIFEST" "$TMP/prior-manifest" || fail 'failed update changed metadata'
pass 'integration failure rolls back data without deleting existing binaries'

# State-write failure after menu generation restores the previous integration too.
TMP_DIR="$TMP/state-failure"
mkdir -p "$TMP_DIR" "$STATE_DIR/installed-sha.tmp" "$DATA_HOME/kio/servicemenus"
printf old-menu > "$DATA_HOME/kio/servicemenus/smart-actions-probe.desktop"
FETCH_PATHS=(); REMOVED_PATHS=(); MENU_REQUIRED=1
desktop_hint=KDE
regenerate_kde_menu() {
    mkdir -p "$TMP_DIR/menu-backup"
    cp "$DATA_HOME/kio/servicemenus/smart-actions-probe.desktop" "$TMP_DIR/menu-backup/"
    printf new-menu > "$DATA_HOME/kio/servicemenus/smart-actions-probe.desktop"
}
if (apply_package "$TEST_COMMIT" "$INSTALLED_MANIFEST") 2>/dev/null; then fail 'state failure accepted'; fi
[[ $(cat "$DATA_HOME/kio/servicemenus/smart-actions-probe.desktop") == old-menu ]] || fail 'state failure left new menu installed'
cmp "$INSTALLED_MANIFEST" "$TMP/prior-manifest" || fail 'state failure changed manifest'
[[ $(installed_sha) == "$TEST_COMMIT" ]] || fail 'state failure changed commit'
pass 'state-write failure restores the previous KDE menu and preserves metadata'
printf 'All Smart Actions manifest tests passed.\n'
