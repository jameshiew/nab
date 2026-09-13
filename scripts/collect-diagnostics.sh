#!/bin/sh

set -eu

script_directory="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
project_directory="$(dirname -- "$script_directory")"
bundle_identifier="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$project_directory/Sources/Nab/Resources/Info.plist")"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
output_directory="$project_directory/build/diagnostics/$timestamp"
user_library_directory="${HOME}/Library"
nab_log_directory="$user_library_directory/Logs/Nab"
crash_report_directory="$user_library_directory/Logs/DiagnosticReports"

/bin/mkdir -p "$output_directory/nab-events" "$output_directory/crash-reports"

{
    /usr/bin/sw_vers
    /usr/bin/uname -a
    /usr/bin/arch
} > "$output_directory/system.txt"

{
    /usr/bin/git -C "$project_directory" rev-parse HEAD
    /usr/bin/git -C "$project_directory" status --short --branch
} > "$output_directory/repository.txt"

if [ -d "$nab_log_directory" ]; then
    /usr/bin/find "$nab_log_directory" -type f -mtime -7 -print | while IFS= read -r log_file; do
        /bin/cp "$log_file" "$output_directory/nab-events/"
    done
fi

if ! /usr/bin/log show \
    --style json \
    --last 24h \
    --info \
    --debug \
    --predicate "subsystem == \"$bundle_identifier\"" \
    > "$output_directory/unified-log.jsonl" \
    2> "$output_directory/unified-log-error.txt"
then
    :
fi

if [ -d "$crash_report_directory" ]; then
    /usr/bin/find "$crash_report_directory" -maxdepth 1 -type f -name 'Nab*.ips' -mtime -7 -print \
        | while IFS= read -r crash_report; do
            /bin/cp "$crash_report" "$output_directory/crash-reports/"
        done
fi

debug_executable="$project_directory/build/debug/Nab.app/Contents/MacOS/Nab"
if [ -x "$debug_executable" ]; then
    /usr/bin/xcrun dwarfdump --uuid "$debug_executable" > "$output_directory/debug-binary.txt"
    /usr/bin/shasum -a 256 "$debug_executable" >> "$output_directory/debug-binary.txt"
fi

debug_symbols="$project_directory/build/debug/Nab.app.dSYM"
if [ -d "$debug_symbols" ]; then
    /bin/mkdir -p "$output_directory/symbols"
    /usr/bin/ditto "$debug_symbols" "$output_directory/symbols/Nab.app.dSYM"
fi

echo "$output_directory"
