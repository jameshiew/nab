app_name := "Nab"
bundle_id := `/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' Sources/Nab/Resources/Info.plist`
debug_app_path := "build/debug/Nab.app"
release_app_path := "build/release/Nab.app"
test_results := "build/test-results.xml"

default: verify

run-debug: build-debug quit
    open {{ debug_app_path }}

run-debug-attached: build-debug quit
    "{{ debug_app_path }}/Contents/MacOS/Nab"

build-debug:
    swift scripts/bundle-app.swift debug

build-release:
    swift scripts/bundle-app.swift release

test:
    #!/bin/sh
    set -u
    rm -f "{{ test_results }}"
    mkdir -p "$(dirname "{{ test_results }}")"
    if swift test --parallel --disable-swift-testing --xunit-output "{{ test_results }}"; then
        status=0
    else
        status=$?
    fi
    swift scripts/summarize-tests.swift "{{ test_results }}" || exit 1
    exit "$status"

test-tsan:
    swift test --sanitize=thread

test-asan:
    swift test --sanitize=address

quit:
    if pgrep -xq {{ app_name }}; then osascript -e 'tell application id "{{ bundle_id }}" to quit'; fi
    for _ in $(seq 1 50); do pgrep -xq {{ app_name }} || break; sleep 0.1; done

collect-diagnostics:
    swift scripts/collect-diagnostics.swift

verify: lint test build-debug
    @echo "verify passed: lint, test, build-debug"

run: build-debug quit
    open {{ debug_app_path }}

run-release: build-release quit
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
