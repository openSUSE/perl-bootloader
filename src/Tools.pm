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

C<< $dm_dev = Bootloader::Udev2DMDev($udevdevice); >>

C<< $udev_dev = Bootloader::Tools::DMDev2Udev($dmdev); >>

C<< $majmin = Bootloader::Tools::DMDev2MajMin($dmdev); >>

C<< $majmin = Bootloader::Tools::Udev2MajMin($udev); >>

C<< $udev_dev = Bootloader::Tools::MajMin2Udev($majmin); >>

C<< $dm_dev = Bootloader::Tools::MajMin2DMDev($majmin); >>

C<< $md_ref = Bootloader::Tools::ReadRAID1Arrays (); >>

C<< $loader = Bootloader::Tools::GetBootloader (); >>

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

C<< $exec_with_path = Bootloader::Tools::AddPathToExecutable($executable); >>

=head1 DESCRIPTION

=over 2

=cut


package Bootloader::Tools;

use strict;
use base 'Exporter';

our @EXPORT = qw(InitLibrary CountImageSections CountSections
		 RemoveImageSections GetDefaultImage
		 GetDefaultInitrd GetBootloader UpdateBootloader
		 GetGlobals SetGlobals
		 GetSectionList GetSection AddSection RemoveSections
);

use Bootloader::Library;
use Bootloader::Core;

my $lib_ref = undef;
my $dmsetup = undef;

sub DumpLog {
    foreach my $rec (@{$lib_ref->GetLogRecords ()})
    {
	my $message = $rec->{"message"};
	my $level = $rec->{"level"};
	if ($level eq "debug")
	{
	    #print STDERR ("DEBUG: $message\n");
	}
	elsif ($level eq "milestone")
	{
	    #print STDERR ("MILESTONE: $message\n");
	}
	elsif ($level eq "warning")
	{
	    print STDERR ("WARNING: $message\n");
	}
	elsif ($level eq "error")
	{
	    print STDERR ("ERROR: $message\n");
	}
	else
	{
	    print STDERR ("ERROR: Uncomplete log record\n");
	    print STDERR ("ERROR: $message\n");
	}
    }
}

sub ResolveCrossDeviceSymlinks {
    my $path = shift;

    my $core_lib = Bootloader::Core->new ();
    $path = $core_lib->RealFileName ($path);
    return $path;
}

=item
C<< $mp_ref = Bootloader::Tools::ReadMountPoints (); >>

reads the information about mountpoints in the system. The returned
data is needed to initialize the bootloader library properly.

See InitLibrary function for example.

=cut

sub ReadMountPoints {
    open (FILE, "/etc/fstab") || 
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
		    open (BLKID, "/sbin/blkid -t $dev |") || 
			die ("ReadMountPoints(): Failed to run blkid");

		    my $line = <BLKID>;
		    close (BLKID);
		    chomp ($line);
		    my $index = index ($line, ":");
		    if ($index != -1)
		    {
			$dev = substr ($line, 0, $index);
		    }
		}
		$mountpoints{$mp} = $dev;
	    }
	}
    }
    close (FILE);
    return \%mountpoints;
}

sub Udev2Dev {
    my $udev = shift;
    my $cmd = "udevinfo -q name -p /block/$udev";
    my $dev = qx{ $cmd 2>/dev/null };
    chomp ($dev);

    $dev = $dev ? "/dev/$dev" : "/dev/$udev";
    # CCISS maps slashes to bangs so we have to reverse that.
    $dev =~ s:!:/:g;

    return $dev;
}

=item
C<< $part_ref = Bootloader::Tools::ReadPartitions (); >>

reads the information about disk partitions. This data is needed
to initialize the bootloader library properly.

See InitLibrary function for example.

=cut

# FIXME: this has to be read through yast::storage
sub ReadPartitions {
    my $sb="/sys/block";
    opendir(BLOCK_DEVICES, "$sb") || 
	die ("ReadPartitions(): Failed to open dir $sb");

    my @disks = grep {
	!m/^\./ and -r "$sb/$_/range" and qx{ cat $sb/$_/range } > 1
    } readdir(BLOCK_DEVICES);
    closedir BLOCK_DEVICES;

    my @devices = ();
    # Add DM RAID Partitions to @devices
    if (DMRaidAvailable()){
        my $dev_ref = ReadDMRaidPartitions();   
        push (@devices, @{$dev_ref});

    }

    foreach my $disk (@disks)
    {
	my $dev_disk = Udev2Dev ($disk);
        if (!IsDMDevice($disk) && !IsDMRaidSlave($disk)){
	    opendir(BLOCK_DEVICES, "$sb/$disk") ||
	        die ("ReadPartitions(): Failed to open dir $sb/$disk");

	    my @parts = grep {
	        !m/^\./ and -d "$sb/$disk/$_" and -f "$sb/$disk/$_/dev"
	    }  readdir (BLOCK_DEVICES);
	    closedir BLOCK_DEVICES;

	    foreach my $part (@parts)
	    {
	        chomp ($part);
	        $part = Udev2Dev ("$disk/$part");
	        my $index = substr ($part, length ($dev_disk));
	        while (length ($index) > 0 && substr ($index, 0, 1) !~ /[0-9]/)
	        {
		    $index = substr ($index, 1);
	        }
	        push @devices, [$part, $dev_disk, $index];
            }
	}
    }
    return \@devices;
}

=item
C<< Bootloader::Tools::DMRaidAvailable (); >>

Tests wether DMRAID is available.
Return 0 if no device, 1 if there are any.

=cut

sub DMRaidAvailable {
    my $retval = 1;

    $dmsetup = AddPathToExecutable("dmsetup");

    if (-e $dmsetup) {
	my $dm_devices = qx{$dmsetup info -c --noheadings -o uuid};
	chomp($dm_devices);

	if ($dm_devices eq "No devices found") {
	    $retval = 0;
	}
    }
    else {
	print ("The command \"dmsetup\" is not available.\n");
	print ("Is the package \"device-mapper\" installed?\n");
    }
    
    return $retval;
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

#FIXME: this has to be done through Storage
sub ReadDMRaidPartitions {

    my @dmdisks = ();
    my @dmparts = ();
    my $dmdev;


    open(DMDEV, "$dmsetup info -c --noheadings -o name |") || 
	die ("ReadDMRaidPartitions(): dmsetup failed.");

    while (<DMDEV>) {
	$dmdev = $_;
	chomp($dmdev);

	#FIXME: I should not need to do this twice
	if ($dmdev !~ m/part/) {
	    # $dmdev is the base device
	    $dmdev = "/dev/mapper/" . $dmdev;
	    push @dmdisks, $dmdev;
	}
	#FIXME: need to check what needs to be removed
	else {
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
    my $majmin_disk = Udev2MajMin($disk);
    chomp($majmin_disk);
    my @dmparts = ();
    my @dm_devs = qx{$dmsetup info -c --noheadings -o name | grep -v part};

    if ($dm_devs[0] !~ /No devices found/) {
        foreach my $dmdisk (@dm_devs) {
            my @tables = qx{$dmsetup table $dmdisk};

            foreach my $line (@tables) {
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

    my $cmd = "$dmsetup info -c --noheadings -oname $dev";
    if (my $test = qx{$cmd 2>/dev/null}){
        chomp $test;

        if ($dev =~ m/$test/){
            return 1;
        }
    }
    return 0;
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

sub Bootloader::Tools::DMDev2MajMin {

    my $dmdev = shift;
    my $majmin;
    $majmin =  qx{$dmsetup info -c  --noheadings -o major,minor $dmdev};

    return $majmin;
}


=item
C<< $majmin = Bootloader::Tools::Udev2MajMin($udev); >>
takes a udev device as reported from udevinfo
returns a string containing major:minor

=cut

sub Bootloader::Tools::Udev2MajMin {

    my $udev_dev = shift;
    my $majmin;
    my $cmd = "udevinfo -qpath -n $udev_dev";

    if (my $udev_path = qx{$cmd 2>/dev/null}){
       chomp ($udev_path);
       $majmin = qx{cat /sys$udev_path/dev};
    }
    chomp ($majmin);
    return $majmin;
}

=item
C<< $udev_dev = Bootloader::Tools::MajMin2Udev($majmin); >>
takes a string major:minor as reported from udevinfo
returns a string containing the udev device as reported 
by udevinfo

=cut

sub Bootloader::Tools::MajMin2Udev {

    my $majmin = shift;

    my ($major,  $minor) = split (/:/, $majmin );
    my $udevdev;
    my $sb="/sys/block";
    my $devmajmin;

    opendir (SYSBLOCK, "$sb");

    foreach my $dirent (readdir(SYSBLOCK)) {
	next if $dirent =~ m/^\./;
	next if -r "$sb/$dirent/range" and qx{ cat $sb/$dirent/range } == 1;
	$devmajmin = qx{cat $sb/$dirent/dev};
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

    return $part;
}

=item
C<< $dm_dev = Bootloader::Tools::DMDev2MajMin($majmin); >>
takes a string major:minor as reported from udevinfo
returns a string containing the device as reported by 
dmsetup

=cut

sub Bootloader::Tools::MajMin2DMDev {

    my $majmin = shift;
    my $dm_name  =  qx{devmap_name $majmin};

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

    my @members = ();
    open (MD, "/sbin/mdadm --detail --verbose --scan |") ||
        die ("ReadRAID1Arrays(): Failed getting information about MD arrays");

    my ($array, $level, $num_devices);
    while (my $line = <MD>)
    {
        chomp ($line);

        if ($line =~ /ARRAY (\S+) level=(\w+) num-devices=(\d+)/)
        {
            ($array, $level, $num_devices) = ($1, $2, $3);
        }
        elsif ($level eq "raid1" and $line =~ /devices=(\S+)/)
        {
            # we could test $num_device against number of found devices to
            # detect degradedmode but that does not matter here (really?) 
             $mapping{$array} = [ split(/,/, $1) ];
        }
    }
    close( MD );

    return \%mapping;
}

=item
C<< $loader = Bootloader::Tools::GetBootloader (); >>

returns the used bootloader. Reads the value from sysconfig.
Returns the string - bootloader type.

See InitLibrary function for example.

=cut

# FIXME: this has to be read through yast::storage or such
sub GetBootloader {
    my $lt = qx{ . /etc/sysconfig/bootloader && echo \$LOADER_TYPE } or
	die ("GetBootloader(): Cannot determine the loader type");
    chomp ($lt);
    return $lt;
}   

=item
C<< Bootloader::Tools::InitLibrary (); >>

initializes the bootloader configuration library. Fills its internal structures
needed for it to run properly.

=cut

sub InitLibrary {
    $lib_ref = Bootloader::Library->new ();
    my $mp = ReadMountPoints ();
    my $part = ReadPartitions ();
    my $md = ReadRAID1Arrays ();

    $lib_ref->SetLoaderType (GetBootloader ());
    $lib_ref->DefineMountPoints ($mp);
    $lib_ref->DefinePartitions ($part);
    $lib_ref->DefineMDArrays ($md);

    # parse Bootloader configuration files   
    $lib_ref->ReadSettings();

    DumpLog ();
}

# internal: does section match with set of tags
sub match_section {
    my ($sect_ref, $opt_ref,) = @_;
    my $match = 0;

    foreach my $opt (keys %{$opt_ref}) {
	next unless exists $sect_ref->{"$opt"};
	# FIXME: avoid "kernel"
	# FIXME: if opt_ref doesn't have (hdX,Y), there is a mountpoint, thus remove it from sect_ref
        # FIXME: to compare !!
	if ($opt eq "image" or $opt eq "kernel" or $opt eq "initrd") {
	    $match = (ResolveCrossDeviceSymlinks($sect_ref->{"$opt"}) eq
		      $opt_ref->{"$opt"});
	}
	else {
	    $match = ($sect_ref->{"$opt"} eq $opt_ref->{"$opt"});
	}
	last unless $match;
    }
    return $match;
}


# internal: normalize options in a way needed for 'match_section'
sub normalize_options {
    my $opt_ref = shift;

    foreach ("image", "initrd" ) {
	$opt_ref->{"$_"} = ResolveCrossDeviceSymlinks($opt_ref->{"$_"})
	    if exists $opt_ref->{"$_"};
    }

    # FIXME: some have "kernel" some have "image" tag, latter makes more sense
    $opt_ref->{"kernel"} = $opt_ref->{"image"} if exists $opt_ref->{"image"};
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
    $lib_ref->UpdateBootloader ();
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
    DumpLog ();
}


=item
C<< Bootloader::Tools::GetSectionList(@selectors); >>

# FIXME: Add documentation
=cut

sub GetSectionList {
    my %option = @_;
    my $loader = GetBootloader ();

# FIXME: Maybe activate this part of code later if - against all expectations
# - still needed, but this shouldn't happen.
    # Examines if image and initrd strings already contain a grub device
    # prefix. If it is not the case, attach it.
=cut
    if ($loader eq "grub") {
	foreach my $key (sort keys %option) {
	    unless ($option{$key} =~ /^\(hd\d+,\d+\).*$/) {
		# In case /boot is resided on an own partition, the function
		# UnixPath2GrubPath (in GRUB.pm) doesn't substitute "/boot"
		# with the corresponding grub device, but keeps it.
		#
		# So the image, kernel and initrd values in the @sections
		# array don't contain such a grub device prefix. Thus, to
		# match sections to be deleted, a grub device prefix must not
		# be attached to the given @option elements.
		if ($lib_ref->UnixFile2GrubDev ("/boot") eq $lib_ref->UnixFile2GrubDev ("/")){
		    if ($key eq "image" || $key eq "initrd" || $key eq "kernel") {
			my $grub_dev = $lib_ref->UnixFile2GrubDev ("/boot");
			$option{$key} = $grub_dev . $option{$key};
		    }
		}
	    }
	}
    }
=cut

    normalize_options(\%option);
    my @sections = @{$lib_ref->GetSections ()};
    my @section_names = map {
	match_section($_, \%option) ? $_->{"name"} : ();
    } @sections;

    DumpLog ();
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

    my $mp = $lib_ref->GetMountPoints ();
    my @sections = @{$lib_ref->GetSections ()};
    my %new = (
	"root" => $mp->{"/"} || "/dev/null",
    );
    # FIXME: sf@: what is this code good for?
    # FIXME: removed resetting root parameter if it's already set
    my %def = ();
    foreach my $s (@sections) {
	if (defined ($s->{"initial"}) && $s->{"initial"}) {
	    %def = %{$s};
	    last;
	}
    }

    while ((my $k, my $v) = each (%def)) {
	if (substr ($k, 0, 2) ne "__" && $k ne "original_name"
		&& $k ne "initrd") {
	    if (!defined $new{$k}) {
		$new{$k} = $v;
	    }	
	}
    }

    if (exists $option{"image"}) {
	if (exists $new{"kernel"}) { 
	    $new{"kernel"} = delete $option{"image"};
	}
	else {	
	    $new{"image"} = delete $option{"image"};
	}
    }

    foreach (keys %option) {
	$new{"$_"} = $option{"$_"};
    }
    $new{"name"} = $name;

    my $failsafe_modified = 0;

    # FIXME: Failsafe parameters should be set dynamically in the future
    if ($name =~ m/^Failsafe.*$/) {
	my $arch = `uname --hardware-platform`;
	chomp ($arch);

	if ($arch eq "i386") {
	    $new{"append"} = "showopts ide=nodma apm=off acpi=off noresume nosmp noapic maxcpus=0 edd=off";
	}
	elsif ($arch eq "x86_64") {
	    $new{"append"} = "showopts ide=nodma apm=off acpi=off noresume edd=off";
	}
	elsif ($arch eq "ia64") {
	    $new{"append"} = "ide=nodma nohalt noresume";
	}
	else {
	    print ("Architecture $arch does not support failsafe entries.\n");
	}

	# Set vgamode to "normal" for failsafe entries
	if (exists $new{"vgamode"} && defined $new{"vgamode"}) {
	    $new{"vgamode"} = "normal";
	}

	$failsafe_modified = 1;

	# Don't make the failsafe entry the default one
	$default = 0;
    }
    $new{"__modified"} = 1;

    my $match = '';
    my $new_name = '';

    my $loader = Bootloader::Tools::GetBootloader ();

    if ($loader ne "grub") {
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

    # Put new entries on top
    unshift @sections, \%new;

    my $mp_ref = ReadMountPoints ();
    my $root_mp = '';
    my $boot_mp = '';
    my $valid_part = 0;

    while ((my $k, my $v) = each (%$mp_ref)) {
	$root_mp = $v if ($k eq "/");
	$boot_mp = $v if ($k eq "/boot");
    }

    # Resolve kernel symlinks (if available) to full names
    my $link_target = '';
    foreach my $s (@sections) {
	while ((my $k, my $v) = each (%$s)) {
	    if ($k eq "initrd" || $k eq "image" || $k eq "kernel") {

		if (($v =~ s#\/.*$##) && $v ne '') {
		    my $unix_dev = $lib_ref->GrubDev2UnixDev($v);

		    if ($unix_dev eq $root_mp || $unix_dev eq $boot_mp) {
			$valid_part = 1;
		    }
		    else {
			$valid_part = 0;
		    }
		}
	    }

	    if (($k eq "kernel" || $k eq "image" || $k eq "initrd") && $valid_part) {
		if ($link_target = readlink ($v)) {
		    chomp ($link_target);
		    $s->{$k} = "/boot/" . $link_target;
		}
            }

	    if (($k eq "__lines") && $valid_part) {
		my $index = 0;
		foreach my $elem (@$v) {
		    while ((my $k, my $v) = each (%$elem)) {
			if ((index ($v, "vmlinuz") >= 0 || index ($v, "initrd") >= 0)
				&& ($link_target = readlink ($v))) {
			    $v = (split (/ /, $v))[0];
			    chomp ($link_target);
			    $s->{"__lines"}[$index]->{$k} = "/boot/" . $link_target;
			}
		    }
		    $index += 1;
		}
	    }
	}
    }

    # Switch the first 2 entries in @sections array to put the normal entry on
    # top of corresponding failsafe entry
    if (($failsafe_modified == 1) && scalar (@sections) >= 2) {
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

    $lib_ref->SetSections (\@sections);

    # If the former default boot entry is updated, the new one will become now
    # the new default entry.
    my $glob_ref = $lib_ref->GetGlobalSettings ();
    if ($default) {
	$glob_ref->{"default"} = $new{"name"};
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

    $lib_ref->WriteSettings (1);
    $lib_ref->UpdateBootloader (1); # avoid initialization but write config to
                                    # the right place

    DumpLog ();
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
C<< Bootloader::Tools::RemoveSection($name); >>

=cut

sub RemoveSections {
    my %option = @_;
    my @sections = @{$lib_ref->GetSections()};
    my $glob_ref = $lib_ref->GetGlobalSettings();
    my $default_section = $glob_ref->{"default"} || "";
    my $default_removed = 0;

# FIXME: Maybe activate this part of code later if - against all expectations 
# - still needed, but this shouldn't happen.
    my $loader = GetBootloader ();
    # Examines if image and initrd strings already contain a grub device
    # prefix. If it is not the case, attach it.
=cut
    if ($loader eq "grub") {
	foreach my $key (sort keys %option) {
	    unless ($option{$key} =~ /^\(hd\d+,\d+\).*$/) {
		print ("(hdx,y) not detected, key = $key,\tval = $option{$key}\n");
		# In case /boot is resided on an own partition, the function
		# UnixPath2GrubPath (in GRUB.pm) doesn't substitute "/boot"
		# with the corresponding grub device, but keeps it.
		#
		# So the image, kernel and initrd values in the @sections
		# array don't contain such a grub device prefix. Thus, to
		# match sections to be deleted, a grub device prefix must not
		# be attached to the given @option elements.
		if ($lib_ref->UnixFile2GrubDev ("/boot") eq $lib_ref->UnixFile2GrubDev ("/")){
		    print("equal\n");			
		    if ($key eq "image" || $key eq "initrd" || $key eq "kernel") {
			my $grub_dev = $lib_ref->UnixFile2GrubDev ("/boot");
			$option{$key} = $grub_dev . $option{$key};
		    }
		}
	    }
	}
    }
=cut

    normalize_options(\%option);
    @sections = grep {
	my $match = match_section($_, \%option);
	$default_removed = 1
	    if $match and $default_section eq $_->{"name"};
	!$match;
    } @sections;

    $lib_ref->SetSections (\@sections);
    if ($default_removed) {
	$glob_ref->{"default"} = $sections[0]{"name"};
    }
    $glob_ref->{"__modified"} = 1; # needed because of GRUB - index of default
				   # may change even if not deleted
    $lib_ref->SetGlobalSettings ($glob_ref);
    $lib_ref->WriteSettings (1);
    $lib_ref->UpdateBootloader (1); # avoid initialization but write config to
                                    # the right place

    DumpLog ();
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
