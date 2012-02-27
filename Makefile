# you can probably leave these settings alone:

LUADIR=lua
MUPDFDIR=mupdf
MUPDFTARGET=build/debug
MUPDFLIBDIR=$(MUPDFDIR)/$(MUPDFTARGET)

SQLITE3DIR=sqlite-amalgamation-3070900
LSQLITE3DIR=lsqlite3_svn08
FREETYPEDIR=$(MUPDFDIR)/thirdparty/freetype-2.4.8
LFSDIR=luafilesystem

# set this to your ARM cross compiler:

CC:=arm-unknown-linux-gnueabi-gcc
HOSTCC:=gcc

CFLAGS:=-O0 -g

# you can configure an emulation for the (eink) framebuffer here.
# the application won't use the framebuffer (and the special e-ink ioctls)
# in that case.

ifdef EMULATE_READER
CC:=$(HOSTCC)
EMULATE_READER_W?=824
EMULATE_READER_H?=1200
EMU_CFLAGS?=$(shell sdl-config --cflags)
EMU_CFLAGS+= -DEMULATE_READER \
	     -DEMULATE_READER_W=$(EMULATE_READER_W) \
	     -DEMULATE_READER_H=$(EMULATE_READER_H) \
	
EMU_LDFLAGS?=$(shell sdl-config --libs)
endif

# standard includes
KPDFREADER_CFLAGS=$(CFLAGS) -I$(LUADIR)/src -I$(MUPDFDIR)/

# enable tracing output:

#KPDFREADER_CFLAGS+= -DMUPDF_TRACE

# for now, all dependencies except for the libc are compiled into the final binary:

MUPDFLIBS := $(MUPDFLIBDIR)/libfitz.a
THIRDPARTYLIBS := $(MUPDFLIBDIR)/libfreetype.a \
	       	$(MUPDFLIBDIR)/libjpeg.a \
	       	$(MUPDFLIBDIR)/libopenjpeg.a \
	       	$(MUPDFLIBDIR)/libjbig2dec.a \
	       	$(MUPDFLIBDIR)/libz.a

# comment this out to build without sqlite3
SQLITE3OBJS := lsqlite3.o sqlite3.o
SQLITE3LDFLAGS := -lpthread

LUALIB := $(LUADIR)/src/liblua.a

kpdfview: kpdfview.o einkfb.o pdf.o blitbuffer.o input.o util.o ft.o $(SQLITE3OBJS) lfs.o $(MUPDFLIBS) $(THIRDPARTYLIBS) $(LUALIB)
	$(CC) -lm -ldl $(EMU_LDFLAGS) $(SQLITE3LDFLAGS) \
		kpdfview.o \
		einkfb.o \
		pdf.o \
		blitbuffer.o \
		input.o \
		util.o \
		ft.o \
		$(SQLITE3OBJS) \
		lfs.o \
		$(MUPDFLIBS) \
		$(THIRDPARTYLIBS) \
		$(LUALIB) \
		-o kpdfview

einkfb.o input.o: %.o: %.c
	$(CC) -c $(KPDFREADER_CFLAGS) $(EMU_CFLAGS) $< -o $@

ft.o: %.o: %.c
	$(CC) -c $(KPDFREADER_CFLAGS) -I$(FREETYPEDIR)/include $< -o $@

kpdfview.o pdf.o blitbuffer.o util.o: %.o: %.c
	$(CC) -c $(KPDFREADER_CFLAGS) -I$(LFSDIR)/src $< -o $@

sqlite3.o: $(SQLITE3DIR)/sqlite3.c
	$(CC) -c $(CFLAGS) $(SQLITE3DIR)/sqlite3.c -o $@

lsqlite3.o: $(LSQLITE3DIR)/lsqlite3.c
	$(CC) -c $(CFLAGS) -I$(LUADIR)/src -I$(SQLITE3DIR) $(LSQLITE3DIR)/lsqlite3.c -o $@

lfs.o: $(LFSDIR)/src/lfs.c
	$(CC) -c $(CFLAGS) -I$(LUADIR)/src -I$(LFSDIR)/src $(LFSDIR)/src/lfs.c -o $@

fetchthirdparty:
	-rmdir mupdf
	-rmdir lua
	-rm lua
	git clone git://git.ghostscript.com/mupdf.git
	( cd mupdf ; wget http://www.mupdf.com/download/mupdf-thirdparty.zip && unzip mupdf-thirdparty.zip )
	wget http://www.lua.org/ftp/lua-5.1.4.tar.gz && tar xvzf lua-5.1.4.tar.gz && ln -s lua-5.1.4 lua
	wget "http://lua.sqlite.org/index.cgi/zip/lsqlite3_svn08.zip?uuid=svn_8" && unzip "lsqlite3_svn08.zip?uuid=svn_8"
	wget "http://sqlite.org/sqlite-amalgamation-3070900.zip" && unzip sqlite-amalgamation-3070900.zip
	git clone https://github.com/keplerproject/luafilesystem.git

clean:
	-rm -f *.o kpdfview

cleanthirdparty:
	make -C $(LUADIR) clean
	make -C $(MUPDFDIR) clean
	-rm $(MUPDFDIR)/fontdump.host
	-rm $(MUPDFDIR)/cmapdump.host

$(MUPDFDIR)/fontdump.host:
	make -C mupdf CC="$(HOSTCC)" $(MUPDFTARGET)/fontdump
	cp -a $(MUPDFLIBDIR)/fontdump $(MUPDFDIR)/fontdump.host
	make -C mupdf clean

$(MUPDFDIR)/cmapdump.host:
	make -C mupdf CC="$(HOSTCC)" $(MUPDFTARGET)/cmapdump
	cp -a $(MUPDFLIBDIR)/cmapdump $(MUPDFDIR)/cmapdump.host
	make -C mupdf clean

$(MUPDFLIBS) $(THIRDPARTYLIBS): $(MUPDFDIR)/cmapdump.host $(MUPDFDIR)/fontdump.host
	# build only thirdparty libs, libfitz and pdf utils, which will care for libmupdf.a being built
	CFLAGS="$(CFLAGS)" make -C mupdf CC="$(CC)" CMAPDUMP=cmapdump.host FONTDUMP=fontdump.host MUPDF= XPS_APPS=

$(LUALIB):
	make -C lua/src CC="$(CC)" CFLAGS="$(CFLAGS)" MYCFLAGS=-DLUA_USE_LINUX MYLIBS="-Wl,-E" liblua.a

thirdparty: $(MUPDFLIBS) $(THIRDPARTYLIBS) $(LUALIBS)

INSTALL_DIR=kindlepdfviewer

install:
	# install to kindle using USB networking
	scp kpdfview *.lua root@192.168.2.2:/mnt/us/$(INSTALL_DIR)/
	scp launchpad/* root@192.168.2.2:/mnt/us/launchpad/

VERSION?=$(shell git rev-parse --short HEAD)
customupdate: kpdfview
	# ensure that build binary is for ARM
	file kpdfview | grep ARM || exit 1
	mkdir $(INSTALL_DIR)
	cp -p README.TXT COPYING kpdfview *.lua $(INSTALL_DIR)
	zip -r kindlepdfviewer-$(VERSION).zip $(INSTALL_DIR) launchpad/
	rm -Rf $(INSTALL_DIR)
	@echo "copy kindlepdfviewer-$(VERSION).zip to /mnt/us/customupdates and install with shift+shift+I"
