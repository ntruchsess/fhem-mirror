################################################################
#
#  88_HMCCUDEV.pm
#
#  $Id:$
#
#  Version 2.5
#
#  (c) 2015 zap (zap01 <at> t-online <dot> de)
#
################################################################
#
#  define <name> HMCCUDEV <ccudev> [readonly]
#
#  set <name> datapoint <channel>.<datapoint> <value>
#  set <name> devstate <value>
#  set <name> <stateval_cmds>
#  set <name> config [<channel>] <parameter>=<value> [...]
#
#  get <name> devstate
#  get <name> datapoint <channel>.<datapoint>
#  get <name> channel <channel>[.<datapoint-expr>]
#  get <name> config [<channel>]
#  get <name> configdesc [<channel>]
#  get <name> update
#
#  attr <name> ccureadings { 0 | 1 }
#  attr <name> ccureadingformat { address | name }
#  attr <name> ccureadingfilter <regexp>
#  attr <name> statechannel <channel>
#  attr <name> statedatapoint <datapoint>
#  attr <name> statevals <text1>:<subtext1>[,...]
#  attr <name> substitute <regexp1>:<subtext1>[,...]
#
################################################################
#  Requires module 88_HMCCU
################################################################

package main;

use strict;
use warnings;
use SetExtensions;
# use Data::Dumper;

use Time::HiRes qw( gettimeofday usleep );

sub HMCCUDEV_Define ($@);
sub HMCCUDEV_Set ($@);
sub HMCCUDEV_Get ($@);
sub HMCCUDEV_Attr ($@);
sub HMCCUDEV_SetError ($$);

#####################################
# Initialize module
#####################################

sub HMCCUDEV_Initialize ($)
{
	my ($hash) = @_;

	$hash->{DefFn} = "HMCCUDEV_Define";
	$hash->{SetFn} = "HMCCUDEV_Set";
	$hash->{GetFn} = "HMCCUDEV_Get";
	$hash->{AttrFn} = "HMCCUDEV_Attr";

	$hash->{AttrList} = "IODev ccureadingfilter ccureadingformat:name,address ccureadings:0,1 ccustate ccuget:State,Value statevals substitute statechannel statedatapoint controldatapoint stripnumber:0,1,2 loglevel:0,1,2,3,4,5,6 ". $readingFnAttributes;
}

#####################################
# Define device
#####################################

sub HMCCUDEV_Define ($@)
{
	my ($hash, $def) = @_;
	my $name = $hash->{NAME};
	my @a = split("[ \t][ \t]*", $def);

	my $usage = "Usage: define <name> HMCCUDEV {<device-name>|<device-address>} [<state-channel>] [readonly]";
	return $usage if (@a < 3);

	my $devname = shift @a;
	my $devtype = shift @a;
	my $devspec = shift @a;

	return "Invalid or unknown CCU device name or address" if (! HMCCU_IsValidDevice ($devspec));

	if ($devspec =~ /^(.+)\.([A-Z]{3,3}[0-9]{7,7})$/) {
		# CCU Device address with interface
		$hash->{ccuif} = $1;
		$hash->{ccuaddr} = $2;
		$hash->{ccuname} = HMCCU_GetDeviceName ($hash->{ccuaddr}, '');
	}
	elsif ($devspec =~ /^[A-Z]{3,3}[0-9]{7,7}$/) {
		# CCU Device address without interface
		$hash->{ccuaddr} = $devspec;
		$hash->{ccuname} = HMCCU_GetDeviceName ($devspec, '');
		$hash->{ccuif} = HMCCU_GetDeviceInterface ($hash->{ccuaddr}, 'BidCos-RF');
	}
	else {
		# CCU Device name
		$hash->{ccuname} = $devspec;
		my ($add, $chn) = HMCCU_GetAddress ($devspec, '', '');
		return "Name is a channel name" if ($chn ne '');
		$hash->{ccuaddr} = $add;
		$hash->{ccuif} = HMCCU_GetDeviceInterface ($hash->{ccuaddr}, 'BidCos-RF');
	}

	return "CCU device address not found for $devspec" if ($hash->{ccuaddr} eq '');
	return "CCU device name not found for $devspec" if ($hash->{ccuname} eq '');

	$hash->{ccutype} = HMCCU_GetDeviceType ($hash->{ccuaddr}, '');
	$hash->{channels} = HMCCU_GetDeviceChannels ($hash->{ccuaddr});
	$hash->{statevals} = 'devstate';

	my $n = 0;
	my $arg = shift @a;
	while (defined ($arg)) {
		return $usage if ($n == 2);
		if ($arg eq 'readonly') {
			$hash->{statevals} = $arg;
			$n++;
		}
		elsif ($arg =~ /^[0-9]+$/) {
			$attr{$name}{statechannel} = $arg;
			$n++;
		}
		else {
			return $usage;
		}
		$arg = shift @a;
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

sub HMCCUDEV_Attr ($@)
{
	my ($cmd, $name, $attrname, $attrval) = @_;
	my $hash = $defs{$name};

	if ($cmd eq "set") {
		return "Missing attribute value" if (!defined ($attrval));
		if ($attrname eq 'IODev') {
			$hash->{IODev} = $defs{$attrval};
		}
		elsif ($attrname eq "statevals") {
			return "Device is read only" if ($hash->{statevals} eq 'readonly');
			$hash->{statevals} = 'devstate';
			my @states = split /,/,$attrval;
			foreach my $st (@states) {
				my @statesubs = split /:/,$st;
				return "value := text:substext[,...]" if (@statesubs != 2);
				$hash->{statevals} .= '|'.$statesubs[0];
			}
		}
	}
	elsif ($cmd eq "del") {
		if ($attrname eq "statevals") {
			$hash->{statevals} = "devstate";
		}
	}

	return undef;
}

#####################################
# Set commands
#####################################

sub HMCCUDEV_Set ($@)
{
	my ($hash, @a) = @_;
	my $name = shift @a;
	my $opt = shift @a;

	if (!exists ($hash->{IODev})) {
		return HMCCUDEV_SetError ($hash, "No IO device defined");
	}
	if ($hash->{statevals} eq 'readonly') {
		return undef;
	}

	my $statechannel = AttrVal ($name, "statechannel", '');
	my $statedatapoint = AttrVal ($name, "statedatapoint", 'STATE');
	my $statevals = AttrVal ($name, "statevals", '');
	my $controldatapoint = AttrVal ($name, "controldatapoint", '');

	my $hmccu_hash = $hash->{IODev};
	my $hmccu_name = $hash->{IODev}->{NAME};

	my $result = '';
	my $rc;

	if ($opt eq 'datapoint') {
		my $objname = shift @a;
		my $objvalue = join ('%20', @a);

		if (!defined ($objname) || $objname !~ /^[0-9]+\..+$/ || !defined ($objvalue)) {
			return HMCCUDEV_SetError ($hash, "Usage: set <name> datapoint <channel-number>.<datapoint> <value> [...]");
		}
		$objvalue = HMCCU_Substitute ($objvalue, $statevals, 1, '');

		# Build datapoint address
		$objname = $hash->{ccuif}.'.'.$hash->{ccuaddr}.':'.$objname;

		$rc = HMCCU_SetDatapoint ($hash, $objname, $objvalue);
		return HMCCUDEV_SetError ($hash, $rc) if ($rc < 0);

		usleep (100000);
		($rc, $result) = HMCCU_GetDatapoint ($hash, $objname);
		return HMCCUDEV_SetError ($hash, $rc) if ($rc < 0);

		HMCCU_SetState ($hash, "OK");
		return undef;
	}
	elsif ($opt eq 'control') {
		return HMCCUDEV_SetError ($hash, "Attribute control datapoint not set") if ($controldatapoint eq '');
		my $objvalue = shift @a;
		my $objname = $hash->{ccuif}.'.'.$hash->{ccuaddr}.':'.$controldatapoint;
		$rc = HMCCU_SetDatapoint ($hash, $objname, $objvalue);
		return HMCCUDEV_SetError ($hash, $rc) if ($rc < 0);

		HMCCU_SetState ($hash, "OK");
		return undef;
	}
	elsif ($opt =~ /^($hash->{statevals})$/) {
		my $cmd = $1;
		my $objvalue = ($cmd ne 'devstate') ? $cmd : join ('%20', @a);

		return HMCCUDEV_SetError ($hash, "No state channel specified") if ($statechannel eq '');
		return HMCCUDEV_SetError ($hash, "Usage: set <name> devstate <value> [...]") if (!defined ($objvalue));

		$objvalue = HMCCU_Substitute ($objvalue, $statevals, 1, '');

		# Build datapoint address
		my $objname = $hash->{ccuif}.'.'.$hash->{ccuaddr}.':'.$statechannel.'.'.$statedatapoint;

		$rc = HMCCU_SetDatapoint ($hash, $objname, $objvalue);
		return HMCCUDEV_SetError ($hash, $rc) if ($rc < 0);

		usleep (100000);
		($rc, $result) = HMCCU_GetDatapoint ($hash, $objname);
		return HMCCUDEV_SetError ($hash, $rc) if ($rc < 0);

		HMCCU_SetState ($hash, "OK");
		return undef;
	}
	elsif ($opt eq 'config') {
		return HMCCUDEV_SetError ($hash, "Usage: set $name config [{channel-number}] {parameter}={value} [...]") if (@a < 1);;
		my $objname = $hash->{ccuaddr};
		$objname .= ':'.shift @a if ($a[0] =~ /^[0-9]+$/);

		my $rc = HMCCU_RPCSetConfig ($hash, $objname, \@a);
		return HMCCUDEV_SetError ($hash, $rc) if ($rc < 0);

		HMCCU_SetState ($hash, "OK");
		return undef;
	}
	else {
		my $retmsg = "HMCCUDEV: Unknown argument $opt, choose one of config control datapoint";
		return undef if ($hash->{statevals} eq 'readonly');

		if ($statechannel ne '') {
			$retmsg .= " devstate";
			if ($hash->{statevals} ne '') {
				my @cmdlist = split /\|/,$hash->{statevals};
				shift @cmdlist;
				$retmsg .= ':'.join(',',@cmdlist);
				foreach my $sv (@cmdlist) {
					$retmsg .= ' '.$sv.':noArg';
				}
			}
		}

		return $retmsg;
	}
}

#####################################
# Get commands
#####################################

sub HMCCUDEV_Get ($@)
{
	my ($hash, @a) = @_;
	my $name = shift @a;
	my $opt = shift @a;

	if (!defined ($hash->{IODev})) {
		return HMCCUDEV_SetError ($hash, "No IO device defined");
	}

	my $statechannel = AttrVal ($name, 'statechannel', '');
	my $statedatapoint = AttrVal ($name, 'statedatapoint', 'STATE');
	my $ccureadings = AttrVal ($name, 'ccureadings', 1);

	my $result = '';
	my $rc;

	if ($opt eq 'devstate') {
		if ($statechannel eq '') {
			return HMCCUDEV_SetError ($hash, "No state channel specified");
		}

		my $objname = $hash->{ccuif}.'.'.$hash->{ccuaddr}.':'.$statechannel.'.'.$statedatapoint;
		($rc, $result) = HMCCU_GetDatapoint ($hash, $objname);

		return HMCCUDEV_SetError ($hash, $rc) if ($rc < 0);
		return $ccureadings ? undef : $result;
	}
	elsif ($opt eq 'datapoint') {
		my $objname = shift @a;
		if (!defined ($objname) || $objname !~ /^[0-9]+\..*$/) {
			return HMCCUDEV_SetError ($hash, "Usage: get <name> datapoint <channel-number>.<datapoint>");
		}

		$objname = $hash->{ccuif}.'.'.$hash->{ccuaddr}.':'.$objname;
		($rc, $result) = HMCCU_GetDatapoint ($hash, $objname);

		return HMCCUDEV_SetError ($hash, $rc) if ($rc < 0);

		HMCCU_SetState ($hash, "OK") if (exists ($hash->{STATE}) && $hash->{STATE} eq "Error");
		return $ccureadings ? undef : $result;
	}
	elsif ($opt eq 'channel') {
		my @chnlist;
		foreach my $objname (@a) {
			last if (!defined ($objname));
			if ($objname =~ /^([0-9]+)/ && exists ($hash->{channels})) {
				return HMCCUDEV_SetError ($hash, "Invalid channel number: $objname") if ($1 >= $hash->{channels});
			}
			else {
				return HMCCUDEV_SetError ($hash, "Invalid channel number: $objname");
			}
			if ($objname =~ /^[0-9]{1,2}.*=/) {
				$objname =~ s/=/ /;
			}
			push (@chnlist, $hash->{ccuif}.'.'.$hash->{ccuaddr}.':'.$objname);
		}
		if (@chnlist == 0) {
			return HMCCUDEV_SetError ($hash, "Usage: get $name channel {channel-number}[.{datapoint-expr}] [...]");
		}

		($rc, $result) = HMCCU_GetChannel ($hash, \@chnlist);
		return HMCCUDEV_SetError ($hash, $rc) if ($rc < 0);

		HMCCU_SetState ($hash, "OK") if (exists ($hash->{STATE}) && $hash->{STATE} eq "Error");
		return $ccureadings ? undef : $result;
	}
	elsif ($opt eq 'update') {
		my $ccuget = shift @a;
		$ccuget = 'Attr' if (!defined ($ccuget));
		if ($ccuget !~ /^(Attr|State|Value)$/) {
			return HMCCUDEV_SetError ($hash, "Usage: get $name update [{'State'|'Value'}]");
		}
		$rc = HMCCU_GetUpdate ($hash, $hash->{ccuaddr}, $ccuget);
		return HMCCUDEV_SetError ($hash, $rc) if ($rc < 0);

		return undef;
	}
	elsif ($opt eq 'deviceinfo') {
		my $ccuget = shift @a;
		$ccuget = 'Attr' if (!defined ($ccuget));
		if ($ccuget !~ /^(Attr|State|Value)$/) {
			return HMCCUDEV_SetError ($hash, "Usage: get $name deviceinfo [{'State'|'Value'}]");
		}
		$result = HMCCU_GetDeviceInfo ($hash, $hash->{ccuaddr}, $ccuget);
		return HMCCUDEV_SetError ($hash, -2) if ($result eq '');
		return $result;
	}
	elsif ($opt eq 'config') {
		my $channel = shift @a;
		my $ccuobj = $hash->{ccuaddr};
		$ccuobj .= ':'.$channel if (defined ($channel));

                my ($rc, $res) = HMCCU_RPCGetConfig ($hash, $ccuobj, "getParamset");
                return HMCCUDEV_SetError ($hash, $rc) if ($rc < 0);
		HMCCU_SetState ($hash, "OK") if (exists ($hash->{STATE}) && $hash->{STATE} eq "Error");
                return $ccureadings ? undef : $result;
	}
	elsif ($opt eq 'configdesc') {
		my $channel = shift @a;
		my $ccuobj = $hash->{ccuaddr};
		$ccuobj .= ':'.$channel if (defined ($channel));

                my ($rc, $res) = HMCCU_RPCGetConfig ($hash, $ccuobj, "getParamsetDescription");
                return HMCCUDEV_SetError ($hash, $rc) if ($rc < 0);
		HMCCU_SetState ($hash, "OK") if (exists ($hash->{STATE}) && $hash->{STATE} eq "Error");
                return $res;
	}
	else {
		my $retmsg = "HMCCUDEV: Unknown argument $opt, choose one of datapoint channel update:noArg config configdesc deviceinfo:noArg";
		if ($statechannel ne '') {
			$retmsg .= ' devstate:noArg';
		}
		return $retmsg;
	}
}

#####################################
# Set error status
#####################################

sub HMCCUDEV_SetError ($$)
{
	my ($hash, $text) = @_;
	my $name = $hash->{NAME};
        my $msg;
        my %errlist = (
           -1 => 'Channel name or address invalid',
           -2 => 'Execution of CCU script failed',
           -3 => 'Cannot detect IO device',
	   -4 => 'Device deleted in CCU'
        );

        if (exists ($errlist{$text})) {
                $msg = $errlist{$text};
        }
        else {
                $msg = $text;
        }

	$msg = "HMCCUDEV: ".$name." ". $msg;
	readingsSingleUpdate ($hash, "state", "Error", 1);
	Log 1, $msg;
	return $msg;
}

1;

=pod
=begin html

<a name="HMCCUDEV"></a>
<h3>HMCCUDEV</h3>
<div style="width:800px"> 
<ul>
   The module implements client devices for HMCCU. A HMCCU device must exist
   before a client device can be defined.
   </br></br>
   <a name="HMCCUDEVdefine"></a>
   <b>Define</b>
   <ul>
      <br/>
      <code>define &lt;name&gt; HMCCUDEV {&lt;device-name&gt;|&lt;device-address&gt;} [&lt;statechannel&gt;] [readonly]</code>
      <br/><br/>
      If <i>readonly</i> parameter is specified no set command will be available.
      <br/><br/>
      Examples:<br/>
      <code>define window_living HMCCUDEV WIN-LIV-1 readonly</code><br/>
      <code>define temp_control HMCCUDEV BidCos-RF.LEQ1234567 1</code>
      <br/>
   </ul>
   <br/>
   
   <a name="HMCCUDEVset"></a>
   <b>Set</b><br/>
   <ul>
      <br/>
      <li>set &lt;name&gt; devstate &lt;value&gt; [...]
         <br/>
         Set state of a CCU device channel. Channel must be defined as attribute
         'statechannel'. Default datapoint can be modfied by setting attribute
         'statedatapoint'.
         <br/><br/>
         Example:<br/>
         <code>set light_entrance devstate on</code>
      </li><br/>
      <li>set &lt;name&gt; &lt;statevalue&gt;
         <br/>
         State of a CCU device channel is set to <i>statevalue</i>. Channel must
         be defined as attribute 'statechannel'. Default datapoint STATE can be
         modified by setting attribute 'statedatapoint'. Values for <i>statevalue</i>
         are defined by setting attribute 'statevals'.
         <br/><br/>
         Example:<br/>
         <code>
         attr myswitch statechannel 1<br/>
         attr myswitch statevals on:true,off:false<br/>
         set myswitch on
         </code>
      </li><br/>
      <li>set &lt;name&gt; datapoint &lt;channel-number&gt;.&lt;datapoint&gt; &lt;value&gt; [...]
        <br/>
        Set value of a datapoint of a CCU device channel.
        <br/><br/>
        Example:<br/>
        <code>set temp_control datapoint 1.SET_TEMPERATURE 21</code>
      </li><br/>
      <li>set &lt;name&gt; config [&lt;channel-number&gt;] &lt;parameter&gt;=&lt;value&gt; [...]
        <br/>
        Set configuration parameter of CCU device or channel.
      </li>
   </ul>
   <br/>
   
   <a name="HMCCUDEVget"></a>
   <b>Get</b><br/>
   <ul>
      <br/>
      <li>get &lt;name&gt; devstate
         <br/>
         Get state of CCU device. Attribute 'statechannel' must be set.
      </li><br/>
      <li>get &lt;name&gt; datapoint &lt;channel-number&gt;.&lt;datapoint&gt;
         <br/>
         Get value of a CCU device datapoint.
      </li><br/>
      <li>get &lt;name&gt; config
         <br/>
         Get configuration parameters of CCU device.
      </li><br/>
      <li>get &lt;name&gt; configdesc
         <br/>
         Get description of configuration parameters for CCU device.
      </li><br/>
      <li>get &lt;name&gt; update [{'State'|'Value'}]<br/>
         Update datapoints / readings of device.
      </li><br/>
      <li>get &lt;name&gt; deviceinfo [{'State'|'Value'}]<br/>
         Display all channels and datapoints of device.
      </li>
   </ul>
   <br/>
   
   <a name="HMCCUDEVattr"></a>
   <b>Attributes</b><br/>
   <br/>
   <ul>
      <li>ccuget &lt;State | <u>Value</u>&gt;<br/>
         Set read access method for CCU channel datapoints. Method 'State' is slower than 'Value' because
         each request is sent to the device. With method 'Value' only CCU is queried. Default is 'Value'.
      </li><br/>
      <li>ccureadings &lt;0 | <u>1</u>&gt;<br/>
         If set to 1 values read from CCU will be stored as readings. Default is 1.
      </li><br/>
      <li>ccureadingfilter &lt;datapoint-expr&gt;
         <br/>
            Only datapoints matching specified expression are stored as
            readings.
      </li><br/>
      <li>ccureadingformat &lt;address | name&gt;
         <br/>
            Set format of readings. Default is 'name'.
      </li><br/>
      <li>statechannel &lt;channel-number&gt;
         <br/>
            Channel for setting device state by devstate command.
      </li><br/>
      <li>statedatapoint &lt;datapoint&gt;
         <br/>
            Datapoint for setting device state by devstate command.
      </li><br/>
      <li>statevals &lt;text&gt;:&lt;text&gt;[,...]
         <br/>
            Define substitution for set commands values. The parameters &lt;text&gt;
            are available as set commands. Example:<br/>
            <code>attr my_switch statevals on:true,off:false</code><br/>
            <code>set my_switch on</code>
      </li><br/>
      <li>substitude &lt;subst-rule&gt;[;...]
         <br/>
            Define substitions for reading values. Substitutions for parfile values must
            be specified in parfiles. Syntax of subst-rule is<br/><br/>
            [datapoint!]&lt;regexp1&gt;:&lt;text1&gt;[,...]
      </li><br/>
   </ul>
</ul>
</div>

=end html
=cut

