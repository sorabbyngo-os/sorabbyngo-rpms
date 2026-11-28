# Sorabbyngo RPMs

**The RPM packaging and distribution infrastructure for Sorabbyngo OS.**

Sorabbyngo RPMs is the home for RPM packaging standards, repository infrastructure, package publishing, signing, build automation and package-source policies for Sorabbyngo OS.

Our goal is to build a reliable software distribution ecosystem without requiring Sorabbyngo OS to independently package every application available to Linux users.

## Objectives

- Maintain and distribute first-party Sorabbyngo OS RPM packages.
- Provide a trusted, signed RPM repository for Sorabbyngo software.
- Reuse compatible packages from explicitly trusted upstream sources when a package is unavailable in Sorabbyngo repositories.
- Establish consistent packaging, versioning, signing and release standards.
- Integrate with the Sorabbyngo OS package manager and graphical App Store.
- Make package distribution reproducible, auditable and maintainable.

## Repository architecture

| Project | Responsibility |
|---|---|
| `sorabbyngo-rpms` | RPM packaging standards, repository infrastructure, publishing, signing and package-source policies. |
| `sorabbyngo-app-store` | Graphical application discovery and installation interface. |
| `sorabbyngo OS` | System integration, package-management experience and operating-system policy. |

The App Store is a client of the package-management infrastructure. It is not responsible for hosting or maintaining the RPM repository itself.

## Distribution identity

Sorabbyngo OS maintains its own distribution identity, release lifecycle and architecture targets, independently of developer workstations and build environments.

The canonical distribution ID is `sorabbyngo`. Repository configuration and build tooling must use explicit Sorabbyngo target information rather than deriving product identity from the host system.

See [Distribution Identity](policy/distribution-identity.md).

## Package-source policy

Sorabbyngo OS will prioritize packages from its own repositories.

When a requested package is unavailable in enabled Sorabbyngo repositories, the package-management system may resolve it from explicitly trusted upstream repositories with a validated compatibility profile.

The fallback mechanism must:

1. Prioritize Sorabbyngo packages.
2. Restrict upstream fallback to explicitly configured and trusted repositories.
3. Verify package signatures and repository metadata.
4. Enforce architecture and release compatibility.
5. Resolve dependencies as part of a coherent transaction.
6. Avoid mixing incompatible package versions or releases.
7. Provide transaction visibility and appropriate rollback capabilities where supported.

Upstream fallback is a controlled compatibility mechanism, not unrestricted RPM downloading.

See [Package Source Policy](policy/package-source-policy.md).

## Upstream compatibility

Sorabbyngo OS maintains its own distribution identity, release lifecycle and package-source policies.

The RPM ecosystem provides access to established upstream packaging ecosystems and build practices. Sorabbyngo OS may reuse compatible upstream packages while maintaining independent release policies and first-party software.

Upstream distributions are package sources, not Sorabbyngo OS identities. Each source must have an explicitly maintained compatibility profile covering release, architecture, ABI, dependencies and system integration.

Package availability upstream does not automatically guarantee suitability for Sorabbyngo OS.

## Packaging standards

First-party packages should follow consistent standards covering:

- RPM spec files and build reproducibility.
- Package versioning and release numbering.
- Source provenance and upstream attribution.
- License declarations and compliance.
- Dependency declaration.
- RPM signing and repository metadata.
- Automated build and validation.
- Installation, upgrade and removal behavior.
- Security updates and vulnerability handling.

See [Packaging](packaging/README.md).

## Repository infrastructure

The repository infrastructure will eventually support:

- Signed RPM repository metadata.
- First-party package publication.
- Automated package builds.
- Build artifact verification.
- Repository indexing and metadata generation.
- Release channels, where appropriate.
- Package updates and retirement.
- Integration with Sorabbyngo OS package management.

See [Repository Infrastructure](repository/README.md).

## Release engineering

Repository metadata generation, signing, verification and release validation
are documented in the [Release Process](policy/release-process.md).

The current local tooling supports metadata signing and verification,
package signature verification and automated regression testing.
Repository hosting and automated publishing are not yet operational.

## Development status

This repository is under active development.

The policies and documentation are being established before the full repository infrastructure is implemented. A functioning hosted RPM repository, automated publishing system and integrated fallback resolver are not yet claimed by this project.

## License

Licensing is determined per component, packaging file, documentation or other artifact. Third-party software retains its original license and attribution.
