Name:       jenkins-worker-util
Summary:    Utils for Otctools Jenkins worker
Version:    0.9
Release:    1
Group:      Development/Tools/Other
License:    Intel Proprietary
BuildArch:  noarch
URL:        https://otctools.jf.intel.com/pm/projects/tools-testing
Source0:    %{name}-%{version}.tar.gz

BuildRequires:  coreutils

Requires:   coreutils git-core make osc

%description
Utils for Otctools Jenkins worker host

%prep
%setup -q -n %{name}-%{version}

%build

%install
rm -rf %{buildroot}
make DESTDIR=%{buildroot} install

%files
%defattr(-,root,root,-)

%{_bindir}/*
