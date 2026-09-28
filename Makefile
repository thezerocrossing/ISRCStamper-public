APP_NAME = ISRC Stamper
DIST = dist
APP = $(DIST)/$(APP_NAME).app

ICON_SRC = Resources/ISRC Stamper icon.png
ICNS = $(DIST)/AppIcon.icns
ICONSET = $(DIST)/AppIcon.iconset

.PHONY: all test app run xcode icon clean FORCE

all: app

test:
	swift test

icon:
	@if [ ! -f "$(ICON_SRC)" ]; then echo "error: missing $(ICON_SRC)"; exit 1; fi
	@mkdir -p "$(ICONSET)"
	@for sz in 16 32 128 256 512; do \
		sips -z $$sz $$sz "$(ICON_SRC)" --out "$(ICONSET)/icon_$${sz}x$${sz}.png" >/dev/null; \
		dbl=$$((sz * 2)); \
		sips -z $$dbl $$dbl "$(ICON_SRC)" --out "$(ICONSET)/icon_$${sz}x$${sz}@2x.png" >/dev/null; \
	done
	iconutil -c icns "$(ICONSET)" -o "$(ICNS)"
	@rm -rf "$(ICONSET)"

$(APP): icon FORCE
	swift build -c release
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp .build/release/ISRCStamperApp "$(APP)/Contents/MacOS/$(APP_NAME)"
	cp .build/release/bwfctl "$(APP)/Contents/MacOS/bwfctl"
	cp Resources/Info.plist "$(APP)/Contents/Info.plist"
	cp "$(ICNS)" "$(APP)/Contents/Resources/AppIcon.icns"
	codesign --force --deep --sign - "$(APP)"

FORCE:

app: $(APP)
	@echo "Built $(APP)"

run: app
	open "$(APP)"

xcode:
	xed .

clean:
	swift package clean
	rm -rf "$(DIST)"
