################################################################
#
#  88_HMCCUCHN.pm
#
#  $Id$
#
#  Version 3.4
#
#  (c) 2016 zap (zap01 <at> t-online <dot> de)
#
################################################################
#
#  define <name> HMCCUCHN <ccudev> [readonly]
#
#  set <name> control <value>
#  set <name> datapoint <datapoint> <value>
#  set <name> devstate <value>
#  set <name> <stateval_cmds>
#  set <name> on-till <timestamp>
#  set <name> on-for-timer <ontime>
#  set <name> pct <level> [{ <ontime> | 0 } [<ramptime>]]
#  set <name> toggle
#  set <name> config <parameter>=<value> [...]
#
#  get <name> devstate
#  get <name> datapoint <datapoint>
#  get <name> channel <datapoint-expr>
#  get <name> config
#  get <name> configdesc
#  get <name> update
#
#  attr <name> ccuackstate { 0 | 1 }
#  attr <name> ccuflags { nochn0, trace }
#  attr <name> ccuget { State | Value }
#  attr <name> ccureadings { 0 | 1 }
#  attr <name> ccureadingfilter <datapoint-expr>
#  attr <name> ccureadingformat { name[lc] | address[lc] | datapoint[lc] }
#  attr <name> ccureadingname <oldname>:<newname>[,...]
#  attr <name> ccuverify { 0 | 1 | 2 }
#  attr <name> controldatapoint <datapoint>
#  attr <name> disable { 0 | 1 }
#  attr <name> statedatapoint <datapoint>
#  attr <name> statevals <text1>:<subtext1>[,...]
#  attr <name> substitute <subst-rule>[;...]
#
################################################################
#  Requires module 88_HMCCU.pm
################################################################

package main;

use strict;
use warnings;
use SetExtensions;

# use Time::HiRes qw( gettimeofday usleep );

sub HMCCUCHN_Define ($@);
sub HMCCUCHN_Set ($@);
sub HMCCUCHN_Get ($@);
sub HMCCUCHN_Attr ($@);
sub HMCCUCHN_SetError ($$);

#####################################
# Initialize module
#####################################

sub HMCCUCHN_Initialize ($)
{
	my ($hash) = @_;

	$hash->{DefFn} = "HMCCUCHN_Define";
	$hash->{SetFn} = "HMCCUCHN_Set";
	$hash->{GetFn} = "HMCCUCHN_Get";
	$hash->{AttrFn} = "HMCCUCHN_Attr";

	$hash->{AttrList} = "IODev ccuackstate:0,1 ccuflags:multiple-strict,nochn0,trace ccureadingfilter ccureadingformat:name,namelc,address,addresslc,datapoint,datapointlc ccureadingname ccureadings:0,1 ccuscaleval ccuverify:0,1,2 ccuget:State,Value controldatapoint disable:0,1 statedatapoint statevals substitute stripnumber ". $readingFnAttributes;
}

#####################################
# Define device
#####################################

sub HMCCUCHN_Define ($@)
{
	my ($hash, $def) = @_;
	my $name = $hash->{NAME};
	my @a = split("[ \t][ \t]*", $def);

	return "Specifiy the CCU device name or address as parameters" if (@a < 3);

	my $devname = shift @a;
	my $devtype = shift @a;
	my $devspec = shift @a;

	return "Invalid or unknown CCU channel name or address" if (! HMCCU_IsValidDevice ($devspec));

	if (HMCCU_IsChnAddr ($devspec, 1)) {
		# CCU Channel address with interface
		$hash->{ccuif} = $1;
		$hash->{ccuaddr} = $2;
		$hash->{ccuname} = HMCCU_GetChannelName ($hash->{ccuaddr}, '');
		return "CCU device name not found for channel address $devspec" if ($hash->{ccuname} eq '');
	}
	elsif (HMCCU_IsChnAddr ($devspec, 0)) {
		# CCU Channel address
		$hash->{ccuaddr} = $devspec;
		$hash->{ccuif} = HMCCU_GetDeviceInterface ($hash->{ccuaddr}, 'BidCos-RF');
		$hash->{ccuname} = HMCCU_GetChannelName ($devspec, '');
		return "CCU device name not found for channel address $devspec" if ($hash->{ccuname} eq '');
	}
	else {
		# CCU Channel name
		$hash->{ccuname} = $devspec;
		my ($add, $chn) = HMCCU_GetAddress ($devspec, '', '');
		return "Channel address not found for channel name $devspec" if ($add eq '' || $chn eq '');
		$hash->{ccuaddr} = $add.':'.$chn;
		$hash->{ccuif} = HMCCU_GetDeviceInterface ($hash->{ccuaddr}, 'BidCos-RF');
	}

	$hash->{ccutype} = HMCCU_GetDeviceType ($hash->{ccuaddr}, '');
	$hash->{channels} = 1;
	$hash->{statevals} = 'devstate';

	my $arg = shift @a;
	if (defined ($arg) && $arg eq 'readonly') {
		$hash->{statevals} = $arg;
	}

	# Inform HMCCU device about client device
	AssignIoPort ($hash);

	readingsSingleUpdate ($hash, "state", "Initialized", 1);
	$hash->{ccudevstate} = 'Active';

	return undef;
}

#####################################
# Set attribute
#####################################

sub HMCCUCHN_Attr ($@)
{
	my ($cmd, $name, $attrname, $attrval) = @_;
	my $hash = $defs{$name};

	if ($cmd eq "set") {
		return "Missing attribute value" if (!defined ($attrval));
		if ($attrname eq 'IODev') {
			$hash->{IODev} = $defs{$attrval};
		}
		elsif ($attrname eq 'statevals') {
			return "Device is read only" if ($hash->{statevals} eq 'readonly');
			$hash->{statevals} = "devstate";
			my @states = split /,/,$attrval;
			foreach my $st (@states) {
				my @statesubs = split /:/,$st;
				return "value := text:substext[,...]" if (@statesubs != 2);
				$hash->{statevals} .= '|'.$statesubs[0];
			}
		}
	}
	elsif ($cmd eq "del") {
		if ($attrname eq 'statevals') {
			$hash->{statevals} = "devstate";
		}
	}

	return undef;
}

#####################################
# Set commands
#####################################

sub HMCCUCHN_Set ($@)
{
	my ($hash, @a) = @_;
	my $name = shift @a;
	my $opt = shift @a;

	my $rocmds = "clear config";
	
	return HMCCU_SetError ($hash, -3) if (!defined ($hash->{IODev}));
	return undef
		if ($hash->{statevals} eq 'readonly' && $opt ne '?' && $opt ne 'clear' && $opt ne 'config');

	my $disable = AttrVal ($name, "disable", 0);
	return undef if ($disable == 1);	

	my $hmccu_hash = $hash->{IODev};
	if (HMCCU_IsRPCStateBlocking ($hmccu_hash)) {
		return undef if ($opt eq '?');
		return "HMCCUCHN: CCU busy";
	}

	my $ccutype = $hash->{ccutype};
	my $ccuaddr = $hash->{ccuaddr};
	my $ccuif = $hash->{ccuif};
	my $statevals = AttrVal ($name, "statevals", '');
	my ($sc, $sd, $cc, $cd) = HMCCU_GetSpecialDatapoints ($hash, '', 'STATE', '', '');

	my $result = '';
	my $rc;

	if ($opt eq 'datapoint') {
		my $objname = shift @a;
		my $objvalue = shift @a;

		return HMCCU_SetError ($hash, "Usage: set $name datapoint {datapoint} {value}")
		   if (!defined ($objname) || !defined ($objvalue));
		return HMCCU_SetError ($hash, -8)
			if (!HMCCU_IsValidDatapoint ($hash, $ccutype, $ccuaddr, $objname, 2));
		   
		$objvalue =~ s/\\_/%20/g;
		$objvalue = HMCCU_Substitute ($objvalue, $statevals, 1, '');

		$objname = $ccuif.'.'.$ccuaddr.'.'.$objname;
		$rc = HMCCU_SetDatapoint ($hash, $objname, $objvalue);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);

		HMCCU_SetState ($hash, "OK");
		return undef;
	}
	elsif ($opt eq 'control') {
		return HMCCU_SetError ($hash, -14) if ($cd eq '');
		return HMCCU_SetError ($hash, -8) if (!HMCCU_IsValidDatapoint ($hash, $ccutype, $cc, $cd, 2));
		my $objvalue = shift @a;
		return HMCCU_SetError ($hash, "Usage: set $name control {value}") if (!defined ($objvalue));

		$objvalue =~ s/\\_/%20/g;
		$objvalue = HMCCU_Substitute ($objvalue, $statevals, 1, '');
		
		my $objname = $ccuif.'.'.$ccuaddr.'.'.$cd;
		$rc = HMCCU_SetDatapoint ($hash, $objname, $objvalue);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);
		
		HMCCU_SetState ($hash, "OK");
		return undef;
	}
	elsif ($opt =~ /^($hash->{statevals})$/) {
		my $cmd = $1;
		my $objvalue = ($cmd ne 'devstate') ? $cmd : shift @a;

		return HMCCU_SetError ($hash, -13) if ($sd eq '');		
		return HMCCU_SetError ($hash, -8)
			if (!HMCCU_IsValidDatapoint ($hash, $ccutype, $ccuaddr, $sd, 2));
		return HMCCU_SetError ($hash, "Usage: set $name devstate {value}") if (!defined ($objvalue));

		$objvalue =~ s/\\_/%20/g;
		$objvalue = HMCCU_Substitute ($objvalue, $statevals, 1, '');

		my $objname = $ccuif.'.'.$ccuaddr.'.'.$sd;

		$rc = HMCCU_SetDatapoint ($hash, $objname, $objvalue);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);

		HMCCU_SetState ($hash, "OK");
		return undef;
	}
	elsif ($opt eq 'toggle') {
		return HMCCU_SetError ($hash, -15) if ($statevals eq '' || !exists($hash->{statevals}));
		return HMCCU_SetError ($hash, -13) if ($sd eq '');	
		return HMCCU_SetError ($hash, -8)
			if (!HMCCU_IsValidDatapoint ($hash, $ccutype, $ccuaddr, $sd, 2));

		my $tstates = $hash->{statevals};
		$tstates =~ s/devstate\|//;
		my @states = split /\|/, $tstates;
		my $sc = scalar (@states);

		my $objname = $ccuif.'.'.$ccuaddr.'.'.$sd;
		($rc, $result) = HMCCU_GetDatapoint ($hash, $objname);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);

		my $objvalue = '';
		my $st = 0;
		while ($st < $sc) {
			if ($states[$st] eq $result) {
				$objvalue = ($st == $sc-1) ? $states[0] : $states[$st+1];
				last;
			}
			else {
				$st++;
			}
		}

		return HMCCU_SetError ($hash, "Current device state doesn't match statevals")
		   if ($objvalue eq '');

		$objvalue = HMCCU_Substitute ($objvalue, $statevals, 1, '');
		$rc = HMCCU_SetDatapoint ($hash, $objname, $objvalue);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);
		
		HMCCU_SetState ($hash, "OK");
		return undef;
	}
	elsif ($opt eq 'pct') {
		return HMCCU_SetError ($hash, "Can't find LEVEL datapoint for device type $ccutype")
		   if (!HMCCU_IsValidDatapoint ($hash, $ccutype, $ccuaddr, "LEVEL", 2));
		   
		my $objname = '';
		my $objvalue = shift @a;
		return HMCCU_SetError ($hash, "Usage: set $name pct {value} [{ontime} [{ramptime}]]")
			if (!defined ($objvalue));
		
		my $timespec = shift @a;
		my $ramptime = shift @a;

		# Set on time
		if (defined ($timespec)) {
			return HMCCU_SetError ($hash, "Can't find ON_TIME datapoint for device type $ccutype")
				if (!HMCCU_IsValidDatapoint ($hash, $ccutype, $ccuaddr, "ON_TIME", 2));
			if ($timespec =~ /^[0-9]{2}:[0-9]{2}/) {
				my (undef, $h, $m, $s)  = GetTimeSpec ($timespec);
				return HMCCU_SetError ($hash, "Wrong time format. Use HH:MM or HH:MM:SS")
					if (!defined ($h));
				$s += $h*3600+$m*60;
				my @lt = localtime;
				my $cs = $lt[2]*3600+$lt[1]*60+$lt[0];
				$s += 86400 if ($cs > $s);
				$timespec = $s-$cs;
			}
			if ($timespec > 0) {
				$objname = $ccuif.'.'.$ccuaddr.'.ON_TIME';
				$rc = HMCCU_SetDatapoint ($hash, $objname, $timespec);
				return HMCCU_SetError ($hash, $rc) if ($rc < 0);
			}
		}
		
		# Set ramp time
		if (defined ($ramptime)) {
			return HMCCU_SetError ($hash, "Can't find RAMP_TIME datapoint for device type $ccutype")
				if (!HMCCU_IsValidDatapoint ($hash, $ccutype, $ccuaddr, "RAMP_TIME", 2));
			$objname = $ccuif.'.'.$ccuaddr.'.RAMP_TIME';
			$rc = HMCCU_SetDatapoint ($hash, $objname, $ramptime);
			return HMCCU_SetError ($hash, $rc) if ($rc < 0);
		}

		# Set level	
		$objname = $ccuif.'.'.$ccuaddr.'.LEVEL';
		$rc = HMCCU_SetDatapoint ($hash, $objname, $objvalue);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);
		
		HMCCU_SetState ($hash, "OK");
		return undef;
	}
	elsif ($opt eq 'on-for-timer' || $opt eq 'on-till') {
		return HMCCU_SetError ($hash, -15) if ($statevals eq '' || !exists($hash->{statevals}));
		return HMCCU_SetError ($hash, "No state value for 'on' defined")
		   if ("on" !~ /($hash->{statevals})/);
		return HMCCU_SetError ($hash, -13) if ($sd eq '');
		return HMCCU_SetError ($hash, -8)
			if (!HMCCU_IsValidDatapoint ($hash, $ccutype, $ccuaddr, $sd, 2));
		return HMCCU_SetError ($hash, "Can't find ON_TIME datapoint for device type")
		   if (!HMCCU_IsValidDatapoint ($hash, $ccutype, $ccuaddr, "ON_TIME", 2));

		my $timespec = shift @a;
		return HMCCU_SetError ($hash, "Usage: set $name $opt {ontime-spec}")
			if (!defined ($timespec));
			
		if ($opt eq 'on-till') {
			my (undef, $h, $m, $s)  = GetTimeSpec ($timespec);
			return HMCCU_SetError ($hash, "Wrong time format. Use HH:MM or HH:MM:SS")
				if (!defined ($h));
			$s += $h*3600+$m*60;
			my @lt = localtime;
			my $cs = $lt[2]*3600+$lt[1]*60+$lt[0];
			$s += 86400 if ($cs > $s);
			$timespec = $s-$cs;
		}

		# Set time
		my $objname = $ccuif.'.'.$ccuaddr.'.ON_TIME';
		$rc = HMCCU_SetDatapoint ($hash, $objname, $timespec);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);
				
		# Set state
		$objname = $ccuif.'.'.$ccuaddr.'.'.$sd;
		my $objvalue = HMCCU_Substitute ("on", $statevals, 1, '');
		$rc = HMCCU_SetDatapoint ($hash, $objname, $objvalue);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);
		
		HMCCU_SetState ($hash, "OK");
		return undef;
	}
	elsif ($opt eq 'clear') {
		my $rnexp = shift @a;
		$rnexp = '.*' if (!defined ($rnexp));
		my @readlist = keys %{$hash->{READINGS}};
		foreach my $rd (@readlist) {
			delete ($hash->{READINGS}{$rd}) if ($rd ne 'state' && $rd ne 'control' && $rd =~ /$rnexp/);
		}
	}
	elsif ($opt eq 'config') {
		return HMCCU_SetError ($hash, "Usage: set $name config {parameter}={value} [...]") if (@a < 1);;

		my $rc = HMCCU_RPCSetConfig ($hash, $ccuaddr, \@a);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);
		HMCCU_SetState ($hash, "OK");
		return undef;
	}
	else {
		return "HMCCUCHN: Unknown argument $opt, choose one of ".$rocmds
			if ($hash->{statevals} eq 'readonly');

		my $retmsg = "HMCCUCHN: Unknown argument $opt, choose one of clear config datapoint devstate";
		if ($hash->{statevals} ne '') {
			my @cmdlist = split /\|/,$hash->{statevals};
			shift @cmdlist;
			$retmsg .= ':'.join(',',@cmdlist) if (@cmdlist > 0);
			foreach my $sv (@cmdlist) {
				$retmsg .= ' '.$sv.':noArg';
			}
			$retmsg .= " toggle:noArg";
			$retmsg .= " on-for-timer on-till"
				if (HMCCU_IsValidDatapoint ($hash, $hash->{ccutype}, $ccuaddr, "ON_TIME", 2));
			$retmsg .= " pct"
				if (HMCCU_IsValidDatapoint ($hash, $hash->{ccutype}, $ccuaddr, "LEVEL", 2));
		}

		return $retmsg;
	}
}

#####################################
# Get commands
#####################################

sub HMCCUCHN_Get ($@)
{
	my ($hash, @a) = @_;
	my $name = shift @a;
	my $opt = shift @a;

	return HMCCU_SetError ($hash, -3) if (!defined ($hash->{IODev}));

	my $disable = AttrVal ($name, "disable", 0);
	return undef if ($disable == 1);	

	my $hmccu_hash = $hash->{IODev};
	if (HMCCU_IsRPCStateBlocking ($hmccu_hash)) {
		return undef if ($opt eq '?');
		return "HMCCUCHN: CCU busy";
	}

	my $ccutype = $hash->{ccutype};
	my $ccuaddr = $hash->{ccuaddr};
	my $ccuif = $hash->{ccuif};
	my ($sc, $sd, $cc, $cd) = HMCCU_GetSpecialDatapoints ($hash, '', 'STATE', '', '');
	my $ccureadings = AttrVal ($name, "ccureadings", 1);

	my $result = '';
	my $rc;

	if ($opt eq 'devstate') {
		return HMCCU_SetError ($hash, -13) if ($sd eq '');
		return HMCCU_SetError ($hash, -8)
			if (!HMCCU_IsValidDatapoint ($hash, $ccutype, $ccuaddr, $sd, 1));

		my $objname = $ccuif.'.'.$ccuaddr.'.'.$sd;
		($rc, $result) = HMCCU_GetDatapoint ($hash, $objname);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);
		return $ccureadings ? undef : $result;
	}
	elsif ($opt eq 'datapoint') {
		my $objname = shift @a;
		
		return HMCCU_SetError ($hash, "Usage: get $name datapoint {datapoint}")
			if (!defined ($objname));		
		return HMCCU_SetError ($hash, -8)
			if (!HMCCU_IsValidDatapoint ($hash, $ccutype, $ccuaddr, $objname, 1));

		$objname = $ccuif.'.'.$ccuaddr.'.'.$objname;
		($rc, $result) = HMCCU_GetDatapoint ($hash, $objname);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);
		return $ccureadings ? undef : $result;
	}
	elsif ($opt eq 'update') {
		my $ccuget = shift @a;
		$ccuget = 'Attr' if (!defined ($ccuget));
		if ($ccuget !~ /^(Attr|State|Value)$/) {
			return HMCCU_SetError ($hash, "Usage: get $name update [{'State'|'Value'}]");
		}
		$rc = HMCCU_GetUpdate ($hash, $ccuaddr, $ccuget);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);
		return undef;
	}
	elsif ($opt eq 'config') {
		my $ccuobj = $ccuaddr;

		my ($rc, $res) = HMCCU_RPCGetConfig ($hash, $ccuobj, "getParamset");
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);
		return $ccureadings ? undef : $res;
	}
	elsif ($opt eq 'configdesc') {
		my $ccuobj = $ccuaddr;

		my ($rc, $res) = HMCCU_RPCGetConfig ($hash, $ccuobj, "getParamsetDescription");
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);
		return $res;
	}
	else {
		my $retmsg = "HMCCUCHN: Unknown argument $opt, choose one of devstate:noArg datapoint";
		
		my ($a, $c) = split(":", $hash->{ccuaddr});
		my @valuelist;
		my $valuecount = HMCCU_GetValidDatapoints ($hash, $hash->{ccutype}, $c, 1, \@valuelist);	
		$retmsg .= ":".join(",",@valuelist) if ($valuecount > 0);
		$retmsg .= " update:noArg config:noArg configdesc:noArg";
		
		return $retmsg;
	}
}

#####################################
# Set error status
#####################################

sub HMCCUCHN_SetError ($$)
{
	my ($hash, $text) = @_;
	my $name = $hash->{NAME};
	my $msg;
	my %errlist = (
		-1 => 'Channel name or address invalid',
		-2 => 'Execution of CCU script failed',
		-3 => 'Cannot detect IO device',
		-4 => 'Device deleted in CCU',
		-5 => 'No response from CCU',
		-6 => 'Update of readings disabled. Set attribute ccureadings first'
	);

	if (exists ($errlist{$text})) {
		$msg = $errlist{$text};
	}
	else {
		$msg = $text;
	}

	$msg = "HMCCUCHN: ".$name." ". $msg;
	readingsSingleUpdate ($hash, "state", "Error", 1);
	Log3 $name, 1, $msg;
	return $msg;
}

1;

=pod
=item device
=item summary controls HMCCU client devices for Homematic CCU2 - FHEM integration
=begin html

<a name="HMCCUCHN"></a>
<h3>HMCCUCHN</h3>
<ul>
   The module implements Homematic CCU channels as client devices for HMCCU. A HMCCU I/O device must
   exist before a client device can be defined. If a CCU channel is not found execute command
   'get devicelist' in I/O device.
   </br></br>
   <a name="HMCCUCHNdefine"></a>
   <b>Define</b><br/><br/>
   <ul>
      <code>define &lt;name&gt; HMCCUCHN {&lt;channel-name&gt; | &lt;channel-address&gt;}
      [readonly]</code>
      <br/><br/>
      If option 'readonly' is specified no set command will be available. Define command
      accepts a CCU2 channel name or channel address as parameter.
      <br/><br/>
      Examples:<br/>
      <code>define window_living HMCCUCHN WIN-LIV-1 readonly</code><br/>
      <code>define temp_control HMCCUCHN BidCos-RF.LEQ1234567:1</code>
      <br/><br/>
      The interface part of a channel address must not be specified. The default is 'BidCos-RF'.
      Channel addresses can be found with command 'get deviceinfo &lt;devicename&gt;' executed
      in I/O device.
   </ul>
   <br/>
   
   <a name="HMCCUCHNset"></a>
   <b>Set</b><br/><br/>
   <ul>
      <li><b>set &lt;name&gt; clear [&lt;reading-exp&gt;]</b><br/>
         Delete readings matching specified reading name expression. Default expression is '.*'.
         Readings 'state' and 'control' are not deleted.
      </li><br/>
      <li><b>set &lt;name&gt; config [&lt;rpcport&gt;] &lt;parameter&gt;=&lt;value&gt;] 
      [...]</b><br/>
        Set config parameters of CCU channel. This is equal to setting device parameters in CCU.
        Valid parameters can be listed by using command 'get configdesc'.
      </li>
      <li><b>set &lt;name&gt; datapoint &lt;datapoint&gt; &lt;value&gt;</b><br/>
        Set value of a datapoint of a CCU channel. If parameter <i>value</i> contains special
        character \_ it's substituted by blank.
        <br/><br/>
        Examples:<br/>
        <code>set temp_control datapoint SET_TEMPERATURE 21</code>
      </li><br/>
      <li><b>set &lt;name&gt; devstate &lt;value&gt;</b><br/>
         Set state of a CCU device channel. The state datapoint of a channel must be defined
         by setting attribute 'statedatapoint' to a valid datapoint name.
         <br/><br/>
         Example:<br/>
         <code>set light_entrance devstate true</code>
      </li><br/>
      <li><b>set &lt;name&gt; &lt;statevalue&gt;</b><br/>
         Set state of a CCU device channel to <i>StateValue</i>. The state datapoint of a channel
         must be defined by setting attribute 'statedatapoint'. The available state values must
         be defined by setting attribute 'statevals'.
         <br/><br/>
         Example: Turn switch on<br/>
         <code>
         attr myswitch statedatapoint STATE<br/>
         attr myswitch statevals on:true,off:false<br/>
         set myswitch on
         </code>
      </li><br/>
      <li><b>set &lt;name&gt; toggle</b><br/>
        Toggle state datapoint between values defined by attribute 'statevals'. This command is
        only available if attribute 'statevals' is set. Toggling supports more than two state
        values.
        <br/><br/>
        Example: Toggle blind actor<br/>
        <code>
        attr myswitch statedatapoint LEVEL<br/>
        attr myswitch statevals up:100,down:0<br/>
        set myswitch toggle
        </code>
      </li><br/>
      <li><b>set &lt;name&gt; on-for-timer &lt;ontime&gt;</b><br/>
         Switch device on for specified number of seconds. This command is only available if
         channel contains a datapoint ON_TIME. The attribute 'statevals' must contain at least a
         value for 'on'. The attribute 'statedatapoint' must be set to a writeable datapoint.
         <br/><br/>
         Example: Turn switch on for 300 seconds<br/>
         <code>
         attr myswitch statedatapoint STATE<br/>
         attr myswitch statevals on:true,off:false<br/>
         set myswitch on-for-timer 300
         </code>
      </li><br/>
      <li><b>set &lt;name&gt; on-till &lt;timestamp&gt;</b><br/>
         Switch device on until <i>timestamp</i>. Parameter <i>timestamp</i> can be a time in
         format HH:MM or HH:MM:SS. This command is only available if channel contains a datapoint
         ON_TIME. The attribute 'statevals' must contain at least a value for 'on'. The Attribute
         'statedatapoint' must be set to a writeable datapoint.
      </li><br/>
      <li><b>set &lt;name&gt; pct &lt;value&gt; [&lt;ontime&gt; [&lt;ramptime&gt;]]</b><br/>
         Set datapoint LEVEL of a channel to the specified <i>value</i>. Optionally a <i>ontime</i>
         and a <i>ramptime</i> (both in seconds) can be specified. This command is only available
         if channel contains at least a datapoint LEVEL and optionally datapoints ON_TIME and
         RAMP_TIME. The parameter <i>ontime</i> can be specified in seconds or as timestamp in
         format HH:MM or HH:MM:SS. If <i>ontime</i> is 0 it's ignored. This syntax can be used to
         modify the ramp time only.
         <br/><br/>
         Example: Turn dimmer on for 600 second. Increase light to 100% over 10 seconds<br>
         <code>
         attr myswitch statedatapoint LEVEL<br/>
         attr myswitch statevals on:100,off:0<br/>
         set myswitch pct 100 600 10
         </code>
      </li><br/>
   </ul>
   <br/>
   
   <a name="HMCCUCHNget"></a>
   <b>Get</b><br/><br/>
   <ul>
      <li><b>get &lt;name&gt; config</b><br/>
         Get configuration parameters of CCU channel. If attribute 'ccureadings' is 0 results
         are displayed in browser window.
      </li><br/>
      <li><b>get &lt;name&gt; configdesc</b><br/>
         Get description of configuration parameters of CCU channel.
      </li><br/>
      <li><b>get &lt;name&gt; devstate</b><br/>
         Get state of CCU device. Default datapoint STATE can be changed by setting
         attribute 'statedatapoint'. Command will fail if state datapoint does not exist in
         channel.
      </li><br/>
      <li><b>get &lt;name&gt; datapoint &lt;datapoint&gt;</b><br/>
         Get value of a CCU channel datapoint.
      </li><br/>
      <li><b>get &lt;name&gt; update [{State | <u>Value</u>}]</b><br/>
         Update all datapoints / readings of channel. With option 'State' the device is queried.
         This request method is more accurate but slower then 'Value'.
      </li>
   </ul>
   <br/>
   
   <a name="HMCCUCHNattr"></a>
   <b>Attributes</b><br/><br/>
   <ul>
      To reduce the amount of events it's recommended to set attribute 'event-on-change-reading'
      to '.*'.
      <br/><br/>
      <li><b>ccuackstate {<u>0</u> | 1}</b><br/>
         If set to 1 state will be set to result of command (i.e. 'OK'). Otherwise state is only
         updated if value of state datapoint has changed.
      </li><br/>
      <li><b>ccuflags {nochn0, trace}</b><br/>
      	Control behaviour of device:<br/>
      	nochn0: Prevent update of status channel 0 datapoints / readings.<br/>
      	trace: Write log file information for operations related to this device.
      </li><br/>
      <li><b>ccuget {State | <u>Value</u>}</b><br/>
         Set read access method for CCU channel datapoints. Method 'State' is slower than 'Value'
         because each request is sent to the device. With method 'Value' only CCU is queried.
         Default is 'Value'.
      </li><br/>
      <li><b>ccureadings {0 | <u>1</u>}</b><br/>
         If set to 1 values read from CCU will be stored as readings. Default is 1.
      </li><br/>
      <li><b>ccureadingfilter &lt;filter-rule[,...]&gt;</b><br/>
         Only datapoints matching specified expression are stored as readings.<br/>
         Syntax for <i>filter-rule</i> is: [&lt;channel-name&gt;!]&lt;RegExp&gt;<br/>
         If <i>channel-name</i> is specified the following rule applies only to this channel.
      </li><br/>
      <li><b>ccureadingformat {address[lc] | name[lc] | datapoint[lc]}</b><br/>
         Set format of reading names. Default is 'name'. If set to 'address' format of reading names
         is channel-address.datapoint. If set to 'name' format of reading names is
         channel-name.datapoint. If set to 'datapoint' format is channel-number.datapoint. With
         suffix 'lc' reading names are converted to lowercase.
      </li><br/>
      <li><b>ccureadingname &lt;old-readingname-expr&gt;:&lt;new-readingname&gt;[,...]</b><br/>
         Set alternative reading names.
      </li><br/>
      <li><b>ccuscaleval &lt;datapoint&gt;:&lt;factor&gt;[,...]</b><br/>
      ccuscaleval &lt;[!]datapoint&gt;:&lt;min&gt;:&lt;max&gt;:&lt;minn&gt;:&lt;maxn&gt;[,...]<br/>
         Scale, spread, shift and optionally reverse values before executing set datapoint commands
         or after executing get datapoint commands / before storing values in readings.<br/>
         If first syntax is used during get the value read from CCU is devided by <i>factor</i>.
         During set the value is multiplied by factor.<br/>
         With second syntax one must specify the interval in CCU (<i>min,max</i>) and the interval
         in FHEM (<i>minn, maxn</i>). The scaling factor is calculated automatically. If parameter
         <i>datapoint</i> starts with a '!' the resulting value is reversed.
         <br/><br/>
         Example: Scale values of datapoint LEVEL for blind actor and reverse values<br/>
         <code>
         attr myblind ccuscale !LEVEL:0:1:0:100
         </code>
      </li><br/>
      <li><b>ccuverify {<u>0</u> | 1 | 2}</b><br/>
         If set to 1 a datapoint is read for verification after set operation. If set to 2 the
         corresponding reading will be set to the new value directly after setting a datapoint
         in CCU without any verification.
      </li><br/>
      <li><b>controldatapoint &lt;datapoint&gt;</b><br/>
         Set datapoint for device control. Can be use to realize user defined control elements for
         setting control datapoint. For example if datapoint of thermostat control is 
         SET_TEMPERATURE one can define a slider for setting the destination temperature with
         following attributes:<br/><br/>
         attr mydev controldatapoint SET_TEMPERATURE
         attr mydev webCmd control
         attr mydev widgetOverride control:slider,10,1,25
      </li><br/>
      <li><b>disable {<u>0</u> | 1}</b><br/>
      	Disable client device.
      </li><br/>
      <li><b>statedatapoint &lt;datapoint&gt;</b><br/>
         Set state datapoint used by some commands like 'set devstate'.
      </li><br/>
      <li><b>statevals &lt;text&gt;:&lt;text&gt;[,...]</b><br/>
         Define substitution for values of set commands. The parameters <i>text</i> are available
         as set commands.
         <br/><br/>
         Example:<br/>
         <code>
         attr my_switch statevals on:true,off:false<br/>
         set my_switch on
         </code>
      </li><br/>
      <li><b>stripnumber {<u>0</u> | 1 | 2 | -n}</b><br/>
      	Remove trailing digits or zeroes from floating point numbers and/or round floating
      	point numbers. If attribute is negative (-0 is valid) floating point values are rounded
      	to the specified number of digits before they are stored in readings. The meaning of
      	values 0-2 is:<br/>
      	0 = Floating point numbers are stored as read from CCU (i.e. with trailing zeros)<br/>
      	1 = Trailing zeros are stripped from floating point numbers except one digit.<br/>
   		2 = All trailing zeros are stripped from floating point numbers.
      </li><br/>
      <li><b>substitude &lt;subst-rule&gt;[;...]</b><br/>
         Define substitions for reading values. Syntax of <i>subst-rule</i> is<br/><br/>
         [datapoint!]&lt;regexp1&gt;:&lt;text1&gt;[,...]
      </li>
   </ul>
</ul>

=end html
=cut

