#!/usr/local/bin/perl

use strict;

use Getopt::Std;

my $interval = 5 * 60;

my %opts;
getopts('di:', \%opts);
if (defined($opts{'i'})) {
  $interval = $opts{'i'};
}

use NBU;
NBU->debug($opts{'d'});

foreach my $server (NBU->servers) {
  NBU::Drive->populate($server);
}
sub msg {
  my $self = shift;
  my $state = shift;

  open (PIPE, "| /usr/bin/mailx -s \"Drive ".$self->id." went $state\" winkeler");
  print PIPE "Drive ".$self->id." on ".$self->host->name." went $state, new state is ".$self->control."\n";
  print PIPE "Its comment field read: ".$self->comment."\n";
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
