#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
export HOME="$TMP/home" XDG_DATA_HOME="$TMP/home/.local/share" XDG_CONFIG_HOME="$TMP/config" XDG_STATE_HOME="$TMP/state" XDG_BIN_HOME="$TMP/bin" TMPDIR="$TMP/tmp" SMART_ACTIONS_TESTING=1
mkdir -p "$HOME" "$TMPDIR"
SMART_ACTIONS_GOVERNOR_LIBRARY_ONLY=1 source "$ROOT/smart-actions-governor.sh"
trap 'rm -rf -- "$TMP"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
ui_confirm() { return 0; }
desktop_hint=KDE
menu_dir="$DATA_HOME/kio/servicemenus"
mkdir -p "$menu_dir" "$CONFIG_DIR/presets"
printf 'personal menu\n' > "$menu_dir/smart-actions-personal.desktop"
cp "$menu_dir/smart-actions-personal.desktop" "$TMP/personal"
cp "$ROOT/presets/video/resolve-safe.yaml" "$CONFIG_DIR/presets/personal.yaml"
# Local transport preserves the real plan, verification, staging and apply paths.
revision=1
prepare_remote_plan() {
    REMOTE_SHA=$(printf '%040d' "$revision")
    cp "$ROOT/smart-actions-manifest.sha256" "$TMP_DIR/remote-manifest.sha256"
    manifest_load "$TMP_DIR/remote-manifest.sha256" REMOTE_MAP
    OLD_MAP=()
    if [[ -f "$INSTALLED_MANIFEST" ]]; then manifest_load "$INSTALLED_MANIFEST" OLD_MAP; fi
    manifest_plan "$1"
}
fetch_raw() { mkdir -p "$(dirname -- "$3")"; cp "$ROOT/$2" "$3"; }
# Exercise the real build invocation, without recompiling every lifecycle operation.
cargo() {
    [[ "$*" == $'build\n--release\n--workspace\n-j\n15' ]] || fail 'unexpected Cargo job limit'
    mkdir -p target/release
    cp "$ROOT/target/release/cli" target/release/cli
    cp "$ROOT/target/release/manager" target/release/manager
    printf 'build\n' >> "$TMP/builds"
}
check_personal() {
    cmp "$TMP/personal" "$menu_dir/smart-actions-personal.desktop"
    cmp "$ROOT/presets/video/resolve-safe.yaml" "$CONFIG_DIR/presets/personal.yaml"
}
do_install
check_personal
mapfile -d '' -t official < <(owned_kde_menus)
((${#official[@]} > 0)) || fail 'official menus missing after install'
# An old owned menu is removed during a necessary regeneration.
printf 'X-Smart-Actions-Owner=%s\n' "$APP_DIR" > "$menu_dir/smart-actions-obsolete.desktop"
# Simulate previous-version metadata to trigger a real update of the generator.
sed -i '/  crates\/action_core\/src\/kde.rs$/s/^[a-f0-9]\{64\}/0000000000000000000000000000000000000000000000000000000000000000/' "$INSTALLED_MANIFEST"
revision=2
do_update
check_personal
[[ ! -e "$menu_dir/smart-actions-obsolete.desktop" ]] || fail 'obsolete owned menu survived'
# Repair must detect actual changed source bytes and regenerate integration.
printf '\n// corruption\n' >> "$(install_path crates/action_core/src/kde.rs)"
do_repair
check_personal
[[ $(wc -l < "$TMP/builds") == 3 ]] || fail 'build mock did not exercise all flows'
# A same-name unowned file must not be overwritten, even by the Rust generator.
collision="${official[0]}"
printf 'unowned collision\n' > "$collision"
cp "$collision" "$TMP/collision"
if "$BIN_DIR/smart-actions" generate-kde-menu > "$TMP/collision-output" 2>&1; then fail 'unowned collision was accepted'; fi
cmp "$collision" "$TMP/collision"
# A failed regeneration restores owned menus and leaves the collision untouched.
TMP_DIR="$TMP/menu-failure"
mkdir -p "$TMP_DIR"
while IFS= read -r -d '' path; do sha256sum "$path"; done < <(owned_kde_menus) > "$TMP/menus-before"
if regenerate_kde_menu > "$TMP/regeneration-output" 2>&1; then fail 'regeneration accepted collision'; fi
sha256sum -c "$TMP/menus-before" >/dev/null
cmp "$collision" "$TMP/collision"
check_personal
do_uninstall
check_personal
cmp "$collision" "$TMP/collision"
[[ -z $(owned_kde_menus) ]] || fail 'official menus survived uninstall'
printf 'PASS: install/update/repair/uninstall preserve personal menus and presets; ownership, collision and 15-job checks passed\n'
