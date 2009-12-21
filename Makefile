all::

# Define NO_VISIBILITY if your compiler does not support symbol
# visibility in general (and the -fvisibility switch in particular).
#
# Define NO_OPENSSL if you do not have OpenSSL, or if you simply want
# to use the bundled (Mozilla) SHA1 routines. (The bundled SHA1
# routines are reported to be faster than OpenSSL on some platforms)
#

DOXYGEN = doxygen
INSTALL = install
RANLIB  = ranlib
AR      = ar cr

prefix=/usr/local
libdir=$(prefix)/lib

uname_S := $(shell sh -c 'uname -s 2>/dev/null || echo no')

CFLAGS = -g -O2 -Wall
OS     = unix

EXTRA_SRC =
EXTRA_OBJ =

# Platform specific tweaks

ifneq (,$(findstring CYGWIN,$(uname_S)))
	NO_VISIBILITY=YesPlease
endif

ifneq (,$(findstring MINGW,$(uname_S)))
	OS=win32
	NO_VISIBILITY=YesPlease
	SPARSE_FLAGS=-Wno-one-bit-signed-bitfield
endif

SRC_C = $(wildcard src/*.c)
OS_SRC = $(wildcard src/$(OS)/*.c)
SRC_C += $(OS_SRC)
OBJS = $(patsubst %.c,%.o,$(SRC_C))
HDRS = $(wildcard src/*.h)
PUBLIC_HEADERS = $(wildcard src/git/*.h)
HDRS += $(PUBLIC_HEADERS)

GIT_LIB = libgit2.a

TEST_OBJ = $(patsubst %.c,%.o,\
           $(wildcard tests/t[0-9][0-9][0-9][0-9]-*.c))
TEST_EXE = $(patsubst %.o,%.exe,$(TEST_OBJ))
TEST_RUN = $(patsubst %.exe,%.run,$(TEST_EXE))
TEST_VAL = $(patsubst %.exe,%.val,$(TEST_EXE))

ifndef NO_OPENSSL
	SHA1_HEADER = <openssl/sha.h>
else
	SHA1_HEADER = "sha1/sha1.h"
	EXTRA_SRC += src/sha1/sha1.c
	EXTRA_OBJ += src/sha1/sha1.o
endif

BASIC_CFLAGS := -Isrc -DSHA1_HEADER='$(SHA1_HEADER)'
ifndef NO_VISIBILITY
BASIC_CFLAGS += -fvisibility=hidden
endif

ALL_CFLAGS = $(CFLAGS) $(BASIC_CFLAGS)
SRC_C += $(EXTRA_SRC)
OBJ += $(EXTRA_OBJ)

all:: $(GIT_LIB)

clean:
	rm -f $(GIT_LIB)
	rm -f libgit2.pc
	rm -f src/*.o src/sha1/*.o src/unix/*.o src/win32/*.o
	rm -rf apidocs
	rm -f *~ src/*~ src/git/*~ src/sha1/*~ src/unix/*~ src/win32/*~
	@$(MAKE) -C tests -s --no-print-directory clean
	@$(MAKE) -s --no-print-directory cov-clean

test-clean:
	@$(MAKE) -C tests -s --no-print-directory clean

apidocs:
	$(DOXYGEN) api.doxygen
	cp CONVENTIONS apidocs/

test: $(GIT_LIB)
	@$(MAKE) -C tests --no-print-directory test

valgrind: $(GIT_LIB)
	@$(MAKE) -C tests --no-print-directory valgrind

sparse:
	cgcc -no-compile $(ALL_CFLAGS) $(SPARSE_FLAGS) $(SRC_C)

install-headers: $(PUBLIC_HEADERS)
	@$(INSTALL) -d /tmp/gitinc/git
	@for i in $^; do cat .HEADER $$i > /tmp/gitinc/$${i##src/}; done

install: $(GIT_LIB) $(PUBLIC_HEADERS) libgit2.pc
	@$(INSTALL) -d $(DESTDIR)/$(prefix)/include/git
	@for i in $(PUBLIC_HEADERS); do \
		cat .HEADER $$i > $(DESTDIR)/$(prefix)/include/$${i##src/}; \
	done
	@$(INSTALL) -d $(DESTDIR)/$(libdir)
	@$(INSTALL) $(GIT_LIB) $(DESTDIR)/$(libdir)/libgit2.a
	@$(INSTALL) -d $(DESTDIR)/$(libdir)/pkgconfig
	@$(INSTALL) libgit2.pc $(DESTDIR)/$(libdir)/pkgconfig/libgit2.pc

uninstall:
	@rm -f $(DESTDIR)/$(libdir)/libgit2.a
	@rm -f $(DESTDIR)/$(libdir)/pkgconfig/libgit2.pc
	@for i in $(PUBLIC_HEADERS); do \
		rm -f $(DESTDIR)/$(prefix)/include/$${i##src/}; \
	done
	@rmdir $(DESTDIR)/$(prefix)/include/git

.c.o:
	$(CC) $(ALL_CFLAGS) -c $< -o $@

$(OBJS): $(HDRS)
$(GIT_LIB): $(OBJS)
	rm -f $(GIT_LIB)
	$(AR) $(GIT_LIB) $(OBJS)
	$(RANLIB) $(GIT_LIB)

$(TEST_OBJ) $(TEST_EXE) $(TEST_RUN) $(TEST_VAL):
	@$(MAKE) -C tests --no-print-directory \
		OS=$(OS) NO_OPENSSL=$(NO_OPENSSL) $(@F)

libgit2.pc: libgit2.pc.in
	sed -e 's#@prefix@#$(prefix)#' -e 's#@libdir@#$(libdir)#' $< > $@

.PHONY: all
.PHONY: clean
.PHONY: test $(TEST_VAL) $(TEST_RUN) $(TEST_EXE) $(TEST_OBJ)
.PHONY: apidocs
.PHONY: install-headers
.PHONY: install uninstall
.PHONY: sparse

### Test suite coverage testing
#
.PHONY: coverage cov-clean cov-build cov-report

COV_GCDA = $(patsubst %.c,%.gcda,$(SRC_C))
COV_GCNO = $(patsubst %.c,%.gcno,$(SRC_C))

coverage:
	@$(MAKE) -s --no-print-directory clean
	@$(MAKE) --no-print-directory cov-build
	@$(MAKE) --no-print-directory cov-report

cov-clean:
	rm -f $(COV_GCDA) $(COV_GCNO) *.gcov untested

COV_CFLAGS = $(CFLAGS) -O0 -ftest-coverage -fprofile-arcs

cov-build:
	$(MAKE) CFLAGS="$(COV_CFLAGS)" all
	$(MAKE) TEST_COVERAGE=1 NO_OPENSSL=$(NO_OPENSSL) test

cov-report:
	@echo "--- untested files:" | tee untested
	@{ for f in $(SRC_C); do \
		gcda=$$(dirname $$f)"/"$$(basename $$f .c)".gcda"; \
		if test -f $$gcda; then \
			gcov -b -p -o $$(dirname $$f) $$f >/dev/null; \
		else \
			echo $$f | tee -a untested; \
		fi; \
	   done; }
	@rm -f *.h.gcov
	@echo "--- untested functions:" | tee -a untested
	@grep '^function .* called 0' *.c.gcov \
	| sed -e 's/\([^:]*\)\.gcov:function \([^ ]*\) called.*/\1: \2/' \
	| sed -e 's|#|/|g' | tee -a untested

