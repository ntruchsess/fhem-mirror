##############################################
# $Id$
package main;

=pod
### Usage:
=cut

use vars qw{%attr %defs $devcount};
use strict;
use warnings;
use IO::Socket::INET;

sub
AsyncDevice($$@) {
  my ($hash,$port,$parentInitFn,$parentReadFn,$childInitFn,$childReadFn) = @_;
  
  my $type = $hash->{TYPE};
  my $name = $hash->{NAME};
  my $pname = "$type:localhost:$port";
  my $phash = {
    NR          => $devcount,
    NAME        => $pname,
    TYPE        => $type,
    STATE       => "Defiend",
    DNAME       => $name,
    TEMPORARY   => 1,              # Don't want to save it
    ReadFn      => "AsyncDevice_ParentRead",
    ReadyFn     => "AsyncDevice_ParentReady", 
    InitFn      => $parentInitFn,
    AsyncReadFn => $parentReadFn,
  };
  my $ret = TcpServer_Open($phash, $port, undef);
  if ($ret) {
    return $ret;
  };
  $phash->{STATE}="listening";

  $attr{$pname}{room} = "hidden";
  $defs{$pname} = $phash;
  $devcount++;

  # do fork
  my $pid = fork;
  if(!defined($pid)) {
    Log3 (1, "Cannot fork: $!");
    TcpServer_Close($phash);
    delete $attr{$pname};
    delete $defs{$pname};
    return undef;
  }

  if($pid) {
    $phash->{PID} = $pid;
    return undef;
  }

  # Child here

  foreach my $d (sort keys %defs) {   # Close all kind of FD
    my $h = $defs{$d};
    TcpServer_Close($h) if($h->{SERVERSOCKET});
    DevIo_CloseDev($h,1)  if($h->{DeviceName});
  }
  
  %attr = ( global => $attr{global}, $name => $attr{$name} );
  %defs = ( $name => $defs{$name} ); 
  
  my $cname = "$type:localhost:$port";
  my $chash = {
    NAME        => $cname,
    TYPE        => $type,
    STATE       => "Connected",
    SNAME       => $name,
    TEMPORARY   => 1,              # Don't want to save it
    DeviceName  => "localhost:$port",
    ReadFn      => "AsyncDevice_ClientRead",
    InitFn      => $childInitFn,
    AsyncReadFn => $childReadFn,
  };
  $attr{$cname}{room} = "hidden";
  $defs{$cname} = $chash;
  
  $ret = DevIo_OpenDev($chash,0,"AsyncDevice_ClientInit");
  if ($ret) {
    Log3 (1, "Error connecting to Parent device: $ret");
    exit 1;
  }
}

sub AsyncDevice_Close($) {
  my ( $hash ) = @_;
  
  # dispose existing connections
  foreach my $e ( sort keys %main::defs ) {
    if ( defined( my $dev = $main::defs{$e} )) {
      if ( defined( $dev->{SNAME} ) && ( $dev->{SNAME} eq $hash->{NAME} )) {
        AsyncDevice_ParentTcpConnectionClose($dev);
      }
    }
  }
  
  TcpServer_Close($hash);
  
  if ($hash->{ChildReadFn}) {
    $hash->{ReadFn} = $hash->{ChildReadFn};
    delete $hash->{ChildReadFn};
  }
  if ($hash->{ChildReadyFn}) {
    $hash->{ReadyFn} = $hash->{ChildReadyFn};
    delete $hash->{ChildReadyFn};
  }
}

sub AsyncDevice_ParentRead($) {

  my ( $hash ) = @_;
  if($hash->{SERVERSOCKET}) {   # Accept and create a child
    my $chash = TcpServer_Accept($hash, "AsyncDevice");
    return if(!$chash);
    $chash->{DeviceName}=$hash->{PORT}; # required for DevIo_CloseDev and AsyncDevice_Ready
    $chash->{TCPDev}=$chash->{CD};
    
    # dispose preexisting connections
    foreach my $e ( sort keys %main::defs ) {
      if ( defined( my $dev = $main::defs{$e} )) {
        if ( $dev != $chash && defined( $dev->{SNAME} ) && ( $dev->{SNAME} eq $chash->{SNAME} )) {
          AsyncDevice_ParentTcpConnectionClose($dev);
        }
      }
    }
    my $dname = $hash->{DNAME};
    if (defined $dname) {
      $chash->{DNAME} = $dname;
      $chash->{AsyncReadFn} = $hash->{AsyncReadFn};
      my $initfn = $hash->{AsyncInitFn};
      if($initfn and $dname) {
        &$initfn($defs{$dname});
      }
    }
    return;
  }
  my $readfn = $hash->{AsyncReadFn};
  my $dname = $hash->{DNAME};
  if($readfn and $dname) {
    &$readfn($defs{$dname},$hash);
  }
}

sub AsyncDevice_ParentReady($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  # this is a closed tcp-connection, remove it
  if ($name=~/^^AsyncDevice:.+:\d+$/) {
    AsyncDevice_ParentTcpConnectionClose($hash);
  }
}

sub AsyncDevice_ParentTcpConnectionClose($) {
  my $hash = shift;
  TcpServer_Close($hash);
  if ($hash->{SNAME}) {
    my $shash = $main::defs{$hash->{SNAME}};
    $hash->{SocketDevice} = undef if (defined $shash);
  }
  my $dev = $hash->{DeviceName};
  my $name = $hash->{NAME};
  if (defined $name) {
    delete $main::readyfnlist{"$name.$dev"} if (defined $dev);
    delete $main::attr{$name};
    delete $main::defs{$name};
  }
  return undef;
}

sub AsyncDevice_ClientInit($) {
  my $hash = shift;
  my $sname = $hash->{SNAME};
  my $initFn = $hash->{InitFn};
  if ($sname and $initFn) {
    &$initFn($defs{$sname});
  }
}

sub AsyncDevice_ClientRead($) {
  my $hash = shift;  
  my $sname = $hash->{SNAME};
  my $readFn = $hash->{ClientReadFn};
  if ($sname and $readFn) {
    &$readFn($defs{$sname},$hash);
  }
}

1;
