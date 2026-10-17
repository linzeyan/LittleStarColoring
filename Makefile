# Coloring ("小星星塗色" / Little Star Coloring) — iPad coloring app for children 5 and under.
#
#   make pages        # rebuild Coloring/Resources/Pages from LineArt/sources
#   make stamps       # fetch the emoji stamp pictures into Coloring/Resources/Stamps
#   make icon         # render the app icon from tools/AppIcon.svg
#   make test         # unit tests on the simulator (+ brush snapshots in build/snapshots)
#   make test-ui      # UI walk; screenshots are exported to build/ui-shots
#   make run          # build, install and launch on the simulator
#   make device       # build Release and install on the iPad mini 4 (see below)
#   make release      # archive + export an .ipa for App Store Connect
#
# Coloring.xcodeproj is generated from project.yml via xcodegen — not hand-edited and
# not committed. Edit project.yml, then `make generate`.

PROJECT   := Coloring.xcodeproj
SCHEME    := Coloring
DERIVED   := build
BUNDLE_ID := com.zeyanlin.littlestarcoloring
# The smallest-height iPad simulator: if the toolbars fit its 744pt landscape height,
# they fit the iPad mini 4's 768pt.
SIMULATOR ?= iPad mini (A17 Pro)
SIM_OS    ?= 27.0
DESTINATION := platform=iOS Simulator,name=$(SIMULATOR),OS=$(SIM_OS)
SNAPSHOTS := $(CURDIR)/$(DERIVED)/snapshots
UI_RESULT := $(DERIVED)/ui.xcresult
UI_SHOTS  := $(DERIVED)/ui-shots
ICON      := Coloring/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
ARCHIVE   := $(DERIVED)/$(SCHEME).xcarchive
EXPORT    := $(DERIVED)/export

.DEFAULT_GOAL := help
.PHONY: help generate pages pages-check stamps icon build test test-ui run device profile release archive ipa open clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

generate: ## Regenerate Coloring.xcodeproj from project.yml
	xcodegen generate --quiet

pages: ## Rebuild coloring pages from LineArt/sources (needs uv + rsvg-convert)
	uv run tools/build_pages.py

pages-check: ## Self-check the page pipeline on a synthetic drawing
	uv run tools/build_pages.py --self-check

stamps: ## Fetch the emoji stamp pictures (Fluent Emoji, MIT) from Stamps.swift's list
	uv run tools/fetch_stamps.py

# App Store Connect rejects an icon with an alpha channel, even a fully opaque one,
# and rsvg-convert always writes one: flatten to RGB.
icon: ## Render the app icon from tools/AppIcon.svg (needs rsvg-convert + uv)
	rsvg-convert -w 1024 -h 1024 tools/AppIcon.svg | uv run --quiet --with pillow python -c \
		"import sys; from PIL import Image; Image.open(sys.stdin.buffer).convert('RGB').save('$(ICON)')"

build: generate ## Compile the app for the simulator
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination 'generic/platform=iOS Simulator' \
		-derivedDataPath $(DERIVED) build

test: generate ## Run unit tests; brush snapshots go to build/snapshots
	@mkdir -p $(SNAPSHOTS)
	TEST_RUNNER_SNAPSHOT_DIR=$(SNAPSHOTS) xcodebuild test -project $(PROJECT) \
		-scheme $(SCHEME) -derivedDataPath $(DERIVED) \
		-destination '$(DESTINATION)' -only-testing:ColoringTests

test-ui: generate ## Run the UI walk and export its screenshots to build/ui-shots
	rm -rf $(UI_RESULT) $(UI_SHOTS)
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(DERIVED) \
		-destination '$(DESTINATION)' -only-testing:ColoringUITests \
		-resultBundlePath $(UI_RESULT)
	xcrun xcresulttool export attachments --path $(UI_RESULT) --output-path $(UI_SHOTS)

run: build ## Install and launch on the simulator
	xcrun simctl boot '$(SIMULATOR)' 2>/dev/null || true
	open -a Simulator
	xcrun simctl install booted $(DERIVED)/Build/Products/Debug-iphonesimulator/$(SCHEME).app
	xcrun simctl launch booted $(BUNDLE_ID)

# Xcode 27 doesn't list iOS 15 devices at all (no Run, no Instruments) and `devicectl`
# needs iOS 17, so the mini 4 is installed through libimobiledevice
# (`brew install ideviceinstaller`). The UDID is explicit because a plugged-in iPhone
# would otherwise be picked first. Release: it's what a child uses and what
# performance is judged on.
IPAD_UDID ?= 000b0f27b97f1a516b007cba6237f6a2c925a39b
device: generate ## Build Release and install on the iPad mini 4 (iOS 15)
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release -derivedDataPath $(DERIVED) \
		-destination 'generic/platform=iOS' -allowProvisioningUpdates build
	ideviceinstaller -u $(IPAD_UDID) install $(DERIVED)/Build/Products/Release-iphoneos/$(SCHEME).app

# Xcode 27's Instruments can't record iOS 15 either. Xcode 26.6 can: it sits in
# ~/Developer/Xcode-26.6.noindex, is never xcode-select'ed or opened, and only its
# xctrace runs, for this one command. One recording covers all three budgets (frame
# time, `open page`, memory) so the iPad is walked through once. Profiles the
# installed app: run `make device` first.
XCODE_26  ?= $(HOME)/Developer/Xcode-26.6.noindex/Xcode.app/Contents/Developer
TRACE_FOR ?= 3m
profile: ## Record the installed app on the iPad mini 4 with Xcode 26.6's xctrace
	@mkdir -p $(DERIVED)/traces
	DEVELOPER_DIR=$(XCODE_26) xcrun xctrace record --template 'Metal System Trace' \
		--instrument 'Points of Interest' --instrument 'Activity Monitor' \
		--device $(IPAD_UDID) --time-limit $(TRACE_FOR) --output $(DERIVED)/traces --no-prompt \
		--launch -- $(BUNDLE_ID)

release: archive ipa ## Archive + export an uploadable .ipa

archive: generate ## Archive a signed Release build (auto signing)
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-destination 'generic/platform=iOS' -archivePath $(ARCHIVE) \
		-allowProvisioningUpdates archive

ipa: ## Export an uploadable .ipa from the archive (run `make archive` first)
	@# Force the system rsync first: a Homebrew rsync in PATH breaks the IPA
	@# packaging step with "Copy failed" (extended-attributes incompatibility).
	PATH="/usr/bin:/bin:/usr/sbin:/sbin:$$PATH" xcodebuild -exportArchive \
		-archivePath $(ARCHIVE) -exportOptionsPlist exportOptions.plist \
		-exportPath $(EXPORT) -allowProvisioningUpdates
	@echo "IPA → $(EXPORT)/$(SCHEME).ipa  (upload via Transporter)"

open: generate ## Open the project in Xcode
	open $(PROJECT)

clean: ## Remove build artifacts
	rm -rf $(DERIVED)
