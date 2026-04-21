app_name := "Nab"
project := "Nab.xcodeproj"
scheme := "Nab"
release_app_path := "build/Build/Products/Release/Nab.app"

run-debug: build-debug
    open ~/Library/Developer/Xcode/DerivedData/Nab-*/Build/Products/Debug/Nab.app

build-debug:
    xcodebuild -project {{ project }} -scheme {{ scheme }} -configuration Debug build

build-release:
    xcodebuild -project {{ project }} -scheme {{ scheme }} -configuration Release -derivedDataPath build build

run-release: build-release
    open {{ release_app_path }}

install: build-release
    #!/usr/bin/env bash
    set -euo pipefail
    app_path="$PWD/{{ release_app_path }}"
    osascript \
      -e 'set sourceApp to POSIX file "'"$app_path"'"' \
      -e 'do shell script "/bin/rm -rf /Applications/{{ app_name }}.app && /usr/bin/ditto " & quoted form of POSIX path of sourceApp & " /Applications/{{ app_name }}.app" with administrator privileges'

fmt:
    xcrun swift-format format -i -r Nab/

lint:
    xcrun swift-format lint -r Nab/

clean:
    trash build
    xcodebuild -project {{ project }} -scheme {{ scheme }} -configuration Debug clean
    xcodebuild -project {{ project }} -scheme {{ scheme }} -configuration Release -derivedDataPath build clean
