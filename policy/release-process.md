# Sorabbyngo RPM Repository Release Process

## 1. Purpose

This document defines the release-engineering workflow and verification gates for publishing RPM packages through Sorabbyngo OS repositories.

It establishes a repeatable process for package integrity, repository metadata, signing, validation and publication readiness.

This process documents the current local tooling and the intended release workflow. It does not imply that a hosted repository or automated publication service is operational.

## 2. Repository layout

The planned repository layout is:

```text
rpm/
├── stable/
│   └── releases/
│       └── <release>/
│           └── <architecture>/
│               ├── RPM packages
│               └── repodata/
└── testing/
    └── releases/
        └── <release>/
            └── <architecture>/
                ├── RPM packages
                └── repodata/
```

The repository configuration package defines the stable and testing channels.
- Stable is the intended production channel.
- Testing is intended for validation before stable promotion.
Release and architecture directories must contain packages appropriate to their declared targets.
## 3. Release prerequisites
Before preparing a repository release:
- Confirm that each RPM has an approved package name, version and release.
- Review package source provenance and licensing.
- Validate package build results.
- Confirm target release and architecture compatibility.
- Review package dependencies and transaction behavior.
- Confirm that the intended signing identity is available through approved key custody procedures.
- Confirm that the repository verification tooling and required dependencies are available.
Package artifacts must not be published merely because they successfully build.
## 4. Repository metadata
Repository metadata is generated with createrepo_c.

The repository metadata must:
- Describe the packages contained in the repository.
- Use SHA-256 checksums for primary metadata and package entries.
- Be regenerated when repository content changes.
- Be signed after metadata generation.
- Be verified before publication.
Regenerating repository metadata invalidates the previous metadata signature. A repository must be signed again after metadata regeneration.

The current tooling uses unique metadata filenames to avoid collisions between metadata generations.
## 5. Signing
RPM packages and repository metadata serve different verification purposes.
- RPM signatures authenticate individual package artifacts.
- Repository metadata signatures authenticate the repository index.
- Metadata checksums bind the index to referenced metadata and package artifacts.
The release signing identity must be managed independently of ordinary development operations.

Signing keys must:
- Have documented ownership and custody.
- Be protected against unauthorized access.
- Be used only for their intended signing responsibilities.
- Have a defined expiration, rotation and revocation procedure.
- Have a recovery and continuity plan.
The release signing key must not be exposed through repository hosting infrastructure.

Signing operations should be performed in a controlled environment. Long-term signing-key custody should be separated from routine development and repository hosting.
## 6. Local metadata generation and signing
The current tooling supports metadata generation and signing for repositories inside the project's build/ directory.

Example:
scripts/repository.sh metadata build/release-candidate
scripts/repository.sh sign build/release-candidate


The repository directory must contain RPM packages before metadata generation.

The signing operation requires access to the configured release signing key.

The signing command does not publish the repository.
## 7. Metadata verification
Before publication, verify the repository:
scripts/repository.sh verify build/release-candidate


This verification checks:
- Repository metadata signature.
- Repository index XML validity.
- Primary metadata checksum.
- Primary metadata XML validity.
- Package entries in primary metadata.
- Package file locations.
- Package SHA-256 checksums.
Repository verification must pass before repository content is considered publication-ready.

The verifier restricts repository paths to this checkout's build/ directory.
## 8. RPM signature verification
RPM signature verification must use an explicitly supplied RPM database containing the expected trusted signing key.

Example:
scripts/repository.sh rpm-verify \
    build/release-candidate \
    /path/to/isolated/rpmdb


The verifier checks:
- RPM signature validity.
- Header integrity.
- Payload integrity.
- Expected signing-key fingerprint.
The verification database must not be assumed to be the host's default RPM database.

The verifier explicitly checks the expected fingerprint rather than relying solely on the RPM database's trust presentation.
## 9. Automated regression tests
Run the repository regression suite:
tests/run-repository-tests.sh


The regression suite exercises:
- Release-variable contract.
- Valid repository metadata verification.
- Tampered repository index rejection.
- Modified package checksum rejection.
- Valid RPM signature and digest verification.
- Modified RPM payload rejection.
- Wrong trusted fingerprint rejection.
- Repository boundary rejection.
- Invalid RPM database rejection.
The test suite uses disposable directories under build/ and removes its temporary test copies when it exits.

RPM signature regression testing requires an explicitly prepared isolated RPM verification database. The test runner uses /var/tmp/sorabbyngo-rpm-verify by default and supports overriding this location through SORABBYNGO_TEST_RPM_DB.
## 10. Publication gates
A release must not be published until all applicable gates are satisfied:
1. Package source and licensing review.
2. Package build validation.
3. Release and architecture compatibility review.
4. Package signature verification.
5. Metadata generation.
6. Metadata signing.
7. Repository metadata verification.
8. RPM signature verification.
9. Automated regression tests.
10. Release manifest or equivalent inventory review.
11. Publication destination and access-control review.
12. Publication and rollback plan review.
The publication process must preserve the signed metadata and package artifacts that were verified.

Repository content must not be modified after verification without regenerating metadata and repeating the required verification.
## 11. Testing and stable promotion
Testing repository releases should undergo appropriate validation before promotion to stable.

Validation may include:
- Installation and upgrade tests.
- Dependency resolution tests.
- Removal tests.
- Compatibility tests on supported releases and architectures.
- Security review.
- Integration testing with Sorabbyngo OS.
- Application Store integration testing, where applicable.
Stable promotion should preserve the identity and integrity of approved artifacts.

Promotion must not silently replace approved package artifacts with different builds.
## 12. Publication, rollback and incident handling
The hosted publication infrastructure is not yet implemented.

When publication infrastructure is introduced, it must support:
- Controlled access to publication operations.
- Atomic or otherwise consistency-preserving publication.
- Preservation of repository metadata and package integrity.
- Release inventory and audit records.
- Recovery from incomplete publication.
- Rollback or withdrawal procedures.
- Signing-key rotation and compromise response.
- Clear handling of repository metadata expiration and stale clients.
A compromised signing key requires a documented incident response, including key revocation or replacement, repository recovery and communication to affected users.
## 13. Current implementation status
Implemented locally
- RPM repository configuration package.
- Repository metadata generation tooling.
- Repository metadata signing tooling.
- Repository metadata verification.
- RPM signature verification against an explicit RPM database.
- SHA-256 integrity verification.
- Automated regression tests for the verifier.
- Release-variable contract testing.
Not yet established
- Hosted production repository.
- Automated publication service.
- CI release pipeline.
- Repository mirroring and availability infrastructure.
- Automated stable promotion.
- Production key-custody infrastructure.
- Repository transparency and provenance infrastructure.
- Fully integrated Sorabbyngo OS package resolver.
The release process must be updated as these components become operational.
## 14. Related documentation
- Package Source Policy
- Distribution Identity
- Repository Configuration Package
- Project README
