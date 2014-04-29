#! /usr/bin/perl -w
#
# Bootloader configuration base library
#

=head1 NAME

Bootloader::Core - core library for bootloader configuration


=head1 PREFACE

This package is the core library of the bootloader configuration

=head1 SYNOPSIS

use Bootloader::Core;

C<< $res = Bootloader::Core->trim ($string); >>

C<< $members_ref = Bootloader::Core->MD2Members ($md_device); >>

C<< $md_dev = Bootloader::Core->Member2MD (string $md_member); >>

C<< $index = Bootloader::Core->IndexOfSection ($name, \@section_names); >>

C<< ($device, $path) = Bootloader::Core->SplitDevPath ($path); >>

C<< $quoted = Bootloader::Core->Quote ($text, $when); >>

C<< $unquoted = Bootloader::Core->Unquote ($text); >>

C<< $section_ref = Bootloader::Core->FixSectionLineOrder (\@section_ref, \@preferred); >>

C<< $sections_ref Bootloader::Core->SplitLinesToSections (\@lines, \@section_starts); >>

C<< $lines_ref Bootloader::Core->MergeSectionsLines (\@sections, $indent); >>

C<< $lines_ref Bootloader::Core->ProcessMenuFileLines (\@lines, $separator); >>

C<< $line_empty = Bootloader::Core->MenuFileLineEmpty ($line); >>

C<< ($lines_ref, $com_bef) Bootloader::Core->ProcessSingleMenuFileLine ($lines, $com_bef, $separator); >>

C<< $lines_ref = Bootloader::Core->CreateMenuFileLines (\@parsed_lines, $separator); >>

C<< $line = Bootloader::Core->CreateSingleMenuFileLine ($key, $value, $separator); >>

C<< $empty = Bootloader::Core->HasEmptyValue ($key, $value); >>

C<< $obj_ref = Bootloader::Core->new (); >>

C<< files_list_ref = Bootloader::Core->ListMenuFiles (); >>

C<< $files_ref = Bootloader::Core->ReadFiles (\@file_names); >>

C<< $status = Bootloader::Core->WriteFiles (\%files, $suffix); >>

C<< $original_name = Bootloader::Core->Comment2OriginalName ($comment); >>

C<< $line_ref = Bootloader::Core->UpdateSectionNameLine ($name, \%line, $original_name); >>

C<< $original_name = Bootloader::Core->Comment2FormerFlavor ($comment); >>

C<< $sectin_info_ref = Bootloader::Core->Section2Info (\@section_lines); >>

C<< $label = Bootloader::Core->FixSectionName ($name, \@existing, $orig_name); >>

C<< $lines_ref = Bootloader::Core->Info2Section (\%section_info, @section_names); >>

C<< $glob_info = $Bootloader::Core->Global2Info (\@glob_lines, \@section_names); >>

C<< $lines_ref = Bootloader::Core->Info2Global (\%section_info, \@section_names); >>

C<< $sections_ref = Bootloader::Core->MarkInitialSection (\@sections, default); >>

C<< ($global_ref, $sections_ref) Bootloader::Core->ParseMenuFileLines ($separator, \@start_keys, \@lines); >>

C<< $lines_ref = Bootloader::Core->PrepareMenuFileLines (\@sectinos, \%global, $indent, $separator); >>

C<< $status = Bootloader::Core->UpdateBootloader (); >>

C<< $status = Bootloader::Core->RunCommand ($command, $try); >>

C<< $mapping_ref = Bootloader::Core->GetDeviceMapping (); >>

C<< $status = Bootloader::Core->SetDeviceMapping (\%mapping_ref); >>

C<< $settings_ref = Bootloader::Core->GetSettings (); >>

C<< $status = Bootloader::Core->SetSettings (\%settings); >>

C<< $path = Bootloader::Core->ConcatPath ($path1, $path2); >>

C<< $crosses = Bootloader::Core->SymlinkCrossesDevice ($path); >>

C<< $resolved = Bootloader::Core->ResolveCrossDeviceSymlinks ($path); >>

C<< $canonical = Bootloader::Core->CanonicalPath ($path); >>

C<< $real = Bootloader::Core->RealFileName ($filename); >>

C<< $records_ref = Bootloader::Core->GetLogRecords (); >>

C<< Bootloader::Core->MangleSections (\@sections, \%global); >>

=head1 DESCRIPTION

=over 2

=cut

package Bootloader::Core;

use strict;

use base qw ( Bootloader::FileIO Bootloader::Logger );

#constants

my $headline = "# Modified by YaST2. Last modification on ";
my $headline2 = "# THIS FILE WILL BE PARTIALLY OVERWRITTEN by perl-Bootloader";
my $headline3 = "# For the new kernel it try to figure out old parameters. In case we are not able to recognize it (e.g. change of flavor or strange install order ) it it use as fallback installation parameters from /etc/sysconfig/bootloader";

# variables

=item
C<< $res = Bootloader::Core->trim ($string); >>

Cut whitespace from front and back.

=cut
sub trim{
    my $self = shift;
    my $string = shift;
    $string =~ s/^\s+//;
    $string =~ s/\s+$//;
    return $string;
}

=item
C<< $members_ref = Bootloader::Core->MD2Members ($md_device); >>

Gets the list of partitions building an MD software RAID array. As argument
it takes a MD device (string), returns a reference to a list of its members.

=cut

# list<string> MD2Members (string md_device)
sub MD2Members {
    my $self = shift;
    my $md_dev = shift;

    my $md_dev_red = substr ($md_dev, 5);
    my $members_ref = $self->{"md_arrays"}{$md_dev} || $self->{"md_arrays"}{$md_dev_red} || [$md_dev];
    return $members_ref;
}

=item
C<< $md_dev = Bootloader::Core->Member2MD (string $md_member); >>

Gets the MD RAID device a specified disk belongs to. As argument, it takes
a disk which is supposed to be a member of a RAID, returns the RAID device
name.

=cut

#string Member2MD (string md_member)
sub Member2MD
{
  my $self = shift;
  my $member = shift;

  my $orig = $member;

  my $find = undef;

    while ((my $md, my $mem_ref) = each (%{$self->{"md_arrays"}}))
    {
      unless (defined $find)
      {
	foreach my $mem (@{$mem_ref})
	{
	    if ($mem eq $member)
	    {
		if (substr ($md, 0, 5) ne "/dev/")
		{
		    $md = "/dev/" . $md;
		}
		$member = $md;
                $find = 1;
                last;
	    }
	}
      }
    }

  $self->milestone("$orig => $member");

  return $member;
}

=item
C<< $index = Bootloader::Core->IndexOfSection ($name, \@section_names); >>

Finds the section in the list. As arguments, takes the name of the section
(string, eg. C<'linux'>) and the list of section names (list reference, eg.
C<['linux', 'failsafe']>). Returns index of the section (integer) or undef
if the section was not found in the list.

=cut

# integer IndexOfSection (string name, list<string> section_names)
sub IndexOfSection {
    my $self = shift;
    my $name = shift;
    my @sections = @{+shift};

    my $index = -1;
    foreach my $sn (@sections)
    {
	$index = $index + 1;
	if ($sn eq $name)
	{
	    return $index;
	}
    }
    return undef;
}

=item
C<< ($device, $path) = Bootloader::Core->SplitDevPath ($path); >>

Divides the absolute path to the mountpoint and path relative
to the mountpoint, transforms the mountpoint to the device holding
the filesystem. As argument it takes the path (string, eg. 
C<'/boot/grub/device.map'>), returns two-entry-list (NOT a reference)
containing the device and the relative path (eg. C<('/dev/hda1', '/grub/device.map')>)

=cut

# string, string SplitDevPath (string path)
sub SplitDevPath {
    my $self = shift;
    my $path = shift;
    my $orig = $path;

    $path = $self->RealFileName ($path);

    my $mp = $path || "/";
    until (exists $self->{"mountpoints"}{$mp}) {
	unless ($mp =~ s#/[^/]*$##) {
	    $self->error("Cannot get device for $path");
	    return undef;
	}
 	if ($mp eq "") {
	    unless (exists $self->{"mountpoints"}{"/"}) {
	    	$self->error("Cannot get device for $path, no root mount point set");
	    	return undef;
	    }
	    $mp = "/";
	}
    }

    my $dev = $self->{"mountpoints"}{$mp};
    $path =~ s#^$mp/?#/#;
    $self->milestone("$orig was split to $dev + $path");
    return ($dev, $path);
}

=item
C<< $extended_part_dev = Bootloader::Core->GetExtendedPartition ($part_dev); >>

Takes a device name (string, eg. C<'/dev/sda7'>) and returns the device name
of the extended partition on the same disk (string, eg. C<'/dev/sda3'>). If no
extended partition exists on that disk, returns undef.

=cut

# string GetExtendedPartition (string part_dev)
sub GetExtendedPartition {
    my $self = shift;
    my $part_dev = shift;
    my $extended_part_dev = undef;

    # Check for valid devices
    unless (defined $part_dev and $part_dev =~ m/^\/dev\/[shv]d[a-z](\d+)?$/) {
	$self->milestone("Specified device ".
	    $part_dev||"undefined partdev".
            " is not valid and cannot be used as base for detecting an
            extended partition on the same disk.");
	return $extended_part_dev;
    }

    # Cut the partition number (if any) to get the corresponding disk
    my $disk_dev = $part_dev;
    $disk_dev =~ s/\d+$//;

    # Partitioninfo is a list of list references of the format:
    #   Device,   disk,    nr, fsid, fstype,   part_type, start_cyl, size_cyl
    #   /dev/sda9 /dev/sda 9   258   Apple_HFS `primary   0          18237

    foreach my $part_ref (@{$self->{"partitions"}}) {
	if ($part_ref->[1] eq $disk_dev and
	    $part_ref->[5] eq "`extended") {
	    $extended_part_dev = $part_ref->[0];
	}
    }

    return $extended_part_dev;
}

=item
C<< $quoted = Bootloader::Core->Quote ($text, $when); >>

Puts a text to quotes. As arguments takes the text (string) and information
when the text should be put into quotes (string, C<'always'> or C<'blanks'>
to specify if the text should be put between quotes always or only if it
contains at least one blank character. Returns the text put into the quotes
(if wanted or needed) (string)

=cut

# string Quote (string text, string when)
sub Quote {
    my $self = shift;
    my $text = shift;
    my $when = shift;

    if ($when eq "always"
	|| ($when eq "blanks" && index ($text, " ") >= 0)
	|| ($when eq "blanks" && $text eq "")
	|| index ($text, "=") >= 0)
    {
        $text =~ s: +: :; #remove duplicated spaces
	$text = "\"$text\"";
    }
    
    return $text;
}

=item
C<< $unquoted = Bootloader::Core->Unquote ($text); >>

Removes leading and tailing quotes of a string. As argument takes a string,
returns it unquoted.

=cut

# string Unquote (string text)
sub Unquote {
    my $self = shift;
    my $text = shift;

    $text = $self->trim($text);
    #now unquote
    if ($text =~ /^\"(.*)\"$/)
    {
	$text = $1;
    }
    return $text;
}

=item
C<< $merged = Bootloader::Core->MergeDefined (@strings); >>

Merges the strings (those defined and non-empty). As arguments, it takes
strings, returns them merged with one space character.

=cut

# string MergeIfDefined (string s1, string s2, ...)
sub MergeIfDefined {
    my $self = shift;
    my @args = @_;

    my $ret = "";
    foreach my $arg (@args)
    {
	if (defined ($arg))
	{
          if ($ret eq "") #first defined entry
          {
            $ret = $arg;
          }
          else
          {
	    $ret = $ret . " " . $arg;
          }
	}
    }
    return $ret;
}

=item
C<< $section_ref = Bootloader::Core->FixSectionLineOrder (\@section_ref, \@preferred); >>

reorders the lines of the section. As arguments takes reference to lines of the
section (each line represented as a hash reference), and a list of preferred keys.
Returns a reference to the reordered lines of a section. Lines having any of the
preferred keys will be in the return value placed before the other ones. If there
are multiple lines having a preferred key, they will be sorted according to the list
of oreferred keys.

=cut

# list<map<string,any>> FixSectionLineOrder
#   (list<map<string,any>> section, list<string> preferred)
sub FixSectionLineOrder {
    my $self = shift;
    my @section = @{+shift};
    my @preferred = @{+shift};

    my @first = ();
    my @later = @section;
    foreach my $pref (@preferred)
    {
	@section = @later;
	@later = ();
	foreach my $entry_ref (@section)
	{
	    if ($pref eq $entry_ref->{"key"})
	    {
		push @first, $entry_ref;
	    }
	    else
	    {
		push @later, $entry_ref;
	    }
	}
    }

    splice (@later, 0, 0, @first);
    return \@later;
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
    my @parsed_lines = @{+shift};
    my @section_start_keys = @{+shift};

    my %start_keys = ();
    foreach my $key (@section_start_keys)
    {
	$start_keys{$key} = 1;
    }

    my @sections = ();
    my @one_section = ();
    foreach my $line_ref (@parsed_lines)
    {
	my $key = $line_ref->{"key"};
	if (defined ($start_keys{$key}))
	{
	    my @new_section = @one_section;
	    push (@sections, \@new_section);
	    @one_section = ();
	}
	push (@one_section, $line_ref);
    }
    push (@sections, \@one_section);
    return \@sections;
}

=item
C<< $lines_ref Bootloader::Core->MergeSectionsLines (\@sections, $indent); >>

merges the sections into one. Except all lines of the first section and
the first lines of other sections, all lines are indented by the specified
string. As arguments takes a list of sections (global section should be at
the beginning of the list) and a string specifying the indentation. Returns
a list of lines.
Each section is represented as a list of lines, line is represented as a hash.

=cut

# list<map<string,any>> MergeSectionsLines
#   (list<list<map<string, any>>> sections, string indent)
sub MergeSectionsLines {
    my $self = shift;
    my @sections = @{+shift};
    my $indent = shift;

    my @ret = ();
    my $ind = "";
    foreach my $sect_ref (@sections)
    {
	my $first = 1;
	my @sect = @{$sect_ref};
	foreach my $entry (@sect)
	{
	    if ($first && $ind ne "")
	    {
		$entry->{"comment_before"} = [] unless defined $entry->{"comment_before"};
		unshift @{$entry->{"comment_before"}}, "";
	    }
	    else
	    {
		$entry->{"indent"} = $ind;
	    }
	    $first = 0;
	    push @ret, $entry;
	}
	$ind = $indent;
    }
    return @ret;
}

=item
C<< $lines_ref Bootloader::Core->ProcessMenuFileLines (\@lines, $separator); >>

processes lines represented as strings and returns them represented as hashes
(containing key, value, relevant comments). As argument, it takes a reference to
the list of lines of the file containing the menu and separator between the key
and value. Returns a reference to a list of hashed.

=cut

# list<map<string,string>> ProcessMenuFileLines (list<string> lines, string separator)
sub ProcessMenuFileLines {
    my $self = shift;
    my @lilo_conf_lines = @{+shift};
    my $equal_sep = shift;

    my $comment_before = [];
    my @ret = ();

    my $real_line = undef;
    foreach my $line (@lilo_conf_lines)
    {
        #handle multiline entries
        if (defined $real_line) 
        {
          $real_line = "$real_line $line";
        }
        else
        {
          $real_line = $line;
        }

        if ($real_line =~ m/[^\\]\\$/)
        {
          $real_line = substr $real_line, 0, -1;
          next;
        }

	(my $new_lines_ref, $comment_before) =
	    $self->ProcessSingleMenuFileLine ($real_line, $comment_before, $equal_sep);
	foreach my $l (@{$new_lines_ref}) {
	    push @ret, $l;
	};
        $real_line = undef;
    }
    return @ret;
}

=item
C<< $line_empty = Bootloader::Core->MenuFileLineEmpty ($line); >>

checks if a line is empty (or contains the time stamp by the library),
or contains some information (comment is treated as information here).
Takes the line as string, returns a scalar (1 if empty, 0 otherwise).

=cut

# boolean MenuFileLineEmpty (string line)
sub MenuFileLineEmpty {
    my $self = shift;
    my $line = shift;

    if (index ($line, $headline) >= 0
        or index ($line, $headline2) >= 0
        or index ($line, $headline3) >= 0)
    {
	# ignore the headline with modification date/time
	return 1;
    }
    elsif ($line =~ /^\s*$/)
    {
	# ignore empty line
	return 1;
    }
    else
    {
	#contains at least a comment
	return 0;
    }
}

=item
C<< $allow_afterline_empty = Bootloader::Core->AllowCommentAfterText(); >>

checks if bootloader configuration allow comments after text on line,
returns a scalar (1 if true, 0 otherwise).

=cut

# boolean MenuFileLineEmpty (string line)
sub AllowCommentAfterText {
  return 1;
}

=item
C<< ($lines_ref, $com_bef) Bootloader::Core->ProcessSingleMenuFileLine ($lines, $com_bef, $separator); >>

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

    # convert 'hidden magic' entry to normal one
    $line =~ s/^##YaST - //;

    if ($self->MenuFileLineEmpty ($line))
    {
	# skip empty
    }
    elsif ($line =~ /^\s*#/)
    {
	push @{$comment_before}, $line;
    }
    elsif ($line =~ /^\s*([^:\[ \t=#]+)[ \t]*(.*)$/)
    {
	my $value = "";
	my $comment_after = "";
	my $key = $1;
	$line = $2;
	if ($self->AllowCommentAfterText() and $line =~ /^([^#]*?)(\s*#.*)$/)
	{
            print "comment after";
	    $line = $1;
	    $comment_after = $2;
	}
	if ($equal_sep && ($line =~ /=\s*(.*)/)) 
	{
	    $value = $1;
	}
	elsif (!$equal_sep && ($line !~ /^\s*$/))
	{
	    $value = $line;
	}
	$value = $self->Unquote ($value);
	my %val = (
	    "key" => $key,
	    "value" => $value,
	    "comment_before" => $comment_before,
	    "comment_after" => $comment_after,
	);
	push @ret, \%val;
	$comment_before = [];
    }
    return ( \@ret, $comment_before );
}

=item
C<< $lines_ref = Bootloader::Core->CreateMenuFileLines (\@parsed_lines, $separator); >>

Transforms the list of lines (hashes) to list of lines-string to save. As arguments
it takes the list of lines represented as hashes and a string to separate the key ent
the value. Returns a reference to a list of strings.

=cut

# CreateMenuFileLines (list<map<string,any>> parsed_lines, string separator)
sub CreateMenuFileLines {
    my $self = shift;
    my @parsed_lines = @{+shift};
    my $equal_sep = shift;

    use POSIX qw(strftime);
    my $date = strftime "%a %b %e %H:%M:%S %Z %Y", localtime;
    my @ret = ($headline . $date."\n".$headline2."\n".$headline3."\n");

    foreach my $l (@parsed_lines) {
	push @ret, @{$l->{"comment_before"}} if defined $l->{"comment_before"};

	my $ind = $l->{"indent"} || "";
	my $line = $self->CreateSingleMenuFileLine (
	    $l->{"key"},
	    defined ($l->{"value"}) ? $l->{"value"} : "",
	    $equal_sep);
    
	$line = $l->{"indent"} . $line if defined $l->{"indent"};
	$line .= $l->{"comment_after"} if defined $l->{"comment_after"};

	push @ret, $line;
    }
    return \@ret;
}

=item
C<< $line = Bootloader::Core->CreateSingleMenuFileLine ($key, $value, $separator); >>

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
	$value = $self->Quote ($value, "blanks");
	$line = "$line$equal_sep$value";
    }
    return $line;
}

=item
C<< $empty = Bootloader::Core->HasEmptyValue ($key, $value); >>

Checks if a value is empty and only the keyword is to be written to the
configuration file. Takes the key and value, returns if only keyword is to
be written to configuration file

=cut

# boolean HasEmptyValue (string key, string value)
sub HasEmptyValue {
    my $self = shift;
    my $key = shift;
    my $value = shift;

    return $value eq "";
}

#module interface

=item
C<< $obj_ref = Bootloader::Core->new ($old); >>

Creates an instance of the Bootloader::Core class.
Optional parameter 'old' is object reference to former bootloader
=cut
sub new
{
  my $self = shift;
  my $ref = shift;
  my $old = shift;

  my $loader = {};
  bless($loader);

  # keep old settings if given as parameter
  if(defined $old) {
    $ref->milestone("keeping old settings");
    for my $key (keys %{$old}) {
      $loader->{$key} = $old->{$key};
    }
  }

  # copy log data from Library object
  $loader->CloneLog($ref);

  return $loader;
}


# list<string> ListFiles ();
# must be overridden
sub ListFiles {
    my $self = shift;
    $self->error("Running generic function, it should never be called");
    return [];
}

=item
C<< files_list_ref = Bootloader::Core->ListMenuFiles (); >>

List configuration files which have to be changed if only the boot menu
has changed.

=cut

# list<string> ListMenuFiles ();
sub ListMenuFiles {
    my $self = shift;

    return $self->ListFiles ();
}


=item
C<< $status = Bootloader::Core->WriteFiles (\%files, $suffix, $menu_only); >>

Writes the files to the disk.
As 1st argument it takes a reference to a hash where the keys are file names and
values are references to a list of lines to write to the file.
The 2nd argument is an extra file suffix to append.
If the 3rd argument is true it only writes those files that ListMenuFiles() returns.

Returns 1 on success, 0 otherwise.

=cut

# boolean WriteFiles (map<string,list<string>>, string suffix, boolean menu_only)
sub WriteFiles
{
  my $self = shift;
  my $files = shift;
  my $suffix = shift;
  my $menu_only = shift;
  my $ok = 1;
  local $_;

  $self->milestone("menu_only = $menu_only, suffix = $suffix, files =", [ sort keys %$files ] );

  my $files2write = $menu_only ? $self->ListMenuFiles() : [ sort keys %$files ];

  $ok &= $self->WriteFile($_ . $suffix, $files->{$_}) for @$files2write;

  return $ok;
}

=item
C<< $original_name = Bootloader::Core->CompleteSection($section_info); >>

Fill missing required keys of section.

=cut

sub CompleteSection($) {
  my $self = shift;
  my $info = shift;

  unless (defined $info->{"__handled"})
  {
    $self->milestone("Add missing handled section");
    if ($info->{"type"} eq "image"
      || $info->{"type"} eq "xen")
    {
      $info->{"__handled"} = "auto";
      $info->{"__handled"} = "all";
    }
    else
    {
      $info->{"__handled"} = "user";
    }
  }
}


=item
C<< $original_name = Bootloader::Core->Comment2OriginalName ($section_ref,$comment); >>

Gets the aditional information of the section from the comment. As argument, takes
reference to section and the comment.

=cut

my $orig_name_comment="###Don't change this comment - YaST2 identifier: Original name: ";
my $auto_comment_read="###Don't change this comment - YaST2 identifier: Original name: \(.*\) Handled by: YaST2 flavor: \(.*\)###";
my $auto_comment_write="###Don't change this comment - YaST2 identifier: Original name: %s Handled by: YaST2 flavor: %s###";
my $manual_comment_read="###Don't change this comment - YaST2 identifier: Original name: \(.*\) Handled by: user###";
my $manual_comment_write="###Don't change this comment - YaST2 identifier: Original name: %s Handled by: user###";

# string Comment2OriginalName (list<string> comment)
sub Comment2OriginalName() {
    my $self = shift;
    my $section = shift;
    my $comment_lines_ref = shift || [];
    my $ret = "";
    foreach my $comment (@{$comment_lines_ref}) {
	if( $comment =~ m/$orig_name_comment(.*)###/)
        {
          $section->{"original_name"} = $1;
          $ret = $1;
        }
=cut prepared autosections
        elsif ( $comment =~ $auto_comment_read )
        {
          $section->{"original_name"} = $1;
          $section->{"__handled"} = "auto";
          $section->{"__flavor"} = $2;
        }
        elsif ( $comment =~ $manual_comment_read )
        {
          $section->{"original_name"} = $1;
          $section->{"__handled"} = "user";
        }
=cut
    }
    return $ret;
}

=item
C<< $line_ref = Bootloader::Core->UpdateSectionNameLine ($section, \%line, $original_name); >>

Updates the 'section name line' so that it contains specified name and original name
inside the comment. As arguments, takes the section reference (hash reference), the line (hash reference)
and the original name (string). If original name is set to undef or empty string,
it is not set in the comment. Returns the updated line reference.

=cut

# map<string,any> UpdateSectionNameLine (map section, map<string,any> line, string original_name)
sub UpdateSectionNameLine {
    my $self = shift;
    my $name = shift;
    my $line_ref = shift || {};
    my $original_name = shift;

    $line_ref->{"value"} = $name;
    if (defined ($original_name) && $original_name ne "")
    {
	my @comment_before = grep {
          my $line = $_;
          my $ret = 1;
          if ($line =~ m/$orig_name_comment/
            || $line =~ m/$auto_comment_read/
            || $line =~ m/$manual_comment_read/)
          {
            $ret = 0;
          }
          $ret;
	}  @{$line_ref->{"comment_before"} || []};
        push @comment_before, $orig_name_comment.$original_name."###";
=cut
        if ( $section->{"__handled"} eq "auto" )
        {
          my $flavor = $section->{"__flavor"};
          my $comment = sprintf($auto_comment_write, $original_name, $flavor);
	  push @comment_before, $comment;
          $self->milestone("section name: $name comment: $comment" );
        }
        elsif( $section->{"__handled"} eq "manual")
        {
          my $comment = sprintf($manual_comment_write, $original_name);
	  push @comment_before, $comment;
          $self->milestone("section name: $name comment: $comment" );
        }
=cut
	$line_ref->{"comment_before"} = \@comment_before;
    }
    return $line_ref;
}

=item
C<< $original_name = Bootloader::Core->Comment2RemovedDefault ($comment); >>

Gets 1 if comment contains info about removed default. This can happen when you remove default kernel (this can handle situation when changing kernele and old kernel is removed before installing new.

=cut

my $remove_default_comment = "###YaST update: removed default";

# string Comment2FormerFlavor (list<string> comment)
sub Comment2RemovedDefault($) {
    my $self = shift;
    my $comment_lines_ref = shift || [];
    foreach (@{$comment_lines_ref}) {
	return 1
	    if m/${remove_default_comment}/o;
    }
    return 0;
}

=item
C<< $line_ref = Bootloader::Core->CreateRemovedDefaultLine (\%line,); >>

Updates the 'default line' in globals so that it contains info about removed default line. Returns the updated line reference.

=cut

# map<string,any> CreateRemovedDefaultLine (map<string,any> line)
sub CreateRemovedDefaultLine {
    my $self = shift;
    my $line_ref = shift || {};

    my @comment_before;

    push @comment_before, "${remove_default_comment}";

    $self->milestone("put removed default comment");
		
    $line_ref->{"comment_before"} = \@comment_before;

    return $line_ref;
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
	    $ret{"name"} = $line_ref->{"value"};
	    my $on = $self->Comment2OriginalName (\%ret,$line_ref->{"comment_before"});
	    $ret{"original_name"} = $on if ($on ne "");
	}
	elsif ($key eq "image")
	{
	    $ret{"image"} = $line_ref->{"value"};
	    $ret{"type"} = "image";
	}
	elsif ($key eq "initrd" || $key eq "root" || $key eq "append" || $key eq "wildcard")
	{
	    $ret{$key} = $line_ref->{"value"};
	}
        elsif (  $key eq "vga" )
        {
            $ret{"vgamode"} = $line_ref->{"value"};
        }
        elsif (  $key eq "optional" )
        {
            $ret{$key} = "true";
        }
	elsif ($key eq "other")
	{
	    $ret{"chainloader"} = $line_ref->{"value"};
	    $ret{"type"} = "chainloader";
	}
    }
    $ret{"__lines"} = \@lines;
    return \%ret;
}

=item
C<< $label = Bootloader::Core->FixSectionName ($name, \@existing, $orig_name); >>

Update the section name so that it does not break anything (is in compliance
with the bootloader and is unique). As arguments takes suggested section name
and list of existing sections, returns updated section name and updates the
list of section names as a side effect. Optional parameter orig_name is
intended for internal use of the loader specific modules

=cut
 
# string FixSectionName (string name, list<string> existing, optional orig_name)
sub FixSectionName {
    my $self = shift;
    my $name = shift;
    my $names_ref = shift;
    my $orig_name = shift || $name;

    my $index = 0;	# 0 means not-found, 1 is_unique, else index to be
    			# appended
    my $name_ix = -1;

    # make the section name unique, if you find a duplicate then make it
    # distinguishable by appending an underscore followed by a number 
    for (my $i = 0; $i <= $#$names_ref; $i++) {
	$_ = $names_ref->[$i];
	$name_ix = $i
	    if $_ eq $orig_name; # remember index of original name
	# Does the name start with $name? -> cut off and calc $index
	if (s/^\Q$name\E//) {
	    if ($_ eq '') {
		# count one up for every identical entry, should be
		# maximum one but who knows ...
		$index++;
		next;
	    }
	    s/^_//;	# cut off an optional leading underscore
	    if (/^\d*$/) {
		my $new_index = $_ + 1;	# interprete the remainder string as
	    				# integer index and try next number
		# finally take the maximum as index to append to $name
		$index = $new_index if $index < $new_index;
	    }
	}
    }
    
    # update $name and list of section names if neccessary
    $name .= "_" . $index if $index>1;
    $names_ref->[$name_ix] = $name if $name_ix>=0;

    return $name;
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

    # allow to keep the section unchanged
    if (! ($sectinfo{"__modified"} || 0))
    {
	return $self->FixSectionLineOrder (
	    \@lines,
	    ["image", "other"]);
    }

    $sectinfo{"name"} = $self->FixSectionName ($sectinfo{"name"}, $sect_names_ref);

    @lines = map {
	my $line_ref = $_;
	my $key = $line_ref->{"key"};

	if ($key eq "label")
	{
	    $line_ref = $self->UpdateSectionNameLine ($sectinfo{"name"}, $line_ref, $sectinfo{"original_name"});
	    delete ($sectinfo{"name"});
	}
        elsif ($key eq "vga"){
	  $line_ref->{"value"} = $sectinfo{"vgamode"} if (defined  $sectinfo{"vgamode"});
        }
	elsif ($key eq "image" || $key eq "initrd" || $key eq "root"
	     || $key eq "append" || $key eq "wildcard")
	{
	    if ($type eq "chainloader" || ! defined ($sectinfo{$key}))
	    {
		$line_ref = undef;
	    }
	    else
	    {
		$line_ref->{"value"} = $sectinfo{$key};
		delete ($sectinfo{$key});
	    }
	}
	elsif ($key eq "other")
	{
	    if ($type eq "image" || ! defined ($sectinfo{$key}))
	    {
		$line_ref = undef;
	    }
	    else
	    {
		$line_ref->{"value"} = $sectinfo{$key};
		delete ($sectinfo{$key});
	    }
	}

	$line_ref;
    } @lines;

    @lines = grep {
	defined $_;
    } @lines;

    while ((my $key, my $value) = each (%sectinfo))
    {
	if ($key eq "name")
	{
	    my $line_ref = $self->UpdateSectionNameLine ($sectinfo{"name"}, {}, $sectinfo{"original_name"});
	    $line_ref->{"key"} = "label";
	    push @lines, $line_ref;
	}
	elsif ($key eq "initrd" || $key eq "root"
	    || $key eq "vgamode" || $key eq "append" || $key eq "chainloader"
	    || $key eq "wildcard" || $key eq "image" || $key eq "other")
	{
	    $key = "other" if ($key eq "chainloader");
	    $key = "vga" if ($key eq "vgamode");
	    push @lines, {
		"key" => $key,
		"value" => $value,
	    };
	}
        else
        {
          $self->milestone("Unknown key $key with value $value");
        }
    }

    my $ret = $self->FixSectionLineOrder (\@lines,
	["image", "other"]);

    return $ret;
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

    my %ret = ();

    foreach my $line_ref (@lines) {
	my $key = $line_ref->{"key"};
	my $val = $line_ref->{"value"};
	$val = $val / 10 if ($key eq "timeout");
	$key = "gfxmenu" if ($key eq "message");
	if ($key eq "default" || $key eq "timeout" || $key eq "gfxmenu" || $key eq "password")
	{
	    $ret{$key} = $val;
	}
	elsif ($key eq "boot")
	{
	    my @devs = @{$ret{"stage1_dev"} || []};
	    push @devs, $val;
	    $ret{"stage1_dev"} = \@devs;
	}
	elsif ($key eq "prompt")
	{
	    $ret{$key} = 1;
	}
	elsif ($key eq "activate")
        {
            $ret{$key} = "true"
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
    my @added_lines = ();

    # allow to keep the section unchanged
    if (! ($globinfo{"__modified"} || 0))
    {
	return \@lines;
    }

    if (scalar (@lines) == 0)
    {
	@lines = @{$self->{"default_global_lines"} || []};
    }

    @lines = map {
	my $line_ref = $_;
	my $key = $line_ref->{"key"};
	if ($key eq "default" || $key eq "timeout" || $key eq "message" || $key eq "password")
	{
	    $key = "gfxmenu" if ($key eq "message");
	    if (! defined ($globinfo{$key}))
	    {
		$line_ref = undef;
	    }
	    else
	    {
		my $value = $globinfo{$key};
		$value = $value * 10 if ($key eq "timeout");
		$line_ref->{"value"} = $value;
		delete ($globinfo{$key});
	    }
	}
	elsif ($key eq "boot")
	{
	    $key = "stage1_dev";
	    if (defined ($globinfo{$key}))
	    {
		my %line = %{$line_ref};
		foreach my $dest (@{$globinfo{$key}})
		{
		    my %new_line = %line;
		    $new_line{"value"} = $dest;
		    push (@added_lines, \%new_line);
		}
		$line_ref = shift @added_lines;

		delete ($globinfo{$key});
	    }
	    else
	    {
		$line_ref = undef;
	    }
	}
	elsif ($key eq "prompt")
	{
	    if (defined ($globinfo{"prompt"}) && "0" ne $globinfo{"prompt"})
	    {
		$line_ref->{"value"} = "";
		delete ($globinfo{$key});
	    }
	    else
	    {
		$line_ref = undef;
	    }
	} elsif ($key eq "read-only"){
          $line_ref = undef;
        }
	$line_ref;
    } @lines;

    @lines = grep {
	defined $_;
    } @lines;
    foreach my $line_ref (@added_lines)
    {
	push @lines, $line_ref;
    }

    while ((my $key, my $value) = each (%globinfo))
    {
	if ($key eq "default" || $key eq "timeout" || $key eq "gfxmenu" || $key eq "password")
	{
	    $key = "message" if ($key eq "gfxmenu");
	    $value = $value * 10 if ($key eq "timeout");
	    push @lines, {
		"key" => $key,
		"value" => $value,
	    };
	}
	elsif ($key eq "stage1_dev")
	{
	    my @devs = @{$value || []};
	    foreach my $dev (@devs) {
		push @lines, {
		    "key" => "boot",
		    "value" => $dev,
		} 
	    }
	}
	elsif ($key eq "prompt" && "0" ne $globinfo{"prompt"})
	{
	    push @lines, {
		"key" => $key,
		"value" => "",
	    };
	}
    }
    return \@lines;
}

=item
C<< $sections_ref = Bootloader::Core->MarkInitialSection (\@sections, default); >>

Marks the section that is the initial one - the "Linux" section (even if
it had been renamed). Uses several heuristics to get this one, one of them
is the default section name. As arguments, takes the list of all sections
and the default section name.
Returns the list of sections, where the default one has the "initial" key set.

=cut

# list MarkInitialSection (list sections, string default);
sub MarkInitialSection {
    my $self = shift;
    my @sects = @{+shift};
    my $default = shift;

    my $found = 0;
    # first check the flag in comment
    @sects = map {
	if (defined ($_->{"original_name"}) && $_->{"original_name"} eq "linux" && ! $found)
	{
	    $found = 1;
	    $_->{"initial"} = 1;
	}
	$_;
    } @sects;
    # well, try section called 'linux'
    if (! $found)
    {
	@sects = map {
	    if (defined ($_->{"name"}) && $_->{"name"} eq "linux" && ! $found)
	    {
		$found = 1;
		$_->{"initial"} = 1;
	    }
	    $_;
	} @sects;
    }
    # check if default is image
    if (! $found)
    {
	@sects = map {
	    if (defined ($_->{"type"}) && $_->{"type"} eq "image"
		&& defined ($_->{"name"}) && $_->{"name"} eq $default
		&& ! $found)
	    {
		$found = 1;
		$_->{"initial"} = 1;
	    }
	    $_;
	} @sects;
    }
    # ok, take the first image section
    if (! $found)
    {
	@sects = map {
	    if (defined ($_->{"type"}) && $_->{"type"} eq "image" && ! $found)
	    {
		$found = 1;
		$_->{"initial"} = 1;
	    }
	    $_;
	} @sects;
    }

    return \@sects;
}


=item
C<< ($global_ref, $sections_ref) Bootloader::Core->ParseMenuFileLines($separator, \@start_keys, \@lines); >>

Parses the lines of the file containing the bootloader menu, and creates the hashes representing
the global settings and the sections. As arguments takes the separator of the key and value in the
file, reference to a list starting a new section, and reference to the list of lines. Returns
reference to a hash representing global options and reference to a list representing all sections.

=cut

# (map<string,any> global, list<map<string,any>> sections) ParseMenuFileLines
#   (string separator, list<string> section_start_keys, list<string> lines)
sub ParseMenuFileLines
{
  my $self = shift;
  my $separator = shift;
  my $section_starts_ref = shift;
  my @lines = @{+shift};

  @lines = $self->ProcessMenuFileLines (\@lines, $separator);
  my @sects = @{$self->SplitLinesToSections (\@lines, $section_starts_ref)};
  my @global = @{+shift @sects};

  @sects = map {
    $self->milestone(
      "section lines to convert:\n\{\n" .
      join("\n", map { "  '$_->{key}'" . " => " . "'$_->{value}'," } @$_) .
      "\n\}"
    );

    my $s = $self->Section2Info($_);

    $self->milestone(
      "parsing result:\n\{\n" .
      join("\n", map { m/^__/ ? () : "  '$_'" . " => " . "'$s->{$_}'," } keys %$s) .
      "\n\}"
    );

    $s;
  } @sects;

  $self->MangleSections(\@sects, \@global);
  my @sect_names = map { $_->{name} || "" } @sects;
  my %global = %{$self->Global2Info (\@global, \@sect_names)};
  @sects = @{$self->MarkInitialSection (\@sects, $global{default} || "")};

  return (\%global, \@sects);
}


=item
C<< $lines_ref = Bootloader::Core->PrepareMenuFileLines (\@sectinos, \%global, $indent, $separator); >>

takes the information about sections and creates the list of lines to be written
to the file holding the boot menu. As arguments, takes reference to the list of sections,
reference to hash holding global options, indentation of the lines inside sections
and separator to be used between key and value in the configuration file. Returns the
list of lines to be written to the configuration file.

=cut

# list<string> PrepareMenuFileLines (list<map<string,any>> sections,
#   map<string,any> global, string indent, string separ)
sub PrepareMenuFileLines {
    my $self = shift;
    my @sects = @{+shift};
    my %glob = %{+shift};
    my $indent = shift;
    my $separ = shift;

    my @sect_names = map {
	$_->{"name"} || "";
    } @sects;
    @sects = map {
	my $sect_ref = $self->Info2Section ($_, \@sect_names);
	$sect_ref;
    } @sects;
    my @global = @{$self->Info2Global (\%glob, \@sect_names)};
    unshift @sects, \@global;
    my @lines = $self->MergeSectionsLines (\@sects, $indent);
    return $self->CreateMenuFileLines (\@lines, $separ);
}


# void ParseLines (map<string,list<string>>)
# must be overridden
sub ParseLines {
    my $self = shift;
    $self->error("Running generic function, it should never be called");
    return undef;
}

# map<string,list<string>> CreateLines ()
# must be overridden
sub CreateLines {
    my $self = shift;
    $self->error("Running generic function, it should never be called");
    return {};
}

=item
C<< $status = Bootloader::Core->UpdateBootloader (); >>

Updates the settings in the system. Backs original configuration files
up and replaces them with the ones with the '.new' suffix. If other operations
are needed to make the change effect, they must be done
in the loader-specific package (eg. not needed for GRUB, run
'/sbin/lilo' for LILO).
Returns undef on fail, 1 on success.

=cut

# boolean UpdateBootloader ()
sub UpdateBootloader
{
  my $self = shift;

  my $files_ref = $self->ListFiles();
  my @files = @{$files_ref};
  my $ok = 1;

  $self->milestone("Files to update:", $files_ref);

  foreach my $file (@files) {
    next unless -f "$file.new";

    # backup file only if is exists and previos backup is older than 6 hours
    if(-f $file) {
      if(-f "$file.old") {
        my $mtime = time - (stat "$file.old")[9];
        if($mtime > 6 * 3600) {
          rename $file, "$file.old";
          $self->milestone("rename $file -> $file.old");
        }
      }
      else {
        rename $file, "$file.old";
        $self->milestone("rename $file -> $file.old");
      }
    }

    $self->milestone("rename $file.new -> $file");

    if(!rename("$file.new", $file)) {
      $self->error("Error occurred while updating $file: $!");
      $ok = undef;
    }
  }

  return $ok;
}

=item
C<< $status = Bootloader::Core->RunCommand ($command, $try); >>

Runs specified command.
If $try is set, ignores command errors and returns 0.
Otherwise it returns the exit code of the command.
command, exit code, and output are stored internally in $self->{last_command}.

=cut

# integer RunCommand (string command, integer try)
sub RunCommand
{
  my $self = shift;
  my $command = shift;
  my $try = shift;

  my $ret;
  my $output;

  if(open my $f, "($command) 2>&1 |") {
    local $/;
    $output = <$f>;
    close $f;
    $ret = $? >> 8;
    chomp $output;
    $output .= "\n";
  }
  else {
    $ret = 127;
    $output = "$command: " . ($! == 13 ? $! : "command not found") . " \n";
  }

  $self->{last_command} = { cmd => $command, exit => $ret, out => $output};

  if(!$ret || $try) {
    $self->milestone("'$command' = $ret, output:", $output);
    $ret = 0;
  }
  else {
    $self->error("'$command' failed with exit code $ret, output:", $output);
  }

  return $ret;
}

=item
C<< $mapping_ref = Bootloader::Core->GetDeviceMapping (); >>

Returns the device mapping as a reference to a hash, where
key is the UNIX device identification and value is the firmware
device identification.

=cut

# map<string,string> GetDeviceMapping ()
sub GetDeviceMapping {
    my $self = shift;

    return $self->{"device_map"};
}

=item
C<< $status = Bootloader::Core->SetDeviceMapping (\%mapping_ref); >>

Sets the device mapping. As argument takes a hash reference, where
key is UNIX device identificatino and value is the firmware
devide identification. Returns undef on fail, defined nonzero value
otherwise.

=cut

# void SetDeviceMapping (map<string,string> device_mapping)
sub SetDeviceMapping {
    my $self = shift;
    my $devmap_ref = shift;

    $self->debug("TRACE");
    $self->{"device_map"} = $devmap_ref;
    while  ( my ($key, $value) = each (%$devmap_ref)){
        $self->milestone("device_mapping: $key <=> $value");
    }
    return 1;
}

=item
C<< $settings_ref = Bootloader::Core->GetSettings (); >>

returns the complete settings in a hash. Does not read the settings
from the system, but returns internal structures.

=cut

# map<string,any> GetSettings ()
sub GetSettings
{
  my $self = shift;

  my $ret = {};

  for ("global", "exports", "sections", "device_map") {
    $ret->{$_} = $self->{$_} if defined $self->{$_};
  }

  $self->milestone("ret =", $ret);

  return $ret;
}


=item
C<< $status = Bootloader::Core->SetSettings (\%settings); >>

Stores the settings in the given parameter to the internal
structures. Does not touch the system.
Returns undef on fail, defined nonzero value on success.

=cut

# void SetSettings (map<string,any> settings)
sub SetSettings {
    my $self = shift;
    my %settings = %{+shift};

    foreach my $key ("global", "imports", "sections", "device_map")
    {
	if (defined ($settings{$key}))
	{
	    $self->{$key} = $settings{$key};
            if ($key eq "sections")
            {
              foreach my $section (@{$settings{$key}})
              {
                $self->milestone("store: $key:" . join( " - ", %{$section}||""));
              }
            }
            elsif ($key eq "global" or $key eq "device_map")
            {
              $self->milestone("store: $key:" . join( ",", %{$settings{$key}} || ""));
            }
            else
            {
              $self->milestone("store: $key:" . join( ",", $settings{$key}||""));
            }
        }
    }
    return 1;
}

=item
C<< $path = Bootloader::Core->ConcatPath ($path1, $path2); >>

Concatenates two path elements, added slash inbeteween if needed. Returns
the two elements (arguments) concatenated.

=cut

# string ConcatPath (string path1, string path2)
sub ConcatPath($$$) {
    my $self = shift;
    my $a = shift;
    my $b = shift;

    if (!length($a) || !length($b) || $a =~ m#/$# || $b =~ m#^/#)
    {
	return $a . $b;
    }
    else
    {
	return $a . '/' . $b;
    }
}

=item
C<< $crosses = Bootloader::Core->SymlinkCrossesDevice ($path); >>

Checks if specified path is a symlink and if it links to path on a different
device. As argument takes a path, returns 1 if path is a symlink and crosses
device, 0 otherwise.

=cut

#boolean SymlinkCrossesDevice (string path)
sub SymlinkCrossesDevice($$) {
    my $self = shift;
    my $path = shift;

    my ($dev_file,)  = stat($path);
    my ($dev_symlink,) = lstat($path);
    $self->milestone("dev_file: $dev_file, dev_symlink: $dev_symlink");

    if (defined ($dev_file) && defined ($dev_symlink))
    {
	return $dev_file != $dev_symlink;
    }
    return 0;
}

=item
C<< $resolved = Bootloader::Core->ResolveCrossDeviceSymlinks ($path); >>

Resolves all symlinks crossing device in the path. As argument, takes
a path possibly with symlinks crossing device, returns the same path
with these symlinks resolved.

=cut

#string ResolveCrossDeviceSymlinks (string path)
sub ResolveCrossDeviceSymlinks($$) {
    my $self = shift;
    my $path = shift;
    my $resolved = '';
    my $readlink;

    while ($path =~ s#^(/*)[^/]+##) {
	$self->milestone("path: $path, \$1: $1, \$&: $&");

	my $here = $self->ConcatPath($resolved, $&);
	$self->milestone("here: $here, resolved: $resolved");

	if (-l $here && ($readlink = readlink $here) =~ /\//) {
	    $self->milestone("readlink: $readlink");
	    $resolved = ""
	    	if ($readlink =~ m#^/#);
	    $self->milestone("\$&: $&");
	    $path = $self->ConcatPath(($1 || '') . $readlink, $path);
	    $self->milestone("path: $path, \$1: $1");
	    next;
	}
	$resolved = $self->ConcatPath($resolved, $&);
	$self->milestone("resolved: $path, \$&: $&");
    }
    $resolved = $self->ConcatPath($resolved, $path);
    $self->milestone("returns resolved: $resolved, path: $path");
    return $self->CanonicalPath($resolved);
}

=item
C<< $canonical = Bootloader::Core->CanonicalPath ($path); >>

Makes a "beautification" of the path given as an argument, returns the
path.

=cut

#string CanonicalPath (string path)
sub CanonicalPath($$) {
    my $self = shift;
    my $path = shift;

#    if ($path !~ m#^/#) {
#	$path = $self->ConcatPath(getcwd, $path);
#    }
    while ($path =~ s#/[^/]+/\.\.(/|$)#$1#) { }
    while ($path =~ s#/\.(/|$)#$1#) { }
    while ($path =~ s#//#/#) { }
    $self->milestone("ret path: $path");
    return $path;
}

=item
C<< $real = Bootloader::Core->RealFileName ($filename); >>

Gets the file name with all symlinks resolved and with some "beautification"
(eg. removing duplicate slashes). Takes one argument - path, returns it
after symlniks resolved.

=cut

#string RealFileName (filename)
sub RealFileName {
    my $self = shift;
    my $filename = shift;

    return "" unless $filename;

    my $ret = "";
    if ($self->{"resolve_symlinks"})
    {
	$self->milestone("resolve_symlinks:" . $self->{"resolve_symlinks"});
	$ret = $self->CanonicalPath($self->ResolveCrossDeviceSymlinks ($filename));
    }
    else
    {
	$ret = $self->CanonicalPath($filename);
    }
    $self->milestone("Filename $filename after resolving symlinks: $ret");
    return $ret;
}

=item
C<< Bootloader::Core->MangleSections (\@sections, \%global); >>

In this version does not do anything, is needed just to be overridden
by the ZIPL implementation where global stuff is in sections

=cut

#MangleSections (list &sections, map &global);
sub MangleSections {
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
