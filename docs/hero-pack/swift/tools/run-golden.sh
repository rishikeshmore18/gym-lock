#!/usr/bin/env bash
# Re-runs the Matrix golden script under bun against the in-repo web reference.
#
# mx/common.ts imports PROOF from hero4/card4.tsx, which pulls React and
# ../../src/springFast (not part of the pack). A scratch copy swaps that import
# for the constant (20 * 60) so the pure TS modules load on their own.
# Output goes to stdout; compare it with MatrixParity in
# ios-gymlock/GymLock/Views/Home/Hero/Matrix/MatrixScene.swift and MatrixStoryView.swift.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PACK="$(cd "$HERE/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/matrix-golden.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/swift"
cp -r "$PACK/web-reference" "$WORK/"
cp -r "$HERE" "$WORK/swift/tools"
sed -i "s#^import {PROOF} from '../../hero4/card4';#const PROOF = 20 * 60;#" "$WORK/web-reference/hero13/mx/common.ts"
cd "$WORK/swift/tools"
bun run matrix-golden.local.ts
