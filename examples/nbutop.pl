#!/usr/local/bin/perl -w
#
# Don't be intimidated by the GUI logic.  The juicy, useful bits are in the
# main loop where we call NBU::Drive->updateStatus and NBU::Job->refreshJobs
# to get NBU's data structures synchronized with the real world.
# After that updating the display with information on the active jobs is trivial

use strict;

use lib '/usr/local/lib/perl5';

use Getopt::Std;
use Time::Local;

#
# Download this one from CPAN
use Curses;

my %opts;
getopts('sldri:', \%opts);

my $interval = 60;
if (defined($opts{'i'})) {
  $interval = $opts{'i'};
}

use NBU;
NBU->debug($opts{'d'});

sub dispInterval {
  my $i = shift;

  my $seconds = $i % 60;  $i = int($i / 60);
  my $minutes = $i % 60;
  my $hours = int($i / 60);

  my $fmt = sprintf("%02d", $seconds);
  $fmt = sprintf("%02d:", $minutes).$fmt;
  $fmt = sprintf("%02d:", $hours).$fmt;
  return $fmt;
}

sub sortByDrive {

  my $aDrive = defined($a->volume) && defined($a->volume->drive) ? $a->volume->drive->id : undef;
  my $bDrive = defined($b->volume) && defined($b->volume->drive) ? $b->volume->drive->id : undef;

  return 1 if (!defined($aDrive));
  return -1 if (!defined($bDrive));
  return ($aDrive <=> $bDrive);
}
sub sortByVolume {

  my $aVolume = defined($a->volume) ? $a->volume->id : undef;
  my $bVolume = defined($b->volume) ? $b->volume->id : undef;

  return 1 if (!defined($aVolume));
  return -1 if (!defined($bVolume));
  return ($aVolume cmp $bVolume);
}
sub sortByThroughput {

  return 1 if (!defined($a->dataWritten) || !$a->elapsedTime);
  return -1 if (!defined($b->dataWritten) || !$b->elapsedTime);

  my $aSpeed = $a->dataWritten/$a->elapsedTime;
  my $bSpeed = $b->dataWritten/$b->elapsedTime;

  return ($aSpeed <=> $bSpeed);
}
sub sortBySize {

  my $aSize = defined($a->dataWritten) ? $a->dataWritten : 0;
  my $bSize = defined($b->dataWritten) ? $b->dataWritten : 0;

  return ($bSize <=> $aSize);
}
sub sortByClient {

  return ($a->client->name cmp $b->client->name);
}
sub sortByID {
  my $result;

  $result = ($b->id <=> $a->id);
  return $result;
}
my $sortOrder = \&sortByID;

sub menu {
  my $answer = shift;
  my $win = shift;

  if ($answer eq 'o') {
    $win->addstr(2, 0, "Order by: (v)olume (d)rive (s)ize (t)hroughput (i)d (c)lient?");
    my $o = $win->getch();
    if ($o eq 'd') {
      $sortOrder = \&sortByDrive;
    }
    elsif ($o eq 'v') {
      $sortOrder = \&sortByVolume;
    }
    elsif ($o eq 'i') {
      $sortOrder = \&sortByID;
    }
    elsif ($o eq 's') {
      $sortOrder = \&sortBySize;
    }
    elsif ($o eq 'c') {
      $sortOrder = \&sortByClient;
    }
    elsif ($o eq 't') {
      $sortOrder = \&sortByThroughput;
    }
  }
  elsif ($answer eq "i") {
    $win->addstr(2, 0, "Refresh interval:");
    echo();  $win->getstr(2, 17, $answer);  noecho();
    if ($answer =~ /^[\d]+$/) {
      $interval = $answer;
    }
  }
  elsif (($answer eq "?") || ($answer eq 'h')) {
    $win->refresh();
  }
  $win->move(2, 0);  $win->clrtoeol();
  $win->refresh();

  return 'r';
}

#
# Gather first round of drive data if we're running live
if (!$opts{'r'}) {
  foreach my $server (NBU->servers) {
    NBU::Drive->populate($server);
  }
}

#
# Load the first round of Job data
print STDERR "Loading...";
NBU::Job->loadJobs($opts{'r'}, $opts{'l'});

my $win = new Curses;
noecho();  cbreak();
$win->clear();
$win->refresh();

my $hdr = sprintf("%15s", "CLIENT    ");
if ($opts{'s'}) {
  $hdr .= " ".sprintf("%-40s", "             CLASS/SCHEDULE");
}
else {
  $hdr .= " ".sprintf("%-23s", "         CLASS");
}
$hdr .= " ".sprintf("%7s", " JOBID ");
$hdr .= " ".sprintf("%8s", "  START ");
$hdr .= " ".sprintf("%3s", "OP ");
$hdr .= " ".sprintf("%6s", "VOLUME");
$hdr .= " ".sprintf("%9s", "  SIZE   ");
$hdr .= " ".sprintf("%4s", "SPD ");
$hdr .= " ".sprintf("%4s", "DRIVE");

my $refreshCounter = 0;
while (1) {
  my $jobCount = 0;
  my $totalSpeed = 0;
  my @jl = NBU::Job->list;

  #
  # Sort the job list according to the order du jour
  # For each active job, a description is built up and added to the display
  # in one fell swoop.
  $win->addstr(3, 1, $hdr);
  for my $job (sort $sortOrder (@jl)) {
    next unless ($job->active);


    my $who = sprintf("%15s", $job->client->name);

    my $classID = $job->class->name;
    my $classIDlength = 23;
    if ($opts{'s'}) {
      $classID .= "/".$job->schedule->name;
      $classIDlength = 40;
    }
    $classID = sprintf("%-".$classIDlength."s", $classID);

    my $jid = sprintf("%7u", $job->id);

    my $startTime = ((time - $job->start) < (24 * 60 * 60)) ?
	  substr(localtime($job->start), 11, 8) :
	  " ".substr(localtime($job->start), 4, 6)." ";

    my $jobDescription = "$who $classID $jid $startTime ".$job->operation;

    my $speed;
    if (defined($job->volume)) {
      $jobDescription .= " ".$job->volume->id;
      $jobDescription .= " ".sprintf("%9.2f", ($job->dataWritten/1024));
      $jobDescription .= " ".sprintf("%.2f", $speed = ($job->dataWritten / $job->elapsedTime / 1024))
	if ($job->elapsedTime);
      if (!$opts{'r'}) {
	if ($job->volume->drive) {
	  $jobDescription .= " in ".$job->volume->drive->id;
	}
      }
    }
    my $alert = 0;
    if (defined($speed)) {
      $totalSpeed += $speed;

      if ($job->dataWritten > (30 * 1024)) {
	$alert |= ($job->class->name eq "NBUPR2") && ($speed < 5);
	$alert |= ($job->class->name eq "PR2_SAP_ARCHIVES") && ($speed < 1.5);
      }
    }
    $win->attron(A_REVERSE) if ($alert);
    $win->addstr(4 + $jobCount++, 1, $jobDescription);
    $win->attroff(A_REVERSE) if ($alert);
  }
  $win->addstr(0, 0, "Pass $refreshCounter; $jobCount active jobs; total throughput ".sprintf("%.2f", $totalSpeed)."Mb/s");
  $refreshCounter++;
  my $timestamp = localtime;
  $win->addstr(0, $COLS-length($timestamp), $timestamp);

  if (!$opts{'r'}) {
    my $down = 0;
    my $total = 0;
    for my $d (NBU::Drive->pool) {
      $total++;
      $down++ if ($d->down);
    }
    $win->addstr(1, 0, "Drives: $down down out of $total");
  }

  $win->refresh;

  my $answer;
  eval {
    local $SIG{ALRM} = sub { die "timed out\n"; };

    alarm $interval if ($interval);
    $answer = getch;
    alarm 0 if ($interval);
  };
  if ($@) {
    $answer = 'r';
  }

  last if ($answer eq 'q');

  if ($answer ne 'r') {
    $answer = menu($answer, $win);
  }

  $win->addstr(2, 0, "Refreshing...");  $win->refresh();
  if (!$opts{'r'}) {
    foreach my $server (NBU->servers) {
      NBU::Drive->updateStatus($server);
    }
  }
  if (!defined(NBU::Job->refreshJobs)) {
    last;
  }

  $win->clear;
}
endwin();
