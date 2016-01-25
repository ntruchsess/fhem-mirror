# $Id$
##############################################
package main;

use strict;
use warnings;

#use Switch;
require "44_S7_Client.pm";

my %gets = (

	#  "libnodaveversion"   => ""
);

sub _isfloat {
	my $val = shift;

	#  return $val =~ m/^\d+.\d+$/;
	return $val =~ m/^[-+]?\d*\.?\d*$/;

	#[-+]?[0-9]*\.?[0-9]*
}

#####################################
sub S7_ARead_Initialize($) {
	my $hash = shift @_;

	# Provider

	# Consumer
	$hash->{Match} = "^AR";

	$hash->{DefFn}   = "S7_ARead_Define";
	$hash->{UndefFn} = "S7_ARead_Undef";
	$hash->{ParseFn} = "S7_ARead_Parse";

	$hash->{AttrFn} = "S7_ARead_Attr";

	$hash->{AttrList} = "IODev offset multiplicator " . $readingFnAttributes;

	main::LoadModule("S7");
}

#####################################
sub S7_ARead_Define($$) {
	my ( $hash, $def ) = @_;
	my @a = split( "[ \t][ \t]*", $def );

	my ( $name, $area, $DB, $start, $datatype );

	$name     = $a[0];
	$area     = lc $a[2];
	$DB       = $a[3];
	$start    = $a[4];
	$datatype = lc $a[5];

	if (   $area ne "inputs"
		&& $area ne "outputs"
		&& $area ne "flags"
		&& $area ne "db" )
	{
		my $msg =
"wrong syntax: define <name> S7_ARead {inputs|outputs|flags|db} <DB> <start> {u8|s8|u16|s16|u32|s32|float}";

		Log3 undef, 2, $msg;
		return $msg;
	}

	if (   $datatype ne "u8"
		&& $datatype ne "s8"
		&& $datatype ne "u16"
		&& $datatype ne "s16"
		&& $datatype ne "u32"
		&& $datatype ne "s32"
		&& $datatype ne "float" )
	{
		my $msg =
"wrong syntax: define <name> S7_ARead {inputs|outputs|flags|db} <DB> <start> {u8|s8|u16|s16|u32|s32|float}";

		Log3 undef, 2, $msg;
		return $msg;
	}

	$hash->{AREA}     = $area;
	$hash->{DB}       = $DB;
	$hash->{ADDRESS}  = $start;
	$hash->{DATATYPE} = $datatype;

	if ( $datatype eq "u16" || $datatype eq "s16" ) {
		$hash->{LENGTH} = 2;
	}
	elsif ( $datatype eq "u32" || $datatype eq "s32" || $datatype eq "float" ) {
		$hash->{LENGTH} = 4;
	}
	else {
		$hash->{LENGTH} = 1;
	}

	my $ID = "$area $DB";

	if ( !defined( $modules{S7_ARead}{defptr}{$ID} ) ) {
		my @b = ();
		push( @b, $hash );
		$modules{S7_ARead}{defptr}{$ID} = \@b;

	}
	else {
		push( @{ $modules{S7_ARead}{defptr}{$ID} }, $hash );
	}

	AssignIoPort($hash);    # logisches modul an physikalisches binden !!!

	$hash->{IODev}{dirty} = 1;
	Log3 $name, 4,
	  "S7_ARead (" . $hash->{IODev}{NAME} . "): define $name Adress:$start";

	return undef;
}
#####################################
sub S7_ARead_Undef($$) {
	my ( $hash, $name ) = @_;

	Log3 $name, 4,
	    "S7_ARead ("
	  . $hash->{IODev}{NAME}
	  . "): undef "
	  . $hash->{NAME}
	  . " Adress:"
	  . $hash->{ADDRESS};
	delete( $modules{S7_ARead}{defptr} );

	return undef;
}

#####################################
sub S7_ARead_Parse($$) {
	my ( $hash, $rmsg ) = @_;
	my $name = $hash->{NAME};

	my @a = split( "[ \t][ \t]*", $rmsg );
	my @list;

	my ( $area, $DB, $start, $length, $datatype, $s7name, $hexbuffer,
		$clientNames );

	$area        = lc $a[1];
	$DB          = $a[2];
	$start       = $a[3];
	$length      = $a[4];
	$s7name      = $a[5];
	$hexbuffer   = $a[6];
	$clientNames = $a[7];

	my $ID = "$area $DB";

	Log3 $name, 5, "$name S7_ARead_Parse $rmsg";

	my @clientList = split( ",", $clientNames );

	if ( int(@clientList) > 0 ) {
		my @Writebuffer = unpack( "C" x $length,
			pack( "H2" x $length, split( ",", $hexbuffer ) ) );

		#my $b = pack( "C" x $length, @Writebuffer );
		foreach my $clientName (@clientList) {

			my $h = $defs{$clientName};

			if (   $h->{TYPE} eq "S7_ARead"
				&& $start <= $h->{ADDRESS}
				&& $start + $length >= $h->{ADDRESS} + $h->{LENGTH} )
			{

				my $n = $h->{NAME};   #damit die werte im client gesetzt werden!
				push( @list, $n );

				#aktualisierung des wertes
				my $s = $h->{ADDRESS} - $start;
				my $myI;

				if ( $h->{DATATYPE} eq "u8" ) {
					$myI = $hash->{S7TCPClient}->ByteAt( \@Writebuffer, $s );
				}
				elsif ( $h->{DATATYPE} eq "s8" ) {
					$myI = $hash->{S7TCPClient}->ShortAt( \@Writebuffer, $s );
				}
				elsif ( $h->{DATATYPE} eq "u16" ) {
					$myI = $hash->{S7TCPClient}->WordAt( \@Writebuffer, $s );
				}
				elsif ( $h->{DATATYPE} eq "s16" ) {
					$myI = $hash->{S7TCPClient}->IntegerAt( \@Writebuffer, $s );
				}
				elsif ( $h->{DATATYPE} eq "u32" ) {
					$myI = $hash->{S7TCPClient}->DWordAt( \@Writebuffer, $s );
				}
				elsif ( $h->{DATATYPE} eq "s32" ) {
					$myI = $hash->{S7TCPClient}->DintAt( \@Writebuffer, $s );
				}
				elsif ( $h->{DATATYPE} eq "float" ) {
					$myI = $hash->{S7TCPClient}->FloatAt( \@Writebuffer, $s );
				}
				else {
					Log3 $name, 3,
					  "$name S7_ARead: Parse unknown type : ("
					  . $h->{DATATYPE} . ")";
				}

 #now we need to correct the analog value by the parameters attribute and offset
				my $offset = 0;
				if ( defined( $main::attr{$n}{offset} ) ) {
					$offset = $main::attr{$n}{offset};
				}

				my $multi = 1;
				if ( defined( $main::attr{$n}{multiplicator} ) ) {
					$multi = $main::attr{$n}{multiplicator};
				}

				$myI = $myI * $multi + $offset;

				#my $myResult;

				main::readingsSingleUpdate( $h, "state", $myI, 1 );

				#			main::readingsSingleUpdate($h,"value",$myResult, 1);
			}

		}
	}
	else {

		Log3 $name, 3, "$name S7_ARead_Parse going the save way ";
		if ( defined( $modules{S7_ARead}{defptr}{$ID} ) ) {

			foreach my $h ( @{ $modules{S7_ARead}{defptr}{$ID} } ) {
				if ( defined( $main::attr{ $h->{NAME} }{IODev} )
					&& $main::attr{ $h->{NAME} }{IODev} eq $name )
				{
					if (   $start <= $h->{ADDRESS}
						&& $start + $length >= $h->{ADDRESS} + $h->{LENGTH} )
					{

						my $n =
						  $h->{NAME}; #damit die werte im client gesetzt werden!
						push( @list, $n );

						#aktualisierung des wertes

						my @Writebuffer = unpack( "C" x $length,
							pack( "H2" x $length, split( ",", $hexbuffer ) ) );
						my $s = $h->{ADDRESS} - $start;

						#my $b = pack( "C" x $length, @Writebuffer );
						my $myI;

						if ( $h->{DATATYPE} eq "u8" ) {
							$myI =
							  $hash->{S7TCPClient}->ByteAt( \@Writebuffer, $s );
						}
						elsif ( $h->{DATATYPE} eq "s8" ) {
							$myI =
							  $hash->{S7TCPClient}
							  ->ShortAt( \@Writebuffer, $s );
						}
						elsif ( $h->{DATATYPE} eq "u16" ) {
							$myI =
							  $hash->{S7TCPClient}->WordAt( \@Writebuffer, $s );
						}
						elsif ( $h->{DATATYPE} eq "s16" ) {
							$myI =
							  $hash->{S7TCPClient}
							  ->IntegerAt( \@Writebuffer, $s );
						}
						elsif ( $h->{DATATYPE} eq "u32" ) {
							$myI =
							  $hash->{S7TCPClient}
							  ->DWordAt( \@Writebuffer, $s );
						}
						elsif ( $h->{DATATYPE} eq "s32" ) {
							$myI =
							  $hash->{S7TCPClient}->DintAt( \@Writebuffer, $s );
						}
						elsif ( $h->{DATATYPE} eq "float" ) {
							$myI =
							  $hash->{S7TCPClient}
							  ->FloatAt( \@Writebuffer, $s );
						}
						else {
							Log3 $name, 3,
							  "$name S7_ARead: Parse unknown type : ("
							  . $h->{DATATYPE} . ")";
						}

 #now we need to correct the analog value by the parameters attribute and offset
						my $offset = 0;
						if ( defined( $main::attr{$n}{offset} ) ) {
							$offset = $main::attr{$n}{offset};
						}

						my $multi = 1;
						if ( defined( $main::attr{$n}{multiplicator} ) ) {
							$multi = $main::attr{$n}{multiplicator};
						}

						$myI = $myI * $multi + $offset;

						#my $myResult;

						main::readingsSingleUpdate( $h, "state", $myI, 1 );

						#			main::readingsSingleUpdate($h,"value",$myResult, 1);
					}
				}
			}
		}

	}

	if ( int(@list) == 0 ) {
		Log3 $name, 6, "S7_ARead: Parse no client found ($name) ...";
		push( @list, "" );
	}

	return @list;

}

#####################################

sub S7_ARead_Attr(@) {
	my ( $cmd, $name, $aName, $aVal ) = @_;

	# $cmd can be "del" or "set"
	# $name is device name
	# aName and aVal are Attribute name and value
	my $hash = $defs{$name};
	if ( $cmd eq "set" ) {
		if ( $aName eq "offset" || $aName eq "multiplicator" ) {

			if ( !_isfloat($aVal) ) {

				Log3 $name, 3,
"S7_ARead: Invalid $aName in attr $name $aName $aVal ($aVal is not a number): $@";
				return "Invalid $aName $aVal: $aVal is not a number";
			}

		}
		elsif ( $aName eq "IODev" ) {
			if ( defined( $hash->{IODev} ) ) {    #set old master device dirty
				$hash->{IODev}{dirty} = 1;
			}
			if ( defined( $defs{$aVal} ) ) {      #set new master device dirty
				$defs{$aVal}{dirty} = 1;
			}
			Log3 $name, 4, "S7_ARead: IODev for $name is $aVal";

		}

	}
	return undef;
}

1;

=pod
=begin html

<a name="S7_ARead"></a>
<h3>S7_ARead</h3>
<ul>
	This module is a logical module of the physical module S7.<br />
	This module provides analog data (signed / unsigned integer Values).<br />
	Note: you have to configure a PLC reading at the physical module (S7) first.<br />
	<br />
	<br />
	<b>Define</b><br />
	<code>define &lt;name&gt; S7_ARead {inputs|outputs|flags|db} &lt;DB&gt; &lt;start&gt; {u8|s8|u16|s16|u32|s32}</code><br />
	&nbsp;
	<ul>
		<li>inputs|outputs|flags|db &hellip; defines where to read.</li>
		<li>DB &hellip; Number of the DB</li>
		<li>start &hellip; start byte of the reading</li>
		<li>{u8|s8|u16|s16|u32|s32} &hellip; defines the datatype:
		<ul>
			<li>u8 &hellip;. unsigned 8 Bit integer</li>
			<li>s8 &hellip;. signed 8 Bit integer</li>
			<li>u16 &hellip;. unsigned 16 Bit integer</li>
			<li>s16 &hellip;. signed 16 Bit integer</li>
			<li>u32 &hellip;. unsigned 32 Bit integer</li>
			<li>s32 &hellip;. signed 32 Bit integer</li>
		</ul>
		</li>
		<li>Note: the required memory area (start &ndash; start + datatypelength) need to be with in the configured PLC reading of the physical module.</li>
	</ul>
	<br />
	<b>Attr</b><br />
	The following parameters are used to scale every reading
	<ul>
		<li>multiplicator</li>
		<li>offset</li>
	</ul>
	newValue = &lt;multiplicator&gt; * Value + &lt;offset&gt;
</ul>
=end html

=begin html_DE

<a name="S7_ARead"></a>
<h3>S7_ARead</h3>
<ul>
	This module is a logical module of the physical module S7.<br />
	This module provides analog data (signed / unsigned integer Values).<br />
	Note: you have to configure a PLC reading at the physical module (S7) first.<br />
	<br />
	<br />
	<b>Define</b><br />
	<code>define &lt;name&gt; S7_ARead {inputs|outputs|flags|db} &lt;DB&gt; &lt;start&gt; {u8|s8|u16|s16|u32|s32}</code><br />
	&nbsp;
	<ul>
		<li>inputs|outputs|flags|db &hellip; defines where to read.</li>
		<li>DB &hellip; Number of the DB</li>
		<li>start &hellip; start byte of the reading</li>
		<li>{u8|s8|u16|s16|u32|s32} &hellip; defines the datatype:
		<ul>
			<li>u8 &hellip;. unsigned 8 Bit integer</li>
			<li>s8 &hellip;. signed 8 Bit integer</li>
			<li>u16 &hellip;. unsigned 16 Bit integer</li>
			<li>s16 &hellip;. signed 16 Bit integer</li>
			<li>u32 &hellip;. unsigned 32 Bit integer</li>
			<li>s32 &hellip;. signed 32 Bit integer</li>
			<li>float &hellip;. 4 byte float</li>
		</ul>
		</li>
		<li>Note: the required memory area (start &ndash; start + datatypelength) need to be with in the configured PLC reading of the physical module.</li>
	</ul>
	<b>Attr</b><br />
	The following parameters are used to scale every reading
	<ul>
		<li>multiplicator</li>
		<li>offset</li>
	</ul>
	newValue = &lt;multiplicator&gt; * Value + &lt;offset&gt;
</ul>
=end html_DE

=cut

