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


=item
Determines whether grub2 files are installed on an encrypted partition.
=cut

sub CryptoNeeded()
{
  my $self = shift;
  my $crypto = 0;

  my ($dev) = $self->SplitDevPath("/boot/grub2");

  $dev = Cwd::realpath($dev);

  $self->milestone("/boot/grub2 is on $dev");

  $dev =~ s#/dev#/sys/block#;

  do {
    $self->milestone("checking $dev");

    my $uuid;
    if(open my $f, "$dev/dm/uuid") {
      $uuid = <$f>;
      close $f;
    }

    $crypto = 1 if $uuid =~ /^CRYPT/;

    $dev = (glob "$dev/slaves/*")[0];
  }
  while($dev && !$crypto);

  $self->milestone("crypto = $crypto");

  return $crypto;
}


sub GetDeviceMap {

    my $self = shift;
    my $ret = 0;
    my %map_byid = ();
    my %map_kern = ();
    my @blacklist = ();

    # WARN: It may not report disks without partitions.
    # TODO: We need a better way to figure out physical drive though
    # eg, whatever listed by `find /sys/class/block/*/device`
    GETMAP: foreach (@{$self->{"partitions"}}) {

        my $kern_dev = $_->[1];
        my $probe = '/usr/sbin/grub2-probe';
        my $probe_args = "--target=compatibility_hint --device $kern_dev";

        # skip empty drive which is not likely.
        if ($kern_dev eq "") {
            $self->warning ("no drive for a partition\n");
            next GETMAP;
        }

        # skip blaklisted device
        foreach (@blacklist) {
            if ($kern_dev eq $_) {
                $self->milestone ("blacklisted drive $kern_dev in device map");
                next GETMAP;
            }
        }

        my $sys_dev = $kern_dev;
        $sys_dev =~ s#^/dev/##;
        $sys_dev =~ s#/#!#g;
        $sys_dev = "/sys/block/$sys_dev";
        if ( ! -d $sys_dev ) {
            $self->milestone ("skip partition $kern_dev in device map");
            next GETMAP;
        }

        # skip device that's known to be invalid if installed to
        my @ignore = ('/dev/sr', '/dev/tmpfs');
        foreach (@ignore) {
            if ($kern_dev =~ $_) {
                $self->milestone ("ignore $kern_dev in device map");
                next GETMAP;
            }
        }

        # try to map kernel device to grub device if not mapped yet
        if (not exists $map_kern{$kern_dev}) {
            my $gdev = qx($probe $probe_args 2>&1);
            if ($? == 0) {
                chomp $gdev;
                if ($gdev =~ /^[a-z]{1,2}\d+$/) {
                    $map_kern{$kern_dev} = $gdev;
                } else {
                    $self->milestone ("not a grub device: $gdev");
                }
            } else {
                # blacklist the device if grub2-probe fails on them
                # to save some unnecessary cpu cycles
                $self->milestone ("run $probe $probe_args failed with $gdev\n");
                $self->milestone ("blacklist $kern_dev\n");
                push @blacklist, $kern_dev;
            }
        }
    }

    while ((my $udev_dev, my $kern_dev) = each %{$self->{"udevmap"}}) {
        # map by-id device to grub device
        if ($udev_dev =~ /\/by-id\// and exists $map_kern{$kern_dev}) {
            $map_byid{$udev_dev} = $map_kern{$kern_dev};
        }
    }

    # we prefer by-id device than kernel device
    if (%map_kern || %map_byid) {
        # ensure that hash values (hd0, hd1...) are unique
        my %x;
        $x{$map_kern{$_}} = $_ for reverse sort keys %map_kern;
        $x{$map_byid{$_}} = $_ for reverse sort keys %map_byid;
        $self->{device_map}{$x{$_}} = $_ for sort keys %x;
    } else {
        $self->{device_map} = {};
        $self->warning ("empty device.map\n");
    }

    $self->milestone("grub2 device map =", $self->{device_map});
}

sub GetKernelDevice {
    my $self = shift;
    my $orig = shift;
    my $device = $orig;

    unless (defined ($self->{"udevmap"}))
    {
        $self->warning("Udev mapping is not set");
        return $orig;
    }
    $device =  $self->{"udevmap"}->{$device}
        if defined ($self->{"udevmap"}->{$device});

    $self->milestone("From $orig to $device");

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
        $self->error("Empty device to translate");
        return $dev;
    }
    if ($dev !~ /^\(.*\)$/) {
        $self->warning("Not translating device $dev");
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

    $self->milestone("device_map =", $self->{device_map});

    my $match_found = 0;
    while ((my $unix, my $fw) = each (%{$self->{"device_map"}})) {
        if ($dev eq $fw) {
            $dev = $unix;
            $match_found = 1;
        }
    }

    if ($match_found == 0) {
        $self->error("did not find a match for $dev in the device map");
        return $original;
    }

    # resolve symlinks.....
    $dev = $self->GetKernelDevice($dev);
    $self->milestone("Kernel device is $dev");

    if (defined ($partition)) {
        my $finded = undef;
        foreach my $dev_ref (@{$self->{"partitions"}}) {
            if ( $dev_ref->[1] eq $dev
              && $dev_ref->[2] == $partition) {
                $dev = $dev_ref->[0];
                $self->milestone("Translated $original to $dev");
                $finded = 1;;
            }
        }
        if (defined $finded){
            return $dev;
        }
        #no partition found so return $dev with partition
        $self->warning("No partition found for $dev with $partition.");
        return $dev.$partition;
    }

    $dev = $self->Member2MD ($dev);
    $self->milestone("Translated GRUB2->UNIX: $original to $dev");
    return $dev;
}

# Pattern for grub device specification. Please note that this does not work
# with BSD labeled disks which use things like "hd0,b"
# The pattern matches disk or floppy or network or cd
my $grubdev_pattern = "(?:hd\\d+(?:,\\d+)?|fd\\d+|nd|cd)";

sub GrubCfgSections {
    my ($parent, $cfg, $sect) = @_;
    my @m = $cfg =~ /(submenu|menuentry) \s+ '([^']*)' (.*?) ( \{ (?: [^{}]++ | (?-1))*+ \} )/sxg;

    for (my $i = 0; $i <= $#m; $i += 4) {

        my $type  = $m[$i];
        my $title = $m[$i+1];
        my $args  = $m[$i+2];
        my $cfg2  = $m[$i+3];
        my $name  = ($parent) ? "$parent>$title" : "$title";

        if ($type eq "menuentry") {
            my %sect_info;

            $sect_info{"name"} = $name;
            $sect_info{"menuentry"} = $name;

            if ($args =~ m/'gnulinux-[^\s]+-recovery-[^\s]+'/) {
                $sect_info{"usage"} = "linux_failsafe";
            } else {
                $sect_info{"usage"} = "linux";
            }

            if ($args =~ m/--class xen/) {

                $sect_info{"type"} = "xen";

                if ($cfg2 =~ /^\s+multiboot\s+(\S+)\s+\S+\s*(.*)$/m) {
                    $sect_info{"xen"} = $1;
                    $sect_info{"xen_append"} = $2;
                } 

                while ($cfg2 =~ /^\s+module\s+(\S+)\s+\S+\s*(.*)$/gm) {

                    if (!exists $sect_info{"image"}) {

                        my $append = $2;
                        $sect_info{"image"} = $1;

                        if ($append =~ /root=/) {
                            $append =~ s/root=(\S+)\s*//;
                            $sect_info{"root"} = $1;
                        }

                        if ($append =~ /vga=/) {
                            $append =~ s/vga=(\S+)\s*//;
                            $sect_info{"vgamode"} = $1;
                        }

                        $sect_info{"append"} = $append;

                    } elsif (!exists $sect_info{"initrd"}) {
                        $sect_info{"initrd"} = $1;
                    }
                }

            } else {

                $sect_info{"type"} = "image";

                if ($cfg2 =~ /^\s+linux\s+(\S+)\s*(.*)$/m) {
                    my $append = $2;
                    $sect_info{"image"} = $1;

                    if ($append =~ /root=/) {
                        $append =~ s/root=(\S+)\s*//;
                        $sect_info{"root"} = $1;
                    }

                    if ($append =~ /vga=/) {
                        $append =~ s/vga=(\S+)\s*//;
                        $sect_info{"vgamode"} = $1;
                    }

                    $sect_info{"append"} = $append;
                }
                if ($cfg2 =~ /^\s+initrd\s+(\S+)\s*$/m) {
                    $sect_info{"initrd"} = $1;
                }
            }

            push @{$sect}, \%sect_info;
        } elsif ($type eq "submenu") {
            &GrubCfgSections ($name, $cfg2, $sect);
        }
    }
}

=item
C<< $obj_ref = Bootloader::Core::GRUB2->new (); >>

Creates an instance of the Bootloader::Core::GRUB2 class.

=cut

sub new
{
    my $self = shift;
    my $ref = shift;
    my $old = shift;
    my $arch = `uname --hardware-platform`;
    chomp $arch;
    my $target;

    my $loader = $self->SUPER::new($ref, $old);
    bless($loader);

    # Set target based on architecture (ppc or x86)
    $target = "i386-pc" if $arch =~ /(i386|x86_64)/;
    $target = "powerpc-ieee1275" if $arch =~ /(ppc|ppc64)/;
    $target = "s390x-emu" if $arch eq 's390x';
    $loader->{target} = $target;

    $loader->milestone("Created GRUB2 instance for target \"$target\" (arch = $arch)");

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
    return [ Bootloader::Path::Grub2_installdevice(),
        Bootloader::Path::Grub2_defaultconf(),
        Bootloader::Path::Grub2_conf(),
        Bootloader::Path::Grub2_devicemap()
    ];
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

    $self->GetDeviceMap () if (! $avoid_reading_device_map);

    # and now proceed with /etc/default/grub
    my @defaultconf = @{$files{Bootloader::Path::Grub2_defaultconf()} || []};
    $self->milestone("input from default conf :\n'" .
                     join("'\n' ", @defaultconf) . "'");

    # prefix commented config with '@' instread of '#'
    # this is to new notation for "commented config" and
    # need to process saparately
    foreach my $conf (@defaultconf) {
        if ($conf =~ m/^\s*#\s*GRUB_/) {
            $conf =~ s/^\s*#\s*/@/;
        }
    }

    (my $glob_ref, my $sect_ref) = $self->ParseMenuFileLines (
        "=",
        [],
        \@defaultconf
    );

    my @devices = @{$files{Bootloader::Path::Grub2_installdevice()} || []};

    if (not exists $self->{"mountpoints"}{'/'})
    {
        $self->milestone("Mount points doesn't have '/', skipped parsing grub2 config");
    }
    elsif (scalar (@devices) == 0)
    {
        $self->warning("No device configured, skip parsing boot device");
    } else {
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
            $self->milestone("checking boot device $dev");

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

            if ($dev =~ /^\(${grubdev_pattern}\)$/) {
                $dev = $self->GrubDev2UnixDev($dev);
            } else {
                $dev = $self->GetKernelDevice($dev);
            }

            if ($dev eq $mbr_dev) {
                $glob_ref->{"boot_mbr"} = "true";
                $self->milestone("detected boot_mbr");
                if (defined $self->{"md_arrays"}
                    and ((scalar keys %{$self->{"md_arrays"}}) > 0)){
                    if (defined $glob_ref->{"boot_md_mbr"}
                        and $glob_ref->{"boot_md_mbr"} ne "" ){
                        $glob_ref->{"boot_md_mbr"} = $glob_ref->{"boot_md_mbr"}.",".$dev;
                    } else {
                        $glob_ref->{"boot_md_mbr"} =$dev;
                    }
                    $self->milestone("detected boot_md_mbr ".$glob_ref->{"boot_md_mbr"});
                }
            }
            elsif ($dev eq $root_dev) {
                $glob_ref->{"boot_root"} = "true";
                $self->milestone("detected boot_root");
            }
            elsif ($dev eq $boot_dev) {
                $glob_ref->{"boot_boot"} = "true";
                $self->milestone("detected boot_boot");
            }
            elsif ($dev eq $extended_dev) {
                $glob_ref->{"boot_extended"} = "true";
                $self->milestone("detected boot_extended");
            }
            elsif ($self->IsDisc($dev)
                   and defined $self->{"md_arrays"}
                   and ((scalar keys %{$self->{"md_arrays"}}) > 0)){
                if (defined $glob_ref->{"boot_md_mbr"} and $glob_ref->{"boot_md_mbr"} ne "" ){
                    $glob_ref->{"boot_md_mbr"} = $glob_ref->{"boot_md_mbr"}.",".$dev;
                } else {
                    $glob_ref->{"boot_md_mbr"} =$dev;
                }
                $self->milestone("detected boot_md_mbr ".$glob_ref->{"boot_md_mbr"});
            }
            else {
                $glob_ref->{"boot_custom"} = $dev;
                $self->milestone("set boot_custom");
            }
        }
    }

    my @entries;

    my $cfg = $self->ReadFileUnicode(Bootloader::Path::Grub2_conf());
    if ($cfg) {
        &GrubCfgSections ("", $cfg, \@entries);
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

    $self->milestone("found s1_devices: " . join(",",keys %s1_devices));

    if (scalar (keys (%s1_devices)) > 0)
    {
        foreach my $new_dev (keys (%s1_devices))
        {
            while ((my $udev_dev, my $kern_dev) = each %{$self->{"udevmap"}}) {
                if ($udev_dev =~ /\/by-id\// and $kern_dev eq $new_dev) {
                    $self->milestone("Translating install device from $new_dev to $udev_dev");
                    $new_dev = $udev_dev;
                    last;
                }
            }

            if ($new_dev ne "") {
                push @grub2_installdev, $new_dev;
            }
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

    # now process the device map
    my %glob = %{$self->{"global"}};
    my @device_map = ();
    while ((my $unix, my $fw) = each (%{$self->{"device_map"}}))
    {
        # this doesn't matters, as floppy device is specified
        # by os device now
        if ($fw =~ m/^fd[0-9]+$/) {
            $self->milestone ("skip floppy device for writing device.map");
            next;
        }

        my $line = "($fw)\t$unix";
        push @device_map, $line;
    }
    return {
        Bootloader::Path::Grub2_installdevice() => $grub2_installdev,
        Bootloader::Path::Grub2_defaultconf() => $grub2_defaultconf,
        Bootloader::Path::Grub2_devicemap() => \@device_map,
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
            # GRUB_TERMINAL is a space separated list of terminal devices to use
            if ($val =~ m/^(\b(serial|console|gfxterm)\b|\s+)*$/) {
                $ret{"terminal"} = $val;
            }
        } elsif ($key =~ m/@?GRUB_SERIAL_COMMAND/) {
            $ret{"serial"} = $val;
        } elsif ($key =~ m/@?GRUB_GFXMODE/) {
            $ret{"gfxmode"} = $val;
        } elsif ($key =~ m/@?GRUB_THEME/) {
            $ret{"gfxtheme"} = $val;
        } elsif ($key =~ m/@?GRUB_DISTRIBUTOR/) {
            $ret{"distributor"} = $val;
        } elsif ($key =~ m/@?GRUB_DISABLE_RECOVERY/) {
            $ret{"failsafe_disabled"} = $val;
        } elsif ($key =~ m/@?GRUB_CMDLINE_LINUX_RECOVERY$/) {
            $ret{"append_failsafe"} = $val;
        } elsif ($key =~ m/@?GRUB_BACKGROUND/) {
            $ret{"gfxbackground"} = $val;
        } elsif ($key =~ m/@?GRUB_DISABLE_OS_PROBER$/) {
            $ret{"os_prober"} = ($val eq "true") ? "false" : "true";
        } elsif ($key =~ m/@?GRUB_CMDLINE_XEN_DEFAULT$/) {
            $ret{"xen_append"} = $val; 
        } elsif ($key =~ m/@?GRUB_CMDLINE_LINUX_XEN_REPLACE_DEFAULT$/) {
            $ret{"xen_kernel_append"} = $val; 
        } elsif ($key =~ m/@?SUSE_BTRFS_SNAPSHOT_BOOTING$/) {
            $ret{"suse_btrfs"} = $val;
        } elsif ($key =~ m/@?GRUB_ENABLE_CRYPTODISK$/) {
            $ret{"cryptodisk"} = $val eq 'y' ? 1 : 0;
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
                'value' => '""',
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
                'key' => 'GRUB_CMDLINE_LINUX_RECOVERY',
                'value' => 'single',
                'comment_before' => [
                  '# kernel command line options for failsafe mode',
                ],
            },
            {
                'key' => 'GRUB_CMDLINE_LINUX',
                'value' =>  '""',
            },
            {
                'key' => '@GRUB_BADRAM',
                'value' => '0x01234567,0xfefefefe,0x89abcdef,0xefefefef',
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
                'value' => 'auto',
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
                'key' => '@GRUB_DISABLE_RECOVERY',
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
            {
                'key' => 'GRUB_DISABLE_OS_PROBER',
                'value' => 'false',
                'comment_before' => [
                  '# Skip 30_os-prober if you experienced very slow in probing them',
                  '# WARNING foregin OS menu entries will be lost if set true here'
                ],
            },
            {
                'key' => 'GRUB_ENABLE_CRYPTODISK',
                'value' => 'n',
                'comment_before' => [
                  "# Set to 'y' for grub to be installed on an encrypted partition"
                ],
            },
        );

    }

    # We don't need to set root= as grub2-mkconfig
    # already detect that for us ..
    # my $root = delete $globinfo{"root"} || "";
    my $vga = delete $globinfo{"vgamode"} || "";
    my $append = delete $globinfo{"append"} || "";
    my $xen_append = delete $globinfo{"xen_append"} || "";
    my $xen_kernel_append = delete $globinfo{"xen_kernel_append"} || "";
    # YaST doesn't save bootloader settings when 'Timeout in seconds' is set to 0 (bnc#804176)
    my $timeout = delete $globinfo{"timeout"} || 0;
    my $hiddenmenu = delete $globinfo{"hiddenmenu"} || "";
    my $terminal = delete $globinfo{"terminal"} || "";
    my $serial = delete $globinfo{"serial"} || "";
    my $gfxmode = delete $globinfo{"gfxmode"} || "";
    my $gfxtheme = delete $globinfo{"gfxtheme"} || "";
    my $gfxbackground = delete $globinfo{"gfxbackground"} || "";
    my $distributor = delete $globinfo{"distributor"};
    # handle empty default distributor
    $distributor = '""' if $distributor eq "";
    my $failsafe_disabled = delete $globinfo{"failsafe_disabled"} || "";
    my $append_failsafe = delete $globinfo{"append_failsafe"} || "";
    my $os_prober = delete $globinfo{"os_prober"} || "";
    my $suse_btrfs = delete $globinfo{"suse_btrfs"} || "true";
    my $cryptodisk = delete $globinfo{"cryptodisk"} || 0;
    # $root = " root=$root" if $root ne "";
    $vga = " vga=$vga" if $vga ne "";

    $self->milestone("XXX append = $append");
    $append =~ s/rootflags=subvol\S*\s*//;

    $cryptodisk = $self->CryptoNeeded() unless $cryptodisk;

    my $hidden_timeout = "$timeout";
    if ("$hiddenmenu" eq "true") {
        $timeout = "0" if "$timeout" ne "";
    } else {
        $hidden_timeout = "0" if "$hidden_timeout" ne "";
    }

    # bnc#862614 - serial console settings not propagated into xen entry
    if ($append =~ /console=ttyS(\d+),(\w+)/)
    {
        # merge console and speed into xen_append
        my $console = sprintf("com%d", $1+1);
        my $speed   = sprintf("%s=%s", $console, $2);

        if ($xen_append  ne "") {
            while ($xen_append =~ s/(.*)console=(\S+)\s*(.*)$/$1$3/) {
                my $del_console = $2;
                $xen_append =~ s/(.*)${del_console}=\w+\s*(.*)$/$1$2/g;
            }
            $xen_append = "console=$console $speed $xen_append";
        } else {
            $xen_append = "console=$console $speed";
	    }

        $xen_kernel_append = $append if ($xen_kernel_append eq "");
        $xen_kernel_append =~ s/console=ttyS(\S+)\s*//g;
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
        } elsif ($key =~ m/@?GRUB_THEME/) {
            if ($gfxtheme ne "") {
                $line_ref->{"key"} = "GRUB_THEME";
                $line_ref->{"value"} = $gfxtheme;
            } else {
                $line_ref = undef;
            }
            $gfxtheme = "";
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
        } elsif ($key =~ m/@?GRUB_DISTRIBUTOR/) {
            $line_ref->{"value"} = $distributor;
            $distributor = undef;
        } elsif ($key =~ m/@?GRUB_DISABLE_RECOVERY$/) {
            if ("$failsafe_disabled" ne "") {
              # uncomment option
              $line_ref->{"key"} = "GRUB_DISABLE_RECOVERY";
              $line_ref->{"value"} = "$failsafe_disabled";
              $failsafe_disabled = "";
            }
        } elsif ($key =~ m/@?GRUB_CMDLINE_LINUX_RECOVERY$/) {
            $line_ref->{"value"} = "$append_failsafe" if "$append_failsafe" ne "";
            $append_failsafe = "";
        } elsif ($key =~ m/@?GRUB_BACKGROUND/) {
            if ($gfxbackground ne "") {
                $line_ref->{"key"} = "GRUB_BACKGROUND";
                $line_ref->{"value"} = $gfxbackground;
            } else {
                # delete the line once the value unset
                $line_ref = undef;
            }
            $gfxbackground = "";
        } elsif ($key =~ m/@?GRUB_DISABLE_OS_PROBER$/) {
            $line_ref->{"value"} = ($os_prober eq "false") ? "true" : "false";
            $os_prober = "";
        } elsif ($key =~ m/@?GRUB_CMDLINE_XEN_DEFAULT$/) {
            $line_ref->{"value"} = $xen_append if $xen_append ne "";
            $xen_append = "";
        } elsif ($key =~ m/@?GRUB_CMDLINE_LINUX_XEN_REPLACE_DEFAULT$/) {
            $line_ref->{"value"} = $xen_kernel_append if $xen_kernel_append ne "";
            $xen_kernel_append = "";
        } elsif ($key =~ m/@?SUSE_BTRFS_SNAPSHOT_BOOTING$/) {
            $line_ref->{"value"} = $suse_btrfs if $suse_btrfs ne "";
            $suse_btrfs = "";
        } elsif ($key =~ m/@?GRUB_ENABLE_CRYPTODISK$/) {
            $line_ref->{value} = $cryptodisk ? 'y' : 'n' if defined $cryptodisk;
            undef $cryptodisk;
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

    if ($gfxtheme ne "") {
        push @lines, {
            "key" => "GRUB_THEME",
            "value" => "$gfxtheme",
        }
    }

    if (defined($distributor)) {
        push @lines, {
            "key" => "GRUB_DISTRIBUTOR",
            "value" => $distributor,
        }
    }

    if ("$failsafe_disabled" ne "") {
        push @lines, {
            "key" => "GRUB_DISABLE_RECOVERY",
            "value" => "$failsafe_disabled",
        }
    }

    if ("$append_failsafe" ne "") {
        push @lines, {
            "key" => "GRUB_CMDLINE_LINUX_RECOVERY",
            "value" => "$append_failsafe",
        }
    }

    if ($gfxbackground ne "") {
        push @lines, {
            "key" => "GRUB_BACKGROUND",
            "value" => "$gfxbackground",
        }
    }

    if ("$os_prober" ne "") {
        push @lines, {
            "key" => "GRUB_DISABLE_OS_PROBER",
            "value" => ($os_prober eq "false") ? "true" : "false",
        }
    }

    if ($xen_append ne "") {
        push @lines, {
            "key" => "GRUB_CMDLINE_XEN_DEFAULT",
            "value" => $xen_append,
        }
    }

    if ($xen_kernel_append ne "") {
        push @lines, {
            "key" => "GRUB_CMDLINE_LINUX_XEN_REPLACE_DEFAULT",
            "value" => $xen_kernel_append,
        }
    }

    if ($suse_btrfs ne "") {
        push @lines, {
            "key" => "SUSE_BTRFS_SNAPSHOT_BOOTING",
            "value" => $suse_btrfs,
        }
    }

    if (defined $cryptodisk) {
        push @lines, {
            "key" => "GRUB_ENABLE_CRYPTODISK",
            "value" => $cryptodisk ? 'y' : 'n',
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

    if (! -e "/usr/bin/grub2-editenv") {
        $self->warning ("file not exist /usr/bin/grub2-editenv");
        return $ret;
    }

    my $saved_entry = `/usr/bin/grub2-editenv list|sed -n '/^saved_entry=/s/.*=//p'`;

    chomp $saved_entry;
    $saved_entry =~ s/\s+$//;
    if ($saved_entry eq "") {
        $saved_entry = "0";
    }
    if ($saved_entry =~ m/^\d+$/) {
        my $sect = $sections->[$saved_entry];

        if (defined $sect) {
            $globals->{"default"} = $sect->{"menuentry"};
        }
    } else {
        $globals->{"default"} = $saved_entry;
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
    my %glob = %{$self->{"global"}};

    # backup the config file
    # it really did nothing for now
    my $ret = $self->SUPER::UpdateBootloader ();
    return undef unless defined $ret;

    if (! $avoid_init)
    {
        return $self->InitializeBootloader ();
    }

    my $default  = delete $glob{"default"};

    if (defined $default and $default ne "") {
        $self->RunCommand (
            "/usr/sbin/grub2-set-default '$default'"
        );
    }

    return 0 == $self->RunCommand (
        "/usr/sbin/grub2-mkconfig -o /boot/grub2/grub.cfg"
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
    my $files_ref;

    # some targets might need an install device list
    if($self->{target} !~ /(-emu|-efi)$/) {
      $files_ref = $self->ReadFiles([$file,]);
    }

    $self->milestone("files_ref", $files_ref);

    if ($files_ref->{$file})
    {
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

        $self->milestone("devices =", \@devices);

        foreach my $dev (@devices) {

            my $cmd = "/usr/sbin/grub2-install";
            my $opt = "--target=$self->{'target'} $install_opts \"$dev\"";

            if ($dev eq "activate" or $dev eq "generic_mbr") {
                next;
            }

            my $ret = $self->RunCommand ("$cmd $opt");

            return 0 if (0 != $ret);
        }
    }
    else {
        my $ret = $self->RunCommand (
            "/usr/sbin/grub2-install --target=$self->{'target'}"
        );

        return 0 if $ret;
    }

    my $default  = delete $glob{"default"};

    if (defined $default and $default ne "") {
        $self->RunCommand (
            "/usr/sbin/grub2-set-default '$default'"
        );
    }

    return 0 ==  $self->RunCommand (
        "/usr/sbin/grub2-mkconfig -o /boot/grub2/grub.cfg"
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
