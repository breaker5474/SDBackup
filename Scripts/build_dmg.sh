#!/bin/bash
set -e

# SDBackupApp DMG Packaging Script
# Version — update this when AppEnvironment.appVersion changes in Sources/Language.swift
VERSION="1.0.0"
APP_NAME="SDBackup"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
BUILD_DIR="build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
DMG_TEMP_DIR="${BUILD_DIR}/dmg_temp"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_DIR}"

echo "=== SDBackupApp DMG Builder ==="
echo "Version: ${VERSION}"
echo "Project: ${PROJECT_DIR}"
echo ""

# Clean previous build
echo "Cleaning previous build artifacts..."
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

# Build release binary
echo "Building release binary..."
swift build -c release

# Get the binary path (SPM target name is always SDBackupApp)
BINARY_PATH=".build/release/SDBackupApp"

if [ ! -f "${BINARY_PATH}" ]; then
    echo "Error: Binary not found at ${BINARY_PATH}"
    exit 1
fi
echo "Binary built successfully: ${BINARY_PATH}"

# Create .app bundle structure
echo "Creating .app bundle..."
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Copy binary (keep executable name as SDBackupApp, bundle display name is SDBackup)
cp "${BINARY_PATH}" "${APP_BUNDLE}/Contents/MacOS/SDBackupApp"
chmod +x "${APP_BUNDLE}/Contents/MacOS/SDBackupApp"

# Create .icns from user's AppIcons
ICONS_SRC="AppIcons/Assets.xcassets/AppIcon.appiconset"
ICONSET_DIR="${BUILD_DIR}/AppIcon.iconset"
mkdir -p "${ICONSET_DIR}"

cp "${ICONS_SRC}/16.png"  "${ICONSET_DIR}/icon_16x16.png"
cp "${ICONS_SRC}/32.png"  "${ICONSET_DIR}/icon_16x16@2x.png"
cp "${ICONS_SRC}/32.png"  "${ICONSET_DIR}/icon_32x32.png"
cp "${ICONS_SRC}/64.png"  "${ICONSET_DIR}/icon_32x32@2x.png"
cp "${ICONS_SRC}/128.png" "${ICONSET_DIR}/icon_128x128.png"
cp "${ICONS_SRC}/256.png" "${ICONSET_DIR}/icon_128x128@2x.png"
cp "${ICONS_SRC}/256.png" "${ICONSET_DIR}/icon_256x256.png"
cp "${ICONS_SRC}/512.png" "${ICONSET_DIR}/icon_256x256@2x.png"
cp "${ICONS_SRC}/512.png" "${ICONSET_DIR}/icon_512x512.png"
cp "${ICONS_SRC}/1024.png" "${ICONSET_DIR}/icon_512x512@2x.png"

iconutil -c icns "${ICONSET_DIR}" -o "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
rm -rf "${ICONSET_DIR}"
echo "Icon created."

# Create Info.plist
cat > "${APP_BUNDLE}/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>SDBackupApp</string>
    <key>CFBundleIdentifier</key>
    <string>com.nayan.sdbackup</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>SDBackup</string>
    <key>CFBundleDisplayName</key>
    <string>SDBackup</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

echo "App bundle created at: ${APP_BUNDLE}"

# Create DMG with volume icon
echo "Creating DMG..."

# Step 1: Create a temporary read-write DMG
TEMP_DMG="${BUILD_DIR}/temp_rw.dmg"
DMG_SIZE=10  # MB, enough for the app
hdiutil create -volname "SDBackup" \
    -size ${DMG_SIZE}m \
    -fs HFS+ \
    -type SPARSE \
    "${TEMP_DMG%.dmg}" >/dev/null 2>&1

# Mount it
MOUNT_DIR="/Volumes/SDBackup"
hdiutil attach "${TEMP_DMG%.dmg}.sparseimage" -readwrite -noverify -noautoopen -nobrowse -quiet

if [ -d "${MOUNT_DIR}" ]; then
    # Copy app and Applications symlink
    cp -R "${APP_BUNDLE}" "${MOUNT_DIR}/"
    ln -s /Applications "${MOUNT_DIR}/Applications"
    
    # Set volume icon
    ICNS_PATH="${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
    if [ -f "${ICNS_PATH}" ]; then
        cp "${ICNS_PATH}" "${MOUNT_DIR}/.VolumeIcon.icns"
        SetFile -c icnC "${MOUNT_DIR}/.VolumeIcon.icns" 2>/dev/null || true
        SetFile -a C "${MOUNT_DIR}" 2>/dev/null || true
        echo "Volume icon set."
    fi
    
    # Unmount
    hdiutil detach "${MOUNT_DIR}" -quiet
    
    # Convert to compressed read-only DMG
    if ! hdiutil convert "${TEMP_DMG%.dmg}.sparseimage" \
        -format UDZO -ov \
        -o "${BUILD_DIR}/${DMG_NAME}" >/dev/null 2>&1; then
        echo "Warning: hdiutil convert failed, using simple create"
        hdiutil create -volname "SDBackup" \
            -srcfolder "${MOUNT_DIR}" \
            -ov -format UDZO \
            "${BUILD_DIR}/${DMG_NAME}"
    fi
    
    rm -f "${TEMP_DMG%.dmg}.sparseimage"
else
    echo "Warning: Could not mount temp DMG, falling back to simple create"
    hdiutil create -volname "SDBackup" \
        -srcfolder "${DMG_TEMP_DIR}" \
        -ov -format UDZO \
        "${BUILD_DIR}/${DMG_NAME}"
fi

# Clean up temp files
rm -rf "${DMG_TEMP_DIR}"

echo ""
echo "=== Done! ==="
echo "DMG created at: ${BUILD_DIR}/${DMG_NAME}"
echo "Size: $(du -h "${BUILD_DIR}/${DMG_NAME}" | cut -f1)"
