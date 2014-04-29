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

sub GetOptions{
  my $loader = shift;

  my $arch = $loader->{"arch"};

  my %exports;
    $exports{"global"} = {
	default		=> "",
	timeout		=> "",
	delay		=> "",
	prompt		=> "bool",
	verbose		=> "",
	root		=> "",
	"read-only"	=> "bool",
	append		=> "",
	initrd		=> "",
	image		=> "",
	chooser		=> "",
	message		=> "",
	fX		=> "",
	noedd30		=> "bool",
	fpswa		=> "",

	# shadow entries for efi boot manager
	boot_efilabel	=> "",
	#boot_rm_efilabel => "bool:Remove existing EFI Boot Manager Entries by Name:",
    };

    if ($arch eq "ia64") {
      $exports{"global_options"}{"relocatable"} = "bool";
    }

    $exports{"section"} = {
        type_image         => "",
	image_append       => "",
	image_description  => "",
	image_image        => "",
	image_initrd       => "",
	image_noverifyroot => "bool",
	"image_read-only"  => "bool",
	image_root	   => "",

	type_xen          => "",
	xen_xen => "",
	xen_xen_append    => "",
	xen_image         => "",
	xen_root          => "",
	xen_append        => "",
	xen_initrd        => "",
    };
    if ($arch eq "ia64") {
      $exports{"section_options"}{"image_relocatable"} = "bool";
    }

    $loader->{"options"}=\%exports;
}

=item
C<< $obj_ref = Bootloader::Core::ELILO->new (); >>

Creates an instance of the Bootloader::Core::ELILO class.
First argumetn is old configuration and second is architecture string like x86_64 or ia64

=cut

sub new
{
  my $self = shift;
  my $ref = shift;
  my $old = shift;
  my $arch = shift;

  my $loader = $self->SUPER::new($ref, $old);
  bless($loader);

  $loader->{default_global_lines} = [
    { key => "timeout", value => 80 },
  ];

  if($arch eq "ia64") {
    my $line = { key => "relocatable",  value => "" };
    push @{$loader->{default_global_lines}}, $line;
  }

  $loader->{arch} = $arch;
  $loader->GetOptions();

  $loader->milestone ("Created ELILO instance");

  return $loader;
}

=item
C<< $files_ref = Bootloader::Core::ELILO->ListFiles (); >>

Returns the list of the configuration files of the bootloader
Returns undef on fail

=cut


# list<string> ListFiles ();
sub ListFiles {
    my $self = shift;

    return [ Bootloader::Path::Elilo_conf() ];
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
    my @elilo_conf = @{$files{Bootloader::Path::Elilo_conf()} || []};
    (my $glob_ref, my $sect_ref) = $self->ParseMenuFileLines (
	"=",
	["image"],
	\@elilo_conf
    );

    foreach my $opt_ref (@{$glob_ref->{"__lines"}|| []})
    {
        my $key = $opt_ref->{"key"};
        my $val = $opt_ref->{"value"};
        if ($key eq "append")
        {
           $self->milestone("GLOBAL APPEND: $val \n"); 
        }
    }


    # handle section append information
    foreach my $sect_ref (@{$sect_ref} ) {
        foreach my $opt_ref (@{$sect_ref->{"__lines"}|| []})
        {
          my $key = $opt_ref->{"key"};
          my $val = $opt_ref->{"value"};
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
	Bootloader::Path::Elilo_conf() => $elilo_conf,
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
    my $go = $self->{"options"}{"global"};

    my %ret = ();

    foreach my $line_ref (@lines) {
	my $key = $line_ref->{"key"};
	my $val = $line_ref->{"value"};
	my $type = $go->{$key};

        $val = int($val/10) if ($key eq "timeout");

	if (defined $type && $type eq "bool") {
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
    my $go = $self->{"options"}{"global"};
    $globinfo{"default"} = $sections[0]->{"name"} unless (defined $globinfo{"default"});
    $globinfo{"default"} = $self->FixSectionName($globinfo{"default"},[]);

    # allow to keep the section unchanged
    return \@lines unless $globinfo{"__modified"} || 0;

    if (scalar (@lines) == 0)
    {
	@lines = @{$self->{"default_global_lines"} || []};
    }

    foreach my $line_ref (@lines) {
	my $key = $line_ref->{"key"};

	# only accept known global options :-)
	unless (exists $go->{$key})
        {
	    $self->milestone("Ignoring key '$key' for global section");
            next;
        }

        if (defined ($globinfo{$key})) {
            $line_ref->{"value"} = delete $globinfo{$key};
            $line_ref->{"value"} = $line_ref->{"value"}*10 if ($key eq "timeout");
	}else {
	    next;
	}

	my $type = $go->{$key};
	# bool values appear in a config file or not. there might be types
	# like 'yesno' or 'truefalse' in the future which behave differently
	if ($type eq "bool") {
	    next if $line_ref->{"value"} ne "true";
	    $line_ref->{"value"} = "";
	}

	push @lines_new, $line_ref;
    };

    @lines = @lines_new;


    while ((my $key, my $value) = each (%globinfo)) {
	# only accept known global options :-)
	next unless exists $go->{$key};
        $value = $value*10 if ($key eq "timeout");

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
    my $so = $self->{"options"}{"section"};
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
        $key = "xen" if ($key eq "vmm"); #standartize xen key

	if ($key eq "label")
	{
	    $line_ref = $self->UpdateSectionNameLine ($sectinfo{"name"}, $line_ref,
						      $sectinfo{"original_name"});
	    delete ($sectinfo{"name"});
	}
	elsif (!exists $so->{$type . "_" . $key}) {
	    # only accept known section options :-)
	    $self->milestone("Ignoring key '$key' for section type '$type'");
	    next; 
	}
        #append in xen contains also xen append, so it must handled special
        elsif ($key eq "append") 
        {
          my $first = $sectinfo{"xen_append"} || "";
          $first = "vga=mode-".(delete $sectinfo{"vgamode"})." $first" if (defined $sectinfo{'vgamode'} && $sectinfo{"vgamode"} ne "");
          my $second = $sectinfo{"append"} || "";  
          my $console = $sectinfo{"console"} || "";
          $console = "console=$console" if ($console ne "");
          my $value = "$second $console";
          $value = "$first -- $value" if ($type eq "xen");
          $value = $self->trim($value);
          $line_ref->{"value"} = $value;
          delete $sectinfo{"xen_append"};
          delete $sectinfo{"append"};
          delete $sectinfo{"console"};
        }
	else
	{
	    next unless defined ($sectinfo{$key});

	    $line_ref->{"value"} = $sectinfo{$key};
	    delete ($sectinfo{$key});
	    my $stype = $so->{$type . "_" . $key};
	    # bool values appear in a config file or not
	    if ($stype eq "bool") {
	        next if $line_ref->{"value"} ne "true";
	        $line_ref->{"value"} = "";
	    }
	}

        #FIXME is if needed?
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
        elsif ( $key eq "append" || $key eq "console" || $key eq "xen_append"  || $key eq "vgamode")
        {
          if (defined($create_append))
          {
            my $append = $sectinfo{"append"} || "";
            my $console = $sectinfo{"console"} || "";
            $console = "console=$console" if ($console ne "");
            my $val = "$append $console";
            if ($type eq "xen")
            {
              my $xen_append = $sectinfo{"xen_append"} || "";
              my $vga = "";
              $vga="vga=mode-".$sectinfo{"vgamode"}." " if (defined $sectinfo{"vgamode"} && $sectinfo{"vgamode"} ne "");
              $val = "$vga$xen_append -- $val";
            }
            push @lines, {
	        "key" => "append",
	        "value" => $val,
	    };
            $create_append = undef;
          }
        }
        elsif ($key eq "xen" and $type eq "xen")
        {
            push @lines, {
	        "key" => "vmm",
	        "value" => $value,
	    };
        }
	elsif (! exists ($so->{$type . "_" . $key}))
	{
	    # only accept known section options :-)
	    $self->milestone("Ignoring key '$key' for section type '$type'");
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
    my $so = $self->{"options"}{"section"};

    my %ret = ();

    foreach my $line_ref (@lines) {
	my $key = $line_ref->{"key"};
	my $val = $line_ref->{"value"};

	if ($key eq "label")
	{
	    my $on = $self->Comment2OriginalName (\%ret,$line_ref->{"comment_before"});
	    $ret{"original_name"} = $on if ($on ne "");
	    $ret{"name"} = $val;
	    next;
	}
	elsif ($key eq "image" or $key eq "other")
	{
	    $ret{"type"} = $key;
	}
        elsif ($key eq "vmm")
        {
            $ret{"type"} = "xen";
            $ret{"xen"} = $val;
            next;
        }
        elsif ($key eq "append")
        {
           if ($val =~ /^(?:(.*)\s+)?console=ttyS(\d+),(\w+)(?:\s+(.*))?$/)
           {
              $ret{"console"} = "ttyS$2,$3" if $2 ne "";
              $val = $self->MergeIfDefined( $1, $4);
           }
           if ($val =~ m/--/) #value contains separator between hypervisor and host
           {
             $val =~ m/(.*)--(.*)/;
             my $xen_app = $1;
             my $host_app = $2;             
             if ($xen_app =~ m/(.*)vga=mode-(\S+)\s*(.*)/)
             {
               $ret{"vgamode"} = $2;
               $xen_app = $self->MergeIfDefined($1,$3)
             }
             $ret{"xen_append"} = $self->trim($xen_app);
             $ret{"append"} = $self->trim($host_app);
           }
           else
           {
             $ret{"append"} = $val;
           }
           next;
        }

	unless (exists $ret{"type"} && exists $so->{$ret{"type"} . "_" . $key}) {
	    # only accept known section options :-)
	    $self->milestone("Ignoring key '$key' for section" . " type '" . $ret{"type"} . "'");
	    next; 
	}
	
	my ($type) = $so->{$ret{"type"} . "_" . $key};
	if ($type eq "bool")
        {
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
 
    return 0 == $self->RunCommand (
	Bootloader::Path::Elilo_elilo() . " -v"
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
