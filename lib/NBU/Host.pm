#
# Copyright (c) 2002 Paul Winkeler.  All Rights Reserved.
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.
#
package NBU::Host;

use strict;
use Carp;

my %hostList;

BEGIN {
  use Exporter   ();
  use AutoLoader qw(AUTOLOAD);
  use vars       qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS $AUTOLOAD);
  $VERSION =	 do { my @r=(q$Revision: 1.20 $=~/\d+/g); sprintf "%d."."%02d"x$#r,@r };
  @ISA =         qw();
  @EXPORT =      qw();
  @EXPORT_OK =   qw();
  %EXPORT_TAGS = qw();
}

my %aliases = (
  'opscenter' => 'opscenter.bkup',
  'opscenter.bk' => 'opscenter.bkup',
);

sub new {
  my $proto = shift;
  my $host;

  if (@_) {
    my $name = shift;
    $name = $aliases{$name} if (exists($aliases{$name}));
#    my $keyName = substr($name, 0, 12);
    my $keyName = $name;

    if (!($host = $hostList{$keyName})) {
      $host = {};
      bless $host, $proto;
      $host->{NAME} = $name;

      $hostList{$keyName} = $host;

      $host->{ENROLLED} = 0;
    }
  }
  return $host;
}

sub populate {
  my $proto = shift;

  my $pipe = NBU->cmd("bpclclients -allunique -noheader |");
  while (<$pipe>) {
    my ($platform, $os, $name) = split;
    my $host = NBU::Host->new($name);

    $host->os($os);
    $host->platform($platform);
  }
  close($pipe);
}

sub byName {
  my $proto = shift;
  my $name = shift;
  my $keyName = substr($name, 0, 12);

  if (my $host = $hostList{$keyName}) {
    return $host;
  }
  return undef;
}

sub list {
  my $proto = shift;

  return (values %hostList);
}

sub enrolled {
  my $self = shift;

  $self->{ENROLLED} = 1;
}

sub loadClasses {
  my $self = shift;

  NBU::Pool->populate;

  my $pipe = NBU->cmd("bpcllist -byclient ".$self->name." -l |");
  NBU::Class->loadClasses($pipe, "CLIENT", $self->clientOf);

  close($pipe);
}

sub makeClassMember {
  my $self = shift;
  my $newClass = shift;

  if (!defined($self->{CLASSES})) {
    $self->{CLASSES} = [];
  }

  my $classesR = $self->{CLASSES};
  push @$classesR, $newClass;

  return $newClass;
}

sub classes {
  my $self = shift;

  $self->loadClasses if (!$self->{ENROLLED});

  my $classesR = $self->{CLASSES};
  if (defined($classesR)) {
    return (@$classesR);
  }
  return ();
}

sub name {
  my $self = shift;

  return $self->{NAME};
}

sub loadConfig {
  my $self = shift;

  return 1 if ($self->{CONFIGLOADED});
  $self->{CONFIGLOADED} = 1;

  my $pipe = NBU->cmd("bpgetconfig -g ".$self->name." |");
  return unless defined($_ = <$pipe>);  chop;
  if (/Client of ([\S]+)/) {
    $self->{MASTER} = NBU::Host->new($1);
  }

  # OS on this machine
  return unless defined($_ = <$pipe>);  chop;
  if (/^([\S]+), ([\S]+)$/) {
    $self->{PLATFORM} = $1;
    $self->{OS} = $2;
  }
  else {
    $self->{PLATFORM} = $self->{OS} = $_;
  }

  # Now get the NetBackup version information
  # All the hosts in the cluster better be running the same version
  # but we're not checking for that at this time.
  return unless defined($_ = <$pipe>);  chop;
  $self->{NBUVERSION} = $_;

  # Product identifier
  return unless defined($_ = <$pipe>);  chop;

  if (defined($_ = <$pipe>)) {
    chop;
    $self->{RELEASE} = $_;
  }
    
  close($pipe);
}

sub clientOf {
  my $self = shift;

  $self->loadConfig;
  return $self->{MASTER};
}

sub platform {
  my $self = shift;

  if (@_) {
    $self->{PLATFORM} = shift;
  }
  else {
    $self->loadConfig;
  }

  return $self->{PLATFORM};
}

sub os {
  my $self = shift;

  if (@_) {
    $self->{OS} = shift;
  }
  else {
    $self->loadConfig;
  }

  return $self->{OS};
}

sub NBUVersion {
  my $self = shift;

  if (@_) {
    $self->{NBUVERSION} = shift;
  }
  else {
    $self->loadConfig;
  }

  return $self->{NBUVERSION};
}

sub release {
  my $self = shift;

  if (@_) {
    $self->{RELEASE} = shift;
  }
  else {
    $self->loadConfig;
  }

  return $self->{RELEASE};
}

sub loadCoverage {
  my $self = shift;
  my $name = $self->name;

  my %coverage;
  my $loadOK;

  my $pipe = NBU->cmd("bpcoverage -c $name -no_cov_header -no_hw_header |");
  while (<$pipe>) {
    if (!$loadOK) {
      if (/^CLIENT: $name/) {
	while (<$pipe>) {
          last if (/Mount Point/ || /Drive Letter/);
	}
        $_ = <$pipe>;
        $loadOK = 1;
      }
    }
    elsif ($loadOK && !(/^$/) && !(/   Exit status/)) {
      my ($mountPoint, @remainder) = split;

      if ($self->os =~ /[Ss]olaris|linux|hp10.20/) {
	my ($deviceFile, $className, $status) = @remainder;

	next if ($deviceFile !~ /^\//);

        if ($className eq "UNCOVERED") {
	  $coverage{$mountPoint} = undef;
        }
        else {
	  $className =~ s/^\*//;
	  my $clR = $coverage{$mountPoint};
	  if (!$clR) {
	    $coverage{$mountPoint} = $clR = [];
	  }
	  my $class = NBU::Class->byName($className, $self->clientOf);
	  $class->providesCoverage(1);
          push @$clR, $class;
        }
      }
      elsif ($self->os =~ /Windows(NT|2000)/) {
        my ($className, $status) = @remainder;
        if ($className eq "UNCOVERED") {
	  $coverage{$mountPoint} = undef;
        }
        else {
	  $className =~ s/^\*//;
	  my $clR = $coverage{$mountPoint};
	  if (!$clR) {
	    $coverage{$mountPoint} = $clR = [];
	  }
	  my $class = NBU::Class->byName($className, $self->clientOf);
	  $class->providesCoverage(1);
          push @$clR, $class;
        }
      }
      else {
        print "coverage from ".$self->os.": $_";
      }
    }
    else {
      last;
    }
  }
  close($pipe);

  $self->{COVERAGE} = \%coverage;
}

sub coverage {
  my $self = shift;

  if (!$self->{COVERAGE}) {
    $self->loadCoverage;
  }

  my $coverageR = $self->{COVERAGE};
  return (%$coverageR);
}

#
# Add an image to a host's list of backup images
sub addImage {
  my $self = shift;
  my $image = shift;
  
  $self->{IMAGES} = {} if (!defined($self->{IMAGES}));

  my $images = $self->{IMAGES};

  $$images{$image->id} =  $image;
}

#
# Load the list of images run against this host
sub loadImages {
  my $self = shift;

  if (!defined($self->{ALLIMAGES})) {
    NBU::Image->loadImages(NBU->cmd("bpimmedia -l -client ".$self->name." |"));
  }
  return ($self->{ALLIMAGES} = $self->{IMAGES});
}

sub images {
  my $self = shift;

  $self->loadImages;

  if (defined(my $images = $self->{IMAGES})) {
    return (values %$images);
  }
  else {
    return ();
  }
}

1;

__END__
