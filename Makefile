PYTHON      := python3
MENU_BAR_APP = menu-bar/.build/TeamRecorderBar.app
DIST_DIR     = dist

.PHONY: run test setup build-recorder doctor permissions stop index menu-bar menu-bar-install dist icon reset-setup uninstall clean-reinstall

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

menu-bar: icon
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
	@# Embed absolute watcher path so the app can find it after `make menu-bar-install`
	@echo "$$(pwd)/teams_recorder_v2.py" \
	       > "$(MENU_BAR_APP)/Contents/Resources/watcher_path.txt"
	@# Pin the Python interpreter setup.sh installed deps into. Launch Services strips
	@# /opt/homebrew/bin from PATH, so `env python3` resolves to system Python 3.9
	@# (no python-dotenv). Use absolute brew paths — make subshell PATH is not reliable.
	@BREW=""; \
	  [ -x /opt/homebrew/bin/brew ] && BREW=/opt/homebrew/bin/brew; \
	  [ -z "$$BREW" ] && [ -x /usr/local/bin/brew ] && BREW=/usr/local/bin/brew; \
	  PY=""; \
	  [ -n "$$BREW" ] && PY="$$($$BREW --prefix python 2>/dev/null)/bin/python3"; \
	  [ -x "$$PY" ] || PY="$$(command -v python3)"; \
	  echo "$$PY" > "$(MENU_BAR_APP)/Contents/Resources/python_path.txt"; \
	  echo "  ✓  pinned python: $$PY"
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
	@python3 scripts/make_icon.py

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
	@echo "    Privacy & Security → Automation         → icalBuddy → toggle off"
	@echo ""
	@echo "  To reinstall: make menu-bar-install"

clean-reinstall: uninstall menu-bar-install

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
