#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_DIR="$PROJECT_ROOT/ios"
PROJECT="$IOS_DIR/TodoNative.xcodeproj"
SCHEME="TodoNative"

DEST_NAME="${1:-iPhone 17 Pro}"
DEST_OS="${2:-26.5}"
ACTION="${3:-run}"
SIM_UDID="${4:-}"

if [ ! -d "$PROJECT" ]; then
  echo "未找到 $PROJECT，请先执行 xcodegen generate 生成工程。"
  exit 1
fi

BUILD_DIR="$HOME/Library/Developer/Xcode/DerivedData/TodoNative-Preview"
DESTINATION="platform=iOS Simulator,name=$DEST_NAME,OS=$DEST_OS"
APP_PATH="$BUILD_DIR/Build/Products/Debug-iphonesimulator/TodoNative.app"

cd "$IOS_DIR"

detect_udid() {
  if [ -z "${SIM_UDID:-}" ]; then
    if ! command -v jq >/dev/null; then
      return 1
    fi

    local runtime
    runtime="com.apple.CoreSimulator.SimRuntime.iOS-$(echo "$DEST_OS" | sed 's/\./-/')"
    SIM_UDID="$(xcrun simctl list devices --json | jq -r --arg runtime "$runtime" --arg name "$DEST_NAME" '.devices[$runtime][]? | select(.isAvailable == true and .name == $name) | .udid' | head -n 1)"
  fi

  if [ -z "$SIM_UDID" ]; then
    return 1
  fi

  echo "$SIM_UDID"
}

run_with_simctl() {
  echo "开始编译（build）"
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -destination "$DESTINATION" -derivedDataPath "$BUILD_DIR" build

  local udid
  if ! udid=$(detect_udid); then
    echo "无法根据 '$DEST_NAME' + '$DEST_OS' 自动定位可用模拟器，建议改用第四个参数直接传 udid，或继续使用 run 模式。"
    exit 1
  fi

  echo "目标模拟器 UDID: $udid"
  open -a Simulator >/dev/null 2>&1 || true
  xcrun simctl boot "$udid" || true
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl install "$udid" "$APP_PATH"
  xcrun simctl launch "$udid" com.zhili.todo-native
}

echo "目标设备：$DESTINATION"
if [ "$ACTION" = "run-simctl" ]; then
  run_with_simctl
  exit 0
fi

echo "执行：xcodebuild $ACTION（如果目标不可用会自动回退到 generic）"
if ! xcodebuild -project "$PROJECT" -scheme "$SCHEME" -destination "$DESTINATION" -showBuildSettings >/tmp/xcbuild_settings 2>&1; then
  echo "⚠️ 目标不可用，自动回退到 generic 模拟器"
  DESTINATION="generic/platform=iOS Simulator"
fi

if [ "$ACTION" = "run" ]; then
  set -x
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -destination "$DESTINATION" -derivedDataPath "$BUILD_DIR" run
  set +x
else
  set -x
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -destination "$DESTINATION" -derivedDataPath "$BUILD_DIR" build
  set +x
fi
