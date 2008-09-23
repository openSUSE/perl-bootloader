#! /usr/bin/perl -w
#
# Bootloader configuration base library
#

=head1 NAME

Bootloader::Core::PowerLILO - LILO library for bootloader configuration on POWER


=head1 PREFACE

This package is the LILO library of the bootloader configuration on POWER

=head1 SYNOPSIS

use Bootloader::Core::PowerLILO;

C<< $obj_ref = Bootloader::Core::PowerLILO->new (); >>

C<< $files_ref = Bootloader::Core::PowerLILO->ListFiles (); >>

C<< $status = Bootloader::Core::PowerLILO->ParseLines (\%files, $avoid_reading_device_map); >>

C<< $files_ref = Bootloader::Core::PowerLILO->CreateLines (); >>

C<< $status = Bootloader::Core::PowerLILO->UpdateBootloader ($avoid_init); >>

C<< $status = Bootloader::Core::PowerLILO->InitializeBootloader (); >>

=head1 DESCRIPTION

=over 2

=cut


package Bootloader::Core::PowerLILO;

use strict;

use Bootloader::Core;

our @ISA = qw(Bootloader::Core);

use Bootloader::Path;

#module interface

sub GetMetaData() {
    my $loader = shift;

    # possible global entries:
    #
    #	boot (might be more than one)
    #	clone
    #	activate
    #	force_fat
    #	force
    #	progressbar (deprecated, check yaboot)
    #	bootfolder
    #	timeout
    #	macos_timeout
    #	default
    #	append
    #	initrd
    #
    #
    # per section entries
    #	image
    #   optional
    #	other
    #	root
    #	copy
    #	label
    #	append
    #	sysmap (deprecated, yaboot))
    #   	initrd

    # FIXME: add help texts for all widgets

    my %exports;

    # one of iseries, prep, chrp, pmac_old, pmac_new ...
    my $lilo = Bootloader::Path::Lilo_lilo();
    my $arch = qx{ $lilo --get-arch };
    chomp( $arch );
    $arch = "pmac" if "$arch" =~ /^pmac/;

    my @bootpart;
    my @partinfo = @{$loader->{"partitions"} || []};

    # Partitioninfo is a list of list references of the format:
    #   Device,   disk,    nr, fsid, fstype,   part_type, start_cyl, size_cyl
    #   /dev/sda9 /dev/sda 9   258   Apple_HFS `primary   0          18237
    #
    if ( "$arch" eq "chrp" ) {
	# boot from any primary partition with PReP or FAT partition id
	@bootpart = map {
	    my ($device, $disk, $nr, $fsid, $fstype,
		$part_type, $start_cyl, $size_cyl) = @$_;
	    ($part_type eq "`primary" and
	     ($fsid eq "6" or $fsid eq "12" or $fsid eq "65"))
		? $device : ();
	} @partinfo;
    }
    elsif ( "$arch" eq "iseries" ) {
	# boot from any primary PReP partition on a virtual disk
	@bootpart = map {
	    my ($device, $disk, $nr, $fsid, $fstype,
		$part_type, $start_cyl, $size_cyl) = @$_;
	    ($part_type eq "`primary" and
	     $fsid eq "65" and
	     $device =~ m:^/dev/iseries/:)
		? $device : ();
	} @partinfo;
    }
    elsif ( "$arch" eq "pmac" ) {
	# boot from any Apple_HFS partition but dont take the big ones
	@bootpart = map {
	    my ($device, $disk, $nr, $fsid, $fstype,
		$part_type, $start_cyl, $size_cyl) = @$_;
	    (($fstype eq "Apple_HFS" or
	      $fstype eq "Apple_Bootstrap")
	     and $size_cyl < 20)
		? $device : ();
	} @partinfo;
    }
    elsif ( "$arch" eq "prep" ) {
	# boot from any primary PReP partition
	@bootpart = map {
	    my ($device, $disk, $nr, $fsid, $fstype,
		$part_type, $start_cyl, $size_cyl) = @$_;
	    ($fsid eq "65" and
	     $part_type eq "`primary")
		? $device : ();
	} @partinfo;
    }

    # unknown architecture, or no match, give no valid selection
    @bootpart = ("- no valid boot partition -") unless @bootpart;

    my $boot_partitions = join(":", @bootpart);

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
    );

    $exports{"arch"} = $arch;
    $exports{"global_options"} = {
 	# for iseries list for others exactly one allowed
	boot     => ( "$arch" eq "iseries" )
		 ?  "multi:iSeries boot image location:"
		 :  "select:PPC Boot loader location:",
	activate => "bool:Change boot-device in NV-RAM:true",
	timeout  => "int:Timeout in 1/10th seconds:50:0:600",
	default  => "string:Default boot section:Linux",
	root     => "selectdevice:Default root device::" . ":" . $root_devices,
	append   => "string:Append options for kernel command line",
	initrd   => "path:Default initrd path"			  
	};

    my $go = $exports{"global_options"};
    
    if ( "$arch" eq "chrp" ) {
	# pSeries only
	$go->{clone}       = "selectdevice:Partition for boot loader duplication::" . ":" . $boot_partitions;
	$go->{force_fat}   = "bool:Always boot from FAT partition:false";
	$go->{force}       = "bool:Install boot loader even on errors:false";

	$go->{boot_chrp_custom}
			   = "select:PReP or FAT partition::" . $boot_partitions;
    }
    elsif ( "$arch" eq "prep" ) {
	# only on old prep machines
	$go->{bootfolder}  = "string:Bootfolder path";
	$go->{boot_prep_custom}
			   = "selectdevice:PReP partition::" . $boot_partitions;
    }
    elsif ( "$arch" eq "iseries" ) {
	# only on legacy iseries
	$go->{boot_slot}   = "select:Write to boot slot:B:" . "A:B:C:D";
	$go->{boot_file}   = "path:Create boot image in file:/tmp/suse_boot_image";
	$go->{boot_iseries_custom}
			   = "selectdevice:PReP partition::" . $boot_partitions;
    }
    elsif ( "$arch" eq "pmac" ) {
	# only on pmac_new and pmac_old
	$go->{bootfolder}  = "string:Bootfolder path:";
	$go->{boot_pmac_custom}
			   = "select:HFS boot partition::" . $boot_partitions;
 	$go->{no_os_chooser} = "bool:Do not use os-chooser:false";
	$go->{macos_timeout} = "int:Timeout in seconds for MacOS/Linux selection:5:0:60",
   }

    $exports{"section_options"} = {
	type_image        => "bool:Kernel section",
	image_image       => "path:Kernel image:/boot/vmlinux",
	image_root        => "select:Root device::" . $root_devices,
	# image_label     => "string:Name of section", # implicit
	image_append      => "string:Optional kernel command line parameter",
	image_initrd      => "path:Initial RAM disk:/boot/initrd",
	image_optional    => "bool:Skip section gracefully on errors:true",
	};

    my $so = $exports{"section_options"};

    if ( "$arch" eq "pmac" ) {
	# only on pmac_new and pmac_old
	$so->{image_copy}  = "bool:Copy image to boot partition:false";

	# define new section type for MacOS boot
	$so->{type_other}  = "bool:Boot other system";
	# $so{other_label} = "string:Name of section" # implicit!
	$so->{other_other} = "select:Boot partition of other system::" . join
	    (":",
	     # boot from any Apple_HFS partition but _only_ take the big ones
	     map {
		 my ($device, $disk, $nr, $fsid, $fstype,
		     $part_type, $start_cyl, $size_cyl) = @$_;
		 ($fstype eq "Apple_HFS" and $size_cyl >= 20)
		     ? $device : ();
	     } @partinfo
	     );
    }

    $loader->{"exports"}=\%exports;
    return \%exports;
}


=item
C<< $obj_ref = Bootloader::Core::PowerLILO->new (); >>

Creates an instance of the Bootloader::Core::PowerLILO class.

=cut

sub new {
    my $self = shift;
    my $old = shift;

    my $loader = $self->SUPER::new ($old);
    $loader->{"default_global_lines"} = [
	{ key => "activate", value => "" },
    ];
    bless ($loader);

    $loader->GetMetaData();
    $loader->l_milestone ("PowerLILO::new: Created PowerLILO instance");
    return $loader;
}


=item
C<< $settings_ref = Bootloader::Core::PowerLILO->GetSettings (); >>

returns the complete settings in a hash. Does not read the settings
from the system, but returns internal structures.

=cut

# map<string,any> GetSettings ()
sub GetSettings {
    my $self = shift;

    return $self->SUPER::GetSettings();
}

=item
C<< $files_ref = Bootloader::Core::PowerLILO->ListFiles (); >>

Returns the list of the configuration files of the bootloader
Returns undef on fail

=cut

# list<string> ListFiles ();
sub ListFiles {
    my $self = shift;

    return [ Bootloader::Path::Lilo_conf() ];
}

# FIXME document

sub FixSectionName {
    my $self = shift;
    my $name = shift;
    my $names_ref = shift;

    my $orig_name = $name;

    # replace unwanted characters by underscore, normally all printables
    # beside space equal sign and quote signs should be ok, no length limit
    $name =~ s/[^\w.-]/_/g;

    # and make the section name unique
    $name = $self->SUPER::FixSectionName($name, $names_ref, $orig_name);

    return $name;
}


=item
C<< $status = Bootloader::Core::PowerLILO->ParseLines (\%files, $avoid_reading_device_map); >>

Parses the contents of all files and stores the settings in the
internal structures. As first argument, it takes a hash reference, where
keys are file names and values are references to lists, each member is
one line of the file. As second argument, it takes a boolean flag
that, if set to a true value, causes it to skip updating the
internal device_map information. The latter argument is not used
for PowerLILO. Returns undef on fail, defined nonzero value on
success.

=cut

# void ParseLines (map<string,list<string>>, boolean)
sub ParseLines {
    my $self = shift;
    my %files = %{+shift};
    my $avoid_reading_device_map = shift;

    # the only file is /etc/lilo.conf
    my @lilo_conf = @{$files{Bootloader::Path::Lilo_conf()} || []};
    (my $glob_ref, my $sect_ref) = $self->ParseMenuFileLines (
	"=",
	["image", "other"],
	\@lilo_conf
    );

    $self->{"sections"} = $sect_ref;
    $self->{"global"} = $glob_ref;
    return 1;
}


=item
C<< $files_ref = Bootloader::Core::PowerLILO->CreateLines (); >>

creates contents of all files from the internal structures.
Returns a hash reference in the same format as argument of
ParseLines on success, or undef on fail.

=cut

# map<string,list<string>> CreateLines ()
sub CreateLines {
    my $self = shift;

    if ($self->{"global"}{"__modified"} || 0)
    {
	# FIXME: this looks as completely useless to me
	my @lines = @{$self->{"global"}{"__lines"} || []};
	my @out_lines = ();
	foreach my $line_ref (@lines) {
	    push @out_lines, $line_ref;
	}
	$self->{"global"}{"__lines"} = \@out_lines;
    }

    # create /etc/lilo.conf lines
    my $lilo_conf = $self->PrepareMenuFileLines (
	$self->{"sections"},
	$self->{"global"},
	"    ",
	" = "
    );
    return undef unless defined ($lilo_conf);

    return {
	Bootloader::Path::Lilo_conf() => $lilo_conf,
    }
}


# give me the unique internal boot= label for this special value
sub boot2special($$) {
    my $val = shift;
    my $arch = shift;

    if ($val =~ /^[ABCD]$/) {
	return "boot_slot";
    }
    elsif ($val =~ m:^/dev/:) {
	return "boot_" . $arch . "_custom";
	
    }
    elsif ($val =~ m:^/:) {
	return "boot_file";
	
    }
    
    # bummer, should never happen
    # ignore wrong entry
    return undef;
}


=item
C<< $glob_info = $Bootloader::Core->Global2Info (\@glob_lines, \@section_names); >>

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
    my $arch = $self->{"exports"}{"arch"};

    my %ret = ();

    foreach my $line_ref (@lines) {
	my $key = $line_ref->{"key"};
	my $val = $line_ref->{"value"};
	my ($type) = split /:/, $go->{$key};

	if ($key eq "boot")
	{
	    $key = boot2special($val, $arch);
	    $ret{$key} = $val if defined $key;
	}
	elsif ($type eq "bool") {
	    $ret{$key} = "true";
	}
	else {
	    $ret{$key} = $val;
	}
    }
    $ret{"__lines"} = \@lines;
    return \%ret;
}

=item
C<< $lines_ref = Bootloader::Core->Info2Global (\%section_info, \@section_names); >>

Takes the info about the global options and uses it to construct the list of lines.
The info about global option also contains the original lines.
As parameter, takes the section info (reference to a hash) and a list of sectino names,
returns the lines (a list of hashes).

=cut

# list<map<string,any>> Info2Global (map<string,string> info, list<string>sections)
sub Info2Global {
    my $self = shift;
    my %globinfo = %{+shift};
    my @sections = @{+shift};

    my @lines = @{$globinfo{"__lines"} || []};
    my @lines_new = ();
    my $go = $self->{"exports"}{"global_options"};
    my $arch = $self->{"exports"}{"arch"};

    # allow to keep the section unchanged
    return \@lines unless $globinfo{"__modified"} || 0;

    if (scalar (@lines) == 0)
    {
	@lines = @{$self->{"default_global_lines"} || []};
    }

    foreach my $line_ref (@lines) {
	my $key = $line_ref->{"key"};

	# only accept known global options :-)
	next unless exists $go->{$key};

	if ($key eq "boot"){
	    my $special = boot2special($line_ref->{"value"}, $arch);

	    if ( exists ($globinfo{$special}) ) {
		if ( defined ($globinfo{$special})) {
		    $line_ref->{"value"} = $globinfo{$special};
		}		
		delete $globinfo{$special};
	    }
	}
	else {
	    if (defined ($globinfo{$key})) {
		$line_ref->{"value"} = delete $globinfo{$key};
	    }
	    else {
		next;
	    }
	}

	my ($type) = split /:/, $go->{$key};
	# bool values appear in a config file or not. there might be types
	# like 'yesno' or 'truefalse' in the future which behave differently
	if ($type eq "bool") {
	    next if $line_ref->{"value"} ne "true";
	    $line_ref->{"value"} = "";
	}

	push @lines_new, $line_ref if defined $line_ref;
    };

    @lines = @lines_new;


    while ((my $key, my $value) = each (%globinfo)) {
	# only accept known global options :-)
	next unless exists $go->{$key};
	#next if $key =~ /^__/;

	if ($key eq "boot_" . $arch . "_custom") {
		push @lines, {
		    "key" => "boot",
		    "value" => $value,
		}
	}
	elsif ($key eq "boot_slot") {
		push @lines, {
		    "key" => "boot",
		    "value" => $value,
		}
	}
	elsif ($key eq "boot_file") {
		push @lines, {
		    "key" => "boot",
		    "value" => $value,
		}
	}
	else {
	    my ($type) = split /:/, $go->{$key};
	    # bool values appear in a config file or not
	    if ($type eq "bool") {
		next if $value ne "true";
		$value = "";
	    }

	    push @lines, {
		"key" => $key,
		"value" => $value,
	    };
	}
    }
    return \@lines;
}


=item
C<< $lines_ref = Bootloader::Core->Info2Section (\%section_info, \@section_names); >>

Takes the info about the section and uses it to construct the list of lines.
The info about the section also contains the original lines.
As parameter, takes the section info (reference to a hash), returns
the lines (a list of hashes).
=cut

# list<map<string,any>> Info2Section (map<string,string> info, list<string> section_names)
sub Info2Section {
    my $self = shift;
    my %sectinfo = %{+shift};
    my $sect_names_ref = shift;

    my @lines = @{$sectinfo{"__lines"} || []};
    my $type = $sectinfo{"type"} || "";
    my $so = $self->{"exports"}{"section_options"};
    my @lines_new = ();

    # allow to keep the section unchanged
    if (! ($sectinfo{"__modified"} || 0))
    {
	return $self->FixSectionLineOrder (
	    \@lines,
	    ["image", "other"]);
    }

    $sectinfo{"name"} = $self->FixSectionName ($sectinfo{"name"}, $sect_names_ref);

    foreach my $line_ref (@lines) {
	my $key = $line_ref->{"key"};

	if ($key eq "label")
	{
	    $line_ref = $self->UpdateSectionNameLine ($sectinfo{"name"}, $line_ref,
						      $sectinfo{"original_name"});
	    delete ($sectinfo{"name"});
	}
	elsif (!exists $so->{$type . "_" . $key}) {
	    # only accept known section options :-)
	    next; 
	}
	else
	{
	    next unless defined ($sectinfo{$key});

	    $line_ref->{"value"} = $sectinfo{$key};
	    delete ($sectinfo{$key});
	    my ($stype) = split /:/, $so->{$type . "_" . $key};
	    # bool values appear in a config file or not
	    if ($stype eq "bool") {
	        next if $line_ref->{"value"} ne "true";
	        $line_ref->{"value"} = "";
	    }
	}

	push @lines_new, $line_ref if defined $line_ref;
    }

    @lines = @lines_new;


    my $create_append = 1;
    while ((my $key, my $value) = each (%sectinfo))
    {
	if ($key eq "name")
	{
	    my $line_ref = $self->UpdateSectionNameLine ($sectinfo{"name"}, {},
							 $sectinfo{"original_name"});
	    $line_ref->{"key"} = "label";
	    push @lines, $line_ref;
	}
        elsif ( $key eq "append" || $key eq "console" )
        {
          if (defined($create_append))
          {
            my $append = $sectinfo{"append"} || "";
            my $console = $sectinfo{"console"} || "";
            push @lines, {
                "key" => "append",
                "value" => $append.$console,
            };
            $create_append = undef;
          }
        }
	elsif (! exists ($so->{$type . "_" . $key}))
	{
	    # only accept known section options :-)
	    next;
	}
	else
	{
	    my ($stype) = split /:/, $so->{$type . "_" . $key};
	    # bool values appear in a config file or not
	    if ($stype eq "bool") {
		next if $value ne "true";
		$value = "";
	    }

	    push @lines, {
		"key" => $key,
		"value" => $value,
	    };
	}
    }

    my $ret = $self->FixSectionLineOrder (\@lines,
	["image", "other"]);

    return $ret;
}


=item
C<< $sectin_info_ref = Bootloader::Core->Section2Info (\@section_lines); >>

Gets the information about the section. As argument, takes a reference to the
list of lines building the section, returns a reference to a hash containing
information about the section.

=cut

# map<string,string> Section2Info (list<map<string,any>> section)
sub Section2Info {
    my $self = shift;
    my @lines = @{+shift};

    my %ret = ();

    foreach my $line_ref (@lines) {
	my $key = $line_ref->{"key"};
	if ($key eq "label")
	{
	    my $on = $self->Comment2OriginalName ($line_ref->{"comment_before"});
	    $ret{"original_name"} = $on if ($on ne "");
	    $key="name";
	}
	elsif ($key eq "image" or $key eq "other")
	{
	    $ret{"type"} = $key;
	}
        elsif ($key eq "append")
        {
          my $val = $line_ref->{"value"};
          if ($val =~ /^(?:(.*)\s+)?console=ttyS(\d+),(\w+)(?:\s+(.*))?$/)
          {
            $ret{"console"} = "ttyS$2,$3" if $2 ne "";
            $val = $self->MergeIfDefined( $1, $4);
          }
          $ret{"append"} = $val if $val ne "";
          next;
        }
        my ($stype) = undef;
        if (defined $ret{"type"})
        {
          ($stype) = split /:/, $self->{"exports"}{"section_options"}->{$ret{"type"} . "_" . $key} || ""; 
        }
	# bool values appear in a config file or not
	if (defined $stype and $stype eq "bool")
        {
	  $ret{$key} = "true";
	}
        else
        {
          $ret{$key} = $line_ref->{"value"};
        }
    }
    $ret{"__lines"} = \@lines;
    return \%ret;
}


=item
C<< $status = Bootloader::Core::PowerLILO->UpdateBootloader ($avoid_init); >>

Updates the settings in the system. Backs original configuration files
up and replaces them with the ones with the '.new' suffix. Also performs
operations needed to make the change effect (run '/sbin/lilo').
Returns undef on fail, defined nonzero value on success.

=cut

# boolean UpdateBootloader (boolean avoid_init)
sub UpdateBootloader {
    my $self = shift;
    my $avoid_init = shift;

    my $ret = $self->SUPER::UpdateBootloader ();
    return undef unless defined ($ret);

    unless ($avoid_init) {
	$ret = $self->InitializeBootloader ();
    }

    return $ret;
}

=item
C<< $status = Bootloader::Core::PowerLILO->InitializeBootloader (); >>

Initializes the firmware to boot the bootloader.
Returns undef on fail, defined nonzero value otherwise

=cut

# boolean InitializeBootloader ()
sub InitializeBootloader {
    my $self = shift;

    my $lilo = Bootloader::Path::Lilo_lilo();
    return 0 == $self->RunCommand (
	"$lilo",
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
