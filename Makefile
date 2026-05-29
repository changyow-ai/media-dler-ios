# media-dler-ios — 常用開發指令
#
# repo 內沒有 .xcodeproj：它由 XcodeGen 依 project.yml 產生（已 .gitignore）。
# 需要 Xcode 的目標（project / open）只能在 macOS 上跑；test-core 在 Linux 上
# 用 Swift toolchain 亦可。執行 `make` 或 `make help` 看所有指令。

XCODEPROJ := MediaDler.xcodeproj

.DEFAULT_GOAL := help

.PHONY: help project open test-core clean

help: ## 顯示可用指令
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

project: ## 用 XcodeGen 從 project.yml 產生 MediaDler.xcodeproj（需 macOS）
	@command -v xcodegen >/dev/null 2>&1 \
		|| { echo "找不到 xcodegen，請先安裝：brew install xcodegen"; exit 1; }
	xcodegen generate

open: project ## 產生專案並用 Xcode 開啟（需 macOS + Xcode）
	open $(XCODEPROJ)

test-core: ## 跑 MediaDlerCore 純邏輯單元測試（不需 Xcode；Linux 亦可）
	cd MediaDlerCore && swift test

clean: ## 刪除產生的專案檔與建置產物
	rm -rf $(XCODEPROJ) .build DerivedData
