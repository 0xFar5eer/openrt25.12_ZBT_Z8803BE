#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Build-time-only backport for the pinned external QModem feed.
# Invoke after feeds update and before building an existing feed checkout.
# This helper never contacts a router or edits runtime UCI configuration.
set -eu

here=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
root=$(dirname "$here")
feed=${1:-$root/feeds/qmodem}
revision=a8b8a63e5b0853c79d2ad3f1ebbb673a724872bf
patch_file=$here/patches/qmodem-dial-guards.patch

fail() {
	printf 'QModem dial guards: %s\n' "$*" >&2
	exit 1
}

grep -Fqx "src-git qmodem https://github.com/FUjr/QModem.git^$revision" \
	"$root/feeds.conf.default" || fail 'feed pin changed; review this backport before building'
[ -d "$feed" ] || fail 'feed is missing; run .buildenv/build.sh feeds first'
feed=$(CDPATH= cd -- "$feed" && pwd -P)
top=$(git -C "$feed" rev-parse --show-toplevel 2>/dev/null) || fail 'feed is not a git checkout'
[ "$top" = "$feed" ] || fail 'feed must be its own git checkout'
actual=$(git -C "$feed" rev-parse HEAD) || fail 'cannot read feed revision'
[ "$actual" = "$revision" ] || fail "expected feed $revision, found $actual; refusing an unreviewed revision"

# Test every hunk before writing anything. Repeated feeds/build invocations
# accept the fully applied patch; partial application or drift fails closed.
# A feed update that restored the pinned source is patched again next time.
if patch --batch --fuzz=0 --forward --dry-run -d "$feed" -p1 < "$patch_file" >/dev/null 2>&1; then
	patch --batch --fuzz=0 --forward -d "$feed" -p1 < "$patch_file"
	printf 'QModem dial guards applied\n'
elif patch --batch --fuzz=0 --reverse --dry-run -d "$feed" -p1 < "$patch_file" >/dev/null 2>&1; then
	printf 'QModem dial guards already applied\n'
else
	fail 'pinned source differs or patch is partially applied; no files were changed'
fi
