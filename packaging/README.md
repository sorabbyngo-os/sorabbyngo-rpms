# RPM Packaging Standards

This directory contains packaging standards, build guidance and future tooling for first-party Sorabbyngo OS RPM packages.

## Goals

- Consistent RPM packaging.
- Reproducible and auditable builds.
- Clear upstream provenance.
- Correct dependency declarations.
- Safe upgrades and removal.
- License compliance.
- Automated validation.

## Package structure

Each package should eventually have its own dedicated directory when packaging assets become substantial.

Typical packaging files include:

- RPM spec file.
- Source references or source archives.
- Patches.
- Build configuration.
- Validation scripts.
- Package-specific documentation.

## RPM spec requirements

First-party packages should maintain clear and accurate spec files.

Spec files should appropriately define:

- Name.
- Version.
- Release.
- Summary.
- License.
- Source.
- Build dependencies.
- Runtime dependencies.
- Description.
- Build instructions.
- Installation instructions.
- File ownership.
- Changelog.

## Versioning

Package versions must reflect the upstream software version wherever practical.

The RPM release field should distinguish Sorabbyngo packaging revisions without misrepresenting upstream versions.

## Dependencies

Dependencies must be explicitly declared.

Packaging must not depend on undeclared libraries, development files, tools or files available only in the packager's workstation.

## Build integrity

Packages should be built in controlled environments.

Builds should avoid unnecessary dependencies on the host system and should document exceptions.

Where practical, packaging workflows should use isolated build environments and established RPM build tooling.

## Licensing

Packages must correctly declare their license.

Upstream licenses, copyright notices, trademarks and attribution must be preserved where required.

Redistribution requirements must be reviewed before publishing.

## Validation

Packages should undergo appropriate checks before publication:

- Spec file validation.
- RPM build validation.
- Dependency checks.
- File ownership checks.
- Installation and removal checks in test environments.
- Upgrade testing.
- Signature validation.
- License and provenance review.

## Security

Packaging must not introduce unsafe installation scripts or unnecessary privileged operations.

RPM scriptlets must be limited to appropriate installation, upgrade and removal tasks.

## Status

These standards are being established. Automated enforcement and build infrastructure will be introduced incrementally.
