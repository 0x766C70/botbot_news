#!/usr/bin/env bash
set -euo pipefail  # Exit on error, undefined vars, or pipe failures

# Configuration
API_URL=""          # Populated by load_config
API_TOKEN=""        # Populated by load_config
MODEL=""            # Populated by load_config
AGENT_ID=""         # Optional; populated by load_config
LLM_NAME=""         # Selected with -llm; defaults to the first llm
NTFY_URL="https://ntfy.766c70.com/botbot_talk"
NTFY_USER="botbot"
NTFY_PASS=""        # Populated by load_config
CONFIG_FILE="${HOME}/.config/botbot/config.json"
RSS_URL="https://rss.766c70.com"
RSS_TOKEN=""        # Populated by load_config

# Resolve the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# sleep $((RANDOM % 31))m

# Function to check dependencies
check_deps() {
    if ! command -v jq &> /dev/null; then
        echo "Error: 'jq' is required. Install with: sudo apt install jq" >&2
        exit 1
    fi
    if ! command -v curl &> /dev/null; then
        echo "Error: 'curl' is required." >&2
        exit 1
    fi
}

# Function to load credentials from the JSON config file
# Expects: ~/.config/botbot/config.json with keys .llm[] (name, endpoint, api_key, model), .ntfy and .rss.token
load_config() {
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        echo "Error: Config file not found at '${CONFIG_FILE}'." >&2
        echo "Please create it with your LLM settings and ntfy password." >&2
        exit 1
    fi

    # Select the LLM by name; default to the first one
    local llm
    if [[ -n "${LLM_NAME}" ]]; then
        llm=$(jq -c --arg n "${LLM_NAME}" '[.llm[]? | select(.name == $n)][0] // empty' "${CONFIG_FILE}")
        if [[ -z "${llm}" ]]; then
            echo "Error: LLM '${LLM_NAME}' not found in '${CONFIG_FILE}'." >&2
            exit 1
        fi
    else
        llm=$(jq -c '.llm[0]? // empty' "${CONFIG_FILE}")
        if [[ -z "${llm}" ]]; then
            echo "Error: No LLM defined in '.llm' of '${CONFIG_FILE}'." >&2
            exit 1
        fi
    fi

    API_URL=$(printf '%s' "${llm}" | jq -r '.endpoint // empty')
    API_TOKEN=$(printf '%s' "${llm}" | jq -r '.api_key // empty')
    MODEL=$(printf '%s' "${llm}" | jq -r '.model // empty')
    AGENT_ID=$(printf '%s' "${llm}" | jq -r '.agent // empty')
    if [[ -z "${API_URL}" || -z "${API_TOKEN}" ]] || [[ -z "${MODEL}" && -z "${AGENT_ID}" ]]; then
        echo "Error: LLM entry must define 'endpoint', 'api_key' and 'model' (or 'agent')." >&2
        exit 1
    fi

    local ntfy_pass
    ntfy_pass=$(jq -r '.ntfy // empty' "${CONFIG_FILE}")
    if [[ -z "${ntfy_pass}" ]]; then
        echo "Error: Could not read '.ntfy' from '${CONFIG_FILE}'." >&2
        exit 1
    fi
    NTFY_PASS="${ntfy_pass}"

    local rss_token
    rss_token=$(jq -r '.rss.token // empty' "${CONFIG_FILE}")
    if [[ -z "${rss_token}" ]]; then
        echo "Error: Could not read '.rss.token' from '${CONFIG_FILE}'." >&2
        exit 1
    fi
    RSS_TOKEN="${rss_token}"
}

# Helper to escape JSON strings properly
escape_json() {
    # Reads raw input from stdin and outputs a valid JSON string
    jq -Rs '.'
}

send_ntfy_alert() {
    local message="$1"

    if ! printf '%s' "${message}" | curl -fsS -u "${NTFY_USER}:${NTFY_PASS}" \
        --data-binary @- \
        "${NTFY_URL}" > /dev/null; then
        echo "Error: Failed to send ntfy alert." >&2
        exit 1
    fi
}

# Parse command-line flags
# Supports: -llm LLM_name (defaults to the first llm in the config)
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -llm)
                if [[ $# -lt 2 || -z "$2" ]]; then
                    echo "Error: -llm requires an LLM name." >&2
                    exit 1
                fi
                LLM_NAME="$2"
                shift 2
                ;;
            *)
                echo "Error: Unknown argument '$1'." >&2
                echo "Usage: $0 [-llm LLM_name]" >&2
                exit 1
                ;;
        esac
    done
}

# Fetch unread entries from the Miniflux RSS server
# Returns the raw JSON payload from the API
fetch_rss_entries() {
    local entries
    entries=$(curl -fsS \
        -H "X-Auth-Token: ${RSS_TOKEN}" \
        "${RSS_URL}/v1/entries?status=unread&limit=50&order=published_at&direction=desc")

    if [[ -z "${entries}" ]]; then
        echo "Error: Received empty response from Miniflux API." >&2
        exit 1
    fi

    printf '%s' "${entries}"
}

# Extract a compact text list of title + URL for the LLM to summarize
format_rss_entries_for_summary() {
    local entries_json="$1"

    printf '%s' "${entries_json}" | jq -r \
        '.entries[] | "- \(.title): \(.url)"'
}

# Mark all fetched RSS feeds as read in Miniflux
mark_rss_feeds_as_read() {
    local entries_json="$1"
    local feed_id

    while IFS= read -r feed_id; do
        [[ -n "${feed_id}" ]] || continue

        curl -fsS -X PUT \
            -H "X-Auth-Token: ${RSS_TOKEN}" \
            "${RSS_URL}/v1/feeds/${feed_id}/mark-all-as-read" > /dev/null
    done < <(printf '%s' "${entries_json}" | jq -r '.entries | map(.feed_id) | unique[]')
}

# Send RSS entries to the LLM and return a summarized digest
summarize_rss() {
    local entries_text="$1"

    local escaped_user
    escaped_user=$(printf '%s' "${entries_text}" | escape_json)

    local model_field
    if [[ -n "${AGENT_ID}" ]]; then
        model_field="\"agent_id\": \"${AGENT_ID}\""
    else
        model_field="\"model\": \"${MODEL}\""
    fi

    local response
    response=$(curl -s -X POST \
        -H "Authorization: Bearer ${API_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{
            \"messages\": [
                {
                    \"role\": \"user\",
                    \"content\": ${escaped_user}
                }
            ],
            ${model_field}
        }" \
        "${API_URL}")

    if [[ -z "${response}" ]]; then
        echo "Error: Received empty response from API." >&2
        exit 1
    fi

    local answer
    answer=$(printf '%s' "${response}" | jq -r '.choices[0].message.content // empty')

    if [[ -z "${answer}" ]]; then
        echo "Error: Could not extract answer from API response." >&2
        echo "Raw response: ${response}" >&2
        exit 1
    fi

    printf '%s' "${answer}"
}

# Main logic
main() {
    check_deps
    parse_args "$@"
    load_config

    local entries_json
    entries_json=$(fetch_rss_entries)

    if [[ "$(printf '%s' "${entries_json}" | jq '.entries | length')" -eq 0 ]]; then
        echo "No unread RSS entries found." >&2
        exit 0
    fi

    local entries
    entries=$(format_rss_entries_for_summary "${entries_json}")

    local digest
    digest=$(summarize_rss "${entries}")

    send_ntfy_alert "${digest}"

    #mark_rss_feeds_as_read "${entries_json}"
}

main "$@"
