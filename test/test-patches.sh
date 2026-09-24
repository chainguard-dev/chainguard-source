#!/bin/bash
# Copyright (C) 2025 Chainguard
#
# Offline tests for the patch collection logic.
#
# These build a structurally faithful APK fixture -- concatenated gzip streams,
# with the control segment deliberately missing its tar end-of-archive marker,
# exactly as apk v2 lays one out -- so the control section parsing is exercised
# for real without touching the network.

set -e

SELF_DIR=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$SELF_DIR/../chainguard-source"
TMP=$(mktemp -d /tmp/chainguard-source-test.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

FAILED=0

ok() { echo "ok   - $*"; }
fail() { echo "FAIL - $*" 1>&2; FAILED=1; }

check() {
	local desc="$1" expected="$2" actual="$3"
	if [ "$expected" = "$actual" ]; then
		ok "$desc"
	else
		fail "$desc (expected [$expected], got [$actual])"
	fi
}

# Source just the function definitions, stopping before the script body runs
eval "$(sed -n '1,/^# Check dependencies and set default values$/p' "$SCRIPT" | sed -e '$d')"

# Build an APK fixture. Arguments after the first are relative paths to include
# in the control section.
make_apk() {
	local apk="$1"; shift
	local root="$TMP/build"
	rm -rf "$root"
	mkdir -p "$root/control/.patches" "$root/data/var/lib/db/sbom"

	cat > "$root/control/.melange.yaml" <<-'YAML'
	package:
	  name: testpkg
	  version: 1.0
	  epoch: 0
	pipeline:
	  - uses: fetch
	    with:
	      uri: https://example.com/testpkg-1.0.tar.xz
	  - uses: patch
	    with:
	      patches: |
	        applied-one.patch
	        applied-two.patch
	  - name: a nested pipeline
	    pipeline:
	      - uses: patch
	        with:
	          patches: nested.patch
	subpackages:
	  - name: testpkg-dev
	    pipeline:
	      - uses: patch
	        with:
	          patches: subpkg.patch
	YAML
	printf 'pkgname = testpkg\npkgver = 1.0-r0\n' > "$root/control/.PKGINFO"
	echo '{"packages":[]}' > "$root/data/var/lib/db/sbom/testpkg.spdx.json"

	local p
	for p in "$@"; do
		printf -- '--- a/x\n+++ b/x\n' > "$root/control/.patches/$p"
	done
	# apk-tools rejects control entries whose names contain a '/', so patches
	# ship as a single flat .patches.tar rather than a .patches/ directory.
	# With no patches we model today's APKs, which carry none at all.
	if [ "$#" -gt 0 ]; then
		tar cf "$root/control/.patches.tar" -C "$root/control/.patches" .
	fi
	rm -rf "$root/control/.patches"

	# Name the members explicitly: real APK control sections store them
	# unprefixed, and 'tar -C dir .' would store them as ./.melange.yaml
	local members=".PKGINFO .melange.yaml"
	[ -f "$root/control/.patches.tar" ] && members="$members .patches.tar"
	tar cf "$root/control.tar" -C "$root/control" $members
	# apk v2 control segments omit the end-of-archive marker so that the
	# control and data gzip streams concatenate into one readable archive.
	# Truncate at the exact end of the last member rather than stripping
	# trailing NULs: .patches.tar ends in its own zero padding, and stripping
	# would eat part of it.
	python3 -c "
import io, tarfile
raw = open('$root/control.tar','rb').read()
tf = tarfile.open(fileobj=io.BytesIO(raw), mode='r:')
end = 0
for m in tf.getmembers():
    end = m.offset_data + ((m.size + 511) // 512) * 512
open('$root/control.stripped.tar','wb').write(raw[:end])
"
	gzip -9 -c "$root/control.stripped.tar" > "$root/control.tar.gz"
	tar czf "$root/data.tar.gz" -C "$root/data" var
	cat "$root/control.tar.gz" "$root/data.tar.gz" > "$apk"
}

echo "# fixture sanity"
APK="$TMP/testpkg-1.0-r0.apk"
make_apk "$APK" applied-one.patch applied-two.patch nested.patch subpkg.patch
check "data section still readable" \
	'{"packages":[]}' \
	"$(tar zxOf "$APK" --wildcards 'var/lib/db/sbom/*.spdx.json' 2>/dev/null)"

echo "# extract_melange_config"
CONFIG="$TMP/testpkg.melange.yaml"
extract_melange_config "$APK" "$CONFIG" >/dev/null 2>&1
check "config extracted from control section" "testpkg" "$(yq -r '.package.name' "$CONFIG")"
check "melange_pkg_name" "testpkg" "$(melange_pkg_name "$CONFIG")"

echo "# melange_patch_list"
check "finds top level, nested and subpackage patch steps" \
	"applied-one.patch applied-two.patch nested.patch subpkg.patch" \
	"$(melange_patch_list "$CONFIG" "" | sort | tr '\n' ' ' | sed -e 's/ $//')"

echo "# extract_embedded_patches (patches shipped inside the APK)"
WORK_DIR="$TMP/work"
mkdir -p "$WORK_DIR"
harvest_apk_metadata "$APK" "$WORK_DIR/testpkg.sbom.spdx.json"
check "patches landed in the package patch dir" \
	"applied-one.patch applied-two.patch nested.patch subpkg.patch" \
	"$(cd "$(patchdir_for_pkg testpkg)" && ls *.patch | sort | tr '\n' ' ' | sed -e 's/ $//')"

check "provenance recorded as embedded" \
	"embedded" \
	"$(cat "$(patchdir_for_pkg testpkg)/.provenance" 2>/dev/null)"

echo "# summarize_patches with everything present"
PATCH_REPO_DENIED=
summarize_patches >/dev/null 2>&1
MANIFEST="$WORK_DIR/patches/MANIFEST.txt"
check "no patches reported missing" "0" "$(grep -c '^MISSING' "$MANIFEST" || true)"
check "all four patches accounted for" "4" "$(grep -c '^OK' "$MANIFEST" || true)"
check "embedded patches are not labelled MIRROR" "0" "$(grep -c '^MIRROR' "$MANIFEST" || true)"

echo "# summarize_patches against a present-day APK that ships no patches"
APK2="$TMP/testpkg-nopatches-1.0-r0.apk"
make_apk "$APK2"
WORK_DIR="$TMP/work2"
mkdir -p "$WORK_DIR"
harvest_apk_metadata "$APK2" "$WORK_DIR/testpkg.sbom.spdx.json"
PATCH_REPO_DENIED=
summarize_patches >/dev/null 2>&1
MANIFEST="$WORK_DIR/patches/MANIFEST.txt"
check "every applied patch is reported missing" "4" "$(grep -c '^MISSING' "$MANIFEST" || true)"
check "the config still tells us what was applied" \
	"1" \
	"$(grep -c 'applied-one.patch' "$MANIFEST" || true)"

echo
if [ "$FAILED" -eq 0 ]; then
	echo "All tests passed."
else
	echo "Some tests FAILED." 1>&2
	exit 1
fi
