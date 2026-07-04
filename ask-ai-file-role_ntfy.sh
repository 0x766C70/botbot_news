#!/usr/bin/env bash
set -euo pipefail  # Exit on error, undefined vars, or pipe failures

# Configuration
API_URL="https://api.infomaniak.com/2/ai/108574/openai/v1/chat/completions"
API_TOKEN="${INFOMANIAK_AI_TOKEN:-YOUR-TOKEN-HERE}"
MODEL="qwen3"

# Resolve the directory where the script is located
# This ensures role.txt is found even if you run the script from elsewhere
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROLE_FILE="${SCRIPT_DIR}/role.txt"

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

# Function to validate inputs and files
validate_inputs() {
    if [[ -z "${1:-}" ]]; then
        echo "Usage: $0 \"Your question here\"" >&2
        exit 1
    fi

    if [[ ! -f "${ROLE_FILE}" ]]; then
        echo "Error: Role file not found at '${ROLE_FILE}'." >&2
        echo "Please create a role.txt file in the script's directory." >&2
        exit 1
    fi
}

# Helper to escape JSON strings properly
escape_json() {
    # Reads raw input from stdin and outputs a valid JSON string
    jq -Rs '.'
}

# Main logic
main() {
    check_deps
    validate_inputs "$1"

    local user_message="$1"
    
    # Read the role from the file
    # We use cat to read the whole file content
    local system_prompt
    system_prompt=$(cat "${ROLE_FILE}")

    # Escape both prompts to ensure valid JSON
    # This handles newlines, quotes, and special characters safely
    local escaped_system
    local escaped_user
    
    escaped_system=$(echo "${system_prompt}" | escape_json)
    escaped_user=$(echo "${user_message}" | escape_json)

    # Send the request
    response=$(curl -s -X POST \
        -H "Authorization: Bearer ${API_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{
            \"messages\": [
                {
                    \"role\": \"system\",
                    \"content\": ${escaped_system}
                },
                {
                    \"role\": \"user\",
                    \"content\": ${escaped_user}
                }
            ],
            \"model\": \"${MODEL}\"
        }" \
        "${API_URL}")

    if [[ -z "${response}" ]]; then
        echo "Error: Received empty response from API." >&2
        exit 1
    fi

    # Extract the content
    answer=$(echo "${response}" | jq -r '.choices[0].message.content // empty')

    if [[ -z "${answer}" ]]; then
        echo "Error: Could not extract answer. API might have returned an error." >&2
        echo "Raw response: ${response}" >&2
        exit 1
    fi

    echo "${answer}"
}

main "$@"
