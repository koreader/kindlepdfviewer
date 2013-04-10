all: update

update:
	tx pull -a

bootstrap:
	tx set --auto-local -r kindlepdfviewer.kindlepdfviewer "<lang>/kindlepdfviewer.po" \
		--source-language=en \
		--source-file "templates/kindlepdfviewer.pot" --execute

.PHONY: all clean

