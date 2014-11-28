#################################################################
#
#  Copyright notice
#
#  (c) 2014
#  Copyright: Norbert Truchsess (norbert.truchsess@t-online.de)
#  All rights reserved
#
#  This script free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  This copyright notice MUST APPEAR in all copies of the script!
#
#  Homepage:  http://fhem.de
#
# $Id$

package main;
use strict;
use warnings;
use TcpServerUtils;

##########################
sub
websocket_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "websocket::Define";
  $hash->{ReadFn}   = "websocket::Read";
  $hash->{UndefFn}  = "websocket::Undef";
  $hash->{AttrFn}   = "websocket::Attr";
  $hash->{NotifyFn} = "websocket::Notify";
  $hash->{AttrList} = "allowfrom SSL timeout";
}

package websocket;

use strict;
use warnings;

use GPUtils qw(:all);

use JSON;
use Protocol::WebSocket::Handshake::Server;
use Time::Local;
use POSIX qw(strftime);

use Data::Dumper;

BEGIN {GP_Import(qw(
  TcpServer_Open
  TcpServer_Accept
  TcpServer_SetSSL
  TcpServer_Close
  RemoveInternalTimer
  InternalTimer
  AnalyzeCommand
  AnalyzeCommandChain
  AttrVal
  CommandDelete
  Log3
  gettimeofday
  devspec2array
  IsIgnored
  getAllSets
  getAllGets
  getAllAttr
))};

##########################
sub
Define($$$)
{
  my ($hash, $def) = @_;

  my @a = split("[ \t][ \t]*", $def);
  my ($name, $type, $port, $global) = split("[ \t]+", $def);

  my $isServer = 1 if(defined($port) && $port =~ m/^(IPV6:)?\d+$/);
  
  return "Usage: define <name> websocket { [IPV6:]<tcp-portnr> [global] }"
        if(!($isServer) ||
            ($global && $global ne "global"));

  $hash->{port} = $port;
  $hash->{global} = $global;
  $hash->{NOTIFYDEV} = '';
  $hash->{onopen} = {};
  $hash->{onclose} = {};

  if ($main::init_done) {
    Init($hash);
  }
}

sub
Init($) {
  my ($hash) = @_;
  if (my $ret = TcpServer_Close($hash)) {
    Log3 ($hash->{NAME}, 1, "websocket failed to close port: $ret");
  } elsif ($ret = TcpServer_Open($hash, $hash->{port}, $hash->{global})) {
    Log3 ($hash->{NAME}, 1, "websocket failed to open port: $ret");
  }
  subscribeOpen($hash,\&onSocketConnected,$hash);
}

##########################
sub
Read($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  if($hash->{SERVERSOCKET}) {   # Accept and create a child
    my $chash = TcpServer_Accept($hash, "websocket");
    return if(!$chash);
    $chash->{hs} = Protocol::WebSocket::Handshake::Server->new;
    $chash->{ws} = 'new';
    $chash->{timeout} = AttrVal($name,"timeout",30);
    $chash->{pong_received} = 1;
    return;
  }

  my $cl = $hash; # $hash is master device, $cl is open client
  my $buf;
  my $ret = sysread($cl->{CD}, $buf, 256);
  if(!defined($ret) || $ret <= 0) {
    CommandDelete(undef, $name);
    return;
  }

  my $sname = $cl->{SNAME};
  Log3 ($sname,5,$buf);

  if ($cl->{ws} eq 'new') {
    unless ($cl->{hs}->parse($buf) and $cl->{hs}->is_done) {
      Log3 ($sname,5,$cl->{hs}->error) if ($cl->{hs}->error);
      #closeSocket($cl);
      return;
    }
    #Log3 ($sname,5,Dumper($cl->{hs}));
    Log3 ($sname,5,$cl->{hs}->to_string);
    syswrite($cl->{CD},$cl->{hs}->to_string);
    $cl->{ws} = 'open';
    $cl->{frame} = $cl->{hs}->build_frame;
    $cl->{resource} = $cl->{hs}->req->resource_name;
    $cl->{protocols} = [split "[ ,]",$cl->{hs}->req->subprotocol];
    $cl->{json} = grep (/^json$/,@{$cl->{protocols}}) ? 1 : 0;
    
    if ($hash = $main::defs{$sname}) {
      foreach my $arg (keys %{$hash->{onopen}}) {
        eval {
          &{$hash->{onopen}->{$arg}}($cl,$arg);
        };
        Log3 ($sname,4,"websocket: ".GP_Catch($@)) if $@;
      }
    }
    Timer($cl);
  }

  if ($cl->{ws} eq 'open') {
    my $frame = $cl->{frame};
    $frame->append($buf);
    while (defined(my $message = $frame->next)) {
      MESSAGE: {
        $frame->is_continuation and do {
          Log3 ($sname,5,"websocket continuation $message");
          last;
        };
        $frame->is_text and do {
          Log3 ($sname,5,"websocket text $message");
          if ($cl->{json}) {
            eval {
              if (my $json = decode_json $message) {
                #Log3 ($sname,5,"websocket jsonmessage: ".Dumper($json));
                if (defined (my $type = $json->{type})) {
                  if (defined (my $subscriptions = $cl->{typeSubscriptions}->{$type})) {
                    foreach my $arg (keys %$subscriptions) {
                      my $fn = $subscriptions->{$arg};
                      &$fn($cl,$json->{payload},$arg);
                    }
                  } else {
                    Log3 ($sname,5,"websocket ignoring json-message type '$type' without subscription");
                  }
                } else {
                  Log3 ($sname,4,"websocket json-message without type: $message");
                }
              }
            };
            Log3 ($sname,4,"websocket: ".GP_Catch($@)) if $@;
          } else {
            my $ret = AnalyzeCommandChain($cl, $message);
            sendMessage($cl, type => 'text', buffer => $ret) if (defined $ret);
          }
          last;
        };
        $frame->is_binary and do {
          Log3 ($sname,5,"websocket binary $message");
          last;
        };
        $frame->is_ping and do {
          Log3 ($sname,5,"websocket ping $message");
          last;
        };
        $frame->is_pong and do {
          Log3 ($sname,5,"websocket pong $message");
          $cl->{pong_received} = 1;
          last;
        };
        $frame->is_close and do {
          Log3 ($sname,5,"websocket close $message");
          closeSocket($cl);
          last;
        };
      }
    }
  }
}

##########################
sub
Attr(@)
{
  my @a = @_;
  my $hash = $main::defs{$a[1]};

  if($a[0] eq "set" && $a[2] eq "SSL") {
    TcpServer_SetSSL($hash);
    if($hash->{CD}) {
      my $ret = IO::Socket::SSL->start_SSL($hash->{CD});
      Log3 $a[1], 1, "$hash->{NAME} start_SSL: $ret" if($ret);
    }
  }
  return undef;
}

sub
Undef($$) {
  my ($hash, $arg) = @_;
  return TcpServer_Close($hash);
}

sub Notify() {
  my ($hash,$dev) = @_;
  my $name = $hash->{NAME};

  #if ($name eq "global") {
    if( grep(m/^(INITIALIZED|REREADCFG)$/, @{$dev->{CHANGED}}) ) {
      Init($hash);
    } elsif( grep(m/^SAVE$/, @{$dev->{CHANGED}}) ) {
    }
  #}

  foreach my $clname ( grep {($main::defs{$_}{SNAME} || "") eq $name} keys %main::defs ) {
    my $cl = $main::defs{$clname};
    unless ($cl->{CD} and $cl->{hs} and $cl->{ws} eq 'open') {; # for connected clients in state open only
      Log3 ($name,5,"skip notify unconnected $clname for $dev->{NAME}");
    } else {
      foreach my $arg (keys %{$cl->{eventSubscriptions}}) {
        my @changed = ();
        foreach my $changed (@{$dev->{CHANGED}}) {
          push @changed,$changed if (grep {($dev->{NAME} =~ /$_->{name}/) and ($dev->{TYPE} =~ /$_->{type}/) and ($changed =~ /$_->{changed}/)} @{$cl->{eventSubscriptions}->{$arg}});
        }
        sendTypedMessage($cl,'event',{
          name    => $dev->{NAME},
          type    => $dev->{TYPE},
          arg     => $arg,
          'time'  => strftime ("%c GMT", _fhemTimeGm($dev->{NTFY_TRIGGERTIME})),
          changed => {map {$_=~ /^([^:]+)(: )?(.*)$/; ((defined $3) and ($3 ne "")) ? ($1 => $3) : ('STATE' => $1) } @changed},
        }) if (@changed);
      }
    }
  }
}

sub
Timer($) {
  my $cl = shift;
  RemoveInternalTimer($cl);
  unless ($cl->{pong_received}) {
    Log3 ($cl->{NAME},3,"websocket $cl->{NAME} disconnect due to timeout");
    closeSocket($cl);
    return undef;
  }
  $cl->{pong_received} = 0;
  InternalTimer(gettimeofday()+$cl->{timeout}, "websocket::Timer", $cl, 0);
  sendMessage($cl,type => 'ping');
}

sub
closeSocket($) {
  my ($cl) = @_;
  # Send close frame back
  sendMessage($cl, type => 'close');
  TcpServer_Close($cl);
  RemoveInternalTimer($cl);
  my $sname = $cl->{SNAME};
  if (my $hash = $main::defs{$sname}) {
    foreach my $arg (keys %{$hash->{onclose}}) {
      eval {
        &{$hash->{onclose}->{$arg}}($cl,$arg);
      };
      Log3 ($sname,4,"websocket: ".GP_Catch($@)) if $@;
    }
  }
  CommandDelete(undef, $cl->{NAME});
}

sub
sendMessage($%) {
  my ($cl,%msg) = @_;
  Log3 ($cl->{SNAME},5,Dumper(\%msg));
  syswrite($cl->{CD}, $cl->{hs}->build_frame(%msg)->to_bytes);
}

sub
onSocketConnected($$) {
  my ($cl,$hash) = @_;
  Log3($cl->{SNAME},5,"websocket onSocketConnected");
  subscribeMsgType($cl,'command',\&onCommandMessage,$cl);
}

sub
onCommandMessage($$$) {
  my ($cl,$message) = @_;
  if (defined (my $command = $message->{command})) {
    COMMAND: {
      $command eq "subscribe" and do {
        subscribeEvent($cl,%$message);
        last;
      };
      $command eq "unsubscribe" and do {
        unsubscribeEvent($cl,$message->{arg});
        last;
      };
      $command eq "list" and do {
        my @devs = grep {!IsIgnored($_)} (defined $message->{arg}) ? devspec2array($message->{arg}) : keys %main::defs;
        Log3 ($cl->{SNAME},5,"websocket command list devs: ".join(",",@devs));
        my $i = 0;
        my $num = @devs;
        foreach my $dev (@devs) {
          my $h = $main::defs{$dev};
          my $r = $h->{READINGS};
          sendTypedMessage($cl,'listentry',{
            arg        => $message->{arg},
            name       => $dev,
            'index'    => $i++,
            num        => $num,
            sets       => {map {if ($_ =~ /:/) { $_ =~ /^(.+):(.*)$/; $1 => [split (",",$2)] } else { $_ => undef } } split(/ /,getAllSets($dev))},
            gets       => {map {if ($_ =~ /:/) { $_ =~ /^(.+):(.*)$/; $1 => [split (",",$2)] } else { $_ => undef } } split(/ /,getAllGets($dev))},
            attrList   => {map {if ($_ =~ /:/) { $_ =~ /^(.+):(.*)$/; $1 => [split (",",$2)] } else { $_ => undef } } split(/ /,getAllAttr($dev))},
            internals  => {map {(ref ($h->{$_}) eq "") ? ($_ => $h->{$_}) : ()} keys %$h},
            readings   => {map {$_ => {value  => $r->{$_}->{VAL}, 'time' => strftime ("%c GMT", _fhemTimeGm($r->{$_}->{TIME}))}} keys %$r},
            attributes => $main::attr{$dev},
          });
        }
        last;
      };
      $command eq "get" and do {
        my $ret = AnylyzeCommand($cl, 'get '.($message->{device} // '').' '.($message->{property} // ''));
        sendTypedMessage($cl,'getreply',{
          device   => $message->{device},
          property => $message->{property},
          value    => $ret
        });
        last;
      };
      my $ret = AnalyzeCommandChain($cl, $command);
      sendTypedMessage($cl,'commandreply',{
        command => $command,
        reply   => $ret // '',
      });
    };
  } else {
    Log3 ($cl->{SNAME},4,"websocket no command in command-message");
  }
}

sub _fhemTimeGm($)
{
  my ($fhemtime) = @_;
  $fhemtime =~ /^(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)$/;
  return gmtime timelocal($6,$5,$4,$3,$2-1,$1);
}

# these are master hash API methods:
sub
subscribeOpen($$$) {
  my ($hash,$fn,$arg) = @_;
  $hash->{onopen}->{$arg} = $fn;
  Log3 ($hash->{NAME},5,"websocket subscribeOpen $fn");
}

sub
unsubscribeOpen($$) {
  my ($hash,$arg) = @_;
  my $deleted = (delete $hash->{onopen}->{$arg}) // "- undefined -";
  Log3 ($hash->{NAME},5,"websocket unsubscribeOpen");
}

sub
subscribeClose($$$) {
  my ($hash,$fn,$arg) = @_;
  $hash->{onclose}->{$arg} = $fn;
  Log3 ($hash->{NAME},5,"websocket subscribeClose $fn");
}

sub
unsubscribeClose($$) {
  my ($hash,$arg) = @_;
  my $deleted = (delete $hash->{onclose}->{$arg}) // "- undefined -";
  Log3 ($hash->{NAME},5,"websocket unsubscribeClose");
}

# these are client hash API methods:
sub
subscribeMsgType($$$$) {
  my ($cl,$type,$sub,$arg) = @_;
  $cl->{typeSubscriptions}->{$type}->{$arg} = $sub;
  Log3 ($cl->{SNAME},5,"websocket subscribe for messagetype: '$type' $sub");
}

sub
unsubscribeMsgType($$$) {
  my ($cl,$type,$arg) = @_;
  my $deleted = (delete $cl->{typeSubscriptions}->{$type}->{$arg}) // "- undefined";
  delete $cl->{typeSubscriptions}->{$type} unless (keys %{$cl->{typeSubscriptions}->{$type}});
  Log3 ($cl->{SNAME},5,"websocket unsubscribe for messagetype: '$type' $deleted");
}

sub
subscribeEvent($@) {
  my ($cl,%args) = @_;
  my $arg     = $args{arg}     // '';
  my $name    = $args{name}    // '';
  my $type    = $args{type}    // '';
  my $changed = $args{changed} // '';
  my $subscriptions;
  unless (defined ($subscriptions = $cl->{eventSubscriptions}->{$arg})) {
    $subscriptions = [];
    $cl->{eventSubscriptions}->{$arg} = $subscriptions;
  }
  push @$subscriptions,{
    name    => $name,
    type    => $type,
    changed => $changed,
  };
  Log3 ($cl->{SNAME},5,"websocket subscribe for device /$name/, type /$type/, arg '$arg' changed /$changed/");
}

sub
unsubscribeEvent($$) {
  my ($cl,$arg) = @_;
  delete $cl->{eventSubscriptions}->{$arg // ''};
  Log3 ($cl->{SNAME},5,"websocket unsubscribe for '$arg'");
}

sub
sendTypedMessage($$$) {
  my ($cl,$type,$arg) = @_;
  sendMessage($cl, type => 'text', buffer => encode_json {
    type => $type,
    payload => $arg,
  });
}

1;

=pod
=begin html

<a name="websocket"></a>
<h3>websocket</h3>
<ul>
  <br>
  <a name="websocketdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; websocket &lt;portNumber&gt; [global]</code><br>
    <br><br>

    Listen on the TCP/IP port <code>&lt;portNumber&gt;</code> for incoming
    websocket connections. If the second parameter global is <b>not</b> specified,
    the server will only listen to localhost connections.
    <br>
    To use IPV6, specify the portNumber as IPV6:&lt;number&gt;, in this
    case the perl module IO::Socket:INET6 will be requested.
    On Linux you may have to install it with cpan -i IO::Socket::INET6 or
    apt-get libio-socket-inet6-perl; OSX and the FritzBox-7390 perl already has
    this module.<br>
    Examples:
    <ul>
        <code>define wsPort websocket 7072 global</code><br>
        <code>attr wsPort SSL</code><br>
    </ul>
  </ul>
  <br>

  <a name="websocketset"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="websocketget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="websocketattr"></a>
  <b>Attributes:</b>
  <ul>
    <a name="SSL"></a>
    <li>SSL<br>
        Enable SSL encryption of the connection, see the description <a
        href="#HTTPS">here</a> on generating the needed SSL certificates. To
        connect to such a port use one of the following commands:
        <ul>
          socat openssl:fhemhost:fhemport,verify=0 readline<br>
          ncat --ssl fhemhost fhemport<br>
          openssl s_client -connect fhemhost:fhemport<br>
        </ul>
        </li><br>

    <a name="allowfrom"></a>
    <li>allowfrom<br>
        Regexp of allowed ip-addresses or hostnames. If set,
        only connections from these addresses are allowed.
        </li><br>

    <a name="timeout"></a>
    <li>timeout<br>
        ping the remote-side after this many seconds. Close connection if there's no reponse.
        Default is 30.
        </li><br>

  </ul>

</ul>

=end html
=cut

1;
