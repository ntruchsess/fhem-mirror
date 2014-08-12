########################################################################################
#
# OWX_DS2482.pm
#
# FHEM module providing hardware dependent functions for I2C- interface of OWX_ASYNC
#
# Norbert Truchsess
#
# $Id$
#
########################################################################################
#
# Provides the following methods for OWX_ASYNC
#
# Alarms
# Complex
# Define
# Discover
# Init
# Reset
# Verify
#
########################################################################################

package OWX_DS2482;

use strict;
use warnings;
use Time::HiRes qw( gettimeofday );
use ProtoThreads;
no warnings 'deprecated';

########################################################################################
# 
# Constructor
#
########################################################################################

sub new() {
  my $class = shift;
  my $self = {
    interface => "i2c",
    #-- module version
    version => 1.0,
    alarmdevs => [],
    devs => [],
    fams => [],
  };
  return bless $self,$class;
}

########################################################################################
# 
# Public methods
#
########################################################################################
#
# Define - Implements Define method
# 
# Parameter def = definition string
#
# Return undef if ok, otherwise error message
#
########################################################################################

sub Define ($$) {
  my ($self,$hash,$def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  $self->{name} = $hash->{NAME};

  #-- check syntax
  if(int(@a) < 3 or $a[2] ne "i2c") {
    return "OWX_DS2482: Syntax error - must be define <name> OWX_ASYNC i2c <i2c-address>"
  }
  
  $hash->{I2C_Address} = @a>3 ? $a[3] =~ /^0.*$/ ? oct($a[3]) : $a[3] : 0b0011000; 
  
  $self->{address} = $hash->{I2C_Address};
  $self->{hash} = $hash;
  
  return undef;
}

sub get_pt_alarms() {
  my ($self) = @_;
  return PT_THREAD(sub {
    my ($thread) = @_;
    PT_BEGIN($thread);
    delete $self->{alarmdevs};
    main::FRM_Client_FirmataDevice($self->{hash})->onewire_search_alarms($self->{pin});
    main::OWX_ASYNC_TaskTimeout($self->{hash},gettimeofday+main::AttrVal($self->{name},"timeout",2));
    PT_WAIT_UNTIL(defined $self->{alarmdevs});
    PT_EXIT($self->{alarmdevs});
    PT_END;
  });
}

sub get_pt_verify($) {
  my ($self,$dev) = @_;
  return PT_THREAD(sub {
    my ($thread) = @_;
    PT_BEGIN($thread);
    delete $self->{devs};
    main::FRM_Client_FirmataDevice($self->{hash})->onewire_search($self->{pin});
    main::OWX_ASYNC_TaskTimeout($self->{hash},gettimeofday+main::AttrVal($self->{name},"timeout",2));
    PT_WAIT_UNTIL(defined $self->{devs});
    PT_EXIT(scalar(grep {$dev eq $_} @{$self->{devs}}));
    PT_END;
  });
}

sub get_pt_execute($$$$) {
  my ($self, $reset, $owx_dev, $writedata, $numread) = @_;
  return PT_THREAD(sub {
    my ($thread) = @_;
    
    PT_BEGIN($thread);

    if (  my $firmata = main::FRM_Client_FirmataDevice($self->{hash}) and my $pin = $self->{pin} ) {
      my @data = unpack "C*", $writedata if defined $writedata;
      my $id = $self->{id};
      my $ow_command = {
        'reset'  => $reset,
        'skip'   => defined($owx_dev) ? undef : 1,
        'select' => defined($owx_dev) ? device_to_firmata($owx_dev) : undef,
        'read'  => $numread,
        'write' => @data ? \@data : undef,
        'delay' => undef,
        'id'    => $numread ? $id : undef
      };
      main::Log3 ($self->{name},5,"FRM_OWX_Execute: $id: $owx_dev [".join(" ",(map sprintf("%02X",$_),@data))."] numread: ".(defined $numread ? $numread : 0)) if $self->{debug};
      $firmata->onewire_command_series( $pin, $ow_command );
      if ($numread) {
        $thread->{id} = $id;
        $self->{id} = ( $id + 1 ) & 0xFFFF;
        delete $self->{responses}->{$id};
        main::OWX_ASYNC_TaskTimeout($self->{hash},gettimeofday+main::AttrVal($self->{name},"timeout",2));
        PT_WAIT_UNTIL(defined $self->{responses}->{$thread->{id}});
        my $ret = pack "C*", @{$self->{responses}->{$thread->{id}}};
        delete $self->{responses}->{$thread->{id}};
        PT_EXIT($ret);
      };
    };
    PT_END;
  });
};

sub poll() {
  my ( $self ) = @_;
  if ( my $frm = $self->{hash}->{IODev} ) {
    main::FRM_poll($frm);
  }
};

sub exit($) {
  my ($self) = @_;
}

########################################################################################
# 
# DS2482 library code
#
########################################################################################

use constant {
  DS2482_I2C_ADDR => 0x18, # Base I2C address of DS2482 devices
  POLL_LIMIT => 0x30, # 0x30 is the minimum poll limit
# 1-wire eeprom and silicon serial number commands
  READ_DEVICE_ROM => 0x33,
  SKIP_ROM => 0xCC,
  WRITE_SCRATCHPAD => 0x0F,
  READ_MEMORY => 0xF0,
  COPY_SCRATCHPAD => 0x55,
  SEARCH => 0xF0,
  SEARCH_ALARMS => 0xEC,
# DS2482 command defines
  DS2482_CMD_DRST => 0xF0, # DS2482 Device Reset
  DS2482_CMD_SRP => 0xE1, # DS2482 Set Read Pointer
  DS2482_CMD_WCFG => 0xD2, # DS2482 Write Configuration
  DS2482_CMD_CHSL => 0xC3, # DS2482 Channel Select
  DS2482_CMD_1WRS => 0xB4, # DS2482 1-Wire Reset
  DS2482_CMD_1WWB => 0xA5, # DS2482 1-Wire Write Byte
  DS2482_CMD_1WRB => 0x96, # DS2482 1-Wire Read Byte
  DS2482_CMD_1WSB => 0x87, # DS2482 1-Wire Single Bit
  DS2482_CMD_1WT => 0x78, # DS2482 1-Wire Triplet
# DS2482 status register bit defines
  DS2482_STATUS_1WB => 0x01, # DS2482 Status 1-Wire Busy
  DS2482_STATUS_PPD => 0x02, # DS2482 Status Presence Pulse Detect
  DS2482_STATUS_SD => 0x04, # DS2482 Status Short Detected
  DS2482_STATUS_LL => 0x08, # DS2482 Status 1-Wire Logic Level
  DS2482_STATUS_RST => 0x10, # DS2482 Status Device Reset
  DS2482_STATUS_SBR => 0x20, # DS2482 Status Single Bit Result
  DS2482_STATUS_TSB => 0x40, # DS2482 Status Triplet Second Bit
  DS2482_STATUS_DIR => 0x80, # DS2482 Status Branch Direction Taken
# DS2482 configuration register bit defines
  DS2482_CFG_APU => 0x01, # DS2482 Config Active Pull-Up
# DS2482_CFG_PPM => 0x02, # DS2482 Config Presence Pulse Masking
# (not recommendet according to Datasheet since 11/2009)
  DS2482_CFG_SPU => 0x04, # DS2482 Config Strong Pull-Up
  DS2482_CFG_1WS => 0x08, # DS2482 Config 1-Wire Speed
# DS2482 channel selection code for defines
  DS2482_CH_IO0 => 0xF0, # DS2482 Select Channel IO0
  DS2482_CH_IO1 => 0xE1, # DS2482 Select Channel IO1
  DS2482_CH_IO2 => 0xD2, # DS2482 Select Channel IO2
  DS2482_CH_IO3 => 0xC3, # DS2482 Select Channel IO3
  DS2482_CH_IO4 => 0xB4, # DS2482 Select Channel IO4
  DS2482_CH_IO5 => 0xA5, # DS2482 Select Channel IO5
  DS2482_CH_IO6 => 0x96, # DS2482 Select Channel IO6
  DS2482_CH_IO7 => 0x87, # DS2482 Select Channel IO7
# DS2482 channel selection read back code for defines
  DS2482_RCH_IO0 => 0xB8, # DS2482 Select Channel IO0
  DS2482_RCH_IO1 => 0xB1, # DS2482 Select Channel IO1
  DS2482_RCH_IO2 => 0xAA, # DS2482 Select Channel IO2
  DS2482_RCH_IO3 => 0xA3, # DS2482 Select Channel IO3
  DS2482_RCH_IO4 => 0x9C, # DS2482 Select Channel IO4
  DS2482_RCH_IO5 => 0x95, # DS2482 Select Channel IO5
  DS2482_RCH_IO6 => 0x8E, # DS2482 Select Channel IO6
  DS2482_RCH_IO7 => 0x87, # DS2482 Select Channel IO7
# DS2482 read pointer code defines
  DS2482_READPTR_SR => 0xF0, # DS2482 Status Register
  DS2482_READPTR_RDR => 0xE1, # DS2482 Read Data Register
  DS2482_READPTR_CSR => 0xD2, # DS2482 Channel Selection Register
  DS2482_READPTR_CR => 0xC3, # DS2482 Configuration Register
  DS2482_STATE_TIMEOUT => 1,
  DS2482_STATE_SHORTEND => 2,
};

sub detect($) {
  my ( $self, $address ) = @_;
  $self->{address} = DS2482_I2C_ADDR | $address;
  return undef unless ($self->reset()); 
  return $self->configure(DS2482_CFG_APU);
}

sub setReadPtr($) {
  my ( $self, $readPtr ) = @_;
  $self->i2c_write(DS2482_CMD_SRP,$readPtr);
}

sub readByte() {
  my ( $self ) = @_;
  return $self->i2c_request($self->{address},1);
}

sub wireReadStatus($) {
  my ( $self, $setPtr ) = @_;
  if ($setPtr) {
    $self->setReadPtr(DS2482_READPTR_SR);
  }
  return $self->readByte();
}

sub busyWait($) {
  my ( $self, $setReadPtr ) = @_;
  my $status;
  my $loopCount = 1000;
  while(($status = $self->wireReadStatus($setReadPtr)) & DS2482_STATUS_1WB) {
    if (--$loopCount <= 0) {
      $self->{state} |= DS2482_STATE_TIMEOUT;
      last;
    }
    select(undef,undef,undef,0.000020); # was: delayMicroseconds(20); #TODO protothreads here!
  }
  return $status;
}

#-- interface

sub reset() {
  my ( $self ) = @_;
  $self->{state} = 0;
  $self->i2c_write(DS2482_CMD_DRST);
  my $result = readByte();
  # check for failure due to incorrect read back of status
  return (($result & 0xf7) == 0x10);
}

sub configure($) {
  my ( $self, $config ) = @_;
  
  if ($self->busyWait(1) && ($self->{state} & DS2482_STATE_TIMEOUT)) {
    return undef;
  }
  
  $self->i2c_write(DS2482_CMD_WCFG, $config | (~$config << 4));

  if ($self->readByte() == $config) {
    return 1;
  }
  $self->reset();
  return undef;
}

sub selectChannel($) {
  my ( $self, $channel ) = @_;	
  my ($ch, $ch_read);
  CHANNEL: {
    $channel == 0 and do {
      $ch = DS2482_CH_IO0;
      $ch_read = DS2482_RCH_IO0;
      last;
    };
    $channel == 1 and do {
      $ch = DS2482_CH_IO1;
      $ch_read = DS2482_RCH_IO1;
      last;
    };
    $channel == 2 and do {
      $ch = DS2482_CH_IO2;
      $ch_read = DS2482_RCH_IO2;
      last;
    };
    $channel == 3 and do {
      $ch = DS2482_CH_IO3;
      $ch_read = DS2482_RCH_IO3;
      last;
    };
    $channel == 4 and do {
      $ch = DS2482_CH_IO4;
      $ch_read = DS2482_RCH_IO4;
      last;
    };
    $channel == 5 and do {
      $ch = DS2482_CH_IO5;
      $ch_read = DS2482_RCH_IO5;
      last;
    };
    $channel == 6 and do {
      $ch = DS2482_CH_IO6;
      $ch_read = DS2482_RCH_IO6;
      last;
    };
    $channel == 7 and do {
      $ch = DS2482_CH_IO7;
      $ch_read = DS2482_RCH_IO7;
      last;
    };
  };

  if ($self->busyWait(1) && ($self->{state} & DS2482_STATE_TIMEOUT)) {
    return undef;
  }
  
  $self->i2c_write(DS2482_CMD_CHSL,$ch);
  
  if ($self->busyWait() && ($self->{state} & DS2482_STATE_TIMEOUT)) {
    return false;
  }
  
  return ($self->readByte() == $ch_read);
}

sub wireReset() {
  my ( $self ) = @_;
  if ($self->busyWait(1) && ($self->{state} & DS2482_STATE_TIMEOUT)) {
    return 0;
  }
  $self->i2c_write(DS2482_CMD_1WRS);

  my $status = $self->busyWait();

  # check for short condition
  if ($status & DS2482_STATUS_SD) {
    $self->{state} |= DS2482_STATE_SHORTEND;
  }
  # check for presence detect
  return status & DS2482_STATUS_PPD;
}

sub wireWriteByte($) {
  my ( $self, $b ) = @_;
  if ($self->busyWait(1) && ($self->{state} & DS2482_STATE_TIMEOUT)) {
    return;
  }
  $self->i2c_write(DS2482_CMD_1WWB,$b);
}

sub wireReadByte() {
  my ( $self ) = @_;
  if ($self->busyWait(1) && ($self->{state} & DS2482_STATE_TIMEOUT)) {
    return 0;
  }
  
  $self->i2c_write(DS2482_CMD_1WRB);
  
  if ($self->busyWait() && ($self->{state} & DS2482_STATE_TIMEOUT)) {
    return 0;
  }
  $self->setReadPtr(DS2482_READPTR_RDR);
  return $self->readByte();
}

sub wireWriteBit($) {
  my ( $self, $bit ) = @_;
  if ($self->busyWait(1) && ($self->{state} & DS2482_STATE_TIMEOUT)) {
    return;
  }
  $self->i2c_write(DS2482_CMD_1WSB,$bit ? 0x80 : 0);
}

sub wireReadBit() {
  my ( $self ) = @_;
  $self->wireWriteBit(1);
  my $status = $self->busyWait(1);
  return $status & DS2482_STATUS_SBR ? 1 : 0;
}

sub wireSkip() {
  my ( $self ) = @_;
  $self->wireWriteByte(SKIP_ROM);
}

sub wireSelect($) {
  my ( $self, $rom ) = @_;
  $self->wireWriteByte(COPY_SCRATCHPAD);
  if (!$self->{state}) {
    for (my $i=0; $i < 8 && !$self->{state}; $i++) {
      $self->wireWriteByte($rom->[$i]);
    }
  }
}

#if ONEWIRE_SEARCH
sub wireResetSearch() {
  my ( $self ) = @_;
  $self->{searchExhausted} = 0;
  $self->{searchLastDisrepancy} = 0;
  $self->{searchAddress} = [0,0,0,0,0,0,0,0];
}

sub wireSearch($) {
  my ( $self ) = @_;
  return $self->wireSearchInternal(SEARCH);
}

sub wireSearchAlarms($) {
  my ( $self ) = @_;
  return $self->wireSearchInternal(SEARCH_ALARMS);
}

sub wireSearchInternal($) {
  my ( $self, $command ) = @_;
  my $i;
  my $direction;
  my $last_zero=0;

  if ($self->{searchExhausted}) {
    return 0;
  }

  if (!$self->wireReset()) {
    return 0;
  }

  $self->busyWait(1);
  $self->wireWriteByte($command);

  for(my $i=1;$i<65;$i++) {

    my $romByte = ($i-1)>>3;
    my $romBit = 1<<(($i-1)&7);

    if ($i < $self->{searchLastDisrepancy}) {
      $direction = $self->{searchAddress}->[$romByte] & $romBit;
    } else {
      $direction = $i == $self->{searchLastDisrepancy} ? 1 : 0;
    }

    $self->busyWait();
    
    $self->i2c_write(DS2482_CMD_1WT,$direction ? 0x80 : 0);
    
    my $status = $self->busyWait();

    my $id = $status & DS2482_STATUS_SBR;
    my $comp_id = $status & DS2482_STATUS_TSB;
    $direction = $status & DS2482_STATUS_DIR;

    if ($id == 1 && $comp_id == 1) {
      return 0;
    } elsif ($id == 0 && $comp_id == 0 && $direction == 0) {
      $last_zero = i;
    }

    if ($direction) {
      $self->{searchAddress}->[$romByte] |= $romBit;
    } else {
      $self->{searchAddress}->[$romByte] &= ~$romBit;
    }
  }

  $self->{searchLastDisrepancy} = $last_zero;

  if ($last_zero == 0) {
    $self->{searchExhausted} = 1;
  }

  return 1;
}

########################################################################################
# 
# adaption to fhem I2C hardware-independent interface
#
########################################################################################

sub i2c_write(@) {
	my ( $self, @data ) = @_;
	my $hash = $self->{hash};
	if (defined (my $iodev = $hash->{IODev})) {
		main::CallFn($iodev->{NAME}, "I2CWrtFn", $iodev, {
			i2caddress => $hash->{I2C_Address},
			direction  => "i2cwrite",
			data       => join (' ',@data)
		});
	} else {
		die "no IODev assigned to '$hash->{NAME}'";
	}
}

sub i2c_request($) {
	my ( $self, $nbyte ) = @_;
	my $hash = $self->{hash};
	if (defined (my $iodev = $hash->{IODev})) {
	  delete $self->{response};
		main::CallFn($iodev->{NAME}, "I2CWrtFn", $iodev, {
			i2caddress => $hash->{I2C_Address},
			direction  => "i2cread",
			nbyte      => $nbyte
		});
	} else {
		die "no IODev assigned to '$hash->{NAME}'";
	}
}

sub i2c_response_ready() {
  my ( $self ) = @_;
  return undef unless defined $self->{response}; 
  die "I2C-Error" unless $self->{response}->{state};
  return 1;
}

sub i2c_received($$@) {
  my ( $self, $nbyte, $data, $ok ) = @_;
  $self->{response} = {
    len   => $nbyte,
    data  => $data,
    state => $ok,
  };
}

1;