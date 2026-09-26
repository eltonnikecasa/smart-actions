#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

readonly REPOSITORY="eltonnikecasa/smart-actions"
readonly BRANCH="main"
readonly APP_NAME="Smart Actions"
COMMAND="${1:-install}"
if (($#)); then shift; fi

HOME_DIR="${HOME:?HOME must be set}"
DATA_HOME="${XDG_DATA_HOME:-$HOME_DIR/.local/share}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME_DIR/.config}"
PUBLIC_BIN="${XDG_BIN_HOME:-$HOME_DIR/.local/bin}"
STATE_HOME="${XDG_STATE_HOME:-$HOME_DIR/.local/state}"
APP_DIR="$DATA_HOME/smart-actions"
BIN_DIR="$APP_DIR/bin"
GOVERNOR="$APP_DIR/smart-actions-governor.sh"
CONFIG_DIR="$CONFIG_HOME/smart-actions"
PRESET_DIR="$CONFIG_DIR/presets"
STATE_DIR="$STATE_HOME/smart-actions"
INSTALLED_MANIFEST="$STATE_DIR/installed-manifest.sha256"
TMP_DIR=""
UI_BACKEND=terminal
UPDATE_CONFIRMED=0

cleanup() { [[ -z "$TMP_DIR" ]] || rm -rf -- "$TMP_DIR"; }
trap cleanup EXIT
trap 'status=$?; ui_error "Operation failed (exit $status). See terminal output for details."; exit "$status"' ERR

have() { command -v "$1" >/dev/null 2>&1; }
desktop_hint="${XDG_CURRENT_DESKTOP:-} ${XDG_SESSION_DESKTOP:-} ${DESKTOP_SESSION:-}"
if [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" && -z "${SMART_ACTIONS_TESTING:-}" ]]; then
    if [[ "$desktop_hint" =~ [Kk][Dd][Ee] ]] && have kdialog; then UI_BACKEND=kdialog
    elif have zenity; then UI_BACKEND=zenity
    elif have kdialog; then UI_BACKEND=kdialog
    fi
fi

ui_info() {
    case "$UI_BACKEND" in
        kdialog) kdialog --title "$APP_NAME" --msgbox "$*" >/dev/null 2>&1 || printf '%s\n' "$*" ;;
        zenity) zenity --info --title="$APP_NAME" --text="$*" >/dev/null 2>&1 || printf '%s\n' "$*" ;;
        *) printf '%s\n' "$*" ;;
    esac
}
ui_error() {
    case "$UI_BACKEND" in
        kdialog) kdialog --title "$APP_NAME" --error "$*" >/dev/null 2>&1 || printf 'Erro: %s\n' "$*" >&2 ;;
        zenity) zenity --error --title="$APP_NAME" --text="$*" >/dev/null 2>&1 || printf 'Erro: %s\n' "$*" >&2 ;;
        *) printf 'Erro: %s\n' "$*" >&2 ;;
    esac
}
ui_warning() {
    case "$UI_BACKEND" in
        kdialog) kdialog --title "$APP_NAME" --sorry "$*" >/dev/null 2>&1 || printf 'Aviso: %s\n' "$*" ;;
        zenity) zenity --warning --title="$APP_NAME" --text="$*" >/dev/null 2>&1 || printf 'Aviso: %s\n' "$*" ;;
        *) printf 'Aviso: %s\n' "$*" ;;
    esac
}
ui_confirm() {
    case "$UI_BACKEND" in
        kdialog) kdialog --title "$APP_NAME" --yesno "$*" ;;
        zenity) zenity --question --title="$APP_NAME" --text="$*" ;;
        *)
            local answer
            read -r -p "$* [S/n] " answer || return 1
            [[ ! "$answer" =~ ^[Nn]$ ]]
            ;;
    esac
}
ui_question() { ui_confirm "$@"; }
ui_progress() {
    # Announce stages without claiming a fabricated percentage.
    case "$UI_BACKEND" in
        kdialog) kdialog --title "$APP_NAME" --passivepopup "$*" 4 >/dev/null 2>&1 || printf '%s\n' "$*" ;;
        zenity) zenity --notification --title="$APP_NAME" --text="$*" >/dev/null 2>&1 || printf '%s\n' "$*" ;;
        *) printf '%s\n' "$*" ;;
    esac
}

die() { ui_error "$*"; exit 1; }
require_user() { [[ "$EUID" -ne 0 ]] || die 'Do not run the Governor as root.'; }
safe_parent() {
    local path="$1" parent candidate
    for candidate in "$HOME_DIR" "$DATA_HOME" "$CONFIG_HOME" "$PUBLIC_BIN" "$STATE_HOME"; do
        [[ "$candidate" == /* && ! "$candidate" =~ (^|/)\.\.(/|$) ]] || die "Unsafe configured directory: $candidate"
    done
    parent="$(dirname -- "$path")"
    [[ "$parent" == "$HOME_DIR"/* || "$parent" == "$DATA_HOME"/* || "$parent" == "$CONFIG_HOME"/* || "$parent" == "$STATE_HOME"/* ]] || die "Refusing unsafe path: $path"
}

installed_sha() {
    if [[ -r "$STATE_DIR/installed-sha" ]]; then cat "$STATE_DIR/installed-sha"
    elif [[ -r "$APP_DIR/installed-sha" ]]; then cat "$APP_DIR/installed-sha"
    else printf 'not installed'; fi
}
sha256_file() {
    have sha256sum || die 'sha256sum is required to verify Smart Actions files.'
    sha256sum -- "$1" | cut -d ' ' -f 1
}
valid_manifest_path() {
    local path="$1" part
    local -a parts
    [[ "$path" =~ ^[A-Za-z0-9._/+@-]+$ ]] || return 1
    [[ "$path" != /* && "$path" != *//* ]] || return 1
    local IFS=/
    read -r -a parts <<< "$path"
    for part in "${parts[@]}"; do [[ "$part" != . && "$part" != .. && -n "$part" ]] || return 1; done
    case "$path" in
        Cargo.toml|Cargo.lock|rust-toolchain.toml|smart-actions-governor.sh|scripts/smart-actions-launcher) return 0 ;;
        crates/*/Cargo.toml|crates/*/build.rs|crates/*/src/*.rs) return 0 ;;
        presets/custom/*) return 1 ;;
        assets/icons/*|lang/*.yaml|presets/*/*.yaml) return 0 ;;
        *) return 1 ;;
    esac
}
manifest_load() {
    local file="$1" map_name="$2" line hash path line_no=0
    [[ -r "$file" && ! -L "$file" ]] || { MANIFEST_ERROR="Unreadable or symbolic-link manifest"; return 1; }
    local -n output_map="$map_name"
    local line_re='^([[:xdigit:]]{64})  ([A-Za-z0-9._/+@-]+)$'
    output_map=()
    MANIFEST_ERROR=''
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_no += 1))
        [[ -z "$line" ]] && continue
        if [[ ! "$line" =~ $line_re ]]; then MANIFEST_ERROR="Malformed manifest line $line_no"; return 1; fi
        hash="${BASH_REMATCH[1],,}"
        path="${BASH_REMATCH[2]}"
        if ! valid_manifest_path "$path"; then MANIFEST_ERROR="Unsafe or unsupported path on line $line_no"; return 1; fi
        if [[ -v output_map["$path"] ]]; then MANIFEST_ERROR="Duplicate path on line $line_no"; return 1; fi
        output_map["$path"]="$hash"
    done < "$file"
    (( ${#output_map[@]} > 0 )) || { MANIFEST_ERROR='Manifest contains no distribution files'; return 1; }
}
is_build_path() {
    case "$1" in Cargo.toml|Cargo.lock|rust-toolchain.toml|crates/*) return 0 ;; *) return 1 ;; esac
}
is_menu_path() {
    case "$1" in scripts/smart-actions-launcher|presets/*|lang/*|crates/action_core/src/kde.rs|crates/action_core/src/i18n.rs|crates/action_core/src/config.rs|crates/action_core/src/presets.rs) return 0 ;; *) return 1 ;; esac
}
install_path() {
    local rel="$1"
    case "$rel" in
        smart-actions-governor.sh) printf '%s\n' "$GOVERNOR" ;;
        scripts/smart-actions-launcher) printf '%s\n' "$BIN_DIR/smart-actions-launcher" ;;
        crates/*|Cargo.toml|Cargo.lock|rust-toolchain.toml) printf '%s/%s\n' "$APP_DIR/source" "$rel" ;;
        *) printf '%s/share/%s\n' "$APP_DIR" "$rel" ;;
    esac
}
ensure_safe_destination() {
    local rel="$1" target parent stop
    target="$(install_path "$rel")"
    case "$rel" in
        smart-actions-governor.sh) stop="$APP_DIR" ;;
        scripts/smart-actions-launcher) stop="$BIN_DIR" ;;
        crates/*|Cargo.toml|Cargo.lock|rust-toolchain.toml) stop="$APP_DIR/source" ;;
        *) stop="$APP_DIR/share" ;;
    esac
    [[ ! -L "$APP_DIR" && ! -L "$APP_DIR/share" && ! -L "$APP_DIR/source" && ! -L "$BIN_DIR" ]] || die "Symbolic-link installation root"
    parent="$(dirname -- "$target")"
    while [[ "$parent" != "$stop" && "$parent" == "$stop"/* ]]; do
        [[ ! -L "$parent" ]] || die "Refusing to write through a symbolic-link path: $parent"
        parent="$(dirname -- "$parent")"
    done
    [[ "$parent" == "$stop" && ! -L "$stop" ]] || die "Refusing unsafe install path: $target"
}
resolve_remote_sha() {
    local result
    result="$(curl --fail --silent --show-error --location --max-time 30 \
        -H 'Accept: application/vnd.github+json' \
        "https://api.github.com/repos/$REPOSITORY/commits/$BRANCH")" || return 1
    printf '%s' "$result" | grep -o '"sha"[[:space:]]*:[[:space:]]*"[0-9a-fA-F]\{40\}"' | sed -n '1p' | cut -d '"' -f 4
}
fetch_raw() {
    local sha="$1" rel="$2" output="$3"
    valid_manifest_path "$rel" || die "Refusing unsafe download path: $rel"
    curl --fail --silent --show-error --location --max-time 60 \
        "https://raw.githubusercontent.com/$REPOSITORY/$sha/$rel" -o "$output"
}
load_remote_manifest() {
    local sha="$1" output="$2"
    curl --fail --silent --show-error --location --max-time 30 \
        "https://raw.githubusercontent.com/$REPOSITORY/$sha/smart-actions-manifest.sha256" -o "$output"
    declare -gA REMOTE_MAP=()
    manifest_load "$output" REMOTE_MAP || die "Invalid published manifest: $MANIFEST_ERROR"
}
declare -A REMOTE_MAP=() OLD_MAP=()
NEW_PATHS=() CHANGED_PATHS=() UNCHANGED_PATHS=() REMOVED_PATHS=() CORRUPT_PATHS=() FETCH_PATHS=()
BUILD_REQUIRED=0 MENU_REQUIRED=0
manifest_plan() {
    local repair="$1" path local_file expected
    NEW_PATHS=() CHANGED_PATHS=() UNCHANGED_PATHS=() REMOVED_PATHS=() CORRUPT_PATHS=() FETCH_PATHS=()
    BUILD_REQUIRED=0 MENU_REQUIRED=0
    while IFS= read -r path; do
        [[ -n "$path" ]] || continue
        expected="${REMOTE_MAP[$path]}"
        if [[ ! -v OLD_MAP["$path"] ]]; then NEW_PATHS+=("$path"); FETCH_PATHS+=("$path")
        elif [[ "${OLD_MAP[$path]}" != "$expected" ]]; then CHANGED_PATHS+=("$path"); FETCH_PATHS+=("$path")
        else
            UNCHANGED_PATHS+=("$path")
            if [[ "$repair" == 1 ]]; then
                local_file="$(install_path "$path")"
                if [[ ! -f "$local_file" || -L "$local_file" ]] || [[ "$(sha256_file "$local_file")" != "$expected" ]]; then
                    CORRUPT_PATHS+=("$path")
                    FETCH_PATHS+=("$path")
                    is_build_path "$path" && BUILD_REQUIRED=1
                    is_menu_path "$path" && MENU_REQUIRED=1
                fi
            fi
        fi
        if [[ -v OLD_MAP["$path"] && "${OLD_MAP[$path]}" != "$expected" ]] || [[ ! -v OLD_MAP["$path"] ]]; then
            is_build_path "$path" && BUILD_REQUIRED=1
            is_menu_path "$path" && MENU_REQUIRED=1
        fi
    done < <(printf '%s\n' "${!REMOTE_MAP[@]}" | LC_ALL=C sort)
    while IFS= read -r path; do
        [[ -n "$path" && -v REMOTE_MAP["$path"] ]] && continue
        [[ -n "$path" ]] || continue
        REMOVED_PATHS+=("$path")
        is_build_path "$path" && BUILD_REQUIRED=1
        is_menu_path "$path" && MENU_REQUIRED=1
    done < <(printf '%s\n' "${!OLD_MAP[@]}" | LC_ALL=C sort)
    if [[ ! -x "$BIN_DIR/smart-actions" || ! -x "$BIN_DIR/smart-actions-manager" ]]; then BUILD_REQUIRED=1; fi
}
manifest_counts() {
    printf 'Arquivos novos: %d\nArquivos alterados: %d\nArquivos removidos: %d\nRecompilação necessária: %s\n' \
        "${#NEW_PATHS[@]}" "${#CHANGED_PATHS[@]}" "${#REMOVED_PATHS[@]}" "$([[ "$BUILD_REQUIRED" == 1 ]] && printf Sim || printf Não)"
}
manifest_generate() {
    local root="${1:-${SMART_ACTIONS_PROJECT_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}}" list rel
    [[ -f "$root/Cargo.toml" && -d "$root/presets" && -d "$root/lang" && -d "$root/assets/icons" && -f "$root/scripts/smart-actions-launcher" ]] || die 'manifest must be run from the complete project checkout.'
    have sha256sum || die 'sha256sum is required to generate the manifest.'
    list="$(mktemp "${TMPDIR:-/tmp}/smart-actions-files.XXXXXXXX")"
    git -C "$root" rev-parse --show-toplevel >/dev/null 2>&1 || die 'manifest requires a Git checkout; only tracked distribution files are included.'
    git -C "$root" ls-files | LC_ALL=C sort -u > "$list"
    : > "$root/smart-actions-manifest.sha256.tmp"
    while IFS= read -r rel; do
        if have git && git -C "$root" rev-parse --show-toplevel >/dev/null 2>&1 && git -C "$root" check-ignore -q -- "$rel"; then continue; fi
        valid_manifest_path "$rel" || continue
        [[ -f "$root/$rel" && ! -L "$root/$rel" ]] || continue
        printf '%s  %s\n' "$(sha256_file "$root/$rel")" "$rel" >> "$root/smart-actions-manifest.sha256.tmp"
    done < "$list"
    mv -f -- "$root/smart-actions-manifest.sha256.tmp" "$root/smart-actions-manifest.sha256"
    rm -f -- "$list"
    printf 'Generated %s\n' "$root/smart-actions-manifest.sha256"
}
load_old_manifest() {
    OLD_MAP=()
    [[ -f "$INSTALLED_MANIFEST" ]] || return 0
    manifest_load "$INSTALLED_MANIFEST" OLD_MAP || die "Installed manifest is invalid: $MANIFEST_ERROR"
}
download_paths() {
    local sha="$1" path dest expected actual target
    FETCH_PATHS=($(printf '%s\n' "${FETCH_PATHS[@]}" | sed '/^$/d' | LC_ALL=C sort -u))
    for path in "${FETCH_PATHS[@]}"; do
        expected="${REMOTE_MAP[$path]}"
        target="$(install_path "$path")"
        # Skip transfer only when the existing bytes independently match the remote digest.
        if [[ -f "$target" && ! -L "$target" ]] && [[ "$(sha256_file "$target")" == "$expected" ]]; then continue; fi
        dest="$TMP_DIR/download/$path"
        mkdir -p -- "$(dirname -- "$dest")"
        fetch_raw "$sha" "$path" "$dest"
        actual="$(sha256_file "$dest")"
        [[ "$actual" == "$expected" ]] || die "SHA-256 mismatch for downloaded file: $path"
    done
}
prepare_build() {
    local path staged expected
    BUILD_SOURCE="$TMP_DIR/build-source"
    mkdir -p "$BUILD_SOURCE"
    for path in "${!REMOTE_MAP[@]}"; do
        is_build_path "$path" || continue
        staged="$TMP_DIR/download/$path"
        if [[ ! -f "$staged" ]]; then
            ensure_safe_destination "$path"
            local existing="$(install_path "$path")"
            if [[ -f "$existing" && ! -L "$existing" ]] && [[ "$(sha256_file "$existing")" == "${REMOTE_MAP[$path]}" ]]; then
                mkdir -p -- "$(dirname -- "$BUILD_SOURCE/$path")"
                cp -- "$existing" "$BUILD_SOURCE/$path"
            fi
        fi
        expected="${REMOTE_MAP[$path]}"
        if [[ -f "$staged" ]]; then
            mkdir -p -- "$(dirname -- "$BUILD_SOURCE/$path")"
            install -m 0644 "$staged" "$BUILD_SOURCE/$path"
        elif [[ ! -f "$BUILD_SOURCE/$path" || -L "$BUILD_SOURCE/$path" ]] || [[ "$(sha256_file "$BUILD_SOURCE/$path")" != "$expected" ]]; then
            staged="$TMP_DIR/download/$path"
            mkdir -p -- "$(dirname -- "$staged")"
            FETCH_PATHS+=("$path")
            fetch_raw "$REMOTE_SHA" "$path" "$staged"
            [[ "$(sha256_file "$staged")" == "$expected" ]] || die "SHA-256 mismatch for downloaded build file: $path"
            mkdir -p -- "$(dirname -- "$BUILD_SOURCE/$path")"
            install -m 0644 "$staged" "$BUILD_SOURCE/$path"
        fi
    done
    ui_progress 'Compilando versão de distribuição'
    (cd "$BUILD_SOURCE" && cargo build --release --workspace)
    [[ -x "$BUILD_SOURCE/target/release/cli" && -x "$BUILD_SOURCE/target/release/manager" ]] || die 'Release binaries were not produced.'
}
backup_path() {
    local rel="$1" target backup
    target="$(install_path "$rel")"
    backup="$TMP_DIR/backup/$rel"
    if [[ -e "$target" || -L "$target" ]]; then
        mkdir -p -- "$(dirname -- "$backup")"
        cp -a -- "$target" "$backup"
        BACKUP_HAD["$rel"]=1
    else BACKUP_HAD["$rel"]=0; fi
    APPLIED_PATHS+=("$rel")
}
rollback_changes() {
    local rel target backup
    for rel in "${APPLIED_PATHS[@]}"; do
        target="$(install_path "$rel")"
        backup="$TMP_DIR/backup/$rel"
        if [[ "${BACKUP_HAD[$rel]:-0}" == 1 ]]; then
            mkdir -p -- "$(dirname -- "$target")"
            rm -rf -- "$target"
            cp -a -- "$backup" "$target"
        else rm -f -- "$target"; fi
    done
}
declare -A BACKUP_HAD=()
APPLIED_PATHS=()
apply_package() (
    trap 'status=$?; trap - ERR; rollback_binaries; rollback_changes; restore_kde_menu; exit "$status"' ERR
    local sha="$1" manifest_file="$2" path source target mode
    APPLIED_PATHS=(); BACKUP_HAD=()
    mkdir -p "$TMP_DIR/backup"
    mkdir -p "$BIN_DIR" "$APP_DIR/share" "$APP_DIR/source" "$PRESET_DIR" "$CONFIG_DIR" "$PUBLIC_BIN" "$STATE_DIR"
    [[ ! -L "$APP_DIR" && ! -L "$APP_DIR/share" && ! -L "$APP_DIR/source" && ! -L "$BIN_DIR" && ! -L "$STATE_DIR" ]] || die 'Refusing to write through a symbolic-link installation directory.'
    if [[ -e "$PUBLIC_BIN/smart-actions" && ! -L "$PUBLIC_BIN/smart-actions" ]]; then die "Refusing to replace existing command: $PUBLIC_BIN/smart-actions"; fi
    if [[ -L "$PUBLIC_BIN/smart-actions" && "$(readlink -- "$PUBLIC_BIN/smart-actions")" != "$BIN_DIR/smart-actions" ]]; then die "Refusing to replace unrelated symlink: $PUBLIC_BIN/smart-actions"; fi
    for path in "${FETCH_PATHS[@]}"; do
        source="$TMP_DIR/download/$path"
        [[ -f "$source" ]] || continue
        ensure_safe_destination "$path"
        target="$(install_path "$path")"
        backup_path "$path"
        if [[ -L "$target" ]]; then rm -f -- "$target"; fi
        [[ ! -d "$target" ]] || { rollback_changes; return 1; }
        mkdir -p -- "$(dirname -- "$target")"
        mode=0644
        [[ "$path" == smart-actions-governor.sh || "$path" == scripts/smart-actions-launcher ]] && mode=0755
        install -m "$mode" "$source" "$TMP_DIR/apply-file" && mv -f -- "$TMP_DIR/apply-file" "$target" || { rollback_changes; return 1; }
    done
    for path in "${REMOVED_PATHS[@]}"; do
        target="$(install_path "$path")"
        [[ -e "$target" ]] || continue
        ensure_safe_destination "$path"
        backup_path "$path"
        rm -f -- "$target" || { rollback_changes; return 1; }
    done
    if [[ "$BUILD_REQUIRED" == 1 ]]; then
        for path in "$BIN_DIR/smart-actions" "$BIN_DIR/smart-actions-manager"; do
            local key="@binary:${path##*/}"
            if [[ -e "$path" ]]; then cp -a "$path" "$TMP_DIR/backup/${key#@}"; BACKUP_HAD["$key"]=1; else BACKUP_HAD["$key"]=0; fi
        done
        install -m 0755 "$BUILD_SOURCE/target/release/cli" "$TMP_DIR/cli-new" && mv -f "$TMP_DIR/cli-new" "$BIN_DIR/smart-actions" || { rollback_binaries; rollback_changes; return 1; }
        install -m 0755 "$BUILD_SOURCE/target/release/manager" "$TMP_DIR/manager-new" && mv -f "$TMP_DIR/manager-new" "$BIN_DIR/smart-actions-manager" || { rollback_binaries; rollback_changes; return 1; }
    fi
    local link_created=0 link_tmp="$PUBLIC_BIN/.smart-actions-link.$$"
    if [[ ! -e "$PUBLIC_BIN/smart-actions" && ! -L "$PUBLIC_BIN/smart-actions" ]]; then
        ln -s "$BIN_DIR/smart-actions" "$link_tmp" && mv -f -- "$link_tmp" "$PUBLIC_BIN/smart-actions" || { rm -f -- "$link_tmp"; rollback_binaries; rollback_changes; return 1; }
        link_created=1
    fi
    if [[ "$MENU_REQUIRED" == 1 && ( "$desktop_hint" =~ [Kk][Dd][Ee] || "${XDG_CURRENT_DESKTOP:-}" =~ [Kk][Dd][Ee] ) ]]; then
        if ! regenerate_kde_menu; then
            ((link_created == 0)) || rm -f -- "$PUBLIC_BIN/smart-actions"
            rollback_binaries; rollback_changes; return 1
        fi
    fi
    local staged_manifest="$STATE_DIR/installed-manifest.sha256.tmp" staged_sha="$STATE_DIR/installed-sha.tmp"
    if ! install -m 0644 "$manifest_file" "$staged_manifest" || ! printf '%s\n' "$sha" > "$staged_sha"; then
        ((link_created == 0)) || rm -f -- "$PUBLIC_BIN/smart-actions"
        rollback_binaries; rollback_changes; restore_kde_menu; return 1
    fi
    local previous_sha="$TMP_DIR/previous-installed-sha"
    [[ ! -f "$STATE_DIR/installed-sha" ]] || cp -p "$STATE_DIR/installed-sha" "$previous_sha"
    if ! mv -f -- "$staged_sha" "$STATE_DIR/installed-sha" || ! mv -f -- "$staged_manifest" "$INSTALLED_MANIFEST"; then
        rm -f -- "$staged_manifest" "$staged_sha"
        if [[ -f "$previous_sha" ]]; then cp -p "$previous_sha" "$STATE_DIR/installed-sha"; else rm -f -- "$STATE_DIR/installed-sha"; fi
        ((link_created == 0)) || rm -f -- "$PUBLIC_BIN/smart-actions"
        rollback_binaries; rollback_changes; restore_kde_menu; return 1
    fi
)
rollback_binaries() {
    [[ "$BUILD_REQUIRED" == 1 ]] || return 0
    local path key backup
    for path in "$BIN_DIR/smart-actions" "$BIN_DIR/smart-actions-manager"; do
        key="@binary:${path##*/}"
        backup="$TMP_DIR/backup/${key#@}"
        [[ -v BACKUP_HAD["$key"] ]] || continue
        if [[ "${BACKUP_HAD[$key]:-0}" == 1 ]]; then cp -a "$backup" "$path"; else rm -f -- "$path"; fi
    done
}
prepare_remote_plan() {
    local repair="$1"
    if [[ "$repair" == 1 ]]; then
        REMOTE_SHA="$(installed_sha)"
        [[ "$REMOTE_SHA" =~ ^[0-9a-fA-F]{40}$ ]] || die 'Repair requires a valid installed commit. Use install to establish an installation.'
    else
        REMOTE_SHA="$(resolve_remote_sha)" || die 'Could not determine the published main commit.'
    fi
    [[ "$REMOTE_SHA" =~ ^[0-9a-fA-F]{40}$ ]] || die 'GitHub returned an invalid commit SHA.'
    load_remote_manifest "$REMOTE_SHA" "$TMP_DIR/remote-manifest.sha256"
    OLD_MAP=()
    if [[ -f "$INSTALLED_MANIFEST" ]]; then
        if ! manifest_load "$INSTALLED_MANIFEST" OLD_MAP; then
            if [[ "$repair" == 1 ]]; then
                ui_warning "Installed manifest is invalid; repair will restore current official files without removing untracked paths. ($MANIFEST_ERROR)"
                OLD_MAP=()
            else die "Installed manifest is invalid: $MANIFEST_ERROR"; fi
        fi
    fi
    manifest_plan "$repair"
}
restore_kde_menu() {
    [[ -d "$TMP_DIR/menu-backup" ]] || return 0
    local menu_dir="$DATA_HOME/kio/servicemenus" path
    rm -f -- "$menu_dir"/smart-actions-*.desktop
    for path in "$TMP_DIR/menu-backup"/*.desktop; do
        [[ ! -f "$path" ]] || cp -p -- "$path" "$menu_dir/"
    done
}
regenerate_kde_menu() {
    local menu_dir="$DATA_HOME/kio/servicemenus" path
    mkdir -p "$menu_dir" "$TMP_DIR/menu-backup"
    for path in "$menu_dir"/smart-actions-*.desktop; do
        [[ -f "$path" ]] || continue
        cp -p -- "$path" "$TMP_DIR/menu-backup/"
    done
    rm -f -- "$menu_dir"/smart-actions-*.desktop
    if "$BIN_DIR/smart-actions" generate-kde-menu; then return 0; fi
    rm -f -- "$menu_dir"/smart-actions-*.desktop
    for path in "$TMP_DIR/menu-backup"/*.desktop; do [[ -f "$path" ]] && cp -p -- "$path" "$menu_dir/"; done
    return 1
}
run_distribution() {
    local operation="$1" repair="$2" current prompt path
    have flock || die 'flock is required to serialize installation operations.'
    [[ ! -L "$STATE_DIR" ]] || die 'Symbolic-link state directory'
    mkdir -p "$STATE_DIR"
    exec 9>"$STATE_DIR/governor.lock"
    flock -n 9 || die 'Another Governor operation is running.'
    safe_parent "$STATE_DIR/installed-manifest.sha256"
    TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/smart-actions.XXXXXXXX")"
    prepare_remote_plan "$repair"
    current="$(installed_sha)"
    if [[ "$operation" == update && "$current" == "$REMOTE_SHA" && ${#NEW_PATHS[@]} == 0 && ${#CHANGED_PATHS[@]} == 0 && ${#REMOVED_PATHS[@]} == 0 ]]; then
        ui_info 'Smart Actions is already up to date.'; return 0
    fi
    if [[ "$operation" == update ]]; then
        printf 'Nova atualização disponível\n'
        manifest_counts
        printf -v prompt 'Nova atualização disponível\n\nArquivos novos: %d\nArquivos alterados: %d\nArquivos removidos: %d\nRecompilação necessária: %s\n\nAtualizar agora?' \
            "${#NEW_PATHS[@]}" "${#CHANGED_PATHS[@]}" "${#REMOVED_PATHS[@]}" "$([[ "$BUILD_REQUIRED" == 1 ]] && printf Sim || printf Não)"
        if ! ui_confirm "$prompt"; then printf 'Atualização cancelada.\n'; return 0; fi
    fi
    for path in "${FETCH_PATHS[@]}" "${REMOVED_PATHS[@]}"; do ensure_safe_destination "$path"; done
    ui_progress 'Baixando somente os arquivos novos ou alterados'
    download_paths "$REMOTE_SHA"
    if [[ "$BUILD_REQUIRED" == 1 ]]; then prepare_build; fi
    apply_package "$REMOTE_SHA" "$TMP_DIR/remote-manifest.sha256"
    if [[ "$desktop_hint" =~ [Kk][Dd][Ee] || "${XDG_CURRENT_DESKTOP:-}" =~ [Kk][Dd][Ee] ]]; then
        ui_info 'Smart Actions installed. Administrative interface: available. KDE/Dolphin integration: configured.'
    else
        ui_info 'Smart Actions installed. Administrative interface: available. File manager integration: not available for this desktop in this version.'
    fi
}

do_install() {
    require_user
    run_distribution install 0
}
do_check() {
    TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/smart-actions.XXXXXXXX")"
    prepare_remote_plan 0
    local current="$(installed_sha)"
    if [[ "$current" == "$REMOTE_SHA" && ${#NEW_PATHS[@]} == 0 && ${#CHANGED_PATHS[@]} == 0 && ${#REMOVED_PATHS[@]} == 0 ]]; then
        printf 'Smart Actions is up to date.\n'; return 0
    fi
    printf 'Atualização disponível.\n'
    manifest_counts
}
do_update() {
    require_user
    run_distribution update 0
}
do_repair() {
    require_user
    run_distribution repair 1
}
do_doctor() {
    printf 'Smart Actions doctor\n'
    printf 'Installed SHA: %s\n' "$(installed_sha)"
    printf 'Desktop: %s\n' "${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-${DESKTOP_SESSION:-unknown}}}"
    printf 'Dialog backend: %s\n' "$UI_BACKEND"
    for program in curl sha256sum cargo; do if have "$program"; then printf '%s: available\n' "$program"; else printf '%s: missing\n' "$program"; fi; done
    for program in kdialog zenity; do if have "$program"; then printf '%s: available (optional UI backend)\n' "$program"; else printf '%s: unavailable (optional UI backend)\n' "$program"; fi; done
    if [[ -x "$BIN_DIR/smart-actions" ]]; then printf 'CLI: installed\n'; else printf 'CLI: missing\n'; fi
    if [[ "$desktop_hint" =~ [Kk][Dd][Ee] ]]; then printf 'File manager integration: KDE/Dolphin supported\n'; else printf 'File manager integration: not available for this desktop in this version\n'; fi
    if [[ ! -f "$INSTALLED_MANIFEST" ]]; then
        printf 'Installed manifest: missing\n'; return 1
    fi
    declare -A doctor_map=()
    if ! manifest_load "$INSTALLED_MANIFEST" doctor_map; then printf 'Installed manifest: invalid (%s)\n' "$MANIFEST_ERROR"; return 1; fi
    local missing=0 corrupt=0 path target expected commit
    for path in "${!doctor_map[@]}"; do
        target="$(install_path "$path")"; expected="${doctor_map[$path]}"
        if [[ ! -f "$target" ]]; then ((missing+=1))
        elif [[ -L "$target" ]] || [[ "$(sha256_file "$target")" != "$expected" ]]; then ((corrupt+=1)); fi
    done
    commit="$(installed_sha)"
    if [[ "$commit" =~ ^[0-9a-fA-F]{40}$ ]]; then printf 'Installed commit: valid (%s)\n' "$commit"; else printf 'Installed commit: invalid or missing\n'; fi
    printf 'Installed manifest: valid (%d files)\nOfficial files missing: %d\nOfficial files with hash mismatch: %d\n' "${#doctor_map[@]}" "$missing" "$corrupt"
    [[ "$missing" == 0 && "$corrupt" == 0 && "$commit" =~ ^[0-9a-fA-F]{40}$ ]]
}
do_version() { printf 'Installed: %s\n' "$(installed_sha)"; }
do_uninstall() {
    require_user
    [[ -d "$APP_DIR" ]] || { printf 'Smart Actions is not installed.\n'; return 0; }
    if ! ui_confirm 'Remove Smart Actions binaries and integration? Personal config and presets will be preserved.'; then printf 'Uninstall cancelled.\n'; return 0; fi
    rm -rf -- "$APP_DIR"
    if [[ -L "$PUBLIC_BIN/smart-actions" && "$(readlink -- "$PUBLIC_BIN/smart-actions")" == "$BIN_DIR/smart-actions" ]]; then
        rm -f -- "$PUBLIC_BIN/smart-actions"
    fi
    rm -f -- "$DATA_HOME/kio/servicemenus"/smart-actions-*.desktop
    rm -rf -- "$STATE_DIR"
    ui_info 'Smart Actions was removed. Personal configuration and presets were preserved.'
}

if [[ "${SMART_ACTIONS_GOVERNOR_LIBRARY_ONLY:-0}" == 1 ]]; then return 0; fi

case "$COMMAND" in
    install) do_install ;;
    update) do_update ;;
    check) do_check ;;
    repair) do_repair ;;
    doctor) do_doctor ;;
    version) do_version ;;
    uninstall) do_uninstall ;;
    manifest) manifest_generate ;;
    -h|--help|help)
        printf 'Usage: smart-actions-governor.sh {install|update|check|repair|doctor|version|uninstall|manifest}\n' ;;
    *) die "Unknown command: $COMMAND" ;;
esac
