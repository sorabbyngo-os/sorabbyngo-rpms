# Sorabbyngo Repository Configuration

## Purpose

This package provides the official RPM repository definitions and
distribution release metadata for Sorabbyngo OS.

## Repository channels

- **Stable:** Enabled by default for supported Sorabbyngo OS releases.
- **Testing:** Disabled by default. Intended for controlled testing.

Both repositories require RPM package signature verification and
repository metadata signature verification.

## Release version requirement

The Sorabbyngo OS base system must provide:

`/etc/dnf/vars/sorabbyngo_releasever`

Its value must match the Sorabbyngo OS release version. This package
does not derive the release version from the build host or create that
variable.

## Repository availability

The configured repository and signing-key URLs are planned endpoints.
A published signing key, signed repository metadata, and hosted RPM
content are required before these definitions can be used operationally.

## Configuration files

- `sorabbyngo-stable.repo`
- `sorabbyngo-testing.repo`
- `sorabbyngo-release.conf`

## Project

https://github.com/sorabbyngo-os/sorabbyngo-rpms
