APP_NAME := MyHelper
DISPLAY_NAME := MyHelper
VERSION := $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist 2>/dev/null || echo 0.1.0)
BUILD_DIR := build
DIST_DIR := dist
APP_DIR := $(BUILD_DIR)/$(APP_NAME).app
MACOS_DIR := $(APP_DIR)/Contents/MacOS
RESOURCES_DIR := $(APP_DIR)/Contents/Resources
SOURCES := $(shell find Sources/MyHelper -name '*.swift' | sort)
MINDANCHOR_PLUGIN_SOURCES := $(shell find Sources/MindAnchorPlugin -name '*.swift' | sort)
MINDANCHOR_PLUGIN_BUILD_DIR := $(BUILD_DIR)/MindAnchorPlugin
MINDANCHOR_PLUGIN_LIB := $(MINDANCHOR_PLUGIN_BUILD_DIR)/libMindAnchorPlugin.a
GITLAB_MENU_PLUGIN_SOURCES := $(shell find Sources/GitLabMenuPlugin -name '*.swift' | sort)
GITLAB_MENU_PLUGIN_BUILD_DIR := $(BUILD_DIR)/GitLabMenuPlugin
GITLAB_MENU_PLUGIN_LIB := $(GITLAB_MENU_PLUGIN_BUILD_DIR)/libGitLabMenuPlugin.a
DEVELOPER_TOOLKIT_PLUGIN_SOURCES := $(shell find Sources/DeveloperToolkitPlugin -name '*.swift' | sort)
DEVELOPER_TOOLKIT_PLUGIN_BUILD_DIR := $(BUILD_DIR)/DeveloperToolkitPlugin
DEVELOPER_TOOLKIT_PLUGIN_LIB := $(DEVELOPER_TOOLKIT_PLUGIN_BUILD_DIR)/libDeveloperToolkitPlugin.a
TWO_FA_PLUGIN_SOURCES := $(shell find Sources/TwoFAPlugin -name '*.swift' | sort)
TWO_FA_PLUGIN_BUILD_DIR := $(BUILD_DIR)/TwoFAPlugin
TWO_FA_PLUGIN_LIB := $(TWO_FA_PLUGIN_BUILD_DIR)/libTwoFAPlugin.a
APP_ICON := Resources/MyHelper.icns
DEPLOYMENT_TARGET ?= 14.0
HOST_ARCH := $(shell uname -m)
APPLE_SILICON_TARGET_TRIPLE ?= arm64-apple-macos$(DEPLOYMENT_TARGET)
INTEL_TARGET_TRIPLE ?= x86_64-apple-macos$(DEPLOYMENT_TARGET)
TARGET_TRIPLE ?= $(HOST_ARCH)-apple-macos$(DEPLOYMENT_TARGET)
ARCH_NAME := $(shell echo "$(TARGET_TRIPLE)" | sed -E 's/-apple-macos.*//')
DMG_NAME := $(APP_NAME)-$(VERSION)-mac-$(ARCH_NAME).dmg
DMG_PATH := $(DIST_DIR)/$(DMG_NAME)
SIGN_IDENTITY ?= -
CODESIGN_EXTRA_FLAGS ?=
SWIFTC_TARGET_FLAGS := -target $(TARGET_TRIPLE)

ifeq ($(SIGN_IDENTITY),-)
CODESIGN_FLAGS := --force --sign -
else
CODESIGN_FLAGS := --force --options runtime --timestamp --sign "$(SIGN_IDENTITY)" $(CODESIGN_EXTRA_FLAGS)
endif

.PHONY: build run probe install dmg dmg-arm64 dmg-intel checksum checksum-arm64 checksum-intel release release-arm64 release-intel release-all notarize verify clean clean-dist

build:
	rm -rf "$(APP_DIR)"
	mkdir -p "$(MACOS_DIR)" "$(RESOURCES_DIR)"
	cp Resources/Info.plist "$(APP_DIR)/Contents/Info.plist"
	cp "$(APP_ICON)" "$(RESOURCES_DIR)/"
	cp Resources/*.png "$(RESOURCES_DIR)/"
	/usr/bin/xattr -dr com.apple.quarantine "$(APP_DIR)" 2>/dev/null || true
	mkdir -p "$(MINDANCHOR_PLUGIN_BUILD_DIR)"
	MACOSX_DEPLOYMENT_TARGET="$(DEPLOYMENT_TARGET)" swiftc -O -parse-as-library $(SWIFTC_TARGET_FLAGS) \
		-module-name MindAnchorPlugin \
		-emit-module -emit-module-path "$(MINDANCHOR_PLUGIN_BUILD_DIR)/MindAnchorPlugin.swiftmodule" \
		-emit-library -static $(MINDANCHOR_PLUGIN_SOURCES) \
		-o "$(MINDANCHOR_PLUGIN_LIB)" \
		-framework AppKit \
		-framework SwiftUI \
		-framework SwiftData \
		-framework AVFoundation \
		-framework Vision \
		-framework UserNotifications \
		-framework Security \
		-framework CryptoKit \
		-framework ImageIO
	mkdir -p "$(GITLAB_MENU_PLUGIN_BUILD_DIR)"
	MACOSX_DEPLOYMENT_TARGET="$(DEPLOYMENT_TARGET)" swiftc -O -parse-as-library $(SWIFTC_TARGET_FLAGS) \
		-module-name GitLabMenuPlugin \
		-emit-module -emit-module-path "$(GITLAB_MENU_PLUGIN_BUILD_DIR)/GitLabMenuPlugin.swiftmodule" \
		-emit-library -static $(GITLAB_MENU_PLUGIN_SOURCES) \
		-o "$(GITLAB_MENU_PLUGIN_LIB)" \
		-framework AppKit \
		-framework SwiftUI \
		-framework Security
	mkdir -p "$(DEVELOPER_TOOLKIT_PLUGIN_BUILD_DIR)"
	MACOSX_DEPLOYMENT_TARGET="$(DEPLOYMENT_TARGET)" swiftc -O -parse-as-library $(SWIFTC_TARGET_FLAGS) \
		-module-name DeveloperToolkitPlugin \
		-emit-module -emit-module-path "$(DEVELOPER_TOOLKIT_PLUGIN_BUILD_DIR)/DeveloperToolkitPlugin.swiftmodule" \
		-emit-library -static $(DEVELOPER_TOOLKIT_PLUGIN_SOURCES) \
		-o "$(DEVELOPER_TOOLKIT_PLUGIN_LIB)" \
		-framework AppKit \
		-framework SwiftUI \
		-framework CryptoKit
	mkdir -p "$(TWO_FA_PLUGIN_BUILD_DIR)"
	MACOSX_DEPLOYMENT_TARGET="$(DEPLOYMENT_TARGET)" swiftc -O -parse-as-library $(SWIFTC_TARGET_FLAGS) \
		-module-name TwoFAPlugin \
		-emit-module -emit-module-path "$(TWO_FA_PLUGIN_BUILD_DIR)/TwoFAPlugin.swiftmodule" \
		-emit-library -static $(TWO_FA_PLUGIN_SOURCES) \
		-o "$(TWO_FA_PLUGIN_LIB)" \
		-framework AppKit \
		-framework SwiftUI \
		-framework CryptoKit \
		-framework Security \
		-framework Vision \
		-framework UniformTypeIdentifiers
	MACOSX_DEPLOYMENT_TARGET="$(DEPLOYMENT_TARGET)" swiftc -O -parse-as-library $(SWIFTC_TARGET_FLAGS) $(SOURCES) \
		-o "$(MACOS_DIR)/$(APP_NAME)" \
		-I "$(MINDANCHOR_PLUGIN_BUILD_DIR)" \
		-I "$(GITLAB_MENU_PLUGIN_BUILD_DIR)" \
		-I "$(DEVELOPER_TOOLKIT_PLUGIN_BUILD_DIR)" \
		-I "$(TWO_FA_PLUGIN_BUILD_DIR)" \
		"$(MINDANCHOR_PLUGIN_LIB)" \
		"$(GITLAB_MENU_PLUGIN_LIB)" \
		"$(DEVELOPER_TOOLKIT_PLUGIN_LIB)" \
		"$(TWO_FA_PLUGIN_LIB)" \
		-framework Cocoa \
		-framework Carbon \
		-framework SwiftUI \
		-framework SwiftData \
		-framework AVFoundation \
		-framework Vision \
		-framework UserNotifications \
		-framework Security \
		-framework CryptoKit \
		-framework ImageIO \
		-framework UniformTypeIdentifiers
	codesign $(CODESIGN_FLAGS) "$(APP_DIR)"
	codesign --verify --deep --strict "$(APP_DIR)"

run: build
	open "$(APP_DIR)"

probe: build
	"$(MACOS_DIR)/$(APP_NAME)" --dump-json

install: build
	rm -rf "/Applications/$(APP_NAME).app"
	cp -R "$(APP_DIR)" "/Applications/$(APP_NAME).app"
	open "/Applications/$(APP_NAME).app"

dmg: build
	APP_NAME="$(APP_NAME)" \
	DISPLAY_NAME="$(DISPLAY_NAME)" \
	VERSION="$(VERSION)" \
	ARCH_NAME="$(ARCH_NAME)" \
	BUILD_DIR="$(BUILD_DIR)" \
	DIST_DIR="$(DIST_DIR)" \
	APP_DIR="$(APP_DIR)" \
	DMG_PATH="$(DMG_PATH)" \
	DMG_SIGN_IDENTITY="$(DMG_SIGN_IDENTITY)" \
	./scripts/package-dmg.sh

dmg-arm64:
	$(MAKE) dmg TARGET_TRIPLE="$(APPLE_SILICON_TARGET_TRIPLE)"

dmg-intel:
	$(MAKE) dmg TARGET_TRIPLE="$(INTEL_TARGET_TRIPLE)"

checksum: dmg
	shasum -a 256 "$(DMG_PATH)" > "$(DMG_PATH).sha256"
	@cat "$(DMG_PATH).sha256"

checksum-arm64:
	$(MAKE) checksum TARGET_TRIPLE="$(APPLE_SILICON_TARGET_TRIPLE)"

checksum-intel:
	$(MAKE) checksum TARGET_TRIPLE="$(INTEL_TARGET_TRIPLE)"

release: clean checksum
	@echo "Release artifact: $(DMG_PATH)"

release-arm64:
	$(MAKE) release TARGET_TRIPLE="$(APPLE_SILICON_TARGET_TRIPLE)"

release-intel:
	$(MAKE) release TARGET_TRIPLE="$(INTEL_TARGET_TRIPLE)"

release-all: clean-dist
	$(MAKE) release-arm64
	$(MAKE) release-intel

notarize: dmg
	APPLE_ID="$(APPLE_ID)" \
	TEAM_ID="$(TEAM_ID)" \
	NOTARY_PASSWORD="$(NOTARY_PASSWORD)" \
	DMG_PATH="$(DMG_PATH)" \
	./scripts/notarize-dmg.sh

verify: build
	file "$(MACOS_DIR)/$(APP_NAME)"
	codesign -dv --verbose=4 "$(APP_DIR)"

clean:
	rm -rf "$(BUILD_DIR)"

clean-dist:
	rm -rf "$(DIST_DIR)"
