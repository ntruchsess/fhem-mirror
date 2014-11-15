##############################################
# $Id: 31_svDevice.pm 0 2014-10-01 08:00:00Z herrmannj $

package main;

use strict;
use warnings;

use JSON;
use URI::Escape;
use Data::Dumper;

sub
svDevice_Initialize(@)
{

  my ($hash) = @_;
  
  $hash->{DefFn}        = "svDevice_Define";
  $hash->{SetFn}        = "svDevice_Set";
  $hash->{GetFn}        = "svDevice_Get";
  $hash->{NotifyFn}     = "svDevice_Notify";
  $hash->{ShutdownFn}   = "svDevice_Shutdown";
  $hash->{FW_detailFn}  = "svDevice_fwDetail";
  $hash->{AttrList}     = "configFile ".$readingFnAttributes;

  $data{FWEXT}{svDevice}{SCRIPT}  = "smartVisuEditor.js";
}

# define name svDevice ip

sub
svDevice_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $name = $a[0];
  my $identity = $a[2];

  svDevice_Register($hash) if ($init_done);

  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, "identity", $identity);
  readingsEndUpdate($hash, 0);

  #$hash->{helper}->{lfs}->{RGBW2}->{RGB}->{test1};
  #$hash->{helper}->{lfs}->{RGBW2}->{RGB}->{test2};
  #$hash->{helper}->{lsf}->{GAD} = block

  #print to_json($cfg, {utf8 => 1, pretty => 1});
  
  return undef;
}

sub
svDevice_Register(@)
{
  my ($hash) = @_;
  foreach my $key (keys %defs)
  {
    if ($defs{$key}{TYPE} eq 'smartVisu')
    {
      $hash->{helper}->{gateway} = $key;
      smartVisu_RegisterClient($defs{$key}, $hash->{NAME});
      $hash->{helper}->{init} = 'done';
      last;
    }
  }
  return undef;
}

sub
svDevice_Set(@)
{
  my ($hash, $name, $cmd, @args) = @_;
  my $cnt = @args;

  if ($cmd eq 'webif-data')
  {
    print Dumper decode_json(uri_unescape($args[0]));
  }
  return undef;
}

sub
svDevice_Get(@)
{
  my ($hash, $name, $cmd, @args) = @_;
  my $cnt = @args;
  print "get $cmd $args[0] \n";

  if ($cmd eq 'webif-data')
  {
    my $transfer;
    eval 
    {
      $transfer = decode_json($args[0] || '');
      1;
    } or do {
      my $e = $@;
      die "err $e\n";
      #TODO log and take caution
      return undef;
    };

    if ($transfer->{cmd} eq 'gadList')
    {
      if ($hash->{helper}->{gateway})
      {
        return encode_json($defs{$hash->{helper}->{gateway}}->{helper}->{config});
      }
    }
    elsif ($transfer->{cmd} eq 'gadItem')
    {
      svDevice_ValidateGAD($hash, $transfer);
      my %tmp = %{$defs{$hash->{helper}->{gateway}}->{helper}->{config}->{$transfer->{item}}};
      my $result = \%tmp;
      #type:mode, js editor support
      $result->{editor} = defined($result->{mode})?$result->{type}.':'.$result->{mode}:$result->{type}.':'.'unknown';
      print "webif-data gadItem\n";
      print Dumper $result;
      return encode_json($result);  
    }
    elsif ($transfer->{cmd} eq 'gadItemSave')
    {
      my $result;
      svDevice_ValidateGAD($hash, $transfer);
      $result->{result} = 'ok';
      return encode_json($result);  
    }
    elsif ($transfer->{cmd} eq 'gadModeSelect')
    {
      my $result;
      svDevice_ValidateGAD($hash, $transfer);

      $result->{result} = 'ok';
      return encode_json($result);  
    }
  }
  return undef;
}

sub svDevice_ValidateGAD(@)
{
  my ($hash, $transfer) = @_;

  my $result = '';
  my $gadItem = $transfer->{item};
  if (!defined($defs{$hash->{helper}->{gateway}}->{helper}->{config}->{$transfer->{item}}))
  {
    Log3 ($hash, 2, "gadModeSelect with unknown GAD $gadItem");
  }
  my $gadAtGateway = $defs{$hash->{helper}->{gateway}}->{helper}->{config}->{$transfer->{item}};
  #literally delete item
  if ($transfer->{editor} eq 'unknown:unknown')
  {
    $gadAtGateway->{type} = 'unknown';
    $gadAtGateway->{mode} = 'unknown';
  }
  elsif ($transfer->{editor} eq 'item:simple')
  {
    $gadAtGateway->{type} = 'item';
    $gadAtGateway->{mode} = 'simple';
    #device
    if (defined($transfer->{device}))
    {
      $result .= 'device not found. ' if (!defined($defs{$transfer->{device}}));
      $gadAtGateway->{device} = $transfer->{device};
    }
    elsif (!defined($gadAtGateway->{device}))
    {
      $gadAtGateway->{device} = 'unknown device';
    }
    #reading
    if (defined($transfer->{reading}))
    {
      $gadAtGateway->{reading} = $transfer->{reading};
    }
    elsif (!defined($gadAtGateway->{reading}))
    {
      $gadAtGateway->{reading} = 'unknown reading';
    }
    #converter
    if (defined($transfer->{simple}->{converter}))
    {
      $gadAtGateway->{simple}->{converter} = $transfer->{simple}->{converter};
    }
    elsif (!defined($gadAtGateway->{simple}->{converter}))
    {
      $gadAtGateway->{simple}->{converter} = 'unknown converter';
    }
    #set
    if (defined($transfer->{simple}->{set}))
    {
      $gadAtGateway->{simple}->{set} = $transfer->{simple}->{set};
    }
    elsif (!defined($gadAtGateway->{simple}->{set}))
    {
      $gadAtGateway->{simple}->{set} = 'unknown set';
    }
  }
}

sub 
svDevice_Notify($$)
{
  my ($hash, $ntfyDev) = @_;
  my $ntfyDevName = $ntfyDev->{NAME};

  #find parent if initialization done
  svDevice_Register($hash) if (!$hash->{helper}->{init} && ($ntfyDevName eq 'global') && grep(m/^INITIALIZED$/, @{$ntfyDev->{CHANGED}}));
  return undef if(AttrVal($hash->{NAME}, "disable", undef));

  my $result;

  #of interest, device is in list ?
  if (exists($defs{$hash->{helper}->{gateway}}->{helper}->{listen}->{$ntfyDevName}))
  {
    my $max = int(@{$ntfyDev->{CHANGED}});

    for (my $i = 0; $i < $max; $i++) {
      my $s = $ntfyDev->{CHANGED}[$i];
      $s = "state: $s" if (($ntfyDevName ne 'global') && ($s !~ m/.*:.*/));
      my @reading = split(': ', $s);
      print "notify $ntfyDevName $i : $reading[0] | $reading[1] | $reading[2] \n";
      if (defined($hash->{helper}->{lfs}->{$ntfyDevName}->{$reading[0]}))
      {
        #list of all gad using it
        my @gads;
        foreach my $gad (@gads)
        {
          print "$hash->{NAME}: $gad\n";
        }
      }
    }
    #TODO: see if there is a publisher
  }
  return undef;
}

#device and reading to gad
sub
svDevice_GadNamesFromDevice(@)
{
  my ($hash, $device, $reading) = @_;
  my @result;
  my $node = $defs{$hash->{helper}->{gateway}}->{helper}->{listen}->{$device}->{$reading};
  if (defined($node))
  {
    foreach my $key (keys %{ $node })
    {
      push (@result, $key);
    }
  }
  return \@result;
}

sub
svDevice_Shutdown(@)
{
  return undef;
}

sub
svDevice_fwDetail(@)
{
  my ($FW_wname, $d, $FW_room) = @_;
  my $result = '';

  $result = "<div>\n";
  $result .= "<table class=\"block wide \">\n";
  $result .= "<tr>\n";
  $result .= "<td>\n";
  $result .= "<div id=\"gadlist\" style=\"max-height: 200px; overflow-y: scroll;\"></div>\n";
  $result .= "</td>\n";
  $result .= "</tr>\n";
  $result .= "</table>\n";
  $result .= "<script type='text/javascript'>\n";
  $result .= "sveReadGADList('$d');\n";
  $result .= "</script>\n";
  $result .= "</div>\n";
  $result .= "<div id=\"gadeditcontainer\" style=\"display: none;\">\n";
  $result .= "<br>";
  $result .= "GAD Edit\n";
  $result .= "<table class=\"block wide \">\n";
  $result .= "<tr>\n";
  $result .= "<td>\n";
  $result .= "<div id=\"gadeditor\">Editor<br>1</div>\n";
  $result .= "</td>\n";
  $result .= "</tr>\n";
  $result .= "</table>\n";
  $result .= "</div>\n";
  
  return $result;
}

# communicating with sv main instance
sub
svDevice_fromDriver(@)
{
  my ($hash, $msg) = @_;
  print "device $hash->{NAME} \n"; 
  print Dumper $msg;
  if (($msg->{message}->{cmd} ne 'disconnect') && ($hash->{READINGS}->{state}->{VAL} ne 'connected'))
  {
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, 'state', 'connected');
    readingsEndUpdate($hash, 1);
    return undef;
  }
  if ($msg->{message}->{cmd} eq 'disconnect')
  {
    $hash->{helper}->{monitor} = [];
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, 'state', 'disconnected');
    readingsEndUpdate($hash, 1);
    return undef;
  }
  if ($msg->{message}->{cmd} eq 'proto')
  {
    #TODO check if protokoll version match
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, 'protokoll', $msg->{message}->{ver});
    readingsEndUpdate($hash, 1);
  }
  if ($msg->{message}->{cmd} eq 'monitor')
  {
    $hash->{helper}->{monitor} = $msg->{message}->{items};
  }
  return undef;
}

sub
svDevice_toDriver(@)
{
  return undef;
}

#gad mapping changed
sub
svDevice_ModifyCfg(@)
{
}

#save and write 
sub
svDevice_ReadCfg(@)
{
  my $hash = @_;
}

1;
