#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"
# Project dir name is "Edrawk", but the binary / source file is lowercase
# "edrawk" (matches edrawk.nimble's `bin = @["edrawk"]`). Keep these two
# decoupled so a future rename of the directory doesn't break the build.
BIN_NAME="edrawk"
RELEASE_DIR="$(cd "$PROJECT_DIR/.." && pwd)/${PROJECT_NAME}-release"

usage() {
    cat <<EOF
usage: $(basename "$0") [--local] [--public --version vX.Y.Z [--notes "text"]]

  --local               build locally into <project>-release/ next to the project
  --public              trigger release.yml workflow via gh CLI
  --version <tag>       required when --public is used
  --notes <text>        optional release notes
EOF
}

DO_LOCAL=0
DO_PUBLIC=0
VERSION=""
NOTES=""

while [ $# -gt 0 ]; do
    case "$1" in
        --local)   DO_LOCAL=1; shift ;;
        --public)  DO_PUBLIC=1; shift ;;
        --version) VERSION="${2:-}"; shift 2 ;;
        --notes)   NOTES="${2:-}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown flag: $1" >&2; usage; exit 1 ;;
    esac
done

if [ $DO_LOCAL -eq 0 ] && [ $DO_PUBLIC -eq 0 ]; then
    usage
    exit 1
fi

if [ $DO_LOCAL -eq 1 ]; then
    echo "==> Local build: $PROJECT_NAME -> $RELEASE_DIR"
    rm -rf "$RELEASE_DIR"
    mkdir -p "$RELEASE_DIR"

    # Size-trimming flag set — kept in sync with .github/workflows/release.yml
    # so what we test locally matches what CI ships:
    #   -d:danger / -d:strip / -d:lto / -d:noSignalHandler
    #   --threads:off / --panics:on / --stackTrace:off / --lineTrace:off
    #   -fno-pie / -ffunction-sections / -fdata-sections /
    #     -fno-asynchronous-unwind-tables / -fno-unwind-tables /
    #     -fno-stack-protector
    #   -Wl,--gc-sections / -Wl,--build-id=none / -Wl,-z,norelro
    build_flavor() {
        local out="$1"; shift
        ( cd "$PROJECT_DIR" && \
          nim c --opt:size -d:danger -d:strip -d:lto \
                -d:noSignalHandler \
                --threads:off --panics:on \
                --stackTrace:off --lineTrace:off \
                --passC:-fno-pie --passL:-no-pie \
                --passC:-ffunction-sections --passC:-fdata-sections \
                --passC:-fno-asynchronous-unwind-tables \
                --passC:-fno-unwind-tables \
                --passC:-fno-stack-protector \
                --passL:-Wl,--gc-sections \
                --passL:-Wl,--build-id=none \
                --passL:-Wl,-z,norelro \
                --nimcache:"$RELEASE_DIR/.nimcache-$(basename "$out")" \
                "$@" \
                --out:"$out" "src/${BIN_NAME}.nim" )
    }

    BIN_X11="$RELEASE_DIR/$BIN_NAME"
    BIN_WL="$RELEASE_DIR/${BIN_NAME}-wayland"

    # Probe — a Wayland-only dev box won't have libX11 dev headers. Skip
    # the X11 flavor rather than failing the whole build.
    HAS_X11=0
    HAS_WL=0
    [ -f /usr/include/X11/Xlib.h ] && HAS_X11=1
    [ -f /usr/include/wayland-client.h ] && HAS_WL=1
    pkg-config --exists x11 2>/dev/null && HAS_X11=1
    pkg-config --exists wayland-client 2>/dev/null && HAS_WL=1

    if [ $HAS_X11 -eq 1 ]; then
        echo "  -> X11 build"
        build_flavor "$BIN_X11"
    else
        echo "  -> X11 skipped (libX11 headers not found)"
    fi
    if [ $HAS_WL -eq 1 ]; then
        echo "  -> Wayland build"
        build_flavor "$BIN_WL" -d:wayland
    else
        echo "  -> Wayland skipped (wayland-client headers not found)"
    fi

    [ -f "$PROJECT_DIR/README.md" ]      && cp -f "$PROJECT_DIR/README.md"      "$RELEASE_DIR/" || true
    [ -f "$PROJECT_DIR/LICENSE" ]        && cp -f "$PROJECT_DIR/LICENSE"        "$RELEASE_DIR/" || true
    [ -f "$PROJECT_DIR/LICENSE.txt" ]    && cp -f "$PROJECT_DIR/LICENSE.txt"    "$RELEASE_DIR/" || true
    [ -f "$PROJECT_DIR/gpl-3.0.txt" ]    && cp -f "$PROJECT_DIR/gpl-3.0.txt"    "$RELEASE_DIR/" || true
    [ -f "$PROJECT_DIR/config.example" ] && cp -f "$PROJECT_DIR/config.example" "$RELEASE_DIR/" || true
    if [ -d "$PROJECT_DIR/themes" ]; then
        rm -rf "$RELEASE_DIR/themes"
        cp -R "$PROJECT_DIR/themes" "$RELEASE_DIR/themes"
    fi

    echo "==> Local done:"
    [ -f "$BIN_X11" ] && echo "    $BIN_X11 ($(du -h "$BIN_X11" | cut -f1))"
    [ -f "$BIN_WL"  ] && echo "    $BIN_WL  ($(du -h "$BIN_WL"  | cut -f1))"
fi

if [ $DO_PUBLIC -eq 1 ]; then
    if [ -z "$VERSION" ]; then
        echo "error: --public requires --version <tag>" >&2
        exit 1
    fi
    if ! command -v gh >/dev/null 2>&1; then
        echo "error: gh CLI not found; install it and run 'gh auth login'" >&2
        exit 1
    fi
    REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null || true)
    if [ -z "$REPO" ]; then
        echo "error: not in a github repo (or gh not authenticated)" >&2
        exit 1
    fi
    WORKFLOW="release.yml"
    echo "==> Triggering $WORKFLOW on $REPO ($VERSION)"
    OLD_ID=$(gh run list --workflow="$WORKFLOW" --limit 1 --json databaseId -q '.[0].databaseId' 2>/dev/null || echo "")
    gh workflow run "$WORKFLOW" \
        --field version="$VERSION" \
        --field notes="$NOTES"
    echo "==> Waiting for run to register..."
    NEW_ID=""
    for i in $(seq 1 30); do
        sleep 2
        CUR_ID=$(gh run list --workflow="$WORKFLOW" --limit 1 --json databaseId -q '.[0].databaseId' 2>/dev/null || echo "")
        if [ -n "$CUR_ID" ] && [ "$CUR_ID" != "$OLD_ID" ]; then
            NEW_ID="$CUR_ID"
            break
        fi
    done
    if [ -z "$NEW_ID" ]; then
        echo "error: failed to detect new workflow run" >&2
        exit 1
    fi
    echo "==> Watching run $NEW_ID"
    gh run watch "$NEW_ID" --exit-status
fi
