#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
RELEASE_HOME="${SORABBYNGO_SIGNING_HOME:-$HOME/.local/share/sorabbyngo-signing/release}"
VERIFY_KEY="${SORABBYNGO_PUBLIC_KEY:-$ROOT/config-package/keys/RPM-GPG-KEY-sorabbyngo.asc}"
SIGNING_FINGERPRINT="${SORABBYNGO_SIGNING_FINGERPRINT:-F6A4554DD4DCF09AA7F79B12C7F3EFB04D5058A7}"
TRUSTED_RPM_FINGERPRINT="${SORABBYNGO_RPM_FINGERPRINT:-3B98F632BDC26FC933EE2D653A974697E5E940F2}"

usage() {
    cat <<'USAGE'
Usage:
  scripts/repository.sh metadata <repository-directory> [revision]
  scripts/repository.sh sign     <repository-directory>
  scripts/repository.sh verify   <repository-directory>
  scripts/repository.sh rpm-verify <repository-directory> <rpm-db-path>

All repository directories must be inside this checkout's build/ directory.
Verification checks the metadata signature, primary metadata checksum,
and every RPM checksum. rpm-verify checks package signatures and digests
against an explicitly supplied RPM database.
This tool does not publish repositories.
USAGE
}

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

repository_path() {
    local requested="$1"
    local resolved

    [[ -d "$requested" ]] || fail "Repository directory does not exist: $requested"
    resolved="$(cd -- "$requested" && pwd -P)"

    case "$resolved/" in
        "$ROOT"/build/*/) ;;
        *) fail "Repository directory must be inside $ROOT/build/" ;;
    esac

    printf '%s\n' "$resolved"
}

metadata() {
    local repo="$1"
    local revision="${2:-}"
    local -a packages=()
    local -a args=(--checksum sha256 --unique-md-filenames)

    mapfile -d '' packages < <(
        find "$repo" -maxdepth 1 -type f -name '*.rpm' -print0
    )
    ((${#packages[@]} > 0)) || fail "No RPM packages found directly inside $repo"

    command -v createrepo_c >/dev/null || fail "createrepo_c is required"

    # Never leave a stale signature attached to regenerated metadata.
    rm -f -- "$repo/repodata/repomd.xml.asc"

    if [[ -n "$revision" ]]; then
        args+=(--revision "$revision")
    fi

    createrepo_c "${args[@]}" "$repo"

    printf 'Metadata generated: %s/repodata/repomd.xml\n' "$repo"
    printf 'Metadata must be signed before this repository is used.\n'
}

sign_metadata() {
    local repo="$1"
    local repomd="$repo/repodata/repomd.xml"

    [[ -s "$repomd" ]] || fail "Missing repository metadata: $repomd"
    [[ -d "$RELEASE_HOME" ]] || fail "Signing key home not found: $RELEASE_HOME"
    command -v gpg >/dev/null || fail "gpg is required"

    rm -f -- "$repomd.asc"

    gpg --homedir "$RELEASE_HOME" \
        --batch \
        --local-user "$SIGNING_FINGERPRINT" \
        --armor --detach-sign \
        --output "$repomd.asc" \
        "$repomd"

    printf 'Signed repository metadata: %s\n' "$repomd.asc"
}

xml_value() {
    local expression="$1"
    local document="$2"

    xmllint --nonet --xpath "string($expression)" "$document"
}

safe_repo_file() {
    local repo="$1"
    local href="$2"
    local candidate resolved
    local component
    local -a components=()

    [[ -n "$href" ]] || fail "Repository metadata contains an empty file location"
    [[ "$href" != /* ]] || fail "Absolute repository path rejected: $href"

    IFS='/' read -r -a components <<< "$href"
    for component in "${components[@]}"; do
        case "$component" in
            ""|"."|"..")
                fail "Unsafe repository path rejected: $href"
                ;;
        esac
    done

    candidate="$repo/$href"
    [[ -f "$candidate" ]] || fail "Referenced repository file is missing: $href"

    resolved="$(realpath -e -- "$candidate")"

    case "$resolved" in
        "$repo"/*) ;;
        *) fail "Repository file resolves outside repository: $href" ;;
    esac

    printf '%s\n' "$resolved"
}

verify_metadata() (
    local repo="$1"
    local repomd="$repo/repodata/repomd.xml"
    local signature="$repomd.asc"
    local temp_dir gpg_home
    local primary_href primary_type primary_expected
    local primary_file primary_actual primary_xml
    local package_count package_href package_expected package_type
    local package_file package_actual
    local i

    [[ -s "$repomd" ]] || fail "Missing repository metadata: $repomd"
    [[ -s "$signature" ]] || fail "Missing metadata signature: $signature"
    [[ -s "$VERIFY_KEY" ]] || fail "Public verification key not found: $VERIFY_KEY"

    for tool in gpg xmllint sha256sum realpath; do
        command -v "$tool" >/dev/null || fail "$tool is required"
    done

    temp_dir="$(mktemp -d "$ROOT/build/verify.XXXXXXXX")"
    trap 'rm -rf -- "$temp_dir"' EXIT
    chmod 700 "$temp_dir"

    gpg_home="$temp_dir/gnupg"
    install -d -m 700 "$gpg_home"

    # Verify the signed repository index before trusting any metadata paths.
    gpg --homedir "$gpg_home" --batch --import "$VERIFY_KEY"
    gpg --homedir "$gpg_home" --batch --verify "$signature" "$repomd"
    printf 'Repository metadata signature: VALID\n'

    xmllint --nonet --noout "$repomd" ||
        fail "Repository index is not valid XML"

    primary_href="$(
        xml_value "(
            /*[local-name()='repomd']/*
            [local-name()='data' and @type='primary']/*
            [local-name()='location']
        )[1]/@href" "$repomd"
    )"
    primary_type="$(
        xml_value "(
            /*[local-name()='repomd']/*
            [local-name()='data' and @type='primary']/*
            [local-name()='checksum']
        )[1]/@type" "$repomd"
    )"
    primary_expected="$(
        xml_value "(
            /*[local-name()='repomd']/*
            [local-name()='data' and @type='primary']/*
            [local-name()='checksum']
        )[1]/text()" "$repomd"
    )"

    [[ "$primary_type" == "sha256" ]] ||
        fail "Primary metadata must use SHA-256; found: ${primary_type:-missing}"
    [[ "$primary_expected" =~ ^[[:xdigit:]]{64}$ ]] ||
        fail "Primary metadata has an invalid SHA-256 checksum"

    primary_file="$(safe_repo_file "$repo" "$primary_href")"
    primary_actual="$(sha256sum -- "$primary_file" | awk '{print $1}')"

    [[ "$primary_actual" == "$primary_expected" ]] ||
        fail "Primary metadata checksum mismatch: $primary_href"

    printf 'Primary metadata checksum: OK\n'

    primary_xml="$temp_dir/primary.xml"

    case "$primary_file" in
        *.zst)
            command -v zstd >/dev/null || fail "zstd is required for .zst metadata"
            zstd -q -d -c -- "$primary_file" > "$primary_xml"
            ;;
        *.gz)
            command -v gzip >/dev/null || fail "gzip is required for .gz metadata"
            gzip -dc -- "$primary_file" > "$primary_xml"
            ;;
        *.xz)
            command -v xz >/dev/null || fail "xz is required for .xz metadata"
            xz -dc -- "$primary_file" > "$primary_xml"
            ;;
        *.xml)
            cp -- "$primary_file" "$primary_xml"
            ;;
        *)
            fail "Unsupported primary metadata compression: $primary_file"
            ;;
    esac

    xmllint --nonet --noout "$primary_xml" ||
        fail "Primary metadata is not valid XML"

    package_count="$(
        xml_value "count(
            /*[local-name()='metadata']/*
            [local-name()='package']
        )" "$primary_xml"
    )"

    [[ "$package_count" =~ ^[0-9]+$ ]] ||
        fail "Could not determine primary metadata package count"
    ((package_count > 0)) ||
        fail "Primary metadata contains no packages"

    for ((i = 1; i <= package_count; i++)); do
        package_href="$(
            xml_value "(
                /*[local-name()='metadata']/*
                [local-name()='package'][$i]/*
                [local-name()='location']
            )[1]/@href" "$primary_xml"
        )"
        package_type="$(
            xml_value "(
                /*[local-name()='metadata']/*
                [local-name()='package'][$i]/*
                [local-name()='checksum']
            )[1]/@type" "$primary_xml"
        )"
        package_expected="$(
            xml_value "(
                /*[local-name()='metadata']/*
                [local-name()='package'][$i]/*
                [local-name()='checksum']
            )[1]/text()" "$primary_xml"
        )"

        [[ "$package_type" == "sha256" ]] ||
            fail "Package $i does not use SHA-256"
        [[ "$package_expected" =~ ^[[:xdigit:]]{64}$ ]] ||
            fail "Package $i has an invalid SHA-256 checksum"

        package_file="$(safe_repo_file "$repo" "$package_href")"
        package_actual="$(sha256sum -- "$package_file" | awk '{print $1}')"

        [[ "$package_actual" == "$package_expected" ]] ||
            fail "RPM checksum mismatch: $package_href"

        printf 'RPM checksum: OK  %s\n' "$package_href"
    done

    printf 'Repository checksum verification: PASS (%s packages)\n' "$package_count"
)

verify_rpm_signatures() {
    local repo="$1"
    local requested_db="$2"
    local rpm_db
    local -a packages=()

    [[ -d "$requested_db" ]] ||
        fail "Explicit RPM database directory does not exist: $requested_db"

    rpm_db="$(cd -- "$requested_db" && pwd -P)"

    command -v rpmkeys >/dev/null || fail "rpmkeys is required"

    mapfile -d '' packages < <(
        find "$repo" -maxdepth 1 -type f -name '*.rpm' -print0
    )
    ((${#packages[@]} > 0)) || fail "No RPM packages found directly inside $repo"

    printf 'Using explicit RPM database: %s\n' "$rpm_db"

    local package
    local verification_output
    for package in "${packages[@]}"; do
        printf '\nVerifying RPM: %s\n' "$(basename -- "$package")"

        if verification_output="$(
            rpmkeys --dbpath "$rpm_db" --checksig --verbose "$package"
        )"; then
            printf '%s\n' "$verification_output"
        else
            printf '%s\n' "$verification_output" >&2
            fail "RPM signature verification failed: $(basename -- "$package")"
        fi

        grep -Eiq "Header OpenPGP .*signature, key fingerprint: ${TRUSTED_RPM_FINGERPRINT,,}: OK" <<<"$verification_output" ||
            fail "RPM signer fingerprint or header signature does not match the trusted Sorabbyngo fingerprint: $(basename -- "$package")"
    done

    printf '\nRPM signature verification: PASS (%s packages)\n' "${#packages[@]}"
}

main() {
    (($# >= 2)) || {
        usage
        exit 2
    }

    local operation="$1"
    local repo
    shift

    case "$operation" in
        metadata)
            (($# >= 1 && $# <= 2)) ||
                fail "metadata expects a directory and optional revision"
            repo="$(repository_path "$1")"
            metadata "$repo" "${2:-}"
            ;;
        sign)
            (($# == 1)) || fail "sign expects exactly one repository directory"
            repo="$(repository_path "$1")"
            sign_metadata "$repo"
            ;;
        verify)
            (($# == 1)) || fail "verify expects exactly one repository directory"
            repo="$(repository_path "$1")"
            verify_metadata "$repo"
            ;;
        rpm-verify)
            (($# == 2)) ||
                fail "rpm-verify expects a repository directory and explicit RPM database path"
            repo="$(repository_path "$1")"
            verify_rpm_signatures "$repo" "$2"
            ;;
        *)
            usage
            fail "Unknown operation: $operation"
            ;;
    esac
}

main "$@"
