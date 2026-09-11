APP_NAME  = PhemeMurmur
BUILD_DIR = .build/release
APP_BUNDLE = $(APP_NAME).app
CONTENTS  = $(APP_BUNDLE)/Contents
MACOS     = $(CONTENTS)/MacOS
CERT_NAME = PhemeMurmurDev
DIST_DIR  = dist
ARCH      = $(shell uname -m)
ZIP_NAME  = $(APP_NAME)-macOS-$(ARCH).zip

.PHONY: build app run clean icon install release

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
	DATE=$$(git log -1 --format=%cd --date=format:'%Y%m%d' 2>/dev/null); \
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
	@TAG=$$(git describe --tags --abbrev=0 2>/dev/null); \
	if [ -n "$$TAG" ]; then \
		VER=$${TAG#v}; \
		/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $$VER" $(CONTENTS)/Info.plist; \
		echo "Injected CFBundleShortVersionString=$$VER"; \
	else \
		echo "No git tag found; leaving CFBundleShortVersionString as-is"; \
	fi
	cp Resources/AppIcon.icns $(CONTENTS)/Resources/AppIcon.icns
	@# The in-app updater runs this exact script, so the app ships the copy it
	@# was built with rather than fetching one at update time. Single source of
	@# truth: install.sh in the repo root.
	cp install.sh $(CONTENTS)/Resources/install.sh
	mkdir -p $(CONTENTS)/Resources/Fonts
	cp Resources/Fonts/*.ttf $(CONTENTS)/Resources/Fonts/
	cp Resources/Fonts/OFL-*.txt $(CONTENTS)/Resources/Fonts/
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
	rm -rf $(DIST_DIR)
	mkdir -p $(DIST_DIR)
	ditto -c -k --sequesterRsrc --keepParent $(APP_BUNDLE) $(DIST_DIR)/$(ZIP_NAME)
	@echo "Created $(DIST_DIR)/$(ZIP_NAME)"
	rm -rf $(APP_BUNDLE)
	@# Reinstalling keeps whatever onboarding state you already had. Pass
	@# ONBOARD=1 to replay the boot sequence, e.g. `make install ONBOARD=1`.
	@if [ -n "$(ONBOARD)" ]; then \
		rm -f ~/.config/pheme-murmur/.onboarding-done; \
		echo "Reset onboarding; the boot sequence will run again"; \
	fi
	open /Applications/$(APP_BUNDLE)

clean:
	rm -rf .build $(APP_BUNDLE) $(DIST_DIR)

# Half-automated release: tag first, so `git describe` in `app` embeds the
# about-to-publish version, then build, zip, publish and upload.
#
# Usage: make release VERSION=vX.Y.Z
#
# gh targets PureFuncInc/PhemeMurmur with the echoulen token, because the
# machine's active gh account cannot resolve that repo.
release:
	@if [ -z "$(VERSION)" ]; then echo "Usage: make release VERSION=vX.Y.Z"; exit 1; fi
	@# Retrying after a partial failure? A local tag from the prior run lingers.
	@if git rev-parse --verify --quiet "refs/tags/$(VERSION)" >/dev/null; then \
		echo "Tag $(VERSION) already exists locally. If retrying a failed release, first run: git tag -d $(VERSION)"; \
		exit 1; \
	fi
	swift test
	git tag $(VERSION)
	$(MAKE) app
	rm -rf $(DIST_DIR)
	mkdir -p $(DIST_DIR)
	ditto -c -k --sequesterRsrc --keepParent $(APP_BUNDLE) $(DIST_DIR)/$(ZIP_NAME)
	rm -rf $(APP_BUNDLE)
	git push origin $(VERSION)
	@export GH_TOKEN=$$(gh auth token --user echoulen); \
	gh release create $(VERSION) --repo PureFuncInc/PhemeMurmur --title "$(VERSION)" \
		--generate-notes --target "$$(git rev-parse HEAD)"; \
	BODY=$$(gh release view $(VERSION) --repo PureFuncInc/PhemeMurmur --json body -q .body); \
	{ printf '## 安裝\n\n```\ncurl -fsSL https://raw.githubusercontent.com/PureFuncInc/PhemeMurmur/main/install.sh | bash\n```\n\n已安裝的使用者可以直接從選單列的「檢查更新…」更新。\n\n---\n\n'; \
	  printf '%s\n' "$$BODY"; } > $(DIST_DIR)/release-notes.md; \
	gh release edit $(VERSION) --repo PureFuncInc/PhemeMurmur --notes-file $(DIST_DIR)/release-notes.md; \
	gh release upload $(VERSION) --repo PureFuncInc/PhemeMurmur $(DIST_DIR)/$(ZIP_NAME) --clobber
	@echo "Released $(VERSION)"
