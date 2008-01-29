package VyattaClusterConfig;

use strict;
use lib "/opt/vyatta/share/perl5/";
use VyattaConfig;

my $DEFAULT_INITDEAD = 120;
my $DEFAULT_LOG_FACILITY = 'daemon';
my $SERVICE_DIR = "/etc/init.d";

my %fields = (
  _interface        => undef,
  _pre_shared       => undef,
  _keepalive_itvl   => undef,
  _dead_itvl        => undef,
  _groups           => {},
  _is_empty         => 1,
);

sub new {
  my $that = shift;
  my $class = ref ($that) || $that;
  my $self = {
    %fields,
  };

  bless $self, $class;
  return $self;
}

sub setup {
  my ( $self, $level ) = @_;
  my $config = new VyattaConfig;

  $config->setLevel("$level");
  my @nodes = $config->listNodes();
  if (scalar(@nodes) <= 0) {
    $self->{_is_empty} = 1;
    return 0;
  } else {
    $self->{_is_empty} = 0;
  }

  my @tmp = $config->returnValues("interface");
  $self->{_interface} = [ @tmp ];
  $self->{_pre_shared} = $config->returnValue("pre-shared-secret");
  $self->{_keepalive_itvl} = $config->returnValue("keepalive-interval");
  $self->{_dead_itvl} = $config->returnValue("dead-interval");

  $config->setLevel("$level group");
  my @groups = $config->listNodes();
  my $group;
  for $group (@groups) {
    my $hashref = {};
    $config->setLevel("$level group $group");
    $hashref->{_primary} = $config->returnValue("primary");
    @tmp = $config->returnValues("secondary");
    $hashref->{_secondary} = [ @tmp ];
    $hashref->{_auto_failback} = $config->returnValue("auto-failback");
    @tmp = $config->returnValues("monitor");
    $hashref->{_monitor} = [ @tmp ];
    @tmp = $config->returnValues("service");
    $hashref->{_service} = [ @tmp ];
    $self->{_groups}->{$group} = $hashref;
  }

  return 0;
}

sub setupOrig {
  my ( $self, $level ) = @_;
  my $config = new VyattaConfig;

  $config->setLevel("$level");
  my @nodes = $config->listOrigNodes();
  if (scalar(@nodes) <= 0) {
    $self->{_is_empty} = 1;
    return 0;
  } else {
    $self->{_is_empty} = 0;
  }

  my @tmp = $config->returnOrigValues("interface");
  $self->{_interface} = [ @tmp ];
  $self->{_pre_shared} = $config->returnOrigValue("pre-shared-secret");
  $self->{_keepalive_itvl} = $config->returnOrigValue("keepalive-interval");
  $self->{_dead_itvl} = $config->returnOrigValue("dead-interval");

  $config->setLevel("$level group");
  my @groups = $config->listOrigNodes();
  my $group;
  for $group (@groups) {
    my $hashref = {};
    $config->setLevel("$level group $group");
    $hashref->{_primary} = $config->returnOrigValue("primary");
    @tmp = $config->returnOrigValues("secondary");
    $hashref->{_secondary} = [ @tmp ];
    $hashref->{_auto_failback} = $config->returnOrigValue("auto-failback");
    @tmp = $config->returnOrigValues("monitor");
    $hashref->{_monitor} = [ @tmp ];
    @tmp = $config->returnOrigValues("service");
    $hashref->{_service} = [ @tmp ];
    $self->{_groups}->{$group} = $hashref;
  }

  return 0;
}

sub primaryNode {
  my ($self) = @_;
  my @groups = keys %{$self->{_groups}};
  my $hashref = $self->{_groups}->{$groups[0]};
  return $hashref->{_primary};
}

sub secondaryNode {
  my ($self) = @_;
  my @groups = keys %{$self->{_groups}};
  my $hashref = $self->{_groups}->{$groups[0]};
  return ${$hashref->{_secondary}}[0];
}

sub monitorNodes {
  my ($self) = @_;
  my @groups = keys %{$self->{_groups}};
  my $hashref = $self->{_groups}->{$groups[0]};
  return @{$hashref->{_monitor}};
}

sub serviceStr {
  my ($self) = @_;
  my @groups = keys %{$self->{_groups}};
  my $hashref = $self->{_groups}->{$groups[0]};
  return (join " ", @{$hashref->{_service}});
}

sub isEmpty {
  my ($self) = @_;
  return $self->{_is_empty};
}

sub authkeys {
  my ($self) = @_;
  my $key = $self->{_pre_shared};
  return (undef, "pre-shared secret not defined") if (!defined($key));
  my $str =<<EOS;
auth 1
1 sha1 $key
EOS
  return ($str, undef);
}

sub check_interfaces {
  my @interfaces = @_;
  foreach (@interfaces) {
    system("ip addr show $_ >& /dev/null");
    if ($? >> 8) {
      return "interface $_ does not exist";
    }
  }
  return undef;
}

sub ha_cf {
  my ($self) = @_;
  my @groups = keys %{$self->{_groups}};
  return (undef, "no resource group defined") if ($#groups < 0);
  return (undef, "using multiple resource groups is not supported yet")
    if ($#groups > 0);

  my $ierr = check_interfaces(@{$self->{_interface}});
  if (defined($ierr)) {
    return (undef, $ierr);
  }
  my $interfaces = join " ", @{$self->{_interface}};
  my $kitvl = $self->{_keepalive_itvl};
  my $ditvl = $self->{_dead_itvl};

  my $hashref = $self->{_groups}->{$groups[0]};
  my $primary = $hashref->{_primary};
  my @secondaries =  @{$hashref->{_secondary}};
  my $pings = join " ", @{$hashref->{_monitor}};
  my $auto_failback = ($hashref->{_auto_failback} eq "true") ?
                      "on" : "off";
  my $my_name = `uname -n`;
  chomp $my_name;

  return (undef, "heartbeat interface(s) not defined") if ($interfaces eq "");
  return (undef, "keepalive interval not defined") if (!defined($kitvl));
  return (undef, "dead interval not defined") if (!defined($ditvl));
  return (undef, "cluster primary system not defined")
    if (!defined($primary));
  return (undef, "cluster secondary node(s) not defined")
    if ($#secondaries < 0);
  return (undef, "using multiple secondary nodes is not supported yet")
    if ($#secondaries > 0);
  return (undef,
          "dead interval must be more than twice the keepalive interval")
    if ($ditvl <= (2 * $kitvl));
  return (undef,
          "dead interval must be smaller than $DEFAULT_INITDEAD seconds")
    if ($ditvl >= $DEFAULT_INITDEAD);
  return (undef,
          "the current node '$my_name' is not defined in the configuration")
    if (($my_name ne $primary) && ($my_name ne $secondaries[0]));
 
  my $monitor_str = "";
  if ($pings ne "") {
    $monitor_str = "\nping $pings\n"
                   . "respawn hacluster /usr/lib/heartbeat/ipfail";
  }

  my $wtime = int($kitvl * 2);
  if ($wtime > $ditvl) {
    $wtime = $ditvl;
  }

  my $str =<<EOS;
keepalive $kitvl
deadtime $ditvl
warntime $wtime
initdead $DEFAULT_INITDEAD
logfacility $DEFAULT_LOG_FACILITY
bcast $interfaces
auto_failback $auto_failback
node $primary $secondaries[0]$monitor_str
EOS

  return ($str, undef);
}

sub isValidIPSpec {
  my $str = shift;
  my @comps = split /\//, $str;
  return 0 if ($#comps > 3);
  return 0 if (!isValidIPv4($comps[0]));
  # check optional prefix len
  if (defined($comps[1])) {
    return 0 if (!($comps[1] =~ m/^\d+$/));
    return 0 if (($comps[1] > 32) || ($comps[1] < 0));
  }
  # check optional interface
  if (defined($comps[2])) {
    return 0 if (defined(check_interfaces($comps[2])));
  }
  # check optional broadcast addr
  if (defined($comps[3])) {
    return 0 if (!isValidIPv4($comps[3]));
  }
  return 1;
}

sub isValidIPv4 {
  my $str = shift;
  return 0 if (!($str =~ m/^(\d+)\.(\d+)\.(\d+)\.(\d+)$/));
  my ($a1, $a2, $a3, $a4) = ($1, $2, $3, $4);
  return 1 if (($a1 >= 0 && $a1 < 256) && ($a2 >= 0 && $a2 < 256)
               && ($a3 >= 0 && $a3 < 256) && ($a4 >= 0 && $a4 < 256));
  return 0;
}

my @service_list = ();
sub isValidService {
  my $service = shift;
  if (scalar(@service_list) == 0) {
    opendir(SDIR, "$SERVICE_DIR")
      or (print STDERR "Error: can't open $SERVICE_DIR" && return 0);
    @service_list = grep !/^\./, readdir SDIR;
  }
  return 1 if (grep /^$service$/, @service_list);
  return 0;
}

sub haresources {
  my ($self) = @_;
  my @groups = keys %{$self->{_groups}};
  return (undef, "no resource group defined") if ($#groups < 0);
  return (undef, "using multiple resource groups is not supported yet")
    if ($#groups > 0);
  
  my $hashref = $self->{_groups}->{$groups[0]};
  my $primary = $hashref->{_primary};

  my @init_services = ();
  my @ip_addresses = ();
  foreach (@{$hashref->{_service}}) {
    if (!isValidIPSpec($_)) {
      if (isValidService($_)) {
        push @init_services, $_;
      } else {
        return (undef, "\"$_\" is not a valid IP address or service name");
      }
    } else {
      push @ip_addresses, $_;
    }
  }
  # this forces all ip addresses to be before all services, which may not
  # be the desirable behavior in all cases.
  my $ip_str = join " ", @ip_addresses;
  my $serv_str = join " ", @init_services;
  my $services = join " ", ($ip_str, $serv_str);
  return (undef, "cluster primary system not defined") if (!defined($primary));
  return (undef, "cluster service(s) not defined") if ($services eq "");

  my $str =<<EOS;
$primary $services
EOS
  
  return ($str, undef, @init_services);
}

sub print_str {
  my ($self) = @_;
  my $str = "cluster";
  $str .= "\n  interface " . (join ",", @{$self->{_interface}});
  $str .= "\n  pre-shared-secret $self->{_pre_shared}";
  $str .= "\n  keepalive-interval $self->{_keepalive_itvl}";
  $str .= "\n  dead-interval $self->{_dead_itvl}";
  my $group;
  foreach $group (keys %{$self->{_groups}}) {
    $str .= "\n  group $group";
    my $hashref = $self->{_groups}->{$group};
    $str .= "\n    primary $hashref->{_primary}";
    $str .= "\n    secondary " . (join ",", @{$hashref->{_secondary}});
    $str .= "\n    monitor " . (join ",", @{$hashref->{_monitor}});
    $str .= "\n    service " . (join ",", @{$hashref->{_service}});
  }

  return $str;
}

1;

