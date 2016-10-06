##############################################################################
#
#     50_TelegramBot.pm
#
#     This file is part of Fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with Fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################
#  
#  TelegramBot (c) Johannes Viegener / https://github.com/viegener/Telegram-fhem
#
# This module handles receiving and sending messages to the messaging service telegram (see https://telegram.org/)
# TelegramBot is making use of the Telegrom Bot API (see https://core.telegram.org/bots and https://core.telegram.org/bots/api)
# For using it with fhem an telegram BOT API key is needed! --> see https://core.telegram.org/bots/api#authorizing-your-bot
#
# Discussed in FHEM Forum: https://forum.fhem.de/index.php/topic,38328.0.html
#
# $Id$
#
##############################################################################
# 0.0 2015-09-16 Started
# 1.0 2015-10-17 Initial SVN-Version 
#   
#   INTERNAL: sendIt allows providing a keyboard json
#   Favorites sent as keyboard
#   allow sending to contacts not in the contacts list (by giving id of user)
#   added comment on save (statefile) for correct operation in documentation
#   contacts changed on new contacts found
#   saveStateOnContactChange attribute to disaloow statefile save on contact change
#   writeStatefile on contact change
#   make contact restore simpler --> whenever new contact found write all contacts into log with loglevel 1
#   Do not allow shutdown as command for execution
#   ret from command handlings logged
#   maxReturnSize for command results
#   limit sentMsgTxt internal to 1000 chars (even if longer texts are sent)
#   contact reading now written in contactsupdate before statefile written
#   documentation corrected - forum#msg350873
#   cleanup on comments 
#   removed old version changes to history.txt
#   add digest readings for error
#   attribute to reduce logging on updatepoll errors - pollingVerbose:0_None,1_Digest,2_Log - (no log, default digest log daily, log every issue)
#   documentation for pollingverbose
#   reset / log polling status also in case of no error
#   removed remark on timeout of 20sec
#   LastCommands returns keyboard with commands 
#   added send / image command for compatibility with yowsup
#   image not in cmd list to avoid this being first option
#   FIX: Keyboard removed after fac execution
#   Do not use contacts from msg since this might be NON-Telegram contact
#   cmdReturnEmptyResult - to suppress empty results from command execution
#   prev... Readings do not trigger events (to reduce log content)
#   Contacts reading only changed if string is not equal
#   Need to replace \n again with Chr10 - linefeed due to a telegram change - FORUM #msg363825
# 1.1 2015-11-24 keyboards added, log changes and multiple smaller enhancements
#   
#   Prepared for allowing multiple contacts being given for msg/image commands
#   Prepare for defaultpeer specifying multiple peers as a list
#   Allow multiple peers specified for send/msg/image etc
#   Remove deprecated commands messageTo sendImageTo sendPhotoTo
#   Minor fixes on lineendings for cmd results and log messages
#   pollingVerbose attribute checked on set
#   allowUnknownContacts attribute added default 1
# 1.2 2015-12-20 multiple contacts for send etc/removed depreacted messageTo,sendImageTo,sendPhotoTo/allowunknowncontacts
#
#   modified cmd handling in preparation for alias (and more efficient)
#   allow alias to be defined for favorites: /aliasx=cmdx;
#   docu for alias
#   correction for keyboard (no abbruch)
#   added sentMsgId on sentMsgs
#   Also set sentMsg Id and result in Readings (when finished)
#   add docu for new readings on sentMsg
#   fix for checkCmdKeyword to not sent unauthorized on every message
#   avoid unauthorized messages to be sent multiple times 
#   added sendVoice for Voice messages
#   added sendMedia / sendDocument for arbitrary media files
#   specified a longer description in the doc for gaining telegramBot tokens
#   fix: allowunknowncontacts for known contacts
# 1.3 2016-01-02 alias for commands, new readings, support for sending media files plus fixes
#   
#   receiving media files is possible --> file id is stored in msgFileId / msgText starting with "received..."
#     additional info from message (type, name, etc) is contained in msgText 
#   added get function to return url for file ids on media messages "urlForFile"
#     writes returned url into internal: fileUrl
#   INT: switch command result sending to direct _sendIt call
#   forum msg396189
#     favorite commands can be used also to send images back if the result of the command is an image 
#     e.g. { plotAsPng('SVG_FileLog_something') } --> returns PNG if used in favorite the result will be send as photo
#   Forbid all commands starting with shutdown
#   Recognize MP3 also with ID3v2 tag (2.2 / 2.3 / 2.4)
# 1.4 2016-02-07 receive media files, send media files directly from parameter (PNG, JPG, MP3, PDF, etc)

#   Retry-Preparation: store arsg in param array / delete in case of error before sending
#   added maxRetries for Retry send with wait time 1=10s / 2=100s / 3=1000s ~ 17min / 4=10000s ~ 3h / 5=100000s ~ 30h
#   tested Retry of send in case of errors (after finalizing message)
#   attr returns text to avoid automatic attr setting in fhem.pl
#   documented maxRetries
#   fixed attributehandling to normalize and correct attribute values
#   fix for perl "keys on reference is experimental" forum#msg417968
#   allow confirmation for favorite commands by prefixing with question ark (?)
#   fix contact update 
# 1.5 2016-03-19 retry for send / confirmation 

#   supergroups added now also to contacts
#   fix for first name of contacts undefined
#   remove stale/duplicate contacts (based on username) on update of contacts (supergroups get new ids)
#   Allow localization outward facing messages -> templates with replacements (German as default)
#     New attributes for visible telegram responses: 
#       textResponseConfirm, textResponseFavorites, textResponseCommands, textResponseResult, textResponseUnauthorized
#   descriptions for favorites can be specified (enclosed in [])
#   descriptions are shown in favorite list and confirmation dialogue
#   texts are converted to UTF8 also for keyboards
#   favorite list corrected
# 1.6 2016-04-08 text customization for replies/messages and favorite descriptions 

#   Fix: contact handling failed (/ in contact names ??)
#   Reply keyboards also for sendVoice/sendDocument ect
#   reply msg id in sendit - new set cmd reply
#   Fix: reset also removes retry timer 
#   TEMP: SNAME in hash is needed for allowed (SNAME reflects if the TCPServer device name) 
#   Remove unnecessary attribute setters
#   added allowedCommands and doc (with modification of allowed_... device)
#   allowedCommands only modified on the allowed_... device
# 1.7 2016-05-05 reply set command / allowedCommands as restriction

#   fix for addPar (Caption) on photos in SendIt
#   fix for contact list UTF8 encoding on restart
#   fix: encoding problem in some environments leading to wrong length calc in httputils (msg457443)
#
#   fix: Favorite description without alias name was not parsed correctly
#   fix: Favorite alias only handled if really contains more than the /
#   
#   Complete rework of JSON/UTF8 code to solve timeout and encoding issues
#   Add \t for messages texts - will be a single space in the message
# 1.8 2016-05-05 UNicode / Umlaute handling changed, \t added 

#   Add unescaping of filenames for send - this allows also spaces (%20)
#   Attribut filenameUrlEscape allows switching on urlescaping for filenames
#   Caption also for documents
#   Location and venue received as message type
#   sendLocation command
#   add attribute for timeout on do execution (similar to polling) --> cmdTimeout - timeout in do_params / Forum msg480844
#   fix for timeout on sent and addtl log - forum msg497239
#   change log levels for deep encoding
#   add summary for fhem commandref
# 1.9 2016-10-06 urlescaped filenames / location send-receive / timeout for send 

#
#   
##############################################################################
# TASKS 
#   
#   allow keyboards in the device api
#   
#   Wait: Look for solution on space at beginning of line --> checked that data is sent correctly to telegram but does not end up in the message
#
##############################################################################
# Ideas / Future
#   
#   Idea: allow literals in msges: U+27F2 - \xe2\x9f\xb2 / Forum msg458794
#
##############################################################################

package main;

use strict;
use warnings;

#use HttpUtils;
use utf8;

use Encode;

# JSON:XS is used here normally
use JSON; 

use File::Basename;

use URI::Escape;

use Scalar::Util qw(reftype looks_like_number);

#########################
# Forward declaration
sub TelegramBot_Define($$);
sub TelegramBot_Undef($$);

sub TelegramBot_Set($@);
sub TelegramBot_Get($@);

sub TelegramBot_Callback($$$);
sub TelegramBot_SendIt($$$$$;$$);
sub TelegramBot_checkAllowedPeer($$$);

sub TelegramBot_SplitFavoriteDef($$);

sub TelegramBot_GetUTF8Back( $ );
sub TelegramBot_PutToUTF8( $ );

#########################
# Globals
my %sets = (
  "message" => "textField",
  "msg" => "textField",
  "send" => "textField",

  "sendImage" => "textField",
  "sendPhoto" => "textField",

  "sendDocument" => "textField",
  "sendMedia" => "textField",
  "sendVoice" => "textField",

  "sendLocation" => "textField",

  "replaceContacts" => "textField",
  "reset" => undef,

  "reply" => "textField",

  "zDebug" => "textField"

);

my %deprecatedsets = (

  "image" => "textField",   
  "sendPhoto" => "textField",   
);

my %gets = (
  "urlForFile" => "textField"
);

my $TelegramBot_header = "agent: TelegramBot/1.0\r\nUser-Agent: TelegramBot/1.0\r\nAccept: application/json\r\nAccept-Charset: utf-8";


my %TelegramBot_hu_upd_params = (
                  url        => "",
                  timeout    => 5,
                  method     => "GET",
                  header     => $TelegramBot_header,
                  isPolling  => "update",
                  hideurl    => 1,
                  callback   => \&TelegramBot_Callback
);

my %TelegramBot_hu_do_params = (
                  url        => "",
                  timeout    => 30,
                  method     => "GET",
                  header     => $TelegramBot_header,
                  hideurl    => 1,
                  callback   => \&TelegramBot_Callback
);


##############################################################################
##############################################################################
##
## Module operation
##
##############################################################################
##############################################################################

#####################################
# Initialize is called from fhem.pl after loading the module
#  define functions and attributed for the module and corresponding devices

sub TelegramBot_Initialize($) {
  my ($hash) = @_;

  require "$attr{global}{modpath}/FHEM/DevIo.pm";

  $hash->{DefFn}      = "TelegramBot_Define";
  $hash->{UndefFn}    = "TelegramBot_Undef";
  $hash->{StateFn}    = "TelegramBot_State";
  $hash->{GetFn}      = "TelegramBot_Get";
  $hash->{SetFn}      = "TelegramBot_Set";
  $hash->{AttrFn}     = "TelegramBot_Attr";
  $hash->{AttrList}   = "defaultPeer defaultPeerCopy:0,1 cmdKeyword cmdSentCommands favorites:textField-long cmdFavorites cmdRestrictedPeer ". "cmdTriggerOnly:0,1 saveStateOnContactChange:1,0 maxFileSize maxReturnSize cmdReturnEmptyResult:1,0 pollingVerbose:1_Digest,2_Log,0_None ".
  "cmdTimeout pollingTimeout ".
  "allowUnknownContacts:1,0 textResponseConfirm:textField textResponseCommands:textField allowedCommands filenameUrlEscape:1,0 ". 
  "textResponseFavorites:textField textResponseResult:textField textResponseUnauthorized:textField ".
  " maxRetries:0,1,2,3,4,5 ".$readingFnAttributes;           
}


######################################
#  Define function is called for actually defining a device of the corresponding module
#  For TelegramBot this is mainly API id for the bot
#  data will be stored in the hash of the device as internals
#  
sub TelegramBot_Define($$) {
  my ($hash, $def) = @_;
  my @a = split("[ \t]+", $def);
  my $name = $hash->{NAME};

  Log3 $name, 3, "TelegramBot_Define $name: called ";

  my $errmsg = '';
  
  # Check parameter(s)
  if( int(@a) != 3 ) {
    $errmsg = "syntax error: define <name> TelegramBot <APIid> ";
    Log3 $name, 1, "TelegramBot $name: " . $errmsg;
    return $errmsg;
  }
  
  if ( $a[2] =~ /^([[:alnum:]]|[-:_])+[[:alnum:]]+([[:alnum:]]|[-:_])+$/ ) {
    $hash->{Token} = $a[2];
  } else {
    $errmsg = "specify valid API token containing only alphanumeric characters and -: characters: define <name> TelegramBot  <APItoken> ";
    Log3 $name, 1, "TelegramBot $name: " . $errmsg;
    return $errmsg;
  }
  
  my $ret;
  
  $hash->{TYPE} = "TelegramBot";

  $hash->{STATE} = "Undefined";

  $hash->{WAIT} = 0;
  $hash->{FAILS} = 0;
  $hash->{UPDATER} = 0;
  $hash->{POLLING} = -1;

  $hash->{HU_UPD_PARAMS} = \%TelegramBot_hu_upd_params;
  $hash->{HU_DO_PARAMS} = \%TelegramBot_hu_do_params;

  TelegramBot_Setup( $hash );

  return $ret; 
}

#####################################
#  Undef function is corresponding to the delete command the opposite to the define function 
#  Cleanup the device specifically for external ressources like connections, open files, 
#    external memory outside of hash, sub processes and timers
sub TelegramBot_Undef($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 3, "TelegramBot_Undef $name: called ";

  HttpUtils_Close(\%TelegramBot_hu_upd_params); 
  
  HttpUtils_Close(\%TelegramBot_hu_do_params); 

  RemoveInternalTimer($hash);

  RemoveInternalTimer(\%TelegramBot_hu_do_params);

  Log3 $name, 4, "TelegramBot_Undef $name: done ";
  return undef;
}

##############################################################################
##############################################################################
##
## Instance operational methods
##
##############################################################################
##############################################################################


####################################
# State function to ensure contacts internal hash being reset on Contacts Readings Set
sub TelegramBot_State($$$$) {
  my ($hash, $time, $name, $value) = @_; 
  
#  Log3 $hash->{NAME}, 4, "TelegramBot_State called with :$name: value :$value:";

  if ($name eq 'Contacts')  {
    TelegramBot_CalcContactsHash( $hash, $value );
    Log3 $hash->{NAME}, 4, "TelegramBot_State Contacts hash has now :".scalar(keys %{$hash->{Contacts}}).":";
  }
  
  return undef;
}
 
####################################
# set function for executing set operations on device
sub TelegramBot_Set($@)
{
  my ( $hash, $name, @args ) = @_;
  
  Log3 $name, 4, "TelegramBot_Set $name: called ";

  ### Check Args
  my $numberOfArgs  = int(@args);
  return "TelegramBot_Set: No cmd specified for set" if ( $numberOfArgs < 1 );

  my $cmd = shift @args;

  Log3 $name, 4, "TelegramBot_Set $name: Processing TelegramBot_Set( $cmd )";

  if (!exists($sets{$cmd}))  {
    my @cList;
    foreach my $k (keys %sets) {
      my $opts = undef;
      $opts = $sets{$k};

      if (defined($opts)) {
        push(@cList,$k . ':' . $opts);
      } else {
        push (@cList,$k);
      }
    } # end foreach

    return "TelegramBot_Set: Unknown argument $cmd, choose one of " . join(" ", @cList);
  } # error unknown cmd handling

  my $ret = undef;
  
  if( ($cmd eq 'message') || ($cmd eq 'msg') || ($cmd eq 'reply') || ($cmd =~ /^send.*/ ) ) {

    my $msgid;
    
    if ($cmd eq 'reply') {
      return "TelegramBot_Set: Command $cmd, no peer, msgid and no text/file specified" if ( $numberOfArgs < 3 );
      $msgid = shift @args; 
      $numberOfArgs--;
    }
    
    return "TelegramBot_Set: Command $cmd, no peers and no text/file specified" if ( $numberOfArgs < 2 );

    my $sendType = 0;
    
    my $peers;
    while ( $args[0] =~ /^@(..+)$/ ) {
      my $ppart = $1;
      return "TelegramBot_Set: Command $cmd, need exactly one peer" if ( ($cmd eq 'reply') && ( defined( $peers ) ) );
      $peers .= " " if ( defined( $peers ) );
      $peers = "" if ( ! defined( $peers ) );
      $peers .= $ppart;
      
      shift @args;
      $numberOfArgs--;
      last if ( $numberOfArgs == 0 );
    }
    
    return "TelegramBot_Set: Command $cmd, no text/file specified" if ( $numberOfArgs < 2 );

    if ( ! defined( $peers ) ) {
      $peers = AttrVal($name,'defaultPeer',undef);
      return "TelegramBot_Set: Command $cmd, without explicit peer requires defaultPeer being set" if ( ! defined($peers) );
    }
    if ( ($cmd eq 'sendPhoto') || ($cmd eq 'sendImage') || ($cmd eq 'image') ) {
      $sendType = 1;
    } elsif ($cmd eq 'sendVoice')  {
      $sendType = 2;
    } elsif ( ($cmd eq 'sendDocument') || ($cmd eq 'sendMedia') ) {
      $sendType = 3;
    } elsif ($cmd eq 'sendLocation')  {
      $sendType = 10;
    }

    my $msg;
    my $addPar;
    
    if ( $sendType >= 10 ) {
      # location
      
      return "TelegramBot_Set: Command $cmd, 2 parameters latitude / longitude need to be specified" if ( int(@args) != 2 );      

      # first latitude
      $msg = shift @args;

      # first latitude
      $addPar = shift @args;
      
    } elsif ( $sendType > 0 ) {
      # should return undef if succesful
      $msg = shift @args;
      $msg = $1 if ( $msg =~ /^\"(.*)\"$/ );

      if ( $sendType == 1 ) {
        # for Photos a caption can be given
        $addPar = join(" ", @args ) if ( int(@args) > 0 );
      } else {
        return "TelegramBot_Set: Command $cmd, extra parameter specified after filename" if ( int(@args) > 0 );
      }
    } else {
      $msg = join(" ", @args );
    }
      
    Log3 $name, 5, "TelegramBot_Set $name: start send for cmd :$cmd: and sendType :$sendType:";
    $ret = TelegramBot_SendIt( $hash, $peers, $msg, $addPar, $sendType, $msgid );

  } elsif($cmd eq 'zDebug') {
    # for internal testing only
    Log3 $name, 5, "TelegramBot_Set $name: start debug option ";
#    delete $hash->{sentMsgPeer};
    $ret = TelegramBot_SendIt( $hash, AttrVal($name,'defaultPeer',undef), "abc     def\n   def    ghi", undef, 0, undef );

    
  # BOTONLY
  } elsif($cmd eq 'reset') {
    Log3 $name, 5, "TelegramBot_Set $name: reset requested ";
    TelegramBot_Setup( $hash );

  } elsif($cmd eq 'replaceContacts') {
    if ( $numberOfArgs < 2 ) {
      return "TelegramBot_Set: Command $cmd, need to specify contacts string separate by space and contacts in the form of <id>:<full_name>:[@<username>|#<groupname>] ";
    }
    my $arg = join(" ", @args );
    Log3 $name, 3, "TelegramBot_Set $name: set new contacts to :$arg: ";
    # first set the hash accordingly
    TelegramBot_CalcContactsHash($hash, $arg);

    # then calculate correct string reading and put this into the reading
    my @dumarr;
    
    TelegramBot_ContactUpdate($hash, @dumarr);

    Log3 $name, 5, "TelegramBot_Set $name: contacts newly set ";

  }

  if ( ! defined( $ret ) ) {
    Log3 $name, 5, "TelegramBot_Set $name: $cmd done succesful: ";
  } else {
    Log3 $name, 5, "TelegramBot_Set $name: $cmd failed with :$ret: ";
  }
  return $ret
}

#####################################
# get function for gaining information from device
sub TelegramBot_Get($@)
{
  my ( $hash, $name, @args ) = @_;
  
  Log3 $name, 5, "TelegramBot_Get $name: called ";

  ### Check Args
  my $numberOfArgs  = int(@args);
  return "TelegramBot_Get: No value specified for get" if ( $numberOfArgs < 1 );

  my $cmd = $args[0];
  my $arg = ($args[1] ? $args[1] : "");

  Log3 $name, 5, "TelegramBot_Get $name: Processing TelegramBot_Get( $cmd )";

  if(!exists($gets{$cmd})) {
    my @cList;
    foreach my $k (sort keys %gets) {
      my $opts = undef;
      $opts = $sets{$k};

      if (defined($opts)) {
        push(@cList,$k . ':' . $opts);
      } else {
        push (@cList,$k);
      }
    } # end foreach

    return "TelegramBot_Get: Unknown argument $cmd, choose one of " . join(" ", @cList);
  } # error unknown cmd handling

  
  my $ret = undef;
  
  if($cmd eq 'urlForFile') {
    if ( $numberOfArgs != 2 ) {
      return "TelegramBot_Get: Command $cmd, no file id specified";
    }

    $hash->{fileUrl} = "";
    
    # return URL for file id
    my $url = $hash->{URL}."getFile?file_id=".urlEncode($arg);
    my $guret = TelegramBot_DoUrlCommand( $hash, $url );

    if ( ( defined($guret) ) && ( ref($guret) eq "HASH" ) ) {
      if ( defined($guret->{file_path} ) ) {
        # URL is https://api.telegram.org/file/bot<token>/<file_path>
        my $filePath = $guret->{file_path};
        $hash->{fileUrl} = "https://api.telegram.org/file/bot".$hash->{Token}."/".$filePath;
        $ret = $hash->{fileUrl};
      } else {
        $ret = "urlForFile failed: no file path found";
        $hash->{fileUrl} = $ret;
      }      

    } else {
      $ret = "urlForFile failed: ".(defined($guret)?$guret:"<undef>");
      $hash->{fileUrl} = $ret;
    }

  }
  
  Log3 $name, 5, "TelegramBot_Get $name: done with $ret: ";

  return $ret
}

##############################
# attr function for setting fhem attributes for the device
sub TelegramBot_Attr(@) {
  my ($cmd,$name,$aName,$aVal) = @_;
  my $hash = $defs{$name};

  Log3 $name, 5, "TelegramBot_Attr $name: called ";

  return "\"TelegramBot_Attr: \" $name does not exist" if (!defined($hash));

  if (defined($aVal)) {
    Log3 $name, 5, "TelegramBot_Attr $name: $cmd  on $aName to $aVal";
  } else {
    Log3 $name, 5, "TelegramBot_Attr $name: $cmd  on $aName to <undef>";
  }
  # $cmd can be "del" or "set"
  # $name is device name
  # aName and aVal are Attribute name and value
  if ($cmd eq "set") {
    if ($aName eq 'favorites') {
      $attr{$name}{'favorites'} = $aVal;

      # Empty current alias list in hash
      if ( defined( $hash->{AliasCmds} ) ) {
        foreach my $key (keys %{$hash->{AliasCmds}} )
            {
                delete $hash->{AliasCmds}{$key};
            }
      } else {
        $hash->{AliasCmds} = {};
      }

      my @clist = split( /;/, $aVal);

      foreach my $cs (  @clist ) {
        my ( $alias, $desc, $parsecmd, $needsConfirm ) = TelegramBot_SplitFavoriteDef( $hash, $cs );
        if ( $alias ) {
          my $alx = $alias;
          my $alcmd = $parsecmd;
          
          Log3 $name, 2, "TelegramBot_Attr $name: Alias $alcmd defined multiple times" if ( defined( $hash->{AliasCmds}{$alx} ) );
          $hash->{AliasCmds}{$alx} = $alcmd;
        }
      }

    } elsif ($aName eq 'cmdRestrictedPeer') {
      $aVal =~ s/^\s+|\s+$//g;
      
    } elsif ( ($aName eq 'defaultPeerCopy') ||
              ($aName eq 'saveStateOnContactChange') ||
              ($aName eq 'cmdReturnEmptyResult') ||
              ($aName eq 'cmdTriggerOnly') ||
              ($aName eq 'allowUnknownContacts') ) {
      $aVal = ($aVal eq "1")? "1": "0";

    } elsif ( ($aName eq 'maxFileSize') ||
              ($aName eq 'maxReturnSize') ||
              ($aName eq 'maxRetries') ) {
      return "\"TelegramBot_Attr: \" $aName needs to be given in digits only" if ( $aVal !~ /^[[:digit:]]+$/ );

    } elsif ($aName eq 'pollingTimeout') {
      return "\"TelegramBot_Attr: \" $aName needs to be given in digits only" if ( $aVal !~ /^[[:digit:]]+$/ );
      # let all existing methods run into block
      RemoveInternalTimer($hash);
      $hash->{POLLING} = -1;
      
      # wait some time before next polling is starting
      TelegramBot_ResetPolling( $hash );

    } elsif ($aName eq 'pollingVerbose') {
      return "\"TelegramBot_Attr: \" Incorrect value given for pollingVerbose" if ( $aVal !~ /^((1_Digest)|(2_Log)|(0_None))$/ );

    } elsif ($aName eq 'allowedCommands') {
      my $allowedName = "allowed_$name";
      my $exists = ($defs{$allowedName} ? 1 : 0); 
      AnalyzeCommand(undef, "defmod $allowedName allowed");
      AnalyzeCommand(undef, "attr $allowedName validFor $name");
      AnalyzeCommand(undef, "attr $allowedName $aName ".$aVal);
      Log3 $name, 3, "TelegramBot_Attr $name: ".($exists ? "modified":"created")." $allowedName with commands :$aVal:";
      # allowedCommands only set on the corresponding allowed_device
      return "\"TelegramBot_Attr: \" $aName ".($exists ? "modified":"created")." $allowedName with commands :$aVal:"

    }

    $_[3] = $aVal;
  
  }

  return undef;
}


##############################################################################
##############################################################################
##
## Command handling
##
##############################################################################
##############################################################################

#####################################
#####################################
# INTERNAL: Check against cmdkeyword given (no auth check !!!!)
sub TelegramBot_checkCmdKeyword($$$$$) {
  my ($hash, $mpeernorm, $mtext, $cmdKey, $needsSep ) = @_;
  my $name = $hash->{NAME};

  my $cmd;
  my $doRet = 0;
  
#  Log3 $name, 3, "TelegramBot_checkCmdKeyword $name: check :".$mtext.":   against defined :".$ck.":   results in ".index($mtext,$ck);

  return ( undef, 0 ) if ( ! defined( $cmdKey ) );

  # Trim and then if requested add a space to the cmdKeyword
  $cmdKey =~ s/^\s+|\s+$//g;
  
  my $ck = $cmdKey;
  # Check special case end of messages considered separator
  if ( $mtext ne $ck ) { 
    $ck .= " " if ( $needsSep );
    return ( undef, 0 )  if ( index($mtext,$ck) != 0 );
  }

  $cmd = substr( $mtext, length($ck) );
  $cmd =~ s/^\s+|\s+$//g;

  # validate security criteria for commands and return cmd only if succesful
  return ( undef, 1 )  if ( ! TelegramBot_checkAllowedPeer( $hash, $mpeernorm, $mtext ) );

  return ( $cmd, 1 );
}
    

#####################################
#####################################
# INTERNAL: Split Favorite def in alias(optional), description (optional), parsecmd, needsConfirm
sub TelegramBot_SplitFavoriteDef($$) {
  my ($hash, $cmd ) = @_;
  my $name = $hash->{NAME};

  # Valid favoritedef
  #   list TYPE=SOMFY
  #   ?set TYPE=CUL_WM getconfig
  #   /rolladen=list TYPE=SOMFY
  #   /rolladen=?list TYPE=SOMFY
  
  #   /[Liste Rolladen]=list TYPE=SOMFY
  #   /[Liste Rolladen]=?list TYPE=SOMFY
  #   /rolladen[Liste Rolladen]=list TYPE=SOMFY
  #   /rolladen[Liste Rolladen]=list TYPE=SOMFY
  
  my ( $alias, $desc, $parsecmd, $confirm );

  if ( $cmd =~ /^\s*((\/[^\[=]*)?(\[([^\]]+)\])?=)?(\??)(.*?)$/ ) {
    $alias = $2;
    $alias = undef if ( $alias && ( $alias eq "/" ) );
    $desc = $4;
    $confirm = $5;
    $parsecmd = $6;
#    Debug "Parse 1  a:".$alias.":  d:".$desc.":  c:".$parsecmd.":";
  } else {
    Log3 $name, 1, "TelegramBot_SplitFavoriteDef invalid favorite definition :$cmd: ";
  }
  
  return ( $alias, $desc, $parsecmd, (($confirm eq "?")?1:0) );
}
    
#####################################
#####################################
# INTERNAL: handle sentlast and favorites
sub TelegramBot_SentFavorites($$$$) {
  my ($hash, $mpeernorm, $cmd, $mid ) = @_;
  my $name = $hash->{NAME};

  my $ret;
  
  Log3 $name, 4, "TelegramBot_SentFavorites cmd correct peer ";

  my $slc =  AttrVal($name,'favorites',"");
#  Log3 $name, 5, "TelegramBot_SentFavorites Favorites :$slc: ";
  
  my @clist = split( /;/, $slc);
  my $isConfirm;
  
  if ( $cmd =~ /^\s*([0-9]+)(\??)\s*=.*$/ ) {
    $cmd = $1;
    $isConfirm = ($2 eq "?")?1:0; 
  }
  
  # if given a number execute the numbered favorite as a command
  if ( looks_like_number( $cmd ) ) {
    return $ret if ( $cmd == 0 );
    my $cmdId = ($cmd-1);
    Log3 $name, 4, "TelegramBot_SentFavorites exec cmd :$cmdId: ";
    if ( ( $cmdId >= 0 ) && ( $cmdId < scalar( @clist ) ) ) { 
      my $ecmd = $clist[$cmdId];
      
      my ( $alias, $desc, $parsecmd, $needsConfirm ) = TelegramBot_SplitFavoriteDef( $hash, $ecmd );
      return "Alias could not be parsed :$ecmd:" if ( ! $parsecmd );

      $ecmd = $parsecmd;
      
#      Debug "Needsconfirm: ". $needsConfirm;
      
      if ( ( ! $isConfirm ) && ( $needsConfirm ) ) {
        # ask first for confirmation
        my $fcmd = AttrVal($name,'cmdFavorites',undef);
        
        my @tmparr;
        my @keys = ();
#        my @tmparr1 = ( TelegramBot_PutToUTF8( $fcmd.$cmd."? = ".(($desc)?$desc:$parsecmd)." ausführen?" ) );
#        my @tmparr1 = ( $fcmd.$cmd."? = ".(($desc)?$desc:$parsecmd)." ausführen?" );
#        my $tmptxt = encode_utf8( $fcmd.$cmd."? = ".(($desc)?$desc:$parsecmd)." ausführen?" );
        my $tmptxt = $fcmd.$cmd."? = ".(($desc)?$desc:$parsecmd).encode_utf8( " ausführen?" );
#        my $tmptxt = $fcmd.$cmd."? = ".(($desc)?$desc:$parsecmd);
#        Debug "tmptxt :$tmptxt:";
        #        utf8::upgrade($tmptxt);
#        $tmptxt = TelegramBot_PutToUTF8($tmptxt);
#        $tmptxt = decode_utf8($tmptxt);
        my @tmparr1 = ( $tmptxt );
        push( @keys, \@tmparr1 );
        my @tmparr2 = ( "Abbruch" );
        push( @keys, \@tmparr2 );

        my $jsonkb = TelegramBot_MakeKeyboard( $hash, 1, @keys );

        # LOCAL: External message
        $ret = encode_utf8( AttrVal( $name, 'textResponseConfirm', 'TelegramBot FHEM : $peer\n Bestätigung \n') );
        $ret =~ s/\$peer/$mpeernorm/g;
#        $ret = "TelegramBot FHEM : ($mpeernorm)\n Bestätigung \n";
        
        return TelegramBot_SendIt( $hash, $mpeernorm, $ret, $jsonkb, 0 );
        
      } else {
        $ecmd = $1 if ( $ecmd =~ /^\s*\?(.*)$/ );
        return TelegramBot_ExecuteCommand( $hash, $mpeernorm, $ecmd );
      }
    } else {
      Log3 $name, 3, "TelegramBot_SentFavorites cmd id not defined :($cmdId+1): ";
    }
  }
  
  # ret not defined means no favorite found that matches cmd or no fav given in cmd
  if ( ! defined( $ret ) ) {
      my $cnt = 0;
      my @keys = ();

      my $fcmd = AttrVal($name,'cmdFavorites',undef);
      
      foreach my $cs (  @clist ) {
        $cnt += 1;
        my ( $alias, $desc, $parsecmd, $needsConfirm ) = TelegramBot_SplitFavoriteDef( $hash, $cs );
        if ( defined($parsecmd) ) { 
          my @tmparr = ( $fcmd.$cnt." = ".($alias?$alias." = ":"").(($desc)?$desc:$parsecmd) );
          push( @keys, \@tmparr );
        }
      }
#      my @tmparr = ( $fcmd."0 = Abbruch" );
#     push( @keys, \@tmparr );

      my $jsonkb = TelegramBot_MakeKeyboard( $hash, 1, @keys );

      Log3 $name, 5, "TelegramBot_SentFavorites keyboard:".$jsonkb.": ";
      
      # LOCAL: External message
      $ret = AttrVal( $name, 'textResponseFavorites', 'TelegramBot FHEM : $peer\n Favoriten \n');
      $ret =~ s/\$peer/$mpeernorm/g;
#      $ret = "TelegramBot FHEM : ($mpeernorm)\n Favorites \n";
      
      $ret = TelegramBot_SendIt( $hash, $mpeernorm, $ret, $jsonkb, 0 );
  
  }
  return $ret;
  
}

  
#####################################
#####################################
# INTERNAL: handle sentlast and favorites
sub TelegramBot_SentLastCommand($$$) {
  my ($hash, $mpeernorm, $cmd ) = @_;
  my $name = $hash->{NAME};

  my $ret;
  
  Log3 $name, 5, "TelegramBot_SentLastCommand cmd correct peer ";

  my $slc =  ReadingsVal($name ,"StoredCommands","");

  my @cmds = split( "\n", $slc );

  # create keyboard
  my @keys = ();

  foreach my $cs (  @cmds ) {
    my @tmparr = ( $cs );
    push( @keys, \@tmparr );
  }
#  my @tmparr = ( $fcmd."0 = Abbruch" );
#  push( @keys, \@tmparr );

  my $jsonkb = TelegramBot_MakeKeyboard( $hash, 1, @keys );

  # LOCAL: External message
  $ret = AttrVal( $name, 'textResponseCommands', 'TelegramBot FHEM : $peer\n Letzte Befehle \n');
  $ret =~ s/\$peer/$mpeernorm/g;
  #  $ret = "TelegramBot FHEM : $mpeernorm \n Last Commands \n";
  
  # overwrite ret with result from SendIt --> send response
  $ret = TelegramBot_SendIt( $hash, $mpeernorm, $ret, $jsonkb, 0 );

############ OLD SentLastCommands sent as message   
#  $ret = "TelegramBot fhem  : $mpeernorm \nLast Commands \n\n".$slc;
  
#  # overwrite ret with result from Analyzecommand --> send response
#  $ret = AnalyzeCommand( undef, "set $name message \@$mpeernorm $ret", "" );

  return $ret;
}

  
#####################################
#####################################
# INTERNAL: execute command and sent return value 
sub TelegramBot_ReadHandleCommand($$$$) {
  my ($hash, $mpeernorm, $cmd, $mtext ) = @_;
  my $name = $hash->{NAME};

  my $ret;
  
  Log3 $name, 3, "TelegramBot_ReadHandleCommand $name: cmd found :".$cmd.": ";
  
  # get human readble name for peer
  my $pname = TelegramBot_GetFullnameForContact( $hash, $mpeernorm );

  Log3 $name, 5, "TelegramBot_ReadHandleCommand cmd correct peer ";
  # Either no peer defined or cmdpeer matches peer for message -> good to execute
  my $cto = AttrVal($name,'cmdTriggerOnly',"0");
  if ( $cto eq '1' ) {
    $cmd = "trigger ".$cmd;
  }
  
  Log3 $name, 5, "TelegramBot_ReadHandleCommand final cmd for analyze :".$cmd.": ";

  # store last commands (original text)
  TelegramBot_AddStoredCommands( $hash, $mtext );

  $ret = TelegramBot_ExecuteCommand( $hash, $mpeernorm, $cmd );

  return $ret;
}

  
#####################################
#####################################
# INTERNAL: execute command and sent return value 
sub TelegramBot_ExecuteCommand($$$) {
  my ($hash, $mpeernorm, $cmd ) = @_;
  my $name = $hash->{NAME};

  my $ret;
  
  # get human readble name for peer
  my $pname = TelegramBot_GetFullnameForContact( $hash, $mpeernorm );

  Log3 $name, 5, "TelegramBot_ExecuteCommand final cmd for analyze :".$cmd.": ";

  # special case shutdown caught here to avoid endless loop
  $ret = "shutdown command can not be executed" if ( $cmd =~ /^shutdown/ );
  
  # Execute command
  my $isMediaStream = 0;
  
  if ( ! defined( $ret ) ) {
    $ret = AnalyzeCommand( $hash, $cmd );

    # Check for image/doc/audio stream in return (-1 image
    ( $isMediaStream ) = TelegramBot_IdentifyStream( $hash, $ret ) if ( defined( $ret ) );
    
  }

  Log3 $name, 5, "TelegramBot_ExecuteCommand result for analyze :".TelegramBot_MsgForLog($ret, $isMediaStream ).": ";

  my $defpeer = AttrVal($name,'defaultPeer',undef);
  $defpeer = TelegramBot_GetIdForPeer( $hash, $defpeer ) if ( defined( $defpeer ) );
  $defpeer = AttrVal($name,'defaultPeer',undef) if ( ! defined( $defpeer ) );
  $defpeer = undef if ( $defpeer eq $mpeernorm );
  
  # LOCAL: External message
  my $retMsg = AttrVal( $name, 'textResponseResult', 'TelegramBot FHEM : $peer\n    Befehl:$cmd:\n  Ergebnis:\n$result \n ');
  $retMsg =~ s/\$cmd/$cmd/g;
  
  if ( defined( $defpeer ) ) {
    $retMsg =~ s/\$peer/$pname/g;
  } else {
    $retMsg =~ s/\$peer//g;
  }

  if ( ( ! defined( $ret ) ) || ( length( $ret) == 0 ) ) {
    $retMsg =~ s/\$result/OK/g;
    $ret = $retMsg if ( AttrVal($name,'cmdReturnEmptyResult',1) );
  } elsif ( ! $isMediaStream ) {
    $retMsg =~ s/\$result/$ret/g;
    $ret = $retMsg;
  }

#  my $retstart = "TelegramBot FHEM";
#  $retstart .= " from $pname ($mpeernorm)" if ( defined( $defpeer ) );
  
#  my $retempty = AttrVal($name,'cmdReturnEmptyResult',1);

  # undef is considered ok
#  if ( ( ! defined( $ret ) ) || ( length( $ret) == 0 ) ) {
#    # : External message
#    $ret = "$retstart cmd :$cmd: result OK" if ( $retempty );
#  } elsif ( ! $isMediaStream ) {
#    $ret = "$retstart cmd :$cmd: result :$ret:";
# }
  Log3 $name, 5, "TelegramBot_ExecuteCommand $name: ".TelegramBot_MsgForLog($ret, $isMediaStream ).": ";
  
  if ( ( defined( $ret ) ) && ( length( $ret) != 0 ) ) {
    if ( ! $isMediaStream ) {
      # replace line ends with spaces
      $ret =~ s/\r//gm;
      
      # shorten to maxReturnSize if set
      my $limit = AttrVal($name,'maxReturnSize',4000);

      if ( ( length($ret) > $limit ) && ( $limit != 0 ) ) {
        $ret = substr( $ret, 0, $limit )."\n \n ...";
      }

      $ret =~ s/\n/\\n/gm;
    }

    my $peers = $mpeernorm;

    my $dpc = AttrVal($name,'defaultPeerCopy',1);
    $peers .= " ".$defpeer if ( ( $dpc ) && ( defined( $defpeer ) ) );

    # Ignore result from sendIt here
    my $retsend = TelegramBot_SendIt( $hash, $peers, $ret, undef, $isMediaStream ); 
    
    # ensure return is not a stream (due to log handling)
    $ret = TelegramBot_MsgForLog($ret, $isMediaStream )
  }
  
  return $ret;
}

######################################
#  add a command to the StoredCommands reading 
#  hash, cmd
sub TelegramBot_AddStoredCommands($$) {
  my ($hash, $cmd) = @_;
 
  my $stcmds = ReadingsVal($hash->{NAME},"StoredCommands","");
  $stcmds = $stcmds;

  if ( $stcmds !~ /^\Q$cmd\E$/m ) {
    # add new cmd
    $stcmds .= $cmd."\n";
    
    # check number lines 
    my $num = ( $stcmds =~ tr/\n// );
    if ( $num > 10 ) {
      $stcmds =~ /^[^\n]+\n(.*)$/s;
      $stcmds = $1;
    }

    # change reading  
    readingsSingleUpdate($hash, "StoredCommands", $stcmds , 1); 
    Log3 $hash->{NAME}, 4, "TelegramBot_AddStoredCommands :$stcmds: ";
  }
 
}
    
#####################################
# INTERNAL: Function to check for commands in messages 
# Always executes and returns on first match also in case of error 
sub Telegram_HandleCommandInMessages($$$$)
{
  my ( $hash, $mpeernorm, $mtext, $mid ) = @_;
  my $name = $hash->{NAME};

  my $cmdRet;
  my $cmd;
  my $doRet;

  # trim whitespace from message text
  $mtext =~ s/^\s+|\s+$//g;

  #### Check authorization for cmd execution is done inside checkCmdKeyword
  
  # Check for cmdKeyword in msg
  ( $cmd, $doRet ) = TelegramBot_checkCmdKeyword( $hash, $mpeernorm, $mtext, AttrVal($name,'cmdKeyword',undef), 1 );
  if ( defined( $cmd ) ) {
    $cmdRet = TelegramBot_ReadHandleCommand( $hash, $mpeernorm, $cmd, $mtext );
    Log3 $name, 4, "TelegramBot_ParseMsg $name: ReadHandleCommand returned :$cmdRet:" if ( defined($cmdRet) );
    return;
  } elsif ( $doRet ) {
    return;
  }
  
  # Check for sentCommands Keyword in msg
  ( $cmd, $doRet ) = TelegramBot_checkCmdKeyword( $hash, $mpeernorm, $mtext, AttrVal($name,'cmdSentCommands',undef), 1 );
  if ( defined( $cmd ) ) {
    $cmdRet = TelegramBot_SentLastCommand( $hash, $mpeernorm, $cmd );
    Log3 $name, 4, "TelegramBot_ParseMsg $name: SentLastCommand returned :$cmdRet:" if ( defined($cmdRet) );
    return;
  } elsif ( $doRet ) {
    return;
  }
    
  # Check for favorites Keyword in msg
  ( $cmd, $doRet ) = TelegramBot_checkCmdKeyword( $hash, $mpeernorm, $mtext, AttrVal($name,'cmdFavorites',undef), 0 );
  if ( defined( $cmd ) ) {
    $cmdRet = TelegramBot_SentFavorites( $hash, $mpeernorm, $cmd, $mid );
    Log3 $name, 4, "TelegramBot_ParseMsg $name: SentFavorites returned :$cmdRet:" if ( defined($cmdRet) );
    return;
  } elsif ( $doRet ) {
    return;
  }

  # Check for favorite aliase in msg - execute command then
  if ( defined( $hash->{AliasCmds} ) ) {
    foreach my $aliasKey (keys %{$hash->{AliasCmds}} ) {
      ( $cmd, $doRet ) = TelegramBot_checkCmdKeyword( $hash, $mpeernorm, $mtext, $aliasKey, 1 );
      if ( defined( $cmd ) ) {
        # Build the final command from the the alias and the remainder of the message
        Log3 $name, 5, "TelegramBot_ParseMsg $name: Alias Match :$aliasKey:";
        $cmd = $hash->{AliasCmds}{$aliasKey}." ".$cmd;
        $cmdRet = TelegramBot_ExecuteCommand( $hash, $mpeernorm, $cmd );
        Log3 $name, 4, "TelegramBot_ParseMsg $name: ExecuteFavoriteCmd returned :$cmdRet:" if ( defined($cmdRet) );
        return;
      } elsif ( $doRet ) {
        return;
      }
    }
  }

  #  ignore result of readhandlecommand since it leads to endless loop
}
  
   
#####################################
# INTERNAL: Function to send a command handle result
# Parameter
#   hash
#   url - url including parameters
#   > returns string in case of error or the content of the result object if ok
sub TelegramBot_DoUrlCommand($$)
{
  my ( $hash, $url ) = @_;
  my $name = $hash->{NAME};

  my $ret;
  
  Log3 $name, 5, "TelegramBot_DoUrlCommand $name: called ";

  my $param = {
                  url        => $url,
                  timeout    => 1,
                  hash       => $hash,
                  method     => "GET",
                  header     => $TelegramBot_header
              };
  my ($err, $data) = HttpUtils_BlockingGet( $param );

  if ( $err ne "" ) {
    # http returned error
    $ret = "FAILED http access returned error :$err:";
    Log3 $name, 2, "TelegramBot_DoUrlCommand $name: ".$ret;
  } else {
    my $jo;
    
    eval {
      $jo = decode_json( $data );
    };

    if ( ! defined( $jo ) ) {
      $ret = "FAILED invalid JSON returned";
      Log3 $name, 2, "TelegramBot_DoUrlCommand $name: ".$ret;
    } elsif ( $jo->{ok} ) {
      $ret = $jo->{result};
      Log3 $name, 4, "TelegramBot_DoUrlCommand OK with result";
    } else {
      my $ret = "FAILED Telegram returned error: ".$jo->{description};
      Log3 $name, 2, "TelegramBot_DoUrlCommand $name: ".$ret;
    }    

  }

  return $ret;
}

  
##############################################################################
##############################################################################
##
## Communication - Send - receive - Parse
##
##############################################################################
##############################################################################

#####################################
# INTERNAL: Function to send a photo (and text message) to a peer and handle result
# addPar is caption for images / keyboard for text / longituted for location (isMedia 10)
sub TelegramBot_SendIt($$$$$;$$)
{
  my ( $hash, @args) = @_;

  my ( $peers, $msg, $addPar, $isMedia, $replyid, $retryCount) = @args;
  my $name = $hash->{NAME};
  
  if ( ! defined( $retryCount ) ) {
    $retryCount = 0;
  }

  # increase retrycount for next try
  $args[5] = $retryCount+1;
  
  Log3 $name, 5, "TelegramBot_SendIt $name: called ";

  # ensure sentQueue exists
  $hash->{sentQueue} = [] if ( ! defined( $hash->{sentQueue} ) );

  if ( ( defined( $hash->{sentMsgResult} ) ) && ( $hash->{sentMsgResult} =~ /^WAITING/ ) && (  $retryCount == 0 ) ){
    # add to queue
    Log3 $name, 4, "TelegramBot_SendIt $name: add send to queue :$peers: -:".
        TelegramBot_MsgForLog($msg, ($isMedia<0) ).": - :".(defined($addPar)?$addPar:"<undef>").":";
    push( @{ $hash->{sentQueue} }, \@args );
    return;
  }  
    
  my $ret;
  $hash->{sentMsgResult} = "WAITING";
  
  $hash->{sentMsgResult} .= " retry $retryCount" if ( $retryCount > 0 );
  
  $hash->{sentMsgId} = "";

  my $peer;
  ( $peer, $peers ) = split( " ", $peers, 2 ); 
  
  # handle addtl peers specified (will be queued since WAITING is set already) 
  if ( defined( $peers ) ) {
    # ignore return, since it is only queued
    TelegramBot_SendIt( $hash, $peers, $msg, $addPar, $isMedia );
  }
  
  Log3 $name, 5, "TelegramBot_SendIt $name: try to send message to :$peer: -:".
      TelegramBot_MsgForLog($msg, ($isMedia<0) ).": - :".(defined($addPar)?$addPar:"<undef>").":";

    # trim and convert spaces in peer to underline 
  my $peer2 = TelegramBot_GetIdForPeer( $hash, $peer );

  if ( ! defined( $peer2 ) ) {
    $ret = "FAILED peer not found :$peer:";
#    Log3 $name, 2, "TelegramBot_SendIt $name: failed with :".$ret.":";
    $peer2 = "";
  }
  
  $hash->{sentMsgPeer} = TelegramBot_GetFullnameForContact( $hash, $peer2 );
  $hash->{sentMsgPeerId} = $peer2;
  
  # init param hash
  $TelegramBot_hu_do_params{hash} = $hash;
  $TelegramBot_hu_do_params{header} = $TelegramBot_header;
  delete( $TelegramBot_hu_do_params{args} );
  delete( $TelegramBot_hu_do_params{boundary} );

  
  my $timeout =   AttrVal($name,'cmdTimeout',30);
  $TelegramBot_hu_do_params{timeout} = $timeout;

  # only for test / debug               
#  $TelegramBot_hu_do_params{loglevel} = 3;

  # handle data creation only if no error so far
  if ( ! defined( $ret ) ) {

    # add chat / user id (no file) --> this will also do init
    $ret = TelegramBot_AddMultipart($hash, \%TelegramBot_hu_do_params, "chat_id", undef, $peer2, 0 );

    if ( ! $isMedia ) {
      $TelegramBot_hu_do_params{url} = $hash->{URL}."sendMessage";
      
#      $TelegramBot_hu_do_params{url} = "http://requestb.in";

      ## JVI
#      Debug "send  org msg  :".$msg.":";
  
      if ( length($msg) > 1000 ) {
        $hash->{sentMsgText} = substr($msg,0, 1000)."...";
       } else {
        $hash->{sentMsgText} = $msg;
       }
      $msg =~ s/(?<![\\])\\n/\x0A/g;
      $msg =~ s/(?<![\\])\\t/\x09/g;

      ## JVI
#      Debug "send conv msg  :".$msg.":";
  
      # add msg (no file)
      $ret = TelegramBot_AddMultipart($hash, \%TelegramBot_hu_do_params, "text", undef, $msg, 0 ) if ( ! defined( $ret ) );
      
    } elsif ( $isMedia == 10 ) {
      # Location send    
      $hash->{sentMsgText} = "Location: ".TelegramBot_MsgForLog($msg, ($isMedia<0) ).
          (( defined( $addPar ) )?" - ".$addPar:"");

      $TelegramBot_hu_do_params{url} = $hash->{URL}."sendLocation";

      $ret = TelegramBot_AddMultipart($hash, \%TelegramBot_hu_do_params, "latitude", undef, $msg, 0 ) if ( ! defined( $ret ) );

      $ret = TelegramBot_AddMultipart($hash, \%TelegramBot_hu_do_params, "longitude", undef, $addPar, 0 ) if ( ! defined( $ret ) );
      $addPar = undef;
      
    } elsif ( abs($isMedia) == 1 ) {
      # Photo send    
      $hash->{sentMsgText} = "Image: ".TelegramBot_MsgForLog($msg, ($isMedia<0) ).
          (( defined( $addPar ) )?" - ".$addPar:"");

      $TelegramBot_hu_do_params{url} = $hash->{URL}."sendPhoto";

      # add caption
      if ( defined( $addPar ) ) {
        $ret = TelegramBot_AddMultipart($hash, \%TelegramBot_hu_do_params, "caption", undef, $addPar, 0 ) if ( ! defined( $ret ) );
        $addPar = undef;
      }
      
      # add msg or file or stream
      Log3 $name, 4, "TelegramBot_SendIt $name: Filename for image file :".
      TelegramBot_MsgForLog($msg, ($isMedia<0) ).":";
      $ret = TelegramBot_AddMultipart($hash, \%TelegramBot_hu_do_params, "photo", undef, $msg, $isMedia ) if ( ! defined( $ret ) );
      
    }  elsif ( $isMedia == 2 ) {
      # Voicemsg send    == 2
      $hash->{sentMsgText} = "Voice: $msg";

      $TelegramBot_hu_do_params{url} = $hash->{URL}."sendVoice";

      # add msg or file or stream
      Log3 $name, 4, "TelegramBot_SendIt $name: Filename for document file :".
      TelegramBot_MsgForLog($msg, ($isMedia<0) ).":";
      $ret = TelegramBot_AddMultipart($hash, \%TelegramBot_hu_do_params, "voice", undef, $msg, 1 ) if ( ! defined( $ret ) );
    } else {
      # Media send    == 3
      $hash->{sentMsgText} = "Document: ".TelegramBot_MsgForLog($msg, ($isMedia<0) );

      $TelegramBot_hu_do_params{url} = $hash->{URL}."sendDocument";

      # add msg (no file)
      Log3 $name, 4, "TelegramBot_SendIt $name: Filename for document file :$msg:";
      $ret = TelegramBot_AddMultipart($hash, \%TelegramBot_hu_do_params, "document", undef, $msg, $isMedia ) if ( ! defined( $ret ) );
    }

    if ( defined( $replyid ) ) {
      $ret = TelegramBot_AddMultipart($hash, \%TelegramBot_hu_do_params, "reply_to_message_id", undef, $replyid, 0 ) if ( ! defined( $ret ) );
    }

    if ( defined( $addPar ) ) {
      $ret = TelegramBot_AddMultipart($hash, \%TelegramBot_hu_do_params, "reply_markup", undef, $addPar, 0 ) if ( ! defined( $ret ) );
    }

    # finalize multipart 
    $ret = TelegramBot_AddMultipart($hash, \%TelegramBot_hu_do_params, undef, undef, undef, 0 ) if ( ! defined( $ret ) );

  }
  
  ## JVI
#  Debug "send command  :".$TelegramBot_hu_do_params{data}.":";
  
  if ( defined( $ret ) ) {
    Log3 $name, 3, "TelegramBot_SendIt $name: Failed with :$ret:";
    TelegramBot_Callback( \%TelegramBot_hu_do_params, $ret, "");

  } else {
    $TelegramBot_hu_do_params{args} = \@args;
    # reset UTF8 flag for ensuring length in httputils is correctly handling lenght (as bytes)
#  Debug "send a command  :".$TelegramBot_hu_do_params{data}.":";
#    $TelegramBot_hu_do_params{data} = encode_utf8(decode_utf8($TelegramBot_hu_do_params{data}));
# Debug "send b command  :".$TelegramBot_hu_do_params{data}.":";
    
    Log3 $name, 4, "TelegramBot_SendIt $name: timeout for sent :".$TelegramBot_hu_do_params{timeout}.": ";
    HttpUtils_NonblockingGet( \%TelegramBot_hu_do_params);

  }
  
  return $ret;
}

#####################################
# INTERNAL: Build a multipart form data in a given hash
# Parameter
#   hash (device hash)
#   params (hash for building up the data)
#   paramname --> if not sepecifed / undef - multipart will be finished
#   header for multipart
#   content 
#   isFile to specify if content is providing a file to be read as content
#     
#   > returns string in case of error or undef
sub TelegramBot_AddMultipart($$$$$$)
{
  my ( $hash, $params, $parname, $parheader, $parcontent, $isMedia ) = @_;
  my $name = $hash->{NAME};

  my $ret;
  
  # Check if boundary is defined
  if ( ! defined( $params->{boundary} ) ) {
    $params->{boundary} = "TelegramBot_boundary-x0123";
    $params->{header} .= "\r\nContent-Type: multipart/form-data; boundary=".$params->{boundary};
    $params->{method} = "POST";
    $params->{data} = "";
  }
  
  # ensure parheader is defined and add final header new lines
  $parheader = "" if ( ! defined( $parheader ) );
  $parheader .= "\r\n" if ( ( length($parheader) > 0 ) && ( $parheader !~ /\r\n$/ ) );

  # add content 
  my $finalcontent;
  if ( defined( $parname ) ) {
    $params->{data} .= "--".$params->{boundary}."\r\n";
    if ( $isMedia > 0) {
      # url decode filename
      $parcontent = uri_unescape($parcontent) if ( AttrVal($name,'filenameUrlEscape',0) );

      my $baseFilename =  basename($parcontent);
      $parheader = "Content-Disposition: form-data; name=\"".$parname."\"; filename=\"".$baseFilename."\"\r\n".$parheader."\r\n";

      return( "FAILED file :$parcontent: not found or empty" ) if ( ! -e $parcontent ) ;
      
      my $size = -s $parcontent;
      my $limit = AttrVal($name,'maxFileSize',10485760);
      return( "FAILED file :$parcontent: is too large for transfer (current limit: ".$limit."B)" ) if ( $size >  $limit ) ;
      
      $finalcontent = TelegramBot_BinaryFileRead( $hash, $parcontent );
      if ( $finalcontent eq "" ) {
        return( "FAILED file :$parcontent: not found or empty" );
      }
    } elsif ( $isMedia < 0) {
      my ( $im, $ext ) = TelegramBot_IdentifyStream( $hash, $parcontent );

      my $baseFilename =  "fhem.".$ext;

      $parheader = "Content-Disposition: form-data; name=\"".$parname."\"; filename=\"".$baseFilename."\"\r\n".$parheader."\r\n";
      $finalcontent = $parcontent;
    } else {
      $parheader = "Content-Disposition: form-data; name=\"".$parname."\"\r\n".$parheader."\r\n";
      $finalcontent = $parcontent;
    }
    $params->{data} .= $parheader.$finalcontent."\r\n";
    
  } else {
    return( "No content defined for multipart" ) if ( length( $params->{data} ) == 0 );
    $params->{data} .= "--".$params->{boundary}."--";     
  }

  return undef;
}


#####################################
# INTERNAL: Build a keyboard string for sendMessage
# Parameter
#   hash (device hash)
#   onetime/hide --> true means onetime / false means hide / undef means nothing
#   keys array of arrays for keyboard
#   > returns string in case of error or undef
sub TelegramBot_MakeKeyboard($$@)
{
  my ( $hash, $onetime_hide, @keys ) = @_;
  my $name = $hash->{NAME};

  my $ret;
  
  my %par;
  
  if ( ( defined( $onetime_hide ) ) && ( ! $onetime_hide ) ) {
    %par = ( "hide_keyboard" => JSON::true );
  } else {
    return $ret if ( ! @keys );
    %par = ( "one_time_keyboard" => (( ( defined( $onetime_hide ) ) && ( $onetime_hide ) )?JSON::true:JSON::true ) );
    $par{keyboard} = \@keys;
  }
  
  my $refkb = \%par;
  
#  $refkb = TelegramBot_Deepencode( $name, $refkb );

#  $ret = encode_json( $refkb );
  my $json        = JSON->new->utf8;
  $ret = $json->utf8(0)->encode( $refkb );
  Log3 $name, 4, "TelegramBot_MakeKeyboard $name: json :$ret: is utf8? ".(utf8::is_utf8($ret)?"yes":"no");

  if ( utf8::is_utf8($ret) ) {
    utf8::downgrade($ret); 
    Log3 $name, 4, "TelegramBot_MakeKeyboard $name: json downgraded :$ret: is utf8? ".(utf8::is_utf8($ret)?"yes":"no");
  }
  
#  Debug "json_keyboard :$ret:";

  return $ret;
}
  

#####################################
#  INTERNAL: _PollUpdate is called to set out a nonblocking http call for updates
#  if still polling return
#  if more than one fails happened --> wait instead of poll
#
sub TelegramBot_UpdatePoll($) 
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
    
  Log3 $name, 5, "TelegramBot_UpdatePoll $name: called ";

  if ( $hash->{POLLING} ) {
    Log3 $name, 4, "TelegramBot_UpdatePoll $name: polling still running ";
    return;
  }

  # Get timeout from attribute 
  my $timeout =   AttrVal($name,'pollingTimeout',0);
  if ( $timeout == 0 ) {
    $hash->{STATE} = "Static";
    Log3 $name, 4, "TelegramBot_UpdatePoll $name: Polling timeout 0 - no polling ";
    return;
  }
  
  if ( $hash->{FAILS} > 1 ) {
    # more than one fail in a row wait until next poll
    $hash->{OLDFAILS} = $hash->{FAILS};
    $hash->{FAILS} = 0;
    my $wait = $hash->{OLDFAILS}+2;
    Log3 $name, 5, "TelegramBot_UpdatePoll $name: got fails :".$hash->{OLDFAILS}.": wait ".$wait." seconds";
    InternalTimer(gettimeofday()+$wait, "TelegramBot_UpdatePoll", $hash,0); 
    return;
  } elsif ( defined($hash->{OLDFAILS}) ) {
    # oldfails defined means 
    $hash->{FAILS} = $hash->{OLDFAILS};
    delete $hash->{OLDFAILS};
  }

  # get next offset id
  my $offset = $hash->{offset_id};
  $offset = 0 if ( ! defined($offset) );
  
  # build url 
  my $url =  $hash->{URL}."getUpdates?offset=".$offset."&limit=5&timeout=".$timeout;

  $TelegramBot_hu_upd_params{url} = $url;
  $TelegramBot_hu_upd_params{timeout} = $timeout+$timeout+5;
  $TelegramBot_hu_upd_params{hash} = $hash;
  $TelegramBot_hu_upd_params{offset} = $offset;

  $hash->{STATE} = "Polling";

  $hash->{POLLING} = ( ( defined( $hash->{OLD_POLLING} ) )?$hash->{OLD_POLLING}:1 );
  Log3 $name, 4, "TelegramBot_UpdatePoll $name: initiate polling with nonblockingGet with ".$timeout."s";
  HttpUtils_NonblockingGet( \%TelegramBot_hu_upd_params); 
}


#####################################
#  INTERNAL: Called to retry a send operation after wait time
#   Gets the do params
sub TelegramBot_RetrySend($)
{
  my ( $param ) = @_;
  my $hash= $param->{hash};
  my $name = $hash->{NAME};


  my $ref = $param->{args};
  Log3 $name, 4, "TelegramBot_Retrysend $name: reply ".(defined( @$ref[4] )?@$ref[4]:"<undef>")." retry @$ref[5] :@$ref[0]: -:@$ref[1]: ";
  TelegramBot_SendIt( $hash, @$ref[0], @$ref[1], @$ref[2], @$ref[3], @$ref[4], @$ref[5] );
  
}



sub TelegramBot_Deepencode
{
    my @result;

    my $name = shift( @_ );

#    Debug "TelegramBot_Deepencode with :".(@_).":";

    for (@_) {
        my $reftype= ref $_;
        if( $reftype eq "ARRAY" ) {
            Log3 $name, 5, "TelegramBot_Deepencode $name: found an ARRAY";
            push @result, [ TelegramBot_Deepencode($name, @$_) ];
        }
        elsif( $reftype eq "HASH" ) {
            my %h;
            @h{keys %$_}= TelegramBot_Deepencode($name, values %$_);
            Log3 $name, 5, "TelegramBot_Deepencode $name: found a HASH";
            push @result, \%h;
        }
        else {
            my $us = $_ ;
            if ( utf8::is_utf8($us) ) {
              $us = encode_utf8( $_ );
            }
            Log3 $name, 5, "TelegramBot_Deepencode $name: encoded a String from :".$_.": to :".$us.":";
            push @result, $us;
        }
    }
    return @_ == 1 ? $result[0] : @result; 

}
      
  
#####################################
#  INTERNAL: Callback is the callback for any nonblocking call to the bot api (e.g. the long poll on update call)
#   3 params are defined for callbacks
#     param-hash
#     err
#     data (returned from url call)
# empty string used instead of undef for no return/err value
sub TelegramBot_Callback($$$)
{
  my ( $param, $err, $data ) = @_;
  my $hash= $param->{hash};
  my $name = $hash->{NAME};

  my $ret;
  my $result;
  my $msgId;
  my $ll = 5;

  if ( defined( $param->{isPolling} ) ) {
    $hash->{OLD_POLLING} = ( ( defined( $hash->{POLLING} ) )?$hash->{POLLING}:0 ) + 1;
    $hash->{OLD_POLLING} = 1 if ( $hash->{OLD_POLLING} > 255 );
    
    $hash->{POLLING} = 0 if ( $hash->{POLLING} != -1 ) ;
  }
  
  Log3 $name, 5, "TelegramBot_Callback $name: called from ".(( defined( $param->{isPolling} ) )?"Polling":"SendIt");

  # Check for timeout   "read from $hash->{addr} timed out"
  if ( $err =~ /^read from.*timed out$/ ) {
    $ret = "NonBlockingGet timed out on read from ".($param->{hideurl}?"<hidden>":$param->{url})." after ".$param->{timeout}."s";
  } elsif ( $err ne "" ) {
    $ret = "NonBlockingGet: returned $err";
  } elsif ( $data ne "" ) {
    # assuming empty data without err means timeout
    Log3 $name, 5, "TelegramBot_ParseUpdate $name: data returned :$data:";
    my $jo;
 

### mark as latin1 to ensure no conversion is happening (this works surprisingly)
    eval {
#       $data = encode( 'latin1', $data );
       $data = encode_utf8( $data );
#       $data = decode_utf8( $data );
# Debug "-----AFTER------\n".$data."\n-------UC=".${^UNICODE} ."-----\n";
       $jo = decode_json( $data );
       $jo = TelegramBot_Deepencode( $name, $jo );
    };
 

###################### 
 
    if ( $@ ) {
      $ret = "Callback returned no valid JSON: $@ ";
    } elsif ( ! defined( $jo ) ) {
      $ret = "Callback returned no valid JSON !";
    } elsif ( ! $jo->{ok} ) {
      if ( defined( $jo->{description} ) ) {
        $ret = "Callback returned error:".$jo->{description}.":";
      } else {
        $ret = "Callback returned error without description";
      }
    } else {
      if ( defined( $jo->{result} ) ) {
        $result = $jo->{result};
      } else {
        $ret = "Callback returned no result";
      }
    }
  }

  if ( defined( $param->{isPolling} ) ) {
    # Polling means result must be analyzed
    if ( defined($result) ) {
       # handle result
      $hash->{FAILS} = 0;    # succesful UpdatePoll reset fails
      Log3 $name, 5, "UpdatePoll $name: number of results ".scalar(@$result) ;
      foreach my $update ( @$result ) {
        Log3 $name, 5, "UpdatePoll $name: parse result ";
        if ( defined( $update->{message} ) ) {
          
          $ret = TelegramBot_ParseMsg( $hash, $update->{update_id}, $update->{message} );
        }
        if ( defined( $ret ) ) {
          last;
        } else {
          $hash->{offset_id} = $update->{update_id}+1;
        }
      }
    }
    
    # get timestamps and verbose
    my $now = FmtDateTime( gettimeofday() ); 
    my $tst = ReadingsTimestamp( $name, "PollingErrCount", "1970-01-01 01:00:00" );
    my $pv = AttrVal( $name, "pollingVerbose", "1_Digest" );

    # get current error cnt
    my $cnt = ReadingsVal( $name, "PollingErrCount", "0" );

    # flag if log needs to be written
    my $doLog = 0;
    
    # Error to be converted to Reading for Poll
    if ( defined( $ret ) ) {
      # something went wrong increase fails
      $hash->{FAILS} += 1;

      # Put last error into reading
      readingsSingleUpdate($hash, "PollingLastError", $ret , 1); 
      
      if ( substr($now,0,10) eq substr($tst,0,10) ) {
        # Still same date just increment
        $cnt += 1;
        readingsSingleUpdate($hash, "PollingErrCount", $cnt, 1); 
      } else {
        # Write digest in log on next date
        $doLog = ( $pv ne "3_None" );
        readingsSingleUpdate($hash, "PollingErrCount", 1, 1); 
      }
      
    } elsif ( substr($now,0,10) ne substr($tst,0,10) ) {
      readingsSingleUpdate($hash, "PollingErrCount", 0, 1);
      $doLog = ( $pv ne "3_None" );
    }

    # log level is 2 on error if not digest is selected
    $ll =( ( $pv eq "2_Log" )?2:4 );

    # log digest if flag set
    Log3 $name, 3, "TelegramBot_Callback $name: Digest: Number of poll failures on ".substr($tst,0,10)." is :$cnt:" if ( $doLog );


    # start next poll or wait
    TelegramBot_UpdatePoll($hash); 


  } else {
    # Non Polling means: get msgid, reset the params and set loglevel
    $TelegramBot_hu_do_params{data} = "";
    $ll = 3 if ( defined( $ret ) );
    $msgId = $result->{message_id} if ( defined($result) );
       
  }

  $ret = "SUCCESS" if ( ! defined( $ret ) );
  Log3 $name, $ll, "TelegramBot_Callback $name: resulted in :$ret: from ".(( defined( $param->{isPolling} ) )?"Polling":"SendIt");

  if ( ! defined( $param->{isPolling} ) ) {
    $hash->{sentLastResult} = $ret;

    # handle retry
    # ret defined / args defined in params 
    if ( ( $ret ne  "SUCCESS" ) && ( defined( $param->{args} ) ) ) {
      my $wait = $param->{args}[5];
      
      my $maxRetries =  AttrVal($name,'maxRetries',0);
      if ( $wait <= $maxRetries ) {
        # calculate wait time 10s / 100s / 1000s ~ 17min / 10000s ~ 3h / 100000s ~ 30h
        $wait = 10**$wait;
        
        Log3 $name, 4, "TelegramBot_Callback $name: do retry ".$param->{args}[5]." timer: $wait (ret: $ret) for msg ".
              $param->{args}[0]." : ".$param->{args}[1];

        # set timer
        InternalTimer(gettimeofday()+$wait, "TelegramBot_RetrySend", $param,0); 
        
        # finish
        return;
      }

      Log3 $name, 3, "TelegramBot_Callback $name: Reached max retries (ret: $ret) for msg ".$param->{args}[0]." : ".$param->{args}[1];
      
    } 
    
    $hash->{sentMsgResult} = $ret;
    $hash->{sentMsgId} = ((defined($msgId))?$msgId:"");

    # Also set sentMsg Id and result in Readings
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "sentMsgResult", $ret);        
    readingsBulkUpdate($hash, "sentMsgId", ((defined($msgId))?$msgId:"") );        
    readingsEndUpdate($hash, 1);

    if ( scalar( @{ $hash->{sentQueue} } ) ) {
      my $ref = shift @{ $hash->{sentQueue} };
      Log3 $name, 5, "TelegramBot_Callback $name: handle queued send with :@$ref[0]: -:@$ref[1]: ";
      TelegramBot_SendIt( $hash, @$ref[0], @$ref[1], @$ref[2], @$ref[3], @$ref[4], @$ref[5] );
    }
  }
  
}

#####################################
#  INTERNAL: _ParseMsg handle a message from the update call 
#   params are the hash, the updateid and the actual message
sub TelegramBot_ParseMsg($$$)
{
  my ( $hash, $uid, $message ) = @_;
  my $name = $hash->{NAME};

  my @contacts;
  
  my $ret;
  
  my $mid = $message->{message_id};
  
  my $from = $message->{from};
  my $mpeer = $from->{id};

  # ignore if unknown contacts shall be accepter
  if ( AttrVal($name,'allowUnknownContacts',1) == 0 ) {
#    Debug "test if known :$mpeer";
    return $ret if ( ! TelegramBot_IsKnownContact( $hash, $mpeer ) ) ;
  }

  # check peers beside from only contact (shared contact) and new_chat_participant are checked
  push( @contacts, $from );

  my $chatId = "";
  my $chat = $message->{chat};
  if ( ( defined( $chat ) ) && ( $chat->{type} ne "private" ) ) {
    push( @contacts, $chat );
    $chatId = $chat->{id};
  }

#  my $user = $message->{contact};
#  if ( defined( $user ) ) {
#    push( @contacts, $user );
#  }

  my $user = $message->{new_chat_participant};
  if ( defined( $user ) ) {
    push( @contacts, $user );
  }

  # mtext contains the text of the message (if empty no further handling)
  my ( $mtext, $mfileid );

  if ( defined( $message->{text} ) ) {
    # handle text message
    $mtext = $message->{text};
    Log3 $name, 4, "TelegramBot_ParseMsg $name: Textmessage";

  } elsif ( defined( $message->{audio} ) ) {
    # handle audio message
    my $subtype = $message->{audio};
    $mtext = "received audio ";

    $mfileid = $subtype->{file_id};

    $mtext .= " # Performer: ".$subtype->{performer} if ( defined( $subtype->{performer} ) );
    $mtext .= " # Title: ".$subtype->{title} if ( defined( $subtype->{title} ) );
    $mtext .= " # Mime: ".$subtype->{mime_type} if ( defined( $subtype->{mime_type} ) );
    $mtext .= " # Size: ".$subtype->{file_size} if ( defined( $subtype->{file_size} ) );
    Log3 $name, 4, "TelegramBot_ParseMsg $name: audio fileid: $mfileid";

  } elsif ( defined( $message->{document} ) ) {
    # handle document message
    my $subtype = $message->{document};
    $mtext = "received document ";

    $mfileid = $subtype->{file_id};

    $mtext .= " # Caption: ".$message->{caption} if ( defined( $message->{caption} ) );
    $mtext .= " # Name: ".$subtype->{file_name} if ( defined( $subtype->{file_name} ) );
    $mtext .= " # Mime: ".$subtype->{mime_type} if ( defined( $subtype->{mime_type} ) );
    $mtext .= " # Size: ".$subtype->{file_size} if ( defined( $subtype->{file_size} ) );
    Log3 $name, 4, "TelegramBot_ParseMsg $name: document fileid: $mfileid ";

  } elsif ( defined( $message->{voice} ) ) {
    # handle voice message
    my $subtype = $message->{voice};
    $mtext = "received voice ";

    $mfileid = $subtype->{file_id};

    $mtext .= " # Mime: ".$subtype->{mime_type} if ( defined( $subtype->{mime_type} ) );
    $mtext .= " # Size: ".$subtype->{file_size} if ( defined( $subtype->{file_size} ) );
    Log3 $name, 4, "TelegramBot_ParseMsg $name: voice fileid: $mfileid";

  } elsif ( defined( $message->{video} ) ) {
    # handle video message
    my $subtype = $message->{video};
    $mtext = "received video ";

    $mfileid = $subtype->{file_id};

    $mtext .= " # Caption: ".$message->{caption} if ( defined( $message->{caption} ) );
    $mtext .= " # Mime: ".$subtype->{mime_type} if ( defined( $subtype->{mime_type} ) );
    $mtext .= " # Size: ".$subtype->{file_size} if ( defined( $subtype->{file_size} ) );
    Log3 $name, 4, "TelegramBot_ParseMsg $name: video fileid: $mfileid";

  } elsif ( defined( $message->{photo} ) ) {
    # handle photo message
    # photos are always an array with (hopefully) the biggest size last in the array
    my $photolist = $message->{photo};
    
    if ( scalar(@$photolist) > 0 ) {
      my $subtype = $$photolist[scalar(@$photolist)-1] ;
      $mtext = "received photo ";

      $mfileid = $subtype->{file_id};

      $mtext .= " # Caption: ".$message->{caption} if ( defined( $message->{caption} ) );
      $mtext .= " # Mime: ".$subtype->{mime_type} if ( defined( $subtype->{mime_type} ) );
      $mtext .= " # Size: ".$subtype->{file_size} if ( defined( $subtype->{file_size} ) );
      Log3 $name, 4, "TelegramBot_ParseMsg $name: photo fileid: $mfileid";
    }
  } elsif ( defined( $message->{venue} ) ) {
    # handle location type message
    my $ven = $message->{venue};
    my $loc = $ven->{location};
    
    $mtext = "received venue ";

    $mtext .= " # latitude: ".$loc->{latitude}." # longitude: ".$loc->{longitude};
    $mtext .= " # title: ".$ven->{title}." # address: ".$ven->{address};
    
# urls will be discarded in fhemweb    $mtext .= "\n# url: <a href=\"http://maps.google.com/?q=loc:".$loc->{latitude}.",".$loc->{longitude}."\">maplink</a>";
    
    Log3 $name, 4, "TelegramBot_ParseMsg $name: location received: latitude: ".$loc->{latitude}." longitude: ".$loc->{longitude};;
  } elsif ( defined( $message->{location} ) ) {
    # handle location type message
    my $loc = $message->{location};
    
    $mtext = "received location ";

    $mtext .= " # latitude: ".$loc->{latitude}." # longitude: ".$loc->{longitude};
    
# urls will be discarded in fhemweb    $mtext .= "\n# url: <a href=\"http://maps.google.com/?q=loc:".$loc->{latitude}.",".$loc->{longitude}."\">maplink</a>";
    
    Log3 $name, 4, "TelegramBot_ParseMsg $name: location received: latitude: ".$loc->{latitude}." longitude: ".$loc->{longitude};;
  }


  if ( defined( $mtext ) ) {
    Log3 $name, 4, "TelegramBot_ParseMsg $name: text   :$mtext:";

    my $mpeernorm = $mpeer;
    $mpeernorm =~ s/^\s+|\s+$//g;
    $mpeernorm =~ s/ /_/g;

#    Log3 $name, 5, "TelegramBot_ParseMsg $name: Found message $mid from $mpeer :$mtext:";

    # contacts handled separately since readings are updated in here
    TelegramBot_ContactUpdate($hash, @contacts) if ( scalar(@contacts) > 0 );
    
    readingsBeginUpdate($hash);

    readingsBulkUpdate($hash, "prevMsgId", $hash->{READINGS}{msgId}{VAL});        
    readingsBulkUpdate($hash, "prevMsgPeer", $hash->{READINGS}{msgPeer}{VAL});        
    readingsBulkUpdate($hash, "prevMsgPeerId", $hash->{READINGS}{msgPeerId}{VAL});        
    readingsBulkUpdate($hash, "prevMsgChat", $hash->{READINGS}{msgChat}{VAL});        
    readingsBulkUpdate($hash, "prevMsgText", $hash->{READINGS}{msgText}{VAL});        
    readingsBulkUpdate($hash, "prevMsgFileId", $hash->{READINGS}{msgFileId}{VAL});        

    readingsEndUpdate($hash, 0);
    
    readingsBeginUpdate($hash);

    readingsBulkUpdate($hash, "msgId", $mid);        
    readingsBulkUpdate($hash, "msgPeer", TelegramBot_GetFullnameForContact( $hash, $mpeernorm ));        
    readingsBulkUpdate($hash, "msgChat", TelegramBot_GetFullnameForChat( $hash, $chatId ) );        
    readingsBulkUpdate($hash, "msgPeerId", $mpeernorm);        
    readingsBulkUpdate($hash, "msgText", $mtext);

    readingsBulkUpdate($hash, "msgFileId", ( ( defined( $mfileid ) ) ? $mfileid : "" ) );        

    readingsEndUpdate($hash, 1);
    
    # COMMAND Handling (only if no fileid found
    Telegram_HandleCommandInMessages( $hash, $mpeernorm, $mtext, $mid ) if ( ! defined( $mfileid ) );
   
  } elsif ( scalar(@contacts) > 0 )  {
    # will also update reading
    TelegramBot_ContactUpdate( $hash, @contacts );

    Log3 $name, 5, "TelegramBot_ParseMsg $name: Found message $mid from $mpeer without text/media but with contacts";

  } else {
    Log3 $name, 5, "TelegramBot_ParseMsg $name: Found message $mid from $mpeer without text/media";
  }
  
  return $ret;
}


##############################################################################
##############################################################################
##
## Polling / Setup
##
##############################################################################
##############################################################################


######################################
#  make sure a reinitialization is triggered on next update
#  
sub TelegramBot_ResetPolling($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 4, "TelegramBot_ResetPolling $name: called ";

  RemoveInternalTimer($hash);

  HttpUtils_Close(\%TelegramBot_hu_upd_params); 
  HttpUtils_Close(\%TelegramBot_hu_do_params); 
  
  $hash->{WAIT} = 0;
  $hash->{FAILS} = 0;

  # let all existing methods first run into block
  $hash->{POLLING} = -1;
  
  # wait some time before next polling is starting
  InternalTimer(gettimeofday()+30, "TelegramBot_RestartPolling", $hash,0); 

  Log3 $name, 4, "TelegramBot_ResetPolling $name: finished ";

}

  
######################################
#  make sure a reinitialization is triggered on next update
#  
sub TelegramBot_RestartPolling($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 4, "TelegramBot_RestartPolling $name: called ";

  # Now polling can start
  $hash->{POLLING} = 0;

  # wait some time before next polling is starting
  TelegramBot_UpdatePoll($hash);

  Log3 $name, 4, "TelegramBot_RestartPolling $name: finished ";

}

  
######################################
#  make sure a reinitialization is triggered on next update
#  
sub TelegramBot_Setup($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 4, "TelegramBot_Setup $name: called ";

  $hash->{me} = "<unknown>";
  $hash->{STATE} = "Undefined";

  $hash->{POLLING} = -1;
  
  # Temp?? SNAME is required for allowed (normally set in TCPServerUtils)
  $hash->{SNAME} = $name;

  # Ensure queueing is not happening
  delete( $hash->{sentQueue} );
  delete( $hash->{sentMsgResult} );

  # remove timer for retry
  RemoveInternalTimer(\%TelegramBot_hu_do_params);
  
  $hash->{URL} = "https://api.telegram.org/bot".$hash->{Token}."/";

  $hash->{STATE} = "Defined";

  # getMe as connectivity check and set internals accordingly
  my $url = $hash->{URL}."getMe";
  my $meret = TelegramBot_DoUrlCommand( $hash, $url );
  if ( ( ! defined($meret) ) || ( ref($meret) ne "HASH" ) ) {
    # retry on first failure
    $meret = TelegramBot_DoUrlCommand( $hash, $url );
  }

  if ( ( defined($meret) ) && ( ref($meret) eq "HASH" ) ) {
    $hash->{me} = TelegramBot_userObjectToString( $meret );
    $hash->{STATE} = "Setup";

  } else {
    $hash->{me} = "Failed - see log file for details";
    $hash->{STATE} = "Failed";
    $hash->{FAILS} = 1;
  }
  
  TelegramBot_InternalContactsFromReading( $hash);

  TelegramBot_ResetPolling($hash);

  Log3 $name, 4, "TelegramBot_Setup $name: ended ";

}

##############################################################################
##############################################################################
##
## CONTACT handling
##
##############################################################################
##############################################################################



#####################################
# INTERNAL: get id for a peer
#   if only digits --> assume id
#   if start with @ --> assume username
#   if start with # --> assume groupname
#   else --> assume full name
sub TelegramBot_GetIdForPeer($$)
{
  my ($hash,$mpeer) = @_;

  TelegramBot_InternalContactsFromReading( $hash ) if ( ! defined( $hash->{Contacts} ) );

  my $id;
  
  if ( $mpeer =~ /^\-?[[:digit:]]+$/ ) {
    # check if id is in hash 
#    $id = $mpeer if ( defined( $hash->{Contacts}{$mpeer} ) );
    # Allow also sending to ids which are not in the contacts list
    $id = $mpeer;
  } elsif ( $mpeer =~ /^[@#].*$/ ) {
    foreach  my $mkey ( keys %{$hash->{Contacts}} ) {
      my @clist = split( /:/, $hash->{Contacts}{$mkey} );
      if ( (defined($clist[2])) && ( $clist[2] eq $mpeer ) ) {
        $id = $clist[0];
        last;
      }
    }
  } else {
    $mpeer =~ s/^\s+|\s+$//g;
    $mpeer =~ s/ /_/g;
    foreach  my $mkey ( keys %{$hash->{Contacts}} ) {
      my @clist = split( /:/, $hash->{Contacts}{$mkey} );
      if ( (defined($clist[1])) && ( $clist[1] eq $mpeer ) ) {
        $id = $clist[0];
        last;
      }
    }
  }  
  
  return $id
}
  


#####################################
# INTERNAL: get full name for contact id
sub TelegramBot_GetContactInfoForContact($$)
{
  my ($hash,$mcid) = @_;

  TelegramBot_InternalContactsFromReading( $hash ) if ( ! defined( $hash->{Contacts} ) );

  return ( $hash->{Contacts}{$mcid});
}
  
  
#####################################
# INTERNAL: get full name for contact id
sub TelegramBot_GetFullnameForContact($$)
{
  my ($hash,$mcid) = @_;

  my $contact = TelegramBot_GetContactInfoForContact( $hash,$mcid );
  my $ret = "";
  

  if ( defined( $contact ) ) {
      Log3 $hash->{NAME}, 4, "TelegramBot_GetFullnameForContact # Contacts is $contact:";
      my @clist = split( /:/, $contact );
      $ret = $clist[1];
      $ret = $clist[2] if ( ! $ret);
      $ret = $clist[0] if ( ! $ret);
      Log3 $hash->{NAME}, 4, "TelegramBot_GetFullnameForContact # name is $ret";
  } else {
    Log3 $hash->{NAME}, 4, "TelegramBot_GetFullnameForContact # Contacts is <undef>";
  }
  
  return $ret;
}
  
  
#####################################
# INTERNAL: get full name for a chat
sub TelegramBot_GetFullnameForChat($$)
{
  my ($hash,$mcid) = @_;
  my $ret = "";

  return $ret if ( ! $mcid );

  my $contact = TelegramBot_GetContactInfoForContact( $hash,$mcid );
  

  if ( defined( $contact ) ) {
      my @clist = split( /:/, $contact );
      $ret = $clist[0];
      $ret .= " (".$clist[2].")" if ( $clist[2] );
      Log3 $hash->{NAME}, 4, "TelegramBot_GetFullnameForChat # $mcid is $ret";
  }
  
  return $ret;
}
  
  
#####################################
# INTERNAL: check if a contact is already known in the internals->Contacts-hash
sub TelegramBot_IsKnownContact($$)
{
  my ($hash,$mpeer) = @_;

  TelegramBot_InternalContactsFromReading( $hash ) if ( ! defined( $hash->{Contacts} ) );

#  foreach my $key (keys $hash->{Contacts} )
#      {
#        Log3 $hash->{NAME}, 4, "Contact :$key: is  :".$hash->{Contacts}{$key}.":";
#      }

#  Debug "Is known ? ".( defined( $hash->{Contacts}{$mpeer} ) );
  return ( defined( $hash->{Contacts}{$mpeer} ) );
}

#####################################
# INTERNAL: calculate internals->contacts-hash from Readings->Contacts string
sub TelegramBot_CalcContactsHash($$)
{
  my ($hash, $cstr) = @_;

  # create a new hash
  if ( defined( $hash->{Contacts} ) ) {
    foreach my $key (keys %{$hash->{Contacts}} )
        {
            delete $hash->{Contacts}{$key};
        }
  } else {
    $hash->{Contacts} = {};
  }
  
  # split reading at separator 
  my @contactList = split(/\s+/, $cstr );
  
  # for each element - get id as hashtag and full contact as value
  foreach  my $contact ( @contactList ) {
    my ( $id, $cname, $cuser ) = split( ":", $contact, 3 );
    # add contact only if all three parts are there and either 2nd or 3rd part not empty and 3rd part either empty or start with @ or # and at least 3 chars
    # and id must be only digits
    $cuser = "" if ( ! defined( $cuser ) );
    $cname = "" if ( ! defined( $cname ) );
    
    Log3 $hash->{NAME}, 5, "Contact add :$contact:   :$id:  :$cname: :$cuser:";
  
    if ( ( length( $cname ) == 0 ) && ( length( $cuser ) == 0 ) ) {
      Log3 $hash->{NAME}, 5, "Contact add :$contact: has empty cname and cuser:";
      next;
    } elsif ( ( length( $cuser ) > 0 ) && ( length( $cuser ) < 3 ) ) {
      Log3 $hash->{NAME}, 5, "Contact add :$contact: cuser not long enough (3):";
      next;
    } elsif ( ( length( $cuser ) > 0 ) && ( $cuser !~ /^[\@#]/ ) ) {
      Log3 $hash->{NAME}, 5, "Contact add :$contact: cuser not matching start chars:";
      next;
    } elsif ( $id !~ /^\-?[[:digit:]]+$/ ) {
      Log3 $hash->{NAME}, 5, "Contact add :$contact: cid is not number or -number:";
      next;
    } else {
      $cname = TelegramBot_encodeContactString( $cname );

      $cuser = TelegramBot_encodeContactString( $cuser );
      
      $hash->{Contacts}{$id} = $id.":".$cname.":".$cuser;
    }
  }

}


#####################################
# INTERNAL: calculate internals->contacts-hash from Readings->Contacts string
sub TelegramBot_InternalContactsFromReading($)
{
  my ($hash) = @_;
  TelegramBot_CalcContactsHash( $hash, ReadingsVal($hash->{NAME},"Contacts","") );
}


#####################################
# INTERNAL: update contacts hash and change readings string (no return)
sub TelegramBot_ContactUpdate($@) {

  my ($hash, @contacts) = @_;

  my $newfound = ( int(@contacts) == 0 );

  my $oldContactString = ReadingsVal($hash->{NAME},"Contacts","");

  TelegramBot_InternalContactsFromReading( $hash ) if ( ! defined( $hash->{Contacts} ) );
  
  Log3 $hash->{NAME}, 4, "TelegramBot_ContactUpdate # Contacts in hash before :".scalar(keys %{$hash->{Contacts}}).":";

  foreach my $user ( @contacts ) {
    my $contactString = TelegramBot_userObjectToString( $user );

    # keep the username part of the new contatc for deleting old users with same username
    my $unamepart;
    my @clist = split( /:/, $contactString );
    if (defined($clist[2])) {
      $unamepart = $clist[2]; 
    }
    
    if ( ! defined( $hash->{Contacts}{$user->{id}} ) ) {
      Log3 $hash->{NAME}, 3, "TelegramBot_ContactUpdate new contact :".$contactString.":";
      next if ( AttrVal($hash->{NAME},'allowUnknownContacts',1) == 0 );
      $newfound = 1;
    } elsif ( $contactString ne $hash->{Contacts}{$user->{id}} ) {
      Log3 $hash->{NAME}, 3, "TelegramBot_ContactUpdate updated contact :".$contactString.":";
    }

    # remove all contacts with same username
    if ( defined( $unamepart ) ) {
      my $dupid = TelegramBot_GetIdForPeer( $hash, $unamepart );
      while ( $dupid ) {
         Log3 $hash->{NAME}, 3, "TelegramBot_ContactUpdate removed stale/duplicate contact ($dupid:$unamepart):".$hash->{Contacts}{$dupid}.":" if ( $dupid ne $user->{id} );
         delete( $hash->{Contacts}{$dupid} );
         $dupid = TelegramBot_GetIdForPeer( $hash, $unamepart );
      }
    }
    
    # set new contact data
    $hash->{Contacts}{$user->{id}} = $contactString;
  }

  Log3 $hash->{NAME}, 4, "TelegramBot_ContactUpdate # Contacts in hash after :".scalar(keys %{$hash->{Contacts}}).":";

  my $rc = "";
  foreach  my $key ( keys %{$hash->{Contacts}} )
    {
      if ( length($rc) > 0 ) {
        $rc .= " ".$hash->{Contacts}{$key};
      } else {
        $rc = $hash->{Contacts}{$key};
      }
    }

  # Do a readings change directly for contacts
  readingsSingleUpdate($hash, "Contacts", $rc , 1) if ( $rc ne $oldContactString );
    
  # save state file on new contact 
  if ( $newfound ) {
    WriteStatefile() if ( AttrVal($hash->{NAME}, 'saveStateOnContactChange', 1) ) ;
    Log3 $hash->{NAME}, 2, "TelegramBot_ContactUpdate Updated Contact list :".$rc.":";
  }
  
  return;    
}
  
#####################################
# INTERNAL: Convert TelegramBot user and chat object to string
sub TelegramBot_userObjectToString($) {

  my ( $user ) = @_;
  
  my $ret = $user->{id}.":";
  
  # user objects do not contain a type field / chat objects need to contain a type but only if type=group or type=supergroup it is really a group
  if ( ( defined( $user->{type} ) ) && ( ( $user->{type} eq "group" ) || ( $user->{type} eq "supergroup" ) ) ) {
    
    $ret .= ":";

    $ret .= "#".TelegramBot_encodeContactString($user->{title}) if ( defined( $user->{title} ) );

  } else {

    my $part = "";

    $part .= $user->{first_name} if ( defined( $user->{first_name} ) );
    $part .= " ".$user->{last_name} if ( defined( $user->{last_name} ) );

    $ret .= TelegramBot_encodeContactString($part).":";

    $ret .= "@".TelegramBot_encodeContactString($user->{username}) if ( defined( $user->{username} ) );
  }

  return $ret;
}

#####################################
# INTERNAL: Convert TelegramBot user and chat object to string
sub TelegramBot_encodeContactString($) {
  my ($str) = @_;

    $str =~ s/:/_/g;
    $str =~ s/^\s+|\s+$//g;
    $str =~ s/ /_/g;

  return $str;
}

#####################################
# INTERNAL: Check if peer is allowed - true if allowed
sub TelegramBot_checkAllowedPeer($$$) {
  my ($hash,$mpeer,$msg) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 5, "TelegramBot_checkAllowedPeer $name: called with $mpeer";

  my $cp = AttrVal($name,'cmdRestrictedPeer','');

  return 1 if ( $cp eq '' );
  
  my @peers = split( " ", $cp);  
  foreach my $cp (@peers) {
    return 1 if ( $cp eq $mpeer );
    my $cdefpeer = TelegramBot_GetIdForPeer( $hash, $cp );
    if ( defined( $cdefpeer ) ) {
      return 1 if ( $cdefpeer eq $mpeer );
    }
  }
  # get human readble name for peer
  my $pname = TelegramBot_GetFullnameForContact( $hash, $mpeer );

  # unauthorized fhem cmd
  Log3 $name, 1, "TelegramBot unauthorized cmd from user :$pname: ($mpeer) \n  Msg: $msg";
  # LOCAL: External message
  my $ret = AttrVal( $name, 'textResponseUnauthorized', 'UNAUTHORIZED: TelegramBot FHEM request from user :$peer \n  Msg: $msg');
  $ret =~ s/\$peer/$pname ($mpeer)/g;
  $ret =~ s/\$msg/$msg/g;
  # my $ret =  "UNAUTHORIZED: TelegramBot FHEM request from user :$pname: ($mpeer) \n  Msg: $msg";
  
  # send unauthorized to defaultpeer
  my $defpeer = AttrVal($name,'defaultPeer',undef);
  if ( defined( $defpeer ) ) {
    AnalyzeCommand( undef, "set $name message $ret" );
  }
 
  return 0;
}  



##############################################################################
##############################################################################
##
## HELPER
##
##############################################################################
##############################################################################


#####################################
#  INTERNAL: Convert (Mark) a scalar as UTF8 - coming from telegram
sub TelegramBot_GetUTF8Back( $ ) {
  my ( $data ) = @_;
  
  return $data;
#JVI
#  return encode('utf8', $data);
}
  


#####################################
#  INTERNAL: used to encode a string aas Utf-8 coming from the code
sub TelegramBot_PutToUTF8( $ ) {
  my ( $data ) = @_;
  
  return $data;
#JVI
#  return decode('utf8', $data);
}
  


######################################
#  Get a string and identify possible media streams
#  PNG is tested
#  returns 
#   -1 for image
#   -2 for Audio
#   -3 for other media
# and extension without dot as 2nd list element

sub TelegramBot_IdentifyStream($$) {
  my ($hash, $msg) = @_;

  # signatures for media files are documented here --> https://en.wikipedia.org/wiki/List_of_file_signatures
  # seems sometimes more correct: https://wangrui.wordpress.com/2007/06/19/file-signatures-table/
  return (-1,"png") if ( $msg =~ /^\x89PNG\r\n\x1a\n/ );    # PNG
  return (-1,"jpg") if ( $msg =~ /^\xFF\xD8\xFF/ );    # JPG not necessarily complete, but should be fine here
  
  return (-2 ,"mp3") if ( $msg =~ /^\xFF\xF3/ );    # MP3    MPEG-1 Layer 3 file without an ID3 tag or with an ID3v1 tag
  return (-2 ,"mp3") if ( $msg =~ /^\xFF\xFB/ );    # MP3    MPEG-1 Layer 3 file without an ID3 tag or with an ID3v1 tag
  
  # MP3    MPEG-1 Layer 3 file with an ID3v2 tag 
  #   starts with ID3 then version (most popular 03, new 04 seldom used, old 01 and 02) ==> Only 2,3 and 4 are tested currently
  return (-2 ,"mp3") if ( $msg =~ /^ID3\x03/ );    
  return (-2 ,"mp3") if ( $msg =~ /^ID3\x04/ );    
  return (-2 ,"mp3") if ( $msg =~ /^ID3\x02/ );    

  return (-3,"pdf") if ( $msg =~ /^%PDF/ );    # PDF document
  return (-3,"docx") if ( $msg =~ /^PK\x03\x04/ );    # Office new
  return (-3,"docx") if ( $msg =~ /^PK\x05\x06/ );    # Office new
  return (-3,"docx") if ( $msg =~ /^PK\x07\x08/ );    # Office new
  return (-3,"doc") if ( $msg =~ /^\xD0\xCF\x11\xE0\xA1\xB1\x1A\xE1/ );    # Office old - D0 CF 11 E0 A1 B1 1A E1

  return (0,undef);
}

#####################################
#####################################
# INTERNAL: prepare msg/ret for log file 
sub TelegramBot_MsgForLog($;$) {
  my ($msg, $stream) = @_;

  if ( ! defined( $msg ) ) {
    return "<undef>";
  } elsif ( $stream ) {
    return "<stream:".length($msg).">";
  } 
  return $msg;
}

######################################
#  read binary file for Phototransfer - returns undef or empty string on error
#  
sub TelegramBot_BinaryFileRead($$) {
  my ($hash, $fileName) = @_;

  return '' if ( ! (-e $fileName) );
  
  my $fileData = '';
    
  open TGB_BINFILE, '<'.$fileName;
  binmode TGB_BINFILE;
  while (<TGB_BINFILE>){
    $fileData .= $_;
  }
  close TGB_BINFILE;
  
  return $fileData;
}



######################################
#  write binary file for (hest hash, filename and the data
#  
sub TelegramBot_BinaryFileWrite($$$) {
  my ($hash, $fileName, $data) = @_;

  open TGB_BINFILE, '>'.$fileName;
  binmode TGB_BINFILE;
  print TGB_BINFILE $data;
  close TGB_BINFILE;
  
  return undef;
}


  

##############################################################################
##############################################################################
##
## Documentation
##
##############################################################################
##############################################################################

1;

=pod
=item summary    send and receive of messages through telegram instant messaging
=item summary_DE senden und empfangen von Nachrichten durch telegram IM
=begin html

<a name="TelegramBot"></a>
<h3>TelegramBot</h3>
<ul>
  The TelegramBot module allows the usage of the instant messaging service <a href="https://telegram.org/">Telegram</a> from FHEM in both directions (sending and receiving). 
  So FHEM can use telegram for notifications of states or alerts, general informations and actions can be triggered.
  <br>
  <br>
  TelegramBot makes use of the <a href=https://core.telegram.org/bots/api>telegram bot api</a> and does NOT rely on any addition local client installed. 
  <br>
  Telegram Bots are different from normal telegram accounts, without being connected to a phone number. Instead bots need to be registered through the 
  <a href=https://core.telegram.org/bots#botfather>BotFather</a> to gain the needed token for authorizing as bot with telegram.org. This is done by connecting (in a telegram client) to the BotFather and sending the command <code>/newbot</code> and follow the steps specified by the BotFather. This results in a token, this token (e.g. something like <code>110201543:AAHdqTcvCH1vGWJxfSeofSAs0K5PALDsaw</code> is required for defining a working telegram bot in fhem.
  <br><br>
  Bots also differ in other aspects from normal telegram accounts. Here some examples:
  <ul>
    <li>Bots can not initiate connections to arbitrary users, instead users need to first initiate the communication with the bot.</li> 
    <li>Bots have a different privacy setting then normal users (see <a href=https://core.telegram.org/bots#privacy-mode>Privacy mode</a>) </li> 
    <li>Bots support commands and specialized keyboards for the interaction (not yet supported in the fhem telegramBot)</li> 
  </ul>
  
  <br><br>
  Note:
  <ul>
    <li>This module requires the perl JSON module.<br>
        Please install the module (e.g. with <code>sudo apt-get install libjson-perl</code>) or the correct method for the underlying platform/system.</li>
    <li>The attribute pollingTimeout needs to be set to a value greater than zero, to define the interval of receiving messages (if not set or set to 0, no messages will be received!)</li>
    <li>Multiple infomations are stored in readings (esp contacts) and internals that are needed for the bot operation, so having an recent statefile will help in correct operation of the bot. Generally it is recommended to regularly store the statefile (see save command)</li>
  </ul>   
  <br><br>

  The TelegramBot module allows receiving of messages from any peer (telegram user) and can send messages to known users.
  The contacts/peers, that are known to the bot are stored in a reading (named <code>Contacts</code>) and also internally in the module in a hashed list to allow the usage 
  of contact ids and also full names and usernames. Contact ids are made up from only digits, user names are prefixed with a @, group names are prefixed with a #. 
  All other names will be considered as full names of contacts. Here any spaces in the name need to be replaced by underscores (_).
  Each contact is considered a triple of contact id, full name (spaces replaced by underscores) and username or groupname prefixed by @ respectively #. 
  The three parts are separated by a colon (:).
  <br>
  Contacts are collected automatically during communication by new users contacting the bot or users mentioned in messages.
  <br><br>
  Updates and messages are received via long poll of the GetUpdates message. This message currently supports a maximum of 20 sec long poll. 
  In case of failures delays are taken between new calls of GetUpdates. In this case there might be increasing delays between sending and receiving messages! 
  <br>
  Beside pure text messages also media messages can be sent and received. This includes audio, video, images, documents, locations and venues.
  <br><br>
  <a name="TelegramBotdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; TelegramBot  &lt;token&gt; </code>
    <br><br>
    Defines a TelegramBot device using the specified token perceived from botfather
    <br>

    Example:
    <ul>
      <code>define teleBot TelegramBot 110201543:AAHdqTcvCH1vGWJxfSeofSAs0K5PALDsaw</code><br>
    </ul>
    <br>
  </ul>
  <br><br>

  <a name="TelegramBotset"></a>
  <b>Set</b>
  <ul>
    <li><code>message|msg|send [ @&lt;peer1&gt; ... @&lt;peerN&gt; ] &lt;text&gt;</code><br>Sends the given message to the given peer or if peer(s) is ommitted currently defined default peer user. Each peer given needs to be always prefixed with a '@'. Peers can be specified as contact ids, full names (with underscore instead of space), usernames (prefixed with another @) or chat names (also known as groups in telegram groups must be prefixed with #). Multiple peers are to be separated by space<br>
    Messages do not need to be quoted if containing spaces.<br>
    Examples:<br>
      <dl>
        <dt><code>set aTelegramBotDevice message @@someusername a message to be sent</code></dt>
          <dd> to send to a user having someusername as username (not first and last name) in telegram <br> </dd>
        <dt><code>set aTelegramBotDevice message @@someusername @1234567 a message to be sent to multiple receipients</code></dt>
          <dd> to send to a user having someusername as username (not first and last name) in telegram <br> </dd>
        <dt><code>set aTelegramBotDevice message @Ralf_Mustermann another message</code></dt>
          <dd> to send to a user Ralf as firstname and Mustermann as last name in telegram   <br></dd>
        <dt><code>set aTelegramBotDevice message @#justchatting Hello</code></dt>
          <dd> to send the message "Hello" to a chat with the name "justchatting"   <br></dd>
        <dt><code>set aTelegramBotDevice message @1234567 Bye</code></dt>
          <dd> to send the message "Bye" to a contact or chat with the id "1234567". Chat ids might be negative and need to be specified with a leading hyphen (-). <br></dd>
      <dl>
    </li>
    <li><code>reply &lt;msgid&gt; [ @&lt;peer1&gt; ] &lt;text&gt;</code><br>Sends the given message as a reply to the msgid (number) given to the given peer or if peer is ommitted to the defined default peer user. Only a single peer can be specified. Beside the handling handling of the message as a reply to a message received earlier, the peer and message handling is otherwise identical to the msg command. 
    </li>

    <li><code>sendImage|image [ @&lt;peer1&gt; ... @&lt;peerN&gt;] &lt;file&gt; [&lt;caption&gt;]</code><br>Sends a photo to the given peer(s) or if ommitted to the default peer. 
    File is specifying a filename and path to the image file to be send. 
    Local paths should be given local to the root directory of fhem (the directory of fhem.pl e.g. /opt/fhem).
    Filenames with spaces need to be given in double quotes (")
    Rule for specifying peers are the same as for messages. Multiple peers are to be separated by space. Captions can also contain multiple words and do not need to be quoted.
    </li>
    <li><code>sendMedia|sendDocument [ @&lt;peer1&gt; ... @&lt;peerN&gt;] &lt;file&gt;</code><br>Sends a media file (video, audio, image or other file type) to the given peer(s) or if ommitted to the default peer. Handling for files and peers is as specified above.
    </li>
    <li><code>sendVoice [ @&lt;peer1&gt; ... @&lt;peerN&gt;] &lt;file&gt;</code><br>Sends a voice message for playing directly in the browser to the given peer(s) or if ommitted to the default peer. Handling for files and peers is as specified above.
    </li>

  <br>
    <li><code>sendLocation [ @&lt;peer1&gt; ... @&lt;peerN&gt;] &lt;latitude&gt; &lt;longitude&gt;</code><br>Sends a location as pair of coordinates latitude and longitude as floating point numbers 
    <br>Example: <code>set aTelegramBotDevice sendLocation @@someusername 51.163375 10.447683</code> will send the coordinates of the geographical center of Germany as location.
    </li>

  <br>
    <li><code>replaceContacts &lt;text&gt;</code><br>Set the contacts newly from a string. Multiple contacts can be separated by a space. 
    Each contact needs to be specified as a triple of contact id, full name and user name as explained above. </li>
    <li><code>reset</code><br>Reset the internal state of the telegram bot. This is normally not needed, but can be used to reset the used URL, 
    internal contact handling, queue of send items and polling <br>
    ATTENTION: Messages that might be queued on the telegram server side (especially commands) might be then worked off afterwards immedately. 
    If in doubt it is recommened to temporarily deactivate (delete) the cmdKeyword attribute before resetting.</li>

  </ul>

  <br><br>

  <a name="TelegramBotattr"></a>
  <b>Attributes</b>
  <br><br>
  <ul>
    <li><code>defaultPeer &lt;name&gt;</code><br>Specify contact id, user name or full name of the default peer to be used for sending messages. </li> 
    <li><code>defaultPeerCopy &lt;1 (default) or 0&gt;</code><br>Copy all command results also to the defined defaultPeer. If set results are sent both to the requestor and the defaultPeer if they are different. 
    </li> 

  <br>
    <li><code>cmdKeyword &lt;keyword&gt;</code><br>Specify a specific text that needs to be sent to make the rest of the message being executed as a command. 
      So if for example cmdKeyword is set to <code>ok fhem</code> then a message starting with this string will be executed as fhem command 
        (see also cmdTriggerOnly).<br>
        Please also consider cmdRestrictedPeer for restricting access to this feature!<br>
        Example: If this attribute is set to a value of <code>ok fhem</code> a message of <code>ok fhem attr telegram room IM</code> 
        send to the bot would execute the command  <code>attr telegram room IM</code> and set a device called telegram into room IM.
        The result of the cmd is sent to the requestor and in addition (if different) sent also as message to the defaultPeer (This can be controlled with the attribute <code>defaultPeerCopy</code>). 
    <br>
        Note: <code>shutdown</code> is not supported as a command (also in favorites) and will be rejected. This is needed to avoid reexecution of the shutdown command directly after restart (endless loop !).
    </li> 
    <li><code>cmdSentCommands &lt;keyword&gt;</code><br>Specify a specific text that will trigger sending the last commands back to the sender<br>
        Example: If this attribute is set to a value of <code>last cmd</code> a message of <code>last cmd</code> 
        woud lead to a reply with the list of the last sent fhem commands will be sent back.<br>
        Please also consider cmdRestrictedPeer for restricting access to this feature!<br>
    </li> 

  <br>
    <li><code>cmdFavorites &lt;keyword&gt;</code><br>Specify a specific text that will trigger sending the list of defined favorites or executes a given favorite by number (the favorites are defined in attribute <code>favorites</code>).
    <br>
        Example: If this attribute is set to a value of <code>favorite</code> a message of <code>favorite</code> to the bot will return a list of defined favorite commands and their index number. In the same case the message <code>favorite &lt;n&gt;</code> (with n being a number) would execute the command that is the n-th command in the favorites list. The result of the command will be returned as in other command executions. 
        Please also consider cmdRestrictedPeer for restricting access to this feature!<br>
    </li> 
    <li><code>favorites &lt;list of commands&gt;</code><br>Specify a list of favorite commands for Fhem (without cmdKeyword). Multiple commands are separated by semicolon (;). This also means that only simple commands (without embedded semicolon) can be defined. <br>
    <br>
    Favorite commands are fhem commands with an optional alias for the command given. The alias can be sent as message (instead of the favoriteCmd) to execute the command. Before the favorite command also an alias (other shortcut for the favorite) or/and a descriptive text (enclosed in []) can be specifed. If alias or description is specified this needs to be prefixed with a '/' and the alias if given needs to be specified first.
    <br>
    <br>
        Example: Assuming cmdFavorites is set to a value of <code>favorite</code> and this attribute is set to a value of
        <br><code>get lights status; /light=set lights on; /dark[Make it dark]=set lights off; /heating=set heater; /[status]=get heater status;</code> <br>
        <ul>
          <li>Then a message "favorite1" to the bot would execute the command <code>get lights status</code></li>
          <li>A message "favorite 2" or "/light" to the bot would execute the command <code>set lights on</code>. And the favorite would show as "make it dark" in the list of favorites.</li>
          <li>A message "/heating on" or "favorite 3 on" to the bot would execute the command <code>set heater on</code><br> (Attention the remainder after the alias will be added to the command in fhem!)</li>
          <li>A message "favorite 4" to the bot would execute the command <code>get heater status</code> and this favorite would show as "status" as a description in the favorite list</li>
        </ul>
    <br>
    Favorite commands can also be prefixed with a question mark ('?') to enable a confirmation being requested before executing the command.
    <br>
        Examples: <code>get lights status; /light=?set lights on; /dark=set lights off; ?set heater;</code> <br>
    <br>
    Meaning the full format for a single favorite is <code>/alias[description]=command</code> where the alias can be empty or <code>/alias=command</code> or just the <code>command</code>. In any case the command can be also prefixed with a '?'. Spaces are only allowed in the description and the command, usage of spaces in other areas might lead to wrong interpretation of the definition. Spaces and also many other characters are not supported in the alias commands by telegram, so if you want to have your favorite/alias directly recognized in then telegram app, restriction to letters, digits and underscore is required.  
    </li> 

  <br>
    <li><code>cmdRestrictedPeer &lt;peername(s)&gt;</code><br>Restrict the execution of commands only to messages sent from the given peername or multiple peernames
    (specified in the form of contact id, username or full name, multiple peers to be separated by a space). 
    A message with the cmd and sender is sent to the default peer in case of another user trying to sent messages<br>
    </li> 
    <li><code>allowUnknownContacts &lt;1 or 0&gt;</code><br>Allow new contacts to be added automatically (1 - Default) or restrict message reception only to known contacts and unknwown contacts will be ignored (0).
    </li> 
    <li><code>saveStateOnContactChange &lt;1 or 0&gt;</code><br>Allow statefile being written on every new contact found, ensures new contacts not being lost on any loss of statefile. Default is on (1).
    </li> 
    <li><code>cmdReturnEmptyResult &lt;1 or 0&gt;</code><br>Return empty (success) message for commands (default). Otherwise return messages are only sent if a result text or error message is the result of the command execution.
    </li> 

    <li><code>allowedCommands &lt;list of command&gt;</code><br>Restrict the commands that can be executed through favorites and cmdKeyword to the listed commands (separated by space). Similar to the corresponding restriction in FHEMWEB. The allowedCommands will be set on the corresponding instance of an allowed device with the name "allowed_&lt;TelegrambotDeviceName&gt; and not on the telegramBotDevice! This allowed device is created and modified automatically.<br>
    <b>ATTENTION: This is not a hardened secure blocking of command execution, there might be ways to break the restriction!</b>
    </li> 

    <li><code>cmdTriggerOnly &lt;0 or 1&gt;</code><br>Restrict the execution of commands only to trigger command. If this attr is set (value 1), then only the name of the trigger even has to be given (i.e. without the preceding statement trigger). 
          So if for example cmdKeyword is set to <code>ok fhem</code> and cmdTriggerOnly is set, then a message of <code>ok fhem someMacro</code> would execute the fhem command  <code>trigger someMacro</code>.<br>
    Note: This is deprecated and will be removed in one of the next releases
    </li> 


  <br>
    <li><code>pollingTimeout &lt;number&gt;</code><br>Used to specify the timeout for long polling of updates. A value of 0 is switching off any long poll. 
      In this case no updates are automatically received and therefore also no messages can be received. It is recommended to set the pollingtimeout to a reasonable time between 15 (not too short) and 60 (to avoid broken connections). 
    </li> 
    <li><code>pollingVerbose &lt;0_None 1_Digest 2_Log&gt;</code><br>Used to limit the amount of logging for errors of the polling connection. These errors are happening regularly and usually are not consider critical, since the polling restarts automatically and pauses in case of excess errors. With the default setting "1_Digest" once a day the number of errors on the last day is logged (log level 3). With "2_Log" every error is logged with log level 2. With the setting "0_None" no errors are logged. In any case the count of errors during the last day and the last error is stored in the readings <code>PollingErrCount</code> and <code>PollingLastError</code> </li> 
    
  <br>
    <li><code>cmdTimeout &lt;number&gt;</code><br>Used to specify the timeout for sending commands. The default is a value of 30 seconds, which should be normally fine for most environments. In the case of slow or on-demand connections to the internet this parameter can be used to specify a longer time until a connection failure is considered.
    </li> 

  <br>
    <li><code>maxFileSize &lt;number of bytes&gt;</code><br>Maximum file size in bytes for transfer of files (images). If not set the internal limit is specified as 10MB (10485760B).
    </li> 
    <li><code>filenameUrlEscape &lt;0 or 1&gt;</code><br>Specify if filenames can be specified using url escaping, so that special chanarcters as in URLs. This specifically allows to specify spaces in filenames as <code>%20</code>. Default is off (0).
    </li> 

    <li><code>maxReturnSize &lt;number of chars&gt;</code><br>Maximum size of command result returned as a text message including header (Default is unlimited). The internal shown on the device is limited to 1000 chars.
    </li> 
    <li><code>maxRetries &lt;0,1,2,3,4,5&gt;</code><br>Specify the number of retries for sending a message in case of a failure. The first retry is sent after 10sec, the second after 100, then after 1000s (~16min), then after 10000s (~2.5h), then after approximately a day. Setting the value to 0 (default) will result in no retries.
    </li> 

  <br>
    <li><code>textResponseConfirm &lt;TelegramBot FHEM : $peer\n Bestätigung \n&gt;</code><br>Text to be sent when a confirmation for a command is requested. Default is shown here and $peer will be replaced with the actual contact full name if added.
    </li> 
    <li><code>textResponseFavorites &lt;TelegramBot FHEM : $peer\n Favoriten \n&gt;</code><br>Text to be sent as starter for the list of favorites. Default is shown here and $peer will be replaced with the actual contact full name if added.
    </li> 
    <li><code>textResponseCommands &lt;TelegramBot FHEM : $peer\n Letzte Befehle \n&gt;</code><br>Text to be sent as starter for the list of last commands. Default is shown here and $peer will be replaced with the actual contact full name if added.
    </li> 
    <li><code>textResponseResult &lt;TelegramBot FHEM : $peer\n Befehl:$cmd:\n Ergebnis:\n$result\n&gt;</code><br>Text to be sent as result for a cmd execution. Default is shown here and $peer will be replaced with the actual contact full name if added. Similarly $cmd and $result will be replaced with the cmd and the execution result.
    </li> 
    <li><code>textResponseUnauthorized &lt;UNAUTHORIZED: TelegramBot FHEM request from user :$peer\n  Msg: $msg&gt;</code><br>Text to be sent as warning for unauthorized command requests. Default is shown here and $peer will be replaced with the actual contact full name and id if added. $msg will be replaced with the sent message.
    </li> 

  </ul>
  <br><br>
  
  <a name="TelegramBotreadings"></a>
  <b>Readings</b>
  <br><br>
  <ul>
    <li>Contacts &lt;text&gt;<br>The current list of contacts known to the telegram bot. 
    Each contact is specified as a triple in the same form as described above. Multiple contacts separated by a space. </li> 
  <br>
    <li>msgId &lt;text&gt;<br>The id of the last received message is stored in this reading. 
    For secret chats a value of -1 will be given, since the msgIds of secret messages are not part of the consecutive numbering</li> 
    <li>msgPeer &lt;text&gt;<br>The sender name of the last received message (either full name or if not available @username)</li> 
    <li>msgPeerId &lt;text&gt;<br>The sender id of the last received message</li> 
    <li>msgText &lt;text&gt;<br>The last received message text is stored in this reading. Information about special messages like documents, audio, video, locations or venues will be also stored in this reading</li> 
    <li>msgFileId &lt;fileid&gt;<br>The last received message file_id (Audio, Photo, Video, Voice or other Document) is stored in this reading.</li> 
  <br>
    <li>prevMsgId &lt;text&gt;<br>The id of the SECOND last received message is stored in this reading</li> 
    <li>prevMsgPeer &lt;text&gt;<br>The sender name of the SECOND last received message (either full name or if not available @username)</li> 
    <li>prevMsgPeerId &lt;text&gt;<br>The sender id of the SECOND last received message</li> 
    <li>prevMsgText &lt;text&gt;<br>The SECOND last received message text is stored in this reading</li> 
    <li>prevMsgFileId &lt;fileid&gt;<br>The SECOND last received file id is stored in this reading</li> 
  <br><b>Note: All prev... Readings are not triggering events</b><br>
  <br>

    <li>sentMsgId &lt;text&gt;<br>The id of the last sent message is stored in this reading, if not succesful the id is empty</li> 
    <li>sentMsgResult &lt;text&gt;<br>The result of the send process for the last message is contained in this reading - SUCCESS if succesful</li> 

  <br>
    <li>StoredCommands &lt;text&gt;<br>A list of the last commands executed through TelegramBot. Maximum 10 commands are stored.</li> 

  <br>
    <li>PollingErrCount &lt;number&gt;<br>Show the number of polling errors during the last day. The number is reset at the beginning of the next day.</li> 
    <li>PollingLastError &lt;number&gt;<br>Last error message that occured during a polling update call</li> 
    
  </ul>
  <br><br>
  
  <a name="TelegramBotexamples"></a>
  <b>Examples</b>
  <br><br>
  <ul>

     <li>Send a telegram message if fhem has been newly started
      <p>
      <code>define notify_fhem_reload notify global:INITIALIZED set &lt;telegrambot&gt; message fhem started - just now </code>
      </p> 
    </li> 
  <br>

  <li>A command, that will retrieve an SVG plot and send this as a message back (can be also defined as a favorite).
      <p>
      Send the following message as a command to the bot <code>ok fhem { plotAsPng('SVG_FileLog_Aussen') }</code> 
      <br>assuming <code>ok fhem</code> is the command keyword)
      </p> (
      
      The png picture created by plotAsPng will then be send back in image format to the telegram client. This also works with other pictures returned and should also work with other media files (e.g. MP3 and doc files). The command can also be defined in a favorite.<br>
      Remark: Example requires librsvg installed
    </li> 
  <br>

    <li>Allow telegram bot commands to be used<br>
        If the keywords for commands are starting with a slash (/), the corresponding commands can be also defined with the 
        <a href=http://botsfortelegram.com/project/the-bot-father/>Bot Father</a>. So if a slash is typed a list of the commands will be automatically shown. Assuming that <code>cmdSentCommands</code> is set to <code>/History</code>. Then you can initiate the communication with the botfather, select the right bot and then with the command <code>/setcommands</code> define one or more commands like
        <p>
          <code>History-Show a history of the last 10 executed commands</code>
        </p> 
        When typing a slash, then the text above will immediately show up in the client.
    </li> 

    </ul>
</ul>

=end html
=cut
