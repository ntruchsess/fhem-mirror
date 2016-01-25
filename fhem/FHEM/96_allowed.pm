##############################################
# $Id$
package main;

use strict;
use warnings;

#####################################
sub
allowed_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn} = "allowed_Define";
  $hash->{AuthorizeFn} = "allowed_Authorize";
  $hash->{AuthenticateFn} = "allowed_Authenticate";
  $hash->{AttrFn}   = "allowed_Attr";
  $hash->{AttrList} = "disable:0,1 validFor allowedCommands allowedDevices ".
                        "basicAuth basicAuthMsg password globalpassword ".
                        "basicAuthExpiry";
  $hash->{UndefFn} = "allowed_Undef";
}


#####################################
sub
allowed_Define($$)
{
  my ($hash, $def) = @_;
  my @l = split(" ", $def);

  if(@l > 2) {
    my %list;
    for(my $i=2; $i<@l; $i++) {
      $list{$l[$i]} = 1;
    }
    $hash->{devices} = \%list;
  }
  $auth_refresh = 1;
  readingsSingleUpdate($hash, "state", "active", 0);
  return undef;
}

sub
allowed_Undef($$)
{
  $auth_refresh = 1;
  return undef;
}

#####################################
# Return 0 for don't care, 1 for Allowed, 2 for forbidden.
sub
allowed_Authorize($$$$)
{
  my ($me, $cl, $type, $arg) = @_;

  return 0 if($me->{disabled});
  return 0 if(!$me->{validFor} || $me->{validFor} !~ m/\b$cl->{SNAME}\b/);

  if($type eq "cmd") {
    return 0 if(!$me->{allowedCommands});
    # Return 0: allow stacking with other instances, see Forum#46380
    return ($me->{allowedCommands} =~ m/\b$arg\b/) ? 0 : 2;
  }

  if($type eq "devicename") {
    return 0 if(!$me->{allowedDevices});
    return ($me->{allowedDevices} =~ m/\b$arg\b/) ? 0 : 2;
  }

  return 0;
}

#####################################
# Return 0 for authentication not needed, 1 for auth-ok, 2 for wrong password
sub
allowed_Authenticate($$$$)
{
  my ($me, $cl, $param) = @_;

  return 0 if($me->{disabled});
  return 0 if(!$me->{validFor} || $me->{validFor} !~ m/\b$cl->{SNAME}\b/);
  my $aName = $me->{NAME};

  if($cl->{TYPE} eq "FHEMWEB") {
    my $basicAuth = AttrVal($aName, "basicAuth", undef);
    delete $cl->{".httpAuthHeader"};
    return 0 if(!$basicAuth);

    my $FW_httpheader = $param;
    my $secret = $FW_httpheader->{Authorization};
    $secret =~ s/^Basic //i if($secret);
    
    # Check for Cookie in headers if no basicAuth header is set
    my $authcookie;
    if ( ( ! $secret ) && ( $FW_httpheader->{Cookie} ) ) {
      if ( AttrVal($aName, "basicAuthExpiry", 0)) {  
        my $cookie = "; ".$FW_httpheader->{Cookie}.";"; 
        $authcookie = $1 if ( $cookie =~ /; AuthToken=([^;]+);/ ); 
        $secret = $authcookie;
      }
    }
    
    my $pwok = ($secret && $secret eq $basicAuth);      # Base64
    if($secret && $basicAuth =~ m/^{.*}$/) {
      eval "use MIME::Base64";
      if($@) {
        Log3 $aName, 1, $@;

      } else {
        my ($user, $password) = split(":", decode_base64($secret));
        $pwok = eval $basicAuth;
        Log3 $aName, 1, "basicAuth expression: $@" if($@);
      }
    }

    # Add Cookie header ONLY if 
    #   authentication with basic auth was succesful 
    #   (meaning if no or wrong authcookie set)
    if ( ( $pwok ) &&  
         ( ( ! defined($authcookie) ) || ( $secret ne $authcookie ) ) ) {
      # no cookie set but authorization succesful
      # check if cookie should be set --> Cookie Attribute != 0 
      my $time = int(AttrVal($aName, "basicAuthExpiry", 0));
      if ( $time ) {
        # time specified in days until next expiry (but timestamp is in seconds)
        $time *= 86400;
        $time += time();
        # generate timestamp according to RFC-1130 in Expires
        my $expires = "Expires=".FmtDateTimeRFC1123($time);
        # set header with expiry
        $cl->{".httpAuthHeader"} = "Set-Cookie: AuthToken=".$secret.
                "; Path=/ ; ".$expires."\r\n" ;
      }
    } 

    return 1 if($pwok);

    my $msg = AttrVal($aName, "basicAuthMsg", "FHEM: login required");
    $cl->{".httpAuthHeader"} = "HTTP/1.1 401 Authorization Required\r\n".
                               "WWW-Authenticate: Basic realm=\"$msg\"\r\n";
    return 2;
  }

  if($cl->{TYPE} eq "telnet") {
    my $pw = AttrVal($aName, "password", undef);
    if(!$pw) {
      $pw = AttrVal($aName, "globalpassword", undef);
      $pw = undef if($pw && $cl->{NAME} =~ m/_127.0.0.1_/);
    }
    return 0 if(!$pw);
    return 2 if(!defined($param));
    if($pw =~ m/^{.*}$/) {
      my $password = $param;
      my $ret = eval $pw;
      Log3 $aName, 1, "password expression: $@" if($@);
      return ($ret ? 1 : 2);
    }
    return ($pw eq $param) ? 1 : 2;
  }

  return 0;
}


sub
allowed_Attr(@)
{
  my ($type, $devName, $attrName, @param) = @_;
  my $hash = $defs{$devName};

  my $set = ($type eq "del" ? 0 : (!defined($param[0]) || $param[0]) ? 1 : 0);

  if($attrName eq "disable") {
    readingsSingleUpdate($hash, "state", $set ? "disabled" : "active", 1);
    if($set) {
      $hash->{disable} = 1;
    } else {
      delete($hash->{disable});
    }

  } elsif($attrName eq "allowedCommands" ||     # hoping for some speedup
          $attrName eq "allowedDevices"  ||
          $attrName eq "validFor") {
    if($set) {
      $hash->{$attrName} = join(" ", @param);
    } else {
      delete($hash->{$attrName});
    }

  } elsif(($attrName eq "basicAuth" ||
           $attrName eq "password" || $attrName eq "globalpassword") && 
          $type eq "set") {
    foreach my $d (devspec2array("TYPE=(FHEMWEB|telnet)")) {
      delete $defs{$d}{Authenticated} if($defs{$d});
    }
  }

  return undef;
}

1;

=pod
=item helper
=begin html

<a name="allowed"></a>
<h3>allowed</h3>
<ul>
  <br>

  <a name="alloweddefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; allowed &lt;deviceList&gt;</code>
    <br><br>
    Authorize execution of commands and modification of devices based on the
    frontend used and/or authenticate users.<br><br>

    If there are multiple instances defined which are valid for a given
    frontend device, then all authorizations must succeed. For authentication
    it is sufficient when one of the instances succeeds. The checks are
    executed in alphabetical order of the allowed instance names.<br><br>

    <b>Note:</b> this module should work as intended, but no guarantee
    can be given that there is no way to circumvent it.<br><br>
    Examples:
    <ul><code>
      define allowedWEB allowed<br>
      attr allowedWEB validFor WEB,WEBphone,WEBtablet<br>
      attr allowedWEB basicAuth { "$user:$password" eq "admin:secret" }<br>
      attr allowedWEB allowedCommands set,get<br><br>

      define allowedTelnet allowed<br>
      attr allowedTelnet validFor telnetPort<br>
      attr allowedTelnet password secret<br>
    </code></ul>
    <br>
  </ul>

  <a name="allowedset"></a>
  <b>Set:</b> <ul>N/A</ul><br>

  <a name="allowedget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="allowedattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#disable">disable</a></li><br>

    <a name="allowedCommands"></a>
    <li>allowedCommands<br>
        A comma separated list of commands allowed from the matching frontend
        (see validFor).<br>
        If set to an empty list <code>, (i.e. comma only)</code>
        then no comands are allowed. If set to <code>get,set</code>, then only
        a "regular" usage is allowed via set and get, but changing any
        configuration is forbidden.<br>
        </li><br>

    <a name="allowedDevices"></a>
    <li>allowedDevices<br>
        A comma separated list of device names which can be manipulated via the
        matching frontend (see validFor).
        </li><br>

    <a name="basicAuth"></a>
    <li>basicAuth, basicAuthMsg<br>
        request a username/password authentication for FHEMWEB access. You have
        to set the basicAuth attribute to the Base64 encoded value of
        &lt;user&gt;:&lt;password&gt;, e.g.:<ul>
        # Calculate first the encoded string with the commandline program<br>
        $ echo -n fhemuser:secret | base64<br>
        ZmhlbXVzZXI6c2VjcmV0<br>
        # Set the FHEM attribute<br>
        attr allowed_WEB basicAuth ZmhlbXVzZXI6c2VjcmV0
        </ul>
        You can of course use other means of base64 encoding, e.g. online
        Base64 encoders.<br>

        If the argument of basicAuth is enclosed in { }, then it will be
        evaluated, and the $user and $password variable will be set to the
        values entered. If the return value is true, then the password will be
        accepted.<br>

        If basicAuthMsg is set, it will be displayed in the
        popup window when requesting the username/password.<br>

        Example:<br>
        <ul><code>
          attr allowedWEB basicAuth { "$user:$password" eq "admin:secret" }<br>
        </code></ul>
    </li><br>

    <a name="basicAuthExpiry"></a>
    <li>basicAuthExpiry<br>
        allow the basicAuth to be kept valid for a given number of days. 
        So username/password as specified in basicAuth are only requested 
        after a certain period. 
        This is achieved by sending a cookie to the browser that will expire 
        after the given period.
        Only valid if basicAuth is set.
    </li><br>

    <a name="password"></a>
    <li>password<br>
        Specify a password for telnet instances, which has to be entered as the
        very first string after the connection is established. If the argument
        is enclosed in {}, then it will be evaluated, and the $password
        variable will be set to the password entered. If the return value is
        true, then the password will be accepted. If this parameter is
        specified, FHEM sends telnet IAC requests to supress echo while
        entering the password.  Also all returned lines are terminated with
        \r\n.
        Example:<br>
        <ul>
        <code>
        attr allowed_tPort password secret<br>
        attr allowed_tPort password {"$password" eq "secret"}
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


    <a name="validFor"></a>
    <li>validFor<br>
        A comma separated list of frontend names. Currently supported frontends
        are all devices connected through the FHEM TCP/IP library, e.g. telnet
        and FHEMWEB. <b>Note: changed behaviour:</b>The allowed instance is
        only active, if this attribute is set.
        </li>

  </ul>
  <br>

</ul>

=end html

=begin html_DE

<a name="allowed"></a>
<h3>allowed</h3>
<ul>
  <br>

  <a name="alloweddefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; allowed &lt;deviceList&gt;</code>
    <br><br>
    Authorisiert das Ausf&uuml;hren von Kommandos oder das &Auml;ndern von
    Ger&auml;ten abh&auml;ngig vom verwendeten Frontend.<br>

    Falls man mehrere allowed Instanzen definiert hat, die f&uuml;r dasselbe
    Frontend verantwortlich sind, dann m&uuml;ssen alle Authorisierungen
    genehmigt sein, um das Befehl ausf&uuml;hren zu k&ouml;nnen. Auf der
    anderen Seite reicht es, wenn einer der Authentifizierungen positiv
    entschieden wird.  Die Pr&uuml;fungen werden in alphabetischer Reihenfolge
    der Instanznamen ausgef&uuml;hrt.  <br><br>

    <b>Achtung:</b> das Modul sollte wie hier beschrieben funktionieren,
    allerdings k&ouml;nnen wir keine Garantie geben, da&szlig; man sie nicht
    &uuml;berlisten, und Schaden anrichten kann.<br><br>

    Beispiele:
    <ul><code>
      define allowedWEB allowed<br>
      attr allowedWEB validFor WEB,WEBphone,WEBtablet<br>
      attr allowedWEB basicAuth { "$user:$password" eq "admin:secret" }<br>
      attr allowedWEB allowedCommands set,get<br><br>

      define allowedTelnet allowed<br>
      attr allowedTelnet validFor telnetPort<br>
      attr allowedTelnet password secret<br>
    </code></ul>
    <br>
  </ul>

  <a name="allowedset"></a>
  <b>Set:</b> <ul>N/A</ul><br>

  <a name="allowedget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="allowedattr"></a>
  <b>Attribute</b>
  <ul>
    <li><a href="#disable">disable</a>
      </li><br>

    <a name="allowedCommands"></a>
    <li>allowedCommands<br>
        Eine Komma getrennte Liste der erlaubten Befehle des passenden
        Frontends (siehe validFor). Bei einer leeren Liste (, dh. nur ein
        Komma)  wird dieser Frontend "read-only".
        Falls es auf <code>get,set</code> gesetzt ist, dann sind in dieser
        Frontend keine Konfigurations&auml;nderungen m&ouml;glich, nur
        "normale" Bedienung der Schalter/etc.
        </li><br>

    <a name="allowedDevices"></a>
    <li>allowedDevices<br>
        Komma getrennte Liste von Ger&auml;tenamen, die mit dem passenden
        Frontend (siehe validFor) ge&auml;ndert werden k&ouml;nnen.
        </li><br>

    <a name="basicAuth"></a>
    <li>basicAuth, basicAuthMsg<br>
        Betrifft nur FHEMWEB Instanzen (siehe validFor): Fragt username /
        password zur Autentifizierung ab. Es gibt mehrere Varianten:
        <ul>
        <li>falls das Argument <b>nicht</b> in { } eingeschlossen ist, dann wird
          es als base64 kodiertes benutzername:passwort interpretiert.
          Um sowas zu erzeugen kann man entweder einen der zahlreichen
          Webdienste verwenden, oder das base64 Programm. Beispiel:
          <ul><code>
            $ echo -n fhemuser:secret | base64<br>
            ZmhlbXVzZXI6c2VjcmV0<br>
            fhem.cfg:<br>
            attr WEB basicAuth ZmhlbXVzZXI6c2VjcmV0
          </code></ul>
          </li>
        <li>Werden die Argumente in { } angegeben, wird es als perl-Ausdruck
          ausgewertet, die Variablen $user and $password werden auf die
          eingegebenen Werte gesetzt. Falls der R&uuml;ckgabewert wahr ist,
          wird die Anmeldung akzeptiert.

          Beispiel:<br>
          <ul><code>
            attr allwedWEB basicAuth { "$user:$password" eq "admin:secret" }<br>
          </code></ul>
          </li>
        </ul>
    </li><br>


    <a name="password"></a>
    <li>password<br>
        Betrifft nur telnet Instanzen (siehe validFor): Bezeichnet ein
        Passwort, welches als allererster String eingegeben werden muss,
        nachdem die Verbindung aufgebaut wurde. Wenn das Argument in { }
        eingebettet ist, dann wird es als Perl-Ausdruck ausgewertet, und die
        Variable $password mit dem eingegebenen Passwort verglichen. Ist der
        zur&uuml;ckgegebene Wert wahr (true), wird das Passwort akzeptiert.
        Falls dieser Parameter gesetzt wird, sendet FHEM telnet IAC Requests,
        um ein Echo w&auml;hrend der Passworteingabe zu unterdr&uuml;cken.
        Ebenso werden alle zur&uuml;ckgegebenen Zeilen mit \r\n abgeschlossen.

        Beispiel:<br>
        <ul>
        <code>
        attr allowed_tPort password secret<br>
        attr allowed_tPort password {"$password" eq "secret"}
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
        Betrifft nur telnet Instanzen (siehe validFor): Entspricht dem
        Attribut password; ein Passwort wird aber ausschlie&szlig;lich f&uuml;r
        nicht-lokale Verbindungen verlangt.
        </li><br>

    <a name="validFor"></a>
    <li>validFor<br>
        Komma separierte Liste von Frontend-Instanznamen.  Aktuell werden nur
        Frontends unterst&uuml;tzt, die das FHEM TCP/IP Bibliothek verwenden,
        z.Bsp. telnet und FHEMWEB. <b>Achtung, &Auml;nderung:</b> falls nicht
        gesetzt, ist die allowed Instanz nicht aktiv.
        </li>

  </ul>
  <br>

</ul>
=end html_DE

=cut
