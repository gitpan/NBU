#
# Top level entry point for the NBU module set to inspect, report on and
# occasionally manipulate a Veritas NetBackup environment.
#
# Copyright (c) 2002 Paul Winkeler.  All Rights Reserved.
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.
#
package NBU;

require 5.005;

use IPC::Open2;

use strict;
use Carp;

use NBU::Class;
use NBU::Retention;
use NBU::Media;
use NBU::Pool;
use NBU::Image;
use NBU::Fragment;
use NBU::Mount;
use NBU::Host;
use NBU::Schedule;
use NBU::Robot;
use NBU::StorageUnit;
use NBU::Job;
use NBU::License;

BEGIN {
  use Exporter   ();
  use AutoLoader qw(AUTOLOAD);
  use vars       qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS $AUTOLOAD);
  $VERSION =	 do { my @r=(q$Revision: 1.32 $=~/\d+/g); sprintf "%d."."%02d"x$#r,@r };
  @ISA =         qw();
  @EXPORT_OK =   qw();
  %EXPORT_TAGS = qw();
}

my $NBUVersion;
my $NBP;
my $sudo;

my $PS;
my $NBdir;
my $MMdir;

#
# Determine the path to the top of the NetBackup binaries
if (exists($ENV{"WINDIR"})) {

  $PS = "\\";

  require Win32::TieRegistry || die "Cannot require Win32::TieRegistry!";

  *Registry = *Win32::TieRegistry::Registry;

  # The preferred way to code this is to take control of the Registry symbol
  # table entry with:
  # our $Registry;
  # However that requires at least Perl 5.6 :-(
  no strict "vars";

  my($PATHS) = "HKEY_LOCAL_MACHINE\\SOFTWARE\\VERITAS\\NetBackup\\CurrentVersion\\Paths";

  $NBdir = $Registry->{ $PATHS . "\\_ov_fs"       } . "\\" .
           $Registry->{ $PATHS . "\\SM_DIR"       } . "\\" .
	   $Registry->{ $PATHS . "\\BP_DIR_NAME"  };

  $MMdir =  $Registry->{ $PATHS . "\\_ov_fs"       } . "\\" .
	    $Registry->{ $PATHS . "\\SM_DIR"       } . "\\" .
	    $Registry->{ $PATHS . "\\VM_DIR_NAME"  };
}
else {
  if (-e ($NBP = "/usr/openv")) {
    $PS = "/";
    $NBdir = "/usr/openv/netbackup";
    $MMdir = "/usr/openv/volmgr";

    #
    # If we can execute them as is great, else insert sudo
    $sudo = "";
    if (!-x $NBP."/volmgr/bin/vmoprcmd")  {
      if (-x "/usr/local/bin/sudo") {
        $sudo = "/usr/local/bin/sudo ";
      }
      else {
	die "Unable to execute NetBackup binaries\n";
      }
    }
  }
  else {
    die "Expected NetBackup installation at $NBP\n";
  }
}

my $debug = undef;
sub debug {
  my $proto = shift;
  
  if (@_) {
    $debug = shift;
  }
  return $debug;
}

my %cmdList = (
  bpclntcmd => $sudo."${NBdir}${PS}bin${PS}bpclntcmd",
  bpconfig => $sudo."${NBdir}${PS}bin${PS}admincmd${PS}bpconfig",
  bpgetconfig => $sudo."${NBdir}${PS}bin${PS}admincmd${PS}bpgetconfig",
  bpcllist => $sudo."${NBdir}${PS}bin${PS}admincmd${PS}bpcllist",
  bpclclients => $sudo."${NBdir}${PS}bin${PS}admincmd${PS}bpclclients",
  bpcoverage => $sudo."${NBdir}${PS}bin${PS}admincmd${PS}bpcoverage",
  bpflist => $sudo."${NBdir}${PS}bin${PS}admincmd${PS}bpflist",
  bpmedialist => $sudo."${NBdir}${PS}bin${PS}admincmd${PS}bpmedialist",
  bpdbjobs => $sudo."${NBdir}${PS}bin${PS}admincmd${PS}bpdbjobs",
  bpmedia => $sudo."${NBdir}${PS}bin${PS}admincmd${PS}bpmedia",
  bpimmedia => $sudo."${NBdir}${PS}bin${PS}admincmd${PS}bpimmedia",
  bpimagelist => $sudo."${NBdir}${PS}bin${PS}admincmd${PS}bpimagelist",
  bpstulist => $sudo."${NBdir}${PS}bin${PS}admincmd${PS}bpstulist",
  bpretlevel => $sudo."${NBdir}${PS}bin${PS}admincmd${PS}bpretlevel",
  bperror => $sudo."${NBdir}${PS}bin${PS}admincmd${PS}bperror",
  bpminlicense => $sudo."${NBdir}${PS}bin${PS}admincmd${PS}bpminlicense",

  bperrcode => $sudo."${NBdir}${PS}bin${PS}goodies${PS}bperrcode",

  vmoprcmd => $sudo."${MMdir}${PS}bin${PS}vmoprcmd",
  vmquery => $sudo."${MMdir}${PS}bin${PS}vmquery",
  vmchange => $sudo."${MMdir}${PS}bin${PS}vmchange",
  vmpool => $sudo."${MMdir}${PS}bin${PS}vmpool",
  vmcheckxxx => $sudo."${MMdir}${PS}bin${PS}vmcheckxxx",
  vmupdate => $sudo."${MMdir}${PS}bin${PS}vmupdate",
  vmglob => $sudo."${MMdir}${PS}bin${PS}vmglob",
);

my $vmchangeDelay = 1;
my $lastChange = 0;

my $pipeNames = "PIPE00";
sub cmd {
  my $proto = shift;
  my $cmdline = shift;
  my $biDirectional;
  my $quash = " 2> /dev/null ";

  my $originalCmdline = $cmdline;
  #
  # Providing one's own trailing pipe is deprecated
  $cmdline =~ s/[\s]*\|[\s]*$//;

  if ($cmdline =~ s/^[\s]*\|[\s]*//) {
    $biDirectional = 1;
  }

  my $cmd = $cmdline;
  my $arglist = "";
  if ((my $argoffset = index($cmdline, " ")) >= 0) {
    $cmd = substr($cmdline, 0, $argoffset);
    $arglist = substr($cmdline, $argoffset+1);
  }

  if (!exists($cmdList{$cmd})) {
    print STDERR "Not aware of such a NetBackup command as \"$cmd\" extracted from\n\t$originalCmdline";
    return undef;
  }

  $cmdline = $cmdList{$cmd}." ".$arglist;
  if ($debug) {
    print STDERR "Executing: ".(defined($biDirectional) ? "bi-directional " : "")."$cmdline\n";
  }

  if ($cmd eq "vmchange") {
    if ((my $gap = time - $lastChange) < $vmchangeDelay) {
      print STDERR "Delay ($vmchangeDelay - $gap) for vmchange\n" if ($debug);
      sleep($vmchangeDelay - $gap);
    }
    $lastChange = time;
  }
    
  if (defined($biDirectional)) {
    my $readPipe = $pipeNames++;
    my $writePipe = $pipeNames++;
    no strict 'refs';
    open2($readPipe, $writePipe, $cmdline.$quash);
    return (*$readPipe{IO}, *$writePipe{IO});
  }
  elsif (!@_) {
    my $pipe = $pipeNames++;
    no strict 'refs';
    open($pipe, $cmdline.$quash." |");
    return *$pipe{IO};
  }
  else {
    system($cmdline."\n");
    return undef;
  }
}

my ($me, $master, @servers, @knownMasters);
my $adminAddress;
sub loadClusterInformation {

  my $myName = "localhost";

  #
  # Find out my own name (as far as NetBackup is concerned anyway).
  my $pipe = NBU->cmd("bpclntcmd -self |");
  while (<$pipe>) {
    chop;
    if (/gethostname\(\) returned: ([\S]+)/) {
      $myName = $1;
    }
  }
  close($pipe);

  #
  # Probe around to determine the full set of servers in this NetBackup
  # environment.  First we use bpgetconfig to locate the master in this
  # environment.  Then we use the same program to get the master to re-
  # gurgitate the full list of servers.
  $master = $me = NBU::Host->new($myName);  $myName = $me->name;
  $master = $me->clientOf
    if ($me->clientOf);
  push @knownMasters, $master;
  $NBUVersion = $me->NBUVersion;

  close($pipe);

  $pipe = NBU->cmd("bpgetconfig -M ".$master->name." |");
  while (<$pipe>) {
    if (/SERVER = ([\S]+)/) {
      my $serverName = $1;
      my $server = NBU::Host->new($serverName);
      push @servers, $server;
    }
    if (/KNOWN_MASTER = ([^\s,]+)/) {
      my $serverName = $1;
      my $server = NBU::Host->new($serverName);
      push @knownMasters, $server
	unless ($server == $master);
    }
  }
  close($pipe);

  $pipe = NBU->cmd("bpconfig -M ".$master->name." -l |");
  $_ = <$pipe>;
  my (
    $email, $wakeupInterval,
    $retryPeriod,
    $maxClientJobs,
    $retryCount,
    $logFileRetentionPeriod,
    $u1, $u2, $u3, $u4,
    $immediatePostProcess,
    $reportDisplayWindow,
    $TIRRetentionPeriod,
    $prepInterval
  ) = split;
  $email = undef if ($email eq "*NULL*");
  $adminAddress = $email;
}

sub masters {
  my $proto = shift;

  loadClusterInformation() if (!defined($me));
  return (@knownMasters);
}

sub master {
  my $proto = shift;

  loadClusterInformation() if (!defined($me));
  return ($master == $me);
}

sub me {
  my $proto = shift;

  loadClusterInformation() if (!defined($me));
  return $me;
}

sub servers {
  my $proto = shift;

  loadClusterInformation() if (!defined($me));
  return @servers;
}

sub adminAddress {
  my $proto = shift;

  loadClusterInformation() if (!defined($me));
  return $adminAddress;
}

my $msgsLoaded;
my %msgs;
sub loadErrorMessages {
  my $proto = shift;

  $msgsLoaded = 0;
  my $pipe = NBU->cmd("bperrcode  |");
  while (<$pipe>) {
    chop;
    my ($code, $msg) = split(/ /, $_, 2);
    $msgs{$code} = $msg;
    $msgsLoaded += 1;
  }
  close($pipe);
}

sub errorMessage {
  my $proto = shift;

  NBU->loadErrorMessages if (!defined($msgsLoaded));

  my $code = shift;
  return $msgs{$code};
}

sub date {
  my $proto = shift;
  my $epochTime = shift;

  my ($s, $m, $h, $mday, $mon, $year, $wday, $yday, $isdst) = localtime($epochTime);
  $year += 1900;
  my $mm = $mon + 1;
  my $dd = $mday;
  my $yyyy = $year;

  return "$mm/$dd/$yyyy $h:$m:$s";
}

1;

__END__

=head1 NAME

NBU - Main entry point for NetBackup OO Modules

=head1 SUPPORTED PLATFORMS

=over 4

=item * 

Solaris

=item * 

Windows/NT

=back

=head1 SYNOPSIS

    To come...

=head1 DESCRIPTION

This module provides generic support for the entire collection of NBU::* modules.  Not
only does it ensure that all other modules are properly "use"d but it also provides several
methods to these other modules to hide the details of the NetBackup environment.

=head1 SEE ALSO

=over 4

=item L<NBU::Media|NBU::Media>

=back

=head1 AUTHOR

Winkeler, Paul pwinkeler@pbnj-solutions.com

=head1 COPYRIGHT

Copyright (C) 2002 Paul Winkeler

=cut
