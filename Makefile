SH_FILES := install_package run_tests otc-tools-tester-run-test-kvm.sh \
otc-tools-tester-system-what-release.sh \
kvm-worker.sh run-itest-kvm.sh trigger_itest_verify.sh \
otc-tools-tester-delete-merged-jobs.sh otc-tools-update-kvm-seed-image.sh

PY_FILES := build-package safeosc

install:
	install -d $(DESTDIR)/usr/bin
	install -m 0755 $(SH_FILES) $(PY_FILES) $(DESTDIR)/usr/bin
	install -d $(DESTDIR)/etc/sudoers.d
	install -m 0644 sudoers.jenkins $(DESTDIR)/etc/sudoers.d/jenkins

test:
	checkbashisms $(SH_FILES)
