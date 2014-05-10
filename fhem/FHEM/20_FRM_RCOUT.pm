#############################################
package main;

use strict;
use warnings;

#add FHEM/lib to @INC if it's not allready included. Should rather be in fhem.pl than here though...
BEGIN {
	if (!grep(/FHEM\/lib$/,@INC)) {
		foreach my $inc (grep(/FHEM$/,@INC)) {
			push @INC,$inc."/lib";
		};
	};
};

use Device::Firmata::Constants  qw/ :all /;

#####################################

my %sets = (
  "tristateCode"     => $Device::Firmata::Protocol::RCOUTPUT_COMMANDS->{RCOUTPUT_CODE_PACKED_TRISTATE},
  "longCode"         => $Device::Firmata::Protocol::RCOUTPUT_COMMANDS->{RCOUTPUT_CODE_LONG},
  "charCode"         => $Device::Firmata::Protocol::RCOUTPUT_COMMANDS->{RCOUTPUT_CODE_CHAR},
);

my %attributes = (
  "protocol"         => $Device::Firmata::Protocol::RCOUTPUT_COMMANDS->{RCOUTPUT_PROTOCOL},
  "pulseLength"      => $Device::Firmata::Protocol::RCOUTPUT_COMMANDS->{RCOUTPUT_PULSE_LENGTH},
  "repeatTransmit"   => $Device::Firmata::Protocol::RCOUTPUT_COMMANDS->{RCOUTPUT_REPEAT_TRANSMIT},
  "defaultBitCount"  => 24,
);

my %tristateBits = (
  "0" => $Device::Firmata::Protocol::RC_TRISTATE_BITS->{TRISTATE_0},
  "F" => $Device::Firmata::Protocol::RC_TRISTATE_BITS->{TRISTATE_F},
  "1" => $Device::Firmata::Protocol::RC_TRISTATE_BITS->{TRISTATE_1},
);

sub
FRM_RCOUT_Initialize($)
{
  my ($hash) = @_;

  $hash->{SetFn}     = "FRM_RCOUT_Set";
  $hash->{DefFn}     = "FRM_Client_Define";
  $hash->{InitFn}    = "FRM_RCOUT_Init";
  $hash->{UndefFn}   = "FRM_Client_Undef";
  $hash->{AttrFn}    = "FRM_RCOUT_Attr";
  
  $hash->{AttrList}  = "IODev " . join(" ", keys %attributes) . " $main::readingFnAttributes";
  main::LoadModule("FRM");
}

sub
FRM_RCOUT_Init($$)
{
  my ($hash, $args) = @_;
  my $ret = FRM_Init_Pin_Client($hash, $args, PIN_RCOUTPUT);
  return $ret if (defined $ret);
  my $pin = $hash->{PIN};
  eval {
    my $firmata = FRM_Client_FirmataDevice($hash);
    $firmata->observe_rc($pin, \&FRM_RCOUT_observer, $hash);
  };
  return FRM_Catch($@) if $@;
  readingsSingleUpdate($hash, "state", "Initialized", 1);
  return undef;
}

sub
FRM_RCOUT_Attr($$$$) {
  my ($command,$name,$attribute,$value) = @_;
  my $hash = $main::defs{$name};
  eval {
    if ($command eq "set") {
      ARGUMENT_HANDLER: {
        $attribute eq "IODev" and do {
          if ($main::init_done and (!defined ($hash->{IODev}) or $hash->{IODev}->{NAME} ne $value)) {
            FRM_Client_AssignIOPort($hash,$value);
            FRM_Init_Client($hash) if (defined ($hash->{IODev}));
          }
          last;
        };
        
        defined($attributes{$attribute}) and do {
          if ($main::init_done) {
          	$main::attr{$name}{$attribute}=$value;
            FRM_RCOUT_apply_attribute($hash,$attribute);
          }
          last;
        };
        
      }
    }
  };
  my $ret = FRM_Catch($@) if $@;
  if ($ret) {
    $hash->{STATE} = "error setting $attribute to $value: ".$ret;
    return "cannot $command attribute $attribute to $value for $name: ".$ret;
  }
  return undef;
}

# The attribute is not applied within this module; instead, it is sent to the
# microcontroller. When the change was successful, a response message will
# arrive in the observer sub.
sub FRM_RCOUT_apply_attribute {
  my ($hash,$attribute) = @_;
  my $name = $hash->{NAME};

  return "Unknown attribute $attribute, choose one of " . join(" ", sort keys %attributes)
  	if(!defined($attributes{$attribute}));

  if ($attribute ne "defaultBitCount") {
    FRM_Client_FirmataDevice($hash)->rc_set_parameter($hash->{PIN},
                                                      $attributes{$attribute},
                                                      $main::attr{$name}{$attribute});
  }
}

sub FRM_RCOUT_observer
{
  my ( $key, $value, $hash ) = @_;
  my $name = $hash->{NAME};
  
  my %s = reverse(%sets);
  my %a = reverse(%attributes);
  my $subcommand = $s{$key};
  my $attrName = $a{$key};
  
COMMAND_HANDLER: {
    defined($subcommand) and do {
      if ("tristateCode" eq $subcommand) {
        my $tristateCode = shift @$value;
        Log3 $name, 5, "$subcommand: $tristateCode";
        readingsSingleUpdate($hash, $subcommand, $tristateCode, 1);
      } elsif ("longCode" eq $subcommand) {
        my $bitlength = shift @$value;
        my $longCode  = shift @$value;
        Log3 $name, 5, "$subcommand: $longCode";
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash, $subcommand, $longCode);
        readingsBulkUpdate($hash, "bitlength", $bitlength);
        readingsEndUpdate($hash, 1);
      } elsif ("charCode" eq $subcommand || "tristateString" eq $subcommand) {
        my $charCode = shift @$value; 
        readingsSingleUpdate($hash, $subcommand, $charCode, 1);
      } else {
        readingsSingleUpdate($hash, "state", "unknown subcommand $subcommand", 1);
      }
      last;
    };
    defined($attrName) and do {
      $value = shift @$value;
      Log3 $name, 4, "$attrName: $value";

      $main::attr{$name}{$attrName}=$value;
      # TODO refresh web GUI somehow?
      last;
    };
};
}

sub
FRM_RCOUT_Set($@)
{
  my ($hash, @a) = @_;
  return "Need at least 2 parameters" if(@a < 2);
  my $command = $sets{$a[1]};
  return "Unknown argument $a[1], choose one of " . join(" ", sort keys %sets)
  	if(!defined($command));
  my @code;
  eval {
    if ($command eq $Device::Firmata::Protocol::RCOUTPUT_COMMANDS->{RCOUTPUT_CODE_PACKED_TRISTATE}) {
      @code = map {$tristateBits{$_}} split("", uc($a[2])); 
    } elsif ($command eq $Device::Firmata::Protocol::RCOUTPUT_COMMANDS->{RCOUTPUT_CODE_LONG}) {
      my $value = $a[2];
      my $bitCount = $a[3];
      $bitCount = $attr{$hash->{NAME}}{"defaultBitCount"} if not defined $bitCount;
      $bitCount = 24 if not defined $bitCount;
      @code = ($bitCount, $value);
    } elsif ($command eq $Device::Firmata::Protocol::RCOUTPUT_COMMANDS->{RCOUTPUT_CODE_CHAR}) {
        @code = map {ord($_)} split("", $a[2]);
    }
    FRM_Client_FirmataDevice($hash)->rcoutput_send_code($command, $hash->{PIN}, @code);
  };
  return $@;
}

1;

=pod
=begin html

<a name="FRM_RCOUT"></a>
<h3>FRM_RCOUT</h3>
<ul>
  represents a pin of an <a href="http://www.arduino.cc">Arduino</a> running <a href="http://www.firmata.org">Firmata</a>
  configured to send data via the RCSwitch library.<br>
  Requires a defined <a href="#FRM">FRM</a>-device to work.<br><br> 
  
  <a name="FRM_RCOUTdefine"></a>
  <b>Define</b>
  <ul>
  <code>define &lt;name&gt; FRM_RCOUT &lt;pin&gt;</code> <br>
  Defines the FRM_RCOUT device. &lt;pin&gt> is the arduino-pin to use.
  </ul>
  
  <br>
  <a name="FRM_RCOUTset"></a>
  <b>Set</b><br>
  <ul>
  <code>set &lt;name&gt; code &lt;code&gt;</code><br>sends a tristate coded message, e.g. <code>00FFF FF0FF F0<code> <br/> 
  </ul>
  <a name="FRM_RCOUTget"></a>
  <b>Get</b><br>
  <ul>
  N/A
  </ul><br>
  <a name="FRM_RCOUTattr"></a>
  <b>Attributes</b><br>
  <ul>
      <li><a href="#IODev">IODev</a><br>
      Specify which <a href="#FRM">FRM</a> to use. (Optional, only required if there is more
      than one FRM-device defined.)
      </li>
      <li>protocol</li>
      <li>pulseLength</li>
      <li>repeatTransmit</li>
      <li><a href="#eventMap">eventMap</a><br></li>
      <li><a href="#readingFnAttributes">readingFnAttributes</a><br></li>
    </ul>
  </ul>
<br>

=end html
=cut
