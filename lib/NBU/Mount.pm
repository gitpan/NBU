#
# Copyright (c) 2002 Paul Winkeler.  All Rights Reserved.
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.
#
package NBU::Mount;

use strict;
use Carp;

use NBU::Drive;

BEGIN {
  use Exporter   ();
  use AutoLoader qw(AUTOLOAD);
  use vars       qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS $AUTOLOAD);
  $VERSION =	 do { my @r=(q$Revision: 1.8 $=~/\d+/g); sprintf "%d."."%02d"x$#r,@r };
  @ISA =         qw();
  @EXPORT =      qw();
  @EXPORT_OK =   qw();
  %EXPORT_TAGS = qw();
}

sub new {
  my $class = shift;
  my $mount = {
  };

  bless $mount, $class;

  if (@_) {
    my ($job, $volume, $drive, $tm) = @_;

    #
    # The bpdbjobs output, for example, is devoid of drive
    # references hence we may not be able to record an actual
    # mount event at this time...
    if (defined($drive)) {
      $mount->drive($drive)->use($mount, $tm);
      $volume->mount($mount, $drive, $tm);
    }

    $mount->{JOB} = $job;
    $mount->{MEDIA} = $volume;
    $mount->{MOUNTTIME} = $tm;
    $mount->{MOUNTDELAY} = $tm - $volume->selected
      if ($volume->selected);

  }

  return $mount;
}

sub job {
  my $self = shift;

  return $self->{JOB};
}

sub unmount {
  my $self = shift;
  my $job = $self->{JOB};

  my $tm = $self->{UNMOUNTTIME} = shift;

  if ($job->mount == $self) {
    $job->mount(undef);
  }

  $self->drive->free($tm)
    if ($self->drive);

  return $self->{UNMOUNTTIME};
}

sub start {
  my $self = shift;

  return $self->{MOUNTTIME};
}

sub stop {
  my $self = shift;

  return $self->{UNMOUNTTIME};
}

sub startPositioning {
  my $self = shift;
  my $fileNumber = shift;
  my $tm = shift;

}

sub positioned {
  my $self = shift;
  my $tm = shift;

}

sub drive {
  my $self = shift;

  if (@_) {
    $self->{DRIVE} = shift;
  }
  return $self->{DRIVE};
}

sub volume {
  my $self = shift;

  return $self->{MEDIA};
}

sub write {
  my $self = shift;

  my ($fragment, $size, $speed) = @_;

  $self->{FRAGMENT} = $fragment;
  $self->{SIZE} = $size;
  $self->{SPEED} = $speed;

  $self->volume->write($size, $speed);

  return $self;
}

sub speed {
  my $self = shift;

  return $self->{SPEED};
}

sub writeTime {
  my $self = shift;

  if (my $speed = $self->{SPEED}) {
    my $size = $self->{SIZE};
    return ($size / $speed);
  }
  return undef;
}

sub dataWritten {
  my $self = shift;

  return $self->{SIZE};
}

1;

__END__
