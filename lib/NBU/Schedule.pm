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
  $VERSION =	 do { my @r=(q$Revision: 1.10 $=~/\d+/g); sprintf "%d."."%02d"x$#r,@r };
  @ISA =         qw();
  @EXPORT =      qw();
  @EXPORT_OK =   qw();
  %EXPORT_TAGS = qw();
}

#
# The parent class, name and type of the schedule MUST be
# provided.  Next comes an optional IO stream from which to read the
# window, residence and pool data, followed by any additional attributes
# for the schedule itself.
sub new {
  my $proto = shift;
  my $schedule = {
  };

  bless $schedule, $proto;

  if (@_) {
    $schedule->{CLASS} = shift;
    $schedule->{NAME} = shift;
    $schedule->{TYPE} = shift;
  }

  if (defined(my $pipe = shift)) {

    #
    # Read in one line with 7 pairs of window start and length numbers; record them as a 7
    # element array of arrays.
    $_ = <$pipe>;  return undef if (!/^SCHEDWIN/);
    my @times = split;
    my @windows;
    for my $d (0..6) {
      $windows[$d] = [ shift @times, shift @times ];
    }
    $schedule->{WINDOWS} = \@windows;

    $_ = <$pipe>;  return undef if (!/^SCHEDRES/);
    my (@residences) = split;
    $schedule->{STUNIT} = NBU::StorageUnit->byLabel($residences[0]) if ($residences[0] ne "*NULL*");

    $_ = <$pipe>;  return undef if (!/^SCHEDPOOL/);
    my (@pools) = split;
    $schedule->{POOL} = NBU::Pool->byName($pools[0]) unless ($pools[0] eq "*NULL*");

    $schedule->{MAXMPX} = shift;
    $schedule->{FREQUENCY} = shift;
    my $retentionLevel = shift;
    $schedule->{RETENTION} = NBU::Retention->byLevel($retentionLevel);
  }

  return $schedule;
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
  0 => "FULL",
  1 => "INCR",
  2 => "UBAK",
  3 => "UARC",
  4 => "CINC",
);
sub type {
  my $self = shift;

  return $scheduleTypes{$self->{TYPE}};
}

sub frequency {
  my $self = shift;

  return $self->{FREQUENCY};
}

sub maximumMPX {
  my $self = shift;

  return $self->{MAXMPX};
}

sub retention {
  my $self = shift;

  return $self->{RETENTION};
}

sub pool {
  my $self = shift;

  return defined($self->{POOL}) ? $self->{POOL} : $self->class->pool;
}

sub storageUnit {
  my $self = shift;

  return defined($self->{STUNIT}) ? $self->{STUNIT} : $self->class->storageUnit;
}

1;

__END__
