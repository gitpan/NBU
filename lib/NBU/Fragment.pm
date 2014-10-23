#
# Copyright (c) 2002 Paul Winkeler.  All Rights Reserved.
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.
#
package NBU::Fragment;

use strict;
use Carp;

BEGIN {
  use Exporter   ();
  use AutoLoader qw(AUTOLOAD);
  use vars       qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS $AUTOLOAD);
  $VERSION =	 do { my @r=(q$Revision: 1.7 $=~/\d+/g); sprintf "%d."."%02d"x$#r,@r };
  @ISA =         qw();
  @EXPORT =      qw();
  @EXPORT_OK =   qw();
  %EXPORT_TAGS = qw();
}

sub new {
  my $Class = shift;
  my $fragment = { };

  bless $fragment, $Class;

  if (@_) {
    $fragment->{NUMBER} = shift;
    $fragment->{IMAGE} = shift;
    $fragment->{VOLUME} = shift;
    $fragment->{OFFSET} = shift;
    $fragment->{SIZE} = shift;
    $fragment->{DWO} = shift;
    $fragment->{FILENUMBER} = shift;
    $fragment->{BLOCKSIZE} = shift;
  }

  return $fragment;
}

sub number {
  my $self = shift;

  return $self->{NUMBER};
}

#
# Volume offset data is stored in blocks but reported back in KBytes
sub offset {
  my $self = shift;

  return (($self->{OFFSET} * $self->{BLOCKSIZE})/1024);
}

sub size {
  my $self = shift;

  return $self->{SIZE};
}

sub volume {
  my $self = shift;

  return $self->{VOLUME};
}

sub fileNumber {
  my $self = shift;

  return $self->{FILENUMBER};
}

sub driveWrittenOn {
  my $self = shift;

  return $self->{DWO};
}

sub blockSize {
  my $self = shift;

  return $self->{BLOCKSIZE};
}

sub image {
  my $self = shift;

  return $self->{IMAGE};
}

1;

__END__
