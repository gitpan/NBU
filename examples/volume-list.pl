#!/usr/local/bin/perl

use strict;

use Getopt::Std;
use Time::Local;

my %opts;
getopts('duUaAfFe:m:', \%opts);

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

my @list = NBU::Media->list;
for my $m (sort levelStatusSort @list) {

#print STDERR "Trouble: ".$m->id." does not equal ".$m->barcode."\n" if ($m->id ne $m->barcode);

  print $m->id.
        ": ".($m->robot ? $m->robot->id : " ").
        ": ".$m->type.
        ": ".(defined($m->pool) ? $m->pool->name : "NONE").
        ": ".(defined($m->group) ? $m->group : "NONE").
        ($m->allocated ? ": Allocated on ".substr(localtime($m->allocated), 4)." at rl ".$m->retention->level : "").
        ($m->frozen ? ": Frozen" : "").
	($m->full ? ": Filled in ".dispInterval($m->fillTime) : "").
        "\n";
}
