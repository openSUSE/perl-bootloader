#! /usr/bin/perl -w
#
# Bootloader configuration base library
#

=head1 NAME

Bootlader::Core::GRUB - GRUB library for bootloader configuration


=head1 PREFACE

This package is the GRUB library of the bootloader configuration

=head1 SYNOPSIS

use Bootloader::Core::GRUB;

C<< $obj_ref = Bootloader::Core::GRUB->new (); >>

C<< $unquoted = Bootloader::Core::GRUB->Unquote ($text); >>

C<< $quoted = Bootloader::Core::GRUB->Quote ($text, $when); >>

C<< $unix_dev = Bootloader::Core::GRUB->UnixFile2UnixDev ($unix_file); >>

C<< $unix_dev = Bootloader::Core::GRUB->GrubDev2UnixDev ($grub_dev); >>

C<< $grub_dev = Bootloader::Core::GRUB->UnixDev2GrubDev ($unix_dev); >>

C<< $unix_path = Bootloader::Core::GRUB->GrubPath2UnixPath ($grub_path, $grub_dev_prefix); >>

C<< $grub_path = Bootloader::Core::GRUB->UnixPath2GrubPath ($unix_path, $grub_dev_prefix); >>

C<< $grub_conf_line_ref = Bootloader::Core::GRUB->CreateGrubConfLine ($target, $discswitch); >>

C<< $files_ref = Bootloader::Core::GRUB->ListFiles (); >>

C<< $status = Bootloader::Core::GRUB->ParseLines (\%files); >>

C<< $files_ref = Bootloader::Core::GRUB->CreateLines (); >>

C<< $dev = Bootloader::Core::GRUB->GetCommonDevice (@paths); >>

C<< $line = Bootloader::Core::GRUB->CreateKernelLine (\%sectingo, $grub_root); >>

C<< $line = Bootloader::Core::GRUB->CreateChainloaderLine (\%sectinfo, $grub_root); >>

C<< $disk = Bootloader::Core::GRUB->Partition2Disk ($partition); >>

C<< $sectin_info_ref = Bootloader::Core::GRUB->Section2Info (\@section_lines); >>

C<< $lines_ref = Bootloader::Core::GRUB->Info2Section (\%section_info); >>

C<< $glob_info = $Bootloader::Core::GRUB->Global2Info (\@glob_lines, \@section_names); >>

C<< $lines_ref = Bootloader::Core::GRUB->Info2Global (\%section_info, \@section_names); >>

C<< $settings_ref = Bootloader::Core::GRUB->GetSettings (); >>

C<< $status = Bootloader::Core::GRUB->SetSettings (\%settings); >>

C<< $status = Bootloader::Core::GRUB->InitializeBootloader (); >>

C<< $opt_types_ref = BootGrub->GetOptTypes (); >>

C<< $mountpoint = Bootloader::Core::GRUB->GrubDev2MountPoint ($grub_dev); >>


=head1 DESCRIPTION

=over 2

=cut


package Bootloader::Core::GRUB;

use strict;

use Bootloader::Core;
our @ISA = ('Bootloader::Core');

#module interface

sub bootable($) {
    my $fsid = shift;

    for my $id ( 5, 6, 11..15, 130, 131) {
	return 1 if $fsid == $id;
    }
    return 0;
}

sub GetMetaData() {
    my $loader = shift;

    # possible global entries:
    #

    # activate		# encode somewhere in grub.conf
    # generic_mbr	# ditto

    # boot_custom	# data for grub.conf
    # boot_mbr
    # boot_root
    # boot_boot

    # map
    # unhide
    # hide
    # rootnoverify
    # serial
    # terminal
    # default
    # timeout
    # fallback
    # hiddenmenu
    # gfxmenu
    # * password::                    Set a password for the menu interface

    # * bootp:: --with-configfile     Initialize a network device via BOOTP
    # * color::                       Color the menu interface
    # * dhcp::                        Initialize a network device via DHCP
    # * ifconfig::                    Configure a network device manually
    # * rarp::                        Initialize a network device via RARP
    # debug

    # image section

    # root (hd0,0) # omit this, it's always encoded in image/initrd path
    # image	# kernel /new_kernel
    # append
    # initrd
    # savedefault # not supported

    # xen section

    # xen
    # xen_append
    # image
    # append
    # initrd

    # chainloader section
    # lock
    # root
    # noverifyroot	# true if rootnoverify is used instead of root
    # makeactive
    # blockoffset	# this is encoded in 'chainloader' +1

    # FIXME: add help texts for all widgets

    my %exports;

    my @bootpart;
    my @partinfo = @{$loader->{"partitions"} || []};

    # Partitioninfo is a list of list references of the format:
    #   Device,   disk,    nr, fsid, fstype,   part_type, start_cyl, size_cyl
    #   /dev/sda9 /dev/sda 9   258   Apple_HFS `primary   0          18237
    #

    # boot from any primary partition with PReP or FAT partition id
    my $boot_partitions = join(":", 
	map {
	    my ($device, $disk, $nr, $fsid, $fstype,
		$part_type, $start_cyl, $size_cyl) = @$_;
	    ($fstype ne "xfs" and bootable($fsid))
		? $device : ();
	} @partinfo
    );

    # give a list of possible root devices: all MD devices
    # and all 'Linux' devices above 20 cylinders
    my $root_devices = join(":",
	(map {
	    my ($device, $disk, $nr, $fsid, $fstype,
		$part_type, $start_cyl, $size_cyl) = @$_;
	    (($fsid eq "131" or $fstype =~ m:linux:i) and
	     $size_cyl >= 20)
		? $device : ();
	} @partinfo),
	keys %{$loader->{"md_arrays"} || {}}
	# FIXME this does no longer include raid0 and raid5 devices
    );

    # give a list of all other partitions possibly ready for chain loading
    my $other_partitions = join(":",
	map {
	    my ($device, $disk, $nr, $fsid, $fstype,
		$part_type, $start_cyl, $size_cyl) = @$_;
	    ($size_cyl >= 20) ? $device : ();
	} @partinfo
    );

    # FIXME: does it make sense to distinguish between x86_64 and x86?
    $exports{"arch"} = "x86";
    $exports{"global_options"} = {
 	# for iseries list for others exactly one allowed
	boot     => "multi:Boot Loader Locations:",
	activate => "bool:Set active Flag in Partition Table for Boot Partition:true",
	timeout  => "int:Timeout in Seconds:8:0:3600",
	default  => "string:Default Boot Section:Linux",
	generic_mbr => "bool:Write generic Boot Code to MBR:true",
	boot_custom => "selectdevice:Custom Boot Partition::" . $boot_partitions,
	boot_mbr => "bool:Boot from Master Boot Record:false",
	boot_root => "bool:Boot from Root Partition:true",
	boot_boot => "bool:Boot from Boot Partition:true",
	boot_extended => "bool:Boot from Extended Partition:true",

	# map
	# unhide
	# hide
	# rootnoverify

	serial => "string:Serial connection parameters:",
	terminal => "string:Terminal definition:",
	fallback => "string:Fallback sections if default fails:1",
	hiddenmenu => "bool:Hide menu on boot:false",
	gfxmenu => "path:Graphical menu file:/boot/message",
	password => "password:Password for the Menu Interface:",

	# * bootp:: --with-configfile                      Initialize a network device via BOOTP
	# * color::                       Color the menu interface
	# * dhcp::                        Initialize a network device via DHCP
	# * ifconfig::                    Configure a network device manually
	# * rarp::                        Initialize a network device via RARP
	debug => "bool:Debugging flag:false"
    };

    my $go = $exports{"global_options"};

    $exports{"section_options"} = {
	type_image        => "bool:Image section",
	# image_name     => "string:Name of section", # implicit
	image_image       => "path:Kernel image:/boot/vmlinux",
	image_root        => "selectdevice:Root device::" . $root_devices,
	image_vgamode     => "string:Vga Mode",
	image_append      => "string:Optional kernel command line parameter",
	image_initrd      => "path:Initial RAM disk:/boot/initrd",
	image_noverifyroot=> "bool:Do not verify filesystem before booting:false",

	type_other        => "bool:Chainloader section",
	other_lock        => "bool:Use password protection:false",
	other_chainloader => "selectdevice:Other system::" . $other_partitions,
	other_noverifyroot=> "bool:Do not verify filesystem before booting:false",
	other_makeactive  => "bool:Activate this partition when selected for boot:false",
	other_blockoffset => "int:Block offset for chainloading:1:0:32",

	type_xen          => "bool:Xen section",
	xen_xen => "select:Hypervisor:/boot/xen.gz:/boot/xen.gz:/boot/xen-pae.gz",
	xen_xen_append    => "string:Additional Xen Hypervisor Parameters:",
	xen_image         => "path:Kernel image:/boot/vmlinux",
	xen_root          => "select:Root device::" . $root_devices,
	xen_vgamode       => "string:Vga Mode",
	xen_append        => "string:Optional kernel command line parameter",
	xen_initrd        => "path:Initial RAM disk:/boot/initrd",

	type_menu         => "bool:Menu section",
	menu_root         => "select:Partition of menu file:::" . $other_partitions,
	menu_configfile   => "path:Menu description file:/boot/grub/menu.lst"
    };

    # my $so = $exports{"section_options"};
    # add architecture specific section_options here in case

    $loader->{"exports"}=\%exports;
    return \%exports;
}


=item
C<< $obj_ref = Bootloader::Core::GRUB->new (); >>

Creates an instance of the Bootloader::Core::GRUB class.

=cut

sub new {
    my $self = shift;
    my $old = shift;

    my $loader = $self->SUPER::new ($old);
    bless ($loader);

    # FIXME: Add an 'init-only' parameter to GetMetaData if
    # perfomance goes down
    $loader->GetMetaData();
    $loader->l_milestone ("GRUB::new: Created GRUB instance");
    return $loader;
}

#internal routines

=item
C<< $unquoted = Bootloader::Core::GRUB->Unquote ($text); >>

Just override of Bootloader::Core->Unquote function, returning the first parameter.

=cut

# string Unquote (string text)
sub Unquote {
    my $self = shift;
    my $text = shift;

    return $text;
}

=item
C<< $quoted = Bootloader::Core::GRUB->Quote ($text, $when); >>

Just override of Bootloader::Core->Quote function, returning the first parameter.

=cut

# string Quote (string text, string when)
sub Quote {
    my $self = shift;
    my $text = shift;
    my $when = shift;

    return $text;
}

=item
C<< $unix_dev = Bootloader::Core::GRUB->UnixFile2UnixDev ($unix_file); >>

Detects the underlying partition (e.g. '/dev/sda1') a given UNIX file 
(e.g. '/boot') is located on. Takes a UNIX file as argument and returns 
the corresponding UNIX device.

=cut

# string UnixFile2UnixDev (string unix_file)
sub UnixFile2UnixDev {
    my $self = shift;
    my $unix_file = shift;
    my $unix_dev = "";

    # Collect information about device using "stat"
    my ($temp_unix_dev, undef, undef, undef, undef, undef, undef, undef,
	undef, undef, undef, undef, undef)
    = stat ($unix_file);

    # Open "/proc/partitions" to look up the partition corresponding to
    # major and minor device numbers
    open (PARTITIONS, "</proc/partitions");
    while (<PARTITIONS>) {
	chomp;

	# Omit header and empty lines in /proc/partitions
        unless ($_ =~ /^\s+\d+\s+\d+.*$/) {
	    next;
        }

	my ($empty1 , $major, $minor, $empty2, $dev_name) = split (/\s+/, $_);

	# Assemble major and minor device numbers to be able to compare the
        # result with $temp_unix_dev
	my $majmin = ($major << 8 | $minor);

	if ($majmin == $temp_unix_dev) {
	    $unix_dev = "/dev/" . $dev_name;
            last;
	}
    }
    close (PARTITIONS);

    return $unix_dev;
}

=item
C<< $unix_dev = Bootloader::Core::GRUB->GrubDev2UnixDev ($grub_dev); >>

Translates the GRUB device (eg. '(hd0,0)') to UNIX device (eg. '/dev/hda1').
As argument takes the GRUB device, returns the UNIX device (both strings).

=cut

# string GrubDev2UnixDev (string grub_dev)
sub GrubDev2UnixDev {
    my $self = shift;
    my $dev = shift;

    unless ($dev) {
	$self->l_debug ("GRUB::GrubDev2UnixDev: Empty device to translate");
	return $dev;
    }
    if ($dev !~ /^\(.*\)$/) {
	$self->l_debug ("GRUB::GrubDev2UnixDev: Not translating device $dev");
	return $dev;
    }

    my $original = $dev;
    my $partition = undef;

    # Check if $dev consists of something like (hd0,0), thus a grub device
    if ($dev =~ /\(([^,]+),([^,]+)\)/) {
	$dev = $1;
	$partition = $2 + 1;
    }
    elsif ($dev =~ /\(([^,]+)\)/) {
	$dev = $1;
    }

    while ((my $unix, my $fw) = each (%{$self->{"device_map"}})) {
	if ($dev eq $fw) {
	    $dev = $unix;
	}
    }

    # resolve symlinks.....
    my $cmd = "udevinfo  -q name -n $dev";
    if (my $resolved_link = qx{$cmd 2> /dev/null}) {
	chomp ($resolved_link);
	$dev = "/dev/" . $resolved_link; 
    }

    if (defined ($partition)) {
	foreach my $dev_ref (@{$self->{"partitions"}}) {
	    if ($dev_ref->[1] eq $dev && $dev_ref->[2] == $partition) {
		$dev = $dev_ref->[0];
		$self->l_debug ("GRUB::GrubDev2UnixDev: Translated $original to $dev");
		return $dev;
	    }
	}
    }

    $dev = $self->Member2MD ($dev);
    $self->l_debug ("GRUB::GrubDev2UnixDev: Translated GRUB->UNIX: $original to $dev");
    return $dev;
}

=item
C<< $grub_dev = Bootloader::Core::GRUB->UnixDev2GrubDev ($unix_dev); >>

Translates the UNIX device (eg. '/dev/hda1') to GRUB device (eg. '(hd0,0)').
As argument takes the UNIX device, returns the GRUB device (both strings).

=cut

# string UnixDev2GrubDev (string unix_dev)
sub UnixDev2GrubDev {
    my $self = shift;
    my $dev = shift;

    unless (defined($dev) and $dev) {
	$self->l_debug ("GRUB::UnixDev2GrubDev: Empty device to translate");
	return $dev;
    }
    # Seems to be a grub device already 
    if ($dev =~ /^\(.*\)$/) {
	$self->l_debug ("GRUB::UnixDev2GrubDev: Not translating device $dev");
	return $dev;
    }

    # This gives me the devicename, wether $dev is the device or a link!
    # This works for udev (kernel) devices only, devicemapper doesn't 
    # need to be changed here 
    my $original = $dev;
    my $kernel_dev;
    my $cmd = "udevinfo  -q name -n $dev";
    if ($kernel_dev = qx{$cmd 2> /dev/null}) {
	chomp $kernel_dev;
	$kernel_dev = "/dev/" . $kernel_dev;
    }
    else {
	$kernel_dev = $dev;
    }
    
    my $partition = undef;
    if ($dev =~ m#/dev/md\d+#) {
	my @members = @{$self->MD2Members ($dev) || []};
	# FIXME! This only works for mirroring (Raid1)
	$kernel_dev = $members[0] || $kernel_dev;
	$self->l_debug ("GRUB::UnixDev2GrubDev: First device of MDRaid:: $original --> $kernel_dev");
    }

    # fetch the underlying device (sda1 --> sda)
    foreach my $dev_ref (@{$self->{"partitions"}}) {
	if ($dev_ref->[0] eq $kernel_dev) {
	    $kernel_dev = $dev_ref->[1];
	    $partition = $dev_ref->[2] - 1;
	    $self->l_debug ("GRUB::UnixDev2GrubDev: dev_ref:  ".$dev_ref->[0]." ".$dev_ref->[1]." ".$dev_ref->[2]);
	    last;
	}
    }

    # get the symbolic link from udev, it might be used in device.map
    # udevinfo returns a space separated list of strings
    $cmd = "udevinfo  -q symlink -n $kernel_dev";

    my @udev_links = split (/ /, qx{$cmd 2>/dev/null});

    # now check kernel devices / devicemapper devices 
    if ( exists $self->{"device_map"}->{$kernel_dev} ) {
	$dev = $self->{"device_map"}->{$kernel_dev};
    }
    else {
	foreach my $udev_link (@udev_links) { 
	    chomp ($udev_link);
	    $udev_link = "/dev/" . $udev_link;
	    if (exists $self->{"device_map"}->{$udev_link} ) {
		$dev = $self->{"device_map"}->{$udev_link};
	    }
	}
    }

    $dev = defined ($partition)
	? "($dev,$partition)"
	: "($dev)";
    $self->l_debug ("GRUB::UnixDev2GrubDev: Translated UNIX->GRUB: $original to $dev");
    return $dev;
}

=item
C<< $unix_path = Bootloader::Core::GRUB->GrubPath2UnixPath ($grub_path, $grub_dev_prefix); >>

Translates the GRUB path (eg. '(hd0,0)/grub/device.map') to UNIX path (eg.
'/boot/grub/device.map'). If the GRUB path does not contain the device, the one
specified in the argument is used instead.
As arguments, the function takes the GRUB path and the device to be used if not
specified in the GRUB path, and returns the UNIX path (all strings).

=cut

# string GrubPath2UnixPath (string grub_path, string grub_dev_prefix)
sub GrubPath2UnixPath {
    my $self = shift;
    my $path = shift;
    my $dev = shift;

    my $orig_path = $path;
    if ($path =~ /^(\(.+\))(.+)$/) {
	$dev = $1;
	$path = $2;
    }
    else {
	$orig_path = $dev . $path;
    }

    if ($dev eq "") {
	$self->l_warning ("GRUB::GrubPath2UnixPath: Path $orig_path in UNIX form, not modifying it");
	return $orig_path;
    }

    #FIXME: sf@ need to check for udev links here as well
    #$dev = $self->GrubDev2UnixDev ($dev);
    #$dev = $self->Member2MD ($dev);

    my $mountpoint;
    if ($dev) {
	 $mountpoint = $self->GrubDev2MountPoint($dev)
    }
    else {
	$mountpoint = $dev;
    }

=cut
    while ((my $mp, my $d) = each (%{$self->{"mountpoints"}})) {
	if ($d eq $dev) {
	    $mountpoint = $mp;
	}
    }
=cut

    # no mount point found 
    if ($mountpoint eq $dev) {
	$self->l_milestone ("GRUB::GrubPath2UnixPath: Device $dev does not have mount point, keeping GRUB path $orig_path");
	return $orig_path;
    }

    $path = $mountpoint . $path;
    $path = $self->CanonicalPath ($path);
    $self->l_debug ("GRUB::GrubPath2UnixPath: Translated GRUB->UNIX dev: $dev, path: $orig_path to: $path");
    return $path;
}

=item
C<< $grub_path = Bootloader::Core::GRUB->UnixPath2GrubPath ($unix_path, $grub_dev_prefix); >>

Translates the UNIX path (eg. '/boot/grub/device.map') to GRUB path (eg.
'(hd0,0)/grub/device.map'). If the device (as specified in GRUB configuration
files via the 'root' option) is the same as the device in the resulting path,
the resulting path does not contain the device.
As arguments, the function takes the UNIX path and the device as specified via
'root' option, and returns the GRUB path (all strings).

=cut

# string UnixPath2GrubPath (string unix_path, string grub_dev_prefix)
sub UnixPath2GrubPath {
    my $self = shift;
    my $orig_path = shift;
    my $preset_dev = shift;

    if ($orig_path =~ /^\(.+\).+$/) {
	$self->l_milestone ("GRUB::UnixPath2GrubPath: Path $orig_path in GRUB form, keeping it");
	return $orig_path;
    }

    (my $dev, my $path) = $self->SplitDevPath ($orig_path);

    $dev = $self->UnixDev2GrubDev ($dev);
    if ($dev eq $preset_dev) {
	$dev = "";
    }

    $path = $dev . $path;
    $self->l_debug ("GRUB::UnixPath2GrubPath: Translated path: $orig_path, prefix $preset_dev, to: $path");
    return $path;
}

=item
C<< $grub_conf_line_ref = Bootloader::Core::GRUB->CreateGrubConfLine ($target, $discswitch); >>

Creates a hash representing a line of /etc/grub.conf file. As arguments, it takes
the device to install GRUB to, and the discswitch argument ('d' or ''). Returns a
reference to a hash containing info about the 'install' line.

=cut

# map<string,string> CreateGrubConfLine (string target, string discswitch,
# boolean use_setup)
sub CreateGrubConfLine {
    my $self = shift;
    my $target = shift;
    my $discswitch = shift;
    my $use_setup = shift;


    my $line_ref = {};
    if ($use_setup)
    {
	$line_ref = {
	    'options' => [
		'--stage2=/boot/grub/stage2'
	    ],
	    'device' => $target,
	    'command' => 'setup'
	};
    }
    else
    {
	$line_ref = {
	    'options' => [
		'--stage2=/boot/grub/stage2'
	    ],
	    'discswitch' => $discswitch || "",
	    'stage2' => '/boot/grub/stage2',
	    'menu' => '/boot/grub/menu.lst',
	    'stage1' => '/boot/grub/stage1',
	    'device' => $target,
	    'addr' => '0x8000',
	    'command' => 'install'
	};
    }
    return $line_ref;
}

#external iface

=item
C<< $files_ref = Bootloader::Core::GRUB->ListFiles (); >>

Returns the list of the configuration files of the bootloader
Returns undef on fail

=cut

# list<string> ListFiles ()
sub ListFiles {
    my $self = shift;

    return [ "/boot/grub/menu.lst", "/boot/grub/device.map", "/etc/grub.conf" ];
}

sub ListMenuFiles {
    my $self = shift;

    return [ "/boot/grub/menu.lst" ];
}

=item
C<< $status = Bootloader::Core::GRUB->ParseLines (\%files); >>

Parses the contents of all files and stores the settings in the
internal structures. As argument, it takes a hash reference, where
keys are file names and values are references to lists, each member is
one line of the file. Returns undef on fail, defined nonzero value on
success.

=cut

# void ParseLines (map<string,list<string>>)
sub ParseLines {
    my $self = shift;
    my %files = %{+shift};

    #first set the device map - other parsing uses it
    my @device_map = @{$files{"/boot/grub/device.map"} || []};
    my %devmap = ();
    foreach my $dm_entry (@device_map)
    {
	if ($dm_entry =~ /^\s*\(([^\s#]+)\)\s+(\S+)\s*$/)
	{
	    $devmap{$2} = $1;
	}
    };
    $self->{"device_map"} = \%devmap;

    # and now proceed with menu.lst
    my @menu_lst = @{$files{"/boot/grub/menu.lst"} || []};
    $self->l_milestone ("GRUB::Parselines: input from menu.lst :\n'" .
			join("'\n' ", @menu_lst) . "'");
    (my $glob_ref, my $sect_ref) = $self->ParseMenuFileLines (
	0,
	["title"],
	\@menu_lst
    );

    # and finally get the location from /etc/grub.conf
    my @grub_conf_lines = @{$files{"/etc/grub.conf"} || []};
    $self->l_milestone ("GRUB::Parselines: input from /etc/grub.conf :\n'" .
			join("'\n' ", @grub_conf_lines) . "'");
    my $grub_root = "";
    my @grub_conf = ();
    my @devices = ();

    $self->l_milestone ("GRUB::Parselines: global boot setting already found: ". 
			 join( ", ", grep { m/^boot_/; } keys %$glob_ref));
    foreach my $line (@grub_conf_lines)
    {
	next unless $line =~ /^\s*(\S+)(\s+(\S+.*))?$/;

	my $key = $1;
	my $value = $3;
	
	last if $key eq "quit";
	next if substr ($key, 0, 1) eq "#";

	if ($key eq "root" || $key eq "rootnoverify")
	{
	    $grub_root = $value;
	}
	elsif (($key eq "install") or ($key eq "setup")) {
	    my @options = ();
	    my %grub_conf_item = ();
	    $grub_conf_item{"command"} = $key;
	    my @entries = split /\s+/, $value;
	    my $tmp = shift @entries;
	    while (substr ($tmp, 0, 2) eq "--")
	    {
		push @options, $tmp;
		$tmp = shift @entries;
	    }
	    $grub_conf_item{"options"} = \@options;

	    if ($key eq "install") {
		$grub_conf_item{"stage1"} = $self->GrubPath2UnixPath ($tmp, $grub_root);
		$tmp = shift @entries;
		if ("d" eq $tmp)
		{
		    $grub_conf_item{"discswitch"} = "d";
		    $tmp = shift @entries;
		}
		else
		{
		    $grub_conf_item{"discswitch"} = "";
		}
		$tmp = $self->GrubDev2UnixDev ($tmp);
		push @devices, $tmp;
		$grub_conf_item{"device"} = $tmp;
		$grub_conf_item{"stage2"} = $self->GrubPath2UnixPath ( shift @entries, $grub_root);
		$grub_conf_item{"addr"} = shift @entries || "";
		$tmp = shift @entries;
		if ($tmp ne "")
		{
		    $grub_conf_item{"menu"} = $self->GrubPath2UnixPath ($tmp, $grub_root);
		}
	    }
	    else
	    { # "setup"
		$tmp = $self->GrubDev2UnixDev ($tmp);
		push @devices, $tmp;
		$grub_conf_item{"options"} = \@options;
		$grub_conf_item{"device"} = $tmp;
		# not interested in the rest
	    }
	    push @grub_conf, \%grub_conf_item;
	}
    }

    # FIXME: still incomplete for MD and dmraid devs
    # translate device array to the various boot_* flags else set boot_custom
    # in glob_ref accordingly
    my ($boot_dev,) = $self->SplitDevPath ("/boot");
    my ($root_dev,) = $self->SplitDevPath ("/");
    my $extended_dev = $self->GetExtendedPartition($boot_dev);
    # mbr_dev is the first bios device
    my $mbr_dev =  $self->GrubDev2UnixDev("(hd0)");

    foreach my $dev (@devices) {
	$self->l_milestone ("GRUB::Parselines: checking boot device $dev");

	if ($dev eq $mbr_dev) {
	    $glob_ref->{"boot_mbr"} = "true";
	    $self->l_milestone ("GRUB::Parselines: detected boot_mbr");
	}
	elsif ($dev eq $root_dev) {
	    $glob_ref->{"boot_root"} = "true";
	    $self->l_milestone ("GRUB::Parselines: detected boot_root");
	}
	elsif ($dev eq $boot_dev) {
	    $glob_ref->{"boot_boot"} = "true";
	    $self->l_milestone ("GRUB::Parselines: detected boot_boot");
	}
	elsif ($dev eq $extended_dev) {
	    $glob_ref->{"boot_extended"} = "true";
	    $self->l_milestone ("GRUB::Parselines: detected boot_extended");
	}
	else {
	    $glob_ref->{"boot_custom"} = $dev;
	    $self->l_milestone ("GRUB::Parselines: set boot_custom");
	}
    }			 

    # $glob_ref->{"stage1_dev"} = \@devices;
    $self->{"sections"} = $sect_ref;
    $self->{"global"} = $glob_ref;
    $self->{"grub_conf"} = \@grub_conf;
    return 1;
}


=item
C<< $files_ref = Bootloader::Core::GRUB->CreateLines (); >>

creates contents of all files from the internal structures.
Returns a hash reference in the same format as argument of
ParseLines on success, or undef on fail.

=cut

# map<string,list<string>> CreateLines ()
sub CreateLines {
    my $self = shift;

    # first create /etc/grub.conf
    my $grub_conf = $self->CreateGrubConfLines();

    # secondly process /boot/grub/menu.lst
    my $menu_lst = $self->PrepareMenuFileLines (
	$self->{"sections"},
	$self->{"global"},
	"    ",
	" "
    );

    # handle 'hidden magic' entries
    map {
	s/^/##YaST - /
	    if /^activate/ or /^generic_mbr/;
    } @{$menu_lst};

    # now process the device map
    my %glob = %{$self->{"global"}};
    my @device_map = ();
    while ((my $unix, my $fw) = each (%{$self->{"device_map"}}))
    {
	my $line = "($fw)\t$unix";
	push @device_map, $line;
    }

    #return all files
    return {
	"/boot/grub/menu.lst" => $menu_lst,
	"/boot/grub/device.map" => \@device_map,
	"/etc/grub.conf" => $grub_conf,
    }
}


sub CreateGrubConfLines() {
    my $self = shift;

    # process /etc/grub.conf
    my %glob = %{$self->{"global"}};
    my @grub_conf = ();
    my %s1_devices = ();

    {
	my $dev;
	my $flag;

	# boot_custom => "selectdevice:Custom Boot Partition::"
	$dev = delete($glob{"boot_custom"});
	$s1_devices{$dev} = 1 if defined $dev;
	
	# boot_mbr    => "bool:Boot from Master Boot Record:false",
	$flag = delete $glob{"boot_mbr"};
	if (defined $flag and $flag eq "true") {
	    # if /boot mountpoint exists add($disk(/boot) else add disk(/)
	    # mbr_dev is the first bios device
	    $dev =  $self->GrubDev2UnixDev("(hd0)");
	    $s1_devices{$dev} = 1 if defined $dev;
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

    $self->l_milestone ("GRUB::CreateGrubConfLines: found s1_devices: "
			. join(",",keys %s1_devices));

    # keep the first bootloader setup command for every boot device and drop
    # all other
    # FIXME: shouldn't we make comments from that? comment handling here at all?
    my @grub_conf_items = grep {
	my $keep = 1;
	if ($_->{"command"} eq "install"|| $_->{"command"} eq "setup")
	{
	    $keep = defined (delete $s1_devices{$_->{"device"}});
	}
	$keep;
    } @{$self->{"grub_conf"}};

    $self->l_milestone ("GRUB::CreateGrubConfLines: " .
			"remaining s1_devices to create new lines: "
			. join(",",keys %s1_devices));

    if (scalar (keys (%s1_devices)) > 0)
    {
	my $discswitch = undef;
	foreach my $item_ref (@grub_conf_items)
	{
	    last if defined $discswitch;
	    $discswitch = $item_ref->{"discswitch"}
	}

	unless (defined ($discswitch))
	{
	    $discswitch = "";
	    my ($loc, ) = keys (%s1_devices);
	    if (defined ($loc))
	    {
		my $s1_dev = $loc;
		my ($s2_dev,) = $self->SplitDevPath ("/boot/grub/stage2");
		$s1_dev = $self->Partition2Disk ($s1_dev);
		$s2_dev = $self->Partition2Disk ($s2_dev);
		if ($s1_dev ne $s2_dev)
		{
		    $discswitch = "d";
		}
	    }
	}

	foreach my $new_dev (keys (%s1_devices))
	{
	    my $line = $self->CreateGrubConfLine ($new_dev, $discswitch, 1);
	    $self->l_milestone ("GRUB::CreateGrubConfLines: new line created: $line");

	    push @grub_conf_items, $line;
	}
    }

    my $last_root = "";
    (my $stage1dev,) = $self->SplitDevPath ("/boot/grub/stage1");

    # For RAID1 devices, tell grub to read the kernel&stuff from first disk
    # array member
    if ($stage1dev =~ m:/dev/md\d+:) {
	my @members = @{$self->MD2Members ($stage1dev) || []};
	# FIXME! This only works for mirroring (Raid1)
	# FIXME: boot from MBR does not work for RAID1 yet
	$stage1dev = $members[0] || $stage1dev;
    }
    $stage1dev = $self->UnixDev2GrubDev ($stage1dev);

    foreach my $grub_conf_item (@grub_conf_items)
    {
	if ($grub_conf_item->{"command"} eq "install")
	{
	    (my $s1dev,) = $self->SplitDevPath ($grub_conf_item->{"stage1"});
	    (my $s2dev,) = $self->SplitDevPath ($grub_conf_item->{"stage2"});
	    my $grub_root = "";
	    if ($s1dev eq $s2dev)
	    {
		$grub_root = $self->UnixDev2GrubDev ($s1dev);
		if ($last_root ne $grub_root)
		{
		    push @grub_conf, "root $grub_root";
		}
		$last_root = $grub_root;
	    }
	    my $options = join " ", @{$grub_conf_item->{"options"} || []};
	    my $s1 = $self->UnixPath2GrubPath ($grub_conf_item->{"stage1"}, $grub_root);
	    my $s2 = $self->UnixPath2GrubPath ($grub_conf_item->{"stage2"}, $grub_root);
	    my $location = $self->UnixDev2GrubDev ($grub_conf_item->{"device"});
	    my $address = $grub_conf_item->{"addr"};
	    my $discswitch = $grub_conf_item->{"discswitch"};
	    $discswitch = " " . $discswitch if ($discswitch ne "");
	    my $menu_lst = $self->UnixPath2GrubPath ($grub_conf_item->{"menu"}, "");
	    my $line = "install $options $s1$discswitch $location $s2 $address $menu_lst";
	    push @grub_conf, $line;
	    delete $s1_devices{$grub_conf_item->{"device"}};
	}
	elsif ($grub_conf_item->{"command"} eq "setup")
	{
	    my $options = join " ", @{$grub_conf_item->{"options"} || []};
	    my $location = $self->UnixDev2GrubDev ($grub_conf_item->{"device"});
	    my $line = "setup $options $location " . $stage1dev || $location;
	    push @grub_conf, $line;
	    delete $s1_devices{$grub_conf_item->{"device"}};
	}
    }
    push @grub_conf, "quit";

    return \@grub_conf;
}


=item
C<< $sectin_info_ref = Bootloader::Core::GRUB->Section2Info (\@section_lines); >>

Gets the information about the section. As argument, takes a reference to the
list of lines building the section, returns a reference to a hash containing
information about the section.
=cut

# map<string,string> Section2Info (list<map<string,any>> section)
sub Section2Info {
    my $self = shift;
    my @lines = @{+shift};

    my %ret = ();
    my $grub_root = "";
    my $modules = 0;
    my $type = $self->EvalSectionType (\@lines);
    $ret{"type"} = $type;

    foreach my $line_ref (@lines) {
	my $key = $line_ref->{"key"};
	my $val = $line_ref->{"value"};

	# do mapping of config file names to internal
	if ($type eq "xen") {
	    if ($key eq "kernel") {
		$key = "xen";
	    }
	    elsif ($line_ref->{"key"} eq "module") {
		if ($modules == 0) {
		    $key = "image";
		}
		elsif ($modules == 1) {
		    $key = "initrd";
		}
		$modules++;
	    }
	}
	elsif ($type eq "image") {
	    if ($key eq "kernel") {
		$key = "image";
	    }
	}
	# remapping end, start processing

	# FIXME : check against metadata?

	if ($key eq "root" || $key eq "rootnoverify")
	{
	    if ($type eq "menu") {
		$ret{"root"} = $self->GrubDev2UnixDev ($val);
	    }
	    else {
		$grub_root = $val;
		$ret{"noverifyroot"} = "true" if ($key eq "rootnoverify");
	    }
	}
	elsif ($key eq "title")
	{
	    $ret{"name"} = $val;
	    my $on = $self->Comment2OriginalName ($line_ref->{"comment_before"});
	    $ret{"original_name"} = $on if ($on ne "");
	}
	elsif ($key eq "image")
	{
	    # split into loader and parameter, note that the regex does
	    # always match, then split out root= vgamode= and append= values
	    $val =~ /^\s*(\S+)(?:\s+(.*))?$/;
    
	    $ret{"image"} = $self->GrubPath2UnixPath ($1, $grub_root);
	    $val = $2 || "";

	    if ($val =~ /^(?:(.*)\s+)?root=(\S+)(?:\s+(.*))?$/)
	    {
		$ret{"root"} = $2 if $2 ne "";
		$val = $self->MergeIfDefined ($1, $3);
	    }
	    if ($val =~ /^(?:(.*)\s+)?vga=(\S+)(?:\s+(.*))?$/)
	    {
		$ret{"vgamode"} = $2 if $2 ne "";
		$val = $self->MergeIfDefined ($1, $3);
	    }
	    if ($val ne "")
	    {
		$ret{"append"} = $val;
		if ($type eq "xen") {
		    if ($val =~ /console=ttyS(\d+),(\d+)/) {
			# merge console and speed into xen_append
			my $console = sprintf("com%d", $1+1);
			my $speed   = sprintf("%s=%d", $console, $2);
			if (exists $ret{"xen_append"}) {
			    my $xen_append = $ret{"xen_append"};
			    while ($xen_append =~
				   s/(.*)console=(\S+)\s*(.*)$/$1$3/o) {
				my $del_console = $2;
				$xen_append =~
				    s/(.*)${del_console}=\d+\s*(.*)$/$1$2/g;
			    }
			    $ret{"xen_append"} = "console=$console $speed $xen_append";
			} else {
			    $ret{"xen_append"} = "console=$console $speed";
			}
		    }
		}
	    }
	}
	elsif ($key eq "xen")
	{
	    # split into loader and parameter, note that the regex does
	    # always match
	    $val =~ /^\s*(\S+)(?:\s+(.*))?$/;

	    $ret{"xen"} = $self->GrubPath2UnixPath ($1, $grub_root);
	    $ret{"xen_append"} = $2 if defined $2;
	}
	elsif ($key eq "initrd" || $key eq "wildcard" || $key eq "configfile")
	{
	    $ret{$key} = $self->GrubPath2UnixPath ($val, $grub_root);
	}
	elsif ($key eq "chainloader")
	{
	    if ($val =~ /^(.*)\+(\d+)/)
	    {
		$val = $1;
		$ret{"blockoffset"} = $2;
		if ($val eq "")
		{
		    $val = $grub_root;
		}
		$val = $self->GrubDev2UnixDev ($val);
	    }
	    else
	    {
		$val = $self->GrubPath2UnixPath ($val, $grub_root);
	    }
	    $ret{$key} = $val;
	}
    }

    $ret{"__lines"} = \@lines;
    return \%ret;
}

=item

C<< $dev = Bootloader::Core::GRUB->GetCommonDevice (@paths); >>

Checks all paths given as arguments if they are on the same device. If so,
returns the common device, otherwise returns empty string.

=cut

#string GetCommonDevice (string path1, string path2, ...)
sub GetCommonDevice {
    my $self = shift;
    my @paths = @_;

    my $common_device = undef;
    my $occurrences = 0;

    foreach my $path (@paths)
    {
	(my $dev, $path) = $self->SplitDevPath ($path || "");
	if (defined ($dev))
	{
	    if (! defined ($common_device))
	    {
		$common_device = $dev;
		$occurrences = 1;
	    }
	    elsif ($common_device eq $dev)
	    {
		$occurrences = $occurrences + 1;
	    }
	    else
	    {
		return "";
	    }
	}
    }
    return $occurrences > 1 ? $common_device : "";
}

=item

C<< $line = Bootloader::Core::GRUB->CreateKernelLine (\%sectingo, $grub_root); >>

Creates a line with the kernel command for GRUB's menu.lst. As arguments.
it takes a hash containing information about the section and the root
device specified by the GRUB's root command. Returns the line to be written
to menu.lst (without the leading kernel keyword).

=cut

#string CreateKernelLine (map sectinfo, string grub_root)
sub CreateKernelLine {
    my $self = shift;
    my $sectinfo_ref = shift;
    my $grub_root = shift || "";

    my $root = $sectinfo_ref->{"root"} || "";
    my $vga = $sectinfo_ref->{"vgamode"} || "";
    my $append = $sectinfo_ref->{"append"} || "";
    my $image = $sectinfo_ref->{"image"} || "";
    $root = " root=$root" if $root ne "";
    $vga = " vga=$vga" if $vga ne "";
    $append = " $append" if $append ne "";
    $image = $self->UnixPath2GrubPath ($image, $grub_root);
    return "$image$root$vga$append";
}

=item

C<< $line = Bootloader::Core::GRUB->CreateChainloaderLine (\%sectinfo, $grub_root); >>

Creates a line with the chainloader command for GRUB's menu.lst. As arguments.
it takes a hash containing information about the section and the root
device specified by the GRUB's root command. Returns the line to be written
to menu.lst (without the leading chainloader keyword).

=cut

#string CreateChainloaderLine (map sectinfo, string grub_root)
sub CreateChainloaderLine {
    my $self = shift;
    my $sectinfo_ref = shift;
    my $grub_root = shift || "";

    my $sectors = $sectinfo_ref->{"blockoffset"};
    my $line = $sectinfo_ref->{"chainloader"};
    if (substr ($line, 0, 5) eq "/dev/" && ! defined ($sectors))
    {
	$sectors = 1;
    }
    if (defined ($sectors) && $sectors > 0)
    {
	$line = $self->UnixDev2GrubDev ($line);
	if (substr ($line, 0, length ($grub_root)) eq $grub_root)
	{
	    $line = substr ($line, length ($grub_root));
	}
	$line = $line . "+" . $sectors;
	return $line;
    }
    else
    {
	return $self->UnixPath2GrubPath ($line, $grub_root);
    }
}

=item
C<< $disk = Bootloader::Core::Grub->Partition2Disk ($partition); >>

Gets the disk a partition resides on. As argument, it takes the partition
device node (eg. C<'/dev/hda3'>), returns the device node of the disk
holding the partition (eg. C</dev/hda>), or undef if checking failed.

=cut

# string Partition2Disk (string partition)
sub Partition2Disk {
    my $self = shift;
    my $partition = shift;

    foreach my $dev_ref (@{$self->{"partitions"}})
    {
	if ($dev_ref->[0] eq $partition)
	{
	    return $dev_ref->[1];
	}
    }

    # FIXME:
    # check in device mapping as a fallback

    return $partition; 
}

sub EvalSectionType {
    my $self = shift;
    my @lines = @{+shift};

    my $modules = 0;
    my $kernel_xen = 0;
    my $chainloader = 0;
    my $configfile = 0;
    my $image = 0;

    foreach my $line_ref (@lines) {
	if ($line_ref->{"key"} eq "module") {
	    $modules++;
	}
	elsif ($line_ref->{"key"} eq "kernel" && $line_ref->{"value"} =~ m/xen/) {
	    $kernel_xen = 1;
	}
	elsif ($line_ref->{"key"} eq "chainloader") {
	    $chainloader = 1;
	}
	elsif ($line_ref->{"key"} eq "configfile") {
	    $configfile = 1;
	}
        elsif ($line_ref->{"key"} eq "kernel" or $line_ref->{"key"} eq "image") {
            $image = 1;
        }
    }
    if ($configfile) {
	return "menu";
    }
    elsif ($modules > 0 and $kernel_xen and not $chainloader) {
	return "xen";
    }
    elsif ($chainloader and $modules == 0 and $kernel_xen == 0) {
	return "other";
    }
    elsif ($image) {
        return "image";
    }

    # return "custom" type as a fallback (for unknown or custom section types)
    return "custom";
}

=item
C<< $lines_ref = Bootloader::Core::GRUB->Info2Section (\%section_info); >>

Takes the info about the section and uses it to construct the list of lines.
The info about the section also contains the original lines.
As parameter, takes the section info (reference to a hash), returns
the lines (a list of hashes).
=cut

# list<map<string,any>> Info2Section (map<string,string> info)
sub Info2Section {
    my $self = shift;
    my %sectinfo = %{+shift};

    my @lines = @{$sectinfo{"__lines"} || []};
    my $type = $sectinfo{"type"} || "";
    my $so = $self->{"exports"}{"section_options"};
    my $modules = 0;

    # allow to keep the section unchanged
    if (! ($sectinfo{"__modified"} || 0))
    {
	return $self->FixSectionLineOrder (
	    \@lines,
	    ["title"]);
    }

    #if section type is not known, don't touch it.
    if ($type ne "image" and $type ne "other" and $type ne "xen" and $type ne "menu")
    {
	return \@lines;
    }
    my $grub_root = "";
    if (defined ($sectinfo{"image"}) && defined ($sectinfo{"initrd"}))
    {
	$grub_root = $self->GetCommonDevice ($sectinfo{"image"}, $sectinfo{"initrd"});
	$grub_root = $self->UnixDev2GrubDev ($grub_root);
    }
    elsif ($type eq "menu") {
	my ($boot_dev,) = $self->SplitDevPath ("/boot");
	$grub_root = $self->UnixDev2GrubDev (
	    exists $sectinfo{"root"} ? delete($sectinfo{"root"}) : $boot_dev
        );
    }

    if ($type eq "xen") {
	if (exists($sectinfo{"append"}) and
	    ($sectinfo{"append"} =~ /console=ttyS(\d+),(\d+)/) )
	{
	    # merge console and speed into xen_append
	    my $console = sprintf("com%d", $1+1);
	    my $speed   = sprintf("%s=%d", $console, $2);
	    if (exists $sectinfo{"xen_append"}) {
		my $xen_append = $sectinfo{"xen_append"};
		while ($xen_append =~
		       s/(.*)console=(\S+)\s*(.*)$/$1$3/o) {
		    my $del_console = $2;
		    $xen_append =~
			s/(.*)${del_console}=\d+\s*(.*)$/$1$2/g;
		}
		$sectinfo{"xen_append"} = "console=$console $speed $xen_append";
	    } else {
		$sectinfo{"xen_append"} = "console=$console $speed";
	    }
	}
    }

    @lines = map {
	my $line_ref = $_;
	my $key = $line_ref->{"key"};

	if ($key eq "root" or $key eq "rootnoverify" or $key eq "configfile")
	{
	    # always remove old root line
	    $line_ref = undef;
	}
	elsif ($key eq "title")
	{
	    $line_ref = $self->UpdateSectionNameLine ($sectinfo{"name"}, $line_ref, $sectinfo{"original_name"});
	    delete ($sectinfo{"name"});
	}
	elsif ($key eq "module") {
	    # put module lines always at the end.
	    $line_ref = undef;
	}
	elsif ($key eq "kernel") {
	    if ($type eq "xen") {
		$line_ref->{"value"} =
		    $self->UnixPath2GrubPath (delete($sectinfo{"xen"}), $grub_root)
		    . " " . (delete($sectinfo{"xen_append"}) || "");
	    }
	    elsif ($type eq "image") {
		$line_ref->{"value"} = $self->CreateKernelLine (\%sectinfo, $grub_root);
		delete ($sectinfo{"root"});
		delete ($sectinfo{"vgamode"});
		delete ($sectinfo{"append"});
		delete ($sectinfo{"image"});
	    }
	}
	elsif ($key eq "initrd" || $key eq "wildcard")
	{
	    if ($type eq "other" or not defined ($sectinfo{$key})) {
		$line_ref = undef;
	    }
	    else {
		$line_ref->{"value"} = $self->UnixPath2GrubPath ($sectinfo{$key}, $grub_root);
	    }
	    delete ($sectinfo{$key});
	}
	elsif ($key eq "chainloader")
	{
	    if ($type eq "other" and defined ($sectinfo{$key})) {
		$line_ref->{"value"} = $self->CreateChainloaderLine (\%sectinfo, $grub_root);
		delete ($sectinfo{$key});
		delete ($sectinfo{"blockoffset"});
	    }
	    else {
		$line_ref = undef;
	    }
	}
	defined $line_ref ? $line_ref : ();
    } @lines;

    # prepend a root/rootnoverify line where appropriate
    # handle noverify flag and do never verify on chainloader sections
    my $noverify = ($type eq "other");
    if ( exists $sectinfo{"noverifyroot"} and
	 defined $sectinfo{"noverifyroot"})
    {
	$noverify = ($noverify or ($sectinfo{"noverifyroot"} eq "true"));
	delete($sectinfo{"noverifyroot"});
    }
    if ($grub_root ne "" or $noverify) {
	unshift @lines, {
	    "key" => $noverify ? "rootnoverify" : "root",
	    "value" => $grub_root ne "" ? $grub_root : "(hd0,0)",
	};
    }

    # keep a hard order for the following three entries
    if (exists $sectinfo{"xen"}) {
	push @lines, {
	    "key" => "kernel",
	    "value" => $self->UnixPath2GrubPath ($sectinfo{"xen"}, $grub_root)
		. " " . ($sectinfo{"xen_append"} || ""),
	    };
    }
    if (exists $sectinfo{"image"}) {
	my $val = $self->CreateKernelLine (\%sectinfo, $grub_root);
	push @lines, {
	    "key" => ($type eq "xen") ? "module" : "kernel",
	    "value" => $val,
	};
    }
    if (exists $sectinfo{"initrd"}) {
	push @lines, {
	    "key" => ($type eq "xen") ? "module" : "initrd",
	    "value" => $self->UnixPath2GrubPath ($sectinfo{"initrd"}, $grub_root),
	};
    }

    while ((my $key, my $value) = each (%sectinfo))
    {
	if ($key eq "name")
	{
	    my $line_ref = $self->UpdateSectionNameLine ($value, {}, $sectinfo{"original_name"});
	    $line_ref->{"key"} = "title";
	    unshift @lines, $line_ref;
	}
	elsif ($key eq "chainloader")
	{
	    push @lines, {
		"key" => $key,
		"value" => $self->CreateChainloaderLine (\%sectinfo, $grub_root), 
	    };
	}
	elsif ($key eq "configfile")
	{
	    push @lines, {
		"key" => $key,
		"value" => $value,
	    };
	}
    }

    my $ret = $self->FixSectionLineOrder (\@lines,
	["title"]);
    return $ret;
}

=item
C<< $glob_info = $Bootloader::Core::GRUB->Global2Info (\@glob_lines, \@section_names); >>

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
    my $go = $self->{"exports"}{"global_options"};

    my %ret = ();
    my $grub_root = "";

    foreach my $line_ref (@lines) {
	my $key = $line_ref->{"key"};
	my $val = $line_ref->{"value"};
	my ($type) = split(/:/, $go->{$key}||"");
	if (defined ($key) and (($key eq "root") or ($key eq "rootnoverify"))) {
	    $grub_root = $val;
	    $ret{"verifyroot"} = ($key eq "root");
	}
	elsif ($key eq "default") {
	    # cast $val to integer. That means that if no valid default has
	    # been given, we'll take the first section as default.
	    no warnings "numeric"; # this is neccessary to avoid to trigger a perl bug
	    my $defindex = 0+ $val;
	    $ret{"default"} = $sections[$defindex];
	}
	elsif ($type eq "path") {
	    $ret{$key} = $self->GrubPath2UnixPath ($val, $grub_root);
	}
	elsif ($type eq "bool") {
	    $ret{$key} = "true";
	}
	elsif ($key =~ m/^boot_/) {
	    # boot_* parameters are handled else where but should not happen!
	    $self->l_milestone ("GRUB::Global2Info: Wrong item here $key, ignored");
	}
	else {
	    $ret{$key} = $val;
	}
    }
    $ret{"__lines"} = \@lines;
    return \%ret;
}

=item
C<< $lines_ref = Bootloader::Core::GRUB->Info2Global (\%section_info, \@section_names); >>

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
    my $go = $self->{"exports"}{"global_options"};
  
    # allow to keep the section unchanged
    return \@lines unless $globinfo{"__modified"} || 0;

    if (scalar (@lines) == 0)
    {
	@lines = (
	    { "key" => "color", "value" => "white/blue black/light-gray" },
	    { "key" => "default", "value" => 0 },
	    { "key" => "timeout", "value" => 8 },
	);
    }

    @lines = map {
	my $line_ref = $_;
	my $key = $line_ref->{"key"};
	my ($type) = split(/:/, $go->{$key} || "");

	# only accept known global options :-)
	if ( !exists $go->{$key} ) {
		$line_ref = undef;
	}
	elsif (!defined ($globinfo{$key}))
	{
	    $line_ref = undef;
	}
	elsif ($key eq "default")
	{
	    $line_ref->{"value"} = $self->IndexOfSection (
		delete $globinfo{$key}, $sections_ref) || 0;
	}
	elsif ($key eq "password")
	{
	    # FIXME: Do md5 encryption
	    $line_ref->{"value"} = delete $globinfo{$key};
	}
	elsif ($type eq "path")
	{
	    $line_ref->{"value"} = $self->UnixPath2GrubPath (delete $globinfo{$key}, "");
	}
	# bool values appear in a config file or not. there might be types
	# like 'yesno' or 'truefalse' in the future which behave differently
	elsif ($type eq "bool") {
	    if (delete $globinfo{$key} ne "true") {
		$line_ref = undef;
	    }
	    else {
		$line_ref->{"value"} = "";
	    }
	}
	else
	{
	    $line_ref->{"value"} = delete $globinfo{$key};
	}
	defined $line_ref ? $line_ref : ();
    } @lines;


    while ((my $key, my $value) = each (%globinfo))
    {
	# only accept known global options :-)
	next unless exists $go->{$key};
	next if $key =~ m/^boot_/; # handled else where
	my ($type) = split /:/, $go->{$key};

	if ($key eq "default") {
	    $value = $self->IndexOfSection ($value, $sections_ref) || 0;
	}
	# bool values appear in a config file or not
	elsif ($type eq "bool") {
	    next if $value ne "true";
	    $value = "";
	}
	elsif ($type eq "path")
	{
	    $value = $self->UnixPath2GrubPath ($value, "");
	}

	push @lines, {
	    "key" => $key,
	    "value" => $value,
	}
    }

    return \@lines;
}

=item
C<< $settings_ref = Bootloader::Core::GRUB->GetSettings (); >>

returns the complete settings in a hash. Does not read the settings
from the system, but returns internal structures.

=cut

# map<string,any> GetSettings ()
sub GetSettings {
    my $self = shift;

    my $ret = $self->SUPER::GetSettings ();
    foreach my $key ("grub_conf")
    {
	if (defined ($self->{$key}))
	{
	    $ret->{$key} = $self->{$key};
	}
    }
    return $ret;
}

=item
C<< $status = Bootloader::Core::GRUB->SetSettings (\%settings); >>

Stores the settings in the given parameter to the internal
structures. Does not touch the system.
Returns undef on fail, defined nonzero value on success.

=cut

# void SetSettings (map<string,any> settings)
sub SetSettings {
    my $self = shift;
    my %settings = %{+shift};

    foreach my $key ("grub_conf")
    {
	if (defined ($settings{$key}))
	{
	    $self->{$key} = $settings{$key};
	}
    }
    return $self->SUPER::SetSettings (\%settings);
}

=item
C<< $status = Bootloader::Core::GRUB->InitializeBootloader (); >>

Initializes the firmware to boot the bootloader.
Returns undef on fail, defined nonzero value otherwise

=cut

# boolean InitializeBootloader ()
sub InitializeBootloader {
    my $self = shift;

    # FIXME: activate
    # call parted if activate set

    # FIXME: generic_mbr
    # write generic_mbr in case

    my $log = "/var/log/YaST2/y2log_bootloader";
    my $ret = $self->RunCommand (
	"cat /etc/grub.conf | /usr/sbin/grub --device-map=/boot/grub/device.map --batch",
	$log
    );
    if ($ret == 0)
    {
	open (LOG, $log) || return $ret;
	while (my $line = <LOG>)
	{
	    if ($line =~ /Error [0-9]*:/)
	    {
		return undef;
	    }
	}
	close (LOG);
    }
    return $ret == 0;
}

=item
C<< $mountpoint = Bootloader::Core::GRUB->GrubDev2MountPoint (); >>

creates the mountpoint from a Grub Device (hdX,Y), be it
a udev device, a udev link or a device mapper device

returns the mountpoint or the grub device, if it couldn't be resolved

=cut

sub GrubDev2MountPoint {
    my $self = shift;
    my $grub_dev = shift;
    my @devices = ();
    my $device = $self->GrubDev2UnixDev($grub_dev);

    # MD-RAID handling: find the corresponding /dev/mdX if any.
    while ((my $md, my $members_ref) = each (%{$self->{"md_arrays"}})) {

	my $members = join ", ", @{$members_ref};
	$self->l_debug ("GRUB::GrubDev2MountPoint : MD Array: $md ; Members: $members");

	foreach my $md_member (@{$members_ref}) {
	    if ($device eq $md_member) {
		push (@devices, $md);
	    }
	}
    }

    push (@devices, $device);

    #FIXME: sf@ need handling for /dev/dm-X devices here
    if ($device !~ /mapper/) {
	my $cmd = "udevinfo  -q symlink -n $device";
	my @udev_links = split (/ /, qx{$cmd 2>/dev/null});

	foreach $device (@udev_links) {
	    chomp $device;
	    $device = "/dev/" . $device; 
	    push (@devices, $device);
	}    
    }

    my $mountpoint = $grub_dev;
    foreach $device (@devices) {
	while ((my $mp, my $d) = each (%{$self->{"mountpoints"}})) {
	    if ($d eq $device) {
		$mountpoint = $mp;
	    }
	}
    }

    return $mountpoint;  
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
