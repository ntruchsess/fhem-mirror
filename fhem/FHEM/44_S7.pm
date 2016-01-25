# $Id$
####################################################

package main;

use strict;
use warnings;
#use Devel::NYTProf; #profiler


require "44_S7_Client.pm";

my %gets = (
	"S7TCPClientVersion" => "",
	"PLCTime"            => ""
);

my @areasconfig = (
	"ReadInputs-Config",  "ReadOutputs-Config",
	"ReadFlags-Config",   "ReadDB-Config",
	"WriteInputs-Config", "WriteOutputs-Config",
	"WriteFlags-Config",  "WriteDB-Config"
);
my @s7areas = (
	&S7Client::S7AreaPE, &S7Client::S7AreaPA, &S7Client::S7AreaMK,
	&S7Client::S7AreaDB, &S7Client::S7AreaPE, &S7Client::S7AreaPA,
	&S7Client::S7AreaMK, &S7Client::S7AreaDB
);
my @areaname =
  ( "inputs", "outputs", "flags", "db", "inputs", "outputs", "flags", "db" );

#####################################
sub S7_Initialize($) {
	my $hash = shift @_;

	# Provider
	$hash->{Clients} = ":S7_DRead:S7_ARead:S7_AWrite:S7_DWrite:";
	my %matchList = (
		"1:S7_DRead"  => "^DR",
		"2:S7_DWrite" => "^DW",
		"3:S7_ARead"  => "^AR",
		"4:S7_AWrite" => "^AW"
	);

	$hash->{MatchList} = \%matchList;

	# Consumer
	$hash->{DefFn}    = "S7_Define";
	$hash->{UndefFn}  = "S7_Undef";
	$hash->{GetFn}    = "S7_Get";
	$hash->{AttrFn}   = "S7_Attr";
	$hash->{AttrList} = "MaxMessageLength " . $readingFnAttributes;

	#	$hash->{AttrList} = join( " ", @areasconfig )." PLCTime";
}

#####################################
sub S7_connect($) {
	my $hash = shift @_;

	my $name = $hash->{NAME};

	if ( $hash->{STATE} eq "connected to PLC" ) {
		Log3 $name, 2, "$name S7_connect: allready connected!";
		return;
	}

	Log3 $name, 4,
	    "S7: $name connect ip_address="
	  . $hash->{ipAddress}
	  . ", LocalTSAP="
	  . $hash->{LocalTSAP}
	  . ", RemoteTSAP="
	  . $hash->{RemoteTSAP} . " ";


	if ( !defined( $hash->{S7TCPClient} ) ) {
		S7_reconnect($hash);
		return;
	}


	$hash->{STATE} = "disconnected";
	main::readingsSingleUpdate( $hash, "state", "disconnected", 1 );

	$hash->{S7TCPClient}
	  ->SetConnectionParams( $hash->{ipAddress}, $hash->{LocalTSAP},
		$hash->{RemoteTSAP} );

	my $res;
	eval {
		local $SIG{__DIE__} = sub {
			my ($s) = @_;
			Log3 $hash, 0, "S7_connect: $s";
			$res = -1;
		};
		$res = $hash->{S7TCPClient}->Connect();
	};

	if ($res) {
		Log3 $name, 2, "S7_connect: $name Could not connect to PLC ($res)";
		return;
	}

	my $PDUlength = $hash->{S7TCPClient}->{PDULength};
	$hash->{maxPDUlength} = $PDUlength;

	Log3 $name, 3,
	  "$name S7_connect: connect to PLC with maxPDUlength=$PDUlength";

	$hash->{STATE} = "connected to PLC";
	main::readingsSingleUpdate( $hash, "state", "connected to PLC", 1 );


	return undef;

}

#####################################
sub S7_disconnect($) {
	my $hash = shift @_;
	my ( $ph, $res, $di);
	my $name  = $hash->{NAME};
	my $error = "";

	$hash->{S7TCPClient}->Disconnect() if ( defined( $hash->{S7TCPClient} ) );
	$hash->{S7TCPClient} = undef;    #TCP Client freigeben

	$hash->{STATE} = "disconnected";
	main::readingsSingleUpdate( $hash, "state", "disconnected", 1 );

	Log3 $name, 2, "$name S7 disconnected";

}

#####################################
sub S7_reconnect($) {
	my $hash = shift @_;
	S7_disconnect($hash) if ( defined( $hash->{S7TCPClient} ) );

	$hash->{S7TCPClient} = S7Client->new();
	InternalTimer( gettimeofday() + 3, "S7_connect", $hash, 1 )
	  ;    #wait 3 seconds for reconnect
}

#####################################
sub S7_Define($$) {
	my ( $hash, $def ) = @_;
	my @a = split( "[ \t][ \t]*", $def );

	my ( $name, $ip_address, $LocalTSAP, $RemoteTSAP, $res, $PDUlength, $rack,
		$slot );

	$name = $a[0];

	if ( uc $a[2] eq "LOGO7" || uc $a[2] eq "LOGO8" ) {
		$ip_address       = $a[3];
		$LocalTSAP        = 0x0100;
		$RemoteTSAP       = 0x0200;
		$hash->{Interval} = 1;
		if ( uc $a[2] eq "LOGO7" ) {
			$hash->{S7TYPE} = "LOGO7";
		}
		else {
			$hash->{S7TYPE} = "LOGO8";
		}
		$PDUlength = 240;

	}
	else {

		$ip_address = $a[2];

		$rack = int( $a[3] );
		return "invalid rack parameter (0 - 15)"
		  if ( $rack < 0 || $rack > 15 );

		$slot = int( $a[4] );
		return "invalid slot parameter (0 - 15)"
		  if ( $slot < 0 || $slot > 15 );

		$hash->{Interval} = 1;
		if ( int(@a) == 6 ) {
			$hash->{Interval} = int( $a[5] );
			return "invalid intervall parameter (1 - 86400)"
			  if ( $hash->{Interval} < 1 || $hash->{Interval} > 86400 );
		}
		$LocalTSAP = 0x0100;
		$RemoteTSAP = ( &S7Client::S7_PG << 8 ) + ( $rack * 0x20 ) + $slot;

		$PDUlength = 0x3c0;

		$hash->{S7TYPE} = "NATIVE";
	}

	$hash->{ipAddress}          = $ip_address;
	$hash->{LocalTSAP}          = $LocalTSAP;
	$hash->{RemoteTSAP}         = $RemoteTSAP;
	$hash->{maxPDUlength}       = $PDUlength;    #initial PDU length

	Log3 $name, 4,
"S7: define $name ip_address=$ip_address,LocalTSAP=$LocalTSAP, RemoteTSAP=$RemoteTSAP ";

	$hash->{STATE} = "disconnected";
	main::readingsSingleUpdate( $hash, "state", "disconnected", 1 );

	S7_connect($hash);

	InternalTimer( gettimeofday() + $hash->{Interval},
		"S7_GetUpdate", $hash, 0 );

	return undef;
}

#####################################
sub S7_Undef($) {
	my $hash = shift;

	RemoveInternalTimer($hash);

	S7_disconnect($hash);

	delete( $modules{S7}{defptr} );

	return undef;
}

#####################################
sub S7_Get($@) {
	my ( $hash, @a ) = @_;
	return "Need at least one parameters" if ( @a < 2 );
	return "Unknown argument $a[1], choose one of "
	  . join( " ", sort keys %gets )
	  if ( !defined( $gets{ $a[1] } ) );
	my $name = shift @a;
	my $cmd  = shift @a;

  ARGUMENT_HANDLER: {
		$cmd eq "S7TCPClientVersion" and do {

			return $hash->{S7TCPClient}->version();
			last;
		};
		$cmd eq "PLCTime" and do {
			return $hash->{S7TCPClient}->getPLCDateTime();
			last;
		};
	}

}

#####################################
sub S7_Attr(@) {
	my ( $cmd, $name, $aName, $aVal ) = @_;

	my $hash = $defs{$name};

	# $cmd can be "del" or "set"
	# $name is device name
	# aName and aVal are Attribute name and value

	if ( $cmd eq "set" ) {
		if ( $aName eq "MaxMessageLength" ) {

			if ( $aVal < $hash->{S7TCPClient}->{MaxReadLength} ) {

				$hash->{S7TCPClient}->{MaxReadLength} = $aVal;

				Log3 $name, 3, "$name S7_Attr: setting MaxReadLength= $aVal";
			}
		}
		###########

		if (   $aName eq "WriteInputs-Config"
			|| $aName eq "WriteOutputs-Config"
			|| $aName eq "WriteFlags-Config"
			|| $aName eq "WriteDB-Config" )
		{
			my $PDUlength = $hash->{maxPDUlength};
			
			my @a = split( "[ \t][ \t]*", $aVal );
			if ( int(@a) % 3 != 0 || int(@a) == 0 ) {
				Log3 $name, 3,
				  "S7: Invalid $aName in attr $name $aName $aVal: $@";
				return
"Invalid $aName $aVal \n Format: <DB> <STARTPOSITION> <LENGTH> [<DB> <STARTPOSITION> <LENGTH> ]";
			}
			else {

				for ( my $i = 0 ; $i < int(@a) ; $i++ ) {
					if ( $a[$i] ne int( $a[$i] ) ) {
						my $s = $a[$i];
						Log3 $name, 3,
"S7: Invalid $aName in attr $name $aName $aVal ($s is not a number): $@";
						return "Invalid $aName $aVal: $s is not a number";
					}
					if ( $i % 3 == 0 && ( $a[$i] < 0 || $a[$i] > 1024 ) ) {
						Log3 $name, 3,
						  "S7: Invalid $aName db. valid db 0 - 1024: $@";
						return
						  "Invalid $aName length: $aVal db: valid db 0 - 1024";

					}
					if ( $i % 3 == 1 && ( $a[$i] < 0 || $a[$i] > 32768 ) ) {
						Log3 $name, 3,
"S7: Invalid $aName startposition. valid startposition 0 - 32768: $@";
						return
"Invalid $aName startposition: $aVal db: valid startposition 0 - 32768";

					}
					if ( $i % 3 == 2
						&& ( $a[$i] < 1 || $a[$i] > $PDUlength ) )
					{
						Log3 $name, 3,
"S7: Invalid $aName length. valid length 1 - $PDUlength: $@";
						return
"Invalid $aName lenght: $aVal: valid length 1 - $PDUlength";
					}

				}

				return undef if ( $hash->{STATE} ne "connected to PLC" );

				#we need to fill-up the internal buffer from current PLC values
				my $hash = $defs{$name};

				my $res =
				  S7_getAllWritingBuffersFromPLC( $hash, $aName, $aVal );
				if ( int($res) != 0 ) {

					#quit because of error
					return $res;
				}

			}
		}
	}
	return undef;
}

#####################################

sub S7_getAreaIndex4AreaName($) {
	my ($aName) = @_;

	my $AreaIndex = -1;
	for ( my $j = 0 ; $j < int(@areaname) ; $j++ ) {
		if ( $aName eq $areasconfig[$j] || $aName eq $areaname[$j] ) {
			$AreaIndex = $j;
			last;
		}
	}
	if ( $AreaIndex < 0 ) {
		Log3 undef, 2, "S7_Attr: Internal error invalid WriteAreaIndex";
		return "Internal error invalid WriteAreaIndex";
	}
	return $AreaIndex;

}

#####################################
sub S7_WriteToPLC($$$$$$) {
	my ( $hash, $areaIndex, $dbNr, $startByte, $WordLen, $dataBlock ) = @_;

	my $PDUlength = -1;
	if ( defined $hash->{maxPDUlength} ) {
		$PDUlength = $hash->{maxPDUlength};
	}
	my $name = $hash->{NAME};

	my $res          = -1;
	my $Bufferlength = length($dataBlock);

	if ( $Bufferlength <= $PDUlength ) {
		if ( $hash->{STATE} eq "connected to PLC" ) {

			my $bss = join( ", ", unpack( "H2" x $Bufferlength, $dataBlock ) );
			Log3 $name, 5,
"$name S7_WriteToPLC: Write Bytes to PLC: $areaIndex, $dbNr,$startByte , $Bufferlength, $bss";


			eval {
				local $SIG{__DIE__} = sub {
					my ($s) = @_;
					print "DIE:$s";
					Log3 $hash, 0, "DIE:$s";
					$res = -2;
				};

				$res =
				  $hash->{S7TCPClient}
				  ->WriteArea( $s7areas[$areaIndex], $dbNr, $startByte,
					$Bufferlength, $WordLen, $dataBlock );

			};
			if ( $res != 0 ) {
				my $error = $hash->{S7TCPClient}->getErrorStr($res);

				my $msg = "$name S7_WriteToPLC WriteArea error: $res=$error";
				Log3 $name, 3, $msg;

				S7_reconnect($hash);    #lets try a reconnect
				return ( -2, $msg );
			}
		}
		else {
			my $msg = "$name S7_WriteToPLC: PLC is not connected ";

			Log3 $name, 3, $msg;

			S7_reconnect($hash);        #lets try a reconnect

			return ( -2, $msg );
		}

	}
	else {
		my $msg =
"S7_WriteToPLC: wrong block length  $Bufferlength (max length $PDUlength)";
		Log3 $name, 3, $msg;
		return ( -1, $msg );
	}
}
#####################################
sub S7_WriteBitToPLC($$$$$) {
	my ( $hash, $areaIndex, $dbNr, $bitPosition, $bitValue ) = @_;

	my $PDUlength = -1;
	if ( defined $hash->{maxPDUlength} ) {
		$PDUlength = $hash->{maxPDUlength};
	}
	my $name = $hash->{NAME};

	my $res          = -1;
	my $Bufferlength = 1;

	if ( $Bufferlength <= $PDUlength ) {
		if ( $hash->{STATE} eq "connected to PLC" ) {

			my $bss = join( ", ", unpack( "H2" x $Bufferlength, $bitValue ) );
			Log3 $name, 5,
"$name S7_WriteBitToPLC: Write Bytes to PLC: $areaIndex, $dbNr, $bitPosition , $Bufferlength, $bitValue";



			eval {
				local $SIG{__DIE__} = sub {
					my ($s) = @_;
					print "DIE:$s";
					Log3 $hash, 0, "DIE:$s";
					$res = -2;
				};

				$res =
				  $hash->{S7TCPClient}
				  ->WriteArea( $s7areas[$areaIndex], $dbNr, $bitPosition,
					$Bufferlength, &S7Client::S7WLBit, chr($bitValue) );


			};
			if ( $res != 0 ) {
				my $error = $hash->{S7TCPClient}->getErrorStr($res);

				my $msg = "$name S7_WriteBitToPLC WriteArea error: $res=$error";
				Log3 $name, 3, $msg;

				S7_reconnect($hash);    #lets try a reconnect
				return ( -2, $msg );
			}
		}
		else {
			my $msg = "$name S7_WriteBitToPLC: PLC is not connected ";
			Log3 $name, 3, $msg;
			return ( -1, $msg );
		}

	}
	else {
		my $msg =
"S7_WriteBitToPLC: wrong block length  $Bufferlength (max length $PDUlength)";
		Log3 $name, 3, $msg;
		return ( -1, $msg );
	}
}

#####################################
#sub S7_WriteBlockToPLC($$$$$) {
#	my ( $hash, $areaIndex, $dbNr, $startByte, $dataBlock ) = @_;
#
#
#	return S7_WriteToPLC($hash, $areaIndex, $dbNr, $startByte, &S7Client::S7WLByte, $dataBlock);
#
#}
#####################################

sub S7_ReadBlockFromPLC($$$$$) {
	my ( $hash, $areaIndex, $dbNr, $startByte, $requestedLength ) = @_;

	my $PDUlength = -1;
	if ( defined $hash->{maxPDUlength} ) {
		$PDUlength = $hash->{maxPDUlength};
	}
	my $name       = $hash->{NAME};
	my $readbuffer = "";
	my $res        = -1;

	if ( $requestedLength <= $PDUlength ) {
		if ( $hash->{STATE} eq "connected to PLC" ) {

			eval {
				local $SIG{__DIE__} = sub {
					my ($s) = @_;
					print "DIE:$s";
					Log3 $hash, 0, "DIE:$s";
					$res = -2;
				};

				( $res, $readbuffer ) =
				  $hash->{S7TCPClient}->ReadArea( $s7areas[$areaIndex], $dbNr, $startByte,
					$requestedLength, &S7Client::S7WLByte );
			};


			if ( $res != 0 ) {

				my $error = $hash->{S7TCPClient}->getErrorStr($res);
				my $msg =
				  "$name S7_ReadBlockFromPLC ReadArea error: $res=$error";
				Log3 $name, 3, $msg;

				S7_reconnect($hash);    #lets try a reconnect
				return ( -2, $msg );
			}
			else {

				#reading was OK
				return ( 0, $readbuffer );
			}
		}
		else {
			my $msg = "$name S7_ReadBlockFromPLC: PLC is not connected ";
			Log3 $name, 3, $msg;
			return ( -1, $msg );

		}
	}
	else {
		my $msg =
"$name S7_ReadBlockFromPLC: wrong block length (max length $PDUlength)";
		Log3 $name, 3, $msg;
		return ( -1, $msg );
	}
}

#####################################

sub S7_setBitInBuffer($$$) {
	my ( $bitPosition, $buffer, $newValue ) = @_;

	my $Bufferlength = ( length($buffer) + 1 ) / 3;
	my $bytePosition = int( $bitPosition / 8 );

#	Log3 undef, 3, "S7_setBitInBuffer in: ".length($buffer)." , $Bufferlength , $bytePosition , $bitPosition";

	if ( $bytePosition < 0 || $bytePosition > $Bufferlength - 1 ) {

		#out off buffer request !!!!!
		#		Log3 undef, 3, "S7_setBitInBuffer out -1 : ".length($buffer);

		return ( -1, undef );
	}

	my @Writebuffer = unpack( "C" x $Bufferlength,
		pack( "H2" x $Bufferlength, split( ",", $buffer ) ) );

	#my $intrestingByte = $Writebuffer[$bytePosition];
	my $intrestingBit = $bitPosition % 8;

	if ( $newValue eq "on" || $newValue eq "trigger" ) {
		$Writebuffer[$bytePosition] |= ( 1 << $intrestingBit );
	}
	else {
		$Writebuffer[$bytePosition] &= ( ( ~( 1 << $intrestingBit ) ) & 0xff );
	}

	my $resultBuffer = join(
		",",
		unpack(
			"H2" x $Bufferlength,
			pack( "C" x $Bufferlength, @Writebuffer )
		)
	);

	$Bufferlength = length($resultBuffer);

	#	Log3 undef, 3, "S7_setBitInBuffer out: $Bufferlength";

	return ( 0, $resultBuffer );
}

#####################################
sub S7_getBitFromBuffer($$) {
	my ( $bitPosition, $buffer ) = @_;

	my $Bufferlength = ( length($buffer) * 3 ) - 1;
	my $bytePosition = int( $bitPosition / 8 );
	if ( $bytePosition < 0 || $bytePosition > length($Bufferlength) ) {

		#out off buffer request !!!!!
		return "unknown";
	}
	my @Writebuffer = unpack( "C" x $Bufferlength,
		pack( "H2" x $Bufferlength, split( ",", $buffer ) ) );

	my $intrestingByte = $Writebuffer[$bytePosition];
	my $intrestingBit  = $bitPosition % 8;

	if ( ( $intrestingByte & ( 1 << $intrestingBit ) ) != 0 ) {

		return "on";
	}
	else {
		return "off";
	}

}

#####################################
sub S7_getAllWritingBuffersFromPLC($$$) {

	#$hash ... from S7 physical modul
	#$writerConfig ... writer Config
	#$aName ... area name

	my ( $hash, $aName, $writerConfig ) = @_;

	Log3 $aName, 4, "S7: getAllWritingBuffersFromPLC called";

	my @a = split( "[ \t][ \t]*", $writerConfig );

	my $PDUlength = $hash->{maxPDUlength};

	my @writingBuffers = ();
	my $readbuffer;

	my $writeAreaIndex = S7_getAreaIndex4AreaName($aName);
	return $writeAreaIndex if ( $writeAreaIndex ne int($writeAreaIndex) );

	my $nr = int(@a);

	#	Log3 undef, 4, "S7: getAllWritingBuffersFromPLC $nr";

	my $res;
	for ( my $i = 0 ; $i < int(@a) ; $i = $i + 3 ) {
		my $readbuffer;
		my $res;

		my $dbnr            = $a[$i];
		my $startByte       = $a[ $i + 1 ];
		my $requestedLength = $a[ $i + 2 ];

		( $res, $readbuffer ) =
		  S7_ReadBlockFromPLC( $hash, $writeAreaIndex, $dbnr, $startByte,
			$requestedLength );
		if ( $res == 0 ) {    #reading was OK
			my $hexbuffer =
			  join( ",", unpack( "H2" x length($readbuffer), $readbuffer ) );
			push( @writingBuffers, $hexbuffer );
		}
		else {

			#error in reading so just return the error MSG
			return $readbuffer;
		}
	}

	if ( int(@writingBuffers) > 0 ) {
		$hash->{"${areaname[$writeAreaIndex]}_DBWRITEBUFFER"} =
		  join( " ", @writingBuffers );
	}
	else {
		$hash->{"${areaname[$writeAreaIndex]}_DBWRITEBUFFER"} = undef;
	}
	return 0;
}

#####################################
sub S7_GetUpdate($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	Log3 $name, 4, "S7: $name GetUpdate called ...";

	my $res = S7_readFromPLC($hash);

	if ( $res == 0 ) {
		InternalTimer( gettimeofday() + $hash->{Interval},
			"S7_GetUpdate", $hash, 1 );
	}
	else {

		#an error has occoured --> 10sec break
		InternalTimer( gettimeofday() + 10, "S7_GetUpdate", $hash, 1 );
	}

}

#####################################
sub S7_dispatchMsg($$$$$$$$) {
	my ( $hash, $msgprefix, $areaIndex, $dbNr, $startByte, $hexbuffer,$length, $clientsNames ) = @_;

	my $name   = $hash->{NAME};
	my $dmsg =
	    $msgprefix . " "
	  . $areaname[$areaIndex] . " "
	  . $dbNr . " "
	  . $startByte . " "
	  . $length . " "
	  . $name . " "
	  . $hexbuffer. " "
	  . $clientsNames
	  ;


	Log3 $name, 5, $name . " S7_dispatchMsg " . $dmsg;

	Dispatch( $hash, $dmsg, {} );

}
#####################################
sub S7_readAndDispatchBlockFromPLC($$$$$$$$$$) {
	my (
		$hash,              $area,             $dbnr,
		$blockstartpos,     $blocklength,      $hasAnalogReading,
		$hasDigitalReading, $hasAnalogWriting, $hasDigitalWriting, $clientsNames
	) = @_;

	my $name      = $hash->{NAME};
	my $state     = $hash->{STATE};
	my $areaIndex = S7_getAreaIndex4AreaName($area);


	Log3 $name, 4,
	    $name
	  . " READ Block AREA="
	  . $area
	  . ", DB ="
	  . $dbnr
	  . ", ADDRESS="
	  . $blockstartpos
	  . ", LENGTH="
	  . $blocklength;

	if ( $state ne "connected to PLC" ) {
		Log3 $name, 3, "$name is disconnected ? --> reconnect";
		S7_reconnect($hash);    #lets try a reconnect
		    #@nextreadings[ $i / 4 ] = $now + 10;    #retry in 10s
		return -2;
	}

	my $res;
	my $readbuffer;

	( $res, $readbuffer ) =
	  S7_ReadBlockFromPLC( $hash, $areaIndex, $dbnr, $blockstartpos,
		$blocklength );

	if ( $res == 0 ) {

		#reading was OK
		my $length = length($readbuffer);
		my $hexbuffer = join( ",", unpack( "H2" x $length, $readbuffer ) );

		#dispatch to reader
		S7_dispatchMsg( $hash, "AR", $areaIndex, $dbnr, $blockstartpos,
			$hexbuffer,$length,$clientsNames )
		  if ( $hasAnalogReading > 0 );
		S7_dispatchMsg( $hash, "DR", $areaIndex, $dbnr, $blockstartpos,
			$hexbuffer,$length,$clientsNames )
		  if ( $hasDigitalReading > 0 );

		#dispatch to writer
		S7_dispatchMsg( $hash, "AW", $areaIndex, $dbnr, $blockstartpos,
			$hexbuffer,$length,$clientsNames )
		  if ( $hasAnalogWriting > 0 );
		S7_dispatchMsg( $hash, "DW", $areaIndex, $dbnr, $blockstartpos,
			$hexbuffer,$length,$clientsNames )
		  if ( $hasDigitalWriting > 0 );
		return 0;
	}
	else {

		#reading failed
		return -1;
	}

}
#####################################
sub S7_getReadingsList($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};

	my @readings;

	# Jetzt suchen wir alle Readings
	my @mykeys;
	my %logoClients;

	@mykeys =
	  grep $defs{$_}{TYPE} =~ /^S7_/ && $defs{$_}{IODev}{NAME} eq $hash->{NAME},
	  keys(%defs);
	@logoClients{@mykeys} = @defs{@mykeys};#jetzt haben wir alle clients in logoClients

	#we need to find out the unique areas
	my %tmphash = map { $logoClients{$_}{AREA} => 1 } keys %logoClients;
	my @uniqueArea = keys %tmphash;

	foreach my $Area (@uniqueArea) {
		my %logoClientsArea;
		@mykeys =
		     grep $defs{$_}{TYPE} =~ /^S7_/
		  && $defs{$_}{IODev}{NAME} eq $hash->{NAME}
		  && $defs{$_}{AREA} eq $Area, keys(%defs);
		@logoClientsArea{@mykeys} = @defs{@mykeys};

		#now we findout which DBs are used (unique)
		%tmphash = map { $logoClientsArea{$_}{DB} => 1 } keys %logoClientsArea;
		my @uniqueDB = keys %tmphash;

		foreach my $DBNr (@uniqueDB) {

			#now we filter all readinfy by DB!
			my %logoClientsDB;

			@mykeys =
			     grep $defs{$_}{TYPE} =~ /^S7_/
			  && $defs{$_}{IODev}{NAME} eq $hash->{NAME}
			  && $defs{$_}{AREA} eq $Area
			  && $defs{$_}{DB} == $DBNr, keys(%defs);
			@logoClientsDB{@mykeys} = @defs{@mykeys};

			#next step is, sorting all clients by ADDRESS
			my @positioned = sort {
				$logoClientsDB{$a}{ADDRESS} <=> $logoClientsDB{$b}{ADDRESS}
			} keys %logoClientsDB;

			my $blockstartpos = -1;
			my $blocklength   = 0;

			my $hasAnalogReading  = 0;
			my $hasDigitalReading = 0;
			my $hasAnalogWriting  = 0;
			my $hasDigitalWriting = 0;
			my $clientsName = "";

			for ( my $i = 0 ; $i < int(@positioned) ; $i++ ) {
				if ( $blockstartpos < 0 ) {

					#we start a new block
					$blockstartpos =
					  int( $logoClientsDB{ $positioned[$i] }{ADDRESS} );
					$blocklength = $logoClientsDB{ $positioned[$i] }{LENGTH};

					$hasAnalogReading++
					  if (
						$logoClientsDB{ $positioned[$i] }{TYPE} eq "S7_ARead" );
					$hasDigitalReading++
					  if (
						$logoClientsDB{ $positioned[$i] }{TYPE} eq "S7_DRead" );
					$hasAnalogWriting++
					  if ( $logoClientsDB{ $positioned[$i] }{TYPE} eq
						"S7_AWrite" );
					$hasDigitalWriting++
					  if ( $logoClientsDB{ $positioned[$i] }{TYPE} eq
						"S7_DWrite" );
						
					$clientsName = $logoClientsDB{ $positioned[$i] }{NAME};

				}
				else {

					if ( $logoClientsDB{ $positioned[$i] }{ADDRESS} +
						$logoClientsDB{ $positioned[$i] }{LENGTH} -
						$blockstartpos <=
						$hash->{S7TCPClient}->{MaxReadLength} )
					{

						#extend existing block
						if (
							int( $logoClientsDB{ $positioned[$i] }{ADDRESS} ) +
							$logoClientsDB{ $positioned[$i] }{LENGTH} -
							$blockstartpos > $blocklength )
						{
							$blocklength =
							  int( $logoClientsDB{ $positioned[$i] }{ADDRESS} )
							  + $logoClientsDB{ $positioned[$i] }{LENGTH} -
							  $blockstartpos;

							$hasAnalogReading++
							  if ( $logoClientsDB{ $positioned[$i] }{TYPE} eq
								"S7_ARead" );
							$hasDigitalReading++
							  if ( $logoClientsDB{ $positioned[$i] }{TYPE} eq
								"S7_DRead" );
							$hasAnalogWriting++
							  if ( $logoClientsDB{ $positioned[$i] }{TYPE} eq
								"S7_AWrite" );
							$hasDigitalWriting++
							  if ( $logoClientsDB{ $positioned[$i] }{TYPE} eq
								"S7_DWrite" );
								
							
								
						}
						$clientsName .= "," .$logoClientsDB{ $positioned[$i] }{NAME};
					}
					else {

						#block would exeed MaxReadLength

						#read and dispatch block from PLC
						#block in liste speichern
						push(
							@readings,
							[
								$logoClientsDB{ $positioned[$i] }{AREA},
								$logoClientsDB{ $positioned[$i] }{DB},
								$blockstartpos,
								$blocklength,
								$hasAnalogReading,
								$hasDigitalReading,
								$hasAnalogWriting,
								$hasDigitalWriting,
								$clientsName
							]
						);

						$hasAnalogReading  = 0;
						$hasDigitalReading = 0;
						$hasAnalogWriting  = 0;
						$hasDigitalWriting = 0;

						#start new block new time
						$blockstartpos =
						  int( $logoClientsDB{ $positioned[$i] }{ADDRESS} );
						$blocklength =
						  $logoClientsDB{ $positioned[$i] }{LENGTH};

						$hasAnalogReading++
						  if ( $logoClientsDB{ $positioned[$i] }{TYPE} eq
							"S7_ARead" );
						$hasDigitalReading++
						  if ( $logoClientsDB{ $positioned[$i] }{TYPE} eq
							"S7_DRead" );
						$hasAnalogWriting++
						  if ( $logoClientsDB{ $positioned[$i] }{TYPE} eq
							"S7_AWrite" );
						$hasDigitalWriting++
						  if ( $logoClientsDB{ $positioned[$i] }{TYPE} eq
							"S7_DWrite" );
							
						$clientsName = $logoClientsDB{ $positioned[$i] }{NAME};							
					}

				}

			}
			if ( $blockstartpos >= 0 ) {

				#read and dispatch block from PLC

				push(
					@readings,
					[
						$logoClientsDB{ $positioned[ int(@positioned) - 1 ] }
						  {AREA},
						$logoClientsDB{ $positioned[ int(@positioned) - 1 ] }
						  {DB},
						$blockstartpos,
						$blocklength,
						$hasAnalogReading,
						$hasDigitalReading,
						$hasAnalogWriting,
						$hasDigitalWriting,
						$clientsName
					]
				);

			}
		}
	}
	@{ $hash->{ReadingList} } = @readings;
	return 0;

}

#####################################
sub S7_readFromPLC($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $res;

	if ( ( !defined( $hash->{dirty} ) ) || $hash->{dirty} == 1 ) {
		S7_getReadingsList($hash);
		$hash->{dirty} = 0;
	}

	my @readingList = @{ $hash->{ReadingList} };

	for ( my $i = 0 ; $i < int(@readingList) ; $i++ ) {
		my @readingSet = @{ $readingList[$i] };
		$res = S7_readAndDispatchBlockFromPLC(
			$hash,          $readingSet[0], $readingSet[1],
			$readingSet[2], $readingSet[3], $readingSet[4],
			$readingSet[5], $readingSet[6], $readingSet[7], $readingSet[8]
		);

		return $res if ( $res != 0 );
	}
	return 0;
}



1;

=pod
=begin html

<a name="S7"></a>
<h3>S7</h3>
<ul>
	This module connects a SIEMENS PLC (Note: also SIEMENS Logo is supported). The TCP communication module is based on settimino (http://settimino.sourceforge.net) You can found a german wiki here: httl://www.fhemwiki.de/wiki/S7<br />
	<br />
	For the communication the following modules have been implemented:
	<ul>
		<li>S7 &hellip; sets up the communication channel to the PLC</li>
		<li>S7_ARead &hellip; Is used for reading integer Values from the PLC</li>
		<li>S7_AWrite &hellip; Is used for write integer Values to the PLC</li>
		<li>S7_DRead &hellip; Is used for read bits</li>
		<li>S7_DWrite &hellip; Is used for writing bits.</li>
	</ul>
	<br />
	<br />
	Reading work flow:<br />
	<br />
	The S7 module reads periodically the configured DB areas from the PLC and stores the data in an internal buffer. Then all reading client modules are informed. Each client module extracts his data and the corresponding readings are set. <brl> <brl> Writing work flow:<br />
	<br />
	At the S7 module you need to configure the PLC writing target. Also the S7 module holds a writing buffer. Which contains a master copy of the data needs to send.<br />
	(Note: after configuration of the writing area a copy from the PLC is read and used as initial fill-up of the writing buffer)<br />
	Note: The S7 module will send always the whole data block to the PLC. When data on the clients modules is set then the client module updates the internal writing buffer on the S7 module and triggers the writing to the PLC.<br />
	<br />
	<a name="S7define"></a> <b>Define</b>

	<ul>
		<li><code>define &lt;name&gt; S7 &lt;ip_address&gt; &lt;rack&gt; &lt;slot&gt; [&lt;Interval&gt;] </code><br />
		<br />
		<code>define logo S7 10.0.0.241 2 0 </code>

		<ul>
			<li>ip_address &hellip; IP address of the PLC</li>
			<li>rack &hellip; rack of the PLC</li>
			<li>slot &hellip; slot of the PLC</li>
			<li>Interval &hellip; Intervall how often the modul should check if a reading is required</li>
		</ul>
		<br />
		Note: For Siemens logo you should use a alternative (more simply configuration method):<br />
		define logo S7 LOGO7 10.0.0.241</li>
	</ul>
	<br />
	<br />
	<b>Attr</b><br />
	The following attributes are supported:<br />
	<br />
	&nbsp;
	<ul>
		<li>MaxMessageLength</li>
		<br />
		<li>MaxMessageLength ... restricts the packet length if lower than the negioated PDULength. This could be used to increate the processing speed. 2 small packages may be smaler than one large package</li>
	</ul>
</ul>

=end html

=begin html_DE


<a name="S7"></a>
<h3>S7</h3>
<ul>
	This module connects a SIEMENS PLC (Note: also SIEMENS Logo is supported). The TCP communication module is based on settimino (http://settimino.sourceforge.net) You can found a german wiki here: httl://www.fhemwiki.de/wiki/S7<br />
	<br />
	For the communication the following modules have been implemented:
	<ul>
		<li>S7 &hellip; sets up the communication channel to the PLC</li>
		<li>S7_ARead &hellip; Is used for reading integer Values from the PLC</li>
		<li>S7_AWrite &hellip; Is used for write integer Values to the PLC</li>
		<li>S7_DRead &hellip; Is used for read bits</li>
		<li>S7_DWrite &hellip; Is used for writing bits.</li>
	</ul>
	<br />
	<br />
	Reading work flow:<br />
	<br />
	The S7 module reads periodically the configured DB areas from the PLC and stores the data in an internal buffer. Then all reading client modules are informed. Each client module extracts his data and the corresponding readings are set. <brl> <brl> Writing work flow:<br />
	<br />
	At the S7 module you need to configure the PLC writing target. Also the S7 module holds a writing buffer. Which contains a master copy of the data needs to send.<br />
	(Note: after configuration of the writing area a copy from the PLC is read and used as initial fill-up of the writing buffer)<br />
	Note: The S7 module will send always the whole data block to the PLC. When data on the clients modules is set then the client module updates the internal writing buffer on the S7 module and triggers the writing to the PLC.<br />
	<br />
	<a name="S7define"></a> <b>Define</b>

	<ul>
		<li><code>define &lt;name&gt; S7 &lt;ip_address&gt; &lt;rack&gt; &lt;slot&gt; [&lt;Interval&gt;] </code><br />
		<br />
		<code>define logo S7 10.0.0.241 2 0 </code>

		<ul>
			<li>ip_address &hellip; IP address of the PLC</li>
			<li>rack &hellip; rack of the PLC</li>
			<li>slot &hellip; slot of the PLC</li>
			<li>Interval &hellip; Intervall how often the modul should check if a reading is required</li>
		</ul>
		<br />
		Note: For Siemens logo you should use a alternative (more simply configuration method):<br />
		define logo S7 LOGO7 10.0.0.241</li>
	</ul>
	<br />
	<br />
	<b>Attr</b><br />
	The following attributes are supported:<br />
	<br />
	&nbsp;
	<ul>
		<li>MaxMessageLength</li>
		<br />
		<li>MaxMessageLength ... restricts the packet length if lower than the negioated PDULength. This could be used to increate the processing speed. 2 small packages may be smaler than one large package</li>
	</ul>
</ul>


=end html_DE

=cut
