#!/bin/sh
# Regression tests: `make test`.
# Checks the generated configs against tests/expected/ and a few error cases.
# After an intended change to cain.json or the generators, refresh with:
#   UPDATE=1 sh tests/run.sh
cd "$(dirname "$0")/.." || exit 1
export HOME=/home/cain-test CAIN_DIR=.
fail=0

for os in linux windows macos; do
    if [ -n "$UPDATE" ]; then
        ./cain generate $os > tests/expected/$os.txt
    elif ./cain generate $os | diff -u tests/expected/$os.txt - > /tmp/cain-test.diff; then
        echo "ok    generate $os"
    else
        echo "FAIL  generate $os"; cat /tmp/cain-test.diff; fail=1
    fi
done

expect_error() {  # expect_error <description> <message> <cain.json> <args...>
    desc=$1 msg=$2 json=$3; shift 3
    dir=$(mktemp -d)
    printf '%s' "$json" > "$dir/cain.json"
    if CAIN_DIR=$dir ./cain "$@" 2>&1 | grep -q "$msg"; then echo "ok    $desc"
    else echo "FAIL  $desc (wanted: $msg)"; fail=1; fi
    rm -rf "$dir"
}
expect_error "bad key combo"   "alt+nope"             '{"remaps": [{"from": "alt+nope", "to": "left"}]}' generate linux
expect_error "broken JSON"     "line 2"               '{"remaps": [
}' generate linux
expect_error "unknown action"  "unknown shortcut"     '{"shortcuts": [{"action": "fly", "keys": ["alt+f"]}]}' generate windows
expect_error "unknown step"    "unknown install step" '{}' install nope

exit $fail
