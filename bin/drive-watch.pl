#!/usr/local/bin/perl

use strict;

use Getopt::Std;

my $interval = 5 * 60;

my %opts;
getopts('dM:i:n:', \%opts);
if (defined($opts{'i'})) {
  $interval = $opts{'i'};
}
my $notify = "winkeler";
$notify .= ",".$opts{'n'} if ($opts{'n'});

use NBU;
NBU->debug($opts{'d'});

my $master;
if ($opts{'M'}) {
  $master = NBU::Host->new($opts{'M'});
}
else {
  my @masters = NBU->masters;  $master = $masters[0];
}
my @mediaManagers;
foreach my $server (NBU::StorageUnit->mediaServers($master)) {
  if (NBU::Drive->populate($server)) {
    push @mediaManagers, $server;
  }
}

sub msg {
  my $self = shift;
  my $state = shift;

  #
  # Start counting down drives at one since we are about to be marked as such
  my $down = 1;
  my $total = 0;
  for my $d (NBU::Drive->pool) {
    next unless ($d->known);
    $total++;
    $down++ if ($d->down);
  }

  open (PIPE, "| /usr/bin/mailx -s \"Drive ".$self->id." went $state\" $notify");
  print PIPE "Drive ".$self->id." on ".$self->host->name." went $state, new state is ".$self->control."\n";
  print PIPE "Its comment field read: ".$self->comment."\n";

  print PIPE "\nThere are now $down drives down out of $total\n";
  close(PIPE);
}

foreach my $d (NBU::Drive->pool) {
  next unless $d->known;
  $d->notifyOn("DOWN", \&msg);
}

while (1) {
  system("sleep $interval\n");

  foreach my $server (@mediaManagers) {
    NBU::Drive->updateStatus($server);
  }
}
