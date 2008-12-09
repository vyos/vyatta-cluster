#!/usr/bin/perl

use strict;
use lib "/opt/vyatta/share/perl5";
use Vyatta::Cluster::Config;

my $CL_STATUS = "/usr/bin/cl_status";

my $config = new Vyatta::Cluster::Config;
$config->setupOrig("cluster");
if ($config->isEmpty()) {
  # config is empty.
  print "Clustering is not configured\n";
  exit 0;
}

my $primary = $config->primaryNode();
my $secondary = $config->secondaryNode();
my @monitors = $config->monitorNodes();
my $services = $config->serviceStr();

my $pri_st = `$CL_STATUS nodestatus $primary 2>/dev/null`;
chomp $pri_st;
my $sec_st = `$CL_STATUS nodestatus $secondary 2>/dev/null`;
chomp $sec_st;
my %mon_st = ();
my $non_reach = 0;
foreach (@monitors) {
  my $st = `$CL_STATUS nodestatus $_ 2>/dev/null`;
  chomp $st;
  if ($st ne "ping") {
    $non_reach = 1;
  }
  $mon_st{$_} = $st;
}
my $res_st = `$CL_STATUS rscstatus 2>/dev/null`;
chomp $res_st;

my $my_name = `uname -n`;
chomp $my_name;

if ($my_name eq $primary) {
  printPrimaryStatus();
  exit 0;
} elsif ($my_name eq $secondary) {
  printSecondaryStatus();
  exit 0;
} else {
  print "Error: this node ($my_name) is neither primary ($primary) "
        . "nor secondary ($secondary)\n";
  exit 1;
}

sub printPrimaryStatus {
  my $all_reachable = 1;
  foreach (keys %mon_st) {
    if ($mon_st{$_} eq "dead") {
      $all_reachable = 0;
      last;
    }
  }

  print "=== Status report on primary node $my_name ===\n\n";
  print "  Primary $primary (this node): ";
  my $other_init = 0;
  if ($pri_st eq "up") {
    print "Started (waiting for secondary)";
    $other_init = 1;
  } elsif (($res_st eq "all") || ($res_st eq "local")) {
    print "Active";
  } elsif ($res_st eq "transition") {
    print "Node status in transition";
  } elsif ($res_st eq "none") {
    if ($pri_st eq "active") {
      if ($all_reachable) {
        # work around heartbeat state problem
        print "Active (standby)";
      } else {
        print "Down (at least 1 monitor not reachable)";
      }
    } elsif ($pri_st eq "dead") {
      # this should be unreachable
      print "Down";
    } else {
      print "Unknown";
    }
  } else {
    print "Unknown";
  }
  print "\n\n";

  print "  Secondary $secondary: ";
  if ($other_init) {
    print "Initializing";
  } elsif ($res_st eq "all") {
    if ($sec_st eq "active") {
      # this could also be "Down (at least 1 monitor node not reachable)"
      # we might want to just say "Unknown".
      print "Active (standby)";
    } elsif ($sec_st eq "dead") {
      print "Down";
    } elsif ($sec_st eq "up") {
      print "Initializing";
    } else {
      print "Unknown";
    }
  } elsif ($res_st eq "local") {
    if ($sec_st eq "active") {
      print "Active (standby)";
    } else {
      print "Unknown";
    }
  } elsif ($res_st eq "transition") {
    print "Node status in transition";
  } elsif ($res_st eq "none") {
    if ($sec_st eq "active") {
      print "Active";
    } else {
      print "Unknown";
    }
  } else {
    print "Unknown";
  }
  print "\n\n";
  
  foreach (keys %mon_st) {
    print "  Monitor $_: ";
    if ($other_init) {
      print "Initializing";
    } elsif ($res_st eq "transition") {
      print "Node status in transition";
    } elsif ($mon_st{$_} eq "ping") {
      print "Reachable";
    } elsif ($mon_st{$_} eq "dead") {
      print "Unreachable";
    } else {
      print "Unknown";
    }
    print "\n";
  }
  print "\n";

  print "  Resources [$services]:\n    ";
  if ($other_init) {
    print "Initializing";
  } elsif (($res_st eq "all") || ($res_st eq "local")) {
    print "Active on primary $my_name (this node)";
  } elsif ($res_st eq "transition") {
    print "Resource status in transition";
  } elsif ($res_st eq "none") {
    print "Active on secondary $secondary";
  } else {
    print "Unknown";
  }
  print "\n\n";
}

sub printSecondaryStatus {
  print "=== Status report on secondary node $my_name ===\n\n";
  my $other_init = 0;
  if ($sec_st eq "up") {
    $other_init = 1;
  }
 
  my $all_reachable = 1;
  foreach (keys %mon_st) {
    if ($mon_st{$_} eq "dead") {
      $all_reachable = 0;
      last;
    }
  }

  print "  Primary $primary: ";
  if ($other_init) {
    print "Initializing";
  } elsif ($res_st eq "all") {
    if ($pri_st eq "active") {
      # this could also be "Down (at least 1 monitor node not reachable)".
      # we might want to just say "Unknown".
      print "Active (standby)";
    } elsif ($pri_st eq "dead") {
      print "Down";
    } elsif ($pri_st eq "up") {
      print "Initializing";
    } else {
      print "Unknown";
    }
  } elsif ($res_st eq "local") {
    if ($pri_st eq "active") {
      print "Active";
    } else {
      print "Unknown";
    }
  } elsif ($res_st eq "transition") {
    print "Node status in transition";
  } elsif ($res_st eq "none") {
    if ($pri_st eq "active") {
      print "Active";
    } else {
      print "Unknown";
    }
  } else {
    print "Unknown";
  }
  print "\n\n";
  
  print "  Secondary $my_name (this node): ";
  if ($sec_st eq "up") {
    print "Started (waiting for primary)";
  } elsif ($res_st eq "all") {
    print "Active";
  } elsif ($res_st eq "local") {
    print "Active (standby)";
  } elsif ($res_st eq "transition") {
    print "Node status in transition";
  } elsif ($res_st eq "none") {
    if ($sec_st eq "active") {
      if ($all_reachable) {
        # work around heartbeat state problem
        print "Active (standby)";
      } else {
        print "Down (at least 1 monitor not reachable)";
      }
    } elsif ($sec_st eq "dead") {
      # this should be unreachable
      print "Down";
    } else {
      print "Unknown";
    }
  } else {
    print "Unknown";
  }
  print "\n\n";

  foreach (keys %mon_st) {
    print "  Monitor $_: ";
    if ($other_init) {
      print "Initializing";
    } elsif ($res_st eq "transition") {
      print "Node status in transition";
    } elsif ($mon_st{$_} eq "ping") {
      print "Reachable";
    } elsif ($mon_st{$_} eq "dead") {
      print "Unreachable";
    } else {
      print "Unknown";
    }
    print "\n";
  }
  print "\n";

  print "  Resources [$services]:\n    ";
  if ($other_init) {
    print "Initializing";
  } elsif ($res_st eq "all") {
    print "Active on secondary $my_name (this node)";
  } elsif ($res_st eq "transition") {
    print "Resource status in transition";
  } elsif (($res_st eq "none") || ($res_st eq "local")) {
    print "Active on primary $primary";
  } else {
    print "Unknown";
  }
  print "\n\n";
}

exit 0;
