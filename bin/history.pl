#!/usr/local/bin/perl -w

use strict;

use Getopt::Std;

use NBU;

my %opts;
getopts('?vnbadfRc:', \%opts);

if ($opts{'?'}) {
  print <<EOT;
history.pl [-a] [-f] [-R] [-c <class-regexp>] <client-name>
EOT
  exit 0;
}

sub dispInterval {
  my $i = shift;

  return "--:--:--" if (!defined($i));

  my $seconds = $i % 60;  $i = int($i / 60);
  my $minutes = $i % 60;
  my $hours = int($i / 60);

  my $fmt = sprintf("%02d", $seconds);
  $fmt = sprintf("%02d:", $minutes).$fmt;
  $fmt = sprintf("%02d:", $hours).$fmt;
  return $fmt;
}

#
# Activate internal debugging if -d was specified
NBU->debug($opts{'d'});

#
# The remaining arguments are the names of hosts whose image history
# is to be analyzed
push @ARGV, NBU->me->name if (@ARGV == 0);
my $displayHostName = ($#ARGV > 0);
for my $clientName (@ARGV) {

  print "$clientName\:\n" if ($displayHostName);
  my $h = NBU::Host->new($clientName);

  my $n = 0;
  my %found;
  foreach my $image (sort { $b->ctime <=> $a->ctime} $h->images) {
    $n++;

    if ($opts{'c'}) {
      my $classPattern = $opts{'c'};
      next unless ($image->class->name =~ /$classPattern/);
    }
    my $key = $image->class->name."/".($opts{'n'} ? $image->schedule->name : $image->schedule->type);
    next if (!$opts{'a'} && exists($found{$key}));

    $found{$key} += 1;

    printf("%4u:", $n);

    my $id = $key;
    if ($opts{'b'}) {
      $id .= " (".$image->id.")";
    }

    print substr(localtime($image->ctime), 4)." $id";
    print " wrote ".$image->size if (defined($image->size));
    print " in ".dispInterval($image->elapsed) if ($opts{'v'});
    print " Expires ".substr(localtime($image->expires), 4);
    print "\n";
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
