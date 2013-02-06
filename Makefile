FILES := build-package install_package safeosc run_tests otc-tools-tester-run-test-kvm.sh \
otc-tools-tester-system-what-release.sh otc-tools-tester-maintenance-del-old-buildroots.sh \
otc-tools-tester-maintenance-del-old-obs-builds.sh otc-tools-tester-update-all-packages.sh

install:
	install -d $(DESTDIR)/usr/bin
	install -m 0755 $(FILES) $(DESTDIR)/usr/bin

