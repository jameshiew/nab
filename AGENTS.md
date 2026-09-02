# Validation

Run `just verify` for macOS changes. It runs Swift format checks, unit tests, and a Debug app build with Swift Package Manager.

# Native crash debugging

Run `just collect-diagnostics` before rebuilding an app that already crashed.
This preserves its event journal, crash reports, binary identity, and symbols.

Use LLDB to reproduce a native crash:

```sh
just build-debug
lldb build/debug/Nab.app/Contents/MacOS/Nab
```

The Debug app has the `com.apple.security.get-task-allow` entitlement. Release
builds must not have this entitlement.

Set breakpoints and start the app from the LLDB prompt:

```text
breakpoint set -n objc_exception_throw
breakpoint set -n _swift_runtime_on_report
run
```

After LLDB stops at the fault, collect the stack and local state:

```text
thread backtrace all
frame variable
```
