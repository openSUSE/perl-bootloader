#
# spec file for package perl-Bootloader
#
# Copyright (c) 2023 SUSE LLC
#
# All modifications and additions to the file contributed by third parties
# remain the property of their copyright owners, unless otherwise agreed
# upon. The license for this file, and modifications and additions to the
# file, is the same license as for the pristine package itself (unless the
# license for the pristine package is not an Open Source License, in which
# case the license is the MIT License). An "Open Source License" is a
# license that conforms to the Open Source Definition (Version 1.9)
# published by the Open Source Initiative.

# Please submit bugfixes or comments via https://bugs.opensuse.org/
#


%if 0%{?usrmerged}
%define sbindir %{_sbindir}
%else
%define sbindir /sbin
%endif

%{!?_distconfdir:%global _distconfdir /etc}

Name:           perl-Bootloader
Version:        0.0
Release:        0
Requires:       coreutils
Requires:       perl-base = %{perl_version}
Summary:        Tool for boot loader configuration
License:        GPL-2.0-or-later
Group:          System/Boot
URL:            https://github.com/opensuse/perl-bootloader
Source:         %{name}-%{version}.tar.xz
BuildRoot:      %{_tmppath}/%{name}-%{version}-build
BuildRequires:  perl
#!BuildIgnore: mdadm e2fsprogs limal-bootloader

%description
Shell script wrapper for configuring various boot loaders.



Authors:
--------
    Jiri Srain <jsrain@suse.cz>
    Joachim Plack <jplack@suse.de>
    Alexander Osthof <aosthof@suse.de>
    Josef Reidinger <jreidinger@suse.cz>
    Steffen Winterfeldt <snwint@suse.com>

%package YAML
Requires:       %{name} = %{version}
Requires:       perl-Bootloader-legacy = %{version}
Requires:       perl-YAML-LibYAML
Summary:        YAML interface for perl-Bootloader
Group:          System/Boot

%description YAML
A command line interface to perl-Bootloader using YAML files for input and output.

%package legacy
Requires:       %{name} = %{version}
Requires:       perl-base = %{perl_version}
Recommends:     perl-gettext
Summary:        Legacy part of perl-Bootloader
Group:          System/Boot

%description legacy
The legacy part of perl-Bootloader (that is, the original perl-based library code).

%prep
%setup -q

%build

%install
make install DESTDIR=%{buildroot} SBINDIR=%{sbindir} ETCDIR=%{_distconfdir}
install -d -m 700 %{buildroot}/var/log/YaST2
touch %{buildroot}/var/log/pbl.log
%perl_process_packlist
#install only necessary files for specific architecture
%ifarch %ix86 x86_64
rm -f %{buildroot}/%{perl_vendorlib}/Bootloader/Core/{ZIPL*,PowerLILO*}
%endif
%ifarch ppc ppc64
rm -f %{buildroot}/%{perl_vendorlib}/Bootloader/Core/{ZIPL*,LILO*,ELILO*,GRUB.*}
%endif
%ifarch s390 s390x
rm -f %{buildroot}/%{perl_vendorlib}/Bootloader/Core/{*LILO*,GRUB.*,GRUB2EFI.*}
%endif

%post
echo -n >>/var/log/pbl.log
chmod 600 /var/log/pbl.log

%files
%defattr(-, root, root)
%license COPYING
%doc %{_mandir}/man8/*
%doc boot.readme
%{sbindir}/update-bootloader
%{sbindir}/pbl
/usr/lib/bootloader
%if "%{_distconfdir}" == "/etc"
%config(noreplace) %{_distconfdir}/logrotate.d/pbl
%else
%{_distconfdir}/logrotate.d/pbl
%endif
%ghost %attr(0600,root,root) /var/log/pbl.log

%files YAML
%defattr(-, root, root)
%{_sbindir}/pbl-yaml

%files legacy
%defattr(-, root, root)
%doc %{_mandir}/man3/*
%{perl_vendorarch}/auto/Bootloader
%{perl_vendorlib}/Bootloader
%dir %attr(0700,root,root) /var/log/YaST2

%changelog
