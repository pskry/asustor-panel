# SPDX-License-Identifier: GPL-2.0-or-later
PREFIX    ?= /usr/local
SBINDIR   ?= $(PREFIX)/sbin
BINDIR    ?= $(PREFIX)/bin
UNITDIR   ?= /etc/systemd/system
HOOKDIR   ?= /etc/asustor-panel/hooks

.PHONY: install uninstall check

install:
	install -D -m 0755 asustor-panel    $(DESTDIR)$(SBINDIR)/asustor-panel
	install -D -m 0755 asustor-panelctl $(DESTDIR)$(BINDIR)/asustor-panelctl
	install -D -m 0644 asustor-panel.service $(DESTDIR)$(UNITDIR)/asustor-panel.service
	install -d -m 0755 $(DESTDIR)$(HOOKDIR)
	@echo
	@echo "Mask the getty on the panel's port, or it will eat the button frames:"
	@echo "  systemctl mask serial-getty@ttyS1.service"

uninstall:
	rm -f $(DESTDIR)$(SBINDIR)/asustor-panel
	rm -f $(DESTDIR)$(BINDIR)/asustor-panelctl
	rm -f $(DESTDIR)$(UNITDIR)/asustor-panel.service

check:
	python3 -m py_compile asustor-panel
	sh -n asustor-panelctl
