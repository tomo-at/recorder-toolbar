APP      = .build/RecorderToolbar.app
BINARY   = .build/debug/RecorderToolbar
PLIST    = Sources/RecorderToolbar/Info.plist
ASSETS   = Sources/RecorderToolbar/assets
# ad-hoc 署名だと通知が "Notifications are not allowed" で拒否されるので
# Apple Development 証明書で署名する。未設定なら ad-hoc にフォールバック。
SIGN_ID ?= $(shell security find-identity -v -p codesigning 2>/dev/null | grep -m1 "Apple Development" | awk -F'"' '{print $$2}')
CODESIGN_ID = $(if $(SIGN_ID),$(SIGN_ID),-)

.PHONY: build run clean doctor

build:
	swift build 2>&1 | grep -E "error:|Build complete"
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(BINARY) $(APP)/Contents/MacOS/RecorderToolbar
	cp $(PLIST)  $(APP)/Contents/Info.plist
	# 標準の Resources/ にアセットを配置（Bundle.main から参照）
	cp $(ASSETS)/icon-menu.png $(APP)/Contents/Resources/
	# Info.plist を署名にバインド + Apple Development 証明書で署名
	codesign --force --deep --sign "$(CODESIGN_ID)" $(APP)

run: build
	pkill RecorderToolbar 2>/dev/null || true
	sleep 1
	open $(APP)

clean:
	rm -rf $(APP)
	swift package clean

# 通知が出ないとき等に1コマンドで全failure modeを診断。
# build 済みの .app を前提に静的にチェックする（実行は不要）。
doctor: build
	@echo ""
	@echo "▶ 1. .app バンドル構造"
	@test -f $(APP)/Contents/Info.plist                     && echo "  ✅ Contents/Info.plist"                     || echo "  ❌ Contents/Info.plist が無い"
	@test -f $(APP)/Contents/MacOS/RecorderToolbar          && echo "  ✅ Contents/MacOS/RecorderToolbar"          || echo "  ❌ Contents/MacOS/RecorderToolbar が無い"
	@test -f $(APP)/Contents/Resources/icon-menu.png        && echo "  ✅ Contents/Resources/icon-menu.png"        || echo "  ❌ Contents/Resources/icon-menu.png が無い（メニューバーアイコンが欠落）"
	@echo ""
	@echo "▶ 2. コード署名"
	@codesign -d --verbose=2 $(APP) 2>&1 | grep -E "^(Identifier|Authority|TeamIdentifier|Signature)" | sed 's/^/  /' || echo "  ❌ 署名情報が取得できない"
	@codesign -d --verbose=2 $(APP) 2>&1 | grep -q "Apple Development" \
	  && echo "  ✅ Apple Development 証明書で署名済み" \
	  || echo "  ❌ Apple Development 証明書で署名されていない（ad-hoc だと通知が拒否される）"
	@echo ""
	@echo "▶ 3. Info.plist の必須キー"
	@/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier"        $(APP)/Contents/Info.plist 2>/dev/null | sed 's/^/  CFBundleIdentifier: /'        || echo "  ❌ CFBundleIdentifier 未設定"
	@/usr/libexec/PlistBuddy -c "Print :NSCameraUsageDescription"     $(APP)/Contents/Info.plist >/dev/null 2>&1 && echo "  ✅ NSCameraUsageDescription"     || echo "  ❌ NSCameraUsageDescription 未設定（TCC クラッシュの原因）"
	@/usr/libexec/PlistBuddy -c "Print :NSMicrophoneUsageDescription" $(APP)/Contents/Info.plist >/dev/null 2>&1 && echo "  ✅ NSMicrophoneUsageDescription" || echo "  ❌ NSMicrophoneUsageDescription 未設定（TCC クラッシュの原因）"
	@echo ""
	@echo "▶ 4. macOS 通知システムへの登録状態"
	@BID=$$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" $(APP)/Contents/Info.plist 2>/dev/null); \
	  echo "  bundle ID: $$BID"; \
	  if plutil -p ~/Library/Preferences/com.apple.ncprefs.plist 2>/dev/null | grep -q "\"$$BID\""; then \
	    echo "  ✅ ncprefs.plist に登録あり（許可ダイアログ応答済み）"; \
	    echo "     → System Settings > Notifications > Recorder Toolbar で許可状態を確認"; \
	  else \
	    echo "  ❌ ncprefs.plist に未登録"; \
	    echo "     原因候補: (a) 一度も起動していない (b) 起動したがプロンプトを閉じた"; \
	    echo "             (c) ad-hoc 署名で過去に拒否されキャッシュが残っている"; \
	    echo "     対処: Info.plist の CFBundleIdentifier を bump（例: .v3 → .v4）して make run"; \
	  fi
	@echo ""
	@echo "▶ 5. 現在動作中プロセスのバンドル整合性"
	@PIDS=$$(pgrep -f RecorderToolbar 2>/dev/null); \
	  if [ -z "$$PIDS" ]; then \
	    echo "  ℹ プロセスは未起動（make run で起動）"; \
	  else \
	    for pid in $$PIDS; do \
	      RUN_PATH=$$(ps -p $$pid -o comm= 2>/dev/null); \
	      echo "  pid=$$pid path=$$RUN_PATH"; \
	      case "$$RUN_PATH" in \
	        *.app/Contents/MacOS/*) echo "  ✅ .app バンドルから起動（通知 OK）" ;; \
	        *DerivedData*)          echo "  ❌ Xcode DerivedData の裸バイナリで起動中。Bundle.main.bundleIdentifier=nil のため通知は無効。" ; \
	                                echo "     対処: pkill RecorderToolbar && make run" ;; \
	        *.build/debug/*)        echo "  ❌ swift build の裸バイナリで起動中。通知は無効。" ; \
	                                echo "     対処: pkill RecorderToolbar && make run" ;; \
	        *)                      echo "  ⚠ 想定外のパス。.app バンドル経由で起動推奨" ;; \
	      esac; \
	    done; \
	  fi
	@echo ""
	@echo "▶ 6. ランタイムログの見方"
	@echo "  log show --predicate 'process == \"RecorderToolbar\"' --last 60s --info | grep '\\[Notification\\]'"
	@echo "  または Console.app で process=RecorderToolbar をフィルタ"
	@echo ""
