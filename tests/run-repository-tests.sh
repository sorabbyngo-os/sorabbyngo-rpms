#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
VERIFIER="$ROOT/scripts/repository.sh"
SOURCE_REPO="$ROOT/build/metadata-test/repo"
RPM_DB="${SORABBYNGO_TEST_RPM_DB:-/var/tmp/sorabbyngo-rpm-verify}"
TEMP_ROOT=""

pass() {
    printf '[PASS] %s\n' "$*"
}

fail() {
    printf '[FAIL] %s\n' "$*" >&2
    exit 1
}

expect_failure() {
    local description="$1"
    shift

    if "$@" >"$TEMP_ROOT/expected-failure.log" 2>&1; then
        cat "$TEMP_ROOT/expected-failure.log"
        fail "$description (unexpected success)"
    fi

    pass "$description"
}

[[ -x "$VERIFIER" ]] || fail "Repository verifier is missing or not executable"
[[ -d "$SOURCE_REPO" ]] || fail "Test repository is missing: $SOURCE_REPO"
[[ -d "$RPM_DB" ]] || fail "RPM verification database is missing: $RPM_DB"

mkdir -p "$ROOT/build"
TEMP_ROOT="$(mktemp -d "$ROOT/build/regression.XXXXXXXX")"
trap 'rm -rf -- "$TEMP_ROOT"' EXIT

VALID="$TEMP_ROOT/valid"
BAD_INDEX="$TEMP_ROOT/bad-index"
BAD_CHECKSUM="$TEMP_ROOT/bad-checksum"
BAD_SIGNATURE="$TEMP_ROOT/bad-signature"

cp -a "$SOURCE_REPO" "$VALID"
cp -a "$SOURCE_REPO" "$BAD_INDEX"
cp -a "$SOURCE_REPO" "$BAD_CHECKSUM"
cp -a "$SOURCE_REPO" "$BAD_SIGNATURE"

printf '\n===== RELEASE CONTRACT =====\n'
bash "$ROOT/tests/test-release-contract.sh"
pass "Release contract"

printf '\n===== VALID REPOSITORY =====\n'
"$VERIFIER" verify "$VALID"
pass "Valid repository metadata and package checksums"

printf '\n===== TAMPERED INDEX =====\n'
printf '\n<!-- regression tampering -->\n' >> "$BAD_INDEX/repodata/repomd.xml"
expect_failure "Tampered repository index rejected" \
    "$VERIFIER" verify "$BAD_INDEX"

printf '\n===== TAMPERED PACKAGE CHECKSUM =====\n'
rpm_file="$(find "$BAD_CHECKSUM" -maxdepth 1 -type f -name '*.rpm' -print -quit)"
[[ -n "$rpm_file" ]] || fail "Test repository has no RPM"
printf 'tampering' >> "$rpm_file"
expect_failure "Modified RPM checksum rejected by metadata verifier" \
    "$VERIFIER" verify "$BAD_CHECKSUM"

printf '\n===== VALID RPM SIGNATURE =====\n'
"$VERIFIER" rpm-verify "$VALID" "$RPM_DB"
pass "Valid RPM signature and digests"

printf '\n===== TAMPERED RPM PAYLOAD =====\n'
rpm_file="$(find "$BAD_SIGNATURE" -maxdepth 1 -type f -name '*.rpm' -print -quit)"
[[ -n "$rpm_file" ]] || fail "Test repository has no RPM"
printf 'tampering' >> "$rpm_file"
expect_failure "Modified RPM payload rejected by signature verifier" \
    "$VERIFIER" rpm-verify "$BAD_SIGNATURE" "$RPM_DB"

printf '\n===== WRONG TRUSTED FINGERPRINT =====\n'
expect_failure "Wrong trusted RPM fingerprint rejected" \
    env SORABBYNGO_RPM_FINGERPRINT=0000000000000000000000000000000000000000 \
    "$VERIFIER" rpm-verify "$VALID" "$RPM_DB"

printf '\n===== REPOSITORY BOUNDARY =====\n'
expect_failure "Repository outside build directory rejected" \
    "$VERIFIER" verify "$ROOT/tests"

printf '\n===== INVALID RPM DATABASE =====\n'
expect_failure "Nonexistent RPM database rejected" \
    "$VERIFIER" rpm-verify "$VALID" "$TEMP_ROOT/nonexistent-rpm-db"

printf '\n===== SUMMARY =====\n'
printf 'All repository regression tests passed.\n'
