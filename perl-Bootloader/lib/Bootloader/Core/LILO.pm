#! /usr/bin/perl -w
#
# Bootloader configuration base library
#

=head1 NAME

Bootloader::Core::LILO - LILO library for bootloader configuration


=head1 PREFACE

This package is the LILO library of the bootloader configuration

=head1 SYNOPSIS

use Bootloader::Core::LILO;

C<< $obj_ref = Bootloader::Core::LILO->new (); >>

C<< $files_ref = Bootloader::Core::LILO->ListFiles (); >>

C<< $status = Bootloader::Core::LILO->ParseLines (\%files); >>

C<< $files_ref = Bootloader::Core::LILO->CreateLines (); >>

C<< $status = Bootloader::Core::LILO->UpdateBootloader ($avoid_init); >>

C<< $status = Bootloader::Core::LILO->InitializeBootloader (); >>

=head1 DESCRIPTION

=over 2

=cut


package Bootloader::Core::LILO;

use strict;

use Bootloader::Core;
our @ISA = ('Bootloader::Core');

#module interface

=item
C<< $obj_ref = Bootloader::Core::LILO->new (); >>

Creates an instance of the Bootloader::Core::LILO class.

=cut

sub new {
    my $self = shift;

    my $loader = $self->SUPER::new ();
    $loader->{"default_global_lines"} = [
	{ "key" => "menu-scheme", "value" => "Wb:kw:Wb:Wb" },
	{ "key" => "timeout", "value" => 80 },
	{ "key" => "lba32", "value" => "" },
	{ "key" => "change-rules", "value" => "" },
	{ "key" => "reset", "value" => "" },
	{ "key" => "read-only", "value" => "" },
	{ "key" => "prompt", "value" => "" },
    ];
    bless ($loader);
    $loader->l_milestone ("LILO::new: Created LILO instance");
    return $loader;
}

=item
C<< $files_ref = Bootloader::Core::LILO->ListFiles (); >>

Returns the list of the configuration files of the bootloader
Returns undef on fail

=cut

# list<string> ListFiles ();
sub ListFiles {
    my $self = shift;

    return [ "/etc/lilo.conf" ];
}

# TODO document

sub FixSectionName {
    my $self = shift;
    my $label = shift;
    my $names_ref = shift;

    my $orig_label = $label;

    # first fix length
    if (length ($label) > 11 && substr (lc ($label), 0, 6) eq "linux-")
    {
	$label = substr ($label, 6);
    }
    if (length ($label) > 11)
    {
	$label = substr ($label, 0, 11);
    }

    # then check not allowed chars
    $label =~ s/[^a-zA-Z0-9_.-]/_/g;

    # and make the label unique
    if (scalar (grep {$_ eq $label} @$names_ref) > 1)
    {
	while (length ($label) > 5 && scalar (grep {$_ eq $label} @$names_ref) != 0)
	{
	    $label = substr ($label, 0, length ($label) - 1);
	}
	my $short_label = $label;
	my $index = 1;
	while (scalar (grep {$_ eq $label} @$names_ref) != 0)
	{
	    $label = $short_label . "_" . $index;
	    $index = $index + 1;
	}
    }

    #update list of section names
    my $updated = 0;
    for (my $i = 0; $i < $#$names_ref; $i++)
    {
	my $name = $names_ref->[$i];
	if ($name eq $orig_label && $updated == 0)
	{
	    $names_ref->[$i] = $label;
	    $i = $#$names_ref + 1; # to finish the cycleA
	    $updated = 1;
	}
    }

    return $label;
}

=item
C<< $status = Bootloader::Core::LILO->ParseLines (\%files); >>

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

    # the only file is /etc/lilo.conf
    my @lilo_conf = @{$files{"/etc/lilo.conf"} || []};
    (my $glob_ref, my $sect_ref) = $self->ParseMenuFileLines (
	"=",
	["image", "other"],
	\@lilo_conf
    );
    # get the device mapping from global options
    my %devmap = ();
    my $disk = undef;
    foreach my $opt_ref (@{$glob_ref->{"__lines"}|| []})
    {
	my $key = $opt_ref->{"key"};
	my $val = $opt_ref->{"value"};
	if ($key eq "disk")
	{
	    $disk = $val;
	}
	elsif ($key eq "bios" && defined ($disk))
	{
	    $val = oct ($val) - 0x80;
	    $val = "hd$val";
	    $devmap{$disk} = $val;
	    $disk = undef;
	}
    }

    $self->{"sections"} = $sect_ref;
    $self->{"global"} = $glob_ref;
    $self->{"device_map"} = \%devmap if (scalar (keys (%devmap)) > 0);
    return 1;
}

sub BiosName2ID {
    my $self = shift;
    my $fw = shift;

    $fw = substr ($fw, 2);
    $fw = $fw + 0x80;
    $fw = sprintf ("0x\%x", $fw);
    return $fw;
}

=item
C<< $files_ref = Bootloader::Core::LILO->CreateLines (); >>

creates contents of all files from the internal structures.
Returns a hash reference in the same format as argument of
ParseLines on success, or undef on fail.

=cut

# map<string,list<string>> CreateLines ()
sub CreateLines {
    my $self = shift;

    if ($self->{"global"}{"__modified"} || 0)
    {
	my @lines = @{$self->{"global"}{"__lines"} || []};
	my @out_lines = ();
	foreach my $line_ref (@lines) {
	    if ($line_ref->{"key"} eq "disk")
	    {
		push @out_lines, $line_ref;
		my $sys = $line_ref->{"value"};
		if (exists ($self->{"device_map"}{$sys}))
		{
		    my $bios = $self->BiosName2ID ($self->{"device_map"}{$sys});
		    push @out_lines, {
			"key" => "bios",
			"value" => $bios,
		    };
		    delete ($self->{"device_map"}{$sys});
		}
	    }
	    elsif ($line_ref->{"key"} ne "bios")
	    {
		push @out_lines, $line_ref;
	    }
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
    if (! defined ($lilo_conf))
    {
	return undef;
    }

    return {
	"/etc/lilo.conf" => $lilo_conf,
    }
}

=item
C<< $status = Bootloader::Core::LILO->UpdateBootloader ($avoid_init); >>

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
C<< $status = Bootloader::Core::LILO->InitializeBootloader (); >>

Initializes the firmware to boot the bootloader.
Returns undef on fail, defined nonzero value otherwise

=cut

# boolean InitializeBootloader ()
sub InitializeBootloader {
    my $self = shift;

    return 0 == $self->RunCommand (
	"/sbin/lilo",
	"/var/log/YaST2/y2log_tool_lilo"
    );
}

1;
