PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

EXTENSION = pgsynonym
DATA = pgsynonym--0.1.sql 
MODULES = pgsynonym 

install_files:
  cp pgsynonym--0.1.sql pgsynonym.control '$(DESTDIR)$(datadir)/extension/'

all: install_files

clean:
  rm -f $(EXTENSION).o $(EXTENSION).so

install: install_files

uninstall:
  rm -f '$(DESTDIR)$(datadir)/extension/$(DATA)'
  rm -f '$(DESTDIR)$(datadir)/extension/pgsynonym.control'

.PHONY: all install_files clean install uninstall
