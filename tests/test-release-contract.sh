#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
manifest="$root/config-package/sorabbyngo-release.conf"
[[ -f "$manifest" ]] || manifest="$root/sorabbyngo-release.conf"
fixture="$root/tests/fixtures/sorabbyngo-os-release"

get_value() {
    local key="$1"
    sed -n "s/^${key}=//p" "$2" | head -n 1 | tr -d '"'
}

release_source="$(get_value RELEASE_SOURCE "$manifest")"
version_key="$(get_value RELEASE_VERSION_KEY "$manifest")"
variable_name="$(get_value DNF_RELEASE_VARIABLE_NAME "$manifest")"
variable_path="$(get_value DNF_RELEASE_VARIABLE "$manifest")"

[[ "$release_source" == "/etc/os-release" ]]
[[ "$version_key" == "VERSION_ID" ]]
[[ "$variable_name" == "sorabbyngo_releasever" ]]
[[ "$variable_path" == "/etc/dnf/vars/$variable_name" ]]

release_version="$(get_value "$version_key" "$fixture")"
[[ "$release_version" == "2026.1" ]]

printf '%s=%s\n' "$variable_name" "$release_version"
echo "Release-variable contract: PASS"
