#
# Copyright (c) 2002 Paul Winkeler.  All Rights Reserved.
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.
#
package NBU::Schedule;

use strict;
use Carp;

BEGIN {
  use Exporter   ();
  use AutoLoader qw(AUTOLOAD);
  use vars       qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS $AUTOLOAD);
  $VERSION =	 do { my @r=(q$Revision: 1.6 $=~/\d+/g); sprintf "%d."."%02d"x$#r,@r };
  @ISA =         qw();
  @EXPORT =      qw();
  @EXPORT_OK =   qw();
  %EXPORT_TAGS = qw();
}

sub new {
  my $class = shift;
  my $Schedule = {
  };

  bless $Schedule, $class;

  if (@_) {
    my $name = $Schedule->{NAME} = shift;
    $Schedule->{CLASS} = shift;
  }
  return $Schedule;
}

sub name {
  my $self = shift;

  return $self->{NAME};
}

sub class {
  my $self = shift;

  return $self->{CLASS};
}

my %scheduleTypes = (
  0 => "Full",
  1 => "Differential Incremental",
  2 => "User Backup",
  3 => "User Archive",
  4 => "Cumulative Incremental",
);

1;

__END__
