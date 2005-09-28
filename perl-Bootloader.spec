#
# spec file for package perl-Bootloader
#
# Copyright (c) 2005 SUSE LINUX Products GmbH, Nuernberg, Germany.
# This file and all modifications and additions to the pristine
# package are under the same license as the package itself.
#
# Please submit bugfixes or comments via http://www.suse.de/feedback/
#

# neededforbuild  

BuildRequires: aaa_base acl attr bash bind-utils bison bzip2 coreutils cpio cpp cracklib cvs cyrus-sasl db devs diffutils e2fsprogs file filesystem fillup findutils flex gawk gdbm-devel gettext-devel glibc glibc-devel glibc-locale gpm grep groff gzip info insserv klogd less libacl libattr libcom_err libgcc libnscd libselinux libstdc++ libxcrypt libzio m4 make man mktemp module-init-tools ncurses ncurses-devel net-tools netcfg openldap2-client openssl pam pam-modules patch permissions popt procinfo procps psmisc pwdutils rcs readline sed strace sysvinit tar tcpd texinfo timezone unzip util-linux vim zlib zlib-devel autoconf automake binutils gcc gdbm gettext libtool perl rpm

Name:         perl-Bootloader
Version:      0.2
Release:      38
Requires:     perl = %{perl_version}
Autoreqprov:  on
Group:        System/Boot
License:      GPL
Summary:      Library for Configuring Boot Loaders
Source:       perl-Bootloader-%{version}.tar.bz2
Source1:      update-bootloader
BuildRoot:    %{_tmppath}/%{name}-%{version}-build

%description
Perl modules for configuring various boot loaders.



Authors:
--------
    Jiri Srain <jsrain@suse.cz>

%prep
#setup -n Bootloader-%{version} -q
%setup -q

%build
perl Makefile.PL
make

%install
make DESTDIR=$RPM_BUILD_ROOT install_vendor
%perl_process_packlist
mkdir -p $RPM_BUILD_ROOT/sbin
install -m 755 %_sourcedir/update-bootloader $RPM_BUILD_ROOT/sbin

%files
%defattr(-, root, root)
%doc COPYING
%doc %{_mandir}/man?/*
%{perl_vendorarch}/auto/Bootloader
%{perl_vendorlib}/Bootloader
/var/adm/perl-modules/perl-Bootloader
/sbin/update-bootloader

%changelog -n perl-Bootloader
* Tue Sep 27 2005 - jsrain@suse.cz
- fixed quoting of options in lilo.conf (#117642)
* Tue Aug 30 2005 - jsrain@suse.cz
- added ELILO support
* Mon Aug 29 2005 - aj@suse.de
- Do not package .orig file.
* Mon Aug 29 2005 - jsrain@suse.cz
- added support for PPC loader
- fixed rootnoverify handling for GRUB (#113683)
* Fri Aug 19 2005 - jsrain@suse.cz
- fixed kernel/initrd specification in merged sections (#105660)
* Thu Aug 18 2005 - jsrain@suse.cz
- fixed order of lines in XEN sections (#105171)
* Wed Aug 17 2005 - jsrain@suse.cz
- fixed installing GRUB if /boot is on MD array (104908)
- fixed displayed paths in configuration file editor during
  bootloader installation (105140)
* Tue Aug 09 2005 - jsrain@suse.cz
- fixed writing chainloader sections for GRUB (#102703)
* Wed Aug 03 2005 - jsrain@suse.cz
- fixed crashes if using on unsupported bootloader
* Tue Aug 02 2005 - jsrain@suse.cz
- fixed crash in some cases
* Wed Jul 27 2005 - jsrain@suse.cz
- added possibility to set password
* Tue Jul 26 2005 - jsrain@suse.cz
- fixed typo in function name
* Thu Jul 21 2005 - jsrain@suse.cz
- fixed GRUB <-> UNIX path translations to make menus merging work
* Thu Jun 30 2005 - jsrain@suse.cz
- fixed handling of wildcard sections
- fixed determining whether bootloader initialization succeeded
  for LILO and ZIPL
* Wed Jun 29 2005 - jsrain@suse.cz
- fixed checking of labels for LILO
- fixed creating global sections during distro installation
* Thu Jun 02 2005 - jsrain@suse.cz
- use rootnoverify instead of root in chainloader sections (#84575)
* Wed Jun 01 2005 - jsrain@suse.cz
- merged last patch to main tarball
- fixed cripplink lilo.conf if detailed disk information is
  present (#81526)
* Tue May 31 2005 - uli@suse.de
- fixed syntax error
* Mon May 23 2005 - uli@suse.de
- shift s390* ramdisk up to 16MB so it will not be overwritten
  on machines with many CPUs (bug #63045)
* Fri Apr 15 2005 - jsrain@suse.cz
- added GRUB support for XEN
* Wed Apr 06 2005 - jsrain@suse.cz
- removed code duplication between generic and S/390 specific code
* Wed Mar 16 2005 - jsrain@suse.cz
- added license to documentation
* Mon Mar 14 2005 - jsrain@suse.cz
- limit LILO section name length (#71830)
- fixed setting default entry when GRUB section added (#71217)
- make bootloader files not public readable (#72385)
* Tue Mar 08 2005 - jsrain@suse.de
- fixed creating zipl.conf during installation
- added missing documentation in source code
* Mon Mar 07 2005 - jsrain@suse.cz
- fixed reading zip.conf (uli)
* Wed Mar 02 2005 - jsrain@suse.cz
- fixed error message written on terminal while finishing
  installation
* Fri Feb 25 2005 - jsrain@suse.cz
- fixed initialization when device specified via UUID or LABEL
  in /etc/fstab (#66623)
* Fri Feb 25 2005 - agruen@suse.de
- Add --default option to update-bootloader script.
* Wed Feb 23 2005 - ihno@suse.de
- added s390/s390x specific part (zipl)
* Thu Feb 17 2005 - jsrain@suse.cz
- avoid calling hwinfo when detecting partitioning (#50615)
* Wed Feb 16 2005 - schwab@suse.de
- Don't remove BuildRoot in %%install.
* Wed Feb 16 2005 - jsrain@suse.cz
- added support for embedding stage1.5 of GRUB
* Mon Feb 14 2005 - jsrain@suse.cz
- fixed parameters of added kernel if the comment saying which
  kernel comes from initial installation is missing (#50708)
- fixed errors if removing entry for unexistent kernel (#50708)
* Mon Feb 07 2005 - jsrain@suse.cz
- fixed last patch (more entries can be removed with one kernel)
- write only modified configuration files and modified sections
- fixed splitting path to mountpoint + path relative to the mp
* Fri Feb 04 2005 - agruen@suse.de
- Set the new default boot entry to the first entry in the boot
  menu when removing the current default entry.
- A few minor code cleanups.
* Fri Feb 04 2005 - jsrain@suse.de
- fixed possible corruption of data files
- fixed counting and removing sections with specified kernel
* Thu Feb 03 2005 - agruen@suse.de
- Rename the man pages so that they include the Bootloader::
  prefix.
- Fix a bug in Bootloader::Core::SplitDevPath.
- Add update-bootloader frontend script.
* Mon Jan 31 2005 - jsrain@suse.cz
- fixed several bugs
* Tue Jan 25 2005 - jsrain@suse.cz
- fixed GRUB to work properly with MD arrays
- fixed handlink of symlinks
- fixed root device when creating a new section
- implemented logging support when running without YaST
- fixed handling of GRUB path prefix
* Mon Jan 24 2005 - jsrain@suse.cz
- implemented logging mechanism
- several bugfixes
* Thu Jan 20 2005 - jsrain@suse.cz
- initial package
