#!/usr/local/bin/perl

use strict;
use Getopt::Std;
use Time::Local;

use NBU;

my %opts;
getopts('utbseidjmfc:C:a:p:n:', \%opts);

my $period = 1;
my $mm;  my $dd;  my $yyyy;
if (!$opts{'a'}) {
  my ($s, $m, $h, $mday, $mon, $year, $wday, $yday, $isdst) = localtime();
  $year += 1900;
  $mm = $mon + 1;
  $dd = $mday;
  $yyyy = $year;

}
else {
  $opts{'a'} =~ /^([\d]{4})([\d]{2})([\d]{2})$/;
  if ($opts{'p'}) {
    $period = $opts{'p'};
  }
  $mm = $2;
  $dd = $3;
  $yyyy = $1;
}

my $lastParsedTime;
my $midnight;
sub parseTime {
  my $line = shift;

  $line =~ /^(\d\d):(\d\d):(\d\d)/;
  my $hr = $1;  my $min = $2;  my $sec = $3;
  my $tm = $midnight + $sec + ($min + ($hr * 60)) * 60;

  if ($tm < $lastParsedTime) {
    $tm += (24 * 60 * 60);
    $midnight += (24 * 60 * 60);
  }

  return $lastParsedTime = $tm;
}

sub dispInterval {
  my $i = shift;

  my $seconds = $i % 60;
  my $i = int($i / 60);
  my $minutes = $i % 60;
  my $hours = int($i / 60);

  my $fmt = sprintf("%02d", $seconds);
  $fmt = sprintf("%02d:", $minutes).$fmt if ($minutes || $hours);
  $fmt = sprintf("%02d:", $hours).$fmt if ($hours);
  return $fmt;
}

my $logPath = "/opt/openv/netbackup/logs";
my $asOf;
my $daysLeft = $period;
while ($daysLeft--) {
  my $mmddyy = sprintf("%02d%02d%02d", $mm, $dd, ($yyyy % 100));
  open (LOG, "<${logPath}/bptm/log.".$mmddyy);

  $midnight = timelocal(0, 0, 0, $dd, $mm-1, $yyyy);
  $lastParsedTime = undef;
  $asOf = $midnight unless(defined($asOf));

  while (<LOG>) {
    #
    if (/\[([\d]+)\] <2> bptm: INITIATING: -([\S]+)/) {
      my $pid = $1;
      my $option = $2;

      my $job = NBU::Job->new($pid);

      $job->start(parseTime($_));

      #
      # "w" jobs are your basic archive operations
      # Setting the job's backupID is really short hand for allocating
      # an image (which it therefore promptly returns) and the remaining
      # attributes are part of the image, not the job 
      if ($option eq "w") {
        /-jobid ([\d]+) /;  $job->id($1);
        /-stunit ([\S]+) /;  $job->storageUnit($1);
        /-mediasvr ([\S]+) /;  $job->mediaServer(NBU::Host->new($1));
        /-b ([\S]+) /;  my $image = $job->image($1);
        /-cl ([\S]+) /;  $image->class(NBU::Class->new($1));
        /-c ([\S]+) /;  $image->client(NBU::Host->new($1));
      }
      # when handed a "pid" we will likely be involved in a restore
      elsif ($option eq "pid") {
      }
      # deleting images
      elsif ($option eq "d") {
      }
      # some jobs operate on a single media
      elsif ($option eq "ev") {
      }
    }
    if (/\[([\d]+)\] <2> select_media: selected media id ([\S]+) for backup/) {
      my $job = NBU::Job->byPID($1);
      my $volume = NBU::Media->byID($2);

      $job->startMounting(parseTime($_), $volume);
    }
    if (/\[([\d]+)\] <2> write_backup: media id ([\S]+) mounted on drive index ([\d]+)/) {
      my $job = NBU::Job->byPID($1);
      my $mediaID = $2;
      my $drive = NBU::Drive->byIndex($3, $job->mediaServer);

      $job->mounted(parseTime($_), $drive);
    }
    if (/\[([\d]+)\] <4> write_backup: successfully wrote/) {
      my $job = NBU::Job->byPID($1);

      /fragment ([\d]+), ([\d]+) Kbytes at ([\d]+\.[\d]+)/;
      my $fragment = $1;
      my $size = $2;
      my $speed = $3;

      $job->write($fragment, $size, $speed);
    }
    if (/\[([\d]+)\] <2> fill_buffer: \[([\d]+)\] socket is closed, waited for empty buffer ([\d]+) times, delayed ([\d]+) times, read ([\d]+) bytes/) {
      my $job = NBU::Job->byPID($2);

      $job->ioStats($3, $4, $5);
    }
    if (/\[([\d]+)\] <2> write_data: waited for full buffer ([\d]+) times, delayed ([\d]+) times/) {
      my $job = NBU::Job->byPID($1);
      $job->ioStats($2, $3);
    }
    if (/\[([\d]+)\] <2> .* tpunmount.ing .*tpreq\/([\S]+)/) {
      if (my $media = NBU::Media->byID($2)) {
        $media->unmount(parseTime($_));
      }
    }
    if (/\[([\d]+)\] <2> (bptm|catch_signal|mpx_terminate_exit): EXITING with status ([\d]+)/) {
      my $job = NBU::Job->byPID($1);

      if (!$job) {
print STDERR "EXITING non existent job from pid \"$1\"\n";
        next;
      }

      #
      # Jobs that never had an id associated with them are not of interest
      if (!defined($job->id)) {
        $job->forget;
      }
      else {
        my $result = $3;
        $job->stop(parseTime($_), $result);
      }
    }
  }
  $dd += 1;
}

my @list = NBU::Job->list;
@list = sort { $a->start <=> $b->start } @list;

my $j;
my $jobCounter = 0;
my $firstJob;  my $lastJob;
my $overallDataWritten = 0;  my $overallElapsedTime = 0;
my %volumesUsed;
foreach $j (@list) {
 my $totalWriteTime = 0;
 my $totalKbytes = 0;

if (!$j->id) {
    print STDERR "Process was not eliminated? ".$j->pid."\n";
    next;
}

  if ($opts{'e'}) {
    next unless ($j->status);
  }

  if ($opts{'c'}) {
    my $classPattern = $opts{'c'};
    next unless ($j->class->name =~ /$classPattern/);
  }
  if ($opts{'C'}) {
    my $clientPattern = $opts{'C'};
    next unless ($j->client->name =~ /$clientPattern/);
  }

  $firstJob = $j if (!defined($firstJob));

  $jobCounter++;

  my $jid = $j->id;
  if ($opts{'j'}) {
    my $tmb = sprintf("%.2f", $j->dataWritten / 1024);  my $tunits = "Mb";
    if ($tmb > 1024) {
      $tmb = sprintf("%.2f", $j->dataWritten / 1024 / 1024);  $tunits = "Gb";
    }
    my $sp = sprintf("%.2f", ($j->dataWritten / $j->elapsedTime / 1024));
    print "J:$jid".":".sprintf("%5u", $j->pid).":".$j->class->name." ".localtime($j->start);
    if (defined($j->status)) {
      print " ${tmb}${tunits} in ".dispInterval($j->elapsedTime)." (${sp}Mb/s)";
      print " status ".$j->status."\n";
    }
    else {
      print " still running\n";
    }
    if ($opts{'b'}) {
      my ($s, $m, $h, $dd, $mon, $year, $wday, $yday, $isdst) = localtime($j->start);
      my $mm = $mon + 1;
      my $yy = sprintf("%02d", ($year + 1900) % 100);
      print "sudo /opt/openv/netbackup/bin/admincmd/bpflist -t ANY -option GET_ALL_FILES".
								" -client ".$j->client->name.
                " -backupid ".$j->image->id.
                " -d ${mm}/${dd}/${yy}"."\n";
    }
 }

  my %mountList = $j->mountList;

  foreach my $tm (sort (keys %mountList)) {
    my $mount = $mountList{$tm};
    my $volume = $mount->volume;
    my $mediaID = $volume->id;

    $volumesUsed{$mediaID} += 1;

    if ($opts{'m'}) {
      my $wt = sprintf("%.2f", $mount->writeTime);
      my $mb = sprintf("%.2f", ($mount->dataWritten / 1024));  my $units = "Mb";
      if ($mb > 1024) {
        $mb = sprintf("%.2f", ($mount->dataWritten / 1024 / 1024));  $units = "Gb";
      }
      my $sp = 0;
      if ($mount->writeTime) {
        $sp = sprintf("%.2f", ($mount->dataWritten / $mount->writeTime / 1024));
      }
      print "M:${jid}:${mediaID}".sprintf(" in %2u ", $mount->drive->id).localtime($mount->start).
            " ${mb}${units} over ".dispInterval($wt).
            " at ${sp}Mb/s\n";
    }

    $totalWriteTime += $mount->writeTime;
  }

  if ($opts{'j'}) {
    if ($opts{'s'}) {
      my $overHeadTime = sprintf("%.2f", ($j->elapsedTime - $totalWriteTime));
      my $overHead = sprintf("%.2f", ($overHeadTime * 100)/ $j->elapsedTime);
      my ($noBuffer, $noData) = $j->ioStats;
      print "J:${jid}:ended ".localtime($j->stop)." overhead ${overHeadTime}s ($overHead\%)".
              " $noBuffer/$noData\n";
    }
  }
  $lastJob = $j;

  $overallDataWritten += $j->dataWritten;
  $overallElapsedTime += $j->elapsedTime;
}

if (!$opts{'d'} && !$opts{'u'}) {
  my $overallVolumesUsed = (keys %volumesUsed);
  $overallDataWritten = sprintf("%.2f", ($overallDataWritten / 1024 / 1024));
  print "$jobCounter jobs wrote ${overallDataWritten}Gb over ".
    dispInterval($overallElapsedTime).
    " to $overallVolumesUsed distinct volumes\n";
}

#print "Jobs ran from ".localtime($firstJob->start)." until ".localtime($lastJob->stop)."\n";

if ($opts{'d'}) {
  my @dl = NBU::Drive->pool;

  @dl = sort { $a->id <=> $b->id} (@dl);

  if (!$opts{'i'}) {
    foreach my $d (@dl) {
      my $header = "Drive ".$d->id."\n";
      my $usage = $d->usage;
      @$usage = (sort {$$a{START} <=> $$b{START} } @$usage);
      foreach my $use (@$usage) {

        my $mount = $$use{'MOUNT'};
        # Was this mount part of a job from a specific class?
        if ($opts{'c'}) {
          my $p = $opts{'c'};
          my $j = $mount->job;
          next unless ($j->class->name =~ /$p/);
        }
        print $header;  $header = "";
        my $mediaID = $mount->volume->id;
        if ($$use{'STOP'}) {
          my $u = "Mb";
          my $dw = sprintf("%.2f", ($mount->dataWritten / 1024));
          if ($dw > 1024) {
            $dw = sprintf("%.2f", $mount->dataWritten / 1024 / 1024);  $u = "Gb";
          }
          my $sp = "-.--";
          if ($mount->writeTime) {
            $sp = sprintf("%.2f", ($mount->dataWritten / $mount->writeTime / 1024));
          }
          print localtime($$use{'START'})." ${dw}${u} over ".
                dispInterval($mount->writeTime).
                " at ${sp}Mb/s onto $mediaID";
        }
        else {
          print localtime($$use{'START'})." still running onto $mediaID";
        }
	print " from ".$mount->job->client->name."\n";
      }
    }
  }
  else {
    my $idleThreshold = 5 * 60;
    my $endOfPeriod = $asOf + (24 * 60 * 60) * $period;
    foreach my $d (@dl) {
      print "Drive ".$d->id."\n";
      my $usage = $d->usage;
      my $lastUsed = $asOf;
      my $idleTime = 0;
      foreach my $use (@$usage) {
        my $startBusy = $$use{'START'};
        $startBusy = $endOfPeriod if ($startBusy > $endOfPeriod);
        if (($startBusy - $lastUsed) > $idleThreshold) {
          print " idle from ".localtime($lastUsed)." for ";
          print dispInterval($startBusy - $lastUsed)."\n";;
          $idleTime += ($startBusy - $lastUsed);
        }
        $lastUsed = $$use{'STOP'};
        next unless (!$lastUsed || ($lastUsed > $endOfPeriod));
      }
      if ($lastUsed && ($lastUsed < $endOfPeriod)) {
        if (($endOfPeriod - $lastUsed) > $idleThreshold) {
          print " idle from ".localtime($lastUsed)." for ";
          print dispInterval($endOfPeriod - $lastUsed)."\n";
          $idleTime += ($endOfPeriod - $lastUsed);
        }
      }
      print " Total idle time for drive ".$d->id." is ";
      print dispInterval($idleTime).
          sprintf("(%.2f%%)\n", (($idleTime * 100) / (24 * 60 * 60 * $period)));
    }
  }
}

if ($opts{'u'}) {
  my @dl = NBU::Drive->pool;

  @dl = sort { $a->id <=> $b->id} (@dl);

  my $stepSize = 5 * 60;
  my $endOfPeriod = $asOf + (24 * 60 * 60) * $period;

  print "Time,Drive,Busy\n";
  foreach my $d (@dl) {
    my $id = $d->id;
    my $usage = $d->usage;
    @$usage = (sort {$$a{START} <=> $$b{START} } @$usage);

    my $step = $asOf;
    my $use = shift @$usage;
    my $mount = $$use{MOUNT};
    my $job = $mount->job;
    my $du = 1;
    if ($opts{'t'}) {
      $du = sprintf("%.2f", ($mount->speed / 1024));
      $du = 0 if ($job->client->name eq $opts{'n'});
    }

    while ($step < $endOfPeriod) {
      if (!defined($use) || ($step < $$use{START})) {
        print "\"".localtime($step)."\",$id,0\n";
      }
      elsif ($step < $$use{STOP}) {
        print "\"".localtime($step)."\",$id,$du\n";
      }
      else {
        $use = shift @$usage;
        if (defined($use) && defined($mount = $$use{MOUNT})) {
          $du = 1;
          if ($opts{'t'}) {
            $du = sprintf("%.2f", ($mount->speed / 1024));
            $du = 0 if ($job->client->name eq $opts{'n'});
          }
        }
        else {
          $du = 0;
        }
        next;
      }
      $step += $stepSize;
    }
  }
}
