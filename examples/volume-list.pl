#!/usr/local/bin/perl

#use strict;

use Getopt::Std;
use Time::Local;
use POSIX qw(strftime);

my %opts;
getopts('dcuUaAfFe:m:', \%opts);

use NBU;
NBU->debug($opts{'d'});

sub dispInterval {
  my $i = shift;

  my $seconds = $i % 60;  $i = int($i / 60);
  my $minutes = $i % 60; $i = int($i / 60);
  my $hours = $i % 24;
  my $days = int($i / 24);

  my $fmt = sprintf("%02d", $seconds);
  $fmt = sprintf("%02d:", $minutes).$fmt;
  $fmt = sprintf("%02d:", $hours).$fmt;
  $fmt = "$days days ".$fmt if ($days);
  return $fmt;
}

NBU::Media->populate(1);

sub levelStatusSort {

  return -1 if (!$a->pool);
  return 1 if (!$b->pool);
  if (my $notSame = $a->pool->name cmp $b->pool->name) {
    return $notSame;
  }

  return -1 if (!$a->allocated);
  return 1 if (!$b->allocated);
  if (my $notSame = $a->retention->level <=> $b->retention->level) {
    return $notSame;
  }

  return $a->allocated <=> $b->allocated;
}

my $csv, $io;
if ($opts{'c'}) {
  eval "use Text::CSV_XS";
  $csv = Text::CSV_XS->new();

  my @heading = ('ID', 'pool', 'group', 'allocated', 'return-date');
  $csv->combine(@heading);
  print $csv->string."\n";
}

my @list = NBU::Media->list;
for my $m (sort levelStatusSort @list) {

#print STDERR "Trouble: ".$m->id." does not equal ".$m->barcode."\n" if ($m->id ne $m->barcode);

  if ($opts{'c'}) {
    $csv->combine($m->id,
      (defined($m->pool) ? $m->pool->name : "NONE"),
      (defined($m->group) ? $m->group : "NONE"),
      ($m->allocated ? strftime("%D %R", localtime($m->allocated)) : ""),
      (defined($m->offsiteLocation) ? strftime("%D %R", localtime($m->offsiteReturnDate)) : ""),
    );
    print $csv->string;
  }
  else {
    print $m->id
	  .": ".($m->robot ? $m->robot->id : " ")
	  .": ".$m->type
	  .": ".(defined($m->pool) ? $m->pool->name : "NONE")
	  .": ".(defined($m->group) ? $m->group : "NONE")
	  .($m->allocated ? ": Allocated ".substr(localtime($m->allocated), 4).": rl ".$m->retention->level : "")
	  .($m->mpx ? ": Multiplexed" : "")
  #	.($m->full ? ": Filled in ".dispInterval($m->fillTime) : "")
	  ;
    if (defined($m->offsiteLocation)) {
      print " at ".$m->offsiteLocation."/".(defined($m->offsiteSlot) ? sprintf("%4d", $m->offsiteSlot) : "????");
      print " return ".substr(localtime($m->offsiteReturnDate), 4);
    }
    print ": Frozen" if ($m->frozen);
  }
  print "\n";
}
