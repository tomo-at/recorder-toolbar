APP      = .build/RecorderToolbar.app
BINARY   = .build/debug/RecorderToolbar
PLIST    = Sources/RecorderToolbar/Info.plist
# ad-hoc 署名だと通知が "Notifications are not allowed" で拒否されるので
# Apple Development 証明書で署名する。未設定なら ad-hoc にフォールバック。
SIGN_ID ?= $(shell security find-identity -v -p codesigning 2>/dev/null | grep -m1 "Apple Development" | awk -F'"' '{print $$2}')
CODESIGN_ID = $(if $(SIGN_ID),$(SIGN_ID),-)

.PHONY: build run clean

build:
	swift build 2>&1 | grep -E "error:|Build complete"
	mkdir -p $(APP)/Contents/MacOS
	cp $(BINARY) $(APP)/Contents/MacOS/RecorderToolbar
	cp $(PLIST)  $(APP)/Contents/Info.plist
	# Info.plist を署名にバインド + Apple Development 証明書で署名
	codesign --force --deep --sign "$(CODESIGN_ID)" $(APP)

run: build
	pkill RecorderToolbar 2>/dev/null || true
	sleep 1
	open $(APP)

clean:
	rm -rf $(APP)
	swift package clean
