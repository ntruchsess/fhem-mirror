##############################################
# $Id$

package main;
use strict;
use warnings;

sub SetExtensions($$@);
sub SetExtensionsFn($);

sub
SetExtensionsCancel($)
{
  my ($hash) = @_;
  $hash = $defs{$hash} if( ref($hash) ne 'ARRAY' );

  return undef if( !$hash );
  my $name = $hash->{NAME};

  return undef if( !$hash->{SetExtensionTimer} );
  my $cmd = $hash->{SetExtensionTimer}{CMD};

  RemoveInternalTimer("SE $name $cmd");

  delete $hash->{SetExtensionTimer};

  return undef;
}

sub
SetExtensions($$@)
{
  my ($hash, $list, $name, $cmd, @a) = @_;

  return "Unknown argument $cmd, choose one of " if(!$list);

  my %se_list = (
    "on-for-timer"      => 1,
    "off-for-timer"     => 1,
    "on-till"           => 1,
    "off-till"          => 1,
    "on-till-overnight" => 1,
    "off-till-overnight"=> 1,
    "blink"             => 2,
    "intervals"         => 0,
    "toggle"            => 0
  );

  my $hasOn  = ($list =~ m/(^| )on\b/);
  my $hasOff = ($list =~ m/(^| )off\b/);
  my $value = Value($name);
  my $em = AttrVal($name, "eventMap", undef);
  if($em) {
    if(!$hasOn || !$hasOff) {
      $hasOn  = ($em =~ m/:on\b/)  if(!$hasOn);
      $hasOff = ($em =~ m/:off\b/) if(!$hasOff);
    }
    # Following is fix for P#1: /B0:on/on-for-timer 300:5Min/
    # $cmd = ReplaceEventMap($name, $cmd, 1) if($cmd ne "?");
    # Has problem with P#2 (Forum #28855): /on-for-timer 300:5Min/on:Ein/
    # Workaround for P#1 /on-for-timer 300:5Min/on-for-timer:on-for-timer/B0:on/
    (undef,$value) = ReplaceEventMap($name, [$name, $value], 0) if($cmd ne "?");
  }
  if(!$hasOn || !$hasOff) { # No extension
    return "Unknown argument $cmd, choose one of $list";
  }

  if(!defined($se_list{$cmd})) {
    # Add only "new" commands
    my @mylist = grep { $list !~ m/\b$_\b/ } keys %se_list;
    return "Unknown argument $cmd, choose one of $list " .
        join(" ", @mylist);
  }
  if($se_list{$cmd} && $se_list{$cmd} != int(@a)) {
    return "$cmd requires $se_list{$cmd} parameter";
  }

  my $cmd1 = ($cmd =~ m/^on.*/ ? "on" : "off");
  my $cmd2 = ($cmd =~ m/^on.*/ ? "off" : "on");
  my $param = $a[0];

  if($cmd eq "on-for-timer" || $cmd eq "off-for-timer") {
    SetExtensionsCancel($hash);
    return "$cmd requires a number as argument" if($param !~ m/^\d*\.?\d*$/);

    if($param) {
      $hash->{SetExtensionTimer} = {
        START=>time(), START_FMT=>TimeNow(), DURATION=>$param, CMD=>$cmd 
      };
      DoSet($name, $cmd1);
      InternalTimer(gettimeofday()+$param,"SetExtensionsFn","SE $name $cmd",0);
    }

  } elsif($cmd =~ m/^(on|off)-till/) {
    my ($err, $hr, $min, $sec, $fn) = GetTimeSpec($param);
    return "$cmd: $err" if($err);

    my $at = $name . "_till";
    CommandDelete(undef, $at) if($defs{$at});

    my $hms_till = sprintf("%02d:%02d:%02d", $hr, $min, $sec);
    if($cmd =~ m/-till$/) {
      my @lt = localtime;
      my $hms_now  = sprintf("%02d:%02d:%02d", $lt[2], $lt[1], $lt[0]);
      if($hms_now ge $hms_till) {
        Log3 $hash, 4,
          "$cmd: won't switch as now ($hms_now) is later than $hms_till";
        return "";
      }
    }
    DoSet($name, $cmd1);
    CommandDefine(undef, "$at at $hms_till set $name $cmd2");

  } elsif($cmd eq "blink") {
    my $p2 = $a[1];
    delete($hash->{SE_BLINKPARAM});
    return "$cmd requires 2 numbers as argument"
        if($param !~ m/^\d+$/ || $p2 !~ m/^\d*\d?\d*$/);

    if($param) {
      DoSet($name, "on-for-timer", $p2);
      $param--;
      if($param) {
        $hash->{SE_BLINKPARAM} = "$param $p2";
        InternalTimer(gettimeofday()+2*$p2,"SetExtensionsFn","SE $name $cmd",0);
      }
    }

  } elsif($cmd eq "intervals") {
    my $at0 = "${name}_till";
    my $at1 = "${name}_intervalFrom",
    my $at2 = "${name}_intervalNext";
    CommandDelete(undef, $at0) if($defs{$at0});
    CommandDelete(undef, $at1) if($defs{$at1});
    CommandDelete(undef, $at2) if($defs{$at2});

    my $intSpec = shift(@a);
    if($intSpec) {
      my ($from, $till) = split("-", $intSpec);

      my ($err, $hr, $min, $sec, $fn) = GetTimeSpec($from);
      return "$cmd: $err" if($err);
      my @lt = localtime;
      my $hms_from = sprintf("%02d:%02d:%02d", $hr, $min, $sec);
      my $hms_now  = sprintf("%02d:%02d:%02d", $lt[2], $lt[1], $lt[0]);

      if($hms_from le $hms_now) { # By slight delays at will schedule tomorrow.
        SetExtensions($hash, $list, $name, "on-till", $till);

      } else {
        CommandDefine(undef, "$at1 at $from set $name on-till $till");

      }

      if(@a) {
        my $rest = join(" ", @a);
        my ($from, $till) = split("-", shift @a);
        CommandDefine(undef, "$at2 at $from set $name intervals $rest");
      }
    }
    
  } elsif($cmd eq "toggle") {
    $value = ($1==0 ? "off" : "on") if($value =~ m/dim (\d+)/); # Forum #49391
    DoSet($name, $value =~ m/^on/ ? "off" : "on");

  }

  return undef;
}

sub
SetExtensionsFn($)
{
  my (undef, $name, $cmd) = split(" ", shift, 3);
  my $hash = $defs{$name};
  return if(!$hash);

  delete $hash->{SetExtensionTimer};

  if($cmd eq "on-for-timer") {
    DoSet($name, "off");

  } elsif($cmd eq "off-for-timer") {
    DoSet($name, "on");

  } elsif($cmd eq "blink" && $defs{$name}{SE_BLINKPARAM}) {
    DoSet($name, "blink", split(" ", $defs{$name}{SE_BLINKPARAM}, 2));

  }

}

1;
