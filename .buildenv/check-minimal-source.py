#!/usr/bin/env python3
"""Verify the complete, unchanged Minimal source handoff against its inventory."""
import hashlib
import json
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parent.parent
snapshot = root / ".buildenv/minimal"
inventory = json.loads((root / ".buildenv/minimal-source.json").read_text())
expected = set()
for entry in inventory["files"]:
    relative = Path(entry["path"])
    assert not relative.is_absolute() and ".." not in relative.parts, relative
    target = snapshot / relative
    assert target.is_file() and not target.is_symlink(), relative
    assert hashlib.sha256(target.read_bytes()).hexdigest() == entry["sha256"], relative
    assert bool(target.stat().st_mode & 0o111) == (entry["mode"] == "100755"), relative
    expected.add(entry["path"])

# Include untracked, non-ignored files so accidental additions are also caught.
files = subprocess.check_output(
    ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", ".buildenv/minimal/"],
    cwd=root,
).decode().split("\0")
actual = {p.removeprefix(".buildenv/minimal/") for p in files if p}
assert actual == expected, {"missing": sorted(expected - actual), "extra": sorted(actual - expected)}
assert (snapshot / "firmware/files/etc/zbt-build-flavor").read_text().strip() == "minimal"
print(f"Complete Minimal snapshot verified: {len(expected)} files from {inventory['source_commit']}")
