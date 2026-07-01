PREFIX ?= /usr/local
BINDIR := $(PREFIX)/bin

.PHONY: install uninstall test

install:
	install -d "$(BINDIR)"
	install -m 755 log-archive "$(BINDIR)/log-archive"

uninstall:
	rm -f "$(BINDIR)/log-archive"

test:
	bash tests/test.sh
