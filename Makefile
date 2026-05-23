PYTHON      := python3
MENU_BAR_APP = menu-bar/.build/TeamRecorderBar.app
DIST_DIR     = dist

.PHONY: run test setup build-recorder doctor permissions stop index menu-bar menu-bar-install dist

run:
	$(PYTHON) teams_recorder_v2.py

test:
	$(PYTHON) -m pytest test_recorder_v2.py -q -p no:cacheprovider

setup:
	@bash setup.sh

doctor:
	@$(PYTHON) teams_recorder_v2.py --doctor

permissions:
	@$(PYTHON) teams_recorder_v2.py --permissions

stop:
	@$(PYTHON) teams_recorder_v2.py --stop

index:
	@$(PYTHON) teams_recorder_v2.py --index

build-recorder:
	cd recorder && swift build -c release
	cp recorder/.build/release/recorder recorder/recorder
	codesign -s - --force \
	    --entitlements recorder/entitlements.plist \
	    recorder/recorder
	@echo "  ✓  recorder ($$(uname -m)) — done"

menu-bar:
	cd menu-bar && swift build -c release
	@rm -rf "$(MENU_BAR_APP)"
	@mkdir -p "$(MENU_BAR_APP)/Contents/MacOS" \
	           "$(MENU_BAR_APP)/Contents/Resources"
	@cp menu-bar/.build/release/TeamRecorderBar \
	       "$(MENU_BAR_APP)/Contents/MacOS/"
	@cp menu-bar/Resources/Info.plist \
	       "$(MENU_BAR_APP)/Contents/"
	@# Embed absolute watcher path so the app can find it after `make menu-bar-install`
	@echo "$$(pwd)/teams_recorder_v2.py" \
	       > "$(MENU_BAR_APP)/Contents/Resources/watcher_path.txt"
	@codesign -s - --force "$(MENU_BAR_APP)"
	@echo "  ✓  TeamRecorderBar.app ($$(uname -m)) → $(MENU_BAR_APP)"

menu-bar-install: menu-bar
	@rm -rf /Applications/TeamRecorderBar.app
	@cp -r "$(MENU_BAR_APP)" /Applications/
	@echo "  ✓  Installed to /Applications/TeamRecorderBar.app"
	@open /Applications/TeamRecorderBar.app

dist: menu-bar
	@mkdir -p "$(DIST_DIR)"
	@rm -f "$(DIST_DIR)/TeamRecorder.zip"
	@rm -rf "$(DIST_DIR)/TeamRecorderBar.app"
	@cp -r "$(MENU_BAR_APP)" "$(DIST_DIR)/"
	@(cd "$(DIST_DIR)" && zip -qr "TeamRecorder.zip" "TeamRecorderBar.app")
	@rm -rf "$(DIST_DIR)/TeamRecorderBar.app"
	@echo "  ⚠  $(DIST_DIR)/TeamRecorder.zip — LOCAL MACHINE ONLY"
	@echo "     The .app embeds an absolute path to teams_recorder_v2.py on this machine."
	@echo "     It will NOT work on a teammate's machine. See packaging/README.md."
