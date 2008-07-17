#! /usr/bin/perl -w
#
# Bootloader configuration base library
#

=head1 NAME

Bootloader::Core::ELILO - ELILO library for bootloader configuration


=head1 PREFACE

This package is the ELILO library of the bootloader configuration

=head1 SYNOPSIS

use Bootloader::Core::ELILO;

C<< $obj_ref = Bootloader::Core::ELILO->new (); >>

C<< $files_ref = Bootloader::Core::ELILO->ListFiles (); >>

C<< $status = Bootloader::Core::ELILO->ParseLines (\%files, $avoid_reading_device_map); >>

C<< $files_ref = Bootloader::Core::ELILO->CreateLines (); >>

C<< $status = Bootloader::Core::ELILO->UpdateBootloader (); >>

C<< $status = Bootloader::Core::ELILO->InitializeBootloader (); >>

=head1 DESCRIPTION

=over 2

=cut


package Bootloader::Core::ELILO;

use strict;

use Bootloader::Core;
our @ISA = ('Bootloader::Core');
use Bootloader::Path;

#module interface


sub GetMetaData() {
    my $loader = shift;
   
    # Options or entries respectively have types. Four types are defined:
    #
    # 	- boolean:           set or not set
    # 	- string:            a string of characters which can be quoted if necessary
    # 	- number:            a decimal number
    # 	- filename:          a string interpreted as a filename
    #
    # 	
    # The config file (/etc/elilo.conf) supports the following options:
    # 
    # Global options
    # --------------
    #
    #     default=value       Name the default image to boot. If not defined ELILO
    #                         will boot the first defined image.
    #     timeout=number      The number of 10th of seconds to wait while in
    #                         interactive mode before auto booting default kernel.
    #                         Default is infinity.
    #     delay=number        The number of 10th of seconds to wait before
    #                         auto booting when not in interactive mode. 
    #                         Default is 0.
    #     prompt              Force interactive mode
    #     verbose=number      Set level of verbosity [0-5]. Default 0 (no verbose)
    #     root=filename       Set global root filesystem for Linux/ia64
    #     read-only           Force root filesystem to be mounted read-only
    #     append=string       Append a string of options to kernel command line
    #     initrd=filename     Name of initrd file
    #     image=filename      Define a new image
    #     chooser=name        Specify kernel chooser to use: 'simple' or 'textmenu'.
    #     message=filename    a message that is printed on the main screen if 
    #                         supported by the chooser.
    #     fX=filename         Some choosers may take advantage of this option to
    #                         display the content of a file when a certain function
    #                         key X is pressed. X can vary from 1-12 to cover 
    #                         function keys F1 to F12.
    #     noedd30             do not force the EDD30 EFI variable to TRUE when FALSE. 
    #                         In other words, don't force the EDD30 mode if not set.
    #
    #
    # Possible section types
    # ----------------------
    # 
    #     image
    #
    #
    # Image (section) options
    # -----------------------
    # 
    #     root=filename       Set root filesystem for kernel
    #     read-only           Force root filesystem to be mounted read-only
    #     append=string       Append a string of options to kernel command line
    #     initrd=filename     Name of initrd file
    #     label=string        Logical name of image (used in interactive mode)
    #     description=string  One line text description of the image.
    #
    #
    # IA-64 specific global options
    # -----------------------------
    #
    #     fpswa=file          Specify the filename for a specific FPSWA to load
    #                         If this option is used no other file will be tried.
    #     relocatable         In case of memory allocation error at initial
    #                         load point of kernel, allow attempt to relocate 
    #                         (assume kernels are relocatable).
    #
    # IA-64 specific image options
    # ----------------------------
    #
    #     relocatable         In case of memory allocation error at initial
    #                         load point of kernel, allow attempt to relocate 
    #                         (assume this kernel is relocatable).
    #
    #
    # IA-32 specific options
    # ----------------------
    #
    #     legacy-free         Indicate that the host machine does not have a
    #                         legacy BIOS at all.
    #                         


    my %exports;
    
    my @bootpart;
    my @partinfo = @{$loader->{"partitions"} || []};
    
    # FIXME: boot from any partition (really?)
    @bootpart = map {
        my ($device, $disk, $nr, $fsid, $fstype, $part_type, $start_cyl, $size_cyl) = @$_;
        $device;
    } @partinfo;
    
    my $boot_partitions = join(":", @bootpart);
    
    my @md_arrays = keys %{$loader->{"md_arrays"} || {}};
    my $root_devices = join(":",
        map {
            my ($device, $disk, $nr, $fsid, $fstype, $part_type, $start_cyl, $size_cyl) = @$_;
            # FIXME: weed out non-root partitions
        } @partinfo,
	\@md_arrays
    );
    
    # FIXME: is "arch" export necessary?

    # FIXME: Add quotation marks around all keys (like key "read-only")

    $exports{"global_options"} = {
	default		=> "string:Default Boot Section:Linux",
	timeout		=> "int:Timeout in 10th of Seconds:80:0:36000",
	delay		=> "int:Delay to wait before Auto Booting in 10th of Seconds:0",
	prompt		=> "bool:Show Boot Menu",
	verbose		=> "int:Set Level of Verbosity [0-5]:0",
	root		=> "path:Set global Root Filesystem:/",
	"read-only"	=> "bool:Force rootfs to be mounted read-only",
	append		=> "string:Append String of Options to Kernel Command Line:",
	initrd		=> "path:Name of initrd File:/boot/initrd",
	image		=> "path:Name of image File:/boot/vmlinuz",
	chooser		=> "string:Specify Kernel Chooser to use:textmenu",
	message		=> "string:Message printed on Main Screen (if supported):",
	fX		=> "path:Display the Content of a File by Function Keys:",
	noedd30		=> "bool:Don't force EDD30 Mode if not set:",
	fpswa		=> "path:Specify the Filename for a specific FPSWA to load:",
	relocatable	=> "bool:Allow Attempt to relocate:",

	# shadow entries for efi boot manager
	boot_efilabel	=> "string:EFI Boot Manager Label::",
	#boot_rm_efilabel => "bool:Remove existing EFI Boot Manager Entries by Name:",
    };

    my $go = $exports{"global_options"};
    
    $exports{"section_options"} = {
        type_image         => "bool:Image Section",
	image_append       => "string:Optional Kernel Command Line Parameter",
	image_description  => "string:One Line Text Description of the Image:",
	image_image        => "path:Kernel Image:/boot/vmlinux",
	image_initrd       => "path:Initial RAM Disk:/boot/initrd",
	image_noverifyroot => "bool:Do not verify Filesystem before Booting:false",
	image_readonly	   => "bool:Force Root Filesystem to be mounted read-only:",
	image_relocatable  => "bool:Allow Attempt to relocate:",
	image_root	   => "selectdevice:Root Device::" . $root_devices,
    };

    my $so = $exports{"section_options"};

    $loader->{"exports"}=\%exports;
    return \%exports;
}


=item
C<< $obj_ref = Bootloader::Core::ELILO->new (); >>

Creates an instance of the Bootloader::Core::ELILO class.

=cut

sub new {
    my $self = shift;
    my $old = shift;

    my $loader = $self->SUPER::new ($old);
    $loader->{"default_global_lines"} = [
	{ "key" => "timeout", "value" => 80 },
	{ "key" => "relocatable", "value" => "" },
    ];
    bless ($loader);

    $loader->GetMetaData();
    $loader->l_milestone ("ELILO::new: Created ELILO instance");
    return $loader;
}

=item
C<< $files_ref = Bootloader::Core::ELILO->ListFiles (); >>

Returns the list of the configuration files of the bootloader
Returns undef on fail

=cut

my $default_conf = Bootloader::Path::Elilo_conf();

# list<string> ListFiles ();
sub ListFiles {
    my $self = shift;

    return [ $default_conf ];
}


=item
C<< $status = Bootloader::Core::ELILO->FixSectionName ($name, \$names_ref); >>

=cut

# FIXME: complete the docu
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
C<< $status = Bootloader::Core::ELILO->ParseLines (\%files, $avoid_reading_device_map); >>

Parses the contents of all files and stores the settings in the
internal structures. As first argument, it takes a hash reference,
where keys are file names and values are references to lists, each
member is one line of the file. As second argument, it takes a
boolean flag that, if set to a true value, causes it to skip
updating the internal device_map information. The latter argument
is not used for ELILO. Returns undef on fail, defined nonzero
value on success.

=cut

# void ParseLines (map<string,list<string>>, boolean)
sub ParseLines {
    my $self = shift;
    my %files = %{+shift};
    my $avoid_reading_device_map = shift;

    # the only file is /etc/elilo.conf
    my @elilo_conf = @{$files{$default_conf} || []};
    (my $glob_ref, my $sect_ref) = $self->ParseMenuFileLines (
	"=",
	["image"],
	\@elilo_conf
    );

    # handle global append information 
    my $glob_app = undef;
    my $flag = 0;
    foreach my $opt_ref (@{$glob_ref->{"__lines"}|| []})
    {
        my $key = $opt_ref->{"key"};
        my $val = $opt_ref->{"value"};
        if ($key eq "append")
        {
           $flag = 1;
           $glob_app = $val;
#          print STDERR "\nGLOBAL APPEND: $glob_app \n\n"; 
        }
    }
#   if(! $flag) {
#     print STDERR "\nNO GLOBAL APPEND!\n\n";
#   } 


    # handle section append information
    foreach my $sect_ref (@{$sect_ref} ) {
        my $sect_app = undef;
        my $sect_title = undef;
        foreach my $opt_ref (@{$sect_ref->{"__lines"}|| []})
        {
          my $key = $opt_ref->{"key"};
          my $val = $opt_ref->{"value"};
          if($key eq "label") {
            $sect_title = $val;
#            print STDERR "label name: $val\n";
          }
          if ($key eq "append") {
            $sect_app = $val;
          }
        }
        if( defined $sect_app ) {
#          print STDERR "SECTION $sect_title has APPEND: $sect_app \n";
	} else {
#          print STDERR "SECTION $sect_title has NO APPEND!\n";
        }
     }

    $self->{"sections"} = $sect_ref;
    $self->{"global"} = $glob_ref;

    return 1;

}


=item
C<< $line = Bootloader::Core::ELILO->CreateSingleMenuFileLine ($key, $value, $separator); >>

Transforms a line (hash) to a string to save. As arguments it takes the the key, the
value and a string to separate the key and the value. Returns a string.

=cut

# string CreateSingleMenuFileLine (string key, string value, string separator)
sub CreateSingleMenuFileLine {
    my $self = shift;
    my $key = shift;
    my $value = shift;
    my $equal_sep = shift;

    my $line = "$key";
    if (! $self->HasEmptyValue ($key, $value))
    {
	# I like this crappy elilo thing
	if ($key eq "append") {
	    $value = $self->Quote ($value, "always");
	} else {
	    $value = $self->Quote ($value, "blanks");
	}
	$line = "$line$equal_sep$value";
    }
    return $line;
}


=item
C<< $files_ref = Bootloader::Core::ELILO->CreateLines (); >>

creates contents of all files from the internal structures.
Returns a hash reference in the same format as argument of
ParseLines on success, or undef on fail.

=cut

# map<string,list<string>> CreateLines ()
sub CreateLines {
    my $self = shift;

    # FIXME: think this is unnecessary code, no one else needs it, please check
    if ($self->{"global"}{"__modified"} || 0) {
	my @lines = @{$self->{"global"}{"__lines"} || []};
	my @out_lines = ();
	foreach my $line_ref (@lines) {
	    push @out_lines, $line_ref;
	}
	$self->{"global"}{"__lines"} = \@out_lines;
    }

    # create /etc/elilo.conf lines
    my $elilo_conf = $self->PrepareMenuFileLines (
	$self->{"sections"},
	$self->{"global"},
	"    ",
	" = "
    );

    return undef unless defined $elilo_conf;

    # handle 'hidden magic' entries
    map {
	s/^/##YaST - / if /^boot_efilabel/;
	    #if /^boot_efilabel/ or /^boot_rm_efilabel/;
    } @{$elilo_conf};

    return {
	$default_conf => $elilo_conf,
    }
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

    # FIXME: Do we need the arch stuff???
    #my $arch = $self->{"exports"}{"arch"};

    my %ret = ();

    foreach my $line_ref (@lines) {
	my $key = $line_ref->{"key"};
	my $val = $line_ref->{"value"};
	my ($type) = split /:/, $go->{$key};

	#if ($key eq "boot")
	#{
	#    $key = boot2special($val, $arch);
	#    $ret{$key} = $val if defined $key;
	#}
	#elsif ($type eq "bool") {
	if ($type eq "bool") {
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
As parameter, takes the section info (reference to a hash) and a list of section names,
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

    # FIXME: Do we need the arch stuff???
    #my $arch = $self->{"exports"}{"arch"};

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

	#if ($key eq "boot"){
	#    my $special = boot2special($line_ref->{"value"}, $arch);
	#
	#    if ( exists ($globinfo{$special}) ) {
	#	if ( defined ($globinfo{$special})) {
	#	    $line_ref->{"value"} = $globinfo{$special};
	#	}		
	#	delete $globinfo{$special};
	#    }
	#}
	#else {
	    if (defined ($globinfo{$key})) {
		$line_ref->{"value"} = delete $globinfo{$key};
	    }
	    else {
		next;
	    }
	#}

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

	if ($key eq "boot_slot") {
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
	    $self->l_milestone (
		"ELILO::Info2Section: Ignoring key '$key' for section type '$type'");
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


    while ((my $key, my $value) = each (%sectinfo))
    {
	if ($key eq "name")
	{
	    my $line_ref = $self->UpdateSectionNameLine ($sectinfo{"name"}, {},
							 $sectinfo{"original_name"});
	    $line_ref->{"key"} = "label";
	    push @lines, $line_ref;
	}
	elsif (! exists ($so->{$type . "_" . $key}))
	{
	    # only accept known section options :-)
	    $self->l_milestone (
		"ELILO::Info2Section: Ignoring key '$key' for section type '$type'");
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
    my $so = $self->{"exports"}{"section_options"};

    my %ret = ();

    foreach my $line_ref (@lines) {
	my $key = $line_ref->{"key"};
	my $val = $line_ref->{"value"};

	if ($key eq "label")
	{
	    my $on = $self->Comment2OriginalName ($line_ref->{"comment_before"});
	    $ret{"original_name"} = $on if ($on ne "");
	    $ret{"name"} = $val;
	    next;
	}
	elsif ($key eq "image" or $key eq "other")
	{
	    $ret{"type"} = $key;
	}

	unless (exists $ret{"type"} && exists $so->{$ret{"type"} . "_" . $key}) {
	    # only accept known section options :-)
	    $self->l_milestone (
		"ELILO::Section2Info: Ignoring key '$key' for section"
		. " type '" . $ret{"type"} . "'");
	    next; 
	}
	
	my ($type) = split /:/, $so->{$ret{"type"} . "_" . $key};
	if ($type eq "bool") {
	    $val = "true";
	}
	$ret{$key} = $val;
    }
    $ret{"__lines"} = \@lines;
    return \%ret;
}



=item
C<< $status = Bootloader::Core::ELILO->UpdateBootloader (); >>

Updates the settings in the system. Backs original configuration files
up and replaces them with the ones with the '.new' suffix. Also performs
operations needed to make the change effect (run '/sbin/elilo').
Returns undef on fail, defined nonzero value on success.

=cut

# boolean UpdateBootloader ()
sub UpdateBootloader {
    my $self = shift;

    my $ret = $self->SUPER::UpdateBootloader ();
    return undef unless defined $ret;

    # FIXME: this is good-weather programming: /boot/efi is _always_ a
    #        FAT partition which has to be mounted
    my $efi = Bootloader::Path::Elilo_efi();
    system ("mkdir -p $efi") unless -d "$efi";
 
    my $elilo = Bootloader::Path::Elilo_elilo(); 
    return 0 == $self->RunCommand (
	"$elilo -v",
	"/var/log/YaST2/y2log_bootloader"
    );
}

=item
C<< $status = Bootloader::Core::ELILO->InitializeBootloader (); >>

Initializes the firmware to boot the bootloader.
Returns undef on fail, defined nonzero value otherwise

=cut

# boolean InitializeBootloader ()
sub InitializeBootloader {
    my $self = shift;

    # FIXME run EFI boot manager
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
