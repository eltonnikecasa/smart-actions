"""Validate the official package before any release API mutation (stdlib only)."""
import hashlib
from pathlib import Path
import re
import sys


def validate(directory, sha):
    root = Path(directory)
    if not re.fullmatch(r"[0-9a-f]{40}", sha) or root.name != f"sa-{sha}":
        raise ValueError("Package directory and full commit SHA must match")
    manifest = root / "manifest-linux-x86_64.sha256"
    if manifest.is_symlink() or not manifest.is_file():
        raise ValueError("Missing regular platform manifest")
    entries = {}
    expected = {manifest.name}
    required = {"bin/smart-actions", "bin/smart-actions-manager", "release.txt",
                "smart-actions-governor.sh", "scripts/smart-actions-launcher"}
    for line in manifest.read_text().splitlines():
        match = re.fullmatch(r"([0-9a-f]{64})  ([A-Za-z0-9._/+@-]+)", line)
        if not match:
            raise ValueError("Malformed manifest line")
        digest, path = match.groups()
        if path in entries or any(p in ("", ".", "..") for p in path.split("/")):
            raise ValueError(f"Duplicate or unsafe path: {path}")
        asset_path = (path.startswith("assets/icons/") or
                      re.fullmatch(r"lang/[^/]+\.yaml", path) or
                      re.fullmatch(r"presets/(?!custom/)[^/]+/[^/]+\.yaml", path))
        if path.endswith(".rs") or not (path in required or asset_path):
            raise ValueError(f"Source or unsupported distribution path: {path}")
        asset = root / f"sha256-{digest}"
        if asset.is_symlink() or not asset.is_file():
            raise ValueError(f"Missing regular asset: {path}")
        if hashlib.sha256(asset.read_bytes()).hexdigest() != digest:
            raise ValueError(f"Hash mismatch: {path}")
        entries[path] = asset
        expected.add(asset.name)
    if not required <= entries.keys():
        raise ValueError("Missing required distribution paths")
    if entries["release.txt"].read_bytes() != f"commit={sha}\nplatform=linux-x86_64\n".encode():
        raise ValueError("Release identity mismatch")
    if {p.name for p in root.iterdir()} != expected:
        raise ValueError("Unexpected files in package directory")
    return sorted(expected)


if __name__ == "__main__":
    validate(*sys.argv[1:])
    print("PASS: package identity, paths, assets and SHA-256")
