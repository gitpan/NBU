#!/usr/local/bin/perl

use strict;

use Getopt::Std;
use Time::Local;

my %opts;
getopts('pasfaidmvc:t:', \%opts);

use NBU;
NBU->debug($opts{'d'});

NBU::Class->populate;

my @list;
if ($#ARGV > -1 ) {
  for my $className (@ARGV) {
    my $class = NBU::Class->byName($className);
    push @list, $class if (defined($class));
  }
}
else {
  
  @list = (sort {
		  my $r = $a->type cmp $b->type;
		  $r = $a->name cmp $b->name if ($r == 0);
		  return $r;
		} (NBU::Class->list));
}

my %clientNames;
my $classCount;
for my $c (@list) {

  next if (!$c->active && !(defined($opts{'a'}) || defined($opts{'i'})));
  next if ($c->active && defined($opts{'i'}));
  next unless (!defined($opts{'c'}) || ($c->name =~ /$opts{'c'}/));
  next unless (!defined($opts{'t'}) || ($c->type =~ /$opts{'t'}/));

  $classCount += 1;
  my $description = "";
  $description .=  $c->name;
  $description .= ": ".$c->type if ($opts{'v'});
  print $description."\n";
  my @ifl = $c->include;
  if ($opts{'f'}) {
    if (@ifl) {
      print "Included:\n";
      for my $if (@ifl) {
	print "\t$if\n" unless ($if eq "NEW_STREAM");
      }
    }

    my @efl = $c->exclude;
    if (@efl) {
      print "Excluded:\n";
      for my $ef (@efl) {
	print "\t$ef\n";
      }
    }
  }

  my @cl = (sort {$a->name cmp $b->name} $c->clients);
  if (@cl) {
    print "  Clients:\n" if ($opts{'m'});
    for my $client (@cl) {
      $clientNames{$client->name} += 1;
      print "    ".$client->name."\n" if ($opts{'m'});
    }
  }
  elsif ($opts{'a'}) {
    print "  No allowed clients!\n";
  }

  if ($opts{'s'}) {
    my @sl = $c->schedules;
    if (@sl) {
      print "  Schedules:\n";
    }
    for my $s (@sl) {
      print "    ".$s->name." (".$s->type.")\n";
    }
  }
}
my $clientCount = (keys %clientNames);
print "For a total of $classCount classes used by $clientCount clients\n";
