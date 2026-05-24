#!/usr/bin/env bash
# Test for script/bin/jj-set-snapshot-url. Exercises:
#   - fresh add appends a managed block
#   - same args re-run is a no-op (mtime stable)
#   - different URL replaces the prior block in place
#   - two different REPO_PATHs coexist as separate blocks
#   - resolves through a symlink (the production-shape case)
#   - refuses when ~/.config/jj/conf.d/user.toml is missing
#
# Usage: bash script/bin/test_jj-set-snapshot-url.sh

set -uo pipefail

DOTFILES_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
WRAPPER="$DOTFILES_ROOT/script/bin/jj-set-snapshot-url"

TMPDIR=$(mktemp -d /tmp/jj-set-snapshot-url-test.XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

# Override $HOME so the wrapper writes inside the sandbox.
export HOME="$TMPDIR"
mkdir -p "$HOME/.config/jj/conf.d"

# The "real" user.toml lives outside ~/.config so we can prove the wrapper
# follows the symlink.
real_config="$TMPDIR/private/user.toml"
mkdir -p "$(dirname "$real_config")"
cat >"$real_config" <<'BASE'
[user]
name = "Test User"
email = "test@example.com"
BASE

ln -s "$real_config" "$HOME/.config/jj/conf.d/user.toml"

pass=0
fail=0
check() {
    local label=$1 expected=$2 actual=$3
    if [ "$expected" = "$actual" ]; then
        echo "PASS: $label"
        pass=$((pass+1))
    else
        echo "FAIL: $label"
        echo "  expected: [$expected]"
        echo "  actual:   [$actual]"
        fail=$((fail+1))
    fi
}

count_blocks() {
    local file=$1 tag=$2
    grep -c "^# >>> jj-set-snapshot-url: $tag >>>$" "$file"
}

echo
echo "=== Test 1: fresh add appends a managed block ==="
"$WRAPPER" "~/brazil-repos/Foo" "ssh://server/Foo"
check "Foo block count = 1" "1" "$(count_blocks "$real_config" '~/brazil-repos/Foo' 2>/dev/null || echo X)"
# Marker tag derives from the repo path with leading ~/ stripped and / -> -
check "Foo marker tag = brazil-repos-Foo" "1" "$(count_blocks "$real_config" 'brazil-repos-Foo')"
check "Foo URL present" "snapshot-url = \"ssh://server/Foo\"" "$(grep -E '^snapshot-url' "$real_config" | head -1)"

echo
echo "=== Test 2: same args re-run is a no-op (file unchanged) ==="
mtime_before=$(stat -c %Y "$real_config")
sleep 1.1
"$WRAPPER" "~/brazil-repos/Foo" "ssh://server/Foo"
mtime_after=$(stat -c %Y "$real_config")
check "mtime unchanged on no-op re-run" "$mtime_before" "$mtime_after"

echo
echo "=== Test 3: different URL replaces the prior block in place ==="
"$WRAPPER" "~/brazil-repos/Foo" "ssh://server/Foo-v2"
foo_blocks=$(count_blocks "$real_config" 'brazil-repos-Foo')
check "Foo block count still 1 after URL update" "1" "$foo_blocks"
url_count=$(grep -c '^snapshot-url' "$real_config")
check "exactly one snapshot-url line for Foo" "1" "$url_count"
check "Foo URL updated" "snapshot-url = \"ssh://server/Foo-v2\"" "$(grep -E '^snapshot-url' "$real_config" | head -1)"

echo
echo "=== Test 4: two different REPO_PATHs coexist ==="
"$WRAPPER" "~/brazil-repos/Bar" "ssh://server/Bar"
foo_blocks=$(count_blocks "$real_config" 'brazil-repos-Foo')
bar_blocks=$(count_blocks "$real_config" 'brazil-repos-Bar')
check "Foo block still present" "1" "$foo_blocks"
check "Bar block added" "1" "$bar_blocks"
url_count=$(grep -c '^snapshot-url' "$real_config")
check "two snapshot-url lines now" "2" "$url_count"

echo
echo "=== Test 5: refuses when ~/.config/jj/conf.d/user.toml missing ==="
rm -f "$HOME/.config/jj/conf.d/user.toml"
"$WRAPPER" "~/brazil-repos/Baz" "ssh://server/Baz" >/dev/null 2>&1
rc=$?
if [ "$rc" -ne 0 ]; then
    echo "PASS: refused (exit $rc) when user.toml missing"
    pass=$((pass+1))
else
    echo "FAIL: silently accepted with missing user.toml"
    fail=$((fail+1))
fi

echo
echo "=== Test 6: idempotent against pre-existing manual block ==="
# Prove we don't clobber a manually-curated block with a different tag —
# the wrapper only manages its own tagged region.
ln -s "$real_config" "$HOME/.config/jj/conf.d/user.toml"
cat >>"$real_config" <<'MANUAL'

# Manual entry — must survive jj-set-snapshot-url runs.
[[--scope]]
--when.repositories = ["~/some/manual/path"]
[--scope.user]
email = "manual@example.com"
MANUAL
manual_email_before=$(grep '^email = "manual@example.com"' "$real_config" | wc -l)
"$WRAPPER" "~/brazil-repos/Foo" "ssh://server/Foo-v3"
manual_email_after=$(grep '^email = "manual@example.com"' "$real_config" | wc -l)
check "manual scope preserved across wrapper run" "$manual_email_before" "$manual_email_after"

echo
echo "=== Sample final user.toml ==="
cat "$real_config"

echo
echo "=== Results: $pass passed, $fail failed ==="
[ $fail -eq 0 ]
