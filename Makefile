# koreader-base directory
KOR_BASE=koreader-base

# the repository might not have been checked out yet, so make this
# able to fail:
-include $(KOR_BASE)/Makefile.defs

# we want VERSION to carry the version of koreader, not koreader-base
VERSION=$(shell git describe HEAD)

# subdirectory we use to build the installation bundle
INSTALL_DIR=kindlepdfviewer-$(MACHINE)

# files to link from main directory
INSTALL_FILES=battery.lua commands.lua crereader.lua defaults.lua dialog.lua djvureader.lua readerchooser.lua filechooser.lua filehistory.lua fileinfo.lua filesearcher.lua font.lua graphics.lua helppage.lua image.lua inputbox.lua keys.lua pdfreader.lua koptconfig.lua koptreader.lua picviewer.lua reader.lua rendertext.lua screen.lua selectmenu.lua settings.lua unireader.lua widget.lua gettext.lua kpdf.sh

# for gettext
DOMAIN=kindlepdfviewer
TEMPLATE_DIR=l10n/templates
KOREADER_MISC_TOOL=../misc
XGETTEXT_BIN=$(KOREADER_MISC_TOOL)/gettext/lua_xgettext.py
MO_DIR=$(INSTALL_DIR)/kindlepdfviewer/i18n


all: mo $(KOR_BASE)/$(OUTPUT_DIR)/luajit
	echo $(VERSION) > git-rev
	mkdir -p $(INSTALL_DIR)/kindlepdfviewer
	cp -rfL $(KOR_BASE)/$(OUTPUT_DIR)/* $(INSTALL_DIR)/kindlepdfviewer/
ifdef EMULATE_READER
	cp -f $(KOR_BASE)/ev_replay.py $(INSTALL_DIR)/kindlepdfviewer/
endif
	for f in $(INSTALL_FILES); do \
		ln -sf ../../$$f $(INSTALL_DIR)/kindlepdfviewer/; \
		done
	mkdir -p $(INSTALL_DIR)/kindlepdfviewer/screenshots
	mkdir -p $(INSTALL_DIR)/kindlepdfviewer/data/dict
	mkdir -p $(INSTALL_DIR)/kindlepdfviewer/data/tessdata
	mkdir -p $(INSTALL_DIR)/kindlepdfviewer/fonts/host
	ln -sf ../extensions $(INSTALL_DIR)/
	ln -sf ../launchpad $(INSTALL_DIR)/
	# clean up
	rm -rf $(INSTALL_DIR)/kindlepdfviewer/data/{cr3.ini,cr3skin-format.txt,desktop,devices,manual}
	rm $(INSTALL_DIR)/kindlepdfviewer/fonts/droid/DroidSansFallbackFull.ttf

$(KOR_BASE)/$(OUTPUT_DIR)/luajit: koreader-base
$(KOR_BASE)/$(OUTPUT_DIR)/extr: koreader-base

koreader-base:
	$(MAKE) -C $(KOR_BASE)

fetchthirdparty:
	git submodule init
	git submodule update
	$(MAKE) -C $(KOR_BASE) fetchthirdparty

clean:
	rm -rf $(INSTALL_DIR)
	$(MAKE) -C $(KOR_BASE) clean

customupdate: all
	# ensure that the binaries were built for ARM
	file $(INSTALL_DIR)/kindlepdfviewer/luajit | grep ARM || exit 1
	# remove old package if any
	rm -f kindlepdfviewer-$(MACHINE)-$(VERSION).zip
	# create new package
	cd $(INSTALL_DIR) && \
		zip -9 -r \
			../kindlepdfviewer-$(MACHINE)-$(VERSION).zip *
	# @TODO write an installation script for KUAL   (houqp)
	@echo "copy kindlepdfviewer-$(MACHINE)-$(VERSION).zip to /mnt/us/customupdates and install with shift+shift+I"


pot:
	$(XGETTEXT_BIN) reader.lua `find frontend -iname "*.lua"` \
		> $(TEMPLATE_DIR)/$(DOMAIN).pot

mo:
	for po in `find l10n -iname '*.po'`; do \
		resource=`basename $$po .po` ; \
		lingua=`dirname $$po | xargs basename` ; \
		mkdir -p $(MO_DIR)/$$lingua/LC_MESSAGES/ ; \
		msgfmt -o $(MO_DIR)/$$lingua/LC_MESSAGES/$$resource.mo $$po ; \
		done

