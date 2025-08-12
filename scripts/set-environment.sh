#!/bin/bash

# Script to set environment based on git branch
# This script should be run as a build phase in Xcode

# Get the current branch name
BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD)

# Set environment based on branch
if [[ "$BRANCH_NAME" == "develop" || "$BRANCH_NAME" == "upgrade" ]]; then
    echo "Setting environment to PRODUCTION for branch: $BRANCH_NAME"
    ENVIRONMENT="production"
    BUNDLE_ID="com.bittr.bittr"
    APP_NAME="bittr"
else
    echo "Setting environment to DEVELOPMENT for branch: $BRANCH_NAME"
    ENVIRONMENT="development"
    BUNDLE_ID="com.bittr.bittrRegtest"
    APP_NAME="bittrRegtest"
fi

# Use SRCROOT if available (Xcode build), otherwise use current directory
TARGET_DIR="${SRCROOT:-$(pwd)}/bittr"

# Create a simple environment file that can be read at runtime
echo "$ENVIRONMENT" > "$TARGET_DIR/environment.txt"

# Modify the Info.plist file directly
INFO_PLIST="$TARGET_DIR/Info.plist"

if [ -f "$INFO_PLIST" ]; then
    # Use PlistBuddy to modify the Info.plist
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$INFO_PLIST" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $APP_NAME" "$INFO_PLIST" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" "$INFO_PLIST" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Set :ENVIRONMENT $ENVIRONMENT" "$INFO_PLIST" 2>/dev/null || true
    
    echo "Modified Info.plist with new bundle ID and app name"
else
    echo "Warning: Info.plist not found at $INFO_PLIST"
fi

echo "Environment set to: $ENVIRONMENT"
echo "Bundle ID set to: $BUNDLE_ID"
echo "App name set to: $APP_NAME"
