app_name := "Nab"
debug_app_path := "build/debug/Nab.app"
release_app_path := "build/release/Nab.app"

run-debug: build-debug
    open {{ debug_app_path }}

build-debug:
    Scripts/build-app.sh debug

build-release:
    Scripts/build-app.sh release

test:
    swift test --parallel

verify: lint test build-debug

run:
    open {{ debug_app_path }}

run-release: build-release
    open {{ release_app_path }}

install: build-release
    mkdir -p "$HOME/Applications"
    rsync --archive --delete --extended-attributes "{{ release_app_path }}/" "$HOME/Applications/{{ app_name }}.app/"

icon:
    swift Scripts/generate-app-icon.swift

fmt:
    swift format --in-place --recursive Package.swift Nab/ NabTests/ Scripts/

lint:
    swift format lint --strict --recursive Package.swift Nab/ NabTests/ Scripts/

clean:
    swift package clean
    if test -d build; then trash build; fi
