SHELL := /bin/sh

SCHEME ?= PathPal
CONFIG ?= Release
TEAM_ID ?= 542GXYT5Z2
PROJECT := PathPal/PathPal.xcodeproj
SIGN_IDENTITY ?= Developer ID Application: Kevin Tang (542GXYT5Z2)
APP_ENTITLEMENTS := PathPal/PathPal/PathPal.entitlements
FINDER_EXTENSION_ENTITLEMENTS := PathPal/PathPalFinderExtension/PathPalFinderExtension.entitlements

BUILD_SETTINGS = xcodebuild -showBuildSettings -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG)
TARGET_BUILD_DIR := $(shell $(BUILD_SETTINGS) 2>/dev/null | awk -F ' = ' '/TARGET_BUILD_DIR/ {print $$2; exit}')
WRAPPER_NAME := $(shell $(BUILD_SETTINGS) 2>/dev/null | awk -F ' = ' '/WRAPPER_NAME/ {print $$2; exit}')
APP_PATH := $(TARGET_BUILD_DIR)/$(WRAPPER_NAME)
PROCESS_NAME := $(basename $(WRAPPER_NAME))

.PHONY: build sign install test clean app-path

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
		DEVELOPMENT_TEAM=$(TEAM_ID) -allowProvisioningUpdates build
	$(MAKE) sign

sign:
	@test -d "$(APP_PATH)" || (echo "App not found at $(APP_PATH)" && exit 1)
	@if [ -d "$(APP_PATH)/Contents/PlugIns/PathPalFinderExtension.appex" ]; then \
		codesign --force --options runtime --timestamp=none \
			--entitlements "$(FINDER_EXTENSION_ENTITLEMENTS)" \
			--sign "$(SIGN_IDENTITY)" \
			"$(APP_PATH)/Contents/PlugIns/PathPalFinderExtension.appex"; \
	fi
	codesign --force --options runtime --timestamp=none \
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

app-path:
	@echo "$(APP_PATH)"
