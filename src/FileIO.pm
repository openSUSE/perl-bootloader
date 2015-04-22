#! /usr/bin/perl -w
#
# Bootloader file IO class
#

=head1 NAME

Bootloader::FileIO - functions for accessing files


=head1 PREFACE

This package provides basic file-i/o functions.

=head1 SYNOPSIS

C<< use Bootloader::FileIO; >>

C<< $files_ref = Bootloader::FileIO->ReadFiles(\@file_list); >>

C<< $lines_ref = Bootloader::FileIO->ReadFile($file_name); >>

C<< $lines_ref = Bootloader::FileIO->ReadFileUnicode($file_name); >>

C<< $lines_ref = Bootloader::FileIO->ReadFileRaw($file_name); >>

C<< $number = Bootloader::FileIO->ReadNumber($file_name); >>

C<< $lines_ref = Bootloader::FileIO->WriteFile($file, $lines); >>

C<< $lines_ref = Bootloader::FileIO->WriteFileUnicode($file, $data); >>

C<< $lines_ref = Bootloader::FileIO->WriteFileRaw($file, $data); >>

=head1 DESCRIPTION

=over 2

=cut


package Bootloader::FileIO;

use strict;

use base qw ( Bootloader::Logger );

# remap invalid 8-bit input data to this codepoint
my $utf8_remap_codepoint = 0x101000;

# private helper to convert a byte-stream into valid utf8
sub u_decode;

# private helper to convert utf8 back into byte-stream
sub u_encode;


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
newline stripped).
If the file could not be read, returns undef.

=cut

sub ReadFile
{
  my $self = shift;
  my $file = shift;

  my $lines;

  my $f = $self->ReadFileUnicode($file);

  if($f) {
    chomp $f;
    $lines = [ split /\n/, $f, -1 ];
  }

  $self->debug("lines =", $lines);

  return $lines;
}


=item
C<< $lines_ref = Bootloader::FileIO->ReadFileUnicode($file_name); >>

Reads a file from disk and returns its content.
Some special processing is done to ensure it returns proper Unicode data.
If the file could not be read, returns undef.

=cut

sub ReadFileUnicode
{
  my $self = shift;
  my $file = shift;

  return $self->ReadFileRaw($file, 1);
}


=item
C<< $lines_ref = Bootloader::FileIO->ReadFileRaw($file_name); >>

Reads a file from disk and returns its content.
If the file could not be read, returns undef.

=cut

sub ReadFileRaw
{
  my $self = shift;
  my $file = shift;
  my $uni_decode = shift;

  my $res;
  my $utf8_ok = 1;

  if(open(my $fh, $file)) {
    # we read per-line so we don't have to treat the whole file specially
    # when just a single char is wrong
    while(<$fh>) {
      if($uni_decode) {
        my $x = u_decode($_);
        $utf8_ok &&= $x->[1];
        $res .= $x->[0];
      }
      else {
        $res .= $_;
      }
    }
    close $fh;

    if(!$utf8_ok) {
      $self->warning("$file: contains non-utf8 chars");
    }

    $self->milestone("$file =", $res);
  }
  else {
    $self->error("Failed to open $file: $!");
  }

  return $res;
}


=item
C<< $lines_ref = Bootloader::FileIO->ReadNumber($file_name); >>

Reads a file and expects the first line to start with a number.

=cut

sub ReadNumber
{
  my $self = shift;
  my $file = shift;

  open(my $fd, $file);
  my $num = <$fd> + 0;
  close $fd;

  return $num;
}


=item
C<< $lines_ref = Bootloader::FileIO->WriteFile($file, $lines); >>

Writes Unicode text in $lines to $file.
Returns 1 on success, 0 otherwise.

=cut

sub WriteFile
{
  my $self = shift;
  my $file = shift;
  my $lines = shift;

  return $self->WriteFileUnicode($file, join("\n", @$lines) . "\n");
}


=item
C<< $lines_ref = Bootloader::FileIO->WriteFileUnicode($file, $data); >>

Writes Unicode text $data to $file.
Returns 1 on success, 0 otherwise.

=cut

sub WriteFileUnicode
{
  my $self = shift;
  my $file = shift;
  my $data = shift;
  my $ok = 1;

  $self->milestone("$file =", $data);

  return $self->WriteFileRaw($file, u_encode($data));
}


=item
C<< $lines_ref = Bootloader::FileIO->WriteFileRaw($file, $data); >>

Writes $data to $file.
Returns 1 on success, 0 otherwise.

=cut

sub WriteFileRaw
{
  my $self = shift;
  my $file = shift;
  my $data = shift;
  my $ok = 1;

  my $saved_umask = umask 0066;

  if(open(my $fh, '>', $file)) {
    print $fh $data;
    if(!close($fh)) {
      $self->error("Failed to close $file: $!");
      $ok = 0;
    }
  }
  else {
    $self->error("Failed to open $file: $!");
    $ok = 0;
  }

  umask $saved_umask;

  return $ok;
}


# Convert binary data into well-formed utf8 data.
#
# We are not allowed to use Encode, so we do our own malformed-utf8 handling
# here and remap invalid 8-bit input data to codepoint U+101000-U1010FF
# which is within a private-use range.
#
# u_encode() reverses this process.
#
# Returns a ref to an array that holds the decoded string and a tag
# indicating whether it was valid utf8.
#
sub u_decode
{
  my $s = $_[0];
  my $l = length $s;
  my $p = 0;
  my $u;
  my $ok;

  # if it's valid utf8, just return
  return [ $s, 1 ] if utf8::decode($s);

  no warnings 'utf8';

  # what we do here is processing the utf8 data step-by-step using perl's
  # unpack() function
  # if we find a non-utf8 sequence, we return the first byte and map it to
  # $utf8_remap_codepoint + X
  while($p < $l) {
    # add bytes until unpack() says it's utf8; give up at 8 bytes length
    for($ok = 0, my $i = 1; $i < 8 && $i <= $l - $p; $i++) {
      my $x = (unpack "C0U*", substr($s, $p, $i))[0];
      if($x) {
        # ok: return unicode char and continue
        $u .= pack "U", $x;
        $p += $i;
        $ok = 1;
        last;
      }
    }

    if(!$ok) {
      # not ok: return one byte and continue
      $u .= pack("U", $utf8_remap_codepoint + ord(substr $s, $p, 1));
      $p++;
    }
  }

  return [ $u, 0 ];
}


# Convert utf8 data back to binary data.
#
# This is the reverse of u_decode().
#
sub u_encode
{
  my $x;

  for (unpack "U*", $_[0]) {
    if(
      $_ >= $utf8_remap_codepoint &&
      $_ <= $utf8_remap_codepoint + 0xff
    ) {
      $x .= chr($_ - $utf8_remap_codepoint);
    }
    else {
      my $z = pack "U", $_;
      # important: ensure perl removes its internal utf8 tag
      utf8::encode($z);
      $x .= $z;
    }
  }

  return $x;
}


1;
