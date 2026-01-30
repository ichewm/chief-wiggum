#!/usr/bin/env bash
# terminal-header.sh - Fixed terminal header for wiggum run
#
# Provides a fixed header at the top of the terminal showing current worker
# status, with log output scrolling in the region below.
#
# Uses ANSI terminal scroll regions to split the terminal into:
#   - Top zone (fixed header): Compact worker status, refreshed each iteration
#   - Bottom zone (scroll region): All log()/echo output scrolls naturally
#
# Disabled (all functions no-op) when:
#   - stdout is not a TTY
#   - $TERM is unset or "dumb"
#   - WIGGUM_NO_HEADER=1 is set
#
# shellcheck disable=SC2154  # _th_now, _th_entries set via dynamic scope
set -euo pipefail

[ -n "${_TERMINAL_HEADER_LOADED:-}" ] && return 0
_TERMINAL_HEADER_LOADED=1

# =============================================================================
# Module State
# =============================================================================

_TH_ENABLED=false
_TH_HEADER_HEIGHT=0
_TH_TERM_ROWS=0
_TH_TERM_COLS=0
_TH_LAST_CONTENT=""
_TH_RUN_MODE=""
_TH_MAX_LINES="${WIGGUM_HEADER_MAX_LINES:-10}"

# =============================================================================
# Public API
# =============================================================================

# Initialize the terminal header
#
# Detects terminal capabilities, sets scroll region, and prepares for
# header rendering. No-ops if stdout is not a TTY, TERM is dumb, or
# WIGGUM_NO_HEADER=1.
#
# Args:
#   max_workers - Maximum concurrent workers
#   run_mode    - Run mode description (e.g., "standard", "plan mode")
terminal_header_init() {
    local max_workers="$1"
    local run_mode="$2"

    # Disable if not interactive or explicitly opted out
    if [[ ! -t 1 ]] || [[ -z "${TERM:-}" ]] || [[ "${TERM:-}" == "dumb" ]] \
       || [[ "${WIGGUM_NO_HEADER:-}" == "1" ]]; then
        _TH_ENABLED=false
        return 0
    fi

    # Verify /dev/tty is writable
    if ! printf '' > /dev/tty 2>/dev/null; then
        _TH_ENABLED=false
        return 0
    fi

    _TH_ENABLED=true
    _TH_RUN_MODE="$run_mode"

    _terminal_header_query_size

    # Initial height: banner + separator (adjusted on first refresh)
    _TH_HEADER_HEIGHT=2
    _terminal_header_set_scroll_region

    # Position cursor at start of scroll region
    local scroll_top=$((_TH_HEADER_HEIGHT + 1))
    printf '\033[%d;1H' "$scroll_top" > /dev/tty 2>/dev/null || true

    _terminal_header_clear_header_area
}

# Refresh the header with current worker status
#
# Rebuilds header content from the worker pool. Skips terminal writes
# if content is unchanged from the last render.
#
# Args:
#   iteration   - Current loop iteration number
#   max_workers - Maximum concurrent workers
terminal_header_refresh() {
    [[ "$_TH_ENABLED" == true ]] || return 0

    local iteration="$1"
    local max_workers="$2"

    local content
    content=$(_terminal_header_build_content "$iteration" "$max_workers")

    # Skip if unchanged
    [[ "$content" != "$_TH_LAST_CONTENT" ]] || return 0
    _TH_LAST_CONTENT="$content"

    # Recalculate height from content
    local new_height
    new_height=$(printf '%s\n' "$content" | wc -l)
    new_height=$((new_height))  # trim whitespace from wc

    local old_height=$_TH_HEADER_HEIGHT
    if [[ "$new_height" -ne "$_TH_HEADER_HEIGHT" ]]; then
        _TH_HEADER_HEIGHT="$new_height"
        # DECSC: save cursor before DECSTBM (which resets cursor to home)
        printf '\0337' > /dev/tty 2>/dev/null || true
        _terminal_header_set_scroll_region
        # DECRC: restore cursor to pre-DECSTBM position
        printf '\0338' > /dev/tty 2>/dev/null || true
    fi

    _terminal_header_render "$content" "$old_height"
}

# Force the next refresh to redraw (clear cached content)
terminal_header_force_redraw() {
    _TH_LAST_CONTENT=""
}

# Clean up terminal state
#
# Resets scroll region to full terminal and moves cursor to bottom.
# Safe to call multiple times.
terminal_header_cleanup() {
    [[ "$_TH_ENABLED" == true ]] || return 0
    _TH_ENABLED=false

    # Reset scroll region to full terminal
    printf '\033[r' > /dev/tty 2>/dev/null || true

    # Move cursor to bottom of terminal
    printf '\033[%d;1H\n' "$_TH_TERM_ROWS" > /dev/tty 2>/dev/null || true
}

# Check if header mode is active
#
# Returns: 0 if enabled, 1 if disabled
terminal_header_is_enabled() {
    [[ "$_TH_ENABLED" == true ]]
}

# =============================================================================
# SIGWINCH Handler
# =============================================================================

# Handle terminal resize - re-query size, reset scroll region, force redraw
_terminal_header_on_resize() {
    [[ "$_TH_ENABLED" == true ]] || return 0

    _terminal_header_query_size
    # DECSC: save cursor before DECSTBM (which resets cursor to home)
    printf '\0337' > /dev/tty 2>/dev/null || true
    _terminal_header_set_scroll_region
    # DECRC: restore cursor
    printf '\0338' > /dev/tty 2>/dev/null || true
    _TH_LAST_CONTENT=""
}

# =============================================================================
# Internal Helpers
# =============================================================================

# Query terminal dimensions
_terminal_header_query_size() {
    _TH_TERM_ROWS=$(tput lines 2>/dev/null || echo 24)
    _TH_TERM_COLS=$(tput cols 2>/dev/null || echo 80)
}

# Set the scroll region below the header
#
# Only sets DECSTBM (scroll margins). Does NOT reposition the cursor.
# Callers are responsible for cursor placement after calling this.
#
# Note: DECSTBM moves cursor to home (1,1) per VT100 spec.
_terminal_header_set_scroll_region() {
    local scroll_top=$((_TH_HEADER_HEIGHT + 1))

    # Ensure scroll region has at least 2 usable rows
    if [[ "$scroll_top" -ge "$((_TH_TERM_ROWS - 1))" ]]; then
        scroll_top=$((_TH_TERM_ROWS - 2))
        [[ "$scroll_top" -ge 2 ]] || scroll_top=2
    fi

    # DECSTBM: set scroll region (moves cursor to home per VT100 spec)
    printf '\033[%d;%dr' "$scroll_top" "$_TH_TERM_ROWS" > /dev/tty 2>/dev/null || true
}

# Clear all lines in the header area
_terminal_header_clear_header_area() {
    # DECSC: save cursor
    printf '\0337' > /dev/tty 2>/dev/null || true

    local i
    for ((i = 1; i <= _TH_HEADER_HEIGHT; i++)); do
        printf '\033[%d;1H\033[2K' "$i" > /dev/tty 2>/dev/null || true
    done

    # DECRC: restore cursor
    printf '\0338' > /dev/tty 2>/dev/null || true
}

# Callback for pool_foreach - collects worker entries into _th_entries array
#
# Uses dynamic scoping to access _th_entries and _th_now from
# _terminal_header_build_content.
#
# Args (from pool_foreach):
#   $1 - pid
#   $2 - type (main|fix|resolve)
#   $3 - task_id
#   $4 - start_time (epoch)
_th_collect_worker() {
    local pid="$1" type="$2" task_id="$3" start_time="$4"
    local elapsed=$((_th_now - start_time))
    local mins=$((elapsed / 60))
    local secs=$((elapsed % 60))
    local entry
    printf -v entry '%-10s %-7s PID:%-7s %dm%02ds' "$task_id" "$type" "$pid" "$mins" "$secs"
    _th_entries+=("$entry")
}

# Build header content as a multi-line string on stdout
#
# Args:
#   iteration   - Current loop iteration
#   max_workers - Maximum concurrent workers
_terminal_header_build_content() {
    local iteration="$1"
    local max_workers="$2"
    local _th_now
    _th_now=$(date +%s)

    # Gather worker counts
    local main_count fix_count resolve_count total_count
    main_count=$(pool_count "main")
    fix_count=$(pool_count "fix")
    resolve_count=$(pool_count "resolve")
    total_count=$((main_count + fix_count + resolve_count))

    # --- Banner line ---
    local banner
    printf -v banner '── Chief Wiggum ── %s ── workers: %d/%d ── fix:%d resolve:%d ── iter %d ──' \
        "$_TH_RUN_MODE" "$main_count" "$max_workers" "$fix_count" "$resolve_count" "$iteration"

    # Pad banner with ─ to terminal width
    local banner_len=${#banner}
    if [[ "$banner_len" -lt "$_TH_TERM_COLS" ]]; then
        local pad_count=$((_TH_TERM_COLS - banner_len))
        local padding
        printf -v padding '%*s' "$pad_count" ''
        padding="${padding// /─}"
        banner="${banner}${padding}"
    fi
    echo "$banner"

    # --- Worker detail lines (2 per row) ---
    if [[ "$total_count" -gt 0 ]]; then
        local -a _th_entries=()
        pool_foreach "all" _th_collect_worker

        local entry_count=${#_th_entries[@]}
        local max_worker_lines=$((_TH_MAX_LINES - 2))  # reserve banner + separator
        [[ "$max_worker_lines" -ge 1 ]] || max_worker_lines=1

        local worker_lines_needed=$(( (entry_count + 1) / 2 ))
        local show_overflow=false
        local overflow_count=0

        if [[ "$worker_lines_needed" -gt "$max_worker_lines" ]]; then
            show_overflow=true
            local visible_entries=$(( (max_worker_lines - 1) * 2 ))
            overflow_count=$((entry_count - visible_entries))
            worker_lines_needed="$max_worker_lines"
        fi

        local idx=0
        local row
        for ((row = 0; row < worker_lines_needed; row++)); do
            if [[ "$show_overflow" == true && "$row" -eq $((worker_lines_needed - 1)) ]]; then
                echo "  ... and $overflow_count more"
                break
            fi

            local line="  ${_th_entries[$idx]:-}"
            ((++idx)) || true

            if [[ "$idx" -lt "$entry_count" ]]; then
                line="${line}    ${_th_entries[$idx]:-}"
                ((++idx)) || true
            fi

            echo "$line"
        done
    fi

    # --- Separator line ---
    local separator
    printf -v separator '%*s' "$_TH_TERM_COLS" ''
    separator="${separator// /─}"
    echo "$separator"
}

# Render content into the header area
#
# Saves cursor position, writes header lines, clears leftover lines
# from a previously taller header, then restores cursor position.
#
# Args:
#   content    - Multi-line header content string
#   old_height - Previous header height (for clearing stale rows)
_terminal_header_render() {
    local content="$1"
    local old_height="${2:-$_TH_HEADER_HEIGHT}"

    # DECSC: save cursor position (more reliable with scroll regions than SCP)
    printf '\0337' > /dev/tty 2>/dev/null || true

    # Write each header line
    local line_num=1
    while IFS= read -r line; do
        printf '\033[%d;1H\033[2K%s' "$line_num" "$line" > /dev/tty 2>/dev/null || true
        ((++line_num)) || true
    done <<< "$content"

    # Clear leftover lines from previously taller header
    local clear_to=$_TH_HEADER_HEIGHT
    [[ "$old_height" -gt "$clear_to" ]] && clear_to="$old_height"
    while [[ "$line_num" -le "$clear_to" ]]; do
        printf '\033[%d;1H\033[2K' "$line_num" > /dev/tty 2>/dev/null || true
        ((++line_num)) || true
    done

    # DECRC: restore cursor position (back to scroll region)
    printf '\0338' > /dev/tty 2>/dev/null || true
}
