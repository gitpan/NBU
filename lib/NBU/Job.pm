#
# Copyright (c) 2002 Paul Winkeler.  All Rights Reserved.
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.
#
package NBU::Job;

use Time::Local;

use strict;
use Carp;

BEGIN {
  use Exporter   ();
  use AutoLoader qw(AUTOLOAD);
  use vars       qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS $AUTOLOAD);
  $VERSION =	 do { my @r=(q$Revision: 1.19 $=~/\d+/g); sprintf "%d."."%02d"x$#r,@r };
  @ISA =         qw();
  @EXPORT =      qw();
  @EXPORT_OK =   qw();
  %EXPORT_TAGS = qw();
}

my %pids;
my %jobs;

#
# New jobs are registered under their Process IDs
sub new {
  my $Class = shift;
  my $job = {
    MOUNTLIST => {},
  };

  bless $job, $Class;

  if (@_) {
    $job->{PID} = shift;
    if (exists($pids{$job->pid})) {
      my $pidArray = $pids{$job->pid};
      push @$pidArray, $job;
    }
    else {
      $pids{$job->pid} = [ $job ];
    }
  }
  return $job;
}

#
# Extract all jobs from the hash and return them
# in a simple array
sub list {
  my $Class = shift;

  my @jobList;
  foreach my $pidArray (values %pids) {
    foreach my $job (@$pidArray) {
      push @jobList, $job;
    }
  }

  return @jobList;
}

my @jobTypes = ("immediate", "scheduled", "user");
my $asOf;
my $fromFile = $ENV{"HOME"}."/.alljobs.allcolumns";
my ($jobPipe, $refreshPipe);
sub loadJobs {
  my $Class = shift;
  my $readFromFile = shift;
  my $logFile = shift;

  if (defined($readFromFile)) {
    die "Cannot open previous job log file \"$fromFile\"\n" unless open(PIPE, "<$fromFile");
    $jobPipe = *PIPE{IO};
    my @stat = stat(PIPE);  $asOf = $stat[9];
  }
  else {
    $asOf = time;
    my $tee = defined($logFile) ? "| tee $fromFile" : "";
    ($jobPipe, $refreshPipe) = NBU->cmd("| bpdbjobs -report -all_columns -stay_alive $tee |");
  }

  if (!(<$jobPipe> =~ /^C([\d]+)$/)) {
    return undef;
  }
  my $jobRowCount = $1;

  while ($jobRowCount--) {
    my $jobDescription;
    if (!($jobDescription = <$jobPipe>)) {
      print STDERR "Failed to read from job pipe ($jobPipe)\n";
      last;
    }
    parseJob($jobDescription);
  }

  return $asOf;
}

sub refreshJobs {
  my $Class = shift;

  return undef if (!defined($jobPipe));

  print $refreshPipe "refresh\n" if (defined($refreshPipe));

  if (!(<$jobPipe> =~ /^C([\d]+)$/)) {
    return undef;
  }
  my $jobRowCount = $1;

  while ($jobRowCount--) {
    my $jobDescription;
    if (!($jobDescription = <$jobPipe>)) {
      print STDERR "Failed to read from job pipe ($jobPipe)\n";
      last;
    }
    parseJob($jobDescription);
  }

  return $asOf;
}



sub parseJob {
  my $jobDescription = shift;
  chop $jobDescription;

  #
  # Occasionally some well-meaning but severely misguided soul decides that
  # the occasional comma inserted in the midst of an error message is a bad
  # thing indeed (which it is) so it was decided to quote that comma with a
  # back-slash.  It is for occasions such as this that the expression "From
  # the frying pan into the fire" was invented.  'nuff said.
  $jobDescription =~ s/([^\\])\\,/${1}-/;

  my (
    $jobID, $jobType, $state, $status, $className, $scheduleName, $client,
    $server, $started, $elapsed, $ended, $stUnit, $currentTry, $operation,
    $KBytesWritten, $filesWritten, $currentFile, $percent,
    # This is the PID of the bpsched process on the master
    $jobPID,
    $owner,
    $subType, $classType, $scheduleType, $priority,
    $group, $masterServer, $retentionUnits, $retentionPeriod,
    $compression,
    # The next two values are used to compute % complete information, i.e.
    # they represent historical data
    $KBytesLastWritten, $filesLastWritten,
    $pathListCount,
    @rest) = split(/,/, $jobDescription);

  my $job;
  if (!($job = NBU::Job->byID($jobID))) {
    $job = NBU::Job->new($jobPID);
    $job->id($jobID);


    $job->start($started);

    $job->type($jobTypes[$jobType]);

    $job->storageUnit(NBU::StorageUnit->byLabel($stUnit));
    my $backupID = $client."_".$started;
    my $image = $job->image($backupID);
    my $class = $image->class(NBU::Class->new($className));
    $image->schedule(NBU::Schedule->new($scheduleName, $class));
    $image->client(NBU::Host->new($client));
  }
  $job->state($state);
  $job->try($currentTry);

  #
  # Extract the list of paths (either in the class definition's include list
  # or the ones provided by the user.
  my @paths;
  if (defined($pathListCount)) {
    for my $i (1..$pathListCount) {
      my $p = shift @rest;
      push @paths, $p;
    }
  }

  #
  # March through the list of tries and for each of them, extract the progress
  # scenario.  Need to think about a way to do delta's: remember last try and
  # progress indices perhaps?
  if (defined(my $tryCount = shift @rest)) {
    for my $i (1..$tryCount) {
      my ($tryPID, $tryStUnit, $tryServer,
	  $tryStarted, $tryElapsed, $tryEnded,
	  $tryStatus, $description, $tryProgressCount, @tryRest) = @rest;

      $elapsed = $tryElapsed;
      for my $t (1..$tryProgressCount) {
	my $tryProgress = shift @tryRest;
	my ($dt, $tm, $dash, $msg) = split(/[\s]+/, $tryProgress, 4);

	if ($dt =~ /([\d]{2})\/([\d]{2})\/([\d]{4})/) {
	}
	elsif ($dt =~ /([\d]{2})\/([\d]{2})\/([\d]{2})/) {
	  $3 += 2000;
	}
	my $mm = $1;  my $dd = $2;  my $yyyy = $3;

	$tm =~ /([\d]{2}):([\d]{2}):([\d]{2})/;
	my $h = $1;  my $m = $2;  my $s = $3;
	my $now = timelocal($s, $m, $h, $dd, $mm-1, $yyyy);

	if ($msg =~ /connecting/) {
	  $job->startConnecting($now);
	}
	elsif ($msg =~ /connected/) {
	  $job->connected($now);
	}
	elsif ($msg =~ /^mounting ([\S]+)/) {
	  my $volume = NBU::Media->byID($1);
	  $job->startMounting($volume, $now);
	}
	elsif ($msg =~ /mounted/) {
	  # unfortunately this data stream does not tell us which drive :-(
	  $job->mounted(undef, $now);
	}
	elsif ($msg =~ /positioning/) {
	  my $fileNumber;
	  $job->startPositioning($fileNumber, $now);
	}
	elsif ($msg =~ /positioned/) {
	  $job->positioned($now);
	}
	elsif ($msg =~ /begin writing/) {
	  $job->startWriting($now);
	}
	elsif ($msg =~ /end writing/) {
	  $job->doneWriting($now);
	}
	else {
print "$jobID\:$i\: $msg\n";
	}
      }
      my $tryKBytesWritten = $KBytesWritten = shift @tryRest;
      my $tryFilesWritten = $filesWritten = shift @tryRest;

      @rest = @tryRest;
    }
  }

  if ($job->state eq "active") {
    $job->{CURRENTFILE} = $currentFile;
    $job->{SIZE} = $KBytesWritten;
    $job->{FILECOUNT} = $filesWritten;
    $job->{OPERATION} = $operation;
    $job->{ELAPSED} = $elapsed;
  }
  elsif ($job->state eq "done") {
    $job->{SIZE} = $KBytesWritten;
    $job->{FILECOUNT} = $filesWritten;
    $job->stop($ended, $status);
    $job->{ELAPSED} = $elapsed;
  }
  
  return $job;
}

sub byID {
  my $Class = shift;

  if (@_) {
    my $id = shift;

    return $jobs{$id} if (exists($jobs{$id}));
  }
  return undef;
}

#
# Returns the last job associated with the argument PID.
sub byPID {
  my $Class = shift;
  my $pid = shift;

  if (my $pidArray = $pids{$pid}) {
    my $job = @$pidArray[@$pidArray - 1];
    if (!defined($job)) {
      print STDERR "Strange doings with pid $pid\n";
    }
    return $job;
  }
  return undef;
} 

#
# Some jobs turn out to be worse than useless
sub forget {
  my $self = shift;

  if (my $pidArray = $pids{$self->pid}) {
    my @newArray;
    foreach my $job (@$pidArray) {
      push @newArray, $job unless ($job eq $self);
    }
    if (@newArray < 0) {
      delete $pids{$self->pid};
    }
    else {
      $pids{$self->pid} = \@newArray;
    }
  }
  if ($self->id) {
    delete $jobs{$self->id};
  }

  return $self;
}

sub pid {
  my $self = shift;

  return $self->{PID};
}

sub id {
  my $self = shift;

  if (@_) {
    $jobs{$self->{ID} = shift} = $self;
  }
  return $self->{ID};
}

#
# A job's backup ID really identifies the image that job wrote
# out to the volume(s).
sub backupID {
  my $self = shift;

  if (@_) {
    my $image = NBU::Image->new(shift);
    $self->{IMAGE} = $image;
  }

  return $self->{IMAGE};
}

sub image {
  my $self = shift;

  if (@_) {
    my $image = NBU::Image->new(shift);
    $self->{IMAGE} = $image;
  }

  return $self->{IMAGE};
}

#
# The client and class methods on Job are merely short hand
# for retrieving these attributes from the Job's Image.
sub client {
  my $self = shift;
  my $image = $self->{IMAGE};

  return $image->client;
}

#
# A job's class is really the class of the image it is creating.  Just
# as the job's schedule is the schedule of the image of the job being
# written.
sub class {
  my $self = shift;
  my $image = $self->{IMAGE};

  return $image->class;
}
sub schedule {
  my $self = shift;
  my $image = $self->{IMAGE};

  return $image->schedule;
}

sub start {
  my $self = shift;

  if (@_) {
    $self->{START} = shift;
  }
  return $self->{START};
}

sub stop {
  my $self = shift;

  if (@_) {
    $self->{STOP} = shift;
    if ($self->mount) {
      $self->mount->unmount($self->{STOP});
    }
    $self->{STATUSCODE} = shift;
    $self->{ELAPSED} = undef;
  }
  return $self->{STOP};
}

sub status {
  my $self = shift;

  return $self->{STATUSCODE};
}

sub elapsedTime {
  my $self = shift;

  if ($self->{ELAPSED}) {
    return $self->{ELAPSED};
  }
  else {
    my $stop = $self->stop;
    $stop = time() if (!$stop);

    return ($stop - $self->start);
  }
}

sub storageUnit {
  my $self = shift;

  if (@_) {
    $self->{STUNIT} = shift;
  }
  return $self->{STUNIT};
}

sub mountList {
  my $self = shift;
  my $ml = $self->{MOUNTLIST};

  return %$ml;
}

sub pushState {
  my $self = shift;
  my $newState = shift;
  my $tm = shift;

  my $states = $self->{STATES};
  my $times = $self->{TIMES};
  if (!$states) {
    $states = $self->{STATES} = [];
    $times = $self->{TIMES} = [];
  }
  push @$states, $newState;
  push @$times, $tm;
  $self->{STARTOP} = $tm;
}

sub popState {
  my $self = shift;
  my $tm = shift;
  my $states = $self->{STATES};
  my $times = $self->{TIMES};

  my $lastState = pop @$states;
  $self->{$lastState} += ($tm - $self->{STARTOP});

  $self->{STARTOP} = pop @$times;
}

sub volume {
  my $self = shift;

  return $self->{SELECTED};
}

sub startConnecting {
  my $self = shift;
  my $tm = shift;

  $self->pushState('CON', $tm);
}

sub connected {
  my $self = shift;
  my $tm = shift;

  $self->popState($tm);
}

sub startMounting {
  my $self = shift;
  my $volume = shift;
  my $tm = shift;

  $self->pushState('MNT', $tm);

  $self->{SELECTED} = $volume;
  $volume->selected($tm);

  return $self;
}

sub mounted {
  my $self = shift;
  my $driveIndex = shift;
  my $tm = shift;

  $self->popState($tm);

  my $volume = $self->{SELECTED};

  my $mount = NBU::Mount->new($self, $volume, $driveIndex, $tm);

  my $mountListR = $self->{MOUNTLIST};
  $$mountListR{$tm} = $mount;

  return $self->mount($mount);
}

sub startPositioning {
  my $self = shift;
  my $fileNumber = shift;
  my $tm = shift;

  $self->pushState('POS', $tm);
  $self->mount->startPositioning($fileNumber, $tm);
}

sub positioned {
  my $self = shift;
  my $tm = shift;

  $self->popState($tm);
  $self->mount->positioned($tm);
}

sub startWriting {
  my $self = shift;
  my $tm = shift;

  $self->pushState('WRI', $tm);
  $self->{FRAGMENTCOUNTER}++;
}

sub doneWriting {
  my $self = shift;
  my $tm = shift;

  $self->popState($tm);
}

sub type {
  my $self = shift;

  if (@_) {
    $self->{TYPE} = shift;
  }

  return $self->{TYPE};
}

my @jobStates = ("queued", "active", "re-queued", "done");
sub state {
  my $self = shift;

  if (@_) {
    $self->{STATE} = shift;
  }
  return $jobStates[$self->{STATE}];
}

sub active {
  my $self = shift;

  return ($self->{STATE} == 1);
}

sub done {
  my $self = shift;

  return ($self->{STATE} == 3);
}

sub queued {
  my $self = shift;

  return (($self->{STATE} == 0) || ($self->{STATE} == 2));
}

sub busy {
  my $self = shift;

  if (!$self->{STARTOP}) {
print STDERR "Job ".$self->id." has no start op?\n";
    return undef;
  }
  else  {
    return $asOf - $self->{STARTOP};
  }
}

my %opCodes = (
  26 => 'CON',
  27 => 'MNT',
  29 => 'POS',
  35 => 'WRI',
);

sub operation {
  my $self = shift;

  return undef if ($self->state ne "active");

  if (@_) {
    $self->{OPERATION} = shift;
  }
  my $opCode;
  if (!defined($opCode = $opCodes{$self->{OPERATION}})) {
    $opCode = sprintf("%3d", $self->{OPERATION});
  }

  return $opCode;
}

sub currentFile {
  my $self = shift;

  return ($self->state eq "active") ? $self->{CURRENTFILE} : undef;
}

sub try {
  my $self = shift;

  if (@_) {
    my $try = shift;

    if ($self->{TRY} && ($self->{TRY} != $try)) {
      # Maybe call somebody that we're on our next try?
    }
    $self->{TRY} = $try;
  }

  return $self->{TRY};
}

sub mount {
  my $self = shift;

  if (@_) {
    $self->{MOUNT} = shift;
  }
  return $self->{MOUNT};
}

sub write {
  my $self = shift;
  my ($fragment, $size, $speed) = @_;

  $self->{SIZE} += $size;
  $self->mount->write($fragment, $size, $speed);

  return $self;
}

sub ioStats {
  my $self = shift;

  if (@_) {
    my ($noBuffer, $noData, $bytesRead) = @_;

    $self->{NOBUFFER} = $noBuffer;
    $self->{NODATA} = $noData;
  }

  return ($self->{NOBUFFER}, $self->{NODATA}, $self->{SIZE});
}

sub dataWritten {
  my $self = shift;

  return $self->{SIZE};
}

sub filesWritten {
  my $self = shift;

  return $self->{FILECOUNT};
}

sub printHeader {
  my $self = shift;

  my $pid = $self->pid;
  my $id = $self->id;
  print "Process $pid manages job $id\n";

  return $self;
}

1;

__END__
