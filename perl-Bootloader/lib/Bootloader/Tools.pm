#!/usr/bin/perl -w
#
# Set of high-level bootloader configuration functions
#

=head1 NAME

Bootloader::Tools - set of high-level bootloader configuration functions


=head1 PREFACE

This package contains a set of high-level bootloader configuration functions

=head1 SYNOPSIS

C<< use BootTool; >>

C<< $mp_ref = BootTool::ReadMountPoints (); >>

C<< $part_ref = BootTool::ReadPartitions (); >>

C<< $md_ref = BootTool::ReadMDArrays (); >>

C<< $loader = BootTool::GetBootloader (); >>

C<< BootTool::InitLibrary (); >>

C<< BootTool::AddNewImageSection ($name, $image, $initrd, $default); >>

C<< BootTool::CountImageSections ($image); >>

C<< BootTool::RemoveImageSections ($image); >>

=head1 DESCRIPTION

=over 2

=cut


package Bootloader::Tools;

use strict;
use base 'Exporter';

our @EXPORT = qw(InitLibrary AddNewImageSection CountImageSections
		 RemoveImageSections);

use Bootloader::Library;
use Bootloader::Core;

my $lib_ref = undef;

sub DumpLog {
    foreach my $rec (@{$lib_ref->GetLogRecords ()})
    {
	my $message = $rec->{"message"};
	my $level = $rec->{"level"};
	if ($level eq "debug")
	{
#	    print STDERR ("DEBUG: $message\n");
	}
	elsif ($level eq "milestone")
	{
#	    print STDERR ("MILESTONE: $message\n");
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
C<< $mp_ref = BootTool::ReadMountPoints (); >>

reads the information about mountpoints in the system. The returned
data is needed to initialize the bootloader library properly.

See InitLibrary function for example.

=cut

sub ReadMountPoints {
    open (FILE, "/etc/fstab") || die ("Failed to open /etc/fstab");
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
		    open (BLKID, "/sbin/blkid -t $dev |") || die ("Failed to run blkid");
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

    open (OUT, "udevinfo -q name -p /block/$udev |") || die "Cannot run udevinfo";
    my $dev = <OUT>;
    close OUT;
    chomp ($dev);
    return "/dev/$dev";
}

=item
C<< $part_ref = BootTool::ReadPartitions (); >>

reads the information about disk partitions. This data is needed
to initialize the bootloader library properly.

See InitLibrary function for example.

=cut
sub ReadPartitions {
    opendir(BLOCK_DEVICES, "/sys/block") || die ("Failed to open dir /sys/block");
    my @disks = grep {
	! ($_ =~ /^md/ || $_ =~ /^dm-/ || $_ =~ /^fd/ || $_ =~ /^loop/ || $_ =~ /^ram/ || $_ =~ /^\./)
    } readdir(BLOCK_DEVICES);
    closedir BLOCK_DEVICES;

    my @devices = ();
    foreach my $disk (@disks)
    {
	my $dev_disk = Udev2Dev ($disk);
	opendir(BLOCK_DEVICES, "/sys/block/$disk") || die ("Failed to open dir /sys/block/$disk");
	my @parts = grep {
	    ! ($_ =~ /^dev/ || $_ =~ /^queue$/ || $_ =~ /^range/ || $_ =~ /^removable/
		|| $_ =~ /^size/ || $_ =~ /^stat/ || $_ =~ /^\./)

	} readdir (BLOCK_DEVICES);
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
    return \@devices;
}

=item
C<< $md_ref = BootTool::ReadMDArrays (); >>

reads the information about disk MD RAID arrays. This data is needed
to initialize the bootloader library properly.

=cut

sub ReadMDArrays {
    my $index = 0;
    my %mapping = ();
    while ($index < 32)
    {
	my @members = ();
	open (MD, "/sbin/mdadm -Q --detail /dev/md$index 2>/dev/null |") || die ("Failed getting information about MD arrays");
	while (my $line = <MD>)
	{
	    chomp ($line);
	    if ($line =~ /[-0-9]+[ \t]+[-0-9]+[ \t]+[-0-9]+[ \t]+([-0-9]+)[ \t]+.*[ \t]+([^ \t]+)$/)
	    {
		my $dev = $2;
		my $raid_dev = $1;
		if ($raid_dev =~ /^[0-9]+$/ && $raid_dev >= 0)
		{
		    push @members, $dev;
		}
	    }
	}
	close (MD);
	if (scalar (@members))
	{
	    $mapping{"/dev/md$index"} = \@members;
	}
	$index = $index + 1;
    }
    return \%mapping;
}

=item
C<< $loader = BootTool::GetBootloader (); >>

returns the used bootloader. Reads the value from sysconfig.
Returns the string - bootloader type.

See InitLibrary function for example.

=cut

sub GetBootloader {
    open (FILE, ". /etc/sysconfig/bootloader && echo \$LOADER_TYPE |")
	|| die "Cannot determine the loader type";
    my $lt = <FILE>;
    close (FILE);
    chomp ($lt);
    return $lt;
}   

=item
C<< BootTool::InitLibrary (); >>

initializes the bootloader configuration library. Fills its internal structures
needed for it to run properly.

=cut

sub InitLibrary {
    $lib_ref = Bootloader::Library->new ();
    my $mp = ReadMountPoints ();
    my $part = ReadPartitions ();
    my $md = ReadMDArrays ();

    $lib_ref->Initialize (GetBootloader ());
    $lib_ref->DefineMountPoints ($mp);
    $lib_ref->DefinePartitions ($part);
    $lib_ref->DefineMDArrays ($md);
    DumpLog ();
}

=item
C<< BootTool::AddNewImageSection ($name, $image, $initrd, $default); >>

Adds a new section to the bootloader menu via one function call (just the
library needs to be initialized before). C<$initrd> and C<$default> are
optional, if C<$default> is defined and nonzero, the new section is marked
as default.

EXAMPLE:

  BootTool::InitLibrary ();
  BootTool::AddNewImageSection ("2.6.11", "/boot/vmlinuz-2.6.11", "/boot/initrd-2.6.11", 1);

=cut

sub AddNewImageSection {
    my $name = shift;
    my $image = shift;
    my $initrd = shift;
    my $default = shift;

    $lib_ref->ReadSettings ();
    my $mp = $lib_ref->GetMountPoints ();
    my @sections = @{$lib_ref->GetSections ()};
    my %new = (
	"append" => "splash=silent",
	"root" => $mp->{"/"} || "/dev/null",
    );
    my %def = ();
    foreach my $s (@sections)
    {
	if (defined ($s->{"initial"}) && $s->{"initial"})
	{
	    %def = %{$s};
	    last;
	}
    }

    while ((my $k, my $v) = each (%def))
    {
	if (substr ($k, 0, 2) ne "__" && $k ne "original_name"
	    && $k ne "initrd")
	{
	    $new{$k} = $v;
	}
    }

    $new{"kernel"} = $image;
    $new{"initrd"} = $initrd if defined ($initrd);
    $new{"name"} = $name;
    $new{"type"} = "image";
    $new{"__modified"} = 1;
    unshift @sections, \%new;

    $lib_ref->SetSections (\@sections);
    my $glob_ref = $lib_ref->GetGlobalSettings ();
    if (defined ($default) && $default)
    {
	$glob_ref->{"default"} = $name;
    }
    $glob_ref->{"__modified"} = 1; # needed because of GRUB - index of default
				   # may change
    $lib_ref->SetGlobalSettings ($glob_ref);

    $lib_ref->WriteSettings (1);
    $lib_ref->UpdateBootloader ();
    DumpLog ();
}


=item
C<< BootTool::CountImageSections ($image); >>

counts sections in the bootolader menu reffering to the
specified kernel.

EXAMPLE:

  BootTool::InitLibrary ();
  my $count = BootTool::CountImageSections ("/boot/vmlinuz-2.6.11");
  print "Sections: $count\n";

=cut

sub CountImageSections {
    my $image = shift;

    $image = ResolveCrossDeviceSymlinks ($image);
    $lib_ref->ReadSettings ();
    my @sections = @{$lib_ref->GetSections ()};
    @sections = grep {
	(ResolveCrossDeviceSymlinks ($_->{"kernel"} || "")) eq $image;
    } @sections;
    my $count = scalar (@sections);
    DumpLog ();
    return $count;
}


=item
C<< BootTool::RemoveImageSections ($image); >>

removes all sections in the bootloader menu referring to the
specified kernel.

EXAMPLE:

  BootTool::InitLibrary ();
  BootTool::RemoveImageSections ("/boot/vmlinuz-2.6.11");

=cut

sub RemoveImageSections {
    my $image = shift;

    $image = ResolveCrossDeviceSymlinks ($image);
    $lib_ref->ReadSettings ();

    my @sections = @{$lib_ref->GetSections ()};
    my $glob_ref = $lib_ref->GetGlobalSettings ();
    my $default_section = $glob_ref->{"default"} || "";
    my $default_removed = 0;

    @sections = grep {
	if ((ResolveCrossDeviceSymlinks ($_->{"kernel"} || "")) eq $image) {
	    if ($default_section eq $_->{"name"})
	    {
		$default_removed = 1;
	    }
	    0;
	} else {
	    1;
	}
    } @sections;
    $lib_ref->SetSections (\@sections);
    if ($default_removed)
    {
	$glob_ref->{"default"} = $sections[0]{"name"};
    }
    $glob_ref->{"__modified"} = 1; # needed because of GRUB - index of default
				   # may change
    $lib_ref->SetGlobalSettings ($glob_ref);
    $lib_ref->WriteSettings (1);
    $lib_ref->UpdateBootloader ();
    DumpLog ();
}

1;
