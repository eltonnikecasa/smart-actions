# Smart Actions

## Installation and maintenance

Install the latest official immutable Linux x86_64 release (no Rust, rustc or Cargo required) with:

```sh
curl -fsSL https://raw.githubusercontent.com/eltonnikecasa/smart-actions/main/smart-actions-governor.sh | bash
```

The installed `smart-actions` command provides `install`, `update`, `check`, `repair`, `doctor`, `version`, and `uninstall`. KDE Plasma with Dolphin has service menu integration; other desktops can use the administration commands, while file manager integration is not yet available. Dialogs use `kdialog` on KDE, `zenity` when available, and otherwise the terminal.

Smart Actions is a modern Linux automation system focused on fast media workflows, desktop integration, and configurable file actions.

The project provides a lightweight action engine capable of processing files through reusable presets, allowing users to create contextual actions for videos, audio, images, PDFs, and more.

Designed with a minimal and user-friendly philosophy inspired by modern desktop applications, Smart Actions combines powerful automation with a clean graphical manager.

---

# Features

- Fast preset-based file automation
- Modern graphical preset manager
- Multi-language interface support
- Video, audio, image, and PDF workflows
- FFmpeg, ImageMagick, Ghostscript integration
- Desktop environment integration
- KDE Plasma support (GNOME/XFCE planned)
- Custom user presets
- Multi-file processing support
- Linux-native runtime structure
- Lightweight and modular architecture

---

# Example Actions

## Video
- H264 compression
- Safe DaVinci Resolve conversion
- Audio extraction

## Audio
- MP3 conversion
- Loudness normalization
- Audio compression

## Images
- WebP conversion
- PNG optimization
- Resize large images
- Metadata removal

## PDF
- Merge PDF files
- Compress PDF
- Images to PDF

---

# Project Goals

Smart Actions aims to become a universal Linux action system capable of integrating directly into desktop environments and file managers while remaining lightweight, extensible, and easy to use.

The long-term vision includes:

- Cross-desktop Linux integration
- Simple installer experience
- User-friendly preset creation
- Advanced workflow pipelines
- Smart media processing
- Contextual desktop actions

---

# Current Status

Current stage:
- Alpha / Early Beta

Tested on:
- KDE Plasma
- Garuda Linux

Planned:
- GNOME support
- XFCE support
- Improved desktop integration
- Standalone installer
- Expanded preset ecosystem

---

# Distribution and development

The Governor downloads prebuilt files only. `install`, `update` and `repair` never
compile and never install system packages. Unsupported platforms stop explicitly.
Linux `x86_64` and `amd64` from `uname -m` map to `linux-x86_64`.
The current build environment produces GNU/Linux binaries requiring glibc 2.39+
and libgcc_s; the manager also needs libm and a working graphical session with
its X11/Wayland/OpenGL runtime libraries. This is not an Alpine/musl build.

FFmpeg (`ffmpeg`), Ghostscript (`gs`), `qpdf` and `img2pdf` are optional action
dependencies. Install them through your distribution when using those actions.
KDE launcher dialogs use `kdialog` and `qdbus6`. Missing action tools report their
names; they do not prevent installation. The Governor requires Bash 4.3+,
curl, sha256sum, flock and standard GNU/Linux command-line utilities.

Developers can clone the source and run:

```sh
cargo check -j 15
cargo test -j 15
cargo build --release --workspace -j 15
bash tests/smart-actions-manifest.sh
bash tests/smart-actions-prebuilt.sh
bash tests/smart-actions-kde.sh
```

Maintainers, from a clean committed checkout on Linux x86_64:

```sh
./scripts/package.sh
bash tests/smart-actions-release.sh "dist/sa-$(git rev-parse HEAD)"
```

This runs a locked release build with 15 jobs and writes
`dist/sa-<full-commit>/`. Only `target/release/cli` and
`target/release/manager` are distributed, installed as `bin/smart-actions` and
`bin/smart-actions-manager`. Other workspace crates are libraries. Runtime
files comprise the Governor, launcher, official presets, translations and icons.
No debug files or build directories are published.

Each asset `sha256-<64-hex-digest>` contains one uncompressed file. Identical
contents share one asset. `manifest-linux-x86_64.sha256` maps hashes to logical
paths, sorted deterministically, without self-reference. `release.txt`, itself
hashed in that manifest, binds the commit and platform. Packaging the same input
bytes produces the same manifest/assets; reproducible Rust builds across different
toolchains or hosts are not claimed.

`smart-actions-manifest.sha256` in Git is the **source manifest**, regenerated
with `./smart-actions-governor.sh manifest`. It is not an install manifest.
The release **distribution manifest** includes prebuilt executables and excludes
Rust sources. Both use the same SHA-256 parser and safe path rules. An old source
installation migrates on `install`/`update`; repair of a pre-release source
installation requires installing a published release first.

The Governor resolves `releases/latest` once to `sa-<full-commit>`, requires
GitHub's `immutable: true` for that release, then obtains all assets from that
tag. Repair uses the installed commit. The manifest checks release identity;
every downloaded payload is checked with SHA-256 before any file is replaced.
Installed state retains the distribution manifest. NEW/CHANGED/UNCHANGED/REMOVED
planning avoids retransferring or replacing unchanged binaries. Repair verifies
actual bytes; doctor is read-only. Failed application/integration restores prior
files. Only previously official files are removed; personal presets/configuration
and KDE files without ownership markers are preserved.

For the first publication, manually:

1. Make the committed source available in the official GitHub repository.
2. Enable **Settings → General → Releases → Enable release immutability**.
3. Create a draft Release with tag `sa-<full-commit>` pointing to that exact
   commit (use the commit printed by package, not a moving branch).
4. Upload **every file** from `dist/sa-<full-commit>/`, including the manifest.
5. Check the assets and publish the Release as the latest stable release.
   Immutable releases lock the tag and assets, so upload everything before publishing.
6. Smoke-test the bootstrap on a supported clean client without Rust.

See [GitHub immutable releases](https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases).
No package command creates tags, pushes, uploads assets or publishes releases.
