Name:       jenkins-worker-util
Summary:    Utils for Otctools Jenkins worker
Version:    1.14.2
Release:    1
Group:      Development/Tools/Other
License:    Intel Proprietary
BuildArch:  noarch
URL:        https://otctools.jf.intel.com/pm/projects/tools-testing
Source0:    %{name}-%{version}.tar.gz

BuildRequires:  coreutils

Requires:   coreutils sudo git-core make osc kvm python-urlgrabber
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

%{_bindir}/build-package
%{_bindir}/install_package
%{_bindir}/kvm-worker.sh
%{_bindir}/otc-tools-tester-delete-merged-jobs.sh
%{_bindir}/otc-tools-tester-run-test-kvm.sh
%{_bindir}/otc-tools-tester-system-what-release.sh
%{_bindir}/pre_deployment_test_dispatcher.py
%{_bindir}/pre_deployment_test_worker.py
%{_bindir}/run_tests
%{_bindir}/run-itest-kvm.sh
%{_bindir}/run-mic-in-kvm.sh
%{_bindir}/safeosc
%{_bindir}/trigger_itest_verify.sh
/etc/sudoers.d
%config /etc/sudoers.d/jenkins

%package -n jenkins-worker-mgmt
Summary:  Management scripts for jenkins-worker images

%description -n jenkins-worker-mgmt
Management scripts for jenkins-worker-util package, to deploy
images in various ways, and to run hda seed image update.

Requires: jenkins-worker-utils

%files -n jenkins-worker-mgmt
%defattr(-,root,root,-)

%{_bindir}/otc-tools-update-kvm-seed-image.sh
%{_bindir}/deploy-*.sh
/etc/jenkins-worker
%config /etc/jenkins-worker/workers.env
