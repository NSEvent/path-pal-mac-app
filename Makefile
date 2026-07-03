SHELL := /bin/sh

SCHEME ?= PathPal
CONFIG ?= Release
TEAM_ID ?= 542GXYT5Z2
PROJECT := PathPal/PathPal.xcodeproj
SIGN_IDENTITY ?= Developer ID Application: Kevin Tang (542GXYT5Z2)
APP_ENTITLEMENTS := PathPal/PathPal/PathPal.entitlements
FINDER_EXTENSION_ENTITLEMENTS := PathPal/PathPalFinderExtension/PathPalFinderExtension.entitlements

# Dev signing skips the timestamp server round-trip; `make release` overrides
# with a secure timestamp, which notarization requires.
TIMESTAMP_FLAG ?= --timestamp=none

# App Store Connect API key for notarytool (key file stays outside the repo)
NOTARY_KEY_FILE ?= $(HOME)/.config/app-store-connect/AuthKey_3RJ3N575K3.p8
NOTARY_KEY_ID ?= 3RJ3N575K3
NOTARY_ISSUER ?= 8f102d01-4be9-47cc-afd3-f96a20c65119

VERSION := $(shell /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' PathPal/PathPal/Info.plist)
DIST_DIR := dist

BUILD_SETTINGS = xcodebuild -showBuildSettings -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG)
TARGET_BUILD_DIR := $(shell $(BUILD_SETTINGS) 2>/dev/null | awk -F ' = ' '/TARGET_BUILD_DIR/ {print $$2; exit}')
WRAPPER_NAME := $(shell $(BUILD_SETTINGS) 2>/dev/null | awk -F ' = ' '/WRAPPER_NAME/ {print $$2; exit}')
APP_PATH := $(TARGET_BUILD_DIR)/$(WRAPPER_NAME)
PROCESS_NAME := $(basename $(WRAPPER_NAME))

.PHONY: build sign install test clean app-path release notarize dmg

# UNIVERSAL=1 forces an arm64+x86_64 build. Release builds need it: the
# 1.0.0 default came out arm64-only even though ONLY_ACTIVE_ARCH only
# lives in Debug. Dev builds stay single-arch for speed.
ifeq ($(UNIVERSAL),1)
ARCH_SETTINGS := ARCHS=arm64\ x86_64 ONLY_ACTIVE_ARCH=NO
else
ARCH_SETTINGS :=
endif

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
		DEVELOPMENT_TEAM=$(TEAM_ID) $(ARCH_SETTINGS) -allowProvisioningUpdates build
	$(MAKE) sign TIMESTAMP_FLAG=$(TIMESTAMP_FLAG)

sign:
	@test -d "$(APP_PATH)" || (echo "App not found at $(APP_PATH)" && exit 1)
	@if [ -d "$(APP_PATH)/Contents/Frameworks/Sparkle.framework" ]; then \
		SPARKLE="$(APP_PATH)/Contents/Frameworks/Sparkle.framework/Versions/B"; \
		for item in "$$SPARKLE/XPCServices/"*.xpc "$$SPARKLE/Updater.app" "$$SPARKLE/Autoupdate"; do \
			[ -e "$$item" ] && codesign --force --options runtime $(TIMESTAMP_FLAG) \
				--sign "$(SIGN_IDENTITY)" "$$item"; \
		done; \
		codesign --force --options runtime $(TIMESTAMP_FLAG) \
			--sign "$(SIGN_IDENTITY)" \
			"$(APP_PATH)/Contents/Frameworks/Sparkle.framework"; \
	fi
	@if [ -d "$(APP_PATH)/Contents/PlugIns/PathPalFinderExtension.appex" ]; then \
		codesign --force --options runtime $(TIMESTAMP_FLAG) \
			--entitlements "$(FINDER_EXTENSION_ENTITLEMENTS)" \
			--sign "$(SIGN_IDENTITY)" \
			"$(APP_PATH)/Contents/PlugIns/PathPalFinderExtension.appex"; \
	fi
	codesign --force --options runtime $(TIMESTAMP_FLAG) \
		--entitlements "$(APP_ENTITLEMENTS)" \
		--sign "$(SIGN_IDENTITY)" "$(APP_PATH)"

install: build
	-pkill -x "$(PROCESS_NAME)" || true
	sleep 1
	/usr/bin/ditto "$(APP_PATH)" "/Applications/$(WRAPPER_NAME)"
	open "/Applications/$(WRAPPER_NAME)"

test:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		DEVELOPMENT_TEAM=$(TEAM_ID) -allowProvisioningUpdates test

clean:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean
	rm -rf ~/Library/Developer/Xcode/DerivedData/PathPal-*
	rm -rf $(DIST_DIR)

app-path:
	@echo "$(APP_PATH)"

# Full release: timestamped build, notarize, staple, then zip + DMG in dist/
release:
	$(MAKE) build TIMESTAMP_FLAG=--timestamp UNIVERSAL=1
	$(MAKE) notarize
	$(MAKE) dmg
	@echo "Release artifacts:"
	@ls -lh $(DIST_DIR)

notarize:
	@test -f "$(NOTARY_KEY_FILE)" || (echo "Notary key not found at $(NOTARY_KEY_FILE)" && exit 1)
	mkdir -p $(DIST_DIR)
	/usr/bin/ditto -c -k --keepParent "$(APP_PATH)" "$(DIST_DIR)/$(PROCESS_NAME)-notarize.zip"
	xcrun notarytool submit "$(DIST_DIR)/$(PROCESS_NAME)-notarize.zip" \
		--key "$(NOTARY_KEY_FILE)" --key-id "$(NOTARY_KEY_ID)" --issuer "$(NOTARY_ISSUER)" \
		--wait
	xcrun stapler staple "$(APP_PATH)"
	rm -f "$(DIST_DIR)/$(PROCESS_NAME)-notarize.zip"
	/usr/bin/ditto -c -k --keepParent "$(APP_PATH)" "$(DIST_DIR)/$(PROCESS_NAME)-$(VERSION).zip"

dmg:
	mkdir -p $(DIST_DIR)/dmg-staging
	/usr/bin/ditto "$(APP_PATH)" "$(DIST_DIR)/dmg-staging/$(WRAPPER_NAME)"
	ln -sf /Applications "$(DIST_DIR)/dmg-staging/Applications"
	hdiutil create -volname "$(PROCESS_NAME)" -srcfolder "$(DIST_DIR)/dmg-staging" \
		-ov -format UDZO "$(DIST_DIR)/$(PROCESS_NAME)-$(VERSION).dmg"
	rm -rf $(DIST_DIR)/dmg-staging
