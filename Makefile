PREFIX ?= /usr
SBINDIR ?= $(PREFIX)/sbin
BINDIR ?= $(PREFIX)/bin
ETCDIR ?= /etc
DOCDIR ?= $(PREFIX)/share/doc/$(PROGRAM)

SYSTEMDDIR ?= /usr/lib/systemd/system
OPENRCDIR ?= /etc/init.d

# FreeBSD-style defaults for staged installs can be overridden:
FREEBSD_PREFIX ?= /usr/local
FREEBSD_SBINDIR ?= $(FREEBSD_PREFIX)/sbin
FREEBSD_BINDIR ?= $(FREEBSD_PREFIX)/bin
FREEBSD_ETCDIR ?= $(FREEBSD_PREFIX)/etc
FREEBSD_RCDIR ?= /usr/local/etc/rc.d
FREEBSD_DOCDIR ?= $(FREEBSD_PREFIX)/share/doc/$(PROGRAM)

PROGRAM = rn
TOOLS = v6alt

SRC_DIR = src
CONF_DIR = conf

MAIN_SRC = $(SRC_DIR)/rn.pas
V6ALT_SRC = $(SRC_DIR)/v6alt.pas

COMMON_SOURCES = \
	$(SRC_DIR)/dns_packet.pas \
	$(SRC_DIR)/v6alt_codec.pas \
	$(SRC_DIR)/v6alt_base32.pas

RN_SOURCES = \
	$(MAIN_SRC) \
	$(COMMON_SOURCES)

V6ALT_SOURCES = \
	$(V6ALT_SRC) \
	$(COMMON_SOURCES)

CONFIG_FILE = $(CONF_DIR)/rn.conf
SYSTEMD_FILE = $(CONF_DIR)/rn.service
OPENRC_FILE = $(CONF_DIR)/rn.openrc
FREEBSD_RC_FILE = $(CONF_DIR)/rn.freebsd
README_FILE = readme.md

all: $(PROGRAM) $(TOOLS)

$(PROGRAM): $(RN_SOURCES)
	fpc -FE. -FU$(SRC_DIR) $(MAIN_SRC)

v6alt: $(V6ALT_SOURCES)
	fpc -FE. -FU$(SRC_DIR) $(V6ALT_SRC)

install: install-base

install-base: $(PROGRAM) $(TOOLS)
	install -d $(DESTDIR)$(SBINDIR)
	install -d $(DESTDIR)$(BINDIR)
	install -d $(DESTDIR)$(ETCDIR)
	install -d $(DESTDIR)$(DOCDIR)

	install -m 755 $(PROGRAM) $(DESTDIR)$(SBINDIR)/$(PROGRAM)
	install -m 755 v6alt $(DESTDIR)$(BINDIR)/v6alt
	install -m 644 $(CONFIG_FILE) $(DESTDIR)$(ETCDIR)/rn.conf

	if [ -f $(README_FILE) ]; then \
		install -m 644 $(README_FILE) $(DESTDIR)$(DOCDIR)/$(README_FILE); \
	fi

install-openrc:
	install -d $(DESTDIR)$(OPENRCDIR)
	install -m 755 $(OPENRC_FILE) $(DESTDIR)$(OPENRCDIR)/rn

install-systemd:
	install -d $(DESTDIR)$(SYSTEMDDIR)
	install -m 644 $(SYSTEMD_FILE) $(DESTDIR)$(SYSTEMDDIR)/rn.service

install-freebsd:
	install -d $(DESTDIR)$(FREEBSD_SBINDIR)
	install -d $(DESTDIR)$(FREEBSD_BINDIR)
	install -d $(DESTDIR)$(FREEBSD_ETCDIR)
	install -d $(DESTDIR)$(FREEBSD_RCDIR)
	install -d $(DESTDIR)$(FREEBSD_DOCDIR)

	install -m 755 $(PROGRAM) $(DESTDIR)$(FREEBSD_SBINDIR)/$(PROGRAM)
	install -m 755 v6alt $(DESTDIR)$(FREEBSD_BINDIR)/v6alt
	install -m 644 $(CONFIG_FILE) $(DESTDIR)$(FREEBSD_ETCDIR)/rn.conf
	install -m 755 $(FREEBSD_RC_FILE) $(DESTDIR)$(FREEBSD_RCDIR)/rn

	if [ -f $(README_FILE) ]; then \
		install -m 644 $(README_FILE) $(DESTDIR)$(FREEBSD_DOCDIR)/$(README_FILE); \
	fi

install-all-init: install-openrc install-systemd install-freebsd

uninstall:
	rm -f $(DESTDIR)$(SBINDIR)/$(PROGRAM)
	rm -f $(DESTDIR)$(BINDIR)/v6alt
	rm -f $(DESTDIR)$(ETCDIR)/rn.conf
	rm -f $(DESTDIR)$(DOCDIR)/$(README_FILE)

uninstall-openrc:
	rm -f $(DESTDIR)$(OPENRCDIR)/rn

uninstall-systemd:
	rm -f $(DESTDIR)$(SYSTEMDDIR)/rn.service

uninstall-freebsd:
	rm -f $(DESTDIR)$(FREEBSD_SBINDIR)/$(PROGRAM)
	rm -f $(DESTDIR)$(FREEBSD_BINDIR)/v6alt
	rm -f $(DESTDIR)$(FREEBSD_ETCDIR)/rn.conf
	rm -f $(DESTDIR)$(FREEBSD_RCDIR)/rn
	rm -f $(DESTDIR)$(FREEBSD_DOCDIR)/$(README_FILE)

clean:
	rm -f $(PROGRAM) v6alt *.o *.ppu
	rm -f $(SRC_DIR)/*.o $(SRC_DIR)/*.ppu

.PHONY: \
	all clean \
	install install-base install-openrc install-systemd install-freebsd install-all-init \
	uninstall uninstall-openrc uninstall-systemd uninstall-freebsd
