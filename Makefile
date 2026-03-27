PREFIX ?= /usr
SBINDIR ?= $(PREFIX)/sbin
ETCDIR ?= /etc
SYSTEMDDIR ?= /etc/systemd/system
OPENRCDIR ?= /etc/init.d

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

all: $(PROGRAM)

$(PROGRAM): $(SOURCES)
	fpc -FE. -FU$(SRC_DIR) $(MAIN_SRC)

install: $(PROGRAM)
	install -d $(DESTDIR)$(SBINDIR)
	install -d $(DESTDIR)$(ETCDIR)
	install -d $(DESTDIR)$(SYSTEMDDIR)
	install -d $(DESTDIR)$(OPENRCDIR)
	install -m 755 $(PROGRAM) $(DESTDIR)$(SBINDIR)/$(PROGRAM)
	install -m 644 $(CONFIG_FILE) $(DESTDIR)$(ETCDIR)/rn.conf
	install -m 644 $(SYSTEMD_FILE) $(DESTDIR)$(SYSTEMDDIR)/rn.service
	install -m 755 $(OPENRC_FILE) $(DESTDIR)$(OPENRCDIR)/rn

clean:
	rm -f $(PROGRAM) *.o *.ppu
	rm -f $(SRC_DIR)/*.o $(SRC_DIR)/*.ppu

.PHONY: all install clean