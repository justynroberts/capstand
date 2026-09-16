.PHONY: help build app run install devices release release-dry clean

help:          ## List targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | sed -E 's/:.*## /\t/'

build:         ## Debug build of the bare binary
	swift build

app:           ## Release build wrapped in a signed Capstand.app
	swift build -c release
	./scripts/bundle.sh release

run: app       ## Build the app and launch it
	-pkill -x Capstand
	open Capstand.app

install: app   ## Copy into /Applications and launch (needed for Open at Login and self-update)
	-pkill -x Capstand
	rm -rf /Applications/Capstand.app
	ditto Capstand.app /Applications/Capstand.app
	open /Applications/Capstand.app

devices:       ## List capture devices as the app sees them
	swift run Capstand --list-devices

release:       ## Sign, notarise and publish: make release VERSION=0.2.0
	./scripts/release.sh $(VERSION)

release-dry:   ## Everything except tag and publish: make release-dry VERSION=0.2.0
	./scripts/release.sh $(VERSION) --dry-run

clean:         ## Remove build output
	rm -rf .build Capstand.app dist
