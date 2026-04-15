APP_NAME  = PhemeMurmur
BUILD_DIR = .build/release
APP_BUNDLE = $(APP_NAME).app
CONTENTS  = $(APP_BUNDLE)/Contents
MACOS     = $(CONTENTS)/MacOS
CERT_NAME = PhemeMurmurDev

.PHONY: build app run clean icon install

build:
	swift build -c release

icon:
	swift scripts/generate_icon.swift

app: build
	rm -rf $(APP_BUNDLE)
	mkdir -p $(MACOS)
	mkdir -p $(CONTENTS)/Resources
	cp $(BUILD_DIR)/$(APP_NAME) $(MACOS)/$(APP_NAME)
	cp Resources/Info.plist $(CONTENTS)/Info.plist
	@HASH=$$(git rev-parse --short=7 HEAD 2>/dev/null); \
	if [ -n "$$HASH" ]; then \
		/usr/libexec/PlistBuddy -c "Delete :GitCommitHash" $(CONTENTS)/Info.plist >/dev/null 2>&1 || true; \
		/usr/libexec/PlistBuddy -c "Add :GitCommitHash string $$HASH" $(CONTENTS)/Info.plist; \
		echo "Injected GitCommitHash=$$HASH"; \
	fi; \
	DATE=$$(git log -1 --format=%cd --date=format:'%y%m%d' 2>/dev/null); \
	if [ -n "$$DATE" ]; then \
		/usr/libexec/PlistBuddy -c "Delete :GitCommitDate" $(CONTENTS)/Info.plist >/dev/null 2>&1 || true; \
		/usr/libexec/PlistBuddy -c "Add :GitCommitDate string $$DATE" $(CONTENTS)/Info.plist; \
		echo "Injected GitCommitDate=$$DATE"; \
	fi; \
	COUNT=$$(git rev-list --count HEAD 2>/dev/null); \
	if [ -n "$$COUNT" ]; then \
		/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $$COUNT" $(CONTENTS)/Info.plist; \
		echo "Injected CFBundleVersion=$$COUNT"; \
	fi
	cp Resources/AppIcon.icns $(CONTENTS)/Resources/AppIcon.icns
	@bash scripts/ensure_signing_cert.sh "$(CERT_NAME)" || true
	@if security find-certificate -c "$(CERT_NAME)" ~/Library/Keychains/login.keychain-db >/dev/null 2>&1; then \
		codesign --force --deep --sign "$(CERT_NAME)" $(APP_BUNDLE); \
	else \
		echo "⚠ Using ad-hoc signing (TCC permissions may not persist after rebuilds)"; \
		codesign --force --deep --sign - $(APP_BUNDLE); \
	fi

run: app
	open $(APP_BUNDLE)

install: app
	pkill -x $(APP_NAME) 2>/dev/null || true
	rm -rf /Applications/$(APP_BUNDLE)
	cp -r $(APP_BUNDLE) /Applications/$(APP_BUNDLE)
	rm -rf $(APP_BUNDLE)
	rm -f ~/.config/pheme-murmur/.onboarding-done
	open /Applications/$(APP_BUNDLE)

clean:
	rm -rf .build $(APP_BUNDLE)

