# RPM Repository Infrastructure

This directory documents and will eventually contain the infrastructure responsible for building, signing, publishing and maintaining Sorabbyngo OS RPM repositories.

## Architecture

The repository infrastructure is intended to support the lifecycle of first-party RPM packages:

1. Source acquisition.
2. Package building.
3. Build validation.
4. Artifact verification.
5. RPM signing.
6. Repository metadata generation.
7. Repository publication.
8. Updates and maintenance.

## Repository layout

The published repository must follow a structure compatible with RPM repository tooling.

A future repository may support multiple architectures and release channels.

Example conceptual layout:

```text
repository-root/
├── repodata/
├── Packages/
│   ├── x86_64/
│   └── aarch64/
└── repository configuration
The final layout will be determined by the publishing implementation.
Repository metadata
Published repositories must provide valid RPM repository metadata.

Metadata must be generated using established RPM repository tooling and must be verifiable by compatible package managers.
Signing
First-party RPM packages and repository metadata must follow the Sorabbyngo OS signing policy.

Signing keys must be protected.

Private signing keys must not be stored in this repository.

Signing infrastructure must be separated from ordinary package build environments where practical.
Publishing
Package publication should be automated.

The publication pipeline must validate artifacts before they become available to clients.

Publication should avoid exposing incomplete repository metadata or partially published package sets.
Build pipeline
The planned build pipeline should:
- Build packages in controlled environments.
- Validate RPM artifacts.
- Record package provenance.
- Check dependencies.
- Verify architecture compatibility.
- Sign approved packages.
- Generate repository metadata.
- Publish validated releases.
Release management
Repository releases should be traceable.

The infrastructure should eventually support package promotion, release channels, package retirement and recovery from publishing failures.
Hosting
Repository hosting will be evaluated based on reliability, cost, scalability, integrity and accessibility.

Potential approaches include dedicated hosting, object storage or other compatible distribution infrastructure.
Offline support
Repository infrastructure should eventually support repository mirroring and local caching.

This will help support installations, updates and software access in environments with limited or unreliable internet connectivity.
Status
The repository infrastructure described here is architectural documentation.

Hosted repositories, build automation, signing services and publishing pipelines have not yet been implemented.
