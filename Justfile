app_name := "Nab"
project := "Nab.xcodeproj"
scheme := "Nab"
debug_app_path := "build/Build/Products/Debug/Nab.app"
release_app_path := "build/Build/Products/Release/Nab.app"

run-debug: build-debug
    open {{ debug_app_path }}

build-debug:
    xcodebuild -project {{ project }} -scheme {{ scheme }} -configuration Debug -derivedDataPath build build

build-release:
    xcodebuild -project {{ project }} -scheme {{ scheme }} -configuration Release -derivedDataPath build build

test:
    xcodebuild -project {{ project }} -scheme {{ scheme }} -configuration Debug -derivedDataPath build test

audit:
    xcodebuild -project {{ project }} -scheme {{ scheme }} -configuration Debug -derivedDataPath build analyze

verify: lint audit test build-debug

run-release: build-release
    open {{ release_app_path }}

install: build-release
    #!/usr/bin/env bash
    set -euo pipefail
    app_path="$PWD/{{ release_app_path }}"
    osascript \
      -e 'set sourceApp to POSIX file "'"$app_path"'"' \
      -e 'do shell script "/bin/rm -rf /Applications/{{ app_name }}.app && /usr/bin/ditto " & quoted form of POSIX path of sourceApp & " /Applications/{{ app_name }}.app" with administrator privileges'

icon:
    xcrun swift Scripts/generate-app-icon.swift

fmt:
    xcrun swift-format format -i -r Nab/ NabTests/

lint:
    xcrun swift-format lint -r Nab/ NabTests/

clean:
    trash build
    xcodebuild -project {{ project }} -scheme {{ scheme }} -configuration Debug clean
    xcodebuild -project {{ project }} -scheme {{ scheme }} -configuration Release -derivedDataPath build clean
