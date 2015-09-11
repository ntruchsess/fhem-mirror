package Device::MySensors::Constants;

use List::Util qw(first); 
 
#-- Message types
use constant {
  C_PRESENTATION => 0,
  C_SET          => 1,
  C_REQ          => 2,
  C_INTERNAL     => 3,
  C_STREAM       => 4,
};

use constant commands => qw( C_PRESENTATION C_SET C_REQ C_INTERNAL C_STREAM );

sub commandToStr($) {
  (commands)[shift];
}

#-- Variable types
use constant {
  V_TEMP        => 0,
  V_HUM         => 1,
  V_LIGHT       => 2,
  V_DIMMER      => 3,
  V_PRESSURE    => 4,
  V_FORECAST    => 5,
  V_RAIN        => 6,
  V_RAINRATE    => 7,
  V_WIND        => 8,
  V_GUST        => 9,
  V_DIRECTION   => 10,
  V_UV          => 11,
  V_WEIGHT      => 12,
  V_DISTANCE    => 13,
  V_IMPEDANCE   => 14,
  V_ARMED       => 15,
  V_TRIPPED     => 16,
  V_WATT        => 17,
  V_KWH         => 18,
  V_SCENE_ON    => 19,
  V_SCENE_OFF   => 20,
  V_LIGHT_LEVEL => 21,
  V_VAR1        => 22,
  V_VAR2        => 23,
  V_VAR3        => 24,
  V_VAR4        => 25,
  V_VAR5        => 26,
  V_UP          => 27,
  V_DOWN        => 28,
  V_STOP        => 29,
  V_IR_SEND     => 30,
  V_IR_RECEIVE  => 31,
  V_FLOW        => 32,
  V_VOLUME      => 33,
  V_LOCK_STATUS => 34,
  V_VOLTAGE	    => 35,
  V_CURRENT     => 36,
  V_STATUS      => 37,
  V_PERCENTAGE  => 38,
  V_HVAC_FLOW_STATE => 39,
  V_HVAC_SPEED  => 40,
  V_LEVEL       => 41,
  V_RGB         => 42,
  V_RGBW        => 43,
  V_ID          => 44,
  V_UNIT_PREFIX => 45, 
  V_HVAC_SETPOINT_COOL => 46,
  V_HVAC_SETPOINT_HEAT => 47,
  V_HVAC_FLOW_MODE => 48,
};

use constant variableTypes => qw{ V_TEMP V_HUM V_LIGHT V_DIMMER V_PRESSURE V_FORECAST V_RAIN
        V_RAINRATE V_WIND V_GUST V_DIRECTION V_UV V_WEIGHT V_DISTANCE
        V_IMPEDANCE V_ARMED V_TRIPPED V_WATT V_KWH V_SCENE_ON V_SCENE_OFF
        V_LIGHT_LEVEL V_VAR1 V_VAR2 V_VAR3 V_VAR4 V_VAR5
        V_UP V_DOWN V_STOP V_IR_SEND V_IR_RECEIVE V_FLOW V_VOLUME V_LOCK_STATUS 
        V_VOLTAGE V_CURRENT V_STATUS V_PERCENTAGE V_HVAC_FLOW_STATE V_HVAC_SPEED 
        V_LEVEL V_RGB V_RGBW V_ID V_UNIT_PREFIX V_HVAC_SETPOINT_COOL V_HVAC_SETPOINT_HEAT V_HVAC_FLOW_MODE};

sub variableTypeToStr($) {
  (variableTypes)[shift];
}

sub variableTypeToIdx($) {
  my $var = shift;
  return first { (variableTypes)[$_] eq $var } 0 .. scalar(variableTypes);
}

#-- Internal messages
use constant {
  I_BATTERY_LEVEL    => 0,
  I_TIME             => 1,
  I_VERSION          => 2,
  I_ID_REQUEST       => 3,
  I_ID_RESPONSE      => 4,
  I_INCLUSION_MODE   => 5,
  I_CONFIG           => 6,
  I_PING             => 7,
  I_PING_ACK         => 8,
  I_LOG_MESSAGE      => 9,
  I_CHILDREN         => 10,
  I_SKETCH_NAME      => 11,
  I_SKETCH_VERSION   => 12,
  I_REBOOT           => 13,
  I_STARTUP_COMPLETE => 14.
};

use constant internalMessageTypes => qw{ I_BATTERY_LEVEL I_TIME I_VERSION I_ID_REQUEST I_ID_RESPONSE
        I_INCLUSION_MODE I_CONFIG I_PING I_PING_ACK
        I_LOG_MESSAGE I_CHILDREN I_SKETCH_NAME I_SKETCH_VERSION
        I_REBOOT I_STARTUP_COMPLETE };

sub internalMessageTypeToStr($) {
  (internalMessageTypes)[shift];
}

#-- Sensor types
use constant {
  S_DOOR                  => 0,
  S_MOTION                => 1,
  S_SMOKE                 => 2,
  S_LIGHT                 => 3,
  S_DIMMER                => 4,
  S_COVER                 => 5,
  S_TEMP                  => 6,
  S_HUM                   => 7,
  S_BARO                  => 8,
  S_WIND                  => 9,
  S_RAIN                  => 10,
  S_UV                    => 11,
  S_WEIGHT                => 12,
  S_POWER                 => 13,
  S_HEATER                => 14,
  S_DISTANCE              => 15,
  S_LIGHT_LEVEL           => 16,
  S_ARDUINO_NODE          => 17,
  S_ARDUINO_REPEATER_NODE => 18,
  S_LOCK                  => 19,
  S_IR                    => 20,
  S_WATER                 => 21,
  S_AIR_QUALITY           => 22,
  S_CUSTOM                => 23,
  S_DUST                  => 24,
  S_SCENE_CONTROLLER      => 25,
  S_BINARY                => 26,
  S_RGB_LIGHT             => 27,
  S_RGBW_LIGHT            => 28,
  S_COLOR_SENSOR          => 29,
  S_HVAC                  => 30,
  S_MULTIMETER            => 31,
  S_SPRINKLER             => 32,
  S_WATER_LEAK            => 33,	
  S_SOUND                 => 34,	
  S_VIBRATION             => 35,
  S_MOISTURE              => 36,
};

use constant sensorTypes => qw{ S_DOOR S_MOTION S_SMOKE S_LIGHT S_DIMMER S_COVER S_TEMP S_HUM S_BARO S_WIND
        S_RAIN S_UV S_WEIGHT S_POWER S_HEATER S_DISTANCE S_LIGHT_LEVEL S_ARDUINO_NODE
        S_ARDUINO_REPEATER_NODE S_LOCK S_IR S_WATER S_AIR_QUALITY S_CUSTOM S_DUST S_SCENE_CONTROLLER S_BINARY
        S_RGB_LIGHT S_RGBW_LIGHT S_COLOR_SENSOR S_HVAC S_MULTIMETER S_SPRINKLER S_WATER_LEAK S_SOUND S_VIBRATION
        S_MOISTURE};

sub sensorTypeToStr($) {
  (sensorTypes)[shift];
}

sub sensorTypeToIdx($) {
  my $var = shift;
  return first { (sensorTypes)[$_] eq $var } 0 .. scalar(sensorTypes);
}

#-- Datastream types
use constant {
  ST_FIRMWARE_CONFIG_REQUEST  => 0,
  ST_FIRMWARE_CONFIG_RESPONSE => 1,
  ST_FIRMWARE_REQUEST         => 2,
  ST_FIRMWARE_RESPONSE        => 3,
  ST_SOUND                    => 4,
  ST_IMAGE                    => 5,
};

use constant datastreamTypes => qw{ ST_FIRMWARE_CONFIG_REQUEST ST_FIRMWARE_CONFIG_RESPONSE ST_FIRMWARE_REQUEST ST_FIRMWARE_RESPONSE
        ST_SOUND ST_IMAGE };

sub datastreamTypeToStr($) {
  (datastreamTypes)[shift];
}

#-- Payload types
use constant {
  P_STRING  => 0,
  P_BYTE    => 1,
  P_INT16   => 2,
  P_UINT16  => 3,
  P_LONG32  => 4,
  P_ULONG32 => 5,
  P_CUSTOM  => 6,
};

use constant payloadTypes => qw{ P_STRING P_BYTE P_INT16 P_UINT16 P_LONG32 P_ULONG32 P_CUSTOM };

sub payloadTypeToStr($) {
  (payloadTypes)[shift];
}

sub subTypeToStr($$) {
  my $cmd = shift;
  my $subType = shift;
  # Convert subtype to string, depending on message type
  TYPE: {
    $cmd == C_PRESENTATION and do {
      $subType = (sensorTypes)[$subType];
      last;
    };
    $cmd == C_SET and do {
      $subType = (variableTypes)[$subType];
      last;
    };
    $cmd == C_REQ and do {
      $subType = (variableTypes)[$subType];
      last;
    };
    $cmd == C_INTERNAL and do {
      $subType = (internalMessageTypes)[$subType];
      last;
    };
    $subType = "<UNKNOWN_$subType>";
  }  
  return $subType;
}

use Exporter ('import');
@EXPORT = ();
@EXPORT_OK = (
  commands,
  variableTypes,
  internalMessageTypes,
  sensorTypes,
  datastreamTypes,
  payloadTypes,
  qw(commandToStr
    variableTypeToStr
    variableTypeToIdx
    internalMessageTypeToStr
    sensorTypeToStr
    sensorTypeToIdx
    datastreamTypeToStr
    payloadTypeToStr
    subTypeToStr
    commands
    variableTypes
    internalMessageTypes
    sensorTypes
    datastreamTypes
    payloadTypes
  ));

%EXPORT_TAGS = (all => [@EXPORT_OK]);

1;
