#!/usr/bin/env bash
# Calculate time spent and API cost from worker logs

calculate_worker_cost() {
    local log_file="$1"
    local log_dir="$(dirname "$log_file")/logs"

    # Sum all result entries from iteration logs using jq
    local totals
    totals=$(find "$log_dir" -type f -name "iteration-*.log" -exec grep '"type":"result"' {} \; | \
        jq -s '{
            duration_ms: (map(.duration_ms) | add),
            duration_api_ms: (map(.duration_api_ms) | add),
            total_cost: (map(.total_cost_usd) | add),
            num_turns: (map(.num_turns) | add),
            web_search_requests: (map(.usage.server_tool_use.web_search_requests) | add),
            input_tokens: (map(.usage.input_tokens) | add),
            output_tokens: (map(.usage.output_tokens) | add),
            cache_creation_tokens: (map(.usage.cache_creation_input_tokens) | add),
            cache_read_tokens: (map(.usage.cache_read_input_tokens) | add),
            model_usage: (map(.modelUsage | to_entries) | flatten | group_by(.key) | map({
                key: .[0].key,
                value: {
                    inputTokens: (map(.value.inputTokens) | add),
                    outputTokens: (map(.value.outputTokens) | add),
                    cacheReadInputTokens: (map(.value.cacheReadInputTokens) | add),
                    cacheCreationInputTokens: (map(.value.cacheCreationInputTokens) | add),
                    costUSD: (map(.value.costUSD) | add)
                }
            }) | from_entries)
        }')

    local duration_ms=$(echo "$totals" | jq -r '.duration_ms')
    local duration_api_ms=$(echo "$totals" | jq -r '.duration_api_ms')
    local total_cost=$(echo "$totals" | jq -r '.total_cost')
    local num_turns=$(echo "$totals" | jq -r '.num_turns')
    local web_search_requests=$(echo "$totals" | jq -r '.web_search_requests')
    local input_tokens=$(echo "$totals" | jq -r '.input_tokens')
    local output_tokens=$(echo "$totals" | jq -r '.output_tokens')
    local cache_creation_tokens=$(echo "$totals" | jq -r '.cache_creation_tokens')
    local cache_read_tokens=$(echo "$totals" | jq -r '.cache_read_tokens')

    # Format time
    local time_spent=$((duration_ms / 1000))
    local hours=$((time_spent / 3600))
    local minutes=$(((time_spent % 3600) / 60))
    local seconds=$((time_spent % 60))
    local time_formatted=$(printf "%02d:%02d:%02d" $hours $minutes $seconds)

    local api_time_spent=$((duration_api_ms / 1000))
    local api_hours=$((api_time_spent / 3600))
    local api_minutes=$(((api_time_spent % 3600) / 60))
    local api_seconds=$((api_time_spent % 60))
    local api_time_formatted=$(printf "%02d:%02d:%02d" $api_hours $api_minutes $api_seconds)

    # Output results
    echo "=== Worker Time and Cost Report ==="
    echo ""
    echo "Time Spent: $time_formatted (API: $api_time_formatted)"
    echo "Turns: $num_turns"
    echo "Web Searches: $web_search_requests"
    echo ""
    echo "Token Usage:"
    echo "  Input tokens: $(printf "%'d" $input_tokens)"
    echo "  Output tokens: $(printf "%'d" $output_tokens)"
    echo "  Cache creation tokens: $(printf "%'d" $cache_creation_tokens)"
    echo "  Cache read tokens: $(printf "%'d" $cache_read_tokens)"
    echo "  Total tokens: $(printf "%'d" $((input_tokens + output_tokens + cache_creation_tokens + cache_read_tokens)))"
    echo ""
    echo "Per-Model Usage:"
    echo "$totals" | jq -r '.model_usage | to_entries[] | "  \(.key):\n    Input: \(.value.inputTokens), Output: \(.value.outputTokens)\n    Cache read: \(.value.cacheReadInputTokens), Cache create: \(.value.cacheCreationInputTokens)\n    Cost: $\(.value.costUSD | . * 100 | round / 100)"'
    echo ""
    echo "Total Cost: \$$(printf "%.2f" $total_cost)"
    echo ""

    # Export for use in PR summary
    export WORKER_TIME_SPENT="$time_formatted"
    export WORKER_TOTAL_COST=$(printf "%.2f" $total_cost)
    export WORKER_INPUT_TOKENS=$input_tokens
    export WORKER_OUTPUT_TOKENS=$output_tokens
    export WORKER_CACHE_CREATION_TOKENS=$cache_creation_tokens
    export WORKER_CACHE_READ_TOKENS=$cache_read_tokens
}

# If called directly with log file argument
if [ $# -gt 0 ]; then
    calculate_worker_cost "$1"
fi
