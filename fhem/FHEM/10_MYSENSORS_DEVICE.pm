##############################################
#
# fhem bridge to MySensors (see http://mysensors.org)
#
# Copyright (C) 2014 Norbert Truchsess
#
#     This file is part of fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
# $Id$
#
##############################################

use strict;
use warnings;

my %gets = (
  "version"   => "",
);

sub MYSENSORS_DEVICE_Initialize($) {

  my $hash = shift @_;

  # Consumer
  $hash->{DefFn}    = "MYSENSORS::DEVICE::Define";
  $hash->{UndefFn}  = "MYSENSORS::DEVICE::UnDefine";
  $hash->{SetFn}    = "MYSENSORS::DEVICE::Set";
  $hash->{AttrFn}   = "MYSENSORS::DEVICE::Attr";
  
  $hash->{AttrList} =
    "config:M,I ".
    "setCommands ".
    "set_.+_\\d+ ".
    "mapReadingType_.+ ".
    "requestAck:yes,no ". 
    "IODev ".
    $main::readingFnAttributes;

  main::LoadModule("MYSENSORS");
}

package MYSENSORS::DEVICE;

use strict;
use warnings;
use GPUtils qw(:all);

use Device::MySensors::Constants qw(:all);
use Device::MySensors::Message qw(:all);

BEGIN {
  MYSENSORS->import(qw(:all));

  GP_Import(qw(
    AttrVal
    readingsSingleUpdate
    CommandDeleteReading
    AssignIoPort
    Log3
  ))
};

my %static_mappings = (
  V_TEMP        => { type => "temperature" },
  V_HUM         => { type => "humidity" },
  V_PRESSURE    => { type => "pressure" },
  V_LIGHT_LEVEL => { type => "brightness" },
  V_LIGHT       => { type => "switch", val => { 0 => 'off', 1 => 'on' }},
);

sub Define($$) {
  my ( $hash, $def ) = @_;
  my ($name, $type, $radioId) = split("[ \t]+", $def);
  return "requires 1 parameters" unless (defined $radioId and $radioId ne "");
  $hash->{radioId} = $radioId;
  $hash->{sets} = {
    'time' => "",
    clear  => "",
    reboot => "",
  };
  $hash->{typeMappings} = {map {variableTypeToIdx($_) => $static_mappings{$_}} keys %static_mappings};
  $hash->{readingMappings} = {};
  AssignIoPort($hash);
};

sub UnDefine($) {
  my ($hash) = @_;
  
  return undef;
}

sub Set($@) {
  my ($hash,$name,$command,@values) = @_;
  return "Need at least one parameters" unless defined $command;
  return "Unknown argument $command, choose one of " . join(" ", map {$hash->{sets}->{$_} ne "" ? "$_:$hash->{sets}->{$_}" : $_} sort keys %{$hash->{sets}})
    if(!defined($hash->{sets}->{$command}));
  COMMAND_HANDLER: {
    $command eq "clear" and do {
      sendClientMessage($hash, childId => 255, cmd => C_INTERNAL, subType => I_CHILDREN, payload => "C");
      last;
    };
    $command eq "time" and do {
      sendClientMessage($hash, childId => 255, cmd => C_INTERNAL, subType => I_TIME, payload => time);
      last;
    };
    $command eq "reboot" and do {
      sendClientMessage($hash, childId => 255, cmd => C_INTERNAL, subType => I_REBOOT);
      last;
    };
    $command =~ /^(.+_\d+)$/ and do {
      my $value = @values ? join " ",@values : "";
      my ($type,$childId,$mappedValue) = readingToType($hash,$1,$value);
      sendClientMessage($hash, childId => $childId, cmd => C_SET, subType => $type, payload => $mappedValue);
      readingsSingleUpdate($hash,$command,$value,1) unless ($hash->{IODev}->{ack});
      last;
    };
    (defined ($hash->{setcommands}->{$command})) and do {
      my $setcommand = $hash->{setcommands}->{$command};
      my ($type,$childId,$mappedValue) = readingToType($hash,$setcommand->{var},$setcommand->{val});
      sendClientMessage($hash,
        childId => $childId,
        cmd => C_SET,
        subType => $type,
        payload => $mappedValue,
      );
      readingsSingleUpdate($hash,$setcommand->{var},$setcommand->{val},1) unless ($hash->{IODev}->{ack});
      last;
    };
    return "$command not defined by attr setCommands";
  }
}

sub Attr($$$$) {
  my ($command,$name,$attribute,$value) = @_;

  my $hash = $main::defs{$name};
  ATTRIBUTE_HANDLER: {
    $attribute eq "config" and do {
      if ($main::init_done) {
        sendClientMessage($hash, cmd => C_INTERNAL, subType => I_CONFIG, payload => $command eq 'set' ? $value : "M");
      }
      last;
    };
    $attribute eq "setCommands" and do {
      if ($command eq "set") {
        foreach my $setCmd (split ("[, \t]+",$value)) {
          $setCmd =~ /^(.+):(.+_\d+):(.+)$/;
          $hash->{sets}->{$1}="";
          $hash->{setcommands}->{$1} = {
            var => $2,
            val => $3,
          };
        }
      } else {
        foreach my $set (keys %{$hash->{setcommands}}) {
          delete $hash->{sets}->{$set};
        }
        $hash->{setcommands} = {};
      }
      last;
    };
    $attribute =~ /^set_(.+_\d+)$/ and do {
      if ($command eq "set") {
        $hash->{sets}->{$1}=join(",",split ("[, \t]+",$value));
      } else {
        CommandDeleteReading(undef,"$hash->{NAME} $1");
        delete $hash->{sets}->{$1};
      }
      last;
    };
    $attribute =~ /^mapReadingType_(.+)/ and do {
      my $type = variableTypeToIdx("V_$1");
      if ($command eq "set") {
        my @values = split ("[, \t]",$value);
        $hash->{typeMappings}->{$type}={
          type => shift @values,
          val => {map {$_ =~ /^(.+):(.+)$/; $1 => $2} @values},
        }
      } else {
        if ($static_mappings{"V_$1"}) {
          $hash->{typeMappings}->{$type}=$static_mappings{"V_$1"};
        } else {
          delete $hash->{typeMappings}->{$type};
        }
        CommandDeleteReading(undef,"$hash->{NAME} $1"); #TODO do propper remap of existing readings
      }
      last;
    };
  }
}

sub onGatewayStarted($) {
  my ($hash) = @_;
}

sub onPresentationMessage($$) {
  my ($hash,$msg) = @_;
}

sub onSetMessage($$) {
  my ($hash,$msg) = @_;
  my ($reading,$value) = mapReading($hash,$msg->{subType},$msg->{childId},$msg->{payload});
  readingsSingleUpdate($hash,$reading,$value,1);
}

sub onRequestMessage($$) {
  my ($hash,$msg) = @_;
  variableTypeToStr($msg->{subType}) =~ /^V_(.+)$/;
  sendClientMessage($hash,
    childId => $msg->{childId},
    cmd => C_SET,
    subType => $msg->{subType},
    payload => ReadingsVal($hash->{NAME},"$1\_$msg->{childId}","")
  );
}

sub onInternalMessage($$) {
  my ($hash,$msg) = @_;
  my $name = $hash->{NAME};
  my $type = $msg->{subType};
  my $typeStr = internalMessageTypeToStr($type);
  INTERNALMESSAGE: {
    $type == I_BATTERY_LEVEL and do {
      readingsSingleUpdate($hash,"batterylevel",$msg->{payload},1);
      Log3 ($name,4,"MYSENSORS_DEVICE $name: batterylevel $msg->{payload}");
      last;
    };
    $type == I_TIME and do {
      sendClientMessage($hash,cmd => C_INTERNAL, subType => I_TIME, payload => time);
      Log3 ($name,4,"MYSENSORS_DEVICE $name: update of time requested");
      last;
    };
    $type == I_VERSION and do {
      $hash->{$typeStr} = $msg->{payload};
      last;
    };
    $type == I_ID_REQUEST and do {
      $hash->{$typeStr} = $msg->{payload};
      last;
    };
    $type == I_ID_RESPONSE and do {
      $hash->{$typeStr} = $msg->{payload};
      last;
    };
    $type == I_INCLUSION_MODE and do {
      $hash->{$typeStr} = $msg->{payload};
      last;
    };
    $type == I_CONFIG and do {
      sendClientMessage($hash,cmd => C_INTERNAL, subType => I_CONFIG, payload => AttrVal($name,"config","M"));
      Log3 ($name,4,"MYSENSORS_DEVICE $name: respond to config-request");
      last;
    };
    $type == I_PING and do {
      $hash->{$typeStr} = $msg->{payload};
      last;
    };
    $type == I_PING_ACK and do {
      $hash->{$typeStr} = $msg->{payload};
      last;
    };
    $type == I_LOG_MESSAGE and do {
      $hash->{$typeStr} = $msg->{payload};
      last;
    };
    $type == I_CHILDREN and do {
      readingsSingleUpdate($hash,"state","routingtable cleared",1);
      Log3 ($name,4,"MYSENSORS_DEVICE $name: routingtable cleared");
      last;
    };
    $type == I_SKETCH_NAME and do {
      $hash->{$typeStr} = $msg->{payload};
      last;
    };
    $type == I_SKETCH_VERSION and do {
      $hash->{$typeStr} = $msg->{payload};
      last;
    };
    $type == I_REBOOT and do {
      $hash->{$typeStr} = $msg->{payload};
      last;
    };
  }
}

sub sendClientMessage($%) {
  my ($hash,%msg) = @_;
  $msg{radioId} = $hash->{radioId};
  sendMessage($hash->{IODev},%msg);
}

sub mapReading($$) {
  my($hash, $type, $childId, $value) = @_;

  if(defined (my $mapping = $hash->{typeMappings}->{$type})) {
    return ("$mapping->{type}_$childId",defined $mapping->{val}->{$value} ? $mapping->{val}->{$value} : $value);
  } else {
    return (variableTypeToStr($type)."_$childId",$value);
  }
}

sub readingToType($$$) {
  my ($hash,$reading,$value) = @_;
  $reading =~ /^(.+)_(\d+)$/;
  if (my @types = grep {$hash->{typeMappings}->{$_}->{type} eq $1} keys %{$hash->{typeMappings}}) {
    my $type = shift @types;
    my $valueMappings = $hash->{typeMappings}->{$type}->{val};
    if (my @mappedValues = grep {$valueMappings->{$_} eq $value} keys %$valueMappings) {
      return ($type,$2,shift @mappedValues);
    }
    return ($type,$2,$value);
  }
  return (variableTypeToIdx("V_$1"),$2,$value);
}

1;

=pod
=begin html

<a name="MYSENSORS_DEVICE"></a>
<h3>MYSENSORS_DEVICE</h3>
<ul>
  <p>represents a mysensors sensor attached to a mysensor-node</p>
  <p>requires a <a href="#MYSENSOR">MYSENSOR</a>-device as IODev</p>
  <a name="MYSENSORS_DEVICEdefine"></a>
  <p><b>Define</b></p>
  <ul>
    <p><code>define &lt;name&gt; MYSENSORS_DEVICE &lt;Sensor-type&gt; &lt;node-id&gt;</code><br/>
      Specifies the MYSENSOR_DEVICE device.</p>
  </ul>
  <a name="MYSENSORS_DEVICEattr"></a>
  <p><b>Attributes</b></p>
  <ul>
    <li>
      <p><code>attr &lt;name&gt; config [&lt;M|I&gt;]</code><br/>
         configures metric (M) or inch (I). Defaults to 'M'</p>
    </li>
    <li>
      <p><code>attr &lt;name&gt; mapReadingType_&lt;reading&gt; &lt;new reading name&gt; [&lt;value&gt;:&lt;mappedvalue&gt;]*</code><br/>
         configures reading user names that should be used instead of technical names<br/>
         E.g.: <code>attr xxx mapReadingType_LIGHT switch 0:on 1:off</code></p>
    </li>
  </ul>
</ul>

=end html
=cut
