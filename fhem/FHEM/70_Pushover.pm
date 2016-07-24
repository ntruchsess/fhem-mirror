# $Id$
###############################################################################
#
# A module to send notifications to Pushover.
#
# written        2013 by Johannes B <johannes_b at icloud.com>
# modified 24.02.2014 by Benjamin Battran <fhem.contrib at benni.achalmblick.de>
#	-> Added title, device, priority and sound attributes (see documentation below)
# modified 09.08.2015 by Julian Pawlowski <julian.pawlowski@gmail.com>
# -> Rewrite for Non-Blocking HttpUtils
# -> much more readings
# -> Support for emergency callback via push (see documentation below)
# -> Support for supplementary URLs incl. push callback (e.g. for priority < 2)
# -> Added readingFnAttributes to AttrList
# -> Added support for HTML formatted text
# -> Added user/group token validation
#
###############################################################################
#
# Definition:
# define <name> Pushover <token> <user> [<infix>]
#
# Example:
# define Pushover1 Pushover 12345 6789
# define Pushover1 Pushover 12345 6789 pushCallback1
#
#
# You can send messages via the following command:
# set <Pushover_device> msg ['title'] '<msg>' ['<device>' <priority> '<sound>' [<retry> <expire> ['<url_title>' '<action>']]]
#
# Examples:
# set Pushover1 msg 'This is a text.'
# set Pushover1 msg 'Title' 'This is a text.'
# set Pushover1 msg 'Title' 'This is a text.' '' 0 ''
# set Pushover1 msg 'Emergency' 'Security issue in living room.' '' 2 'siren' 30 3600
# set Pushover1 msg 'Hint' 'This is a reminder to do something' '' 0 '' '' 3600 'Click here for action' 'set device something'
#
# Explantation:
#
# For the first and the second example the corresponding device attributes for the
# missing arguments must be set with valid values (see attributes section)
#
# If device is empty, the message will be sent to all devices.
# If sound is empty, the default setting in the app will be used.
# If priority is higher or equal 2, retry and expire must be defined.
#
#
# For further documentation of these parameters:
# https://pushover.net/api

package main;

use HttpUtils;
use utf8;
use Data::Dumper;
use HttpUtils;
use SetExtensions;
use Encode;

no if $] >= 5.017011, warnings => 'experimental::smartmatch';

my %sets = ( "msg" => 1 );

#------------------------------------------------------------------------------
sub Pushover_Initialize($$) {
    my ($hash) = @_;
    $hash->{DefFn}   = "Pushover_Define";
    $hash->{UndefFn} = "Pushover_Undefine";
    $hash->{SetFn}   = "Pushover_Set";
    $hash->{AttrList} =
"disable:0,1 timestamp:0,1 title sound:pushover,bike,bugle,cashregister,classical,cosmic,falling,gamelan,incoming,intermission,magic,mechanical,pianobar,siren,spacealarm,tugboat,alien,climb,persistent,echo,updown,none device priority:0,1,-1,-2 callbackUrl "
      . $readingFnAttributes;

    # a priority value of 2 is not predifined as for this also a value for
    # retry and expire must be set which will most likely not be used with
    # default values.
}

#------------------------------------------------------------------------------
sub Pushover_addExtension($$$) {
    my ( $name, $func, $link ) = @_;

    my $url = "/$link";

    return 0
      if ( defined( $data{FWEXT}{$url} )
        && $data{FWEXT}{$url}{deviceName} ne $name );

    Log3 $name, 2,
      "Pushover $name: Registering Pushover for webhook URI $url ...";
    $data{FWEXT}{$url}{deviceName} = $name;
    $data{FWEXT}{$url}{FUNC}       = $func;
    $data{FWEXT}{$url}{LINK}       = $link;
    $name->{HASH}{FHEMWEB_URI}     = $url;

    return 1;
}

#------------------------------------------------------------------------------
sub Pushover_removeExtension($) {
    my ($link) = @_;

    my $url  = "/$link";
    my $name = $data{FWEXT}{$url}{deviceName};
    Log3 $name, 2,
      "Pushover $name: Unregistering Pushover for webhook URL $url...";
    delete $data{FWEXT}{$url};
    delete $name->{HASH}{FHEMWEB_URI};
}

#------------------------------------------------------------------------------
sub Pushover_Define($$) {
    my ( $hash, $def ) = @_;

    my @args = split( "[ \t]+", $def );

    return
"Invalid number of arguments: define <name> Pushover <token> <user> [<infix>]"
      if ( int(@args) < 2 );

    my ( $name, $type, $token, $user, $infix ) = @args;

    return "$user does not seem to be a valid user or group token"
      if ( $user !~ /^([a-zA-Z0-9]{30})$/ );

    if ( defined($token) && defined($user) ) {

        $hash->{APP_TOKEN} = $token;
        $hash->{USER_KEY}  = $user;

        if ( defined($infix) && $infix ne "" ) {
            $hash->{fhem}{infix} = $infix;

            return "Could not register infix, seems to be existing"
              if ( !Pushover_addExtension( $name, "Pushover_CGI", $infix ) );
        }

        # start Validation Timer
        RemoveInternalTimer($hash);
        if (   ReadingsVal( $name, "tokenState", "invalid" ) ne "valid"
            || ReadingsVal( $name, "userState", "invalid" ) ne "valid"
            || $init_done )
        {
            InternalTimer( gettimeofday() + 5,
                "Pushover_ValidateUser", $hash, 0 );
        }
        else {
            InternalTimer( gettimeofday() + 21600,
                "Pushover_ValidateUser", $hash, 0 );
        }

        return undef;
    }
    else {
        return "App or user/group token missing.";
    }
}

#------------------------------------------------------------------------------
sub Pushover_Undefine($$) {
    my ( $hash, $name ) = @_;

    if ( defined( $hash->{fhem}{infix} ) ) {
        Pushover_removeExtension( $hash->{fhem}{infix} );
    }

    RemoveInternalTimer($hash);

    return undef;
}

#------------------------------------------------------------------------------
sub Pushover_Set($@) {
    my ( $hash, $name, $cmd, @args ) = @_;

    if ( !defined( $sets{$cmd} ) ) {
        return
            "Unknown argument "
          . $cmd
          . ", choose one of "
          . join( " ", sort keys %sets );
    }

    return "Unable to send message: Device is disabled"
      if ( AttrVal( $name, "disable", 0 ) == 1 );

    return "Unable to send message: User key is invalid"
      if ( ReadingsVal( $name, "userState", "valid" ) eq "invalid" );

    return "Unable to send message: App token is invalid"
      if ( ReadingsVal( $name, "tokenState", "valid" ) eq "invalid" );

    return Pushover_SetMessage( $hash, @args )
      if ( $cmd eq 'msg' );
}

#------------------------------------------------------------------------------
sub Pushover_SendCommand($$;$\%) {
    my ( $hash, $service, $cmd, $type ) = @_;
    my $name            = $hash->{NAME};
    my $address         = "api.pushover.net";
    my $port            = "443";
    my $apiVersion      = "1";
    my $http_method     = "POST";
    my $http_noshutdown = ( defined( $attr{$name}{"http-noshutdown"} )
          && $attr{$name}{"http-noshutdown"} eq "0" ) ? 0 : 1;
    my $timeout;
    $cmd = ( defined($cmd) ) ? $cmd : "";

    Log3 $name, 5, "Pushover $name: called function Pushover_SendCommand()";

    my $http_proto;
    if ( $port eq "443" ) {
        $http_proto = "https";
    }
    elsif ( defined( $attr{$name}{https} ) && $attr{$name}{https} eq "1" ) {
        $http_proto = "https";
        $port = "443" if ( $port eq "80" );
    }
    else {
        $http_proto = "http";
    }

    $cmd .= "&" if ( $cmd ne "" );
    $cmd .= "token=" . $hash->{APP_TOKEN};

    if ( !defined( $type->{USER_KEY} ) ) {
        $cmd .= "&user=" . $hash->{USER_KEY};
    }
    else {
        Log3 $name, 4,
          "Pushover $name: USER_KEY found in device name: " . $type->{USER_KEY};
        $cmd .= "&user=" . $type->{USER_KEY};
    }

    my $URL;
    my $response;
    my $return;

    if ( !defined($cmd) || $cmd eq "" ) {
        Log3 $name, 4, "Pushover $name: REQ $service";
    }
    else {
        $cmd = "?" . $cmd . "&"
          if ( $http_method eq "GET" || $http_method eq "" );
        Log3 $name, 4, "Pushover $name: REQ $service/" . urlDecode($cmd);
    }

    $URL =
        $http_proto . "://"
      . $address . ":"
      . $port . "/"
      . $apiVersion . "/"
      . $service;
    $URL .= $cmd if ( $http_method eq "GET" || $http_method eq "" );

    if ( defined( $attr{$name}{timeout} )
        && $attr{$name}{timeout} =~ /^\d+$/ )
    {
        $timeout = $attr{$name}{timeout};
    }
    else {
        $timeout = 3;
    }

    # send request via HTTP-GET method
    if ( $http_method eq "GET" || $http_method eq "" || $cmd eq "" ) {
        Log3 $name, 5,
            "Pushover $name: GET "
          . urlDecode($URL)
          . " (noshutdown="
          . $http_noshutdown . ")";

        HttpUtils_NonblockingGet(
            {
                url        => $URL,
                timeout    => $timeout,
                noshutdown => $http_noshutdown,
                data       => undef,
                hash       => $hash,
                service    => $service,
                cmd        => $cmd,
                type       => $type,
                callback   => \&Pushover_ReceiveCommand,
            }
        );

    }

    # send request via HTTP-POST method
    elsif ( $http_method eq "POST" ) {
        Log3 $name, 5,
            "Pushover $name: GET "
          . $URL
          . " (POST DATA: "
          . urlDecode($cmd)
          . ", noshutdown="
          . $http_noshutdown . ")";

        HttpUtils_NonblockingGet(
            {
                url        => $URL,
                timeout    => $timeout,
                noshutdown => $http_noshutdown,
                data       => $cmd,
                hash       => $hash,
                service    => $service,
                cmd        => $cmd,
                type       => $type,
                callback   => \&Pushover_ReceiveCommand,
            }
        );
    }

    # other HTTP methods are not supported
    else {
        Log3 $name, 1,
            "Pushover $name: ERROR: HTTP method "
          . $http_method
          . " is not supported.";
    }

    return;
}

#------------------------------------------------------------------------------
sub Pushover_ReceiveCommand($$$) {
    my ( $param, $err, $data ) = @_;
    my $hash    = $param->{hash};
    my $name    = $hash->{NAME};
    my $service = $param->{service};
    my $cmd     = $param->{cmd};
    my $state   = ReadingsVal( $name, "state", "initialized" );
    my $values  = $param->{type};
    my $return;

    Log3 $name, 5,
        "Pushover $name: Received HttpUtils callback:\n\nPARAM:\n"
      . Dumper($param)
      . "\n\nERROR:\n"
      . Dumper($err)
      . "\n\nDATA:\n"
      . Dumper($data);

    readingsBeginUpdate($hash);

    # service not reachable
    if ($err) {
        $state = "disconnected";

        if ( !defined($cmd) || $cmd eq "" ) {
            Log3 $name, 4, "Pushover $name: RCV TIMEOUT $service";
        }
        else {
            Log3 $name, 4,
              "Pushover $name: RCV TIMEOUT $service/" . urlDecode($cmd);
        }
    }

    # data received
    elsif ($data) {
        $state = "connected";

        if ( !defined($cmd) || $cmd eq "" ) {
            Log3 $name, 4, "Pushover $name: RCV $service";
        }
        else {
            Log3 $name, 4, "Pushover $name: RCV $service/" . urlDecode($cmd);
        }

        if ( $data ne "" ) {
            if ( $data =~ /^{/ || $data =~ /^\[/ ) {
                if ( !defined($cmd) || ref($cmd) eq "HASH" || $cmd eq "" ) {
                    Log3 $name, 5, "Pushover $name: RES $service\n" . $data;
                }
                else {
                    Log3 $name, 5,
                        "Pushover $name: RES $service/"
                      . urlDecode($cmd) . "\n"
                      . $data;
                }

                # Use JSON module if possible
                eval {
                    require JSON;
                    import JSON qw( decode_json );
                };
                $return = decode_json( Encode::encode_utf8($data) )
                  if ( !$@ );
            }
            else {
                if ( !defined($cmd) || ref($cmd) eq "HASH" || $cmd eq "" ) {
                    Log3 $name, 5,
                      "Pushover $name: RES ERROR $service\n" . $data;
                }
                else {
                    Log3 $name, 5,
                        "Pushover $name: RES ERROR $service/"
                      . urlDecode($cmd) . "\n"
                      . $data;
                }

                return undef;
            }
        }

        $return = Encode::encode_utf8($data) if ( ref($return) ne "HASH" );

        #######################
        # process return data
        #

        $values{result} = "ok";

        # extract API stats
        my $apiLimit     = 7500;
        my $apiRemaining = 1;
        my $apiReset;
        if ( $param->{httpheader} =~ m/X-Limit-App-Limit:[\s\t]*(.*)[\s\t\n]*/ )
        {
            $apiLimit = $1;
            readingsBulkUpdate( $hash, "apiLimit", $1 )
              if ( ReadingsVal( $name, "apiLimit", "" ) ne $1 );
        }
        if ( $param->{httpheader} =~
            m/X-Limit-App-Remaining:[\s\t]*(.*)[\s\t\n]*/ )
        {
            $apiRemaining = $1;
            readingsBulkUpdate( $hash, "apiRemaining", $1 )
              if ( ReadingsVal( $name, "apiRemaining", "" ) ne $1 );
        }
        if ( $param->{httpheader} =~ m/X-Limit-App-Reset:[\s\t]*(.*)[\s\t\n]*/ )
        {
            $apiReset = $1;
            readingsBulkUpdate( $hash, "apiReset", $1 )
              if ( ReadingsVal( $name, "apiReset", "" ) ne $1 );
        }

        # Server error
        if ( $param->{code} >= 500 ) {
            $state = "error";
            $values{result} = "Server Error " . $param->{code};
        }

        # error handling
        elsif (
            ( $param->{code} == 200 || $param->{code} >= 400 )
            && (   ( ref($return) eq "HASH" && $return->{status} ne "1" )
                || ( ref($return) ne "HASH" && $return !~ m/"status":1,/ ) )
          )
        {
            $values{result} =
              "Error " . $param->{code} . ": Unspecified error occured";
            if ( ref($return) eq "HASH" && defined $return->{errors} ) {
                $values{result} =
                    "Error "
                  . $param->{code} . ": "
                  . join( ". ", @{ $return->{errors} } );
            }
            elsif ( ref($return) ne "HASH" && $return =~ m/"errors":\[(.*)\]/ )
            {
                $values{result} = "Error " . $param->{code} . ": " . $1;
            }

            $state = "error";

            if ( ref($return) eq "HASH" && defined( $return->{token} ) ) {
                $state = "unauthorized";
                readingsBulkUpdate( $hash, "tokenState", $return->{token} )
                  if (
                    ReadingsVal( $name, "tokenState", "" ) ne $return->{token}
                  );
            }
            elsif ( ref($return) ne "HASH" && $return =~ m/"token":"invalid"/ )
            {
                $state = "unauthorized";
                readingsBulkUpdate( $hash, "tokenState", "invalid" )
                  if ( ReadingsVal( $name, "tokenState", "" ) ne "invalid" );
            }
            else {
                readingsBulkUpdate( $hash, "tokenState", "valid" )
                  if ( ReadingsVal( $name, "tokenState", "" ) ne "valid" );
            }

            if ( ref($return) eq "HASH" && defined( $return->{user} ) ) {

                $state = "unauthorized" if ( !defined( $values->{USER_KEY} ) );
                readingsBulkUpdate( $hash, "userState", $return->{user} )
                  if ( ReadingsVal( $name, "userState", "" ) ne $return->{user}
                    && !defined( $values->{USER_KEY} ) );

                $hash->{helper}{FAILED_USERKEYS}{ $values->{USER_KEY} } =
                    "USERKEY "
                  . $values->{USER_KEY} . " "
                  . $return->{user} . " - "
                  . $values{result}
                  if ( defined( $values->{USER_KEY} ) );

            }
            elsif ( ref($return) ne "HASH" && $return =~ m/"user":"invalid"/ ) {

                $state = "unauthorized" if ( !defined( $values->{USER_KEY} ) );
                readingsBulkUpdate( $hash, "userState", "invalid" )
                  if ( ReadingsVal( $name, "userState", "" ) ne "invalid"
                    && !defined( $values->{USER_KEY} ) );

                $hash->{helper}{FAILED_USERKEYS}{ $values->{USER_KEY} } =
                    "USERKEY "
                  . $values->{USER_KEY}
                  . " invalid - "
                  . $values{result}
                  if ( defined( $values->{USER_KEY} ) );

            }
            else {

                readingsBulkUpdate( $hash, "userState", "valid" )
                  if ( ReadingsVal( $name, "userState", "" ) ne "valid"
                    && !defined( $values->{USER_KEY} ) );

                delete $hash->{helper}{FAILED_USERKEYS}{ $values->{USER_KEY} }
                  if (
                    !defined( $values->{USER_KEY} )
                    && defined(
                        $hash->{helper}{FAILED_USERKEYS}{ $values->{USER_KEY} }
                    )
                  );

            }

        }
        else {
            $state = "limited" if ( $apiRemaining < 1 );

            readingsBulkUpdate( $hash, "tokenState", "valid" )
              if ( ReadingsVal( $name, "tokenState", "" ) ne "valid"
                && !defined( $values->{USER_KEY} ) );
            readingsBulkUpdate( $hash, "userState", "valid" )
              if ( ReadingsVal( $name, "userState", "" ) ne "valid"
                && !defined( $values->{USER_KEY} ) );
        }

        # messages.json
        if ( $service eq "messages.json" ) {

            readingsBulkUpdate( $hash, "lastTitle", $values->{title} );
            readingsBulkUpdate( $hash, "lastMessage",
                urlDecode( $values->{message} ) );
            readingsBulkUpdate( $hash, "lastPriority", $values->{priority} );
            readingsBulkUpdate( $hash, "lastAction",   $values->{action} )
              if ( $values->{action} ne "" );
            readingsBulkUpdate( $hash, "lastAction", "-" )
              if ( $values->{action} eq "" );
            readingsBulkUpdate( $hash, "lastDevice", $values->{device} )
              if ( $values->{device} ne "" );
            readingsBulkUpdate( $hash, "lastDevice",
                ReadingsVal( $name, "devices", "all" ) )
              if ( $values->{device} eq "" );

            if ( ref($return) eq "HASH" ) {

                readingsBulkUpdate( $hash, "lastRequest", $return->{request} )
                  if ( defined $return->{request} );

                if ( $values->{expire} ne "" ) {
                    readingsBulkUpdate( $hash, "cbTitle_" . $values->{cbNr},
                        $values->{title} );
                    readingsBulkUpdate(
                        $hash,
                        "cbMsg_" . $values->{cbNr},
                        urlDecode( $values->{message} )
                    );
                    readingsBulkUpdate( $hash, "cbPrio_" . $values->{cbNr},
                        $values->{priority} );
                    readingsBulkUpdate( $hash, "cbAck_" . $values->{cbNr},
                        "0" );

                    if ( $values->{device} ne "" ) {
                        readingsBulkUpdate( $hash, "cbDev_" . $values->{cbNr},
                            $values->{device} );
                    }
                    else {
                        readingsBulkUpdate(
                            $hash,
                            "cbDev_" . $values->{cbNr},
                            ReadingsVal( $name, "devices", "all" )
                        );
                    }

                    if ( defined $return->{receipt} ) {
                        readingsBulkUpdate( $hash, "cb_" . $values->{cbNr},
                            $return->{receipt} );
                    }
                    else {
                        readingsBulkUpdate( $hash, "cb_" . $values->{cbNr},
                            $values->{cbNr} );
                    }

                    if ( $values->{action} ne "" ) {
                        readingsBulkUpdate( $hash, "cbAct_" . $values->{cbNr},
                            $values->{action} );
                    }
                }
            }

            elsif ( $values{expire} ne "" ) {
                $values{result} =
                  "SoftFail: Callback not supported. Please install Perl::JSON";
            }
        }

        # users/validate.json
        elsif ( $service eq "users/validate.json" ) {
            if ( ref($return) eq "HASH" ) {
                my $devices = "-";
                my $group   = "0";
                $devices = join( ",", @{ $return->{devices} } )
                  if ( defined( $return->{devices} ) );
                $group = $return->{group} if ( defined( $return->{group} ) );

                readingsBulkUpdate( $hash, "devices", $devices )
                  if ( ReadingsVal( $name, "devices", "" ) ne $devices );
                readingsBulkUpdate( $hash, "group", $group )
                  if ( ReadingsVal( $name, "group", "" ) ne $group );
            }
        }

        readingsBulkUpdate( $hash, "lastResult", $values{result} );
    }

    # Set reading for availability
    #
    my $available = 0;
    $available = 1
      if ( $param->{code} ne "429"
        && ( $state eq "connected" || $state eq "error" ) );
    readingsBulkUpdate( $hash, "available", $available )
      if ( ReadingsVal( $name, "available", "" ) ne $available );

    # Set reading for state
    #
    readingsBulkUpdate( $hash, "state", $state )
      if ( ReadingsVal( $name, "state", "" ) ne $state );

    # credentials validation loop
    #
    my $nextTimer = "none";

    # if we could not connect, try again in 5 minutes
    if ( $state eq "disconnected" ) {
        $nextTimer = gettimeofday() + 300;

    }

    # re-validate every 6 hours if there was no message sent during
    # that time
    elsif ( $available eq "1" ) {
        $nextTimer = gettimeofday() + 21600;

    }

    # re-validate after API limit was reset
    elsif ( $state eq "limited" || $param->{code} == 429 ) {
        $nextTimer =
          ReadingsVal( $name, "apiReset", gettimeofday() + 21277 ) + 323;
    }
    RemoveInternalTimer($hash);
    $hash->{VALIDATION_TIMER} = $nextTimer;
    InternalTimer( $nextTimer, "Pushover_ValidateUser", $hash, 0 )
      if ( $nextTimer ne "none" );

    readingsEndUpdate( $hash, 1 );

    return;
}

#------------------------------------------------------------------------------
sub Pushover_ValidateUser ($;$) {
    my ( $hash, $update ) = @_;
    my $name = $hash->{NAME};
    my $device = AttrVal( $name, "device", "" );

    Log3 $name, 5, "Pushover $name: called function Pushover_ValidateUser()";

    RemoveInternalTimer($hash);

    if ( AttrVal( $name, "disable", 0 ) == 1 ) {
        $hash->{VALIDATION_TIMER} = "disabled";
        RemoveInternalTimer($hash);
        InternalTimer( gettimeofday() + 900, "Pushover_ValidateUser", $hash,
            0 );
        return;
    }

    elsif ( $device ne "" ) {
        Pushover_SendCommand( $hash, "users/validate.json", "device=$device" );
    }

    else {
        Pushover_SendCommand( $hash, "users/validate.json" );
    }

    return;
}

#------------------------------------------------------------------------------
sub Pushover_SetMessage {
    my $hash   = shift;
    my $name   = $hash->{NAME};
    my %values = ();

    #Set defaults
    $values{title}     = AttrVal( $hash->{NAME}, "title", "" );
    $values{message}   = "";
    $values{device}    = AttrVal( $hash->{NAME}, "device", "" );
    $values{priority}  = AttrVal( $hash->{NAME}, "priority", 0 );
    $values{sound}     = AttrVal( $hash->{NAME}, "sound", "" );
    $values{retry}     = "";
    $values{expire}    = "";
    $values{url_title} = "";
    $values{action}    = "";

    my $callback = (
        defined( $attr{$name}{callbackUrl} )
          && defined( $hash->{fhem}{infix} )
        ? $attr{$name}{callbackUrl}
        : ""
    );

    #Split parameters
    my $param = join( " ", @_ );
    my $argc = 0;
    if ( $param =~
/(".*"|'.*')\s*(".*"|'.*')\s*(".*"|'.*')\s*(-?\d+)\s*(".*"|'.*')\s*(\d+)\s*(\d+)\s*(".*"|'.*')\s*(".*"|'.*')\s*$/s
      )
    {
        $argc = 9;
    }
    elsif ( $param =~
/(".*"|'.*')\s*(".*"|'.*')\s*(".*"|'.*')\s*(-?\d+)\s*(".*"|'.*')\s*(\d+)\s*(\d+)\s*$/s
      )
    {
        $argc = 7;
    }
    elsif ( $param =~
        /(".*"|'.*')\s*(".*"|'.*')\s*(".*"|'.*')\s*(-?\d+)\s*(".*"|'.*')\s*$/s )
    {
        $argc = 5;
    }
    elsif ( $param =~ /(".*"|'.*')\s*(".*"|'.*')\s*$/s ) {
        $argc = 2;
    }
    elsif ( $param =~ /(".*"|'.*')\s*$/s ) {
        $argc = 1;
    }

    Log3 $name, 4, "Pushover $name: Found $argc argument(s)";

    if ( $argc > 1 ) {
        $values{title}   = $1;
        $values{message} = $2;
        Log3 $name, 4,
          "Pushover $name:		title=$values{title} message=$values{message}";

        if ( $argc > 2 ) {
            $values{device}   = $3;
            $values{priority} = $4;
            $values{sound}    = $5;
            Log3 $name, 4,
"Pushover $name:		device=$values{device} priority=$values{priority} sound=$values{sound}";

            if ( $argc > 5 ) {
                $values{retry}  = $6;
                $values{expire} = $7;
                Log3 $name, 4,
"Pushover $name:		retry=$values{retry} expire=$values{expire}";

                if ( $argc > 7 ) {
                    $values{url_title} = $8;
                    $values{action}    = $9;
                    Log3 $name, 4,
"Pushover $name:		url_title=$values{url_title} action=$values{action}";
                }
            }
        }
    }
    elsif ( $argc == 1 ) {
        $values{message} = $1;
        Log3 $name, 4, "Pushover $name:		message=$values{message}";
    }

    #Remove quotation marks
    if ( $values{title} =~ /^['"](.*)['"]$/s ) {
        $values{title} = $1;
    }
    if ( $values{message} =~ /^['"](.*)['"]$/s ) {
        $values{message} = $1;
    }
    if ( $values{device} =~ /^['"](.*)['"]$/s ) {
        $values{device} = $1;
    }
    if ( $values{priority} =~ /^['"](.*)['"]$/s ) {
        $values{priority} = $1;
    }
    if ( $values{sound} =~ /^['"](.*)['"]$/s ) {
        $values{sound} = $1;
    }
    if ( $values{retry} =~ /^['"](.*)['"]$/s ) {
        $values{retry} = $1;
    }
    if ( $values{expire} =~ /^['"](.*)['"]$/s ) {
        $values{expire} = $1;
    }
    if ( $values{url_title} =~ /^['"](.*)['"]$/s ) {
        $values{url_title} = $1;
    }
    if ( $values{action} =~ /^['"](.*)['"]$/s ) {
        $values{action} = $1;
    }

    # check if we got a user or group key as device and use it as
    # user-key instead of hash->USER_KEY
    if ( $values{device} =~ /^([A-Za-z0-9]{30})(:([A-Za-z0-9_-]+))?$/s ) {
        $values{USER_KEY} = $1;
        $values{device}   = $3;

        return $hash->{helper}{FAILED_USERKEYS}{ $values{USER_KEY} }
          if (
            defined( $hash->{helper}{FAILED_USERKEYS}{ $values{USER_KEY} } ) );
    }

    # Check if all mandatory arguments are filled:
    # "message" can not be empty and if "priority" is set to "2" "retry" and
    # "expire" must also be set.
    # "url_title" and "action" need to be set together and require "expire"
    # to be set as well.
    if (
        $values{message} ne ""
        && ( ( $values{retry} ne "" && $values{expire} ne "" )
            || $values{priority} < 2 )
        && (
            (
                   $values{url_title} ne ""
                && $values{action} ne ""
                && $values{expire} ne ""
            )
            || ( $values{url_title} eq "" && $values{action} eq "" )
        )
      )
    {
        my $body;
        $body = "title=" . urlEncode( $values{title} )
          if ( $values{title} ne "" );

        if ( $values{message} =~
            /\<(\/|)[biu]\>|\<(\/|)font(.+)\>|\<(\/|)a(.*)\>|\<br\s?\/?\>/
            && $values{message} !~ /^nohtml:.*/ )
        {
            Log3 $name, 4, "Pushover $name: handling message with HTML content";
            $body = $body . "&html=1";

            # replace \n by <br /> but ignore \\n
            $values{message} =~ s/(?<!\\)(\\n)/<br \/>/g;
        }

        elsif ( $values{message} =~ /^nohtml:.*/ ) {
            Log3 $name, 4,
              "Pushover $name: explicitly ignoring HTML tags in message";
            $values{message} =~ s/^(nohtml:).*//;
        }

        # HttpUtil's urlEncode() does not handle \n but would escape %
        # so we encode first
        $values{message} = urlEncode( $values{message} );

        # replace any URL-encoded \n with their hex equivalent but ignore \\n
        $values{message} =~ s/(?<!%5c)(%5cn)/%0a/g;

        # replace any URL-encoded \\n by \n
        $values{message} =~ s/%5c%5cn/%5cn/g;

        $body = $body . "&message=" . $values{message};

        if ( $values{device} ne "" ) {
            $body = $body . "&device=" . $values{device};
        }

        if ( $values{priority} ne "" ) {
            $values{priority} = 2  if ( $values{priority} > 2 );
            $values{priority} = -2 if ( $values{priority} < -2 );
            $body = $body . "&priority=" . $values{priority};
        }

        if ( $values{sound} ne "" ) {
            $body = $body . "&sound=" . $values{sound};
        }

        if ( $values{retry} ne "" ) {
            $body = $body . "&retry=" . $values{retry};
        }

        if ( $values{expire} ne "" ) {
            $body = $body . "&expire=" . $values{expire};

            $values{cbNr} = int( time() ) + $values{expire};
            my $cbReading = "cb_" . $values{cbNr};
            until ( ReadingsVal( $name, $cbReading, "" ) eq "" ) {
                $values{cbNr}++;
                $cbReading = "cb_" . $values{cbNr};
            }
        }

        if ( 1 == AttrVal( $hash->{NAME}, "timestamp", 0 ) ) {
            $body = $body . "&timestamp=" . int( time() );
        }

        if ( $callback ne "" && $values{priority} > 1 ) {
            Log3 $name, 5,
              "Pushover $name: Adding emergency callback URL $callback";
            $body = $body . "&callback=" . $callback;
        }

        if (   $values{url_title} ne ""
            && $values{action} ne ""
            && $values{expire} ne "" )
        {
            my $url;

            if (
                $callback eq ""
                || (   $values{action} !~ /^http[s]?:\/\/.*$/
                    && $values{action} =~ /^[\w-]+:\/\/.*$/ )
              )
            {
                $url = $values{action};
                $values{expire} = "";
            }
            else {
                $url =
                    $callback
                  . "?acknowledged=1&acknowledged_by="
                  . $hash->{USER_KEY}
                  . "&FhemCallbackId="
                  . $values{cbNr};
            }

            Log3 $name, 5,
"Pushover $name: Adding supplementary URL '$values{url_title}' ($url) with "
              . "action '$values{action}' (expires after $values{expire} => "
              . "$values{cbNr})";
            $body =
                $body
              . "&url_title="
              . urlEncode( $values{url_title} ) . "&url="
              . urlEncode($url);
        }

        # cleanup callback readings
        my $revReadings;
        while ( ( $key, $value ) = each %{ $hash->{READINGS} } ) {
            if ( $key =~ /^cb_\d+$/ ) {
                my @rBase  = split( "_", $key );
                my $rTit   = "cbTitle_" . $rBase[1];
                my $rMsg   = "cbMsg_" . $rBase[1];
                my $rPrio  = "cbPrio_" . $rBase[1];
                my $rAct   = "cbAct_" . $rBase[1];
                my $rAck   = "cbAck_" . $rBase[1];
                my $rAckAt = "cbAckAt_" . $rBase[1];
                my $rAckBy = "cbAckBy_" . $rBase[1];
                my $rDev   = "cbDev_" . $rBase[1];

                Log3 $name, 5,
                    "Pushover $name: checking to clean up "
                  . $hash->{NAME}
                  . " $key: time="
                  . $rBase[1] . " ack="
                  . ReadingsVal( $name, $rAck, "-" )
                  . " curTime="
                  . int( time() );

                if ( ReadingsVal( $name, $rAck, 0 ) == 1
                    || $rBase[1] <= int( time() ) )
                {
                    delete $hash->{READINGS}{$key};
                    delete $hash->{READINGS}{$rTit};
                    delete $hash->{READINGS}{$rMsg};
                    delete $hash->{READINGS}{$rPrio};
                    delete $hash->{READINGS}{$rAck};
                    delete $hash->{READINGS}{$rDev};

                    if ( defined( $hash->{READINGS}{$rAct} ) ) {
                        delete $hash->{READINGS}{$rAct};
                    }
                    if ( defined( $hash->{READINGS}{$rAckAt} ) ) {
                        delete $hash->{READINGS}{$rAckAt};
                    }
                    if ( defined( $hash->{READINGS}{$rAckBy} ) ) {
                        delete $hash->{READINGS}{$rAckBy};
                    }

                    Log3 $name, 4,
                      "Pushover $name: cleaned up expired receipt " . $rBase[1];
                }
            }
        }

        Pushover_SendCommand( $hash, "messages.json", $body, %values );

        return;
    }
    else {

        # There was a problem with the arguments, so tell the user the
        # correct usage of the 'set msg' command
        if ( 1 == $argc && $values{title} eq "" ) {
            return
"Please define the default title in the pushover device arguments.";
        }
        else {
            return
"Syntax: $name msg ['<title>'] '<msg>' ['<device>' <priority> '<sound>' "
              . "[<retry> <expire> ['<url_title>' '<action>']]]";
        }
    }
}

#------------------------------------------------------------------------------
sub Pushover_CGI() {
    my ($request) = @_;

    my $hash;
    my $name = "";
    my $link = "";
    my $URI  = "";

    # data received
    if ( $request =~ m,^(/[^/]+?)(?:\&|\?)(.*)?$, ) {
        $link = $1;
        $URI  = $2;

        # get device name
        $name = $data{FWEXT}{$link}{deviceName} if ( $data{FWEXT}{$link} );
        $hash = $defs{$name};

        # return error if no such device
        return ( "text/plain; charset=utf-8",
            "NOK No Pushover device for callback $link" )
          unless ($name);

        Log3 $name, 4, "Pushover $name callback: link='$link' URI='$URI'";

        my $webArgs;
        my $receipt = "";
        my $revReadings;

        # extract values from URI
        foreach my $pv ( split( "&", $URI ) ) {
            next if ( $pv eq "" );
            $pv =~ s/\+/ /g;
            $pv =~ s/%([\dA-F][\dA-F])/chr(hex($1))/ige;
            my ( $p, $v ) = split( "=", $pv, 2 );

            $webArgs->{$p} = $v;
        }

        if ( defined( $webArgs->{receipt} ) ) {
            $receipt = $webArgs->{receipt};
        }
        elsif ( defined( $webArgs->{FhemCallbackId} ) ) {
            $receipt = $webArgs->{FhemCallbackId};
        }
        else {
            return ( "text/plain; charset=utf-8",
                "NOK missing argument receipt or FhemCallbackId" );
        }

        # search for existing receipt
        while ( ( $key, $value ) = each %{ $hash->{READINGS} } ) {
            if ( $key =~ /^cb_\d+$/ ) {
                my $val = $value->{VAL};
                $revReadings{$val} = $key;
            }
        }

        if ( defined( $revReadings{$receipt} ) ) {
            my $r      = $revReadings{$receipt};
            my @rBase  = split( "_", $r );
            my $rAct   = "cbAct_" . $rBase[1];
            my $rAck   = "cbAck_" . $rBase[1];
            my $rAckAt = "cbAckAt_" . $rBase[1];
            my $rAckBy = "cbAckBy_" . $rBase[1];
            my $rDev   = "cbDev_" . $rBase[1];

            return ( "text/plain; charset=utf-8",
                "NOK " . $receipt . ": invalid argument 'acknowledged'" )
              if ( !defined( $webArgs->{acknowledged} )
                || $webArgs->{acknowledged} ne "1" );

            return ( "text/plain; charset=utf-8",
                "NOK " . $receipt . ": invalid argument 'acknowledged_by'" )
              if ( !defined( $webArgs->{acknowledged_by} )
                || $webArgs->{acknowledged_by} ne $hash->{USER_KEY} );

            if ( ReadingsVal( $name, $rAck, 1 ) == 0
                && $rBase[1] > int( time() ) )
            {
                readingsBeginUpdate($hash);

                readingsBulkUpdate( $hash, $rAck, "1" );
                readingsBulkUpdate( $hash, $rAckBy,
                    $webArgs->{acknowledged_by} );

                if ( defined( $webArgs->{acknowledged_at} )
                    && $webArgs->{acknowledged_at} ne "" )
                {
                    readingsBulkUpdate( $hash, $rAckAt,
                        $webArgs->{acknowledged_at} );
                }
                else {
                    readingsBulkUpdate( $hash, $rAckAt, int( time() ) );
                }

                my $redirect = "";

                # run FHEM command if desired
                if ( ReadingsVal( $name, $rAct, "pushover://" ) !~
                    /^[\w-]+:\/\/.*$/ )
                {
                    $redirect = "pushover://";

                    fhem ReadingsVal( $name, $rAct, "" );
                    readingsBulkUpdate( $hash, $rAct,
                        "executed: " . ReadingsVal( $name, $rAct, "" ) );
                }

                # redirect to presented URL
                if ( ReadingsVal( $name, $rAct, "none" ) =~ /^[\w-]+:\/\/.*$/ )
                {
                    $redirect = ReadingsVal( $name, $rAct, "" );
                }

                readingsEndUpdate( $hash, 1 );

                return (
                    "text/html; charset=utf-8",
                    "<html><head><meta http-equiv=\"refresh\" content=\"0;url="
                      . $redirect
                      . "\"></head><body><a href=\""
                      . $redirect
                      . "\">Click here to get redirected to your destination"
                      . "</a></body></html>"
                ) if ( $redirect ne "" );

            }
            else {
                Log3 $name, 4,
                  "Pushover $name callback: " . $receipt . " has expired";
                return (
                    "text/plain; charset=utf-8",
                    "NOK " . $receipt . " has expired"
                );
            }

        }
        else {
            Log3 $name, 4,
              "Pushover $name callback: unable to find existing receipt "
              . $receipt;
            return ( "text/plain; charset=utf-8",
                "NOK unable to find existing receipt " . $receipt );
        }

    }

    # no data received
    else {
        Log3 $name, 5,
          "Pushover $name callback: received malformed request\n$request";
        return ( "text/plain; charset=utf-8", "NOK malformed request" );
    }

    return ( "text/plain; charset=utf-8", "OK" );
}

1;

###############################################################################

=pod
=item device
=begin html

<a name="Pushover"></a>
<h3>Pushover</h3>
<ul>
  Pushover is a service to receive instant push notifications on your
  phone or tablet from a variety of sources.<br>
  You need an account to use this module.<br>
  For further information about the service see <a href="https://pushover.net">pushover.net</a>.<br>
  <br>
  Installation of Perl module IO::Socket::SSL is mandatory to use this module (i.e. via 'cpan -i IO::Socket::SSL').<br>
  It is recommended to install Perl-JSON to make use of advanced functions like supplementary URLs.<br>
  <br>
  Discuss the module <a href="http://forum.fhem.de/index.php/topic,16215.0.html">here</a>.<br>
  <br>
  <br>
  <a name="PushoverDefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Pushover &lt;token&gt; &lt;user&gt; [&lt;infix&gt;]</code><br>
    <br>
    You have to create an account to get the user key.<br>
    And you have to create an application to get the API token.<br>
    <br>
    Attribute infix is optional to define FHEMWEB uri name for Pushover API callback function.<br>
    Callback URL may be set using attribute callbackUrl (see below).<br>
    Note: A uri name can only be used once within each FHEM instance!<br>
    <br>
    Example:
    <ul>
      <code>define Pushover1 Pushover 01234 56789</code>
    </ul>
    <ul>
      <code>define Pushover1 Pushover 01234 56789 pushCallback1</code>
    </ul>
  </ul>
  <br>
  <a name="PushoverSet"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;Pushover_device&gt; msg [title] &lt;msg&gt; [&lt;device&gt; &lt;priority&gt; &lt;sound&gt; [&lt;retry&gt; &lt;expire&gt; [&lt;url_title&gt; &lt;action&gt;]]]</code>
    <br>
    <br>
    Examples:
    <ul>
      <code>set Pushover1 msg 'This is a text.'</code><br>
      <code>set Pushover1 msg 'Title' 'This is a text.'</code><br>
      <code>set Pushover1 msg 'Title' 'This is a text.' '' 0 ''</code><br>
      <code>set Pushover1 msg 'Emergency' 'Security issue in living room.' '' 2 'siren' 30 3600</code><br>
      <code>set Pushover1 msg 'Hint' 'This is a reminder to do something' '' 0 '' 0 3600 'Click here for action' 'set device something'</code><br>
      <code>set Pushover1 msg 'Emergency' 'Security issue in living room.' '' 2 'siren' 30 3600 'Click here for action' 'set device something'</code><br>
    </ul>
    <br>
    Notes:
    <ul>
      <li>For the first and the second example the corresponding default attributes for the missing arguments must be defined for the device (see attributes section)
      </li>
      <li>If device is empty, the message will be sent to all devices.
      </li>
      <li>If device has a User or Group Key, the message will be sent to this recipient instead. Should you wish to address a specific device here, add it at the end separated by colon.
      </li>
      <li>If sound is empty, the default setting in the app will be used.
      </li>
      <li>If priority is higher or equal 2, retry and expire must be defined.
      </li>
      <li>For further documentation of these parameters have a look at the <a href="https://pushover.net/api">Pushover API</a>.
      </li>
    </ul>
  </ul>
  <br>
  <b>Get</b> <ul>N/A</ul><br>
  <a name="PushoverAttr"></a>
  <b>Attributes</b>
  <ul>
    <a name="callbackUrl"></a>
    <li>callbackUrl<br>
        Set the callback URL to be used to acknowledge messages with emergency priority or supplementary URLs.
    </li><br>
    <a name="timestamp"></a>
    <li>timestamp<br>
        Send the unix timestamp with each message.
    </li><br>
    <a name="title"></a>
    <li>title<br>
        Will be used as title if title is not specified as an argument.
    </li><br>
    <a name="device"></a>
    <li>device<br>
        Will be used for the device name if device is not specified as an argument. If left blank, the message will be sent to all devices.
    </li><br>
    <a name="priority"></a>
    <li>priority<br>
        Will be used as priority value if priority is not specified as an argument. Valid values are -1 = silent / 0 = normal priority / 1 = high priority
    </li><br>
    <a name="sound"></a>
    <li>sound<br>
        Will be used as the default sound if sound argument is missing. If left blank the adjusted sound of the app will be used. 
    </li><br>
  </ul>
  <br>
  <a name="PushoverEvents"></a>
  <b>Generated events:</b>
  <ul>
     N/A
  </ul>
</ul>

=end html
=begin html_DE

<a name="Pushover"></a>
<h3>Pushover</h3>
<ul>
  Pushover ist ein Dienst, um Benachrichtigungen von einer vielzahl
  von Quellen auf Deinem Smartphone oder Tablet zu empfangen.<br>
  Du brauchst einen Account um dieses Modul zu verwenden.<br>
  Für weitere Informationen über den Dienst besuche <a href="https://pushover.net">pushover.net</a>.<br>
  <br>
  Die Installation des Perl Moduls IO::Socket::SSL ist Voraussetzung zur Nutzung dieses Moduls (z.B. via 'cpan -i IO::Socket::SSL').<br>
  Es wird empfohlen Perl-JSON zu installieren, um erweiterte Funktion wie Supplementary URLs nutzen zu können.<br>
  <br>
  Diskutiere das Modul <a href="http://forum.fhem.de/index.php/topic,16215.0.html">hier</a>.<br>
  <br>
  <br>
  <a name="PushoverDefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Pushover &lt;token&gt; &lt;user&gt; [&lt;infix&gt;]</code><br>
    <br>
    Du musst einen Account erstellen, um den User Key zu bekommen.<br>
    Und du musst eine Anwendung erstellen, um einen API APP_TOKEN zu bekommen.<br>
    <br>
    Das Attribut infix ist optional, um einen FHEMWEB uri Namen für die Pushover API Callback Funktion zu definieren.<br>
    Die Callback URL Callback URL kann dann mit dem Attribut callbackUrl gesetzt werden (siehe unten).<br>
    Hinweis: Eine infix uri can innerhalb einer FHEM Instanz nur einmal verwendet werden!<br>
    <br>
    Beispiel:
    <ul>
      <code>define Pushover1 Pushover 01234 56789</code>
    </ul>
    <ul>
      <code>define Pushover1 Pushover 01234 56789 pushCallback1</code>
    </ul>
  </ul>
  <br>
  <a name="PushoverSet"></a>
  <b>Set</b>
  <ul>
	<code>set &lt;Pushover_device&gt; msg [title] &lt;msg&gt; [&lt;device&gt; &lt;priority&gt; &lt;sound&gt; [&lt;retry&gt; &lt;expire&gt; [&lt;url_title&gt; &lt;action&gt;]]]</code>
    <br>
    <br>
    Beispiele:
    <ul>
      <code>set Pushover1 msg 'Dies ist ein Text.'</code><br>
      <code>set Pushover1 msg 'Titel' 'Dies ist ein Text.'</code><br>
      <code>set Pushover1 msg 'Titel' 'Dies ist ein Text.' '' 0 ''</code><br>
      <code>set Pushover1 msg 'Notfall' 'Sicherheitsproblem im Wohnzimmer.' '' 2 'siren' 30 3600</code><br>
      <code>set Pushover1 msg 'Erinnerung' 'Dies ist eine Erinnerung an etwas' '' 0 '' 0 3600 'Hier klicken, um Aktion auszuführen' 'set device irgendwas'</code><br>
      <code>set Pushover1 msg 'Notfall' 'Sicherheitsproblem im Wohnzimmer.' '' 2 'siren' 30 3600 'Hier klicken, um Aktion auszuführen' 'set device something'</code><br>
    </ul>
    <br>
    Anmerkungen:
    <ul>
      <li>Bei der Verwendung der ersten beiden Beispiele müssen die entsprechenden Attribute als Ersatz für die fehlenden Parameter belegt sein (s. Attribute)
      </li>
      <li>Wenn device leer ist, wird die Nachricht an alle Geräte geschickt.
      </li>
      <li>Wenn device ein User oder Group Key ist, wird die Nachricht stattdessen hierhin verschickt. Möchte man trotzdem ein dediziertes Device angeben, trennt man den Namen mit einem Doppelpunkt ab.
      </li>
      <li>Wenn sound leer ist, dann wird die Standardeinstellung in der App verwendet.
      </li>
      <li>Wenn die Priorität höher oder gleich 2 ist müssen retry und expire definiert sein.
      </li>
      <li>Für weiterführende Dokumentation über diese Parameter lies Dir die <a href="https://pushover.net/api">Pushover API</a> durch.
      </li>
    </ul>
  </ul>
  <br>
  <b>Get</b> <ul>N/A</ul><br>
  <a name="PushoverAttr"></a>
  <b>Attributes</b>
  <ul>
    <a name="callbackUrl"></a>
    <li>callbackUrl<br>
        Setzt die Callback URL, um Nachrichten mit Emergency Priorität zu bestätigen.
    </li><br>
    <a name="timestamp"></a>
    <li>timestamp<br>
        Sende den Unix-Zeitstempel mit jeder Nachricht.
    </li><br>
    <a name="title"></a>
    <li>title<br>
        Wird beim Senden als Titel verwendet, sofern dieser nicht als Aufrufargument angegeben wurde.
    </li><br>
    <a name="device"></a>
    <li>device<br>
        Wird beim Senden als Gerätename verwendet, sofern dieser nicht als Aufrufargument angegeben wurde. Kann auch generell entfallen, bzw. leer sein, dann wird an alle Geräte gesendet.
    </li><br>
    <a name="priority"></a>
    <li>priority<br>
        Wird beim Senden als Priorität verwendet, sofern diese nicht als Aufrufargument angegeben wurde. Zulässige Werte sind -1 = leise / 0 = normale Priorität / 1 = hohe Priorität
    </li><br>
    <a name="sound"></a>
    <li>sound<br>
        Wird beim Senden als Titel verwendet, sofern dieser nicht als Aufrufargument angegeben wurde. Kann auch generell entfallen, dann wird der eingestellte Ton der App verwendet.
    </li><br>
  </ul>
  <br>
  <a name="PushoverEvents"></a>
  <b>Generated events:</b>
  <ul>
     N/A
  </ul>
</ul>

=end html_DE
=cut
