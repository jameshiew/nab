app_name := "Nab"
bundle_id := `/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' Sources/Nab/Resources/Info.plist`
debug_app_path := "build/debug/Nab.app"
release_app_path := "build/release/Nab.app"
test_results := "build/test-results.xml"
script := "swift run --quiet --package-path scripts"

default: verify

run-debug: build-debug quit
    open {{ debug_app_path }}

run-debug-attached: build-debug quit
    "{{ debug_app_path }}/Contents/MacOS/Nab"

build-debug:
    {{ script }} bundle-app debug

build-release:
    {{ script }} bundle-app release

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
    {{ script }} summarize-tests "{{ test_results }}" || exit 1
    exit "$status"

test-tsan:
    swift test --sanitize=thread

test-asan:
    swift test --sanitize=address

quit:
    if pgrep -xq {{ app_name }}; then osascript -e 'tell application id "{{ bundle_id }}" to quit'; fi
    for _ in $(seq 1 50); do pgrep -xq {{ app_name }} || break; sleep 0.1; done

collect-diagnostics:
    {{ script }} collect-diagnostics

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
    {{ script }} generate-app-icon

fmt:
    swift format --in-place --recursive Package.swift Sources/ Tests/ scripts/

lint:
    swift format lint --strict --recursive Package.swift Sources/ Tests/ scripts/

clean:
    swift package clean
    swift package --package-path scripts clean
    if test -d build; then trash build; fi
