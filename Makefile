SH_FILES := install_package run_tests otc-tools-tester-run-test-kvm.sh \
otc-tools-tester-system-what-release.sh otc-tools-tester-maintenance-del-old-buildroots.sh \
otc-tools-tester-maintenance-del-old-obs-builds.sh otc-tools-create-failedjob-vm-config.sh \
otc-tools-scan-failedjobs.sh kvm-worker.sh run-itest-kvm.sh

PY_FILES := build-package safeosc

install:
	install -d $(DESTDIR)/usr/bin
	install -m 0755 $(SH_FILES) $(PY_FILES) $(DESTDIR)/usr/bin
	install -d $(DESTDIR)/etc/sudoers.d
	install -m 0644 sudoers.jenkins $(DESTDIR)/etc/sudoers.d/jenkins
	install -d $(DESTDIR)/usr/share/libvirt-templates
	install -m 0644 otc-tools-failedjob-vm-template.xml $(DESTDIR)/usr/share/libvirt-templates

test:
	checkbashisms $(SH_FILES)
