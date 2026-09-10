#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Run the pinned dialer functions with mocked UCI/AT calls, never hardware.

QMODEM_TEST_TREE points to a checkout of the pinned QModem feed (defaults to
feeds/qmodem). All mutations are confined to temporary test clones. BusyBox
ash is preferred; bash can run the same bracket/variable regression tests
on development hosts without BusyBox. No SIM PINs, profiles or data sessions
are read or written on a router.
"""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
FEED = Path(os.environ.get("QMODEM_TEST_TREE", ROOT / "feeds/qmodem")).resolve()
REVISION = "a8b8a63e5b0853c79d2ad3f1ebbb673a724872bf"
DIALER = Path("application/qmodem/files/usr/share/qmodem/modem_dial.sh")
HELPER = ROOT / ".buildenv/apply-qmodem-fixes.sh"
PATCH = ROOT / ".buildenv/patches/qmodem-dial-guards.patch"
shell_choice = os.environ.get("QMODEM_TEST_SHELL", "busybox" if shutil.which("busybox") else "bash")
if shell_choice not in ("busybox", "bash"):
    raise RuntimeError("QMODEM_TEST_SHELL must be busybox or bash")
SHELL = ["busybox", "sh"] if shell_choice == "busybox" else ["bash"]


def command(argv, *, env=None, check=True):
    result = subprocess.run(argv, text=True, capture_output=True, timeout=30,
                            env={**os.environ, **(env or {})})
    if check and result.returncode:
        raise AssertionError(f"command failed: {argv}\n{result.stdout}\n{result.stderr}")
    return result


def function_range(source, first, following):
    return source[source.index(f"\n{first}()") + 1:
                  source.index(f"\n{following}()")]


class DialGuardTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not FEED.is_dir():
            raise RuntimeError("Install pinned QModem feeds or set QMODEM_TEST_TREE")
        actual = command(["git", "-C", str(FEED), "rev-parse", "HEAD"]).stdout.strip()
        if actual != REVISION:
            raise RuntimeError(f"Tests require pinned QModem {REVISION}, found {actual}")
        cls.pristine = command(["git", "-C", str(FEED), "show", f"HEAD:{DIALER}"]).stdout

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="qmodem-dial-guards-")
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.feed = self.base / "feed"
        command(["git", "clone", "--quiet", "--shared", "--no-checkout", str(FEED), str(self.feed)])
        command(["git", "-C", str(self.feed), "checkout", "--quiet", "--detach", REVISION])
        self.apply()
        self.source = (self.feed / DIALER).read_text()

    def apply(self, *, check=True, feed=None):
        return command(["sh", str(HELPER), str(feed or self.feed)], check=check)

    def shell(self, script, *, env=None, clean=True):
        # No errexit: unlock_sim intentionally handles a failed AT command
        # by checking its status; forcing -e would change production behavior.
        result = command([*SHELL, "-c", script], env=env)
        self.last_diagnostics = result.stderr
        if clean:
            self.assertEqual(result.stderr, "", "unexpected shell-test diagnostic")
        return result.stdout.strip()

    def config_fixture(self, *, source=None, **values):
        defaults = dict(PLATFORM="qualcomm", USER_INDEX="", SUGGESTED_INDEX="",
                        SIM_SLOT="1", SECOND_PIN="", STALE_PIN="")
        defaults.update(values)
        functions = function_range(source or self.source,
                                   "get_platform_suggest_pdp_index", "check_dial_prepare")
        return self.shell(functions + r'''
config_load() { :; }
config_foreach() { :; }
find() { echo /fixture/net; }
ls() { echo wwan_fixture; }
get_driver() { echo qmi; }
update_sim_slot() { sim_slot="$SIM_SLOT"; }
config_get() {
    local value=''
    case "$3" in
        path) value=/fixture/modem ;;
        manufacturer) value=quectel ;;
        platform) value="$PLATFORM" ;;
        pdp_index) value="$USER_INDEX" ;;
        suggest_pdp_index) value="$SUGGESTED_INDEX" ;;
        pincode) value=1111 ;;
        pincode2) value="$SECOND_PIN" ;;
    esac
    export "$1=$value"
}
modem_config=fixture_modem
pin="$STALE_PIN"
update_config
printf '%s:%s:%s:%s' "$pdp_index" "$suggest_pdp_index" "$userset_pdp_index" "$pincode"
''', env=defaults, clean=source is None)

    def pin_fixture(self, *, source=None):
        runtime = self.base / ("original-runtime" if source else "patched-runtime")
        (runtime / "fixture_modem_dir").mkdir(parents=True)
        functions = function_range(source or self.source, "unlock_sim", "get_platform_suggest_pdp_index")
        functions = functions.replace("/var/run/qmodem/", str(runtime) + "/")
        return self.shell(functions + r'''
lock() { :; }
m_debug() { :; }
at() { echo attempted >> "$ATTEMPTS"; return 1; }
modem_config=fixture_modem
unlock_sim 1234
unlock_sim 1234
unlock_sim 5678
wc -l < "$ATTEMPTS"
''', env={"ATTEMPTS": str(runtime / "attempts")}, clean=source is None)

    def test_duplicate_failed_pin_is_not_retried_but_new_pin_is(self):
        self.assertEqual(self.pin_fixture(), "2")
        self.assertEqual(self.pin_fixture(source=self.pristine), "3",
                         "fixture must reproduce the original failed retry guard")

    def test_missing_pdp_index_uses_platform_default(self):
        self.assertEqual(self.config_fixture(), "1:1:0:1111")
        self.assertEqual(self.config_fixture(PLATFORM="lte"), "3:3:0:1111")

    def test_explicit_suggestion_and_user_pdp_index_survive(self):
        self.assertEqual(self.config_fixture(SUGGESTED_INDEX="7"), "7:7:0:1111")
        self.assertEqual(self.config_fixture(USER_INDEX="5", SUGGESTED_INDEX="7"), "5:7:1:1111")
        self.config_fixture(source=self.pristine, SUGGESTED_INDEX="7")
        self.assertRegex(self.last_diagnostics, r"missing.*\]",
                      "the original nonempty suggestion must reproduce its bracket error")

    def test_internal_sim2_pin_is_preserved(self):
        self.assertEqual(self.config_fixture(SIM_SLOT="2", SECOND_PIN="2222"), "1:1:0:2222")
        self.assertEqual(self.config_fixture(source=self.pristine, SIM_SLOT="2",
                                             SECOND_PIN="2222", SUGGESTED_INDEX="1").split(":")[-1], "1111")

    def test_empty_internal_sim2_pin_falls_back_independently_of_stale_pin(self):
        self.assertEqual(self.config_fixture(SIM_SLOT="2", STALE_PIN="9999"), "1:1:0:1111")

    def test_internal_sim1_pin_is_unchanged(self):
        self.assertEqual(self.config_fixture(SIM_SLOT="1", SECOND_PIN="2222"), "1:1:0:1111")

    def test_patch_is_idempotent_and_only_changes_three_lines(self):
        before = (self.feed / DIALER).read_bytes()
        self.assertIn("already applied", self.apply().stdout)
        self.assertEqual((self.feed / DIALER).read_bytes(), before)
        changes = command(["git", "-C", str(self.feed), "diff", "--numstat"]).stdout.strip()
        self.assertEqual(changes, f"3\t3\t{DIALER}")
        command([*SHELL, "-n", str(self.feed / DIALER)])

    def test_patch_reapplies_after_feed_source_is_restored(self):
        command(["patch", "--batch", "--fuzz=0", "--reverse", "-d", str(self.feed), "-p1", "-i", str(PATCH)])
        self.assertEqual((self.feed / DIALER).read_text(), self.pristine)
        self.assertIn("guards applied", self.apply().stdout)
        self.assertEqual((self.feed / DIALER).read_text(), self.source)

    def test_partial_patch_is_rejected_without_modification(self):
        altered = self.source.replace('[ -z "$pincode" ] && config_get pincode',
                                      '[ -z "$pin" ] && config_get pincode')
        (self.feed / DIALER).write_text(altered)
        result = self.apply(check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("partially applied", result.stderr)
        self.assertEqual((self.feed / DIALER).read_text(), altered)
        self.assertFalse(list(self.feed.rglob("*.rej")))
        self.assertFalse(list(self.feed.rglob("*.orig")))

    def test_other_feed_revision_is_rejected(self):
        command(["git", "-C", str(self.feed), "-c", "user.name=Test Fixture", "-c",
                 "user.email=fixture@example.invalid", "commit", "--quiet", "--allow-empty", "-m", "fixture-only revision"])
        before = (self.feed / DIALER).read_bytes()
        result = self.apply(check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unreviewed revision", result.stderr)
        self.assertEqual((self.feed / DIALER).read_bytes(), before)

    def test_missing_or_nested_feed_directory_is_rejected(self):
        self.assertNotEqual(self.apply(feed=self.base / "missing", check=False).returncode, 0)
        result = self.apply(feed=self.feed / "application", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("own git checkout", result.stderr)

    def test_feed_and_build_hooks_apply_before_package_operations(self):
        wrapper = (ROOT / ".buildenv/build.sh").read_text()
        feed_stage = wrapper.split("    feeds)\n", 1)[1].split("    config)\n", 1)[0]
        build_stage = wrapper.split("    build)\n", 1)[1].split("    extract)\n", 1)[0]
        self.assertLess(feed_stage.rindex("./scripts/feeds update -a"),
                        feed_stage.index("sh .buildenv/apply-qmodem-fixes.sh"))
        self.assertLess(feed_stage.index("sh .buildenv/apply-qmodem-fixes.sh"),
                        feed_stage.index("./scripts/feeds install -a"))
        self.assertLess(build_stage.index("sh .buildenv/apply-qmodem-fixes.sh"),
                        build_stage.index("run_in_container make"))
        replay = (ROOT / ".buildenv/replay-customizations.sh").read_text()
        directories = replay.split("DIRS=(", 1)[1].split(")", 1)[0]
        self.assertIn("    .buildenv\n", directories)


if __name__ == "__main__":
    print("QModem fixture shell:", " ".join(SHELL), flush=True)
    unittest.main(verbosity=2)
