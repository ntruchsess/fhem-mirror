##############################################
# $Id$

# Note: this is not really a telnet server, but a TCP server with slight telnet
# features (disable echo on password)

package main;
use strict;
use warnings;
use TcpServerUtils;

##########################
sub
websocket_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "websocket::Define";
  $hash->{ReadFn}   = "websocket::Read";
  $hash->{UndefFn}  = "websocket::Undef";
  $hash->{AttrFn}   = "websocket::Attr";
  $hash->{NotifyFn} = "websocket::Notify";
  $hash->{AttrList} = "allowfrom SSL";
}

package websocket;

use strict;
use warnings;
use JSON;

use GPUtils qw(:all);

BEGIN {GP_Import(qw(
  TcpServer_Open
  TcpServer_Accept
  TcpServer_SetSSL
  TcpServer_Close
  AnalyzeCommandChain
  CommandDelete
  CommandInform
  Log3
))};

##########################
sub
Define($$$)
{
  my ($hash, $def) = @_;

  my @a = split("[ \t][ \t]*", $def);
  my ($name, $type, $port, $global) = split("[ \t]+", $def);

  my $isServer = 1 if(defined($port) && $port =~ m/^(IPV6:)?\d+$/);
  
  return "Usage: define <name> websocket { [IPV6:]<tcp-portnr> [global] }"
        if(!($isServer) ||
            ($global && $global ne "global"));

  # Make sure that fhem only runs once
  if($isServer) {
    my $ret = TcpServer_Open($hash, $port, $global);
    if($ret && !$init_done) {
      Log3 $name, 1, "$ret. Exiting.";
      exit(1);
    }
    return $ret;
  }
  
  $hash->{NOTIFYDEV} = 'global';
}

##########################
sub
Read($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  if($hash->{SERVERSOCKET}) {   # Accept and create a child
    my $chash = TcpServer_Accept($hash, "telnet");
    return if(!$chash);
    $chash->{handshake} = Protocol::WebSocket::Handshake::Server->new;
    $chash->{NOTIFYDEV} = '*';
    %ntfyHash = ();
    return;
  }

  my $buf;
  my $ret = sysread($hash->{CD}, $buf, 256);
  if(!defined($ret) || $ret <= 0) {
    CommandDelete(undef, $name);
    return;
  }

  my $frame = $hash->{frame};
  unless (defined $frame) {
    if (defined my $hs = $hash->{handshake}) {
      $hs->parse($buf);
      if ($hs->is_done) { # tells us when handshake is done
        $frame = $hs->build_frame;
        $hash->{frame} = $frame;
      }
    } else {
      return;
    }
  }
  if (defined $frame) {
    $frame->append($buf);
    while (defined(my $message = $frame->next)) {
      MESSAGE: {
        $frame->is_continuation and do {
          Log3 ($name,5,"websocket continuation $message");
          last;
        };
        $frame->is_text and do {
          Log3 ($name,5,"websocket text $message");
          onTextMessage($hash,$message);
          last;
        };
        $frame->is_binary and do {
          Log3 ($name,5,"websocket binary $message");
          last;
        };
        $frame->is_ping and do {
          Log3 ($name,5,"websocket ping $message");
          last;
        };
        $frame->is_pong and do {
          Log3 ($name,5,"websocket pong $message");
          last;
        };
        $frame->is_close and do {
          Log3 ($name,5,"websocket close $message");
          onClose($hash,$message);
          last;
        };
      }
    }
    return;
  }
}

##########################
sub
Attr(@)
{
  my @a = @_;
  my $hash = $defs{$a[1]};

  if($a[0] eq "set" && $a[2] eq "SSL") {
    TcpServer_SetSSL($hash);
    if($hash->{CD}) {
      my $ret = IO::Socket::SSL->start_SSL($hash->{CD});
      Log3 $a[1], 1, "$hash->{NAME} start_SSL: $ret" if($ret);
    }
  }
  return undef;
}

sub
Undef($$) {
  my ($hash, $arg) = @_;
  return TcpServer_Close($hash);
}

sub Notify() {
  my ($hash,$dev) = @_;

  return unless $hash->{CD}; # for connected clients only
  my $json = encode_json {
    event => {
      name => $dev->{NAME},
      changed => [map {$_=~ /^([^:]+)(: )?(.*)$/; defined $3 and $3 ne "" ? $1 => $3 : 'state' => $1 } @{$dev->{CHANGED}}];
    }
  };
  Log3($hash->{NAME},5,"websocket notify: $json");
  sendMessage($hash, buffer => $json);
}

sub
onTextMessage($$) {
  my ($cl,$message) = @_;
  $ret = AnalyzeCommandChain($cl, $message);
}

sub
onClose($) {
  my ($cl) = @_;
  # Send close frame back
  sendMessage($cl, type => 'close'); #, version => $cl->{handshake}->version);
  TcpServer_Close($cl);
  CommandDelete(undef, $cl->{NAME});
}

sub
sendMessage($%) {
  my ($cl,%msg) = @_;
  syswrite($cl->{CD}, $cl->{handshake}->build_frame(%msg)->to_bytes);
}
1;

=pod
=begin html

<a name="telnet"></a>
<h3>telnet</h3>
<ul>
  <br>
  <a name="telnetdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; telnet &lt;portNumber&gt; [global]</code><br>
    or<br>
    <code>define &lt;name&gt; telnet &lt;servername&gt:&lt;portNumber&gt;</code>
    <br><br>

    First form, <b>server</b> mode:<br>
    Listen on the TCP/IP port <code>&lt;portNumber&gt;</code> for incoming
    connections. If the second parameter global is <b>not</b> specified,
    the server will only listen to localhost connections.
    <br>
    To use IPV6, specify the portNumber as IPV6:&lt;number&gt;, in this
    case the perl module IO::Socket:INET6 will be requested.
    On Linux you may have to install it with cpan -i IO::Socket::INET6 or
    apt-get libio-socket-inet6-perl; OSX and the FritzBox-7390 perl already has
    this module.<br>
    Examples:
    <ul>
        <code>define tPort telnet 7072 global</code><br>
        <code>attr tPort globalpassword mySecret</code><br>
        <code>attr tPort SSL</code><br>
    </ul>
    Note: The old global attribute port is automatically converted to a
    telnet instance with the name telnetPort. The global allowfrom attibute is
    lost in this conversion.

    <br><br>
    Second form, <b>client</b> mode:<br>
    Connect to the specified server port, and execute commands received from
    there just like in server mode. This can be used to connect to a fhem
    instance sitting behind a firewall, when installing exceptions in the
    firewall is not desired or possible. Note: this client mode supprts SSL,
    but not IPV6.<br>
    Example:
    <ul>
      Start tcptee first on publicly reachable host outside the firewall.<ul>
        perl contrib/tcptee.pl --bidi 3000</ul>
      Configure fhem inside the firewall:<ul>
        define tClient telnet &lt;tcptee_host&gt;:3000</ul>
      Connect to the fhem from outside of the firewall:<ul>
        telnet &lt;tcptee_host&gt; 3000</ul>
    </ul>

  </ul>
  <br>


  <a name="telnetset"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="telnetget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="telnetattr"></a>
  <b>Attributes:</b>
  <ul>
    <a name="password"></a>
    <li>password<br>
        Specify a password, which has to be entered as the very first string
        after the connection is established. If the argument is enclosed in {},
        then it will be evaluated, and the $password variable will be set to
        the password entered. If the return value is true, then the password
        will be accepted. If thies parameter is specified, fhem sends telnet
        IAC requests to supress echo while entering the password.
        Also all returned lines are terminated with \r\n.
        Example:<br>
        <ul>
        <code>
        attr tPort password secret<br>
        attr tPort password {"$password" eq "secret"}
        </code>
        </ul>
        Note: if this attribute is set, you have to specify a password as the
        first argument when using fhem.pl in client mode:
        <ul>
          perl fhem.pl localhost:7072 secret "set lamp on"
        </ul>
        </li><br>

    <a name="globalpassword"></a>
    <li>globalpassword<br>
        Just like the attribute password, but a password will only required for
        non-local connections.
        </li><br>

    <a name="SSL"></a>
    <li>SSL<br>
        Enable SSL encryption of the connection, see the description <a
        href="#HTTPS">here</a> on generating the needed SSL certificates. To
        connect to such a port use one of the following commands:
        <ul>
          socat openssl:fhemhost:fhemport,verify=0 readline<br>
          ncat --ssl fhemhost fhemport<br>
          openssl s_client -connect fhemhost:fhemport<br>
        </ul>
        </li><br>

    <a name="allowfrom"></a>
    <li>allowfrom<br>
        Regexp of allowed ip-addresses or hostnames. If set,
        only connections from these addresses are allowed.
        </li><br>

    <a name="connectTimeout"></a>
    <li>connectTimeout<br>
        Wait at maximum this many seconds for the connection to be established.
        Default is 2.
        </li><br>

    <a name="connectInterval"></a>
    <li>connectInterval<br>
        After closing a connection, or if a connection cannot be estblished,
        try to connect again after this many seconds. Default is 60.
        </li><br>

    <a name="encoding"></a>
    <li>encoding<br>
        Sets the encoding for the data send to the client. Possible values are latin1 and utf8. Default is utf8.
        </li><br>


  </ul>

</ul>

=end html

=begin html_DE

<a name="telnet"></a>
<h3>telnet</h3>
<ul>
  <br>
  <a name="telnetdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; telnet &lt;portNumber&gt; [global]</code><br>
    oder<br>
    <code>define &lt;name&gt; telnet &lt;servername&gt:&lt;portNummer&gt;</code>
    <br><br>

    Erste Form, <b>Server</b>-mode:<br>
    &Uuml;berwacht den TCP/IP-Port <code>&lt;portNummer&gt;</code> auf
    ankommende Verbindungen. Wenn der zweite Parameter gobal <b>nicht</b>
    angegeben wird, wird der Server nur auf Verbindungen von localhost achten.

    <br>
    F&uuml;r den Gebrauch von IPV6 muss die Portnummer als IPV6:&lt;nummer&gt;
    angegeben werden, in diesem Fall wird das Perl-Modul IO::Socket:INET6
    angesprochen. Unter Linux kann es sein, dass dieses Modul mittels cpan -i
    IO::Socket::INET6 oder apt-get libio-socket-inet6-perl nachinstalliert werden
    muss; OSX und Fritzbox-7390 enthalten bereits dieses Modul.<br>

    Beispiele:
    <ul>
        <code>define tPort telnet 7072 global</code><br>
        <code>attr tPort globalpassword mySecret</code><br>
        <code>attr tPort SSL</code><br>
    </ul>
    Hinweis: Das alte (pre 5.3) "global attribute port" wird automatisch in
    eine telnet-Instanz mit dem Namen telnetPort umgewandelt. Im Rahmen dieser
    Umwandlung geht das globale Attribut allowfrom verloren.

    <br><br>
    Zweite Form, <b>Client</b>-mode:<br>
    Verbindet zu einem angegebenen Server-Port und f&uuml;hrt die von dort aus
    empfangenen Anweisungen - genau wie im Server-mode - aus. Dies kann
    verwendet werden, um sich mit einer fhem-Instanz, die sich hinter einer
    Firewall befindet, zu verbinden, f&uuml;r den Fall, wenn das Installieren
    von Ausnahmen in der Firewall nicht erw&uuml;nscht oder nicht m&ouml;glich
    sind. Hinweis: Dieser Client-mode unterst&uuml;tzt zwar SSL, aber nicht
    IPV6.<br>

    Beispiel:
    <ul>
      Starten von tcptee auf einem &ouml;ffentlich erreichbaren Host ausserhalb
      der Firewall:<ul>
        <code>perl contrib/tcptee.pl --bidi 3000</code></ul>
      Konfigurieren von fhem innerhalb der Firewall:<ul>
        <code>define tClient telnet &lt;tcptee_host&gt;:3000</code></ul>
      Verbinden mit fhem (hinter der Firewall) von ausserhalb der Firewall:<ul>
        <code>telnet &lt;tcptee_host&gt; 3000</code></ul>
    </ul>

  </ul>
  <br>


  <a name="telnetset"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="telnetget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="telnetattr"></a>
  <b>Attribute</b>
  <ul>
    <a name="password"></a>
    <li>password<br>
        Bezeichnet ein Passwort, welches als allererster String eingegeben
        werden muss, nachdem die Verbindung aufgebaut wurde. Wenn das Argument
        in {} eingebettet ist, dann wird es als Perl-Ausdruck ausgewertet, und
        die Variable $password mit dem eingegebenen Passwort verglichen. Ist
        der zur&uuml;ckgegebene Wert wahr (true), wurde das Passwort
        akzeptiert.  Falls dieser Parameter gesetzt wird, sendet fhem
        telnet IAC Requests, um ein Echo w&auml;hrend der Passworteingabe zu
        unterdr&uuml;cken. Ebenso werden alle zur&uuml;ckgegebenen Zeilen mit
        \r\n abgeschlossen.

        Beispiel:<br>
        <ul>
        <code>
        attr tPort password secret<br>
        attr tPort password {"$password" eq "secret"}
        </code>
        </ul>
        Hinweis: Falls dieses Attribut gesetzt wird, muss als erstes Argument
        ein Passwort angegeben werden, wenn fhem.pl im Client-mode betrieben
        wird:
        <ul>
        <code>
          perl fhem.pl localhost:7072 secret "set lamp on"
        </code>
        </ul>
        </li><br>

    <a name="globalpassword"></a>
    <li>globalpassword<br>
        Entspricht dem Attribut password; ein Passwort wird aber
        ausschlie&szlig;lich f&uuml;r nicht-lokale Verbindungen verlangt.
        </li><br>

    <a name="SSL"></a>
    <li>SSL<br>
        SSL-Verschl&uuml;sselung f&uuml;r eine Verbindung aktivieren. <a
        href="#HTTPS">Hier</a> gibt es eine Beschreibung, wie das erforderliche
        SSL-Zertifikat generiert werden kann. Um eine Verbindung mit solch
        einem Port herzustellen, sind folgende Befehle m&ouml;glich:
        <ul>
        <code>
          socat openssl:fhemhost:fhemport,verify=0 readline<br>
          ncat --ssl fhemhost fhemport<br>
          openssl s_client -connect fhemhost:fhemport<br>
        </code>
        </ul>		
	</li><br>

    <a name="allowfrom"></a>
    <li>allowfrom<br>
        Regexp der erlaubten IP-Adressen oder Hostnamen. Wenn dieses Attribut
        gesetzt wurde, werden ausschlie&szlig;lich Verbindungen von diesen
        Adressen akzeptiert.
        </li><br>

    <a name="connectTimeout"></a>
    <li>connectTimeout<br>
        Gibt die maximale Wartezeit in Sekunden an, in der die Verbindung
        aufgebaut sein muss. Standardwert ist 2.
    </li><br>

    <a name="connectInterval"></a>
    <li>connectInterval<br>
        Gibt die Dauer an, die entweder nach Schlie&szlig;en einer Verbindung
        oder f&uuml;r den Fall, dass die Verbindung nicht zustande kommt,
        gewartet werden muss, bis ein erneuter Verbindungsversuch gestartet
        werden soll. Standardwert ist 60.
        </li><br>

    <a name="encoding"></a>
    <li>encoding<br>
        Bezeichnet die Zeichentabelle f&uuml;r die zum Client gesendeten Daten.
        M&ouml;gliche Werte sind utf8 und latin1. Standardwert ist utf8. 
    </li><br>


  </ul>

</ul>

=end html_DE

=cut

1;
