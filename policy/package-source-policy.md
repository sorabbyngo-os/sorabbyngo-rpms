# Sorabbyngo OS Package Source Policy

## 1. Purpose

Sorabbyngo OS aims to provide a unified software installation experience while maintaining its own software ecosystem.

Sorabbyngo OS will not attempt to independently package every application in the Linux ecosystem. Instead, it will maintain first-party RPM repositories and selectively reuse packages from explicitly trusted upstream sources with validated compatibility.

This policy defines package-source precedence and the requirements for upstream fallback.

## 2. Source precedence

Package resolution should follow this priority:

1. Enabled Sorabbyngo OS repositories.
2. Explicitly enabled upstream repositories with approved compatibility profiles.
3. Other sources only when explicitly configured and approved by the system's repository policy.

First-party packages take precedence when they intentionally provide the same package or a compatible replacement.

The resolver must not silently select an incompatible package simply because it has a higher version number.

## 3. Upstream fallback

When a package is unavailable in enabled Sorabbyngo repositories, the package manager may search approved upstream repositories for a compatible package.

Fallback must be transparent to the package-management system and must not bypass normal RPM dependency resolution, transaction validation or repository security controls.

Fallback is not permission to download arbitrary RPM files from untrusted websites.

## 4. Trust and security requirements

Upstream package resolution must:

- Require trusted repository configuration.
- Validate repository metadata and package signatures.
- Respect repository signing-key policy.
- Reject packages from untrusted or unauthorized sources.
- Validate package architecture.
- Validate release and system compatibility.
- Preserve dependency integrity.
- Avoid downgrades or replacement of protected system components without appropriate transaction policy.
- Respect system security and update policies.

## 5. Compatibility requirements

Upstream compatibility is source-specific and release-specific.

Sorabbyngo OS must define supported upstream compatibility profiles and target architectures rather than assuming packages from different distributions or releases are interchangeable.

Compatibility evaluation should consider:

- RPM dependency constraints.
- Upstream release and package build metadata.
- Architecture.
- Core system libraries.
- System-critical package relationships.
- Kernel and boot-related packages.
- Package conflicts and replacements.
- System deployment model.

OSTree-based systems must integrate package operations with their deployment and layering model.

## 6. Resolution and transactions

The package manager must resolve dependencies before executing a transaction.

Users should be able to review significant package transactions, including:

- Packages to be installed.
- Packages to be upgraded or downgraded.
- Packages to be removed.
- Dependency changes.
- Package source repositories.

The resolver must not perform partial or unmanaged installations that bypass the system package-management framework.

## 7. First-party package ownership

Sorabbyngo OS may publish custom RPMs to provide:

- Sorabbyngo OS components.
- Custom desktop applications.
- OS integrations.
- Repackaged upstream software.
- Software with Sorabbyngo-specific patches.
- Software selected for distribution support.

First-party packages must preserve applicable upstream licensing and attribution.

## 8. App Store integration

The Sorabbyngo App Store should use the system package-management infrastructure.

It should not implement a separate RPM dependency resolver or independently bypass repository trust, package validation and transaction policies.

The App Store may display package source, availability and relevant transaction details.

## 9. Repository management

Repository configuration must be managed consistently across the OS.

Repository enablement, removal, key management, compatibility configuration and update policies must be controlled through supported system mechanisms.

Third-party repository configuration must not silently weaken system trust policy.

## 10. Implementation direction

The implementation should evaluate established RPM ecosystem components rather than introducing a custom RPM dependency resolver.

DNF and RPM tooling are candidates for conventional RPM-based installations.

OSTree-based deployments must use an approach compatible with their deployment and layering semantics.

The final implementation must be selected based on the Sorabbyngo OS deployment architecture.

## 11. Future extensions

This policy may evolve to support:

- Multiple Sorabbyngo release channels.
- Package provenance and transparency.
- Automated compatibility testing.
- Package vulnerability monitoring.
- Controlled third-party repositories.
- Package caching.
- Offline package operations.
- Repository mirroring.
- Rollback-aware package transactions.

## 12. Policy enforcement

This document establishes the intended package-source behavior.

The policy is not considered fully implemented until repository configuration, package resolution, trust validation, transaction integration and compatibility enforcement have been implemented and tested.
