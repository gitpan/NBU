#!/usr/local/bin/perl

use strict;

use Getopt::Std;
use Time::Local;

my %opts;
getopts('aidCtc:', \%opts);

use NBU;
NBU->debug($opts{'d'});

NBU::Class->populate;

my @list = NBU::Class->list;
for my $c (sort {$a->name cmp $b->name} @list) {

  if ($opts{'c'}) {
    my $classPattern = $opts{'c'};
    next unless ($c->name =~ /$classPattern/);
  }

  next if (!$c->active && !(defined($opts{'a'}) || defined($opts{'i'})));
  next if ($c->active && defined($opts{'i'}));

  my $description = "";
  $description .= $c->type.": " if ($opts{'t'});
  $description .=  $c->name;
  print $description."\n";
  if ($opts{'C'}) {
    for my $client (sort {$a->name cmp $b->name} $c->clientList) {
      print "  ".$client->name."\n";
    }
  }
}
