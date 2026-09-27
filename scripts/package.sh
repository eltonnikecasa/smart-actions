#!/usr/bin/env bash
# Maintainer-only build. No publication or system package installation.
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || { echo 'Packaging requires Linux x86_64.' >&2; exit 1; }
[[ -z $(git status --porcelain) ]] || { echo 'Commit changes before packaging an identifiable release.' >&2; exit 1; }
COMMIT="$(git rev-parse HEAD)"
OUT="$ROOT/dist/sa-$COMMIT"
[[ ! -e "$OUT" ]] || { echo "Output already exists: $OUT" >&2; exit 1; }
CARGO_TARGET_DIR="$ROOT/target" cargo build --release --workspace -j 15 --locked
SMART_ACTIONS_GOVERNOR_LIBRARY_ONLY=1 source "$ROOT/smart-actions-governor.sh"
STAGE="$(mktemp -d)"
trap 'rm -rf -- "$STAGE"' EXIT
mkdir -p "$STAGE/assets"
MANIFEST="$STAGE/assets/manifest-linux-x86_64.sha256"
add_file() {
    local source="$1" rel="$2" hash
    [[ -f "$source" && ! -L "$source" ]] || { echo "Missing regular file: $source" >&2; exit 1; }
    hash="$(sha256_file "$source")"
    cp -- "$source" "$STAGE/assets/sha256-$hash"
    printf '%s  %s\n' "$hash" "$rel" >> "$MANIFEST"
}
add_file target/release/cli bin/smart-actions
add_file target/release/manager bin/smart-actions-manager
printf 'commit=%s\nplatform=linux-x86_64\n' "$COMMIT" > "$STAGE/release.txt"
add_file "$STAGE/release.txt" release.txt
while IFS= read -r rel; do
    case "$rel" in
        smart-actions-governor.sh|scripts/smart-actions-launcher|assets/icons/*|lang/*.yaml|presets/*/*.yaml)
            valid_manifest_path "$rel" && add_file "$ROOT/$rel" "$rel" ;;
    esac
done < <(git ls-files | LC_ALL=C sort)
LC_ALL=C sort -k2 "$MANIFEST" -o "$MANIFEST"
mkdir -p "$ROOT/dist"
mv "$STAGE/assets" "$OUT"
printf 'Prepared %s\nRelease tag: sa-%s\nUpload every file in this directory as an asset. Enable GitHub immutable releases before publishing.\n' "$OUT" "$COMMIT"
