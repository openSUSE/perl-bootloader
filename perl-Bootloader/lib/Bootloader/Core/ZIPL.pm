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

C<< $files_ref = Bootloader::Core::ZIPL->ListFiles (); >>

C<< $status = Bootloader::Core::ZIPL->ParseLines (\%files); >>

C<< $files_ref = Bootloader::Core::ZIPL->CreateLines (); >>

C<< $status = Bootloader::Core::ZIPL->UpdateBootloader ($avoid_init); >>

C<< $status = Bootloader::Core::ZIPL->InitializeBootloader (); >>

C<< $sectin_info_ref = Bootloader::Core::ZIPL->Section2Info (\@section_lines); >>

C<< $lines_ref = Bootloader::Core::ZIPL->Info2Section (\%section_info); >>

C<< $glob_info = $Bootloader::Core::ZIPL->Global2Info (\@glob_lines, \@section_names); >>

C<< $lines_ref = Bootloader::Core::ZIPL->Info2Global (\%section_info, \@section_names); >>

C<< Bootloader::Core::ZIPL->MangleSections (\@sections, \%global); >>

C<< ($lines_ref, $com_bef) Bootloader::Core::ZIPL->ProcessSingleMenuFileLine ($lines, $com_bef, $separator); >>

C<< $line = Bootloader::Core::ZIPL->CreateSingleMenuFileLine ($key, $value, $separator); >>

=head1 DESCRIPTION

=over 2

=cut


package Bootloader::Core::ZIPL;

use strict;

use Bootloader::Core;
our @ISA = ('Bootloader::Core');


#module interface

=item
C<< $obj_ref = Bootloader::Core::ZIPL->new (); >>

Creates an instance of the Bootloader::Core::ZIPL class.

=cut

sub new {
    my $self = shift;

    my $loader = $self->SUPER::new ();
    bless ($loader);
    $loader->l_milestone ("ZIPL::new: Created ZIPL instance");
    return $loader;
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
    );
}

=item
C<< $lines_ref = Bootloader::Core::ZIPL->Info2Section (\%section_info); >>

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

    # allow to keep the section unchanged
    if (! ($sectinfo{"__modified"} || 0))
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
#	    $line_ref->{"key"}="[".$line_ref->{"value"}."]";
#	    $line_ref->{"value"}="";
	}
	elsif ($key eq "image" || $key eq "ramdisk")
	{
	    $key = "kernel" if ($key eq "image");
	    $key = "initrd" if ($key eq "ramdisk");
            $line_ref->{"value"} = $sectinfo{$key};
            delete ($sectinfo{$key});
	}
	elsif ($key eq "parameters")
	{
	    $line_ref->{"value"} = "root=".$sectinfo{"root"}." ".$sectinfo{"append"};
	    delete ($sectinfo{"root"});
	    delete ($sectinfo{"append"});
        }
	elsif ($key eq "dumpto" || $key eq "target")
	{
            $line_ref->{"value"} = $sectinfo{$key};
            delete ($sectinfo{$key});
	}
	elsif ($key eq "menuname")
	{
            $line_ref->{"key"}="menuname";
            $line_ref->{"value"}="";
        }

	$line_ref;
    } @lines;

    @lines = grep {
	defined $_;
    } @lines;

    my $parameters = "";
    while ((my $key, my $value) = each (%sectinfo))
    {
	if ($key eq "name")
	{
	    my $line_ref = $self->UpdateSectionNameLine ($sectinfo{"name"}, {}, $sectinfo{"original_name"});
	    $line_ref->{"key"} = "label";
#	    $line_ref->{"key"}="[".$line_ref->{"value"}."]";
#	    $line_ref->{"value"}="";
	    push @lines, $line_ref;
	}
	elsif ($key eq "kernel" || $key eq "initrd" || $key eq "dumpto" || $key eq "target")
	{
	    $key = "image" if ($key eq "kernel");
	    $key = "ramdisk" if ($key eq "initrd");
	    push @lines, {
		"key" => $key,
		"value" => $value,
	    };
	}
	elsif ($key eq "root")
	{
	    $parameters = "root=" . $value . " " . $parameters;
        }
        elsif ($key eq "append")
        {
            $parameters = $parameters . $value;
        }
    }
    if($parameters)
    {
        push @lines, {
            "key" => "parameters",
            "value" => "" . $parameters . ""
        };
    }

    my $ret = $self->FixSectionLineOrder (\@lines,
	["label","menuname"]);

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

    foreach my $line_ref (@lines) {
	my $key = $line_ref->{"key"};
	if ($key eq "label")
	{
	    $ret{"name"} = $line_ref->{"value"};
	    my $on = $self->Comment2OriginalName ($line_ref->{"comment_before"});
	    $ret{"original_name"} = $on if ($on ne "");
	}
	elsif ($key eq "image")
	{
	    $ret{"kernel"} = $line_ref->{"value"};
	    $ret{"type"} = "image";
	}
	elsif ($key eq "ramdisk" || $key eq "dumpto" || $key eq "default" ||
	       $key eq "prompt" || $key eq "timeout" || $key eq "target")
	{
	    $key = "initrd" if $key eq "ramdisk";
	    $ret{"type"} = "dump" if $key eq "dumpto";
	    $ret{$key} = $line_ref->{"value"};
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
	    $ret{"menuname"} = $line_ref->{"value"};
	    $ret{"type"} = "menu";
            $ret{"target"} = "/boot/zipl" unless $ret{"target"};
            $ret{"menuname"} = "menu" unless $ret{"menuname"};
            $ret{"prompt"} = "1" unless $ret{"prompt"};
            $ret{"timeout"} = "10" unless $ret{"timeout"};
        }
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

    my %ret = ();

    foreach my $line_ref (@lines) {
	my $key = $line_ref->{"key"};
	my $val = $line_ref->{"value"};
	if ($key eq "default" || $key eq "timeout" || $key eq "prompt" || $key eq "menuname" || $key eq "target")
	{
	    $ret{$key} = $val;
	}
    }
    $ret{"__lines"} = \@lines;
    return \%ret;
}

=item
C<< $lines_ref = Bootloader::Core::ZIPL->Info2Global (\%section_info, \@section_names); >>

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

    my @lines = @{[]};

    # allow to keep the section unchanged
    if (! ($globinfo{"__modified"} || 0))
    {
	return \@lines;
    }

    # create [defaultboot] section
    push @lines, {
      "key" => "label",
      "value" => "defaultboot"
    };
    
    my $defbootsectionname = "";

    while ((my $key, my $value) = each (%globinfo))
    {
	if ($key eq "default" || $key eq "defaultmenu")
	{
	    push @lines, {
		"key" => $key,
		"value" => $value,
	    };
	}
	$defbootsectionname = $value if $key eq "default";
    }
    

    # create auto-generated menu
    while ((my $key, my $value) = each (%globinfo))
    {
        if ($key eq "menuname")
        {
            push @lines, {
                "key" => "menuname",
                "value" => "$value"
            };
        }
    }

    while ((my $key, my $value) = each (%globinfo))
    {
        if ($key eq "prompt" || $key eq "timeout" || $key eq "target")
        {
            push @lines, {
                "key" => $key,
                "value" => $value
            };
        }
    }
    
    my $defbootsec=1;
    my $seccount=1;
    for (my $i = 0; $i<= $#sections ; $i++)
    {
      if($sections[$i])
      {
        push @lines, {
            "key" => $seccount,
            "value" => $sections[$i]
        };
        $defbootsec = $seccount if ($sections[$i] eq $defbootsectionname);
        $seccount++;
      }
    }
    push @lines, {
        "key" => "default",
        "value" => $defbootsec
    };
    
    return \@lines;
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

      # menu to mangle -> global section
      if (defined ($sections->[$i]->{"type"}) && $sections->[$i]->{"type"} eq "menu" && !$automangled_menu)
      {
        push @$global_ref, {
          "key" => "menuname",
          "value" => $sections->[$i]->{"menuname"}
        };
        if($sec->{"prompt"})
        {
          push @$global_ref, {
            "key" => "prompt",
            "value" => $sec->{"prompt"}
          };
        }
        else
        {
          push @$global_ref, {
            "key" => "prompt",
            "value" => 1
          };
        }
        
        if($sec->{"timeout"})
        {
          push @$global_ref, {
            "key" => "timeout",
            "value" => $sec->{"timeout"}
          };
        }
        else
        {
          push @$global_ref, {
            "key" => "timeout",
            "value" => 10
          };
        }
        if($sec->{"target"})
        {
          push @$global_ref, {
            "key" => "target",
            "value" => $sec->{"target"}
          };
        }
        else
        {
          push @$global_ref, {
            "key" => "target",
            "value" => "/boot/zipl"
          };
        }
        
        # delete it
        splice(@$sections,$i,1);
	$i--;
        
        # make sure we only mangle one menu and pass thru the other ones
        $automangled_menu = 1;
      }

      # defaultboot -> global section
      elsif ($sec->{"name"} eq "defaultboot")
      {
        push @$global_ref, {
          "key" => "default",
          "value" => $sec->{"default"}
        };
        if($sec->{"defaultmenu"})
        {
          push @$global_ref, {
            "key" => "defaultmenu",
            "value" => $sec->{"defaultmenu"}
          };
        }
        # delete it
        splice(@$sections,$i,1);
        $i--;
      }
    }

    if($automangled_menu == 0)
    {
      # push default menu values
      push @$global_ref, { "key" => "menuname", "value" => "menu" };
      push @$global_ref, { "key" => "prompt", "value" => 1 };
      push @$global_ref, { "key" => "timeout", "value" => 10 };
      push @$global_ref, { "key" => "target", "value" => "/boot/zipl" };
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

# (list<map<string,string>>, string comment_before) ProcessSingleMenuFileLine
#     (string line, string comment_before, string separator)
sub ProcessSingleMenuFileLine {
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
	return ( [\%val], "");
    }
    elsif ($line =~ /^[ \t]*\:(.+)$/)
    {
	my %val = (
	    "key" => "menuname",
	    "value" => $1,
	    "comment_before" => $comment_before,
	    "comment_after" => ""
	);
	return ( [\%val], "");
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
	return ":$value";
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
