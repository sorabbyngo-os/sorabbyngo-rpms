#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
BUILD_ROOT="$ROOT/build"
VERIFIER="$ROOT/scripts/repository.sh"
DEFAULT_PUBLICATION_ROOT="$BUILD_ROOT/publication"
TRUSTED_RPM_FINGERPRINT="${SORABBYNGO_RPM_FINGERPRINT:-3B98F632BDC26FC933EE2D653A974697E5E940F2}"
MANIFEST_SIGNING_HOME="${SORABBYNGO_MANIFEST_SIGNING_HOME:-$HOME/.local/share/sorabbyngo-signing/release}"
MANIFEST_SIGNING_FINGERPRINT="${SORABBYNGO_MANIFEST_SIGNING_FINGERPRINT:-F6A4554DD4DCF09AA7F79B12C7F3EFB04D5058A7}"
MANIFEST_VERIFY_KEY="${SORABBYNGO_MANIFEST_VERIFY_KEY:-$ROOT/config-package/keys/RPM-GPG-KEY-sorabbyngo.asc}"
TRUSTED_MANIFEST_FINGERPRINT="${SORABBYNGO_MANIFEST_TRUSTED_FINGERPRINT:-F6A4554DD4DCF09AA7F79B12C7F3EFB04D5058A7}"

STAGING_DIR=""
PROMOTION_TMP_DIR=""

cleanup_temporary_directories() {
    local directory resolved
    for directory in "$STAGING_DIR" "$PROMOTION_TMP_DIR"; do
        [[ -n "$directory" ]] || continue
        [[ -d "$directory" && ! -L "$directory" ]] || continue

        resolved="$(cd -- "$directory" && pwd -P)" || continue
        case "$resolved" in
            "$BUILD_ROOT"/*/snapshots/.staging.*|\
            "$BUILD_ROOT"/*/*/releases/.promotion.*|\
            "$BUILD_ROOT"/*/*/releases/.rollback.*)
                chmod -R u+rwX -- "$resolved" 2>/dev/null || true
                rm -rf -- "$resolved"
                ;;
            *)
                printf 'WARNING: refusing cleanup of unexpected temporary path: %s\n' "$resolved" >&2
                ;;
        esac
    done
}
trap cleanup_temporary_directories EXIT

usage() {
    cat <<'USAGE'
Usage:
  scripts/publication.sh prepare <release-version> <rpm-db-path> <arch=repository-dir>...
  scripts/publication.sh verify-snapshot <snapshot-id> <rpm-db-path>
  scripts/publication.sh promote <testing|stable> <release> <snapshot-id> <rpm-db-path>
  scripts/publication.sh rollback <testing|stable> <release> <target-snapshot-id> <rpm-db-path>
  scripts/publication.sh recover <rpm-db-path>
  scripts/publication.sh history
  scripts/publication.sh status

Example:
  scripts/publication.sh prepare 2026.1 /var/tmp/sorabbyngo-rpm-verify \
      x86_64=build/release-x86_64

Environment:
  SORABBYNGO_PUBLICATION_ROOT  Local publication storage inside build/.
  SORABBYNGO_RPM_FINGERPRINT   Trusted RPM signing-key fingerprint.
  SORABBYNGO_MANIFEST_SIGNING_HOME       GPG home used to sign release manifests.
  SORABBYNGO_MANIFEST_SIGNING_FINGERPRINT Signing subkey used for manifest signatures.
  SORABBYNGO_MANIFEST_VERIFY_KEY          Public key used to verify manifest signatures.
  SORABBYNGO_MANIFEST_TRUSTED_FINGERPRINT Required manifest signing-subkey fingerprint.

Preparation validates staged repositories and creates an immutable,
content-addressed snapshot. It does not promote or publish a release.
USAGE
}

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

valid_release() {
    [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]{0,63}$ ]] &&
        [[ "$1" != "." && "$1" != ".." ]]
}

valid_arch() {
    [[ "$1" =~ ^[A-Za-z0-9_][A-Za-z0-9_.+-]{0,31}$ ]]
}

require_tools() {
    local tool
    for tool in bash sha256sum rpm rpmkeys flock install find sort awk python3 \
                cp chmod mv mktemp date xargs sed gpg; do
        command -v "$tool" >/dev/null 2>&1 ||
            fail "Required command not found: $tool"
    done

    [[ -x "$VERIFIER" ]] || fail "Repository verifier is missing or not executable"
}

verify_manifest_signature() {
    local manifest="$1"
    local signature="$2"
    local temp_dir gpg_home status signer
    local -a signers=()

    [[ -s "$manifest" && ! -L "$manifest" ]] ||
        fail "Missing or unsafe release manifest: $manifest"
    [[ -s "$signature" && ! -L "$signature" ]] ||
        fail "Missing or unsafe release manifest signature: $signature"
    [[ -s "$MANIFEST_VERIFY_KEY" ]] ||
        fail "Manifest verification public key not found: $MANIFEST_VERIFY_KEY"
    [[ "$TRUSTED_MANIFEST_FINGERPRINT" =~ ^[A-Fa-f0-9]{40,64}$ ]] ||
        fail "Invalid trusted manifest signing fingerprint"

    temp_dir="$(mktemp -d "$BUILD_ROOT/manifest-verify.XXXXXXXX")"
    gpg_home="$temp_dir/gnupg"
    install -d -m 0700 "$gpg_home"

    if ! gpg --homedir "$gpg_home" --batch --import "$MANIFEST_VERIFY_KEY" >/dev/null 2>&1; then
        rm -rf -- "$temp_dir"
        fail "Could not import manifest verification public key"
    fi

    if ! status="$(gpg --homedir "$gpg_home" --batch --status-fd 1 \
        --verify "$signature" "$manifest" 2>/dev/null)"; then
        rm -rf -- "$temp_dir"
        fail "Release manifest signature verification failed"
    fi

    mapfile -t signers < <(
        awk '$1 == "[GNUPG:]" && $2 == "VALIDSIG" { print toupper($3) }' <<< "$status"
    )
    rm -rf -- "$temp_dir"

    ((${#signers[@]} == 1)) ||
        fail "Expected exactly one valid manifest signature, found ${#signers[@]}"

    signer="${signers[0]}"
    [[ "$signer" == "${TRUSTED_MANIFEST_FINGERPRINT^^}" ]] ||
        fail "Manifest signer fingerprint mismatch: expected $TRUSTED_MANIFEST_FINGERPRINT, got ${signer:-none}"

    printf 'Manifest signature: VALID (%s)\n' "$signer"
}

input_repository() {
    local requested="$1"
    local resolved

    [[ -d "$requested" ]] || fail "Repository directory does not exist: $requested"
    resolved="$(cd -- "$requested" && pwd -P)"

    case "$resolved/" in
        "$BUILD_ROOT"/*/) ;;
        *) fail "Input repository must be inside $BUILD_ROOT/" ;;
    esac

    printf '%s\n' "$resolved"
}

reject_unsafe_tree() {
    local repo="$1"
    local unsafe

    unsafe="$(find "$repo" -type l -print -quit)"
    [[ -z "$unsafe" ]] ||
        fail "Repository contains a symbolic link: $unsafe"

    unsafe="$(find "$repo" ! -type d ! -type f -print -quit)"
    [[ -z "$unsafe" ]] ||
        fail "Repository contains a non-regular file: $unsafe"
}

repository_inventory() {
    local repo="$1"
    local target_arch="$2"
    local package package_arch source_rpm
    local count=0

    while IFS= read -r -d '' package; do
        package_arch="$(rpm -qp --qf '%{ARCH}' "$package")" ||
            fail "Cannot read RPM architecture: $package"

        source_rpm="$(rpm -qp --qf '%{SOURCERPM}' "$package")" ||
            fail "Cannot read RPM source identity: $package"

        [[ "$source_rpm" != "(none)" ]] ||
            fail "Source RPMs are not permitted in client repositories: $(basename -- "$package")"

        [[ "$package_arch" != "src" && "$package_arch" != "nosrc" ]] ||
            fail "Source RPM architecture is not permitted: $(basename -- "$package")"

        [[ "$package_arch" == "noarch" || "$package_arch" == "$target_arch" ]] ||
            fail "Package architecture $package_arch does not match target $target_arch: $(basename -- "$package")"

        ((count += 1))
    done < <(find "$repo" -maxdepth 1 -type f -name '*.rpm' -print0)

    ((count > 0)) || fail "No binary RPM packages found in $repo"
}

hash_tree() {
    local directory="$1"
    (
        cd -- "$directory"
        find . -type f -printf '%P\0' |
            sort -z |
            while IFS= read -r -d '' file; do
                sha256sum -- "$file"
            done
    )
}

prepare() {
    (($# >= 3)) || {
        usage
        fail "prepare requires a release, RPM database, and at least one architecture repository"
    }

    local release="$1"
    local rpm_db_requested="$2"
    shift 2

    valid_release "$release" || fail "Invalid release version: $release"
    [[ -d "$rpm_db_requested" ]] ||
        fail "RPM database does not exist: $rpm_db_requested"

    local rpm_db
    rpm_db="$(cd -- "$rpm_db_requested" && pwd -P)"

    local publication_root="${SORABBYNGO_PUBLICATION_ROOT:-$DEFAULT_PUBLICATION_ROOT}"
    install -d -m 0755 "$publication_root"
    publication_root="$(cd -- "$publication_root" && pwd -P)"

    case "$publication_root/" in
        "$BUILD_ROOT"/*/) ;;
        *) fail "Publication root must be inside $BUILD_ROOT/" ;;
    esac

    local snapshots="$publication_root/snapshots"
    install -d -m 0755 "$snapshots"

    local lock_fd
    exec {lock_fd}>"$publication_root/.publication.lock"
    flock -x "$lock_fd"

    STAGING_DIR="$(mktemp -d "$snapshots/.staging.XXXXXXXX")"
    local staging="$STAGING_DIR"

    local -a architectures=()
    local -a source_repositories=()
    local -A seen_architectures=()

    local mapping arch requested_repo repo
    for mapping in "$@"; do
        [[ "$mapping" == *=* ]] ||
            fail "Expected architecture=repository mapping: $mapping"

        arch="${mapping%%=*}"
        requested_repo="${mapping#*=}"

        valid_arch "$arch" || fail "Invalid target architecture: $arch"
        [[ -n "$requested_repo" ]] || fail "Repository path is empty for $arch"
        [[ -z "${seen_architectures[$arch]:-}" ]] ||
            fail "Duplicate target architecture: $arch"

        repo="$(input_repository "$requested_repo")"
        reject_unsafe_tree "$repo"

        seen_architectures["$arch"]=1
        architectures+=("$arch")
        source_repositories+=("$repo")
    done

    install -d -m 0755 "$staging/$release"

    local index=0
    for arch in "${architectures[@]}"; do
        repo="${source_repositories[$index]}"
        local destination="$staging/$release/$arch"

        printf '\n===== STAGING %s =====\n' "$arch"
        install -d -m 0755 "$destination"
        cp -a -- "$repo/." "$destination/"

        reject_unsafe_tree "$destination"

        printf '\n===== VERIFYING STAGED %s =====\n' "$arch"
        "$VERIFIER" verify "$destination"
        "$VERIFIER" rpm-verify "$destination" "$rpm_db"
        repository_inventory "$destination" "$arch"

        ((index += 1))
    done

    local manifest="$staging/$release/RELEASE-MANIFEST"
    {
        printf 'FORMAT_VERSION=1\n'
        printf 'DISTRIBUTION_ID=sorabbyngo\n'
        printf 'RELEASE_VERSION=%s\n' "$release"
        printf 'TRUSTED_RPM_FINGERPRINT=%s\n' "$TRUSTED_RPM_FINGERPRINT"
        printf 'ARCHITECTURES=%s\n' "$(IFS=,; printf '%s' "${architectures[*]}")"

        for arch in "${architectures[@]}"; do
            printf '\n[ARCHITECTURE %s]\n' "$arch"
            hash_tree "$staging/$release/$arch"
        done
    } > "$manifest"

    [[ -d "$MANIFEST_SIGNING_HOME" ]] ||
        fail "Manifest signing GPG home not found: $MANIFEST_SIGNING_HOME"
    gpg --homedir "$MANIFEST_SIGNING_HOME" --batch \
        --local-user "$MANIFEST_SIGNING_FINGERPRINT" \
        --armor --detach-sign \
        --output "$manifest.asc" \
        "$manifest"
    verify_manifest_signature "$manifest" "$manifest.asc"

    local snapshot_id
    snapshot_id="$(sha256sum "$manifest" | awk '{print $1}')"

    local final="$snapshots/$snapshot_id"
    [[ ! -e "$final" && ! -L "$final" ]] ||
        fail "Snapshot already exists; refusing to overwrite: $snapshot_id"

    chmod 0444 "$manifest"
    find "$staging" -type f -exec chmod 0444 {} +
    find "$staging" -type d -exec chmod 0555 {} +

    # One same-filesystem rename publishes the complete snapshot directory.
    mv -T -- "$staging" "$final"
    STAGING_DIR=""

    printf '\n[PASS] Immutable snapshot prepared\n'
    printf 'Snapshot ID:  %s\n' "$snapshot_id"
    printf 'Release:      %s\n' "$release"
    printf 'Architectures: %s\n' "$(IFS=,; printf '%s' "${architectures[*]}")"
    printf 'Location:     %s/%s\n' "$final" "$release"
    printf '\nThis snapshot has not been promoted to testing or stable.\n'
}


verify_snapshot() {
    (($# == 2 || $# == 3)) ||
        fail "verify-snapshot expects a snapshot ID, RPM database path, and optional internal lock mode"

    local snapshot_id="$1"
    local rpm_db_requested="$2"

    [[ "$snapshot_id" =~ ^[a-f0-9]{64}$ ]] ||
        fail "Snapshot ID must be a 64-character lowercase SHA-256 digest"
    [[ -d "$rpm_db_requested" ]] ||
        fail "RPM database does not exist: $rpm_db_requested"

    local rpm_db
    rpm_db="$(cd -- "$rpm_db_requested" && pwd -P)"

    local publication_root="${SORABBYNGO_PUBLICATION_ROOT:-$DEFAULT_PUBLICATION_ROOT}"
    [[ -d "$publication_root" ]] ||
        fail "Publication root does not exist: $publication_root"
    publication_root="$(cd -- "$publication_root" && pwd -P)"

    case "$publication_root/" in
        "$BUILD_ROOT"/*/) ;;
        *) fail "Publication root must be inside $BUILD_ROOT/" ;;
    esac

    local snapshot="$publication_root/snapshots/$snapshot_id"
    [[ -d "$snapshot" && ! -L "$snapshot" ]] ||
        fail "Snapshot directory does not exist or is a symlink: $snapshot"

    local lock_mode="${3:-shared}"
    local lock_fd
    if [[ "$lock_mode" == "shared" ]]; then
        exec {lock_fd}>"$publication_root/.publication.lock"
        flock -s "$lock_fd"
    elif [[ "$lock_mode" != "locked" ]]; then
        fail "Invalid internal snapshot lock mode"
    fi

    local manifest_path signature_path
    manifest_path="$(find "$snapshot" -mindepth 2 -maxdepth 2 -type f -name RELEASE-MANIFEST -print -quit)"
    [[ -n "$manifest_path" ]] || fail "Snapshot release manifest is missing"
    signature_path="$manifest_path.asc"

    printf '\n===== VERIFYING RELEASE MANIFEST SIGNATURE =====\n'
    verify_manifest_signature "$manifest_path" "$signature_path"

    printf '\n===== SNAPSHOT CONTENT INTEGRITY =====\n'
    python3 - "$snapshot" "$snapshot_id" <<'PYVERIFY'
import hashlib
import re
import sys
from pathlib import Path, PurePosixPath

root = Path(sys.argv[1])
snapshot_id = sys.argv[2]
# The release directory is discovered from the manifest's own parent
# after requiring exactly one release directory.
release_dirs = [
    p for p in root.iterdir()
    if p.is_dir() and not p.is_symlink()
]
if len(release_dirs) != 1:
    raise SystemExit("ERROR: Snapshot must contain exactly one release directory")

release_dir = release_dirs[0]
manifest = release_dir / "RELEASE-MANIFEST"
if not manifest.is_file() or manifest.is_symlink():
    raise SystemExit("ERROR: Missing or unsafe RELEASE-MANIFEST")

actual_id = hashlib.sha256(manifest.read_bytes()).hexdigest()
if actual_id != snapshot_id:
    raise SystemExit(
        f"ERROR: Manifest digest mismatch: expected {snapshot_id}, got {actual_id}"
    )

lines = manifest.read_text(encoding="utf-8").splitlines()
headers = {}
architectures = []
records = {}
current_arch = None
in_files = False

for line in lines:
    if not line:
        continue
    if line.startswith("[ARCHITECTURE ") and line.endswith("]"):
        current_arch = line[len("[ARCHITECTURE "):-1]
        if not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.+-]{0,31}", current_arch):
            raise SystemExit(f"ERROR: Invalid architecture section: {current_arch}")
        if current_arch in records:
            raise SystemExit(f"ERROR: Duplicate architecture section: {current_arch}")
        architectures.append(current_arch)
        records[current_arch] = {}
        in_files = True
        continue

    if in_files:
        match = re.fullmatch(r"([a-f0-9]{64})  (.+)", line)
        if not match:
            raise SystemExit(f"ERROR: Invalid manifest file record: {line!r}")
        digest, relative = match.groups()
        rel = PurePosixPath(relative)
        if rel.is_absolute() or ".." in rel.parts or "." in rel.parts:
            raise SystemExit(f"ERROR: Unsafe manifest path: {relative}")
        if relative in records[current_arch]:
            raise SystemExit(f"ERROR: Duplicate manifest path: {relative}")
        records[current_arch][relative] = digest
    else:
        if "=" not in line:
            raise SystemExit(f"ERROR: Invalid manifest header: {line!r}")
        key, value = line.split("=", 1)
        if key in headers:
            raise SystemExit(f"ERROR: Duplicate manifest field: {key}")
        headers[key] = value

if headers.get("FORMAT_VERSION") != "1":
    raise SystemExit("ERROR: Unsupported manifest format")
if headers.get("DISTRIBUTION_ID") != "sorabbyngo":
    raise SystemExit("ERROR: Unexpected distribution ID")
if headers.get("RELEASE_VERSION") != release_dir.name:
    raise SystemExit("ERROR: Release directory does not match manifest")
if not re.fullmatch(r"[A-Fa-f0-9]{40,64}", headers.get("TRUSTED_RPM_FINGERPRINT", "")):
    raise SystemExit("ERROR: Invalid trusted RPM fingerprint")

declared = headers.get("ARCHITECTURES", "").split(",")
if not declared or declared != architectures or len(set(declared)) != len(declared):
    raise SystemExit("ERROR: Architecture declaration does not match manifest sections")

expected_top = {"RELEASE-MANIFEST", "RELEASE-MANIFEST.asc", *declared}
actual_top = {p.name for p in release_dir.iterdir()}
if actual_top != expected_top:
    raise SystemExit("ERROR: Unexpected or missing release-level entries")

for arch in declared:
    repo = release_dir / arch
    if not repo.is_dir() or repo.is_symlink():
        raise SystemExit(f"ERROR: Missing or unsafe architecture directory: {arch}")

    expected_files = records[arch]
    actual_files = set()

    for path in repo.rglob("*"):
        if path.is_symlink():
            raise SystemExit(f"ERROR: Symlink found in snapshot: {path}")
        if path.is_file():
            actual_files.add(path.relative_to(repo).as_posix())
        elif not path.is_dir():
            raise SystemExit(f"ERROR: Non-regular entry found: {path}")

    if actual_files != set(expected_files):
        missing = sorted(set(expected_files) - actual_files)
        extra = sorted(actual_files - set(expected_files))
        raise SystemExit(f"ERROR: File inventory mismatch in {arch}; missing={missing}, extra={extra}")

    for relative, expected_digest in expected_files.items():
        file_path = repo / relative
        actual_digest = hashlib.sha256(file_path.read_bytes()).hexdigest()
        if actual_digest != expected_digest:
            raise SystemExit(f"ERROR: SHA-256 mismatch: {arch}/{relative}")

print(f"Manifest SHA-256: VALID ({snapshot_id})")
print(f"Release: {release_dir.name}")
print(f"Architectures: {', '.join(declared)}")
print("File inventory and checksums: VALID")
PYVERIFY

    local release_dir
    release_dir="$(find "$snapshot" -mindepth 1 -maxdepth 1 -type d -print -quit)"
    [[ -n "$release_dir" ]] || fail "Snapshot release directory is missing"

    local arch
    for arch in "$release_dir"/*; do
        [[ -d "$arch" ]] || continue
        arch="${arch##*/}"

        printf '\n===== VERIFYING SNAPSHOT ARCHITECTURE %s =====\n' "$arch"
        "$VERIFIER" verify "$release_dir/$arch"
        "$VERIFIER" rpm-verify "$release_dir/$arch" "$rpm_db"
        repository_inventory "$release_dir/$arch" "$arch"
    done

    printf '\n[PASS] Snapshot integrity and cryptographic verification passed.\n'
}


publication_root() {
    local root="${SORABBYNGO_PUBLICATION_ROOT:-$DEFAULT_PUBLICATION_ROOT}"
    [[ -d "$root" ]] || fail "Publication root does not exist: $root"
    root="$(cd -- "$root" && pwd -P)"
    case "$root/" in
        "$BUILD_ROOT"/*/) ;;
        *) fail "Publication root must be inside $BUILD_ROOT/" ;;
    esac
    printf '%s\n' "$root"
}


history_file() {
    local root="$1"
    printf '%s\n' "$root/history/promotions.tsv"
}

initialize_history() {
    local root="$1"
    local file
    file="$(history_file "$root")"

    if [[ ! -d "$root/history" ]]; then
        install -d -m 0755 "$root/history"
        sync -f "$root" ||
            fail "Could not flush publication root after creating history directory"
    fi
    [[ ! -L "$root/history" ]] ||
        fail "Promotion history directory must not be a symbolic link"
    [[ ! -L "$file" ]] ||
        fail "Promotion history must not be a symbolic link: $file"

    if [[ ! -e "$file" ]]; then
        (umask 022; set -o noclobber; printf 'FORMAT_VERSION=2\n' > "$file") ||
            fail "Could not safely initialize promotion history: $file"
        sync -f "$file" ||
            fail "Could not flush newly initialized promotion history: $file"
        sync -f "$root/history" ||
            fail "Could not flush history directory after journal creation"
    fi

    [[ -f "$file" ]] ||
        fail "Promotion history is not a regular file: $file"

    python3 - "$file" <<'PYHISTORY'
import re
import sys
from datetime import datetime

with open(sys.argv[1], "r", encoding="utf-8") as stream:
    lines = stream.read().splitlines()

if not lines or lines[0] != "FORMAT_VERSION=2":
    raise SystemExit("ERROR: Unsupported promotion history format")

pending = {}
for number, line in enumerate(lines[1:], start=2):
    fields = line.split("\t")
    if len(fields) != 7:
        raise SystemExit(f"ERROR: Invalid history record at line {number}")

    timestamp, phase, channel, release, previous, new, action = fields

    try:
        parsed = datetime.fromisoformat(timestamp.replace("Z", "+00:00"))
    except ValueError:
        raise SystemExit(f"ERROR: Invalid timestamp at history line {number}")
    if parsed.tzinfo is None or not timestamp.endswith("Z"):
        raise SystemExit(f"ERROR: Timestamp is not UTC at history line {number}")

    if phase not in {"PREPARE", "COMMIT", "ABORT"}:
        raise SystemExit(f"ERROR: Invalid event phase at history line {number}")
    if channel not in {"testing", "stable"}:
        raise SystemExit(f"ERROR: Invalid channel at history line {number}")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._+-]{0,63}", release):
        raise SystemExit(f"ERROR: Invalid release at history line {number}")
    if previous != "-" and not re.fullmatch(r"[a-f0-9]{64}", previous):
        raise SystemExit(f"ERROR: Invalid previous snapshot at history line {number}")
    if not re.fullmatch(r"[a-f0-9]{64}", new):
        raise SystemExit(f"ERROR: Invalid new snapshot at history line {number}")
    if action not in {"promote", "rollback"}:
        raise SystemExit(f"ERROR: Invalid action at history line {number}")

    key = (channel, release, previous, new, action)
    if phase == "PREPARE":
        if key in pending:
            raise SystemExit(f"ERROR: Duplicate pending history event at line {number}")
        pending[key] = number
    elif key not in pending:
        raise SystemExit(f"ERROR: Terminal event without matching PREPARE at line {number}")
    else:
        del pending[key]
PYHISTORY
}


assert_no_pending_history() {
    local root="$1"
    local file
    initialize_history "$root"
    file="$(history_file "$root")"

    python3 - "$file" <<'PYPENDING'
import sys

pending = set()
with open(sys.argv[1], "r", encoding="utf-8") as stream:
    next(stream)
    for line in stream:
        fields = line.rstrip("\n").split("\t")
        if len(fields) != 7:
            raise SystemExit("ERROR: Invalid promotion history record")
        _, phase, channel, release, previous, new, action = fields
        key = (channel, release, previous, new, action)
        if phase == "PREPARE":
            pending.add(key)
        elif phase in {"COMMIT", "ABORT"}:
            pending.discard(key)

if pending:
    raise SystemExit(
        "ERROR: An earlier publication transaction is unresolved; "
        "inspect promotion history and channel pointers before proceeding"
    )
PYPENDING
}

append_history_event() {
    local root="$1"
    local phase="$2"
    local channel="$3"
    local release="$4"
    local previous="$5"
    local new="$6"
    local action="$7"
    local file timestamp

    [[ "$phase" == "PREPARE" || "$phase" == "COMMIT" || "$phase" == "ABORT" ]] ||
        fail "Invalid history event phase: $phase"

    initialize_history "$root"
    file="$(history_file "$root")"
    timestamp="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$timestamp" "$phase" "$channel" "$release" \
        "$previous" "$new" "$action" >> "$file"
    sync -f "$file" ||
        fail "Could not flush promotion history to storage: $file"
}

promote() {
    (($# == 4)) || fail "promote expects: <testing|stable> <release> <snapshot-id> <rpm-db-path>"

    local channel="$1"
    local release="$2"
    local snapshot_id="$3"
    local rpm_db="$4"

    [[ "$channel" == "testing" || "$channel" == "stable" ]] ||
        fail "Channel must be testing or stable"
    valid_release "$release" || fail "Invalid release version: $release"
    [[ "$snapshot_id" =~ ^[a-f0-9]{64}$ ]] ||
        fail "Snapshot ID must be a 64-character lowercase SHA-256 digest"
    [[ -d "$rpm_db" ]] || fail "RPM database does not exist: $rpm_db"
    rpm_db="$(cd -- "$rpm_db" && pwd -P)"

    local root
    root="$(publication_root)"
    local lock_fd
    exec {lock_fd}>"$root/.publication.lock"
    flock -x "$lock_fd"

    printf '\n===== VERIFYING BEFORE PROMOTION =====\n'
    verify_snapshot "$snapshot_id" "$rpm_db" locked

    local snapshot="$root/snapshots/$snapshot_id"
    local release_dir="$snapshot/$release"
    [[ -d "$release_dir" && ! -L "$release_dir" ]] ||
        fail "Snapshot does not contain requested release: $release"
    [[ -f "$release_dir/RELEASE-MANIFEST" ]] ||
        fail "Snapshot release manifest is missing"

    local manifest_release
    manifest_release="$(sed -n 's/^RELEASE_VERSION=//p' "$release_dir/RELEASE-MANIFEST")"
    [[ "$manifest_release" == "$release" ]] ||
        fail "Requested release does not match snapshot manifest"

    local releases="$root/$channel/releases"
    install -d -m 0755 "$releases"

    local pointer="$releases/$release"
    local target="../../snapshots/$snapshot_id/$release"
    local previous_snapshot="-"

    assert_no_pending_history "$root"

    if [[ -L "$pointer" ]]; then
        local previous_target
        previous_target="$(readlink -- "$pointer")"

        [[ "$previous_target" =~ ^\.\./\.\./snapshots/([a-f0-9]{64})/([^/]+)$ ]] ||
            fail "Existing channel pointer has an unexpected target: $pointer"

        previous_snapshot="${BASH_REMATCH[1]}"
        [[ "${BASH_REMATCH[2]}" == "$release" ]] ||
            fail "Existing channel pointer targets a different release"

        [[ -d "$root/snapshots/$previous_snapshot/$release" &&
           ! -L "$root/snapshots/$previous_snapshot/$release" ]] ||
            fail "Existing channel pointer does not resolve to a valid snapshot"
    elif [[ -e "$pointer" ]]; then
        fail "Existing channel pointer is not a symbolic link: $pointer"
    fi

    append_history_event "$root" PREPARE "$channel" "$release" \
        "$previous_snapshot" "$snapshot_id" promote

    PROMOTION_TMP_DIR="$(mktemp -d "$releases/.promotion.XXXXXXXX")"
    ln -s -- "$target" "$PROMOTION_TMP_DIR/$release"

    # Atomic replacement: clients see either the old pointer or the new one.
    mv -Tf -- "$PROMOTION_TMP_DIR/$release" "$pointer"
    rmdir -- "$PROMOTION_TMP_DIR"
    PROMOTION_TMP_DIR=""
    sync -f "$releases" ||
        fail "Could not flush channel directory after promotion"

    append_history_event "$root" COMMIT "$channel" "$release" \
        "$previous_snapshot" "$snapshot_id" promote

    printf '\n[PASS] Release promoted to %s\n' "$channel"
    printf 'Release:    %s\n' "$release"
    printf 'Snapshot:   %s\n' "$snapshot_id"
    printf 'Pointer:    %s\n' "$pointer"
    printf 'Target:     %s\n' "$target"
}



rollback() {
    (($# == 4)) || fail "rollback expects: <testing|stable> <release> <target-snapshot-id> <rpm-db-path>"

    local channel="$1"
    local release="$2"
    local target_snapshot="$3"
    local rpm_db="$4"

    [[ "$channel" == "testing" || "$channel" == "stable" ]] ||
        fail "Channel must be testing or stable"
    valid_release "$release" || fail "Invalid release version: $release"
    [[ "$target_snapshot" =~ ^[a-f0-9]{64}$ ]] ||
        fail "Target snapshot ID must be a 64-character lowercase SHA-256 digest"
    [[ -d "$rpm_db" ]] || fail "RPM database does not exist: $rpm_db"
    rpm_db="$(cd -- "$rpm_db" && pwd -P)"

    local root
    root="$(publication_root)"

    local lock_fd
    exec {lock_fd}>"$root/.publication.lock"
    flock -x "$lock_fd"

    assert_no_pending_history "$root"

    local history
    history="$(history_file "$root")"

    python3 - "$history" "$channel" "$release" "$target_snapshot" <<'PYTARGET'
import sys

path, wanted_channel, wanted_release, wanted_snapshot = sys.argv[1:]
found = False

with open(path, "r", encoding="utf-8") as stream:
    next(stream)
    for line in stream:
        fields = line.rstrip("\n").split("\t")
        if len(fields) != 7:
            raise SystemExit("ERROR: Invalid promotion history record")
        _, phase, channel, release, previous, new, action = fields
        if (
            phase == "COMMIT"
            and channel == wanted_channel
            and release == wanted_release
            and new == wanted_snapshot
        ):
            found = True

if not found:
    raise SystemExit(
        "ERROR: Rollback target was never committed to this channel and release"
    )
PYTARGET

    local releases="$root/$channel/releases"
    local pointer="$releases/$release"
    [[ -L "$pointer" ]] ||
        fail "No promoted release pointer exists for $channel/$release"

    local current_target current_snapshot
    current_target="$(readlink -- "$pointer")"
    [[ "$current_target" =~ ^\.\./\.\./snapshots/([a-f0-9]{64})/([^/]+)$ ]] ||
        fail "Current channel pointer has an unexpected target: $pointer"

    current_snapshot="${BASH_REMATCH[1]}"
    [[ "${BASH_REMATCH[2]}" == "$release" ]] ||
        fail "Current channel pointer targets a different release"
    [[ -d "$root/snapshots/$current_snapshot/$release" &&
       ! -L "$root/snapshots/$current_snapshot/$release" ]] ||
        fail "Current channel pointer does not resolve to a valid snapshot"

    [[ "$current_snapshot" != "$target_snapshot" ]] ||
        fail "Requested rollback target is already active"

    printf '\n===== VERIFYING ROLLBACK TARGET =====\n'
    verify_snapshot "$target_snapshot" "$rpm_db" locked

    local target_release_dir="$root/snapshots/$target_snapshot/$release"
    [[ -d "$target_release_dir" && ! -L "$target_release_dir" ]] ||
        fail "Target snapshot does not contain requested release: $release"
    [[ -f "$target_release_dir/RELEASE-MANIFEST" ]] ||
        fail "Target snapshot release manifest is missing"

    local manifest_release
    manifest_release="$(sed -n 's/^RELEASE_VERSION=//p' "$target_release_dir/RELEASE-MANIFEST")"
    [[ "$manifest_release" == "$release" ]] ||
        fail "Rollback target manifest does not match requested release"

    local target="../../snapshots/$target_snapshot/$release"

    append_history_event "$root" PREPARE "$channel" "$release" \
        "$current_snapshot" "$target_snapshot" rollback

    PROMOTION_TMP_DIR="$(mktemp -d "$releases/.rollback.XXXXXXXX")"
    ln -s -- "$target" "$PROMOTION_TMP_DIR/$release"

    # Atomic replacement: clients see either the current or restored snapshot.
    mv -Tf -- "$PROMOTION_TMP_DIR/$release" "$pointer"
    sync -f "$releases"
    rmdir -- "$PROMOTION_TMP_DIR"
    PROMOTION_TMP_DIR=""

    append_history_event "$root" COMMIT "$channel" "$release" \
        "$current_snapshot" "$target_snapshot" rollback

    printf '\n[PASS] Release rolled back on %s\n' "$channel"
    printf 'Release:    %s\n' "$release"
    printf 'Previous:   %s\n' "$current_snapshot"
    printf 'Restored:   %s\n' "$target_snapshot"
    printf 'Pointer:    %s\n' "$pointer"
    printf 'Target:     %s\n' "$target"
}



recover() {
    (($# == 1)) || fail "recover expects: <rpm-db-path>"

    local rpm_db="$1"
    [[ -d "$rpm_db" ]] || fail "RPM database does not exist: $rpm_db"
    rpm_db="$(cd -- "$rpm_db" && pwd -P)"

    local root
    root="$(publication_root)"

    local lock_fd
    exec {lock_fd}>"$root/.publication.lock"
    flock -x "$lock_fd"

    initialize_history "$root"

    local file pending_record
    file="$(history_file "$root")"

    pending_record="$(
        python3 - "$file" <<'PYPENDINGRECOVERY'
import sys

pending = {}
with open(sys.argv[1], "r", encoding="utf-8") as stream:
    next(stream)
    for number, line in enumerate(stream, start=2):
        fields = line.rstrip("\n").split("\t")
        if len(fields) != 7:
            raise SystemExit(f"ERROR: Invalid history record at line {number}")
        _, phase, channel, release, previous, new, action = fields
        key = (channel, release, previous, new, action)
        if phase == "PREPARE":
            if key in pending:
                raise SystemExit("ERROR: Duplicate pending transaction")
            pending[key] = number
        else:
            if key not in pending:
                raise SystemExit("ERROR: Terminal event without PREPARE")
            del pending[key]

if len(pending) != 1:
    raise SystemExit(
        f"ERROR: Recovery requires exactly one unresolved transaction; found {len(pending)}"
    )

(channel, release, previous, new, action), _ = next(iter(pending.items()))
print("\t".join((channel, release, previous, new, action)))
PYPENDINGRECOVERY
    )" || fail "Could not identify a unique unresolved transaction"

    local channel release previous new action
    IFS=$'\t' read -r channel release previous new action <<< "$pending_record"

    printf '\n===== RECOVERING PUBLICATION TRANSACTION =====\n'
    printf 'Channel:  %s\nRelease:  %s\nPrevious: %s\nIntended: %s\nAction:   %s\n' \
        "$channel" "$release" "$previous" "$new" "$action"

    local pointer="$root/$channel/releases/$release"
    local actual="-"

    if [[ -L "$pointer" ]]; then
        local current_target
        current_target="$(readlink -- "$pointer")"

        [[ "$current_target" =~ ^\.\./\.\./snapshots/([a-f0-9]{64})/([^/]+)$ ]] ||
            fail "Channel pointer has an unexpected target; manual intervention required"

        actual="${BASH_REMATCH[1]}"
        [[ "${BASH_REMATCH[2]}" == "$release" ]] ||
            fail "Channel pointer targets a different release; manual intervention required"

        [[ -d "$root/snapshots/$actual/$release" &&
           ! -L "$root/snapshots/$actual/$release" ]] ||
            fail "Channel pointer does not resolve to a valid snapshot"
    elif [[ -e "$pointer" ]]; then
        fail "Channel pointer is not a symbolic link; manual intervention required"
    fi

    if [[ "$actual" == "$new" ]]; then
        printf '\nObserved pointer matches intended snapshot; verifying it.\n'
        verify_snapshot "$new" "$rpm_db" locked

        local release_dir="$root/snapshots/$new/$release"
        [[ -f "$release_dir/RELEASE-MANIFEST" ]] ||
            fail "Intended snapshot release manifest is missing"

        local manifest_release
        manifest_release="$(sed -n 's/^RELEASE_VERSION=//p' "$release_dir/RELEASE-MANIFEST")"
        [[ "$manifest_release" == "$release" ]] ||
            fail "Intended snapshot manifest release mismatch"

        append_history_event "$root" COMMIT "$channel" "$release" \
            "$previous" "$new" "$action"

        printf '\n[PASS] Interrupted transaction finalized as COMMIT.\n'
    elif [[ "$actual" == "$previous" ]]; then
        if [[ "$previous" != "-" ]]; then
            printf '\nObserved pointer matches previous snapshot; verifying it.\n'
            verify_snapshot "$previous" "$rpm_db" locked

            local release_dir="$root/snapshots/$previous/$release"
            [[ -f "$release_dir/RELEASE-MANIFEST" ]] ||
                fail "Previous snapshot release manifest is missing"

            local manifest_release
            manifest_release="$(sed -n 's/^RELEASE_VERSION=//p' "$release_dir/RELEASE-MANIFEST")"
            [[ "$manifest_release" == "$release" ]] ||
                fail "Previous snapshot manifest release mismatch"
        else
            printf '\nNo previous channel pointer existed; confirming it remains absent.\n'
        fi

        append_history_event "$root" ABORT "$channel" "$release" \
            "$previous" "$new" "$action"

        printf '\n[PASS] Interrupted transaction finalized as ABORT.\n'
    else
        fail "Channel pointer matches neither recorded snapshot; manual intervention required"
    fi

    printf 'Channel pointer was not modified by recovery.\n'
}

history() {
    (($# == 0)) || fail "history takes no arguments"

    local root file lock_fd
    root="$(publication_root)"
    file="$(history_file "$root")"

    [[ -d "$root/history" ]] ||
        fail "Promotion history directory does not exist"
    [[ -f "$file" && ! -L "$file" ]] ||
        fail "Promotion history is missing or is not a regular file"
    [[ -f "$root/.publication.lock" && ! -L "$root/.publication.lock" ]] ||
        fail "Publication lock file is missing or invalid"

    exec {lock_fd}>"$root/.publication.lock"
    flock -s "$lock_fd"

    python3 - "$file" <<'PYSHOW'
import re
import sys
from datetime import datetime

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as stream:
    lines = stream.read().splitlines()

if not lines or lines[0] != "FORMAT_VERSION=2":
    raise SystemExit("ERROR: Unsupported promotion history format")

pending = {}
records = []

for number, line in enumerate(lines[1:], start=2):
    fields = line.split("\t")
    if len(fields) != 7:
        raise SystemExit(f"ERROR: Invalid history record at line {number}")

    timestamp, phase, channel, release, previous, new, action = fields

    try:
        parsed = datetime.fromisoformat(timestamp.replace("Z", "+00:00"))
    except ValueError:
        raise SystemExit(f"ERROR: Invalid timestamp at history line {number}")
    if parsed.tzinfo is None or not timestamp.endswith("Z"):
        raise SystemExit(f"ERROR: Timestamp is not UTC at history line {number}")
    if phase not in {"PREPARE", "COMMIT", "ABORT"}:
        raise SystemExit(f"ERROR: Invalid phase at history line {number}")
    if channel not in {"testing", "stable"}:
        raise SystemExit(f"ERROR: Invalid channel at history line {number}")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._+-]{0,63}", release):
        raise SystemExit(f"ERROR: Invalid release at history line {number}")
    if previous != "-" and not re.fullmatch(r"[a-f0-9]{64}", previous):
        raise SystemExit(f"ERROR: Invalid previous snapshot at history line {number}")
    if not re.fullmatch(r"[a-f0-9]{64}", new):
        raise SystemExit(f"ERROR: Invalid new snapshot at history line {number}")
    if action not in {"promote", "rollback"}:
        raise SystemExit(f"ERROR: Invalid action at history line {number}")

    key = (channel, release, previous, new, action)
    if phase == "PREPARE":
        if key in pending:
            raise SystemExit(f"ERROR: Duplicate pending event at line {number}")
        pending[key] = number
    else:
        if key not in pending:
            raise SystemExit(f"ERROR: Terminal event without matching PREPARE at line {number}")
        del pending[key]

    records.append(fields)

print("===== PROMOTION HISTORY =====")
if not records:
    print("No promotion events recorded.")
else:
    print("UTC TIMESTAMP\tPHASE\tCHANNEL\tRELEASE\tPREVIOUS SNAPSHOT\tNEW SNAPSHOT\tACTION")
    for fields in records:
        print("\t".join(fields))

print()
print("===== UNRESOLVED TRANSACTIONS =====")
if not pending:
    print("None.")
else:
    for (channel, release, previous, new, action), line_number in pending.items():
        print(f"Line: {line_number}")
        print(f"  Channel:  {channel}")
        print(f"  Release:  {release}")
        print(f"  Previous: {previous}")
        print(f"  New:      {new}")
        print(f"  Action:   {action}")
PYSHOW
}

status() {
    (($# == 0)) || fail "status takes no arguments"

    local root
    root="$(publication_root)"

    local channel releases pointer target
    for channel in testing stable; do
        releases="$root/$channel/releases"
        printf '\n===== %s =====\n' "${channel^^}"

        if [[ ! -d "$releases" ]]; then
            printf 'No releases promoted.\n'
            continue
        fi

        local found=0
        for pointer in "$releases"/*; do
            [[ -L "$pointer" ]] || continue
            found=1
            target="$(readlink -- "$pointer")"
            printf '%s -> %s\n' "${pointer##*/}" "$target"
        done

        ((found == 1)) || printf 'No releases promoted.\n'
    done
}

main() {
    (($# >= 1)) || {
        usage
        exit 2
    }

    local operation="$1"
    shift

    case "$operation" in
        prepare)
            prepare "$@"
            ;;
        verify-snapshot)
            verify_snapshot "$@"
            ;;
        promote)
            promote "$@"
            ;;
        rollback)
            rollback "$@"
            ;;
        recover)
            recover "$@"
            ;;
        status)
            status "$@"
            ;;
        history)
            history "$@"
            ;;
        *)
            usage
            fail "Unknown operation: $operation"
            ;;
    esac
}

require_tools
main "$@"
