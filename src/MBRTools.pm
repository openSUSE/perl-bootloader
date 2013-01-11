#!/usr/bin/perl -w
#
# Set of low level tools for mbr manipulation
#

=head1 NAME

Bootloader::MBRTools - set of low-level functions for mbr manipulation


=head1 PREFACE

This package contains a set of low-level functions for mbr manipulation.
Now it is only for testing purpose. Don't use it.

=head1 SYNOPSIS

C<< use Bootloader::MBRTools; >>

C<< $value = Bootloader::MBRTools::IsThinkpadMBR ($disk); >>

C<< $value = Bootloader::MBRTools::PatchThinkpadMBR ($disk); >>

=head1 DESCRIPTION

=over 2

=cut


package Bootloader::MBRTools;

use strict;

use Bootloader::Logger;

use base qw ( Exporter );

our @EXPORT = qw( IsThinkpadMBR PatchThinkpadMBR examineMBR );


sub IsThinkpadMBR()
{
  my $self = shift;

  my $disk = shift;
  my $mbr = qx{dd status=noxfer if=$disk bs=512 count=1 2>/dev/null | od -v -t x1 -};
  $mbr =~ s/\d{7}//g; #remove address
  $mbr =~ s/\n//g; #remove end lines
  $mbr =~ s/\s//g; #remove whitespace

  $self->milestone("checked mbr is: $mbr");

  my $first_segment = hex("0x".substr ($mbr, 4, 2));
  my $second_segment = hex("0x".substr ($mbr, 6, 2));

  my $ret = $first_segment >= 2;
  $ret &&= $first_segment <= hex("0x63");
  $ret &&= $second_segment >= 2;
  $ret &&= $second_segment <= hex("0x63");
  $ret &&= hex(substr($mbr,28,2)) == hex("0x4e");
  $ret &&= hex(substr($mbr,30,2)) == hex("0x50");

  return $ret;
}


# crc function
sub crc
{
  my $c = 0;
  local $_;

  $c ^= $_ for @{$_[0]};

  return $c;
}


sub PatchThinkpadMBR()
{
  my $self = shift;

  my $disk = shift;

  my $new_mbr = 
   "\x31\xc0\x8e\xd0\x66\xbc\x00\x7c\x00\x00\x8e\xc0\x8e\xd8\x89\xe6" .
   "\x66\xbf\x00\x06\x00\x00\x66\xb9\x00\x01\x00\x00\xf3\xa5\xea\x23" .
   "\x06\x00\x00\x80\xfa\x80\x7c\x05\x80\xfa\x87\x7e\x02\xb2\x80\x88" .
   "\x16\x49\x07\x66\xbf\xbe\x07\x00\x00\x31\xf6\x66\xb9\x04\x00\x00" .
   "\x00\x67\x80\x3f\x80\x75\x07\x85\xf6\x75\x0c\x66\x89\xfe\x83\xc7" .
   "\x10\xe2\xee\x85\xf6\x75\x0b\x66\xbe\x4a\x07\x00\x00\xe9\x8d\x00" .
   "\x00\x00\x8a\x16\x49\x07\x66\x31\xc9\x66\x31\xc0\xb4\x08\xcd\x13" .
   "\xc1\xea\x08\x42\x89\xc8\x83\xe0\x3f\x89\xcb\xc1\xe9\x08\x81\xe3" .
   "\xc0\x00\x00\x00\xc1\xe3\x02\x09\xd9\x41\xf7\xe2\x66\xf7\xe1\x8a" .
   "\x16\x49\x07\x66\x67\x8b\x5e\x08\x66\x39\xc3\x66\x7c\x63\x66\x56" .
   "\x52\x66\xbb\xaa\x55\x00\x00\xb4\x41\xcd\x13\x5a\x66\x5e\x72\x51" .
   "\x66\xb8\x55\xaa\x00\x00\x39\xc3\x75\x47\xf6\xc1\x01\x74\x42\x67" .
   "\x66\xc7\x06\x10\x00\x01\x00\x67\x66\xc7\x46\x04\x00\x7c\x00\x00" .
   "\x67\x66\xc7\x46\x0c\x00\x00\x00\x00\xb6\x05\x56\x52\xb4\x42\xcd" .
   "\x13\x5a\x5e\x73\x45\xfe\xce\x75\xf2\x66\xbe\x76\x07\x00\x00\xac" .
   "\x84\xc0\x74\x0a\xb4\x0e\xb3\x07\x56\xcd\x10\x5e\xeb\xf1\xfb\xeb" .
   "\xfd\x67\x8a\x76\x01\x67\x8b\x4e\x02\x66\xbf\x05\x00\x00\x00\x66" .
   "\xbb\x00\x7c\x00\x00\x66\xb8\x01\x02\x00\x00\x57\x52\x51\xcd\x13" .
   "\x59\x5a\x5f\x73\x05\x4f\x75\xe7\xeb\xbf\x66\xbe\x62\x07\x00\x00" .
   "\x67\xa1\xfe\x7d\x00\x00\x66\xbb\x55\xaa\x00\x00\x39\xc3\x75\xaf" .
   "\x8a\x16\x49\x07\xea\x00\x7c\x00\x00\x80\x49\x6e\x76\x61\x6c\x69" .
   "\x64\x20\x70\x61\x72\x74\x69\x74\x69\x6f\x6e\x20\x74\x61\x62\x6c" .
   "\x65\x00\x4e\x6f\x20\x6f\x70\x65\x72\x61\x74\x69\x6e\x67\x20\x73" .
   "\x79\x73\x74\x65\x6d\x00\x45\x72\x72\x6f\x72\x20\x6c\x6f\x61\x64" .
   "\x69\x6e\x67\x20\x6f\x70\x65\x72\x61\x74\x69\x6e\x67\x20\x73\x79" .
   "\x73\x74\x65\x6d\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" .
   "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" .
   "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00";

  open F,$disk;
  my $mbr_s;
  sysread F,$mbr_s,0x200;
  
  my @mbr = unpack "C512", $mbr_s;

  my $old_mbr_sec = $mbr[7];

  # read original mbr

  unless (seek F, ($old_mbr_sec - 1) << 9, 0)
  {
    $self->error("$disk $! \n");
    return 0;
  }

  my $old_mbr_s;
  sysread F, $old_mbr_s, 0x200;

  my @old_mbr = unpack "C512", $old_mbr_s;


  close F;


  # verify crc

  if($mbr[6] == 0) {
    $self->warning("$disk: orig mbr crc not checked");
  }
  else {
    unless (crc(\@old_mbr) == $mbr[6]){
      $self->error("$disk: orig mbr crc failure\n");
      return 0;
    }
  }


  # store new mbr & update crc

  substr($old_mbr_s, 0, length $new_mbr) = $new_mbr;

  @old_mbr = unpack "C512", $old_mbr_s;

  $mbr[6] = crc \@old_mbr;

  $mbr_s = pack "C512", @mbr;


  # write it

  open F, "+<$disk";
  syswrite F, $mbr_s, 0x200;
  seek F, ($old_mbr_sec - 1) << 9, 0;
  syswrite F, $old_mbr_s;
  close F;

  return 1;
}


sub examineMBR()
{
  my $self = shift;

  my $device = shift;
  my $MBR;

  $self->milestone("Examine MBR for device $device");

  return undef unless defined $device;

  unless (open(FD, "<" . $device)){
      $self->error("Examine MBR cannot open $device");
      return undef;
  }

  my $readed  = sysread(FD, $MBR, 512, 0);
  unless ($readed or $readed == 512){
      $self->error("Examine MBR cannot read 512 bytes from device $device");
      return undef;
  }

  close(FD);

  if (substr($MBR, 320, 126) =~
        m/invalid partition table.*no operating system/i) {
        $self->milestone("Examine MBR find Generic MBR");
        return "generic";
  }

  if (substr($MBR, 346, 100) =~
        m/GRUB .Geom.Hard Disk.Read. Error/) {
        $self->milestone("Examine MBR find Grub MBR");
        return "grub";
  }

  if (substr($MBR, 4, 20) =~
        m/LILO/) {
        $self->milestone("Examine MBR find lilo MBR");
        return "lilo";
  }

  if (substr($MBR, 12, 500) =~
        m/NTLDR is missing/) {
        $self->milestone("Examine MBR find windows non-vista MBR");
        return "windows";
  }

  if (substr($MBR, 0, 440) =~
        m/invalid partition table.*Error loading operating system/i) {
        $self->milestone("Examine MBR find windows Vista MBR");
        return "vista";
  }
  
  if ($self->IsThinkpadMBR($device)){
    $self->milestone("Examine MBR find thinkpad MBR");
    return "thinkpad";
  }

  return "unknown";
}


1;
