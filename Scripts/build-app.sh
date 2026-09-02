#!/bin/sh

set -eu

configuration="${1:?usage: Scripts/build-app.sh debug|release}"

case "$configuration" in
    debug | release) ;;
    *)
        echo "configuration must be debug or release" >&2
        exit 2
        ;;
esac

script_directory="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
project_directory="$(dirname -- "$script_directory")"
app_path="$project_directory/build/$configuration/Nab.app"
contents_path="$app_path/Contents"

cd "$project_directory"
swift build --configuration "$configuration" --product Nab
binary_path="$(swift build --configuration "$configuration" --show-bin-path)/Nab"

/usr/bin/install -d "$contents_path/MacOS" "$contents_path/Resources"
/usr/bin/install -m 755 "$binary_path" "$contents_path/MacOS/Nab"
/usr/bin/install -m 644 Resources/Info.plist "$contents_path/Info.plist"
/usr/bin/iconutil --convert icns --output "$contents_path/Resources/AppIcon.icns" Resources/AppIcon.iconset
/usr/bin/xcrun dsymutil "$binary_path" -o "$app_path.dSYM"
if [ "$configuration" = "debug" ]; then
    /usr/bin/codesign --force --sign - --options runtime --timestamp=none \
        --entitlements Resources/NabDebug.entitlements "$app_path"
else
    /usr/bin/codesign --force --sign - --options runtime --timestamp=none "$app_path"
fi
