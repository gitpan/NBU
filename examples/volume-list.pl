#!/usr/local/bin/perl

use strict;

use Getopt::Std;
use Time::Local;

my %opts;
getopts('duUaAfFe:m:', \%opts);

use NBU;
NBU->debug($opts{'d'});

NBU::Media->populate(1);

my @list = NBU::Media->listIDs;
for my $id (sort @list) {
  my $m = NBU::Media->byID($id);

print STDERR "Trouble: ".$m->id." does not equal ".$m->barcode."\n" if ($m->id ne $m->barcode);

  print $m->id.
        ": ".($m->robot ? $m->robot->id : " ").
        ": ".$m->type.
        ": ".(defined($m->pool) ? $m->pool->name : "NONE").
        ": ".(defined($m->group) ? $m->group : "NONE").
        ($m->allocated ? ": Allocated" : "").
        ($m->frozen ? ": Frozen" : "").
        "\n";
}
