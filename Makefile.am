cfgdir = $(datadir)/vyatta-cfg/templates
opdir = $(datadir)/vyatta-op/templates
share_perl5dir = $(datadir)/perl5
bin_sudo_usersdir = $(bindir)/sudo-users
curverdir = $(sysconfdir)/config-migrate/current

sbin_SCRIPTS = scripts/vyatta-update-cluster.pl
bin_sudo_users_SCRIPTS = scripts/vyatta-show-cluster.pl

share_perl5_DATA = scripts/VyattaClusterConfig.pm
curver_DATA = cfg-version/cluster@1

cpiop = find  . ! -regex '\(.*~\|.*\.bak\|.*\.swp\|.*\#.*\#\)' -print0 | \
	cpio -0pd

install-exec-hook:
	mkdir -p $(DESTDIR)$(cfgdir)
	cd templates-cfg; $(cpiop) $(DESTDIR)$(cfgdir)
	mkdir -p $(DESTDIR)$(opdir)
	cd templates-op; $(cpiop) $(DESTDIR)$(opdir)
