#!/bin/sh

set -eu

results_file="$1"

if [ ! -f "$results_file" ]; then
    echo "No test results were written to $results_file" >&2
    exit 1
fi

suite_attribute() {
    /usr/bin/xmllint --xpath "string(/testsuites/testsuite/@$1)" "$results_file"
}

tests="$(suite_attribute tests)"
failures="$(suite_attribute failures)"
errors="$(suite_attribute errors)"

if [ "$failures" -gt 0 ] || [ "$errors" -gt 0 ]; then
    /usr/bin/xmllint --xpath '//testcase[failure or error]' "$results_file" \
        | /usr/bin/sed -n 's/.*<testcase classname="\([^"]*\)" name="\([^"]*\)".*/Failed: \1\/\2/p'
fi

printf 'Tests: %s run, %s failed, %s errors\n' "$tests" "$failures" "$errors"
