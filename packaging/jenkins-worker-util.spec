Name:       jenkins-worker-util
Summary:    Utils for Otctools Jenkins worker
Version:    1.11.0
Release:    1
Group:      Development/Tools/Other
License:    Intel Proprietary
BuildArch:  noarch
URL:        https://otctools.jf.intel.com/pm/projects/tools-testing
Source0:    %{name}-%{version}.tar.gz

BuildRequires:  coreutils

Requires:   coreutils sudo git-core make osc kvm
%if 0%{?suse_version} > 1220
BuildRequires:   shadow
%endif

%description
Utils for Otctools Jenkins worker host

%prep
%setup -q -n %{name}-%{version}

%build

%install
rm -rf %{buildroot}
make DESTDIR=%{buildroot} install

%post
if [ ! "$(getent passwd jenkins)" ]; then
  useradd -m -d /var/lib/jenkins -u 777 -g users -s /bin/sh -c "Jenkins user account" jenkins
fi
if [ "$(getent group kvm)" ]; then
  usermod -G kvm jenkins
fi

%files
%defattr(-,root,root,-)

%{_bindir}/*
/etc/sudoers.d
%config /etc/sudoers.d/jenkins
/usr/share/libvirt-templates/
/usr/share/libvirt-templates/otc-tools-failedjob-vm-template.xml
