SHELL := /bin/sh

SCHEME ?= PathPal
CONFIG ?= Release
TEAM_ID ?= 542GXYT5Z2
PROJECT := PathPal/PathPal.xcodeproj

BUILD_SETTINGS = xcodebuild -showBuildSettings -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG)
TARGET_BUILD_DIR := $(shell $(BUILD_SETTINGS) 2>/dev/null | awk -F ' = ' '/TARGET_BUILD_DIR/ {print $$2; exit}')
WRAPPER_NAME := $(shell $(BUILD_SETTINGS) 2>/dev/null | awk -F ' = ' '/WRAPPER_NAME/ {print $$2; exit}')
APP_PATH := $(TARGET_BUILD_DIR)/$(WRAPPER_NAME)
PROCESS_NAME := $(basename $(WRAPPER_NAME))

.PHONY: build install test clean app-path

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
		DEVELOPMENT_TEAM=$(TEAM_ID) -allowProvisioningUpdates build

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
