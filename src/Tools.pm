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

C<< Bootloader::Tools::AdaptCommentLine($old_sections_ref, $original_name); >>

C<< Bootloader::Tools::AddSection($name, @params); >>

C<< Bootloader::Tools::RemoveSections($name); >>

C<< Bootloader::Tools::AdjustSectionNameAppendix ($mode, $sect_ref_new, $sect_ref_old); >>

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
		 GetSectionList GetSection AdaptCommentLine
		 AddSection RemoveSections
);

use Bootloader::Library;
use Bootloader::Core;

my $lib_ref = undef;

sub DumpLog {
    my $core_lib = shift;

    my $perl_logfile = "/var/log/YaST2/perl-BL-standalone-log";
    my $using_logfile = 1;

    if (not open LOGFILE, ">>$perl_logfile") {
	$using_logfile = 0;
	open LOGFILE, ">&STDERR" or die "Can't dup STDERR: $!";
	print LOGFILE ("WARNING: Can't open $perl_logfile, using STDERR instead.\n");
    }

    # Adding timestamp to log messages
    use POSIX qw(strftime);

    sub timestamp () {
	return strftime ( "%Y-%m-%d %H:%M:%S", localtime);
    }

    foreach my $rec (@{$core_lib->GetLogRecords ()})
    {
	my $message = $rec->{"message"};
	my $level = $rec->{"level"};

	# If debug messages should be printed, the environment variable
	# Y2DEBUG has to be set ("export Y2DEBUG=1").
	if ($level eq "debug" and defined $ENV{'Y2DEBUG'})
	{
	    print LOGFILE (timestamp() . "DEBUG: $message\n");
	}
	elsif ($level eq "debug" and not defined $ENV{'Y2DEBUG'})
	{
	    # Omit debug messages
	}
	elsif ($level eq "milestone")
	{
	    print LOGFILE (timestamp() . "MILESTONE: $message\n");
	}
	elsif ($level eq "warning")
	{
	    print LOGFILE (timestamp() . "WARNING: $message\n");

	    # If writing to perl logfile, also print warnings to STDERR
	    if ($using_logfile) {
		print STDERR (timestamp() . "WARNING: $message\n");
	    }
	}
	elsif ($level eq "error")
	{
	    print LOGFILE (timestamp() . "ERROR: $message\n");

	    # If writing to perl logfile, also print errors to STDERR
	    if ($using_logfile) {
		print STDERR (timestamp() . "ERROR: $message\n");
	    }
	}
	else
	{
	    print LOGFILE (timestamp() . "ERROR: Uncomplete log record\n");
	    print LOGFILE (timestamp() . "ERROR: $message\n");

	    # If writing to perl logfile, also print errors to STDERR
	    if ($using_logfile) {
		print STDERR (timestamp() . "ERROR: Uncomplete log record\n");
		print STDERR (timestamp() . "ERROR: $message\n");
	    }
	}
    }
    close LOGFILE;
}

sub ResolveCrossDeviceSymlinks {
    my $path = shift;

    my $core_lib = Bootloader::Core->new ();
    $path = $core_lib->RealFileName ($path);

    DumpLog ($core_lib);
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
			die ("ReadMoountPoints(): Failed to run blkid");

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

    # FIXME: maybe useless code
    my $cmd = "udevinfo -q name -p /block/$udev";
    my $dev = qx{ $cmd 2>/dev/null };
    chomp ($dev);

    if ($dev ne "") {
        $dev = "/dev/$dev";
    }

    # Fallback in case udevinfo fails
    else {

	#If $udev consists of both device and partition - e.g. "sda/sda1" -
	#then only assign the partition.
    	if ($udev =~ m#\w+/(\w+)#) {
	    $dev = "/dev/$1";
	}

	#Else, just assign the content of $udev, e.g. "sda".
	else {
	    $dev = "/dev/$udev";
	}
    }

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
    my $sb = "/sys/block";
    opendir(BLOCK_DEVICES, "$sb") || 
	die ("ReadPartitions(): Failed to open dir $sb");

    # get disk devices
    my @disks = grep {
	!m/^\./ and -r "$sb/$_/range" and qx{ cat $sb/$_/range } > 1
    } readdir(BLOCK_DEVICES);
    closedir BLOCK_DEVICES;

    # get partition info for all partitions on all @disks
    my @devices = ();
    foreach my $disk (@disks)
    {
	# get kernel device name for this device
	my $dev_disk = Udev2Dev ($disk);

	# get additional info from parted for the partitions on this $disk
	#
	# Disk geometry for /dev/sdb: 0cyl - 14593cyl
	# BIOS cylinder,head,sector geometry: 14593,255,63.  Each cylinder is 8225kB.
	# Disk label type: msdos
	# Number  Start   End     Size    Type      File system  Flags
	# 1       0cyl    63cyl   63cyl   primary   reiserfs     raid, type=fd
	# 2       64cyl   2022cyl 1959cyl primary   ext3         boot, raid, type=fd
	# 3       2023cyl 3067cyl 1045cyl primary   linux-swap   raid, type=fd
	# 4       3068cyl 14592cyl 11525cyl extended               lba, type=0f
	# 5       3068cyl 3198cyl 130cyl  logical   reiserfs     type=83
	#
	my @parted_info_list = ();
	my $parted_info = `parted -s $dev_disk unit cyl print`;
	if ( $? == 0 ) {
	    my @parted_info_split = split(/\n/, $parted_info);
	    # skip header lines


	    while ($#parted_info_split >=0 and $parted_info_split[0] !~ /^\s*\d/) {
		shift @parted_info_split;
	    }

	    foreach $parted_info (@parted_info_split) {
		# FIXME: parse the rest of the lines
		chomp($parted_info);
		my ($p_nr, $p_startcyl, $p_endcyl, $p_sizecyl, $p_type, $rest) =
		    split(' ', $parted_info);

		$p_startcyl =~ s/cyl$//;
		$p_endcyl   =~ s/cyl$//;
		$p_sizecyl  =~ s/cyl$//;
		$p_type	    =~ s/^/`/;

		# array: part_nr -> (startcyl, endcyl, sizecyl, type)
		$parted_info_list[$p_nr] =
		    [$p_startcyl, $p_endcyl, $p_sizecyl, $p_type];
	    }
	}

	# get partitions of $disk
	opendir(BLOCK_DEVICES, "$sb/$disk") ||
	    die ("ReadPartitions(): Failed to open dir $sb/$disk");

	my @parts = grep {
	    !m/^\./ and -d "$sb/$disk/$_" and -f "$sb/$disk/$_/dev"
	} readdir (BLOCK_DEVICES);
	closedir BLOCK_DEVICES;

	# generate proper device names and other info for all @part[ition]s
	foreach my $part (@parts)
	{
	    chomp ($part);
	    $part = Udev2Dev ("$disk/$part");
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
	    #  3    fsid	    258
	    #  4    fstype	    Apple_HFS
	    #  5    part_type	    `primary
	    #  6    start_cyl	    0
	    #  7    size_cyl	    18237

	    push @devices, [$part, $dev_disk, $index, 0, "",
		defined( $parted_info_list[$index]->[3] ) ?
		    $parted_info_list[$index]->[3] : "",
		defined( $parted_info_list[$index]->[0] ) ?
		    $parted_info_list[$index]->[0] : 0,
		defined( $parted_info_list[$index]->[1] ) ?
		    $parted_info_list[$index]->[1] : 0];
	}
    }
    return \@devices;
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

    DumpLog ($lib_ref->{"loader"});
}


# internal: does section match with set of tags
sub match_section {
    my ($sect_ref, $opt_ref,) = @_;
    my $match = 0;

    my $loader = GetBootloader ();
    my $core_lib = $lib_ref->{"loader"};

    $core_lib->l_milestone ("Tools::match_section: matching section name: " . $sect_ref->{"name"});

    foreach my $opt (keys %{$opt_ref}) {
	next unless exists $sect_ref->{"$opt"};

	$core_lib->l_milestone ("Tools::match_section: matching key: $opt");

	# FIXME: avoid "kernel"
	# FIXME: if opt_ref doesn't have (hdX,Y), there is a mountpoint, thus remove it from sect_ref
        # FIXME: to compare !!
	if ($opt eq "image" or $opt eq "kernel" or $opt eq "initrd") {

	    # Only do this in case /boot is located on a single boot evms device
	    if (boot_is_on_evms () and $loader eq "grub" and $sect_ref->{"$opt"} =~ m/^(\(hd\d+,\d+\)).*$/) {
		my $device_map_ref = $lib_ref->GetDeviceMapping ();
		my $grub_boot_dev = Bootloader::Core::GRUB::BootDev2GrubDev ($device_map_ref);
		$opt_ref->{"$opt"} =~ s#/boot#$grub_boot_dev#;
	    }
	    $match = (ResolveCrossDeviceSymlinks($sect_ref->{"$opt"}) eq
		      $opt_ref->{"$opt"});

	    # Print info for this match
	    $core_lib->l_milestone ("Tools::match_section: key: $opt, matched: " .
		ResolveCrossDeviceSymlinks($sect_ref->{"$opt"}) .
		", with: " . $opt_ref->{"$opt"} . ", result: $match");
	}
	else {
	    $match = ($sect_ref->{"$opt"} eq $opt_ref->{"$opt"});

	    # Print info for this match
	    $core_lib->l_milestone ("Tools::match_section: key: $opt, matched: " .
		$sect_ref->{"$opt"} . ", with: " . $opt_ref->{"$opt"} . ", result: $match");
	}
	last unless $match;
    }
    $core_lib->l_milestone ("Tools::match_section: end result: $match");

    return $match;
}


# internal: checks if /boot is located on a evms partition
sub boot_is_on_evms {
    my $cmd = "cat /etc/fstab |grep \"/boot\" |cut -d \" \" -f1";
    my $boot_dev = qx{ $cmd 2>/dev/null };

    if ($boot_dev =~ m#^/dev/evms/#) {
	return 1;
    }

    return 0;
}


# internal: normalize options in a way needed for 'match_section'
sub normalize_options {
    my $opt_ref = shift;

    my $core_lib = $lib_ref->{"loader"};

    foreach ("image", "initrd" ) {
	# Print found sections to logfile
	$core_lib->l_milestone ("Tools::normalize_options: key: $_, resolving if exists:" . $opt_ref->{"$_"});
	$opt_ref->{"$_"} = ResolveCrossDeviceSymlinks($opt_ref->{"$_"})
	    if exists $opt_ref->{"$_"};
	$core_lib->l_milestone ("Tools::normalize_options: resolved result:" . $opt_ref->{"$_"});
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
    DumpLog ($lib_ref->{"loader"});
}


=item
C<< Bootloader::Tools::GetSectionList(@selectors); >>

# FIXME: Add documentation
=cut

sub GetSectionList {
    my %option = @_;
    my $loader = GetBootloader ();

    my $core_lib = $lib_ref->{"loader"};

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

    # Print sections from file to logfile
    $core_lib->l_milestone ("Tools::GetSectionList: sections from file:\n' " .
			join("'\n' ",
			     map {
				 $_->{"name"};
			     } @sections) . "'\n"
		       );

    my @section_names = map {
	match_section($_, \%option) ? $_->{"name"} : ();
    } @sections;

    # Print found sections to logfile
    $core_lib->l_milestone ("Tools::GetSectionList: Found sections:\n' " .
			join("'\n' ", @section_names) . "'\n"
		       );

    DumpLog ($lib_ref->{"loader"});
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
C<< Bootloader::Tools::AdaptCommentLine($old_sections_ref, $original_name); >>

Adapt YaST-like comments in already existing sections to be handled correctly
by yast2-bootloader. Returns reference to sections array with adapted comment
lines.

EXAMPLE:

  my $old_sections_ref = $lib_ref->GetSections ();
  my $adapted_sections_ref = "";
  my $original_name = "linux";

  $adapted_sections = Bootloader::Tools::AdaptCommentLine ($old_sections_ref, $original_name);

=cut

sub AdaptCommentLine {
    my $sections_ref = shift;
    my $original_name = shift;

    return unless defined $sections_ref;
    return unless defined $original_name;

    my $comment_string = "###Don't change this comment - YaST2 identifier: Original name: ";

    # Adapt YaST-like comment in __lines member of sections array
    foreach my $sect_ref (@$sections_ref) {

	my $lines_ref = $sect_ref->{"__lines"};

	# Only check sections referring to a real kernel or xen image
	if ($sect_ref->{"type"} eq "image" or $sect_ref->{"type"} eq "xen") {
	    foreach my $line_ref (@$lines_ref) {

		my $comment = $line_ref->{"comment_before"};
		my @temp = grep m/$original_name###/, @$comment;

		# Only lines containing the section title need to be checked
		if ($line_ref->{"key"} eq "title" and scalar @temp > 0) {

		    # Determine version and flavor of section to be adapted
		    my $version_and_flavor = $sect_ref->{"initrd"};
		    $version_and_flavor =~ s/^[^-]+//;

		    my $adapted_comment = $comment_string . $original_name . $version_and_flavor . "###";

		    # Finally, adapt the comment line
		    $line_ref->{"comment_before"} = [$adapted_comment];
		}
	    }
	}

	# Remove empty lines
	foreach my $line_ref (@$lines_ref) {
	    if ($line_ref->{"key"} eq "title") {
		@{$line_ref->{"comment_before"}}  = grep m/\S/, @{$line_ref->{"comment_before"}};
	    }
	}

	# Set new comment line, thus commit changes made
	$sect_ref->{"__lines"} = $lines_ref;
    }

    return @$sections_ref;
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

    # Adapt YaST-like comment lines in old sections
    @sections = AdaptCommentLine (\@sections, $option{"original_name"});

    # FIXME: sf@: what is this code good for?
    # FIXME: removed resetting root parameter if it's already set
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

    # Append flavor appendix to section label if necessary
    AdjustSectionNameAppendix ("add", \%new);

    my $failsafe_modified = 0;

    # FIXME: Failsafe parameters should be set dynamically in the future
    if ($name =~ m/^Failsafe.*$/) {
	my $arch = `uname --hardware-platform`;
	chomp ($arch);

	if ($arch eq "i386") {
	    $new{"append"} = "showopts ide=nodma apm=off acpi=off noresume nosmp noapic maxcpus=0 edd=off 3";
	}
	elsif ($arch eq "x86_64") {
	    $new{"append"} = "showopts ide=nodma apm=off acpi=off noresume edd=off 3";
	}
	elsif ($arch eq "ia64") {
	    $new{"append"} = "ide=nodma nohalt noresume 3";
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

    my $core_lib = $lib_ref->{"loader"};

    # Print new section to be added to logfile
    $core_lib->l_milestone ("Tools::AddSection: New section to be added :\n\n' " .
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

    # Resolve kernel symlinks (if available) to full names
    my $link_target = '';
    foreach my $s (@sections) {
	while ((my $k, my $v) = each (%$s)) {
	    if ($k eq "initrd" || $k eq "image" || $k eq "kernel") {
		# Check if $v has a grub device prefix
		if (($v =~ s#\/.*$##) && $v ne '') {
		    my $unix_dev = $lib_ref->GrubDev2UnixDev($v);

		    $valid_part = 1;
		    unless ($unix_dev eq $root_mp || $unix_dev eq $boot_mp) {
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

		# Print the whole __lines structure
		# Comment out this area for debug purposes
		#foreach my $elem (@$v) {
		#    print ("__lines contains: $elem\n");
		#    while ((my $k, my $v) = each (%$elem)) {
		#	print ("key = $k,\tvalue = $v\n");
		#    }
		#    print ("\n");
		#}

		foreach my $lineref (@$v) {
		    # Search in lines cache for possible kernel symlinks
		    # and resolve them if found
		    if ($lineref->{"key"} eq "kernel") {
			my $kernel_symlink = (split (/ /, $lineref->{"value"}))[0];
			if ($link_target = readlink ($kernel_symlink)) {
			    chomp ($link_target);

			    # Create the new kernel line with long (resolved)
			    # kernel filename
			    my $kernel_line = $s->{"__lines"}[$index]->{"value"};
			    $kernel_line =~ s/(^\S*)vmlinu[xz](\s*)/\1$link_target\2/;
			    $s->{"__lines"}[$index]->{"value"} = $kernel_line;
			}
		    }

		    # Search in lines cache for possible kernel symlinks
		    # and resolve them if found
		    if ($lineref->{"key"} eq "initrd") {
			my $initrd_symlink = (split (/ /, $lineref->{"value"}))[0];
			if ($link_target = readlink ($initrd_symlink)) {
			    chomp ($link_target);

			    # Create the new initrd line with long (resolved)
			    # initrd filename
			    my $initrd_line = $s->{"__lines"}[$index]->{"value"};
			    $initrd_line =~ s/(^\S*)initrd(\s*)/\1$link_target\2/;
			    $s->{"__lines"}[$index]->{"value"} = $initrd_line;
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

    # Print all available sections to logfile
    $core_lib->l_milestone (
	"Tools::AddSection: All available sections (including new ones):\n");

    my $section_count = 1;
    foreach my $s (@sections) {
	$core_lib->l_milestone ("$section_count. section :\n' " .
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

    # Print globals to logfile
    $core_lib->l_milestone ("Tools::AddSection: Global section of config :\n\n' " .
			join("'\n' ",
			     map {
				 m/^__/ ? () : $_ . " => '" . $glob_ref->{$_} . "'";
			     } keys %{$glob_ref}) . "'\n"
		       );

    $lib_ref->WriteSettings (1);
    $lib_ref->UpdateBootloader (1); # avoid initialization but write config to
                                    # the right place

    DumpLog ($lib_ref->{"loader"});
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

    my @section_names_before_removal = ();

    # Extract section names (before removal) out of @sections array
    foreach my $s (@sections) {
	push (@section_names_before_removal, $s->{"name"});
    }

    my $core_lib = $lib_ref->{"loader"};

    # Print section to be removed to logfile
    $core_lib->l_milestone ("Tools::RemoveSections: Old section to be removed :\n\n' " .
			join("'\n' ",
			     map {
				 $_ . " => '" . $option{$_} . "'";
			     } keys %option) . "'\n"
		       );

    # Print all available sections (before removal) to logfile
    $core_lib->l_milestone (
	"Tools::RemoveSections: All available sections (before removal):\n");

    my $section_count = 1;
    foreach my $s (@sections) {
	$core_lib->l_milestone ("$section_count. section :\n' " .
			    join("'\n' ",
				 map {
				     m/^__/ ? () : $_ . " => '" . $s->{$_} . "'";
				 } keys %{$s}) . "'\n"
			   );
	$section_count++;
    }

    normalize_options(\%option);
    @sections = grep {
	my $match = match_section($_, \%option);
	$default_removed = 1
	    if $match and $default_section eq $_->{"name"};
	!$match;
    } @sections;

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
    $core_lib->l_milestone (
	"Tools::RemoveSections: All available sections (after removal):\n");

    $section_count = 1;
    foreach my $s (@sections) {
	$core_lib->l_milestone ("$section_count. section :\n' " .
			    join("'\n' ",
				 map {
				     m/^__/ ? () : $_ . " => '" . $s->{$_} . "'";
				 } keys %{$s}) . "'\n"
			   );
	$section_count++;
    }

    $lib_ref->SetSections (\@sections);
    if ($default_removed or $loader eq "lilo") {
	$glob_ref->{"default"} = $sections[0]{"name"};
    }
    $glob_ref->{"__modified"} = 1; # needed because of GRUB - index of default
				   # may change even if not deleted
    $lib_ref->SetGlobalSettings ($glob_ref);
    $lib_ref->WriteSettings (1);
    $lib_ref->UpdateBootloader (1); # avoid initialization but write config to
                                    # the right place

    DumpLog ($lib_ref->{"loader"});
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
			    $flavor_old =~ s/.*-(\w+)/(\1)/;
			    $s->{"name"} = $s->{"name"} . " " . $flavor_old;
			    $s->{"__modified"} = 1;
			}

			my $flavor_new = $sect_ref_new->{"image"};
			$flavor_new =~ s/.*-(\w+)/(\1)/;
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
		$s_name_old =~ s/^(.+) \(\w+\)$/\1/;
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
		    $sections[$hit]->{"name"} =~ s/(.*) \(\w+\)/\1/;
		    $sections[$hit]->{"__modified"} = 1;
		}
	    }
	}
    }

    else {
	print "Bootloader::Tools::AdjustSectionNameAppendix(): Invalid parameters.\n";
    }
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
