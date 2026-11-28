# Sorabbyngo OS Distribution Identity

## 1. Purpose

Sorabbyngo OS is an independent Linux distribution with its own identity, release lifecycle, package policies and software distribution infrastructure.

The identity of the distribution must remain independent of the operating system used by developers, build machines or CI runners.

## 2. Canonical identity

| Property | Value |
|---|---|
| Distribution name | Sorabbyngo OS |
| Distribution ID | sorabbyngo |
| Package ecosystem | RPM |
| Primary repository domain | repo.sorabbyngo.org |
| Primary repository protocol | HTTPS |

The distribution ID is a stable machine-readable identifier. It must not change between releases.

## 3. Release identity

Sorabbyngo OS owns its release numbering and lifecycle.

Release identifiers must be defined by the Sorabbyngo OS release process. They must not be inferred from the release number of a developer workstation or upstream distribution.

The release identity must be consistent across:

- Operating system release metadata.
- RPM repository configuration.
- Package build metadata.
- Installation media.
- Update infrastructure.
- System diagnostics.

## 4. Architecture identity

Architecture identifiers must use established RPM architecture naming conventions.

Initial architecture targets may include:

- x86_64
- aarch64

An architecture is supported only after its build, dependency and runtime compatibility have been validated.

## 5. Host and target separation

Build tooling must distinguish between the host environment and the target environment.

The host is the machine or environment performing a build.

The target is the intended Sorabbyngo OS release and architecture.

Host distribution identity must never silently determine the identity of a Sorabbyngo OS package or release.

Build systems must accept explicit target configuration and validate it before producing artifacts.

## 6. Upstream compatibility

Sorabbyngo OS may reuse compatible software from external Linux distribution ecosystems.

Upstream distributions are package sources, not Sorabbyngo OS identities.

Each upstream source must have a separately maintained compatibility profile.

Compatibility must consider package dependencies, ABI, release metadata, architecture, system integration and security requirements.

## 7. Repository identity

The canonical repository domain is:

`repo.sorabbyngo.org`

Repository configuration must use HTTPS and verified repository metadata.

Repository channels and release paths must follow the Sorabbyngo OS release policy.

No repository configuration should derive its product identity from the host distribution.

## 8. Naming and branding

First-party package metadata, repository documentation and system-facing configuration must consistently identify Sorabbyngo OS.

Upstream package names, licenses, trademarks and attribution must be preserved where required.

## 9. Implementation status

This document establishes the intended identity contract.

The operating system release metadata, build tooling and repository configuration must implement and validate this contract before it is considered fully enforced.
