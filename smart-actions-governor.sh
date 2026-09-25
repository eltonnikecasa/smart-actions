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
APP_DIR="$DATA_HOME/smart-actions"
BIN_DIR="$APP_DIR/bin"
GOVERNOR="$APP_DIR/smart-actions-governor.sh"
CONFIG_DIR="$CONFIG_HOME/smart-actions"
PRESET_DIR="$CONFIG_DIR/presets"
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
    for candidate in "$HOME_DIR" "$DATA_HOME" "$CONFIG_HOME" "$PUBLIC_BIN"; do
        [[ "$candidate" == /* && ! "$candidate" =~ (^|/)\.\.(/|$) ]] || die "Unsafe configured directory: $candidate"
    done
    parent="$(dirname -- "$path")"
    [[ "$parent" == "$HOME_DIR"/* || "$parent" == "$DATA_HOME"/* || "$parent" == "$CONFIG_HOME"/* ]] || die "Refusing unsafe path: $path"
}

installed_sha() {
    if [[ -r "$APP_DIR/installed-sha" ]]; then cat "$APP_DIR/installed-sha"; else printf 'not installed'; fi
}
remote_sha() {
    local result
    result="$(curl --fail --silent --show-error --location --max-time 30 \
        -H 'Accept: application/vnd.github+json' \
        "https://api.github.com/repos/$REPOSITORY/commits/$BRANCH")" || return 1
    printf '%s' "$result" \
        | grep -o '"sha"[[:space:]]*:[[:space:]]*"[0-9a-fA-F]\{40\}"' \
        | sed -n '1p' \
        | cut -d '"' -f 4
}
download_and_build() {
    local sha="$1" archive="$TMP_DIR/source.tar.gz" src="$TMP_DIR/source"
    [[ "$sha" =~ ^[0-9a-fA-F]{40}$ ]] || die 'Invalid published commit SHA.'
    ui_progress 'Baixando arquivos'
    curl --fail --silent --show-error --location --max-time 180 \
        "https://codeload.github.com/$REPOSITORY/tar.gz/$sha" -o "$archive"
    mkdir -p "$src"
    tar -xzf "$archive" --strip-components=1 -C "$src"
    [[ -f "$src/Cargo.toml" && -f "$src/smart-actions-governor.sh" ]] || die 'Downloaded source archive is incomplete.'
    ui_progress 'Verificando dependências e compilando'
    (cd "$src" && cargo build --release --workspace)
    [[ -x "$src/target/release/cli" && -x "$src/target/release/manager" ]] || die 'Release binaries were not produced.'
    SOURCE_DIR="$src"
}

install_built() {
    local sha="$1" src="$2"
    safe_parent "$APP_DIR/installed-sha"
    mkdir -p "$BIN_DIR" "$APP_DIR/share" "$PRESET_DIR" "$CONFIG_DIR" "$PUBLIC_BIN"
    if [[ -e "$PUBLIC_BIN/smart-actions" && ! -L "$PUBLIC_BIN/smart-actions" ]]; then
        die "Refusing to replace existing command: $PUBLIC_BIN/smart-actions"
    fi
    install -m 0755 "$src/target/release/cli" "$BIN_DIR/smart-actions"
    install -m 0755 "$src/target/release/manager" "$BIN_DIR/smart-actions-manager"
    install -m 0755 "$src/smart-actions-governor.sh" "$GOVERNOR"
    install -m 0755 "$src/scripts/smart-actions-launcher" "$BIN_DIR/smart-actions-launcher"
    ln -sfn "$BIN_DIR/smart-actions" "$PUBLIC_BIN/smart-actions"
    # Project defaults are replaceable; user config and custom presets stay in XDG_CONFIG_HOME.
    rm -rf -- "$APP_DIR/share/presets" "$APP_DIR/share/lang"
    mkdir -p "$APP_DIR/share"
    cp -a "$src/presets" "$APP_DIR/share/presets"
    cp -a "$src/lang" "$APP_DIR/share/lang"
    find "$src/presets" -type f -name '*.yaml' -exec install -m 0644 {} "$PRESET_DIR/" \;
    printf '%s\n' "$sha" > "$APP_DIR/installed-sha"
    mkdir -p "$DATA_HOME/kio/servicemenus"
    if [[ "$desktop_hint" =~ [Kk][Dd][Ee] ]] || [[ "${XDG_CURRENT_DESKTOP:-}" =~ [Kk][Dd][Ee] ]]; then
        "$BIN_DIR/smart-actions" generate-kde-menu || ui_warning 'KDE/Dolphin service menus could not be refreshed.'
        ui_info 'Smart Actions installed. Administrative interface: available. KDE/Dolphin integration: configured.'
    else
        ui_info 'Smart Actions installed. Administrative interface: available. File manager integration: not available for this desktop in this version.'
    fi
}

do_install() {
    require_user
    TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/smart-actions.XXXXXXXX")"
    local sha
    sha="$(remote_sha)" || die 'Could not determine the published version from GitHub.'
    [[ "$sha" =~ ^[0-9a-fA-F]{40}$ ]] || die 'GitHub returned an invalid commit SHA.'
    ui_progress 'Preparando Smart Actions'
    download_and_build "$sha"
    ui_progress 'Instalando e configurando integração'
    install_built "$sha" "$SOURCE_DIR"
    ui_progress 'Concluído'
}

do_check() {
    local current available
    current="$(installed_sha)"
    printf 'Instalada: %s\n' "$current"
    available="$(remote_sha)" || die 'Could not check GitHub for updates.'
    [[ "$available" =~ ^[0-9a-fA-F]{40}$ ]] || die 'GitHub returned an invalid commit SHA.'
    printf 'Disponível: %s\n' "$available"
    [[ "$current" == "$available" ]] && { printf 'Smart Actions is up to date.\n'; return 0; }
    printf 'A new version is available.\n'
    local prompt
    printf -v prompt 'Smart Actions\n\nA new version is available.\n\nInstalled: %s\nAvailable: %s\n\nUpdate now?' "$current" "$available"
    if ui_confirm "$prompt"; then
        UPDATE_CONFIRMED=1
        do_update
    else
        printf 'Update deferred. Run smart-actions update when ready.\n'
    fi
}
do_update() {
    require_user
    local current available answer
    current="$(installed_sha)"
    available="$(remote_sha)" || die 'Could not check GitHub for updates.'
    [[ "$available" =~ ^[0-9a-fA-F]{40}$ ]] || die 'GitHub returned an invalid commit SHA.'
    if [[ "$current" == "$available" ]]; then ui_info 'Smart Actions is already up to date.'; return 0; fi
    printf 'Smart Actions\nUma nova versão está disponível.\n\nInstalada: %s\nDisponível: %s\n' "$current" "$available"
    if ((UPDATE_CONFIRMED == 0)); then
        local prompt
        printf -v prompt 'Smart Actions\n\nA new version is available.\n\nInstalled: %s\nAvailable: %s\n\nUpdate now?' "$current" "$available"
        if ! ui_confirm "$prompt"; then printf 'Update cancelled.\n'; return 0; fi
    fi
    TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/smart-actions.XXXXXXXX")"
    download_and_build "$available"
    ui_progress 'Instalando'
    install_built "$available" "$SOURCE_DIR"
    ui_progress 'Concluído'
}
do_repair() {
    require_user
    local available
    TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/smart-actions.XXXXXXXX")"
    available="$(remote_sha)" || die 'Could not determine the published version from GitHub.'
    [[ "$available" =~ ^[0-9a-fA-F]{40}$ ]] || die 'GitHub returned an invalid commit SHA.'
    download_and_build "$available"
    install_built "$available" "$SOURCE_DIR"
    ui_info 'Smart Actions was repaired.'
}
do_doctor() {
    printf 'Smart Actions doctor\n'
    printf 'Installed SHA: %s\n' "$(installed_sha)"
    printf 'Desktop: %s\n' "${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-${DESKTOP_SESSION:-unknown}}}"
    printf 'Dialog backend: %s\n' "$UI_BACKEND"
    for program in curl tar cargo; do if have "$program"; then printf '%s: available\n' "$program"; else printf '%s: missing\n' "$program"; fi; done
    for program in kdialog zenity; do if have "$program"; then printf '%s: available (optional UI backend)\n' "$program"; else printf '%s: unavailable (optional UI backend)\n' "$program"; fi; done
    if [[ -x "$BIN_DIR/smart-actions" ]]; then printf 'CLI: installed\n'; else printf 'CLI: missing\n'; fi
    if [[ "$desktop_hint" =~ [Kk][Dd][Ee] ]]; then printf 'File manager integration: KDE/Dolphin supported\n'; else printf 'File manager integration: not available for this desktop in this version\n'; fi
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
    ui_info 'Smart Actions was removed. Personal configuration and presets were preserved.'
}

case "$COMMAND" in
    install) do_install ;;
    update) do_update ;;
    check) do_check ;;
    repair) do_repair ;;
    doctor) do_doctor ;;
    version) do_version ;;
    uninstall) do_uninstall ;;
    -h|--help|help)
        printf 'Usage: smart-actions-governor.sh {install|update|check|repair|doctor|version|uninstall}\n' ;;
    *) die "Unknown command: $COMMAND" ;;
esac
