app_name := "Nab"
debug_app_path := "build/debug/Nab.app"
release_app_path := "build/release/Nab.app"

default: verify

run-debug: build-debug
    open {{ debug_app_path }}

run-debug-attached: build-debug
    "{{ debug_app_path }}/Contents/MacOS/Nab"

build-debug:
    swift scripts/bundle-app.swift debug

build-release:
    swift scripts/bundle-app.swift release

test:
    swift test --parallel

test-tsan:
    swift test --sanitize=thread

test-asan:
    swift test --sanitize=address

collect-diagnostics:
    scripts/collect-diagnostics.sh

verify: lint test build-debug

run: build-debug
    open {{ debug_app_path }}

run-release: build-release
    open {{ release_app_path }}

install: build-release
    mkdir -p "$HOME/Applications"
    rsync --archive --delete --extended-attributes "{{ release_app_path }}/" "$HOME/Applications/{{ app_name }}.app/"

icon:
    swift scripts/generate-app-icon.swift

fmt:
    swift format --in-place --recursive Package.swift Sources/ Tests/ scripts/

lint:
    swift format lint --strict --recursive Package.swift Sources/ Tests/ scripts/

clean:
    swift package clean
    if test -d build; then trash build; fi
