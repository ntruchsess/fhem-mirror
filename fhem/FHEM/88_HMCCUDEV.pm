#####################################################################
#
#  88_HMCCUDEV.pm
#
#  $Id$
#
#  Version 3.4
#
#  (c) 2016 zap (zap01 <at> t-online <dot> de)
#
#####################################################################
#
#  define <name> HMCCUDEV {<ccudev>|virtual} [<statechannel>] [readonly] [defaults]
#     [{group={<device>|<channel>}[,...]|groupexp=<regexp>}]
#
#  set <name> clear [<regexp>]
#  set <name> config [<channel-number>] <parameter>=<value> [...]
#  set <name> control <value>
#  set <name> datapoint [<channel-number>.]<datapoint> <value>
#  set <name> defaults
#  set <name> devstate <value>
#  set <name> on-till <timestamp>
#  set <name> on-for-timer <ontime>
#  set <name> pct <level> [{<ontime>|0} [<ramptime>]]
#  set <name> <stateval_cmds>
#  set <name> toggle
#
#  get <name> devstate
#  get <name> datapoint [<channel-number>.]<datapoint>
#  get <name> defaults
#  get <name> config [<channel-number>]
#  get <name> configdesc [<channel-number>]
#  get <name> update
#
#  attr <name> ccuackstate { 0 | 1 }
#  attr <name> ccuflags { nochn0, trace }
#  attr <name> ccuget { State | Value }
#  attr <name> ccureadings { 0 | 1 }
#  attr <name> ccureadingformat { address[lc] | name[lc] | datapoint[lc] }
#  attr <name> ccureadingfilter <filter-rule>[,...]
#  attr <name> ccureadingname <oldname>:<newname>[,...]
#  attr <name> ccuscaleval <datapoint>:<factor>[:<min>:<max>][,...]
#  attr <name> ccuverify { 0 | 1 | 2}
#  attr <name> controldatapoint <channel-number>.<datapoint>
#  attr <name> disable { 0 | 1 }
#  attr <name> statechannel <channel>
#  attr <name> statedatapoint [<channel-number>.]<datapoint>
#  attr <name> statevals <text1>:<subtext1>[,...]
#  attr <name> substitute <regexp1>:<subtext1>[,...]
#
#####################################################################
#  Requires module 88_HMCCU
#####################################################################

package main;

use strict;
use warnings;
use SetExtensions;
# use Data::Dumper;

# use Time::HiRes qw( gettimeofday usleep );

sub HMCCUDEV_Define ($@);
sub HMCCUDEV_Set ($@);
sub HMCCUDEV_Get ($@);
sub HMCCUDEV_Attr ($@);

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

	$hash->{AttrList} = "IODev ccuackstate:0,1 ccuflags:multiple-strict,nochn0,trace ccureadingfilter:textField-long ccureadingformat:name,namelc,address,addresslc,datapoint,datapointlc ccureadingname ccureadings:0,1 ccuget:State,Value ccuscaleval ccuverify:0,1,2 disable:0,1 statevals substitute statechannel statedatapoint controldatapoint stripnumber ". $readingFnAttributes;
}

#####################################
# Define device
#####################################

sub HMCCUDEV_Define ($@)
{
	my ($hash, $def) = @_;
	my $name = $hash->{NAME};
	my @a = split("[ \t][ \t]*", $def);

	my $usage = "Usage: define $name HMCCUDEV {device|'virtual'} [state-channel] ['readonly'] ['defaults'] [{groupexp=regexp|group={device|channel}[,...]]";
	return $usage if (@a < 3);

	my $devname = shift @a;
	my $devtype = shift @a;
	my $devspec = shift @a;

	my $hmccu_hash = undef;

	if ($devspec ne 'virtual') {
		return "Invalid or unknown CCU device name or address" if (!HMCCU_IsValidDevice ($devspec));
	}
	
	if ($devspec eq 'virtual') {
		# Virtual device FHEM only
		my $no = 0;
		foreach my $d (sort keys %defs) {
			my $ch = $defs{$d};
			$hmccu_hash = $ch if ($ch->{TYPE} eq 'HMCCU' && !defined ($hmccu_hash));
			next if ($ch->{TYPE} ne 'HMCCUDEV');
			next if ($d eq $name);
			next if ($ch->{ccuif} ne 'VirtualDevices' || $ch->{ccuname} ne 'none');
			$no++;
		}
		return "No IO device found" if (!defined ($hmccu_hash));
		$hash->{ccuif} = "VirtualDevices";
		$hash->{ccuaddr} = sprintf ("VIR%07d", $no+1);
		$hash->{ccuname} = "none";
	}
	elsif (HMCCU_IsDevAddr ($devspec, 1)) {
		# CCU Device address with interface
		my ($i, $add) = split ('\.', $devspec);
		$hash->{ccuif} = $i;
		$hash->{ccuaddr} = $add;
		$hash->{ccuname} = HMCCU_GetDeviceName ($add, '');
	}
	elsif (HMCCU_IsDevAddr ($devspec, 0)) {
		# CCU Device address without interface
		$hash->{ccuaddr} = $devspec;
		$hash->{ccuname} = HMCCU_GetDeviceName ($devspec, '');
		$hash->{ccuif} = HMCCU_GetDeviceInterface ($hash->{ccuaddr}, 'BidCos-RF');
	}
	else {
		# CCU Device or channel name
		$hash->{ccuname} = $devspec;
		my ($add, $chn) = HMCCU_GetAddress ($devspec, '', '');
		return "Channel name not allowed" if ($chn ne '');
		$hash->{ccuaddr} = $add;
		$hash->{ccuif} = HMCCU_GetDeviceInterface ($hash->{ccuaddr}, 'BidCos-RF');
	}

	return "CCU device address not found for $devspec" if ($hash->{ccuaddr} eq '');
	return "CCU device name not found for $devspec" if ($hash->{ccuname} eq '');

	$hash->{ccutype} = HMCCU_GetDeviceType ($hash->{ccuaddr}, '');
	$hash->{channels} = HMCCU_GetDeviceChannels ($hash->{ccuaddr});

	if ($hash->{ccuif} eq "VirtualDevices" && $hash->{ccuname} eq 'none') {
		$hash->{statevals} = 'readonly';
	}
	else {
		$hash->{statevals} = 'devstate';
	}

	# Parse optional command line parameters
	my $n = 0;
	my $arg = shift @a;
	while (defined ($arg)) {
		return $usage if ($n == 3);
		if ($arg eq 'readonly') {
			$hash->{statevals} = $arg;
			$n++;
		}
		elsif ($arg eq 'defaults') {
			HMCCU_SetDefaults ($hash);
		}
		elsif ($arg =~ /^groupexp=/ && $hash->{ccuif} eq "VirtualDevices") {
			my ($g, $gdev) = split ("=", $arg);
			return $usage if (!defined ($gdev));
			my @devlist;
			my $cnt = HMCCU_GetMatchingDevices ($hmccu_hash, $gdev, 'dev', \@devlist);
			return "No matching CCU devices found" if ($cnt == 0);
			$hash->{ccugroup} = shift @devlist;
			foreach my $gd (@devlist) {
				$hash->{ccugroup} .= ",".$gd;
			}
		}
		elsif ($arg =~ /^group=/ && $hash->{ccuif} eq "VirtualDevices") {
			my ($g, $gdev) = split ("=", $arg);
			return $usage if (!defined ($gdev));
			my @gdevlist = split (",", $gdev);
			$hash->{ccugroup} = '' if (@gdevlist > 0);
			foreach my $gd (@gdevlist) {
				my ($gda, $gdc, $gdo) = ('', '', '', '');

				return "Invalid device or channel $gd"
				   if (!HMCCU_IsValidDevice ($gd));

				if (HMCCU_IsDevAddr ($gd, 0) || HMCCU_IsChnAddr ($gd, 1)) {
					$gdo = $gd;
				}
				else {
					($gda, $gdc) = HMCCU_GetAddress ($gd, '', '');
					$gdo = $gda;
					$gdo .= ':'.$gdc if ($gdc ne '');
				}

				if (exists ($hash->{ccugroup}) && $hash->{ccugroup} ne '') {
					$hash->{ccugroup} .= ",".$gdo;
				}
				else {
					$hash->{ccugroup} = $gdo;
				}
			}
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

	return "No devices in group" if ($hash->{ccuif} eq "VirtualDevices" && (
	   !exists ($hash->{ccugroup}) || $hash->{ccugroup} eq ''));

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

	return;
}

#####################################
# Set commands
#####################################

sub HMCCUDEV_Set ($@)
{
	my ($hash, @a) = @_;
	my $name = shift @a;
	my $opt = shift @a;

	my $rocmds = "clear config";

	return HMCCU_SetError ($hash, -3) if (!exists ($hash->{IODev}));
	return undef
		if ($hash->{statevals} eq 'readonly' && $opt ne '?' && $opt ne 'clear' && $opt ne 'config');

	my $disable = AttrVal ($name, "disable", 0);
	return undef if ($disable == 1);	

	my $hmccu_hash = $hash->{IODev};
	my $hmccu_name = $hash->{IODev}->{NAME};
	if (HMCCU_IsRPCStateBlocking ($hmccu_hash)) {
		return undef if ($opt eq '?');
		return "HMCCUDEV: CCU busy";
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

		return HMCCU_SetError ($hash, "Usage: set $name datapoint [{channel-number}.]{datapoint} {value}")
			if (!defined ($objname) || !defined ($objvalue));

		if ($objname =~ /^([0-9]+)\..+$/) {
			my $chn = $1;
			return HMCCU_SetError ($hash, -7) if ($chn >= $hash->{channels});
		}
		else {
			return HMCCU_SetError ($hash, -11) if ($sc eq '');
			$objname = $sc.'.'.$objname;
		}
		
		return HMCCU_SetError ($hash, -8)
			if (!HMCCU_IsValidDatapoint ($hash, $ccutype, 0, $objname, 2));
		   
		$objvalue =~ s/\\_/%20/g;
		$objvalue = HMCCU_Substitute ($objvalue, $statevals, 1, '');
		$objname = $ccuif.'.'.$ccuaddr.':'.$objname;

		$rc = HMCCU_SetDatapoint ($hash, $objname, $objvalue);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);

		HMCCU_SetState ($hash, "OK");
		return undef;
	}
	elsif ($opt eq 'control') {
		return HMCCU_SetError ($hash, -12) if ($cc eq '');
		return HMCCU_SetError ($hash, -14) if ($cd eq '');
		return HMCCU_SetError ($hash, -7) if ($cc >= $hash->{channels});

		my $objvalue = shift @a;
		return HMCCU_SetError ($hash, "Usage: set $name control {value}") if (!defined ($objvalue));
		return HMCCU_SetError ($hash, -8) if (!HMCCU_IsValidDatapoint ($hash, $ccutype, $cc, $cd, 2));	

		$objvalue =~ s/\\_/%20/g;
		$objvalue = HMCCU_Substitute ($objvalue, $statevals, 1, '');
		
		my $objname = $ccuif.'.'.$ccuaddr.':'.$cc.'.'.$cd;
		$rc = HMCCU_SetDatapoint ($hash, $objname, $objvalue);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);

		HMCCU_SetState ($hash, "OK");
		return undef;
	}
	elsif ($opt =~ /^($hash->{statevals})$/) {
		my $cmd = $1;
		my $objvalue = ($cmd ne 'devstate') ? $cmd : shift @a;

		return HMCCU_SetError ($hash, -11) if ($sc eq '');		
		return HMCCU_SetError ($hash, -13) if ($sd eq '');		
		return HMCCU_SetError ($hash, -8) if (!HMCCU_IsValidDatapoint ($hash, $ccutype, $sc, $sd, 2));
		return HMCCU_SetError ($hash, "Usage: set $name devstate {value}") if (!defined ($objvalue));

		$objvalue =~ s/\\_/%20/g;
		$objvalue = HMCCU_Substitute ($objvalue, $statevals, 1, '');
		
		my $objname = $ccuif.'.'.$ccuaddr.':'.$sc.'.'.$sd;
		$rc = HMCCU_SetDatapoint ($hash, $objname, $objvalue);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);

		HMCCU_SetState ($hash, "OK");
		return undef;
	}
	elsif ($opt eq 'toggle') {
		return HMCCU_SetError ($hash, -15) if ($statevals eq '' || !exists($hash->{statevals}));
		return HMCCU_SetError ($hash, -11) if ($sc eq '');		
		return HMCCU_SetError ($hash, -13) if ($sd eq '');	
		return HMCCU_SetError ($hash, -8) if (!HMCCU_IsValidDatapoint ($hash, $ccutype, $sc, $sd, 2));

		my $tstates = $hash->{statevals};
		$tstates =~ s/devstate\|//;
		my @states = split /\|/, $tstates;
		my $stc = scalar (@states);

		my $objname = $ccuif.'.'.$ccuaddr.':'.$sc.'.'.$sd;
		
		# Read current value of datapoint
		($rc, $result) = HMCCU_GetDatapoint ($hash, $objname);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);

		my $objvalue = '';
		my $st = 0;
		while ($st < $stc) {
			if ($states[$st] eq $result) {
				$objvalue = ($st == $stc-1) ? $states[0] : $states[$st+1];
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
		return HMCCU_SetError ($hash, -11) if ($sc eq '');
		return HMCCU_SetError ($hash, "Can't find LEVEL datapoint for device type $ccutype")
		   if (!HMCCU_IsValidDatapoint ($hash, $ccutype, $sc, "LEVEL", 2));

		my $objname = '';
		my $objvalue = shift @a;
		return HMCCU_SetError ($hash, "Usage: set $name pct {value} [{ontime} [{ramptime}]]")
			if (!defined ($objvalue));
		
		my $timespec = shift @a;
		my $ramptime = shift @a;

		# Set on time
		if (defined ($timespec)) {
			return HMCCU_SetError ($hash, "Can't find ON_TIME datapoint for device type $ccutype")
				if (!HMCCU_IsValidDatapoint ($hash, $ccutype, $sc, "ON_TIME", 2));
			if ($timespec =~ /^[0-9]{2}:[0-9]{2}/) {
				$timespec = HMCCU_GetTimeSpec ($timespec);
				return HMCCU_SetError ($hash, "Wrong time format. Use HH:MM[:SS]") if ($timespec < 0);
			}
			if ($timespec > 0) {
				$objname = $ccuif.'.'.$ccuaddr.':'.$sc.'.ON_TIME';
				$rc = HMCCU_SetDatapoint ($hash, $objname, $timespec);
				return HMCCU_SetError ($hash, $rc) if ($rc < 0);
			}
		}
		
		# Set ramp time
		if (defined ($ramptime)) {
			return HMCCU_SetError ($hash, "Can't find RAMP_TIME datapoint for device type $ccutype")
				if (!HMCCU_IsValidDatapoint ($hash, $ccutype, $sc, "RAMP_TIME", 2));
			$objname = $ccuif.'.'.$ccuaddr.':'.$sc.'.RAMP_TIME';
			$rc = HMCCU_SetDatapoint ($hash, $objname, $ramptime);
			return HMCCU_SetError ($hash, $rc) if ($rc < 0);
		}

		# Set level	
		$objname = $ccuif.'.'.$ccuaddr.':'.$sc.'.LEVEL';
		$rc = HMCCU_SetDatapoint ($hash, $objname, $objvalue);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);
		
		HMCCU_SetState ($hash, "OK");
		return undef;
	}
	elsif ($opt eq 'on-for-timer' || $opt eq 'on-till') {
		return HMCCU_SetError ($hash, -15) if ($statevals eq '' || !exists($hash->{statevals}));
		return HMCCU_SetError ($hash, "No state value for 'on' defined")
		   if ("on" !~ /($hash->{statevals})/);
		return HMCCU_SetError ($hash, -11) if ($sc eq '');
		return HMCCU_SetError ($hash, -13) if ($sd eq '');
		return HMCCU_SetError ($hash, -8) if (!HMCCU_IsValidDatapoint ($hash, $ccutype, $sc, $sd, 2));
		return HMCCU_SetError ($hash, "Can't find ON_TIME datapoint for device type")
		   if (!HMCCU_IsValidDatapoint ($hash, $ccutype, $sc, "ON_TIME", 2));

		my $timespec = shift @a;
		return HMCCU_SetError ($hash, "Usage: set $name $opt {ontime-spec}")
			if (!defined ($timespec));
			
		if ($opt eq 'on-till') {
			$timespec = HMCCU_GetTimeSpec ($timespec);
			return HMCCU_SetError ($hash, "Wrong time format. Use HH:MM[:SS]") if ($timespec < 0);
		}
		
		# Set time
		my $objname = $ccuif.'.'.$ccuaddr.':'.$sc.'.ON_TIME';
		$rc = HMCCU_SetDatapoint ($hash, $objname, $timespec);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);
		
		# Set state
		$objname = $ccuif.'.'.$ccuaddr.':'.$sc.'.'.$sd;
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
		return HMCCU_SetError ($hash, "Usage: set $name config [{channel-number}] {parameter}={value} [...]")
		   if (@a < 1);
		my $objname = $ccuaddr;
		
		# Channel number is optional because paramter can be related to device or channel
		if ($a[0] =~ /^([0-9]{1,2})$/) {
			return HMCCU_SetError ($hash, -7) if ($1 >= $hash->{channels});
			$objname .= ':'.$1;
		}

		my $rc = HMCCU_RPCSetConfig ($hash, $objname, \@a);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);

		HMCCU_SetState ($hash, "OK");
		return undef;
	}
	elsif ($opt eq 'defaults') {
		HMCCU_SetDefaults ($hash);
		HMCCU_SetState ($hash, "OK");
		return undef;
	}
	else {
		return "HMCCUCHN: Unknown argument $opt, choose one of ".$rocmds
			if ($hash->{statevals} eq 'readonly');

		my $retmsg = "HMCCUDEV: Unknown argument $opt, choose one of clear config control datapoint defaults:noArg";
		if ($sc ne '') {
			$retmsg .= " devstate";
			if ($hash->{statevals} ne '') {
				my @cmdlist = split /\|/,$hash->{statevals};
				shift @cmdlist;
				$retmsg .= ':'.join(',',@cmdlist) if (@cmdlist > 0);
				foreach my $sv (@cmdlist) {
					$retmsg .= ' '.$sv.':noArg';
				}
				$retmsg .= " toggle:noArg";
				$retmsg .= " on-for-timer on-till"
					if (HMCCU_IsValidDatapoint ($hash, $hash->{ccutype}, $sc, "ON_TIME", 2));
				$retmsg .= " pct"
					if (HMCCU_IsValidDatapoint ($hash, $hash->{ccutype}, $sc, "LEVEL", 2));
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

	return HMCCU_SetError ($hash, -3) if (!defined ($hash->{IODev}));

	my $disable = AttrVal ($name, "disable", 0);
	return undef if ($disable == 1);	

	my $hmccu_hash = $hash->{IODev};
	if (HMCCU_IsRPCStateBlocking ($hmccu_hash)) {
		return undef if ($opt eq '?');
		return "HMCCUDEV: CCU busy";
	}

	my $ccutype = $hash->{ccutype};
	my $ccuaddr = $hash->{ccuaddr};
	my $ccuif = $hash->{ccuif};
	my $ccureadings = AttrVal ($name, 'ccureadings', 1);
	my ($sc, $sd, $cc, $cd) = HMCCU_GetSpecialDatapoints ($hash, '', 'STATE', '', '');

	my $result = '';
	my $rc;

	if ($ccuif eq "VirtualDevices" && $hash->{ccuname} eq "none" && $opt ne 'update') {
		return "HMCCUDEV: Unknown argument $opt, choose one of update:noArg";
	}

	if ($opt eq 'devstate') {
		return HMCCU_SetError ($hash, -11) if ($sc eq '');
		return HMCCU_SetError ($hash, -13) if ($sd eq '');
		return HMCCU_SetError ($hash, -8) if (!HMCCU_IsValidDatapoint ($hash, $ccutype, $sc, $sd, 1));
		   
		my $objname = $ccuif.'.'.$ccuaddr.':'.$sc.'.'.$sd;
		($rc, $result) = HMCCU_GetDatapoint ($hash, $objname);

		return HMCCU_SetError ($hash, $rc) if ($rc < 0);
		return $ccureadings ? undef : $result;
	}
	elsif ($opt eq 'datapoint') {
		my $objname = shift @a;
		return HMCCU_SetError ($hash, "Usage: get $name datapoint [{channel-number}.]{datapoint}")
			if (!defined ($objname));

		if ($objname =~ /^([0-9]+)\..+$/) {
			my $chn = $1;
			return HMCCU_SetError ($hash, -7) if ($chn >= $hash->{channels});
		}
		else {
			return HMCCU_SetError ($hash, -11) if ($sc eq '');
			$objname = $sc.'.'.$objname;
		}

		return HMCCU_SetError ($hash, -8)
			if (!HMCCU_IsValidDatapoint ($hash, $ccutype, $0, $objname, 1));

		$objname = $ccuif.'.'.$ccuaddr.':'.$objname;
		($rc, $result) = HMCCU_GetDatapoint ($hash, $objname);

		return HMCCU_SetError ($hash, $rc) if ($rc < 0);

		HMCCU_SetState ($hash, "OK") if (exists ($hash->{STATE}) && $hash->{STATE} eq "Error");
		return $ccureadings ? undef : $result;
	}
	elsif ($opt eq 'update') {
		my $ccuget = shift @a;
		$ccuget = 'Attr' if (!defined ($ccuget));
		if ($ccuget !~ /^(Attr|State|Value)$/) {
			return HMCCU_SetError ($hash, "Usage: get $name update [{'State'|'Value'}]");
		}

		if ($hash->{ccuname} ne 'none') {
			$rc = HMCCU_GetUpdate ($hash, $ccuaddr, $ccuget);
			return HMCCU_SetError ($hash, $rc) if ($rc < 0);
		}

		# Update other devices belonging to group
		if ($hash->{ccuif} eq "VirtualDevices" && exists ($hash->{ccugroup})) {
			my @vdevs = split (",", $hash->{ccugroup});
			foreach my $vd (@vdevs) {
				$rc = HMCCU_GetUpdate ($hash, $vd, $ccuget);
				return HMCCU_SetError ($hash, $rc) if ($rc < 0);
			}
		}

		return undef;
	}
	elsif ($opt eq 'deviceinfo') {
		my $ccuget = shift @a;
		$ccuget = 'Attr' if (!defined ($ccuget));
		if ($ccuget !~ /^(Attr|State|Value)$/) {
			return HMCCU_SetError ($hash, "Usage: get $name deviceinfo [{'State'|'Value'}]");
		}
		$result = HMCCU_GetDeviceInfo ($hash, $ccuaddr, $ccuget);
		return HMCCU_SetError ($hash, -2) if ($result eq '');
		return HMCCU_FormatDeviceInfo ($result);
	}
	elsif ($opt eq 'config') {
		my $channel = undef;
		my $ccuobj = $ccuaddr;
		my $par = shift @a;
		if (defined ($par)) {
			if ($par =~ /^([0-9]{1,2})$/) {
				return HMCCU_SetError ($hash, -7) if ($1 >= $hash->{channels});
				$ccuobj .= ':'.$1;
			}
			else {
				return HMCCU_SetError ($hash, -7) if ($1 >= $hash->{channels});
			}
		}

		my ($rc, $res) = HMCCU_RPCGetConfig ($hash, $ccuobj, "getParamset");
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);		
		HMCCU_SetState ($hash, "OK") if (exists ($hash->{STATE}) && $hash->{STATE} eq "Error");
		return $ccureadings ? undef : $res;
	}
	elsif ($opt eq 'configdesc') {
		my $channel = undef;
		my $ccuobj = $ccuaddr;
		my $par = shift @a;
		if (defined ($par)) {
			if ($par =~ /^([0-9]{1,2})$/) {
				return HMCCU_SetError ($hash, -7) if ($1 >= $hash->{channels});
				$ccuobj .= ':'.$1;
			}
			else {
				return HMCCU_SetError ($hash, -7) if ($1 >= $hash->{channels});
			}
		}

		my ($rc, $res) = HMCCU_RPCGetConfig ($hash, $ccuobj, "getParamsetDescription");
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);
		HMCCU_SetState ($hash, "OK") if (exists ($hash->{STATE}) && $hash->{STATE} eq "Error");
		return $res;
	}
	elsif ($opt eq 'defaults') {
		$result = HMCCU_GetDefaults ($hash);
		return $result;
	}
	else {
		my $retmsg = "HMCCUDEV: Unknown argument $opt, choose one of datapoint";
		
		my @valuelist;
		my $valuecount = HMCCU_GetValidDatapoints ($hash, $ccutype, -1, 1, \@valuelist);
		   
		$retmsg .= ":".join(",", @valuelist) if ($valuecount > 0);
		$retmsg .= " defaults:noArg update:noArg config configdesc deviceinfo:noArg";
		$retmsg .= ' devstate:noArg' if ($sc ne '');
			
		return $retmsg;
	}
}


1;

=pod
=item device
=item summary controls HMCCU client devices for Homematic CCU2 - FHEM integration
=begin html

<a name="HMCCUDEV"></a>
<h3>HMCCUDEV</h3>
<ul>
   The module implements Homematic CCU devices as client devices for HMCCU. A HMCCU I/O device must
   exist before a client device can be defined. If a CCU channel is not found execute command
   'get devicelist' in I/O device.<br/>
   This reference contains only commands and attributes which differ from module
   <a href="#HMCCUCHN">HMCCUCHN</a>.
   </br></br>
   <a name="HMCCUDEVdefine"></a>
   <b>Define</b><br/><br/>
   <ul>
      <code>define &lt;name&gt; HMCCUDEV {&lt;device&gt; | 'virtual'} [&lt;statechannel&gt;]
      [readonly] [defaults] [{group={device|channel}[,...]|groupexp=regexp]</code>
      <br/><br/>
      If option 'readonly' is specified no set command will be available. With option 'defaults'
      some default attribute depending on CCU device type will be set (default attributes are only
      available for some device types. Parameter <i>statechannel</i> corresponds to attribute
      'statechannel'.<br/>
      A HMCCUDEV device supports CCU group devices. The CCU devices or channels related to a group
      device are specified by using options 'group' or 'groupexp' followed by the names or
      addresses of the CCU devices or channels. By using 'groupexp' one can specify a regular
      expression for CCU device or channel names.<br/>
      It's also possible to group any kind of CCU devices or channels without defining a real
      group in CCU by using option 'virtual' instead of a CCU device specification. 
      <br/><br/>
      Examples:<br/>
      <code>
      # Simple device by using CCU device name<br/>
      define window_living HMCCUDEV WIN-LIV-1<br/>
      # Simple device by using CCU device address and with state channel<br/>
      define temp_control HMCCUDEV BidCos-RF.LEQ1234567 1<br/>
      # Simple read only device by using CCU device address and with default attributes<br/>
      define temp_sensor HMCCUDEV BidCos-RF.LEQ2345678 1 readonly defaults
      # Group device by using CCU group device and 3 group members<br/>
      define heating_living HMCCUDEV GRP-LIV group=WIN-LIV,HEAT-LIV,THERM-LIV
      </code>
      <br/>
   </ul>
   <br/>
   
   <a name="HMCCUDEVset"></a>
   <b>Set</b><br/><br/>
   <ul>
      <li><b>set &lt;name&gt; clear [&lt;reading-exp&gt;]</b><br/>
      	<a href="#HMCCUCHNset">see HMCCUCHN</a> 
      </li><br/>
      <li><b>set &lt;name&gt; config [&lt;channel-number&gt;] &lt;parameter&gt;=&lt;value&gt;
       </b><br/>
        Set configuration parameter of CCU device or channel. Valid parameters can be listed by 
        using command 'get configdesc'.
      </li><br/>
      <li><b>set &lt;name&gt; datapoint [&lt;channel-number&gt;.]&lt;datapoint&gt;
       &lt;value&gt;</b><br/>
        Set value of a datapoint of a CCU device channel. If channel number is not specified
        state channel is used. String \_ is substituted by blank.
        <br/><br/>
        Example:<br/>
        <code>set temp_control datapoint 1.SET_TEMPERATURE 21</code>
      </li><br/>
      <li><b>set &lt;name&gt; defaults</b><br/>
   		Set default attributes for CCU device type. Default attributes are only available for
   		some device types.
      </li><br/>
      <li><b>set &lt;name&gt; devstate &lt;value&gt;</b><br/>
         Set state of a CCU device channel. Channel and state datapoint must be defined as
         attribute 'statedatapoint'. If <i>value</i> contains string \_ it is substituted by blank.
      </li><br/>
      <li><b>set &lt;name&gt; on-for-timer &lt;ontime&gt;</b><br/>
      	<a href="#HMCCUCHNset">see HMCCUCHN</a>
      </li><br/>
      <li><b>set &lt;name&gt; on-till &lt;timestamp&gt;</b><br/>
      	<a href="#HMCCUCHNset">see HMCCUCHN</a>
      </li><br/>
      <li><b>set &lt;name&gt; pct &lt;value;&gt; [&lt;ontime&gt; [&lt;ramptime&gt;]]</b><br/>
      	<a href="#HMCCUCHNset">see HMCCUCHN</a>
      </li><br/>
      <li><b>set &lt;name&gt; &lt;statevalue&gt;</b><br/>
         State datapoint of a CCU device channel is set to 'statevalue'. State channel and state
         datapoint must be defined as attribute 'statedatapoint'. Values for <i>statevalue</i>
         are defined by setting attribute 'statevals'.
         <br/><br/>
         Example:<br/>
         <code>
         attr myswitch statedatapoint 1.STATE<br/>
         attr myswitch statevals on:true,off:false<br/>
         set myswitch on
         </code>
      </li><br/>
      <li><b>set &lt;name&gt; toggle</b><br/>
      	<a href="#HMCCUCHNset">see HMCCUCHN</a>
      </li><br/>
      <li><b>ePaper Display</b><br/><br/>
      This display has 5 text lines. The lines 1,2 and 4,5 are accessible via config parameters
      TEXTLINE_1 and TEXTLINE_2 in channels 1 and 2. Example:<br/><br/>
      <code>
      define HM_EPDISP HMCCUDEV CCU_EPDISP<br/>
      set HM_EPDISP config 2 TEXTLINE_1=Line1<br/>
		set HM_EPDISP config 2 TEXTLINE_2=Line2<br/>
		set HM_EPDISP config 1 TEXTLINE_1=Line4<br/>
		set HM_EPDISP config 1 TEXTLINE_2=Line5<br/>
      </code>
      <br/>
      The lines 2,3 and 4 of the display can be accessed by setting the datapoint SUBMIT of the
      display to a string containing command tokens in format 'parameter=value'. The following
      commands are allowed:
      <br/><br/>
      <ul>
      <li>text1-3=Text - Content of display line 2-4</li>
      <li>icon1-3=IconCode - Icons of display line 2-4</li>
      <li>sound=SoundCode - Sound</li>
      <li>signal=SignalCode - Optical signal</li>
      <li>pause=Seconds - Pause between signals (1-160)</li>
      <li>repeat=Count - Repeat count for sound (0-15)</li>
      </ul>
      <br/>
      IconCode := ico_off, ico_on, ico_open, ico_closed, ico_error, ico_ok, ico_info,
      ico_newmsg, ico_svcmsg<br/>
      SignalCode := sig_off, sig_red, sig_green, sig_orange<br/>
      SoundCode := snd_off, snd_longlong, snd_longshort, snd_long2short, snd_short, snd_shortshort,
      snd_long<br/><br/>
      Example:<br/>
      <code>
      set HM_EPDISP datapoint 3.SUBMIT text1=Line2,text2=Line3,text3=Line4,sound=snd_short,
      signal=sig_red
      </code>
      </li>
   </ul>
   <br/>
   
   <a name="HMCCUDEVget"></a>
   <b>Get</b><br/><br/>
   <ul>
      <li><b>get &lt;name&gt; config [&lt;channel-number&gt;]</b><br/>
         Get configuration parameters of CCU device. If attribute 'ccureadings' is set to 0
         parameters are displayed in browser window (no readings set).
      </li><br/>
      <li><b>get &lt;name&gt; configdesc [&lt;channel-number&gt;] [&lt;rpcport&gt;]</b><br/>
         Get description of configuration parameters for CCU device. Default value for Parameter
         <i>rpcport</i> is 2001 (BidCos-RF). Other valid values are 2000 (wired) and 2010 (HMIP).
      </li><br/>
      <li><b>get &lt;name&gt; datapoint [&lt;channel-number&gt;.]&lt;datapoint&gt;</b><br/>
         Get value of a CCU device datapoint. If <i>channel-number</i> is not specified state 
         channel is used.
      </li><br/>
      <li><b>get &lt;name&gt; defaults</b><br/>
      	Display default attributes for CCU device type.
      </li><br/>
      <li><b>get &lt;name&gt; deviceinfo [{State | <u>Value</u>}]</b><br/>
         Display all channels and datapoints of device with datapoint values and types.
      </li><br/>
      <li><b>get &lt;name&gt; devstate</b><br/>
         Get state of CCU device. Attribute 'statechannel' must be set. Default state datapoint
         STATE can be modified by attribute 'statedatapoint'.
      </li><br/>
      <li><b>get &lt;name&gt; update [{State | <u>Value</u>}]</b><br/>
      	<a href="#HMCCUCHNget">see HMCCUCHN</a>
      </li><br/>
   </ul>
   <br/>
   
   <a name="HMCCUDEVattr"></a>
   <b>Attributes</b><br/><br/>
   <ul>
      To reduce the amount of events it's recommended to set attribute 'event-on-change-reading'
      to '.*'.<br/><br/>
      <li><b>ccuackstate {<u>0</u> | 1}</b><br/>
      	<a href="#HMCCUCHNattr">see HMCCUCHN</a>
      </li><br/>
      <li><b>ccuflags {nochn0, trace}</b><br/>
      	<a href="#HMCCUCHNattr">see HMCCUCHN</a>
      </li><br/>
      <li><b>ccuget {State | <u>Value</u>}</b><br/>
      	<a href="#HMCCUCHNattr">see HMCCUCHN</a>
      </li><br/>
      <li><b>ccureadings {0 | <u>1</u>}</b><br/>
      	<a href="#HMCCUCHNattr">see HMCCUCHN</a>
      </li><br/>
      <li><b>ccureadingfilter &lt;filter-rule[,...]&gt;</b><br/>
      	<a href="#HMCCUCHNattr">see HMCCUCHN</a>
      </li><br/>
      <li><b>ccureadingformat {address[lc] | name[lc] | datapoint[lc]}</b><br/>
      	<a href="#HMCCUCHNattr">see HMCCUCHN</a>
      </li><br/>
      <li><b>ccureadingname &lt;old-readingname-expr&gt;:&lt;new-readingname&gt;[,...]</b><br/>
      	<a href="#HMCCUCHNattr">see HMCCUCHN</a>
      </li><br/>
      <li><b>ccuscaleval &lt;datapoint&gt;:&lt;factor&gt;[,...]</b><br/>
      ccuscaleval &lt;[!]datapoint&gt;:&lt;min&gt;:&lt;max&gt;:&lt;minn&gt;:&lt;maxn&gt;[,...]<br/>
      	<a href="#HMCCUCHNattr">see HMCCUCHN</a>
      </li><br/>
      <li><b>ccuverify {0 | 1 | 2}</b><br/>
      	<a href="#HMCCUCHNattr">see HMCCUCHN</a>
      </li><br/>
      <li><b>controldatapoint &lt;channel-number.datapoint&gt;</b><br/>
         Set channel number and datapoint for device control.
         <a href="#HMCCUCHNattr">see HMCCUCHN</a>
      </li><br/>
      <li><b>disable {<u>0</u> | 1}</b><br/>
         <a href="#HMCCUCHNattr">see HMCCUCHN</a>
      </li><br/>
      <li><b>statechannel &lt;channel-number&gt;</b><br/>
         Channel for setting device state by devstate command. Deprecated, use attribute
         'statedatapoint' instead.
      </li><br/>
      <li><b>statedatapoint [&lt;channel-number&gt;.]&lt;datapoint&gt;</b><br/>
         Set state channel and state datapoint for setting device state by devstate command.
         Default is STATE. If 'statedatapoint' is not defined at least attribute 'statechannel'
         must be set.
      </li><br/>
      <li><b>statevals &lt;text&gt;:&lt;text&gt;[,...]</b><br/>
         <a href="#HMCCUCHNattr">see HMCCUCHN</a>
      </li><br/>
      <li><b>stripnumber {0 | 1 | 2 | -n}</b><br/>
         <a href="#HMCCUCHNattr">see HMCCUCHN</a>
      </li><br/>
      <li><b>substitute &lt;subst-rule&gt;[;...]</b><br/>
         <a href="#HMCCUCHNattr">see HMCCUCHN</a>
      </li><br/>
   </ul>
</ul>

=end html
=cut

