#!/usr/bin/perl

use Getopt::Long;
use strict;
use lib "/opt/vyatta/share/perl5";
use Vyatta::Cluster::Config;

my $HA_DIR = "/etc/ha.d";
my $HA_INIT = "/etc/init.d/heartbeat";
my $SERVICE_DIR = "/etc/init.d";

my $conntrackd_service = undef;
GetOptions("conntrackd_service=s"         => \$conntrackd_service,
);

my $config = new Vyatta::Cluster::Config;
$config->setup("cluster");
if ($config->isEmpty()) {

  # check if conntrack-sync is using clustering as failover-mechanism
  my $vconfig = new Vyatta::Config;
  $vconfig->setLevel('service conntrack-sync failover-mechanism');
  my @nodes = $vconfig->listNodes();
  if (grep(/^cluster$/, @nodes)) {
    print STDERR "Cluster is being used as failover-mechanism in conntrack-sync\n" .
                 "It is either not configured or has been deleted!\n";
    exit 1;
  }

  # config is empty => deleted.
  # shutdown clustering.
  print "Stopping clustering...";
  system("$HA_INIT stop >&/dev/null");
  print " Done\n";  
  exit 0;
}

my ($authkeys, $haresources, $ha_cf, $err, @init_services);
while (1) {
  ($authkeys, $err) = $config->authkeys();
  last if (!defined($authkeys));
  if (defined $conntrackd_service) {
    ($haresources, $err, @init_services) = $config->haresources("$conntrackd_service") if defined $conntrackd_service;
  } else {
    ($haresources, $err, @init_services) = $config->haresources();
  }
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

# stop HA before changing config files
print "Stopping clustering...";
system("$HA_INIT stop >&/dev/null");
print " Done\n";

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

# stop each service in case it is already started
foreach (@init_services) {
  system("$SERVICE_DIR/$_ stop >&/dev/null");
}

print "Starting clustering...";
system("$HA_INIT start >&/dev/null");
if ($? >> 8) {
  print "\nError: Clustering failed to start.\n";
  print "Please make sure all clustering interfaces are functional\n";
  print "and retry the commit.\n";
  exit 1;
}
print " Done\n";
exit 0;

