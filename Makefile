# the repository might not have been checked out yet, so make this
# able to fail:
-include koreader-base/Makefile.defs

# we want VERSION to carry the version of koreader, not koreader-base
VERSION=$(shell git describe HEAD)

# subdirectory we use to build the installation bundle
INSTALL_DIR=kindlepdfviewer

# files to copy from main directory
LUA_FILES=battery.lua commands.lua crereader.lua defaults.lua dialog.lua djvureader.lua readerchooser.lua filechooser.lua filehistory.lua fileinfo.lua filesearcher.lua font.lua graphics.lua helppage.lua image.lua inputbox.lua keys.lua pdfreader.lua koptconfig.lua koptreader.lua picviewer.lua reader.lua rendertext.lua screen.lua selectmenu.lua settings.lua unireader.lua widget.lua

all: koreader-base/koreader-base koreader-base/extr

koreader-base/koreader-base:
	cd koreader-base && make koreader-base

koreader-base/extr:
	cd koreader-base && make extr

fetchthirdparty:
	git submodule init
	git submodule update
	cd koreader-base && make fetchthirdparty

clean:
	cd koreader-base && make clean

cleanthirdparty:
	cd koreader-base && make cleanthirdparty

customupdate: koreader-base/koreader-base koreader-base/extr
	# ensure that the binaries were built for ARM
	file koreader-base/koreader-base | grep ARM || exit 1
	file koreader-base/extr | grep ARM || exit 1
	rm -f kindlepdfviewer-$(VERSION).zip
	rm -rf $(INSTALL_DIR)
	mkdir -p $(INSTALL_DIR)/{history,screenshots,clipboard,libs}
	cp -p README.md COPYING koreader-base/koreader-base koreader-base/extr kpdf.sh $(LUA_FILES) $(INSTALL_DIR)
	$(STRIP) --strip-unneeded $(INSTALL_DIR)/koreader-base $(INSTALL_DIR)/extr
	mkdir $(INSTALL_DIR)/data
	cp -L koreader-base/$(DJVULIB) koreader-base/$(CRELIB) koreader-base/$(LUALIB) koreader-base/$(K2PDFOPTLIB) $(INSTALL_DIR)/libs
	$(STRIP) --strip-unneeded $(INSTALL_DIR)/libs/*
	cp -rpL koreader-base/data/*.css $(INSTALL_DIR)/data
	cp -rpL koreader-base/fonts $(INSTALL_DIR)
	rm $(INSTALL_DIR)/fonts/droid/DroidSansFallbackFull.ttf
	echo $(VERSION) > git-rev
	cp -r git-rev resources $(INSTALL_DIR)
	mkdir $(INSTALL_DIR)/fonts/host
	zip -9 -r kindlepdfviewer-$(VERSION).zip $(INSTALL_DIR) launchpad/ extensions/
	rm -rf $(INSTALL_DIR)
	@echo "copy kindlepdfviewer-$(VERSION).zip to /mnt/us/customupdates and install with shift+shift+I"
