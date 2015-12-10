#!/usr/bin/perl -w
#
# Set of high-level bootloader configuration functions
#

=head1 NAME

Bootloader::Tools - set of high-level bootloader configuration functions


=head1 PREFACE

This package contains a set of high-level bootloader configuration functions

=head1 SYNOPSIS

C<< use Bootloader::Tools; >>

C<< $mp_ref = Bootloader::Tools::ReadMountPoints (); >>

C<< $part_ref = Bootloader::Tools::ReadPartitions (); >>

C<< Bootloader::Tools::GetDeviceMapping (); >>

C<< $numDM = Bootloader::Tools::DMRaidAvailable (); >>

C<< $part_ref = Bootloader::Tools::ReadDMRaidPartitions (); >>

C<< $part_ref = Bootloader::Tools::ReadDMRaidDisks (); >>

C<< Bootloader::Tools::IsDMRaidSlave ($kernel_disk); >>

C<< Bootloader::Tools::IsDMDevice($dev); >>

C<< $dm_dev = Bootloader::Udev2DMDev($udevdevice); >>

C<< $udev_dev = Bootloader::Tools::DMDev2Udev($dmdev); >>

C<< $majmin = Bootloader::Tools::DMDev2MajMin($dmdev); >>

C<< $majmin = Bootloader::Tools::Udev2MajMin($udev); >>

C<< $udev_dev = Bootloader::Tools::MajMin2Udev($majmin); >>

C<< $dm_dev = Bootloader::Tools::MajMin2DMDev($majmin); >>

C<< $md_ref = Bootloader::Tools::ReadRAID1Arrays (); >>

C<< $loader = Bootloader::Tools::GetBootloader (); >>

C<< $value = Bootloader::Tools::GetSysconfigValue (); >>

C<< Bootloader::Tools::InitLibrary (); >>

C<< Bootloader::Tools::CountImageSections ($image); >>

C<< Bootloader::Tools::RemoveImageSections ($image); >>

C<< Bootloader::Tools::GetSystemLanguage (); >>

C<< Bootloader::Tools::GetDefaultSection (); >>

C<< Bootloader::Tools::GetDefaultImage (); >>

C<< Bootloader::Tools::GetDefaultInitrd (); >>

C<< Bootloader::Tools::GetGlobals(); >>

C<< Bootloader::Tools::SetGlobals(@params); >>

C<< Bootloader::Tools::GetSectionList(@selectors); >>

C<< Bootloader::Tools::GetSection($name); >>

C<< Bootloader::Tools::AddSection($name, @params); >>

C<< Bootloader::Tools::RemoveSections($name); >>

C<< Bootloader::Tools::AdjustSectionNameAppendix ($mode, $sect_ref_new, $sect_ref_old); >>

C<< $exec_with_path = Bootloader::Tools::AddPathToExecutable($executable); >>

C<< Bootloader::Tools::DeviceMapperActive (); >>

=head1 DESCRIPTION

=over 2

=cut


package Bootloader::Tools;

use strict;
use POSIX qw ( strftime );

use base 'Exporter';

our @EXPORT = qw(InitLibrary CountImageSections CountSections
		 RemoveImageSections GetDefaultImage
		 GetDefaultInitrd GetBootloader UpdateBootloader GetFittingSection
		 GetGlobals SetGlobals 
		 GetSectionList GetSection 
		 AddSection RemoveSections
);

use Bootloader::Library;
use Bootloader::Core;
use Bootloader::Path;

use Cwd;
use File::Find;

my $lib_ref = undef;
my $dmsetup = undef;
my $mdadm = undef;
my $multipath = undef;
my $devicemapper = undef;


# dummy compat function
sub DumpLog { }


sub ResolveCrossDeviceSymlinks {
    my $path = shift;

    my $core_lib = Bootloader::Core->new ();
    $path = $core_lib->ResolveCrossDeviceSymlinks ($path);

    return $path;
}

=item
C<< $mp_ref = Bootloader::Tools::ReadMountPoints (); >>

reads the information about mountpoints in the system. The returned
data is needed to initialize the bootloader library properly.

See InitLibrary function for example.

=cut

sub ReadMountPoints
{
  my $self = $lib_ref;

  my $udevmap = shift;

  my %mountpoints = ();

  for my $line (@{$self->ReadFile(Bootloader::Path::Fstab())}) {
    (my $dev, my $mp) = split ' ', $line;
    next if $dev =~ /^#/;
    if($dev =~ m/^LABEL="?([^"]*)"?/) {
      $dev = "/dev/disk/by-label/$1";	# do not translate otherwise it changes root always bnc#575362
    }
    elsif($dev =~ m/^UUID="?([^"]*)"?/) {
      $dev = "/dev/disk/by-uuid/$1";
    }
    $mp =~ s/\\040/ /g;			# handle spaces in fstab
    $mountpoints{$mp} = $dev;
  }

  return \%mountpoints;
}


sub __old_ReadMountPoints {
    open (FILE, Bootloader::Path::Fstab()) || 
	die ("ReadMountPoints(): Failed to open /etc/fstab");

    my %mountpoints = ();
    while (my $line = <FILE>)
    {
	if ($line =~ /^[ \t]*([^ \t]+)[ \t]+([^ \t]+).*/)
	{
	    my $dev = $1;
	    my $mp = $2;
	    if (substr ($dev, 0, 1) ne "#")
	    {
		if ($dev =~ m/^LABEL=/ || $dev =~ m/UUID=/)
		{
                    my $command = Bootloader::Path::Blkid() . " -l -o device -t $dev |";
		    open (BLKID, $command) || 
			die ("ReadMountPoints(): Failed to run blkid");

		    my $line = <BLKID>;
		    close (BLKID);
		    chomp $line;
		    $dev = $line if $line ne "";
		}
		$mountpoints{$mp} = $dev;
	    }
	}
    }
    close (FILE);
    return \%mountpoints;
}

=item
C<< $part_ref = Bootloader::Tools::ReadPartitions (); >>

reads the information about disk partitions. This data is needed
to initialize the bootloader library properly.

See InitLibrary function for example.

=cut

# FIXME: this has to be read through yast::storage
sub ReadPartitions
{
  my $self = $lib_ref;
  my $udevmap = shift;

  my $sb = Bootloader::Path::Prefix("/sys/block");

  # get partition info for all partitions on all @disks
  my @devices = ();

  my @disks;

  if (! -e $sb) {
    $self->error("/sys not mounted");

    return \@devices;
  }

  # get disk devices
  if(opendir(my $dh, $sb)) {
    @disks = grep {
      !/^\./ &&
      ($self->ReadNumber("$sb/$_/ext_range") > 1 || $self->ReadNumber("$sb/$_/range") > 1)
    } readdir($dh);

    closedir $dh;
  }
  else {
    $self->error("Failed to open $sb");

    return \@devices;
  }

  $self->milestone("disks =", \@disks);

  # add DM RAID partitions to @devices
  my $dm_devs = ReadDMRaidPartitions();   
  push @devices, @$dm_devs if defined $dm_devs;

  for my $disk (@disks) {
    next if IsDMDevice($disk) || IsDMRaidSlave($disk);

    my $dev_disk = "/dev/$disk";
    # raids have ! in names for /dev/raid/name (bnc #607852)
    $dev_disk =~ s#!#/#;

    my @parts;

    # get partitions of $disk
    if(opendir(my $dh, "$sb/$disk")) {
      @parts = grep {
        !/^\./ &&
        -f "$sb/$disk/$_/dev"
      } readdir($dh);

      closedir $dh;
    }
    else {
      $self->error("Failed to open $sb/$disk");

      next;
    }

    $lib_ref->milestone("partitions =", \@parts);

    # generate proper device names and other info for all @part[ition]s
    for my $part (@parts) {
      $part = "/dev/$part";
      # raids have ! in names for /dev/raid/name (bnc #607852)
      $part =~ s#!#/#;

      $part = $udevmap->{$part} if defined $udevmap->{$part};

      my $index = $part =~ /(\d+)$/ ? $1 : 0;

      # The @devices array will contain the following members:
      #
      # index type	    value (example)
      #
      #  0    device	    /dev/sda9
      #  1    disk	    /dev/sda
      #  2    nr	    9
      #  3    fsid	    258 (obsolete)
      #  4    fstype	    Apple_HFS (obsolete)
      #  5    part_type	    `primary (obsolete)
      #  6    start_cyl	    0 (obsolete)
      #  7    size_cyl	    18237 (obsolete)

      push @devices, [ $part, $dev_disk, $index, 0, "", "", "", "" ];
    }
  }

  return \@devices;
}

=item
C<< Bootloader::Tools::GetMultipath (); >>

Gets multipath configuration. Return reference to hash map, empty if system doesn't contain multipath.

=cut

sub GetMultipath
{
  my %ret = ();

  return \%ret unless DMRaidAvailable();

  $multipath = AddPathToExecutable("multipath");

  if (-e $multipath) {
    my $command = "$multipath -d -l";
 #FIXME log output 
    my @result = qx/$command/;
    # return if problems occurs...typical is not loaded kernel module
    if ( $? ) {
      if ($result[0] =~ m/kernel driver not loaded/) {
        $lib_ref->milestone("multipath kernel module is not loaded, error code: $?");
      } else {
        $lib_ref->warning("multipath command failed with $?");
      }

      return \%ret;
    }

    chomp @result;

    my $line = "";
    $line = shift @result if (scalar @result != 0);
    while (scalar @result != 0) {
      if ($line !~ m/^(\S+)\s.*dm-\d+.*$/){
        $line = shift @result;
        next;
      }
      my $multipathdev = "/dev/mapper/$1";
      while (scalar @result != 0){
        $line = shift @result;
        chomp $line;
        $lib_ref->milestone("processing line: $line");
        if ($line =~ m/(.*)dm-.*$/){
          last;
        }
        if ($line =~ m/\d+:\d+:\d+:\d+\s+(\S+)\s+/){
          $ret{"/dev/$1"} = $multipathdev;
          $lib_ref->milestone("added /dev/$1 => $multipathdev");
        }
      }
    }
  }

  return \%ret;
}


=item
C<< Bootloader::Tools::GetDeviceMapping (); >>

Return reference to hash with symlinks to block devices.

=cut

# Notes:
#   - replaces various udev mapping calls
#   - no logging as map is passed to DefineUdevMapping() and logged there
#   - if issues with device mapper arise, check bnc #590637
sub GetDeviceMapping
{
  my $list;

  find({ wanted => sub {
    if(-l && -b) {
      my $b = $_;
      $b =~ s#[^/]+$##;
      my $l = readlink;
      if(defined $l) {
        $l = "$b$l" if $l !~ /^\//;
        $list->{$_} = Cwd::realpath($l);
      }
    }
  }, no_chdir => 1 } , "/dev");

  return $list;
}


=item
C<< $numDM = Bootloader::Tools::DMRaidAvailable (); >>

Tests wether DMRAID is available.
Return 0 if no device, 1 if there are any.

=cut

sub DMRaidAvailable
{
  my $self = $lib_ref;

  my $r = $self->{cache}{DMRaidAvailable};

  if(defined $r) {
    $self->debug("DMRaidAvailable (cached) = $r");
    return $r;
  }

  $self->{tools}{dmsetup} = $dmsetup = AddPathToExecutable("dmsetup");

  # check for device-mapper in /proc/misc
  $r = grep /device-mapper/, @{$self->ReadFile(Bootloader::Path::Prefix('/proc/misc'))};

  $self->milestone("device-mapper = $r");

  if($r) {
    # check if dmsetup works and reports dm devices
    if (-e $dmsetup) {
      my $dm_devices = qx{$dmsetup info -c --noheadings -o uuid 2>/dev/null};
      chomp $dm_devices;
      $r = $dm_devices eq "No devices found" || $dm_devices eq "" ? 0 : 1;

      $self->milestone("dm devices = $r");
    }
    else {
      $self->error('The command "dmsetup" is not available.');
      $self->error('Is the package "device-mapper" installed?');
    }
  }

  $r = $r ? 1 : 0;

  $self->milestone("DMRaidAvailable = $r");

  return $self->{cache}{DMRaidAvailable} = $r;
}


=item
C<< $part_ref = Bootloader::Tools::ReadDMRaidPartitions (); >>

reads partitions belonging to a Devicemapper RAID device.
needed to be able to put get the correct translation
into Grub notation
DMRaid Devices look like:
dmraid-<strange name>

DMRaid Partitions look like:
partX-dmraid-<strange name>


=cut

# FIXME: this has to be done through Storage
# FIXME: do such devices really exist?

sub ReadDMRaidPartitions
{
  my $self = $lib_ref;

  return undef if !DMRaidAvailable();

  my @dmdisks = ();
  my @dmparts = ();
  my $dmdev;

  if(!open(DMDEV, "$dmsetup info -c --noheadings -o name |")) {
    $self->error("dmsetup failed");

    return undef;
  }

    while (<DMDEV>) {
	$dmdev = $_;
	chomp($dmdev);

	#FIXME: I should not need to do this twice
	if ($dmdev !~ m/part/) {
            $self->milestone("found raid disk $dmdev");
	    # $dmdev is the base device
	    $dmdev = "/dev/mapper/" . $dmdev;
	    push @dmdisks, $dmdev;
	}
	#FIXME: need to check what needs to be removed
	else {
            $self->milestone("found raid part $dmdev");
	    $dmdev = "/dev/mapper/" . $dmdev;
	    push @dmparts, $dmdev;
	}
    }
    close DMDEV;

    my @devices = ();
    my $dmpart;
    my $tmp_part;

    foreach $dmdev (@dmdisks) {
	foreach $dmpart (@dmparts) {
	    if ($dmpart =~ m/$dmdev/) {
		my $index = substr ($dmpart, length($dmpart)-2,2);

		while (length ($index) > 0 && substr ($index, 0, 1) !~ /[0-9]/) {
		    $index = substr ($index, 1);
		}
		push @devices, [$dmpart, $dmdev, $index];
	    }
	}
    }

  $self->milestone("dmraid partitions = ", \@devices);

  return \@devices;
}

=item
C<< $part_ref = Bootloader::Tools::ReadDMRaidDisks (); >>

returns a reference to a list of DMRaid devices

=cut

# FIXME: seems to be unused

sub ReadDMRaidDisks
{
  my $self = $lib_ref;

  return undef if !DMRaidAvailable();

  my @dmdisks = ();
  my @dmparts = ();
  my $dmdev;

  if(!open(DMDEV, "$dmsetup info -c --noheadings -oname |")) {
    $self->error("dmsetup failed");

    return undef;
  }

    while(<DMDEV>){
        $dmdev = $_;
        chomp($dmdev);

        if ($dmdev !~ m/part/){
            # $dmdev is the base device
            $dmdev = "/dev/mapper/" . $dmdev;
            push @dmdisks, $dmdev;
        }
    }

  $self->milestone("dmraid disks = ", \@dmdisks);

  return \@dmdisks;
}

=item
C<< Bootloader::Tools::IsDMRaidSlave ($kernel_disk); >>

checks wether a kernel_device is part of a DMRAID
returns 1 if yes, 0 if no

=cut

sub IsDMRaidSlave
{
  my $self = $lib_ref;
  my $dev = shift;

  my $r = $self->{cache}{IsDMRaidSlave}{$dev};
  
  if(defined $r) {
    $self->debug("IsDMRaidSlave($dev) (cached) = $r");

    return $r;
  }

  my @d = glob Bootloader::Path::Prefix("/sys/block/$dev/holders/*");

  $r = @d && -d $d[0] ? 1 : 0;

  $self->milestone("IsDMRaidSlave($dev) = $r");

  return $self->{cache}{IsDMRaidSlave}{$dev} = $r;
}

=item
C<<  Bootloader::Tools:IsDMDevice ($device); >>

returns 1 if $device is a Devicemapper device,
otherwise 0.

$device is the name as it appears in /sys/block (no leading /dev).

=cut

sub IsDMDevice
{
  my $self = $lib_ref;
  my $dev = shift;

  my $r = $self->{cache}{IsDMDevice}{$dev};
  
  if(defined $r) {
    $self->debug("IsDMDevice($dev) (cached) = $r");

    return $r;
  }

  $r = -f Bootloader::Path::Prefix("/sys/block/$dev/dm/name") ? 1 : 0;

  $self->milestone("IsDMDevice($dev) = $r");

  return $self->{cache}{IsDMDevice}{$dev} = $r;
}

=item
C<< $dm_dev = Bootloader::Tools::Udev2DMDev($udevdevice); >>

takes a udev device (dm-X)
returns the devicemapper device like dmsetup returns  

=cut

sub Bootloader::Tools::Udev2DMDev {

    my $udevd = shift;
    my $majmin = Udev2MajMin($udevd);
    my $dmdev = MajMin2DMDev($majmin);

    return $dmdev
}

=item
C<< $udev_dev = Bootloader::Tools::DMDev2Udev($dmdev); >>

takes a devicemapper device as reported from dmsetup
returns a udev device (dm-X)

=cut

# FIXME: seems to be unused

sub Bootloader::Tools::DMDev2Udev {

    my $dmdev = shift;
    my $majmin = DMDev2MajMin($dmdev);
    my $udevdev = MajMin2Udev($majmin);

    return $udevdev;
}

=item
C<< $majmin = Bootloader::Tools::DMDev2MajMin($dmdev); >>

takes a devicemapper device as reported from dmsetup
returns a string containing major:minor

=cut

# FIXME: seems to be unused

sub Bootloader::Tools::DMDev2MajMin {

    my $dmdev = shift;
    my $majmin;
    $majmin =  qx{$dmsetup info -c  --noheadings -o major,minor '$dmdev'};
    chomp $majmin;

    return $majmin;
}


=item
C<< $majmin = Bootloader::Tools::Udev2MajMin($udev); >>

takes a udev device as reported from udevadm info
returns a string containing major:minor

=cut

sub Bootloader::Tools::Udev2MajMin {

    my $udev_dev = shift;
    my $majmin;
    my $cmd = "udevadm info -qpath -n $udev_dev";

    if (my $udev_path = qx{$cmd 2>/dev/null}){
       chomp ($udev_path);
       
       my $mounted = undef;
       unless (-e "/sys/block") {
         $mounted = `mount /sys`;
       }
       $majmin = qx{cat /sys$udev_path/dev};
       chomp ($majmin);
       `umount /sys` if (defined $mounted);

    }
    return $majmin;
}

=item
C<< $udev_dev = Bootloader::Tools::MajMin2Udev($majmin); >>

takes a string major:minor as reported from udevadm info
returns a string containing the udev device as reported 
by udevadm info

=cut

# FIXME: seems to be unused

sub Bootloader::Tools::MajMin2Udev {

    my $majmin = shift;

    my ($major,  $minor) = split (/:/, $majmin );
    my $udevdev;
    my $sb="/sys/block";
    my $devmajmin;

    my $mounted = undef;
    unless (-e "/sys/block") {
      $mounted = `mount /sys`;
    }
    opendir (SYSBLOCK, "$sb");

    foreach my $dirent (readdir(SYSBLOCK)) {
	next if $dirent =~ m/^\./;
	next if -r "$sb/$dirent/range" and qx{ cat $sb/$dirent/range } == 1;
	$devmajmin = qx{cat $sb/$dirent/dev};
        chomp $devmajmin;
	my ($p, undef) = (split(/:/, $devmajmin));

	if ("$p" eq "$major" ) {
	    $udevdev = "$sb/$dirent";
	    last;
	}
    }
    closedir (SYSBLOCK);

    opendir (SYSBLOCK, "$udevdev");
    my $part;

    foreach my $dirent (readdir(SYSBLOCK)) {
	next if $dirent =~ m/^\./;

	if (-r "$udevdev/$dirent/dev") {
	    my $mm = qx{cat $udevdev/$dirent/dev};
	    chomp ($mm);

	    if ("$mm" eq "$majmin") {
		$part = $dirent;
		last;
	    }
	}
    }
    closedir (SYSBLOCK);

    `umount /sys` if (defined $mounted);

    return $part;
}

=item
C<< $dm_dev = Bootloader::Tools::MajMin2DMDev($majmin); >>

takes a string major:minor as reported from udevadm info
returns a string containing the device as reported by 
dmsetup

=cut

sub Bootloader::Tools::MajMin2DMDev {

    my $majmin = shift;
    my $dm_name  =  qx{devmap_name $majmin};
    chomp $dm_name;

    return $dm_name;

}



=item
C<< $md_ref = Bootloader::Tools::ReadRAID1Arrays (); >>

reads the information about disk MD RAID1 arrays. This data is needed
to initialize the bootloader library properly.

=cut

# FIXME: this has to be read through yast::storage
sub ReadRAID1Arrays {
    my %mapping = ();
    # use '/sbin/mdadm --detail --verbose --scan'
    # Assuming an output format like:
    #
    #	 ARRAY /dev/md1 level=raid5 num-devices=3 UUID=12cdd4f2:0f932f25:adb61ba6:1b34cb24
    #	    devices=/dev/sda3,/dev/sda4,/dev/sdb3
    #	 ARRAY /dev/md0 level=raid1 num-devices=2 UUID=af4346f4:eba443d2:c493326f:36a37aad
    #	    devices=/dev/sda1,/dev/sdb1
    #

    $lib_ref->{tools}{mdadm} = $mdadm = AddPathToExecutable("mdadm");

    if (-e $mdadm) {
      open (MD, "$mdadm --detail --verbose --scan 2>/dev/null |");
    }
    else {
      $lib_ref->milestone('The command "mdadm" is not available.');
      $lib_ref->milestone("Expect that system doesn't have MD array.");

      # if the command "mdadm" isn't available return ref to empty hash
      return \%mapping;
    }
    
    my ($array, $level, $num_devices);
    $lib_ref->milestone("start parsing mdadm --detail --verbose --scan");
    while (my $line = <MD>)
    {
        chomp ($line);
        $lib_ref->milestone("$line");

        if ($line =~ /ARRAY (\S+) level=(\w+) num-devices=(\d+)/)
        {
            ($array, $level, $num_devices) = ($1, $2, $3);
            my $kdevice = `readlink -f $array`; #avoid problems with link /dev/md/* bnc#597812
            $array = $kdevice if $? == 0;
            chomp $array;
            $array = "/dev/md$1" if $array =~ m:^/dev/md/([0-9]+)$:;
            $lib_ref->milestone("set array $array level $level and device count to $num_devices");
        }
        elsif ($level eq "raid1" and $line =~ /devices=(\S+)/)
        {
            # we could test $num_device against number of found devices to
            # detect degradedmode but that does not matter here (really?)
            $lib_ref->milestone("set to array $array values $1");
            my @devices = split(/,/,$1);
            if ($devices[0]=~ m/^.*\d+$/){ #add only non-disc arrays
                $mapping{$array} = [ @devices ];
            }
        }
    }
    $lib_ref->milestone("finish parsing mdadm");
    close( MD );
    return \%mapping;
}

=item
C<< $loader = Bootloader::Tools::GetBootloader (); >>

returns the used bootloader. Reads the value from sysconfig.
Returns the string - bootloader type.

See InitLibrary function for example.

=cut

sub GetBootloader
{
  my $val = GetSysconfigValue("LOADER_TYPE");

  $lib_ref->milestone("loader = $val") if $lib_ref;

  return $val;
}   

=item
C<< $value = Bootloader::Tools::GetSysconfigValue (); >>

returns specified option from the /etc/sysconfig/bootloader
file or undef if variable is not set.

See AddSection for example

=cut

sub GetSysconfigValue
{
  my $key = shift;
  my $val;
  local $_;

  if(open my $fh, Bootloader::Path::Sysconfig()) {
    while(<$fh>) {
      $val = $1, last if /^\s*$key\s*=\s*"(.*)"\s*$/;
    }

    close $fh;
  }

  return $val;
}

=item
C<< Bootloader::Tools::InitLibrary (); >>

initializes the bootloader configuration library. Fills its internal structures
needed for it to run properly.

=cut

sub InitLibrary
{
  $lib_ref = Bootloader::Library->new();

  my $um = GetDeviceMapping();
  my $mp = ReadMountPoints();
  my $part = ReadPartitions($um);
  my $md = ReadRAID1Arrays();
  my $mpath = GetMultipath();

  $lib_ref->SetLoaderType(GetBootloader());
  $lib_ref->DefineMountPoints($mp);
  $lib_ref->DefinePartitions($part);
  $lib_ref->DefineMDArrays($md);
  $lib_ref->DefineMultipath($mpath);
  $lib_ref->DefineUdevMapping($um);

  # parse Bootloader configuration files   
  $lib_ref->ReadSettings();

  $lib_ref->milestone("done");

  return $lib_ref;
}


# internal: does section match with set of tags
sub match_section
{
  my $self = $lib_ref;

  my ($sect_ref, $opt_ref) = @_;
  my $match = 0;

  $self->milestone("section name: \"$sect_ref->{name}\"");

  for my $opt (keys %{$opt_ref}) {
    next unless exists $sect_ref->{$opt};

    # FIXME: avoid "kernel"
    # FIXME: if $opt_ref doesn't have (hdX,Y), there is a mountpoint, thus remove it from sect_ref
    # FIXME: to compare !!

    my $key1 = $sect_ref->{$opt};
    my $key2 = $opt_ref->{$opt};

    if($opt eq "image" || $opt eq "kernel" || $opt eq "initrd") {
      $key1 = ResolveCrossDeviceSymlinks($key1);
      $key2 = ResolveCrossDeviceSymlinks($key2);
    }

    $match = $key1 eq $key2 ? 1 : 0;
    $self->milestone("  $opt($key1 " . ($match ? "=" : "!") . "= $key2)");

    last unless $match;
  }

  $self->milestone("match result: $match");

  return $match;
}


# internal: normalize options in a way needed for 'match_section'
sub normalize_options
{
  my $self = $lib_ref;
  my $opt_ref = shift;

  # FIXME: some have "kernel" some have "image" tag, latter makes more sense
  $opt_ref->{kernel} = $opt_ref->{image} if exists $opt_ref->{image};
}


=item
C<< Bootloader::Tools::CountImageSections ($image); >>

counts sections in the bootolader menu reffering to the
specified kernel.

EXAMPLE:

  Bootloader::Tools::InitLibrary();
  my $count = Bootloader::Tools::CountImageSections ("/boot/vmlinuz-2.6.11");
  print "Sections: $count\n";

=cut

#
# FIXME: This function is bogus as sections are specified by a unique name
# and not all sections of all types have a kernel entry
sub CountImageSections {
    my $image = shift;

    return 0 unless $image;
    return CountSections(type=>"image", image=>$image);
}


=item
C<< Bootloader::Tools::CountSections (@selections); >>

# FIXME: add documentation

=cut

sub CountSections {
    return scalar GetSectionList(@_);
}


=item
C<<  Bootloader::Tools::UpdateBootloader (); >>

Updates the bootloader settings meaning do whatever it takes for the actual
bootloader to use the current configuration

=cut


sub UpdateBootloader {
    my $ret = $lib_ref->UpdateBootloader ();

    return $ret;
}


=item
C<<  $lang = Bootloader::Tools::GetSystemLanguage (); >>

Read the System Language from /etc/sysconfig/language:RC_LANG

EXAMPLE:
  my $Lang;
  $Lang = Bootloader::Tools::GetSystemLanguage ();

  setlocale(LC_MESSAGES, $Lang);

=cut


sub GetSystemLanguage {
    open (FILE, ". /etc/sysconfig/language && echo \$RC_LANG |") || 
	die ("GetSystemLanguage(): Cannot determine the system language");

    my $lang = <FILE>;
    close (FILE);
    chomp ($lang);
    return $lang;
}

=item
C<< %defaultSelection =  Bootloader::Tools::GetDefaultSection (); >>

Get the default section, returns a hash reference 

EXAMPLE:
  my %section;
  %section = Bootloader::Tools::GetDefaultSection ();
  my $default_kernel = $section{"kernel"};
=cut

sub GetDefaultSection {
   #Get global Settings
   my $glob_ref = $lib_ref->GetGlobalSettings ();

   if (! defined ($glob_ref))
   {
      die ("GetDefaultSection(): Getting global data failed");
   }

   # This doesn't return the index of the default section, but the title of it.         
   # All other keys have their real value (eg timeout has 8) 
   my $def = $glob_ref->{"default"};

   # $section_ref is a reference to a list of hashes, where the section data is stored  
   my $section_ref = $lib_ref->GetSections ();

   if (! defined ($section_ref))
   {
      die ("GetDefaultSection(): Getting sections failed");
   }

   # get the hash of the default section, identified by key 'name'
   my @default_sect = grep {$_->{"name"} eq $def} @{$section_ref};

   return $default_sect[0];
}


=item
C<< Bootloader::Tools::GetDefaultImage (); >>

Get the kernel name of the default section

EXAMPLE:
  my $kernel;
  $kernel = Bootloader::Tools::GetDefaultImage ();

  print("Default Kernel Name: $kernel\n");

=cut

sub GetDefaultImage {
    my $ref = GetDefaultSection();
    # FIXME: all modules under .../Core should use "image" as a key tag to the
    # kernel image
    return $ref->{"image"} || $ref->{"kernel"};
}

=item
C<< Bootloader::Tools::GetDefaultInitrd (); >>

Get the initrd of the default section

EXAMPLE:
  my $initrd;
  $initrd = Bootloader::Tools::GetDefaultInitrd ();

  print("Default initrd  Name: $initrd\n");

=cut

sub GetDefaultInitrd {
   return GetDefaultSection()->{"initrd"};
}

=item
C<< Bootloader::Tools::GetGlobals(); >>
=cut

sub GetGlobals() {
    return $lib_ref->GetGlobals();
}


=item
C<< Bootloader::Tools::SetGlobals(@params); >>

# FIXME: Add documentation
=cut
sub SetGlobals {
    my %option = @_;
    my $glob_ref = $lib_ref->GetGlobalSettings();

    # merge with current, undef values delete options
    foreach (keys %option) {
	if (defined $option{$_}) {
	    $glob_ref->{$_} = $option{$_};
	} else {
	    delete $glob_ref->{$_};
	}
    }
    $glob_ref->{"__modified"} = 1;
    $lib_ref->SetGlobalSettings ($glob_ref);
    $lib_ref->WriteSettings (1);
    $lib_ref->UpdateBootloader (1); # avoid initialization but write config to
                                    # the right place
}


=item
C<< Bootloader::Tools::GetSectionList(@selectors); >>

# FIXME: Add documentation
=cut

sub GetSectionList
{
  my $self = $lib_ref;

  my %option = @_;
  my $loader = GetBootloader();

  $self->milestone("search options:", \%option);

  normalize_options(\%option);

  my @sections = @{$self->GetSections()};

  my @section_names = map {
    match_section($_, \%option) ? $_->{name} : ();
  } @sections;

  $self->milestone("sections matched:", \@section_names);

  return @section_names;
}


=item
C<< Bootloader::Tools::GetSection($name); >>

# FIXME: Add documentation
=cut

sub GetSection
{
  my $self = $lib_ref;

  my $name = shift or return undef;

  for (@{$self->GetSections()}) {
    return $_ if $_->{name} eq $name;
  }

  return undef;
}


sub get_flavor
{
  my $flavor;

  $flavor = $1 if $_[0] =~ /^.*-([a-zA-Z0-9]+)/;

  return $flavor;
}


sub get_fallback
{
  my $fallback;

  $fallback = $_[0] =~ /failsafe/i || $_[1] eq "failsafe" ? 1 : 0;

  return $fallback;
}


=item
C<< Bootloader::Tools::GetFittingSection($name, $image, $type, \@sections); >>

Find fitting section for given name and image type.
If not found return undef.

=cut

sub GetFittingSection
{
  my $self = $lib_ref;

  my $name = shift;
  my $image = shift;
  my $type = shift;
  my $sections = shift;
  my $ret;

  $self->milestone("name = $name, image = $image, type = $type");
  $self->milestone("sections =", $sections, 2);

  my $flavor = get_flavor $image;
  my $fallback = get_fallback $name;

  return undef unless defined $flavor;

  $self->milestone("flavor = $flavor, fallback = $fallback");
 
  # heuristic one - try to find same flavor
  for (@$sections) {
    if(
      $_->{type} eq $type &&
      get_flavor($_->{image}) eq $flavor &&
      get_fallback($_->{name}, $_->{original_name}) == $fallback
    ) {
      $ret = $_;
      last;
    }
  }

  if(!$ret) {
    # heuristic two - see if we deleted a matching entry lately
    $ret = get_zombie($type, $flavor, $fallback);

    if($ret) {
      delete $ret->{fallback};
      delete $ret->{flavor};
    }
  }

  $self->milestone("fitting section =", $ret, 1);

  return $ret;
}


=item
C<< Bootloader::Tools::AddSection($name, @params); >>

Add a new section (boot entry) to config file, e.g. to /boot/grub/menu.lst

EXAMPLE:

  my $opt_name = "LabelOfSection";
  my @params = (type   => $type,
              	image  => $opt_image,
		initrd => $opt_initrd,
  );

  Bootloader::Tools::AddSection ($opt_name, @params);

=cut

sub AddSection
{
  my $self = $lib_ref;

  my $name = shift;
  my %option = @_;

  return unless defined $name;
  return unless exists $option{type};

  $self->milestone("name = $name, option = ", \%option);

  my $loader = Bootloader::Tools::GetBootloader();

  $self->ReadZombies();

  my $default = delete $option{default} || 0;
  my %new = ();

  my @sections = @{$self->GetSections()};

  my $fitting_section = GetFittingSection($name, $option{image}, $option{type}, \@sections);

  if($fitting_section) {
    $lib_ref->milestone("Fitting section found so use it");

    ###### FIXME strip 'initial'?
    for (keys %$fitting_section) {
      $new{$_} = $fitting_section->{$_} unless /^(__.*|initial|original_name|initrd)$/
    }

    $new{exists $new{kernel} ? "kernel" : "image"} = delete $option{image} if exists $option{image};
  }
  else {
    $self->milestone("Fitting section not found. Use sysconfig values as fallback.");
    my $sysconf;
    if($name =~ /^Failsafe/ || $option{original_name} eq "failsafe") {
      $sysconf =  GetSysconfigValue("FAILSAFE_APPEND");
      $new{append} = $sysconf if defined $sysconf;
      $sysconf = GetSysconfigValue("FAILSAFE_VGA");
      $new{vgamode} = $sysconf if defined $sysconf;
      $sysconf = GetSysconfigValue("IMAGEPCR");
      $new{imagepcr} = $sysconf if defined $sysconf;
      $sysconf = GetSysconfigValue("INITRDPCR");
      $new{initrdpcr} = $sysconf if defined $sysconf;
      my %measures = split(/:/, GetSysconfigValue("FAILSAFE_MEASURES"));
      $new{measure} = \%measures if keys %measures != 0;
    }
    elsif($option{type} eq "xen") {
      $sysconf = GetSysconfigValue("XEN_KERNEL_APPEND");
      $new{append} = $sysconf if defined $sysconf;
      $sysconf =  GetSysconfigValue("XEN_VGA");
      $new{vgamode} = $sysconf if defined $sysconf;
      $sysconf =  GetSysconfigValue("XEN_APPEND");
      $new{xen_append} =  $sysconf if defined $sysconf;
      $sysconf = GetSysconfigValue("XEN_IMAGEPCR");
      $new{imagepcr} = $sysconf if defined $sysconf;
      $sysconf = GetSysconfigValue("XEN_INITRDPCR");
      $new{initrdpcr} = $sysconf if defined $sysconf;
      $sysconf = GetSysconfigValue("XEN_PCR");
      $new{xenpcr} = $sysconf if defined $sysconf;
      my %measures = split(/:/, GetSysconfigValue("XEN_MEASURES"));
      $new{measure} = \%measures if keys %measures != 0;
    }
    else {
      # RT kernels have special args bnc #450153
      if($new{image} =~ /-rt$/ && defined GetSysconfigValue("RT_APPEND")) {
        $sysconf = GetSysconfigValue("RT_APPEND");
        $new{append} = $sysconf if defined $sysconf;
        $sysconf = GetSysconfigValue("RT_VGA");
        $new{vgamode} = $sysconf if defined $sysconf;
      }
      else {
        $sysconf = GetSysconfigValue("DEFAULT_APPEND");
        $new{append} = $sysconf if defined $sysconf;
        $sysconf = GetSysconfigValue("DEFAULT_VGA");
        $new{vgamode} = $sysconf if defined $sysconf;
        $sysconf = GetSysconfigValue("IMAGEPCR");
        $new{imagepcr} = $sysconf if defined $sysconf;
        $sysconf = GetSysconfigValue("INITRDPCR");
        $new{initrdpcr} = $sysconf if defined $sysconf;
        my %measures = split(/:/, GetSysconfigValue("DEFAULT_MEASURES"));
        $new{measure} = \%measures if keys %measures != 0;
      }
    }

    my $root_dev = ReadMountPoints()->{'/'};
    $new{root} = $root_dev if $root_dev;

    $sysconf = GetSysconfigValue("CONSOLE");
    $new{console} = $sysconf if defined $sysconf;

    if($loader eq "zipl") {
      $new{target} = "/boot/zipl";
    }
  }

  $new{$_} = $option{$_} for keys %option;
  $new{name} = $name;

  # Append flavor appendix to section label if necessary
  AdjustSectionNameAppendix("add", \%new);

  my $failsafe_modified = 0;
  if($name =~ /^Failsafe/ || $option{original_name} eq "failsafe") {
    $failsafe_modified = 1;
    $default = 0;
  }

  $new{__modified} = 1;

  my $match = '';
  my $new_name = '';

  # If we have a bootloader that uses label names to specify the default
  # entry we need unique labels: so, append '_NUMBER', if necessary.
  #
  # cf. Core::FixSectionName()

  if($loader ne "grub" && $loader ne "grub2") {
    my $max_idx = undef;
    for my $s (@sections) {
      $max_idx = $2 + 0 if $s->{name} =~ /^$new{name}(_(\d+))?$/ && $2 >= $max_idx;
    }

    $new{name} .= "_" . ($max_idx + 1) if defined $max_idx;
  }

  # Print new section to be added to logfile
  $self->milestone("New section to be added:", \%new);

  # Put new entries on top
  unshift @sections, \%new;

  # Switch the first 2 entries in @sections array to put the normal entry on
  # top of corresponding failsafe entry
  if(($failsafe_modified == 1) && @sections >= 2) {
	my $failsafe_entry = shift (@sections);
	my $normal_entry = shift (@sections);

	# Delete obsolete (normal) boot entries from section array
	my $section_index = 0;
	foreach my $s (@sections) {
	    if (exists $normal_entry->{"kernel"} && $normal_entry->{"kernel"} eq $s->{"kernel"}) {
		delete $sections[$section_index];
	    }
	    elsif (exists $normal_entry->{"image"} && $normal_entry->{"image"} eq $s->{"image"}) {
		delete $sections[$section_index];
	    }
	    else {
		$section_index++;
	    }
	}

	# Delete obsolete (failsafe) boot entries from section array
	$section_index = 0;
	foreach my $s (@sections) {
	    if (exists $failsafe_entry->{"kernel"} && $failsafe_entry->{"kernel"} eq $s->{"kernel"}) {
		delete $sections[$section_index];
	    }
	    elsif (exists $failsafe_entry->{"image"} && $failsafe_entry->{"image"} eq $s->{"image"}) {
		delete $sections[$section_index];
	    }
	    else {
		$section_index += 1;
	    }
	}

	unshift @sections, $failsafe_entry;
	unshift @sections, $normal_entry;
  }

  # Print all available sections to logfile
  $self->milestone("All available sections (including new ones):", \@sections, 2);

  $self->SetSections(\@sections);

  # If the former default boot entry is updated, the new one will become now
  # the new default entry.
  my $glob_ref = $self->GetGlobalSettings();

  $default = 1 if delete $glob_ref->{removed_default} == 1;
  # avoid non-exist default
  $default = 1 unless defined $glob_ref->{default} && $glob_ref->{default} ne "";

  if($default) {
    $glob_ref->{default} = $new{name};

    # remove read-only flag bnc #381669
    delete $glob_ref->{'read-only'} if $loader eq "lilo";

    $glob_ref->{__modified} = 1;

    $self->SetGlobalSettings($glob_ref);
  }
  elsif($loader eq "grub") {
    # If a non default entry is updated, the index of the current
    # default entry has to be increased, because it is shifted down in the
    # array of sections. Only do this for grub.

    for (@{$glob_ref->{__lines}}) {
      $_->{value} += 1 if $_->{key} eq "default";
    }

    $self->SetGlobalSettings($glob_ref);
  }

  # Print globals to logfile
  $self->milestone("Global section of config:", $glob_ref, 1);

  $self->StoreZombies();

  if($self->WriteSettings(1)) {
    # avoid initialization but write config to the right place
    $self->UpdateBootloader(1);
  }
  else {
    $self->error("An error occurred while writing the settings.");
  }
}


sub add_zombie
{
  my $self = $lib_ref;
  my $section = shift;

  $self->milestone("section =", $section, 1);

  my $flavor = get_flavor $section->{image};
  my $fallback = get_fallback $section->{name};
  return unless defined $flavor;

  my $stored = {
    flavor => $flavor,
    fallback => $fallback,
    date => strftime("%Y-%m-%d %H:%M:%S", localtime)
  };

  for (keys %$section) {
    $stored->{$_} = $section->{$_} unless /^(__.*|initial|original_name|initrd|image|kernel)$/
  }

  $self->{zombies} = [ grep {
    $_->{flavor} ne $stored->{flavor} ||
    $_->{fallback} != $stored->{fallback} ||
    $_->{type} ne $stored->{type};
  } @{$self->{zombies}} ];

  push @{$self->{zombies}}, $stored;

  $self->milestone("zombie list (new) =", $self->{zombies});
}


sub get_zombie
{
  my $self = $lib_ref;
  my $type = shift;
  my $flavor = shift;
  my $fallback = shift;
  my $found;

  $self->{zombies} = [ grep {
    my $ok =
      $_->{flavor} eq $flavor &&
      $_->{fallback} == $fallback &&
      $_->{type} eq $type;
    $found = $_ if $ok;
    !$ok
  } @{$self->{zombies}} ];

  $self->milestone("zombie found =", $found);

  $self->milestone("zombie list (new) =", $self->{zombies});

  return $found;
}


=item
C<< Bootloader::Tools::RemoveImageSections ($image); >>

removes all sections in the bootloader menu referring to the
specified kernel.

EXAMPLE:

  Bootloader::Tools::InitLibrary ();
  Bootloader::Tools::RemoveImageSections ("/boot/vmlinuz-2.6.11");
  Bootloader::Tools::UpdateBootloader();

=cut

sub RemoveImageSections {
    my $image = shift;

    return unless $image;
    RemoveSections(type=>"image", image => $image);
}


=item
C<< Bootloader::Tools::RemoveSections($name); >>

=cut

sub RemoveSections
{
  my $self = $lib_ref;

  my %option = @_;
  my @sections = @{$self->GetSections()};
  my $glob_ref = $self->GetGlobalSettings();
  my $default_section = $glob_ref->{"default"} || "";
  my $default_removed = 0;
  my @removed_sections;

  my $loader = GetBootloader();

  $self->ReadZombies();

  $self->milestone("search options:", \%option);

  normalize_options(\%option);

  $self->milestone("All available sections (before removal):", \@sections, 2);

  my @section_names_before_removal = ();

  # Extract section names (before removal) out of @sections array
  for (@sections) {
    push @section_names_before_removal, $_->{name};
  }

  @sections = grep {
    my $match = match_section($_, \%option);
    $default_removed = 1 if $match and $default_section eq $_->{name};
    push @removed_sections, $_ if $match;
    !$match;
  } @sections;

  add_zombie $_ for @removed_sections;

  $self->milestone("removed sections:", \@removed_sections, 2);

  # Detect wether we have an entry with an initrd line referring to a non
  # existing initrd file and remove this section respectively.
  if($loader eq "grub") {
    @sections = grep {
      my $match = 1;

      # Check if there is a member called "initrd". If this is not the
      # case, do not throw out the corresponding section because boot
      # entries without an initrd are allowed, too.
      if(exists $_->{initrd}) {
        my $initrd_name = $_->{initrd};
        my $other_part = 0;

        $other_part = 1 if $initrd_name =~ m/\(hd.+\)/;
        $initrd_name =~ s/^.*(initrd-.+)$/$1/;
        $initrd_name = "/boot/" . $initrd_name;

        if(
          !$other_part &&
          !-f $initrd_name &&
          ($_->{type} eq "image" || $_->{type} eq "xen")
        ) {
          $match = 0;
          $self->milestone("removed non-existing initrd \"$initrd_name\" in \"$_->{name}\"");
          $default_removed = 1 if $default_section eq $_->{name};
        }
      }
      $match;
    } @sections;
  }

  $self->milestone("default section has been removed") if $default_removed;

  my @section_names_after_removal = ();

  # Extract section names (after removal) out of @sections array
  for (@sections) {
    push @section_names_after_removal, $_->{name};
  }

  # Remove flavor appendix from section labels if necessary
  AdjustSectionNameAppendix("remove", \@section_names_before_removal, \@section_names_after_removal);

  $self->milestone("All available sections (after removal):", \@sections, 2);

  $self->SetSections(\@sections);

  if($default_removed) {
    $glob_ref->{default} = $sections[0]{name};
    $self->milestone("removed default, new default = \"$glob_ref->{default}\"");
    $glob_ref->{removed_default} = 1;
  }

  # needed because of GRUB - index of default may change even if not deleted
  $glob_ref->{"__modified"} = 1;

  $self->SetGlobalSettings($glob_ref);
  $self->WriteSettings(1);

  # store zombie list
  $self->StoreZombies();

  # avoid initialization but write config to the right place
  $self->UpdateBootloader(1);
}


=item
C<< Bootloader::Tools::AdjustSectionNameAppendix ($mode, $sect_ref_new, $sect_ref_old); >>

Adds and respectively removes a potential appendix of a section name.

In case of mode "add", it adjusts labels which only differ in their
corresponding flavors in the following way, e.g.:

  SUSE Linux Enterprise Server 10 - 2.6.16.54-0.2.3 (default) and
  SUSE Linux Enterprise Server 10 - 2.6.16.54-0.2.3 (smp)

Thus, the corresponding flavors will be appended in brackets.

In case of mode "remove", an appended flavor will be removed from the section
label if the corresponding section is the only one left referring to a kernel
with it's specific version.

EXAMPLE:

  my $mode = "add";
  my $sect_ref_new = \%new_section;
  Bootloader::Tools::AdjustSectionNameAppendix ($mode, $sect_ref_new);

  or

  my $mode = "remove"
  my $sect_ref_new = \@section_naems_after_removal;
  my $sect_ref_old = \@section_names_before_removal;
  Bootloader::Tools::AdjustSectionNameAppendix ($mode, $sect_ref_new, $sect_ref_old);

=cut

sub AdjustSectionNameAppendix
{
  my $self = $lib_ref;

  my ($mode, $sect_ref_new, $sect_ref_old) = @_;

  $self->milestone("more = $mode");

  $self->milestone("new =", $sect_ref_new);

  $self->milestone("old =", $sect_ref_old);

  my @sections = @{$lib_ref->GetSections()};

    if ($mode eq "add" && %$sect_ref_new) {
	my $loader = Bootloader::Tools::GetBootloader ();

	if ($loader eq "grub") {
	    foreach my $s (@sections) {
		while ((my $k, my $v) = each (%$s)) {
		    if ($k eq "name" and $v =~ m/$sect_ref_new->{"name"}( \(\w+\))?/) {
			if ($v =~ m/^$sect_ref_new->{"name"}$/) {
			    my $flavor_old = $s->{"image"};
			    $flavor_old =~ s/.*-(\w+)/($1)/;
			    $s->{"name"} = $s->{"name"} . " " . $flavor_old;
			    $s->{"__modified"} = 1;
			}

			my $flavor_new = $sect_ref_new->{"image"};
			$flavor_new =~ s/.*-(\w+)/($1)/;
			$sect_ref_new->{"name"} = $sect_ref_new->{"name"} . " " . $flavor_new;
		    }
		}
	    }
	}
    }

    elsif ($mode eq "remove" && $sect_ref_old && $sect_ref_new) {
	my @section_names_removed = ();

	# Determine removed section names
	foreach my $s_name_old (@$sect_ref_old) {
	    my $hit = 0;

	    foreach my $s_name_new (@$sect_ref_new) {
		if ($s_name_old eq $s_name_new) {
		    $hit = 1;
		}
	    }

	    if (!$hit) {
		$s_name_old =~ s/^(.+) \(\w+\)$/$1/;
		push @section_names_removed, $s_name_old;
	    }
	}

	# Remove appended flavor from title if the corresponding section is the
	# only one left referring to a kernel with it's specific version.
	foreach my $s_removed (@section_names_removed) {
	    my $count = 0;
	    my @hits = ();

	    for (my $i = 0; $i <= $#sections; $i++) {
		while ((my $k, my $v) = each (%{$sections[$i]})) {
		    if ($k eq "name" and $v =~ m/^$s_removed \(\w+\)$/) {
			$count++;
			push (@hits, $i);
		    }
		}
	    }

	    if ($count == 1) {
		foreach my $hit (@hits) {
		    $sections[$hit]->{"name"} =~ s/(.*) \(\w+\)/$1/;
		    $sections[$hit]->{"__modified"} = 1;
		}
	    }
	}
    }
    else {
	$self->warning("Invalid parameters.");
    }
}


=item
C<< Bootloader::Tools::AddPathToExecutable ($executable); >>

Prepends the corresponding (absolute) path to the given executable and returns
the result. If not found in path, function returns undef.

EXAMPLE:

  my $executable = "dmsetup";

  my $exec_with_path = Bootloader::Tools::AddPathToExecutable ($executable);

  if (-e $exec_with_path) {
      print ("The desired executable is located here: $exec_with_path");
  }

=cut

sub AddPathToExecutable {
    my $executable = shift;
    my $retval = undef;

    foreach my $dir ( split(/:/, $ENV{PATH})) {
	# Check if executable exists in current path
	if (-x "$dir/$executable") {
	    $retval = "$dir/$executable";
	    last;
	}
    }

    return $retval; 
}


=item
C<< Bootloader::Tools::DeviceMapperActive (); >>

Check if device-mapper is currently active (kernel module loaded).
It is needed for dmraid and multipath configurations.

Note: keeping for compatibility.

=cut

sub DeviceMapperActive
{
  return DMRaidAvailable();
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
