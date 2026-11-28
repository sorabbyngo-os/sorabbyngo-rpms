Name:           sorabbyngo-repos
Version:        0.1.0
Release:        1
Summary:        RPM repository configuration for Sorabbyngo OS
URL:            https://github.com/sorabbyngo-os/sorabbyngo-rpms
License:        GPL-3.0-or-later
BuildArch:      noarch
Source0:        %{name}-%{version}.tar.gz

%description
Repository configuration and distribution identity metadata for
Sorabbyngo OS. This package configures the official stable and testing
RPM repositories without modifying unrelated repository definitions.

The Sorabbyngo OS base system supplies the release-version variable
required by the configured package manager.

%prep
%autosetup -n %{name}-%{version}

%check
# Validate repository definitions and security policy before packaging.
stable=repo-files/sorabbyngo-stable.repo
testing=repo-files/sorabbyngo-testing.repo
manifest=sorabbyngo-release.conf
key_url=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-sorabbyngo

test -s "$stable"
test -s "$testing"
test -s "$manifest"
test -s "keys/RPM-GPG-KEY-sorabbyngo.asc"

grep -Fqx "[sorabbyngo-stable]" "$stable"
grep -Fqx "[sorabbyngo-testing]" "$testing"
grep -Fqx 'baseurl=https://repo.sorabbyngo.org/rpm/stable/releases/$sorabbyngo_releasever/$basearch/' "$stable"
grep -Fqx 'baseurl=https://repo.sorabbyngo.org/rpm/testing/releases/$sorabbyngo_releasever/$basearch/' "$testing"

grep -Fqx "enabled=1" "$stable"
grep -Fqx "enabled=0" "$testing"

for repo in "$stable" "$testing"; do
    grep -Fqx "gpgcheck=1" "$repo"
    grep -Fqx "repo_gpgcheck=1" "$repo"
    grep -Fqx "skip_if_unavailable=0" "$repo"
    grep -Fqx "gpgkey=$key_url" "$repo"
    test "$(grep -c "^gpgkey=" "$repo")" -eq 1
    grep -Fq "baseurl=https://" "$repo"
    ! grep -Eq "^[[:space:]]*baseurl=http://" "$repo"
done

# Validate the release identity and DNF variable contract.
grep -Fqx "ID=sorabbyngo" "$manifest"
grep -Fqx "RELEASE_SOURCE=/etc/os-release" "$manifest"
grep -Fqx "RELEASE_VERSION_KEY=VERSION_ID" "$manifest"
grep -Fqx "DNF_RELEASE_VARIABLE=/etc/dnf/vars/sorabbyngo_releasever" "$manifest"
grep -Fqx "DNF_RELEASE_VARIABLE_NAME=sorabbyngo_releasever" "$manifest"
grep -Fqx "DEFAULT_CHANNEL=stable" "$manifest"
grep -Fqx "SUPPORTED_CHANNELS=stable,testing" "$manifest"

test -x tests/test-release-contract.sh
bash tests/test-release-contract.sh


%build
# No compilation is required.

%install
mkdir -p %{buildroot}%{_licensedir}/%{name}
install -m 0644 LICENSE %{buildroot}%{_licensedir}/%{name}/LICENSE
mkdir -p %{buildroot}%{_sysconfdir}/yum.repos.d
mkdir -p %{buildroot}%{_datadir}/sorabbyngo-rpms
mkdir -p %{buildroot}%{_sysconfdir}/pki/rpm-gpg

install -m 0644 repo-files/sorabbyngo-stable.repo \
    %{buildroot}%{_sysconfdir}/yum.repos.d/sorabbyngo-stable.repo
install -m 0644 repo-files/sorabbyngo-testing.repo \
    %{buildroot}%{_sysconfdir}/yum.repos.d/sorabbyngo-testing.repo
install -m 0644 keys/RPM-GPG-KEY-sorabbyngo.asc \
    %{buildroot}%{_sysconfdir}/pki/rpm-gpg/RPM-GPG-KEY-sorabbyngo
install -m 0644 sorabbyngo-release.conf \
    %{buildroot}%{_datadir}/sorabbyngo-rpms/sorabbyngo-release.conf

%files
%doc docs/README.md
%license %{_licensedir}/%{name}/LICENSE
%config(noreplace) %{_sysconfdir}/yum.repos.d/sorabbyngo-stable.repo
%config(noreplace) %{_sysconfdir}/yum.repos.d/sorabbyngo-testing.repo
%{_datadir}/sorabbyngo-rpms/sorabbyngo-release.conf
%{_sysconfdir}/pki/rpm-gpg/RPM-GPG-KEY-sorabbyngo


%changelog
* Fri Nov 27 2026 Project maintainers - 0.1.0-1
- Initial repository configuration package for Sorabbyngo OS.
