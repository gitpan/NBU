#!/usr/local/bin/perl -w

use strict;

use Getopt::Std;

use NBU;

my %opts;
getopts('?adfRc:', \%opts);

if ($opts{'?'}) {
  print <<EOT;
history.pl [-a] [-f] [-R] [-c <class-regexp>] <client-name>
EOT
  exit 0;
}

#
# Activate internal debugging if -d was specified
NBU->debug($opts{'d'});

#
# The remaining arguments are the names of hosts whose image history
# is to be analyzed
my $displayHostName = ($#ARGV > 0);
for my $clientName (@ARGV) {

  print "$clientName\:\n" if ($displayHostName);
  my $h = NBU::Host->new($clientName);

  my $n = 0;
  my %found;
  foreach my $image ($h->images) {
    $n++;

    if ($opts{'c'}) {
      my $classPattern = $opts{'c'};
      next unless ($image->class->name =~ /$classPattern/);
    }
    my $key = $image->class->name."/".$image->schedule->name;
    next if (!$opts{'a'} && exists($found{$key}));

    $found{$key} += 1;

    printf("%4u:", $n);

    print substr(localtime($image->ctime), 4)." $key";
    print " wrote ".$image->size if (defined($image->size));
    print " Expires ".substr(localtime($image->expires), 4)."\n";
    if ($opts{'f'}) {
      for my $f ($image->fragments) {
	print "     ".$f->number.": File ".$f->fileNumber." on ".$f->volume->id." drive ".$f->driveWrittenOn."\n";
      }
    }
    if ($opts{'R'}) {
      for my $f ($image->fileList) {
	print "      $f\n";
      }
    }
  }
}
