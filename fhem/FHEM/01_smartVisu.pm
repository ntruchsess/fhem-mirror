##############################################
# $Id: 01_smartVisu.pm 0 2014-10-01 08:00:00Z herrmannj $

#TODO alot ;)
#organize loading order
#attr cfg file


package main;

use strict;
use warnings;

use Socket;
use Fcntl;
use POSIX;
use IO::Socket;
use IO::Select;

use Net::WebSocket::Server;
use JSON;

use Data::Dumper;

sub
smartVisu_Initialize(@)
{

  my ($hash) = @_;
  
  $hash->{DefFn}      = "smartVisu_Define";
  $hash->{SetFn}      = "smartVisu_Set";
  $hash->{ReadFn}     = "smartVisu_Read";
  $hash->{ShutdownFn} = "smartVisu_Shutdown";
  $hash->{AttrList}   = "configFile ".$readingFnAttributes;
}

sub
smartVisu_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $name = $a[0];
  my $cfg;

  $hash->{helper}->{COMMANDSET} = 'save';

  #TODO move it to "initialized"
  smartVisu_ReadCfg($hash, 'smartVisu.cfg');
  
  my $port = 16384;
  # create and register server ipc parent (listener == socket)
  # TODO handle if port isnt available: find a free one
  $hash->{helper}->{listener} = IO::Socket::INET->new(
    LocalHost => 'localhost',
    LocalPort => $port, 
    Listen => 2, 
    Reuse => 1 ) or return "error creating ipc: $@";
  my $flags = fcntl($hash->{helper}->{listener}, F_GETFL, 0) or return "error shaping ipc: $!";
  fcntl($hash->{helper}->{listener}, F_SETFL, $flags | O_NONBLOCK) or return "error shaping ipc: $!";
  $hash->{TCPDev} = $hash->{helper}->{listener};
  $hash->{FD} = $hash->{helper}->{listener}->fileno();
  $selectlist{"$name:ipcListener"} = $hash;

  # prepare forking the ws server
  # workaround, forking from define via webif will lock the webif for unknown reason
  $cfg->{hash} = $hash;
  $cfg->{id} = 'ws';
  $cfg->{ipcPort} = $port;
  InternalTimer(gettimeofday()+1, "smartVisu_StartWebsocketServer", $cfg, 1);

  return undef;
}

sub
smartVisu_Set(@)
{
  my ($hash, $name, $cmd, @args) = @_;
  my $cnt = @args;

  return "unknown command ($cmd): choose one of ".$hash->{helper}->{COMMANDSET} if not ( grep { $cmd eq $_ } split(" ", $hash->{helper}->{COMMANDSET} ));

  return smartVisu_WriteCfg($hash) if ($cmd eq 'save');

  return undef;
}

#ipc, accept from forked socket server
sub 
smartVisu_Read(@) 
{
  my ($hash) = @_;
  my $ipcClient = $hash->{helper}->{listener}->accept();

  #TODO connections from other then localhost possible||usefull ? evaluate the need ...
  
  my $ipcHash;
  $ipcHash->{TCPDev} = $ipcClient;
  $ipcHash->{FD} = $ipcClient->fileno();
  $ipcHash->{PARENT} = $hash;
  $ipcHash->{directReadFn} = \&smartVisu_ipcRead;

  my $name = $hash->{NAME}.":".$ipcClient->peerhost().":".$ipcClient->peerport();
  $ipcHash->{NAME} = $name;
  $ipcHash->{TYPE} = "smartVisu";
  $selectlist{$name} = $ipcHash;

  $hash->{helper}->{ipc}->{$name} = $ipcClient;

  #TODO log connection
  return undef;
}

#ipc, read msg from forked socket server
sub 
smartVisu_ipcRead($) 
{
  my ($ipcHash) = @_;
  my $msg = "";
  my ($up, $rv);
  my ($id,$pid);

  $rv = $ipcHash->{TCPDev}->recv($msg, POSIX::BUFSIZ, 0);
  unless (defined($rv) && length $msg) {
    # child is termitating ... 
    #TODO bookkeeping,cleanup 
    delete $selectlist{$ipcHash->{NAME}};
    $ipcHash->{TCPDev}->close();
    return undef;
  }
  unless (defined($ipcHash->{registered}))
  {
    # first incoming msg, must contain id:pid (name) of forked child
    # security check, see if we are waiting for. id and pid should be registered in $hash->{helper}->{ipc}->{$id}->{pid} before incoming will be accepted 
    if (($msg =~ m/^(\w+):(\d+)$/) && ($ipcHash->{PARENT}->{helper}->{ipc}->{$1}->{pid} eq $2))
    {
      ($id,$pid) = ($1, $2);
      # registered: set id if recognized
      $ipcHash->{registered} = $id;
      # sock: how to talk to client process
      $ipcHash->{PARENT}->{helper}->{ipc}->{$id}->{sock} = $ipcHash;
      # name: how selectlist name it
      $ipcHash->{PARENT}->{helper}->{ipc}->{$id}->{name} = $ipcHash->{NAME};
      $msg =~ s/^\w+:\d+//;
      return undef if ($msg eq '');
    }
    else
    {
      #security breach: unexpected incoming (child?) connection
      #TODO cleanup, log ...
    }
  }

  $id = $ipcHash->{registered};
  #TODO check if a dispatcher is set
  
  #TODO dispatch incoming 
  eval 
  {
    $up = decode_json($msg);
    #print  Dumper($up);
    1;
  } or do {
    my $e = $@;
    #TODO log and take caution
    return undef;
  };
  #keep cfg up to date
  if (defined($up->{message}->{cmd}) && ($up->{message}->{cmd} eq 'monitor'))
  {
    foreach my $item (@{$up->{message}->{items}})
    {
      $ipcHash->{PARENT}->{helper}->{config}->{$item}->{type} = 'unknown' unless defined($ipcHash->{PARENT}->{helper}->{config}->{$item}->{type});
    }
  }
  smartVisu_ProcessDeviceMsg($ipcHash, $up);
  return undef;
}

#id: ..name of process, $msg: what to tell
sub 
smartVisu_ipcWrite(@)
{
  my ($hash,$id,$msg) = @_;
  my $result = $hash->{helper}->{ipc}->{$id}->{sock}->send($msg, 0);  
  return undef;
}

sub
smartVisu_Shutdown(@)
{
  my ($hash) = @_;
  #TODO tell all process we are going down

  return undef;
}

sub
smartVisu_RegisterClient(@)
{
  my ($hash, $client) = @_;
  $hash->{helper}->{client}->{$client} = 'registered';
  return undef;
}

sub
smartVisu_ReadCfg(@)
{
  my ($hash) = @_;
  my $cfgFile = AttrVal($hash->{NAME}, 'configFile', "$hash->{NAME}.cfg");

  my $json_text = do 
  {
     open(my $json_fh, "<:encoding(UTF-8)", $cfgFile) or Log3 ($hash, 2, "can't open $cfgFile: $!\n");
     local $/;
     <$json_fh>
  };

  my $json = JSON->new->utf8;
  my $data = $json->decode($json_text);
  
  $hash->{helper}->{config} = $data->{'config'};
  smartVisu_CreateListen($hash);
  return undef;
}

sub
smartVisu_WriteCfg(@)
{
  my ($hash) = @_;
  my $cfgContent;
  my $cfgFile = AttrVal($hash->{NAME}, 'configFile', "$hash->{NAME}.cfg");

  $cfgContent->{version} = '1.0';
  $cfgContent->{modul} = 'smartVisu';
  
  foreach my $key (keys %{ $hash->{helper}->{config} })
  {
    if (($hash->{helper}->{config}->{$key}->{type} eq 'item') && ($hash->{helper}->{config}->{$key}->{mode} ne 'unknown'))
    {
      $cfgContent->{config}->{$key} = $hash->{helper}->{config}->{$key};
    }
  }

  my $cfgOut = JSON->new->utf8;
  open (my $cfgHandle, ">:encoding(UTF-8)", $cfgFile);
  print $cfgHandle $cfgOut->pretty->encode($cfgContent);
  close $cfgHandle;;

  smartVisu_CreateListen($hash);
  return undef;
}

sub
smartVisu_CreateListen(@)
{
  my ($hash) = @_;
  my $listen;

  foreach my $key (keys %{ $hash->{helper}->{config} })
  {
    my $gad = $hash->{helper}->{config}->{$key};
    if (($gad->{type} eq 'item') && ($gad->{device} ne 'unknown') && ($gad->{reading} ne 'unknown'))
    {
      $listen->{$gad->{device}}->{$gad->{reading}}->{$key} = $hash->{helper}->{config}->{$key};
    }    
  }
  $hash->{helper}->{listen} = $listen;
  return undef;
}

###############################################################################
#
# main device (parent)
# decoding utils
#
# $msg is hash: the former client json plus ws server enrichment data (sender ip, identity, timestamp)

sub
smartVisu_ProcessDeviceMsg(@)
{
  my ($ipcHash, $msg) = @_;

  my $hash = $ipcHash->{PARENT};

  my $connection = $ipcHash->{registered}.':'.$msg->{'connection'};
  my $sender = $msg->{'sender'};
  my $identity = $msg->{'identity'};
  my $message = $msg->{'message'};
  

  #check if conn is actual know
  if (!defined $hash->{helper}->{receiver}->{$connection})
  {
    if (($message->{cmd} || '') eq 'connect')
    {
      $hash->{helper}->{receiver}->{$connection}->{sender} = $sender;
      $hash->{helper}->{receiver}->{$connection}->{identity} = $identity;
      $hash->{helper}->{receiver}->{$connection}->{state} = 'connecting';
    }
    else
    {
      #TODO error logging, disconnect 
    }
  }
  elsif((($message->{cmd} || '') eq 'handshake') && ($hash->{helper}->{receiver}->{$connection}->{state} eq 'connecting') )
  {
    my $access = $msg->{sender};

    foreach my $key (keys %defs)
    {
      if (($defs{$key}{TYPE} eq 'svDevice') && (ReadingsVal($key, 'identity', '') eq $access))
      {
        $hash->{helper}->{receiver}->{$connection}->{device} = $key;
        $hash->{helper}->{receiver}->{$connection}->{state} = 'connected';
        #build sender 
        $hash->{helper}->{sender}->{$key}->{connection} = $ipcHash->{registered};
        $hash->{helper}->{sender}->{$key}->{ressource} = $msg->{'connection'};
        $hash->{helper}->{sender}->{$key}->{state} = 'connected';
      }
    }
    # sender could not be confirmed, put it on-hold because it may be defined later
    $hash->{helper}->{receiver}->{$connection}->{state} = 'rejected' if $hash->{helper}->{receiver}->{$connection}->{state} eq 'connecting';
  }
  elsif(($message->{cmd} || '') eq 'handshake')
  {
    #TODO handshake out of of sync, not really sure whats to do
  }
  elsif($hash->{helper}->{receiver}->{$connection}->{state} eq 'rejected')
  {
    my $access = $msg->{sender};

    #TODO check registered device only
    foreach my $key (keys %defs)
    {
      if (($defs{$key}{TYPE} eq 'svDevice') && (ReadingsVal($key, 'identity', '') eq $access))
      {
        $hash->{helper}->{receiver}->{$connection}->{device} = $key;
        $hash->{helper}->{receiver}->{$connection}->{state} = 'connected';
        #build sender 
        $hash->{helper}->{sender}->{$key}->{connection} = $ipcHash->{registered};
        $hash->{helper}->{sender}->{$key}->{ressource} = $msg->{'connection'};
        $hash->{helper}->{sender}->{$key}->{state} = 'connected';
        #set state
      }
    }
  }
  
  if(($message->{cmd} || '') eq 'disconnect') 
  {
    my $key = $hash->{helper}->{receiver}->{$connection}->{device};

    delete($hash->{helper}->{receiver}->{$connection});
    if ($key)
    {
      my $devHash = $defs{$key};
      svDevice_fromDriver($devHash, $msg);
      delete($hash->{helper}->{sender}->{$key});  
    }  
    return undef;
  }

  return undef if(($hash->{helper}->{receiver}->{$connection}->{state} || '') ne 'connected');
  #dispatch to device
  my $key = $hash->{helper}->{receiver}->{$connection}->{device};
  my $devHash = $defs{$key};
  svDevice_fromDriver($devHash, $msg);

  return undef;
}

sub
smartVisu_StartWebsocketServer(@)
{
  my ($cfg) = @_;
  
  my $id = $cfg->{id};

  my $ws = Net::WebSocket::Server->new(
    listen => 2121,
    on_connect => \&smartVisu_wsConnect
  );

  #TODO error checking
  my $pid = fork();
  if ($pid)
  {
    # prepare parent for incoming connection
    $cfg->{hash}->{helper}->{ipc}->{$id}->{pid} = $pid;
    return undef;
  }
  #connect to main process
  my $ipc = new IO::Socket::INET (
    PeerHost => 'localhost',
    PeerPort => $cfg->{ipcPort},
    Proto => 'tcp',
  );
  #announce my name
  $ipc->send("$id:$$", 0);

  $ws->{'ipc'} = $ipc;
  $ws->{id} = $id;
  $ws->watch_readable($ipc->fileno() => \&smartVisu_wsIpcRead);
  $ws->start;
  POSIX::_exit(0);
}

sub
smartVisu_wsConnect(@)
{
  my ($serv, $conn) = @_;
  $conn->on(
    handshake => \&smartVisu_wsHandshake,
    utf8 => \&smartVisu_wsUtf8,
    disconnect => \&smartVisu_wsDisconnect
  );
  my @chars = ("A".."Z", "a".."z","0".."9");
  my $cName = "conn-";
  $cName .= $chars[rand @chars] for 1..8;
  my $senderIP = $conn->ip();
  my $msg = "{\"connection\":\"$cName\",\"sender\":\"$senderIP\",\"identity\":\"unknown\",\"message\":{\"cmd\":\"connect\"}}";
  my $size = $conn->server()->{ipc}->send($msg);
  $conn->{id} = $cName;
  $serv->{$cName} = $conn;
  return undef;
}

sub
smartVisu_wsHandshake(@)
{
  my ($conn, $handshake) = @_;
  my $senderIP = $conn->ip();
  my $cName = $conn->{id};
  #print Dumper $handshake->req;
  my $msg = "{\"connection\":\"$cName\",\"sender\":\"$senderIP\",\"identity\":\"unknown\",\"message\":{\"cmd\":\"handshake\"}}";
  my $size = $conn->server()->{ipc}->send($msg);
  return undef;
}

sub
smartVisu_wsUtf8(@)
{
  my ($conn, $msg) = @_;
  my $senderIP = $conn->ip();
  my $cName = $conn->{id};
  #add header
  $msg =~ s/^{/{"connection":"$cName","sender":"$senderIP","identity":"unknown", "message":{/g;
  $msg .= "}";
  my $size = $conn->server()->{ipc}->send($msg);
  return undef;
}

#http://tools.ietf.org/html/rfc6455#section-7.4.1
sub
smartVisu_wsDisconnect(@)
{
  my ($conn, $code, $reason) = @_;
  $code = 0 unless(defined($code));
  $reason = 0 unless(defined($reason));
  my $senderIP = $conn->ip();
  my $cName = $conn->{id};
  #add header
  my $msg = "{\"connection\":\"$cName\",\"sender\":\"$senderIP\",\"identity\":\"unknown\",\"message\":{\"cmd\":\"disconnect\"}}";
  my $size = $conn->server()->{ipc}->send($msg);
  return undef;
}

sub
smartVisu_wsIpcRead(@)
{
  my ($serv, $fh) = @_;
  my $msg = '';
  my $rv;

  $rv = $serv->{'ipc'}->recv($msg, POSIX::BUFSIZ, 0);
  unless (defined($rv) && length $msg) {
    #TODO bookkeeping,cleanup 
    $serv -> shutdown();
    return undef;
  }
  smartVisu_wsProcessInboundCmd($serv, $msg);
  return undef;
}

sub
smartVisu_wsProcessInboundCmd(@)
{
   my ($serv, $msg) = @_;
   $serv -> shutdown() if ($msg eq 'shutdown');
}

1;

