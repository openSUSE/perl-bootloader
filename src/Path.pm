#!/usr/bin/perl
#
# Set of path used in bootloader. Allows setting prefix via global variable
# $PERL_BOOTLOADER_TESTSUITE_PATH
#


package Bootloader::Path;

use strict;

sub Prefix {
  my $value = shift;
  return $ENV{PERL_BOOTLOADER_TESTSUITE_PATH} . $value if (defined($ENV{PERL_BOOTLOADER_TESTSUITE_PATH}));
  return $value;
}

sub Logname {
  my $value = "/var/log/YaST2/perl-BL-standalone-log";
  return Prefix($value);
}

sub Fstab {
  my $value = "/etc/fstab";
  return Prefix($value);
}

sub Blkid {
  my $value = "/sbin/blkid";
  return Prefix($value);
}

sub Sysconfig {
  my $value = "/etc/sysconfig/bootloader";
  return Prefix($value);
}

sub Grub_menulst {
  my $value = "/boot/grub/menu.lst";
  return Prefix($value);
}

sub Grub_devicemap {
  my $value = "/boot/grub/device.map";
  return Prefix($value);
}

sub Grub_grubconf {
  my $value = "/etc/grub.conf";
  return Prefix($value);
}

sub Grub_grub {
  my $value = "/usr/sbin/grub";
  return Prefix($value);
}

sub Elilo_conf {
  my $value = "/etc/elilo.conf";
  return Prefix($value);
}

sub Elilo_efi {
  my $value = "/boot/efi/efi/SuSE";
  return Prefix($value);
}

sub Elilo_elilo {
  my $value = "/sbin/elilo";
  return Prefix($value);
}

sub Lilo_lilo {
  my $value = "/sbin/lilo";
  return Prefix($value);
}

sub Lilo_conf {
  my $value = "/etc/lilo.conf";
  return Prefix($value);
}

sub Zipl_conf {
  my $value = "/etc/zipl.conf";
  return Prefix($value);
}

sub Zipl_zipl {
  my $value = "/sbin/zipl";
  return Prefix($value);
}

1;
