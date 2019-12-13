#!/bin/sh
USER_NAME=keisuke.miyako@4d.com
UUID=`uuidgen | tr -d - | tr -d '\n' | tr '[:upper:]' '[:lower:]'`
DEVELOPER_ID=`security find-identity -p codesigning -v | egrep 'Developer ID Application[^"]+' -o`
PRODUCT_PATH="$CODESIGNING_FOLDER_PATH"
xattr -cr "$PRODUCT_PATH"
codesign --remove-signature "$PRODUCT_PATH"
codesign --verbose --deep --timestamp --force --sign "$DEVELOPER_ID" "$PRODUCT_PATH"
DMG_PATH="$PROJECT_DIR/$PRODUCT_NAME.dmg"
ZIP_PATH="$PROJECT_DIR/$PRODUCT_NAME.zip"
rm "$DMG_PATH"
hdiutil create -format UDBZ -plist -srcfolder "$PRODUCT_PATH" "$DMG_PATH"
echo "xcrun stapler staple \"$PRODUCT_PATH\""
echo "hdiutil create -format UDBZ -plist -srcfolder  \"$PRODUCT_PATH\" \"$DMG_PATH\" "
echo "ditto -c -k --keepParent \"$PRODUCT_PATH\" \"$ZIP_PATH\" "
xcrun altool --notarize-app --file "$DMG_PATH" --username "$USER_NAME" --password "@keychain:altool" --primary-bundle-id $PRODUCT_BUNDLE_IDENTIFIER.$UUID
rm -f "$ZIP_PATH"
rm -f "$DMG_PATH"

