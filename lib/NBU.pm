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

BEGIN {
  use Exporter   ();
  use AutoLoader qw(AUTOLOAD);
  use vars       qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS $AUTOLOAD);
  $VERSION =	 do { my @r=(q$Revision: 1.18 $=~/\d+/g); sprintf "%d."."%02d"x$#r,@r };
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
  my $Class = shift;
  
  if (@_) {
    $debug = shift;
  }
  return $debug;
}

my %cmdList = (
  bpclntcmd => $sudo."${NBdir}${PS}bin${PS}bpclntcmd",
  bpgetconfig => $sudo."${NBdir}${PS}bin${PS}admincmd${PS}bpgetconfig",
  bpcllist => $sudo."${NBdir}${PS}bin${PS}admincmd${PS}bpcllist",
  bpclclients => $sudo."${NBdir}${PS}bin${PS}admincmd${PS}bpclclients",
  bpcoverage => $sudo."${NBdir}${PS}bin${PS}admincmd${PS}bpcoverage",
  bpflist => $sudo."${NBdir}${PS}bin${PS}admincmd${PS}bpflist",
  bpmedialist => $sudo."${NBdir}${PS}bin${PS}admincmd${PS}bpmedialist",
  bpdbjobs => $sudo."${NBdir}${PS}bin${PS}admincmd${PS}bpdbjobs",
  bpmedia => $sudo."${NBdir}${PS}bin${PS}admincmd${PS}bpmedia",
  bpimmedia => $sudo."${NBdir}${PS}bin${PS}admincmd${PS}bpimmedia",
  bpstulist => $sudo."${NBdir}${PS}bin${PS}admincmd${PS}bpstulist",
  bpretlevel => $sudo."${NBdir}${PS}bin${PS}admincmd${PS}bpretlevel",

  bperrcode => $sudo."${NBdir}${PS}bin${PS}goodies${PS}bperrcode",

  vmoprcmd => $sudo."${MMdir}${PS}bin${PS}vmoprcmd",
  vmquery => $sudo."${MMdir}${PS}bin${PS}vmquery",
  vmchange => $sudo."${MMdir}${PS}bin${PS}vmchange",
  vmpool => $sudo."${MMdir}${PS}bin${PS}vmpool",
  vmcheckxxx => $sudo."${MMdir}${PS}bin${PS}vmcheckxxx",
  vmglob => $sudo."${MMdir}${PS}bin${PS}vmglob",
);

my $pipeNames = "PIPE00";
sub cmd {
  my $Class = shift;
  my $cmdline = shift;
  my $biDirectional;

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

  if (defined($biDirectional)) {
    my $readPipe = $pipeNames++;
    my $writePipe = $pipeNames++;
    no strict 'refs';
    open2($readPipe, $writePipe, $cmdline);
    return (*$readPipe{IO}, *$writePipe{IO});
  }
  else {
    my $pipe = $pipeNames++;
    no strict 'refs';
    open($pipe, $cmdline." |");
    return *$pipe{IO};
  }
}

my ($me, $master, @servers);
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
  $master = $me = NBU::Host->new($myName);
  $master = $me->clientOf
    if ($me->clientOf);
  $NBUVersion = $me->NBUVersion;

  close($pipe);

  $pipe = NBU->cmd("bpgetconfig -M ".$master->name." |");
  while (<$pipe>) {
    if (/SERVER = ([\S]+)/) {
      my $serverName = $1;

      # This bit of ugly code removes duplicate servers
      # from the list.  Duplicate in the sense that
      # servers <host> and <host>.bkup are really the
      # same machine and should NOT both appear in the list!
      my @canonicalServers;
      foreach my $host (@servers) {
	my $hostName = $host->name;
	if ($hostName =~ /${serverName}.bkup/) {
	  $serverName = undef;
	  push @canonicalServers, $host;
	}
	elsif ($serverName =~ /${hostName}.bkup/) {
	}
	else {
	  push @canonicalServers, $host;
	}
      }
      @servers = @canonicalServers;
      if (defined($serverName)) {
	my $server = NBU::Host->new($serverName);
	push @servers, $server
      }
    }
  }
  close($pipe);
}

sub masters {
  my $Class = shift;

  loadClusterInformation() if (!defined($me));
  return ($master);
}

sub master {
  my $Class = shift;

  loadClusterInformation() if (!defined($me));
  return ($master == $me);
}

sub me {
  my $Class = shift;

  loadClusterInformation() if (!defined($me));
  return $me;
}

sub servers {
  my $Class = shift;

  loadClusterInformation() if (!defined($me));
  return @servers;
}

my $msgsLoaded;
my %msgs;
sub loadErrorMessages {
  my $Class = shift;

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
  my $Class = shift;

  NBU->loadErrorMessages if (!defined($msgsLoaded));

  return $msgs{shift};
}

1;

__END__
