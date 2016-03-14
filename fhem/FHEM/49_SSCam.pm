##########################################################################################################
# $Id$
##########################################################################################################
#       49_SSCam.pm
#
#       (c) 2015-2016 by Heiko Maaz
#       e-mail: Heiko dot Maaz at t-online dot de
#
#       This Module can be used to operate Cameras defined in Synology Surveillance Station 7.0 or higher.
#       It's based on and it's using Synology Surveillance Station API 
# 
#       This script is part of fhem.
#
#       Fhem is free software: you can redistribute it and/or modify
#       it under the terms of the GNU General Public License as published by
#       the Free Software Foundation, either version 2 of the License, or
#       (at your option) any later version.
#
#       Fhem is distributed in the hope that it will be useful,
#       but WITHOUT ANY WARRANTY; without even the implied warranty of
#       MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#       GNU General Public License for more details.
#
#       You should have received a copy of the GNU General Public License
#       along with fhem.  If not, see <http://www.gnu.org/licenses/>.# 
#
##########################################################################################################
#  Versions History:
#
# 1.20.2 14.03.2016    change: routine "initonboot" changed
# 1.20.1 12.03.2016    bugfix: default recordtime 15 s is used if attribute "rectime" is set to "0"
# 1.20   09.03.2016    command "extevent" added
# 1.19.3 07.03.2016    bugfix "uninitialized value $lastrecstarttime",
#                      "uninitialized value $lastrecstoptime",
#                      new attribute "videofolderMap"
# 1.19.2 06.03.2016    Reading "CamLastRec" added which contains Path/name
#                      of last recording
# 1.19.1 28.02.2016    enhanced command runView by option "link_open" to
#                      open a streamlink immediately
# 1.19   25.02.2016    functions for cam-livestream added
# 1.18.1 21.02.2016    fixed a problem that the state is "disable" instead of
#                      "disabled" if a camera is disabled and FHEM will be restarted
# 1.18   20.02.2016    function "get ... eventlist" added,
#                      Reading "CamEventNum" added which containes total number of
#                      camera events,
#                      change usage of reading "LastUpdateTime" 
# 1.17   19.02.2016    function "runPatrol" added that starts predefined patrols
#                      of PTZ-cameras,
#                      Reading "CamDetMotSc" added
# 1.16.1 17.02.2016    Reading "CamExposureControl" added
# 1.16   16.02.2016    set up of motion detection source now possible
# 1.15   15.02.2016    control of exposure mode day, night & auto is possible now
# 1.14   14.02.2016    The port in DEF-String is optional now,
#                      if not given, default port 5000 is used
# 1.13.2 13.02.2016    fixed a problem that manual updates using "getcaminfoall" are
#                      leading to additional pollingloops if polling is used,
#                      attribute "debugactivetoken" added for debugging-use 
# 1.13.1 12.02.2016    fixed a problem that a usersession won't be destroyed if a
#                      function couldn't be executed successfully
# 1.13                 feature for retrieval snapfilename added
# 1.12.1 09.02.2016    bugfix: "goAbsPTZ" may be unavailable on Windows-systems
# 1.12   08.02.2016    added function "move" for continuous PTZ action
# 1.11.1 07.02.2016    entries with loglevel "2" reviewed, changed to loglevel "3"
# 1.11   05.02.2016    added function "goPreset" and "goAbsPTZ" to control the move of PTZ lense
#                      to absolute positions
#                      refere to commandref or have a look in forum at: 
#                      http://forum.fhem.de/index.php/topic,45671.msg404275.html#msg404275 ,
#                      http://forum.fhem.de/index.php/topic,45671.msg404892.html#msg404892
# 1.10   02.02.2016    added function "svsinfo" to get informations about installed SVS-package,
#                      if Availability = " disconnected" then "state"-value will be "disconnected" too,
#                      saved Credentials were deleted from file if a device will be deleted
# 1.9.1  31.01.2016    a little bit code optimization
# 1.9    28.01.2016    fixed the problem a recording may still stay active if fhem
#                      will be restarted after a recording was triggered and
#                      the recordingtime wasn't be over,
#                      Enhancement of readings.
# 1.8    25.01.2016    changed define in order to remove credentials from string,
#                      added "set credentials" command to save username/password,
#                      added Attribute "session" to make login-session selectable,
#                      Note: You have to adapt your define-strings !!
#                      Refere to commandref or look in forum at: 
#                      http://forum.fhem.de/index.php/topic,45671.msg397449.html#msg397449
# 1.7    18.01.2016    Attribute "httptimeout" added
# 1.6    16.01.2016    Change the define-string related to rectime.
#                      Note: See all changes to rectime usage in commandref or here:
#                      http://forum.fhem.de/index.php/topic,45671.msg391664.html#msg391664
# 1.5.1  11.01.2016    Vars "USERNAME" and "RECTIME" removed from internals,
#                      Var (Internals) "SERVERNAME" changed to "SERVERADDR",
#                      minor change of Log messages,
#                      Note: use rereadcfg in order to activate the changes
#  1.5    04.01.2016   Function "Get" for creating Camera-Readings integrated,
#                      Attributs pollcaminfoall, pollnologging  added,
#                      Function for Polling Cam-Infos added.
#  1.4    23.12.2015   function "enable" and "disable" for SS-Cams added,
#                      changed timout of Http-calls to a higher value
#  1.3    19.12.2015   function "snap" for taking snapshots added,
#                      fixed a bug that functions may impact each other 
#  1.2    14.12.2015   improve usage of verbose-modes
#  1.1    13.12.2015   use of InternalTimer instead of fhem(sleep)
#  1.0    12.12.2015   changed completly to HttpUtils_NonblockingGet for calling websites nonblocking, 
#                      LWP is not needed anymore
#
#
# Definition: define <name> SSCam <camname> <ServerAddr> [ServerPort] 
# 
# Example: define CamCP1 SSCAM Carport 192.168.2.20 [5000]
#


package main;

use JSON qw( decode_json );            # From CPAN,, Debian libjson-perl 
use Data::Dumper;                      # Perl Core module
use strict;                           
use warnings;
use Time::HiRes qw(gettimeofday);
use MIME::Base64;
use HttpUtils;


sub SSCam_Initialize($) {
 my ($hash) = @_;
 $hash->{DefFn}        = "SSCam_Define";
 $hash->{UndefFn}      = "SSCam_Undef";
 $hash->{DeleteFn}     = "SSCam_Delete"; 
 $hash->{SetFn}        = "SSCam_Set";
 $hash->{GetFn}        = "SSCam_Get";
 $hash->{AttrFn}       = "SSCam_Attr";
 # Aufrufe aus FHEMWEB
 $hash->{FW_summaryFn} = "SSCam_liveview";
 $hash->{FW_detailFn}  = "SSCam_liveview";
 
 $hash->{AttrList} =
         "httptimeout ".
         "htmlattr ".
         "livestreamprefix ".
         "videofolderMap ".
         "pollcaminfoall ".
         "pollnologging:1,0 ".
         "debugactivetoken:1 ".
         "rectime ".
         "session:SurveillanceStation,DSM ".
         "webCmd ".
         $readingFnAttributes;   
         
return undef;   
}

sub SSCam_Define {
  # Die Define-Funktion eines Moduls wird von Fhem aufgerufen wenn der Define-Befehl für ein Gerät ausgeführt wird 
  # Welche und wie viele Parameter akzeptiert werden ist Sache dieser Funktion. Die Werte werden nach dem übergebenen Hash in ein Array aufgeteilt
  # define CamCP1 SSCAM Carport 192.168.2.20 [5000] 
  #       ($hash)  [1]    [2]        [3]      [4]  
  #
  my ($hash, $def) = @_;
  my $name = $hash->{NAME};
  
  my @a = split("[ \t][ \t]*", $def);
  
  if(int(@a) < 4) {
        return "You need to specify more parameters.\n". "Format: define <name> SSCAM <Cameraname> <ServerAddress> [Port]";
        }
        
  my $camname    = $a[2];
  my $serveraddr = $a[3];
  my $serverport = $a[4] ? $a[4] : 5000;
  
  $hash->{SERVERADDR}       = $serveraddr;
  $hash->{SERVERPORT}       = $serverport;
  $hash->{CAMNAME}          = $camname;
 
  # benötigte API's in $hash einfügen
  $hash->{HELPER}{APIINFO}        = "SYNO.API.Info";                             # Info-Seite für alle API's, einzige statische Seite !                                                    
  $hash->{HELPER}{APIAUTH}        = "SYNO.API.Auth"; 
  $hash->{HELPER}{APISVSINFO}     = "SYNO.SurveillanceStation.Info"; 
  $hash->{HELPER}{APIEVENT}       = "SYNO.SurveillanceStation.Event"; 
  $hash->{HELPER}{APIEXTREC}      = "SYNO.SurveillanceStation.ExternalRecording"; 
  $hash->{HELPER}{APIEXTEVT}      = "SYNO.SurveillanceStation.ExternalEvent";
  $hash->{HELPER}{APICAM}         = "SYNO.SurveillanceStation.Camera";
  $hash->{HELPER}{APISNAPSHOT}    = "SYNO.SurveillanceStation.SnapShot";
  $hash->{HELPER}{APIPTZ}         = "SYNO.SurveillanceStation.PTZ";
  $hash->{HELPER}{APICAMEVENT}    = "SYNO.SurveillanceStation.Camera.Event";
  $hash->{HELPER}{APIVIDEOSTM}    = "SYNO.SurveillanceStation.VideoStreaming";
  
  # Startwerte setzen
  $attr{$name}{webCmd}                 = "on:off:snap:enable:disable";                            # initiale Webkommandos setzen
  $hash->{HELPER}{ACTIVE}              = "off";                                                   # Funktionstoken "off", Funktionen können sofort starten
  $hash->{HELPER}{OLDVALPOLLNOLOGGING} = "0";                                                     # Loggingfunktion für Polling ist an
  $hash->{HELPER}{RECTIME_DEF}         = "15";                                                    # Standard für rectime setzen, überschreibbar durch Attribut "rectime" bzw. beim "set .. on-for-time"
  
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash,"Availability", "");                                                   # Verfügbarkeit ist unbekannt
  readingsBulkUpdate($hash,"PollState","Inactive");                                               # es ist keine Gerätepolling aktiv
  readingsBulkUpdate($hash,"LiveStreamUrl", "");                                                  # LiveStream URL zurücksetzen
  readingsEndUpdate($hash,1);                                          
  
  getcredentials($hash,1);                                                                        # Credentials lesen und in RAM laden ($boot=1)  
  RemoveInternalTimer($hash);                                                                     # alle Timer löschen
  
  # initiale Rotinen nach Restart ausführen , verzögerter zufälliger Start   
  InternalTimer(gettimeofday()+int(rand(30)), "initonboot", $hash, 0);

return undef;
}


sub SSCam_Undef {
    my ($hash, $arg) = @_;
   
    RemoveInternalTimer($hash);
    
return undef;
}

sub SSCam_Delete {
    my ($hash, $arg) = @_;
    my $index = $hash->{TYPE}."_".$hash->{NAME}."_credentials";
    
    # gespeicherte Credentials löschen
    setKeyValue($index, undef);
    
return undef;
}


sub SSCam_Attr {
    my ($cmd,$name,$aName,$aVal) = @_;
    # $cmd can be "del" or "set"
    # $name is device name
    # aName and aVal are Attribute name and value
   if ($cmd eq "set") {
        if ($aName eq "pollcaminfoall") {
           unless ($aVal =~ /^\d+$/) { return " The Value for $aName is not valid. Use only figures 0-9 without decimal places !";}
           }
        if ($aName eq "rectime") {
           unless ($aVal =~ /^\d+$/) { return " The Value for $aName is not valid. Use only figures 0-9 without decimal places !";}
           }
        if ($aName eq "httptimeout") {
           unless ($aVal =~ /^[0-9]+$/) { return " The Value for $aName is not valid. Use only figures 1-9 !";}
           } 
   }
return undef;
}
 
sub SSCam_Set {
        my ($hash, @a) = @_;
        return "\"set X\" needs at least an argument" if ( @a < 2 );
        my $name    = $a[0];
        my $opt     = $a[1];
        my $prop    = $a[2];
        my $prop1   = $a[3];
        my $camname = $hash->{CAMNAME}; 
        my $success;
        my $logstr;
        my $setlist;
        my @prop;

                         
#        my $list .= "on off snap enable disable on-for-timer";
#        return SetExtensions($hash, $list, $name, $opt) if( $opt eq "?" );
#        return SetExtensions($hash, $list, $name, $opt) if( !grep( $_ =~ /^\Q$opt\E($|:)/, split( ' ', $list ) ) );
        
        $setlist = "Unknown argument $opt, choose one of ".
                   "credentials ".
                   "expmode:auto,day,night ".
                   "on ".
                   "off ".
                   "motdetsc:disable,camera,SVS ".
                   "snap ".
                   "enable ".
                   "disable ".
                   "runView:image,link,link_open ".
                   "stopView:noArg ".
                   "extevent:1,2,3,4,5,6,7,8,9,10 ".
                   ((ReadingsVal("$name", "DeviceType", "Camera") eq "PTZ") ? "runPatrol:".ReadingsVal("$name", "Patrols", "")." " : "").
                   ((ReadingsVal("$name", "DeviceType", "Camera") eq "PTZ") ? "goPreset:".ReadingsVal("$name", "Presets", "")." " : "").
                   ((ReadingsVal("$name", "CapPTZAbs", "false")) ? "goAbsPTZ"." " : ""). 
                   ((ReadingsVal("$name", "CapPTZDirections", "0") > 0) ? "move"." " : "");
                    
        
        if ($opt eq "on") {
            if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
            
            if (defined($prop)) {
                unless ($prop =~ /^\d+$/) { return " The Value for \"$opt\" is not valid. Use only figures 0-9 without decimal places !";}
                $hash->{HELPER}{RECTIME_TEMP} = $prop;
                }
            camstartrec($hash);
 
        }
        elsif ($opt eq "off") 
        {
            if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
            camstoprec($hash);
        }
        elsif ($opt eq "snap") 
        {
            if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
            camsnap($hash);
        }
        elsif ($opt eq "enable") 
        {
            if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
            camenable($hash);
        }
        elsif ($opt eq "disable") 
        {
            if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
            camdisable($hash);
        }
        elsif ($opt eq "motdetsc") 
        {
            if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
            unless ($prop) { return " \"$opt\" needs one of those arguments: disable, camera, SVS !";}
            
            $hash->{HELPER}{MOTDETSC} = $prop;
            cammotdetsc($hash);
        }
        elsif ($opt eq "credentials") 
        {
            return "Credentials are incomplete, use username password" if (!$prop || !$prop1);
                        
            ($success) = setcredentials($hash,$prop,$prop1);
            return $success ? "Username and Password saved successfully" : "Error while saving Username / Password - see logfile for details";
        }
        elsif ($opt eq "expmode") 
        {
            if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
            unless ($prop) { return " \"$opt\" needs one of those arguments: auto, day, night !";}
            
            $hash->{HELPER}{EXPMODE} = $prop;
            camexpmode($hash);
        }
        elsif ($opt eq "goPreset") 
        {
            if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
            if (!$prop) {return "Function \"goPreset\" needs a \"Presetname\" as an argument";}
            
            @prop = split(/;/, $prop);
            $prop = $prop[0];
            @prop = split(/,/, $prop);
            $prop = $prop[0];
            $hash->{HELPER}{GOPRESETNAME} = $prop;
            $hash->{HELPER}{PTZACTION}    = "gopreset";
            doptzaction($hash);
        }
        elsif ($opt eq "runPatrol") 
        {
            if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
            if (!$prop) {return "Function \"runPatrol\" needs a \"Patrolname\" as an argument";}
            
            @prop = split(/;/, $prop);
            $prop = $prop[0];
            @prop = split(/,/, $prop);
            $prop = $prop[0];
            $hash->{HELPER}{GOPATROLNAME} = $prop;
            $hash->{HELPER}{PTZACTION}    = "runpatrol";
            doptzaction($hash);
        }
        elsif ($opt eq "goAbsPTZ") 
        {
            if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}

            if ($prop eq "up" || $prop eq "down" || $prop eq "left" || $prop eq "right") {
                if ($prop eq "up")    {$hash->{HELPER}{GOPTZPOSX} = 320; $hash->{HELPER}{GOPTZPOSY} = 480;}
                if ($prop eq "down")  {$hash->{HELPER}{GOPTZPOSX} = 320; $hash->{HELPER}{GOPTZPOSY} = 0;}
                if ($prop eq "left")  {$hash->{HELPER}{GOPTZPOSX} = 0; $hash->{HELPER}{GOPTZPOSY} = 240;}    
                if ($prop eq "right") {$hash->{HELPER}{GOPTZPOSX} = 640; $hash->{HELPER}{GOPTZPOSY} = 240;} 
                
                $hash->{HELPER}{PTZACTION} = "goabsptz";
                doptzaction($hash);
                return undef;
            }               
            else
            {
                if ($prop !~ /\d+/ || $prop1 !~ /\d+/ || abs($prop) > 640 || abs($prop1) > 480) {
                return "Function \"goAbsPTZ\" needs two coordinates, posX=0-640 and posY=0-480, as arguments or use up, down, left, right instead";
                }
                
                $hash->{HELPER}{GOPTZPOSX} = abs($prop);
                $hash->{HELPER}{GOPTZPOSY} = abs($prop1);
                
                $hash->{HELPER}{PTZACTION}  = "goabsptz";
                doptzaction($hash);
                
                return undef;
                
            } 
            return "Function \"goAbsPTZ\" needs two coordinates, posX=0-640 and posY=0-480, as arguments or use up, down, left, right instead";

        }
        elsif ($opt eq "move") 
        {
            if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}

            if (!defined($prop) || ($prop ne "up" && $prop ne "down" && $prop ne "left" && $prop ne "right" && $prop !~ m/dir_\d/)) {return "Function \"move\" needs an argument like up, down, left, right or dir_X (X = 0 to CapPTZDirections-1)";}
            
            $hash->{HELPER}{GOMOVEDIR} = $prop;
            $hash->{HELPER}{GOMOVETIME} = defined($prop1) ? $prop1 : 1;
            
            $hash->{HELPER}{PTZACTION}  = "movestart";
            doptzaction($hash);
        }
        elsif ($opt eq "runView") 
        {
            if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
            
            if ($prop eq "link_open") {
                $prop = "link";
                if ($prop1) {$hash->{HELPER}{VIEWOPENROOM} = $prop1;} else {delete $hash->{HELPER}{VIEWOPENROOM};}
                $hash->{HELPER}{OPENWINDOW} = 1;
            } else {
                $hash->{HELPER}{OPENWINDOW} = 0;
            }
                       
            $hash->{HELPER}{WLTYPE} = $prop;
            runliveview($hash);
        }
        elsif ($opt eq "extevent") 
        {
            if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
                                   
            $hash->{HELPER}{EVENTID} = $prop;
            extevent($hash);
        }
        elsif ($opt eq "stopView") 
        {
            stopliveview($hash);            
        }
        else  
        {
            return $setlist;
        }  
return;
}


sub SSCam_Get {
    my ($hash, @a) = @_;
    return "\"get X\" needs at least an argument" if ( @a < 2 );
    my $name = shift @a;
    my $opt = shift @a;
    my %SSCam_gets = (
                     caminfoall    => "caminfoall",
                     svsinfo       => "svsinfo",
                     snapfileinfo  => "snapfileinfo",
                     eventlist     => "eventlist",
                     );
    my @cList;
        
    # ist die angegebene Option verfügbar ?
    if(!defined($SSCam_gets{$opt})) 
        {
            @cList = keys %SSCam_gets; 
            return "Unknown argument $opt, choose one of " . join(" ", @cList);
        } 
        else 
        {
            # sind die Credentials gesetzt ?
            if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
            
            if ($opt eq "caminfoall") 
            {
                # "1" ist Statusbit für manuelle Abfrage, kein Einstieg in Pollingroutine
                &getcaminfoall($hash,1);
            }
            elsif ($opt eq "svsinfo") 
            {
                &getsvsinfo($hash);
            }
            elsif ($opt eq "snapfileinfo") 
            {
                if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
                getsnapfilename($hash);
            } 
            elsif ($opt eq "eventlist") 
            {
                if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
                geteventlist ($hash);
            }  
        }
return undef;
}

######################################################################################
###  Kamera Liveview Anzeige in FHEMWEB

sub SSCam_liveview ($$$$) {

  my ($FW_wname, $d, $room, $pageHash) = @_;            # pageHash für summaryFn in FHEMWEB
  my $hash          = $defs{$d};
  my $name          = $hash->{NAME};
  my $link          = $hash->{HELPER}{LINK};
  my $wltype        = $hash->{HELPER}{WLTYPE};
  my $ret;
  my $alias;
    
  return if(!$hash->{HELPER}{LINK} || ReadingsVal("$name", "state", "") =~ /^dis.*/);
  
  my $attr = AttrVal($d, "htmlattr", "");
  
  if($wltype eq "image") {
    $ret = "<img src=$link $attr><br>";
  
  } elsif($wltype eq "iframe") {
    $ret = "<iframe src=$link $attr>Iframes disabled</iframe>";
           
  } elsif($wltype eq "link") {
    # $alias = AttrVal($d, "alias", $d)."_liveview";
    $alias = "LiveCam";
    $ret = "<a href=$link $attr>$alias</a><br>";        # wenn attr target=_blank neuer Browsertab
  
  }
  
return $ret;
}

######################################################################################
###  initiale Startroutinen nach Restart FHEM

sub initonboot ($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $logstr;
  
  if ($init_done == 1) {
     
     # check ob alle Recordings = "Stop" nach Reboot -> sonst stoppen
     if (ReadingsVal($hash->{NAME}, "Record", "Stop") eq "Start") {
         $logstr = "Recording of $hash->{CAMNAME} seems to be still active after FHEM restart - try to stop it now"; 
         &printlog($hash,$logstr,"1"); 
         &camstoprec($hash);
         }
         
     # Konfiguration der Synology Surveillance Station abrufen
     if (!$hash->{CREDENTIALS}) {
         $logstr = "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";
         &printlog($hash,$logstr,"1");
         }
         else {
         # allg. SVS-Eigenschaften abrufen
         getsvsinfo($hash);
         # Kameraspezifische Infos holen
         getcaminfo($hash);
         getcapabilities($hash);
         # Preset/Patrollisten in Hash einlesen zur PTZ-Steuerung
         getptzlistpreset($hash);
         getptzlistpatrol($hash);

         }
         
     # Subroutine Watchdog-Timer starten (sollen Cam-Infos regelmäßig abgerufen werden ?), verzögerter zufälliger Start 0-60s 
     InternalTimer(gettimeofday()+int(rand(30)), "watchdogpollcaminfo", $hash, 0);
  
  }
  else 
  {
      InternalTimer(gettimeofday()+0.14, "initonboot", $hash, 0);
  }
  
return undef;
}



######################################################################################
###  Username / Paßwort speichern

sub setcredentials ($@) {
    my ($hash, @credentials) = @_;
    my $logstr;
    my $success;
    my $credstr;
    my $index;
    my $retcode;
    my (@key,$len,$i);
    
    $credstr = encode_base64(join(':', @credentials));
    
    # Beginn Scramble-Routine
    @key = qw(1 3 4 5 6 3 2 1 9);
    $len = scalar @key;  
    $i = 0;  
    $credstr = join "",  
            map { $i = ($i + 1) % $len;  
            chr((ord($_) + $key[$i]) % 256) } split //, $credstr; 
    # End Scramble-Routine    
       
    $index = $hash->{TYPE}."_".$hash->{NAME}."_credentials";
    $retcode = setKeyValue($index, $credstr);
    
    if ($retcode) { 
        $logstr = "Error while saving the Credentials - $retcode";
        &printlog($hash,$logstr,"1");
        $success = 0;
        }
        else
        {
        getcredentials($hash,1);        # Credentials nach Speicherung lesen und in RAM laden ($boot=1) 
        $success = 1;
        }

return ($success);
}

######################################################################################
###  Username / Paßwort abrufen

sub getcredentials ($$) {
    my ($hash,$boot) = @_;
    my $logstr;
    my $success;
    my $username;
    my $passwd;
    my $index;
    my ($retcode, $credstr);
    my (@key,$len,$i);
    
    if ($boot eq 1) {
        # mit $boot=1 Credentials von Platte lesen und als scrambled-String in RAM legen
        $index = $hash->{TYPE}."_".$hash->{NAME}."_credentials";
        ($retcode, $credstr) = getKeyValue($index);
    
        if ($retcode) {
            $logstr = "Unable to read password from file: $retcode";
            &printlog($hash,$logstr,"1");
            $success = 0;
            }  

        if ($credstr) {
     
            # beim Boot scrambled Credentials in den RAM laden
            $hash->{HELPER}{CREDENTIALS} = $credstr;
        
            # "Credentials" wird als Statusbit ausgewertet. Wenn nicht gesetzt -> Warnmeldung und keine weitere Verarbeitung
            $hash->{CREDENTIALS} = "Set";
            $success = 1;
            }
    }
    else
    {
    # boot = 0 -> Credentials aus RAM lesen, decoden und zurückgeben
    $credstr = $hash->{HELPER}{CREDENTIALS};
    
    # Beginn Descramble-Routine
    @key = qw(1 3 4 5 6 3 2 1 9); 
    $len = scalar @key;  
    $i = 0;  
    $credstr = join "",  
    map { $i = ($i + 1) % $len;  
        chr((ord($_) - $key[$i] + 256) % 256) }  
        split //, $credstr;   
    # Ende Descramble-Routine
    
    ($username, $passwd) = split(":",decode_base64($credstr));
    
    $logstr = "Credentials read from RAM: $username $passwd";
    &printlog($hash,$logstr,"4");
    
    $success = (defined($passwd)) ? 1 : 0;
    }
    
return ($success, $username, $passwd);        
}


######################################################################################
###  Polling Überwachung

sub watchdogpollcaminfo ($) {
    # Überwacht die Wert von Attribut "pollcaminfoall" und Reading "PollState"
    # wenn Attribut "pollcaminfoall" > 10 und "PollState"=Inactive -> start Polling
    my ($hash)   = @_;
    my $name     = $hash->{NAME};
    my $camname  = $hash->{CAMNAME};
    my $logstr;
    my $watchdogtimer = 90;
    
    if (defined($attr{$name}{pollcaminfoall}) and $attr{$name}{pollcaminfoall} > 10 and ReadingsVal("$name", "PollState", "Active") eq "Inactive") {
        
        # Polling ist jetzt aktiv
        readingsSingleUpdate($hash,"PollState","Active",0);
            
        $logstr = "Polling Camera $camname is currently activated - Pollinginterval: ".$attr{$name}{pollcaminfoall}."s";
        &printlog($hash,$logstr,"3");
        
        # in $hash eintragen für späteren Vergleich (Changes von pollcaminfoall)
        $hash->{HELPER}{OLDVALPOLL} = $attr{$name}{pollcaminfoall};
        
        &getcaminfoall($hash);           
    }
    
    if (defined($hash->{HELPER}{OLDVALPOLL}) and defined($attr{$name}{pollcaminfoall}) and $attr{$name}{pollcaminfoall} > 10) {
        if ($hash->{HELPER}{OLDVALPOLL} != $attr{$name}{pollcaminfoall}) {
            
            $logstr = "Polling Camera $camname was changed to new Pollinginterval: ".$attr{$name}{pollcaminfoall}."s";
            &printlog($hash,$logstr,"3");
            
            $hash->{HELPER}{OLDVALPOLL} = $attr{$name}{pollcaminfoall};
            }
    }
    
    if (defined($attr{$name}{pollnologging})) {
        if ($hash->{HELPER}{OLDVALPOLLNOLOGGING} ne $attr{$name}{pollnologging}) {
        
            if ($attr{$name}{pollnologging} == "1") {
                $logstr = "Log of Polling Camera $camname is currently deactivated";
                &printlog($hash,$logstr,"3");
                
                # in $hash eintragen für späteren Vergleich (Changes von pollnologging)
                $hash->{HELPER}{OLDVALPOLLNOLOGGING} = $attr{$name}{pollnologging};
                
            } else {
            
                $logstr = "Log of Polling Camera $camname is currently activated";
                &printlog($hash,$logstr,"3");
                
                # in $hash eintragen für späteren Vergleich (Changes von pollnologging)
                $hash->{HELPER}{OLDVALPOLLNOLOGGING} = $attr{$name}{pollnologging};
            }
        }
    } else {
    
        # alter Wert von "pollnologging" war 1 -> Logging war deaktiviert
        if ($hash->{HELPER}{OLDVALPOLLNOLOGGING} == "1") {
            $logstr = "Log of Polling Camera $camname is currently activated";
            &printlog($hash,$logstr,"3");
            
            $hash->{HELPER}{OLDVALPOLLNOLOGGING} = "0";            
        }
    }
InternalTimer(gettimeofday()+$watchdogtimer, "watchdogpollcaminfo", $hash, 0);
return undef;
}



#############################################################################################################################
#########                                        OpMode-Startroutinen                                           #############
#########   $hash->{HELPER}{ACTIVE} = Funktionstoken                                                            #############
#########   $hash->{HELPER}{ACTIVE} = "on"    ->  eine Routine läuft, Start anderer Routine erst wenn "off".    #############
#########   $hash->{HELPER}{ACTIVE} = "off"   ->  keine andere Routine läuft, sofortiger Start möglich          #############
#############################################################################################################################

###############################################################################
###   Kamera Aufnahme starten

sub camstartrec ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    my $logstr;
    my $errorcode;
    my $error;
    
    if (ReadingsVal("$name", "state", "") =~ /^dis.*/) {
        if (ReadingsVal("$name", "state", "") eq "disabled") {
            $errorcode = "402";
            }
            elsif (ReadingsVal("$name", "state", "") eq "disconnected") {
            $errorcode = "502";
            }
        
        # Fehlertext zum Errorcode ermitteln
        $error = &experror($hash,$errorcode);

        # Setreading 
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash,"Errorcode",$errorcode);
        readingsBulkUpdate($hash,"Error",$error);
        readingsEndUpdate($hash, 1);
    
        $logstr = "ERROR - Start Recording of Camera $camname can't be executed - $error" ;
        &printlog($hash,$logstr,"1");
        return;
        }
    
    if ($hash->{HELPER}{ACTIVE} eq "off" and ReadingsVal("$name", "Record", "Start") ne "Start") {
        # Aufnahme starten
        $logstr = "Recording of Camera $camname will be started now";
        &printlog($hash,$logstr,"4");
                           
        $hash->{OPMODE} = "Start";
        $hash->{HELPER}{ACTIVE} = "on";
        
        if ($attr{$name}{debugactivetoken}) {
            $logstr = "Active-Token was set by OPMODE: $hash->{OPMODE}" ;
            &printlog($hash,$logstr,"3");
        }
        
        &getapisites_nonbl($hash);
    }
    else
    {
    InternalTimer(gettimeofday()+0.11, "camstartrec", $hash, 0);
    }
}

###############################################################################
###   Kamera Aufnahme stoppen

sub camstoprec ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    my $logstr;
    my $errorcode;
    my $error;
    
    if (ReadingsVal("$name", "state", "") =~ /^dis.*/) {
        if (ReadingsVal("$name", "state", "") eq "disabled") {
            $errorcode = "402";
            }
            elsif (ReadingsVal("$name", "state", "") eq "disconnected") {
            $errorcode = "502";
            }
        
        # Fehlertext zum Errorcode ermitteln
        $error = &experror($hash,$errorcode);

        # Setreading 
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash,"Errorcode",$errorcode);
        readingsBulkUpdate($hash,"Error",$error);
        readingsEndUpdate($hash, 1);
    
        $logstr = "ERROR - Stop Recording of Camera $camname can't be executed - $error" ;
        &printlog($hash,$logstr,"1");
        return;
        }
    
    if ($hash->{HELPER}{ACTIVE} eq "off" and ReadingsVal("$name", "Record", "Stop") ne "Stop") {
        # Aufnahme stoppen
        $logstr = "Recording of Camera $camname will be stopped now";
        &printlog($hash,$logstr,"4");
                        
        $hash->{OPMODE} = "Stop";
        $hash->{HELPER}{ACTIVE} = "on";
        
        if ($attr{$name}{debugactivetoken}) {
            $logstr = "Active-Token was set by OPMODE: $hash->{OPMODE}" ;
            &printlog($hash,$logstr,"3");
        }
        
        &getapisites_nonbl($hash);
    }
    else
    {
    InternalTimer(gettimeofday()+0.12, "camstoprec", $hash, 0);
    }
}

###############################################################################
###   Kamera Auto / Day / Nightmode setzen

sub camexpmode ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    my $logstr;
    my $errorcode;
    my $error;
    
    if (ReadingsVal("$name", "state", "") =~ /^dis.*/) {
        if (ReadingsVal("$name", "state", "") eq "disabled") {
            $errorcode = "402";
            }
            elsif (ReadingsVal("$name", "state", "") eq "disconnected") {
            $errorcode = "502";
            }
        
        # Fehlertext zum Errorcode ermitteln
        $error = &experror($hash,$errorcode);

        # Setreading 
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash,"Errorcode",$errorcode);
        readingsBulkUpdate($hash,"Error",$error);
        readingsEndUpdate($hash, 1);
    
        $logstr = "ERROR - Setting exposure mode of Camera $camname can't be executed - $error" ;
        &printlog($hash,$logstr,"1");
        return;
        }
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {
        
        $logstr = "Setting of exposure mode of Camera $camname will be started now";
        &printlog($hash,$logstr,"4");
                           
        $hash->{OPMODE} = "ExpMode";
        $hash->{HELPER}{ACTIVE} = "on";
        
        if ($attr{$name}{debugactivetoken}) {
            $logstr = "Active-Token was set by OPMODE: $hash->{OPMODE}" ;
            &printlog($hash,$logstr,"3");
        }
        
        &getapisites_nonbl($hash);
    }
    else
    {
    InternalTimer(gettimeofday()+0.13, "camexpmode", $hash, 0);
    }
}


###############################################################################
###   Art der Bewegungserkennung setzen

sub cammotdetsc ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    my $logstr;
    my $errorcode;
    my $error;
    
    if (ReadingsVal("$name", "state", "") =~ /^dis.*/) {
        if (ReadingsVal("$name", "state", "") eq "disabled") {
            $errorcode = "402";
            }
            elsif (ReadingsVal("$name", "state", "") eq "disconnected") {
            $errorcode = "502";
            }
        
        # Fehlertext zum Errorcode ermitteln
        $error = &experror($hash,$errorcode);

        # Setreading 
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash,"Errorcode",$errorcode);
        readingsBulkUpdate($hash,"Error",$error);
        readingsEndUpdate($hash, 1);
    
        $logstr = "ERROR - Setting of motion detection source of Camera $camname can't be executed - $error" ;
        &printlog($hash,$logstr,"1");
        return;
        }
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {
        
        $logstr = "Setting of motion detection source of Camera $camname will be started now";
        &printlog($hash,$logstr,"4");
                           
        $hash->{OPMODE} = "MotDetSc";
        $hash->{HELPER}{ACTIVE} = "on";
        
        if ($attr{$name}{debugactivetoken}) {
            $logstr = "Active-Token was set by OPMODE: $hash->{OPMODE}" ;
            &printlog($hash,$logstr,"3");
        }
        
        &getapisites_nonbl($hash);
    }
    else
    {
    InternalTimer(gettimeofday()+0.14, "cammotdetsc", $hash, 0);
    }
}



###############################################################################
###   Kamera Schappschuß aufnehmen

sub camsnap ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    my $logstr;
    my $errorcode;
    my $error;
    
    if (ReadingsVal("$name", "state", "") =~ /^dis.*/) {
        if (ReadingsVal("$name", "state", "") eq "disabled") {
            $errorcode = "402";
            }
            elsif (ReadingsVal("$name", "state", "") eq "disconnected") {
            $errorcode = "502";
            }
        
        # Fehlertext zum Errorcode ermitteln
        $error = &experror($hash,$errorcode);

        # Setreading 
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash,"Errorcode",$errorcode);
        readingsBulkUpdate($hash,"Error",$error);
        readingsEndUpdate($hash, 1);
    
        $logstr = "ERROR - Snapshot of Camera $camname can't be executed - $error" ;
        &printlog($hash,$logstr,"1");
        return;
        }
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {
        # einen Schnappschuß aufnehmen
        $logstr = "Take Snapshot of Camera $camname";
        &printlog($hash,$logstr,"4");
                        
        $hash->{OPMODE} = "Snap";
        $hash->{HELPER}{ACTIVE} = "on";
        
        if ($attr{$name}{debugactivetoken}) {
            $logstr = "Active-Token was set by OPMODE: $hash->{OPMODE}" ;
            &printlog($hash,$logstr,"3");
        }
        
        &getapisites_nonbl($hash);
    }
    else
    {
        InternalTimer(gettimeofday()+0.22, "camsnap", $hash, 0);
    }    
}

###############################################################################
###   Kamera Liveview starten

sub runliveview ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    my $logstr;
    my $errorcode;
    my $error;
    
    if (ReadingsVal("$name", "state", "") =~ /^dis.*/) {
        if (ReadingsVal("$name", "state", "") eq "disabled") {
            $errorcode = "402";
            }
            elsif (ReadingsVal("$name", "state", "") eq "disconnected") {
            $errorcode = "502";
            }
        
        # Fehlertext zum Errorcode ermitteln
        $error = &experror($hash,$errorcode);

        # Setreading 
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash,"Errorcode",$errorcode);
        readingsBulkUpdate($hash,"Error",$error);
        readingsEndUpdate($hash, 1);
    
        $logstr = "ERROR - Liveview of Camera $camname can't be started - $error" ;
        &printlog($hash,$logstr,"1");
        return;
        }
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {
        # Liveview starten
        $logstr = "Start Liveview of Camera $camname";
        &printlog($hash,$logstr,"4");
                        
        $hash->{OPMODE} = "runliveview";
        $hash->{HELPER}{ACTIVE} = "on";
        
        if ($attr{$name}{debugactivetoken}) {
            $logstr = "Active-Token was set by OPMODE: $hash->{OPMODE}" ;
            &printlog($hash,$logstr,"3");
        }
        
        readingsSingleUpdate($hash,"state","startview",1); 
        
        &getapisites_nonbl($hash);
    }
    else
    {
        InternalTimer(gettimeofday()+0.23, "runliveview", $hash, 0);
    }    
}

###############################################################################
###   Kamera Liveview stoppen

sub stopliveview ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    my $logstr;
    my $errorcode;
    my $error;
   
    if ($hash->{HELPER}{ACTIVE} eq "off") {
        
        return if (!$hash->{HELPER}{SID_STRM});  # runView ist nicht ausgeführt
        
        # kurzer state-switch -> Browser aktualisieren
        readingsSingleUpdate($hash,"state","stopview",1); 
        
        # Liveview stoppen
        $logstr = "Stop Liveview of Camera $camname now";
        &printlog($hash,$logstr,"4");
                        
        $hash->{OPMODE} = "stopliveview";
        $hash->{HELPER}{ACTIVE} = "on";
        
        if ($attr{$name}{debugactivetoken}) {
            $logstr = "Active-Token was set by OPMODE: $hash->{OPMODE}" ;
            &printlog($hash,$logstr,"3");
        }
        
        $hash->{HELPER}{SID} = $hash->{HELPER}{SID_STRM};
        
        # Liveview-SID und Link aus Helper-hash löschen
        delete $hash->{HELPER}{SID_STRM};
        delete $hash->{HELPER}{LINK};
        
        readingsSingleUpdate($hash,"LiveStreamUrl", "", 1);
        
        if (ReadingsVal("$name", "Record", "") eq "Start") {
            readingsSingleUpdate( $hash,"state", "on", 1); 
            }
            else
            {
            readingsSingleUpdate($hash,"state", "off", 1); 
            }        
        
        logout_nonbl($hash);
    }
    else
    {
        InternalTimer(gettimeofday()+0.23, "stopliveview", $hash, 0);
    }    
}

###############################################################################
###   Filename zu Schappschuß ermitteln

sub getsnapfilename ($) {
    my ($hash)   = @_;
    my $name     = $hash->{NAME};
    my $logstr;
    my $snapid   = ReadingsVal("$name", "LastSnapId", " ");
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {
        # den Filenamen zu einem Schnappschuß ermitteln
        $logstr = "Get filename of present Snap-ID $snapid ";
        &printlog($hash,$logstr,"4");
                        
        $hash->{OPMODE} = "getsnapfilename";
        $hash->{HELPER}{ACTIVE} = "on";
        
        if ($attr{$name}{debugactivetoken}) {
            $logstr = "Active-Token was set by OPMODE: $hash->{OPMODE}" ;
            &printlog($hash,$logstr,"3");
        }
        
        getapisites_nonbl($hash);
    }
    else
    {
        InternalTimer(gettimeofday()+0.23, "getsnapfilename", $hash, 0);
    }    
}


###############################################################################
###   external Event 1-10 auslösen

sub extevent ($) {
    my ($hash)   = @_;
    my $name     = $hash->{NAME};
    my $logstr;
    
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {
        
        $logstr = "trigger external event \"$hash->{HELPER}{EVENTID}\" ";
        &printlog($hash,$logstr,"4");
                        
        $hash->{OPMODE} = "extevent";
        $hash->{HELPER}{ACTIVE} = "on";
        
        if ($attr{$name}{debugactivetoken}) {
            $logstr = "Active-Token was set by OPMODE: $hash->{OPMODE}" ;
            &printlog($hash,$logstr,"3");
        }
        
        getapisites_nonbl($hash);
    }
    else
    {
        InternalTimer(gettimeofday()+0.24, "extevent", $hash, 0);
    }    
}

###############################################################################
###   PTZ-Kamera auf Position fahren

sub doptzaction ($) {
    my ($hash)             = @_;
    my $camname            = $hash->{CAMNAME};
    my $name               = $hash->{NAME};
    my $logstr;
    my $errorcode;
    my $error;

    if (ReadingsVal("$name", "DeviceType", "Camera") ne "PTZ") {
        $logstr = "ERROR - Operation \"$hash->{HELPER}{PTZACTION}\" is only possible for cameras of DeviceType \"PTZ\" - please compare with device Readings" ;
        &printlog($hash,$logstr,"1");
        return;
        }
    if ($hash->{HELPER}{PTZACTION} eq "goabsptz" && !ReadingsVal("$name", "CapPTZAbs", "false")) {
        $logstr = "ERROR - Operation \"$hash->{HELPER}{PTZACTION}\" is only possible if camera supports absolute PTZ action - please compare with device Reading \"CapPTZAbs\"" ;
        &printlog($hash,$logstr,"1");
        return;
        }
    if ( $hash->{HELPER}{PTZACTION} eq "movestart" && ReadingsVal("$name", "CapPTZDirections", "0") < 1) {
        $logstr = "ERROR - Operation \"$hash->{HELPER}{PTZACTION}\" is only possible if camera supports \"Tilt\" and \"Pan\" operations - please compare with device Reading \"CapPTZDirections\"" ;
        &printlog($hash,$logstr,"1");
        return;
        }
    
    if ($hash->{HELPER}{PTZACTION} eq "gopreset") {
        if (!defined($hash->{HELPER}{ALLPRESETS}{$hash->{HELPER}{GOPRESETNAME}})) {
            $errorcode = "600";
            # Fehlertext zum Errorcode ermitteln
            $error = &experror($hash,$errorcode);
        
            # Setreading 
            readingsBeginUpdate($hash);
            readingsBulkUpdate($hash,"Errorcode",$errorcode);
            readingsBulkUpdate($hash,"Error",$error);
            readingsEndUpdate($hash, 1);
    
            $logstr = "ERROR - goPreset to position \"$hash->{HELPER}{GOPRESETNAME}\" of Camera $camname can't be executed - $error" ;
            &printlog($hash,$logstr,"1");
            return;        
            }
    }
    
    if ($hash->{HELPER}{PTZACTION} eq "runpatrol") {
        if (!defined($hash->{HELPER}{ALLPATROLS}{$hash->{HELPER}{GOPATROLNAME}})) {
            $errorcode = "600";
            # Fehlertext zum Errorcode ermitteln
            $error = &experror($hash,$errorcode);
        
            # Setreading 
            readingsBeginUpdate($hash);
            readingsBulkUpdate($hash,"Errorcode",$errorcode);
            readingsBulkUpdate($hash,"Error",$error);
            readingsEndUpdate($hash, 1);
    
            $logstr = "ERROR - runPatrol to patrol \"$hash->{HELPER}{GOPATROLNAME}\" of Camera $camname can't be executed - $error" ;
            &printlog($hash,$logstr,"1");
            return;        
            }
    }
    
    if (ReadingsVal("$name", "state", "") =~ /^dis.*/) {
        if (ReadingsVal("$name", "state", "") eq "disabled") {
            $errorcode = "402";
            }
            elsif (ReadingsVal("$name", "state", "") eq "disconnected") {
            $errorcode = "502";
            }
        
        # Fehlertext zum Errorcode ermitteln
        $error = &experror($hash,$errorcode);

        # Setreading 
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash,"Errorcode",$errorcode);
        readingsBulkUpdate($hash,"Error",$error);
        readingsEndUpdate($hash, 1);
    
        $logstr = "ERROR - $hash->{HELPER}{PTZACTION} of Camera $camname can't be executed - $error" ;
        &printlog($hash,$logstr,"1");
        return;
        }
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {
        
        if ($hash->{HELPER}{PTZACTION} eq "gopreset") {
            $logstr = "Move Camera $camname to position \"$hash->{HELPER}{GOPRESETNAME}\" with ID \"$hash->{HELPER}{ALLPRESETS}{$hash->{HELPER}{GOPRESETNAME}}\" now";
            &printlog($hash,$logstr,"4");
            }
            elsif ($hash->{HELPER}{PTZACTION} eq "runpatrol") {
            $logstr = "Start patrol \"$hash->{HELPER}{GOPATROLNAME}\" with ID \"$hash->{HELPER}{ALLPATROLS}{$hash->{HELPER}{GOPATROLNAME}}\" of Camera $camname now";
            &printlog($hash,$logstr,"4");
            }
            elsif ($hash->{HELPER}{PTZACTION} eq "goabsptz") {
            $logstr = "Start move Camera $camname to position posX=\"$hash->{HELPER}{GOPTZPOSX}\" and posY=\"$hash->{HELPER}{GOPTZPOSY}\"  now";
            &printlog($hash,$logstr,"4");
            }
            elsif ($hash->{HELPER}{PTZACTION} eq "movestart") {
            $logstr = "Start move Camera $camname to direction \"$hash->{HELPER}{GOMOVEDIR}\" with duration of $hash->{HELPER}{GOMOVETIME} s";
            &printlog($hash,$logstr,"4");
            }
 
        if ($attr{$name}{debugactivetoken}) {
             $logstr = "Active-Token was set by OPMODE: $hash->{OPMODE}" ;
             &printlog($hash,$logstr,"3");
        }
    
    $hash->{OPMODE} = $hash->{HELPER}{PTZACTION};
    $hash->{HELPER}{ACTIVE} = "on";
 
    &getapisites_nonbl($hash);
 
    }
    else
    {
    InternalTimer(gettimeofday()+0.31, "doptzaction", $hash, 0);
    }    
}

###############################################################################
###   stoppen continues move

sub movestop ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    my $logstr;
    
   if ($hash->{HELPER}{ACTIVE} eq "off") {
            $logstr = "Stop Camera $camname moving to direction \"$hash->{HELPER}{GOMOVEDIR}\" now";
            &printlog($hash,$logstr,"4");
                        
            $hash->{OPMODE} = "movestop";
            $hash->{HELPER}{ACTIVE} = "on";
            
            if ($attr{$name}{debugactivetoken}) {
                $logstr = "Active-Token was set by OPMODE: $hash->{OPMODE}" ;
                &printlog($hash,$logstr,"3");
            }
        
            &getapisites_nonbl($hash);
    }
    else
    {
    InternalTimer(gettimeofday()+0.121, "movestop", $hash, 0);
    }    
}

###############################################################################
###   Kamera aktivieren

sub camenable ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    my $logstr;
    
    if (ReadingsVal("$name", "Availability", "disabled") eq "enabled") {return;}       # Kamera ist bereits enabled
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {
        # eine Kamera aktivieren
        $logstr = "Enable Camera $camname";
        &printlog($hash,$logstr,"4");
                        
        $hash->{OPMODE} = "Enable";
        $hash->{HELPER}{ACTIVE} = "on";
        
        if ($attr{$name}{debugactivetoken}) {
            $logstr = "Active-Token was set by OPMODE: $hash->{OPMODE}" ;
            &printlog($hash,$logstr,"3");
        }
        
        &getapisites_nonbl($hash);
    }
    else
    {
    InternalTimer(gettimeofday()+0.41, "camenable", $hash, 0);
    }    
}

###############################################################################
###   Kamera deaktivieren

sub camdisable ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    my $logstr;
    
    if (ReadingsVal("$name", "Availability", "enabled") eq "disabled") {return;}       # Kamera ist bereits disabled
    
    if ($hash->{HELPER}{ACTIVE} eq "off" and ReadingsVal("$name", "Record", "Start") ne "Start") {
        # eine Kamera deaktivieren
        $logstr = "Disable Camera $camname";
        &printlog($hash,$logstr,"4");
                        
        $hash->{OPMODE} = "Disable";
        $hash->{HELPER}{ACTIVE} = "on";
        
        if ($attr{$name}{debugactivetoken}) {
            $logstr = "Active-Token was set by OPMODE: $hash->{OPMODE}" ;
            &printlog($hash,$logstr,"3");
        }
        
        &getapisites_nonbl($hash);
    }
    else
    {
    InternalTimer(gettimeofday()+0.43, "camdisable", $hash, 0);
    }    
}

###############################################################################
###   Kamera alle Informationen abrufen (Get) bzw. Einstieg Polling

sub getcaminfoall {
    my ($hash,$mode)   = @_;
    my $camname        = $hash->{CAMNAME};
    my $name           = $hash->{NAME};
    my $logstr;
    my ($now,$new);
    
        geteventlist($hash);
        getcaminfo($hash);
        getmotionenum($hash);
        getcapabilities($hash);
        getptzlistpreset($hash);
        getptzlistpatrol($hash);
    
    # wenn gesetzt = manuelle Abfrage,
    if ($mode) {return;}
    
    if (defined($attr{$name}{pollcaminfoall}) and $attr{$name}{pollcaminfoall} > 10) {
        # Pollen wenn pollcaminfo > 10, sonst kein Polling
        
        $new = gettimeofday()+$attr{$name}{pollcaminfoall};
                    
        InternalTimer($new, "getcaminfoall", $hash, 0);
        
        if (!$attr{$name}{pollnologging}) {
            $now = FmtTime(gettimeofday());
            $new = FmtTime(gettimeofday()+$attr{$name}{pollcaminfoall});
            $logstr = "Polling now: $now , next Polling: $new";
            &printlog($hash,$logstr,"3");
        }
    }
    else 
    {
        # Beenden Polling aller Caminfos
        readingsSingleUpdate($hash,"PollState","Inactive",0);
        
        $logstr = "Polling of Camera $camname is currently deactivated";
        &printlog($hash,$logstr,"3");
        }
return;
}

###########################################################################
###   allgemeine Infos über Synology Surveillance Station

sub getsvsinfo ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    my $logstr;
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {
        # Kamerainfos abrufen
        $logstr = "Retrieval of Surveillance Station related informations starts now";
        &printlog($hash,$logstr,"4");
                        
        $hash->{OPMODE} = "Getsvsinfo";
        $hash->{HELPER}{ACTIVE} = "on";
        
        if ($attr{$name}{debugactivetoken}) {
            $logstr = "Active-Token was set by OPMODE: $hash->{OPMODE}" ;
            &printlog($hash,$logstr,"3");
        }
        
        &getapisites_nonbl($hash);
      }
    else
    {
        InternalTimer(gettimeofday()+0.54, "getsvsinfo", $hash, 0);
    }
    
}

###########################################################################
###   Kamera allgemeine Informationen abrufen (Get), sub von getcaminfoall

sub getcaminfo ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    my $logstr;
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {
        # Kamerainfos abrufen
        $logstr = "Retrieval Camera-Informations of $camname starts now";
        &printlog($hash,$logstr,"4");
                        
        $hash->{OPMODE} = "Getcaminfo";
        $hash->{HELPER}{ACTIVE} = "on";
        
        if ($attr{$name}{debugactivetoken}) {
            $logstr = "Active-Token was set by OPMODE: $hash->{OPMODE}" ;
            &printlog($hash,$logstr,"3");
        }
        
        getapisites_nonbl($hash);
    }
    else
    {
        InternalTimer(gettimeofday()+1.33 , "getcaminfo", $hash, 0);
    }
    
}

###########################################################################
###   query SVS-Event information , sub von getcaminfoall

sub geteventlist ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    my $logstr;
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {
        # Kamerainfos abrufen
        $logstr = "Query event informations of $camname starts now";
        &printlog($hash,$logstr,"4");
                        
        $hash->{OPMODE} = "geteventlist";
        $hash->{HELPER}{ACTIVE} = "on";
        
        if ($attr{$name}{debugactivetoken}) {
            $logstr = "Active-Token was set by OPMODE: $hash->{OPMODE}" ;
            &printlog($hash,$logstr,"3");
        }
        
        getapisites_nonbl($hash);
    }
    else
    {
        InternalTimer(gettimeofday()+0.55 , "geteventlist", $hash, 0);
    }
    
}

###########################################################################
###   Enumerate motion detection parameters, sub von getcaminfoall

sub getmotionenum ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    my $logstr;
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {
        $logstr = "Enumerate motion detection parameters of $camname starts now";
        &printlog($hash,$logstr,"4");
                        
        $hash->{OPMODE} = "getmotionenum";
        $hash->{HELPER}{ACTIVE} = "on";
        
        if ($attr{$name}{debugactivetoken}) {
            $logstr = "Active-Token was set by OPMODE: $hash->{OPMODE}" ;
            &printlog($hash,$logstr,"3");
        }
        
        getapisites_nonbl($hash);
    }
    else
    {
        InternalTimer(gettimeofday()+1.38 , "getmotionenum", $hash, 0);
    }
    
}

##########################################################################
###  Capabilities von Kamera abrufen (Get), sub von getcaminfoall

sub getcapabilities ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    my $logstr;
    
        if ($hash->{HELPER}{ACTIVE} eq "off") {
        # PTZ-ListPresets abrufen
        $logstr = "Retrieval Capabilities of Camera $camname starts now";
        &printlog($hash,$logstr,"4");
                        
        $hash->{OPMODE} = "Getcapabilities";
        $hash->{HELPER}{ACTIVE} = "on";
        
        if ($attr{$name}{debugactivetoken}) {
            $logstr = "Active-Token was set by OPMODE: $hash->{OPMODE}" ;
            &printlog($hash,$logstr,"3");
        }
        
        &getapisites_nonbl($hash);
    }
    else
    {
        InternalTimer(gettimeofday()+1.56, "getcapabilities", $hash, 0);
    }
    
}

##########################################################################
###   PTZ Presets abrufen (Get), sub von getcaminfoall

sub getptzlistpreset ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    my $logstr;
    
    if (defined(ReadingsVal("$name", "DeviceType", undef)) and ReadingsVal("$name", "DeviceType", undef) ne "PTZ") {
        $logstr = "Retrieval of Presets for $camname can't be executed - $camname is not a PTZ-Camera";
        &printlog($hash,$logstr,"4");
        return;
        }

        if ($hash->{HELPER}{ACTIVE} eq "off") {
        # PTZ-ListPresets abrufen
        $logstr = "Retrieval PTZ-ListPresets of $camname starts now";
        &printlog($hash,$logstr,"4");
                        
        $hash->{OPMODE} = "Getptzlistpreset";
        $hash->{HELPER}{ACTIVE} = "on";

        if ($attr{$name}{debugactivetoken}) {
            $logstr = "Active-Token was set by OPMODE: $hash->{OPMODE}" ;
            &printlog($hash,$logstr,"3");
        }
        
        &getapisites_nonbl($hash);
    }
    else
    {
        InternalTimer(gettimeofday()+1.57, "getptzlistpreset", $hash, 0);
    }
    
}


##########################################################################
###   PTZ Patrols abrufen (Get), sub von getcaminfoall

sub getptzlistpatrol ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    my $logstr;
    
    if (defined(ReadingsVal("$name", "DeviceType", undef)) and ReadingsVal("$name", "DeviceType", undef) ne "PTZ") {
        $logstr = "Retrieval of Patrols for $camname can't be executed - $camname is not a PTZ-Camera";
        &printlog($hash,$logstr,"4");
        return;
        }

        if ($hash->{HELPER}{ACTIVE} ne "on") {
        # PTZ-ListPatrols abrufen
        $logstr = "Retrieval PTZ-ListPatrols of $camname starts now";
        &printlog($hash,$logstr,"4");
                        
        $hash->{OPMODE} = "Getptzlistpatrol";
        $hash->{HELPER}{ACTIVE} = "on";
        
        if ($attr{$name}{debugactivetoken}) {
            $logstr = "Active-Token was set by OPMODE: $hash->{OPMODE}" ;
            &printlog($hash,$logstr,"3");
        }
        
        &getapisites_nonbl($hash);
    }
    else
    {
        InternalTimer(gettimeofday()+1.58, "getptzlistpatrol", $hash, 0);
    }
    
}


#############################################################################################################################
#######    Begin Kameraoperationen mit NonblockingGet (nicht blockierender HTTP-Call)                                 #######
#######                                                                                                               #######
#######    Ablauflogik:                                                                                               #######
#######                                                                                                               #######
#######                                                                                                               #######
#######    OpMode-Startroutine                                                                                        #######
#######            |                                                                                                  #######
#######    getapisites_nonbl -> login_nonbl ->  getcamid_nonbl  -> camop_nonbl ->  camret_nonbl -> logout_nonbl       #######
#######                                                                 |                                             #######
#######                                                               OpMode                                          #######
#######                                                                                                               #######
#############################################################################################################################

sub getapisites_nonbl {
   my ($hash) = @_;
   my $serveraddr  = $hash->{SERVERADDR};
   my $serverport  = $hash->{SERVERPORT};
   my $name        = $hash->{NAME};
   my $apiinfo     = $hash->{HELPER}{APIINFO};                         # Info-Seite für alle API's, einzige statische Seite !
   my $apiauth     = $hash->{HELPER}{APIAUTH};                         # benötigte API-Pfade für Funktionen,  
   my $apiextrec   = $hash->{HELPER}{APIEXTREC};                       # in der Abfrage-Url an Parameter "&query="
   my $apiextevt   = $hash->{HELPER}{APIEXTEVT};                       # mit Komma getrennt angeben
   my $apicam      = $hash->{HELPER}{APICAM};                          
   my $apitakesnap = $hash->{HELPER}{APISNAPSHOT};
   my $apiptz      = $hash->{HELPER}{APIPTZ};
   my $apisvsinfo  = $hash->{HELPER}{APISVSINFO};
   my $apicamevent = $hash->{HELPER}{APICAMEVENT};
   my $apievent    = $hash->{HELPER}{APIEVENT};
   my $apivideostm = $hash->{HELPER}{APIVIDEOSTM};
   my $logstr;
   my $url;
   my $param;
   my $httptimeout;
  
   #### API-Pfade und MaxVersions ermitteln #####
 
   $logstr = "--- Begin Function getapisites nonblocking ---";
   &printlog($hash,$logstr,"4");
   
   $httptimeout = $attr{$name}{httptimeout} ? $attr{$name}{httptimeout} : "4";

   $logstr = "HTTP-Call will be done with httptimeout-Value: $httptimeout s";
   &printlog($hash,$logstr,"5");

   # URL zur Abfrage der Eigenschaften der  API's
   $url = "http://$serveraddr:$serverport/webapi/query.cgi?api=$apiinfo&method=Query&version=1&query=$apiauth,$apiextrec,$apicam,$apitakesnap,$apiptz,$apisvsinfo,$apicamevent,$apievent,$apivideostm,$apiextevt";

   $logstr = "Call-Out now: $url";
   &printlog($hash,$logstr,"4");    
   
   $param = {
               url      => $url,
               timeout  => $httptimeout,
               hash     => $hash,
               method   => "GET",
               header   => "Accept: application/json",
               callback => \&login_nonbl
            };

   HttpUtils_NonblockingGet ($param);  
} 
    

####################################################################################  
####      Rückkehr aus Funktion API-Pfade und MaxVersions ermitteln,  
####      nach erfolgreicher Verarbeitung wird login ausgeführt und $sid ermittelt

sub login_nonbl ($) {
   my ($param, $err, $myjson) = @_;
   my $hash        = $param->{hash};
   my $name        = $hash->{NAME};
   my $serveraddr  = $hash->{SERVERADDR};
   my $serverport  = $hash->{SERVERPORT};
   my $username    = $hash->{HELPER}{USERNAME};
   my $password    = $hash->{HELPER}{PASSWORD};
   my $apiauth     = $hash->{HELPER}{APIAUTH};
   my $apiextrec   = $hash->{HELPER}{APIEXTREC};
   my $apiextevt   = $hash->{HELPER}{APIEXTEVT};
   my $apicam      = $hash->{HELPER}{APICAM};
   my $apitakesnap = $hash->{HELPER}{APISNAPSHOT};
   my $apiptz      = $hash->{HELPER}{APIPTZ};
   my $apisvsinfo  = $hash->{HELPER}{APISVSINFO};
   my $apicamevent = $hash->{HELPER}{APICAMEVENT};
   my $apievent    = $hash->{HELPER}{APIEVENT};
   my $apivideostm = $hash->{HELPER}{APIVIDEOSTM};
   my $data;
   my $logstr;
   my $url;
   my $success;
   my $apiauthpath;
   my $apiauthmaxver;
   my $apiextrecpath;
   my $apiextrecmaxver;
   my $apicampath;
   my $apicammaxver;
   my $apitakesnappath;
   my $apitakesnapmaxver;
   my $apiptzpath;
   my $apiptzmaxver;
   my $apisvsinfopath;
   my $apisvsinfomaxver;
   my $apicameventpath;
   my $apicameventmaxver;
   my ($apieventpath,$apieventmaxver);
   my ($apivideostmpath,$apivideostmmaxver);
   my ($apiextevtpath,$apiextevtmaxver);
   my $error;
   my $httptimeout;
  
    # Verarbeitung der asynchronen Rückkehrdaten aus sub "getapisites_nonbl"
    if ($err ne "")                                                                                    # wenn ein Fehler bei der HTTP Abfrage aufgetreten ist
    {
        $logstr = "error while requesting ".$param->{url}." - $err";
        &printlog($hash,$logstr,"1");	                                                             
        $logstr = "--- End Function getapisites nonblocking with error ---";
        &printlog($hash,$logstr,"4");
       
        readingsSingleUpdate($hash, "Error", $err, 1);                                     	       # Readings erzeugen

        # ausgeführte Funktion ist abgebrochen, Freigabe Funktionstoken
        $hash->{HELPER}{ACTIVE} = "off"; 
        
        if ($attr{$name}{debugactivetoken}) {
            $logstr = "Active-Token deleted by OPMODE: $hash->{OPMODE}" ;
            &printlog($hash,$logstr,"3");
        }

        return;
    }
    elsif ($myjson ne "")                                                                               # wenn die Abfrage erfolgreich war ($data enthält die Ergebnisdaten des HTTP Aufrufes)
    {          
        
        # Evaluiere ob Daten im JSON-Format empfangen wurden
        ($hash, $success) = &evaljson($hash,$myjson,$param->{url});
        
        unless ($success) {
            $logstr = "Data returned: ".$myjson; &printlog($hash,$logstr,"4"); 
            $hash->{HELPER}{ACTIVE} = "off";
            
            if ($attr{$name}{debugactivetoken}) {
                $logstr = "Active-Token deleted by OPMODE: $hash->{OPMODE}" ;
                &printlog($hash,$logstr,"3");
            }
            return;
        }
        
        $data = decode_json($myjson);
   
        $success = $data->{'success'};
    
                if ($success) 
                     {
                        # Logausgabe decodierte JSON Daten
                        $logstr = "JSON returned: ". Dumper $data;                                                         
                        &printlog($hash,$logstr,"4");
                        
                     # Pfad und Maxversion von "SYNO.API.Auth" ermitteln
       
                        $apiauthpath = $data->{'data'}->{$apiauth}->{'path'};
                        # Unterstriche im Ergebnis z.B.  "_______entry.cgi" eleminieren
                        $apiauthpath =~ tr/_//d if (defined($apiauthpath));
                        $apiauthmaxver = $data->{'data'}->{$apiauth}->{'maxVersion'}; 
       
                        $logstr = defined($apiauthpath) ? "Path of $apiauth selected: $apiauthpath" : "Path of $apiauth undefined - Surveillance Station may be stopped";
                        &printlog($hash, $logstr,"4");
                        $logstr = defined($apiauthmaxver) ? "MaxVersion of $apiauth selected: $apiauthmaxver" : "MaxVersion of $apiauth undefined - Surveillance Station may be stopped";
                        &printlog($hash, $logstr,"4");
       
                     # Pfad und Maxversion von "SYNO.SurveillanceStation.ExternalRecording" ermitteln
       
                        $apiextrecpath = $data->{'data'}->{$apiextrec}->{'path'};
                        # Unterstriche im Ergebnis z.B.  "_______entry.cgi" eleminieren
                        $apiextrecpath =~ tr/_//d if (defined($apiextrecpath));
                        $apiextrecmaxver = $data->{'data'}->{$apiextrec}->{'maxVersion'}; 
       
                        $logstr = defined($apiextrecpath) ? "Path of $apiextrec selected: $apiextrecpath" : "Path of $apiextrec undefined - Surveillance Station may be stopped";
                        &printlog($hash, $logstr,"4");
                        $logstr = defined($apiextrecmaxver) ? "MaxVersion of $apiextrec selected: $apiextrecmaxver" : "MaxVersion of $apiextrec undefined - Surveillance Station may be stopped";
                        &printlog($hash, $logstr,"4");
       
                     # Pfad und Maxversion von "SYNO.SurveillanceStation.Camera" ermitteln
              
                        $apicampath = $data->{'data'}->{$apicam}->{'path'};
                        # Unterstriche im Ergebnis z.B.  "_______entry.cgi" eleminieren
                        $apicampath =~ tr/_//d if (defined($apicampath));
                        $apicammaxver = $data->{'data'}->{$apicam}->{'maxVersion'};
                               
                        $logstr = defined($apicampath) ? "Path of $apicam selected: $apicampath" : "Path of $apicam undefined - Surveillance Station may be stopped";
                        &printlog($hash, $logstr,"4");
                        $logstr = defined($apiextrecmaxver) ? "MaxVersion of $apicam: $apicammaxver" : "MaxVersion of $apicam undefined - Surveillance Station may be stopped";
                        &printlog($hash, $logstr,"4");
       
                     # Pfad und Maxversion von "SYNO.SurveillanceStation.SnapShot" ermitteln
              
                        $apitakesnappath = $data->{'data'}->{$apitakesnap}->{'path'};
                        # Unterstriche im Ergebnis z.B.  "_______entry.cgi" eleminieren
                        $apitakesnappath =~ tr/_//d if (defined($apitakesnappath));
                        $apitakesnapmaxver = $data->{'data'}->{$apitakesnap}->{'maxVersion'};
                            
                        $logstr = defined($apitakesnappath) ? "Path of $apitakesnap selected: $apitakesnappath" : "Path of $apitakesnap undefined - Surveillance Station may be stopped";
                        &printlog($hash, $logstr,"4");
                        $logstr = defined($apitakesnapmaxver) ? "MaxVersion of $apitakesnap: $apitakesnapmaxver" : "MaxVersion of $apitakesnap undefined - Surveillance Station may be stopped";
                        &printlog($hash, $logstr,"4");

                     # Pfad und Maxversion von "SYNO.SurveillanceStation.PTZ" ermitteln
              
                        $apiptzpath = $data->{'data'}->{$apiptz}->{'path'};
                        # Unterstriche im Ergebnis z.B.  "_______entry.cgi" eleminieren
                        $apiptzpath =~ tr/_//d if (defined($apiptzpath));
                        $apiptzmaxver = $data->{'data'}->{$apiptz}->{'maxVersion'};
                            
                        $logstr = defined($apiptzpath) ? "Path of $apiptz selected: $apiptzpath" : "Path of $apiptz undefined - Surveillance Station may be stopped";
                        &printlog($hash, $logstr,"4");
                        $logstr = defined($apiptzmaxver) ? "MaxVersion of $apiptz: $apiptzmaxver" : "MaxVersion of $apiptz undefined - Surveillance Station may be stopped";
                        &printlog($hash, $logstr,"4");					

                     # Pfad und Maxversion von "SYNO.SurveillanceStation.Info" ermitteln
              
                        $apisvsinfopath = $data->{'data'}->{$apisvsinfo}->{'path'};
                        # Unterstriche im Ergebnis z.B.  "_______entry.cgi" eleminieren
                        $apisvsinfopath =~ tr/_//d if (defined($apisvsinfopath));
                        $apisvsinfomaxver = $data->{'data'}->{$apisvsinfo}->{'maxVersion'};
                            
                        $logstr = defined($apisvsinfopath) ? "Path of $apisvsinfo selected: $apisvsinfopath" : "Path of $apisvsinfo undefined - Surveillance Station may be stopped";
                        &printlog($hash, $logstr,"4");
                        $logstr = defined($apisvsinfomaxver) ? "MaxVersion of $apisvsinfo: $apisvsinfomaxver" : "MaxVersion of $apisvsinfo undefined - Surveillance Station may be stopped";
                        &printlog($hash, $logstr,"4");
                        
                     # Pfad und Maxversion von "SYNO.Surveillance.Camera.Event" ermitteln
              
                        $apicameventpath = $data->{'data'}->{$apicamevent}->{'path'};
                        # Unterstriche im Ergebnis z.B.  "_______entry.cgi" eleminieren
                        $apicameventpath =~ tr/_//d if (defined($apicameventpath));
                        $apicameventmaxver = $data->{'data'}->{$apicamevent}->{'maxVersion'};
                            
                        $logstr = defined($apicameventpath) ? "Path of $apicamevent selected: $apicameventpath" : "Path of $apicamevent undefined - Surveillance Station may be stopped";
                        &printlog($hash, $logstr,"4");
                        $logstr = defined($apicameventmaxver) ? "MaxVersion of $apicamevent: $apicameventmaxver" : "MaxVersion of $apicamevent undefined - Surveillance Station may be stopped";
                        &printlog($hash, $logstr,"4"); 
                        
                     # Pfad und Maxversion von "SYNO.Surveillance.Event" ermitteln
              
                        $apieventpath = $data->{'data'}->{$apievent}->{'path'};
                        # Unterstriche im Ergebnis z.B.  "_______entry.cgi" eleminieren
                        $apieventpath =~ tr/_//d if (defined($apieventpath));
                        $apieventmaxver = $data->{'data'}->{$apievent}->{'maxVersion'};
                            
                        $logstr = defined($apieventpath) ? "Path of $apievent selected: $apieventpath" : "Path of $apievent undefined - Surveillance Station may be stopped";
                        &printlog($hash, $logstr,"4");
                        $logstr = defined($apieventmaxver) ? "MaxVersion of $apievent: $apieventmaxver" : "MaxVersion of $apievent undefined - Surveillance Station may be stopped";
                        &printlog($hash, $logstr,"4"); 
                        
                     # Pfad und Maxversion von "SYNO.Surveillance.VideoStream" ermitteln
              
                        $apivideostmpath = $data->{'data'}->{$apivideostm}->{'path'};
                        # Unterstriche im Ergebnis z.B.  "_______entry.cgi" eleminieren
                        $apivideostmpath =~ tr/_//d if (defined($apivideostmpath));
                        $apivideostmmaxver = $data->{'data'}->{$apivideostm}->{'maxVersion'};
                            
                        $logstr = defined($apivideostmpath) ? "Path of $apivideostm selected: $apivideostmpath" : "Path of $apivideostm undefined - Surveillance Station may be stopped";
                        &printlog($hash, $logstr,"4");
                        $logstr = defined($apivideostmmaxver) ? "MaxVersion of $apivideostm: $apivideostmmaxver" : "MaxVersion of $apivideostm undefined - Surveillance Station may be stopped";
                        &printlog($hash, $logstr,"4"); 
                        
                     # Pfad und Maxversion von "SYNO.SurveillanceStation.ExternalEvent" ermitteln
       
                        $apiextevtpath = $data->{'data'}->{$apiextevt}->{'path'};
                        # Unterstriche im Ergebnis z.B.  "_______entry.cgi" eleminieren
                        $apiextevtpath =~ tr/_//d if (defined($apiextevtpath));
                        $apiextevtmaxver = $data->{'data'}->{$apiextevt}->{'maxVersion'}; 
       
                        $logstr = defined($apiextevtpath) ? "Path of $apiextevt selected: $apiextevtpath" : "Path of $apiextevt undefined - Surveillance Station may be stopped";
                        &printlog($hash, $logstr,"4");
                        $logstr = defined($apiextevtmaxver) ? "MaxVersion of $apiextevt selected: $apiextevtmaxver" : "MaxVersion of $apiextevt undefined - Surveillance Station may be stopped";
                        &printlog($hash, $logstr,"4");
       
                        # ermittelte Werte in $hash einfügen
                        $hash->{HELPER}{APIAUTHPATH}       = $apiauthpath;
                        $hash->{HELPER}{APIAUTHMAXVER}     = $apiauthmaxver;
                        $hash->{HELPER}{APIEXTRECPATH}     = $apiextrecpath;
                        $hash->{HELPER}{APIEXTRECMAXVER}   = $apiextrecmaxver;
                        $hash->{HELPER}{APICAMPATH}        = $apicampath;
                        $hash->{HELPER}{APICAMMAXVER}      = $apicammaxver;
                        $hash->{HELPER}{APITAKESNAPPATH}   = $apitakesnappath;
                        $hash->{HELPER}{APITAKESNAPMAXVER} = $apitakesnapmaxver;
                        $hash->{HELPER}{APIPTZPATH}        = $apiptzpath;
                        $hash->{HELPER}{APIPTZMAXVER}      = $apiptzmaxver;
                        $hash->{HELPER}{APISVSINFOPATH}    = $apisvsinfopath;
                        $hash->{HELPER}{APISVSINFOMAXVER}  = $apisvsinfomaxver;
                        $hash->{HELPER}{APICAMEVENTPATH}   = $apicameventpath;
                        $hash->{HELPER}{APICAMEVENTMAXVER} = $apicameventmaxver;
                        $hash->{HELPER}{APIEVENTPATH}      = $apieventpath;
                        $hash->{HELPER}{APIEVENTMAXVER}    = $apieventmaxver;
                        $hash->{HELPER}{APIVIDEOSTMPATH}   = $apivideostmpath;
                        $hash->{HELPER}{APIVIDEOSTMMAXVER} = $apivideostmmaxver;
                        $hash->{HELPER}{APIEXTEVTPATH}     = $apiextevtpath;
                        $hash->{HELPER}{APIEXTEVTMAXVER}   = $apiextevtmaxver;
       
                        # Setreading 
                        readingsBeginUpdate($hash);
                        readingsBulkUpdate($hash,"Errorcode","none");
                        readingsBulkUpdate($hash,"Error","none");
                        readingsEndUpdate($hash,1);

                        # Logausgabe
                        $logstr = "--- End Function getapisites nonblocking ---";
                        &printlog($hash,$logstr,"4");
                        
                    } 
                    else 
                    {
                        # Fehlertext setzen
                        $error = "couldn't call API-Infosite";
       
                        # Setreading 
                        readingsBeginUpdate($hash);
                        readingsBulkUpdate($hash,"Errorcode","none");
                        readingsBulkUpdate($hash,"Error",$error);
                        readingsEndUpdate($hash, 1);

                        # Logausgabe
                        $logstr = "ERROR - the API-Query couldn't be executed successfully";
                        &printlog($hash,$logstr,"1");

                        $logstr = "--- End Function getapisites nonblocking with error ---";
                        &printlog($hash,$logstr,"4");
                        
                        # ausgeführte Funktion ist abgebrochen, Freigabe Funktionstoken
                        $hash->{HELPER}{ACTIVE} = "off"; 
                        
                        if ($attr{$name}{debugactivetoken}) {
                            $logstr = "Active-Token deleted by OPMODE: $hash->{OPMODE}" ;
                            &printlog($hash,$logstr,"3");
                        }
                        return;
                     }
    }
  
  # Login und SID ermitteln

  $logstr = "--- Begin Function serverlogin nonblocking ---";
  &printlog($hash,$logstr,"4");
  
  # Credentials abrufen
  ($success, $username, $password) = getcredentials($hash,0);
  
  unless ($success) {
      $logstr = "Credentials couldn't be retrieved successfully - make sure you've set it with \"set $name credentials <username> <password>\""; 
      &printlog($hash,$logstr,"1"); 
      
      $hash->{HELPER}{ACTIVE} = "off";
      
      if ($attr{$name}{debugactivetoken}) {
          $logstr = "Active-Token deleted by OPMODE: $hash->{OPMODE}" ;
          &printlog($hash,$logstr,"3");
      }      
      return;
  }
  
  $httptimeout = $attr{$name}{httptimeout} ? $attr{$name}{httptimeout} : "4";
  
  $logstr = "HTTP-Call will be done with httptimeout-Value: $httptimeout s";
  &printlog($hash,$logstr,"5");  
 
  if (defined($attr{$name}{session}) and $attr{$name}{session} eq "SurveillanceStation") {
      $url = "http://$serveraddr:$serverport/webapi/$apiauthpath?api=$apiauth&version=$apiauthmaxver&method=Login&account=$username&passwd=$password&session=SurveillanceStation&format=\"sid\"";
      }
      else
      {
      $url = "http://$serveraddr:$serverport/webapi/$apiauthpath?api=$apiauth&version=$apiauthmaxver&method=Login&account=$username&passwd=$password&format=\"sid\""; 
      }

  $logstr = "Call-Out now: $url";
  &printlog($hash,$logstr,"4");       
  
  $param = {
               url      => $url,
               timeout  => $httptimeout,
               hash     => $hash,
               method   => "GET",
               header   => "Accept: application/json",
               callback => \&getcamid_nonbl
           };
   
   # login wird ausgeführt, $sid ermittelt und mit Routine "getcamid_nonbl" verarbeitet
   HttpUtils_NonblockingGet ($param);
}  
  
  
  
###############################################################################  
####      Rückkehr aus Funktion login und $sid ermitteln,  
####      nach erfolgreicher Verarbeitung wird Kamera-ID ermittelt 
  
sub getcamid_nonbl ($) {  
  
   my ($param, $err, $myjson) = @_;
   my $hash                            = $param->{hash};
   my $name                            = $hash->{NAME};
   my $serveraddr                      = $hash->{SERVERADDR};
   my $serverport                      = $hash->{SERVERPORT};
   my $apicam                          = $hash->{HELPER}{APICAM};
   my $apicampath                      = $hash->{HELPER}{APICAMPATH};
   my $apicammaxver                    = $hash->{HELPER}{APICAMMAXVER};
   my ($success, $username)            = getcredentials($hash,0);   
   my $url;
   my $data;
   my $logstr;
   my $sid;
   my $error;
   my $errorcode;
   my $httptimeout;  
  
   # Verarbeitung der asynchronen Rückkehrdaten aus sub "login_nonbl"
   if ($err ne "")                                                                # wenn ein Fehler bei der HTTP Abfrage aufgetreten ist
   {
        $logstr = "error while requesting ".$param->{url}." - $err";
        &printlog($hash,$logstr,"1");		                                                       
        $logstr = "--- End Function serverlogin nonblocking with error ---";
        &printlog($hash,$logstr,"4");
        
        readingsSingleUpdate($hash, "Error", $err, 1);                               
        
        # ausgeführte Funktion ist abgebrochen, Freigabe Funktionstoken
        $hash->{HELPER}{ACTIVE} = "off"; 
   
        if ($attr{$name}{debugactivetoken}) {
            $logstr = "Active-Token deleted by OPMODE: $hash->{OPMODE}" ;
            &printlog($hash,$logstr,"3");
        }
        
        return;
   }
   elsif ($myjson ne "")                                                          # wenn die Abfrage erfolgreich war ($data enthält die Ergebnisdaten des HTTP Aufrufes)
   {          
        # Evaluiere ob Daten im JSON-Format empfangen wurden
        ($hash, $success) = &evaljson($hash,$myjson,$param->{url});
        
        unless ($success) {
            $logstr = "Data returned: ".$myjson; &printlog($hash,$logstr,"4"); 
            $hash->{HELPER}{ACTIVE} = "off";
            
            if ($attr{$name}{debugactivetoken}) {
                $logstr = "Active-Token deleted by OPMODE: $hash->{OPMODE}" ;
                &printlog($hash,$logstr,"3");
            }
            return;
        }
        
        $data = decode_json($myjson);
   
        $success = $data->{'success'};
        
        # login war erfolgreich
        if ($success) 
        {
             # Logausgabe decodierte JSON Daten
             $logstr = "JSON returned: ". Dumper $data;                                                         
             &printlog($hash,$logstr,"4");
             
             $sid = $data->{'data'}->{'sid'};
             
             # Session ID in hash eintragen
             $hash->{HELPER}{SID} = $sid;
       
             # Setreading 
             readingsBeginUpdate($hash);
             readingsBulkUpdate($hash,"Errorcode","none");
             readingsBulkUpdate($hash,"Error","none");
             readingsEndUpdate($hash, 1);
       
             # Logausgabe
             $logstr = "Login of User $username successful - SID: $sid";
             &printlog($hash,$logstr,"4");
             $logstr = "--- End Function serverlogin nonblocking ---";
             &printlog($hash,$logstr,"4");    
       } 
       else 
       {
             # Errorcode aus JSON ermitteln
             $errorcode = $data->{'error'}->{'code'};
       
             # Fehlertext zum Errorcode ermitteln
             $error = &experrorauth($hash,$errorcode);

             # Setreading 
             readingsBeginUpdate($hash);
             readingsBulkUpdate($hash,"Errorcode",$errorcode);
             readingsBulkUpdate($hash,"Error",$error);
             readingsEndUpdate($hash, 1);
       
             # Logausgabe
             $logstr = "ERROR - Login of User $username unsuccessful. Errorcode: $errorcode - $error";
             &printlog($hash,$logstr,"1");
             
             $logstr = "--- End Function serverlogin nonblocking with error ---";
             &printlog($hash,$logstr,"4"); 
             
             # ausgeführte Funktion nicht erfolgreich, Freigabe Funktionstoken
             $hash->{HELPER}{ACTIVE} = "off"; 
             
             if ($attr{$name}{debugactivetoken}) {
                 $logstr = "Active-Token deleted by OPMODE: $hash->{OPMODE}" ;
                 &printlog($hash,$logstr,"3");
             }
             
             return;
       }
   }
  
  
  # die Kamera-Id wird aus dem Kameranamen (Surveillance Station) ermittelt und mit Routine "camop_nonbl" verarbeitet

  $logstr = "--- Begin Function getcamid nonblocking ---";
  &printlog($hash,$logstr,"4");
  
  $httptimeout = $attr{$name}{httptimeout} ? $attr{$name}{httptimeout} : "4";

  $logstr = "HTTP-Call will be done with httptimeout-Value: $httptimeout s";
  &printlog($hash,$logstr,"5");  
  
  # einlesen aller Kameras - Auswertung in Rückkehrfunktion "camop_nonbl"
  $url = "http://$serveraddr:$serverport/webapi/$apicampath?api=$apicam&version=$apicammaxver&method=List&basic=true&streamInfo=true&camStm=true&_sid=\"$sid\"";

  $logstr = "Call-Out now: $url";
  &printlog($hash,$logstr,"4");             
  
  $param = {
               url      => $url,
               timeout  => $httptimeout,
               hash     => $hash,
               method   => "GET",
               header   => "Accept: application/json",
               callback => \&camop_nonbl
           };
   
  HttpUtils_NonblockingGet ($param);
  
} 



#############################################################################################
####      Rückkehr aus Funktion Kamera-ID ermitteln (getcamid_nonbl),  
####      nach erfolgreicher Verarbeitung wird Kameraoperation entspr. "OpMode" ausgeführt
  
sub camop_nonbl ($) {  
   my ($param, $err, $myjson) = @_;
   my $hash              = $param->{hash};
   my $name              = $hash->{NAME};
   my $serveraddr        = $hash->{SERVERADDR};
   my $serverport        = $hash->{SERVERPORT};
   my $camname           = $hash->{CAMNAME};
   my $apicam            = $hash->{HELPER}{APICAM};
   my $apicampath        = $hash->{HELPER}{APICAMPATH};
   my $apicammaxver      = $hash->{HELPER}{APICAMMAXVER};
   my $apiextrec         = $hash->{HELPER}{APIEXTREC};
   my $apiextrecpath     = $hash->{HELPER}{APIEXTRECPATH};
   my $apiextrecmaxver   = $hash->{HELPER}{APIEXTRECMAXVER};
   my $apiextevt         = $hash->{HELPER}{APIEXTEVT};
   my $apiextevtpath     = $hash->{HELPER}{APIEXTEVTPATH};
   my $apiextevtmaxver   = $hash->{HELPER}{APIEXTEVTMAXVER};
   my $apitakesnap       = $hash->{HELPER}{APISNAPSHOT};
   my $apitakesnappath   = $hash->{HELPER}{APITAKESNAPPATH};
   my $apitakesnapmaxver = $hash->{HELPER}{APITAKESNAPMAXVER};
   my $apiptz            = $hash->{HELPER}{APIPTZ};
   my $apiptzpath        = $hash->{HELPER}{APIPTZPATH};
   my $apiptzmaxver      = $hash->{HELPER}{APIPTZMAXVER};
   my $apisvsinfo        = $hash->{HELPER}{APISVSINFO};
   my $apisvsinfopath    = $hash->{HELPER}{APISVSINFOPATH};
   my $apisvsinfomaxver  = $hash->{HELPER}{APISVSINFOMAXVER};
   my $apicamevent       = $hash->{HELPER}{APICAMEVENT};
   my $apicameventpath   = $hash->{HELPER}{APICAMEVENTPATH};
   my $apicameventmaxver = $hash->{HELPER}{APICAMEVENTMAXVER};
   my $apievent          = $hash->{HELPER}{APIEVENT};
   my $apieventpath      = $hash->{HELPER}{APIEVENTPATH};
   my $apieventmaxver    = $hash->{HELPER}{APIEVENTMAXVER};
   my $apivideostm       = $hash->{HELPER}{APIVIDEOSTM};
   my $apivideostmpath   = $hash->{HELPER}{APIVIDEOSTMPATH};
   my $apivideostmmaxver = $hash->{HELPER}{APIVIDEOSTMMAXVER};
   my $sid               = $hash->{HELPER}{SID};
   my $OpMode            = $hash->{OPMODE};
   my ($livestream,$winname,$attr,$room);
   my $url;
   my $camid;
   my $snapid;
   my $data;
   my $logstr;
   my $success;
   my $error;
   my $errorcode;
   my $camcount;
   my $i;
   my %allcams;
   my $n;
   my $id;
   my $httptimeout;
   my $expmode;
   my $motdetsc;
  
   # Verarbeitung der asynchronen Rückkehrdaten aus sub "getcamid_nonbl"
   if ($err ne "")                                                                         # wenn ein Fehler bei der HTTP Abfrage aufgetreten ist
   {
        $logstr = "error while requesting ".$param->{url}." - $err";
        &printlog($hash,$logstr,"1");		                                           # Eintrag fürs Log
        $logstr = "--- End Function getcamid nonblocking with error ---";
        &printlog($hash,$logstr,"4");
        
        readingsSingleUpdate($hash, "Error", $err, 1);                                     # Readings erzeugen

        return (logout_nonbl($hash));
   }
   elsif ($myjson ne "")                                                                   # wenn die Abfrage erfolgreich war ($data enthält die Ergebnisdaten des HTTP Aufrufes)
   {                             
        
        # Evaluiere ob Daten im JSON-Format empfangen wurden, Achtung: sehr viele Daten mit verbose=5
        ($hash, $success) = &evaljson($hash,$myjson,$param->{url});
        
        unless ($success) {
            $logstr = "Data returned: ".$myjson; &printlog($hash,$logstr,"4"); 
            return (logout_nonbl($hash));
        }
        
        $data = decode_json($myjson);
   
        $success = $data->{'success'};
                
        if ($success)                                                                       # die Liste aller Kameras konnte ausgelesen werden, Anzahl der definierten Kameras ist in Var "total"
        {
             # lesbare Ausgabe der decodierten JSON-Daten
             $logstr = "JSON returned: ". Dumper $data;                                     # Achtung: SEHR viele Daten !                                              
             &printlog($hash,$logstr,"5");
                    
             $camcount = $data->{'data'}->{'total'};
             $i = 0;
         
             # Namen aller installierten Kameras mit Id's in Assoziatives Array einlesen
             %allcams = ();
             while ($i < $camcount) 
                 {
                 $n = $data->{'data'}->{'cameras'}->[$i]->{'name'};
                 $id = $data->{'data'}->{'cameras'}->[$i]->{'id'};
                 $allcams{"$n"} = "$id";
                 $i += 1;
                 }
             
             # Ist der gesuchte Kameraname im Hash enhalten (in SS eingerichtet ?)
             if (exists($allcams{$camname})) 
             {
                 $camid = $allcams{$camname};
                 # in hash eintragen
                 $hash->{CAMID} = $camid;
                 
                 # Logausgabe
                 $logstr = "Detection Camid successful - $camname ID: $camid";
                 &printlog($hash,$logstr,"4");
                 $logstr = "--- End Function getcamid nonblocking ---";
                 &printlog($hash,$logstr,"4");  
             } 
             else 
             {
                 # Kameraname nicht gefunden, id = ""
                 
                 # Setreading 
                 readingsBeginUpdate($hash);
                 readingsBulkUpdate($hash,"Errorcode","none");
                 readingsBulkUpdate($hash,"Error","Camera(ID) not found in Surveillance Station");
                 readingsEndUpdate($hash, 1);
                                  
                 # Logausgabe
                 $logstr = "ERROR - Cameraname $camname wasn't found in Surveillance Station. Check Userrights, Cameraname and Spelling.";
                 &printlog($hash,$logstr,"1");
                 $logstr = "--- End Function getcamid nonblocking with error ---";
                 &printlog($hash,$logstr,"4");
                        
                 return (logout_nonbl($hash));
              }
       }
       else 
       {
            # Errorcode aus JSON ermitteln
            $errorcode = $data->{'error'}->{'code'};

            # Fehlertext zum Errorcode ermitteln
            $error = &experror($hash,$errorcode);
       
            # Setreading 
            readingsBeginUpdate($hash);
            readingsBulkUpdate($hash,"Errorcode",$errorcode);
            readingsBulkUpdate($hash,"Error",$error);
            readingsEndUpdate($hash, 1);

            $logstr = "ERROR - ID of Camera $camname couldn't be selected. Errorcode: $errorcode - $error";
            &printlog($hash,$logstr,"1");
            $logstr = "--- End Function getcamid nonblocking with error ---";
            &printlog($hash,$logstr,"4");
                        
            return (logout_nonbl($hash));
       }
       
   $logstr = "--- Begin Function cam: $OpMode nonblocking ---";
   &printlog($hash,$logstr,"4");

   $httptimeout = $attr{$name}{httptimeout} ? $attr{$name}{httptimeout} : "4";
   
   $logstr = "HTTP-Call will be done with httptimeout-Value: $httptimeout s";
   &printlog($hash,$logstr,"5");
   
   if ($OpMode eq "Start") 
   {
      $url = "http://$serveraddr:$serverport/webapi/$apiextrecpath?api=$apiextrec&method=Record&version=$apiextrecmaxver&cameraId=$camid&action=start&_sid=\"$sid\""; 
   } 
   elsif ($OpMode eq "Stop")
   {
      $url = "http://$serveraddr:$serverport/webapi/$apiextrecpath?api=$apiextrec&method=Record&version=$apiextrecmaxver&cameraId=$camid&action=stop&_sid=\"$sid\"";
   }
   elsif ($OpMode eq "Snap")
   {
      # ein Schnappschuß wird ausgelöst und in SS gespeichert, Rückkehr wird mit "camret_nonbl" verarbeitet
      $url = "http://$serveraddr:$serverport/webapi/$apitakesnappath?api=\"$apitakesnap\"&dsId=0&method=\"TakeSnapshot\"&version=\"$apitakesnapmaxver\"&camId=$camid&blSave=true&_sid=\"$sid\"";
      readingsSingleUpdate($hash,"state", "snap", 0); 
      readingsSingleUpdate($hash, "LastSnapId", "", 1);
   }
   elsif ($OpMode eq "getsnapfilename")
   {
      # der Filename der aktuellen Schnappschuß-ID wird ermittelt
      $snapid = ReadingsVal("$name", "LastSnapId", " ");
      $url = "http://$serveraddr:$serverport/webapi/$apitakesnappath?api=\"$apitakesnap\"&method=\"List\"&version=\"$apitakesnapmaxver\"&imgSize=\"0\"&idList=\"$snapid\"&_sid=\"$sid\"";
   }
   elsif ($OpMode eq "gopreset")
   {
      # mal wieder Maxversion der API funktioniert nicht ! Ticket bei Syno
      $apiptzmaxver -= 1;
      $url = "http://$serveraddr:$serverport/webapi/$apiptzpath?api=\"$apiptz\"&version=\"$apiptzmaxver\"&method=\"GoPreset\"&presetId=\"$hash->{HELPER}{ALLPRESETS}{$hash->{HELPER}{GOPRESETNAME}}\"&cameraId=\"$camid\"&_sid=\"$sid\"";
      readingsSingleUpdate($hash,"state", "moving", 0); 
   }
   elsif ($OpMode eq "runpatrol")
   {
      # eine Überwachungstour starten
      $url = "http://$serveraddr:$serverport/webapi/$apiptzpath?api=\"$apiptz\"&version=\"$apiptzmaxver\"&method=\"RunPatrol\"&patrolId=\"$hash->{HELPER}{ALLPATROLS}{$hash->{HELPER}{GOPATROLNAME}}\"&cameraId=\"$camid\"&_sid=\"$sid\"";
      readingsSingleUpdate($hash,"state", "moving", 0);
   }
   elsif ($OpMode eq "goabsptz")
   {
      $url = "http://$serveraddr:$serverport/webapi/$apiptzpath?api=\"$apiptz\"&version=\"$apiptzmaxver\"&method=\"AbsPtz\"&cameraId=\"$camid\"&posX=\"$hash->{HELPER}{GOPTZPOSX}\"&posY=\"$hash->{HELPER}{GOPTZPOSY}\"&_sid=\"$sid\"";
      readingsSingleUpdate($hash,"state", "moving", 0); 
   }
   elsif ($OpMode eq "movestart")
   {
      $url = "http://$serveraddr:$serverport/webapi/$apiptzpath?api=\"$apiptz\"&version=\"$apiptzmaxver\"&method=\"Move\"&cameraId=\"$camid\"&direction=\"$hash->{HELPER}{GOMOVEDIR}\"&speed=\"3\"&moveType=\"Start\"&_sid=\"$sid\"";
   }
   elsif ($OpMode eq "movestop")
   {
      $url = "http://$serveraddr:$serverport/webapi/$apiptzpath?api=\"$apiptz\"&version=\"$apiptzmaxver\"&method=\"Move\"&cameraId=\"$camid\"&direction=\"$hash->{HELPER}{GOMOVEDIR}\"&moveType=\"Stop\"&_sid=\"$sid\"";
   }
   elsif ($OpMode eq "Enable")
   {
      $url = "http://$serveraddr:$serverport/webapi/$apicampath?api=$apicam&version=$apicammaxver&method=Enable&cameraIds=$camid&_sid=\"$sid\"";     
   }
   elsif ($OpMode eq "Disable")
   {
      $url = "http://$serveraddr:$serverport/webapi/$apicampath?api=$apicam&version=$apicammaxver&method=Disable&cameraIds=$camid&_sid=\"$sid\"";     
   }
   elsif ($OpMode eq "Getsvsinfo")
   {
      $url = "http://$serveraddr:$serverport/webapi/$apisvsinfopath?api=\"$apisvsinfo\"&version=\"$apisvsinfomaxver\"&method=\"GetInfo\"&_sid=\"$sid\"";   
   }
   elsif ($OpMode eq "Getcaminfo")
   {
      $url = "http://$serveraddr:$serverport/webapi/$apicampath?api=\"$apicam\"&version=\"$apicammaxver\"&method=\"GetInfo\"&cameraIds=\"$camid\"&deviceOutCap=\"true\"&streamInfo=\"true\"&ptz=\"true\"&basic=\"true\"&camAppInfo=\"true\"&optimize=\"true\"&fisheye=\"true\"&eventDetection=\"true\"&_sid=\"$sid\"";   
   }
   elsif ($OpMode eq "geteventlist")
   {
      # Abruf der Events einer Kamera
      $url = "http://$serveraddr:$serverport/webapi/$apieventpath?api=\"$apievent\"&version=\"$apieventmaxver\"&method=\"List\"&cameraIds=\"$camid\"&locked=\"0\"&blIncludeSnapshot=\"false\"&reason=\"\"&limit=\"2\"&includeAllCam=\"false\"&_sid=\"$sid\"";   
   }
   elsif ($OpMode eq "Getptzlistpreset")
   {
      $url = "http://$serveraddr:$serverport/webapi/$apiptzpath?api=$apiptz&version=$apiptzmaxver&method=ListPreset&cameraId=$camid&_sid=\"$sid\"";   
   } 
   elsif ($OpMode eq "Getcapabilities")
   {
      # Capabilities einer Cam werden abgerufen
      $url = "http://$serveraddr:$serverport/webapi/$apicampath?api=$apicam&version=$apicammaxver&method=GetCapabilityByCamId&cameraId=$camid&_sid=\"$sid\"";   
   }
   elsif ($OpMode eq "Getptzlistpatrol")
   {
      # PTZ-ListPatrol werden abgerufen
      $url = "http://$serveraddr:$serverport/webapi/$apiptzpath?api=$apiptz&version=$apiptzmaxver&method=ListPatrol&cameraId=$camid&_sid=\"$sid\"";   
   }    
   elsif ($OpMode eq "ExpMode")
   {
      if ($hash->{HELPER}{EXPMODE} eq "auto") {
          $expmode = "0";
      }
      elsif ($hash->{HELPER}{EXPMODE} eq "day") {
          $expmode = "1";
      }
      elsif ($hash->{HELPER}{EXPMODE} eq "night") {
          $expmode = "2";
      }
      $url = "http://$serveraddr:$serverport/webapi/$apicampath?api=\"$apicam\"&version=\"$apicammaxver\"&method=\"SaveOptimizeParam\"&cameraIds=\"$camid\"&expMode=\"$expmode\"&camParamChkList=32&_sid=\"$sid\"";   
   }
   elsif ($OpMode eq "MotDetSc")
   {
      if ($hash->{HELPER}{MOTDETSC} eq "disable") {
          $motdetsc = "-1";
      }
      elsif ($hash->{HELPER}{MOTDETSC} eq "camera") {
          $motdetsc = "0";
      }
      elsif ($hash->{HELPER}{MOTDETSC} eq "SVS") {
          $motdetsc = "1";
      }
      
      $url = "http://$serveraddr:$serverport/webapi/$apicameventpath?api=\"$apicamevent\"&version=\"$apicameventmaxver\"&method=\"MDParamSave\"&camId=\"$camid\"&source=$motdetsc&keep=true&_sid=\"$sid\"";   
   }
   elsif ($OpMode eq "getmotionenum")
   {
      $url = "http://$serveraddr:$serverport/webapi/$apicameventpath?api=\"$apicamevent\"&version=\"$apicameventmaxver\"&method=\"MotionEnum\"&camId=\"$camid\"&_sid=\"$sid\"";   
   }
   elsif ($OpMode eq "extevent")
   {
      $url = "http://$serveraddr:$serverport/webapi/$apiextevtpath?api=$apiextevt&version=$apiextevtmaxver&method=Trigger&eventId=$hash->{HELPER}{EVENTID}&eventName=$hash->{HELPER}{EVENTID}&_sid=\"$sid\"";
   }
   elsif ($OpMode eq "runliveview")
   {
      # SID nach SID_STRM sichern und nutzen (für stopLiveview-Routine)
      $hash->{HELPER}{SID_STRM} = $sid;
      # externe URL
      $livestream = !AttrVal($name, "livestreamprefix", undef) ? "http://$serveraddr:$serverport" : AttrVal($name, "livestreamprefix", undef);
      $livestream .= "/webapi/$apivideostmpath?api=$apivideostm&version=$apivideostmmaxver&method=Stream&cameraId=$camid&format=mjpeg&_sid=\"$sid\"";
      # interne URL
      $url = "http://$serveraddr:$serverport/webapi/$apivideostmpath?api=$apivideostm&version=$apivideostmmaxver&method=Stream&cameraId=$camid&format=mjpeg&_sid=\"$sid\""; 
      
      # Liveview-Link in Hash speichern -> Anzeige über SSCam_liveview, in Reading setzen für Linkversand
      $hash->{HELPER}{LINK} = $url;
      readingsSingleUpdate($hash,"LiveStreamUrl", $livestream, 1);
         
      $logstr = "Set Livestream-URL: $url";
      &printlog($hash,$logstr,"4");
      
      # livestream sofort in neuem Browsertab öffnen
      if ($hash->{HELPER}{OPENWINDOW}) {
          $winname = $name."_view";
          $attr = AttrVal($name, "htmlattr", "");
          # öffnen streamwindow für die Instanz die "VIEWOPENROOM" oder Attr "room" aktuell geöffnet hat
          
          if ($hash->{HELPER}{VIEWOPENROOM}) {
              $room = $hash->{HELPER}{VIEWOPENROOM};
              map {FW_directNotify("FILTER=room=$room", "#FHEMWEB:$_", "window.open ('$url','$winname','$attr')", "")} devspec2array("WEB.*");
          } else {
              map {FW_directNotify("#FHEMWEB:$_", "window.open ('$url','$winname','$attr')", "")} devspec2array("WEB.*");
          }
      }
 
      $logstr = "--- End Function cam: $OpMode nonblocking ---";
      &printlog($hash,$logstr,"4");
      
      if (ReadingsVal("$name", "Record", "") eq "Start") {
                    readingsSingleUpdate( $hash,"state", "on", 1); 
                    }
                    else
                    {
                    readingsSingleUpdate($hash,"state", "off", 1); 
                    }
      
      $hash->{HELPER}{ACTIVE} = "off";   
      return;
   }
   
   $logstr = "Call-Out now: $url";
   &printlog($hash,$logstr,"4");
   
   $param = {
                url      => $url,
                timeout  => $httptimeout,
                hash     => $hash,
                method   => "GET",
                header   => "Accept: application/json",
                callback => \&camret_nonbl
            };
   
   HttpUtils_NonblockingGet ($param);   

   } 
} 
  
  
###################################################################################  
####      Rückkehr aus Funktion camop_nonbl,  
####      Check ob Kameraoperation erfolgreich wie in "OpMOde" definiert 
####      danach Verarbeitung Nutzdaten und weiter zum Logout
  
sub camret_nonbl ($) {  
   my ($param, $err, $myjson) = @_;
   my $hash             = $param->{hash};
   my $name             = $hash->{NAME};
   my $serveraddr       = $hash->{SERVERADDR};
   my $serverport       = $hash->{SERVERPORT};
   my $camname          = $hash->{CAMNAME};
   my $apiauth          = $hash->{HELPER}{APIAUTH};
   my $apiauthpath      = $hash->{HELPER}{APIAUTHPATH};
   my $apiauthmaxver    = $hash->{HELPER}{APIAUTHMAXVER};
   my $sid              = $hash->{HELPER}{SID};
   my $OpMode           = $hash->{OPMODE};
   my $rectime;
   my $url;
   my $data;
   my $logstr;
   my $success;
   my ($error,$errorcode);
   my $snapid;
   my $camLiveMode;
   my $update_time;
   my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst);
   my $deviceType;
   my $camStatus;
   my ($presetcnt,$cnt,$presid,$presname,@preskeys,$presetlist);
   my ($patrolcnt,$patrolid,$patrolname,@patrolkeys,$patrollist);
   my ($recStatus,$exposuremode,$exposurecontrol);
   my $userPriv;
   my $verbose;
   my $httptimeout;
   my $motdetsc;
   
   # Die Aufnahmezeit setzen
   # wird "set <name> on [rectime]" verwendet -> dann [rectime] nutzen, 
   # sonst Attribut "rectime" wenn es gesetzt ist, falls nicht -> "RECTIME_DEF"
   if (defined($hash->{HELPER}{RECTIME_TEMP})) {
       $rectime = delete $hash->{HELPER}{RECTIME_TEMP};
       }
       else
       {
       if (defined($attr{$name}{rectime}) && AttrVal($name,"rectime", undef) == 0) {
           $rectime = 0;
           }
           else
           {
           $rectime = AttrVal($name, "rectime", undef) ? AttrVal($name, "rectime", undef) : $hash->{HELPER}{RECTIME_DEF};
           }
       }
   
   if ($err ne "")                                                                                     # wenn ein Fehler bei der HTTP Abfrage aufgetreten ist
   {
        $logstr = "error while requesting ".$param->{url}." - $err";
        &printlog($hash,$logstr,"1");		                                                      # Eintrag fürs Log
        $logstr = "--- End Function cam: $OpMode nonblocking with error ---";
        &printlog($hash,$logstr,"4");
        
        readingsSingleUpdate($hash, "Error", $err, 1);                                     	       # Readings erzeugen

        return (logout_nonbl($hash));
   }
   elsif ($myjson ne "")                                                                                # wenn die Abfrage erfolgreich war ($data enthält die Ergebnisdaten des HTTP Aufrufes)
   {    
        # Evaluiere ob Daten im JSON-Format empfangen wurden
        ($hash, $success) = &evaljson($hash,$myjson,$param->{url});
        
        unless ($success) {
            $logstr = "Data returned: ".$myjson; &printlog($hash,$logstr,"4"); 
            return (logout_nonbl($hash));
         }
        
        $data = decode_json($myjson);
   
        $success = $data->{'success'};

        if ($success) 
        {       
            # Kameraoperation entsprechend "OpMode" war erfolgreich
            
            # Logausgabe decodierte JSON Daten
            $logstr = "JSON returned: ". Dumper $data;                                                        
            &printlog($hash,$logstr,"4");
                
            if ($OpMode eq "Start") 
            {                             
                # Setreading 
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Record","Start");
                readingsBulkUpdate($hash,"state","on");
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                                
                # Logausgabe
                $logstr = $rectime != "0" ? "Camera $camname Recording with Recordtime $rectime"."s started" : "Camera $camname endless Recording started  - stop it by stop-command !";
                &printlog($hash,$logstr,"3");  
                $logstr = "--- End Function cam: $OpMode nonblocking ---";
                &printlog($hash,$logstr,"4");                
       
                # Logausgabe
                $logstr = "Time for Recording is set to: $rectime";
                &printlog($hash,$logstr,"4");
                
                if ($rectime != 0) {
                    # Stop der Aufnahme nach Ablauf $rectime, wenn rectime = 0 -> endlose Aufnahme
                    InternalTimer(gettimeofday()+$rectime, "camstoprec", $hash, 0);
                    }              

            }
            elsif ($OpMode eq "Stop") 
            {                
                # Setreading 
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Record","Stop");
                readingsBulkUpdate($hash,"state","off");
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
       
                # Logausgabe
                $logstr = "Camera $camname Recording stopped";
                &printlog($hash,$logstr,"3");
                $logstr = "--- End Function cam: $OpMode nonblocking ---";
                &printlog($hash,$logstr,"4");
            }
            elsif ($OpMode eq "ExpMode") 
            {              
                # Setreading 
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
       
                # Logausgabe
                $logstr = "Camera $camname exposure mode was set to \"$hash->{HELPER}{EXPMODE}\"";
                &printlog($hash,$logstr,"3");
                $logstr = "--- End Function cam: $OpMode nonblocking ---";
                &printlog($hash,$logstr,"4");
            }
            elsif ($OpMode eq "MotDetSc") 
            {              
                # Setreading 
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
       
                # Logausgabe
                $logstr = "Camera $camname motion detection source was set to \"$hash->{HELPER}{MOTDETSC}\"";
                &printlog($hash,$logstr,"3");
                $logstr = "--- End Function cam: $OpMode nonblocking ---";
                &printlog($hash,$logstr,"4");
            }
            elsif ($OpMode eq "Snap") 
            {
                # ein Schnapschuß wurde aufgenommen
                # falls Aufnahme noch läuft -> state = on setzen
                if (ReadingsVal("$name", "Record", "Stop") eq "Start") {
                    readingsSingleUpdate( $hash,"state", "on", 0); 
                    }
                    else
                    {
                    readingsSingleUpdate($hash,"state", "off", 0); 
                    }
                
                $snapid = $data->{data}{'id'};
                
                # Setreading 
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsBulkUpdate($hash,"LastSnapId",$snapid);
                readingsEndUpdate($hash, 1);
                                
                # Logausgabe
                $logstr = "Snapshot of Camera $camname has been done successfully";
                &printlog($hash,$logstr,"3");
                $logstr = "--- End Function cam: $OpMode nonblocking ---";
                &printlog($hash,$logstr,"4");
            }
            elsif ($OpMode eq "getsnapfilename") 
            {
                # den Filenamen eines Schnapschusses ermitteln
                $snapid = ReadingsVal("$name", "LastSnapId", " ");
                           
                # Setreading 
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsBulkUpdate($hash,"LastSnapFilename", $data->{'data'}{'data'}[0]{'fileName'});
                readingsEndUpdate($hash, 1);
                                
                # Logausgabe
                 $logstr = "Filename of Snap-ID $snapid is \"$data->{'data'}{'data'}[0]{'fileName'}\" ";
                &printlog($hash,$logstr,"4");
                $logstr = "--- End Function cam: $OpMode nonblocking ---";
                &printlog($hash,$logstr,"4");
            }
            elsif ($OpMode eq "gopreset") 
            {
                # eine Presetposition wurde angefahren
                # falls Aufnahme noch läuft -> state = on setzen
                if (ReadingsVal("$name", "Record", "Stop") eq "Start") {
                    readingsSingleUpdate($hash,"state", "on", 0); 
                    }
                    else
                    {
                    readingsSingleUpdate($hash,"state", "off", 0); 
                    }
                
                # Setreading 
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                                
                # Logausgabe
                $logstr = "Camera $camname has been moved to position \"$hash->{HELPER}{GOPRESETNAME}\"";
                &printlog($hash,$logstr,"3");
                $logstr = "--- End Function cam: $OpMode nonblocking ---";
                &printlog($hash,$logstr,"4");
            }
            elsif ($OpMode eq "runpatrol") 
            {
                # eine Tour wurde gestartet
                # falls Aufnahme noch läuft -> state = on setzen
                if (ReadingsVal("$name", "Record", "Stop") eq "Start") {
                    readingsSingleUpdate($hash,"state", "on", 0); 
                    }
                    else
                    {
                    readingsSingleUpdate($hash,"state", "off", 0); 
                    }
                
                # Setreading 
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                                
                # Logausgabe
                $logstr = "Patrol \"$hash->{HELPER}{GOPATROLNAME}\" of camera $camname has been started successfully";
                &printlog($hash,$logstr,"3");
                $logstr = "--- End Function cam: $OpMode nonblocking ---";
                &printlog($hash,$logstr,"4");
            }
            elsif ($OpMode eq "goabsptz") 
            {
                # eine absolute PTZ-Position wurde angefahren
                # falls Aufnahme noch läuft -> state = on setzen
                if (ReadingsVal("$name", "Record", "Stop") eq "Start") {
                    readingsSingleUpdate($hash,"state", "on", 0); 
                    }
                    else
                    {
                    readingsSingleUpdate($hash,"state", "off", 0); 
                    }
                
                # Setreading 
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                                
                # Logausgabe
                $logstr = "Camera $camname has been moved to absolute position \"posX=$hash->{HELPER}{GOPTZPOSX}\" and \"posY=$hash->{HELPER}{GOPTZPOSY}\"";
                &printlog($hash,$logstr,"3");
                $logstr = "--- End Function cam: $OpMode nonblocking ---";
                &printlog($hash,$logstr,"4");
            }
            elsif ($OpMode eq "movestart") 
            {
                # ein "Move" in eine bestimmte Richtung wird durchgeführt                 
                # Setreading 
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"state","moving");
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                                
                # Logausgabe
                $logstr = "Camera $camname started move to direction \"$hash->{HELPER}{GOMOVEDIR}\" with duration of $hash->{HELPER}{GOMOVETIME} s";
                &printlog($hash,$logstr,"3");
                $logstr = "--- End Function cam: $OpMode nonblocking ---";
                &printlog($hash,$logstr,"4");
                
                 InternalTimer(gettimeofday()+($hash->{HELPER}{GOMOVETIME}), "movestop", $hash, 0);
            }
            elsif ($OpMode eq "movestop") 
            {
                # ein "Move" in eine bestimmte Richtung wurde durchgeführt 
                # falls Aufnahme noch läuft -> state = on setzen
                
                if (ReadingsVal("$name", "Record", "Stop") eq "Start") {
                    readingsSingleUpdate($hash,"state", "on", 0); 
                    }
                    else
                    {
                    readingsSingleUpdate($hash,"state", "off", 0); 
                    }
                
                # Setreading 
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                                
                # Logausgabe
                $logstr = "Camera $camname stopped move to direction \"$hash->{HELPER}{GOMOVEDIR}\"";
                &printlog($hash,$logstr,"3");
                $logstr = "--- End Function cam: $OpMode nonblocking ---";
                &printlog($hash,$logstr,"4");
        
            }
            elsif ($OpMode eq "Enable") 
            {
                # Kamera wurde aktiviert, sonst kann nichts laufen -> "off"                
                # Setreading 
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Availability","enabled");
                readingsBulkUpdate($hash,"state","off");
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                   
                # Logausgabe
                $logstr = "Camera $camname has been enabled successfully";
                &printlog($hash,$logstr,"3");
                $logstr = "--- End Function cam: $OpMode nonblocking ---";
                &printlog($hash,$logstr,"4");
            }
            elsif ($OpMode eq "Disable") 
            {
                # Kamera wurde deaktiviert
                # Setreading 
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Availability","disabled");
                readingsBulkUpdate($hash,"state","disabled");
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                   
                # Logausgabe
                $logstr = "Camera $camname has been disabled successfully";
                &printlog($hash,$logstr,"3");
                $logstr = "--- End Function cam: $OpMode nonblocking ---";
                &printlog($hash,$logstr,"4");
            }
            elsif ($OpMode eq "Getsvsinfo") 
            {
                # Parse SVS-Infos
                $userPriv = $data->{'data'}{'userPriv'};
                if (defined($userPriv)) {
                    if ($userPriv eq "0") {
                        $userPriv = "No Accss";
                        }
                        elsif ($userPriv eq "1") {
                        $userPriv = "Admin";
                        }
                        elsif ($userPriv eq "2") {
                        $userPriv = "Manager";
                        }
                        elsif ($userPriv eq "4") {
                        $userPriv = "Viewer";
                        }
                 }                    
                # "my" nicht am Anfang deklarieren, sonst wird Hash %version wieder geleert !
                my %version = (
                            MAJOR => $data->{'data'}{'version'}{'major'},
                            MINOR => $data->{'data'}{'version'}{'minor'},
                            BUILD => $data->{'data'}{'version'}{'build'}
                            );
                
                if (!exists($data->{'data'}{'customizedPortHttp'})) {
                    delete $defs{$name}{READINGS}{SVScustomPortHttp};
                    }             
               
                if (!exists($data->{'data'}{'customizedPortHttps'})) {
                    delete $defs{$name}{READINGS}{SVScustomPortHttps};
                    }
                                
                # Setreading 
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"SVScustomPortHttp",$data->{'data'}{'customizedPortHttp'});
                readingsBulkUpdate($hash,"SVScustomPortHttps",$data->{'data'}{'customizedPortHttps'});
                readingsBulkUpdate($hash,"SVSlicenseNumber",$data->{'data'}{'liscenseNumber'});
                readingsBulkUpdate($hash,"SVSuserPriv",$userPriv);
                readingsBulkUpdate($hash,"SVSversion",$data->{'data'}{'version'}{'major'}.".".$data->{'data'}{'version'}{'minor'}."-".$data->{'data'}{'version'}{'build'});
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                
                # Werte in $hash zur späteren Auswertung einfügen 
                $hash->{HELPER}{SVSVERSION} = \%version;
                     
                # Logausgabe
                $logstr = "Informations related to Surveillance Station retrieved successfully";
                &printlog($hash,$logstr,"3");
                $logstr = "--- End Function $OpMode nonblocking ---";
                &printlog($hash,$logstr,"4");
            }
            elsif ($OpMode eq "Getcaminfo") 
            {
                # Parse Caminfos
                $camLiveMode = $data->{'data'}->{'cameras'}->[0]->{'camLiveMode'};
                if ($camLiveMode eq "0") {$camLiveMode = "Liveview from DS";}elsif ($camLiveMode eq "1") {$camLiveMode = "Liveview from Camera";}
                
                # $update_time = $data->{'data'}->{'cameras'}->[0]->{'update_time'};
                ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime;
                $update_time = sprintf "%02d.%02d.%04d / %02d:%02d:%02d" , $mday , $mon+=1 ,$year+=1900 , $hour , $min , $sec ;
                
                $deviceType = $data->{'data'}->{'cameras'}->[0]->{'deviceType'};
                if ($deviceType eq "1") {
                    $deviceType = "Camera";
                    }
                    elsif ($deviceType eq "2") {
                    $deviceType = "Video_Server";
                    }
                    elsif ($deviceType eq "4") {
                    $deviceType = "PTZ";
                    }
                    elsif ($deviceType eq "8") {
                    $deviceType = "Fisheye"; 
                    }
                
                $camStatus = $data->{'data'}->{'cameras'}->[0]->{'camStatus'};
                if ($camStatus eq "1") {
                    $camStatus = "enabled";
                    
                    # falls Aufnahme noch läuft -> STATE = on setzen
                    if (ReadingsVal("$name", "Record", "Stop") eq "Start") {
                        readingsSingleUpdate($hash,"state", "on", 0); 
                        }
                        else
                        {
                        readingsSingleUpdate($hash,"state", "off", 0); 
                        }
                    }
                    elsif ($camStatus eq "3") {
                    $camStatus = "disconnected";
                    readingsSingleUpdate($hash,"state", "disconnected", 0);
                    }
                    elsif ($camStatus eq "7") {
                    $camStatus = "disabled";
                    readingsSingleUpdate($hash,"state", "disabled ", 0); 
                    }
                    else {
                    $camStatus = "other";
                    }
               
                $recStatus = $data->{'data'}->{'cameras'}->[0]->{'recStatus'};
                if ($recStatus ne "0") {
                    $recStatus = "Start";
                    }
                    else {
                    $recStatus = "Stop";
                    }
                
                $exposuremode = $data->{'data'}->{'cameras'}->[0]->{'exposure_mode'};
                if ($exposuremode == 0) {
                    $exposuremode = "Auto";
                    }
                    elsif ($exposuremode == 1) {
                    $exposuremode = "Day";
                    }
                    elsif ($exposuremode == 2) {
                    $exposuremode = "Night";
                    }
                    elsif ($exposuremode == 3) {
                    $exposuremode = "Schedule";
                    }
                    elsif ($exposuremode == 4) {
                    $exposuremode = "Unknown";
                    }
                    
                $exposurecontrol = $data->{'data'}->{'cameras'}->[0]->{'exposure_control'};
                if ($exposurecontrol == 0) {
                    $exposurecontrol = "Auto";
                    }
                    elsif ($exposurecontrol == 1) {
                    $exposurecontrol = "50HZ";
                    }
                    elsif ($exposurecontrol == 2) {
                    $exposurecontrol = "60HZ";
                    }
                    elsif ($exposurecontrol == 3) {
                    $exposurecontrol = "Hold";
                    }
                    elsif ($exposurecontrol == 4) {
                    $exposurecontrol = "Outdoor";
                    }
                    elsif ($exposurecontrol == 5) {
                    $exposurecontrol = "None";
                    }
                    elsif ($exposurecontrol == 6) {
                    $exposurecontrol = "Unknown";
                    }
                    
                # Setreading 
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"CamLiveMode",$camLiveMode);
                readingsBulkUpdate($hash,"CamExposureMode",$exposuremode);
                readingsBulkUpdate($hash,"CamExposureControl",$exposurecontrol);
                readingsBulkUpdate($hash,"CamModel",$data->{'data'}->{'cameras'}->[0]->{'detailInfo'}{'camModel'});
                readingsBulkUpdate($hash,"CamRecShare",$data->{'data'}->{'cameras'}->[0]->{'camRecShare'});
                readingsBulkUpdate($hash,"CamRecVolume",$data->{'data'}->{'cameras'}->[0]->{'camRecVolume'});
                readingsBulkUpdate($hash,"CamIP",$data->{'data'}->{'cameras'}->[0]->{'host'});
                readingsBulkUpdate($hash,"CamVendor",$data->{'data'}->{'cameras'}->[0]->{'detailInfo'}{'camVendor'});
                readingsBulkUpdate($hash,"CamPreRecTime",$data->{'data'}->{'cameras'}->[0]->{'detailInfo'}{'camPreRecTime'});
                readingsBulkUpdate($hash,"CamPort",$data->{'data'}->{'cameras'}->[0]->{'port'});
                readingsBulkUpdate($hash,"CamPtSpeed",$data->{'data'}->{'cameras'}->[0]->{'ptSpeed'});
                readingsBulkUpdate($hash,"CamblPresetSpeed",$data->{'data'}->{'cameras'}->[0]->{'blPresetSpeed'});
                readingsBulkUpdate($hash,"CamVideoMirror",$data->{'data'}->{'cameras'}->[0]->{'video_mirror'});
                readingsBulkUpdate($hash,"CamVideoFlip",$data->{'data'}->{'cameras'}->[0]->{'video_flip'});
                readingsBulkUpdate($hash,"Availability",$camStatus);
                readingsBulkUpdate($hash,"DeviceType",$deviceType);
                readingsBulkUpdate($hash,"LastUpdateTime",$update_time);
                readingsBulkUpdate($hash,"Record",$recStatus);
                readingsBulkUpdate($hash,"UsedSpaceMB",$data->{'data'}->{'cameras'}->[0]->{'volume_space'});
                readingsBulkUpdate($hash,"VideoFolder",AttrVal($name, "videofolderMap", undef) ? AttrVal($name, "videofolderMap", undef) : $data->{'data'}->{'cameras'}->[0]->{'folder'});
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                            
                # Logausgabe
                $logstr = "Camera-Informations of $camname retrieved";
                # wenn "pollnologging" = 1 -> logging nur bei Verbose=4, sonst 3 
                if (defined($attr{$name}{pollnologging}) and $attr{$name}{pollnologging} eq "1") {
                    $verbose = 4;
                    }
                    else
                    {
                    $verbose = 3;
                    }
                &printlog($hash,$logstr,$verbose);
                $logstr = "--- End Function cam: $OpMode nonblocking ---";
                &printlog($hash,$logstr,"4");
            }
            elsif ($OpMode eq "geteventlist") 
            {              
                my $eventnum    = $data->{'data'}{'total'};
                my $lastrecord  = $data->{'data'}{'events'}[0]{name};
                my ($lastrecstarttime,$lastrecstoptime);
                
                if ($eventnum > 0) {
                    $lastrecstarttime = $data->{'data'}{'events'}[0]{startTime};
                    ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($lastrecstarttime);
                    $lastrecstarttime = sprintf "%02d.%02d.%04d / %02d:%02d:%02d" , $mday , $mon+=1 ,$year+=1900 , $hour , $min , $sec ;
                
                    $lastrecstoptime = $data->{'data'}{'events'}[0]{stopTime};
                    ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($lastrecstoptime);
                    $lastrecstoptime = sprintf "%02d:%02d:%02d" , $hour , $min , $sec ;
                }
                
                # Setreading 
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"CamEventNum",$eventnum);
                readingsBulkUpdate($hash,"CamLastRec",$lastrecord);
                if ($lastrecstarttime) {readingsBulkUpdate($hash,"CamLastRecTime",$lastrecstarttime." - ". $lastrecstoptime);}                
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
       
                # Logausgabe
                $logstr = "Query event list of $camname successfully done";
                # wenn "pollnologging" = 1 -> logging nur bei Verbose=4, sonst 3 
                if (defined($attr{$name}{pollnologging}) and $attr{$name}{pollnologging} eq "1") {
                    $verbose = 4;
                    }
                    else
                    {
                    $verbose = 3;
                    }
                &printlog($hash,$logstr,$verbose);
                $logstr = "--- End Function cam: $OpMode nonblocking ---";
                &printlog($hash,$logstr,"4");
            }
            elsif ($OpMode eq "getmotionenum") 
            {              
                $motdetsc = $data->{'data'}{'MDParam'}{'source'};
                
                if ($motdetsc == -1) {
                    $motdetsc = "disabled";
                }
                elsif ($motdetsc == 0) {
                    $motdetsc = "Camera";
                }
                elsif ($motdetsc == 1) {
                    $motdetsc = "SVS";
                }
                
                # Setreading 
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"CamMotDetSc",$motdetsc);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
       
                # Logausgabe
                $logstr = "Enumerate motion detection parameters of $camname successfully done";
                # wenn "pollnologging" = 1 -> logging nur bei Verbose=4, sonst 2 
                if (defined($attr{$name}{pollnologging}) and $attr{$name}{pollnologging} eq "1") {
                    $verbose = 4;
                    }
                    else
                    {
                    $verbose = 3;
                    }
                &printlog($hash,$logstr,$verbose);
                $logstr = "--- End Function cam: $OpMode nonblocking ---";
                &printlog($hash,$logstr,"4");
            }
            elsif ($OpMode eq "Getcapabilities") 
            {
                # Parse Infos
                my $ptzfocus = $data->{'data'}{'ptzFocus'};
                if ($ptzfocus eq "0") {
                    $ptzfocus = "false";
                    }
                    elsif ($ptzfocus eq "1") {
                    $ptzfocus = "support step operation";
                    }
                    elsif ($ptzfocus eq "2") {
                    $ptzfocus = "support continuous operation";
                    }
                    
                my $ptztilt = $data->{'data'}{'ptzTilt'};
                if ($ptztilt eq "0") {
                    $ptztilt = "false";
                    }
                    elsif ($ptztilt eq "1") {
                    $ptztilt = "support step operation";
                    }
                    elsif ($ptztilt eq "2") {
                    $ptztilt = "support continuous operation";
                    }
                    
                my $ptzzoom = $data->{'data'}{'ptzZoom'};
                if ($ptzzoom eq "0") {
                    $ptzzoom = "false";
                    }
                    elsif ($ptzzoom eq "1") {
                    $ptzzoom = "support step operation";
                    }
                    elsif ($ptzzoom eq "2") {
                    $ptzzoom = "support continuous operation";
                    }
                    
                my $ptzpan = $data->{'data'}{'ptzPan'};
                if ($ptzpan eq "0") {
                    $ptzpan = "false";
                    }
                    elsif ($ptzpan eq "1") {
                    $ptzpan = "support step operation";
                    }
                    elsif ($ptzpan eq "2") {
                    $ptzpan = "support continuous operation";
                    }
                
                my $ptziris = $data->{'data'}{'ptzIris'};
                if ($ptziris eq "0") {
                    $ptziris = "false";
                    }
                    elsif ($ptziris eq "1") {
                    $ptziris = "support step operation";
                    }
                    elsif ($ptziris eq "2") {
                    $ptziris = "support continuous operation";
                    }
                
                # Setreading 
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"CapPTZAutoFocus",$data->{'data'}{'ptzAutoFocus'});
                readingsBulkUpdate($hash,"CapAudioOut",$data->{'data'}{'audioOut'});
                readingsBulkUpdate($hash,"CapChangeSpeed",$data->{'data'}{'ptzSpeed'});
                readingsBulkUpdate($hash,"CapPTZHome",$data->{'data'}{'ptzHome'});
                readingsBulkUpdate($hash,"CapPTZAbs",$data->{'data'}{'ptzAbs'});
                readingsBulkUpdate($hash,"CapPTZDirections",$data->{'data'}{'ptzDirection'});
                readingsBulkUpdate($hash,"CapPTZFocus",$ptzfocus);
                readingsBulkUpdate($hash,"CapPTZIris",$ptziris);
                readingsBulkUpdate($hash,"CapPTZPan",$ptzpan);
                readingsBulkUpdate($hash,"CapPTZTilt",$ptztilt);
                readingsBulkUpdate($hash,"CapPTZZoom",$ptzzoom);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                  
                # Logausgabe
                $logstr = "Capabilities of Camera $camname retrieved";
                # wenn "pollnologging" = 1 -> logging nur bei Verbose=4, sonst 2 
                if (defined(AttrVal($name, "pollnologging", undef)) and AttrVal($name, "pollnologging", undef) eq "1") {
                    $verbose = 4;
                    }
                    else
                    {
                    $verbose = 3;
                    }
                &printlog($hash,$logstr,$verbose);
                $logstr = "--- End Function cam: $OpMode nonblocking ---";
                &printlog($hash,$logstr,"4");
            }            
            elsif ($OpMode eq "Getptzlistpreset") 
            {
                # Parse PTZ-ListPresets
                $presetcnt = $data->{'data'}->{'total'};
                $cnt = 0;
         
                # alle Presets der Kamera mit Id's in Assoziatives Array einlesen
                
                # "my" nicht am Anfang deklarieren, sonst wird Hash %allpresets wieder geleert !
                my %allpresets;
                while ($cnt < $presetcnt) 
                    {
                    $presid = $data->{'data'}->{'presets'}->[$cnt]->{'id'};
                    $presname = $data->{'data'}->{'presets'}->[$cnt]->{'name'};
                    $allpresets{$presname} = "$presid";
                    $cnt += 1;
                    }
                    
                # Presethash in $hash einfügen
                $hash->{HELPER}{ALLPRESETS} = \%allpresets;

                @preskeys = sort(keys(%allpresets));
                $presetlist = join(",",@preskeys);

                # Setreading 
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Presets",$presetlist);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                  
                            
                # Logausgabe
                $logstr = "PTZ Presets of $camname retrieved";
                # wenn "pollnologging" = 1 -> logging nur bei Verbose=4, sonst 2 
                if (defined(AttrVal($name, "pollnologging", undef)) and AttrVal($name, "pollnologging", undef) eq "1") {
                    $verbose = 4;
                    }
                    else
                    {
                    $verbose = 3;
                    }
                &printlog($hash,$logstr,$verbose);
                $logstr = "--- End Function cam: $OpMode nonblocking ---";
                &printlog($hash,$logstr,"4");
            }
            elsif ($OpMode eq "Getptzlistpatrol") 
            {
                # Parse PTZ-ListPatrols
                $patrolcnt = $data->{'data'}->{'total'};
                $cnt = 0;
         
                # alle Patrols der Kamera mit Id's in Assoziatives Array einlesen
                # "my" nicht am Anfang deklarieren, sonst wird Hash %allpatrols wieder geleert !
                my %allpatrols = ();
                while ($cnt < $patrolcnt) 
                    {
                    $patrolid = $data->{'data'}->{'patrols'}->[$cnt]->{'id'};
                    $patrolname = $data->{'data'}->{'patrols'}->[$cnt]->{'name'};
                    $allpatrols{$patrolname} = $patrolid;
                    $cnt += 1;
                    }
                    
                # Presethash in $hash einfügen
                $hash->{HELPER}{ALLPATROLS} = \%allpatrols;

                @patrolkeys = sort(keys(%allpatrols));
                $patrollist = join(",",@patrolkeys);
                
                # print "ID von Tour1 ist : ". %allpatrols->{Tour1};
                # print "aus Hash: ".$hash->{HELPER}{ALLPRESETS}{Tour1};

                # Setreading 
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Patrols",$patrollist);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                  
                            
                # Logausgabe
                $logstr = "PTZ Patrols of $camname retrieved";
                # wenn "pollnologging" = 1 -> logging nur bei Verbose=4, sonst 2 
                if (defined(AttrVal($name, "pollnologging", undef)) and AttrVal($name, "pollnologging", undef) eq "1") {
                    $verbose = 4;
                    }
                    else
                    {
                    $verbose = 3;
                    }
                &printlog($hash,$logstr,$verbose);
                $logstr = "--- End Function cam: $OpMode nonblocking ---";
                &printlog($hash,$logstr,"4");
            }            
            
       }
       else 
       {
            # die API-Operation war fehlerhaft
            # Errorcode aus JSON ermitteln
            $errorcode = $data->{'error'}->{'code'};

            # Fehlertext zum Errorcode ermitteln
            $error = &experror($hash,$errorcode);

            # Setreading 
            readingsBeginUpdate($hash);
            readingsBulkUpdate($hash,"Errorcode",$errorcode);
            readingsBulkUpdate($hash,"Error",$error);
            readingsEndUpdate($hash, 1);
       
            # Logausgabe
            $logstr = "ERROR - Operation $OpMode of Camera $camname was not successful. Errorcode: $errorcode - $error";
            &printlog($hash,$logstr,"1");
            $logstr = "--- End Function cam: $OpMode nonblocking with error ---";
            &printlog($hash,$logstr,"4");

       }
   }
   
return (logout_nonbl($hash));
}


###################################################################################  
####      Funktion logout

sub logout_nonbl ($) {
   my ($hash) = @_;
   my $name             = $hash->{NAME};
   my $serveraddr       = $hash->{SERVERADDR};
   my $serverport       = $hash->{SERVERPORT};
   my $apiauth          = $hash->{HELPER}{APIAUTH};
   my $apiauthpath      = $hash->{HELPER}{APIAUTHPATH};
   my $apiauthmaxver    = $hash->{HELPER}{APIAUTHMAXVER};
   my $sid              = $hash->{HELPER}{SID};
   my $url;
   my $param;
   my $logstr;
   my $httptimeout;
    
    # logout wird ausgeführt, Rückkehr wird mit "logoutret_nonbl" verarbeitet

    $logstr = "--- Begin Function logout nonblocking ---";
    &printlog($hash,$logstr,"4");
    
    $httptimeout = $attr{$name}{httptimeout} ? $attr{$name}{httptimeout} : "4";
    
    $logstr = "HTTP-Call will be done with httptimeout-Value: $httptimeout s";
    &printlog($hash,$logstr,"5");    
  
    if (defined($attr{$name}{session}) and $attr{$name}{session} eq "SurveillanceStation") {
        $url = "http://$serveraddr:$serverport/webapi/$apiauthpath?api=$apiauth&version=$apiauthmaxver&method=Logout&session=SurveillanceStation&_sid=$sid";
        }
        else
        {
        $url = "http://$serveraddr:$serverport/webapi/$apiauthpath?api=$apiauth&version=$apiauthmaxver&method=Logout&_sid=$sid";
        }

    $param = {
                url      => $url,
                timeout  => $httptimeout,
                hash     => $hash,
                method   => "GET",
                header   => "Accept: application/json",
                callback => \&logoutret_nonbl
             };
   
    HttpUtils_NonblockingGet ($param);

}

###################################################################################  
####      Rückkehr aus Funktion logout_nonbl,  
####      check Funktion logout
  
sub logoutret_nonbl ($) {  
   my ($param, $err, $myjson) = @_;
   my $hash                   = $param->{hash};
   my $name                   = $hash->{NAME};
   my $sid                    = $hash->{HELPER}{SID};
   my ($success, $username)   = getcredentials($hash,0);
   my $OpMode                 = $hash->{OPMODE};
   my $data;
   my $logstr;
   my $error;
   my $errorcode;
  
   if($err ne "")                                                                                     # wenn ein Fehler bei der HTTP Abfrage aufgetreten ist
   {
        $logstr = "error while requesting ".$param->{url}." - $err";
        &printlog($hash,$logstr,"1");		                                                      # Eintrag fürs Log
        $logstr = "--- End Function logout nonblocking with error ---";
        &printlog($hash,$logstr,"4");
        
        readingsSingleUpdate($hash, "Error", $err, 1);                                     	       # Readings erzeugen 

   }
   elsif($myjson ne "")                                                                                # wenn die Abfrage erfolgreich war ($data enthält die Ergebnisdaten des HTTP Aufrufes)
   {
        $logstr = "URL-Call: ".$param->{url};                                                          
        &printlog($hash,$logstr,"4");
        
        # An dieser Stelle die Antwort parsen / verarbeiten mit $myjson 
        
        # Evaluiere ob Daten im JSON-Format empfangen wurden
        ($hash, $success) = &evaljson($hash,$myjson,$param->{url});
        
        unless ($success) {
            $logstr = "Data returned: ".$myjson; 
            &printlog($hash,$logstr,"4");
            
            $hash->{HELPER}{ACTIVE} = "off";
            
            if ($attr{$name}{debugactivetoken}) {
                $logstr = "Active-Token deleted by OPMODE: $hash->{OPMODE}" ;
                &printlog($hash,$logstr,"3");
            }
            
            return;
        }
        
        $data = decode_json($myjson);
   
        $success = $data->{'success'};

        if ($success)  
        {
             # die Logout-URL konnte erfolgreich aufgerufen werden
             # Logausgabe decodierte JSON Daten
             $logstr = "JSON returned: ". Dumper $data;                                                        
             &printlog($hash,$logstr,"4");
                        
             # Session-ID aus Helper-hash löschen
             delete $hash->{HELPER}{SID};
             
             # Logausgabe
             $logstr = "Session of User $username has ended - SID: $sid has been deleted";
             &printlog($hash,$logstr,"4");
             $logstr = "--- End Function logout nonblocking ---";
             &printlog($hash,$logstr,"4");
             
        } 
        else 
        {
             # Errorcode aus JSON ermitteln
             $errorcode = $data->{'error'}->{'code'};

             # Fehlertext zum Errorcode ermitteln
             $error = &experrorauth($hash,$errorcode);
    
             # Logausgabe
             $logstr = "ERROR - Logout of User $username was not successful. Errorcode: $errorcode - $error";
             &printlog($hash,$logstr,"1");
             $logstr = "--- End Function logout nonblocking with error ---";
             &printlog($hash,$logstr,"4");
         }
   }
   
   # ausgeführte Funktion ist erledigt (auch wenn logout nicht erfolgreich), Freigabe Funktionstoken
   $hash->{HELPER}{ACTIVE} = "off";  
   
   if ($attr{$name}{debugactivetoken}) {
       $logstr = "Active-Token deleted by OPMODE: $hash->{OPMODE}" ;
       &printlog($hash,$logstr,"3");
   }

   # nach Snap Aufnahme Filename des Snaps ermitteln
   if ($OpMode eq "Snap") {
       return (getsnapfilename($hash));
       }


return;
}

#############################################################################################################################
#########              Ende Kameraoperationen mit NonblockingGet (nicht blockierender HTTP-Call)                #############
#############################################################################################################################



#############################################################################################################################
#########                                               Hilfsroutinen                                           #############
#############################################################################################################################

###############################################################################
###   Test ob JSON-String empfangen wurde
  
sub evaljson { 
  my ($hash,$myjson,$url)= @_;
  my $success = 1;
  my $e;
  my $logstr;
  
  eval {decode_json($myjson);1;} or do 
  {
      $success = 0;
      $e = $@;
  
      # Setreading 
      readingsBeginUpdate($hash);
      readingsBulkUpdate($hash,"Errorcode","none");
      readingsBulkUpdate($hash,"Error","malformed JSON string received");
      readingsEndUpdate($hash, 1);  

  };
  
return($hash,$success);
}

##############################################################################
###  Auflösung Errorcodes bei Login / Logout

sub experrorauth {
  # Übernahmewerte sind $hash, $errorcode
  my ($hash,@errorcode) = @_;
  my $device = $hash->{NAME};
  my $errorcode = shift @errorcode;
  my %errorlist;
  my $error;
  
  # Aufbau der Errorcode-Liste (siehe Surveillance_Station_Web_API_v2.0.pdf)
  %errorlist = (
  100 => "Unknown error",
  101 => "The account parameter is not specified",
  102 => "API does not exist",
  400 => "Invalid user or password",
  401 => "Guest or disabled account",
  402 => "Permission denied - make sure user is member of Admin-group if DSM-Session is used",
  403 => "One time password not specified",
  404 => "One time password authenticate failed",
  );
  unless (exists ($errorlist {$errorcode})) {$error = "Message for Errorcode \"$errorcode\" not found. Please turn to Synology Web API-Guide."; return ($error);}

  # Fehlertext aus Hash-Tabelle oben ermitteln
  $error = $errorlist {$errorcode};
return ($error);
}

##############################################################################
###  Auflösung Errorcodes SVS API

sub experror {
  # Übernahmewerte sind $hash, $errorcode
  my ($hash,@errorcode) = @_;
  my $device = $hash->{NAME};
  my $errorcode = shift @errorcode;
  my %errorlist;
  my $error;
  
  # Aufbau der Errorcode-Liste (siehe Surveillance_Station_Web_API_v2.0.pdf)
  %errorlist = (
  100 => "Unknown error",
  101 => "Invalid parameters",
  102 => "API does not exist",
  103 => "Method does not exist",
  104 => "This API version is not supported",
  105 => "Insufficient user privilege",
  106 => "Connection time out",
  107 => "Multiple login detected",
  117 => "need manager rights in SurveillanceStation for operation",
  400 => "Execution failed",
  401 => "Parameter invalid",
  402 => "Camera disabled",
  403 => "Insufficient license",
  404 => "Codec activation failed",
  405 => "CMS server connection failed",
  407 => "CMS closed",
  410 => "Service is not enabled",
  412 => "Need to add license",
  413 => "Reach the maximum of platform",
  414 => "Some events not exist",
  415 => "message connect failed",
  417 => "Test Connection Error",
  418 => "Object is not exist",
  419 => "Visualstation name repetition",
  439 => "Too many items selected",
  502 => "Camera disconnected",
  600 => "Presetname and PresetID not found in Hash",
  );
  unless (exists ($errorlist {$errorcode})) {$error = "Message for Errorcode $errorcode not found. Please turn to Synology Web API-Guide."; return ($error);}

  # Fehlertext aus Hash-Tabelle oben ermitteln
  $error = $errorlist {$errorcode};
  return ($error);
}

############################################################################
###  Logausgabe

sub printlog {
  # Übernahmewerte ist $hash, $logstr, $verb (Verbose-Level)
  my ($hash,$logstr,$verb)= @_;
  my $name = $hash->{NAME};
  
  Log3 ($name, $verb, "$name - $logstr");
return;
}


1;

=pod
=begin html

<a name="SSCam"></a>
<h3>SSCam</h3>
<ul>
  Using this Module you are able to operate with cameras which are defined in Synology Surveillance Station (SVS). <br>
  At present the following functions are available: <br><br>
   <ul>
    <ul>
       <li>Start a Recording</li>
       <li>Stop a Recording (using command or automatically after the &lt;RecordTime&gt; period</li>
       <li>Trigger a Snapshot </li>
       <li>Deaktivate a Camera in Synology Surveillance Station</li>
       <li>Activate a Camera in Synology Surveillance Station</li>
       <li>Control of the exposure modes day, night and automatic </li>
       <li>switchover the motion detection by camera, by SVS or to deactivate  </li>
       <li>Retrieval of Camera Properties (also by Polling) as well as informations about the installed SVS-package</li>
       <li>Move to a predefined Preset-position (at PTZ-cameras) </li>
       <li>Start a predefined Patrol (at PTZ-cameras) </li>
       <li>Positioning of PTZ-cameras to absolute X/Y-coordinates  </li>
       <li>continuous moving of PTZ-camera lense   </li>
       <li>trigger of external events 1-10 (action rules in SVS)   </li>
       <li>start and stop of camera livestreams  </li><br>
    </ul>
   </ul>
   The recordings and snapshots will be stored in Synology Surveillance Station (SVS) and are managed like the other (normal) recordings / snapshots defined by Surveillance Station rules.<br>
   For example the recordings are stored for a defined time in Surveillance Station and will be deleted after that period.<br><br>
    
   If you like to discuss or help to improve this module please use FHEM-Forum with link: <br>
   <a href="http://forum.fhem.de/index.php/topic,45671.msg374390.html#msg374390">49_SSCam: Fragen, Hinweise, Neuigkeiten und mehr rund um dieses Modul</a>.<br><br>
  
<b> Prerequisites </b> <br><br>
    This module uses the CPAN-module JSON. Please consider to install this package (Debian: libjson-perl).<br>
    You don't need to install LWP anymore, because of SSCam is completely using the nonblocking functions of HttpUtils respectively HttpUtils_NonblockingGet now. <br> 
    In DSM respectively in Synology Surveillance Station an User has to be created. The login credentials are needed later when using a set-command to assign the login-data to a device. <br> 
    Further informations could be find among <a href="#Credentials">Credentials</a>.  <br><br>
    

  <a name="SCamdefine"></a>
  <b>Define</b>
  <ul>
  <br>
    <code>define &lt;name&gt; SSCAM &lt;Cameraname in SVS&gt; &lt;ServerAddr&gt; [Port]  </code><br>
    <br>
    Defines a new camera device for SSCam. At first the devices have to be set up and operable in Synology Surveillance Station 7.0 and above. <br><br>
    
    The Modul SSCam ist based on functions of Synology Surveillance Station API. <br>
    Please refer the <a href="http://global.download.synology.com/download/Document/DeveloperGuide/Surveillance_Station_Web_API_v2.0.pdf">Web API Guide</a>. <br><br>
    
    Currently only HTTP-protocol is supported to call Synology DS. <br><br>  

    The parameters are in detail:
   <br>
   <br>    
     
   <table>
    <colgroup> <col width=15%> <col width=85%> </colgroup>
    <tr><td>name:         </td><td>the name of the new device to use in FHEM</td></tr>
    <tr><td>Cameraname:   </td><td>Cameraname as defined in Synology Surveillance Station, Spaces are not allowed in Cameraname !</td></tr>
    <tr><td>ServerAddr:   </td><td>IP-address of Synology Surveillance Station Host. <b>Note:</b> avoid using hostnames because of DNS-Calls are not unblocking in FHEM </td></tr>
    <tr><td>Port:         </td><td>optional - the port of synology surveillance station, if not set the default of 5000 (HTTP only) is used</td></tr>
   </table>

    <br><br>

    <b>Example:</b>
     <pre>
      define CamCP SSCAM Carport 192.168.2.20 [5000]  
    </pre>
    
    
    When a new Camera is defined, as a start the recordingtime of 15 seconds will be assigned to the device.<br>
    Using the <a href="#SSCamattr">attribute</a> "rectime" you can adapt the recordingtime for every camera individually.<br>
    The value of "0" for rectime will lead to an endless recording which has to be stopped by a "set &lt;name&gt; off" command.<br>
    Due to a Log-Entry with a hint to that circumstance will be written. <br><br>
    
    If the <a href="#SSCamattr">attribute</a> "rectime" would be deleted again, the default-value for recording-time (15s) become active.<br><br>

    With <a href="#SSCamset">command</a> <b>"set &lt;name&gt; on [rectime]"</b> a temporary recordingtime is determinded which would overwrite the dafault-value of recordingtime <br>
    and the attribute "rectime" (if it is set) uniquely. <br><br>

    In that case the command <b>"set &lt;name&gt; on 0"</b> leads also to an endless recording.<br><br>
    
    If you have specified a pre-recording time in SVS it will be considered too. <br><br><br>
    
    
    <a name="SSCam_Credentials"></a>
    <b>Credentials </b><br><br>
    
    After a camera-device is defined, firstly it is needed to save the credentials. This will be done with command:
   
    <pre> 
     set &lt;name&gt; credentials &lt;username&gt; &lt;password&gt;
    </pre>
    
    The operator can, dependend on what functions are planned to execute, create an user in DSM respectively in Synology Surveillance Station as well. <br>
    If the user is member of admin-group, he has access to all module functions. Without this membership the user can only execute functions with lower need of rights. <br>
    The required minimum rights to execute functions are listed in a table further down. <br>
    
    Alternatively to DSM-user a user created in SVS can be used. Also in that case a user of type "manager" has the right to execute all functions, <br>
    whereat the access to particular cameras can be restricted by the privilege profile (please see help function in SVS for details).  <br>
    As best practice it is proposed to create an user in DSM as well as in SVS too:  <br><br>
    
    <ul>
    <li>DSM-User as member of admin group: unrestricted test of all module functions -&gt; session: DSM  </li>
    <li>SVS-User as Manager or observer: adjusted privilege profile -&gt; session: SurveillanceStation  </li>
    </ul>
    <br>
    
    Using the <a href="#SSCamattr">Attribute</a> "session" can be selected, if the session should be established to DSM or the SVS instead. <br>
    If the session will be established to DSM, SVS Web-API methods are available as well as further API methods of other API's what possibly needed for processing. <br><br>
    
    After device definition the default is "login to DSM", that means credentials with admin rights can be used to test all camera-functions firstly. <br>
    After this the credentials can be switched to a SVS-session with a restricted privilege profile as needed on dependency what module functions are want to be executed. <br><br>
    
    The following list shows the minimum rights what the particular module function needs. <br><br>
    <ul>
      <table>
      <colgroup> <col width=20%> <col width=80%> </colgroup>
      <tr><td><li>set ... on                 </td><td> session: ServeillanceStation - observer with enhanced privilege "manual recording" </li></td></tr>
      <tr><td><li>set ... off                </td><td> session: ServeillanceStation - observer with enhanced privilege "manual recording" </li></td></tr>
      <tr><td><li>set ... snap               </td><td> session: ServeillanceStation - observer    </li></td></tr>
      <tr><td><li>set ... disable            </td><td> session: ServeillanceStation - manager       </li></td></tr>
      <tr><td><li>set ... enable             </td><td> session: ServeillanceStation - manager       </li></td></tr>
      <tr><td><li>set ... expmode            </td><td> session: ServeillanceStation - manager       </li></td></tr>
      <tr><td><li>set ... motdetsc           </td><td> session: ServeillanceStation - manager       </li></td></tr>
      <tr><td><li>set ... goPreset           </td><td> session: ServeillanceStation - observer with privilege objective control of camera  </li></td></tr>
      <tr><td><li>set ... runPatrol          </td><td> session: ServeillanceStation - observer with privilege objective control of camera  </li></td></tr>
      <tr><td><li>set ... goAbsPTZ           </td><td> session: ServeillanceStation - observer with privilege objective control of camera  </li></td></tr>
      <tr><td><li>set ... move               </td><td> session: ServeillanceStation - observer with privilege objective control of camera  </li></td></tr>
      <tr><td><li>set ... runView            </td><td> session: ServeillanceStation - observer with privilege liveview of camera </li></td></tr>
      <tr><td><li>set ... extevent           </td><td> session: DSM - user as member of admin-group   </li></td></tr>
      <tr><td><li>set ... stopView           </td><td> -                                          </li></td></tr>
      <tr><td><li>set ... credentials        </td><td> -                                          </li></td></tr>
      <tr><td><li>get ... caminfoall         </td><td> session: ServeillanceStation - observer    </li></td></tr>
      <tr><td><li>get ... eventlist          </td><td> session: ServeillanceStation - observer    </li></td></tr>
      <tr><td><li>get ... svsinfo            </td><td> session: ServeillanceStation - observer    </li></td></tr>
      <tr><td><li>get ... snapfileinfo       </td><td> session: ServeillanceStation - observer    </li></td></tr>
      </table>
    </ul>
      <br><br>
    
    <a name="SSCam_HTTPTimeout"></a>
    <b>HTTP-Timeout Settings</b><br><br>
    
    All functions of the SSCam-Module are using HTTP-Calls to the SVS Web API. <br>
    The Default-Value of the HTTP-Timeout amounts 4 seconds. You can set the <a href="#SSCamattr">Attribute</a> "httptimeout" > 0 to adjust the value as needed in your technical environment. <br>
    
  </ul>
  <br><br><br>
  
  
<a name="SSCamset"></a>
<b>Set </b>
  <ul>
    
  Currently there are the following options for "Set &lt;name&gt; ..."  : <br><br>

  <table>
  <colgroup> <col width=35%> <col width=65%> </colgroup>
      <tr><td>"on [rectime]":                                      </td><td>starts a recording. The recording will be stopped automatically after a period of [rectime] </td></tr>
      <tr><td>                                                     </td><td>if [rectime] = 0 an endless recording will be started </td></tr>
      <tr><td>"off" :                                              </td><td>stopps a running recording manually or using other events (e.g. with at, notify)</td></tr>
      <tr><td>"snap":                                              </td><td>triggers a snapshot of the relevant camera and store it into Synology Surveillance Station</td></tr>
      <tr><td>"disable":                                           </td><td>deactivates a camera in Synology Surveillance Station</td></tr>
      <tr><td>"enable":                                            </td><td>activates a camera in Synology Surveillance Station</td></tr>
      <tr><td>"credentials &lt;username&gt; &lt;password&gt;":     </td><td>save a set of credentils </td></tr>
      <tr><td>"expmode [ day | night | auto ]":                    </td><td>set the exposure mode to day, night or auto </td></tr>
      <tr><td>"extevent [ 1-10 ]":                                 </td><td>triggers the external event 1-10 (see actionrule editor in SVS) </td></tr>
      <tr><td>"motdetsc [ camera | SVS | disable ]":               </td><td>set motion detection to the desired mode </td></tr>
      <tr><td>"goPreset &lt;Presetname&gt;":                       </td><td>moves a PTZ-camera to a predefinied Preset-position  </td></tr>
      <tr><td>"runPatrol &lt;Patrolname&gt;":                      </td><td>starts a predefinied patrol (PTZ-cameras)  </td></tr>
      <tr><td>"goAbsPTZ [ X Y | up | down | left | right ]":       </td><td>moves a PTZ-camera to a absolute X/Y-coordinate or to direction up/down/left/right  </td></tr>
      <tr><td>"move [ up | down | left | right | dir_X ]":         </td><td>starts a continuous move of PTZ-camera to direction up/down/left/right or dir_X  </td></tr> 
      <tr><td>"runView [image | link | link_open &lt;room&gt; ]":  </td><td>starts a livestream as embedded image or link  </td></tr> 
      <tr><td>"stopView":                                          </td><td>stops a camera livestream  </td></tr> 
  </table>
  <br><br>
  
   <b> "set &lt;name&gt; [on] [off]" </b> <br><br>
  
  Examples for simple <b>Start/Stop a Recording</b>: <br><br>

  <table>
  <colgroup> <col width=20%> <col width=80%> </colgroup>
      <tr><td>set &lt;name&gt; on [rectime]  </td><td>starts a recording of camera &lt;name&gt;, stops automatically after [rectime] (default 15s or defined by <a href="#SSCamattr">attribute</a>) </td></tr>
      <tr><td>set &lt;name&gt; off           </td><td>stops the recording of camera &lt;name&gt;</td></tr>
  </table>
  <br>
  <br>

  
  <b> "set &lt;name&gt; snap" </b> <br><br>
  
  A snapshot can be triggered with:
  <pre> 
     set &lt;name&gt; snap 
  </pre>

  Subsequent some Examples for <b>taking snapshots</b>: <br><br>
  
  If a serial of snapshots should be released, it can be done using the following notify command.
  For the example a serial of snapshots are to be triggerd if the recording of a camera starts. <br>
  When the recording of camera "CamHE1" starts (Attribut event-on-change-reading -> "Record" has to be set), then 3 snapshots at intervals of 2 seconds are triggered.

  <pre>
     define he1_snap_3 notify CamHE1:Record.*on define h3 at +*{3}00:00:02 set CamHE1 snap 
  </pre>

  Release of 2 Snapshots of camera "CamHE1" at intervals of 6 seconds after the motion sensor "MelderHE1" has sent an event, <br>
  can be done e.g. with following notify-command:

  <pre>
     define he1_snap_2 notify MelderHE1:on.* define h2 at +*{2}00:00:06 set CamHE1 snap 
  </pre>

  The ID and the filename of the last snapshot will be displayed as value of variable "LastSnapId" respectively "LastSnapFilename" in the device-Readings. <br><br>
  
  <b> "set &lt;name&gt; [enable] [disable]" </b> <br><br>
  
  For <br>deactivating / activating</br> a list of cameras or all cameras using a Regex-expression, subsequent two examples using "at":
  <pre>
     define a13 at 21:46 set CamCP1,CamFL,CamHE1,CamTER disable (enable)
     define a14 at 21:46 set Cam.* disable (enable)
  </pre>
  
  A bit more convenient is it to use a dummy-device for enable/disable all available cameras in Surveillance Station.<br>
  At first the Dummy will be created.
  <pre>
     define allcams dummy
     attr allcams eventMap on:enable off:disable
     attr allcams room Cams
     attr allcams webCmd enable:disable
  </pre>
  
  With combination of two created notifies, respectively one for "enable" and one for "diasble", you are able to switch all cameras into "enable" or "disable" state at the same time if you set the dummy to "enable" or "disable". 
  <pre>
     define all_cams_disable notify allcams:.*off set CamCP1,CamFL,CamHE1,CamTER disable
     attr all_cams_disable room Cams

     define all_cams_enable notify allcams:on set CamCP1,CamFL,CamHE1,CamTER enable
     attr all_cams_enable room Cams
  </pre>
  <br><br>
  
  <b> "set &lt;name&gt; expmode [day] [night] [auto]" </b> <br><br>
  
  With this command you are able to control the exposure mode and can set it to day, night or automatic mode. 
  Thereby, for example, the behavior of camera LED's will be suitable controlled. 
  The successful switch will be reported by the reading CamExposureMode (command "get ... caminfoall"). <br><br>
  
  <b> Hint: </b> <br>
  The successfully execution of this function depends on if SVS supports that functionality of the connected camera.
  Is the field for the Day/Night-mode shown greyed in SVS -&gt; IP-camera -&gt; optimization -&gt; exposure mode, this function will be probably unsupported.  
  
  <br><br>
  
  <b> "set &lt;name&gt; motdetsc [camera] [SVS] [disable]" </b> <br><br>
  
  The command "motdetsc" (stands for "motion detection source") switchover the motion detection to the desired mode.
  If motion detection will be tuned by camera, the original camera settings are kept.
  Wird die Bewegungserkennung durch die Kamera eingestellt, werden die originalen Kameraeinstellungen beibehalten.
  The successful execution of that opreration you can retrace by the state in SVS -&gt; IP-camera -&gt; event detection -&gt; motion.
  The state of motion detection source will also be shown by the <a href="#SSCamreadings">Reading</a> "CamMotDetSc".
  
  <br><br>
  
  <b> "set &lt;name&gt; goPreset &lt;Preset&gt;" </b> <br><br>
  
  Using this command you can move PTZ-cameras to a predefined position. <br>
  The Preset-positions have to be defined first of all in the Synology Surveillance Station. This usually happens in the PTZ-control of IP-camera setup in SVS.
  The Presets will be read ito FHEM with command "get &lt;name&gt; caminfoall" (happens automatically when FHEM restarts). The import process can be repeated regular by camera polling.
  A long polling interval is recommendable in this case because of the Presets are only will be changed if the user change it in the IP-camera setup itself. 
  <br><br>
  
  Here it is an example of a PTZ-control depended on IR-motiondetector event:
  
  <pre>
    define CamFL.Preset.Wandschrank notify MelderTER:on.* set CamFL goPreset Wandschrank, ;; define CamFL.Preset.record at +00:00:10 set CamFL on 5 ;;;; define s3 at +*{3}00:00:05 set CamFL snap ;; define CamFL.Preset.back at +00:00:30 set CamFL goPreset Home
  </pre>
  
  Operating Mode: <br>
  
  The IR-motiondetector registers a motion. Hereupon the camera "CamFL" moves to Preset-posion "Wandschrank". A recording with the length of 5 seconds starts 10 seconds later. 
  Because of the prerecording time of the camera is set to 10 seconds (cf. Reading "CamPreRecTime"), the effectice recording starts when the camera move begins. <br>
  When the recording starts 3 snapshots with an interval of 5 seconds will be taken as well. <br>
  After a time of 30 seconds in position "Wandschrank" the camera moves back to postion "Home". <br><br>
  
  An extract of the log illustrates the process:
  
  <pre>  
   2016.02.04 15:02:14 2: CamFL - Camera Flur_Vorderhaus has moved to position "Wandschrank"
   2016.02.04 15:02:24 2: CamFL - Camera Flur_Vorderhaus Recording with Recordtime 5s started
   2016.02.04 15:02:29 2: CamFL - Snapshot of Camera Flur_Vorderhaus has been done successfully
   2016.02.04 15:02:30 2: CamFL - Camera Flur_Vorderhaus Recording stopped
   2016.02.04 15:02:34 2: CamFL - Snapshot of Camera Flur_Vorderhaus has been done successfully
   2016.02.04 15:02:39 2: CamFL - Snapshot of Camera Flur_Vorderhaus has been done successfully
   2016.02.04 15:02:44 2: CamFL - Camera Flur_Vorderhaus has moved to position "Home"
  </pre>
  
  <br><br>
  
  <b> "set &lt;name&gt; runPatrol &lt;Patrolname&gt;" </b> <br><br>
  
  This commans starts a predefined patrol (tour) of a PTZ-camera. <br>
  At first the patrol has to be predefined in the Synology Surveillance Station. It can be done in the PTZ-control of IP-Kamera Setup -&gt; PTZ-control -&gt; patrol.
  The patrol tours will be read with command "get &lt;name&gt; caminfoall" which is be executed automatically when FHEM restarts.
  The import process can be repeated regular by camera polling. A long polling interval is recommendable in this case because of the patrols are only will be changed 
  if the user change it in the IP-camera setup itself. 
  Further informations for creating patrols you can get in the online-help of Surveillance Station.
  <br><br>
  
  <b> "set &lt;name&gt; goAbsPTZ [ X Y | up | down | left | right ]" </b> <br><br>
  
  This command can be used to move a PTZ-camera to an arbitrary absolute X/Y-coordinate, or to absolute position using up/down/left/right. 
  The option is only available for cameras which are having the Reading "CapPTZAbs=true". The property of a camera can be requested with "get &lt;name&gt; caminfoall" .
  <br><br>

  Example for a control to absolute X/Y-coordinates: <br>

  <pre>
    set &lt;name&gt; goAbsPTZ 120 450
  </pre>
 
  In this example the camera lense moves to position X=120 und Y=450. <br>
  The valuation is:

  <pre>
    X = 0 - 640      (0 - 319 moves lense left, 321 - 640 moves lense right, 320 don't move lense)
    Y = 0 - 480      (0 - 239 moves lense down, 241 - 480 moves lense up, 240 don't move lense) 
  </pre>

  The lense can be moved in smallest steps to very large steps into the desired direction.
  If necessary the procedure has to be repeated to bring the lense into the desired position. <br><br>

  If the motion should be done with the largest possible increment the following command can be used for simplification:

  <pre>
   set &lt;name&gt; goAbsPTZ up [down ] [left] [right]
  </pre>

  In this case the lense will be moved with largest possible increment into the given absolute position.
  Also in this case the procedure has to be repeated to bring the lense into the desired position if necessary. 

  <br><br><br>
  
  <b> set &lt;name&gt; move [ up | down | left | right | dir_X ] [seconds] </b> <br><br>
  
  With this command a continuous move of a PTZ-camera will be started. In addition to the four basic directions up/down/left/right is it possible to use angular dimensions 
  "dir_X". The grain size of graduation depends on properties of the camera and can be identified by the Reading "CapPTZDirections". <br><br>

  The radian measure of 360 degrees will be devided by the value of "CapPTZDirections" and describes the move drections starting with "0=right" counterclockwise. 
  That means, if a camera Reading is "CapPTZDirections = 8" it starts with dir_0 = right, dir_2 = top, dir_4 = left, dir_6 = bottom and respectively dir_1, dir_3, dir_5 and dir_7 
  the appropriate directions between. The possible moving directions of cameras with "CapPTZDirections = 32" are correspondingly divided into smaller sections. <br><br>

  In opposite to the "set &lt;name&gt; goAbsPTZ"-command starts "set &lt;name&gt; move" a continuous move until a stop-command will be received.
  The stop-command will be generated after the optional assignable time of [seconds]. If that retention period wouldn't be set by the command, a time of 1 second will be set implicit. <br><br>
  
  Examples: <br>
  
  <pre>
    set &lt;name&gt; move up 0.5      : moves PTZ 0,5 Sek. (plus processing time) to the top
    set &lt;name&gt; move dir_1 1.5   : moves PTZ 1,5 Sek. (plus processing time) to top-right 
    set &lt;name&gt; move dir_20 0.7  : moves PTZ 1,5 Sek. (plus processing time) to left-bottom ("CapPTZDirections = 32)"
  </pre>
  
  <br>
  
  <b> set &lt;name&gt; runView [ image | link | link_open &lt;room&gt; ] </b> <br><br>
  
  A livestream (mjpeg-stream) of a camera will be started, either as embedded image or as a generated link.
  The behavior of livestream in FHEMWEB can be affected by statements in <a href="#SSCamattr">attribute</a> "htmlattr". <br><br>
  
  <b>Examples:</b><br>
  <pre>
    attr &lt;name&gt; htmlattr target=_blank width="500" height="375"
    attr &lt;name&gt; htmlattr target=_blank width=500,height=375
    attr &lt;name&gt; htmlattr width=700,height=525,top=200,left=300
  </pre>
  
  With these attribute values a streaming link will be opened (by click on) in a new browser tab or windows. If the stream will be started as an image, the size changes appropriately the
  values of width and hight. <br> 
  The command <b>"set &lt;name&gt; runView link_open"</b> starts the stream immediately in a new browser window (longpoll=1 must be set for WEB). 
  A browser window will be initiated to open for every FHEM session which is active. If you want to change this, 
  you can use command <b>"set &lt;name&gt; runView link_open &lt;room&gt;"</b> what initiates to open a browser window in that FHEM session that has just opend the room &lt;room&gt;.
  The settings of <a href="#SSCamattr">attribute</a> "livestreamprefix" overwrite the data for protocol, servername and port in <a href="#SSCamreadings">reading</a> "LiveStreamUrl".
  With it the LivestreamURL can be modified and used for distribution and external access to SVS livestream. <br><br>
  
  <b>Example:</b><br>
  <pre>
    attr &lt;name&gt; livestreamprefix https://&lt;Servername&gt;:&lt;Port&gt;
  </pre>
  
  The livestream will be stopped again using command <b>"set &lt;name&gt; stopView"</b> .
  
  <br><br>
  
  <b> set &lt;name&gt; extevent [ 1-10 ] </b> <br><br>
  
  This command triggers an external event (1-10) in SVS. 
  The actions which will are used have to be defined in the actionrule editor of SVS at first. There are the events 1-10 possible.
  In the message application of SVS you may select Email, SMS or Mobil (DS-Cam) messages to release if an external event has been triggerd.
  Further informations can be found in the online help of the actionrule editor.
  The used user needs to be a member of the admin-group and DSM-session is needed too.
  
  <br><br><br>
  
 </ul>
<br>


<a name="SSCamget"></a>
<b>Get</b>
 <ul>
  With SSCam the properties of SVS and defined Cameras could be retrieved. Actually it could be done by using the following commands:
  <pre>
      get &lt;name&gt; caminfoall
      get &lt;name&gt; eventlist
      get &lt;name&gt; svsinfo
      get &lt;name&gt; snapfileinfo
  </pre>
  
  With command <b>"get &lt;name&gt; caminfoall"</b> dependend of the type of Camera (e.g. Fix- or PTZ-Camera) the available properties will be retrieved and provided as Readings.<br>
  For example the Reading "Availability" will be set to "disconnected" if the Camera would be disconnected from Synology Surveillance Station and can be used for further 
  processing like creating events. <br>
  By command <b>"get &lt;name&gt; eventlist"</b> the <a href="#SSCamreadings">Reading</a> "CamEventNum" and "CamLastRecord" will be refreshed which containes the total number of in SVS 
  registered camera events and the path / name of the last recording. 
  This command will be implicit executed when "get ... caminfoall" is running. <br>
  The <a href="#SSCamattr">attribute</a> "videofolderMap" replaces the content of reading "VideoFolder". You can use it for example if you have mounted the videofolder of SVS 
  under another name or path and want to access by your local pc.
  Using <b>"get &lt;name&gt; snapfileinfo"</b> the filename of the last snapshot will be retrieved. This command will be executed with <b>"get &lt;name&gt; snap"</b> automatically. <br>
  The command <b>"get &lt;name&gt; svsinfo"</b> is not really dependend on a camera, but rather a command to determine common informations about the installed SVS-version and other properties. <br>
  The functions "caminfoall" and "svsinfo" will be executed automatically once-only after FHEM restarts to collect some relevant informations for camera control. <br>
  Please consider to save the <a href="#SSCam_Credentials">credentials</a> what will be used for login to DSM or SVS !
  <br><br>

  <b>Polling of Camera-Properties:</b><br><br>

  Retrieval of Camera-Properties can be done automatically if the attribute "pollcaminfoall" will be set to a value &gt; 10. <br>
  As default that attribute "pollcaminfoall" isn't be set and the automatic polling isn't be active. <br>
  The value of that attribute determines the interval of property-retrieval in seconds. If that attribute isn't be set or &lt; 10 the automatic polling won't be started <br>
  respectively stopped when the value was set to &gt; 10 before. <br><br>

  The attribute "pollcaminfoall" is monitored by a watchdog-timer. Changes of the attribute-value will be checked every 90 seconds and transact corresponding. <br>
  Changes of the pollingstate and pollinginterval will be reported in FHEM-Logfile. The reporting can be switched off by setting the attribute "pollnologging=1". <br>
  Thereby the needless growing of the logfile can be avoided. But if verbose level is set to 4 or above even though the attribute "pollnologging" is set as well, the polling <br>
  will be actived due to analysis purposes. <br><br>

  If FHEM will be restarted, the first data retrieval will be done within 60 seconds after start. <br><br>

  The state of automatic polling will be displayed by reading "PollState": <br><br>
  
  <ul>
    <li><b> PollState = Active </b>     -    automatic polling will be executed with interval correspondig value of attribute "pollcaminfoall" </li>
    <li><b> PollState = Inactive </b>   -    automatic polling won't be executed </li>
  </ul>
  <br>
  
  The meaning of reading values is described under <a href="#SSCamreadings">Readings</a> . <br><br>

  <b>Notes:</b> <br><br>

  If polling is used, the interval should be adjusted only as short as needed due to the detected camera values are predominantly static. <br>
  A feasible guide value for attribute "pollcaminfoall" could be between 600 - 1800 (s). <br>
  Per polling call and camera approximately 10 - 20 Http-calls will are stepped against Surveillance Station. <br>
  Because of that if HTTP-Timeout (pls. refer <a href="#SSCamattr">Attribut</a> "httptimeout") is set to 4 seconds, the theoretical processing time couldn't be higher than 80 seconds. <br>
  Considering a safety margin, in that example you shouldn't set the polling interval lower than 160 seconds. <br><br>

  If several Cameras are defined in SSCam, attribute "pollcaminfoall" of every Cameras shouldn't be set exactly to the same value to avoid processing bottlenecks <br>
  and thereby caused potential source of errors during request Synology Surveillance Station. <br>
  A marginal difference between the polling intervals of the defined cameras, e.g. 1 second, can already be faced as sufficient value. <br><br> 
</ul>

<a name="SSCaminternals"></a>
<b>Internals</b> <br>
 <ul>
 The meaning of used Internals is depicted in following list: <br><br>
  <ul>
  <li><b>CAMID</b> - the ID of camera defined in SVS, the value will be retrieved automatically on the basis of SVS-cameraname </li>
  <li><b>CAMNAME</b> - the name of the camera in SVS </li>
  <li><b>CREDENTIALS</b> - the value is "Set" if Credentials are set </li> 
  <li><b>NAME</b> - the cameraname in FHEM </li>
  <li><b>OPMODE</b> - the last executed operation of the module </li>  
  <li><b>SERVERADDR</b> - IP-Address of SVS Host </li>
  <li><b>SERVERPORT</b> - SVS-Port </li>
  
  <br><br>
  </ul>
 </ul>

<a name="SSCamreadings"></a>
<b>Readings</b>
 <ul>
  <br>
  Using the polling mechanism or retrieval by "get"-call readings are provieded, The meaning of the readings are listed in subsequent table: <br>
  The transfered Readings can be deversified dependend on the type of camera.<br><br>
  <ul>
  <table>  
  <colgroup> <col width=5%> <col width=95%> </colgroup>
    <tr><td><li>Availability</li>       </td><td>- Availability of Camera (disabled, enabled, disconnected, other)  </td></tr>
    <tr><td><li>CamEventNum</li>        </td><td>- delivers the total number of in SVS registered events of the camera  </td></tr>
    <tr><td><li>CamExposureControl</li> </td><td>- indicating type of exposure control  </td></tr>
    <tr><td><li>CamExposureMode</li>    </td><td>- current exposure mode (Day, Night, Auto, Schedule, Unknown)  </td></tr>
    <tr><td><li>CamIP</li>              </td><td>- IP-Address of Camera  </td></tr>
    <tr><td><li>CamLastRec</li>         </td><td>- Path / name of the last recording   </td></tr>
    <tr><td><li>CamLastRecTime</li>     </td><td>- date / starttime / endtime of the last recording   </td></tr>
    <tr><td><li>CamLiveMode</li>        </td><td>- Source of Live-View (DS, Camera)  </td></tr>
    <tr><td><li>CamModel</li>           </td><td>- Model of camera  </td></tr>
    <tr><td><li>CamMotDetSc</li>        </td><td>- state of motion detection source (disabled, by camera, by SVS)  </td></tr>
    <tr><td><li>CamPort</li>            </td><td>- IP-Port of Camera  </td></tr>
    <tr><td><li>CamPreRecTime</li>      </td><td>- Duration of Pre-Recording (in seconds) adjusted in SVS  </td></tr>
    <tr><td><li>CamRecShare</li>        </td><td>- shared folder on disk station for recordings </td></tr>
    <tr><td><li>CamRecVolume</li>       </td><td>- Volume on disk station for recordings  </td></tr>
    <tr><td><li>CamVendor</li>          </td><td>- Identifier of camera producer  </td></tr>
    <tr><td><li>CamVideoFlip</li>       </td><td>- Is the video flip  </td></tr>
    <tr><td><li>CamVideoMirror</li>     </td><td>- Is the video mirror  </td></tr>
    <tr><td><li>CapAudioOut</li>        </td><td>- Capability to Audio Out over Surveillance Station (false/true)  </td></tr>
    <tr><td><li>CapChangeSpeed</li>     </td><td>- Capability to various motion speed  </td></tr>
    <tr><td><li>CapPTZAbs</li>          </td><td>- Capability to perform absolute PTZ action  </td></tr>
    <tr><td><li>CapPTZAutoFocus</li>    </td><td>- Capability to perform auto focus action  </td></tr>
    <tr><td><li>CapPTZDirections</li>   </td><td>- the PTZ directions that camera support  </td></tr>
    <tr><td><li>CapPTZFocus</li>        </td><td>- mode of support for focus action  </td></tr>
    <tr><td><li>CapPTZHome</li>         </td><td>- Capability to perform home action  </td></tr>
    <tr><td><li>CapPTZIris</li>         </td><td>- mode of support for iris action  </td></tr>
    <tr><td><li>CapPTZPan</li>          </td><td>- Capability to perform pan action  </td></tr>
    <tr><td><li>CapPTZTilt</li>         </td><td>- mode of support for tilt action  </td></tr>
    <tr><td><li>CapPTZZoom</li>         </td><td>- Capability to perform zoom action  </td></tr>
    <tr><td><li>DeviceType</li>         </td><td>- device type (Camera, Video_Server, PTZ, Fisheye)  </td></tr>
    <tr><td><li>Error</li>              </td><td>- message text of last error  </td></tr>
    <tr><td><li>Errorcode</li>          </td><td>- error code of last error  </td></tr>
    <tr><td><li>LastSnapFilename</li>   </td><td>- the filename of the last snapshot   </td></tr>
    <tr><td><li>LastSnapId</li>         </td><td>- the ID of the last snapshot   </td></tr>    
    <tr><td><li>LastUpdateTime</li>     </td><td>- date / time the last update of readings by "caminfoall"  </td></tr> 
    <tr><td><li>LiveStreamUrl </li>     </td><td>- the livestream URL if stream is started  </td></tr> 
    <tr><td><li>Patrols</li>            </td><td>- in Synology Surveillance Station predefined patrols (at PTZ-Cameras)  </td></tr>
    <tr><td><li>PollState</li>          </td><td>- shows the state of automatic polling  </td></tr>    
    <tr><td><li>Presets</li>            </td><td>- in Synology Surveillance Station predefined Presets (at PTZ-Cameras)  </td></tr>
    <tr><td><li>Record</li>             </td><td>- if recording is running = Start, if no recording is running = Stop  </td></tr> 
    <tr><td><li>SVScustomPortHttp</li>  </td><td>- Customized port of Surveillance Station (HTTP) (to get with "svsinfo")  </td></tr> 
    <tr><td><li>SVScustomPortHttps</li> </td><td>- Customized port of Surveillance Station (HTTPS) (to get with "svsinfo")  </td></tr>
    <tr><td><li>SVSlicenseNumber</li>   </td><td>- The total number of installed licenses (to get with "svsinfo")  </td></tr>
    <tr><td><li>SVSuserPriv</li>        </td><td>- The effective rights of the user used for log in (to get with "svsinfo")  </td></tr>
    <tr><td><li>SVSversion</li>         </td><td>- package version of the installed Surveillance Station (to get with "svsinfo")  </td></tr>
    <tr><td><li>UsedSpaceMB</li>        </td><td>- used disk space of recordings by Camera  </td></tr>
    <tr><td><li>VideoFolder</li>        </td><td>- Path to the recorded video  </td></tr>
  </table>
  </ul>
  <br><br>    
  
 </ul>

 
<a name="SSCamattr"></a>
<b>Attributes</b>
  <br><br>
  <ul>
  <ul>
  <li><b>debugactivetoken</b> - if set the state of active token will be logged - only for debugging, don't use it in normal operation </li>
  
  <li><b>httptimeout</b> - Timeout-Value of HTTP-Calls to Synology Surveillance Station, Default: 4 seconds (if httptimeout = "0" or not set) </li>
  
  <li><b>htmlattr</b> - additional specifications to livestream-Url to manipulate the behavior of stream, e.g. size of the image </li>
  
  <li><b>livestreamprefix</b> - overwrites the specifications of protocol, servername and port for further use of the livestream address, e.g. as an link for external use  </li>
  
  <li><b>pollcaminfoall</b> - Interval of automatic polling the Camera properties (if < 10: no polling, if &gt; 10: polling with interval) </li>

  <li><b>pollnologging</b> - "0" resp. not set = Logging device polling active (default), "1" = Logging device polling inactive</li>
  
  <li><b>rectime</b> - the determined recordtime when a recording starts. If rectime = 0 an endless recording will be started. If it isn't defined, the default recordtime of 15s is activated </li>
  
  <li><b>session</b>  - selection of login-Session. Not set or set to "DSM" -&gt; session will be established to DSM (Sdefault). "SurveillanceStation" -&gt; session will be established to SVS </li><br>
  
  <li><b>videofolderMap</b> - replaces the content of reading "VideoFolder", Usage if e.g. folders are mountet with different names than original (SVS) </li>
  
  <li><b>verbose</b></li><br>
  
  <ul>
     Different Verbose-Level are supported.<br>
     Those are in detail:
   
   <table>  
   <colgroup> <col width=5%> <col width=95%> </colgroup>
     <tr><td> 0  </td><td>- Start/Stop-Event will be logged </td></tr>
     <tr><td> 1  </td><td>- Error messages will be logged </td></tr>
     <tr><td> 2  </td><td>- messages according to important events were logged </td></tr>
     <tr><td> 3  </td><td>- sended commands will be logged </td></tr> 
     <tr><td> 4  </td><td>- sended and received informations will be logged </td></tr>
     <tr><td> 5  </td><td>- all outputs will be logged for error-analyses. <b>Caution:</b> a lot of data could be written into logfile ! </td></tr>
   </table>
   </ul>     
   <br><br>
  
   <b>further Attributes:</b><br><br>
   
   <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>  
  </ul>
  <br><br>
</ul>


=end html
=begin html_DE

<a name="SSCam"></a>
<h3>SSCam</h3>
<ul>
    Mit diesem Modul können Operationen von in der Synology Surveillance Station (SVS) definierten Kameras ausgeführt werden. <br>
    Zur Zeit werden folgende Funktionen unterstützt: <br><br>
    <ul>
     <ul>
      <li>Start einer Aufnahme</li>
      <li>Stop einer Aufnahme (per Befehl bzw. automatisch nach Ablauf der Aufnahmedauer) </li>
      <li>Aufnehmen eines Schnappschusses und Ablage in der Synology Surveillance Station </li>
      <li>Deaktivieren einer Kamera in Synology Surveillance Station</li>
      <li>Aktivieren einer Kamera in Synology Surveillance Station</li>
      <li>Steuerung der Belichtungsmodi Tag, Nacht bzw. Automatisch </li>
      <li>Umschaltung der Ereigniserkennung durch Kamera, durch SVS oder deaktiviert  </li>
      <li>Abfrage von Kameraeigenschaften (auch mit Polling) sowie den Eigenschaften des installierten SVS-Paketes</li>
      <li>Bewegen an eine vordefinierte Preset-Position (bei PTZ-Kameras) </li>
      <li>Start einer vordefinierten Überwachungstour (bei PTZ-Kameras)  </li>
      <li>Positionieren von PTZ-Kameras zu absoluten X/Y-Koordinaten  </li>
      <li>kontinuierliche Bewegung von PTZ-Kameras   </li>
      <li>auslösen externer Ereignisse 1-10 (Aktionsregel SVS)   </li>
      <li>starten und beenden von Kamera-Livestreams  </li><br>
     </ul> 
    </ul>
    Die Aufnahmen stehen in der Synology Surveillance Station (SVS) zur Verfügung und unterliegen, wie jede andere Aufnahme, den in der Synology Surveillance Station eingestellten Regeln. <br>
    So werden zum Beispiel die Aufnahmen entsprechend ihrer Archivierungsfrist gespeichert und dann gelöscht. <br><br>
    
    Wenn sie über dieses Modul diskutieren oder zur Verbesserung des Moduls beitragen möchten, ist im FHEM-Forum ein Sammelplatz unter:<br>
    <a href="http://forum.fhem.de/index.php/topic,45671.msg374390.html#msg374390">49_SSCam: Fragen, Hinweise, Neuigkeiten und mehr rund um dieses Modul</a>.<br><br>

<b>Vorbereitung </b> <br><br>
    Dieses Modul nutzt das CPAN Module JSON. Bitte darauf achten dieses Paket zu installieren. (Debian: libjson-perl). <br>
    Das CPAN-Modul LWP wird für SSCam nicht mehr benötigt. Das Modul verwendet für HTTP-Calls die nichtblockierenden Funktionen von HttpUtils bzw. HttpUtils_NonblockingGet. <br> 
    Im DSM bzw. der Synology Surveillance Station muß ein Nutzer angelegt sein. Die Zugangsdaten werden später über ein Set-Kommando dem angelegten Gerät zugewiesen. <br>
    Nähere Informationen dazu unter <a href="#Credentials">Credentials</a><br><br>

<a name="SSCamdefine"></a>
<b>Definition</b>
  <ul>
  <br>
    <code>define &lt;name&gt; SSCAM &lt;Kameraname in SVS&gt; &lt;ServerAddr&gt; [Port] </code><br>
    <br>
    
    Definiert eine neue Kamera für SSCam. Zunächst muß diese Kamera in der Synology Surveillance Station 7.0 oder höher eingebunden sein und entsprechend funktionieren.<br><br>
    Das Modul SSCam basiert auf Funktionen der Synology Surveillance Station API. <br>
    Weitere Informationen unter: <a href="http://global.download.synology.com/download/Document/DeveloperGuide/Surveillance_Station_Web_API_v2.0.pdf">Web API Guide</a>. <br><br>
    
    Momentan wird nur das HTTP-Protokoll unterstützt um die Web-Services der Synology DS aufzurufen. <br><br>  
    
    Die Parameter beschreiben im Einzelnen:
   <br>
   <br>    
    
    <table>
    <colgroup> <col width=15%> <col width=85%> </colgroup>
    <tr><td>name:           </td><td>der Name des neuen Gerätes in FHEM</td></tr>
    <tr><td>Kameraname:     </td><td>Kameraname wie er in der Synology Surveillance Station angegeben ist. Leerzeichen im Namen sind nicht erlaubt !</td></tr>
    <tr><td>ServerAddr:     </td><td>die IP-Addresse des Synology Surveillance Station Host. Hinweis: Es sollte kein Servername verwendet werden weil DNS-Aufrufe in FHEM blockierend sind.</td></tr>
    <tr><td>Port:           </td><td>optional - der Port der Synology Surveillance Station. Wenn nicht angegeben wird der Default-Port 5000 (nur HTTP) gesetzt </td></tr>
    </table>

    <br><br>

    <b>Beispiel:</b>
     <pre>
      define CamCP SSCAM Carport 192.168.2.20 [5000]      
     </pre>
     
    
    Wird eine neue Kamera definiert, wird diesem Device zunächst eine Standardaufnahmedauer von 15 zugewiesen. <br>
    Über das <a href="#SSCamattr">Attribut</a> "rectime" kann die Aufnahmedauer für jede Kamera individuell angepasst werden. Der Wert "0" für "rectime" führt zu einer Endlosaufnahme, die durch "set &lt;name&gt; off" wieder gestoppt werden muß. <br>
    Ein Logeintrag mit einem entsprechenden Hinweis auf diesen Umstand wird geschrieben. <br><br>

    Wird das <a href="#SSCamattr">Attribut</a> "rectime" gelöscht, greift wieder der Default-Wert (15s) für die Aufnahmedauer. <br><br>

    Mit dem <a href="#SSCamset">Befehl</a> <b>"set &lt;name&gt; on [rectime]"</b> wird die Aufnahmedauer temporär festgelegt und überschreibt einmalig sowohl den Defaultwert als auch den Wert des gesetzten Attributs "rectime". <br>
    Auch in diesem Fall führt <b>"set &lt;name&gt; on 0"</b> zu einer Daueraufnahme. <br><br>

    Eine eventuell in der SVS eingestellte Dauer der Voraufzeichnung wird weiterhin berücksichtigt. <br><br><br>
    
    
    <a name="SSCam_Credentials"></a>
    <b>Credentials </b><br><br>
    
    Nach dem Definieren des Gerätes müssen zuerst die Zugangsrechte gespeichert werden. Das geschieht mit dem Befehl:
   
    <pre> 
     set &lt;name&gt; credentials &lt;username&gt; &lt;password&gt;
    </pre>
    
    Der Anwender kann in Abhängigkeit der beabsichtigten einzusetzenden Funktionen einen Nutzer im DSM bzw. in der Surveillance Station einrichten. <br>
    Ist der DSM-Nutzer der Gruppe Administratoren zugeordnet, hat er auf alle Funktionen Zugriff. Ohne diese Gruppenzugehörigkeit können nur Funktionen mit niedrigeren <br>
    Rechtebedarf ausgeführt werden. Die benötigten Mindestrechte der Funktionen sind in der Tabelle weiter unten aufgeführt. <br>
    
    Alternativ zum DSM-Nutzer kann ein in der SVS angelegter Nutzer verwendet werden. Auch in diesem Fall hat ein Nutzer vom Typ Manager das Recht alle Funktionen  <br>
    auszuführen, wobei der Zugriff auf bestimmte Kameras/ im Privilegienprofil beschränkt werden kann (siehe Hilfefunktion in SVS). <br>
    Als Best Practice wird vorgeschlagen jeweils einen User im DSM und einen in der SVS anzulegen: <br><br>
    
    <ul>
    <li>DSM-User als Mitglied der Admin-Gruppe: uneingeschränkter Test aller Modulfunktionen -> session:DSM  </li>
    <li>SVS-User als Manager oder Betrachter: angepasstes Privilegienprofil -> session: SurveillanceStation  </li>
    </ul>
    <br>
    
    Über das <a href="#SSCamattr">Attribut</a> "session" kann ausgewählt werden, ob die Session mit dem DSM oder der SVS augebaut werden soll. <br>
    Erfolgt der Session-Aufbau mit dem DSM, stehen neben der SVS Web-API auch darüber hinaus gehende API-Zugriffe zur Verfügung die unter Umständen zur Verarbeitung benötigt werden. <br><br>
    
    Nach der Gerätedefinition ist die Grundeinstellung "Login in das DSM", d.h. es können Credentials mit Admin-Berechtigungen genutzt werden um zunächst alle <br>
    Funktionen der Kameras testen zu können. Danach können die Credentials z.B. in Abhängigkeit der benötigten Funktionen auf eine SVS-Session mit entsprechend beschränkten Privilegienprofil umgestellt werden. <br><br>
    
    Die nachfolgende Aufstellung zeigt die Mindestanforderungen der jeweiligen Modulfunktionen an die Nutzerrechte. <br><br>
    <ul>
      <table>
      <colgroup> <col width=20%> <col width=80%> </colgroup>
      <tr><td><li>set ... on                 </td><td> session: ServeillanceStation - Betrachter mit erweiterten Privileg "manuelle Aufnahme" </li></td></tr>
      <tr><td><li>set ... off                </td><td> session: ServeillanceStation - Betrachter mit erweiterten Privileg "manuelle Aufnahme" </li></td></tr>
      <tr><td><li>set ... snap               </td><td> session: ServeillanceStation - Betrachter    </li></td></tr>
      <tr><td><li>set ... disable            </td><td> session: ServeillanceStation - Manager       </li></td></tr>
      <tr><td><li>set ... enable             </td><td> session: ServeillanceStation - Manager       </li></td></tr>
      <tr><td><li>set ... expmode            </td><td> session: ServeillanceStation - Manager       </li></td></tr>
      <tr><td><li>set ... motdetsc           </td><td> session: ServeillanceStation - Manager       </li></td></tr>
      <tr><td><li>set ... goPreset           </td><td> session: ServeillanceStation - Betrachter mit Privileg Objektivsteuerung der Kamera  </li></td></tr>
      <tr><td><li>set ... runPatrol          </td><td> session: ServeillanceStation - Betrachter mit Privileg Objektivsteuerung der Kamera  </li></td></tr>
      <tr><td><li>set ... goAbsPTZ           </td><td> session: ServeillanceStation - Betrachter mit Privileg Objektivsteuerung der Kamera  </li></td></tr>
      <tr><td><li>set ... move               </td><td> session: ServeillanceStation - Betrachter mit Privileg Objektivsteuerung der Kamera  </li></td></tr>
      <tr><td><li>set ... runView            </td><td> session: ServeillanceStation - Betrachter mit Privileg Liveansicht für Kamera        </li></td></tr>
      <tr><td><li>set ... stopView           </td><td> -                                            </li></td></tr>
      <tr><td><li>set ... credentials        </td><td> -                                            </li></td></tr>
      <tr><td><li>set ... extevent           </td><td> session: DSM - Nutzer Mitglied von Admin-Gruppe     </li></td></tr>
      <tr><td><li>get ... caminfoall         </td><td> session: ServeillanceStation - Betrachter    </li></td></tr>
      <tr><td><li>get ... eventlist          </td><td> session: ServeillanceStation - Betrachter    </li></td></tr>
      <tr><td><li>get ... svsinfo            </td><td> session: ServeillanceStation - Betrachter    </li></td></tr>
      <tr><td><li>get ... snapfileinfo       </td><td> session: ServeillanceStation - Betrachter    </li></td></tr>
      </table>
    </ul>
      <br><br>
    
    
    <a name="SSCam_HTTPTimeout"></a>
    <b>HTTP-Timeout setzen</b><br><br>
    
    Alle Funktionen dieses Moduls verwenden HTTP-Aufrufe gegenüber der SVS Web API. <br>
    Der Standardwert für den HTTP-Timeout beträgt 4 Sekunden. Durch Setzen des <a href="#SSCamattr">Attributes</a> "httptimeout" > 0 kann dieser Wert bei Bedarf entsprechend den technischen Gegebenheiten angepasst werden. <br>
     
    
  </ul>
  <br><br><br>
  
<a name="SSCamset"></a>
<b>Set </b>
<ul>
    
    Es gibt zur Zeit folgende Optionen für "set &lt;name&gt; ...": <br><br>

  <table>
  <colgroup> <col width=30%> <col width=70%> </colgroup>
      <tr><td>"on [rectime]":                                      </td><td>startet eine Aufnahme. Die Aufnahme wird automatisch nach Ablauf der Zeit [rectime] gestoppt.</td></tr>
      <tr><td>                                                     </td><td>Mit rectime = 0 wird eine Daueraufnahme gestartet die durch "set &lt;name&gt; off" wieder gestoppt werden muß.</td></tr>
      <tr><td>"off" :                                              </td><td>stoppt eine laufende Aufnahme manuell oder durch die Nutzung anderer Events (z.B. über at, notify)</td></tr>
      <tr><td>"snap":                                              </td><td>löst einen Schnappschuß der entsprechenden Kamera aus und speichert ihn in der Synology Surveillance Station</td></tr>
      <tr><td>"disable":                                           </td><td>deaktiviert eine Kamera in der Synology Surveillance Station</td></tr>
      <tr><td>"enable":                                            </td><td>aktiviert eine Kamera in der Synology Surveillance Station</td></tr>
      <tr><td>"credentials &lt;username&gt; &lt;password&gt;":     </td><td>speichert die Zugangsinformationen</td></tr>
      <tr><td>"expmode [ day | night | auto ]":                    </td><td>aktiviert den Belichtungsmodus Tag, Nacht oder Automatisch </td></tr>
      <tr><td>"extevent [ 1-10 ]":                                 </td><td>löst das externe Ereignis 1-10 aus (Aktionsregel in SVS) </td></tr>
      <tr><td>"motdetsc [ camera | SVS | disable ]":               </td><td>schaltet die Bewegungserkennung in den gewünschten Modus (durch Kamera, SVS, oder deaktiviert) </td></tr>
      <tr><td>"goPreset &lt;Presetname&gt;":                       </td><td>bewegt eine PTZ-Kamera zu einer vordefinierten Preset-Position  </td></tr>
      <tr><td>"runPatrol &lt;Patrolname&gt;":                      </td><td>startet eine vordefinierte Überwachungstour einer PTZ-Kamera  </td></tr>
      <tr><td>"goAbsPTZ [ X Y | up | down | left | right ]":       </td><td>positioniert eine PTZ-camera zu einer absoluten X/Y-Koordinate oder maximalen up/down/left/right-position  </td></tr>
      <tr><td>"move [ up | down | left | right | dir_X ]":         </td><td>startet kontinuerliche Bewegung einer PTZ-Kamera in Richtung up/down/left/right bzw. dir_X  </td></tr> 
      <tr><td>"runView [image | link | link_open &lt;room&gt; ]":  </td><td>startet einen Livestream als eingbettetes Image oder als Link  </td></tr>
      <tr><td>"stopView":                                          </td><td>stoppt einen Kamera-Livestream  </td></tr>
  </table>
  <br><br>
  
  
  <b> "set &lt;name&gt; [on] [off]" </b> <br><br>
  
  Beispiele für einfachen <b>Start/Stop einer Aufnahme</b>: <br><br>

  <table>
  <colgroup> <col width=20%> <col width=80%> </colgroup>
      <tr><td>set &lt;name&gt; on [rectime]  </td><td>startet die Aufnahme der Kamera &lt;name&gt;, automatischer Stop der Aufnahme nach Ablauf der Zeit [rectime] (default 15s oder wie im <a href="#SSCamattr">Attribut</a> "rectime" angegeben)</td></tr>
      <tr><td>set &lt;name&gt; off   </td><td>stoppt die Aufnahme der Kamera &lt;name&gt;</td></tr>
  </table>
  <br>
  <br>

  
  <b> "set &lt;name&gt; snap" </b> <br><br>
  
  Ein <b>Schnappschuß</b> kann ausgelöst werden mit:
  <pre> 
     set &lt;name&gt; snap 
  </pre>
  
  Nachfolgend einige Beispiele für die <b>Auslösung von Schnappschüssen</b>. <br><br>
  
  Soll eine Reihe von Schnappschüssen ausgelöst werden wenn eine Aufnahme startet, kann das z.B. durch folgendes notify geschehen. <br>
  Sobald der Start der Kamera CamHE1 ausgelöst wird (Attribut event-on-change-reading -> "Record" setzen), werden abhängig davon 3 Snapshots im Abstand von 2 Sekunden getriggert.

  <pre>
     define he1_snap_3 notify CamHE1:Record.*Start define h3 at +*{3}00:00:02 set CamHE1 snap
  </pre>
  
  Triggern von 2 Schnappschüssen der Kamera "CamHE1" im Abstand von 6 Sekunden nachdem der Bewegungsmelder "MelderHE1" einen Event gesendet hat, <br>
  kann z.B. mit folgendem notify geschehen:

  <pre>
     define he1_snap_2 notify MelderHE1:on.* define h2 at +*{2}00:00:06 set CamHE1 snap 
  </pre>

  Es wird die ID und der Filename des letzten Snapshots als Wert der Variable "LastSnapId" bzw. "LastSnapFilename" in den Readings der Kamera ausgegeben. <br><br>
  
  <b> "set &lt;name&gt; [enable] [disable]" </b> <br><br>
  
  Um eine Liste von Kameras oder alle Kameras (mit Regex) zum Beispiel um 21:46 zu <b>deaktivieren</b> / zu <b>aktivieren</b> zwei Beispiele mit at:
  <pre>
     define a13 at 21:46 set CamCP1,CamFL,CamHE1,CamTER disable (enable)
     define a14 at 21:46 set Cam.* disable (enable)
  </pre>
  
  Etwas komfortabler gelingt das Schalten aller Kameras über einen Dummy. Zunächst wird der Dummy angelegt:
  <pre>
     define allcams dummy
     attr allcams eventMap on:enable off:disable
     attr allcams room Cams
     attr allcams webCmd enable:disable
  </pre>
  
  Durch Verknüpfung mit zwei angelegten notify, jeweils ein notify für "enable" und "disable", kann man durch Schalten des Dummys auf "enable" bzw. "disable" alle Kameras auf einmal aktivieren bzw. deaktivieren.
  <pre>
     define all_cams_disable notify allcams:.*off set CamCP1,CamFL,CamHE1,CamTER disable
     attr all_cams_disable room Cams

     define all_cams_enable notify allcams:on set CamCP1,CamFL,CamHE1,CamTER enable
     attr all_cams_enable room Cams
  </pre>
  <br><br>
  
  <b> "set &lt;name&gt; expmode [day] [night] [auto]" </b> <br><br>
  
  Mit diesem Befehl kann der Belichtungsmodus der Kameras gesetzt werden. Dadurch wird z.B. das Verhalten der Kamera-LED's entsprechend gesteuert. 
  Die erfolgreiche Umschaltung wird durch das Reading CamExposureMode ("get ... caminfoall") reportet. <br><br>
  
  <b> Hinweis: </b> <br>
  Die erfolgreiche Ausführung dieser Funktion ist davon abhängig ob die SVS diese Funktionalität der Kamera unterstützt. 
  Ist in SVS -&gt; IP-Kamera -&gt; Optimierung -&gt; Belichtungsmodus das Feld für den Tag/Nachtmodus grau hinterlegt, ist nicht von einer lauffähigen Unterstützung dieser 
  Funktion auszugehen. 
  <br><br>
  
  <b> "set &lt;name&gt; motdetsc [camera] [SVS] [disable]" </b> <br><br>
  
  Der Befehl "motdetsc" (steht für motion detection source) schaltet die Bewegungserkennung in den gewünschten Modus. 
  Wird die Bewegungserkennung durch die Kamera eingestellt, werden die originalen Kameraeinstellungen beibehalten.
  Die erfolgreiche Ausführung der Operation lässt sich u.a anhand des Status von SVS -&gt; IP-Kamera -&gt; Ereigniserkennung -&gt; Bewegung nachvollziehen.
  Den Status der Bewegungserkennung  wird ebenfalls durch das <a href="#SSCamreadings">Reading</a> "CamMotDetSc" angezeigt.
  
  <br><br>
  
  <b> "set &lt;name&gt; goPreset &lt;Preset&gt;" </b> <br><br>
  
  Mit diesem Kommando können PTZ-Kameras in eine vordefininierte Position bewegt werden. <br>
  Die Preset-Positionen müssen dazu zunächst in der Synology Surveillance Station angelegt worden sein. Das geschieht in der PTZ-Steuerung im IP-Kamera Setup.
  Die Presets werden über das Kommando "get &lt;name&gt; caminfoall" eingelesen (geschieht bei restart von FHEM automatisch). Der Einlesevorgang kann durch ein Kamerapolling
  regelmäßig wiederholt werden. Ein langes Pollingintervall ist in diesem Fall empfehlenswert, da sich die Presetpositionen nur im Fall der Neuanlage bzw. Änderung verändern werden. 
  <br><br>
  
  Hier ein Beispiel einer PTZ-Steuerung in Abhängigkeit eines IR-Melder Events:
  
  <pre>
    define CamFL.Preset.Wandschrank notify MelderTER:on.* set CamFL goPreset Wandschrank, ;; define CamFL.Preset.record at +00:00:10 set CamFL on 5 ;;;; define s3 at +*{3}00:00:05 set CamFL snap ;; define CamFL.Preset.back at +00:00:30 set CamFL goPreset Home
  </pre>
  
  Funktionsweise: <br>
  Der IR-Melder "MelderTER" registriert eine Bewegung. Daraufhin wird die Kamera CamFL in die Preset-Position "Wandschrank" gebracht. Eine Aufnahme mit Dauer von 5 Sekunden startet 10 Sekunden
  später. Da die Voraufnahmezeit der Kamera 10s beträgt (vgl. Reading "CamPreRecTime"), startet die effektive Aufnahme wenn der Kameraschwenk beginnt. <br>
  Mit dem Start der Aufnahme werden drei Schnappschüsse im Abstand von 5 Sekunden angefertigt. <br>
  Nach einer Zeit von 30 Sekunden fährt die Kamera wieder zurück in die "Home"-Position. <br><br>
  
  Ein Auszug aus dem Log verdeutlicht den Ablauf:
  
  <pre>  
   2016.02.04 15:02:14 2: CamFL - Camera Flur_Vorderhaus has moved to position "Wandschrank"
   2016.02.04 15:02:24 2: CamFL - Camera Flur_Vorderhaus Recording with Recordtime 5s started
   2016.02.04 15:02:29 2: CamFL - Snapshot of Camera Flur_Vorderhaus has been done successfully
   2016.02.04 15:02:30 2: CamFL - Camera Flur_Vorderhaus Recording stopped
   2016.02.04 15:02:34 2: CamFL - Snapshot of Camera Flur_Vorderhaus has been done successfully
   2016.02.04 15:02:39 2: CamFL - Snapshot of Camera Flur_Vorderhaus has been done successfully
   2016.02.04 15:02:44 2: CamFL - Camera Flur_Vorderhaus has moved to position "Home"
  </pre>
  
  <br>
  
  <b> "set &lt;name&gt; runPatrol &lt;Patrolname&gt;" </b> <br><br>
  
  Dieses Kommando startet die vordefinierterte Überwachungstour einer PTZ-Kamera. <br>
  Die Überwachungstouren müssen dazu zunächst in der Synology Surveillance Station angelegt worden sein. 
  Das geschieht in der PTZ-Steuerung im IP-Kamera Setup -&gt; PTZ-Steuerung -&gt; Überwachung.
  Die Überwachungstouren (Patrols) werden über das Kommando "get &lt;name&gt; caminfoall" eingelesen, welches beim Restart von FHEM automatisch abgearbeitet wird. 
  Der Einlesevorgang kann durch ein Kamerapolling regelmäßig wiederholt werden. Ein langes Pollingintervall ist in diesem Fall empfehlenswert, da sich die 
  Überwachungstouren nur im Fall der Neuanlage bzw. Änderung verändern werden.
  Nähere Informationen zur Anlage von Überwachungstouren sind in der Hilfe zur Surveillance Station enthalten. 
  <br><br>
  
  <b> "set &lt;name&gt; goAbsPTZ [ X Y | up | down | left | right ]" </b> <br><br>
  
  Mit diesem Kommando wird eine PTZ-Kamera in Richtung einer wählbaren absoluten X/Y-Koordinate bewegt, oder zur maximalen Absolutposition in Richtung up/down/left/right. 
  Die Option ist nur für Kameras verfügbar die das Reading "CapPTZAbs=true" (die Fähigkeit für PTZAbs-Aktionen) besitzen. Die Eigenschaften der Kamera kann mit "get &lt;name&gt; caminfoall" abgefragt werden.
  <br><br>

  Beispiel für Ansteuerung absoluter X/Y-Koordinaten: <br>

  <pre>
    set &lt;name&gt; goAbsPTZ 120 450
  </pre>
 
  Dieses Beispiel bewegt die Kameralinse in die Position X=120 und Y=450. <br>
  Der Wertebereich ist dabei:

  <pre>
    X = 0 - 640      (0 - 319 bewegt nach links, 321 - 640 bewegt nach rechts, 320 bewegt die Linse nicht)
    Y = 0 - 480      (0 - 239 bewegt nach unten, 241 - 480 bewegt nach oben, 240 bewegt die Linse nicht) 
  </pre>

  Die Linse kann damit in kleinsten bis sehr großen Schritten in die gewünschte Richtung bewegt werden. 
  Dieser Vorgang muß ggf. mehrfach wiederholt werden um die Kameralinse in die gewünschte Position zu bringen. <br><br>

  Soll die Bewegung mit der maximalen Schrittweite erfolgen, kann zur Vereinfachung der Befehl:

  <pre>
   set &lt;name&gt; goAbsPTZ up [down ] [left] [right]
  </pre>

  verwendet werden. Die Optik wird in diesem Fall mit der größt möglichen Schrittweite zur Absolutposition in der angegebenen Richtung bewegt. 
  Auch in diesem Fall muß der Vorgang ggf. mehrfach wiederholt werden um die Kameralinse in die gewünschte Position zu bringen.
  
  <br><br><br>
  
  <b> set &lt;name&gt; move [ up | down | left | right | dir_X ] [Sekunden] </b> <br><br>
  
  Mit diesem Kommando wird eine kontinuierliche Bewegung der PTZ-Kamera gestartet. Neben den vier Grundrichtungen up/down/left/right stehen auch 
  Zwischenwinkelmaße "dir_X" zur Verfügung. Die Feinheit dieser Graduierung ist von der Kamera abhängig und kann dem Reading "CapPTZDirections" entnommen werden. <br><br>

  Das Bogenmaß von 360 Grad teilt sich durch den Wert von "CapPTZDirections" und beschreibt die Bewegungsrichtungen beginnend mit "0=rechts" entgegen dem 
  Uhrzeigersinn. D.h. bei einer Kamera mit "CapPTZDirections = 8" bedeutet dir_0 = rechts, dir_2 = oben, dir_4 = links, dir_6 = unten bzw. dir_1, dir_3, dir_5 und dir_7 
  die entsprechenden Zwischenrichtungen. Die möglichen Bewegungsrichtungen bei Kameras mit "CapPTZDirections = 32" sind dementsprechend kleinteiliger. <br><br>

  Im Gegensatz zum "set &lt;name&gt; goAbsPTZ"-Befehl startet der Befehl "set &lt;name&gt; move" eine kontinuierliche Bewegung bis ein Stop-Kommando empfangen wird. 
  Das Stop-Kommando wird nach Ablauf der optional anzugebenden Zeit [Sekunden] ausgelöst. Wird diese Laufzeit nicht angegeben, wird implizit Sekunde = 1 gesetzt. <br><br>
  
  <b>Beispiele: </b><br>
  
  <pre> 
    set &lt;name&gt; move up 0.5      : bewegt PTZ 0,5 Sek. (zzgl. Prozesszeit) nach oben
    set &lt;name&gt; move dir_1 1.5   : bewegt PTZ 1,5 Sek. (zzgl. Prozesszeit) nach rechts-oben 
    set &lt;name&gt; move dir_20 0.7  : bewegt PTZ 1,5 Sek. (zzgl. Prozesszeit) nach links-unten ("CapPTZDirections = 32)"
  </pre>

  <br>
  
  <b> set &lt;name&gt; runView [ image | link | link_open &lt;room&gt; ] </b> <br><br>
  
  Es wird ein Livestream (mjpeg-Stream) der Kamera, entweder als eingebettetes Image oder als generierter Link, gestartet. 
  Das Verhalten des Livestreams im FHEMWEB kann durch Angaben im <a href="#SSCamattr">Attribut</a> "htmlattr" beeinflusst werden. <br><br>
  
  <b>Beispiel:</b><br>
  <pre>
    attr &lt;name&gt; htmlattr target=_blank width="500" height="375"
    attr &lt;name&gt; htmlattr target=_blank width=500,height=375
    attr &lt;name&gt; htmlattr width=700,height=525,top=200,left=300
  </pre>
  
  Mit diesen Attributwerten öffnet der Link (mit Klick) als weiteres Fenster/Browsertab. Wird der Stream als Image gestartet, ändert sich die Größe entsprechend der 
  Angaben von Width und Hight. <br>
  Das Kommando <b>"set &lt;name&gt; runView link_open"</b> startet den Livestreamlink sofort in einem neuen Browserfenster (longpoll=1 muß für WEB gesetzt sein).
  Dabei wird für jede aktive FHEM-Session eine Fensteröffnung initiiert. Soll dieses Verhalten geändert werden, kann <b>"set &lt;name&gt; runView link_open &lt;room&gt;"</b>
  verwendet werden um das Öffnen des Browserwindows in einem beliebigen in einer FHEM-Session angezeigten Raum &lt;room&gt; zu initiieren.<br>
  Das gesetzte <a href="#SSCamattr">Attribut</a> "livestreamprefix" überschreibt im <a href="#SSCamreadings">Reading</a> "LiveStreamUrl" die Angaben für Protokoll, Servername und Port. 
  Damit kann z.B. die LiveStreamUrl für den Versand und externen Zugriff auf die SVS modifiziert werden. <br><br>
  
  <b>Beispiel:</b><br>
  <pre>
    attr &lt;name&gt; livestreamprefix https://&lt;Servername&gt;:&lt;Port&gt;
  </pre>
  
  Der Livestream wird über das Kommando <b>"set &lt;name&gt; stopView"</b> wieder beendet.
  
  <br><br>
  
  <b> set &lt;name&gt; extevent [ 1-10 ] </b> <br><br>
  
  Dieses Kommando triggert ein externes Ereignis (1-10) in der SVS. 
  Die Aktionen, die dieses Ereignis auslöst, sind zuvor in dem Aktionsregeleditor der SVS einzustellen. Es stehen die Ereignisse 1-10 zur Verfügung.
  In der Banchrichtigungs-App der SVS können auch Email, SMS oder Mobil (DS-Cam) Nachrichten ausgegeben werden wenn ein externes Ereignis ausgelöst wurde.
  Nähere Informationen dazu sind in der Hilfe zum Aktionsregeleditor zu finden.
  Der verwendete User benötigt Admin-Rechte in einer DSM-Session.
  
  <br><br><br>

</ul>
  <br>

<a name="SSCamget"></a>
<b>Get</b>
 <ul>
  Mit SSCam können die Eigenschaften der Surveillance Station und der Kameras abgefragt werden. ZUr Zeit stehen dazu folgende Befehle zur Verfügung:
  <pre>
      get &lt;name&gt; caminfoall
      get &lt;name&gt; eventlist
      get &lt;name&gt; svsinfo
      get &lt;name&gt; snapfileinfo
  </pre>
  
  Mit dem Befehl <b>"get &lt;name&gt; caminfoall"</b> werden abhängig von der Art der Kamera (z.B. Fix- oder PTZ-Kamera) die verfügbaren Eigenschaften ermittelt und als Readings zur Verfügung gestellt. <br>
  So wird zum Beispiel das Reading "Availability" auf "disconnected" gesetzt falls die Kamera von der Surveillance Station getrennt wird und kann für weitere Verarbeitungen genutzt werden. <br>
  Durch <b>"get &lt;name&gt; eventlist"</b> wird das <a href="#SSCamreadings">Reading</a> "CamEventNum" und "CamLastRec" aktualisiert, welches die Gesamtanzahl der 
  registrierten Kameraevents und den Pfad / Namen der letzten Aufnahme enthält.
  Dieser Befehl wird implizit mit "get ... caminfoall" ausgeführt. <br>
  
  Mit dem <a href="#SSCamattr">Attribut</a> "videofolderMap" kann der Inhalt des Readings "VideoFolder" überschrieben werden. 
  Dies kann von Vortel sein wenn das Surveillance-Verzeichnis der SVS an dem lokalen PC unter anderem Pfadnamen gemountet ist und darüber der Zugriff auf die Aufnahmen
  erfolgen soll (z.B. Verwendung Email-Versand). <br><br>
  
  Ein DOIF-Beispiel für den Email-Versand von Snapshot und Aufnahmelink per Non-blocking sendmail:
  <pre>
     define CamHE1.snap.email DOIF ([CamHE1:"LastSnapFilename"]) 
     ({DebianMailnbl ('Recipient@Domain','Bewegungsalarm CamHE1','Eine Bewegung wurde an der Haustür registriert. Aufnahmelink: \  
     \[CamHE1:VideoFolder]\[CamHE1:CamLastRec]','/media/sf_surveillance/@Snapshot/[CamHE1:LastSnapFilename]')})
  </pre>
  
  Mit <b>"get &lt;name&gt; snapfileinfo"</b> wird der Filename des letzten Schnapschusses ermittelt. Der Befehl wird implizit mit <b>"get &lt;name&gt; snap"</b> ausgeführt. <br>
  Der Befehl <b>"get &lt;name&gt; svsinfo"</b> ist eigentlich nicht von der Kamera abhängig, sondern ermittelt vielmehr allgemeine Informationen zur installierten SVS-Version und andere Eigenschaften. <br>
  Die Funktionen "caminfoall" und "svsinfo" werden einmalig automatisch beim Start von FHEM ausgeführt um steuerungsrelevante Informationen zu sammeln.<br>
  Es ist darauf zu achten dass die <a href="#SSCam_Credentials">Credentials</a> gespeichert wurden !
  <br><br>

  <b>Polling der Kameraeigenschaften:</b><br><br>

  Die Abfrage der Kameraeigenschaften erfolgt automatisch, wenn das Attribut "pollcaminfoall" (siehe Attribute) mit einem Wert &gt; 10 gesetzt wird. <br>
  Per Default ist das Attribut "pollcaminfoall" nicht gesetzt und das automatische Polling nicht aktiv. <br>
  Der Wert dieses Attributes legt das Intervall der Abfrage in Sekunden fest. Ist das Attribut nicht gesetzt oder &lt; 10 wird kein automatisches Polling <br>
  gestartet bzw. gestoppt wenn vorher der Wert &gt; 10 gesetzt war. <br><br>

  Das Attribut "pollcaminfoall" wird durch einen Watchdog-Timer überwacht. Änderungen des Attributwertes werden alle 90 Sekunden ausgewertet und entsprechend umgesetzt. <br>
  Eine Änderung des Pollingstatus / Pollingintervalls wird im FHEM-Logfile protokolliert. Diese Protokollierung kann durch Setzen des Attributes "pollnologging=1" abgeschaltet werden.<br>
  Dadurch kann ein unnötiges Anwachsen des Logs vermieden werden. Ab verbose=4 wird allerdings trotz gesetzten "pollnologging"-Attribut ein Log des Pollings <br>
  zu Analysezwecken aktiviert. <br><br>

  Wird FHEM neu gestartet, wird bei aktivierten Polling der ersten Datenabruf innerhalb 60s nach dem Start ausgeführt. <br><br>

  Der Status des automatischen Pollings wird durch das Reading "PollState" signalisiert: <br><br>
  
  <ul>
    <li><b> PollState = Active </b>    -    automatisches Polling wird mit Intervall entsprechend "pollcaminfoall" ausgeführt </li>
    <li><b> PollState = Inactive </b>  -    automatisches Polling wird nicht ausgeführt </li>
  </ul>
  <br>
 
  Die Bedeutung der Readingwerte ist unter <a href="#SSCamreadings">Readings</a> beschrieben. <br><br>

  <b>Hinweise:</b> <br><br>

  Wird Polling eingesetzt, sollte das Intervall nur so kurz wie benötigt eingestellt werden da die ermittelten Werte überwiegend statisch sind. <br>
  Das eingestellte Intervall sollte nicht kleiner sein als die Summe aller HTTP-Verarbeitungszeiten.
  Pro Pollingaufruf und Kamera werden ca. 10 - 20 Http-Calls gegen die Surveillance Station abgesetzt.<br><br>
  Bei einem eingestellten HTTP-Timeout (siehe <a href="#SSCamattr">Attribut</a>) "httptimeout") von 4 Sekunden kann die theoretische Verarbeitungszeit nicht höher als 80 Sekunden betragen. <br>
  In dem Beispiel sollte man das Pollingintervall mit einem Sicherheitszuschlag auf nicht weniger 160 Sekunden setzen. <br>
  Ein praktikabler Richtwert könnte zwischen 600 - 1800 (s) liegen. <br>

  Sind mehrere Kameras in SSCam definiert, sollte "pollcaminfoall" nicht bei allen Kameras auf exakt den gleichen Wert gesetzt werden um Verarbeitungsengpässe <br>
  und dadurch versursachte potentielle Fehlerquellen bei der Abfrage der Synology Surveillance Station zu vermeiden. <br>
  Ein geringfügiger Unterschied zwischen den Pollingintervallen der definierten Kameras von z.B. 1s kann bereits als ausreichend angesehen werden. <br><br> 
</ul>

<a name="SSCaminternals"></a>
<b>Internals</b> <br>
 <ul>
 Die Bedeutung der verwendeten Internals stellt die nachfolgende Liste dar: <br><br>
  <ul>
  <li><b>CAMID</b> - die ID der Kamera in der SVS, der Wert wird automatisch anhand des SVS-Kameranamens ermittelt. </li>
  <li><b>CAMNAME</b> - der Name der Kamera in der SVS </li>
  <li><b>CREDENTIALS</b> - der Wert ist "Set" wenn die Credentials gesetzt wurden </li>
  <li><b>NAME</b> - der Kameraname in FHEM </li>
  <li><b>OPMODE</b> - die zuletzt ausgeführte Operation des Moduls </li> 
  <li><b>SERVERADDR</b> - IP-Adresse des SVS Hostes </li>
  <li><b>SERVERPORT</b> - der SVS-Port </li>
  
  <br><br>
  </ul>
 </ul>


<a name="SSCamreadings"></a>
<b>Readings</b>
 <ul>
  <br>
  Über den Pollingmechanismus bzw. durch Abfrage mit "Get" werden Readings bereitgestellt, deren Bedeutung in der nachfolgenden Tabelle dargestellt sind. <br>
  Die übermittelten Readings können in Abhängigkeit des Kameratyps variieren.<br><br>
  <ul>
  <table>  
  <colgroup> <col width=5%> <col width=95%> </colgroup>
    <tr><td><li>Availability</li>       </td><td>- Verfügbarkeit der Kamera (disabled, enabled, disconnected, other)  </td></tr>
    <tr><td><li>CamEventNum</li>        </td><td>- liefert die Gesamtanzahl der in SVS registrierten Events der Kamera  </td></tr>
    <tr><td><li>CamExposureControl</li> </td><td>- zeigt den aktuell eingestellten Typ der Belichtungssteuerung  </td></tr>
    <tr><td><li>CamExposureMode</li>    </td><td>- aktueller Belichtungsmodus (Day, Night, Auto, Schedule, Unknown)  </td></tr>
    <tr><td><li>CamIP</li>              </td><td>- IP-Adresse der Kamera  </td></tr>
    <tr><td><li>CamLastRec</li>         </td><td>- Pfad / Name der letzten Aufnahme   </td></tr>
    <tr><td><li>CamLastRecTime</li>     </td><td>- Datum / Startzeit - Stopzeit der letzten Aufnahme   </td></tr>
    <tr><td><li>CamLiveMode</li>        </td><td>- Quelle für Live-Ansicht (DS, Camera)  </td></tr>
    <tr><td><li>CamModel</li>           </td><td>- Kameramodell  </td></tr>
    <tr><td><li>CamMotDetSc</li>        </td><td>- Status der Bewegungserkennung (disabled, durch Kamera, durch SVS)  </td></tr>
    <tr><td><li>CamPort</li>            </td><td>- IP-Port der Kamera  </td></tr>
    <tr><td><li>CamPreRecTime</li>      </td><td>- Dauer der der Voraufzeichnung in Sekunden (Einstellung in SVS)  </td></tr>
    <tr><td><li>CamRecShare</li>        </td><td>- gemeinsamer Ordner auf der DS für Aufnahmen  </td></tr>
    <tr><td><li>CamRecVolume</li>       </td><td>- Volume auf der DS für Aufnahmen  </td></tr>
    <tr><td><li>CamVendor</li>          </td><td>- Kamerahersteller Bezeichnung  </td></tr>
    <tr><td><li>CamVideoFlip</li>       </td><td>- Ist das Video gedreht  </td></tr>
    <tr><td><li>CamVideoMirror</li>     </td><td>- Ist das Video gespiegelt  </td></tr>
    <tr><td><li>CapAudioOut</li>        </td><td>- Fähigkeit der Kamera zur Audioausgabe über Surveillance Station (false/true)  </td></tr>
    <tr><td><li>CapChangeSpeed</li>     </td><td>- Fähigkeit der Kamera verschiedene Bewegungsgeschwindigkeiten auszuführen  </td></tr>
    <tr><td><li>CapPTZAbs</li>          </td><td>- Fähigkeit der Kamera für absolute PTZ-Aktionen   </td></tr>
    <tr><td><li>CapPTZAutoFocus</li>    </td><td>- Fähigkeit der Kamera für Autofokus Aktionen  </td></tr>
    <tr><td><li>CapPTZDirections</li>   </td><td>- die verfügbaren PTZ-Richtungen der Kamera  </td></tr>
    <tr><td><li>CapPTZFocus</li>        </td><td>- Art der Kameraunterstützung für Fokussierung  </td></tr>
    <tr><td><li>CapPTZHome</li>         </td><td>- Unterstützung der Kamera für Home-Position  </td></tr>
    <tr><td><li>CapPTZIris</li>         </td><td>- Unterstützung der Kamera für Iris-Aktion  </td></tr>
    <tr><td><li>CapPTZPan</li>          </td><td>- Unterstützung der Kamera für Pan-Aktion  </td></tr>
    <tr><td><li>CapPTZTilt</li>         </td><td>- Unterstützung der Kamera für Tilt-Aktion  </td></tr>
    <tr><td><li>CapPTZZoom</li>         </td><td>- Unterstützung der Kamera für Zoom-Aktion  </td></tr>
    <tr><td><li>DeviceType</li>         </td><td>- Kameratyp (Camera, Video_Server, PTZ, Fisheye)  </td></tr>
    <tr><td><li>Error</li>              </td><td>- Meldungstext des letzten Fehlers  </td></tr>
    <tr><td><li>Errorcode</li>          </td><td>- Fehlercode des letzten Fehlers   </td></tr>
    <tr><td><li>LastSnapFilename</li>   </td><td>- der Filename des letzten Schnapschusses   </td></tr>
    <tr><td><li>LastSnapId</li>         </td><td>- die ID des letzten Schnapschusses   </td></tr>
    <tr><td><li>LastUpdateTime</li>     </td><td>- Datum / Zeit der letzten Aktualisierung durch "caminfoall" </td></tr> 
    <tr><td><li>LiveStreamUrl </li>     </td><td>- die LiveStream-Url wenn der Stream gestartet ist </td></tr> 
    <tr><td><li>Patrols</li>            </td><td>- in Surveillance Station voreingestellte Überwachungstouren (bei PTZ-Kameras)  </td></tr>
    <tr><td><li>PollState</li>          </td><td>- zeigt den Status des automatischen Pollings an  </td></tr>    
    <tr><td><li>Presets</li>            </td><td>- in Surveillance Station voreingestellte Positionen (bei PTZ-Kameras)  </td></tr>
    <tr><td><li>Record</li>             </td><td>- Aufnahme läuft = Start, keine Aufnahme = Stop  </td></tr> 
    <tr><td><li>SVScustomPortHttp</li>  </td><td>- benutzerdefinierter Port der Surveillance Station (HTTP) im DSM-Anwendungsportal (get mit "svsinfo")  </td></tr> 
    <tr><td><li>SVScustomPortHttps</li> </td><td>- benutzerdefinierter Port der Surveillance Station (HTTPS) im DSM-Anwendungsportal (get mit "svsinfo") </td></tr>
    <tr><td><li>SVSlicenseNumber</li>   </td><td>- die Anzahl der installierten Kameralizenzen (get mit "svsinfo") </td></tr>
    <tr><td><li>SVSuserPriv</li>        </td><td>- die effektiven Rechte des verwendeten Users nach dem Login (get mit "svsinfo") </td></tr>
    <tr><td><li>SVSversion</li>         </td><td>- die Paketversion der installierten Surveillance Station (get mit "svsinfo") </td></tr>
    <tr><td><li>UsedSpaceMB</li>        </td><td>- durch Aufnahmen der Kamera belegter Plattenplatz auf dem Volume  </td></tr>
    <tr><td><li>VideoFolder</li>        </td><td>- Pfad zu den aufgenommenen Videos  </td></tr>
  </table>
  </ul>
  <br><br>    
  
 </ul>


<a name="SSCamattr"></a>
<b>Attribute</b>
  <br><br>
  <ul>
  <ul>
  <li><b>debugactivetoken</b> - wenn gesetzt wird der Status des Active-Tokens gelogged - nur für Debugging, nicht im normalen Betrieb benutzen </li>
  
  <li><b>httptimeout</b> - Timeout-Wert für HTTP-Aufrufe zur Synology Surveillance Station, Default: 4 Sekunden (wenn httptimeout = "0" oder nicht gesetzt) </li>
  
  <li><b>htmlattr</b> - ergänzende Angaben zur Livestream-Url um das Verhalten wie Bildgröße zu beeinflussen  </li>
  
  <li><b>livestreamprefix</b> - überschreibt die Angaben zu Protokoll, Servernamen und Port zur Weiterverwendung der Livestreamadresse als z.B. externer Link   </li>
  
  <li><b>pollcaminfoall</b> - Intervall der automatischen Eigenschaftsabfrage (Polling) einer Kamera (kleiner 10: kein Polling, größer 10: Polling mit Intervall) </li>

  <li><b>pollnologging</b> - "0" bzw. nicht gesetzt = Logging Gerätepolling aktiv (default), "1" = Logging Gerätepolling inaktiv </li>
  
  <li><b>rectime</b> - festgelegte Aufnahmezeit wenn eine Aufnahme gestartet wird. Mit rectime = 0 wird eine Endlosaufnahme gestartet. Ist "rectime" nicht gesetzt, wird der Defaultwert von 15s verwendet.</li>

  <li><b>session</b>  - Auswahl der Login-Session. Nicht gesetzt oder "DSM" -> session wird mit DSM aufgebaut (Standard). "SurveillanceStation" -> Session-Aufbau erfolgt mit SVS </li><br>
  
  <li><b>videofolderMap</b> - ersetzt den Inhalt des Readings "VideoFolder", Verwendung z.B. bei gemounteten Verzeichnissen </li>
  
  <li><b>verbose</b> </li><br>
  
  <ul>
   Es werden verschiedene Verbose-Level unterstützt.
   Dies sind im Einzelnen:
   
    <table>  
    <colgroup> <col width=5%> <col width=95%> </colgroup>
      <tr><td> 0  </td><td>- Start/Stop-Ereignisse werden geloggt </td></tr>
      <tr><td> 1  </td><td>- Fehlermeldungen werden geloggt </td></tr>
      <tr><td> 2  </td><td>- Meldungen über wichtige Ereignisse oder Alarme </td></tr>
      <tr><td> 3  </td><td>- gesendete Kommandos werden geloggt </td></tr>
      <tr><td> 4  </td><td>- gesendete und empfangene Daten werden geloggt </td></tr>
      <tr><td> 5  </td><td>- alle Ausgaben zur Fehleranalyse werden geloggt. <b>ACHTUNG:</b> möglicherweise werden sehr viele Daten in das Logfile geschrieben! </td></tr>
    </table>
   </ul>     
   <br><br>
  
   <b>weitere Attribute:</b><br><br>
   
   <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>  
  </ul>
  <br><br>
</ul>

=end html_DE
=cut

