#!/usr/local/bin/perl

use strict;

use Getopt::Std;
use Time::Local;

my %opts;
getopts('exasfaidmvnc:t:', \%opts);

use NBU;
NBU->debug($opts{'d'});

NBU::Class->populate;


sub printDetail {
  my $h = shift;
  my $d = shift;

  if ($opts{'x'}) {
    print $h;
  }
  else {
    my @elements = split(/\|/, $d);
    my $sep = "";
    foreach my $e (@elements) {
      print $sep."\"$e\"";
      $sep = ",";
    }
    print "\n";
  }
}


sub listSchedules {
  my $c = shift;
  my $lastHeader = shift;
  my $prefix = shift;
  my @detail = @_;

  my $nextDetail = shift(@detail);

  my @sl = $c->schedules;

  if ($opts{'n'}) {
    my @internal;
    for my $s (@sl) {
      push @internal, $s if ($s->type ne "UBAK");
    }
    @sl = @internal;
  }

  my $eCounter = 0;
  if (@sl) {
    for my $s (@sl) {
      my $scheduleName = $s->name;
      if ($opts{'e'}) {
	my $level = $prefix.'|'.$scheduleName;
	my $header = $opts{'x'} ? "<schedule name=\"$scheduleName\">\n" : $scheduleName."\n";
	my $footer = $opts{'x'} ? "</schedule>\n" : "";
	if (defined($nextDetail)) {
          $eCounter = &$nextDetail($c, $lastHeader.$header, $level, @detail)
	}
	else {
	  printDetail($lastHeader.$header, $level);
	  $eCounter += 1;
	}
	print $footer if ($eCounter);
      }
      else {
        print $lastHeader.$prefix.$scheduleName;
      }
      $lastHeader = "";
    }
  }
  if (!$opts{'e'}) {
    &$nextDetail($c, $lastHeader, $prefix."  ", @detail) if (defined($nextDetail));
  }
  return $eCounter;
}

sub listMembers {
  my $c = shift;
  my $lastHeader = shift;
  my $prefix = shift;
  my @detail = @_;

  my $nextDetail = shift(@detail);

  #
  # All members of the policy
  my $eCounter = 0;
  my @cl = (sort {$a->name cmp $b->name} $c->clients);
  if (@cl) {
    for my $client (@cl) {
      my $clientName = $client->name;
      if ($opts{'e'}) {
	my $level = $prefix.'|'.$clientName;
	my $header = $opts{'x'} ? "<client name=\"$clientName\">\n" : $clientName."\n";
	my $footer = $opts{'x'} ? "</client>\n" : "";
	if (defined($nextDetail)) {
          $eCounter = &$nextDetail($c, $lastHeader.$header, $level, @detail)
	}
	else {
	  printDetail($lastHeader.$header, $level);
	  $eCounter += 1;
	}
	print $footer if ($eCounter);
      }
      else {
	print $lastHeader.$prefix.$clientName;
      }
      $lastHeader = "";
    }
  }
  if (!$opts{'e'}) {
    &$nextDetail($c, $lastHeader, $prefix."  ", @detail) if (defined($nextDetail));
  }
  return $eCounter;
}

sub listFiles {
  my $c = shift;
  my $lastHeader = shift;
  my $prefix = shift;
  my @detail = @_;

  my $nextDetail = shift(@detail);

  #
  # All included and excluded files of the policy
  my $eCounter = 0;
  my @ifl = $c->include;
  if (@ifl) {
    for my $if (@ifl) {
      next if ($if eq "NEW_STREAM");
      if ($opts{'e'}) {
	my $header = $opts{'x'} ? "<file path=\"$if\">\n" : $if."\n";
	my $footer = $opts{'x'} ? "</file>\n" : "";
	my $level = $prefix.'|'.$if;
	if (defined($nextDetail)) {
          $eCounter = &$nextDetail($c, $lastHeader.$header, $level, @detail)
	}
	else {
	  printDetail($lastHeader.$header, $level);
	  $eCounter += 1;
	}
	print $footer if ($eCounter);
      }
      else {
	print $lastHeader.$prefix.$if;
      }
      $lastHeader = "";
    }
  }
  if (!$opts{'e'}) {
    &$nextDetail($c, $lastHeader, $prefix."  ", @detail) if (defined($nextDetail));
  }
  return $eCounter;
}

my @detail;
push @detail, \&listSchedules if ($opts{'s'});
push @detail, \&listMembers if ($opts{'m'});
push @detail, \&listFiles if ($opts{'f'});

#
# XML output is created using the '-e' logic
$opts{'e'} = $opts{'x'} if ($opts{'x'});

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

if ($opts{'x'}) {
  print "<?xml version=\"1.0\"?>\n";
  print "<policy-list>\n";
}

my $nextDetail = shift(@detail);
for my $c (@list) {

  next if (!$c->active && !(defined($opts{'a'}) || defined($opts{'i'})));
  next if ($c->active && defined($opts{'i'}));
  next unless (!defined($opts{'c'}) || ($c->name =~ /$opts{'c'}/));
  next unless (!defined($opts{'t'}) || ($c->type =~ /$opts{'t'}/));

  my $policyDescription = "";
  $policyDescription .=  $c->name;
  $policyDescription .= ": ".$c->type if ($opts{'v'});

  my $eCounter = 0;
  if ($opts{'e'}) {
    my $header = $opts{'x'} ? "<policy name=\"$policyDescription\">\n" : $policyDescription."\n";
    my $footer = $opts{'x'} ? "</policy>\n" : "";
    if (defined($nextDetail)) {
      $eCounter = &$nextDetail($c, $header, $policyDescription, @detail)
    }
    else {
      printDetail($header, $policyDescription);
      $eCounter += 1;
    }
    print $footer if ($eCounter);
  }
  else {
    if (defined($nextDetail)) {
      &$nextDetail($c, $policyDescription, "  ", @detail)
    }
    else {
      print $policyDescription;
    }
  }
}
if ($opts{'x'}) {
  print "</policy-list>\n";
}
