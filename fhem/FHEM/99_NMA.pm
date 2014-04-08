##############################################
#
# A module to send notifications to NotifyMyAndroid.
#
# written 2014 by Jonas Hess <jonas.b.hess at gmail.com>
#
##############################################
#
# Definition:
# define <name> NMA <apikey>
#
# Example:
# define NMA1 NMA 1234567890abcdef1234567890deadbeef1234567890affe
#
#
# You can send messages via the following command:
# set <NMA_device> msg <application> <event> <description> <priority>
#
# Examples:
# set NMA1 msg 'FHEM' 'Rauchmelder Kinderzimmer' 'Der Rauchmelder im Kinderzimmer hat ausgelöst' 2
# set NMA1 msg 'FHEM' 'Türklingel' 'Es hat geklingelt' 0
#
#
#
# For further documentation of these parameters:
# https://www.notifymyandroid.com/api.jsp


package main;

use HttpUtils;
use utf8;

my %sets = (
  "msg" => 1
);

sub NMA_Initialize($$)
{
  my ($hash) = @_;
  $hash->{DefFn}    = "NMA_Define";
  $hash->{SetFn}    = "NMA_Set";
}

sub NMA_Define($$)
{
  my ($hash, $def) = @_;
  
  my @args = split("[ \t]+", $def);
  
  if (int(@args) < 1)
  {
    return "Invalid number of arguments: define <name> NMA <apikey>";
  }
  
  my ($name, $type, $apikey) = @args;
  
  $hash->{STATE} = 'Initialized';
  
  if(defined($apikey))
  {    
    $hash->{apikey} = $apikey;
    return undef;
  }
  else
  {
    return "apikey missing.";
  }
}

sub NMA_Set($@)
{
  my ($hash, $name, $cmd, @args) = @_;
  
  if (!defined($sets{$cmd}))
  {
    return "Unknown argument " . $cmd . ", choose one of " . join(" ", sort keys %sets);
  }

  if ($cmd eq 'msg')
  {
    return NMA_Set_Message($hash, @args);
  }
}

sub NMA_Set_Message
{
  my $hash = shift; 
  my $attr = join(" ", @_);
  my $shortExpressionMatched = 0;

   if($attr =~ /(".*"|'.*')\s*(".*"|'.*')\s*(".*"|'.*')\s*(-?\d+)\s*$/s)
  {
    $shortExpressionMatched = 1;
  } 
  
  my $application = "";
  my $event = "";
  my $description = "";
  my $priority = ""; 
  
  if($shortExpressionMatched == 1)
  {
    $application = $1;
    $event = $2;
    $description = $3;
    $priority = $4;
 
    if($application =~ /^['"](.*)['"]$/s)
    {
      $application = $1;
    }
    
    if($event =~ /^['"](.*)['"]$/s)
    {
      $event = $1;
    }
    
    if($description =~ /^['"](.*)['"]$/)
    {
      $description = $1;
    }
} 
 
  if((($application ne "") && ($event ne "")) && ($priority < 3))
  {
    my $body = "apikey=" . $hash->{apikey} . "&" .
    "application=" . $application . "&" .
    "event=" . $event . "&" .
    "description=" . $description;
    
    if ($priority ne "")
    {
      $body = $body . "&" . "priority=" . $priority;
    }   
    
    my $result = NMA_HTTP_Call($hash, $body);
    
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "last-message", $application . "|" . $event . ": " . $description);
    readingsBulkUpdate($hash, "last-result", $result);
    readingsEndUpdate($hash, 1);
    
    return $result;
  }
  else
  {
    return "Syntax: set <NMA_device> msg <application> <event> <description> <priority>\n given:" . $attr . "|" .$application . "|" . $event . "|" . $description;
  }
}

sub NMA_HTTP_Call($$) 
{
  my ($hash,$body) = @_;
  
  my $url = "https://www.notifymyandroid.com/publicapi/notify";
  
  $response = GetFileFromURL($url, 10, $body, 0, 5);
  
  if ($response =~ m/<success code="([0-9]*)"/)
  {
  	if ($1 eq "200")
  	{
      return "OK";
  	}
  	elsif ($response =~ m/<error code="([0-9]*)[^>]*>([^<]*)/)
  	{
      return "Error:[" . $1 . "] " . $2;
  	}
  	else
  	{
      return "Error";
  	}
  }
  else
  {
  	return "Error: No known response"
  }
}

1;

=pod
=begin html

<a name="NMA"></a>
<h3>NMA</h3>
<ul>
  NotifyMyAndroid is a service to receive instant push notifications on your
  android device from a variety of sources.<br>
  You need an account to use this module.<br>
  For further information about the service see <a href="https://www.notifymyandroid.com">https://www.notifymyandroid.com</a>.<br>
  <br>
  <br>
  <br>
  <a name="NMA_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; NMA &lt;apikey&gt;</code><br>
    <br>
    You have to create an account to get the user key.<br>
    And you have to create an application to get the API token.<br>
    <br>
    Example:
    <ul>
      <code>define NMA1 NMA 1234567890abcdef1234567890deadbeef1234567890affe</code>
    </ul>
  </ul>
  <br>
  <a name="NMASet"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; msg &lt;application&gt; &lt;event&gt; &lt;secription&gt; &lt;priority&gt;</code>
    <br>
    <br>
    Examples:
    <ul>
      <code>set NMA1 msg 'FHEM' 'Rauchmelder Kinderzimmer' 'Der Rauchmelder im Kinderzimmer hat ausgelöst' 2</code><br>
      <code>set NMA1 msg 'FHEM' 'Türklingel' 'Es hat geklingelt' 0</code><br>
    </ul>
    <br>
    Notes:
    <ul>
      <li>For further documentation of these parameters have a look at the <a href="https://www.notifymyandroid.com/api.jsp">NMA API</a>.
      </li>
    </ul>
  </ul>
  <br>
  <b>Get</b> <ul>N/A</ul><br>
  <a name="NMAAttr"></a>
  <b>Attributes</b>
  <br>
  <a name="NMAEvents"></a>
  <b>Generated events:</b>
  <ul>
     N/A
  </ul>
</ul>

=end html
=begin html_DE

<a name="NMA"></a>
<h3>NMA</h3>
<ul>
  NMA ist ein Dienst, um Benachrichtigungen von einer vielzahl
  von Quellen auf Deinem Smartphone oder Tablet zu empfangen.<br>
  Du brauchst einen Account um dieses Modul zu verwenden.<br>
  Für weitere Informationen über den Dienst besuche <a href="https://www.notifymyandroid.com">notifymyandroid.com</a>.<br>
  <br>
  <br>
  <br>
  <a name="NMADefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; NMA &lt;apikey&gt;</code><br>
    <br>
    Du musst einen Account erstellen, um den User Key zu bekommen.<br>
    Und du musst eine Anwendung erstellen, um einen API Token zu bekommen.<br>
    <br>
    Beispiel:
    <ul>
      <code>define NMA1 NMA 1234567890abcdef1234567890deadbeef1234567890affe</code>
    </ul>
  </ul>
  <br>
  <a name="NMASet"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; msg &lt;application&gt; &lt;event&gt; &lt;secription&gt; &lt;priority&gt;</code>
    <br>
    <br>
    Beispiele:
    <ul>
      <code>set NMA1 msg 'FHEM' 'Rauchmelder Kinderzimmer' 'Der Rauchmelder im Kinderzimmer hat ausgelöst' 2</code><br>
      <code>set NMA1 msg 'FHEM' 'Türklingel' 'Es hat geklingelt' 0</code><br>
    </ul>
    <br>
    Anmerkungen:
    <ul>
      <li>Für weiterführende Dokumentation über diese Parameter lies Dir die <a href="https://www.notifymyandroid.com/api.jsp">NMA API</a> durch.
      </li>
    </ul>
  </ul>
  <br>
  <b>Get</b> <ul>N/A</ul><br>
  <a name="NMAAttr"></a>
  <b>Attributes</b>
  <br>
  <a name="NMAEvents"></a>
  <b>Generated events:</b>
  <ul>
     N/A
  </ul>
</ul>

=end html_DE
=cut
