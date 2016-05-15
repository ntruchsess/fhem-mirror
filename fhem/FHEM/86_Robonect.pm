##############################################
# $Id$
# ABU 20160307 First release
# ABU 20160321 Added first parsing algos
# ABU 20160311 Migrated to JSON
# ABU 20160412 Integrated basic set-mechanism, added internals, changed callback-routine
# ABU 20160413 Renamed to robonect, added status offline
# ABU 20160414 Changed final two Automower to Robonect
# ABU 20160414 Renamed private fn "decode"
# ABU 20160415 Renamed private fn "decode" again, set eventonchangedreading, removed debug, increased interval to 90
# ABU 20160416 Added logs, removed eventonchangedreading, added debug
# ABU 20160416 Removed logs, added eventonchangedreading, removed debug, added 1=true for json data
# ABU 20160426 Fixed decode warning, added error support
# ABU 20160515 Added splitFn and doku

package main;

use strict;
use warnings;
use HttpUtils;
use JSON;

#available get cmds
my %gets = (
	"status" => "noArg"
);

my $EOD = "feierabend";
my $HOME = "home";
my $AUTO = "auto";
my $MANUAL = "manuell";
my $START = "start";
my $STOP = "stop";
my $OFFLINE = "offline";

#available set cmds
my %sets = (
	$EOD => "noArg",
	$HOME => "noArg",
	$AUTO => "noArg",
	$MANUAL => "noArg",
	$START => "noArg",
	$STOP => "noArg"	
);

my %commands = (
	GET_STATUS	=> "cmd=status",
	SET_MODE	=> {$HOME=>"cmd=mode&mode=home", $MANUAL=>"cmd=mode&mode=man", $AUTO=>"cmd=mode&mode=auto", $EOD=>"cmd=mode&mode=eod", $STOP=>"cmd=stop", $START=>"cmd=start"}	
);

#set to 1 for debug
my $debug = 0;

#elements within group next
my %elements = (
#	"robonect" =>
#	{
		"successful" 	=> {ALIAS=>"kommunikation", "true"=>"erfolgreich", "false"=>"fehlgeschlagen", 1=>"erfolgreich", 0=>"fehlgeschlagen"}, 
		
		"status" =>
		{
			ALIAS		=> "allgemein",
			"status" 	=> {ALIAS=>"status", 0=>"schlafen", 1=>"parken", 2=>"maehen", 3=>"suche-base", 4=>"laden", 5=>"suche", 7=>"fehler", 8=>"schleife-fehlt"}, 
			"mode"	 	=> {ALIAS=>"modus", 0=>"automatik", 1=>"manuell", 2=>"home", 3=>"demo"}, 
			"battery" 	=> {ALIAS=>"batteriezustand"},
			"hours"		=> {ALIAS=>"betriebsstunden"}
		},
		
		"timer" =>
		{
			ALIAS		=> "timer",
			"status"	=> {ALIAS=>"status", 0=>"deaktiviert", 1=>"aktiv", 2=>"standby"},			
			"next" =>
			{
				ALIAS		=> "timer",
				"date"		=> {ALIAS=>"startdatum"},
				"time"		=> {ALIAS=>"startzeit"},
				#"date"		=> {ALIAS=>"start-unix"},
			}
		},
		
		"error" =>
		{
			ALIAS			=> "fehler",
			"error_code"	=> {ALIAS=>"code"},
			"error_message"	=> {ALIAS=>"nachricht"},
			"date"			=> {ALIAS=>"datum"},
			"time"			=> {ALIAS=>"zeit"}
		}		
#	}	
);

#Init this device
#This declares the interface to fhem
#############################
sub Robonect_Initialize($) {
    my ($hash) = @_;

    $hash->{DefFn}      = 'Robonect_Define';
    $hash->{UndefFn}    = 'Robonect_Undef';
    $hash->{SetFn}      = 'Robonect_Set';
    $hash->{GetFn}      = 'Robonect_Get';
    $hash->{AttrFn}     = 'Robonect_Attr';
	$hash->{ShutdownFn} = 'Robonect_Shutdown';
	$hash->{ReadyFn} 	= 'Robonect_Ready';
	$hash->{DbLog_splitFn}  = 'Robonect_DbLog_split';
	$hash->{AttrList}  		= 	"do_not_notify:1,0 " . 		#supress any notification (including log)
								"showtime:1,0 " . 			#shows time instead of received value in state
								"credentials " .			#user/password combination for authentication in mower, stored in a credentials file
								"basicAuth " .				#user/password combination for authentication in mower								
								"pollInterval " .			#interval to poll in seconds
								"$readingFnAttributes ";	#standard attributes
}

#Define this device
#Is called at every define
#############################
sub Robonect_Define($$) 
{
    my ($hash, $def) = @_;
	my @a = split("[ \t][ \t]*", $def);
	#device name
	my $name = $a[0];

	#set verbose to 5, if debug enabled
	$attr{$name}{verbose} = 5 if ($debug eq 1);	

	my $tempStr = join (", ", @a);
	Log3 ($name, 5, "define $name: enter $hash, attributes: $tempStr");
	
	#too less arguments
	return "wrong syntax - define <name> Robonect <ip-adress> [<user> <password>]" if (int(@a) < 3);

	#check IP
	my $ip = $a[2];
	#remove whitespaces
	$ip =~ s/^\s+|\s+$//g;
	#Syntax ok
	if ($ip =~ m/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/)
	{
		my @octs = split (".", $ip);
		
		foreach my $octet (@octs)
		{
			return "wrong syntax - $octet has an invalid range. Allowed is 0..255" if (($octet >= 256) or ($octet <= -1));
		}
	}
	else
	{
		return "wrong syntax - IP must be supplied correctly <0..254>.<0..254>.<0..254>.<0..254>";
	}
	
	#wrong syntax for IP
	return "wrong syntax - IP must be supplied correctly <0..254>.<0..254>.<0..254>.<000..254>" if (int(@a) < 3);
		    
	#assign name and port
    $hash->{NAME} = $name;
	$hash->{IP} = $ip;
	#backup name for a later rename
	$hash->{DEVNAME} = $name;
	
	#get first info and launch timer
	InternalTimer(gettimeofday(), "Robonect_GetUpdate", $hash, 0);	

	#finally create decice
	#defptr is needed to supress FHEM input
	$modules{Robonect}{defptr}{$name} = $hash;

	#default event-on-changed-reading for all readings
	$attr{$name}{"event-on-change-reading"} = ".*";
	#defaul poll-interval
	$attr{$name}{"pollInterval"} = 90;
	
	Log3 ($name, 5, "exit define");
	return undef;	
}

#Release this device
#Is called at every delete / shutdown
#############################
sub Robonect_Undef($$) 
{
	my ($hash, $name) = @_;

	Log3 ($name, 5, "enter undef $name: hash: $hash name: $name");
	
	#kill interval timer
	RemoveInternalTimer($hash);  

	#close port
  	Robonect_Shutdown ($hash);
	
	#remove module. Refer to DevName, because module may be renamed
	delete $modules{KNX}{defptr}{$hash->{DEVNAME}};

	#remove name
	delete $hash->{NAME};
	#remove backuped name
	delete $hash->{DEVNAME};
		
	Log3 ($name, 5, "exit undef");
	return undef;
}

#Release this device
#Is called at every delete / shutdown
#############################
sub Robonect_Shutdown($) 
{
	my ($hash, $name) = @_;
	
	Log3 ($name, 5, "enter shutdown $name: hash: $hash name: $name");
	Log3 ($name, 5, "exit shutdown");
	return undef;
}

#This function is called from fhem from rime to time
#############################
sub Robonect_Ready($) 
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
	Log3 ($name, 5, "enter ready $name: hash: $hash name: $name");
	Log3 ($name, 5, "exit ready");
	return undef;	
}

#Reads info from the mower
#############################
sub Robonect_Get($@) 
{
	my ($hash, @a) = @_;
	my $name = $hash->{NAME};

	my $tempStr = join (", ", @a);
	Log3 ($name, 5, "enter get $name: $name hash: $hash, attributes: $tempStr");

	#backup cmd
	my $cmd = $a[1];
	#response for gui
	return "Unknown argument, choose one of " . join(" ", " ", sort keys %gets) if(!defined($cmd));	
	return "Unknown argument $cmd, choose one of " . join(" ", " ", sort keys %gets) if(!defined($gets{$cmd}));
	#lower cmd
	$cmd = lc($cmd);
	
	my ($userName, $passWord) = getCredentials ($hash);
	
	#basic url
	my $url = "http://" . $hash->{IP} . "/json?";
	#append userdata, if given
	$url = $url . "user=" . $userName . "&pass=" . $passWord . "&" if (defined ($userName) and defined ($passWord));
	#append command
	$url = $url . $commands{GET_STATUS};
		
	my $httpData;
	$httpData->{url} = $url;
	$httpData->{loglevel} = AttrVal ($name, "verbose", 2);
	$httpData->{loglevel} = 5;
	$httpData->{hideurl} = 0;		
	$httpData->{callback} = \&callback;
	$httpData->{hash} = $hash;
	$httpData->{cmd} = $commands{GET_STATUS};
		
	HttpUtils_NonblockingGet($httpData);
		
	return $httpData->{err};
	
	Log3 ($name, 5, "exit get");	
	
	return undef;
}

#Sends commands to the mower
#############################
sub Robonect_Set($@) 
{
	my ($hash, @a) = @_;
	my $name = $hash->{NAME};

	my $tempStr = join (", ", @a);
	Log3 ($name, 5, "enter set $name: $name hash: $hash, attributes: $tempStr");
	
	#backup cmd
	my $cmd = $a[1];
	#response for gui
	return "Unknown argument, choose one of " . join(" ", " ", sort keys %sets) if(!defined($cmd));	
	return "Unknown argument $cmd, choose one of " . join(" ", " ", sort keys %sets) if(!defined($sets{$cmd}));
	#lower cmd
	$cmd = lc($cmd);
	
	my ($userName, $passWord) = getCredentials ($hash);
	my $decodedCmd = $commands{SET_MODE}{$cmd};
	
	#execute it
	if (defined ($decodedCmd))
	{
		my $url = "http://" . $hash->{IP} . "/json?";
		#append userdata, if given
		$url = $url . "user=" . $userName . "&pass=" . $passWord . "&" if (defined ($userName) and defined ($passWord));
		#append command
		$url = $url . $decodedCmd;
		
		print "URL: $url\n";
		
		my $httpData;
		$httpData->{url} = $url;
		$httpData->{loglevel} = AttrVal ($name, "verbose", 2);
		$httpData->{loglevel} = 5;
		$httpData->{hideurl} = 0;		
		$httpData->{callback} = \&callback;
		$httpData->{hash} = $hash;
		$httpData->{cmd} = $decodedCmd;
		
		HttpUtils_NonblockingGet($httpData);
		
		return $httpData->{err};
		
		Robonect_GetUpdate($hash);
    }	
	
	Log3 ($name, 5, "exit set");	
	
	return;
}

#called on every mod of the attributes
#############################
sub Robonect_Attr(@) 
{
	my ($cmd,$name,$attr_name,$attr_value) = @_;

	Log3 ($name, 5, "enter attr $name: $name, attrName: $attr_name");
	
	#if($cmd eq "set") 
	#{		
	#	if(($attr_name eq "debug") and (($attr_value eq "1") or ($attr_value eq "true")))
	#	{
	#		#todo
	#	}			
	#}
	
	Log3 ($name, 5, "exit attr");	
	
	return undef;
}

#Split reading for DBLOG
#############################
sub Robonect_DbLog_split($) {
	my ($event) = @_;
	my ($reading, $value, $unit);

	my $tempStr = join (", ", @_);
	Log (5, "splitFn - enter, attributes: $tempStr");
	
	#detect reading - real reading or state?
	my $isReading = "false"; 
	$isReading = "true" if ($event =~ m/: /);
	
	#split input-string
	my @strings = split (" ", $event);
	
	my $startIndex = undef;
	$unit = "";
	
	return undef if (not defined ($strings[0]));

	#real reading?
	if ($isReading =~ m/true/)
	{
		#first one is always reading
		$reading = $strings[0];
		$reading =~ s/:?$//;
		$startIndex = 1;
	}
	#plain state
	else
	{
		#for reading state nothing is supplied
		$reading = "state";
		$startIndex = 0;	
	}
	
	return undef if (not defined ($strings[$startIndex]));

	#per default join all single pieces
	$value = join(" ", @strings[$startIndex..(int(@strings) - 1)]);
	
	#numeric value?
	#if ($strings[$startIndex] =~ /^[+-]?\d*[.,]?\d+/)
	if ($strings[$startIndex] =~ /^[+-]?\d*[.,]?\d+$/)
	{
		$value = $strings[$startIndex];
		#single numeric value? Assume second par is unit...
		if ((defined ($strings[$startIndex + 1])) && !($strings[$startIndex+1] =~ /^[+-]?\d*[.,]?\d+/)) 
		{
			$unit = $strings[$startIndex + 1] if (defined ($strings[$startIndex + 1]));
		}
	}

	#numeric value?
	#if ($strings[$startIndex] =~ /^[+-]?\d*[.,]?\d+/)
	#{
	#	$value = $strings[$startIndex];
	#	$unit = $strings[$startIndex + 1] if (defined ($strings[$startIndex + 1]));
	#}
	#string or raw
	#else
	#{
	#	$value = join(" ", @strings[$startIndex..(int(@strings) - 1)]);
	#}
		
	Log (5, "splitFn - READING: $reading, VALUE: $value, UNIT: $unit");
	
	return ($reading, $value, $unit);
}

#Called on the interval timer, if enabled
#############################
sub Robonect_GetUpdate($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
	Log3 ($name, 5, "enter update $name: $name");

	#get status	
	my @callAttr;
	$callAttr[0] = $name;
	$callAttr[1] = "status";
	Robonect_Get ($hash, @callAttr);

	my $interval = AttrVal($name,"pollInterval",90);
	#reset timer
	InternalTimer(gettimeofday() + $interval, "Robonect_GetUpdate", $hash, 1) if ($interval > 0);
	
	Log3 ($name, 5, "exit update");	
}

#Private function which handles http-responses
#############################
sub callback ($)
{
    my ($param, $err, $data) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};
 
	#wenn ein Fehler bei der HTTP Abfrage aufgetreten ist
    if($err ne "")
    {
        Log3 ($name, 3, "callback - error while requesting ".$param->{url}." - $err");
		$hash->{LAST_COMM_STATUS} = $err;
		#set reading with failure - notify only, when state has not changed
        readingsSingleUpdate($hash, "state", $OFFLINE, 1);
    }
	#wenn die Abfrage erfolgreich war ($data enth�lt die Ergebnisdaten des HTTP Aufrufes)
    elsif($data ne "")
    {
        Log3 ($name, 3, "callback - url ".$param->{url}." returned: $data");
		
		#repair V5.0b
		$data =~ s/:"/,"/g;
				
		my $answer = decode_json $data;
		
		Log3 ($name, 3, "callback - url ".$param->{url}." repaired: $data");
		
		my ($key, $value) = decodeContent ($hash, $answer, "successful", undef, undef);
		
		$hash->{LAST_CMD} = $param->{cmd};
		$hash->{LAST_COMM_STATUS} = "success: " . $value;
		
		Log3 ($name, 5, "callback - communication ok");
		
		#my %tmp = %$answer;
		#print "answer: ", %tmp, "\n";
		
		#status-readings
		if ($answer->{successful} =~ m/(true)|(1)/)
		{
			Log3 ($name, 5, "callback - update readings");
			
			readingsBeginUpdate($hash);

			#($key, $value) = decodeContent ($hash, $answer, "successful", undef);
			#readingsBulkUpdate($hash, $key, $value);			

			($key, $value) = decodeContent ($hash, $answer, "status", "status", undef);
			readingsBulkUpdate($hash, $key, $value);
			readingsBulkUpdate($hash, "state", $value);
			($key, $value) = decodeContent ($hash, $answer, "status", "mode", undef);
			readingsBulkUpdate($hash, $key, $value);
			($key, $value) = decodeContent ($hash, $answer, "status", "battery", undef);
			readingsBulkUpdate($hash, $key, $value);
			($key, $value) = decodeContent ($hash, $answer, "status", "hours", undef);
			readingsBulkUpdate($hash, $key, $value);

			($key, $value) = decodeContent ($hash, $answer, "timer", "status", undef);
			readingsBulkUpdate($hash, $key, $value);
			
			($key, $value) = decodeContent ($hash, $answer, "timer", "next", "date");
			readingsBulkUpdate($hash, $key, $value);
			($key, $value) = decodeContent ($hash, $answer, "timer", "next", "time");
			readingsBulkUpdate($hash, $key, $value);
			
			readingsEndUpdate($hash, 1);
		}
		
		#error?
		my $errorOccured = $answer->{status}->{status};
		if (defined ($errorOccured) and ($errorOccured  =~ m/7/))
		{
			readingsSingleUpdate($hash, "fehler_aktuell", $answer->{error}->{error_message}, 1);
		}
		#no error
		elsif (defined ($errorOccured))
		{
			my $hashref = $hash->{READINGS};
			my %readings = %$hashref;
			
			#delete readings
			foreach my $key (keys %readings)
			{
				#delete $readings{$key} if ($key =~ m/^fehler.*/);			
				delete $hash->{READINGS}{$key} if ($key =~ m/^fehler.*/);							
				#delete $hash->{READINGS}{$key} if ($key =~ m/^fehler-aktuell.*/);
			}
		}
    }
}

#Private function to get json-content
#############################
sub decodeContent ($$$$$)
{
	my ($hash, $msg, $key1, $key2, $key3) = @_;
	my $name = $hash->{NAME};
	
	my $rdName = undef;
	my $rdValue = undef;
	
	my $template = undef;

	if (defined ($key2) && defined ($key3))
	{
		$template = $elements{$key1}{$key2}{$key3};
		$rdName = $elements{$key1}{$key2}{ALIAS} . "-" . $template->{ALIAS};
		$rdValue = $msg->{$key1}->{$key2}->{$key3};	
	}
	elsif (defined ($key2))
	{
		$template = $elements{$key1}{$key2};
		$rdName = $elements{$key1}{ALIAS} . "-" . $template->{ALIAS};
		$rdValue = $msg->{$key1}->{$key2};
	}
	else
	{
		$template = $elements{$key1};
		$rdValue = $msg->{$key1};
		$rdName = $template->{ALIAS};
	}
	
	$rdValue = "undef" if (not defined ($rdValue));
	$rdValue = $template->{$rdValue} if (defined ($template->{$rdValue}));
	
	Log3 ($name, 5, "decodeContent - NAME: $rdName, VALUE: $rdValue");
	
	return $rdName, $rdValue;
}

#Private function to evaluate credentials
#############################
sub decodeAnswer ($$$)
{
	my ($hash, $getCmd, @readings) = @_;
	my $name = $hash->{NAME};
	
	my @list;
	
	foreach my $reading (@readings)
	{
		my $answer = undef;
		my $transval = undef;
		my ($header, $key, $value) = undef;
		
		$header = $reading->{header};
		$key = $reading->{key};
		$value = $reading->{value};
		
		if ($header =~ m/robonect/i)
		{
			$answer->{name} = $getCmd . "-" . $elements{$header}{$key}{ALIAS};
			$transval = $elements{$header}{$key}{$value};
		}
		else
		{
			$answer->{name} = $getCmd . "-" . $elements{"robonect"}{$header}{ALIAS} . "-" . $elements{"robonect"}{$header}{$key}{ALIAS};
			$transval = $elements{"robonect"}{$header}{$key}{$value};		
		}
		
		if (defined($transval))
		{	
			$answer->{value} = $transval;
		}
		else
		{
			$answer->{value} = $value;
		}
		
		#$answer->{name} = $getCmd . "-" . $answer->{name};
		
		Log3 ($name, 5, "decodeAnswer - NAME: $answer->{name}, VALUE: $answer->{value}");
		
		push (@list, $answer);
	}
	
	return @list;
}

#Private function to evaluate credentials
#############################
sub getCredentials ($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $userName = undef;
	my $passWord = undef;
	
	#parse basicAuth
	my $basicAuth = AttrVal ($name, "basicAuth", undef);
	if (defined ($basicAuth))
	{
		#if the string does NOT contain a ":", assume base64-encoded data
		if (not ($basicAuth =~ m/:/))
		{
			$basicAuth = decode_base64 ($basicAuth);			
			Log3 ($name, 5, "credentials - found encrypted data");
		}

		#try to split 
		my @plainAuth = split (":", $basicAuth);
		
		#found plain authentication
		if (int(@plainAuth) == 2)
		{
			$userName = $plainAuth[0];
			$passWord = $plainAuth[1];
			
			Log3 ($name, 5, "credentials - found plain data");
		}
		else
		{
			Log3 ($name, 0, "credentials - user/pw combination not correct");		
		}
	}
	
	#parse credential-File - overrules basicAuth
	my $credentials = AttrVal ($name, "credentials", undef);
	if(defined($credentials)) 
	{
		#cannot open file
		if(!open(CFG, $credentials))
		{	
			Log3 ($name, 0, "cannot open credentials file: $credentials") ;
		}
		#read it		
		else
		{
			my @cfg = <CFG>;
			close(CFG);
			my %creds;
			eval join("", @cfg);
			#extract it
			$userName =~ $creds{$name}{username};
			$passWord =~ $creds{$name}{password};
		
			Log3 ($name, 5, "credentials - found in file");		
		}
	}
	
	return $userName, $passWord;
}

1;

=pod
=begin html

<a name="Robonect"></a> 
<h3>Robonect</h3>
<ul>
<p>Robonect is a after-market wifi-module for robomowers based on the husky G3-control. It was developed by Fabian H. and can be optained at www.robonect.de. This module gives you access to the basic commands. This module will not work without libjson-perl! Do not forget to install it first!</p>

  <p><a name="RobonectDefine"></a> <b>Define</b></p>
  <ul>
    <code>define &lt;name&gt; Robonect &lt;ip-adress&gt [&lt;user&gt; &lt;password&gt;]</code>
    
	<p>The authentication can be supplied in the definition as plaine text or in a differen way - see the attributes. Per default the status is polled every 90s.</p>

    <p>Example:</p>
      <pre>
      define myMower Robonect 192.168.13.5 test tmySecret
      </pre>
  </ul>
  
  <p><a name="RobonectSet"></a> <b>Set</b></p>
  <ul>
	Switch the mower to automatic-timer:
    <code>set &lt;name&gt; auto</code>
	Send the mower home - prevents further runs triggered by timer (persistent):
    <code>set &lt;name&gt; home</code>
	Sends the mower home for the actual timer-slot. The next timer-slot starts the mower again:
    <code>set &lt;name&gt; feierabend</code>
	Start the mower (only needed after a manual stop:
    <code>set &lt;name&gt; start</code>
	Stop the mower immediately:
    <code>set &lt;name&gt; stop</code>
  </ul>
  <p><a name="RobonectGet"></a> <b>Get</b></p>
  <ul>  
  <p>Gets the actual state of the mower - normally not needed, because the status is polled cyclic.</p>
  </ul>
  
  <p><a name="RobonectAttr"></a> <b>Attributes</b></p>
  <ul><br>
	Common attributes:<br>
    <a href="#DbLogInclude">DbLogInclude</a><br>
	<a href="#DbLogExclude">DbLogExclude</a><br>
    <a href="#IODev">IODev</a><br>
    <a href="#alias">alias</a><br>
    <a href="#comment">comment</a><br>
    <a href="#devStateIcon">devStateIcon</a><br>
    <a href="#devStateStyle">devStateStyle</a><br>
    <a href="#do_not_notify">do_not_notify</a><br>
    <a href="#readingFnAttributes">readingFnAttributes</a><br>
    <a href="#event-aggregator">event-aggregator</a><br>
    <a href="#event-min-interval">event-min-interval</a><br>
    <a href="#event-on-change-reading">event-on-change-reading</a><br>
    <a href="#event-on-update-reading">event-on-update-reading</a><br>
    <a href="#eventMap">eventMap</a><br>
    <a href="#group">group</a><br>
    <a href="#icon">icon</a><br>
    <a href="#room">room</a><br>
    <a href="#showtime">showtime</a><br>
    <a href="#sortby">sortby</a><br>
    <a href="#stateFormat">stateFormat</a><br>
    <a href="#userReadings">userReadings</a><br>
    <a href="#userattr">userattr</a><br>
    <a href="#verbose">verbose</a><br>
    <a href="#webCmd">webCmd</a><br>
    <a href="#widgetOverride">widgetOverride</a><br>
	<br>
  </ul>

  <p><a name="RobonectCredentials"></a> <b>credentials</b></p>
  <ul> 
    If you supply a valid path to a credentials file, this combination is used to log in at robonect. This mechism overrules basicAuth.
  </ul> 

  <p><a name="RobonectBasicAuth"></a> <b>basicAuth</b></p>
  <ul> 
	You can supply username and password plain or base-64-encoded. For a base64-encoder, use google.
      <p>Example:</p>
      <pre>
      define myMower 192.168.5.1
	  attr myMower basicAuth me:mySecret
      </pre>    
	  <pre>
      define myMower 192.168.5.1
	  attr myMower basicAuth bWU6bXlTZWNyZXQ=
      </pre>    
  </ul>	

  <p><a name="RobonectPollInterval"></a> <b>pollInterval</b></p>
  <ul>
	Supplies the interval top poll the robonect in seconds. Per default 90s is set.
  </ul>
</ul>
=end html

=begin html_DE

<a name="Robonect"></a> 
<h3>Robonect</h3>
<ul>
<p>Robonect ist ein Nachr�stmodul f�r automower, die auf der Husky-G3-Steuerung basieren. Es wurde von Fabian H. entwickelt und kann unter www.robonect.de bezogen werden. Dieses Modul gibt Euch Zugriff auf die n�tigsten Kommandos. Dieses Modul ben�tigt libjson-perl. Bitte NICHT VERGESSEN zu installieren!</p>


  <p><a name="RobonectDefine"></a> <b>Define</b></p>
  <ul>
    <code>define &lt;name&gt; Robonect &lt;ip-adress&gt [&lt;user&gt; &lt;password&gt;]</code>
    
	<p>Die Zugangsinformationen k�nnen im Klartext bei der Definition angegeben werden. Wahlweise auch per Attribut. Standardm��ig wird der Status vom RObonect alle 90s aktualisiert.</p>

    <p>Beispiel:</p>
      <pre>
      define myMower Robonect 192.168.13.5 test tmySecret
      </pre>
  </ul>
  
  <p><a name="RobonectSet"></a> <b>Set</b></p>
  <ul>
	Versetzt den M�her in den timerbasierten Automatikmodus:
    <code>set &lt;name&gt; auto</code>
	Schickt den M�her nach hause. Ein erneutes Starten per Timer wird verhindert (persistent):
    <code>set &lt;name&gt; home</code>
	Schickt den M�her nach Hause. Beim n�chsten Timerstart f�hrt der M�her wieder regul�r:
    <code>set &lt;name&gt; feierabend</code>
	Startet den M�her (wird nur nach einem manuellen Stop ben�tigt):
    <code>set &lt;name&gt; start</code>
	Stoppt den M�her:
    <code>set &lt;name&gt; stop</code>
  </ul>
  <p><a name="RobonectGet"></a> <b>Get</b></p>
  <ul>  
  <p>Holt den aktuellen Status des M�hers. Wird normalerweise nicht ben�tigt, da automatisch gepolled wird.</p>
  </ul>
  
  <p><a name="RobonectAttr"></a> <b>Attributes</b></p>
  <ul><br>
	Common attributes:<br>
    <a href="#DbLogInclude">DbLogInclude</a><br>
	<a href="#DbLogExclude">DbLogExclude</a><br>
    <a href="#IODev">IODev</a><br>
    <a href="#alias">alias</a><br>
    <a href="#comment">comment</a><br>
    <a href="#devStateIcon">devStateIcon</a><br>
    <a href="#devStateStyle">devStateStyle</a><br>
    <a href="#do_not_notify">do_not_notify</a><br>
    <a href="#readingFnAttributes">readingFnAttributes</a><br>
    <a href="#event-aggregator">event-aggregator</a><br>
    <a href="#event-min-interval">event-min-interval</a><br>
    <a href="#event-on-change-reading">event-on-change-reading</a><br>
    <a href="#event-on-update-reading">event-on-update-reading</a><br>
    <a href="#eventMap">eventMap</a><br>
    <a href="#group">group</a><br>
    <a href="#icon">icon</a><br>
    <a href="#room">room</a><br>
    <a href="#showtime">showtime</a><br>
    <a href="#sortby">sortby</a><br>
    <a href="#stateFormat">stateFormat</a><br>
    <a href="#userReadings">userReadings</a><br>
    <a href="#userattr">userattr</a><br>
    <a href="#verbose">verbose</a><br>
    <a href="#webCmd">webCmd</a><br>
    <a href="#widgetOverride">widgetOverride</a><br>
	<br>
  </ul>

  <p><a name="RobonectCredentials"></a> <b>credentials</b></p>
  <ul> 
    Hier kann ein Link auf ein credentials-file angegeben werden. Die Zugansinformationen werden dann aus der Datei geholt. Dieser Mechanismus �berschreibt basicAuth.
  </ul> 

  <p><a name="RobonectBasicAuth"></a> <b>basicAuth</b></p>
  <ul> 
	Hier werden die Zugangsinformationen entweder im Klartext oder base-64-codiert �bergeben. Base64-encoder gibts bei google.
      <p>Example:</p>
      <pre>
      define myMower 192.168.5.1
	  attr myMower basicAuth me:mySecret
      </pre>    
	  <pre>
      define myMower 192.168.5.1
	  attr myMower basicAuth bWU6bXlTZWNyZXQ=
      </pre>    
  </ul>	

  <p><a name="RobonectPollInterval"></a> <b>pollInterval</b></p>
  <ul>
	Hier kann das polling-interval in Sekunden angegeben werden. Default sind 90s.
  </ul>
</ul>
=end html_DE

=cut

