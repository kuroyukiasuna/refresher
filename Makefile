APP := build/Refresher.app
INSTALL_DIR ?= /Applications

# The Command Line Tools ship Swift Testing's macro plugin in a folder SwiftPM doesn't search.
TESTING_PLUGINS := $(shell xcode-select -p)/usr/lib/swift/host/plugins/testing
ifneq ($(wildcard $(TESTING_PLUGINS)),)
TEST_FLAGS := -Xswiftc -plugin-path -Xswiftc $(TESTING_PLUGINS)
endif

.PHONY: app run install test detect clean

app:
	scripts/build-app.sh

run: app
	open $(APP)

install: app
	-pkill -x Refresher
	rm -rf "$(INSTALL_DIR)/Refresher.app"
	cp -R $(APP) "$(INSTALL_DIR)/"
	open "$(INSTALL_DIR)/Refresher.app"

test:
	swift test $(TEST_FLAGS)

# Prints what meeting detection sees every 2 seconds. Run it while in a call to check it.
detect: app
	$(APP)/Contents/MacOS/Refresher --detect

clean:
	rm -rf .build build
