app_name := "Nab"
project := "Nab.xcodeproj"
scheme := "Nab"
host_arch := `uname -m`
destination := "platform=macOS,arch=" + host_arch
debug_app_path := "build/Build/Products/Debug/Nab.app"
release_app_path := "build/Build/Products/Release/Nab.app"

run-debug: build-debug
    open {{ debug_app_path }}

build-debug:
    xcodebuild -quiet -project {{ project }} -scheme {{ scheme }} -destination "{{ destination }}" -configuration Debug -derivedDataPath build build

build-release:
    xcodebuild -quiet -project {{ project }} -scheme {{ scheme }} -destination "{{ destination }}" -configuration Release -derivedDataPath build build

test:
    xcodebuild -quiet -project {{ project }} -scheme {{ scheme }} -destination "{{ destination }}" -configuration Debug -derivedDataPath build test

audit:
    xcodebuild -quiet -project {{ project }} -scheme {{ scheme }} -destination "{{ destination }}" -configuration Debug -derivedDataPath build analyze

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
    xcodebuild -quiet -project {{ project }} -scheme {{ scheme }} -destination "{{ destination }}" -configuration Debug clean
    xcodebuild -quiet -project {{ project }} -scheme {{ scheme }} -destination "{{ destination }}" -configuration Release -derivedDataPath build clean
