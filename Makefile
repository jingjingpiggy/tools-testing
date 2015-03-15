SH_FILES := install_package run_tests otc-tools-tester-run-test-kvm.sh \
tools-testing-what-release.sh \
kvm-worker.sh run-itest-kvm.sh \
run-install-upgrade-test.sh \
otc-tools-tester-delete-merged-jobs.sh otc-tools-update-kvm-seed-image.sh \
pre-deployment-test-worker.sh \
deploy-all-new-hda-to-all-workers.sh deploy-one-file-to-all-workers.sh \
deploy-one-new-hda-to-all-workers.sh deploy-images-to-one-worker.sh \
deploy-one-hda-to-all-workers.sh

PY_FILES := build-package safeosc trigger_itest_verify.py

install:
	install -d $(DESTDIR)/usr/bin
	install -m 0755 $(SH_FILES) $(PY_FILES) $(DESTDIR)/usr/bin
	install -d $(DESTDIR)/etc/sudoers.d
	install -m 0644 sudoers.jenkins $(DESTDIR)/etc/sudoers.d/jenkins
	install -d $(DESTDIR)/etc/jenkins-worker
	install -m 0644 workers.env $(DESTDIR)/etc/jenkins-worker
	install -d $(DESTDIR)/etc/tools-tester.d
	install -m 0644 base-repos-*.conf servers-*.conf $(DESTDIR)/etc/tools-tester.d

test:
	checkbashisms $(SH_FILES)
