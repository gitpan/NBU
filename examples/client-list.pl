#!/usr/local/bin/perl

use strict;

use Getopt::Std;

my %opts;
getopts('dv', \%opts);

use NBU;
NBU->debug($opts{'d'});

NBU::Host->populate(1);

foreach my $client (sort {$a->name cmp $b->name} (NBU::Host->list)) {
  my $cn = $client->name;

  print $client->name;
  if ($opts{'v'}) {
      my $version = $client->NBUVersion;
      print ": $version";
  }
  print "\n";
}
