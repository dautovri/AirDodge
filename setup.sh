#!/bin/bash
set -e

echo "🎮 AirDodge – project setup"
echo "----------------------------"

# Install xcodegen if needed
if ! command -v xcodegen &>/dev/null; then
    echo "Installing xcodegen..."
    brew install xcodegen
fi

# Generate .xcodeproj from project.yml
xcodegen generate

echo ""
echo "✅ Done! Opening in Xcode..."
open AirpodsGame.xcodeproj
