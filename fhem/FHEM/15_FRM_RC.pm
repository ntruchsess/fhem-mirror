package main;

use strict;
use warnings;

use Device::Firmata::Constants qw(PIN_OUTPUT PIN_LOW PIN_HIGH $COMMANDS);
our (%attr, %defs, $init_done);


use constant RC_ATTRIBUTES          => {
  'IODev'            => '',
  'vccPin'           => PIN_HIGH,
  'gndPin'           => PIN_LOW,
};
	
use constant RC_TRISTATE_BIT_VALUES => {
  TRISTATE_0        => 0,
  TRISTATE_F        => 1,
  TRISTATE_RESERVED => 2,
  TRISTATE_1        => 3,
};

use constant RC_TRISTATE_CHARS      => {
  RC_TRISTATE_BIT_VALUES->{TRISTATE_0} => '0',
  RC_TRISTATE_BIT_VALUES->{TRISTATE_F} => 'F',
  RC_TRISTATE_BIT_VALUES->{TRISTATE_1} => '1',
};

use constant RC_TRISTATE_BITS      => { reverse(%{RC_TRISTATE_CHARS()}) };

my @rc_observers = ();


sub
FRM_RC_Initialize($)
{
  LoadModule('FRM');
}

sub
FRM_RC_UnDef($$)
{
  my ($hash, $name) = @_;
  my $pin = $hash->{PIN};
  FRM_RC_unregister_observer($hash, $pin);
  FRM_Client_Undef($hash, $name);
}

sub
FRM_RC_Init($$$$$)
{
  my ($hash, $pinmode, $observer_method, $rcswitchAttributes, $args) = @_;

  # Initialize pin for firmata 
  my $ret = FRM_Init_Pin_Client($hash, $args, $pinmode);
  return $ret if (defined $ret);

  my $pin  = $hash->{PIN};
  my $name = $hash->{NAME};
  Log3($hash, 5, "$name: initialization start");
  eval {
    # Register observer for messages from the controller  
    FRM_RC_register_observer($hash, $pin, $observer_method);

    # Read all attributes values - they have been set before by FHEM - and
    # apply them without setting them again    
    my %attributes = (%{RC_ATTRIBUTES()}, %$rcswitchAttributes);
    foreach my $attribute (keys %attributes) {
      if ($attr{$name}{$attribute}) {
        FRM_RC_apply_attribute($hash, $attribute, %$rcswitchAttributes);
      } else {
        Log3($hash, 5, "$name: $attribute is undefined");
      }  
    }
  };
  return FRM_Catch($@) if $@;
  readingsSingleUpdate($hash, 'state', 'Initialized', 1);
  Log3($hash, 5, "$name: initialization end");
  return undef;
}

sub
FRM_RC_Attr($$$$$)
{
  my ($command, $name, $attribute, $value, $rcswitchAttributes) = @_;
  my $hash = $defs{$name};

  eval {
    if ($command eq 'set') {
      Log3($name, 4, "$name: $attribute := $value");
      $attr{$name}{$attribute} = $value;
      my %attributes = (%{RC_ATTRIBUTES()}, %$rcswitchAttributes);
      if (defined $attributes{$attribute}) {
        FRM_RC_apply_attribute($hash, $attribute, %$rcswitchAttributes);
      } else {
      	Log3($name, 5, "$name: no further processing for $attribute");
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

sub FRM_RC_register_observer {
  my ($hash, $pin, $observer_method) = @_;
  my $name = $hash->{NAME};
  $rc_observers[$pin] =  {
      method  => $observer_method,
      context => $hash,
  };
  my $firmata = FRM_Client_FirmataDevice($hash);
  my $currentObserver = $firmata->{sysex_observer};
  if (defined $currentObserver and $currentObserver->{method} eq \&FRM_RC_observe_sysex) {
      Log3($hash, 4, "$name: Reusing existing sysex observer $currentObserver->{method}");
  } else {
    if (defined $currentObserver) {
      Log3($hash, 2, "$name: Overwriting existing sysex observer $currentObserver with "
                     . \&FRM_RC_observe_sysex);
    } else {
      Log3($hash, 4, "$name: Registering new sysex observer");
    }
    $firmata->observe_sysex(\&FRM_RC_observe_sysex, undef);
  }
  return 1;
}

sub FRM_RC_unregister_observer {
  my ($hash, $pin) = @_;
  Log3($hash, 4, "$hash->{NAME}: removing observer");
  $rc_observers[$pin] = undef;
}

# apply an attribute (whose value is already set)
sub FRM_RC_apply_attribute {
  my ($hash, $attribute, %rcswitchAttributes) = @_;
  my $name = $hash->{NAME};

  if (!$init_done) {
    Log3($hash, 4, "$name: $attribute is not applied during initialization");
    return undef;
  }
  
  my %attributes = (%{RC_ATTRIBUTES()}, %rcswitchAttributes);
  return "Unknown attribute $attribute, choose one of " . join(' ', sort keys %attributes)
    if(!defined($attributes{$attribute}));

  my $value = $attr{$name}{$attribute};
  if ($attribute eq 'IODev') {
    if (!defined ($hash->{IODev}) or $hash->{IODev}->{NAME} ne $value) {
      Log3($hash, 4, "$name: Initializing as firmata client");      
      FRM_Client_AssignIOPort($hash, $value);
      FRM_Init_Client($hash) if (defined ($hash->{IODev}));
    }
  } elsif (defined(RC_ATTRIBUTES->{$attribute})) {
    my $pin = $value;
    my $pinValue = $attributes{$attribute};
    Log3($hash, 4, "$name: pin $pin := " . (!$pinValue ? 'LOW' : 'HIGH'));
    my $device = FRM_Client_FirmataDevice($hash);
    $device->pin_mode($pin, PIN_OUTPUT);
    $device->digital_write($pin, $pinValue);
  } else {
    Log3($hash, 4, "$name: Sending $attribute := $value to the controller");
    FRM_RC_set_parameter($hash,
                         $rcswitchAttributes{$attribute},
                         $hash->{PIN},
                         $value);
  }
}

sub FRM_RC_set_parameter {
  my ( $hash, $subcommand, $pin, $value ) = @_;
  my @data = ($value & 0xFF, ($value>>8) & 0xFF);
  return FRM_RC_send_message($hash, $subcommand, $pin, @data);
}


sub FRM_RC_observe_sysex {
  my ($sysex_message, undef) = @_;
  
  my $command            = $sysex_message->{command};
  my $sysex_message_data = $sysex_message->{data};
  my $subcommand         = shift @$sysex_message_data;
  my $pin                = shift @$sysex_message_data;
  my @data               = Device::Firmata::Protocol::unpack_from_7bit(@$sysex_message_data);
  my $observer           = $rc_observers[$pin];

  if (defined $observer) {
    $observer->{method}( $observer->{context}, $subcommand, @data );
  }
}

sub FRM_RC_get_tristate_code {
  return join('', map { my $v = RC_TRISTATE_CHARS->{$_};
                        defined $v ? $v : 'X';
                      }
                  @_);
}	

sub FRM_RC_get_tristate_bits {
  my ($v) = @_;
  return map {RC_TRISTATE_BITS->{$_}} split('', uc($v));
}

sub FRM_RC_get_tristate_byte {
  my @transferSymbols = @_;
  while ((@transferSymbols & 0x03) != 0) {
    push @transferSymbols, RC_TRISTATE_BIT_VALUES->{TRISTATE_RESERVED};
  }
  return @transferSymbols;
}

sub FRM_RC_send_message {
  my ($hash, $subcommand, $pin, @data) = @_;
  my $firmata = FRM_Client_FirmataDevice($hash);
  my $command
    = $COMMANDS->{$firmata->{protocol}->{protocol_version}}->{RESERVED_COMMAND};
  Log3($hash, 4, "$hash->{NAME}: Sending $command $subcommand $pin "
                   . join(' ', @data));
  
  return $firmata->sysex_send($command,
                              $subcommand,
                              $pin,
                              Device::Firmata::Protocol::pack_as_7bit(@data));
}

1;


=pod

=begin html

<a name="FRM_RC"></a>
<h3>FRM_RC</h3>
  <p>
   Support module for <a href="#FRM_RCIN">FRM_RCIN</a> and
   <a href="#FRM_RCOUT">FRM_RCOUT</a>.
  </p>
  <a name="FRM_RCattr"></a>
  <h4>Attributes</h4>
  <ul>
    <li>
      <code>vccPin</code>: Arduino pin that is used as voltage source for the
      RC device.
    </li>
    <li>
      <code>gndPin</code>: Arduino pin that is used as ground for the RC device.
    </li>
  </ul>
  <p>
   These attributes allow an RC sender or receiver to be plugged in directly
   into the Arduino pin sockets, without additional wiring.<br />
   Example:
  </p>
  <pre>
    define sender FRM_RCOUT 5
    attr sender vccPin 6
    attr sender gndPin 7
  </pre>
<br />

=end html
=cut
