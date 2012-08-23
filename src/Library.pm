#! /usr/bin/perl -w
#
# Bootloader configuration accessing library
#

=head1 NAME

Bootloader::Library - library for accessing configuration of the bootloader


=head1 PREFACE

This package is the public API to configure bootloader settings


=head1 SYNOPSIS

C<< use Bootloader::Library; >>

C<< $obj_ref = Bootloader::Library->new (); >>

C<< $status = Bootloader::Library->SetLoaderType ($bootloader); >>

C<< $status = Bootloader::Library->DefineMountPoints (\%mountpoints); >>

C<< $status = Bootloader::Library->DefinePartitions (\@partitions); >>

C<< $status = Bootloader::Library->DefineMDArrays (\%md_arrays); >>

C<< $status = Bootloader::Library->ReadSettings (); >>

C<< $status = Bootloader::Library->WriteSettings (); >>

C<< $status = Bootloader::Library->ReadSettingsTmp ($tmp_dir); >>

C<< $status = Bootloader::Library->WriteSettingsTmp ($tmp_dir); >>

C<< $files_contents_ref = Bootloader::Library->GetFilesContents (); >>

C<< $status = Bootloader::Library->SetFilesContents (\%files_contents); >>

C<< $status = Bootloader::Library->UpdateBootloader ($avoid_init); >>

C<< $status = Bootloader::Library->InitializeBootloader (); >>

C<< $file_list_ref = Bootloader::Library->ListConfigurationFiles (); >>

C<< $settings_ref = Bootloader::Library->GetSettings (); >>

C<< $status Bootloader::Library->SetSettings ($settings_ref); >>

C<< $global_ref = Bootloader::Library->GetGlobalSettings (); >>

C<< $status = Bootloader::Library->SetGlobalSettings ($global_settings_ref); >>

C<< $sections_ref = Bootloader::Library->GetSections (); >>

C<< $status = Bootloader::Library->SetSections ($sections_ref); >>

C<< $device_map_ref = Bootloader::Library->GetDeviceMapping (); >>

C<< $status = Bootloader::Library->SetDeviceMapping ($device_map_ref); >>

C<< $unix_dev = Bootloader::Library->GrubDev2UnixDev ($grub_dev); >>

C<< $result = Bootloader::Library::DetectThinkpadMBR ($disk); >>

C<< $result = Bootloader::Library::WriteThinkpadMBR ($disk); >>

=head1 DESCRIPTION

=over 2

=cut


package Bootloader::Library 0.000;

use strict;

use Bootloader::Core;
use Bootloader::MBRTools;
use Bootloader::Path;

use base qw ( Bootloader::MBRTools Bootloader::Logger );

our $VERSION;

my $instances = 0;
my $global_id;

=item
C<< $obj_ref = Bootloader::Library->new (); >>

Creates an instance of the Bootloader::Library class.

=cut
sub new
{
  my $self = shift;

  my $lib = {};
  bless ($lib);

  my ($c0, $c1, $c2);

  $c0 = (caller(0))[0];

  my $idx = 0;
  while($c1 = (caller($idx))[1]) { $c2 = $c1; $idx++ }

  ($c1 = $c2) =~ s#.*/##;

  my $name = 'xxx';

  if($c1 eq 'Bootloader_API.pm') {
    $name = 'yast';
  }
  elsif($c1 eq 'update-bootloader') {
    $name = 'pbl';
  }
  elsif($c0 eq 'Bootloader::Tools') {
    $name = 'libpbl';
  }

  $global_id = $name . sprintf("-%04d.", int rand 10000) unless defined $global_id;
  $lib->{session_id} = $global_id . ++$instances;

  my $l = "$lib->{session_id} = $c2 (via $c0), version = $VERSION, chroot = " . readlink "/proc/self/root";

  $lib->StartLog();

  $lib->milestone($l);

  return $lib;
}

=item
C<< $status = Bootloader::Library->SetLoaderType($bootloader); >>

Initializes the library for the particular bootloader.
Takes the name of the bootloader as parameter.
Returns undef on fail, defined nonzero value otherwise.

EXAMPLE:

  my $status = Bootloader::Library->SetLoaderType ("lilo");
  if (! defined ($status))
  {
    die "Error occurred while initalizing for LILO";
  }

=cut

sub SetLoaderType
{
  my $self = shift;
  my $bootloader = shift;
  my $arch = shift;

  my $loader = exists $self->{loader} ? $self->{loader} : undef;

  if($bootloader eq "grub") {
    require Bootloader::Core::GRUB;
    $loader = Bootloader::Core::GRUB->new($self, $loader);
  }
  elsif($bootloader eq "grub2") {
    require Bootloader::Core::GRUB2;
    $loader = Bootloader::Core::GRUB2->new($self, $loader);
  }
  elsif($bootloader eq "grub2-efi") {
    require Bootloader::Core::GRUB2EFI;
    $loader = Bootloader::Core::GRUB2EFI->new($self, $loader);
  }
  elsif($bootloader eq "lilo") {
    require Bootloader::Core::LILO;
    $loader = Bootloader::Core::LILO->new($self, $loader);
  }
  elsif($bootloader eq "elilo") {
    require Bootloader::Core::ELILO;
    unless (defined $arch) {
      $self->warning("Missing arch for elilo, using ia64.");
      $arch = "ia64";
    }
    $loader = Bootloader::Core::ELILO->new($self, $loader, $arch);
  }
  elsif($bootloader eq "zipl") {
    require Bootloader::Core::ZIPL;
    $loader = Bootloader::Core::ZIPL->new($self, $loader);
  }
  elsif($bootloader eq "ppc") {
    require Bootloader::Core::PowerLILO;
    unless (defined $arch) {
      $self->warning("Missing subarch for powerlilo, using chrp.");
      $arch = "chrp";
    }
    $loader = Bootloader::Core::PowerLILO->new($self, $loader, $arch);
  }
  else {
    $self->error("Initializing for unknown bootloader $bootloader, fallback to none") if $bootloader ne "none";

    require Bootloader::Core::NONE;
    $loader = Bootloader::Core::NONE->new ($self, $loader);
  }

  $self->{loader} = $loader;
  $self->milestone("loader = $bootloader");

  return 1;
}

=item
C<< $status = Bootloader::Library->DefineMountPoints (\%mountpoints); >>

Defines mount points in the system so that the library
does not need to probe them itself when needed.
Parameter (mountpoints) is a hash reference (key is mountpoint,
value device).
Returns undef on fail, defined nonzero value otherwise.

EXAMPLE:

  my $mp = {
    "/" => "/dev/hda3",
    "/boot" => "/dev/hda1",
  }
  Bootloader::Library->DefineMountPoints ($mp);

=cut

sub DefineMountPoints {
    my $self = shift;
    my $mountpoints_ref = shift;

    my $loader = $self->{"loader"};
    return undef unless defined $loader;

    while ((my $mp, my $dev) = each (%{$mountpoints_ref}))
    {
	$self->milestone ("Mount point: $mp ; Device: $dev");
    }
    $loader->{"mountpoints"} = $mountpoints_ref;
    return 1;
}

sub GetMountPoints {
    my $self = shift;

    my $loader = $self->{"loader"};
    $self->milestone ("TRACE");
    return $loader->{"mountpoints"};
}

=item
C<< $status = Bootloader::Library->DefinePartitions (\@partitions); >>

Defines the information about partitions - what disk a partition belongs
to and the number of the partition
Parameter (partitions) is a list, one entry per partition, each entry
is a 3-item list, containing the device of the partition, the device of
the disk the partition belongs to, and the number of the partition (first is 1).
Returns undef on fail, defined nonzero value otherwise.

EXAMPLE:

  my $part = [
    [ "/dev/hda1", "/dev/hda", 1],
    [ "/dev/hda3", "/dev/hda", 3]
  ];
  Bootloader::Library->DefinePartitions ($part);

=cut

sub DefinePartitions {
    my $self = shift;
    my $partitions_ref = shift;

    my $loader = $self->{"loader"};
    return undef unless defined $loader;

    foreach my $part_ref (@{$partitions_ref})
    {
	my ($part, $disk, $num, @part_info ) = @{$part_ref};
	$self->milestone ("Partition: $part ; " .
			  "Disk: $disk ; Number: $num ; Info: " .
			  join(", ", map { "$_"; } @part_info) );
    }
    $loader->{"partitions"} = $partitions_ref;
    return 1;
}

=item
C<< $status = Bootloader::Library->DefineMDArrays (\%md_arrays); >>

This interface is broken by design and its use is deprecated!!
We only need information about mirrored devices (RAID1) and only GRUB uses
that hack.

Defines the information about MD RAID arrays (what array is built
by what disks).
As parameter, it takes a reference to a map of all MD devices, where
key is the MD device name, and value a reference to a list of its members.
Returns undef on fail, defined nonzero value otherwise.

EXAMPLE:

  my $md = {
    "/dev/md0" => ["/dev/hda1", "/dev/hdc1"],
    "/dev/md1" => ["/dev/hda2", "/dev/hdc2"],
  };
  Bootloader::Library->DefineMDArrays ($md);

=cut

sub DefineMDArrays {
    my $self = shift;
    my $md_arrays_ref = shift;

    my $loader = $self->{"loader"};
    return undef unless defined $loader;

    while ((my $md, my $members_ref) = each (%{$md_arrays_ref}))
    {
	my $members = join ", ", @{$members_ref};
	$self->milestone ("MD Array: $md ; Members: $members");
    }
    $loader->{"md_arrays"} = $md_arrays_ref;
    return 1;
}

=item
C<< $status = Bootloader::Library->DefineMultipath (\%multipath); >>

Define hardware information about multipath device.
We only need information to write to device map real device, because created multipath device doesn't have geometry and GRUB doesn't work.

As parameter, it takes a reference to a map of all multipath devices, where
key is the physical value (/dev/sda), and value a multipath device(/dev/mapper/...).
Returns undef on fail, defined nonzero value otherwise.

EXAMPLE:

  my $mp = {
    "/dev/sda" => "/dev/mapper/little_mapper",
    "/dev/sdb" => "/dev/mapper/little_mapper",
  };
  Bootloader::Library->DefineMultipath ($mp);

=cut

sub DefineMultipath {
    my $self = shift;
    my $mp_ref = shift;

    my $loader = $self->{"loader"};
    return undef unless defined $loader;

    while ((my $phys, my $mp) = each (%{$mp_ref}))
    {
	$self->milestone ("Real device: $phys ;  multipath $mp");
    }
    $loader->{"multipath"} = $mp_ref;
    return 1;
}

=item
C<< $status = Bootloader::Library->DefineMultipath (\%multipath); >>

Define udev mapping of devices.
We only need information for GRUB to translate udev device to kernel and then to grub device.

As parameter, it takes a reference to a map of all udev names to correspond kernel names.
Returns undef on fail, defined nonzero value otherwise.

EXAMPLE:

  my $mp = {
    "/dev/disks/by-id/longhorribleid" => "/dev/sda",
    "/dev/disks/by-id/longhorribleid-part1" => "/dev/sda1",
  };
  Bootloader::Library->DefineUdevMapping ($mp);

=cut

sub DefineUdevMapping($) {
    my $self = shift;
    my $map_ref = shift;

    my $loader = $self->{loader};
    return undef unless defined $loader;

    while ((my $phys, my $mp) = each (%{$map_ref}))
    {
	$self->milestone ("Udev device: ".($phys||"")." ;  kernel: ".($mp||"")."");
    }

  $loader->{udevmap} = $map_ref;

  return 1;
}


=item
C<< $status = Bootloader::Library->ReadSettings (); >>

Reads the settings from the system
Returns undef on fail, defined nonzero value otherwise.

EXAMPLE:

  my $status = Bootloader::Library->ReadSettings ();
  if (! defined ($status))
  {
    die "Error occurred while reading the settings";
  }

=cut

sub ReadSettings {
    my $self = shift;
    my $avoid_reading_device_map = shift;

    my $loader = $self->{"loader"};
    return undef unless defined $loader;

    $self->milestone( "TRACE" );
    my $files_ref = $loader->ReadFiles ($loader->ListFiles ());
    if (! defined ($files_ref))
    {
	return undef;
    }
    $loader->ParseLines ($files_ref, $avoid_reading_device_map);
    return 1;
}

=item
C<< $status = Bootloader::Library->WriteSettings (); >>

Writes the settings to the system. Does not activate the bootloader
or the written settings, InitializeBootloader or UpdateBootloader functions
must be used for it.
Returns undef on fail, defined nonzero value otherwise.

EXAMPLE:

  my $status = Bootloader::Library->WriteSettings ();
  if (! defined ($status))
  {
    die "Error occurred while writing the settings";
  }

=cut

sub WriteSettings {
    my $self = shift;
    my $menu_only = shift;

    my $loader = $self->{"loader"};
    return undef unless defined $loader;

    $self->milestone("TRACE menu_only:". ($menu_only || "undefined"));
    $loader->{"resolve_symlinks"} = 1;
    my $new_lines_ref = $loader->CreateLines ();
    if (! defined ($new_lines_ref))
    {
	return undef;
    }
    return $loader->WriteFiles ($new_lines_ref, ".new", $menu_only);
}

=item
C<< $status = Bootloader::Library->ReadSettingsTmp ($tmp_dir); >>

Reads the settings from the 
Returns undef on fail, defined nonzero value otherwise.

EXAMPLE:

  my $status = Bootloader::Library->ReadSettingsTmp ("/tmp");
  if (! defined ($status))
  {
    die "Error occurred while reading the settings";
  }

=cut

sub ReadSettingsTmp {
    my $self = shift;
    my $tmp_dir = shift;

    my $loader = $self->{"loader"};
    return undef unless defined $loader;

    $self->milestone("TRACE tmp_dir $tmp_dir ");

    my @files = @{$loader->ListFiles ()};
    my %filenames = ();
    @files = map {
	my $f = $_;
	my $tf = join ('_', split ('/', $f));
	$tf = "$tmp_dir/$tf";
	$filenames{$f} = $tf;
	$tf;
    } @files;
    my $files_ref = $loader->ReadFiles (\@files);
    if (! defined ($files_ref))
    {
	return undef;
    }
    my %files = ();
    while ((my $fn, my $tfn) = each (%filenames))
    {
	$files{$fn} = $files_ref->{$tfn};
    }
    return $loader->ParseLines (\%files);
}

=item
C<< $status = Bootloader::Library->WriteSettingsTmp ($tmp_dir); >>

Writes the settings to temporary directory. Slashes in the
filename are replaced with underscores.
Returns undef on fail, defined nonzero value otherwise.

EXAMPLE:

  my $status = Bootloader::Library->WriteSettingsTmp ("/tmp");
  if (! defined ($status))
  {
    die "Error occurred while writing the settings";
  }

=cut

sub WriteSettingsTmp {
    my $self = shift;
    my $tmp_dir = shift;

    my $loader = $self->{"loader"};
    return undef unless defined $loader;

    $self->milestone("TRACE tmp_dir $tmp_dir ");

    my $new_lines_ref = $loader->CreateLines ();
    if (! defined ($new_lines_ref))
    {
	return undef;
    }
    my %new_lines = ();
    while ((my $fn, my $cont) = each (%{$new_lines_ref}))
    {
	$fn = join ('_', split ('/', $fn));
	$fn = "$tmp_dir/$fn";
	$new_lines{$fn} = $cont;
    }
    return $loader->WriteFiles (\%new_lines);
}

=item
C<< $files_contents_ref = Bootloader::Library->GetFilesContents (); >>

Gets the future contents of all bootloader configuration files.
Returns undef on fail, hash where key is file name and value its
contents as value on success.

EXAMPLE:

  my $files_contents_ref = Bootloader::Library->GetFilesContents ();
  if (! defined ($files_contents_ref))
  {
    die "Cannot get the contents of the configuration files"
  }
  my $lilo_conf = $files_contents_ref->{"/etc/lilo.conf"};
  print "$lilo.conf contents: \n$lilo_conf\n";

=cut

sub GetFilesContents {
    my $self = shift;

    my $loader = $self->{"loader"};

    if (! defined $loader or $loader eq "none") {
	return undef;
    }
    $self->milestone("TRACE ");

    $loader->{"resolve_symlinks"} = 0;
    my $new_lines_ref = $loader->CreateLines ();
    if (! defined ($new_lines_ref))
    {
	$self->error ("Library::GetFileContents: Error while getting files contents occurred");
	return undef;
    }
    my %files = ();
    while ((my $fn, my $lines_ref) = each (%{$new_lines_ref}))
    {
	$files{$fn} = join "\n", @{$lines_ref};
	$files{$fn} .= "\n";
    }
    return \%files;
}

=item
C<< $status = Bootloader::Library->SetFilesContents (\%files_contents); >>

Sets the contents of all configuration files (eg. from editor)

$status = Bootloader::Library->SetFilesContents (\%files_contents);

=cut

sub SetFilesContents {
    my $self = shift;
    my $files_ref = shift;

    my $loader = $self->{"loader"};
    return undef unless defined $loader;

    $self->milestone("TRACE ");

    my %lines = ();
    while ((my $fn, my $contents) = each (%{$files_ref}))
    {
	my @lines = split /\n/, $contents;
	$lines{$fn} = \@lines;
    }
    $loader->ParseLines (\%lines);
    return 1;
}

=item
C<< $status = Bootloader::Library->UpdateBootloader ($avoid_init); >>

Really updates the bootloader configuration after writing the settings.
If initialization is needed to make the settings active, but not intended
(because it will be done later), set $avoid_init to 1. It makes no efect eg.
for GRUB, but prevents from calling /sbin/lilo in case of LILO
Returns undef on fail, defined nonzero value otherwise

EXAMPLE:

  my $status = Bootloader::Library->UpdateBootloader (0);
  if (! defined ($status))
  {
    die "Connot update the bootloader configuration";
  }

=cut


sub UpdateBootloader
{
  my $self = shift;
  my $avoid_init = shift;

  my $loader = $self->{"loader"};
  return undef unless defined $loader;

  $self->milestone("avoid_init = " . ($avoid_init || ""));

  return $loader->UpdateBootloader($avoid_init);
}


=item
C<< $status = Bootloader::Library->InitializeBootloader (); >>

Initializes the firmware to boot the bootloader
Returns undef on fail, defined nonzero value otherwise

EXAMPLE:

  my $status = Bootloader::Library->InitializeBootloader ();
  if (! defined ($status))
  {
    die "Cannot initialize the bootloader";
  }

=cut

sub InitializeBootloader {
    my $self = shift;

    my $loader = $self->{"loader"};
    return undef unless defined $loader;

    $self->milestone( "TRACE");

    return $loader->InitializeBootloader ();
}

=item
C<< $files_ref = Bootloader::Library->ListConfigurationFiles (); >>

Returns the list of the configuration files of the bootloader
Returns undef on fail

EXAMPLE:

  my $files_ref = Bootloader::Library->ListConfigurationFiles ();
  if (! defined ($files_ref))
  {
    die "Cannot list configuration files";
  }
  foreach my $fn (@{$files_ref})
  {
    system ("cp $fn $fn.backup");
  }

=cut

sub ListConfigurationFiles {
    my $self = shift;

    my $loader = $self->{"loader"};
    return undef unless defined $loader;

    $self->milestone( "TRACE");

    return $loader->ListFiles ();
}

=item
C<< $sections_ref = Bootloader::Library->GetSettings (); >>

Returns the complete settings of the bootloader.
Returns undef on fail.

EXAMPLE:

  see eg. GetSections function definition

=cut

sub GetSettings {
    my $self = shift;

    my $loader = $self->{"loader"};
    return undef unless defined $loader;

    $self->milestone( "TRACE");
    return $loader->GetSettings ();
}

=item
C<< $status = Bootloader::Library->SetSettings (); >>

Returns the complete settings of the bootloader.
Returns undef on fail.

EXAMPLE:

  see eg. GetSections function definition

=cut

sub SetSettings {
    my $self = shift;
    my $settings_ref = shift;

    my $loader = $self->{"loader"};
    return undef unless defined $loader;

    $self->milestone("TRACE");

    return $loader->SetSettings ($settings_ref);
}

# wrappers for easier use

=item
C<< $sections_ref = Bootloader::Library->GetSections (); >>

Gets the sections of the bootloader. See section description above. TODO
Returns undef on fail.

EXAMPLE:

  my $sections_ref = Bootloader::Library->GetSections ();
  if (! defined ($sections_ref))
  {
    die "Getting sections failed";
  }
  my @sect_names = map {
    $_->{"name"};
  } @{$sections_ref};
  my $list = join ", " @sect_names;
  print "Sections: $list";

=cut

# return empty array if none were read, not undef
sub GetSections {
    my $self = shift;

    my $settings_ref = $self->GetSettings ();
    if (! defined ($settings_ref))
    {
	return [];
    }
    return $settings_ref->{"sections"} || [];
}

=item
C<< $global_ref = Bootloader::Library->GetGlobalSettings (); >>

Gets the global settings of the bootloader. See the example map above TODO
Returns undef on fail.

EXAMPLE:

  my $global_ref = Bootloader::Library->GetGlobalSettings ();
  if (! defined ($global_ref))
  {
    die "Getting global data failed";
  }
  my $default = $global_ref->{"default"};
  print "Default section: $default";

=cut

sub GetGlobalSettings {
    my $self = shift;

    my $settings_ref = $self->GetSettings ();
    if (! defined ($settings_ref))
    {
	return undef;
    }

    # copy the hash and return the ref to copy
    my %globals=%{$settings_ref->{"global"}|| {}};

    return \%globals;
}

=item
C<< $device_map_ref = Bootloader::Library->GetDeviceMapping (); >>

Gets the device mapping between Linux and firmware.
Returns undef on fail.

EXAMPLE:

  $device_map_ref = Bootloader::Library->GetDeviceMapping ();
  if (! defined ($device_map_ref))
  {
    die "Getting device mapping failed";
  }
  my $hda = $device_map_ref->{"/dev/hda"};
  print "/dev/hda is $hda";

=cut

sub GetDeviceMapping {
    my $self = shift;

    my $settings_ref = $self->GetSettings ();
    if (! defined ($settings_ref))
    {
	return undef;
    }
    return $settings_ref->{"device_map"};
}

=item
C<< $status = Bootloader::Library->SetSections (); >>

Sets the sections of the bootloader. Sections have the same format
as return value of GetSections ().
Returns undef on fail, defined nonzero value on success.

EXAMPLE:

  my $sections_ref = Bootloader::Library->GetSections ();
  if (! defined ($sections_ref))
  {
    die "Getting sections failed";
  }
  my @sections = @{$sections_ref};
  pop @sections;
  my $ret = Bootloader::Library->SetSections (\@sections);
  if (! defined ($ret))
  {
    print ("Setting sections failed");
  }

=cut

sub SetSections {
    my $self = shift;
    my $sections_ref = shift;

    my %settings = (
	"sections" => $sections_ref
    );
    return $self->SetSettings (\%settings)

}

=item
C<< $status = Bootloader::Library->SetGlobalSettings (); >>

Sets the global settings of the bootloader. The argument has the same format
as the return value of GetGlobalSettings ().
Returns undef on fail, defined nonzero value on success.

EXAMPLE:

  my $global_ref = Bootloader::Library->GetGlobalSettings ();
  if (! defined ($global_ref))
  {
    die "Getting global data failed";
  }
  $global_ref->{"default"} = "linux";
  my $ret = Bootloader::Library->SetGlobalSettings ($global_ref);
  if (! defined ($ret))
  {
    print ("Setting global options failed.");
  }

=cut
sub SetGlobalSettings {
    my $self = shift;
    my $global_ref = shift;

    my %settings = (
	"global" => $global_ref
    );
    return $self->SetSettings (\%settings)
}

=item
C<< $status = Bootloader::Library->SetDeviceMapping (); >>

Sets the device mapping between Linux device and firmware identification.
Returns undef on fail, defined nonzero value on success.

EXAMPLE:

  $device_map_ref = Bootloader::Library->GetDeviceMapping ();
  if (! defined ($device_map_ref))
  {
    die "Getting device mapping failed";
  }
  $device_map_ref->{"/dev/hda"} = "(hd0)";
  my $ret = Bootloader::Library->SetDeviceMapping ($device_map_ref);
  if (! defined ($ret))
  {
    print ("Setting global options failed.");
  }

=cut
sub SetDeviceMapping {
    my $self = shift;
    my $device_mapping_ref = shift;

    my %settings = (
	"device_map" => $device_mapping_ref
    );
    return $self->SetSettings (\%settings)
}

=item
C<< $unix_dev = Bootloader::Core::GRUB->GrubDev2UnixDev ($grub_dev); >>

Translates the GRUB device (eg. '(hd0,0)') to UNIX device (eg. '/dev/hda1').
As argument takes the GRUB device, returns the UNIX device (both strings).
Wrapper function to be able to use this grub function in Tools.pm.

=cut

# string GrubDev2UnixDev (string grub_dev)
sub GrubDev2UnixDev {
    my $self = shift;
    my $grub_dev = shift;
    my $loader = $self->{loader} || return undef;

    $self->milestone("grub_dev: $grub_dev");

    my $unix_dev = $loader->GrubDev2UnixDev ($grub_dev);

    return $unix_dev;
}

=item
C<< ($dev,$path) = Bootloader::Library->SplitPath ($path); >>

Split unix path to device and relative path on this device.

=cut

# (string,string) SplitPath (string path)
sub SplitPath {
    my $self = shift;
    my $opath = shift;
    my $loader = $self->{loader} || return undef;

    my @ret = $loader->SplitDevPath ($opath);

    if (scalar (@ret) == 2){
        $self->milestone( "arg:: $opath result dev: ".($ret[0]||"")." result path: ".($ret[1]||"") );
    }else{
        $self->milestone( "arg:: $opath result undef");
    }

    return @ret;
}

=item
C<< $result = Bootloader::Library::DetectThinkpadMBR ($disk); >>

Try detect on disk if contains ThinkpadMBR. Return true if detected.

=cut

#  DetectThinkpadMBR (string disk)
sub DetectThinkpadMBR
{
  my $self = shift;
  my $disk = shift;
  my $res = $self->IsThinkpadMBR($disk);
  $self->milestone("on $disk result $res" );
  return $res;
}

=item
C<< $result = Bootloader::Library::WriteThinkpadMBR ($disk); >>

Write generic mbr to disk on thinkpad. Return undef if fail.

=cut

#  WriteThinkpadMBR (string disk)
sub WriteThinkpadMBR
{
   my $self = shift;
   my $disk = shift;
   my $res = $self->PatchThinkpadMBR($disk);
   $self->milestone("on $disk result $res" );
   return $res;
}

=item
C<< $result = Bootloader::Library::ExamineMBR ($disk); >>

Detects what code is in MBR of device. Return string or undef if fail.
Possible string is:
  generic -> generic MBR
  grub -> Grub MBR
  lilo -> lilo stage1
  windows -> windows
  vista -> windows vista (has another mbr)
  thinkpad -> thinkpad custom mbr
  unknown -> unknown code
  invalid -> code which cannot boot

=cut

#  ExamineMBR (string disk)
sub ExamineMBR()
{
  my $self = shift;
  my $disk = shift;
  my $res = $self->examineMBR($disk);
  $self->milestone("on $disk result ".($res||"nil"));
  
  return $res;
}

sub CountGRUBPassword{
  my $self = shift;
  my $pass = shift;
  return $pass if $pass =~ m/--md5/; #check if password is already hashed
  my $res = qx{echo "md5crypt \
  $pass" | grub --batch | grep Encrypted };
  $res =~ s/Encrypted:\s+(.*)$/$1/;
  $self->milestone("result $res" );
  return undef unless $res =~ m/^\$1\$.*\$.*$/;
  return "--md5 $res";
}

sub UpdateSerialConsole{
  my $self = shift;
  my $append = shift;
  my $console = shift;
  my $ret = $append;

  $console = "console=$console" unless ($console eq "");
  if ($ret =~ m/console=ttyS(\d+)(,(\w+))?/){
    $ret =~ s/console=ttyS(\d+)(,(\w+))?/$console/ ;
  } elsif ($console ne ""){
    $ret = "$append $console";
  }

  $self->milestone("append $append console $console res $ret" );

  return $ret;
}

1;

#
# Local variables:
#     mode: perl
#     mode: font-lock
#     mode: auto-fill
#     fill-column: 78
# End:
#
