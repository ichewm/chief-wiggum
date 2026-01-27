#!/usr/bin/env bash
# status-display.sh - Orchestrator status output formatting
#
# Extracts the 140+ line status display block from wiggum-run into a
# dedicated module for better maintainability and testability.
#
# shellcheck disable=SC2329  # Functions are invoked indirectly via callbacks
set -euo pipefail

[ -n "${_STATUS_DISPLAY_LOADED:-}" ] && return 0
_STATUS_DISPLAY_LOADED=1

# Source dependencies
source "$WIGGUM_HOME/lib/scheduler/worker-pool.sh"
source "$WIGGUM_HOME/lib/tasks/task-parser.sh"
source "$WIGGUM_HOME/lib/tasks/conflict-detection.sh"
source "$WIGGUM_HOME/lib/core/logger.sh"

# Display full orchestrator status
#
# Args:
#   iteration         - Current iteration number
#   max_workers       - Maximum workers allowed
#   ready_tasks       - Space-separated list of ready task IDs
#   blocked_tasks     - Space-separated list of blocked task IDs
#   cyclic_tasks_ref  - Name of associative array containing cyclic task IDs
#   ralph_dir         - Ralph directory path
#   ready_since_file  - Path to ready-since tracking file
#   aging_factor      - Aging factor for priority calculation
#   plan_bonus        - Plan bonus for priority calculation
#   dep_bonus_per_task - Dependency bonus per task
#
# Uses: _WORKER_POOL from worker-pool.sh
display_orchestrator_status() {
    local iteration="$1"
    local max_workers="$2"
    local ready_tasks="$3"
    local blocked_tasks="$4"
    local -n _cyclic_tasks_ref="$5"
    local ralph_dir="$6"
    local ready_since_file="$7"
    local aging_factor="$8"
    local plan_bonus="$9"
    local dep_bonus_per_task="${10}"

    local main_count fix_count resolve_count
    main_count=$(pool_count "main")
    fix_count=$(pool_count "fix")
    resolve_count=$(pool_count "resolve")

    echo ""
    echo "=== Status Update (iteration $iteration) ==="
    echo "Active workers: $main_count/$max_workers"

    # Show which tasks are being worked on (main workers)
    if [ "$main_count" -gt 0 ]; then
        echo "In Progress:"
        _display_workers_callback() {
            local pid="$1" type="$2" task_id="$3"
            if [ "$type" = "main" ]; then
                echo "  - $task_id (PID: $pid)"
            fi
        }
        pool_foreach "main" _display_workers_callback
    fi

    # Show active fix workers
    if [ "$fix_count" -gt 0 ]; then
        echo "Fix Workers:"
        local now
        now=$(date +%s)
        _display_fix_callback() {
            local pid="$1" type="$2" task_id="$3" start_time="$4"
            local elapsed=$((now - start_time))
            echo "  - $task_id (PID: $pid, ${elapsed}s elapsed)"
        }
        pool_foreach "fix" _display_fix_callback
    fi

    # Show active resolve workers
    if [ "$resolve_count" -gt 0 ]; then
        echo "Resolve Workers:"
        local now
        now=$(date +%s)
        _display_resolve_callback() {
            local pid="$1" type="$2" task_id="$3" start_time="$4"
            local elapsed=$((now - start_time))
            echo "  - $task_id (PID: $pid, ${elapsed}s elapsed)"
        }
        pool_foreach "resolve" _display_resolve_callback
    fi

    # Show blocked tasks waiting on dependencies
    if [ -n "$blocked_tasks" ]; then
        echo "Blocked (waiting on dependencies):"
        for task_id in $blocked_tasks; do
            local waiting_on
            waiting_on=$(get_unsatisfied_dependencies "$ralph_dir/kanban.md" "$task_id" | tr '\n' ',' | sed 's/,$//')
            echo "  - $task_id (waiting on: $waiting_on)"
        done
    fi

    # Show tasks skipped due to dependency cycles
    if [ ${#_cyclic_tasks_ref[@]} -gt 0 ]; then
        echo "Skipped (dependency cycle):"
        for task_id in "${!_cyclic_tasks_ref[@]}"; do
            local error_type="${_cyclic_tasks_ref[$task_id]}"
            if [ "$error_type" = "SELF" ]; then
                echo "  - $task_id (self-dependency)"
            else
                echo "  - $task_id (circular dependency)"
            fi
        done
    fi

    # Build list of active task IDs for conflict checking
    local -A active_task_ids=()
    _collect_active_tasks() {
        local pid="$1" type="$2" task_id="$3"
        if [ "$type" = "main" ]; then
            active_task_ids[$task_id]=1
        fi
    }
    pool_foreach "main" _collect_active_tasks

    # Show tasks deferred due to file conflicts
    local deferred_conflicts=()
    for task_id in $ready_tasks; do
        # Create a temporary associative array in the format expected by has_file_conflict
        # has_file_conflict expects: PID -> task_id mapping
        local -A _temp_workers=()
        _build_temp_workers() {
            local pid="$1" type="$2" task_id="$3"
            if [ "$type" = "main" ]; then
                _temp_workers[$pid]="$task_id"
            fi
        }
        pool_foreach "main" _build_temp_workers

        if has_file_conflict "$ralph_dir" "$task_id" _temp_workers; then
            deferred_conflicts+=("$task_id")
        fi
    done

    if [ ${#deferred_conflicts[@]} -gt 0 ]; then
        echo "Deferred (file conflict):"
        for task_id in "${deferred_conflicts[@]}"; do
            local -A _temp_workers=()
            _build_temp_workers_for_conflict() {
                local pid="$1" type="$2" tid="$3"
                if [ "$type" = "main" ]; then
                    _temp_workers[$pid]="$tid"
                fi
            }
            pool_foreach "main" _build_temp_workers_for_conflict

            local conflicting_tasks
            conflicting_tasks=$(get_conflicting_tasks "$ralph_dir" "$task_id" _temp_workers | tr '\n' ',' | sed 's/,$//')
            echo "  - $task_id (conflicts with: $conflicting_tasks)"
        done
    fi

    # Show top 7 ready tasks with priority scores (excluding in-progress and deferred)
    local ready_count
    ready_count=$(echo "$ready_tasks" | grep -c . 2>/dev/null || true)
    ready_count=${ready_count:-0}

    # Subtract deferred tasks from count (in-progress tasks already excluded by get_ready_tasks)
    ready_count=$((ready_count - ${#deferred_conflicts[@]}))

    if [ "$ready_count" -gt 0 ]; then
        echo "Ready ($ready_count tasks, top 7 by priority):"

        # Get priority scores for display
        local all_metadata
        all_metadata=$(get_all_tasks_with_metadata "$ralph_dir/kanban.md")

        local display_count=0
        for task_id in $ready_tasks; do
            [ "$display_count" -ge 7 ] && break

            # Skip in-progress tasks
            if [ -n "${active_task_ids[$task_id]+x}" ]; then
                continue
            fi

            # Skip deferred tasks
            local is_deferred=false
            for deferred in "${deferred_conflicts[@]}"; do
                if [ "$task_id" = "$deferred" ]; then
                    is_deferred=true
                    break
                fi
            done
            [ "$is_deferred" = true ] && continue

            local priority iters_waiting effective_pri
            priority=$(echo "$all_metadata" | awk -F'|' -v t="$task_id" '$1 == t { print $3 }')
            iters_waiting=$(awk -F'|' -v t="$task_id" '$1 == t { print $2 }' "$ready_since_file" 2>/dev/null)
            iters_waiting=${iters_waiting:-0}
            effective_pri=$(get_effective_priority "$priority" "$iters_waiting" "$aging_factor")

            # Apply plan bonus
            if task_has_plan "$ralph_dir" "$task_id"; then
                effective_pri=$((effective_pri - plan_bonus))
            fi

            # Apply dep bonus
            local dep_depth
            dep_depth=$(get_dependency_depth "$ralph_dir/kanban.md" "$task_id")
            effective_pri=$((effective_pri - dep_depth * dep_bonus_per_task))
            [[ "$effective_pri" -lt 0 ]] && effective_pri=0 || true

            echo "  - $task_id (score: $effective_pri)"
            ((++display_count))
        done
    fi

    # Show recent errors only (not info)
    if [ -f "$ralph_dir/logs/workers.log" ]; then
        local recent_errors
        recent_errors=$(grep -i "ERROR\|WARN" "$ralph_dir/logs/workers.log" 2>/dev/null | tail -n 5 || true)
        if [ -n "$recent_errors" ]; then
            echo ""
            echo "Recent errors:"
            echo "$recent_errors" | sed 's/^/  /'
        fi
    fi

    echo "=========================================="
}

# Display a compact status line (for non-scheduling iterations)
#
# Args:
#   iteration   - Current iteration number
#   max_workers - Maximum workers allowed
display_compact_status() {
    local iteration="$1"
    local max_workers="$2"

    local main_count fix_count resolve_count
    main_count=$(pool_count "main")
    fix_count=$(pool_count "fix")
    resolve_count=$(pool_count "resolve")

    local priority_info=""
    if [ "$fix_count" -gt 0 ] || [ "$resolve_count" -gt 0 ]; then
        priority_info=" | fix:$fix_count resolve:$resolve_count"
    fi

    echo "[iter $iteration] workers: $main_count/$max_workers$priority_info"
}

# Display final summary when orchestration completes
#
# Args:
#   ralph_dir - Ralph directory path
display_final_summary() {
    local ralph_dir="$1"

    echo ""
    echo "=========================================="
    log "Chief Wiggum finished - all tasks complete!"
    echo ""

    # Show final summary
    local completed_count
    completed_count=$(grep -c '^\- \[x\]' "$ralph_dir/kanban.md" 2>/dev/null || echo "0")

    echo "Summary:"
    echo "  - Total tasks completed: $completed_count"
    echo "  - Changelog: .ralph/changelog.md"
    echo ""
    echo "Next steps:"
    echo "  - Review completed work: wiggum review list"
    echo "  - Merge PRs: wiggum review merge-all"
    echo "  - Clean up: wiggum clean"
    echo ""
}
