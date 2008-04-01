#!/usr/bin/perl

use strict;
use lib "/opt/vyatta/share/perl5/";
use VyattaClusterConfig;

my $HA_DIR = "/etc/ha.d";
my $HA_INIT = "/etc/init.d/heartbeat";
my $SERVICE_DIR = "/etc/init.d";

my $config = new VyattaClusterConfig;
$config->setup("cluster");
if ($config->isEmpty()) {
  # config is empty => deleted.
  # shutdown clustering.
  system("$HA_INIT stop");
  
  $config->del_watchlink_exclude();

  exit 0;
}

my ($authkeys, $haresources, $ha_cf, $err, @init_services);
while (1) {
  ($authkeys, $err) = $config->authkeys();
  last if (!defined($authkeys));
  ($haresources, $err, @init_services) = $config->haresources();
  last if (!defined($haresources));
  ($ha_cf, $err) = $config->ha_cf();
  last;
}
if (defined($err)) {
  print STDERR "Cluster configuration error: $err\n";
  exit 1;
}

my $ret = system("mkdir -p $HA_DIR");
if ($ret >> 8) {
  print STDERR "Error: cannot create $HA_DIR\n";
  exit 1;
}

if (!open(CONF_AUTH, ">$HA_DIR/authkeys")) {
  print STDERR "Error: cannot create $HA_DIR/authkeys\n";
  exit 1;
}
if (!open(CONF_RES, ">$HA_DIR/haresources")) {
  print STDERR "Error: cannot create $HA_DIR/haresources\n";
  exit 1;
}
if (!open(CONF_CF, ">$HA_DIR/ha.cf")) {
  print STDERR "Error: cannot create $HA_DIR/ha.cf\n";
  exit 1;
}
print CONF_AUTH $authkeys;
print CONF_RES $haresources;
print CONF_CF $ha_cf;
close CONF_AUTH;
close CONF_RES;
close CONF_CF;
if (!chmod(0600, "$HA_DIR/authkeys")) {
  print STDERR "Error: cannot change $HA_DIR/authkeys permissions\n";
  exit 1;
}

$config->del_watchlink_exclude();
$config->add_watchlink_exclude();

# stop each service in case it is already started
foreach (@init_services) {
  system("$SERVICE_DIR/$_ stop");
}

# restart clustering.
# using "stop" + "start" ("restart" will cause a long wait).
# (may need to change to "restart".)
system("$HA_INIT stop");
system("$HA_INIT start");

exit 0;

