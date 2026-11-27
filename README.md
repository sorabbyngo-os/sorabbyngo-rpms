# Sorabbyngo RPMs

**The RPM packaging and distribution infrastructure for Sorabbyngo OS.**

Sorabbyngo RPMs is the home for RPM packaging standards, repository infrastructure, package publishing, signing, build automation and package-source policies for Sorabbyngo OS.

Our goal is to build a reliable software distribution ecosystem without requiring Sorabbyngo OS to independently package every application available to Linux users.

## Objectives

- Maintain and distribute first-party Sorabbyngo OS RPM packages.
- Provide a trusted, signed RPM repository for Sorabbyngo software.
- Reuse compatible upstream Fedora packages when a package is not available in Sorabbyngo repositories.
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

## Package-source policy

Sorabbyngo OS will prioritize packages from its own repositories.

When a requested package is unavailable in enabled Sorabbyngo repositories, the package-management system may resolve it from explicitly trusted, compatible Fedora repositories.

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

## Fedora compatibility

Sorabbyngo OS is designed to leverage the Fedora RPM ecosystem where compatibility permits.

Fedora provides a broad package ecosystem, existing build infrastructure and established packaging practices. Sorabbyngo OS can reuse compatible packages while maintaining its own identity, release policies and first-party software.

Compatibility must be explicitly validated. Package availability upstream does not automatically guarantee suitability for Sorabbyngo OS.

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

## Development status

This repository is under active development.

The policies and documentation are being established before the full repository infrastructure is implemented. A functioning hosted RPM repository, automated publishing system and integrated fallback resolver are not yet claimed by this project.

## License

Licensing is determined per component, packaging file, documentation or other artifact. Third-party software retains its original license and attribution.
