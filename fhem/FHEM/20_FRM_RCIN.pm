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
);

my %attributes = (
  "tolerance"        => $Device::Firmata::Protocol::RCINPUT_COMMANDS->{RCINPUT_TOLERANCE},
);

my %tristateBits = (
  "0" => $Device::Firmata::Protocol::RC_TRISTATE_BITS->{TRISTATE_0},
  "F" => $Device::Firmata::Protocol::RC_TRISTATE_BITS->{TRISTATE_F},
  "1" => $Device::Firmata::Protocol::RC_TRISTATE_BITS->{TRISTATE_1},
);

sub
FRM_RCIN_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}     = "FRM_Client_Define";
  $hash->{InitFn}    = "FRM_RCIN_Init";
  $hash->{UndefFn}   = "FRM_Client_Undef";
  $hash->{AttrFn}    = "FRM_RCIN_Attr";
  
  $hash->{AttrList}  = "IODev " . join(" ", keys %attributes) . " $main::readingFnAttributes";
  main::LoadModule("FRM");
}

sub
FRM_RCIN_Init($$)
{
  my ($hash, $args) = @_;
  my $ret = FRM_Init_Pin_Client($hash, $args, PIN_RCINPUT);
  return $ret if (defined $ret);
  my $pin = $hash->{PIN};
  eval {
    my $firmata = FRM_Client_FirmataDevice($hash);
    $firmata->observe_rc($pin, \&FRM_RCIN_observer, $hash);
  };
  return FRM_Catch($@) if $@;
  main::readingsSingleUpdate($hash, "state", "Initialized", 1);
  return undef;
}

sub
FRM_RCIN_Attr($$$$) {
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
            FRM_RCIN_apply_attribute($hash,$attribute);
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
sub FRM_RCIN_apply_attribute { # TODO this one is identical to FRM_RCOUT_apply_attribute, merge
  my ($hash,$attribute) = @_;
  my $name = $hash->{NAME};

  return "Unknown attribute $attribute, choose one of " . join(" ", sort keys %attributes)
  	if(!defined($attributes{$attribute}));

  FRM_Client_FirmataDevice($hash)->rc_set_parameter($hash->{PIN},
                                                    $attributes{$attribute},
                                                    $main::attr{$name}{$attribute});
}

sub FRM_RCIN_observer
{
  my ( $key, $value, $hash ) = @_;
  my $name = $hash->{NAME};
  
  my %a = reverse(%attributes);
  
COMMAND_HANDLER: {
    ($key eq $Device::Firmata::Protocol::RCINPUT_COMMANDS->{RCINPUT_MESSAGE}) and do {
      Log3 $name, 5, "Received RC message: " . join(" ", @$value);

      my $message   = (@$value[0] << 24) + (@$value[1] << 16) + (@$value[2] << 8) + @$value[3];
      my $bitlength = (@$value[4] << 8) + @$value[5];
      my $delay     = (@$value[6] << 8) + @$value[7];
      my $protocol  = (@$value[8] << 8) + @$value[9];

      # TODO: check for redundancy with RCOUT;  extract the sub long_to_tristate_code
      my @messageAsTristateBits;
      for (my $shift = 30; $shift >= 0; $shift-=2) {
        push @messageAsTristateBits, ($message >> $shift) & 3;
      }
      my %tristateChars = reverse(%tristateBits);
      my $tristateCode = join("", map { my $v = $tristateChars{$_}; defined $v ? $v : "X";} @messageAsTristateBits); 
      
      main::readingsSingleUpdate($hash, 'message', $message, 1);
      main::readingsSingleUpdate($hash, 'tristateCode', $tristateCode, 1);
      main::readingsSingleUpdate($hash, 'bitlength', $bitlength, 1);
      main::readingsSingleUpdate($hash, 'delay', $delay, 1);
      main::readingsSingleUpdate($hash, 'protocol', $protocol, 1);
      last;
    };
    defined($a{$key}) and do {
      $value = @$value[0] + (@$value[1] << 8);
      Log3 $name, 4, "$a{$key}: $value";

      $main::attr{$name}{$a{$key}}=$value;
      # TODO refresh web GUI somehow?
      last;
    };
};
}

1;

=pod
=begin html

<a name="FRM_RCIN"></a>
<h3>FRM_RCIN</h3>
<ul>
  represents a pin of an <a href="http://www.arduino.cc">Arduino</a> running <a href="http://www.firmata.org">Firmata</a>
  configured to receive data via the RCSwitch library.<br>
  Requires a defined <a href="#FRM">FRM</a>-device to work.<br><br> 
  
  <a name="FRM_RCINdefine"></a>
  <b>Define</b>
  <ul>
  <code>define &lt;name&gt; FRM_RCIN &lt;pin&gt;</code> <br>
  Defines the FRM_RCIN device. &lt;pin&gt> is the arduino-pin to use.
  </ul>
  
  <br>
  <a name="FRM_RCINset"></a>
  <b>Set</b><br>
  <ul>
  N/A
  </ul>
  <a name="FRM_RCINget"></a>
  <b>Get</b><br>
  <ul>
  N/A
  </ul><br>
  <a name="FRM_RCINattr"></a>
  <b>Attributes</b><br>
  <ul>
      <li><a href="#IODev">IODev</a><br>
      Specify which <a href="#FRM">FRM</a> to use. (Optional, only required if there is more
      than one FRM-device defined.)
      </li>
      <li>tolerance Receive tolerance (in percent)</li>
      <li><a href="#eventMap">eventMap</a><br></li>
      <li><a href="#readingFnAttributes">readingFnAttributes</a><br></li>
    </ul>
  </ul>
<br>

=end html
=cut
