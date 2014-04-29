#! /usr/bin/perl -w
#
# Bootloader configuration base library
#

=head1 NAME

Bootloader::Core::ZIPL - ZIPL library for bootloader configuration


=head1 PREFACE

This package is the ZIPL library of the bootloader configuration

=head1 SYNOPSIS

use Bootloader::Core::ZIPL;



C<< $obj_ref = Bootloader::Core::ZIPL->new (); >>

C<< $settings_ref = Bootloader::Core::ZIPL->GetSettings (); >>

C<< $files_ref = Bootloader::Core::ZIPL->ListFiles (); >>

C<< $status = Bootloader::Core::ZIPL->FixSectionName ($name, \$names_ref, $type); >>

C<< $status = Bootloader::Core::ZIPL->ParseLines (\%files, $avoid_reading_device_map); >>

C<< $sections_ref Bootloader::Core->SplitLinesToSections (\@lines, \@section_starts); >>

C<< $files_ref = Bootloader::Core::ZIPL->CreateLines (); >>

C<< $status = Bootloader::Core::ZIPL->UpdateBootloader ($avoid_init); >>

C<< $status = Bootloader::Core::ZIPL->InitializeBootloader (); >>

C<< $lines_ref = Bootloader::Core::ZIPL->Info2Section (\%section_info, \@sect_names); >>

C<< $sectin_info_ref = Bootloader::Core::ZIPL->Section2Info (\@section_lines); >>

C<< $glob_info = $Bootloader::Core::ZIPL->Global2Info (\@glob_lines, \@section_names); >>

C<< $lines_ref = Bootloader::Core::ZIPL->Info2Global (\%section_info, \@section_names, \@sections); >>

C<< Bootloader::Core::ZIPL->MangleSections (\@sections, \%global); >>

C<< ($lines_ref, $com_bef) Bootloader::Core::ZIPL->ProcessSingleMenuFileLine ($lines, $com_bef, $separator); >>

C<< $line = Bootloader::Core::ZIPL->CreateSingleMenuFileLine ($key, $value, $separator); >>


=head1 DESCRIPTION

=over 2

=cut


package Bootloader::Core::ZIPL;

use strict;

use Bootloader::Core;
our @ISA = qw(Bootloader::Core);

sub SetOptions() {
    my $loader = shift;
    
    # possible global entries
    #
    #	default
    #	timeout
    #	prompt
    #	target
    #
    # possible section types:
    #   image
    #   dump
    #   menu
    #   
    # per section entries
    #
    #	label
    #	menuname
    #	image
    #	ramdisk
    #	dumpto
    #	target
    #	parameters
    #	dumptofs (unimplemented)
    #	parmfile (unimplemented)
    
    my %metadata; 
    
    $metadata{"global"} = {
	# maps to either deafult or default_menu
        default => "string",
    };
    
    $metadata{"section"} = {
        type_image     => "bool",
        image_target   => "",
        image_image    => "",
        # converted from ramdisk => initrd
        image_initrd   => "",
        # converted from parameters => append, root
        image_append   => "",
	image_root     => "",
        image_parmfile => "",

        type_dump      => "bool",
        dump_target    => "",
        dump_dumpto    => "",
        dump_dumptofs  => "",

        type_menu      => "bool",
        menu_target    => "",
	menu_list      => "",
	menu_default   => "",
        menu_timeout   => "",
        menu_prompt    => "bool",
    };
    
    
    $loader->{"options"}=\%metadata;
}


=item
C<< $obj_ref = Bootloader::Core::ZIPL->new (); >>

Creates an instance of the Bootloader::Core::ZIPL class.

=cut

sub new
{
  my $self = shift;
  my $ref = shift;
  my $old = shift;

  my $loader = $self->SUPER::new($ref, $old);
  bless($loader);

  $loader->{default_global_lines} = [ ];
  $loader->SetOptions();

  $loader->milestone("Created ZIPL instance");

  return $loader;
}

=item
C<< $settings_ref = Bootloader::Core::ZIPL->GetSettings (); >>

returns the complete settings in a hash. Does not read the settings
from the system, but returns internal structures.

=cut

# map<string,any> GetSettings ()
sub GetSettings {
    my $self = shift;

    return $self->SUPER::GetSettings();
}

=item
C<< $files_ref = Bootloader::Core::ZIPL->ListFiles (); >>

Returns the list of the configuration files of the bootloader
Returns undef on fail

=cut

# list<string> ListFiles ();
sub ListFiles {
    my $self = shift;

    return [ Bootloader::Path::Zipl_conf() ];
}


=item
C<< $status = Bootloader::Core::ZIPL->FixSectionName ($name, \$names_ref, $type); >>

=cut

#XXX ugly, create generic renaming function instead
sub FixSectionName {
    my $self = shift;
    my $name = shift;
    my $names_ref = shift;
    my $type = shift;

    my $orig_name = $name;
    my $allowed_chars = "[:alnum:]";
    my $replacement_char = '';

    # Within zipl.conf: (from src/scan.c in zipl sources)
    #   - menu section name may only contain alphanumeric characters
    #   - other section name may contain punctuation characters in addition
    if ($type ne "menu") {
	$allowed_chars .= "[:punct:]";
	$replacement_char = '_';
    }

    # replace unwanted characters as defined above to underscore or delete
    # them, no length limit. fix name_ref if needed
    $name =~ s/[^$allowed_chars]/$replacement_char/g;

    my $new_name = undef;
    my $new_name_ix = 2;
    my $new_name_arr_ix = undef;

    for (my $i = 0; $i <= $#$names_ref; $i++) {
	$_ = $names_ref->[$i];
	if ($_ eq $orig_name) {
	    $names_ref->[$i] = $name;
	    $new_name = $name;
	    $new_name_arr_ix = $i;
	}
    }

    LOOP:
    my $count = 0;
    for (my $i = 0; $i <= $#$names_ref; $i++) {
	$_ = $names_ref->[$i];
	if ($_ eq $new_name) {
	    $count++;
	}
    }

    if ($count >= 2) {
	for (my $i = 0; $i <= $#$names_ref; $i++) {
	    $_ = $names_ref->[$i];
	    if ($_ eq $new_name) {
		$new_name =~ s/_\d+$//;
		$new_name .= "_" . $new_name_ix;
		$names_ref->[$new_name_arr_ix] = $new_name;
		$new_name_ix++;
	    }
	}
	goto LOOP;
    }

    return $new_name;
}


=item
C<< $status = Bootloader::Core::ZIPL->ParseLines (\%files, $avoid_reading_device_map); >>

Parses the contents of all files and stores the settings in the
internal structures. As first argument, it takes a hash reference,
where keys are file names and values are references to lists, each
member is one line of the file. As second argument, it takes a
boolean flag that, if set to a true value, causes it to skip
updating the internal device_map information. The latter argument
is not used for ZIPL. Returns undef on fail, defined nonzero value
on success.

=cut

# void ParseLines (map<string,list<string>>, boolean)
sub ParseLines {
    my $self = shift;
    my %files = %{+shift};
    my $avoid_reading_device_map = shift;

    # the only file is /etc/zipl.conf
    my @zipl_conf = @{$files{Bootloader::Path::Zipl_conf()} || []};
    (my $glob_ref, my $sect_ref) = $self->ParseMenuFileLines (
	"=",
	["label","menuname"],
	\@zipl_conf
    );

    $self->{"sections"} = $sect_ref;
    $self->{"global"} = $glob_ref;
    return 1;
}


=item
C<< $sections_ref Bootloader::Core->SplitLinesToSections (\@lines, \@section_starts); >>

Splits the lines of the configuration file to particular sections
As argument it takes a reference to a list of lines (each line represented
as a hash) and a reference to a list of keys starting a new section.
Returns a reference of a list of sections, each represented as a list of
lines. The first section is the global section of the bootloader (without

=cut

# list<list<map<string,any>>> SplitLinesToSection
#   (list<map<string,any>> lines, list<string>, section_starts)
sub SplitLinesToSections {
    my $self = shift;
    my @sections = @{$self->SUPER::SplitLinesToSections(@_)};
    my @globals = @{+shift @sections};
    # merge defaultboot section into (propably empty) global section
    my %lines = ( @{$sections[0]} );
    if (exists $lines{"label"} && $lines{"label"} eq "defaultboot") {
	push @globals, @{+shift @sections};
	unshift @sections, \@globals;
    }

    return \@sections;
}


=item
C<< $files_ref = Bootloader::Core::ZIPL->CreateLines (); >>

creates contents of all files from the internal structures.
Returns a hash reference in the same format as argument of
ParseLines on success, or undef on fail.

=cut

# map<string,list<string>> CreateLines ()
sub CreateLines {
    my $self = shift;

    my $zipl_conf = $self->PrepareMenuFileLines (
	$self->{"sections"},
	$self->{"global"},
	"    ",
	" = "
    );
    if (! defined ($zipl_conf))
    {
	return undef;
    }

    return {
	Bootloader::Path::Zipl_conf() => $zipl_conf,
    }
}

=item
C<< $status = Bootloader::Core::ZIPL->UpdateBootloader ($avoid_init); >>

Updates the settings in the system. Backs original configuration files
up and replaces them with the ones with the '.new' suffix. Also performs
operations needed to make the change effect (run '/sbin/zipl').
Returns undef on fail, defined nonzero value on success.

=cut

# boolean UpdateBootloader (boolean avoid_init)
sub UpdateBootloader {
    my $self = shift;
    my $avoid_init = shift;

    my $ret = $self->SUPER::UpdateBootloader ();
    if (! defined ($ret))
    {
	return undef;
    }
    if (! $avoid_init)
    {
	$ret = $self->InitializeBootloader ();
    }
    return $ret;
}

=item
C<< $status = Bootloader::Core::ZIPL->InitializeBootloader (); >>

Initializes the firmware to boot the bootloader.
Returns undef on fail, defined nonzero value otherwise

=cut

# boolean InitializeBootloader ()
sub InitializeBootloader {
    my $self = shift;

    return 0 == $self->RunCommand (
	Bootloader::Path::Zipl_zipl()
    );
}

=item
C<< $lines_ref = Bootloader::Core::ZIPL->Info2Section (\%section_info, \@sect_names); >>

Takes the info about the section and uses it to construct the list of lines.
The info about the section also contains the original lines.
As parameter, takes the section info (reference to a hash), returns
the lines (a list of hashes).

=cut

# list<map<string,any>> Info2Section (map<string,string> info), list<string> sect_names)
sub Info2Section {
    my $self = shift;
    my %sectinfo = ( %{+shift} ); # make a copy of section info
    my $sect_names_ref = shift;


    my @lines = @{$sectinfo{"__lines"} || []};
    my $type = $sectinfo{"type"} || "";
    my $so = $self->{"options"}{"section"};
    
    # allow to keep the section unchanged
    if ((($sectinfo{"__modified"} || 0) == 0) and ($type ne "menu"))
    {
	return \@lines;
    }
    
    @lines = map {
	my $line_ref = $_;
	my $key = $line_ref->{"key"};
	my $parameters = "";

	if ($key eq "label")
	{
	    $line_ref = $self->UpdateSectionNameLine ($sectinfo{"name"}, $line_ref, $sectinfo{"original_name"});
	    delete ($sectinfo{"name"});
	}
	elsif ($key eq "ramdisk")
	{
	    $key = "initrd";
            $line_ref->{"value"} = delete $sectinfo{$key};
	}
	elsif ($key eq "parameters")
	{
            my $root = $sectinfo{"root"}||"";
            $root = "root=$root " unless $root eq "";
	    $line_ref->{"value"} = $root.$sectinfo{"append"};
	    delete ($sectinfo{"root"});
	    delete ($sectinfo{"append"});
        }
	elsif ($key eq "menuname")
	{
            $line_ref->{"value"} = delete $sectinfo{"name"};
        }
	elsif ($key eq "prompt")
	{
            $line_ref->{"value"} =
		delete $sectinfo{$key} eq "true" ? "1" : "0";
	}
        elsif (not exists $so->{$type . "_" . $key})
        {
	    $self->milestone("Ignoring key '$key' for section type '$type'");
	    $line_ref = undef; # only accept known section options CAVEAT!
        }
        else
        {
            if (defined ($sectinfo{$key})) {
		$line_ref->{"value"} = delete $sectinfo{$key};
	    }
	    else {
		$line_ref = undef;
	    }
        }
	defined $line_ref ? $line_ref : ();
    } @lines;

    my $parameters = "";
    while ((my $key, my $value) = each (%sectinfo))
    {
	if ($key eq "name") {
	    if ($type eq "image" || $type eq "dump") {
		my $line_ref = $self->UpdateSectionNameLine($sectinfo{"name"}, {},
							    $sectinfo{"original_name"});
		$line_ref->{"key"} = "label";
		push @lines, $line_ref;
	    }
	    elsif ($type eq "menu") {
		push @lines, {
		    "key" => "menuname",
		    "value" => $value,
		};
	    } # else ignore for unknown section type
        }
        elsif (not exists ($so->{$type . "_" . $key})) {
	    $self->milestone("Ignoring key '$key' for section type '$type'");
            next; 
        }
	elsif ($key eq "list") {
	    my $i = 1;
	    foreach (split(/\s*,\s*/, $value)) {
		# check for valid section references
		foreach my $section (@{$sect_names_ref}) {
		    if ($_ eq $section) {
			push @lines, {
			    "key" => "$i",
			    "value" => "$_",
			};
			$i++;
			last;
		    }
		}
	    }
        }
	elsif ($key eq "initrd" || $key eq "dumpto" || $key eq "target" || $key eq "parmfile") {
	    $key = "ramdisk" if ($key eq "initrd");
	    push @lines, {
		"key" => $key,
		"value" => $value,
	    };
	}
	elsif ($key eq "root") {
	    $parameters = "root=" . $value . " " . $parameters;
        }
        elsif ($key eq "append") {
            $parameters = $parameters . $value;
        }
        elsif ($key eq "prompt") {
	    push @lines, {
		"key" => $key,
		"value" => "1",
	    } if ( $value eq "true");
        }
        else {
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

    if ($parameters) {
        push @lines, {
            "key" => "parameters",
            "value" => "" . $parameters . ""
        };
    }

    my $ret = $self->FixSectionLineOrder (\@lines,
	[ "label", "menuname" ]);

    return $ret;
}

=item
C<< $sectin_info_ref = Bootloader::Core::ZIPL->Section2Info (\@section_lines); >>

Gets the information about the section. As argument, takes a reference to the
list of lines building the section, returns a reference to a hash containing
information about the section.

=cut

# map<string,string> Section2Info (list<map<string,any>> section)
sub Section2Info {
    my $self = shift;
    my @lines = @{+shift};

    my %ret = ();
    my @list = ();

    foreach my $line_ref (@lines) {
	my $key = $line_ref->{"key"};
	if ($key eq "label") {
	    $ret{"name"} = $line_ref->{"value"};
	    my $on = $self->Comment2OriginalName (\%ret,$line_ref->{"comment_before"});
	    $ret{"original_name"} = $on if ($on ne "");
	}
	elsif ($key eq "image")
	{
	    $ret{$key} = $line_ref->{"value"};
	    $ret{"type"} = "image";
	}
	elsif ($key eq "prompt")
	{
	    $ret{$key} = $line_ref->{"value"} eq "1" ? "true" : "false";
	}
	elsif ($key eq "ramdisk" || $key eq "dumpto" || $key eq "default" ||
	       $key eq "timeout" || $key eq "target" || $key eq "parmfile")
	{
	    if($key eq "ramdisk")
	    {
	      $key = "initrd";
	      ($ret{$key} = $line_ref->{"value"}) =~ s/,0x[A-Fa-f0-9]+$//g; # remove load address
            }
            else
	    {
	      $ret{"type"} = "dump" if $key eq "dumpto";
	      $ret{$key} = $line_ref->{"value"};
            }
	}
	elsif ($key eq "parameters")
	{
	    # split off root device from other kernel parameters
            ($ret{"append"} = $line_ref->{"value"}) =~ s/root=\S+\s*//g;
            if ($line_ref->{"value"} =~ m/root=(\S+)(\s+|$)/)
            {
              $ret{"root"} = $1;
            }
        }
	elsif ($key eq "menuname")
	{
	    $ret{"name"} = $line_ref->{"value"} || "menu";
	    $ret{"type"} = "menu";
        }
	elsif ($key =~ m/\d+/)
	{
	    $list[0+$key] = $line_ref->{"value"}
        }
    }


    # Fill menu with default values
    if ($ret{"type"} eq "menu") {
	$ret{"target"} = "/boot/zipl" unless $ret{"target"};
	$ret{"prompt"} = "true" unless exists $ret{"prompt"};
	$ret{"timeout"} = "10" unless exists $ret{"timeout"};
	$ret{"list"} = join(", ", grep { $_; } @list) if (@list) ;
    }

    $ret{"__lines"} = \@lines;
    return \%ret;
}

=item
C<< $glob_info = $Bootloader::Core::ZIPL->Global2Info (\@glob_lines, \@section_names); >>

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
    my $go = $self->{"options"}{"global"}; #not used due to only two entry, but prepared for future updates

    my %ret = ();

    foreach my $line_ref (@lines) {
	my $key = $line_ref->{"key"};
	my $val = $line_ref->{"value"};
	
	if ($key eq "default" || $key eq "defaultmenu")	{
	    $ret{"default"} = $val;
	}
    }
    $ret{"__lines"} = \@lines;
    return \%ret;
}

=item
C<< $lines_ref = Bootloader::Core::ZIPL->Info2Global (\%section_info,
						      \@section_names,
						      \@sections); >>

Takes the info about the global options and uses it to construct the list of lines.
The info about global option also contains the original lines.
As parameter, takes the section info (reference to a hash) and a list of sectino names,
returns the lines (a list of hashes).

=cut

# list<map<string,any>> Info2Global (map<string,string> info,
# 				     list<string>section_names,
#    				     list<map<string,string>>sections)
sub Info2Global {
    my $self = shift;
    my %globinfo = %{+shift};
    my @section_names = @{+shift};
    my @sections = @{+shift};

    my @lines = @{$globinfo{"__lines"} || []};
    my @added_lines = ();
    my $go = $self->{"options"}{"global"}; #not used due to only two entry, but prepared for future updates
    
    # allow to keep the section unchanged
    # FIXME: always regenerate our 'meta global' section to avoid #160595
    if (! ($globinfo{"__modified"} || 0))
    {
    	return \@lines;
    }
    
    my @newlines;
    foreach my $ding (@lines)
    {
      # print $ding->{"key"} . " = " . $ding->{"value"} . "\n";
      next if exists $go->{$ding->{"key"}};	# ignore everything we take care of ourselves...
      next if $ding->{"key"} == "menuname";	# not in global_options because the user is not supposed to tinker with it
      push @newlines, $ding;			# ...and keep everything else (just to be sure)
    }
    @lines = @newlines;
    
    if (scalar (@lines) == 0)
    {
	@lines = @{$self->{"default_global_lines"} || []};
    }

    # create [defaultboot] section
    unshift @lines, {
      "key" => "label",
      "value" => "defaultboot"
    };
    
    # Create default or defaultmenu line here depending on the section type
    my $default_sect = delete $globinfo{"default"};
    my $default_type = "";

    if (defined $default_sect) {
	foreach (@sections) {
	    if (ref($_) eq "HASH") {
		my $s = $_;
		if (exists $_->{"name"} && $_->{"name"} eq $default_sect) {
		    $default_type = $_->{"type"};
		    last;
		}
	    }
	}
    }
    unless ($default_type) {
	$self->warning("default not found, fallback to first entry");
	$default_sect = $sections[0]->{"name"};
	$default_type = $sections[0]->{"type"};
    }

    push @lines, {
	"key" => $default_type eq "menu" ? "defaultmenu" :"default",
	"value" => $default_sect,
    };
    
    return \@lines;
}

# need to override this so we can filter out dump sections;
# doing this in Info2Global would require an API change
# (and even then I wasn't able to get it right. Perl sucks
# golf balls through a hose.)
# -- uli
sub PrepareMenuFileLines {
    my $self = shift;
    my @sectinfo = @{+shift};
    my %globinfo = %{+shift};
    my $indent = shift;
    my $separ = shift;
    my @sect_names = map { $_->{"name"} || (); } @sectinfo;

    #
    # A special handling like the following is needed to make sure
    # that all image sections are referenced at least in the base menu
    # name "menu":
    #
    # If the global default section is
    #   a) a menu section
    #   b) named "menu"
    # then
    #   check all image sections to be in its "list" member
    #   if not append.
    #

    foreach my $sect (@sectinfo) {
       my $type = $sect->{"type"} || "";
       $sect->{"name"} = $self->FixSectionName ($sect->{"name"},
                                                \@sect_names, $type);
    }

    my $menu_list = '';

    # Check all image sections to be in the "list" member of the base menu and
    # append them if they're not already in it.
    if (($globinfo{"default"} eq "menu")) {
       foreach my $sect (@sectinfo) {
           if (($sect->{"type"} eq "menu") and ($sect->{"name"} eq "menu")) {
               $menu_list = $sect->{"list"};
           }
       }
    }

    # Transform $menu_list into an array to be able to bettter compare it with
    # the @sect_names array
    my @menu_list_array = split (/\s*,\s*/, $menu_list);
    my @sect_names_to_append = ();
    my @failsafe_sect_names_to_append = ();

    # Search for sections in @sect_names array which are not yet in "list" of
    # menu section and which are not a menu section theirselves. If found,
    # append them to the "list" of the menu section.
    foreach my $sect (@sectinfo) {
       my $found = 0;

       foreach my $entry (@menu_list_array) {
           if ($entry eq $sect->{"name"}) {
               $found = 1;
           }
       }
       my $is_dump = (($sect->{"type"} eq "dump") and
         (defined $sect->{"dumpto"}) and ($sect->{"dumpto"} ne ""));
       if (!$found and $sect->{"name"} ne "menu" and !$is_dump) {
	 if ($sect->{"original_name"} =~ /failsafe/i || $sect->{"name"} =~ /failsafe/i)
	 {
	   push @failsafe_sect_names_to_append, $sect->{"name"};
	 }
	 else
	 {
           push @sect_names_to_append, $sect->{"name"};
	 }
       }
    }
    if (scalar @sect_names_to_append > 0) {
       unshift @menu_list_array, @failsafe_sect_names_to_append if (scalar @failsafe_sect_names_to_append > 0);
       unshift @menu_list_array, @sect_names_to_append;
       $menu_list = join (', ', @menu_list_array);
    } elsif (scalar @failsafe_sect_names_to_append > 0){
       #do not add failsafe as first option bnc#600847
       my $name = shift @menu_list_array;
       unshift @menu_list_array, @failsafe_sect_names_to_append;
       unshift @menu_list_array, $name;
       $menu_list = join (', ', @menu_list_array);
    }

    # Write back the new "list" to menu section
    if ($globinfo{"default"} eq "menu") {
       foreach my $sect (@sectinfo) {
           if (($sect->{"type"} eq "menu") and ($sect->{"name"} eq "menu")) {
               $sect->{"list"} = $menu_list;
           }
       }
    }

    my @sects = map {
	local $_ = $_;
	my $sect_ref = $self->Info2Section ($_, \@sect_names);
	$sect_ref;
    } @sectinfo;

    my @global = @{$self->Info2Global (\%globinfo, \@sect_names, \@sectinfo)};

    unshift @sects, \@global;
    my @lines = $self->MergeSectionsLines (\@sects, $indent);
    return $self->CreateMenuFileLines (\@lines, $separ);
}

=item

C<< Bootloader::Core::ZIPL->MangleSections (\@sections, \%global); >>

Modifies the section and global data so that the data which is de-facto
global, but in zipl.conf is in sections (defaultboot, menu) is moved to the
global section. Modifies the data which it gets via references directly!!!

=cut

#MangleSections (list &sctions, map &global);
sub MangleSections
{
    my $self = shift;
    my $sections = shift;
    my $global_ref = shift;
    
    my $automangled_menu = 0;
    my @to_remove = ();
    for (my $i = 0; $i <= $#$sections ; $i++)
    {
	my $key = $sections->[$i]->{"name"};
	my $sec = $sections->[$i];
	
	if ($sec->{"name"} eq "defaultboot")
	{
	    push @$global_ref, {
		"key" => "default",
		"value" => $sec->{"default"} || $sec->{"defaultmenu"}
	    };
	    # delete it
	    splice(@$sections,$i,1);
	    $i--;
	}
    }
}

=item
C<< ($lines_ref, $com_bef) Bootloader::Core::ZIPL->ProcessSingleMenuFileLine ($lines, $com_bef, $separator); >>

processes line represented as string and returns it represented as hashes
(containing key, value, relevant comments). The list may be empty, contain
one or more items. As argument, it takes a line (as string), comment from
previous lines and separator between the key and value. Returns a reference
to a list of hashed and a pending comment.

=cut

# (list<map<string,string>>, list<string> comment_before) ProcessSingleMenuFileLine
#     (string line, array ref comment_before, string separator)
sub ProcessSingleMenuFileLine($$$) {
    my $self = shift;
    my $line = shift;
    my $comment_before = shift;
    my $equal_sep = shift;

    my @ret = ();

    if ($self->MenuFileLineEmpty ($line))
    {
	# ignore empty line
    }
    elsif ($line =~ /^[ \t]*\[([^\]]+)\]/)
    {
	my %val = (
	    "key" => "label",
	    "value" => $1,
	    "comment_before" => $comment_before,
	    "comment_after" => ""
        );
	return ( [\%val], []);
    }
    elsif ($line =~ /^[ \t]*\:(.+)$/)
    {
	my %val = (
	    "key" => "menuname",
	    "value" => $1,
	    "comment_before" => $comment_before,
	    "comment_after" => ""
	);
	return ( [\%val], []);
    }
    else
    {
	return $self->SUPER::ProcessSingleMenuFileLine ($line, $comment_before, $equal_sep);
    }
}
 
=item
C<< $line = Bootloader::Core::ZIPL->CreateSingleMenuFileLine ($key, $value, $separator); >>

Transforms a line (hash) to a string to save. As arguments it takes the the key, the
value and a string to separate the key and the value. Returns a string.

=cut

# string CreateSingleMenuFileLine (string key, string value, string separator)
sub CreateSingleMenuFileLine {
    my $self = shift;
    my $key = shift;
    my $value = shift;
    my $equal_sep = shift;

    if ($key eq "label")
    {
	return "[$value]";
    }
    elsif ($key eq "menuname")
    {
	return "\n:$value"; # zipl barfs if there is no empty line before a menu header
    }
    elsif (($key eq "ramdisk" || $key eq "initrd") && !($value =~ /,0x/))
    {
        return "$key$equal_sep$value,0x2000000";
    }
    else
    {
	return $self->SUPER::CreateSingleMenuFileLine ($key, $value, $equal_sep);
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
