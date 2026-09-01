BREW_PYTHON := $(shell /opt/homebrew/bin/brew --prefix python 2>/dev/null)/bin/python3
PYTHON      := $(if $(wildcard $(BREW_PYTHON)),$(BREW_PYTHON),python3)
MENU_BAR_APP = menu-bar/.build/TeamRecorderBar.app
DIST_DIR     = dist
VERSION      = 1.2.3
RELEASE_ZIP  = $(DIST_DIR)/TeamRecorderBar-v$(VERSION).zip

.PHONY: run test setup build-recorder doctor permissions stop index watcher-pyz menu-bar menu-bar-install release icon reset-setup uninstall clean-reinstall

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

watcher-pyz:
	@echo "  ⏳  Building watcher.pyz..."
	@rm -rf /tmp/watcher-pyz-build
	@mkdir -p /tmp/watcher-pyz-build
	@$(PYTHON) -m pip install --quiet --no-compile --target /tmp/watcher-pyz-build python-dotenv
	@cp teams_recorder_v2.py /tmp/watcher-pyz-build/__main__.py
	@$(PYTHON) -m zipapp /tmp/watcher-pyz-build \
	    --python "/usr/bin/python3" \
	    --output watcher.pyz
	@rm -rf /tmp/watcher-pyz-build
	@echo "  ✓  watcher.pyz ($$(du -sh watcher.pyz | cut -f1))"

menu-bar: icon watcher-pyz
	@echo "  ⏳  Building TeamRecorderBar... (ครั้งแรกอาจใช้เวลา ~1 นาที)"
	@echo "     กำลัง compile Swift app..."
	@cd menu-bar && swift build -c release
	@rm -rf "$(MENU_BAR_APP)"
	@mkdir -p "$(MENU_BAR_APP)/Contents/MacOS" \
		           "$(MENU_BAR_APP)/Contents/Resources"
	@cp menu-bar/.build/release/TeamRecorderBar \
	       "$(MENU_BAR_APP)/Contents/MacOS/"
	@cp menu-bar/Resources/Info.plist \
	       "$(MENU_BAR_APP)/Contents/"
	@cp menu-bar/Resources/AppIcon.icns \
	       "$(MENU_BAR_APP)/Contents/Resources/"
	@cp watcher.pyz "$(MENU_BAR_APP)/Contents/Resources/"
	@cp recorder/recorder "$(MENU_BAR_APP)/Contents/Resources/"
	@cp .env.example "$(MENU_BAR_APP)/Contents/Resources/"
	@codesign -s - --force \
	    --entitlements recorder/entitlements.plist \
	    "$(MENU_BAR_APP)/Contents/Resources/recorder"
	@codesign -s - --force "$(MENU_BAR_APP)"
	@echo "  ✓  TeamRecorderBar.app ($$(uname -m)) → $(MENU_BAR_APP)"

menu-bar-install: menu-bar
	@echo "  ⏳  Installing TeamRecorderBar.app..."
	@rm -rf /Applications/TeamRecorderBar.app
	@cp -r "$(MENU_BAR_APP)" /Applications/
	@touch /Applications/TeamRecorderBar.app
	@/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
	    -f /Applications/TeamRecorderBar.app 2>/dev/null || true
	@echo "  ✓  Installed → /Applications/TeamRecorderBar.app"
	@echo "  ⏳  Opening Team Recorder..."
	@open /Applications/TeamRecorderBar.app
	@echo ""
	@echo "  ▶  แอปเปิดแล้ว — มองหา icon ที่ menu bar มุมขวาบนของจอ"
	@echo "  ▶  Setup Guide จะขึ้นอัตโนมัติถ้ายังไม่เคยติดตั้ง"
	@echo "     (ถ้าไม่ขึ้น รัน: make reset-setup แล้วเปิดแอปใหม่)"

icon:
	@[ -f menu-bar/Resources/AppIcon.icns ] || python3 scripts/make_icon.py

reset-setup:
	@defaults delete com.team-recorder.menu-bar setupCompleted 2>/dev/null || true
	@echo "  ✓  Setup state reset — เปิดแอปใหม่เพื่อรัน Setup Guide"

uninstall:
	@echo "  ⏳  Stopping watcher and quitting app..."
	-@$(PYTHON) teams_recorder_v2.py --stop 2>/dev/null || true
	-@osascript -e 'tell application "TeamRecorderBar" to quit' 2>/dev/null || true
	@sleep 0.5
	@echo "  ⏳  Removing app and preferences..."
	-@rm -rf /Applications/TeamRecorderBar.app
	-@defaults delete com.team-recorder.menu-bar 2>/dev/null || true
	-@rm -f "$(HOME)/Library/Preferences/com.team-recorder.menu-bar.plist"
	@echo "  ⏳  Clearing runtime state (status.json, PID files)..."
	-@rm -f "$(HOME)/Library/Application Support/Team Recorder/status.json"
	-@rm -f "$(HOME)/Library/Application Support/Team Recorder/team-recorder.pid"
	-@rm -f "$(HOME)/Library/Application Support/Team Recorder/recorder.pid"
	@echo ""
	@echo "  ✓  Team Recorder uninstalled."
	@echo ""
	@echo "  ⚠  Recordings in ~/Documents/Teams Recording/ are NOT removed."
	@echo ""
	@echo "  To also clear macOS permissions, revoke manually in System Settings:"
	@echo "    Privacy & Security → Screen Recording  → TeamRecorderBar → click −"
	@echo "    Privacy & Security → Microphone         → TeamRecorderBar → toggle off"
	@echo "    Privacy & Security → Calendars          → TeamRecorderBar → None"
	@echo "    Privacy & Security → Automation         → icalBuddy → toggle off (if listed)"
	@echo ""
	@echo "  To reinstall: make menu-bar-install"

clean-reinstall: uninstall menu-bar-install

release: menu-bar
	@echo "  ⏳  Building release v$(VERSION)..."
	@mkdir -p "$(DIST_DIR)"
	@rm -f "$(RELEASE_ZIP)"
	@rm -rf "$(DIST_DIR)/TeamRecorderBar.app"
	@cp -r "$(MENU_BAR_APP)" "$(DIST_DIR)/"
	@find "$(DIST_DIR)/TeamRecorderBar.app" \( -name ".DS_Store" -o -name "*.pyc" \) -delete 2>/dev/null || true
	@find "$(DIST_DIR)/TeamRecorderBar.app" -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	@(cd "$(DIST_DIR)" && zip -qr "TeamRecorderBar-v$(VERSION).zip" "TeamRecorderBar.app" \
	    --exclude "*.DS_Store" --exclude "*__pycache__/*" --exclude "*.env")
	@rm -rf "$(DIST_DIR)/TeamRecorderBar.app"
	@echo "  ✓  $(RELEASE_ZIP)"
	@printf "     Size:   %s\n" "$$(du -sh '$(RELEASE_ZIP)' | cut -f1)"
	@printf "     SHA256: %s\n" "$$(shasum -a 256 '$(RELEASE_ZIP)' | awk '{print $$1}')"
	@echo ""
	@echo "  ▶  Next steps after smoke test passes:"
	@echo "     git tag v$(VERSION)"
	@echo "     git push && git push --tags"
	@echo "     gh release create v$(VERSION) '$(RELEASE_ZIP)' --title 'v$(VERSION)' --notes-file plan/release-notes-v$(VERSION).md"
