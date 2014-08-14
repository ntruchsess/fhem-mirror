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
  my ($pt_reset,$pt_select,$pt_write,$pt_read,$i,@response);
  my @data = unpack "C*", $writedata if defined $writedata;

  return PT_THREAD(sub {
    my ($thread) = @_;
    
    PT_BEGIN($thread);
    if ($reset) {
      $pt_reset = $self->pt_reset();
      PT_WAIT_THREAD($pt_reset);
      die $pt_reset->PT_CAUSE() if ($pt_reset->PT_STATE() == PT_ERROR || $pt_reset->PT_STATE() == PT_CANCELED);
      die "reset failure" unless ($pt_reset->PT_RETVAL());
    }
    if ($owx_dev) {
      $pt_select = $self->pt_wireSelect();
    } else {
      $pt_select = $self->pt_wireSkip();
    }
    PT_WAIT_THREAD($pt_select);
    die $pt_select->PT_CAUSE() if ($pt_select->PT_STATE() == PT_ERROR || $pt_select->PT_STATE() == PT_CANCELED);
    
    while(@data) {
      $pt_write = $self->pt_wireWriteByte(shift @data);
      PT_WAIT_THREAD($pt_write);
      die $pt_write->PT_CAUSE() if ($pt_write->PT_STATE() == PT_ERROR || $pt_write->PT_STATE() == PT_CANCELED);
    }
    
    if ($numread) {
      for ($i = 0; $i < $numread; $i++) {
        $pt_read = $self->pt_wireReadByte();
        PT_WAIT_THREAD($pt_read);
        die $pt_read->PT_CAUSE() if ($pt_read->PT_STATE() == PT_ERROR || $pt_read->PT_STATE() == PT_CANCELED);
        push @response,$pt_read->PT_RETVAL();
      }
      PT_EXIT(pack "C*", @response);
    }
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

sub pt_detect($) {
  my ( $self, $address ) = @_;
  my ($reset,$configure);
  return PT_THREAD(sub {
    my ($thread) = @_;
    PT_BEGIN($thread);
    $self->{address} = DS2482_I2C_ADDR | $address;
    $reset = $self->pt_reset();
    PT_WAIT_THREAD($reset);
    die $reset->PT_CAUSE() if ($reset->PT_STATE() == PT_ERROR || $reset->PT_STATE() == PT_CANCELED);
    unless ($reset->PT_RETVAL()) {
      PT_EXIT;
    }
    $configure = $self->pt_configure(DS2482_CFG_APU);
    PT_WAIT_THREAD($configure);
    die $configure->PT_CAUSE() if ($configure->PT_STATE() == PT_ERROR || $configure->PT_STATE() == PT_CANCELED);
    PT_EXIT($configure->PT_RETVAL());
    PT_END;
  });
}

#TODO obsolete?
sub pt_wireReadStatus($) {
  my ( $self, $setPtr ) = @_;
  return PT_THREAD(sub {
    my ($thread) = @_;
    PT_BEGIN($thread);
    if ($setPtr) {
      $self->i2c_write(DS2482_CMD_SRP,DS2482_READPTR_SR);
    }
    $self->i2c_request(1);
    PT_WAIT_UNTIL($self->i2c_response_ready());
    # check for failure due to incorrect read back of status
    PT_EXIT(($self->{response});
    PT_END;
  });
}

sub pt_busyWait($) {
  my ( $self, $setReadPtr ) = @_;
  my $status;
  return PT_THREAD(sub {
    my ($thread) = @_;
    PT_BEGIN($thread);
    if($setReadPtr) {
      $self->i2c_write(DS2482_CMD_SRP,DS2482_READPTR_SR);
    }
    do {
      $self->i2c_request(1);
      PT_WAIT_UNTIL($self->i2c_response_ready());
    } while ($status = $self->{response} & DS2482_STATUS_1WB);
    PT_EXIT($status);
    PT_END;
  });
}

#-- interface

sub pt_reset() {
  my ( $self ) = @_;

  return PT_THREAD(sub {
    my ($thread) = @_;
    PT_BEGIN($thread);
    $self->{state} = 0;
    $self->i2c_write(DS2482_CMD_DRST);
    $self->i2c_request(1);
    PT_WAIT_UNTIL($self->i2c_response_ready());
    # check for failure due to incorrect read back of status
    PT_EXIT(($self->{response} & 0xf7) == 0x10);
    PT_END;
  });
}

sub pt_configure($) {
  my ( $self, $config ) = @_;
  my $busyWait;
  return PT_THREAD(sub {
    my ($thread) = @_;
    PT_BEGIN($thread);
    $busyWait = $self->pt_busyWait(1);
    PT_WAIT_THEAD($busyWait);
    die $busyWait->PT_CAUSE() if ($busyWait->PT_STATE() == PT_ERROR || $busyWait->PT_STATE() == PT_CANCELED);

    $self->i2c_write(DS2482_CMD_WCFG, $config | (~$config << 4));

    $self->i2c_request(1);
    PT_WAIT_UNTIL($self->i2c_response_ready());
    if ($self->{response} == $config) {
      PT_EXIT(1);
    }
    $self->reset();
    return undef;
  });
}

sub pt_selectChannel($) {
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

  my $busyWait;

  return PT_THREAD(sub {
    my ($thread) = @_;
    PT_BEGIN($thread);
    $busyWait = $self->pt_busyWait(1);
    PT_WAIT_THEAD($busyWait);
    die $busyWait->PT_CAUSE() if ($busyWait->PT_STATE() == PT_ERROR || $busyWait->PT_STATE() == PT_CANCELED);

    $self->i2c_write(DS2482_CMD_CHSL,$ch);
  
    $busyWait = $self->pt_busyWait(0);
    PT_WAIT_THEAD($busyWait);
    die $busyWait->PT_CAUSE() if ($busyWait->PT_STATE() == PT_ERROR || $busyWait->PT_STATE() == PT_CANCELED);
  
    $self->i2c_request(1);
    PT_WAIT_UNTIL($self->i2c_response_ready());
    PT_EXIT($self->{response} == $ch_read);
    PT_END;
  });  
}

sub pt_wireReset() {
  my ( $self ) = @_;
  my $busyWait;
  return PT_THREAD(sub {
    my ($thread) = @_;
    PT_BEGIN($thread);
    $busyWait = $self->pt_busyWait(1);
    PT_WAIT_THEAD($busyWait);
    die $busyWait->PT_CAUSE() if ($busyWait->PT_STATE() == PT_ERROR || $busyWait->PT_STATE() == PT_CANCELED);

    $self->i2c_write(DS2482_CMD_1WRS);

    $busyWait = $self->pt_busyWait(0);
    PT_WAIT_THEAD($busyWait);
    die $busyWait->PT_CAUSE() if ($busyWait->PT_STATE() == PT_ERROR || $busyWait->PT_STATE() == PT_CANCELED);

    my $status = $busyWait->PT_RETVAL();

    # check for short condition
    if ($status & DS2482_STATUS_SD) {
      $self->{state} |= DS2482_STATE_SHORTEND;
    }
    # check for presence detect
    PT_EXIT($status & DS2482_STATUS_PPD);
    PT_END;
  });
}

sub pt_wireWriteByte($) {
  my ( $self, $b ) = @_;
  my $busyWait;
  return PT_THREAD(sub {
    my ($thread) = @_;
    PT_BEGIN($thread);
    $busyWait = $self->pt_busyWait(1);
    PT_WAIT_THEAD($busyWait);
    die $busyWait->PT_CAUSE() if ($busyWait->PT_STATE() == PT_ERROR || $busyWait->PT_STATE() == PT_CANCELED);
    $self->i2c_write(DS2482_CMD_1WWB,$b);
    PT_END;
  });
}

sub pt_wireReadByte() {
  my ( $self ) = @_;
  my $busyWait;
  return PT_THREAD(sub {
    my ($thread) = @_;
    PT_BEGIN($thread);
    $busyWait = $self->pt_busyWait(1);
    PT_WAIT_THEAD($busyWait);
    die $busyWait->PT_CAUSE() if ($busyWait->PT_STATE() == PT_ERROR || $busyWait->PT_STATE() == PT_CANCELED);
  
    $self->i2c_write(DS2482_CMD_1WRB);

    $busyWait = $self->pt_busyWait(0);
    PT_WAIT_THEAD($busyWait);
    die $busyWait->PT_CAUSE() if ($busyWait->PT_STATE() == PT_ERROR || $busyWait->PT_STATE() == PT_CANCELED);
  
    $self->i2c_write(DS2482_CMD_SRP,DS2482_READPTR_RDR);
    
    $self->i2c_request(1);
    PT_WAIT_UNTIL($self->i2c_response_ready());
    PT_EXIT($self->{response});
    PT_END;
  });
}

sub pt_wireWriteBit($) {
  my ( $self, $bit ) = @_;
  my $busyWait;
  return PT_THREAD(sub {
    my ($thread) = @_;
    PT_BEGIN($thread);
    $busyWait = $self->pt_busyWait(1);
    PT_WAIT_THEAD($busyWait);
    die $busyWait->PT_CAUSE() if ($busyWait->PT_STATE() == PT_ERROR || $busyWait->PT_STATE() == PT_CANCELED);
    $self->i2c_write(DS2482_CMD_1WSB,$bit ? 0x80 : 0);
    PT_END;
  });
}

sub pt_wireReadBit() {
  my ( $self ) = @_;
  my ($busyWait,$writeBit);
  return PT_THREAD(sub {
    my ($thread) = @_;
    PT_BEGIN($thread);
    $writeBit = $self->pt_wireWriteBit(1);
    PT_WAIT_THREAD($writeBit);
    $busyWait = $self->pt_busyWait(1);
    PT_WAIT_THEAD($busyWait);
    die $busyWait->PT_CAUSE() if ($busyWait->PT_STATE() == PT_ERROR || $busyWait->PT_STATE() == PT_CANCELED);
    PT_EXIT($busyWait->PT_RETVAL() & DS2482_STATUS_SBR ? 1 : 0);
    PT_END;
  });
}

sub pt_wireSkip() {
  my ( $self ) = @_;
  return $self->pt_wireWriteByte(SKIP_ROM);
}

sub pt_wireSelect($) {
  my ( $self, $rom ) = @_;
  my $wireWriteByte;
  return PT_THREAD(sub {
    my ($thread) = @_;
    PT_BEGIN($thread);
    $wireWriteByte = $self->pt_wireWriteByte(COPY_SCRATCHPAD);
    PT_WAIT_THREAD($wireWriteByte);
    die $wireWriteByte->PT_CAUSE() if ($wireWriteByte->PT_STATE() == PT_ERROR || $wireWriteByte->PT_STATE() == PT_CANCELED);
    if (!$self->{state}) {
      for (my $i=0; $i < 8 && !$self->{state}; $i++) {
        $wireWriteByte = $self->pt_wireWriteByte($rom->[$i]);
        PT_WAIT_THREAD($wireWriteByte);
        die $wireWriteByte->PT_CAUSE() if ($wireWriteByte->PT_STATE() == PT_ERROR || $wireWriteByte->PT_STATE() == PT_CANCELED);
      }
    }
    PT_END;
  });
}

#if ONEWIRE_SEARCH
sub wireResetSearch() {
  my ( $self ) = @_;
  $self->{searchExhausted} = 0;
  $self->{searchLastDisrepancy} = 0;
  $self->{searchAddress} = [0,0,0,0,0,0,0,0];
}

sub pt_wireSearch($) {
  my ( $self ) = @_;
  return $self->pt_wireSearchInternal(SEARCH);
}

sub pt_wireSearchAlarms($) {
  my ( $self ) = @_;
  return $self->pt_wireSearchInternal(SEARCH_ALARMS);
}

sub pt_wireSearchInternal($) {
  my ( $self, $command ) = @_;
  my $i;
  my $direction;
  my $last_zero=0;
  my ($reset,$busyWait,$wireWriteByte);
  return PT_THREAD(sub {
    my ($thread) = @_;
    PT_BEGIN($thread);

    if ($self->{searchExhausted}) {
      PT_EXIT(0);
    }

    $reset = $self->pt_wireReset();
    PT_WAIT_THREAD($reset);
    die $reset->PT_CAUSE() if ($reset->PT_STATE() == PT_ERROR || $reset->PT_STATE() == PT_CANCELED);
    if (!$reset->PT_RETVAL()) {
      PT_EXIT(0);
    }
    
    $busyWait = $self->pt_busyWait(1);
    PT_WAIT_THREAD($busyWait);
    die $busyWait->PT_CAUSE() if ($busyWait->PT_STATE() == PT_ERROR || $busyWait->PT_STATE() == PT_CANCELED);

    $wireWriteByte = $self->pt_wireWriteByte($command);
    PT_WAIT_THREAD($wireWriteByte);
    die $wireWriteByte->PT_CAUSE() if ($wireWriteByte->PT_STATE() == PT_ERROR || $wireWriteByte->PT_STATE() == PT_CANCELED);

    for(my $i=1;$i<65;$i++) {

      my $romByte = ($i-1)>>3;
      my $romBit = 1<<(($i-1)&7);

      if ($i < $self->{searchLastDisrepancy}) {
        $direction = $self->{searchAddress}->[$romByte] & $romBit;
      } else {
        $direction = $i == $self->{searchLastDisrepancy} ? 1 : 0;
      }

      $busyWait = $self->pt_busyWait();
      PT_WAIT_THREAD($busyWait);
      die $busyWait->PT_CAUSE() if ($busyWait->PT_STATE() == PT_ERROR || $busyWait->PT_STATE() == PT_CANCELED);

      $self->i2c_write(DS2482_CMD_1WT,$direction ? 0x80 : 0);

      $busyWait = $self->pt_busyWait();
      PT_WAIT_THREAD($busyWait);
      die $busyWait->PT_CAUSE() if ($busyWait->PT_STATE() == PT_ERROR || $busyWait->PT_STATE() == PT_CANCELED);
    
      my $status = $busyWait->PT_RETVAL();

      my $id = $status & DS2482_STATUS_SBR;
      my $comp_id = $status & DS2482_STATUS_TSB;
      $direction = $status & DS2482_STATUS_DIR;

      if ($id == 1 && $comp_id == 1) {
        PT_EXIT(0);
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

    PT_EXIT(1);
    PT_END;
  });
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

sub i2c_request() {
	my ( $self ) = @_;
	my $hash = $self->{hash};
	if (defined (my $iodev = $hash->{IODev})) {
	  delete $self->{response};
		main::CallFn($iodev->{NAME}, "I2CWrtFn", $iodev, {
			i2caddress => $hash->{I2C_Address},
			direction  => "i2cread",
			nbyte      => 1
		});
	} else {
		die "no IODev assigned to '$hash->{NAME}'";
	}
}

sub i2c_response_ready() {
  my ( $self ) = @_;
  return undef unless defined $self->{response}; 
  die "I2C-Error" unless $self->{response_state};
  return 1;
}

sub i2c_received($$@) {
  my ( $self, $nbyte, $data, $ok ) = @_;
  die "unexpected response length $nbyte" unless $nbyte == 1; 
  $self->{response} = $data;
  $self->{response_state} = $ok
}

1;
