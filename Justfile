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
    mkdir -p "$HOME/Applications"
    rsync --archive --delete --extended-attributes "{{ release_app_path }}/" "$HOME/Applications/Nab.app/"

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
