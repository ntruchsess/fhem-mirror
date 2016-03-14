#################################################
#
# 70_MEDIAPORTAL.pm
# Connects to a running MediaPortal instance via the WifiRemote plugin
#
# $Id$
#
# Changed, adopted and new copyrighted by Reiner Leins (Reinerlein), (c) in February 2016
# Original Copyright by Andreas Kwasnik (gemx)
#
# Fhem is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# Fhem is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
########################################################################################
# Changelog
# 14.03.2016
#	Es gibt nun ein Attribut "HeartbeatInterval", mit dem das Intervall für die Verbindungsprüfung festgelegt werden kann. Ein Wert von "0" deaktiviert die Prüfung.
#	Es gibt nun das Attribut "disable", mit dem das Modul deaktiviert werden kann.
# 08.02.2016
#	Neuer MediaType "recording" hinzugefügt
# 07.02.2016
#	In das offizielle Fhem-Release übernommen
#	Allgemein im Code aufgeräumt
#	Dokumentation hinzugefügt
#	Umlautproblem bei der Titelanzeige behoben
#	Mehr Readings befüllt, die sowieso geliefert werden. Dazu gehören z.B. Titelinformationen bei TV, Beschreibungen und die Informationen über den nächsten Titel.
#	$readingsFnAttributes hinzugefügt. Damit geht z.B. stateFormat oder event-on-change-reading
#	Fehlende Titelanzeige bei initialem Start der Wiedergabe behoben
#	WakeUp und Sleep hinzugefügt, damit man schnell den entsprechenden Mediaportal-Rechner hochfahren bzw. in den Hibernate-Modus schalten kann. Dazu wurde ein Attribut "macaddress" eingeführt.
#	Mögliche Parameter für Get und Set angegeben, sodass diese in FhemWeb entsprechend angeboten werden.
#	Volume umbenannt, damit das Reading die Grundlage für die Lautstärkeauswahl (Slider) ist.
#	Es gibt jetzt ein Attribut "generateNowPlayingUpdateEvents", mit dem man die Generierung von (bei der Wiedergabe) sekündlichen Aktualisierungen an-/abschalten kann
#	Die Mac-Adresse, die für das Aufwecken benötigt wird, wird nun automatisch ermittelt.
#	Die Read-Callbackfunktion wurde überarbeitet, da in einigen Fällen halbe Nachrichten zu einem Freeze geführt hatten.
#	Es gibt jetzt einen Setter "reconnect", der eine neue Verbindung zu Mediaportal aufbaut.
#	Wenn festgestellt wird, dass eine Verbindung zu Mediaportal nicht mehr lebendig ist, wird ein reconnect ausgeführt.
#
##############################################################################
package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use DevIo;
use JSON;
use HttpUtils;

use Data::Dumper;

# Forward-Declarations
sub MEDIAPORTAL_Set($@);
sub MEDIAPORTAL_Log($$$);

my $MEDIAPORTAL_HeartbeatInterval = 15;

########################################################################################
#
#  MEDIAPORTAL_Initialize
#
########################################################################################
sub MEDIAPORTAL_Initialize($) {
	my ($hash) = @_;
	
	require "$attr{global}{modpath}/FHEM/DevIo.pm";
	
	$hash->{ReadFn} = 'MEDIAPORTAL_Read';
	$hash->{ReadyFn} = 'MEDIAPORTAL_Ready';
	$hash->{GetFn} = 'MEDIAPORTAL_Get';
	$hash->{SetFn} = 'MEDIAPORTAL_Set';
	$hash->{DefFn} = 'MEDIAPORTAL_Define';
	$hash->{UndefFn} = 'MEDIAPORTAL_Undef';
	$hash->{AttrFn} = 'MEDIAPORTAL_Attribute';
	$hash->{AttrList} = 'authmethod:none,userpassword,passcode,both username password HeartbeatInterval generateNowPlayingUpdateEvents:1,0 macaddress '.$readingFnAttributes;
	
	$hash->{STATE} = 'Initialized';
}

########################################################################################
#
#  MEDIAPORTAL_Define
#
########################################################################################
sub MEDIAPORTAL_Define($$) {
	my ($hash, $def) = @_;
	
	my @a = split("[ \t][ \t]*", $def);
	if(@a != 3) {
		my $msg = 'wrong syntax: define <name> MEDIAPORTAL ip[:port]';
		MEDIAPORTAL_Log $hash->{NAME}, 2, $msg;
		return $msg;
	}
	DevIo_CloseDev($hash);
	
	my $name = $a[0];
	my $dev = $a[2];
	$dev .= ":8017" if ($dev !~ m/:/ && $dev ne "none" && $dev !~ m/\@/);
	
	$hash->{DeviceName} = $dev;
	$hash->{STATE} = 'Disconnected';
	
	my $ret = undef;
	$ret = DevIo_OpenDev($hash, 0, 'MEDIAPORTAL_DoInit') if AttrVal($hash->{NAME}, 'disable', 0);
	
	return $ret;
}

########################################################################################
#
#  MEDIAPORTAL_Undef
#
########################################################################################
sub MEDIAPORTAL_Undef($$) {
	my ($hash, $arg) = @_;
	
	RemoveInternalTimer($hash);
	DevIo_CloseDev($hash); 
	
	return undef;
}

########################################################################################
#
#  MEDIAPORTAL_Attribute
#
########################################################################################
sub MEDIAPORTAL_Attribute($@) {
	my ($mode, $devName, $attrName, $attrValue) = @_;
	my $hash = $defs{$devName};
	
	my $disableChange = 0;
	if($mode eq 'set') {
		if ($attrName eq 'disable') {
			if ($attrValue && AttrVal($devName, $attrName, 0) != 1) {
				MEDIAPORTAL_Log($devName, 5, 'Neu-Disabled');
				$disableChange = 1;
			}
			
			if (!$attrValue && AttrVal($devName, $attrName, 0) != 0) {
				MEDIAPORTAL_Log($devName, 5, 'Neu-Enabled');
				$disableChange = 1;
			}
		}
	} elsif ($mode eq 'del') {
		if ($attrName eq 'disable') {
			if (AttrVal($devName, $attrName, 0) != 0) {
				MEDIAPORTAL_Log($devName, 5, 'Deleted-Disabled');
				$disableChange = 1;
				$attrValue = 0;
			}
		}
	}
	
	if ($disableChange) {
		# Wenn die Verbindung beendet werden muss...
		if ($attrValue) {
			MEDIAPORTAL_Log $devName, 5, 'Call AttributeFn: Stop Connection...';
			DevIo_CloseDev($hash);
		}
		
		# Wenn die Verbindung gestartet werden muss...
		if (!$attrValue) {
			MEDIAPORTAL_Log $devName, 5, 'Call AttributeFn: Start Connection...';
			DevIo_OpenDev($hash, 0, 'MEDIAPORTAL_DoInit');
		}
	}
	
	return undef;
}

########################################################################################
#
#  MEDIAPORTAL_DoInit
#
########################################################################################
sub MEDIAPORTAL_DoInit($) {
	my ($hash) = @_;
	
	$hash->{STATE} = 'Connecting...';
	$hash->{helper}{buffer} = '';
	$hash->{helper}{LastStatusTimestamp} = time();
	
	# Versuch, die MAC-Adresse des Ziels selber herauszufinden...
	if (AttrVal($hash->{NAME}, 'macaddress', '') eq '') {
		my $newmac = MEDIAPORTAL_GetMAC($hash);
		
		if (defined($newmac)) {
			CommandAttr(undef, $hash->{NAME}.' macaddress '.$newmac);
		}
	}
	
	RemoveInternalTimer($hash);
	InternalTimer(gettimeofday() + AttrVal($hash->{NAME}, 'HeartbeatInterval', $MEDIAPORTAL_HeartbeatInterval), 'MEDIAPORTAL_GetIntervalStatus', $hash, 0) if AttrVal($hash->{NAME}, 'HeartbeatInterval', $MEDIAPORTAL_HeartbeatInterval);
	
	return undef;
}

########################################################################################
#
#  MEDIAPORTAL_Ready
#
########################################################################################
sub MEDIAPORTAL_Ready($) {
	my ($hash) = @_;
	
	return DevIo_OpenDev($hash, 1, 'MEDIAPORTAL_DoInit');
}

########################################################################################
#
#  MEDIAPORTAL_Get
#
########################################################################################
sub MEDIAPORTAL_Get($@) {
	my ($hash, @a) = @_;
	
	my $cname = $a[1];
	my $cmd = '';
	
	return 'Module disabled!' if AttrVal($hash->{NAME}, 'disable', 0);
	
	if ($cname eq "status") {
		$cmd = "{\"Type\":\"requeststatus\"}\r\n";
	} elsif ($cname eq "nowplaying") {
		$cmd = "{\"Type\":\"requestnowplaying\"}\r\n";
	} elsif ($cname eq "notify") {
		$cmd = '{"Type":"properties","Properties":["#Play.Current.Title","#TV.View.title"]}'."\r\n";
	} else {
		return "Unknown command '$cname', choose one of status:noArg nowplaying:noArg";
	}
	
	DevIo_SimpleWrite($hash, $cmd, 0);
	return undef;
}

########################################################################################
#
#  MEDIAPORTAL_GetStatus
#
########################################################################################
sub MEDIAPORTAL_GetStatus($) {
	my ($hash) = @_;
	
	MEDIAPORTAL_Get($hash, ($hash->{NAME}, 'status'));
}

########################################################################################
#
#  MEDIAPORTAL_GetIntervalStatus
#
########################################################################################
sub MEDIAPORTAL_GetIntervalStatus($) {
	my ($hash) = @_;
	
	return undef if (ReadingsVal($hash->{NAME}, 'state', 'disconnected') eq 'disconnected');
	return undef if (!AttrVal($hash->{NAME}, 'HeartbeatInterval', $MEDIAPORTAL_HeartbeatInterval));
	
	# Prüfen, wann der letzte Status zugestellt wurde...
	if (time() - $hash->{helper}{LastStatusTimestamp} > (2 * $MEDIAPORTAL_HeartbeatInterval + 5)) {
		MEDIAPORTAL_Log $hash->{NAME}, 3, 'GetIntervalStatus hat festgestellt, dass Mediaportal sich seit '.(time() - $hash->{helper}{LastStatusTimestamp}).'s nicht zurückgemeldet hat. Die Verbindung wird neu aufgebaut!';
		
		MEDIAPORTAL_Set($hash, ($hash->{NAME}, 'reconnect'));
		InternalTimer(gettimeofday() + AttrVal($hash->{NAME}, 'HeartbeatInterval', $MEDIAPORTAL_HeartbeatInterval), 'MEDIAPORTAL_GetIntervalStatus', $hash, 0);
		
		return undef;
	}
	
	# Status anfordern...
	MEDIAPORTAL_Get($hash, ($hash->{NAME}, 'status'));
	InternalTimer(gettimeofday() + AttrVal($hash->{NAME}, 'HeartbeatInterval', $MEDIAPORTAL_HeartbeatInterval), 'MEDIAPORTAL_GetIntervalStatus', $hash, 0);
}

########################################################################################
#
#  MEDIAPORTAL_GetNowPlaying
#
########################################################################################
sub MEDIAPORTAL_GetNowPlaying($) {
	my ($hash) = @_;
	
	MEDIAPORTAL_Get($hash, ($hash->{NAME}, 'nowplaying'));
}

########################################################################################
#
#  MEDIAPORTAL_Set
#
########################################################################################
sub MEDIAPORTAL_Set($@) {
	my ($hash, @a) = @_;
	
	my $cname = $a[1];
	my $cmd = '';
	my $powermodes = 'logoff suspend hibernate reboot shutdown exit';
	my $mpcommands = 'stop record pause play rewind forward replay skip back info menu up down left right ok volup voldown volmute chup chdown dvdmenu 0 1 2 3 4 5 6 7 8 9 0 clear enter teletext red blue yellow green home basichome nowplaying tvguide tvrecs dvd playlists first last fullscreen subtitles audiotrack screenshot';
	my $playlistcommands = 'play loadlist loadlist_shuffle loadfrompath loadfrompath_shuffle';
	
	# Legacy Volume writing...
	$cname = 'Volume' if (lc($cname) eq 'volume');
	
	return 'Module disabled!' if AttrVal($hash->{NAME}, 'disable', 0);
	
	if ($cname eq "command") {
		if (!MEDIAPORTAL_isInList($a[2], split(/ /, $mpcommands))) { 
			return "Unknown command '$a[2]'. Supported commands are: $mpcommands";
		}
		
		$cmd = "{\"Type\":\"command\",\"Command\":\"$a[2]\"}\r\n";
	} elsif ($cname eq "wakeup") {
		my $macaddress = AttrVal($hash->{NAME}, 'macaddress', '');
		
		if ($macaddress ne '') {
			MEDIAPORTAL_Wakeup($macaddress);
			return 'WakeUp-Signal sent!';
		} else {
			return 'No MacAddress set! No WakeUp-Signal sent!';
		}
	} elsif ($cname eq "sleep") {
		return MEDIAPORTAL_Set($hash, ($hash->{NAME}, 'powermode', 'hibernate'));
	} elsif ($cname eq "key") {
		$cmd = "{\"Type\":\"key\",\"Key\":\"$a[2]\"}\r\n";
	} elsif ($cname eq "Volume") {
		if (($a[2] ne $a[2]+0) || ($a[2]<0) || ($a[2]>100)) { 
			return "the volume must be in the range 0..100";
		}
		
		$cmd = "{\"Type\":\"volume\",\"Volume\":$a[2]}\r\n";
	} elsif ($cname eq "powermode") {
		if (!MEDIAPORTAL_isInList($a[2], split(/ /, $powermodes))) {
			return "Unknown powermode '$a[2]'. Supported powermodes are: $powermodes";
		}
		
		$cmd = "{\"Type\":\"powermode\",\"PowerMode\":\"$a[2]\"}\r\n";
	} elsif ($cname eq "playfile") {
		$cmd = "{\"Type\":\"playfile\",\"FileType\":\"$a[2]\",\"Filepath\":\"$a[3]\"}\r\n";
	} elsif ($cname eq "playchannel") {
		if ($a[2] ne $a[2]+0) { 
			return "playchannel needs a valid channelid of type int";
		}
		
		$cmd = "{\"Type\":\"playchannel\",\"ChannelId\":$a[2]}\r\n";
	} elsif ($cname eq "playradiochannel") {
		if ($a[2] ne $a[2]+0) { 
			return "playradiochannel needs a valid channelid of type int";
		}
		
		$cmd = "{\"Type\":\"playradiochannel\",\"ChannelId\":$a[2]}\r\n";	
	} elsif ($cname eq "playlist") {
		if (!MEDIAPORTAL_isInList($a[2], split(/ /, $playlistcommands))) { 
			return "Unknown playlist command '$a[2]'. Supported commands are: $playlistcommands";
		}
		
		if ($a[2] eq "play") {
			if ($a[3] ne $a[3]+0) { 
				return "playlist play needs a valid index to start of type int";
			}
			
			$cmd = "{\"Type\":\"playlist\",\"PlaylistAction\":\"play\",\"Index\":$a[3]}\r\n";
		} elsif ($a[2] eq "loadlist") {
			$cmd = "{\"Type\":\"playlist\",\"PlaylistAction\":\"load\",\"PlaylistName\":\"$a[3]\"}\r\n";
		} elsif ($a[2] eq "loadlist_shuffle") {
			$cmd = "{\"Type\":\"playlist\",\"PlaylistAction\":\"load\",\"PlaylistName\":\"$a[3]\",\"Shuffle\":true}\r\n";
		} elsif ($a[2] eq "loadfrompath") {
			$cmd = "{\"Type\":\"playlist\",\"PlaylistAction\":\"load\",\"PlaylistPath\":\"$a[3]\"}\r\n";
		} elsif ($a[2] eq "loadfrompath_shuffle") {
			$cmd = "{\"Type\":\"playlist\",\"PlaylistAction\":\"load\",\"PlaylistPath\":\"$a[3]\",\"Shuffle\":true}\r\n";
		}
	} elsif ($cname eq "connect") {
		$hash->{NEXT_OPEN} = 0; # force NEXT_OPEN used in DevIO
		
		return undef;
	} elsif ($cname eq "reconnect") {
		DevIo_CloseDev($hash);
		select(undef, undef, undef, 0.2);
		DevIo_OpenDev($hash, 0, 'MEDIAPORTAL_DoInit');
		
		return undef;
	} else {
		return "Unknown command '$cname', choose one of wakeup:noArg sleep:noArg connect:noArg reconnect:noArg command:".join(',', split(/ /, $mpcommands))." key Volume:slider,0,1,100 powermode:".join(',', split(/ /, $powermodes))." playfile playchannel playradiochannel playlist";
	}
	
	DevIo_SimpleWrite($hash, $cmd, 0);
	return undef;
}

########################################################################################
#
#  MEDIAPORTAL_Read
#  Receives an event and creates several readings for event triggering
#
########################################################################################
sub MEDIAPORTAL_Read($) {
	my ($hash) = @_;
	
	my $buf = DevIo_SimpleRead($hash);
	if(!defined($buf)) {
		MEDIAPORTAL_Log $hash->{NAME}, 3, 'DevIo_SimpleRead hat keine Daten geliefert, obwohl Read aufgerufen wurde! Setze Buffer zurück. Aktueller Buffer: '.$hash->{helper}{buffer};
		$hash->{helper}{buffer} = '';
		return undef;
	}
	
	return undef if AttrVal($hash->{NAME}, 'disable', 0);
	
	MEDIAPORTAL_Log $hash->{NAME}, 5, "RAW MSG: $buf";
	
	# Zum Buffer hinzufügen
	$hash->{helper}{buffer} .= $buf;
	
	# Bereits vollständige JSON-Strings verarbeiten...
	my @groups = $hash->{helper}{buffer} =~ m/({(?:[^{}]++|(?1))*})/xg;
	for my $elem (@groups) {
		MEDIAPORTAL_ProcessMessage($hash, $elem);
	}
	
	# Bereits verarbeitetes aus dem Buffer wieder entfernen...
	$hash->{helper}{buffer} =~ s/[ \r\n]*({(?:[^{}]++|(?1))*})[ \r\n]*//xg;
	
	return undef;
}

########################################################################################
#
#  MEDIAPORTAL_ProcessMessage
#
########################################################################################
sub MEDIAPORTAL_ProcessMessage($$) {
	my ($hash, $msg) = @_;
	
	MEDIAPORTAL_Log $hash->{NAME}, 5, "Message received: $msg";
	
	my $json = {};
	eval {
		$json = from_json($msg);
	};
	if ($@) {
		MEDIAPORTAL_Log $hash->{NAME}, 5, "Error during JSON-Parser with 'from_json()'-call (but just keep trying another way): $@";
		
		eval {
			$json = decode_json(decode('iso8859-1', $msg));
		};
		if ($@) {
			MEDIAPORTAL_Log $hash->{NAME}, 1, "Final Error during JSON-Parser: $@";
			return;
		}
	}
	
	if (defined($json->{Type})) {
		if ($json->{Type} eq "welcome") {
			MEDIAPORTAL_Log $hash->{NAME}, 4, 'WELCOME received. Sending identify message.';
			
			DevIo_SimpleWrite($hash, MEDIAPORTAL_GetMSG_identify($hash), 0);
		} elsif ($json->{Type} eq "authenticationresponse") {
			MEDIAPORTAL_Log $hash->{NAME}, 4, "AUTHRESPONSE received. SUCCESS=$json->{Success}";
			
			$hash->{STATE} = "Authenticated. Processing messages.";
		} elsif ($json->{Type} eq "status") {
			MEDIAPORTAL_Log $hash->{NAME}, 4, 'STATUS received.';
			
			my $playStatus = 'Stopped';
			$playStatus = 'Playing' if ($json->{IsPlaying});
			$playStatus = 'Paused' if ($json->{IsPaused});
			
			my $title = '';
			$title = $json->{Title} if (defined($json->{Title}) && $json->{Title});
			if (defined($json->{SelectedItem}) && $json->{SelectedItem} ne '' && $title eq '') {
				$title = 'Auswahl: '.$json->{SelectedItem};
				
				# Wenn der Titel während des Abspielens nicht mitgeliefert wurde, dann für später nochmal anfordern...
				# Das ist ein Bug in Wifiremote, das den Titel beim Start nicht immer mitliefert.
				if ($json->{IsPlaying}) {
					InternalTimer(gettimeofday() + 5, 'MEDIAPORTAL_GetNowPlaying', $hash, 0);
				}
			}
			
			readingsBeginUpdate($hash);
			readingsBulkUpdate($hash, 'IsPlaying', $json->{IsPlaying});
			readingsBulkUpdate($hash, 'IsPaused', $json->{IsPaused});
			readingsBulkUpdate($hash, 'playStatus', $playStatus);
			readingsBulkUpdate($hash, 'CurrentModule', $json->{CurrentModule});
			readingsBulkUpdate($hash, 'Title', $title);
			readingsEndUpdate($hash, 1);
			
			$hash->{helper}{LastStatusTitle} = $title;
			$hash->{helper}{LastStatusTimestamp} = time();
		} elsif ($json->{Type} eq "volume") {
			MEDIAPORTAL_Log $hash->{NAME}, 4, 'VOLUME received.';
			
			readingsBeginUpdate($hash);
			readingsBulkUpdate($hash, 'Volume', $json->{Volume});
			readingsBulkUpdate($hash, 'IsMuted', $json->{IsMuted});
			readingsEndUpdate($hash, 1);
		} elsif ($json->{Type} eq "nowplaying") {
			MEDIAPORTAL_Log $hash->{NAME}, 4, 'NOWPLAYING received.';
			
			readingsBeginUpdate($hash);
			
			readingsBulkUpdate($hash, 'Duration', MEDIAPORTAL_ConvertSecondsToTime($json->{Duration}));
			readingsBulkUpdate($hash, 'Position', MEDIAPORTAL_ConvertSecondsToTime($json->{Position}));
			readingsBulkUpdate($hash, 'File', $json->{File});
			
			readingsBulkUpdate($hash, 'Title', '');
			readingsBulkUpdate($hash, 'Description', '');
			readingsBulkUpdate($hash, 'nextTitle', '');
			readingsBulkUpdate($hash, 'nextDescription', '');
			
			if (defined($json->{MediaInfo})) {
				if ($json->{MediaInfo}{MediaType} eq 'tv') {
					readingsBulkUpdate($hash, 'Title', $json->{MediaInfo}{ChannelName}.' - '.$json->{MediaInfo}{CurrentProgramName});
					readingsBulkUpdate($hash, 'Description', $json->{MediaInfo}{CurrentProgramDescription});
					
					if (defined($json->{MediaInfo}{NextProgramName})) {
						readingsBulkUpdate($hash, 'nextTitle', $json->{MediaInfo}{ChannelName}.' - '.$json->{MediaInfo}{NextProgramName});
						readingsBulkUpdate($hash, 'nextDescription', $json->{MediaInfo}{NextProgramDescription});
					}
				} elsif ($json->{MediaInfo}{MediaType} eq 'movie') {
					readingsBulkUpdate($hash, 'Title', $json->{MediaInfo}{Title});
					readingsBulkUpdate($hash, 'Description', $json->{MediaInfo}{Summary});
				} elsif ($json->{MediaInfo}{MediaType} eq 'series') {
					readingsBulkUpdate($hash, 'Title', $json->{MediaInfo}{Series}.' '.$json->{MediaInfo}{Season}.'x'.$json->{MediaInfo}{Episode}.' - '.$json->{MediaInfo}{Title});
					readingsBulkUpdate($hash, 'Description', $json->{MediaInfo}{Plot});
				} elsif ($json->{MediaInfo}{MediaType} eq 'recording') {
					readingsBulkUpdate($hash, 'Title', $json->{MediaInfo}{ChannelName}.' - '.$json->{MediaInfo}{ProgramName});
					readingsBulkUpdate($hash, 'Description', $json->{MediaInfo}{ProgramDescription});
				} else {
					MEDIAPORTAL_Log $hash->{NAME}, 0, 'Unbekannte MediaInfo für "'.$json->{MediaInfo}{MediaType}.'" geliefert, aber nicht verarbeitet. Bitte diese komplette Information ins Forum einstellen: '.Dumper($json->{MediaInfo});
				}
			} else {
				# Die MediaInfos wurden nicht mitgeliefert...
				# Hier nochmal versuchen, den Titel zu extrahieren...
				my $title = '';
				$title = $json->{Title} if (defined($json->{Title}) && $json->{Title});
				
				if ($title eq '') {
					readingsBulkUpdate($hash, 'Title', $hash->{helper}{LastStatusTitle});
				} else {
					readingsBulkUpdate($hash, 'Title', $title);
				}
			}
			
			readingsEndUpdate($hash, 1);
		} elsif ($json->{Type} eq "nowplayingupdate") {
			MEDIAPORTAL_Log $hash->{NAME}, 4, 'NOWPLAYINGUPDATE received.';
			
			readingsBeginUpdate($hash);
			readingsBulkUpdate($hash, 'Duration', MEDIAPORTAL_ConvertSecondsToTime($json->{Duration}));
			readingsBulkUpdate($hash, 'Position', MEDIAPORTAL_ConvertSecondsToTime($json->{Position}));
			readingsEndUpdate($hash, AttrVal($hash->{NAME}, 'generateNowPlayingUpdateEvents', 0));
		} elsif ($json->{Type} eq "properties") {
			MEDIAPORTAL_Log $hash->{NAME}, 4, 'PROPERTIES received.';
			
			MEDIAPORTAL_Log undef, 4, 'JSON: '.Dumper($json);
		} elsif ($json->{Type} eq "facadeinfo") {
			MEDIAPORTAL_Log $hash->{NAME}, 4, 'FACADEINFO5 received.';
		} elsif ($json->{Type} eq "dialog") {
			MEDIAPORTAL_Log $hash->{NAME}, 4, 'DIALOG received.';
		} else {
			MEDIAPORTAL_Log $hash->{NAME}, 1, "Unhandled message received: MessageType '$json->{Type}'";
		}
	} else {
		MEDIAPORTAL_Log $hash->{NAME}, 1, 'Unhandled message received without any Messagetype: '.$msg;
	}
}

########################################################################################
#
#  MEDIAPORTAL_GetMSG_identify
#
########################################################################################
sub MEDIAPORTAL_GetMSG_identify($) {
	my ($hash) = @_;
	
	my $authmethod=AttrVal($hash->{NAME}, 'authmethod', 'none');
	my $uid = AttrVal($hash->{NAME}, 'username', '');
	my $pwd = AttrVal($hash->{NAME}, 'password', '');
	my $cmd = { 
		Type => 'identify',
		Name => 'MP_Connector',
		Application => 'FHEM',
		Version => '1.0'
	};
	if ($authmethod ne "none") {
		$cmd->{Authenticate}{AuthMethod} = $authmethod;
		$cmd->{Authenticate}{User} = $uid;
		$cmd->{Authenticate}{Password} = $pwd;
	}
	my $strcmd = encode_json($cmd)."\r\n";
	
	return $strcmd;
}

########################################################################################
#
#  MEDIAPORTAL_GetMAC
#
########################################################################################
sub MEDIAPORTAL_GetMAC($) {
	my ($hash) = @_;
	my $mac = undef;
	
	eval {
		my ($host, $port) = split(/:/, $hash->{DeviceName});
		
		my $result = qx/arp -a $host/;
		MEDIAPORTAL_Log undef, 5, 'ARP-SysCall: '.$result;
		
		$mac = uc($1) if ($result =~ m/([0-9a-fA-F]{2}(:|-)[0-9a-fA-F]{2}(:|-)[0-9a-fA-F]{2}(:|-)[0-9a-fA-F]{2}(:|-)[0-9a-fA-F]{2}(:|-)[0-9a-fA-F]{2})/s);
		$mac =~ s/-/:/g if (defined($mac)); # Korrektur für Windows-Rechner
		
		if (defined($mac)) {
			MEDIAPORTAL_Log undef, 5, 'Found Mac: '.$mac;
		} else {
			MEDIAPORTAL_Log undef, 5, 'No Mac Found!';
		}
	};
	if ($@) {
		return undef;
	}
	
	return undef if (defined($mac) && ($mac eq '00:00:00:00:00:00')); # Unter Windows wird im Fehlerfall diese Adresse zurückgegeben.
	return $mac;
}

########################################################################################
#
#  MEDIAPORTAL_Wakeup
#
########################################################################################
sub MEDIAPORTAL_Wakeup($;$$) {
	my ($hwaddr, $ipaddr, $port) = @_;
	
	$ipaddr = '255.255.255.255' if (!defined($ipaddr));
	$port = getservbyname('discard', 'udp') if (!defined($port));
	
	# Zur Sicherheit zweimal senden...
	return MEDIAPORTAL_DoWakeup($hwaddr, $ipaddr, $port) || MEDIAPORTAL_DoWakeup($hwaddr, $ipaddr, $port);
}

########################################################################################
#
#  MEDIAPORTAL_DoWakeup
#
########################################################################################
sub MEDIAPORTAL_DoWakeup($;$$) {
	my ($hwaddr, $ipaddr, $port) = @_;
	
	$ipaddr = '255.255.255.255' if (!defined($ipaddr));
	$port = getservbyname('discard', 'udp') if (!defined($port));
	
	# Validate hardware address (ethernet address)
	my $hwaddr_re = join(':', ('[0-9A-Fa-f]{1,2}') x 6);
	if ($hwaddr !~ m/^$hwaddr_re$/) {
		warn "Invalid hardware address: $hwaddr\n";
		return undef;
	}

	# Generate magic sequence
	my $pkt = '';
	foreach (split /:/, $hwaddr) {
		$pkt .= chr(hex($_));
	}
	$pkt = chr(0xFF) x 6 . $pkt x 16;

	# Allocate socket and send packet
	my $raddr = gethostbyname($ipaddr);
	my $them = pack_sockaddr_in($port, $raddr);
	my $proto = getprotobyname('udp');

	socket(S, AF_INET, SOCK_DGRAM, $proto) or die "socket : $!";
	setsockopt(S, SOL_SOCKET, SO_BROADCAST, 1) or die "setsockopt : $!";
	
	send(S, $pkt, 0, $them) or die "send : $!";
	close S;
	
	return 1;
}

########################################################################################
#
#  MEDIAPORTAL_ConvertSecondsToTime
#
########################################################################################
sub MEDIAPORTAL_ConvertSecondsToTime($) {
	my ($seconds) = @_;
	
	return sprintf('%01d:%02d:%02d', $seconds / 3600, ($seconds%3600) / 60, $seconds%60) if ($seconds > 0);
	return '0:00:00';
}

########################################################################################
#
#  MEDIAPORTAL_isInList
#
########################################################################################
sub MEDIAPORTAL_isInList($@) {
	my($search, @list) = @_;
	
	return 1 if MEDIAPORTAL_posInList($search, @list) >= 0;
	return 0;
}

########################################################################################
#
#  MEDIAPORTAL_posInList
#
########################################################################################
sub MEDIAPORTAL_posInList($@) {
	my($search, @list) = @_;
	
	for (my $i = 0; $i <= $#list; $i++) {
		return $i if ($list[$i] && $search eq $list[$i]);
	}
	
	return -1;
}

########################################################################################
#
#  MEDIAPORTAL_Log - Log to the normal Log-command with the prefix 'SONOSPLAYER'
#
########################################################################################
sub MEDIAPORTAL_Log($$$) {
	my ($devicename, $level, $text) = @_;
	  
	Log3 $devicename, $level, 'MEDIAPORTAL: '.$text;
}

1;

=pod
=begin html

<a name="MEDIAPORTAL"></a>
<h3>MEDIAPORTAL</h3>
<p>Connects to a running MediaPortal instance via the WifiRemote plugin</p>
<h4>Example</h4>
<p>
<code>define wohnzimmer_Mediaportal MEDIAPORTAL 192.168.0.47:8017</code>
</p>
<a name="MEDIAPORTALdefine"></a>
<h4>Define</h4>
<b><code>define &lt;name&gt; MEDIAPORTAL host[:port]</code></b>
        <br /><br /> Define a Mediaportal interface to communicate with a Wifiremote-Plugin of a Mediaportal-System.<br />
<p>
<b><code>host[:port]</code></b><br />The name and port of the Mediaportal-Wifiremote-Plugin. If Port is not given, the default of <code>8017</code> will be used.</p>
<a name="MEDIAPORTALset"></a>
<h4>Set</h4>
<ul>
<li><b>Common Tasks</b><ul>
<li><a name="MEDIAPORTAL_setter_connect">
<b><code>connect</code></b></a>
<br />Connects to Mediaportal immediately without waiting for the normal Fhem-Timeout for reconnect (30s).</li>
<li><a name="MEDIAPORTAL_setter_powermode">
<b><code>powermode &lt;mode&gt;</code></b></a>
<br />One of (logoff, suspend, hibernate, reboot, shutdown, exit). Sets the powermode, e.g. shutdown, for shutdown the computersystem of the Mediaportal-System.</li>
<li><a name="MEDIAPORTAL_setter_reconnect">
<b><code>reconnect</code></b></a>
<br />Re-Connects to Mediaportal immediately.</li>
</ul></li>
<li><b>Control-Commands</b><ul>
<li><a name="MEDIAPORTAL_setter_command">
<b><code>command &lt;command&gt;</code></b></a>
<br />One of (stop, record, pause, play, rewind, forward, replay, skip, back, info, menu, up, down, left, right, ok, volup, voldown, volmute, chup, chdown, dvdmenu, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0, clear, enter, teletext, red, blue, yellow, green, home, basichome, nowplaying, tvguide, tvrecs, dvd, playlists, first, last, fullscreen, subtitles, audiotrack, screenshot). Sends the given command to the player.</li>
<li><a name="MEDIAPORTAL_setter_key">
<b><code>key &lt;keyvalue&gt;</code></b></a>
<br />Sends the given key to the player.</li>
<li><a name="MEDIAPORTAL_setter_sleep">
<b><code>sleep</code></b></a>
<br />Sends the hinernate-signal to Mediaportal. This command is a shortcut for "powermode hibernate"</li>
<li><a name="MEDIAPORTAL_setter_wakeup">
<b><code>wakeup</code></b></a>
<br />Wakes the Mediaportal-System up (WakeUp-On-LAN).</li>
</ul></li>
<li><b>Play-Commands</b><ul>
<li><a name="MEDIAPORTAL_setter_playchannel">
<b><code>playchannel &lt;channelID&gt;</code></b></a>
<br />Plays the channel with the given ID.</li>
<li><a name="MEDIAPORTAL_setter_playfile">
<b><code>playfile &lt;fileType&gt; &lt;filePath&gt;</code></b></a>
<br />Plays the given file with the given type. FileType can be one of (audio, video).</li>
<li><a name="MEDIAPORTAL_setter_playlist">
<b><code>playlist &lt;command&gt; &lt;param&gt;</code></b></a>
<br />Sends the given playlistcommand with the given parameter. Command can be one of (play, loadlist, loadlist_shuffle, loadfrompath, loadfrompath_shuffle).</li>
<li><a name="MEDIAPORTAL_setter_Volume">
<b><code>Volume &lt;volumelevel&gt;</code></b></a>
<br />Sets the Volume to the given value.</li>
</ul></li>
</ul>
<a name="MEDIAPORTALget"></a> 
<h4>Get</h4>
<ul>
<li><b>Common Tasks</b><ul>
<li><a name="MEDIAPORTAL_getter_status">
<b><code>status</code></b></a>
<br />Call for the answer of a <code>status</code>-Message. e.g. Asynchronously retrieves the information of "Title" and "PlayStatus".</li>
<li><a name="MEDIAPORTAL_getter_nowplaying">
<b><code>nowplaying</code></b></a>
<br />Call for the answer of a <code>nowplaying</code>-Message. e.g. Asynchronously retrieves the information of "Duration", "Position" and "File"".</li>
</ul></li>
</ul>
<a name="MEDIAPORTALattr"></a>
<h4>Attributes</h4>
<ul>
<li><b>Common</b><ul>
<li><a name="MEDIAPORTAL_attribut_disable"><b><code>disable &lt;value&gt;</code></b>
</a><br />One of (0, 1). With this attribute you can disable the module.</li>
<li><a name="MEDIAPORTAL_attribut_generateNowPlayingUpdateEvents"><b><code>generateNowPlayingUpdateEvents &lt;value&gt;</code></b>
</a><br />One of (0, 1). With this value you can disable (or enable) the generation of <code>NowPlayingUpdate</code>-Events. If set, Fhem generates an event per second with the updated time-values for the current playing. Defaults to "0".</li>
<li><a name="MEDIAPORTAL_attribut_HeartbeatInterval"><b><code>HeartbeatInterval &lt;interval&gt;</code></b>
</a><br />In seconds. Defines the heartbeat interval in seconds which is used for testing the correct work of the connection to Mediaportal. A value of 0 deactivate the heartbeat-check. Defaults to "15".</li>
<li><a name="MEDIAPORTAL_attribut_macaddress"><b><code>macaddress &lt;address&gt;</code></b>
</a><br />Sets the MAC-Address for the Player. This is needed for WakeUp-Function. e.g. "90:E6:BA:C2:96:15"</li>
</ul></li>
<li><b>Authentication</b><ul>
<li><a name="MEDIAPORTAL_attribut_authmethod"><b><code>authmethod &lt;value&gt;</code></b>
</a><br />One of (none, userpassword, passcode, both). With this value you can set the authentication-mode.</li>
<li><a name="MEDIAPORTAL_attribut_password"><b><code>password &lt;value&gt;</code></b>
</a><br />With this value you can set the password for authentication.</li>
<li><a name="MEDIAPORTAL_attribut_username"><b><code>username &lt;value&gt;</code></b>
</a><br />With this value you can set the username for authentication.</li>
</ul></li>
</ul>

=end html

=begin html_DE

<a name="MEDIAPORTAL"></a>
<h3>MEDIAPORTAL</h3>
<p>Verbindet sich über das Wifiremote-Plugin mit einer laufenden Mediaportal-Instanz.</p>
<h4>Beispiel</h4>
<p>
<code>define wohnzimmer_Mediaportal MEDIAPORTAL 192.168.0.47:8017</code>
</p>
<a name="MEDIAPORTALdefine"></a>
<h4>Define</h4>
<b><code>define &lt;name&gt; MEDIAPORTAL host[:port]</code></b>
        <br /><br />Definiert ein Mediaportal Interface für die Kommunikation mit einem Wifiremote-Plugin einer Mediaportal Installation.<br />
<p>
<b><code>host[:port]</code></b><br />Der Hostname und der Port eines laufenden Mediaportal-Wifiremote-Plugins. Wenn der Port nicht angegeben wurde, wird <code>8017</code> als Standard verwendet.</p>
<a name="MEDIAPORTALset"></a>
<h4>Set</h4>
<ul>
<li><b>Grundsätzliches</b><ul>
<li><a name="MEDIAPORTAL_setter_connect">
<b><code>connect</code></b></a>
<br />Erzwingt eine sofortige Verbindung zu Mediaportal. Normalerweise würde die normale Verbindungswiederholung von Fhem (30s) abgewartet werden. </li>
<li><a name="MEDIAPORTAL_setter_powermode">
<b><code>powermode &lt;mode&gt;</code></b></a>
<br />Eins aus (logoff, suspend, hibernate, reboot, shutdown, exit). Setzt den powermode, z.B. shutdown, zum Herunterfahren des Computers des Mediaportal-Systems.</li>
<li><a name="MEDIAPORTAL_setter_reconnect">
<b><code>reconnect</code></b></a>
<br />Erzwingt eine sofortige Trennung und Neuverbindung zu Mediaportal.</li>
</ul></li>
<li><b>Control-Befehle</b><ul>
<li><a name="MEDIAPORTAL_setter_command">
<b><code>command &lt;command&gt;</code></b></a>
<br />Eins aus (stop, record, pause, play, rewind, forward, replay, skip, back, info, menu, up, down, left, right, ok, volup, voldown, volmute, chup, chdown, dvdmenu, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0, clear, enter, teletext, red, blue, yellow, green, home, basichome, nowplaying, tvguide, tvrecs, dvd, playlists, first, last, fullscreen, subtitles, audiotrack, screenshot). Sendet das entsprechende Kommando an den Player.</li>
<li><a name="MEDIAPORTAL_setter_key">
<b><code>key &lt;keyvalue&gt;</code></b></a>
<br />Sendet die entsprechende Taste an den Player.</li>
<li><a name="MEDIAPORTAL_setter_sleep">
<b><code>sleep</code></b></a>
<br />Startet den Hibernate-Modus. Dieser Befehl ist ein Shortcut für "powermode hibernate"</li>
<li><a name="MEDIAPORTAL_setter_wakeup">
<b><code>wakeup</code></b></a>
<br />Weckt den Mediaportal-Rechner auf (WakeUp-On-LAN).</li>
</ul></li>
<li><b>Abspielbefehle</b><ul>
<li><a name="MEDIAPORTAL_setter_playchannel">
<b><code>playchannel &lt;channelID&gt;</code></b></a>
<br />Spielt den Kanal mit der entsprechenden ID ab.</li>
<li><a name="MEDIAPORTAL_setter_playfile">
<b><code>playfile &lt;fileType&gt; &lt;filePath&gt;</code></b></a>
<br />Spielt die entsprechende Datei mit dem angegebenen Typ ab. FileType kann (audio, video) sein.</li>
<li><a name="MEDIAPORTAL_setter_playlist">
<b><code>playlist &lt;command&gt; &lt;param&gt;</code></b></a>
<br />Sendet das entsprechende Playlist-Kommando mit dem gegebenen Parameter. Das Kommando kann (play, loadlist, loadlist_shuffle, loadfrompath, loadfrompath_shuffle) sein.</li>
<li><a name="MEDIAPORTAL_setter_Volume">
<b><code>Volume &lt;volumelevel&gt;</code></b></a>
<br />Setzt die angegebene Lautstärke.</li>
</ul></li>
</ul>
<a name="MEDIAPORTALget"></a> 
<h4>Get</h4>
<ul>
<li><b>Grundsätzliches</b><ul>
<li><a name="MEDIAPORTAL_getter_status">
<b><code>status</code></b></a>
<br />Sendet eine Aufforderung für das Senden einer <code>status</code>-Nachricht. Liefert dann asynchron die Informationen "Title" und "PlayStatus".</li>
<li><a name="MEDIAPORTAL_getter_nowplaying">
<b><code>nowplaying</code></b></a>
<br />Sendet eine Aufforderung für das Senden einer <code>nowplaying</code>-Nachricht. Liefert dann asynchron die Informationen "Duration", "Position" und "File"".</li>
</ul></li>
</ul>
<a name="MEDIAPORTALattr"></a>
<h4>Attribute</h4>
<ul>
<li><b>Grundsätzliches</b><ul>
<li><a name="MEDIAPORTAL_attribut_disable"><b><code>disable &lt;value&gt;</code></b>
</a><br />Eins aus (0, 1). Mit diesem Attribut kann das Modul deaktiviert werden.</li>
<li><a name="MEDIAPORTAL_attribut_generateNowPlayingUpdateEvents"><b><code>generateNowPlayingUpdateEvents &lt;value&gt;</code></b>
</a><br />Eins aus (0, 1). Mit diesem Attribut kann die Erzeugung eines <code>NowPlayingUpdate</code>-Events an- oder abgeschaltet werden. Wenn auf "1" gesetzt, generiert Fhem ein Event pro Sekunde mit den angepassten Zeitangaben. Standard ist "0".</li>
<li><a name="MEDIAPORTAL_attribut_HeartbeatInterval"><b><code>HeartbeatInterval &lt;intervall&gt;</code></b>
</a><br />In Sekunden. Legt das Intervall für die Prüfung der Verbindung zu Mediaportal fest. Mit "0" kann die Prüfung deaktiviert werden. Wenn kein Wert angeggeben wird, wird "15" verwendet.</li>
<li><a name="MEDIAPORTAL_attribut_macaddress"><b><code>macaddress &lt;address&gt;</code></b>
</a><br />Gibt die Mac-Adresse des Mediaportal-Rechners an. Das wird für die WakeUp-Funktionalität benötigt. z.B. "90:E6:BA:C2:96:15"</li>
</ul></li>
<li><b>Authentifizierung</b><ul>
<li><a name="MEDIAPORTAL_attribut_authmethod"><b><code>authmethod &lt;value&gt;</code></b>
</a><br />Eins aus (none, userpassword, passcode, both). Hiermit wird der Authentifizierungsmodus festgelegt.</li>
<li><a name="MEDIAPORTAL_attribut_password"><b><code>password &lt;value&gt;</code></b>
</a><br />Hiermit wird das Passwort für die Authentifzierung festgelegt.</li>
<li><a name="MEDIAPORTAL_attribut_username"><b><code>username &lt;value&gt;</code></b>
</a><br />Hiermit wird der Benutzername für die Authentifizerung festgelegt.</li>
</ul></li>
</ul>

=end html_DE
=cut