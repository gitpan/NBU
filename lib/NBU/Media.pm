#
# Copyright (c) 2002 Paul Winkeler.  All Rights Reserved.
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.
#
package NBU::Media;

use strict;
use Carp;

use NBU::Robot;

BEGIN {
  use Exporter   ();
  use AutoLoader qw(AUTOLOAD);
  use vars       qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS $AUTOLOAD);
  use vars       qw(%densities);
  $VERSION =	 do { my @r=(q$Revision: 1.14 $=~/\d+/g); sprintf "%d."."%02d"x$#r,@r };
  @ISA =         qw();
  @EXPORT =      qw(%densities);
  @EXPORT_OK =   qw();
  %EXPORT_TAGS = qw();
}

%densities = (
  13 => "dlt",
  16 => "8mm",
  12 => "4mm",
  6 => "hcart",
  19 => "dtf",
  9 => "odiskwm",
  10 => "odiskwo",
  0 => "qscsi",
  15 => "dlt2",
  14 => "hcart2",
  20 => "hcart3",
);

my %mediaList;
my %barcodeList;

sub new {
  my $Class = shift;
  my $media = {};

  bless $media, $Class;

  if (@_) {
    my $mediaID = shift;
    $media->{EVSN} = $mediaID;
    $mediaList{$media->{EVSN}} = $media;
  }
  return $media;
}

sub populate {
  my $Class = shift;
  my $updateRobot = shift;
  my $mmdbHost;

  my @masters = NBU->masters;  my $master = $masters[0];

  my $pipe = NBU->cmd("bpmedialist -L |");
  my $volume;
  while (<$pipe>) {
    if (/^Server Host = ([\S]+)$/) {
      $mmdbHost = NBU::Host->new($1);
    }
    if (/^media_id = ([A-Z0-9]{6}), partner_id.*/) {
      if ($volume) {
        print STDERR "New media $1 encountered when old one ".$volume->id." still active!\n";
        exit 0;
      }
      $volume = NBU::Media->new($1);
      $volume->{LOADED} = 1;
      $volume->mmdbHost($mmdbHost);
      next;
    }

    if (/^density = ([\S]+) \(([\d]+)\)/) {
      $volume->density($2);
      next;
    }
    if (/^allocated = .* \(([0-9]+)\)/) {
      $volume->allocated($1);
      next;
    }
    if (/^last_written = .* \(([0-9]+)\)/) {
      $volume->lastWritten($1);
      next;
    }
    if (/^expiration = .* \(([0-9]+)\)/) {
      $volume->expires($1);
      next;
    }
    if (/^last_read = .* \(([0-9]+)\)/) {
      $volume->lastRead($1);
      next;
    }

    if (/retention_level = ([\d]+), num_restores = ([\d]+)/) {
      $volume->retention(NBU::Retention->byLevel($1));
      $volume->{RESTORECOUNT} = $2;
      next;
    }

    if (/^kbytes = ([\d]+), nimages = ([\d]+), vimages = ([\d]+)/) {
      $volume->dataWritten($1);
      next;
    }

    if (/^status = 0x([0-9A-Fa-f]+), /) {
      my $status = $1;
      my $result = 0;
      my $magnitude = 1;
      foreach my $d (split(/ */, $status)) {
        $result *= $magnitude;
        $result += $d;
        $magnitude *= 16;
      }
      $volume->status($result);
      next;
    }

    if (/^$/) {
      $volume = undef;
      next;
    }
  }
  close($pipe);

  #
  # Have to force the pool information to load or we dead-lock.  It appears
  # the VM database deamon is single threaded and won't answer a pool query until
  # the volume listing is completed...
  NBU::Pool->populate;

  $pipe = NBU->cmd("vmquery -a -w -h ".$master->name." |");
  $_ = <$pipe>; $_ = <$pipe>; $_ = <$pipe>;
  while (<$pipe>) {
    my ($id,
        $opticalPartner,
        $mediaType,
        $barcode, $barcodePartner,
        $robotHostName, $robotType, $robotNumber, $slotNumber,
        $side,
        $volumeGroup,
        $volumePool, $volumePoolNumber, $previousVolumePool,
        $mountCount, $maxMounts, $cleaningCount,
        $creationDate, $creationTime,
        $assignDate, $assignTime,
        $firstMountDate, $firstMountTime,
        $lastMountDate, $lastMountTime,
        $expirationDate, $expirationTime,
        $status,
        $offsiteLocation,
        $offsiteSentDate, $offsiteSentTime,
        $offsiteReturnDate, $offsiteReturnTime,
        $offsiteSlot,
        $offsiteSessionID,
        $version,
        $description,
      )
      = split(/[\s]+/, $_, 37);
    $volume = NBU::Media->byID($id);
    if (!defined($volume)) {
      $volume = NBU::Media->new($id);
    }
    $volume->barcode($barcode);
    $volume->{MEDIATYPE} = $mediaType;
    $volume->{CLEANINGCOUNT} = $cleaningCount;
    $volume->{MOUNTCOUNT} = $mountCount;
    $volume->{MAXMOUNTS} = $maxMounts;
    $volume->{VOLUMEGROUP} = ($volumeGroup eq "---") ? undef : $volumeGroup,


    $volume->{POOL} = NBU::Pool->byID($volumePoolNumber);
    $volume->{PREVIOUSPOOL} = NBU::Pool->byName($previousVolumePool);

    $volume->{OFFSITELOCATION} = $offsiteLocation;
    $volume->{VERSION} = $version;
    $volume->{DESCRIPTION} = $description;

    if ($updateRobot && $robotType ne "NONE") {
      my $robot;
      if (!defined($robot = NBU::Robot->byID($robotNumber))) {
        $robot = NBU::Robot->new($robotNumber, $robotType, $robotHostName);
      }
      $robot->insert($slotNumber, $volume);
      $volume->robot($robot);
      $volume->slot($slotNumber);
    }
  } 
  close($pipe);
}

sub loadErrors {
  my $Class = shift;

  if (open(PIPE, "<".$ENV{HOME}."/media-errors.csv")) {
    # Place this use directive inside an eval to postpone missing
    # module diagnostics until run-time
    eval "use Text::CSV_XS";
    my $csv = Text::CSV_XS->new();

    while (<PIPE>) {
      if ($csv->parse($_)) {
	my @fields = $csv->fields;
	my $volume = NBU::Media->byID($fields[1]);
	if ($volume) {
	  $volume->logError($fields[0], $fields[5]);
	}
      }
    }
    close(PIPE);
  }
}

sub listIDs {
  my $Class = shift;

  return (keys %mediaList);
}

sub listVolumes {
  my $Class = shift;

  return (values %mediaList);
}

sub mmdbHost {
  my $self = shift;

  if (@_) {
    $self->{MMDBHOST} = shift;
  }
  return $self->{MMDBHOST};
}

sub density {
  my $self = shift;

  if (@_) {
    $self->{DENSITY} = $densities{shift};
  }

  return $self->{DENSITY};
}

sub retention {
  my $self = shift;

  if (@_) {
    my $retention = shift;
    $self->{RETENTION} = $retention;
  }

  return $self->{RETENTION};
}

sub barcode {
  my $self = shift;

  if (@_) {
    if (my $oldBarcode = $self->{BARCODE}) {
      delete $barcodeList{$oldBarcode};
      $self->{BARCODE} = undef;
    }
    if (my $barcode = shift) {
      $barcodeList{$barcode} = $self;
      $self->{BARCODE} = $barcode;
    }
  }
  return $self->{BARCODE};
}

sub previousPool {
  my $self = shift;

  return $self->{PREVIOUSPOOL};
}

sub pool {
  my $self = shift;

  if (@_) {
  }
  return $self->{POOL};
}

sub group {
  my $self = shift;

  if (@_) {
  }
  return $self->{VOLUMEGROUP};
}

sub type {
  my $self = shift;

  if (@_) {
    $self->{MEDIATYPE} = shift;
  }

  return $self->{MEDIATYPE};
}

sub logError {
  my $self = shift;

  return $self->{ERRORCOUNT} += 1;
}

sub errorCount {
  my $self = shift;

  return $self->{ERRORCOUNT};
}

sub cleaningCount {
  my $self = shift;

  if (@_ && ($self->{MEDIATYPE} =~ /_CLN$/)) {
    my $newCount = shift;
    NBU->cmd("vmchange -m ".$self->id." -n $newCount\n");
    $self->{CLEANINGCOUNT} = $newCount;
  }
  return $self->{CLEANINGCOUNT};
}

sub mountCount {
  my $self = shift;

  if ($self->{MEDIATYPE} =~ /_CLN$/) {
    return $self->{CLEANINGCOUNT};
  }
  else {
    return $self->{MOUNTCOUNT};
  }
}

sub firstMounted {
  my $self = shift;

  if (@_) {
    if (@_ > 1) {
      # convert date and time to epoch seconds first
    }
    else {
      $self->{FIRSTMOUNTED} = shift;
    }
  }

  return $self->{FIRSTMOUNTED};
}

sub lastMounted {
  my $self = shift;

  if (@_) {
    if (@_ > 1) {
      # convert date and time to epoch seconds first
    }
    else {
      $self->{LASTMOUNTED} = shift;
    }
  }

  return $self->{LASTMOUNTED};
}

sub byBarcode {
  my $Class = shift;
  my $barcode = shift;


  if (my $volume = $barcodeList{$barcode}) {
    return $volume;
  }
  return undef;
}

#
# The External Volume Serial Number (evsn) is the same as the media ID hence
# the two variants of id and byID.
sub byID {
  my $Class = shift;
  my $mediaID = shift;


  if (my $volume = $mediaList{$mediaID}) {
    return $volume;
  }
  else {
     return NBU::Media->new($mediaID);
  }
}
sub byEVSN {
  my $self = shift;

  return $self->byID(@_);
}

sub id {
  my $self = shift;

  if (@_) {
    $self->{EVSN} = shift;
    $mediaList{$self->{EVSN}} = $self;
  }

  return $self->{EVSN};
}
sub evsn {
  my $self = shift;

  return $self->id(@_);
}

#
# This is the Recorded Volume Serial Number which can sometimes be
# different.
sub rvsn {
  my $self = shift;

  if (@_) {
    $self->{RVSN} = shift;
  }

  return $self->{RVSN};
}

sub robot {
  my $self = shift;

  if (@_) {
    $self->{ROBOT} = shift;
  }

  return $self->{ROBOT};
}

sub slot {
  my $self = shift;

  if (@_) {
    $self->{SLOT} = shift;
  }

  return $self->{SLOT};
}

sub selected {
  my $self = shift;

  if (@_) {
    $self->{SELECTED} = shift;
  }
  return $self->{SELECTED};
}

sub mount {
  my $self = shift;
  my $id = $self->id;

  if (@_) {
    my ($mount, $drive) = @_;
    $self->{MOUNT} = $mount;
    $self->{DRIVE} = $drive;
  }
  return $self->{MOUNT};
}

sub drive {
  my $self = shift;

  return $self->{DRIVE};
}

sub unmount {
  my $self = shift;
  my ($tm) = @_;

  if (my $mount = $self->mount) {
    $mount->unmount($tm);
  }

  $self->mount(undef, undef);
  return $self;
}

sub write {
  my $self = shift;
  my $id = $self->id;

  my ($size, $speed) = @_;

  $self->{SIZE} += $size;
  $self->{WRITETIME} += ($size / $speed);
}

sub writeTime {
  my $self = shift;

  return $self->{WRITETIME};
}

sub dataWritten {
  my $self = shift;

  if (@_) {
    $self->{SIZE} = shift;
  }
  return $self->{SIZE};
}

sub allocated {
  my $self = shift;

  if (@_) {
    $self->{ALLOCATED} = shift;
  }

  return $self->{ALLOCATED};
}

sub lastWritten {
  my $self = shift;

  if (@_) {
    $self->{LASTWRITTEN} = shift;
  }

  return $self->{LASTWRITTEN};
}

sub lastRead {
  my $self = shift;

  if (@_) {
    $self->{LASTREAD} = shift;
  }

  return $self->{LASTREAD};
}

sub expires {
  my $self = shift;

  if (@_) {
    $self->{EXPIRES} = shift;
  }

  return $self->{EXPIRES};
}

sub status {
  my $self = shift;

  if (@_) {
    $self->{STATUS} = shift;
  }

  return $self->{STATUS};
}

sub maxMounts {
  my $self = shift;

  if (@_) {
    my $maxMounts = shift;
    NBU->cmd("vmchange".
            " -m ".$self->id.
            " -maxmounts $maxMounts\n");
    $self->{MAXMOUNTS} = $maxMounts;
  }

  return $self->{MAXMOUNTS};
}

sub frozen {
  my $self = shift;

  return $self->{STATUS} & 0x1;
}

sub freeze {
  my $self = shift;

  if ($self->allocated && !($self->{STATUS} & 0x1)) {
    # issue freeze command:
    NBU->cmd("bpmedia".
            " -h ".$self->mmdbHost->name.
            " -ev ".$self->id.
            " -freeze\n");
    $self->{STATUS} |= 0x1;
  }
  return $self->{STATUS} & 0x1;
}

sub suspended {
  my $self = shift;

  return $self->{STATUS} & 0x2;
}

sub full {
  my $self = shift;

  return $self->{STATUS} & 0x8;
}

sub eject {
  my $self = shift;

#"vmchange -res -m $media_id -rt $lc_robot_type -mt $media_id -rn $robot_num -rh $robot_host -rc1 $slot -rc2 $side -e" ;
  if ($self->robot) {
    NBU->cmd("vmchange -res"." -m ".$self->id." -mt ".$self->id.
	      " -rn ".$self->robot->id." -rc1 ".$self->slot." -rh ".$self->robot->host->name.
	      " -e\n"
    );
    return $self;
  }
  else {
    return undef;
  }
}

#
# Insert a single fragment into this volume's table of contents
sub insertFragment {
  my $self = shift;
  my $index = shift;
  my $fragment = shift;
  
  $self->{TOC} = [] if (!defined($self->{TOC}));

  my $toc = $self->{TOC};

  $$toc[$index] = $fragment;
}

#
# Load the list of fragments for this volume into its table of
# contents.
sub loadImages {
  my $self = shift;

  if (!$self->{LOADED} || ($self->allocated && ($self->expires > time))) {
    NBU::Image->loadImages(NBU->cmd("bpimmedia -l -mediaid ".$self->id." |"));
  }
  return $self->{TOC};
}

sub tableOfContents {
  my $self = shift;

  if (!defined($self->{TOC})) {
    $self->loadImages;
  }

  my $toc = $self->{TOC};
  return (@$toc);
}

1;

__END__
