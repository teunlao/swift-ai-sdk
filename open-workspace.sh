#!/bin/bash
swift package generate-xcodeproj

open swift-ai-sdk.xcodeproj

echo "✅ Открыт Xcode проект"
echo "Для примеров откройте: cd examples && open Package.swift"
