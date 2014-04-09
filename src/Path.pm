#!/usr/bin/perl
#
# Set of path used in bootloader. Allows setting prefix via global variable
# $PERL_BOOTLOADER_TESTSUITE_PATH
#

=head1 NAME

Bootloader::Path - abstraction of path constants


=head1 PREFACE

This package provides path for configuration files. It is used to enable testing on created chroot.
It is used only for internal purpose.

=head1 SYNOPSIS


C<< use Bootloader::Path; >>

C<< $path = Bootloader::Path::Prefix ($path); >>

C<< $path = Bootloader::Path::Logname(); >>

C<< $path = Bootloader::Path::Fstab(); >>

C<< $path = Bootloader::Path::Sysconfig(); >>

C<< $path = Bootloader::Path::Grub_menulst(); >>

C<< $path = Bootloader::Path::Grub_devicemap(); >>

C<< $path = Bootloader::Path::Grub_grubconf(); >>

C<< $path = Bootloader::Path::Grub_grub(); >>

C<< $path = Bootloader::Path::Elilo_conf(); >>

C<< $path = Bootloader::Path::Elilo_efi(); >>

C<< $path = Bootloader::Path::Elilo_elilo(); >>

C<< $path = Bootloader::Path::Lilo_lilo(); >>

C<< $path = Bootloader::Path::Lilo_conf(); >>

C<< $path = Bootloader::Path::Zipl_conf(); >>

C<< $path = Bootloader::Path::Zipl_zipl(); >>

C<< $path = Bootloader::Path::Grub2_devicemap(); >>

C<< $path = Bootloader::Path::Grub2_installdevice(); >>

=head1 DESCRIPTION

=over 2

=cut

package Bootloader::Path;

use strict;

=item
C<< $path = Bootloader::Path::Prefix ($); >>

Add to absolute path prefix. Only internal function.
Allways retuns correct value.

=cut

sub Prefix {
  my $value = shift;
  return $ENV{PERL_BOOTLOADER_TESTSUITE_PATH} . $value if (defined($ENV{PERL_BOOTLOADER_TESTSUITE_PATH}));
  return $value;
}

=item
C<< $path = Bootloader::Path::Logname(); >>

our logfile: /var/log/pbl.log

=cut

sub Logname {
  my $value = "/var/log/pbl.log";
  return Prefix($value);
}

=item
C<< $path = Bootloader::Path::LognameYaST(); >>

yast logfile: /var/log/YaST2/y2log

=cut

sub LognameYaST {
  my $value = "/var/log/YaST2/y2log";
  return Prefix($value);
}

=item
C<< $path = Bootloader::Path::BootCommandLogname(); >>

Gets logname path.

=cut

sub BootCommandLogname {
  my $value = "/var/log/YaST2/y2log_bootloader";
  return Prefix($value);
}

=item
C<< $path = Bootloader::Path::Fstab(); >>

Gets fstab path.

=cut

sub Fstab {
  my $value = "/etc/fstab";
  return Prefix($value);
}

=item
C<< $path = Bootloader::Path::Sysconfig(); >>

Gets path for bootloader sysconfig.

=cut

sub Sysconfig {
  my $value = "/etc/sysconfig/bootloader";
  return Prefix($value);
}

=item
C<< $path = Bootloader::Path::Grub_menulst(); >>

Gets path for grub configuration file menu.lst.

=cut

sub Grub_menulst {
  my $value = "/boot/grub/menu.lst";
  return Prefix($value);
}

=item
C<< $path = Bootloader::Path::Grub_devicemap(); >>

Gets path for grub configuration file device.map.

=cut

sub Grub_devicemap {
  my $value = "/boot/grub/device.map";
  return Prefix($value);
}

=item
C<< $path = Bootloader::Path::Grub_grubconf(); >>

Gets path for grub configuration file grub.conf
(this file contains commands for initialize bootloader).

=cut

sub Grub_grubconf {
  my $value = "/etc/grub.conf";
  return Prefix($value);
}

=item
C<< $path = Bootloader::Path::Grub_grub(); >>

Gets path for grub binary

=cut

sub Grub_grub {
  my $value = "/usr/sbin/grub";
  return Prefix($value);
}

=item
C<< $path = Bootloader::Path::Elilo_conf(); >>

Gets path of elilo configuration file.

=cut

sub Elilo_conf {
  my $value = "/etc/elilo.conf";
  return Prefix($value);
}

=item
C<< $path = Bootloader::Path::Elilo_efi(); >>

Gets path to efi directory.

=cut

sub Elilo_efi {
  my $value = "/boot/efi/efi/SuSE";
  return Prefix($value);
}

=item
C<< $path = Bootloader::Path::Elilo_elilo(); >>

Gets path to elilo binary.

=cut

sub Elilo_elilo {
  my $value = "/sbin/elilo";
  return Prefix($value);
}

=item
C<< $path = Bootloader::Path::Lilo_lilo(); >>

Gets path to lilo(or powerlilo) binary.

=cut

sub Lilo_lilo {
  my $value = "/sbin/lilo";
  return Prefix($value);
}

=item
C<< $path = Bootloader::Path::Lilo_conf(); >>

Gets path to lilo(or powerlilo) configuration file.

=cut

sub Lilo_conf {
  my $value = "/etc/lilo.conf";
  return Prefix($value);
}

=item
C<< $path = Bootloader::Path::Zipl_conf(); >>

Gets path to zipl configuration file.

=cut

sub Zipl_conf {
  my $value = "/etc/zipl.conf";
  return Prefix($value);
}

=item
C<< $path = Bootloader::Path::Zipl_zipl(); >>

Gets path to zipl binary.

=cut

sub Zipl_zipl {
  my $value = "/sbin/zipl";
  return Prefix($value);
}

=item
C<< $path = Bootloader::Path::Grub2_devicemap(); >>

Gets path for grub2 configuration file device.map.

=cut

sub Grub2_devicemap {
  my $value = "/boot/grub2/device.map";
  return Prefix($value);
}

=item
C<< $path = Bootloader::Path::Grub2_installdevice(); >>

Gets path for grub2 configuration file grub_installdevice.

=cut

sub Grub2_installdevice {
  my $value = "/etc/default/grub_installdevice";
  return Prefix($value);
}

=item
C<< $path = Bootloader::Path::Grub2_defaultconf(); >>

Gets path for grub configuration file grub
(this file contains commands for initialize bootloader).

=cut

sub Grub2_defaultconf {
  my $value = "/etc/default/grub";
  return Prefix($value);
}

=item
C<< $path = Bootloader::Path::Grub2_conf(); >>

Gets path for grub configuration file grub
(this file contains commands for initialize bootloader).

=cut

sub Grub2_conf {
  my $value = "/boot/grub2/grub.cfg";
  return Prefix($value);
}

1;
