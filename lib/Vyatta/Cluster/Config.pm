package Vyatta::Cluster::Config;

use strict;
use lib "/opt/vyatta/share/perl5";
use Vyatta::Config;

my $DEFAULT_INITDEAD = 30000;
my $MIN_DEAD = 300;
my $MIN_KEEP = 100;
my $DEFAULT_LOG_FACILITY = 'daemon';
my $SERVICE_DIR = "/etc/init.d";
my $RESOURCE_SCRIPT_DIR = "/etc/ha.d/resource.d";

# for heartbeat
my $DEFAULT_MCAST_GROUP = '239.251.252.253';
my $DEFAULT_UDP_PORT = '694';
my $DEFAULT_TTL = '1';

my $HA_WATCHLINK_ID = 'ha';

my %fields = (
    _interface          => undef,
    _mcast_grp          => undef,
    _pre_shared         => undef,
    _keepalive_itvl     => undef,
    _dead_itvl          => undef,
    _monitor_dead_itvl  => undef,
    _ucast		          => undef,
    _groups             => {},
    _is_empty           => 1,
);

sub new {
    my $that = shift;
    my $class = ref($that) || $that;
    my $self = {%fields,};

    bless $self, $class;
    return $self;
}

sub setup {
    my ($self, $level) = @_;
    my $config = new Vyatta::Config;

    $config->setLevel("$level");
    my @nodes = $config->listNodes();
    if (scalar(@nodes) <= 0) {
        $self->{_is_empty} = 1;
        return 0;
    } else {
        $self->{_is_empty} = 0;
    }

    my @tmp = $config->returnValues("interface");
    $self->{_interface} = [@tmp];
    $self->{_mcast_grp} = $config->returnValue("mcast-group");
    $self->{_pre_shared} = $config->returnValue("pre-shared-secret");
    $self->{_keepalive_itvl} = $config->returnValue("keepalive-interval");
    $self->{_dead_itvl} = $config->returnValue("dead-interval");
    $self->{_monitor_dead_itvl} = $config->returnValue("monitor-dead-interval");
    @tmp = $config->returnValues("ucast");
    $self->{_ucast} = [ @tmp ];

    $config->setLevel("$level group");
    my @groups = $config->listNodes();
    my $group;
    for $group (@groups) {
        my $hashref = {};
        $config->setLevel("$level group $group");
        $hashref->{_primary} = $config->returnValue("primary");
        @tmp = $config->returnValues("secondary");
        $hashref->{_secondary} = [@tmp];
        $hashref->{_auto_failback} = $config->returnValue("auto-failback");
        @tmp = $config->returnValues("monitor");
        $hashref->{_monitor} = [@tmp];
        @tmp = $config->returnValues("service");
        $hashref->{_service} = [@tmp];
        $self->{_groups}->{$group} = $hashref;
    }

    return 0;
}

sub setupOrig {
    my ($self, $level) = @_;
    my $config = new Vyatta::Config;

    $config->setLevel("$level");
    my @nodes = $config->listOrigNodes();
    if (scalar(@nodes) <= 0) {
        $self->{_is_empty} = 1;
        return 0;
    } else {
        $self->{_is_empty} = 0;
    }

    my @tmp = $config->returnOrigValues("interface");
    $self->{_interface} = [@tmp];
    $self->{_mcast_grp} = $config->returnOrigValue("mcast-group");
    $self->{_pre_shared} = $config->returnOrigValue("pre-shared-secret");
    $self->{_keepalive_itvl} = $config->returnOrigValue("keepalive-interval");
    $self->{_dead_itvl} = $config->returnOrigValue("dead-interval");
    $self->{_monitor_dead_itvl} = $config->returnOrigValue("monitor-dead-interval");
    @tmp = $config->returnOrigValues("ucast");
    $self->{_ucast} = [ @tmp ];

    $config->setLevel("$level group");
    my @groups = $config->listOrigNodes();
    my $group;
    for $group (@groups) {
        my $hashref = {};
        $config->setLevel("$level group $group");
        $hashref->{_primary} = $config->returnOrigValue("primary");
        @tmp = $config->returnOrigValues("secondary");
        $hashref->{_secondary} = [@tmp];
        $hashref->{_auto_failback} = $config->returnOrigValue("auto-failback");
        @tmp = $config->returnOrigValues("monitor");
        $hashref->{_monitor} = [@tmp];
        @tmp = $config->returnOrigValues("service");
        $hashref->{_service} = [@tmp];
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
    my ($exist_only, @interfaces) = @_;
    foreach (@interfaces) {
        system("ip addr show $_ >& /dev/null");
        if ($? >> 8) {
            return "interface $_ does not exist";
        }
        next if ($exist_only);

        my $link = `ip link show $_ | grep $_`;
        my $link_test = 0;

        while (($link =~ /NO-CARRIER/) || !($link =~ /,UP/)) {
            $link_test++;
            sleep(1);
            $link = `ip link show $_ | grep $_`;
            if ($link_test >= 10) {
                return "interface $_ is not connected";
            }
        }

        system("ip addr show dev $_ |grep 'inet ' |grep -q 'scope global'");
        if ($? >> 8) {
            return "interface $_ is not configured";
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

    my $ierr = check_interfaces(0, @{$self->{_interface}});
    if (defined($ierr)) {
        return (undef, $ierr);
    }
    my $interfaces = '';
    foreach my $intf (@{$self->{_interface}}) {
      if (defined($self->{_ucast}) && scalar(@{$self->{_ucast}}) > 0  ) {
  	     foreach my $ucast (@{$self->{_ucast}}) {
  		       my ($uintf,$upip) = split(/:/,$ucast);
  		       if ($uintf eq $intf) {
  			       $interfaces .= "ucast $intf $upip\n";
  		       } else {
               return (undef, "$intf is not a valid interface");
             }
  	     }
      } else {
      	$interfaces .= "mcast $intf ";
      	$interfaces .= ((defined($self->{_mcast_grp}))
                      ?  "$self->{_mcast_grp} " : "$DEFAULT_MCAST_GROUP ");
      	$interfaces .= "$DEFAULT_UDP_PORT $DEFAULT_TTL 0\n";
      }
    }

    my $kitvl = $self->{_keepalive_itvl};
    my $ditvl = $self->{_dead_itvl};
    my $mditvl = $self->{_monitor_dead_itvl};

    my $hashref = $self->{_groups}->{$groups[0]};
    my $primary = $hashref->{_primary};
    my @secondaries =  @{$hashref->{_secondary}};
    my $pings = join " ", @{$hashref->{_monitor}};
    my $auto_failback = ($hashref->{_auto_failback} eq "true") ?"on" : "off";
    my $my_name = `uname -n`;
    chomp $my_name;

    return (undef, "heartbeat interface(s) not defined") if ($interfaces eq "");
    return (undef, "keepalive interval not defined") if (!defined($kitvl));
    return (undef, "dead interval not defined") if (!defined($ditvl));
    return (undef, "monitor dead interval not defined") if (!defined($mditvl));
    return (undef, "cluster primary system not defined") if (!defined($primary));
    return (undef, "cluster secondary node(s) not defined") if ($#secondaries < 0);
    return (undef, "using multiple secondary nodes is not supported yet") if ($#secondaries > 0);
    return (undef, "dead interval must be at least $MIN_DEAD milliseconds") if ($ditvl < $MIN_DEAD);
    return (undef, "monitor dead interval must be at least $MIN_DEAD milliseconds") if ($mditvl < $MIN_DEAD);
    return (undef, "keepalive interval must be at least $MIN_KEEP milliseconds") if ($kitvl < $MIN_KEEP);
    return (undef, "dead interval must be more than twice the keepalive interval") if ($ditvl <= (2 * $kitvl));
    return (undef, "monitor dead interval must be more than twice the keepalive interval") if ($mditvl <= (2 * $kitvl));
    return (undef, "dead interval must be smaller than $DEFAULT_INITDEAD milliseconds") if ($ditvl >= $DEFAULT_INITDEAD);
    return (undef, "monitor dead interval must be smaller than $DEFAULT_INITDEAD milliseconds") if ($mditvl >= $DEFAULT_INITDEAD);
    return (undef, "the current node '$my_name' is not defined in the configuration") if (($my_name ne $primary) && ($my_name ne $secondaries[0]));

    my $monitor_str = "";
    if ($pings ne "") {
        $monitor_str = "\nping $pings\n". "respawn hacluster /usr/lib/heartbeat/ipfail";
    }

    my $wtime = int($kitvl * 2);
    if ($wtime > $ditvl) {
        $wtime = $ditvl;
    }

    # convert to seconds (HA calls "sleep" with this)
    $ditvl /= 1000;

    my $str =<<EOS;
keepalive ${kitvl}ms
deadtime ${ditvl}
warntime ${wtime}ms
initdead ${DEFAULT_INITDEAD}ms
deadping ${mditvl}ms
logfacility $DEFAULT_LOG_FACILITY
${interfaces}auto_failback $auto_failback
node $primary $secondaries[0]$monitor_str
EOS

    return ($str, undef);
}

sub isValidIPSpec {
    my $str = shift;
    my @comps = split /\//, $str;
    return 0 if ($#comps < 1);
    return 0 if ($#comps > 3);
    return 0 if (!isValidIPv4($comps[0]));

    # check optional prefix len
    if (defined($comps[1])) {
        return 0 if (!($comps[1] =~ m/^\d+$/));
        return 0 if (($comps[1] > 32) || ($comps[1] < 0));
    }

    # check optional interface
    if (defined($comps[2])) {
        return 0 if (defined(check_interfaces(1, $comps[2])));
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
    return 1 if (($a1 >= 0 && $a1 < 256)
        && ($a2 >= 0 && $a2 < 256)
        && ($a3 >= 0 && $a3 < 256)
        && ($a4 >= 0 && $a4 < 256));
    return 0;
}

my @service_list = ();

sub isValidService {
    my $service = shift;
    if ($service =~ /^([^:]+)::/) {
        my $script = $1;
        return 0 if (!-e "$RESOURCE_SCRIPT_DIR/$script");
        return 1;
    }
    if (scalar(@service_list) == 0) {
        opendir(SDIR, "$SERVICE_DIR")
            or (print STDERR "Error: can't open $SERVICE_DIR" && return 0);
        @service_list = grep !/^\./, readdir SDIR;
    }
    return 1 if (grep /^$service$/, @service_list);
    return 0;
}

sub haresources {
    my ($self, $conntrackd_service) = @_;
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
                if ($_ eq 'ipsec') {

                    # check if ipsec is configured
                    my $config = new Vyatta::Config;
                    $config->setLevel('vpn');
                    my @nodes = $config->listOrigPlusComNodes();
                    if (!grep(/^ipsec$/, @nodes)) {
                        return (undef, "ipsec is not configured");
                    }
                }
                push @init_services, $_;
            } else {
                return (undef, "\"$_\" is not a valid IP address ". "(with subnet mask length) or service name");
            }
        } else {
            push @ip_addresses, "IPaddr2-vyatta::$_";
        }
    }

    # this forces all ip addresses to be before all services, which may not
    # be the desirable behavior in all cases.
    my $ip_str = join " ", @ip_addresses;
    my $serv_str = join " ", @init_services;
    my $services = join " ", ($ip_str, $serv_str);
    return (undef, "cluster primary system not defined") if (!defined($primary));
    return (undef, "cluster service(s) not defined") if ($services eq "");

    # check if conntrack-sync is configured to use clustering
    my $config = new Vyatta::Config;
    $config->setLevel('service conntrack-sync failover-mechanism');
    my @nodes = $config->listOrigPlusComNodes();
    if (grep(/^cluster$/, @nodes)) {
        $conntrackd_service = "vyatta-cluster-conntracksync";
    }
    $services = join " ", ($services, "$conntrackd_service") if defined $conntrackd_service;
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
    $str .= "\n  monitor-dead-interval $self->{_monitor_dead_itvl}";
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
