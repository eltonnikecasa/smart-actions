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
    {
        for rel in smart-actions-governor.sh scripts/smart-actions-launcher; do printf '%s  %s\n' "$(sha256_file "$ROOT/$rel")" "$rel"; done
        for rel in cli manager; do
            name=smart-actions; [[ "$rel" != manager ]] || name=smart-actions-manager
            printf '%s  bin/%s\n' "$(sha256_file "$ROOT/target/release/$rel")" "$name"
        done
        git -C "$ROOT" ls-files assets/icons lang presets | while IFS= read -r rel; do
            valid_manifest_path "$rel" && printf '%s  %s\n' "$(sha256_file "$ROOT/$rel")" "$rel"
        done
    } > "$TMP_DIR/remote-manifest.sha256"
    manifest_load "$TMP_DIR/remote-manifest.sha256" REMOTE_MAP
    OLD_MAP=()
    if [[ -f "$INSTALLED_MANIFEST" ]]; then manifest_load "$INSTALLED_MANIFEST" OLD_MAP; fi
    manifest_plan "$1"
}
fetch_raw() {
    local source="$ROOT/$2"
    case "$2" in bin/smart-actions) source="$ROOT/target/release/cli" ;; bin/smart-actions-manager) source="$ROOT/target/release/manager" ;; esac
    cp "$source" "$3"
}
# Isolated client PATH has no Rust toolchain. Any attempted invocation fails.
mkdir -p "$TMP/client-path"
for dir in /usr/bin /bin; do
    for executable in "$dir"/*; do
        case "${executable##*/}" in cargo*|rustc*|rustup*) continue ;; esac
        [[ ! -x "$executable" || -d "$executable" || -e "$TMP/client-path/${executable##*/}" ]] || ln -s "$executable" "$TMP/client-path/"
    done
done
export PATH="$TMP/client-path"
! command -v cargo && ! command -v rustc || fail 'toolchain present in client PATH'
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
sed -i '/  bin\/smart-actions$/s/^[a-f0-9]\{64\}/0000000000000000000000000000000000000000000000000000000000000000/' "$INSTALLED_MANIFEST"
revision=2
do_update
check_personal
[[ ! -e "$menu_dir/smart-actions-obsolete.desktop" ]] || fail 'obsolete owned menu survived'
# Repair must detect actual changed binary bytes and regenerate integration.
printf 'corruption' > "$(install_path bin/smart-actions)"
do_repair
check_personal

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
printf 'PASS: install/update/repair/uninstall preserve personal menus and presets; ownership, collision and client without Cargo/rustc checks passed\n'
