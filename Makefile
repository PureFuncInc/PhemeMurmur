APP_NAME = PhemeMurmur
BUILD_DIR = .build/release
APP_BUNDLE = $(APP_NAME).app
CONTENTS = $(APP_BUNDLE)/Contents
MACOS = $(CONTENTS)/MacOS

.PHONY: build app run clean icon

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
	cp Resources/AppIcon.icns $(CONTENTS)/Resources/AppIcon.icns

run: app
	open $(APP_BUNDLE)

clean:
	swift package clean
	rm -rf $(APP_BUNDLE)
