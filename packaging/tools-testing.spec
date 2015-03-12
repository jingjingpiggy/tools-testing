%{!?python_sitelib: %define python_sitelib %(%{__python} -c "from distutils.sysconfig import get_python_lib; print get_python_lib()")}
Name:       tools-testing
Summary:    Utilities for Tools tester Jenkins worker
Version:    1.34.0
Release:    1
Group:      Development/Tools/Other
License:    Intel Proprietary
BuildArch:  noarch
URL:        https://otctools.jf.intel.com/pm/projects/tools-testing
Source0:    %{name}-%{version}.tar.gz

BuildRequires:  coreutils
BuildRequires:  python-devel python-setuptools

Requires: coreutils sudo git-core make osc kvm util-linux sysvinit-tools tar python-Jinja2 python-setuptools socat buffer
Recommends: numactl

%if 0%{?suse_version} > 1220
BuildRequires:   shadow
Requires: gptfdisk
%endif

%description
Utilities for Tools tester Jenkins worker

%prep
%setup -q -n %{name}-%{version}

%build

%install
rm -rf %{buildroot}
make DESTDIR=%{buildroot} install
%{__python} setup.py install --prefix=%{_prefix} --root=%{buildroot}

%post
if [ ! "$(getent passwd jenkins)" ]; then
  useradd -m -d /var/lib/jenkins -u 777 -g users -s /bin/sh -c "Jenkins user account" jenkins
fi
if [ "$(getent group kvm)" ]; then
  usermod -G kvm jenkins
fi

%files
%defattr(-,root,root,-)

%{_bindir}/build-package
%{_bindir}/install_package
%{_bindir}/kvm-worker.sh
%{_bindir}/otc-tools-tester-delete-merged-jobs.sh
%{_bindir}/otc-tools-tester-run-test-kvm.sh
%{_bindir}/tools-testing-what-release.sh
%{_bindir}/pre-deployment-test-worker.sh
%{_bindir}/run_tests
%{_bindir}/run-itest-kvm.sh
%{_bindir}/run-install-upgrade-test.sh
%{_bindir}/safeosc
%{_bindir}/trigger_itest_verify.py
%{python_sitelib}/pre_deployment_test/
%{python_sitelib}/pre_deployment_test-*-py*.egg-info
%dir /etc/sudoers.d
%config /etc/sudoers.d/jenkins

%package mgmt
Summary:  Management scripts for jenkins-worker images
Requires: tools-testing

%description mgmt
Management scripts to go with tools-testing package, for deploying
images to other workers in various ways, and to run hda seed image update.

%files mgmt
%defattr(-,root,root,-)

%{_bindir}/otc-tools-update-kvm-seed-image.sh
%{_bindir}/deploy-*.sh
%dir /etc/jenkins-worker
%config /etc/jenkins-worker/workers.env
