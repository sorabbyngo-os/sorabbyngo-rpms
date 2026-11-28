#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
PUBLISHER="$ROOT/scripts/publication.sh"
SOURCE_REPO="$ROOT/build/metadata-test/repo"
RPM_DB="${SORABBYNGO_TEST_RPM_DB:-/var/tmp/sorabbyngo-rpm-verify}"
SIGNING_HOME="${SORABBYNGO_MANIFEST_SIGNING_HOME:-$HOME/.local/share/sorabbyngo-signing/release}"
VERIFY_KEY="${SORABBYNGO_MANIFEST_VERIFY_KEY:-$ROOT/config-package/keys/RPM-GPG-KEY-sorabbyngo.asc}"
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

[[ -x "$PUBLISHER" ]] || fail "Publication script is missing or not executable"
[[ -d "$SOURCE_REPO" ]] || fail "Signed source repository is missing: $SOURCE_REPO"
[[ -d "$RPM_DB" ]] || fail "RPM verification database is missing: $RPM_DB"
[[ -d "$SIGNING_HOME" ]] || fail "Manifest signing GPG home is missing: $SIGNING_HOME"
[[ -s "$VERIFY_KEY" ]] || fail "Manifest verification key is missing: $VERIFY_KEY"

mkdir -p "$ROOT/build"
TEMP_ROOT="$(mktemp -d "$ROOT/build/publication-regression.XXXXXXXX")"
trap 'chmod -R u+rwX -- "$TEMP_ROOT" 2>/dev/null || true; rm -rf -- "$TEMP_ROOT"' EXIT

VALID_ROOT="$TEMP_ROOT/valid"
MANIFEST_TAMPER_ROOT="$TEMP_ROOT/manifest-tamper"
SIGNATURE_TAMPER_ROOT="$TEMP_ROOT/signature-tamper"
mkdir -p "$VALID_ROOT"

export SORABBYNGO_PUBLICATION_ROOT="$VALID_ROOT"

printf '\n===== PREPARE SIGNED SNAPSHOT =====\n'
prepare_output="$(
    "$PUBLISHER" prepare 2099.1 "$RPM_DB" "x86_64=$SOURCE_REPO"
)"
printf '%s\n' "$prepare_output"

snapshot_id="$(
    awk '/^Snapshot ID:/ {print $3}' <<< "$prepare_output"
)"
[[ "$snapshot_id" =~ ^[a-f0-9]{64}$ ]] ||
    fail "Could not extract a valid snapshot ID"
pass "Signed snapshot prepared"

printf '\n===== VERIFY VALID SNAPSHOT =====\n'
"$PUBLISHER" verify-snapshot "$snapshot_id" "$RPM_DB"
pass "Valid signed snapshot accepted"

snapshot="$VALID_ROOT/snapshots/$snapshot_id"

printf '\n===== TAMPERED MANIFEST =====\n'
mkdir -p "$MANIFEST_TAMPER_ROOT/snapshots"
cp -a "$snapshot" "$MANIFEST_TAMPER_ROOT/snapshots/$snapshot_id"
chmod u+w "$MANIFEST_TAMPER_ROOT/snapshots/$snapshot_id/2099.1/RELEASE-MANIFEST"
printf '\nTAMPERED=1\n' >> "$MANIFEST_TAMPER_ROOT/snapshots/$snapshot_id/2099.1/RELEASE-MANIFEST"

expect_failure "Modified manifest rejected" \
    env SORABBYNGO_PUBLICATION_ROOT="$MANIFEST_TAMPER_ROOT" \
    "$PUBLISHER" verify-snapshot "$snapshot_id" "$RPM_DB"

printf '\n===== TAMPERED MANIFEST SIGNATURE =====\n'
mkdir -p "$SIGNATURE_TAMPER_ROOT/snapshots"
cp -a "$snapshot" "$SIGNATURE_TAMPER_ROOT/snapshots/$snapshot_id"
chmod u+w "$SIGNATURE_TAMPER_ROOT/snapshots/$snapshot_id/2099.1/RELEASE-MANIFEST.asc"
printf 'tampered-signature\n' > "$SIGNATURE_TAMPER_ROOT/snapshots/$snapshot_id/2099.1/RELEASE-MANIFEST.asc"

expect_failure "Modified detached signature rejected" \
    env SORABBYNGO_PUBLICATION_ROOT="$SIGNATURE_TAMPER_ROOT" \
    "$PUBLISHER" verify-snapshot "$snapshot_id" "$RPM_DB"

printf '\n===== WRONG TRUSTED MANIFEST SIGNER =====\n'
expect_failure "Wrong trusted manifest fingerprint rejected" \
    env SORABBYNGO_PUBLICATION_ROOT="$VALID_ROOT" \
        SORABBYNGO_MANIFEST_TRUSTED_FINGERPRINT=0000000000000000000000000000000000000000 \
    "$PUBLISHER" verify-snapshot "$snapshot_id" "$RPM_DB"

printf '\n===== PROMOTE TO TESTING =====\n'
"$PUBLISHER" promote testing 2099.1 "$snapshot_id" "$RPM_DB"
pointer="$VALID_ROOT/testing/releases/2099.1"
[[ -L "$pointer" ]] || fail "Testing channel pointer was not created"
[[ "$(readlink -- "$pointer")" == "../../snapshots/$snapshot_id/2099.1" ]] ||
    fail "Testing channel pointer target is incorrect"
[[ "$(readlink -f -- "$pointer")" == "$snapshot/2099.1" ]] ||
    fail "Testing channel pointer does not resolve to the prepared snapshot"
pass "Testing channel points to the verified snapshot"

printf '\n===== STABLE CHANNEL ISOLATION =====\n'
[[ ! -e "$VALID_ROOT/stable/releases/2099.1" && ! -L "$VALID_ROOT/stable/releases/2099.1" ]] ||
    fail "Testing promotion unexpectedly changed stable"
pass "Stable channel remains untouched"

printf '\n===== PROMOTION JOURNAL =====\n'
history_output="$("$PUBLISHER" history)"
printf '%s\n' "$history_output"
grep -q $'^FORMAT_VERSION=2$' "$VALID_ROOT/history/promotions.tsv" ||
    fail "Promotion journal format header is missing"
grep -q $'\tPREPARE\ttesting\t2099.1\t-\t'"$snapshot_id"$'\tpromote$' "$VALID_ROOT/history/promotions.tsv" ||
    fail "Promotion PREPARE event is missing"
grep -q $'\tCOMMIT\ttesting\t2099.1\t-\t'"$snapshot_id"$'\tpromote$' "$VALID_ROOT/history/promotions.tsv" ||
    fail "Promotion COMMIT event is missing"
grep -q 'UNRESOLVED TRANSACTIONS' <<< "$history_output" ||
    fail "History output did not report transaction status"
grep -q 'None\.' <<< "$history_output" ||
    fail "Promotion journal contains unresolved transactions"
pass "Promotion journal has a matched PREPARE/COMMIT pair"

printf '\n===== PREPARE SECOND SNAPSHOT =====\n'
SECOND_REPO="$TEMP_ROOT/second-repo"
mkdir -p "$SECOND_REPO"
cp -a "$SOURCE_REPO/." "$SECOND_REPO/"
printf 'rollback regression snapshot\n' > "$SECOND_REPO/ROLLBACK-TEST-MARKER"

second_output="$(
    "$PUBLISHER" prepare 2099.1 "$RPM_DB" "x86_64=$SECOND_REPO"
)"
printf '%s\n' "$second_output"

second_snapshot_id="$(
    awk '/^Snapshot ID:/ {print $3}' <<< "$second_output"
)"
[[ "$second_snapshot_id" =~ ^[a-f0-9]{64}$ ]] ||
    fail "Could not extract the second snapshot ID"
[[ "$second_snapshot_id" != "$snapshot_id" ]] ||
    fail "Second snapshot unexpectedly has the same ID"
pass "Distinct second signed snapshot prepared"

printf '\n===== PROMOTE SECOND SNAPSHOT =====\n'
"$PUBLISHER" promote testing 2099.1 "$second_snapshot_id" "$RPM_DB"
[[ "$(readlink -- "$pointer")" == "../../snapshots/$second_snapshot_id/2099.1" ]] ||
    fail "Testing pointer did not switch to the second snapshot"
[[ "$(readlink -f -- "$pointer")" == "$VALID_ROOT/snapshots/$second_snapshot_id/2099.1" ]] ||
    fail "Testing pointer does not resolve to the second snapshot"
pass "Second snapshot promoted to testing"

printf '\n===== ROLLBACK TO FIRST SNAPSHOT =====\n'
"$PUBLISHER" rollback testing 2099.1 "$snapshot_id" "$RPM_DB"
[[ "$(readlink -- "$pointer")" == "../../snapshots/$snapshot_id/2099.1" ]] ||
    fail "Rollback did not restore the first snapshot pointer"
[[ "$(readlink -f -- "$pointer")" == "$snapshot/2099.1" ]] ||
    fail "Rollback pointer does not resolve to the first snapshot"
pass "Rollback restored the original testing snapshot"

printf '\n===== ROLLBACK JOURNAL =====\n'
history_output="$("$PUBLISHER" history)"
printf '%s\n' "$history_output"

grep -q $'\tPREPARE\ttesting\t2099.1\t'"$second_snapshot_id"$'\t'"$snapshot_id"$'\trollback$' \
    "$VALID_ROOT/history/promotions.tsv" ||
    fail "Rollback PREPARE event is missing"

grep -q $'\tCOMMIT\ttesting\t2099.1\t'"$second_snapshot_id"$'\t'"$snapshot_id"$'\trollback$' \
    "$VALID_ROOT/history/promotions.tsv" ||
    fail "Rollback COMMIT event is missing"

grep -q 'None\.' <<< "$history_output" ||
    fail "Rollback left unresolved publication transactions"

[[ ! -e "$VALID_ROOT/stable/releases/2099.1" && ! -L "$VALID_ROOT/stable/releases/2099.1" ]] ||
    fail "Rollback unexpectedly changed stable"

pass "Rollback journal is consistent and stable remains untouched"

append_recovery_prepare() {
    local previous="$1"
    local intended="$2"
    local action="$3"
    printf '%s\tPREPARE\ttesting\t2099.1\t%s\t%s\t%s\n' \
        "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
        "$previous" "$intended" "$action" \
        >> "$VALID_ROOT/history/promotions.tsv"
}

printf '\n===== RECOVERY: ABORT BEFORE POINTER SWITCH =====\n'
append_recovery_prepare "$snapshot_id" "$second_snapshot_id" promote
"$PUBLISHER" recover "$RPM_DB"
[[ "$(readlink -- "$pointer")" == "../../snapshots/$snapshot_id/2099.1" ]] ||
    fail "Recovery changed the previous pointer while aborting"
grep -q $'\tABORT\ttesting\t2099.1\t'"$snapshot_id"$'\t'"$second_snapshot_id"$'\tpromote$' \
    "$VALID_ROOT/history/promotions.tsv" ||
    fail "Recovery did not append the expected ABORT event"
pass "Unswitched transaction safely finalized as ABORT"

printf '\n===== RECOVERY: COMMIT AFTER POINTER SWITCH =====\n'
append_recovery_prepare "$snapshot_id" "$second_snapshot_id" promote
recovery_link="$VALID_ROOT/testing/releases/.recovery-link"
ln -s "../../snapshots/$second_snapshot_id/2099.1" "$recovery_link"
mv -Tf -- "$recovery_link" "$pointer"

"$PUBLISHER" recover "$RPM_DB"
[[ "$(readlink -- "$pointer")" == "../../snapshots/$second_snapshot_id/2099.1" ]] ||
    fail "Recovery changed the already-switched pointer"
grep -q $'\tCOMMIT\ttesting\t2099.1\t'"$snapshot_id"$'\t'"$second_snapshot_id"$'\tpromote$' \
    "$VALID_ROOT/history/promotions.tsv" ||
    fail "Recovery did not append the expected COMMIT event"
pass "Switched transaction safely finalized as COMMIT"

printf '\n===== RECOVERY: AMBIGUOUS POINTER FAILS SAFELY =====\n'
append_recovery_prepare "$second_snapshot_id" "$snapshot_id" rollback
rm -- "$pointer"
printf 'unexpected-pointer-state\n' > "$pointer"

expect_failure "Recovery rejects a non-symlink channel pointer" \
    "$PUBLISHER" recover "$RPM_DB"

[[ -f "$pointer" && ! -L "$pointer" ]] ||
    fail "Recovery modified the unexpected channel pointer"
[[ "$(cat -- "$pointer")" == "unexpected-pointer-state" ]] ||
    fail "Recovery changed the unexpected pointer contents"
grep -q $'\tPREPARE\ttesting\t2099.1\t'"$second_snapshot_id"$'\t'"$snapshot_id"$'\trollback$' \
    "$VALID_ROOT/history/promotions.tsv" ||
    fail "Ambiguous transaction was unexpectedly removed from the journal"
pass "Ambiguous transaction remains pending and pointer is untouched"

printf '\n===== SUMMARY =====\n'
printf 'All publication regression tests passed.\n'
