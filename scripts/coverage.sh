#!/bin/zsh
# Runs the tests with coverage on, prints a per-file summary of the app code,
# and writes a browsable HTML report to build/coverage/index.html.
set -euo pipefail
cd "$(dirname "$0")/.."

swift test --enable-code-coverage
BIN="$(swift build --show-bin-path)"
PROFILE="$BIN/codecov/default.profdata"
TESTS="$BIN/CricketFeedPackageTests.xctest/Contents/MacOS/CricketFeedPackageTests"
# Only the app's own code, not the tests or build files.
xcrun llvm-cov report "$TESTS" -instr-profile "$PROFILE" \
    -show-region-summary=false -show-branch-summary=false Sources/CricketFeed
rm -rf build/coverage
xcrun llvm-cov show "$TESTS" -instr-profile "$PROFILE" -format=html -output-dir build/coverage Sources/CricketFeed
echo "HTML report: build/coverage/index.html"
