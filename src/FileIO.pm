#! /usr/bin/perl -w
#
# Bootloader file IO class
#

=head1 NAME

Bootloader::FileIO - functions for accessing files


=head1 PREFACE

XXX

=head1 SYNOPSIS

C<< use Bootloader::FileIO; >>

C<< $files_ref = Bootloader::Core->ReadFiles(\@file_list); >>

C<< $lines_ref = Bootloader::Core->ReadFile($file_name); >>


=head1 DESCRIPTION

=over 2

=cut


package Bootloader::FileIO;

use strict;

use base qw ( Bootloader::Logger );


=item
C<< $files_ref = Bootloader::FileIO->ReadFiles(\@file_list); >>

Reads the list of files (passed as reference to an array of file names).
Returns a hash reference where the key is a file name and value a reference
to the list of lines of the file.

=cut

sub ReadFiles
{
  my $self = shift;
  my @filenames = @{+shift};

  my %files = ();

  for my $file (@filenames) {
    $files{$file} = $self->ReadFile($file);
  }

  return \%files;
}


=item
C<< $lines_ref = Bootloader::FileIO->ReadFile($file_name); >>

Reads a file from disk and returns a reference to an array of lines (with
newline stripped). If the file could not be read, returns undef.

=cut

sub ReadFile
{
  my $self = shift;
  my $file = shift;

  my $lines;

  if(open(my $fh, $file)) {
    @$lines = (<$fh>);
    close $fh;
    my $l = join '', @$lines;
    chomp @$lines;
    $self->milestone("$file =", $l);
  }
  else {
    $self->error("Failed to open $file: $!");
  }

  return $lines;
}


=item
C<< $lines_ref = Bootloader::FileIO->WriteFile($file, $lines); >>

Writes file to disk.
Returns 1 on success, 0 otherwise.

=cut

sub WriteFile
{
  my $self = shift;
  my $file = shift;
  my $lines = shift;
  my $ok = 1;

  my $l = join("\n", @$lines) . "\n";

  $self->milestone("$file =", $l);

  my $saved_umask = umask 0066;

  if(open(my $fh, '>', $file)) {
    print $fh $l;
    close $fh;
  }
  else {
    $self->error("Failed to open $file: $!");
    $ok = 0;
  }

  umask $saved_umask;

  return $ok;
}


1;
