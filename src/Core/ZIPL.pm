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

C<< $status = Bootloader::Core::ZIPL->ParseLines (\%files); >>

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


#module interface

sub GetMetaData() {
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
    
    my %exports;
    
    my @bootpart;
    my @partinfo = @{$loader->{"partitions"} || []};
    
    # boot from any partition (really?)
    @bootpart = map {
        my ($device, $disk, $nr, $fsid, $fstype, $part_type, $start_cyl, $size_cyl) = @$_;
        $device;
    } @partinfo;
    
    my $boot_partitions = join(":", @bootpart);
    
    my $root_devices = join(":",
        map {
            my ($device, $disk, $nr, $fsid, $fstype, $part_type, $start_cyl, $size_cyl) = @$_;
            # FIXME: weed out non-root partitions
        } @ partinfo,
        keys %{$loader->{"md_arrays"} || {}}
    );
    
    # FIXME: is "arch" export necessary?
    
    $exports{"global_options"} = {
	# maps to either deafult or default_menu
        default => "string:Default Boot Section/Menu:linux",
        #default_menu => "string:Default Boot Menu:",
        #timeout => "int:Timeout in Seconds:5:0:60",
        #prompt => "bool:Show boot menu",
        #target => "path:Target directory for configuration/menu section:/boot/zipl",
    };
    
    my $go = $exports{"global_options"};
    
    $exports{"section_options"} = {
        type_image     => "bool:Image Section",
        image_target   => "path:Target Directory for Image Section:/boot/zipl",
        image_image    => "path:Kernel Image:/boot/image",
        # converted from ramdisk => initrd
        image_initrd   => "path:Initial RAM Disk:/boot/initrd",
        # converted from parameters => append, root
        image_append   => "string:Optional Kernel Parameters",
	image_root     => "selectdevice:Root device::" . $root_devices,
        image_parmfile => "path:Optional Parameter File",

        type_dump      => "bool:Dump Section (obsolete)",
        dump_target    => "path:Target Directory for Dump Section:/boot/zipl",
        dump_dumpto    => "path:Dump Device:/dev/dasd",
        dump_dumptofs  => "path:SCSI Dump Device:/dev/zfcp",

        type_menu      => "bool:Menu Section",
        menu_target    => "path:Target Directory for Menu Section:/boot/zipl",
	menu_list      => "string:List of Menu Entries:linux:",
	# menu_list => "list:List of Menu Entries:linux:",
	menu_default   => "int:Number of Default Entry:1:1:10",
        menu_timeout   => "int:Timeout in seconds:5:0:60",
        menu_prompt    => "bool:Show boot menu",
    };
    
    my $so = $exports{"section_options"};
    
    $loader->{"exports"}=\%exports;
    return \%exports;
}



=item
C<< $obj_ref = Bootloader::Core::ZIPL->new (); >>

Creates an instance of the Bootloader::Core::ZIPL class.

=cut

sub new {
    my $self = shift;
    my $old = shift;

    my $loader = $self->SUPER::new ($old);
    $loader->{"default_global_lines"} = [ ];
    bless ($loader);

    $loader->GetMetaData();
    $loader->l_milestone ("ZIPL::new: Created ZIPL instance");
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

    return [ "/etc/zipl.conf" ];
}


=item
C<< $status = Bootloader::Core::ZIPL->FixSectionName ($name, \$names_ref, $type); >>

=cut

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

    #$orig_name = $name;

    # and make the section name unique
    #$name = $self->SUPER::FixSectionName($name, $names_ref, $orig_name);

    # do it again
    #$name =~ s/[^$allowed_chars]/$replacement_char/g;

    return $new_name;
}


=item
C<< $status = Bootloader::Core::ZIPL->ParseLines (\%files); >>

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

    # the only file is /etc/zipl.conf
    my @zipl_conf = @{$files{"/etc/zipl.conf"} || []};
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
	"/etc/zipl.conf" => $zipl_conf,
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
	"/sbin/zipl",
	"/var/log/YaST2/y2log_bootloader"
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
    my $so = $self->{"exports"}{"section_options"};
    
    # print "info2section, section " . $sectinfo{"name"} . ", type " . $type . ".\n";

    # allow to keep the section unchanged
    if ((($sectinfo{"__modified"} || 0) == 0) and ($type ne "menu"))
    {
	return \@lines;
    }
    
#    $sectinfo{"name"} = $self->FixSectionName ($sectinfo{"name"},
#						$sect_names_ref, $type);
    @lines = map {
	my $line_ref = $_;
	my $key = $line_ref->{"key"};
	my $parameters = "";

	if ($key eq "label")
	{
	    $line_ref = $self->UpdateSectionNameLine ($sectinfo{"name"}, $line_ref, $sectinfo{"original_name"});
	    delete ($sectinfo{"name"});
#	    $line_ref->{"key"}="[".$line_ref->{"value"}."]";
#	    $line_ref->{"value"}="";
	}
	elsif ($key eq "ramdisk")
	{
	    $key = "initrd";
            $line_ref->{"value"} = delete $sectinfo{$key};
	}
	elsif ($key eq "parameters")
	{
	    $line_ref->{"value"} = "root=".$sectinfo{"root"}." ".$sectinfo{"append"};
	    delete ($sectinfo{"root"});
	    delete ($sectinfo{"append"});
        }
	elsif ($key eq "menuname")
	{
            # $line_ref->{"key"}="menuname";
            $line_ref->{"value"} = delete $sectinfo{"name"};
        }
	elsif ($key eq "prompt")
	{
            # $line_ref->{"key"}="menuname";
            $line_ref->{"value"} =
		delete $sectinfo{$key} eq "true" ? "1" : "0";
	}
        elsif (not exists $so->{$type . "_" . $key})
        {
            # print $type . "_" . $key . " unknown!\n";
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
		#  $line_ref->{"key"}="[".$line_ref->{"value"}."]";
		#  $line_ref->{"value"}="";
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
            # print $type . "_" . $key . " unknown!\n";
            next; # only accept known section options CAVEAT!
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
	elsif ($key eq "initrd" || $key eq "dumpto" || $key eq "target") {
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
        else {
            my ($stype) = split /:/, $so->{$type . "_" . $key};
	    # bool values appear in a config file or not
	    if ($stype eq "bool") {
		next if $value ne "true";
		$value = "1";
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
	    my $on = $self->Comment2OriginalName ($line_ref->{"comment_before"});
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
	       $key eq "timeout" || $key eq "target")
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
	    ($ret{"append"} = $line_ref->{"value"}) =~ s/root=[^[:space:]]+[[:space:]]+//g;
	    ($ret{"root"} = $line_ref->{"value"}) =~ s/^.*root=([^[:space:]]+)[[:space:]]+.*$/$1/g;
	    #print "params: ".$ret{"append"}."/".$ret{"root"}."\n";
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
    my $go = $self->{"exports"}{"global_options"};

    my %ret = ();

    foreach my $line_ref (@lines) {
	my $key = $line_ref->{"key"};
	my $val = $line_ref->{"value"};
	# my ($type) = split(/:/, $go->{$key}||""); # not used yet
	
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
    my $go = $self->{"exports"}{"global_options"};
    
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

    #$self->l_milestone ("Info2Global: default_sect = $default_sect");
    #$self->l_milestone ("Info2Global: section_names = ( " . join(",", @section_names) . " )");
    #$self->l_milestone ("Info2Global: sections = ( " . join(",", @sections) . " )");

    if (defined $default_sect) {
	foreach (@sections) {
	    if (ref($_) eq "HASH") {
		my $s = $_;
		#$self->l_milestone ("Info2Global: this_sect = ( " .
		#		    join(",\n", map {"'$_' -> '$s->{$_}'";} keys %{$s})
		#		    . " )");
		if (exists $_->{"name"} && $_->{"name"} eq $default_sect) {
		    $default_type = $_->{"type"};
		    last;
		}
	    }
	}
    }
    unless ($default_type) {
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
    my @menu_list_array = split (/, /, $menu_list);
    my @sect_names_to_append = ();

    # Search for sections in @sect_names array which are not yet in "list" of
    # menu section and which are not a menu section theirselves. If found,
    # append them to the "list" of the menu section.
    foreach my $sect_name (@sect_names) {
	my $found = 0;

	foreach my $entry (@menu_list_array) {
	    if ($entry eq $sect_name) {
		$found = 1;
	    }
	}

	if (!$found and $sect_name ne "menu") {
	    push @sect_names_to_append, $sect_name;
	}
    }
    if (scalar @sect_names_to_append > 0) {
	unshift @menu_list_array, @sect_names_to_append;
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
	
	# print "mangling section " . $sections->[$i]->{"name"} . ", type " . $sections->[$i]->{"type"} . "\n";
	
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
        return "$key$equal_sep$value,0x1000000";
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
