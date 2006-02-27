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

C<< $status = Bootloader::Core::ELILO->ParseLines (\%files); >>

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

#module interface

=item
C<< $obj_ref = Bootloader::Core::ELILO->new (); >>

Creates an instance of the Bootloader::Core::ELILO class.

=cut

sub new {
    my $self = shift;

    my $loader = $self->SUPER::new ();
    $loader->{"default_global_lines"} = [
	{ "key" => "timeout", "value" => 80 },
	{ "key" => "read-only", "value" => "" },
	{ "key" => "relocatable", "value" => "" },
    ];
    bless ($loader);
    $loader->l_milestone ("ELILO::new: Created ELILO instance");
    return $loader;
}

=item
C<< $files_ref = Bootloader::Core::ELILO->ListFiles (); >>

Returns the list of the configuration files of the bootloader
Returns undef on fail

=cut

my $default_conf = "/etc/elilo.conf";
#$default_conf = "/tmp/elilo.conf";

# list<string> ListFiles ();
sub ListFiles {
    my $self = shift;

    return [ $default_conf ];
}

# TODO document

sub FixSectionName {
    my $self = shift;
    my $label = shift;
    my $names_ref = shift;

    my $orig_label = $label;

    # then check not allowed chars
    $label =~ s/[^\w.-]/_/g;

    for (my $i = 0; $i < $#$names_ref; $i++)
    {
	if ($names_ref->[$i] eq $orig_label)
	{
	    $names_ref->[$i] = $label;
	    last;	# finish the cycle
	}
    }

    return $label;
}



=item
C<< $status = Bootloader::Core::ELILO->ParseLines (\%files); >>

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
C<< $files_ref = Bootloader::Core::ELILO->CreateLines (); >>

creates contents of all files from the internal structures.
Returns a hash reference in the same format as argument of
ParseLines on success, or undef on fail.

=cut

# map<string,list<string>> CreateLines ()
sub CreateLines {
    my $self = shift;

    if ($self->{"global"}{"__modified"} || 0) {
	my @lines = @{$self->{"global"}{"__lines"} || []};
	my @out_lines = ();
	foreach my $line_ref (@lines) {
	    push @out_lines, $line_ref;
	}
	$self->{"global"}{"__lines"} = \@out_lines;
    }
    foreach my $sect_ref (@{$self->{"sections"}} ) {
	my %sect = %{$sect_ref};
        my $append = undef;
        my $title = undef;
        my $kernel = undef;
#        foreach my $skey (keys %sect) {
#	    printf STDERR "%s: %s\n", $skey, $sect{$skey};
#        }
if(0){
        foreach my $opt_ref (@{$sect_ref->{"__lines"}|| []}) {
          my $key = $opt_ref->{"key"};
          my $val = $opt_ref->{"value"};
#	  print STDERR "$key = '$val'\n";
          if($key eq "image") {
            $kernel = $val;
          } elsif ($key eq "label") {
            $title = $val;
          } elsif ($key eq "append") {
            $append = $val;
          }
        }
}
	next unless defined( $title = $sect{"name"});
#        if( defined( $append) ) {
#          print STDERR "SECTION $title has APPEND: '$append'\n";
#	} else {
#          print STDERR "SECTION $title has NO APPEND!\n";
#        }
#	print STDERR "\n";
     }

    # create /etc/elilo.conf lines
    my $elilo_conf = $self->PrepareMenuFileLines (
	$self->{"sections"},
	$self->{"global"},
	"    ",
	" = "
    );
    if (! defined ($elilo_conf)) {
	return undef;
    }

    return {
	$default_conf => $elilo_conf,
    }
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

    system ("mkdir -p /boot/efi/efi/SuSE") unless -d "/boot/efi/efi/SuSE";
 
    return $self->RunCommand (
	"/sbin/elilo -v",
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
