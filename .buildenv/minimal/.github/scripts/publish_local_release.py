#!/usr/bin/env python3
"""Validate and publish prebuilt local firmware. Never compiles or flashes it.

Only the trusted default-branch workflow invokes this helper. Downloading uses
fixed numeric GitHub asset API paths, not URLs or paths from release metadata.
The Gemini key is deliberately absent from this helper; a separate trusted
workflow step calls the existing release-note generator on bounded evidence.
"""
from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import urllib.error
import urllib.parse
import urllib.request

from generate_firmware_release_notes import valid as valid_notes

REPOSITORIES = {
    "mfoster978/openwrt-zbtlink-zbt-z8803be-mega-edition": ("master", "mega", "Mega"),
    "mfoster978/openwrt-zbtlink-zbt-z8803be-speedify-minimal-build": ("main", "minimal", "Minimal"),
}
SHA = re.compile(r"[0-9a-f]{40}\Z")
HASH = re.compile(r"[0-9a-f]{64}\Z")
TAG = re.compile(r"firmware-[1-9][0-9]{0,11}\.[1-9][0-9]{0,5}\Z")
DEVICE = "zbtlink_zbt-z8803be"
BOARD = "zbtlink,zbt-z8803be"
PREFIX = "openwrt-mediatek-filogic-" + DEVICE
SYSUPGRADE = PREFIX + "-squashfs-sysupgrade.bin"
INITRAMFS = PREFIX + "-initramfs-kernel.bin"
PACKAGE_MANIFEST = PREFIX + ".manifest"
RUNTIME = "verify-router-runtime.sh"
NOTES = "RELEASE_NOTES.md"
BASE_SHA = "edc738504fe8fae81eb15de967456204699b1830"
LIMITS = {SYSUPGRADE: 128 << 20, INITRAMFS: 128 << 20,
          PACKAGE_MANIFEST: 4 << 20, "SHA256SUMS": 16384,
          "BUILD-INFO.txt": 16384, RUNTIME: 1 << 20, "mega-release.json": 65536}


def git(root, *args, check=True):
    result = subprocess.run(["git", "-C", str(root), *args], stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, input=b"", check=False, timeout=30)
    if check and result.returncode:
        raise ValueError("Trusted repository git validation failed")
    return result.stdout if check else result.returncode


def ancestor(root, before, after):
    if not SHA.fullmatch(before) or not SHA.fullmatch(after):
        return False
    return git(root, "merge-base", "--is-ancestor", before, after, check=False) == 0


def inputs(repository, tag, source_sha):
    if repository not in REPOSITORIES:
        raise ValueError("This workflow is restricted to the two maintained ZBT repositories")
    if not TAG.fullmatch(tag) or not SHA.fullmatch(source_sha):
        raise ValueError("Expected firmware-NUMBER.ATTEMPT and a full lowercase 40-character source SHA")


def trusted_source(root, repository, source_sha):
    branch = REPOSITORIES[repository][0]
    head = git(root, "rev-parse", "HEAD").decode().strip()
    trusted = git(root, "rev-parse", "refs/remotes/origin/" + branch).decode().strip()
    if head != trusted or not ancestor(root, source_sha, trusted):
        raise ValueError("Source must be an ancestor of the checked-out trusted default branch")


class AssetRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, target):
        u = urllib.parse.urlsplit(target)
        if (u.scheme != "https" or u.username or u.password or u.port or u.fragment or
                u.hostname not in {"release-assets.githubusercontent.com", "objects.githubusercontent.com"}):
            raise ValueError("Blocked redirect outside GitHub release asset storage")
        redirected = super().redirect_request(request, fp, code, message, headers, target)
        # Never forward the repository token to signed asset storage URLs.
        redirected.remove_header("Authorization")
        return redirected


class GitHub:
    def __init__(self, repository, token):
        self.repository = repository
        self.root = "https://api.github.com/repos/" + repository
        self.token = token
        self.opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), AssetRedirects())

    def request(self, method, path, data=None, accept="application/vnd.github+json", upload=False):
        host = "https://uploads.github.com/repos/" + self.repository if upload else self.root
        if not path.startswith("/") or ".." in path:
            raise ValueError("Invalid internal GitHub endpoint")
        headers = {"Authorization": "Bearer " + self.token,
                   "Accept": accept, "X-GitHub-Api-Version": "2022-11-28",
                   "User-Agent": "ZBT-local-release-publisher/1.0"}
        if upload:
            headers["Content-Type"] = "text/markdown; charset=utf-8"
        elif data is not None:
            headers["Content-Type"] = "application/json"
            data = json.dumps(data).encode()
        request = urllib.request.Request(host + path, method=method, data=data, headers=headers)
        return self.opener.open(request, timeout=90)

    def api(self, path, method="GET", data=None, allow_missing=False):
        try:
            with self.request(method, path, data) as response:
                raw = response.read((8 << 20) + 1)
        except urllib.error.HTTPError as error:
            if allow_missing and error.code == 404:
                return None
            raise ValueError(f"GitHub API returned HTTP {error.code}; release remains unpublished unless already published") from None
        if len(raw) > 8 << 20:
            raise ValueError("GitHub response exceeds the metadata limit")
        return json.loads(raw) if raw else None

    def download(self, asset, destination):
        expected = asset["size"]
        try:
            with self.request("GET", "/releases/assets/" + str(asset["id"]),
                              accept="application/octet-stream") as response:
                length = response.headers.get("Content-Length")
                if length is not None and int(length) != expected:
                    raise ValueError("Asset Content-Length does not match its declared size")
                flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW
                with os.fdopen(os.open(destination, flags, 0o600), "wb") as output:
                    digest, total = hashlib.sha256(), 0
                    while True:
                        chunk = response.read(min(1 << 20, expected - total + 1))
                        if not chunk:
                            break
                        total += len(chunk)
                        if total > expected:
                            raise ValueError("Downloaded asset exceeds its declared bounded size")
                        digest.update(chunk)
                        output.write(chunk)
                    if total != expected:
                        raise ValueError("Downloaded asset is truncated")
        except urllib.error.HTTPError as error:
            raise ValueError(f"GitHub asset download returned HTTP {error.code}") from None
        actual = digest.hexdigest()
        if asset.get("digest") and asset["digest"] != "sha256:" + actual:
            raise ValueError("Asset does not match GitHub's published SHA-256 digest")
        return actual

    def upload_notes(self, release, notes):
        old = [a for a in release["assets"] if a["name"] == NOTES]
        if len(old) > 1:
            raise ValueError("Duplicate release-note assets")
        for asset in old:
            self.api("/releases/assets/" + str(asset["id"]), method="DELETE")
        path = "/releases/" + str(release["id"]) + "/assets?name=" + NOTES
        with self.request("POST", path, notes.encode(), upload=True) as response:
            result = json.loads(response.read(65536))
        if result.get("name") != NOTES or result.get("state") != "uploaded":
            raise ValueError("Release notes were not uploaded successfully")


def tag_commit(api, tag):
    ref = api.api("/git/ref/tags/" + urllib.parse.quote(tag, safe=""))
    obj = ref.get("object", {})
    for _ in range(6):
        sha = obj.get("sha", "")
        if not SHA.fullmatch(sha):
            break
        if obj.get("type") == "commit":
            return sha
        if obj.get("type") != "tag":
            break
        obj = api.api("/git/tags/" + sha).get("object", {})
    raise ValueError("Release tag must already resolve to a commit; push the exact build tag first")


def find_draft(api, tag):
    # Authenticated list includes drafts; GET /releases/tags is documented for
    # published releases and must not be relied upon to locate an unpublished one.
    for page in range(1, 21):
        batch = api.api(f"/releases?per_page=50&page={page}")
        if not isinstance(batch, list) or len(batch) > 50:
            raise ValueError("Malformed GitHub release listing")
        found = [r for r in batch if r.get("tag_name") == tag]
        if len(found) > 1:
            raise ValueError("Ambiguous release tag")
        if found:
            return api.api("/releases/" + str(found[0]["id"]))
        if len(batch) < 50:
            break
    raise ValueError("Requested existing draft release was not found")


def selected_assets(release, repository, tag, source_sha):
    if (release.get("draft") is not True or release.get("prerelease") is not False or
            release.get("tag_name") != tag or release.get("target_commitish") != source_sha or
            type(release.get("id")) is not int or release["id"] < 1):
        raise ValueError("An existing non-prerelease draft targeting exactly the build SHA is required")
    required = set(LIMITS) - ({"mega-release.json"} if REPOSITORIES[repository][1] == "minimal" else set())
    assets = release.get("assets")
    if not isinstance(assets, list) or len(assets) > len(required) + 1:
        raise ValueError("Unexpected draft release assets")
    selected, names, ids = {}, set(), set()
    for asset in assets:
        name = asset.get("name")
        if name not in required | {NOTES} or name in names:
            raise ValueError("Unknown, duplicate or source archive release asset")
        names.add(name)
        size, ident = asset.get("size"), asset.get("id")
        limit = 32768 if name == NOTES else LIMITS[name]
        if (type(size) is not int or size <= 0 or size > limit or
                type(ident) is not int or ident <= 0 or asset.get("state") != "uploaded" or
                asset.get("url") != "https://api.github.com/repos/" + repository + "/releases/assets/" + str(ident)):
            raise ValueError("Invalid asset identity, size or upload state")
        if ident in ids:
            raise ValueError("Duplicate numeric release asset ID")
        ids.add(ident)
        if name in {SYSUPGRADE, INITRAMFS} and size < 1 << 20:
            raise ValueError("Firmware image is unexpectedly small")
        if name != NOTES:
            selected[name] = asset
    if set(selected) != required:
        raise ValueError("Draft is missing required device-specific release assets")
    return selected


def fingerprint(assets):
    return {name: {key: asset.get(key) for key in ("id", "name", "size", "digest", "updated_at")}
            for name, asset in assets.items()}


def checksums(text):
    result = {}
    for line in text.splitlines():
        if not line:
            continue
        match = re.fullmatch(r"([0-9a-fA-F]{64}) [ *]([^\r\n]+)", line)
        if not match or match[2] not in {SYSUPGRADE, INITRAMFS} or match[2] in result:
            raise ValueError("SHA256SUMS must contain exactly the two fixed image names, without paths or duplicates")
        result[match[2]] = match[1].lower()
    if set(result) != {SYSUPGRADE, INITRAMFS}:
        raise ValueError("Both firmware image checksums are required")
    return result


def validate_files(root, folder, repository, tag, source_sha, hashes):
    expected = checksums((folder / "SHA256SUMS").read_text())
    if any(hashes.get(name) != digest for name, digest in expected.items()):
        raise ValueError("Downloaded firmware SHA-256 verification failed")
    info = {}
    for line in (folder / "BUILD-INFO.txt").read_text().splitlines():
        key, sep, value = line.partition(": ")
        if sep:
            if key in info:
                raise ValueError("Duplicate BUILD-INFO field")
            info[key] = value
    requirements = {"Recipe commit": source_sha, "Target": "mediatek/filogic",
                    "Device": DEVICE, "Edition": REPOSITORIES[repository][2],
                    "Version": tag, "Build host": "local server",
                    "OpenWrt source": "https://github.com/0xFar5eer/openwrt25.12_ZBT_Z8803BE.git",
                    "OpenWrt ref": "v25.12.021", "OpenWrt commit": BASE_SHA}
    for key, value in requirements.items():
        if info.get(key) != value:
            raise ValueError("Local build provenance mismatch: " + key)
    runtime = git(root, "show", source_sha + ":firmware/scripts/" + RUNTIME)
    if hashlib.sha256(runtime).hexdigest() != hashes.get(RUNTIME):
        raise ValueError("Runtime verifier does not match the built recipe commit")
    # A package manifest is text evidence, never commands to run on this runner.
    if "\x00" in (folder / PACKAGE_MANIFEST).read_text():
        raise ValueError("Invalid package manifest")
    if REPOSITORIES[repository][1] == "mega":
        data = json.loads((folder / "mega-release.json").read_text())
        required = {"schema": 1, "variant": "mega", "repository": repository,
                    "board": BOARD, "version": tag, "source_sha": source_sha,
                    "base_version": "v25.12.021", "dirty": False}
        if (any(data.get(k) != v for k, v in required.items()) or data.get("dirty") is not False or
                type(data.get("schema")) is not int):
            raise ValueError("Mega identity metadata does not match this local build")
        date = datetime.datetime.fromisoformat(data.get("built_at", "").replace("Z", "+00:00"))
        if date.tzinfo is None:
            raise ValueError("Mega build timestamp requires a timezone")
        image = data.get("image", {})
        if image != {"name": SYSUPGRADE, "size": (folder / SYSUPGRADE).stat().st_size, "sha256": hashes[SYSUPGRADE]}:
            raise ValueError("Mega manifest image hash/size/name mismatch")


def latest_policy(api, root, tag, source_sha):
    latest = api.api("/releases/latest", allow_missing=True)
    if latest is None:
        return True, None
    latest_sha = tag_commit(api, latest["tag_name"])
    markers = re.findall(r"^<!-- source-sha: ([0-9a-f]{40}) -->$", latest.get("body", ""), re.M)
    if markers and (len(markers) != 1 or markers[0] != latest_sha):
        raise ValueError("Latest release source marker disagrees with its tag")
    if latest_sha == source_sha:
        old = latest.get("tag_name", "")
        comparable = TAG.fullmatch(old)
        order = lambda value: tuple(map(int, value.removeprefix("firmware-").split(".")))
        return bool(comparable and order(tag) > order(old)), latest_sha
    # A valid historical build may be published but cannot displace a newer or
    # unrelated latest source. Actions compiler/publisher share a concurrency key.
    return ancestor(root, latest_sha, source_sha), latest_sha


def evidence(root, source_sha, previous, edition):
    if previous and ancestor(root, previous, source_sha):
        base = previous
        log_range = previous + ".." + source_sha
        baseline = "Changes since the previous published ancestor release."
    else:
        history = git(root, "rev-list", "--max-count=1", "--skip=25", source_sha).decode().strip()
        base = history or git(root, "hash-object", "-t", "tree", "--stdin").decode().strip()
        log_range = history + ".." + source_sha if history else source_sha
        baseline = "Recent/initial history fallback: no previous published ancestor was available; this is not necessarily a delta from the current latest release."
    args = [base, source_sha, "--", "firmware", "README.md"]
    names = git(root, "diff", "--name-status", *args).decode(errors="replace")[:8000]
    stat = git(root, "diff", "--stat", *args).decode(errors="replace")[:4000]
    diff = git(root, "diff", "--unified=1", *args).decode(errors="replace")[:24000]
    commits = git(root, "log", "--max-count=50", "--format=%h %s", log_range).decode(errors="replace")[:4000]
    return (f"Build: ZBT-Z8803BE {edition}\nPinned source: Far5eer v25.12.021 / Linux 6.12.74.\n"
            "Provenance: compiled on the maintainer's local server, not on a GitHub-hosted compiler.\n"
            "Evidence is repository changes only. No hardware flashing or router tests were performed by this publication workflow.\n"
            f"Evidence baseline: {baseline}\n"
            f"Commit summaries:\n{commits}\nChanged files:\n{names}\nChange statistics:\n{stat}\nFirmware diff excerpt:\n{diff}\n")


def prepare(api, root, folder, repository, tag, source_sha):
    inputs(repository, tag, source_sha)
    trusted_source(root, repository, source_sha)
    if tag_commit(api, tag) != source_sha:
        raise ValueError("Existing release tag does not point to the exact build source SHA")
    release = find_draft(api, tag)
    selected = selected_assets(release, repository, tag, source_sha)
    folder.mkdir(mode=0o700, parents=True, exist_ok=False)
    hashes = {name: api.download(asset, folder / name) for name, asset in selected.items()}
    validate_files(root, folder, repository, tag, source_sha, hashes)
    promote, previous = latest_policy(api, root, tag, source_sha)
    (folder / "evidence.txt").write_text(evidence(root, source_sha, previous, REPOSITORIES[repository][2]))
    state = {"repository": repository, "tag": tag, "source_sha": source_sha,
             "release_id": release["id"], "assets": fingerprint(selected), "hashes": hashes,
             "promote": promote}
    (folder / "validation.json").write_text(json.dumps(state, indent=2) + "\n")
    print("Validated local firmware draft and bounded evidence; no build or router operation was performed.")


def finalize(api, root, folder, repository, tag, source_sha):
    inputs(repository, tag, source_sha)
    trusted_source(root, repository, source_sha)
    state = json.loads((folder / "validation.json").read_text())
    if any(state.get(k) != v for k, v in (("repository", repository), ("tag", tag), ("source_sha", source_sha))):
        raise ValueError("Validation state does not match publication inputs")
    if tag_commit(api, tag) != source_sha:
        raise ValueError("Tag moved after local draft validation")
    release = api.api("/releases/" + str(state["release_id"]))
    selected = selected_assets(release, repository, tag, source_sha)
    if fingerprint(selected) != state["assets"]:
        raise ValueError("Draft assets changed after validation; rerun the workflow")
    # Rehash every downloaded asset; never trust a checksum file as a shell list.
    hashes = {}
    for name in selected:
        path = folder / name
        if path.is_symlink() or not path.is_file() or path.stat().st_size != selected[name]["size"]:
            raise ValueError("Validated local asset changed")
        digest = hashlib.sha256()
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1 << 20), b""):
                digest.update(chunk)
        hashes[name] = digest.hexdigest()
    if hashes != state["hashes"]:
        raise ValueError("Validated local asset checksum changed")
    validate_files(root, folder, repository, tag, source_sha, hashes)
    ai = (folder / "ai-notes.md").read_text()
    if not valid_notes(ai):
        raise ValueError("Expected bounded release notes from the trusted Gemini generator")
    notes = (f"<!-- source-sha: {source_sha} -->\n\n" + ai.strip() + "\n\n## Build provenance\n\n"
             f"- Edition: ZBT-Z8803BE {REPOSITORIES[repository][2]}; release `{tag}`.\n"
             "- Firmware was compiled on the maintainer's local server. This Actions workflow only validated uploaded assets, generated release notes and published the draft.\n"
             "- Base: Far5eer `v25.12.021`, Linux `6.12.74`; target ZBT-Link ZBT-Z8803BE.\n"
             "- Repository changes describe intended behavior, not hardware-test certification. This publication workflow did not flash or operate a router.\n"
             "- Use the device-specific SquashFS sysupgrade image for normal upgrades. The initramfs image is for recovery/testing, not a normal persistent upgrade.\n"
             "- Verify downloads using the included `SHA256SUMS`. Back up settings and read upgrade notes before flashing.\n")
    api.upload_notes(release, notes)
    # Recheck after Gemini/network latency and immediately before publishing.
    current = api.api("/releases/" + str(release["id"]))
    if fingerprint(selected_assets(current, repository, tag, source_sha)) != state["assets"]:
        raise ValueError("Draft firmware changed before publication")
    if tag_commit(api, tag) != source_sha:
        raise ValueError("Tag moved before publication")
    promote, _ = latest_policy(api, root, tag, source_sha)
    result = api.api("/releases/" + str(release["id"]), method="PATCH",
                     data={"body": notes, "draft": False, "prerelease": False,
                           "make_latest": "true" if promote else "false"})
    if result.get("draft") is not False or result.get("tag_name") != tag:
        raise ValueError("GitHub did not confirm release publication")
    (folder / NOTES).write_text(notes)
    print("Published https://github.com/" + repository + "/releases/tag/" + tag)
    print("Marked latest." if promote else "Published as a historical release; existing newer/unrelated latest was preserved.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["prepare", "publish"])
    parser.add_argument("--workdir", required=True, type=Path)
    args = parser.parse_args()
    try:
        repository = os.environ.get("GITHUB_REPOSITORY", "")
        tag, source_sha = os.environ.get("RELEASE_TAG", ""), os.environ.get("SOURCE_SHA", "")
        inputs(repository, tag, source_sha)
        key = os.environ.get("GH_TOKEN", "")
        if not key:
            raise ValueError("GitHub Actions token is missing")
        api = GitHub(repository, key)
        command = prepare if args.command == "prepare" else finalize
        command(api, Path.cwd(), args.workdir, repository, tag, source_sha)
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        parser.exit(1, "Local release publication failed: " + str(error) + "\n")


if __name__ == "__main__":
    main()
