"""Offline regression tests for the publication gate; no Rust build or API calls."""
import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    "validator", Path(__file__).resolve().parents[1] / ".github/workflows/validate-package.py")
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)
SHA = "a" * 40


class PackageValidation(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / f"sa-{SHA}"
        self.root.mkdir()
        self.payloads = {p: p.encode() for p in (
            "bin/smart-actions", "bin/smart-actions-manager", "smart-actions-governor.sh",
            "scripts/smart-actions-launcher", "lang/en_US.yaml", "presets/video/a.yaml",
            "assets/icons/a.svg")}
        self.payloads["release.txt"] = f"commit={SHA}\nplatform=linux-x86_64\n".encode()

    def write_package(self):
        lines = []
        for path, data in self.payloads.items():
            digest = hashlib.sha256(data).hexdigest()
            (self.root / f"sha256-{digest}").write_bytes(data)
            lines.append(f"{digest}  {path}\n")
        (self.root / "manifest-linux-x86_64.sha256").write_text("".join(lines))

    def test_valid(self):
        self.write_package()
        validator.validate(self.root, SHA)

    def test_missing_required(self):
        for path in list(self.payloads)[:4] + ["release.txt"]:
            with self.subTest(path=path):
                saved = self.payloads.pop(path)
                self.write_package()
                with self.assertRaises(ValueError):
                    validator.validate(self.root, SHA)
                self.payloads[path] = saved

    def test_identity(self):
        for data in (f"commit={'b' * 40}\nplatform=linux-x86_64\n".encode(),
                     f"commit={SHA}\nplatform=linux-aarch64\n".encode(), b""):
            self.payloads["release.txt"] = data
            self.write_package()
            with self.assertRaises(ValueError):
                validator.validate(self.root, SHA)

    def test_source_and_unsafe_paths(self):
        for path in ("crates/cli/src/main.rs", "Cargo.toml", "assets/icons/source.rs",
                     "../escape", "/absolute", "presets/custom/private.yaml"):
            with self.subTest(path=path):
                self.payloads[path] = b"source"
                self.write_package()
                with self.assertRaises(ValueError):
                    validator.validate(self.root, SHA)
                del self.payloads[path]

    def test_missing_corrupt_symlink_and_extra_asset(self):
        self.write_package()
        asset = next(self.root.glob("sha256-*"))
        data = asset.read_bytes()
        for kind in ("missing", "corrupt", "symlink"):
            with self.subTest(kind=kind):
                asset.unlink()
                if kind == "corrupt":
                    asset.write_bytes(b"corrupt")
                elif kind == "symlink":
                    asset.symlink_to(self.root / "manifest-linux-x86_64.sha256")
                with self.assertRaises(ValueError):
                    validator.validate(self.root, SHA)
                if asset.is_symlink() or asset.exists():
                    asset.unlink()
                asset.write_bytes(data)
        (self.root / "source.rs").write_text("source")
        with self.assertRaises(ValueError):
            validator.validate(self.root, SHA)

    def test_manifest_and_sha(self):
        self.write_package()
        for sha in (SHA[:7], "b" * 40):
            with self.assertRaises(ValueError):
                validator.validate(self.root, sha)
        manifest = self.root / "manifest-linux-x86_64.sha256"
        original = manifest.read_text()
        for content in ("", "malformed\n", original + original):
            manifest.write_text(content)
            with self.assertRaises(ValueError):
                validator.validate(self.root, SHA)
        manifest.unlink()
        with self.assertRaises(ValueError):
            validator.validate(self.root, SHA)


if __name__ == "__main__":
    unittest.main()
