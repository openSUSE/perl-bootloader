#! /usr/bin/perl -w
#
# Bootloader configuration base library
#

=head1 NAME

Bootloader::Core::EXTLINUX - EXTLINUX library for bootloader configuration


=head1 PREFACE

This package is the EXTLINUX library of the bootloader configuration

=head1 SYNOPSIS

use Bootloader::Core::EXTLINUX;

C<< $obj_ref = Bootloader::Core::EXTLINUX->new (); >>

C<< $glob_info = $Bootloader::Core::EXTLINUX->Global2Info (\@glob_lines, \@section_names); >>

C<< $status = Bootloader::Core::EXTLINUX->ParseLines (\%files, $avoid_reading_device_map); >>

C<< $sectin_info_ref = Bootloader::Core::EXTLINUX->Section2Info (\@section_lines); >>

C<< $lines_ref = Bootloader::Core::EXTLINUX->Info2Global (\%section_info, \@section_names); >>

C<< $lines_ref = Bootloader::Core::EXTLINUX->Info2Section (\%section_info); >>

C<< $files_ref = Bootloader::Core::EXTLINUX->CreateLines (); >>

C<< $line = Bootloader::Core::EXTLINUX->CreateSingleMenuFileLine ($key, $value, $separator); >>

=head1 DESCRIPTION

=over 2

=cut

package Bootloader::Core::EXTLINUX;

use strict;

use Bootloader::Core;
our @ISA = ('Bootloader::Core');

use Bootloader::Path;

#module interface
sub GetOptions{
	my $loader = shift;

	my %options;
	$options{"global_options"} = {
		timeout   => "",
		default   => "",
		ontimeout => "",
		menu      => {
			title => "",
		},
		prompt    => "bool",
	};

	$options{"section_options"} = {
		image_name     => "",
		image_image    => "path",
		image_append   => "",
		image_initrd   => "path",
		image_fdtdir   => "path",
		image_fdt      => "",
		image_menu     => {
			title => "",
		},

		other_name     => "",
		other_localboot=> "bool",
		other_menu     => {
			title => "",
		},
	};

	$loader->{"options"}=\%options;
}

=item
C<< Bootloader::Core::EXTLINUX->ParseMenuEntry($line, \%ret); >>

Parses "MENU SUBCMD" command in the configuration file.

=cut

sub ParseMenuEntry {
	my $self = shift;
	my $value = shift;
	my $ret = shift;

	my ($subkey, $subval) = split(/\s+/,$value,2);
	$subkey = lc($subkey);
	if (exists $ret->{menu}) {
		$ret->{menu}->{$subkey} = $subval;
	} else {
		my %menu_hash = ($subkey => $subval);
		$ret->{menu} = \%menu_hash;
	}
}

=item
C<< $obj_ref = Bootloader::Core::EXTLINUX->new (); >>

Creates an instance of the Bootloader::Core::EXTLINUX class.

=cut

sub new
{
	my $self = shift;
	my $ref = shift;
	my $old = shift;

	my $loader = $self->SUPER::new($ref, $old);
	bless($loader);

	$loader->GetOptions();

	$loader->milestone("Created EXTLINUX instance");

	return $loader;
}

=item
C<< $files_ref = Bootloader::Core::EXTLINUX->ListFiles (); >>

Returns the list of the configuration files of the bootloader
Returns undef on fail

=cut

# list<string> ListFiles ();
sub ListFiles {
	my $self = shift;

	return [ Bootloader::Path::Extlinux_conf() ];
}

=item
C<< $glob_info = $Bootloader::Core::EXTLINUX->Global2Info (\@glob_lines, \@section_names); >>

Gets the general information from the global section of the menu file. This information
usually means the default section, timeout etc. As argument it takes
a reference to the list of hashes representing lines of the section, returns a reference
to a hash containing the important information.

=cut

# map<string,string> Global2Info (list<map<string,any>> global, list<string>sections)
sub Global2Info {
	my $self = shift;
	my @lines = @{+shift};
	my @sections = @{+shift};
	my %ret = ();
	my $go = $self->{"options"}{"global_options"};

	foreach my $line (@lines) {
		my $key   = lc($line->{"key"});
		my $value = $line->{"value"};
		next unless defined($key);
		my $type = $go->{$key} || "";

		if ($key eq "default") {
			if(grep {$_ eq $value} @sections) {
				$ret{default} = $value;
			} else {
				$self->warning("Unknown section name $value");
			}
		}
		elsif ($key eq "menu") {
			$self->ParseMenuEntry($value, \%ret);
		}
		elsif (defined ($type) and $type eq "bool") {
			$ret{$key} = "true" if int($value);
		}
		else {
			$ret{$key} = $value;
			unless (defined $go->{$key}){
				$self->warning("Unknown global key $key");
				$ret{"__broken"} = "true";
			}
		}
	}

	$ret{"__lines"} = \@lines;
	return \%ret;
}

=item
C<< $status = Bootloader::Core::EXTLINUX->ParseLines (\%files, $avoid_reading_device_map); >>

Parses the contents of all files and stores the settings in the
internal structures. As first argument, it takes a hash reference,
where keys are file names and values are references to lists, each
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

	# the only file is /boot/extlinux/extlinux.conf
	my @extlinux_conf = @{$files{Bootloader::Path::Extlinux_conf()} || []};
	(my $glob_ref, my $sect_ref) = $self->ParseMenuFileLines (0, ["LABEL"], \@extlinux_conf);

	$self->{global} = $glob_ref;
	$self->{sections} = $sect_ref;

	$self->milestone("global =", $self->{global});
	$self->milestone("sectionsl =", $self->{sections});

	return 1;
}

sub EvalSectionType {
	my $self = shift;
	my @lines = @{+shift};

	my $image = 0;
	my $localboot = 0;

	foreach my $line (@lines) {
		my $key   = lc($line->{key});
		my $value = $line->{value};

		if ($key eq 'linux') {
			$image++;
		}
		elsif ($key eq 'localboot' and int($value)) {
			$localboot++;
		}
	}

	return "image" if($image);
	return "other" if($localboot);
	return "custom";
}

=item
C<< $sectin_info_ref = Bootloader::Core::EXTLINUX->Section2Info (\@section_lines); >>

Gets the information about the section. As argument, takes a reference to the
list of lines building the section, returns a reference to a hash containing
information about the section.


=cut

# map<string,string> Section2Info (list<map<string,any>> section)
sub Section2Info {
	my $self = shift;
	my @lines = @{+shift};
	my %ret = ();
	my $type = $self->EvalSectionType(\@lines);
	my $so = $self->{"options"}{"section_options"};

	$ret{type} = $type;

	foreach my $line (@lines) {
		my $key   = lc($line->{key});
		my $value = $line->{value};
		my $key_type = $so->{$type."_".$key} || "";

		if ($key eq 'label') {
			$key = 'name';
			my $on = $self->Comment2OriginalName(\%ret, $line->{"comment_before"});
			$ret{"original_name"} = $on if ($on ne "");
		}
		elsif ($key eq 'linux') {
			$key = 'image';
		}

		if (defined($key_type) and $key_type eq 'path') {
			$ret{$key} = $self->CanonicalPath($value);
		}
		elsif (defined($key_type) and $key_type eq 'bool') {
			$ret{$key} = 'true' if int($value);
		}
		elsif ($key eq 'menu') {
			$self->ParseMenuEntry($value, \%ret);
		}
		elsif (defined($so->{$type."_".$key})) {
			$ret{$key} = $value;
		}
	}

	$ret{"__lines"} = \@lines;
	return \%ret;
}

=item
C<< $lines_ref = Bootloader::Core::EXTLINUX->Info2Global (\%section_info, \@section_names); >>

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
	my $go = $self->{"options"}{"global_options"};
  
	# allow to keep the section unchanged
	return \@lines unless $globinfo{"__modified"} || 0;

	if (scalar (@lines) == 0) {
		@lines = (
			{ key => "MENU",      value => "TITLE openSUSE boot menu" },
			{ key => "DEFAULT",   value => "linux" },
			{ key => "ONTIMEOUT", value => "linux" },
			{ key => "PROMPT",    value => "true" },
			{ key => "TIMEOUT",   value => 1000 },
		);
	}

	@lines = map {
		my $line = $_;
		my $key = lc($line->{key});
		my $value = $line->{value};
		my $type = $go->{$key} || "";

		if (!defined $go->{$key}) {
			$line = undef;
		}
		elsif (!defined $globinfo{$key}) {
			$line = undef;
		}
		elsif ($key eq "ontimeout") {
			$line->{value} = $globinfo{default};
		}
		elsif ($key eq "menu") {
			my ($subkey, $subval) = split(/\s+/,$value,2);
			$subkey = lc($subkey);
			if (exists $globinfo{menu}->{$subkey}) {
				$line->{value} = join " ", uc($subkey), (delete $globinfo{menu}->{$subkey});
			} else {
				$line = undef;
			}
		}
		elsif (defined $type and $type eq "bool") {
			$line->{"value"} = $value eq "true" ? "1" : "0";
			delete $globinfo{$key};
		}
		else {
			$line->{value} = delete $globinfo{$key};
		}
		$line;
	} @lines;

	@lines = grep {
		defined $_;
	} @lines;

	while ((my $key, my $value) = each (%globinfo)) {
		next unless exists $go->{$key};
		my $type = $go->{$key} || "";

		if($key eq 'menu') {
			while ((my $subkey, my $subvalue) = each (%$value)) {
				push @lines, {
					"key" => uc($key),
					"value" => (join " ", uc($subkey), $subvalue),
				};
			}
			next;		
		}
		elsif (defined($type) and $type eq "bool") {
			$value = $value eq "true" ? "1" : "0";
		}
		push @lines, {
			"key" => uc($key),
			"value" => $value,
		};
	}

	return \@lines;
}

=item
C<< $line = Bootloader::Core::EXTLINUX->CreateSingleMenuFileLine ($key, $value, $separator); >>

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
		$line = "$line$equal_sep$value";
	}
	return $line;
}

=item
C<< $lines_ref = Bootloader::Core::EXTLINUX->Info2Section (\%section_info); >>

Takes the info about the section and uses it to construct the list of lines.
The info about the section also contains the original lines.
As parameter, takes the section info (reference to a hash), returns
the lines (a list of hashes).

=cut

# list<map<string,any>> Info2Section (map<string,string> info)
sub Info2Section {
	my $self = shift;
	my %sectinfo = %{+shift};
	my $so = $self->{"options"}{"section_options"};
	my @lines = @{$sectinfo{"__lines"} || []};
	my $type = $sectinfo{"type"} || "";

	return $self->FixSectionLineOrder(\@lines, ["LABEL","LINUX"]) unless ($sectinfo{"__modified"} || 0);
	return \@lines if ($type ne "image" and $type ne "other");

	@lines = map {
		my $line = $_;
		my $key = lc($line->{key});
		my $value = $line->{value};
		my $key_type = $so->{$type."_".$key} || "";

		if ($key eq "label") {
			$line = $self->UpdateSectionNameLine ($sectinfo{"name"}, $line, $sectinfo{"original_name"});
			delete ($sectinfo{"name"});
		}
		elsif ($key eq "linux") {
			$line->{value} = delete $sectinfo{image};
		}
		elsif (defined $key_type and $key_type eq "bool") {
			$line->{"value"} = $value eq "true" ? "1" : "0";
			delete $sectinfo{$key};
		}
		elsif($key eq "menu") {
			my ($subkey, $subval) = split(/\s+/,$value,2);
			$subkey = lc($subkey);
			if (exists $sectinfo{menu}->{$subkey}) {
				$line->{value} = join " ", uc($subkey), (delete $sectinfo{menu}->{$subkey});
			} else {
				$line = undef;
			}
		}
		else {
			$line->{value} = delete $sectinfo{$key};
		}
		$line;
	} @lines;

	@lines = grep {
		defined $_;
	} @lines;

	while ((my $key, my $value) = each (%sectinfo)) {
		next unless defined($so->{$type."_".$key});
		my $key_type = $so->{$type."_".$key} || "";

		if ($key eq 'name') {
			my %line = ("key" => "LABEL");
			push @lines, $self->UpdateSectionNameLine ($value, \%line, $sectinfo{"original_name"});
			next;
		}
		elsif ($key eq 'image') {
			push @lines, {
				"key" => "LINUX",
				"value" => $value,
			};
			next;
		}
		elsif ($key eq 'menu') {
			while ((my $subkey, my $subvalue) = each (%$value)) {
				push @lines, {
					"key" => uc($key),
					"value" => (join " ", uc($subkey), $subvalue),
				};
			}
			next;		
		}
		elsif (defined($key_type) and $key_type eq 'bool') {
			$value = $value eq "true" ? "1" : "0";
		}
		push @lines, {
			"key" => uc($key),
			"value" => $value,
		};
	}

	return $self->FixSectionLineOrder (\@lines, ["LABEL","LINUX"]);
}

=item
C<< $files_ref = Bootloader::Core::EXTLINUX->CreateLines (); >>

creates contents of all files from the internal structures.
Returns a hash reference in the same format as argument of
ParseLines on success, or undef on fail.

=cut

# map<string,list<string>> CreateLines ()
sub CreateLines {
	my $self = shift;

	my $extlinux_conf = $self->PrepareMenuFileLines (
		$self->{"sections"},
		$self->{"global"},
		"        ", " ");

	return undef if !defined $extlinux_conf;

	return {
		Bootloader::Path::Extlinux_conf() => $extlinux_conf,
	}
}

=item
C<< $status = Bootloader::Core::EXTLINUX->InitializeBootloader (); >>

The function returns 0 always.
Currently, only EXTLINUX + U-Boot is supported, no bootloader initialization is required.

=cut

# boolean InitializeBootloader ()
sub InitializeBootloader {
	my $self = shift;

	return 0;
}

1;

