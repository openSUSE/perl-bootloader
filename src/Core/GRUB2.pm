#! /usr/bin/perl -w
#
# Bootloader configuration base library
#

=head1 NAME

Bootlader::Core::GRUB2 - library for blank configuration


=head1 PREFACE

This package is the GRUB2 library of the bootloader configuration

=head1 SYNOPSIS

use Bootloader::Core::GRUB2;

C<< $obj_ref = Bootloader::Core::GRUB2->new (); >>

C<< $unix_dev = Bootloader::Core::GRUB2->GrubDev2UnixDev ($grub_dev); >>

C<< $files_ref = Bootloader::Core::GRUB2->ListFiles (); >>

C<< $status = Bootloader::Core::GRUB2->ParseLines (\%files, $avoid_reading_device_map); >>

C<< $files_ref = Bootloader::Core::GRUB2->CreateLines (); >>

C<< $settings_ref = Bootloader::Core::GRUB2->GetSettings (); >>

C<< $glob_info = Bootloader::Core::GRUB2->Global2Info (\@glob_lines, \@section_names); >>

C<< $lines_ref = Bootloader::Core::GRUB2->Info2Global (\%section_info, \@section_names); >>

C<< $status = Bootloader::Core::GRUB2->SetSettings (\%settings); >>

C<< $status = Bootloader::Core::GRUB2->InitializeBootloader (); >>


=head1 DESCRIPTION

=over 2

=cut


package Bootloader::Core::GRUB2;

use strict;

use Bootloader::Core;
our @ISA = ('Bootloader::Core');
use Bootloader::Path;

use Data::Dumper;

#module interface

sub GetKernelDevice {
    my $self = shift;
    my $orig = shift;
    my $device = $orig;

    unless (defined ($self->{"udevmap"}))
    {
        $self->l_warning("GRUB2::GetKernelDevice: Udev mapping is not set");
        return $orig;
    }
    $device =  $self->{"udevmap"}->{$device}
        if defined ($self->{"udevmap"}->{$device});

    $self->l_milestone("GRUB2::GetKernelDevice: From $orig to $device");

    return $device;
}

=item
C<< $unix_dev = Bootloader::Core::GRUB2->GrubDev2UnixDev ($grub_dev); >>

Translates the GRUB2 device (eg. '(hd0,1)') to UNIX device (eg. '/dev/hda1').
As argument takes the GRUB2 device, returns the UNIX device (both strings)
or argument if translate fail.

=cut

# string GrubDev2UnixDev (string grub_dev)
sub GrubDev2UnixDev {
    my $self = shift;
    my $dev = shift;

    unless ($dev) {
	$self->l_error ("GRUB2::GrubDev2UnixDev: Empty device to translate");
	return $dev;
    }
    if ($dev !~ /^\(.*\)$/) {
	$self->l_warning ("GRUB2::GrubDev2UnixDev: Not translating device $dev");
	return $dev;
    }

    my $original = $dev;
    my $partition = undef;

    # Check if $dev consists of something like (hd0,1), thus a grub device
    # TODO: warns once detect (hd0,0) as GRUB2 partition is one based
    if ($dev =~ /\(([^,]+),([^,]+)\)/) {
	$dev = $1;
    # GRUB2 device partition is now one based (eg, (hd0,1) = /dev/sda1)
	$partition = $2;
    }
    elsif ($dev =~ /\(([^,]+)\)/) {
	$dev = $1;
    }

    my $match_found = 0;
    $self->l_milestone ("GRUB2::GrubDev2UnixDev: device_map: ".$self->{"device_map"});
    while ((my $unix, my $fw) = each (%{$self->{"device_map"}})) {
        $self->l_milestone ("GRUB2::GrubDev2UnixDev: device_map: $unix <-> $fw.");
    }
    while ((my $unix, my $fw) = each (%{$self->{"device_map"}})) {
	if ($dev eq $fw) {
	    $dev = $unix;
	    $match_found = 1;
	}
    }

    if ($match_found == 0) {
        $self->l_error ("GRUB2::GrubDev2UnixDev: did not find a match for $dev in the device map");
        return $original;
    }

    # resolve symlinks.....
    $dev = $self->GetKernelDevice($dev);
    $self->l_milestone ("GRUB2::GrubDev2UnixDev: Kernel device is $dev");

    if (defined ($partition)) {
        my $finded = undef;
	foreach my $dev_ref (@{$self->{"partitions"}}) {
	    if ( $dev_ref->[1] eq $dev
              && $dev_ref->[2] == $partition) {
		$dev = $dev_ref->[0];
		$self->l_milestone ("GRUB2::GrubDev2UnixDev: Translated $original to $dev");
		$finded = 1;;
	    }
	}
        if (defined $finded){
          return $dev;
        }
        #no partition found so return $dev with partition
	$self->l_warning ("GRUB2::GrubDev2UnixDev: No partition found for $dev with $partition.");
        return $dev.$partition;
    }

    $dev = $self->Member2MD ($dev);
    $self->l_milestone ("GRUB2::GrubDev2UnixDev: Translated GRUB2->UNIX: $original to $dev");
    return $dev;
}

=item
C<< $grub_dev = Bootloader::Core::GRUB2->UnixDev2GrubDev ($unix_dev); >>

Translates the UNIX device (eg. '/dev/hda1') to GRUB2 device (eg. '(hd0,1)').
As argument takes the UNIX device, returns the GRUB2 device (both strings).

=cut

# Pattern for grub device specification. Please note that this does not work
# with BSD labeled disks which use things like "hd0,b"
# The pattern matches disk or floppy or network or cd
my $grubdev_pattern = "(?:hd\\d+(?:,\\d+)?|fd\\d+|nd|cd)";


# string UnixDev2GrubDev (string unix_dev)
sub UnixDev2GrubDev {
    my $self = shift;
    my $dev = shift;
    my $g_dev;
    local $_;

    if ($dev eq "") {
	$self->l_error ("GRUB2::UnixDev2GrubDev: Empty device to translate");
	return ""; # return an error
    }

    # TODO: check whether listed grubdev valid for grub2 ?
    # Seems to be a grub device already
    if ($dev =~ /^\(${grubdev_pattern}\)$/) {
	$self->l_warning ("GRUB2::UnixDev2GrubDev: Not translating device $dev");
	return $dev;
    }

    $self->l_milestone ("GRUB2::UnixDev2GrubDev: Translating $dev ...");

    # remove parenthesis to be able to handle entries like "(/dev/sda1)" which
    # might be there by error
    $dev =~ s/^\((.*)\)$/$1/;

    # This gives me the devicename, whether $dev is the device or a link!
    # This works for udev (kernel) devices only, devicemapper doesn't
    # need to be changed here

    my $original = $dev;
    my $kernel_dev = $self->GetKernelDevice($dev);

    $self->l_milestone ("GRUB2::UnixDev2GrubDev: kernel device: $kernel_dev");

    my $partition = undef;

    if ($kernel_dev =~ m#/dev/md\d+#) {
	my @members = @{$self->MD2Members ($kernel_dev) || []};
	# FIXME! This only works for mirroring (Raid1)
	$kernel_dev = $self->GetKernelDevice($members[0] || $kernel_dev );
	$self->l_milestone ("GRUB2::UnixDev2GrubDev: First device of MDRaid: $original -> $kernel_dev");
    }

    # print all entries of device.map - for debugging
    if ($self->{device_map}) {
        $self->l_milestone ("GRUB2::UnixDev2UnixDev: device_map:");

	for (sort keys %{$self->{device_map}}) {
	    $self->l_milestone ("unix device: $_ <==> grub device: $self->{device_map}{$_}");
	}
    }
    else {
	$self->l_warning ("GRUB2::UnixDev2GrubDev: empty device_map");
    }

    # fetch the underlying device (sda1 --> sda)
    for (@{$self->{partitions}}) {
	if ($_->[0] eq $kernel_dev) {
	    $kernel_dev = $_->[1];
    # grub2 device is one based
	    $partition = $_->[2];
	    $self->l_milestone ("GRUB2::UnixDev2GrubDev: dev base part: $_->[0] $_->[1] $_->[2]");
	    last;
	}
    }

    for (sort keys %{$self->{device_map}}) {
        if ($kernel_dev eq $self->GetKernelDevice($_)) {
            $g_dev = $self->{device_map}{$_};
            last;
        }
    }

    # TODO: Is the fallback work for grub2 ???
    # fallback if translation has failed - this is good enough for many cases
    # FIXME: this is nonsense - we should return an error
    if (!$g_dev) {
        $self->l_warning("GRUB2::UnixDev2GrubDev: Unknown device/partition, using fallback");

        $g_dev = "hd0";
        $partition = undef;

        if (
            $original =~ m#^/dev/(?:vx|das|[ehpsvx])d[a-z]{1,2}(\d+)$# ||
            $original =~ m#^/dev/\S+\-part(\d+)$# ||
            $original =~ m#^/dev(?:/[^/]+){1,2}p(\d+)$#
        ) {
            $partition = $1 - 1;
            $partition = 0 if $partition < 0;
        }
    }

    if (defined $partition) {
        $g_dev = "($g_dev,$partition)";
        $self->l_milestone ("GRUB2::UnixDev2GrubDev: Translated UNIX partition -> GRUB2 device: $original to $g_dev");
    }
    else {
        $g_dev = "($g_dev)";
        $self->l_milestone ("GRUB2::UnixDev2GrubDev: Translated UNIX device -> GRUB2 device: $original to $g_dev");
    }

    return $g_dev;
}

=item
C<< $obj_ref = Bootloader::Core::GRUB2->new (); >>

Creates an instance of the Bootloader::Core::GRUB2 class.

=cut

sub new {
    my $self = shift;
    my $old = shift;

    my $loader = $self->SUPER::new ($old);
    bless ($loader);

    $loader->l_milestone ("GRUB2::new: Created GRUB2 instance");
    return $loader;
}

sub IsDisc {
  my $self = shift;
  my $disc = shift;
  my $ret = undef;
  foreach my $dev (keys %{$self->{"device_map"}}) {
    if ( $self->GetKernelDevice($disc) eq $self->GetKernelDevice($dev) ){
      $ret = 1;
    }
  }
  return $ret;
}

=item
C<< $files_ref = Bootloader::Core::GRUB2->ListFiles (); >>

Returns the list of the configuration files of the bootloader
Returns undef on fail

=cut

# list<string> ListFiles ()
sub ListFiles {
    my $self = shift;

    return [ Bootloader::Path::Grub2_devicemap(),
             Bootloader::Path::Grub2_installdevice(),
             Bootloader::Path::Grub2_defaultconf(),
             Bootloader::Path::Grub2_conf() ];
}

=item
C<< $status = Bootloader::Core::GRUB2->ParseLines (\%files, $avoid_reading_device_map); >>

Parses the contents of all files and stores the settings in the
internal structures. As first argument, it takes a hash reference, where
keys are file names and values are references to lists, each
member is one line of the file. As second argument, it takes a
boolean flag that, if set to a true value, causes it to skip
updating the internal device_map information. Returns undef on
fail, defined nonzero value on success.

=cut

# void ParseLines (map<string,list<string>>, boolean)
sub ParseLines {
    my $self = shift;
    my %files = %{+shift};
    my $avoid_reading_device_map = shift;

    #first set the device map - other parsing uses it
    my @device_map = @{$files{Bootloader::Path::Grub2_devicemap()} || []};
    $self->l_milestone ("GRUB2::Parselines: input from device.map :\n'" .
			join("'\n' ", @device_map) . "'");
    my %devmap = ();
    foreach my $dm_entry (@device_map)
    {
	if ($dm_entry =~ /^\s*\(([^\s#]+)\)\s+(\S+)\s*$/)
	{
          #multipath handling, multipath need real device, because multipath
          # device have broken geometry (bnc #448110)
          if (defined $self->{"multipath"} && defined $self->{"multipath"}->{$self->GetKernelDevice($2)}){
            $devmap{ $self->{"multipath"}->{$self->GetKernelDevice($2)} } = $1;
          } else {
      	    $devmap{$2} = $1;
          }
	}
    };
    $self->l_milestone ("GRUB2::Parselines: avoided_reading device map.") if ($avoid_reading_device_map );
    $self->{"device_map"} = \%devmap	if (! $avoid_reading_device_map);
    $self->l_milestone ("GRUB2::Parselines: device_map: ".$self->{"device_map"});
    while ((my $unix, my $fw) = each (%{$self->{"device_map"}})) {
        $self->l_milestone ("GRUB2::Parselines: device_map: $unix <-> $fw.");
    }

    # and now proceed with /etc/default/grub
    my @defaultconf = @{$files{Bootloader::Path::Grub2_defaultconf()} || []};
    $self->l_milestone ("GRUB2::Parselines: input from default conf :\n'" .
                        join("'\n' ", @defaultconf) . "'");

    # prefix commented config with '@' instread of '#'
    # this is to new notation for "commented config" and
    # need to process saparately
    foreach my $conf (@defaultconf) {
        if ($conf =~ m/^\s*#\s*GRUB_/) {
            $conf =~ s/^\s*#/@/;
        }
    }

    (my $glob_ref, my $sect_ref) = $self->ParseMenuFileLines (
        "=",
        [],
        \@defaultconf
    );

    if (not exists $self->{"mountpoints"}{'/'})
    {
        $self->l_milestone ("GRUB2::Parselines: Mount points doesn't have '/', skipped parsing grub2 config");
    } else {
        # FIXME: Need to figure our a better way to get the
        # device, otherwise user may break setup if they
        # call install script directly
        my @devices = @{$files{Bootloader::Path::Grub2_installdevice()} || []};

        # FIXME: still incomplete for MD and dmraid devs
        # translate device array to the various boot_* flags else set boot_custom
        # in glob_ref accordingly
        my ($boot_dev,) = $self->SplitDevPath ("/boot");
        my ($root_dev,) = $self->SplitDevPath ("/");

        # $boot_dev and $root_dev should be kernel device
        # otherwise GetExtendedPartition() may not work
        # as expected
        $boot_dev = $self->GetKernelDevice($boot_dev);
        $root_dev = $self->GetKernelDevice($root_dev);

        my $extended_dev = $self->GetExtendedPartition($boot_dev) || "";
        # mbr_dev is the first bios device
        my $mbr_dev =  $self->GrubDev2UnixDev("(hd0)");

        foreach my $dev (@devices) {
	    $self->l_milestone ("GRUB2::Parselines: checking boot device $dev");

	    #Quick fix for activate and generic_mbr regression ..
	    # TODO: Need figure out better handling of them
            if ($dev eq "activate") {
                $glob_ref->{"activate"} = "true";
		next;
	    }

	    if ($dev eq "generic_mbr") {
                $glob_ref->{"generic_mbr"} = "true";
		next;
	    }

	    if ($dev eq $mbr_dev) {
	        $glob_ref->{"boot_mbr"} = "true";
	        $self->l_milestone ("GRUB2::Parselines: detected boot_mbr");
                if (defined $self->{"md_arrays"}
                    and ((scalar keys %{$self->{"md_arrays"}}) > 0)){
                    if (defined $glob_ref->{"boot_md_mbr"}
                        and $glob_ref->{"boot_md_mbr"} ne "" ){
                        $glob_ref->{"boot_md_mbr"} = $glob_ref->{"boot_md_mbr"}.",".$dev;
                    } else {
                        $glob_ref->{"boot_md_mbr"} =$dev;
                    }
                    $self->l_milestone ("GRUB2::Parselines: detected boot_md_mbr ".$glob_ref->{"boot_md_mbr"});
                }
	    }
	    elsif ($dev eq $root_dev) {
	        $glob_ref->{"boot_root"} = "true";
	        $self->l_milestone ("GRUB2::Parselines: detected boot_root");
	    }
	    elsif ($dev eq $boot_dev) {
	        $glob_ref->{"boot_boot"} = "true";
	        $self->l_milestone ("GRUB2::Parselines: detected boot_boot");
	    }
	    elsif ($dev eq $extended_dev) {
	        $glob_ref->{"boot_extended"} = "true";
	        $self->l_milestone ("GRUB2::Parselines: detected boot_extended");
	    }
            elsif ($self->IsDisc($dev)
                   and defined $self->{"md_arrays"}
                   and ((scalar keys %{$self->{"md_arrays"}}) > 0)){
                if (defined $glob_ref->{"boot_md_mbr"} and $glob_ref->{"boot_md_mbr"} ne "" ){
                    $glob_ref->{"boot_md_mbr"} = $glob_ref->{"boot_md_mbr"}.",".$dev;
                } else {
                    $glob_ref->{"boot_md_mbr"} =$dev;
                }
                $self->l_milestone ("GRUB2::Parselines: detected boot_md_mbr ".$glob_ref->{"boot_md_mbr"});
            }
	    else {
	        $glob_ref->{"boot_custom"} = $dev;
	        $self->l_milestone ("GRUB2::Parselines: set boot_custom");
	    }
        }
    }

    my @confs = @{$files{Bootloader::Path::Grub2_conf()} || []};
    my @entries = ();
    foreach my $conf (@confs) {
        if ($conf =~ /^menuentry\s+['"](.*)['"]\s+/) {
	    push @entries, { "menuentry" =>  $1 };
        }
    }

    $self->{"global"} = $glob_ref;
    $self->{"sections"} = \@entries;

    return 1;
}

sub CreateGrubInstalldevLines() {
    my $self = shift;

    # process /etc/grub.conf
    my %glob = %{$self->{"global"}};
    my @grub2_installdev = ();
    my %s1_devices = ();
    # md_discs stores grub discs which should be synchronized (needed for correct stage2 location)
    my $md_discs = {};

    {
	my $dev;
	my $flag;

	# boot_custom => "selectdevice:Custom Boot Partition::"
	$dev = delete($glob{"boot_custom"});
	$s1_devices{$dev} = 1 if (defined $dev and $dev ne "");

	# boot_mbr    => "bool:Boot from Master Boot Record:false",
	$flag = delete $glob{"boot_mbr"};
	if (defined $flag and $flag eq "true") {
	    # if /boot mountpoint exists add($disk(/boot) else add disk(/)
	    # mbr_dev is the first bios device
	    $dev =  $self->GrubDev2UnixDev("(hd0)");
	    $s1_devices{$dev} = 1 if defined $dev;
	}

	# boot_md_mbr   synchronize mbr of disc in md raid
  #(it is little tricky as md raid synchronize only partitions)
	$flag = delete $glob{"boot_md_mbr"};
	if (defined $flag and $flag ne "") {
            my @discs = split(/,/,$flag);
            chomp @discs;
            foreach my $mbr_disc (@discs){
      	      $s1_devices{$mbr_disc} = 1;
              my $gdev = $self->UnixDev2GrubDev($mbr_disc);
              $md_discs->{$gdev} = substr($gdev,1,-1);
	            $self->l_milestone ("GRUB2::CreateGrubInstalldevLines: md_mbr device: $gdev ");
            }
	}

	# boot_root   => "bool:Boot from Root Partition:true",
	$flag = delete $glob{"boot_root"};
	if (defined $flag and $flag eq "true") {
	    # add partition(/)
	    ($dev,) = $self->SplitDevPath ("/");
	    $s1_devices{$dev} = 1 if defined $dev;
	}

	# boot_boot   => "bool:Boot from Boot Partition:true",
	$flag = delete $glob{"boot_boot"};
	if (defined $flag and $flag eq "true") {
	    # add partition(/boot)
	    ($dev,) = $self->SplitDevPath ("/boot");
	    $s1_devices{$dev} = 1 if defined $dev;
	}

	# boot_extended   => "bool:Boot from Extended Partition:true",
	$flag = delete $glob{"boot_extended"};
	if (defined $flag and $flag eq "true") {
	    # add partition(extended)
	    $dev = $self->GetExtendedPartition($self->SplitDevPath("/boot"));
	    $s1_devices{$dev} = 1 if defined $dev;
	}

	# convert any raid1 device entry into multiple member entries
	foreach my $s1dev (keys %s1_devices)
	{
	    if ($s1dev =~ m:/dev/md\d+:) {
		delete $s1_devices{$s1dev};
		# Please note all non-mirror raids are silently deleted here
		my @members = @{$self->MD2Members($s1dev) || []};
		map { $s1_devices{$_} = 1; } @members;
	    }
	}

	# FIXME: convert all impossible configurations to some viable
	# fallback:
	#     boot from primary xfs -> mbr
	#     boot from extended -> set generic_mbr
	# other options ???
    }

    $self->l_milestone ("GRUB2::CreateGrubInstalldevLines: found s1_devices: "
			. join(",",keys %s1_devices));

    if (scalar (keys (%s1_devices)) > 0)
    {
	foreach my $new_dev (keys (%s1_devices))
	{
	    push @grub2_installdev, $new_dev;
	}
    }

    my $activate  = delete $glob{"activate"};
    if (defined $activate and $activate eq "true") {
        push @grub2_installdev, "activate";
    }

    my $generic_mbr  = delete $glob{"generic_mbr"};
    if (defined $generic_mbr and $generic_mbr eq "true") {
        push @grub2_installdev, "generic_mbr";
    }

    return \@grub2_installdev;
}

=item
C<< $files_ref = Bootloader::Core::GRUB2->CreateLines (); >>

creates contents of all files from the internal structures.
Returns a hash reference in the same format as argument of
ParseLines on success, or undef on fail.

=cut

# map<string,list<string>> CreateLines ()
sub CreateLines {
    my $self = shift;
    my $global = $self->{"global"};

    # first create /etc/default/grub_installdevice
    my $grub2_installdev = $self->CreateGrubInstalldevLines();

    if (defined $global->{"__lines"}) {
        foreach my $line (@{$global->{"__lines"}}) {
             if (defined $line->{"value"} && $line->{"value"} eq "" ) {
                 $line->{"value"} = '""';
             }
        }
    }

    my $grub2_defaultconf = $self->PrepareMenuFileLines (
        [],
        $global,
        "",
        "="
    );


    foreach my $conf (@{$grub2_defaultconf}) {
        if ($conf =~ m/^\s*@\s*GRUB_/) {
            $conf =~ s/^\s*@/#/;
        }
    }
    # TODO: as we know the grub2-install also create device map
    # I skipped creating them by yast ..

    # now process the device map
    ## my %glob = %{$self->{"global"}};
    ## my @device_map = ();
    ## while ((my $unix, my $fw) = each (%{$self->{"device_map"}}))
    ## {
    ##	my $line = "($fw)\t$unix";
    ##	push @device_map, $line;
    ## }
    return {
	Bootloader::Path::Grub2_installdevice() => $grub2_installdev,
   Bootloader::Path::Grub2_defaultconf() => $grub2_defaultconf,
    ##	Bootloader::Path::Grub2_devicemap() => \@device_map,
    }
}

=item
C<< $glob_info = $Bootloader::Core::GRUB2->Global2Info (\@glob_lines, \@section_names); >>

Gets the general information from the global section of the menu file. This information
usually means the default section, graphical menu, timeout etc. As argument it takes
a reference to the list of hashes representing lines of the section, returns a reference
to a hash containing the important information.

=cut

# map<string,string> Global2Info (list<map<string,any>> global, list<string>sections)

sub Global2Info {
    my $self = shift;
    my @lines = @{+shift};
    my @sections = @{+shift};

    my %ret = ();
    $ret{"__lines"} = \@lines;

    my $timeout;
    my $hidden_timeout;

    foreach my $line_ref (@lines) {
        my $key = $line_ref->{"key"};
        my $val = $line_ref->{"value"};

        # Check if key is defined to prevent perl warnings
        next if (!defined($key));

        if ($key =~ m/@?GRUB_CMDLINE_LINUX_DEFAULT$/)
        {
            if ($val =~ /^(?:(.*)\s+)?vga=(\S+)(?:\s+(.*))?$/)
            {
                $ret{"vgamode"} = $2 if $2 ne "";
                $val = $self->MergeIfDefined ($1, $3);
            }

            $ret{"append"} = $val;
        } elsif ($key =~ m/@?GRUB_TIMEOUT$/) {
            $timeout = $val;
        } elsif ($key =~ m/@?GRUB_HIDDEN_TIMEOUT$/) {
            $hidden_timeout = $val;
        } elsif ($key =~ m/@?GRUB_TERMINAL/) {
            if ($val =~ m/^(serial|console|gfxterm)$/) {
                $ret{"terminal"} = $val;
            }
        } elsif ($key =~ m/@?GRUB_SERIAL_COMMAND/) {
            $ret{"serial"} = $val;
        } elsif ($key =~ m/@?GRUB_GFXMODE/) {
            $ret{"gfxmode"} = $val;
        } elsif ($key =~ m/@?GRUB_BACKGROUND/) {
            $ret{"gfxbackground"} = $val;
        }
    }

    if (defined $timeout) {
        if ($timeout == 0) {
            if (defined $hidden_timeout) {
                $ret{"timeout"} = $hidden_timeout;
                $ret{"hiddenmenu"} = "true";
            } else {
                $ret{"timeout"} = $timeout;
                $ret{"hiddenmenu"} = "true";
            }
        } else {
            $ret{"timeout"} = $timeout;
            $ret{"hiddenmenu"} = "false";
        }
    }


    return \%ret;
}

=item
C<< $lines_ref = Bootloader::Core::GRUB2->Info2Global (\%section_info, \@section_names); >>

Takes the info about the global options and uses it to construct the list of lines.
The info about global option also contains the original lines.
As parameter, takes the section info (reference to a hash) and a list of sectino names,
returns the lines (a list of hashes).

=cut

# list<map<string,any>> Info2Global (map<string,string> info, list<string>sections)

sub Info2Global {
    my $self = shift;
    my %globinfo = %{+shift};
    my $sections_ref = shift;

    my @lines = @{$globinfo{"__lines"} || []};

    # my $sysconf =  Bootloader::Tools::GetSysconfigValue("DEFAULT_APPEND");
    # allow to keep the section unchanged
    return \@lines unless $globinfo{"__modified"} || 0;

    if (scalar (@lines) == 0)
    {
        @lines = (
            {
                'key' => 'GRUB_DISTRIBUTOR',
                'value' => '"openSUSE"',
                'comment_before' => [
                  '# If you change this file, run \'grub2-mkconfig -o /boot/grub2/grub.cfg\' afterwards to update',
                  '# /boot/grub2/grub.cfg.'
                ],
            },
            {
                'key' => 'GRUB_DEFAULT',
                'value' => 'saved',
            },
            {
                'key' => 'GRUB_HIDDEN_TIMEOUT',
                'value' => '0',
            },
            {
                'key' => 'GRUB_HIDDEN_TIMEOUT_QUIET',
                'value' => 'true',
            },
            {
                'key' => 'GRUB_TIMEOUT',
                'value' => '10',
            },
            {
                'key' => 'GRUB_CMDLINE_LINUX_DEFAULT',
                'value' => 'quiet splash=silent',
            },
            {
                'key' => 'GRUB_CMDLINE_LINUX',
                'value' =>  '""',
            },
            {
                'key' => '@GRUB_BADRAM',
                'value' => '"0x01234567,0xfefefefe,0x89abcdef,0xefefefef"',
                'comment_before' => [
                  '# Uncomment to enable BadRAM filtering, modify to suit your needs',
                  '# This works with Linux (no patch required) and with any kernel that obtains',
                  '# the memory map information from GRUB (GNU Mach, kernel of FreeBSD ...)'
                ],
            },
            {
                'key' => '@GRUB_TERMINAL',
                'value' => 'console',
                'comment_before' => [
                  '# Uncomment to disable graphical terminal (grub-pc only)'
                ],
            },
            {
                'key' => '@GRUB_GFXMODE',
                'value' => '640x480',
                'comment_before' => [
                  '# The resolution used on graphical terminal',
                  '# note that you can use only modes which your graphic card supports via VBE',
                  '# you can see them in real GRUB with the command `vbeinfo\''
                ],
            },
            {
                'key' => '@GRUB_DISABLE_LINUX_UUID',
                'value' => 'true',
                'comment_before' => [
                  '# Uncomment if you don\'t want GRUB to pass "root=UUID=xxx" parameter to Linux'
                ],
            },
            {
                'key' => '@GRUB_DISABLE_LINUX_RECOVERY',
                'value' => 'true',
                'comment_before' => [
                  '# Uncomment to disable generation of recovery mode menu entries'
                ],
            },
            {
                'key' => '@GRUB_INIT_TUNE',
                'value' => '480 440 1',
                'comment_before' => [
                  '# Uncomment to get a beep at grub start'
                ],
            },
        );

    }

    # We don't need to set root= as grub2-mkconfig
    # already detect that for us ..
    # my $root = delete $globinfo{"root"} || "";
    my $vga = delete $globinfo{"vgamode"} || "";
    my $append = delete $globinfo{"append"} || "";
    my $timeout = delete $globinfo{"timeout"} || "";
    my $hiddenmenu = delete $globinfo{"hiddenmenu"} || "";
    my $terminal = delete $globinfo{"terminal"} || "";
    my $serial = delete $globinfo{"serial"} || "";
    my $gfxmode = delete $globinfo{"gfxmode"} || "";
    my $gfxbackground = delete $globinfo{"gfxbackground"} || "";
    # $root = " root=$root" if $root ne "";
    $vga = " vga=$vga" if $vga ne "";
    $append = " $append" if $append ne "";

    my $hidden_timeout = "$timeout";
    if ("$hiddenmenu" eq "true") {
        $timeout = "0" if "$timeout" ne "";
    } else {
        $hidden_timeout = "0" if "$hidden_timeout" ne "";
    }

    @lines = map {
        my $line_ref = $_;
        my $key = $line_ref->{"key"};
        if ($key =~ m/@?GRUB_CMDLINE_LINUX_DEFAULT$/)
        {
            $line_ref->{"value"} = "$append$vga" if "$append$vga" ne "";
            $append = "";
            $vga = "";
        } elsif ($key =~ m/@?GRUB_TIMEOUT$/) {
            $line_ref->{"value"} = "$timeout" if "$timeout" ne "";
            $timeout = "";
        } elsif ($key =~ m/@?GRUB_HIDDEN_TIMEOUT$/) {
            $line_ref->{"value"} = "$hidden_timeout" if "$hidden_timeout" ne "";
            $hidden_timeout = "";
        } elsif ($key =~ m/@?GRUB_SERIAL_COMMAND/) {
            if ($serial eq "") {
                $line_ref->{"key"} = '@GRUB_SERIAL_COMMAND';
            } else {
                $line_ref->{"key"} = "GRUB_SERIAL_COMMAND";
                $line_ref->{"value"} = $serial;
                $serial = "";
            }
        } elsif ($key =~ m/@?GRUB_GFXMODE/) {
            if ($gfxmode ne "") {
                $line_ref->{"key"} = "GRUB_GFXMODE";
                $line_ref->{"value"} = $gfxmode;
            }
            $gfxmode = "";
        } elsif ($key =~ m/@?GRUB_BACKGROUND/) {
            if ($gfxbackground ne "") {
                $line_ref->{"key"} = "GRUB_BACKGROUND";
                $line_ref->{"value"} = $gfxbackground;
            } else {
                $line_ref = undef;
            }
            $gfxbackground = "";
        } elsif ($key =~ m/@?GRUB_TERMINAL/) {
            if ($terminal eq "") {
                $line_ref->{"key"} = '@GRUB_TERMINAL';
                $line_ref->{"value"} = "console";
            } else {
                $line_ref->{"key"} = "GRUB_TERMINAL";
                if ($terminal =~ m/^(serial|console|gfxterm)$/) {
                    $line_ref->{"value"} = "$terminal" if "$terminal" ne "";
                }
                $terminal = "";
            }
        }
        defined $line_ref ? $line_ref : ();
    } @lines;

    if ("$append$vga" ne "") {
        push @lines, {
            "key" => "GRUB_CMDLINE_LINUX_DEFAULT",
            "value" => "$append$vga",
        }
    }

    if ("$timeout" ne "") {
        push @lines, {
            "key" => "GRUB_TIMEOUT",
            "value" => "$timeout",
        }
    }

    if ("$hidden_timeout" ne "") {
        push @lines, {
            "key" => "GRUB_HIDDEN_TIMEOUT",
            "value" => "$hidden_timeout",
        }
    }

    if ($terminal ne "") {
        push @lines, {
            "key" => "GRUB_TERMINAL",
            "value" => "$terminal",
        }
    }

    if ($serial ne "") {
        push @lines, {
            "key" => "GRUB_SERIAL_COMMAND",
            "value" => "$serial",
        }
    }

    if ($gfxmode ne "") {
        push @lines, {
            "key" => "GRUB_GFXMODE",
            "value" => "$gfxmode",
        }
    }

    if ($gfxbackground ne "") {
        push @lines, {
            "key" => "GRUB_BACKGROUND",
            "value" => "$gfxbackground",
        }
    }
    return \@lines;
}

=item
C<< $settings_ref = Bootloader::Core::GRUB2->GetSettings (); >>

returns the complete settings in a hash. Does not read the settings
from the system, but returns internal structures.

=cut

# map<string,any> GetSettings ()
sub GetSettings {
    my $self = shift;
    my $ret = $self->SUPER::GetSettings ();

    my $sections = $ret->{"sections"};
    my $globals = $ret->{"global"};
    my $saved_entry = `/usr/bin/grub2-editenv list|sed -n '/^saved_entry=/s/.*=//p'`;

    chomp $saved_entry;
    if ($saved_entry ne "") {
        if ($saved_entry =~ m/^\d+$/) {
            my $sect = $sections->[$saved_entry];

            if (defined $sect) {
                $globals->{"default"} = $sect->{"menuentry"};
            }
        } else {
            $globals->{"default"} = $saved_entry;
        }
    }

    return $ret;
}

=item
C<< $status = Bootloader::Core::GRUB2->SetSettings (\%settings); >>

Stores the settings in the given parameter to the internal
structures. Does not touch the system.
Returns undef on fail, defined nonzero value on success.

=cut

# void SetSettings (map<string,any> settings)
sub SetSettings {
    my $self = shift;
    my %settings = %{+shift};

    my $default  = delete $settings{"global"}->{"default"};

    if (defined $default and $default ne "") {
        $self->RunCommand (
            "/usr/sbin/grub2-set-default '$default'",
            "/var/log/YaST2/y2log_bootloader"
        );
    }

    return $self->SUPER::SetSettings (\%settings);
}

=item
C<< $status = Bootloader::Core::GRUB2->UpdateBootloader (); >>

Updates the settings in the system. Backs original configuration files
up and replaces them with the ones with the '.new' suffix. Also performs
operations needed to make the change effect (run '/sbin/elilo').
Returns undef on fail, defined nonzero value on success.

=cut

# boolean UpdateBootloader ()
sub UpdateBootloader {
    my $self = shift;
    my $avoid_init = shift;

    # backup the config file
    # it really did nothing for now
    my $ret = $self->SUPER::UpdateBootloader ();
    return undef unless defined $ret;

    if (! $avoid_init)
    {
        return $self->InitializeBootloader ();
    }

    return 0 == $self->RunCommand (
        "/usr/sbin/grub2-mkconfig -o /boot/grub2/grub.cfg",
        "/var/log/YaST2/y2log_bootloader"
    );
}

=item
C<< $status = Bootloader::Core::GRUB2->InitializeBootloader (); >>

Initializes the firmware to boot the bootloader.
Returns undef on fail, defined nonzero value otherwise

=cut

# boolean InitializeBootloader ()
sub InitializeBootloader {
    my $self = shift;
    my %glob = %{$self->{"global"}};
    my $file = Bootloader::Path::Grub2_installdevice();
    my $files_ref = $self->ReadFiles ([$file,]);

    if (! defined ($files_ref))
    {
        return undef;
    }

    # Since Bootloader::Tools::ReadPartitions didn't assign
    # correct part_type, the skip-fs-probe check based
    # on `extended may not work.

    #my $skip_fs_probe = delete $glob{"boot_extended"};

    #if (defined $skip_fs_probe and $skip_fs_probe eq "true") {
    #    $install_opts .= " --skip-fs-probe ";
    #}

    # Do skip-fs-probe to avoid error when embedding stage1
    # to extended partition
    my $install_opts = "--force --skip-fs-probe";
    my @devices = @{$files_ref->{$file} || []};

    # Hmm .. grub2-install must has been run before
    # any grub2-mkconfig ...
    # TODO: foreach .. looks awkward .. need clearify
    foreach my $dev (@devices) {

        if ($dev eq "activate" or $dev eq "generic_mbr") {
            next;
        }

        my $ret = $self->RunCommand (
            # TODO: Use --force is for installing on BS
            # the tradeoff is we can't capture errors
            # only patch grub2 package is possible way
            # to get around this problem
            "/usr/sbin/grub2-install $install_opts $dev",
            "/var/log/YaST2/y2log_bootloader"
        );

        return 0 if (0 != $ret);
    }

    return 0 ==  $self->RunCommand (
        "/usr/sbin/grub2-mkconfig -o /boot/grub2/grub.cfg",
        "/var/log/YaST2/y2log_bootloader"
    );
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
