#!/usr/bin/env bash
# 降级 Xcode 工程格式到 56，兼容 macos-14 runner 的 Xcode 15.4
sed -i '' -E 's/objectVersion = [0-9]+;/objectVersion = 56;/g' Weiliao.xcodeproj/project.pbxproj
sed -i '' -E '/preferredProjectObjectVersion = [0-9]+;/d' Weiliao.xcodeproj/project.pbxproj
sed -i '' -E 's/compatibilityVersion = "Xcode [0-9.]+";/compatibilityVersion = "Xcode 14.0";/g' Weiliao.xcodeproj/project.pbxproj
