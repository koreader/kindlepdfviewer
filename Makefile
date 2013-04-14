# the repository might not have been checked out yet, so make this
# able to fail:
-include koreader-base/Makefile.defs

# we want VERSION to carry the version of koreader, not koreader-base
VERSION=$(shell git describe HEAD)

# subdirectory we use to build the installation bundle
INSTALL_DIR=kindlepdfviewer

# subdirectory we use to setup emulation environment
EMU_DIR=emu

# for gettext
DOMAIN=kindlepdfviewer
TEMPLATE_DIR=l10n/templates
KOREADER_MISC_TOOL=../misc
XGETTEXT_BIN=$(KOREADER_MISC_TOOL)/gettext/lua_xgettext.py
MO_DIR=i18n



# files to copy from main directory
LUA_FILES=battery.lua commands.lua crereader.lua defaults.lua dialog.lua djvureader.lua readerchooser.lua filechooser.lua filehistory.lua fileinfo.lua filesearcher.lua font.lua graphics.lua helppage.lua image.lua inputbox.lua keys.lua pdfreader.lua koptconfig.lua koptreader.lua picviewer.lua reader.lua rendertext.lua screen.lua selectmenu.lua settings.lua unireader.lua widget.lua gettext.lua

all: koreader-base/koreader-base koreader-base/extr

koreader-base/koreader-base koreader-base/extr:
	make -C koreader-base extr koreader-base

fetchthirdparty:
	git submodule init
	git submodule update
	cd koreader-base && make fetchthirdparty

bootstrapemu:
	test -d $(EMU_DIR) || mkdir $(EMU_DIR)
	test -d $(EMU_DIR)/libs-emu || (cd $(EMU_DIR) && ln -s ../koreader-base/libs-emu ./)
	test -d $(EMU_DIR)/fonts || (cd $(EMU_DIR) && ln -s ../koreader-base/fonts ./)
	test -d $(EMU_DIR)/data || (cd $(EMU_DIR) && ln -s ../koreader-base/data ./)
	test -d $(EMU_DIR)/resources || (cd $(EMU_DIR) && ln -s ../resources ./)
	test -e $(EMU_DIR)/koreader-base || (cd $(EMU_DIR) && ln -s ../koreader-base/koreader-base ./)
	test -e $(EMU_DIR)/extr || (cd $(EMU_DIR) && ln -s ../koreader-base/extr ./)
	test -e $(EMU_DIR)/$(MO_DIR) || (cd $(EMU_DIR) && ln -s ../$(MO_DIR) ./)
	rm -f $(EMU_DIR)/*.lua && (cd $(EMU_DIR) && ln -s ../*.lua ./)
	test -e $(EMU_DIR)/history || (mkdir $(EMU_DIR)/history)

clean:
	cd koreader-base && make clean

cleanthirdparty:
	cd koreader-base && make cleanthirdparty

customupdate: koreader-base/koreader-base koreader-base/extr mo
	# ensure that the binaries were built for ARM
	file koreader-base/koreader-base | grep ARM || exit 1
	file koreader-base/extr | grep ARM || exit 1
	rm -f kindlepdfviewer-$(VERSION).zip
	rm -rf $(INSTALL_DIR)
	mkdir -p $(INSTALL_DIR)/{history,screenshots,clipboard,libs}
	cp -p README.md COPYING koreader-base/koreader-base koreader-base/extr kpdf.sh $(LUA_FILES) $(INSTALL_DIR)
	cp -r $(MO_DIR) $(INSTALL_DIR)
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

pot:
	$(XGETTEXT_BIN) *.lua > $(TEMPLATE_DIR)/$(DOMAIN).pot

mo:
	for po in `find l10n -iname '*.po'`; do \
		resource=`basename $$po .po` ; \
		lingua=`dirname $$po | xargs basename` ; \
		mkdir -p $(MO_DIR)/$$lingua/LC_MESSAGES/ ; \
		msgfmt -o $(MO_DIR)/$$lingua/LC_MESSAGES/$$resource.mo $$po ; \
		done


