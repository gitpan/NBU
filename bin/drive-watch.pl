#!/usr/local/bin/perl

use strict;

use Getopt::Std;

my $interval = 5 * 60;

my %opts;
getopts('di:n:', \%opts);
if (defined($opts{'i'})) {
  $interval = $opts{'i'};
}
my $notify = "winkeler";
$notify .= ",".$opts{'n'} if ($opts{'n'});

use NBU;
NBU->debug($opts{'d'});

foreach my $server (NBU->servers) {
  NBU::Drive->populate($server);
}
sub msg {
  my $self = shift;
  my $state = shift;

  #
  # Start counting down drives at one since we are about to be marked as such
  my $down = 1;
  my $total = 0;
  for my $d (NBU::Drive->pool) {
    next unless (defined($d->robot));
    $total++;
    $down++ if ($d->down);
  }

  open (PIPE, "| /usr/bin/mailx -s \"Drive ".$self->id." went $state\" $notify");
  print PIPE "Drive ".$self->id." on ".$self->host->name." went $state, new state is ".$self->control."\n";
  print PIPE "Its comment field read: ".$self->comment."\n";

  print PIPE "\nThere are now $down drives down out of $total\n";
  close(PIPE);
}

foreach my $drive (NBU::Drive->pool) {
  $drive->notifyOn("DOWN", \&msg);
}

while (1) {
  system("sleep $interval\n");

  foreach my $server (NBU->servers) {
    NBU::Drive->updateStatus($server);
  }
}
