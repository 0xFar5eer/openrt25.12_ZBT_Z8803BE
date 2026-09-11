"""Offline regression tests: fake GitHub, no secrets, compiler or router access."""
import copy
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock
import urllib.request

import publish_local_release as p

MEGA = next(name for name, details in p.REPOSITORIES.items() if details[1] == "mega")
MINIMAL = next(name for name, details in p.REPOSITORIES.items() if details[1] == "minimal")
TAG = "firmware-202609100657.1"


class FakeGitHub:
    def __init__(self, repository, source_sha, content):
        self.repository, self.source_sha, self.content = repository, source_sha, content
        self.tags, self.latest, self.uploaded = {TAG: source_sha}, None, []
        self.published = None
        self.release = {"id": 11, "tag_name": TAG, "target_commitish": source_sha,
                        "draft": True, "prerelease": False, "assets": []}
        for ident, (name, data) in enumerate(content.items(), 100):
            self.release["assets"].append({"id": ident, "name": name, "size": len(data),
                                           "url": "https://api.github.com/repos/" + repository + "/releases/assets/" + str(ident),
                                           "state": "uploaded", "updated_at": "2026-09-10T00:00:00Z",
                                           "digest": "sha256:" + hashlib.sha256(data).hexdigest()})

    def api(self, path, method="GET", data=None, allow_missing=False):
        if path.startswith("/git/ref/tags/"):
            tag = path.removeprefix("/git/ref/tags/")
            if tag not in self.tags:
                raise ValueError("Tag must exist")
            return {"object": {"type": "commit", "sha": self.tags[tag]}}
        if path == "/releases/latest":
            return copy.deepcopy(self.latest)
        if path.startswith("/releases?per_page=50&page="):
            return [copy.deepcopy(self.release)]
        if path == "/releases/11":
            if method == "PATCH":
                self.published = copy.deepcopy(data)
                self.release.update(data)
            return copy.deepcopy(self.release)
        raise AssertionError((path, method))

    def download(self, asset, destination):
        data = self.content[asset["name"]]
        destination.write_bytes(data)
        return hashlib.sha256(data).hexdigest()

    def upload_notes(self, release, notes):
        self.uploaded.append(notes)


class PublicationTests(unittest.TestCase):
    def setUp(self):
        quiet = mock.patch("builtins.print")
        quiet.start()
        self.addCleanup(quiet.stop)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "repo"
        self.root.mkdir()
        self.command("init", "-b", "master")
        (self.root / "firmware/scripts").mkdir(parents=True)
        self.runtime = b"#!/bin/sh\nprintf '%s\\n' 'read-only verifier fixture'\n"
        (self.root / "firmware/scripts/verify-router-runtime.sh").write_bytes(self.runtime)
        (self.root / "README.md").write_text("Router firmware fixture\n")
        self.source = self.commit("fixture build source")
        self.command("update-ref", "refs/remotes/origin/master", self.source)
        self.command("update-ref", "refs/remotes/origin/main", self.source)

    def command(self, *args):
        return subprocess.check_output(["git", "-C", str(self.root), *args], stderr=subprocess.DEVNULL).decode().strip()

    def commit(self, message):
        self.command("add", ".")
        self.command("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-m", message)
        return self.command("rev-parse", "HEAD")

    def api(self, repository=MEGA):
        images = {p.SYSUPGRADE: b"s" * (1 << 20), p.INITRAMFS: b"i" * (1 << 20)}
        content = {**images, p.PACKAGE_MANIFEST: b"base-files - fixture\n", p.RUNTIME: self.runtime}
        content["SHA256SUMS"] = "".join(hashlib.sha256(data).hexdigest() + "  " + name + "\n" for name, data in images.items()).encode()
        fields = {"Recipe commit": self.source, "Target": "mediatek/filogic", "Device": p.DEVICE,
                  "Edition": p.REPOSITORIES[repository][2], "Version": TAG, "Build host": "local server",
                  "OpenWrt source": "https://github.com/0xFar5eer/openwrt25.12_ZBT_Z8803BE.git",
                  "OpenWrt ref": "v25.12.021", "OpenWrt commit": p.BASE_SHA}
        content["BUILD-INFO.txt"] = "".join(k + ": " + v + "\n" for k, v in fields.items()).encode()
        if repository == MEGA:
            content["mega-release.json"] = json.dumps({"schema": 1, "variant": "mega", "repository": repository,
                                                        "board": p.BOARD, "version": TAG, "source_sha": self.source,
                                                        "base_version": "v25.12.021", "dirty": False,
                                                        "built_at": "2026-09-10T06:57:00Z",
                                                        "image": {"name": p.SYSUPGRADE, "size": len(images[p.SYSUPGRADE]),
                                                                  "sha256": hashlib.sha256(images[p.SYSUPGRADE]).hexdigest()}}).encode()
        return FakeGitHub(repository, self.source, content)

    def prepare(self, api):
        folder = Path(self.temp.name) / "publication"
        p.prepare(api, self.root, folder, api.repository, TAG, self.source)
        return folder

    def notes(self, folder):
        text = "".join(heading + "\n\n- " + "Evidence-bound firmware behavior. " * 7 + "\n\n" for heading in
                       ("## Highlights", "## Bug fixes", "## Features and additions", "## Upgrade notes"))
        (folder / "ai-notes.md").write_text(text)

    def test_valid_mega_publication(self):
        api = self.api()
        folder = self.prepare(api)
        self.notes(folder)
        p.finalize(api, self.root, folder, MEGA, TAG, self.source)
        self.assertFalse(api.published["draft"])
        self.assertEqual(api.published["make_latest"], "true")
        self.assertIn("compiled on the maintainer's local server", api.uploaded[0])
        self.assertIn("did not flash or operate a router", api.uploaded[0])
        self.assertIn("<!-- source-sha: " + self.source, api.uploaded[0])

    def test_valid_minimal_publication(self):
        api = self.api(MINIMAL)
        folder = self.prepare(api)
        self.notes(folder)
        p.finalize(api, self.root, folder, MINIMAL, TAG, self.source)
        self.assertEqual(api.published["make_latest"], "true")
        self.assertNotIn("mega-release.json", api.content)

    def test_rejects_inputs_and_shell_strings(self):
        for tag in ["main", "../../tmp", "firmware-1.1; touch /tmp/pwned", "$(id)", "-v", "firmware-0.1"]:
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                p.inputs(MEGA, tag, self.source)
        for sha in ["HEAD", "f" * 39, "a" * 40 + ";id", "A" * 40]:
            with self.subTest(sha=sha), self.assertRaises(ValueError):
                p.inputs(MEGA, TAG, sha)
        with self.assertRaises(ValueError):
            p.inputs("evil/firmware", TAG, self.source)

    def test_trusted_checkout_and_source_ancestry(self):
        (self.root / "other.txt").write_text("new branch change")
        other = self.commit("untrusted local checkout")
        with self.assertRaises(ValueError):
            p.trusted_source(self.root, MEGA, self.source)
        self.command("update-ref", "refs/remotes/origin/master", other)
        p.trusted_source(self.root, MEGA, self.source)
        with self.assertRaises(ValueError):
            p.trusted_source(self.root, MEGA, "0" * 40)

    def test_preexisting_exact_tag_required(self):
        api = self.api()
        api.tags[TAG] = "b" * 40
        with self.assertRaises(ValueError):
            self.prepare(api)

    def test_rejects_wrong_draft_target_or_published_release(self):
        for key, value in [("target_commitish", "master"), ("target_commitish", "b" * 40),
                           ("draft", False), ("prerelease", True), ("tag_name", "firmware-3.1")]:
            api = self.api()
            api.release[key] = value
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                p.selected_assets(api.release, MEGA, TAG, self.source)

    def test_asset_whitelist_paths_duplicates_and_limits(self):
        changes = [lambda r: r["assets"].append({**r["assets"][0], "name": "source.tar.gz"}),
                   lambda r: r["assets"].append(r["assets"][0]),
                   lambda r: r["assets"][0].update(name="../../evil.bin"),
                   lambda r: r["assets"][0].update(size=(128 << 20) + 1),
                   lambda r: r["assets"][0].update(size=100),
                   lambda r: r["assets"][0].update(url="https://evil.example/image.bin"),
                   lambda r: r["assets"][0].update(state="new"),
                   lambda r: r["assets"].pop()]
        for number, change in enumerate(changes):
            api = self.api()
            change(api.release)
            with self.subTest(number=number), self.assertRaises(ValueError):
                p.selected_assets(api.release, MEGA, TAG, self.source)

    def test_checksum_names_never_become_shell_paths(self):
        good = "a" * 64 + "  " + p.SYSUPGRADE + "\n" + "b" * 64 + " *" + p.INITRAMFS + "\n"
        self.assertEqual(set(p.checksums(good)), {p.SYSUPGRADE, p.INITRAMFS})
        for bad in [good + good, good.replace(p.INITRAMFS, "../" + p.INITRAMFS),
                    good.replace(p.INITRAMFS, "/etc/passwd"), good.replace("a" * 64, "x" * 64), ""]:
            with self.subTest(bad=bad[:90]), self.assertRaises(ValueError):
                p.checksums(bad)

    def test_mega_manifest_board_variant_source_hash_and_size(self):
        for key, value in [("board", "wrong,board"), ("variant", "minimal"), ("dirty", True),
                           ("version", "firmware-2.1"), ("source_sha", "c" * 40),
                           ("repository", MINIMAL), ("built_at", "not a date")]:
            with self.subTest(key=key):
                api = self.api()
                data = json.loads(api.content["mega-release.json"])
                data[key] = value
                api.content["mega-release.json"] = json.dumps(data).encode()
                folder = Path(self.temp.name) / ("invalid-" + key)
                folder.mkdir()
                hashes = {}
                for name, payload in api.content.items():
                    (folder / name).write_bytes(payload)
                    hashes[name] = hashlib.sha256(payload).hexdigest()
                with self.assertRaises(ValueError):
                    p.validate_files(self.root, folder, MEGA, TAG, self.source, hashes)

    def test_provenance_or_runtime_mismatch(self):
        api = self.api()
        folder = self.prepare(api)
        hashes = json.loads((folder / "validation.json").read_text())["hashes"]
        hashes[p.RUNTIME] = "0" * 64
        with self.assertRaises(ValueError):
            p.validate_files(self.root, folder, MEGA, TAG, self.source, hashes)
        text = (folder / "BUILD-INFO.txt").read_text().replace("Build host: local server", "Build host: GitHub")
        (folder / "BUILD-INFO.txt").write_text(text)
        with self.assertRaises(ValueError):
            p.validate_files(self.root, folder, MEGA, TAG, self.source, hashes)

    def test_changed_draft_blocks_publish(self):
        api = self.api()
        folder = self.prepare(api)
        self.notes(folder)
        api.release["assets"][0]["id"] += 500
        with self.assertRaises(ValueError):
            p.finalize(api, self.root, folder, MEGA, TAG, self.source)
        self.assertIsNone(api.published)

    def test_changed_local_download_blocks_publish(self):
        api = self.api()
        folder = self.prepare(api)
        self.notes(folder)
        (folder / p.SYSUPGRADE).write_bytes(b"changed")
        with self.assertRaises(ValueError):
            p.finalize(api, self.root, folder, MEGA, TAG, self.source)
        self.assertIsNone(api.published)

    def test_newer_latest_descendant_is_preserved(self):
        api = self.api()
        (self.root / "new.txt").write_text("newer firmware fixes")
        descendant = self.commit("newer source already released")
        self.command("update-ref", "refs/remotes/origin/master", descendant)
        api.tags["firmware-202609101200.1"] = descendant
        api.latest = {"tag_name": "firmware-202609101200.1", "body": "<!-- source-sha: " + descendant + " -->"}
        folder = self.prepare(api)
        self.notes(folder)
        p.finalize(api, self.root, folder, MEGA, TAG, self.source)
        self.assertEqual(api.published["make_latest"], "false")

    def test_later_latest_rechecked_after_notes(self):
        api = self.api()
        folder = self.prepare(api)
        self.notes(folder)
        (self.root / "new.txt").write_text("newer source")
        descendant = self.commit("latest advanced while Gemini ran")
        self.command("update-ref", "refs/remotes/origin/master", descendant)
        api.tags["firmware-202609101200.1"] = descendant
        api.latest = {"tag_name": "firmware-202609101200.1", "body": ""}
        p.finalize(api, self.root, folder, MEGA, TAG, self.source)
        self.assertEqual(api.published["make_latest"], "false")

    def test_same_source_older_tag_not_promoted(self):
        api = self.api()
        api.tags["firmware-202609101200.1"] = self.source
        api.latest = {"tag_name": "firmware-202609101200.1", "body": ""}
        promote, _ = p.latest_policy(api, self.root, TAG, self.source)
        self.assertFalse(promote)

    def test_redirects_strip_auth_and_reject_external_hosts(self):
        handler = p.AssetRedirects()
        request = urllib.request.Request("https://api.github.com/repos/fixed/repo/releases/assets/1", headers={"Authorization": "Bearer fixture-not-a-secret"})
        redirected = handler.redirect_request(request, None, 302, "found", {}, "https://release-assets.githubusercontent.com/fixed?sig=fixture")
        self.assertIsNone(redirected.get_header("Authorization"))
        for raw in ["http://release-assets.githubusercontent.com/a", "https://evil.example/a", "https://api.github.com/other", "https://user@objects.githubusercontent.com/a", "https://objects.githubusercontent.com:444/a"]:
            with self.subTest(url=raw), self.assertRaises(ValueError):
                handler.redirect_request(request, None, 302, "found", {}, raw)

    def test_http_download_bound_and_digest(self):
        api = p.GitHub(MEGA, "fake-token-not-a-secret")
        class Response:
            headers = {}
            def __init__(self, data): self.data = data
            def __enter__(self): return self
            def __exit__(self, *args): return None
            def read(self, n):
                data, self.data = self.data[:n], self.data[n:]
                return data
        asset = {"id": 7, "size": 3, "digest": "sha256:" + hashlib.sha256(b"abc").hexdigest()}
        for index, data in enumerate([b"abcd", b"ab"]):
            with mock.patch.object(api, "request", return_value=Response(data)), self.assertRaises(ValueError):
                api.download(asset, Path(self.temp.name) / str(index))
        with mock.patch.object(api, "request", return_value=Response(b"abc")):
            self.assertEqual(api.download(asset, Path(self.temp.name) / "good"), hashlib.sha256(b"abc").hexdigest())

    def test_output_folder_symlink_is_not_followed(self):
        api = self.api()
        folder = Path(self.temp.name) / "publication"
        folder.symlink_to(self.root, target_is_directory=True)
        with self.assertRaises(FileExistsError):
            p.prepare(api, self.root, folder, MEGA, TAG, self.source)


if __name__ == "__main__":
    unittest.main()
