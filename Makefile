PREFIX ?= /usr
SBINDIR ?= $(PREFIX)/sbin
ETCDIR ?= /etc
DOCDIR ?= $(PREFIX)/share/doc/$(PROGRAM)

SYSTEMDDIR ?= /usr/lib/systemd/system
OPENRCDIR ?= /etc/init.d

# FreeBSD-style defaults for staged installs can be overridden:
FREEBSD_PREFIX ?= /usr/local
FREEBSD_SBINDIR ?= $(FREEBSD_PREFIX)/sbin
FREEBSD_ETCDIR ?= $(FREEBSD_PREFIX)/etc
FREEBSD_RCDIR ?= /usr/local/etc/rc.d
FREEBSD_DOCDIR ?= $(FREEBSD_PREFIX)/share/doc/$(PROGRAM)

PROGRAM = rn

SRC_DIR = src
CONF_DIR = conf

MAIN_SRC = $(SRC_DIR)/rn.pas
SOURCES = \
	$(SRC_DIR)/rn.pas \
	$(SRC_DIR)/dns_packet.pas \
	$(SRC_DIR)/v6alt_codec.pas \
	$(SRC_DIR)/v6alt_base32.pas

CONFIG_FILE = $(CONF_DIR)/rn.conf
SYSTEMD_FILE = $(CONF_DIR)/rn.service
OPENRC_FILE = $(CONF_DIR)/rn.openrc
FREEBSD_RC_FILE = $(CONF_DIR)/rn.freebsd
README_FILE = README.md

all: $(PROGRAM)

$(PROGRAM): $(SOURCES)
	fpc -FE. -FU$(SRC_DIR) $(MAIN_SRC)

install: install-base

install-base: $(PROGRAM)
	install -d $(DESTDIR)$(SBINDIR)
	install -d $(DESTDIR)$(ETCDIR)
	install -d $(DESTDIR)$(DOCDIR)

	install -m 755 $(PROGRAM) $(DESTDIR)$(SBINDIR)/$(PROGRAM)
	install -m 644 $(CONFIG_FILE) $(DESTDIR)$(ETCDIR)/rn.conf

	if [ -f $(README_FILE) ]; then \
		install -m 644 $(README_FILE) $(DESTDIR)$(DOCDIR)/README.md; \
	fi

install-openrc:
	install -d $(DESTDIR)$(OPENRCDIR)
	install -m 755 $(OPENRC_FILE) $(DESTDIR)$(OPENRCDIR)/rn

install-systemd:
	install -d $(DESTDIR)$(SYSTEMDDIR)
	install -m 644 $(SYSTEMD_FILE) $(DESTDIR)$(SYSTEMDDIR)/rn.service

install-freebsd:
	install -d $(DESTDIR)$(FREEBSD_SBINDIR)
	install -d $(DESTDIR)$(FREEBSD_ETCDIR)
	install -d $(DESTDIR)$(FREEBSD_RCDIR)
	install -d $(DESTDIR)$(FREEBSD_DOCDIR)

	install -m 755 $(PROGRAM) $(DESTDIR)$(FREEBSD_SBINDIR)/$(PROGRAM)
	install -m 644 $(CONFIG_FILE) $(DESTDIR)$(FREEBSD_ETCDIR)/rn.conf
	install -m 755 $(FREEBSD_RC_FILE) $(DESTDIR)$(FREEBSD_RCDIR)/rn

	if [ -f $(README_FILE) ]; then \
		install -m 644 $(README_FILE) $(DESTDIR)$(FREEBSD_DOCDIR)/README.md; \
	fi

install-all-init: install-openrc install-systemd install-freebsd

uninstall:
	rm -f $(DESTDIR)$(SBINDIR)/$(PROGRAM)
	rm -f $(DESTDIR)$(ETCDIR)/rn.conf
	rm -f $(DESTDIR)$(DOCDIR)/README.md

uninstall-openrc:
	rm -f $(DESTDIR)$(OPENRCDIR)/rn

uninstall-systemd:
	rm -f $(DESTDIR)$(SYSTEMDDIR)/rn.service

uninstall-freebsd:
	rm -f $(DESTDIR)$(FREEBSD_SBINDIR)/$(PROGRAM)
	rm -f $(DESTDIR)$(FREEBSD_ETCDIR)/rn.conf
	rm -f $(DESTDIR)$(FREEBSD_RCDIR)/rn
	rm -f $(DESTDIR)$(FREEBSD_DOCDIR)/README.md

clean:
	rm -f $(PROGRAM) *.o *.ppu
	rm -f $(SRC_DIR)/*.o $(SRC_DIR)/*.ppu

.PHONY: \
	all clean \
	install install-base install-openrc install-systemd install-freebsd install-all-init \
	uninstall uninstall-openrc uninstall-systemd uninstall-freebsd