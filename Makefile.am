cfgdir = $(datadir)/vyatta-cfg/templates
opdir = $(datadir)/vyatta-op/templates
share_perl5dir = $(datadir)/perl5
curverdir = $(sysconfdir)/config-migrate/current

etc_ha_resourcedir = /etc/ha.d/resource.d
lib_ocf_resourcedir = /usr/lib/ocf/resource.d/heartbeat

sbin_SCRIPTS = scripts/vyatta-update-cluster.pl
sbin_SCRIPTS += scripts/vyatta-show-cluster.pl

share_perl5_DATA = scripts/VyattaClusterConfig.pm
curver_DATA = cfg-version/cluster@1

cpiop = find  . ! -regex '\(.*~\|.*\.bak\|.*\.swp\|.*\#.*\#\)' -print0 | \
	cpio -0pd

install-exec-hook:
	mkdir -p $(DESTDIR)$(etc_ha_resourcedir)
	cp scripts/etc-IPaddr2-vyatta $(DESTDIR)$(etc_ha_resourcedir)/IPaddr2-vyatta
	mkdir -p $(DESTDIR)$(lib_ocf_resourcedir)
	cp scripts/ocf-IPaddr2-vyatta $(DESTDIR)$(lib_ocf_resourcedir)/IPaddr2-vyatta
	mkdir -p $(DESTDIR)$(cfgdir)
	cd templates-cfg; $(cpiop) $(DESTDIR)$(cfgdir)
	mkdir -p $(DESTDIR)$(opdir)
	cd templates-op; $(cpiop) $(DESTDIR)$(opdir)
