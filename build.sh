#!/usr/bin/env bash
# Build script for AI Shell Assistant Daemon
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
BUILD_TYPE="${BUILD_TYPE:-release}"
VERBOSE="${VERBOSE:-0}"

# Functions
info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1" >&2
}

# Check dependencies
check_dependencies() {
    info "Checking dependencies..."

    # Check Swift
    if ! command -v swift >/dev/null 2>&1; then
        error "Swift is not installed"
        echo "Please install Swift from https://swift.org/download/" >&2
        exit 1
    fi

    local swift_version=$(swift --version | head -n1)
    success "Found $swift_version"

    # Check Swift version (requires 5.9+)
    local version_number=$(swift --version | grep -oE '[0-9]+\.[0-9]+' | head -n1)
    local major=$(echo "$version_number" | cut -d. -f1)
    local minor=$(echo "$version_number" | cut -d. -f2)

    if [[ $major -lt 5 ]] || [[ $major -eq 5 && $minor -lt 9 ]]; then
        error "Swift 5.9 or later is required (found $version_number)"
        exit 1
    fi

    success "Swift version is compatible"
}

# Clean build artifacts
clean() {
    info "Cleaning build artifacts..."

    if [[ -d .build ]]; then
        rm -rf .build
        success "Removed .build directory"
    fi

    if [[ -d .swiftpm ]]; then
        rm -rf .swiftpm
        success "Removed .swiftpm directory"
    fi

    success "Clean complete"
}

# Resolve dependencies
resolve_dependencies() {
    info "Resolving Swift package dependencies..."

    if [[ $VERBOSE -eq 1 ]]; then
        swift package resolve --verbose
    else
        swift package resolve
    fi

    success "Dependencies resolved"
}

# Build the project
build() {
    info "Building AI Shell Daemon ($BUILD_TYPE)..."

    local build_args=("build" "-c" "$BUILD_TYPE")

    if [[ $VERBOSE -eq 1 ]]; then
        build_args+=("--verbose")
    fi

    # Add platform-specific flags
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS specific flags
        build_args+=("--arch" "arm64" "--arch" "x86_64")
    fi

    swift "${build_args[@]}"

    success "Build complete"
}

# Run tests
test() {
    info "Running tests..."

    if [[ $VERBOSE -eq 1 ]]; then
        swift test --verbose
    else
        swift test
    fi

    success "Tests passed"
}

# Show build information
show_build_info() {
    local binary_path=".build/${BUILD_TYPE}/ai-shell-daemon"

    if [[ ! -f "$binary_path" ]]; then
        error "Binary not found at $binary_path"
        return 1
    fi

    echo ""
    echo "Build Information:"
    echo "=================="
    echo "Binary path:     $binary_path"
    echo "Build type:      $BUILD_TYPE"

    if command -v file >/dev/null 2>&1; then
        echo "File type:       $(file "$binary_path" | cut -d: -f2 | xargs)"
    fi

    if [[ -f "$binary_path" ]]; then
        local size=$(du -h "$binary_path" | cut -f1)
        echo "Binary size:     $size"
    fi

    echo ""
    echo "To install, run:  ./install.sh"
    echo "To run locally:   $binary_path"
    echo ""
}

# Main script
main() {
    local clean_build=0
    local run_tests=0
    local show_help=0

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --clean|-c)
                clean_build=1
                shift
                ;;
            --test|-t)
                run_tests=1
                shift
                ;;
            --debug|-d)
                BUILD_TYPE="debug"
                shift
                ;;
            --release|-r)
                BUILD_TYPE="release"
                shift
                ;;
            --verbose|-v)
                VERBOSE=1
                shift
                ;;
            --help|-h)
                show_help=1
                shift
                ;;
            *)
                error "Unknown option: $1"
                show_help=1
                shift
                ;;
        esac
    done

    if [[ $show_help -eq 1 ]]; then
        cat <<EOF
Usage: $0 [OPTIONS]

Build the AI Shell Assistant Daemon

OPTIONS:
    -c, --clean      Clean build artifacts before building
    -t, --test       Run tests after building
    -d, --debug      Build in debug mode (default: release)
    -r, --release    Build in release mode
    -v, --verbose    Verbose output
    -h, --help       Show this help message

EXAMPLES:
    $0                    # Build in release mode
    $0 --clean --test     # Clean, build, and test
    $0 --debug --verbose  # Debug build with verbose output

ENVIRONMENT VARIABLES:
    BUILD_TYPE    Build configuration (debug|release)
    VERBOSE       Enable verbose output (0|1)
EOF
        exit 0
    fi

    echo "AI Shell Assistant - Build Script"
    echo "=================================="
    echo ""

    # Run build steps
    check_dependencies

    if [[ $clean_build -eq 1 ]]; then
        clean
    fi

    resolve_dependencies
    build

    if [[ $run_tests -eq 1 ]]; then
        test
    fi

    show_build_info

    success "All done!"
}

# Run main function
main "$@"
