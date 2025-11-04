#!/bin/sh
set -e  # Exit on error

readonly LIB_MUSL="musl"
readonly LIB_GLIBC="libc"
readonly LIB_DEFAULT="default"
readonly ALPINE_RELEASE_FILE="/etc/alpine-release"

readonly INSTALLER_DOWNLOAD_PATH="/tmp/installer.sh"
readonly INSTALLER_URL_SUFFIX="api/v1/deployment/installer/agent/unix/paas-sh/latest"

# Try using ldd command
check_ldd() {
    if ! command -v ldd >/dev/null 2>&1; then
        return 1
    fi

    ldd_result=$(ldd /bin/echo 2>/dev/null || echo "")
    
    if echo "$ldd_result" | grep -qi "musl"; then
        lib="$LIB_MUSL"
    elif echo "$ldd_result" | grep -qiE "glibc|gnu|libc\.so"; then
        lib="$LIB_DEFAULT"
    fi
}

check_alpine_release_file() {
    if [ -f "$ALPINE_RELEASE_FILE" ]; then
        lib="$LIB_MUSL"
    fi
}

run() {
    # Validate required environment variables
    if [ -z "$DT_ENDPOINT" ]; then
        echo "Error: DT_ENDPOINT is not set" >&2
        exit 1
    fi
    
    if [ -z "$DT_API_TOKEN" ]; then
        echo "Error: DT_API_TOKEN is not set" >&2
        exit 1
    fi
    
    if [ -z "$START_APP_CMD" ]; then
        echo "Error: START_APP_CMD is not set" >&2
        exit 1
    fi

    # Trim trailing slash
    DT_ENDPOINT=$(echo "${DT_ENDPOINT%/}")
    
    echo "Detected library flavor: $DT_FLAVOR"
    echo "Downloading Dynatrace OneAgent installer..."
    
    # Download installer
    if ! wget -O "$INSTALLER_DOWNLOAD_PATH" "$DT_ENDPOINT/$INSTALLER_URL_SUFFIX?Api-Token=$DT_API_TOKEN&flavor=$DT_FLAVOR&include=$DT_INCLUDE"; then
        echo "Error: Failed to download Dynatrace installer" >&2
        exit 1
    fi
    
    echo "Running Dynatrace OneAgent installer..."
    if ! sh "$INSTALLER_DOWNLOAD_PATH"; then
        echo "Error: Dynatrace installer failed" >&2
        rm -f "$INSTALLER_DOWNLOAD_PATH"
        exit 1
    fi
    
    # Cleanup installer
    rm -f "$INSTALLER_DOWNLOAD_PATH"
    
    echo "Starting application with Dynatrace OneAgent..."
    
    # Inject Dynatrace library and run the application
    # Note: exec replaces the current shell process
    LD_PRELOAD="/opt/dynatrace/oneagent/agent/lib64/liboneagentproc.so" exec $START_APP_CMD
}

main() {
    lib=""

    # First check using ldd utility
    check_ldd

    # If still empty check if Alpine release file exists
    if [ -z "$lib" ]; then
        check_alpine_release_file
    fi

    # If lib is empty at the end, set it to "default"
    if [ -z "$lib" ]; then
        lib="$LIB_DEFAULT"
    fi

    # Set dt_flavor based on detected libc
    DT_FLAVOR="$lib"

    run
}

main