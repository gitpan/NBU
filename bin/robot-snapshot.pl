#!/usr/local/bin/perl -w

use strict;
use Getopt::Std;

use lib '/usr/local/lib/perl5';

use XML::Simple;
use NBU;

my %opts;
getopts('ohdispf:', \%opts);

NBU->debug($opts{'d'});

my $file = "/usr/local/etc/robot.conf";
if (defined($opts{'f'})) {
  $file = $opts{'f'};
  die "No such configuration file: $file\n" if (! -f $file);
}

my $xs1 = XML::Simple->new(forcearray => 1);
my $config;
if (-f $file) {
  $config = eval { $xs1->XMLin($file, forcearray => 1) };
  die "robot-snapshot.pl: Could not parse XML configuration file $file\n" unless (defined($config));
}

NBU::Media->populate(1);

for my $robot (NBU::Robot->farm) {

  next unless defined($robot);

  my $r = $robot->id;
  my @l = $robot->slotList;

  my $prefix;
  if ($opts{'h'}) {
    print "Robot number $r on ".$robot->host->name."\n";
    $prefix = "   ";
  }
  else {
    $prefix = "$r\: ";
  }

  my $volumeCount = 0;
  my $netbackupCount = 0;
  my $cleanCount = 0;  my $cleanings = 0;
  my %poolCount;
  my %emptyCount;  my %fullCount;
  my %frozenCount;

  my $oldest;
  for my $position (1..$robot->capacity) {
    $position = sprintf("%03d", $position);
    my $slot;
    my $display = $opts{'i'};
    my $comments = "";
    if (my $volume = $l[$position]) {
      $volumeCount += 1;
      $slot = "$prefix$position\: ".$volume->id;
      if (defined($volume)) {
	if ($volume->netbackup) {
	  $netbackupCount += 1;
	  $slot .= " ".$volume->pool->name if ($opts{'p'});
	  $slot .= " *";
          $poolCount{$volume->pool->name} += 1;
	}
        elsif (!$volume->cleaningTape) {
	  $slot .= " ".$volume->pool->name if ($opts{'p'});
          if ($volume->allocated) {
            $slot .= " ALLOCATED";
	    if ($volume->full) {
              $slot .= " FULL";
              $fullCount{$volume->pool->name} += 1;
	    }
	    if ($volume->frozen) {
              $slot .= " FROZEN";
              $frozenCount{$volume->pool->name} += 1;
	    }
	    if (!defined($oldest) || ($volume->allocated < $oldest->allocated)) {
	      $oldest = $volume;
	    }
            if ($volume->expires < time) {
              $slot .= " EXPIRED";
	    }
	    else {
	      $slot .= " expires ".substr(localtime($volume->expires), 4);
	    }
	    $slot .= " rl=".$volume->retention->level;
          }
          else {
            $emptyCount{$volume->pool->name} += 1;
          }
          $poolCount{$volume->pool->name} += 1;
        }
        elsif ($volume->cleaningTape) {
          $cleanCount += 1;
          $cleanings += $volume->cleaningCount;
	  if ($volume->cleaningCount == 0) {
	    $display ||= 1;
	    $comments = " <-- No cleanings left!";
	  }

        }
      }
    }
    else {
      $slot = "$prefix$position\: <EMPTY>";
    }
    print "$slot$comments\n" if ($display);
  }

  my $emptyCount = 0;
  my $fullCount = 0;

  my $robotConfig = $config ? $$config{robot}->{$r} : undef;

  if (my $constraint = $robotConfig->{netbackup}) {
    my $target = $$constraint[0]->{total};
    if ((my $n = ($target - $netbackupCount)) > 0) {
      print "${prefix}  Add $n NetBackup volumes\n";
    }
  }

  my $levels = $robotConfig->{pool};
  foreach my $pool (keys %poolCount) {
    my $poolSpecs = $levels ? $$levels{$pool} : undef;

    my $total = sprintf("%3u", $poolCount{$pool});
    my $empty = $emptyCount{$pool} += 0;
    my $full = $fullCount{$pool} += 0;
    my $partial = $total - $full - $empty;
    my $frozen = $frozenCount{$pool} += 0;

    if ($poolSpecs) {

      print "${prefix}$total $pool\: $empty/$partial/$full\n";

      if (defined(my $limit = $$poolSpecs{'frozen'})) {
	if ($frozen > $limit) {
	  my $count = $frozen - $limit;
	  print "${prefix}     Remove $count frozen $pool volumes\n";
	}
      }
      if (defined(my $limit = $$poolSpecs{'full'})) {
	if ($full > $limit) {
	  my $count = $full - $limit;
	  print "${prefix}     Remove $count full $pool volumes\n";
	}
      }
      if (defined(my $limit = $$poolSpecs{'empty'})) {
	if ($empty < $limit) {
	  my $count = $limit - $empty;
	  print "${prefix}     Add $count empty $pool volumes\n";
	}
      }

      $emptyCount += $empty;
      $fullCount += $full;
    }
    elsif ($levels) {
      my $count = $total - 0;
      print "${prefix}$total $pool\n";
      print "${prefix}     Remove $count disallowed $pool volumes\n";
    }
    else {
      $emptyCount += $empty;
      $fullCount += $full;
    }
  }

  if ($opts{'s'}) {
    print "${prefix}$volumeCount out of ".$robot->capacity." occupied\n";
    print "${prefix}$emptyCount completely empty volumes available\n";
    print "${prefix}$cleanings cleanings left on $cleanCount cleaning volumes\n";
  }
  if ($opts{'o'}) {
    print "${prefix}Oldest volume is ".$oldest->id." expiring on ".localtime($oldest->expires)."\n";
  }
}
