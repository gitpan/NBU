#!/usr/local/bin/perl

use strict;

use Getopt::Std;
use Time::Local;

my %opts;
getopts('faidCtc:', \%opts);

use NBU;
NBU->debug($opts{'d'});

NBU::Class->populate;

my @list;
if ($#ARGV > -1 ) {
  for my $className (@ARGV) {
    push @list, NBU::Class->new($className);
  }
}
else {
  @list = (sort {$a->name cmp $b->name} (NBU::Class->list));
}


for my $c (@list) {

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
  if ($opts{'f'}) {
    my @fl = $c->include;
    if (@fl) {
      print "Included:\n";
      for my $if (@fl) {
	print "\t$if\n" unless ($if eq "NEW_STREAM");
      }
    }
    @fl = $c->exclude;
    if (@fl) {
      print "Excluded:\n";
      for my $ef (@fl) {
	print "\t$ef\n";
      }
    }
  }
  if ($opts{'C'}) {
    my @cl = (sort {$a->name cmp $b->name} $c->clients);
    if (@cl) {
      print "Clients:\n";
      for my $client (@cl) {
	print "\t".$client->name."\n";
      }
    }
  }
}
