#!/usr/local/bin/perl

use strict;
use Getopt::Std;

my %opts;
getopts('d', \%opts);

use NBU;
NBU->debug($opts{'d'});

my $scratch = NBU::Pool->scratch;
die "No scratch pool defined\n" unless (defined($scratch));

print STDERR "Using scratch pool ".$scratch->name."\n";

my %itchy = (
  'MAXpool' => 1,
);

NBU::Media->populate(1);
my $tc = 0;
my $sc = 0;
for my $m (NBU::Media->list) {
  $tc += 1;

  next if ($m->allocated || $m->cleaningTape);
  next if (defined($m->pool) && !exists($itchy{$m->pool->name}));

  $sc += 1;
  print "Could scratch ".$m->id."\n";
}
printf("Scratched $sc volumes (%.2f%%)\n", ($sc * 100) / $tc);
