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

my $program = $0;  $program =~ s /^.*\/([^\/]+)$/$1/;

my %opts;
getopts('vldrs:p:', \%opts);

my $interval = 60;
if (defined($opts{'s'})) {
  $interval = $opts{'s'};
}

my $passLimit = $opts{'p'};
my $refreshCounter = 0;

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
sub sortByMediaServer {

  return ($a->mediaServer->name cmp $b->mediaServer->name);
}
sub sortByStorageUnit {

  return ($a->storageUnit->label cmp $b->storageUnit->label);
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
my $sortColumn = "JOBID";

sub menu {
  my $answer = shift;
  my $win = shift;

  if ($answer eq 'o') {
    $win->addstr(2, 0, "Order by: (v)olume (d)rive (s)ize (t)hroughput (i)d (c)lient (m)ediaserver?");
    my $o = $win->getch();
    if ($o eq 'd') {
      $sortOrder = \&sortByDrive;
      $sortColumn = "DRIVE";
    }
    elsif ($o eq 'v') {
      $sortOrder = \&sortByVolume;
      $sortColumn = "VOLUME";
    }
    elsif ($o eq 'i') {
      $sortOrder = \&sortByID;
      $sortColumn = "JOBID";
    }
    elsif ($o eq 's') {
      $sortOrder = \&sortBySize;
      $sortColumn = "SIZE";
    }
    elsif ($o eq 'c') {
      $sortOrder = \&sortByClient;
      $sortColumn = "CLIENT";
    }
    elsif ($o eq 'm') {
      $sortOrder = \&sortByMediaServer;
      $sortColumn = "SRVR";
    }
    elsif ($o eq 'u') {
      $sortOrder = \&sortByStorageUnit;
      $sortColumn = "STU";
    }
    elsif ($o eq 't') {
      $sortOrder = \&sortByThroughput;
      $sortColumn = "SPD";
    }
  }
  elsif ($answer eq "s") {
    $win->addstr(2, 0, "Seconds to delay between refresh:");
    echo();  $win->getstr(2, 34, $answer);  noecho();
    if ($answer =~ /^[\d]+$/) {
      $interval = $answer;
    }
  }
  elsif ($answer eq "d") {
    $win->addstr(2, 0, "Number of display passes:");
    echo();  $win->getstr(2, 26, $answer);  noecho();
    if ($answer =~ /^[\d]+$/) {
      $passLimit = $refreshCounter + $answer;
    }
  }
  elsif (($answer eq "?") || ($answer eq 'h')) {
    my $lines = $LINES-10;  my $cols = $COLS-10;
    my $help = $win->subwin($lines, $cols, 5, 5);
    $help->clear();  $help->box('|', '-');

    $help->addstr(1, 2, "$program - A NetBackup job monitoring tool written in Perl");
    $help->addstr(3, 2, "These single-character commands are available:");

    my $r = 5;
    $help->addstr($r, 2, "h or ?");
      $help->addstr($r, 9, "- help; show this text");
    $help->addstr($r+=1, 2, "s");
      $help->addstr($r, 9, "- change number of seconds to delay between updates");
    $help->addstr($r+=1, 2, "d");
      $help->addstr($r, 9, "- set number of display passes");
    $help->addstr($r+=1, 2, "o");
      $help->addstr($r, 9, "- specify sort order");
    $help->addstr($r+=1, 2, "r");
      $help->addstr($r, 9, "- force a refresh");
    $help->addstr($r+=1, 2, "q");
      $help->addstr($r, 9, "- quit");

    $help->attron(A_REVERSE);
    $help->addstr($lines-2, 2, "Hit any key to continue:");
    $help->attroff(A_REVERSE);

    $win->touchwin();
    $help->refresh();
    $win->getch();
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

local $SIG{WINCH} = sub {
  print STDERR "Terminal resized...";
#  initscr();
  $win = new Curses;
  $win->clear();
  $win->refresh()
};


my $hdr = sprintf("%15s", "CLIENT    ");
if ($opts{'v'}) {
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
$hdr .= " ".sprintf("%4s", $opts{'r'} ? "STU" : "DRIVE");

while (!$passLimit || ($refreshCounter <= $passLimit)) {
  my $jobCount = 0;
  my $totalSpeed = 0;
  my $totalWireSpeed = 0;
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
    if ($opts{'v'}) {
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
      else {
	if (defined($job->storageUnit)) {
	  $jobDescription .= " in ".$job->storageUnit->label;
	}
      }
    }
    my $alert = 0;
    if (defined($speed)) {

      $totalSpeed += $speed;
      $totalWireSpeed += $speed if ($job->mediaServer != $job->client);

      if ($job->dataWritten > (30 * 1024)) {
	$alert |= ($job->class->name eq "NBUPR2") && ($speed < 5);
	$alert |= ($job->class->name eq "PR2_SAP_ARCHIVES") && ($speed < 1.5);
      }
    }
    $win->attron(A_REVERSE) if ($alert);
    $win->addstr(4 + $jobCount++, 1, $jobDescription);
    $win->attroff(A_REVERSE) if ($alert);
  }

  my $down = 0;
  my $total = 0;
  if (!$opts{'r'}) {
    for my $d (NBU::Drive->pool) {
      next unless (defined($d->robot));
      $total++;
      $down++ if ($d->down);
    }
  }
  $win->addstr(0, 0, "Pass $refreshCounter; $jobCount active jobs; Drives: $down down out of $total");
  $refreshCounter++;
  my $timestamp = localtime;
  $win->addstr(0, $COLS-length($timestamp), $timestamp);

  $totalSpeed = sprintf("%.2f", $totalSpeed);
  $totalWireSpeed = sprintf("%.2f", $totalWireSpeed);
  $win->addstr(1, 0, "Throughput ${totalSpeed}Mb/s; Network load ${totalWireSpeed}Mb/s");

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

=head1 NAME

nbutop.pl - An active backup job monitoring utility for NetBackup

=head1 SUPPORTED PLATFORMS

=over 4

=item * 

Any media server platform support by NetBackup which has curses terminal
capabilities.


=back

=head1 SYNOPSIS

    To come...

=head1 DESCRIPTION


=head1 SEE ALSO

=over 4

=item L<js.pl|js.pl>

=back

=head1 AUTHOR

Winkeler, Paul pwinkeler@pbnj-solutions.com

=head1 COPYRIGHT

Copyright (C) 2002 Paul Winkeler

=cut
