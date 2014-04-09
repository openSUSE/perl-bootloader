#! /usr/bin/perl -w
#
# Bootloader logging class
#

=head1 NAME

Bootloader::Logger - library for logging


=head1 PREFACE

This package is the private logging part. It doesn't use existing logging
library, because it must handle logging via yast and also logging during
kernel update. Also target is to have minimum dependencies for inst-sys.


=head1 SYNOPSIS

C<< use Bootloader::Logger; >>

C<< $obj_ref = Bootloader::Logger->new (); >>

=head1 DESCRIPTION

=over 2

=cut


package Bootloader::Logger;

use strict;
use POSIX qw ( strftime uname );
use Bootloader::Path;

use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
$Data::Dumper::Terse = 1;
$Data::Dumper::Indent = 1;

my (@log_level_name, %log_level_num);

@log_level_name = qw ( debug milestone warning error );
@log_level_num{@log_level_name} = ( 0 .. 100 );


=item
C<< $obj_ref = Bootloader::Logger->new (); >>

Creates an instance of the Bootloader::Logger class.

=cut


sub StartLog
{
  my $self = shift;

  delete $self->{logger}{log_fh};
  delete $self->{logger}{log_fh_yast};
  delete $self->{logger}{log_is_stderr};

  $self->{logger}{session_id} = $self->{session_id};
  $self->{logger}{log_level} = $ENV{Y2DEBUG} ? 0 : 1;

  $self->{logger}{yast_prefix} = ((uname())[1] || "unknown") . "($$) [pbl]";

  # if PBL_DEBUG is set log to STDERR, else to logfile

  if(!$ENV{PBL_DEBUG} && open my $f, ">>", Bootloader::Path::Logname()) {
    my $tmp = select $f;
    $| = 1;
    select $tmp;
    $self->{logger}{log_fh} = $f;
  }

  # also log to yast log if called from yast
  if($self->{session_id} =~ /^yast-/ && open my $f, ">>", Bootloader::Path::LognameYaST()) {
    my $tmp = select $f;
    $| = 1;
    select $tmp;
    $self->{logger}{log_fh_yast} = $f;
  }

  if(!$self->{logger}{log_fh} && open my $f, ">&STDERR") {
    $self->{logger}{log_fh} = $f;
    $self->{logger}{log_is_stderr} = 1;
  }

  return $self;
}


sub CloneLog
{
  my $self = shift;
  my $src = shift;

  $self->{logger} = $src->{logger};

  return $self;
}


sub SetLogLevel
{
  my $self = shift;
  my $level = shift;

  my $l = $level =~ /^\d+$/ ? $level : $log_level_num{$level};

  $self->{logger}{log_level} = $l if defined $l;
}


sub GetLogRecords
{
  my $self = shift;

  return [];
}


# dummy function; just clears internal log buffer
sub DumpLog
{
  my $self = shift;

  $self->GetLogRecords();
}


sub __log
{
  my $self = shift;
  my $level = shift;
  my $message = shift;

  my $level_name = $log_level_name[$level];

  return if $level < $self->{logger}{log_level};

  my $line = (caller(1))[2];
  my $func = (caller(2))[3];
  $func =~ s/^Bootloader:://;

  $func = 'main' if $func eq '';

  my $id = $self->{logger}{session_id} || "???-0000.0";

  # we split the log line a bit into prefix & message: prefix is not logged by yast

  my $prefix = strftime("%Y-%m-%d %H:%M:%S", localtime) . " <$level>";

  $message = "$id $func.$line: $message";

  if($_[0]) {
    my $x = $_[0];
    if(ref $x) {
      chomp($x = Dumper $x);
    }
    else {
      chomp $x;
      $x = "<<<<<<<<<<<<<<<<\n$x\n>>>>>>>>>>>>>>>>";
    }

    $message .= "\n$x";
  }

  if($self->{logger}{log_fh}) {
    print { $self->{logger}{log_fh} } "$prefix $message\n";
  }

  if($self->{logger}{log_fh_yast}) {
    print { $self->{logger}{log_fh_yast} } "$prefix $self->{logger}{yast_prefix} $message\n";
  }

  # log error messages to STDERR (unless we already did)

  if(!$self->{logger}{log_is_stderr} && $level > 2) {
    print STDERR "Perl-Bootloader: $prefix $message\n";
  }
}


sub debug
{
  my $self = shift;
  my $message = shift;

  $self->__log(0, $message, @_);
}


sub milestone
{
  my $self = shift;
  my $message = shift;

  $self->__log(1, $message, @_);
}


sub warning
{
  my $self = shift;
  my $message = shift;

  $self->__log(2, "Warning: $message", @_);
}


sub error
{
  my $self = shift;
  my $message = shift;

  $self->__log(3, "Error: $message", @_);
}


1;
