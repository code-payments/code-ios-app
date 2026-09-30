# Sourced by Scripts/build.sh and Scripts/test.sh.
#
# Runs xcodebuild with its arguments. When stdout is not a terminal (an agent
# or a pipe) and xcsift is installed, the log goes through `xcsift -f toon`,
# which keeps errors, test results, and a warning count and drops the rest: a raw log
# is tens of thousands of tokens that an agent re-reads on every later step.
# Set RAW_XCODEBUILD=1 to get the unfiltered log.
run_xcodebuild() {
    if [[ -t 1 || -n "${RAW_XCODEBUILD:-}" ]] || ! command -v xcsift >/dev/null 2>&1; then
        xcodebuild "$@"
        return
    fi
    set -o pipefail
    xcodebuild "$@" 2>&1 | xcsift -f toon
}
