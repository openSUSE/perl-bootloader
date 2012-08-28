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

C<< $numDM = Bootloader::Tools::DMRaidAvailable (); >>

C<< $part_ref = Bootloader::Tools::ReadDMRaidPartitions (); >>

C<< $part_ref = Bootloader::Tools::ReadDMRaidDisks (); >>

C<< Bootloader::Tools::IsDMRaidSlave ($kernel_disk); >>

C<< Bootloader::Tools::IsDMDevice($dev); >>

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

my $lib_ref = undef;
my $dmsetup = undef;
my $mdadm = undef;
my $multipath = undef;
my $devicemapper = undef;


# dummy compat function
sub DumpLog { }


sub ResolveCrossDeviceSymlinks {
  my $path = shift;

  my $core_lib = Bootloader::Core->new($lib_ref);
  $path = $core_lib->ResolveCrossDeviceSymlinks($path);

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

  my $f = Bootloader::Path::Fstab();
  my $x = Bootloader::Core::ReadFiles($self, [ $f ]);

  my %mountpoints = ();

  for my $line (@{$x->{$f}}) {
    (my $dev, my $mp) = split ' ', $line;
    next if $dev =~ /^#/;
    if($dev =~ m/^LABEL=(.*)/) {
      $dev = "/dev/disk/by-label/$1";	# do not translate otherwise it changes root always bnc#575362
    }
    elsif($dev =~ m/^UUID=(.*)/) {
      $dev = "/dev/disk/by-uuid/$1";
    }
    $mp =~ s/\\040/ /g;			# handle spaces in fstab
    $mountpoints{$mp} = $dev;
  }

  return \%mountpoints;
}


=item
C<< $part_ref = Bootloader::Tools::ReadPartitions (); >>

reads the information about disk partitions. This data is needed
to initialize the bootloader library properly.

See InitLibrary function for example.

=cut

# FIXME: this has to be read through yast::storage
sub ReadPartitions {
    my $udevmap = shift;
    my $sb = "/sys/block";
    my $mounted = undef;
    unless (-e $sb) {
      $mounted = `mount /sys`;
      $lib_ref->milestone("Mount /sys");
    }
    opendir(BLOCK_DEVICES, "$sb") || 
	die ("ReadPartitions(): Failed to open dir $sb");

    # get disk devices
    my @disks = grep {
	!m/^\./ && (( -r "$sb/$_/ext_range" and qx{ cat $sb/$_/ext_range } > 1) || ( -r "$sb/$_/range" and qx{ cat $sb/$_/range } > 1))
    } readdir(BLOCK_DEVICES);
    closedir BLOCK_DEVICES;

    $lib_ref->milestone("Found disks: ". join (",",@disks));

    # get partition info for all partitions on all @disks
    my @devices = ();

    # Add DM RAID Partitions to @devices
    if (DMRaidAvailable()){
        my $dev_ref = ReadDMRaidPartitions();   
        push (@devices, @{$dev_ref});

    }

    foreach my $disk (@disks)
    {
        my $dev_disk = "/dev/$disk";
        if (!IsDMDevice($dev_disk) && !IsDMRaidSlave($dev_disk)){
	    # get partitions of $disk
	    opendir(BLOCK_DEVICES, "$sb/$disk") ||
	        die ("ReadPartitions(): Failed to open dir $sb/$disk");

	    my @parts = grep {
	        !m/^\./ and -d "$sb/$disk/$_" and -f "$sb/$disk/$_/dev"
	    } readdir (BLOCK_DEVICES);
	    closedir BLOCK_DEVICES;

            $lib_ref->milestone("Found parts: ". join (",",@parts));

	    # generate proper device names and other info for all @part[ition]s
      #raid have ! in names for /dev/raid/name (bnc#607852)
      $dev_disk =~ s:!:/:;
	    foreach my $part (@parts)
	    {
	        chomp ($part);
	        $part = "/dev/$part";
          #raid have ! in names for /dev/raid/name
          $part =~ s:!:/:;
          $part = $udevmap->{$part} if (defined $udevmap->{$part});

	        my $index = substr ($part, length ($dev_disk));
	        while (length ($index) > 0 && substr ($index, 0, 1) !~ /[0-9]/)
	        {
		    $index = substr ($index, 1);
	        }
		# The @devices array will contain the following members:
		#
		# index type	    value (example)
		#
		#  0    device	    /dev/sda9
		#  1    disk	    /dev/sda
		#  2    nr		    9
		#  3    fsid	    258 (not needed for update)
		#  4    fstype	    Apple_HFS(not needed for update)
		#  5    part_type	    `primary(not needed for update)
		#  6    start_cyl	    0(not needed for update)
		#  7    size_cyl	    18237(not needed for update)

		push @devices, [$part, $dev_disk, $index, 0, "", "","",""];
            }
	}
    }

    if (defined $mounted){
      $mounted = `unmount /sys`;
    }

    return \@devices;
}

=item
C<< Bootloader::Tools::GetMultipath (); >>

Gets multipath configuration. Return reference to hash map, empty if system doesn't contain multipath.

=cut

sub GetMultipath {
  my %ret = ();

  unless (DMRaidAvailable())
  {
    return \%ret;
  }

  $multipath = AddPathToExecutable("multipath");

  if (-e $multipath){
    my $command = "$multipath -d -l";
    my @result = qx/$command/;
    # return if problems occurs...typical is not loaded kernel module
    if ( $? ) {
      if ($result[0] =~ m/kernel driver not loaded/) {
        $lib_ref->milestone("multipath kernel module is not loaded Ecode:$?.");
      } else {
        $lib_ref->warning("multipath command failed with $?.");
      }
      return \%ret;
    }

    chomp @result;

    my $line = "";
    $line = shift @result if (scalar @result != 0);
    while (scalar @result != 0){
      $lib_ref->milestone("processing line $line");
      if ($line !~ m/^(\S+)\s.*dm-\d+.*$/){
        $line = shift @result;
        next;
      }
      my $multipathdev = "/dev/mapper/$1";
      while (scalar @result != 0){
        $line = shift @result;
        chomp $line;
        $lib_ref->milestone("processing line $line");
        if ($line =~ m/(.*)dm-.*$/){
          last;
        }
        if ($line =~ m/\d+:\d+:\d+:\d+\s+(\S+)\s+/){
          $ret{"/dev/$1"} = $multipathdev;
          $lib_ref->milestone("added /dev/$1 -> $multipathdev");
        }
      }
    }
  }
  else
  {
    $lib_ref->milestone("multipath command not installed");
  }

  return \%ret;
}

=item
C<< Bootloader::Tools::GetMultipath (); >>

Gets multipath configuration. Return reference to hash map, empty if system doesn't contain multipath.

=cut

sub GetUdevMapping {
  my %mapping= ();
  local $_;

  my @output = `find -P /dev -type b`;
  chomp @output;
  for my $dev (@output) {
    next if ($dev =~ m:^/dev/mapper/:);

    my @output2 = `udevadm info -q all -n $dev 2>/dev/null`;
    chomp @output2;

    if ($dev =~ m:^/dev/dm:) #workaround for incosistency of device mapper and udev
    {
      my $dmdev = undef;
      my $dmpart = undef;
      for my $line (@output2)
      {
        if ($line =~ m/DM_NAME=(.*)$/)
        {
          $dmdev = $1;
        }
        elsif ($line =~ m/DM_PART=(.*)$/)
        {
          $dmpart = $1;
        }
      }

      $lib_ref->error("UDEVMAPPING: dmdev $dev doesn't have defined DM_NAME in udev") unless defined $dmdev;
      my $prevdev = $dev;
      $dev = "/dev/mapper/$dmdev";
      # DM_NAME could contain also part in some case (bnc#590637)
      $dev = $dev."_part$dmpart" if (defined $dmpart and $dev !~ /_part[0-9]+$/);
      $mapping{$prevdev} = $dev; #maps also dm dev to device mapper
    } #end of workaround

    for (@output2) {
      $mapping{"/dev/$1"} = $dev if /S:\s(.*)$/;
    }
  }

#  while (my ($k,$v) = each (%mapping)){
#    $lib_ref->milestone("UDEV MAPPING: ".($k||"")." -> ".($v||""));
#  }

  if(!(keys %mapping)) {
    $lib_ref->milestone("*** WARNING: No UDEV mapping! ***");
    $lib_ref->milestone("device tree:");
    for (`find -P /dev -type b -ls 2>/dev/null`) {
      chomp;
      $lib_ref->milestone("  $_");
    }
    $lib_ref->milestone("udevinfo:");
    for (`udevadm info -e 2>&1`) {
      chomp;
      $lib_ref->milestone("  $_");
    }
  }

  # $lib_ref->milestone("\%mapping =", \%mapping);

  return \%mapping;
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
    $self->milestone("DMRaidAvailable (cached) = $r");
    return $r;
  }

  $self->{tools}{dmsetup} = $dmsetup = AddPathToExecutable("dmsetup");

  # check for device-mapper in /proc/misc
  my $pm = Bootloader::Path::Prefix('/proc/misc');
  my $x = Bootloader::Core::ReadFiles($self, [ $pm ]);
  $r = grep /device-mapper/, @{$x->{$pm}};

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
<strange name>

DMRaid Partitions look like:
<strange name>_part\d


=cut

sub ReadDMRaidPartitions {

    my @dmdisks = ();
    my @dmparts = ();

    open(DMDEV, "$dmsetup info -c --noheadings -o name |") || 
	die ("ReadDMRaidPartitions(): dmsetup failed.");

    while (<DMDEV>) {
	my $dmdev = $_;
	chomp($dmdev);

	#FIXME: I should not need to do this twice
	if ($dmdev !~ m/part/) {
            $lib_ref->milestone("Find raid partition $dmdev");
	    # $dmdev is the base device
	    $dmdev = "/dev/mapper/" . $dmdev;
	    push @dmdisks, $dmdev;
	}
	#FIXME: need to check what needs to be removed
	else {
            $lib_ref->milestone("Find raid disk $dmdev");
	    $dmdev = "/dev/mapper/" . $dmdev;
	    push @dmparts, $dmdev;
	}
    }
    close DMDEV;

    my @devices = ();

    foreach my $dmdev (@dmdisks) {
	foreach my $dmpart (@dmparts) {
	    if ($dmpart =~ m/$dmdev/) {
                $dmpart =~ m/^($dmdev)_part(\d+)$/;
		push @devices, [$dmpart, $dmdev, $2];
	    }
	}
    }

    return \@devices;
}

=item
C<< $part_ref = Bootloader::Tools::ReadDMRaidDisks (); >>

returns a refenrence to a list of DMRaid devices

=cut

sub ReadDMRaidDisks {

    my @dmdisks = ();
    my @dmparts = ();
    my $dmdev;


    open(DMDEV, "$dmsetup info -c --noheadings -oname |") || 
	die ("ReadDMRaidDisks(): dmsetup failed.");

    while(<DMDEV>){
        $dmdev = $_;
        chomp($dmdev);

        if ($dmdev !~ m/part/){
            # $dmdev is the base device
            $dmdev = "/dev/mapper/" . $dmdev;
            push @dmdisks, $dmdev;
        }
    }
    return \@dmdisks;
}

=item
C<< Bootloader::Tools::IsDMRaidSlave ($kernel_disk); >>

checks wether a kernel_device is part of a DMRAID
returns 1 if yes, 0 if no

=cut

sub IsDMRaidSlave {
    my $disk = shift;

    unless ( DMRaidAvailable() and -e $dmsetup) {
        return 0;
    }

    my $majmin_disk = `stat -c "%t:%T" $disk`;
    chomp($majmin_disk);
    my @dmparts = ();


    my @dm_devs = qx{$dmsetup info -c --noheadings -o name | grep -v part};
    chomp @dm_devs;

    if ($dm_devs[0] !~ /No devices found/) {
        foreach my $dmdisk (@dm_devs) {
            my @tables = qx{$dmsetup table '$dmdisk'};
            chomp @tables;

            foreach my $line (@tables) {
                next if $line !~ /mirror/;
                my @content = split(/ /, $line);

                foreach my $majmins (@content){
                    if ($majmins =~ m/(\d+):(\d+)/) {
                    	if ("$majmins" eq "$majmin_disk") {
			    return 1;
		    	}
                    }
                }
            }
        }
    }

    return 0;
}

=item
C<<  Bootloader::Tools:IsDMDevice ($device); >>

returns 1 if $device is a Devicemapper device,
otherwise 0.

=cut

sub IsDMDevice {
    my $dev = shift;

    unless ( DMRaidAvailable() and -e $dmsetup) {
        return 0;
    }

    my $cmd = "$dmsetup info -c --noheadings -oname '$dev'";
    if (my $test = qx{$cmd 2>/dev/null}){
        chomp $test;

        if ($dev =~ m/$test/){
            return 1;
        }
    }
    return 0;
}

=item
C<< $md_ref = Bootloader::Tools::ReadRAID1Arrays (); >>

reads the information about disk MD RAID1 arrays. This data is needed
to initialize the bootloader library properly.

=cut

# FIXME: this has to be read through yast::storage
sub ReadRAID1Arrays {
    my $udevmapping = shift;
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
    	$lib_ref->milestone ('The command "mdadm" is not available.');
    	$lib_ref->milestone ("Expect that system doesn't have MD array.");

    	# If the command "mdadm" isn't available, return a reference to an
    	# empty hash
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
            #udevadm sometime return udev symlink instead of physical device, bnc#547580
            $array = $udevmapping->{$array} if $udevmapping->{$array};
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

sub GetBootloader {
    my $path = Bootloader::Path::Sysconfig();
    my $lt = qx{ . $path && echo \$LOADER_TYPE } or
	die ("GetBootloader(): Cannot determine the loader type");
    chomp ($lt);
    return $lt;
}   

=item
C<< $value = Bootloader::Tools::GetSysconfigValue (); >>

returns specified option from the /etc/sysconfig/bootloader
file or undef if variable is not set.

See AddSection for example

=cut

sub GetSysconfigValue {
    my $key = shift;
    my $file = Bootloader::Path::Sysconfig();
    return undef if ( qx{ grep -c ^[[:space:]]*$key $file} == 0);
    my $value = qx{ . $file && echo \$$key } || "";
    chomp ($value);
    return $value;
}

=item
C<< Bootloader::Tools::InitLibrary (); >>

initializes the bootloader configuration library. Fills its internal structures
needed for it to run properly.

=cut

sub InitLibrary
{
  $lib_ref = Bootloader::Library->new();

  my $um = GetUdevMapping();
  my $mp = ReadMountPoints($um);
  my $part = ReadPartitions($um);
  my $md = ReadRAID1Arrays($um);
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
sub match_section {
    my ($sect_ref, $opt_ref,) = @_;
    my $match = 1;

    $lib_ref->milestone("matching section name: " . $sect_ref->{"name"});

    foreach my $opt (keys %{$opt_ref}) {
	next unless exists $sect_ref->{"$opt"};
	# FIXME: if opt_ref doesn't have (hdX,Y), there is a mountpoint, thus remove it from sect_ref
        # FIXME: to compare !!
	$lib_ref->milestone("matching key: $opt");
	if ($opt eq "image" or $opt eq "initrd") {
	    $match = (ResolveCrossDeviceSymlinks($sect_ref->{"$opt"}) eq
		      ResolveCrossDeviceSymlinks($opt_ref->{"$opt"}));
	    # Print info for this match
	    $lib_ref->milestone("key: $opt, matched: " .
		ResolveCrossDeviceSymlinks($sect_ref->{"$opt"}) .
		", with: " . ResolveCrossDeviceSymlinks($opt_ref->{"$opt"}) . ", result: $match");
	}
	else {
	    $match = ($sect_ref->{"$opt"} eq $opt_ref->{"$opt"});
	    # Print info for this match
	    $lib_ref->milestone("key: $opt, matched: " .
		$sect_ref->{"$opt"} . ", with: " . $opt_ref->{"$opt"} . ", result: $match");
	}
	last unless $match;
    }
    $lib_ref->milestone("end result: $match");
    return $match;
}


# internal: normalize options in a way needed for 'match_section'
sub normalize_options {
    my $opt_ref = shift;

    foreach ("image", "initrd" ) {
	# Print found sections to logfile
	$lib_ref->milestone("key: $_, resolving if exists:" . $opt_ref->{"$_"});
	$opt_ref->{"$_"} = ResolveCrossDeviceSymlinks($opt_ref->{"$_"})
	    if exists $opt_ref->{"$_"};
	$lib_ref->milestone("resolved result:" . $opt_ref->{"$_"});
    }
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


sub UpdateBootloader
{
  my $avoid_init = shift;

  return $lib_ref->UpdateBootloader($avoid_init);
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
  my $default_kernel = $section{"image"};
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
    return $ref->{"image"};
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
    unless (defined $lib_ref->WriteSettings (1)) {
      $lib_ref->error("Cannot write bootloader configuration file.");
      return undef;
    }
    unless (defined $lib_ref->UpdateBootloader (1)) { # avoid initialization but write config to the right place
      $lib_ref->error("Cannot write bootloader configuration file.");
      return undef;
    }
}


=item
C<< Bootloader::Tools::GetSectionList(@selectors); >>

# FIXME: Add documentation
=cut

sub GetSectionList {
    my %option = @_;
    my $loader = GetBootloader ();

    normalize_options(\%option);
    my @sections = @{$lib_ref->GetSections ()};

    # Print sections from file to logfile
    $lib_ref->milestone("sections from file:\n' " .
			join("'\n' ",
			     map {
				 $_->{"name"};
			     } @sections) . "'\n"
		       );

    my @section_names = map {
	match_section($_, \%option) ? $_->{"name"} : ();
    } @sections;

    # Print found sections to logfile
    $lib_ref->milestone("Found sections:\n' " .
			join("'\n' ", @section_names) . "'\n"
		       );

    return @section_names;
}


=item
C<< Bootloader::Tools::GetSection($name); >>

# FIXME: Add documentation
=cut

sub GetSection {
    my $name = shift or return undef;

    foreach (@{$lib_ref->GetSections ()}) {
	return $_ if $_->{"name"} eq $name;
    }
    return undef;
}

=item
C<< Bootloader::Tools::GetFittingSection($name, $image, $type, \@sections); >>

Fing fitting section for given name and image type.
If not find return undef.

=cut

sub GetFittingSection {
  my $name = shift;
  my $image = shift;
  my $type = shift;
  my $sections = shift;
  my $ret = undef;


  if ($image !~ m/^.*-([a-zA-Z0-9]+)(\..*)?$/) {
    return undef;
  }
  my $flavor = $1;
  my $fallback = ($name =~ m/failsafe/i);
 
  # Heuristic one - try find same flavor
  foreach my $s (@{$sections}) {
    next unless $s->{"type"} eq $type;
    if (defined ($s->{"image"}) && $s->{"image"} =~ m/$flavor/) {
      my $sec_fallback = (defined $s->{"original_name"} && $s->{"original_name"} =~ m/failsafe/i) ||
                         (defined $s->{"name"} && $s->{"name"} =~ m/failsafe/i);
      next if ($sec_fallback xor $fallback); #skip if they are not same failsafe or non-failsafe
      $ret = $s;
      last;
    }
  }

  return $ret if $ret;

  # Heuristic two - first fitting section with same type
  foreach my $s (@{$sections}) {
    next unless $s->{"type"} eq $type;
    my $sec_fallback = (defined $s->{"original_name"} && $s->{"original_name"} =~ m/failsafe/i) ||
                       (defined $s->{"name"} && $s->{"name"} =~ m/failsafe/i);
    next if ($sec_fallback xor $fallback); #skip if they are not same failsafe or non-failsafe
    $ret = $s;
    last;
  }

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

sub AddSection {
    my $name = shift;
    my %option = @_;

    return unless defined $name;
    return unless exists $option{"type"};

    my $default = delete $option{"default"} || 0;
    my %new = ();
    my %def = ();

    my @sections = @{$lib_ref->GetSections ()};

    my $fitting_section = GetFittingSection($name,$option{"image"},$option{"type"},\@sections);

    if ($fitting_section) {
      %def = %{$fitting_section};
      $lib_ref->milestone("Fitting section found so use it.");
      while ((my $k, my $v) = each (%def)) {
        if (substr ($k, 0, 2) ne "__" && $k ne "original_name"
        		&& $k ne "initrd") {
          $new{$k} = $v;
      	}
      }

      if (exists $option{"image"}) {
        if (exists $new{"kernel"}) { 
    	    $new{"kernel"} = delete $option{"image"};
        }	else {	
    	    $new{"image"} = delete $option{"image"};
      	}
      }
      } else {
        $lib_ref->milestone("Fitting section not found. Use sysconfig values as fallback.");
        my $sysconf;
        if ($name =~ m/^Failsafe.*$/ or $option{"original_name"} eq "failsafe") {
          $sysconf =  GetSysconfigValue("FAILSAFE_APPEND");
          $new{"append"} = $sysconf if (defined $sysconf);
          $sysconf = GetSysconfigValue("FAILSAFE_VGA");
          $new{"vgamode"} = $sysconf if (defined $sysconf);
          $sysconf = GetSysconfigValue("IMAGEPCR");
        }
        elsif ($option{"type"} eq "xen") 
        {
          $sysconf = GetSysconfigValue("XEN_KERNEL_APPEND");
          $new{"append"} = $sysconf if (defined $sysconf);
          $sysconf =  GetSysconfigValue("XEN_VGA");
          $new{"vgamode"} = $sysconf if (defined $sysconf);
          $sysconf =  GetSysconfigValue("XEN_APPEND");
          $new{"xen_append"} =  $sysconf if (defined $sysconf);
        }
        else 
        {
          #RT kernel have special args bnc #450153
          if ($new{"image"} =~ m/-rt$/ && defined (GetSysconfigValue("RT_APPEND"))){
            $sysconf = GetSysconfigValue("RT_APPEND");
            $new{"append"} = $sysconf if (defined $sysconf);
            $sysconf = GetSysconfigValue("RT_VGA");
            $new{"vgamode"} = $sysconf if (defined $sysconf);
          } else {
            $sysconf = GetSysconfigValue("DEFAULT_APPEND");
            $new{"append"} = $sysconf if (defined $sysconf);
            $sysconf = GetSysconfigValue("DEFAULT_VGA");
            $new{"vgamode"} = $sysconf if (defined $sysconf);
          }
      }

      $sysconf = GetSysconfigValue("CONSOLE");
      $new{"console"} = $sysconf if (defined $sysconf);
    }

    foreach (keys %option) {
      $new{"$_"} = $option{"$_"};
    }
    $new{"name"} = $name;

    # Append flavor appendix to section label if necessary
    AdjustSectionNameAppendix ("add", \%new);

    my $failsafe_modified = 0;
    if ($name =~ m/^Failsafe.*$/ or $option{"original_name"} eq "failsafe") {
      $failsafe_modified = 1;
	    $default = 0;
    }

    $new{"__modified"} = 1;
    $new{"root"} = $lib_ref->GetMountPoints()->{"/"};

    my $match = '';
    my $new_name = '';

    my $loader = Bootloader::Tools::GetBootloader ();

    if ($loader ne "grub" and $loader ne "lilo") {
        # Search for duplicate boot entry label and rename them in a unique way
	foreach my $s (@sections) {
	    while ((my $k, my $v) = each (%$s)) {
		if ($k eq "name" && index ($v, $new{"name"}) >= 0) {
		    $match += 1;
		    $new_name = $new{"name"} . "V" . $match;

		    if ($new_name eq $v) {
			$match += 1;
			$new_name = $new{"name"} . "V" . $match;
		    }
		    $new{"name"} = $new_name;
		}
	    }
	}
    }

    # Print new section to be added to logfile
    $lib_ref->milestone("New section to be added:\n\n' " .
			join("'\n' ",
			     map {
				 $_ . " => '" . $new{$_} . "'";
			     } keys %new) . "'\n"
		       );

    # Put new entries on top
    unshift @sections, \%new;

    my $mp_ref = ReadMountPoints ();
    my $root_mp = '';
    my $boot_mp = '';
    my $valid_part = 1;

    while ((my $k, my $v) = each (%$mp_ref)) {
	$root_mp = $v if ($k eq "/");
	$boot_mp = $v if ($k eq "/boot");
    }

    # Switch the first 2 entries in @sections array to put the normal entry on
    # top of corresponding failsafe entry
    if (($failsafe_modified == 1) && scalar (@sections) >= 2) {
	my $failsafe_entry = shift (@sections);
	my $normal_entry = shift (@sections);

	# Delete obsolete (normal) boot entries from section array
	my $section_index = 0;
	foreach my $s (@sections) {
	    if (exists $normal_entry->{"image"} && $normal_entry->{"image"} eq $s->{"image"}) {
		delete $sections[$section_index];
	    }
	    else {
		$section_index++;
	    }
	}

	# Delete obsolete (failsafe) boot entries from section array
	$section_index = 0;
	foreach my $s (@sections) {
	    if (exists $failsafe_entry->{"image"} && $failsafe_entry->{"image"} eq $s->{"image"}) {
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
    $lib_ref->milestone("All available sections (including new ones):\n");

    my $section_count = 1;
    foreach my $s (@sections) {
	$lib_ref->milestone("$section_count. section :\n' " .
			    join("'\n' ",
				 map {
				     m/^__/ ? () : $_ . " => '" . $s->{$_} . "'";
				 } keys %{$s}) . "'\n"
			   );
	$section_count++;
    }

    $lib_ref->SetSections (\@sections);

    # If the former default boot entry is updated, the new one will become now
    # the new default entry.
    my $glob_ref = $lib_ref->GetGlobalSettings ();
    $default = 1 if (delete($glob_ref->{"removed_default"}) == 1);
    $default = 1 unless (defined ($glob_ref->{"default"}) && $glob_ref->{"default"} ne ""); #avoid non-exist default
    if ($default) {
	$glob_ref->{"default"} = $new{"name"};
        if ($loader eq "lilo") #remove read-only flag bnc #381669
        {
          delete $glob_ref->{"read-only"};
        }
	$glob_ref->{"__modified"} = 1;
	$lib_ref->SetGlobalSettings ($glob_ref);
    }

    # If a non default entry is updated, the index of the current
    # default entry has to be increased, because it is shifted down in the
    # array of sections. Only do this for grub.
    elsif ($loader eq "grub") {
        my $array_ref = $glob_ref->{"__lines"};

        foreach my $line (@$array_ref) {
            if ($line->{"key"} eq "default") {
                $line->{"value"} += 1;
            }
        }
        $lib_ref->SetGlobalSettings ($glob_ref);
    }

    # Print globals to logfile
    $lib_ref->milestone("Global section of config:\n\n' " .
			join("'\n' ",
			     map {
				 m/^__/ ? () : $_ . " => '" . $glob_ref->{$_} . "'";
			     } keys %{$glob_ref}) . "'\n"
		       );

    unless (defined $lib_ref->WriteSettings (1)) {
      $lib_ref->error("Cannot write bootloader configuration file.");
      return undef;
    }
    unless (defined $lib_ref->UpdateBootloader (1)) { # avoid initialization but write config to the right place
      $lib_ref->error("Cannot write bootloader configuration file.");
      return undef;
    }
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

sub RemoveSections {
    my %option = @_;
    my @sections = @{$lib_ref->GetSections()};
    my $glob_ref = $lib_ref->GetGlobalSettings();
    my $default_section = $glob_ref->{"default"} || "";
    my $default_removed = 0;

    my $loader = GetBootloader();

    # Print section to be removed to logfile
    $lib_ref->milestone("Old section to be removed :\n\n' " .
			join("'\n' ",
			     map {
				 $_ . " => '" . $option{$_} . "'";
			     } keys %option) . "'\n"
		       );

    # Print all available sections (before removal) to logfile
    $lib_ref->milestone("All available sections (before removal):\n");

    my $section_count = 1;
    foreach my $s (@sections) {
	$lib_ref->milestone("$section_count. section :\n' " .
			    join("'\n' ",
				 map {
				     m/^__/ ? () : $_ . " => '" . $s->{$_} . "'";
				 } keys %{$s}) . "'\n"
			   );
	$section_count++;
    }

    my @section_names_before_removal = ();

    # Extract section names (before removal) out of @sections array
    foreach my $s (@sections) {
	push (@section_names_before_removal, $s->{"name"});
    }

    normalize_options(\%option);
    @sections = grep {
	my $match = match_section($_, \%option);
	$default_removed = 1
	    if $match and $default_section eq $_->{"name"};
	!$match;
    } @sections;
    $lib_ref->milestone("default is removed by grep") if $default_removed;

    # Detect wether we have an entry with an initrd line referring to a non
    # existing initrd file and remove this section respectively.
    if ($loader eq "grub") {
	@sections = grep {
	    my $match = 1;

	    # Check if there is a member called "initrd". If this is not the
	    # case, do not throw out the corresponding section because boot
	    # entries without an initrd are allowed, too.
	    if (exists $_->{"initrd"}) {
		my $initrd_name = $_->{"initrd"};
		my $other_part = 0;

		$other_part = 1 if $initrd_name =~ m/\(hd.+\)/;
		$initrd_name =~ s/^.*(initrd-.+)$/$1/;
		$initrd_name = "/boot/" . $initrd_name;

		if (!$other_part and !-f $initrd_name and
		    ($_->{"type"} eq "image" or $_->{"type"} eq "xen")) {
		    $match = 0;
                    $lib_ref->milestone(
                	"Remove non-existing initrd :".$_->{"name"}." -- $initrd_name \n");
		}

		$default_removed = 1
		    if !$match and $default_section eq $_->{"name"};
	    }
	    $match;
	} @sections;
    }

    my @section_names_after_removal = ();

    # Extract section names (after removal) out of @sections array
    foreach my $s (@sections) {
	push (@section_names_after_removal, $s->{"name"});
    }

    # Remove flavor appendix from section labels if necessary
    AdjustSectionNameAppendix ("remove",
	\@section_names_before_removal,
	\@section_names_after_removal);

    # Print all available sections (after removal) to logfile
    $lib_ref->milestone(
	"All available sections (after removal):\n");

    $section_count = 1;
    foreach my $s (@sections) {
	$lib_ref->milestone("$section_count. section :\n' " .
			    join("'\n' ",
				 map {
				     m/^__/ ? () : $_ . " => '" . $s->{$_} . "'";
				 } keys %{$s}) . "'\n"
			   );
	$section_count++;
    }

    $lib_ref->SetSections (\@sections);
    if ($default_removed) {
	$glob_ref->{"default"} = $sections[0]{"name"};
        $lib_ref->milestone("removed default");
	$glob_ref->{"removed_default"} = 1;
    }
    $glob_ref->{"__modified"} = 1; # needed because of GRUB - index of default
				   # may change even if not deleted
    $lib_ref->SetGlobalSettings ($glob_ref);
    unless (defined $lib_ref->WriteSettings (1)) {
      $lib_ref->error("Cannot write bootloader configuration file.");
      return undef;
    }
    unless (defined $lib_ref->UpdateBootloader (1)) { # avoid initialization but write config to the right place
      $lib_ref->error("Cannot write bootloader configuration file.");
      return undef;
    }
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

sub AdjustSectionNameAppendix {
    my ($mode, $sect_ref_new, $sect_ref_old) = @_;

    my @sections = @{$lib_ref->GetSections()};

    if ($mode eq "add" and %$sect_ref_new) {
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

    elsif ($mode eq "remove" and @$sect_ref_old and @$sect_ref_new) {
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
	print "Bootloader::Tools::AdjustSectionNameAppendix(): Invalid parameters.\n";
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
 
1;

#
# Local variables:
#     mode: perl
#     mode: font-lock
#     mode: auto-fill
#     fill-column: 78
# End:
#
