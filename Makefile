GIT2LOG := $(shell if [ -x ./git2log ] ; then echo ./git2log --update ; else echo true ; fi)
GITDEPS := $(shell [ -d .git ] && echo .git/HEAD .git/refs/heads .git/refs/tags)
VERSION := $(shell $(GIT2LOG) --version VERSION ; cat VERSION)
BRANCH  := $(shell git branch | perl -ne 'print $$_ if s/^\*\s*//')
PREFIX  := perl-Bootloader-$(VERSION)

SBINDIR ?= /usr/sbin
ETCDIR  ?= /usr/etc

PM_FILES = $(shell find src -name '*.pm')

.PHONY:	export clean archive test install check

all:
	@echo "Choose one target out of 'archive', 'test', 'test_clean', 'docs', or 'clean'"
	@echo

changelog: $(GITDEPS)
	$(GIT2LOG) --changelog changelog

check: $(PM_FILES)
	@rm -rf .check
	@mkdir -p .check
	@cp -a src .check/Bootloader
	@cd .check ; find -name *.pm -exec perl -I. -c '{}' ';'

install: check
	@install -d -m 755 $(DESTDIR)/usr/lib/bootloader/grub2
	@install -m 755 grub2/install $(DESTDIR)/usr/lib/bootloader/grub2
	@install -m 755 grub2/config $(DESTDIR)/usr/lib/bootloader/grub2
	@install -m 755 grub2/add-option $(DESTDIR)/usr/lib/bootloader/grub2
	@install -m 755 grub2/del-option $(DESTDIR)/usr/lib/bootloader/grub2
	@install -m 755 grub2/get-option $(DESTDIR)/usr/lib/bootloader/grub2
	@install -m 755 grub2/default-settings $(DESTDIR)/usr/lib/bootloader/grub2

	@install -d -m 755 $(DESTDIR)/usr/lib/bootloader/grub2-efi
	@install -m 755 grub2-efi/install $(DESTDIR)/usr/lib/bootloader/grub2-efi
	@install -m 755 grub2/config $(DESTDIR)/usr/lib/bootloader/grub2-efi
	@install -m 755 grub2/add-option $(DESTDIR)/usr/lib/bootloader/grub2-efi
	@install -m 755 grub2/del-option $(DESTDIR)/usr/lib/bootloader/grub2-efi
	@install -m 755 grub2/get-option $(DESTDIR)/usr/lib/bootloader/grub2-efi
	@install -m 755 grub2/default-settings $(DESTDIR)/usr/lib/bootloader/grub2-efi

	@install -d -m 755 $(DESTDIR)/usr/lib/bootloader/u-boot
	@install -m 755 u-boot/config $(DESTDIR)/usr/lib/bootloader/u-boot

	@install -d -m 755 $(DESTDIR)/usr/lib/bootloader/systemd-boot
	@install -m 755 systemd-boot/install $(DESTDIR)/usr/lib/bootloader/systemd-boot
	@install -m 755 systemd-boot/config $(DESTDIR)/usr/lib/bootloader/systemd-boot
	@install -m 755 systemd-boot/add-kernel $(DESTDIR)/usr/lib/bootloader/systemd-boot
	@install -m 755 systemd-boot/remove-kernel $(DESTDIR)/usr/lib/bootloader/systemd-boot

	@install -D -m 755 pbl $(DESTDIR)$(SBINDIR)/pbl
	@perl -pi -e 's/0\.0/$(VERSION)/ if /VERSION = /' $(DESTDIR)$(SBINDIR)/pbl
	@ln -snf pbl $(DESTDIR)$(SBINDIR)/update-bootloader
	@ln -rsnf $(DESTDIR)$(SBINDIR)/pbl $(DESTDIR)/usr/lib/bootloader/bootloader_entry
	@install -D -m 644 boot.readme $(DESTDIR)/usr/share/doc/packages/perl-Bootloader/boot.readme
	@install -d -m 755 $(DESTDIR)/usr/share/man/man8
	@install -D -m 644 pbl.logrotate $(DESTDIR)$(ETCDIR)/logrotate.d/pbl
	@pod2man update-bootloader >$(DESTDIR)/usr/share/man/man8/update-bootloader.8
	@chmod 644 $(DESTDIR)/usr/share/man/man8/update-bootloader.8

	@install -D -m 755 kexec-bootloader $(DESTDIR)$(SBINDIR)/kexec-bootloader

archive: changelog
	mkdir -p package
	git archive --prefix=$(PREFIX)/ $(BRANCH) > package/$(PREFIX).tar
	tar -r -f package/$(PREFIX).tar --mode=0664 --owner=root --group=root --mtime="`git show -s --format=%ci`" --transform='s:^:$(PREFIX)/:' VERSION changelog
	xz -f package/$(PREFIX).tar

docs:
	cd doc/ && make

test:
	cd perl-Bootloader-testsuite/tests/test_interface/ && make

test_clean:
	cd perl-Bootloader-testsuite/tests/test_interface/ && make clean

clean:
	rm -rf .check .install .package package
	rm -f *~ */*~ */*/*~
