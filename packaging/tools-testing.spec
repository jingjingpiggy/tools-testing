%{!?python_sitelib: %define python_sitelib %(%{__python} -c "from distutils.sysconfig import get_python_lib; print get_python_lib()")}
Name:       tools-testing
Summary:    Utilities for Tools tester Jenkins worker
Version:    1.34.0
Release:    1
Group:      Development/Tools/Other
License:    Intel Proprietary
BuildArch:  noarch
URL:        https://review.tizendev.org/gerrit/
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
Utilities to be run on Tools Tester Jenkins worker host, to prepare and start VM tester sessions

%package mgmt
Summary:  Management scripts for jenkins-worker images
Group:      Development/Tools/Other
Requires: tools-testing
%description mgmt
Management scripts for tools-testing package, to deploy
images in various ways, and to run hda seed image update.

%package settings-otctools
Summary:  Tools tester jenkins-worker settings in otctools env
Group:      Development/Tools/Other
Requires: tools-testing
#Conflicts: tools-testing-settings-tizenorg
%description settings-otctools
Settings for tools-testing package,
describing repositories for tester VMs.

%package settings-tizenorg
Summary:  Tools tester jenkins-worker settings in tizen.org env
Group:      Development/Tools/Other
Requires: tools-testing
#Conflicts: tools-testing-settings-otctools
%description settings-tizenorg
Settings for tools-testing package,
describing repositories for tester VMs.

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

###############################################
%files
%defattr(-,root,root,-)
%{_bindir}/build-package
%{_bindir}/install_package
%{_bindir}/kvm-worker.sh
%{_bindir}/tools-testing-delete-merged-jobs.sh
%{_bindir}/tools-testing-run-test.sh
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

###############################################
%files mgmt
%defattr(-,root,root,-)
%{_bindir}/tools-testing-update-seed-images.sh
%{_bindir}/deploy-*.sh
%dir /etc/jenkins-worker
%config /etc/jenkins-worker/workers.env

###############################################
%files settings-otctools
%defattr(-,root,root,-)
%dir /etc/tools-tester.d
%config /etc/tools-tester.d/base-repos-otctools.conf
%config /etc/tools-tester.d/servers-otctools.conf

###############################################
%files settings-tizenorg
%defattr(-,root,root,-)
%dir /etc/tools-tester.d
%config /etc/tools-tester.d/base-repos-tizenorg.conf
%config /etc/tools-tester.d/servers-tizenorg.conf
