#!/usr/bin/env bash
set -euo pipefail  # Exit on error, undefined vars, or pipe failures

# Configuration
API_URL="https://api.infomaniak.com/2/ai/108574/openai/v1/chat/completions"
API_TOKEN=""        # Populated by load_config
MODEL="qwen3"
NTFY_URL="https://ntfy.766c70.com/botbot_talk"
NTFY_USER="botbot"
NTFY_PASS=""        # Populated by load_config
IRC_SERVER="irc.geeknode.org"
IRC_CHANNEL="fdn"
II_BASE_DIR="${HOME}/irc"
CONFIG_FILE="${HOME}/.config/botbot/config.json"

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

# Function to load credentials from the JSON config file
# Expects: ~/.config/botbot/config.json with key .llm[0].infomaniak and optional .ntfy
load_config() {
    local use_ntfy="$1"

    if [[ ! -f "${CONFIG_FILE}" ]]; then
        echo "Error: Config file not found at '${CONFIG_FILE}'." >&2
        echo "Please create it with your LLM token and optional ntfy password." >&2
        exit 1
    fi

    # Extract the Infomaniak API token; allow INFOMANIAK_AI_TOKEN env-var override
    local token
    token=$(jq -r '.llm[0].infomaniak // empty' "${CONFIG_FILE}")
    if [[ -z "${token}" ]]; then
        echo "Error: Could not read '.llm[0].infomaniak' from '${CONFIG_FILE}'." >&2
        exit 1
    fi
    API_TOKEN="${INFOMANIAK_AI_TOKEN:-${token}}"

    # Extract the ntfy password only if needed
    if [[ "${use_ntfy}" == "true" ]]; then
        local ntfy_pass
        ntfy_pass=$(jq -r '.ntfy // empty' "${CONFIG_FILE}")
        if [[ -z "${ntfy_pass}" ]]; then
            echo "Error: Could not read '.ntfy' from '${CONFIG_FILE}'." >&2
            exit 1
        fi
        NTFY_PASS="${ntfy_pass}"
    fi
}

# Function to validate inputs and files
# Arguments: <use_ntfy> <use_irc> <user_message>
validate_inputs() {
    local use_ntfy="$1"
    local use_irc="$2"
    local user_message="$3"

    if [[ -z "${user_message}" ]]; then
        echo "Usage: $0 [-ntfy|-irc] [-u <username>] \"Your question here\"" >&2
        exit 1
    fi

    if [[ "${use_ntfy}" == "true" && "${use_irc}" == "true" ]]; then
        echo "Error: -ntfy and -irc cannot be used together." >&2
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

send_ntfy_alert() {
    local message="$1"

    if ! printf '%s' "${message}" | curl -fsS -u "${NTFY_USER}:${NTFY_PASS}" \
        --data-binary @- \
        "${NTFY_URL}" > /dev/null; then
        echo "Error: Failed to send ntfy alert." >&2
        exit 1
    fi
}

send_irc_message() {
    local message="$1"
    local channel_in_file="${II_BASE_DIR}/${IRC_SERVER}/${IRC_CHANNEL}/in"

    if [[ ! -w "${channel_in_file}" ]]; then
        echo "Error: ii channel input not writable at '${channel_in_file}'." >&2
        echo "Start ii and join #${IRC_CHANNEL} on ${IRC_SERVER} first." >&2
        exit 1
    fi

    while IFS= read -r line || [[ -n "${line}" ]]; do
        printf '%s\n' "${line}"
    done <<< "${message}" > "${channel_in_file}"
}

# Parse command-line flags
# Supports: -ntfy (send output to ntfy), -irc (send output to IRC), -u <username> (default: vlp)
parse_args() {
    USE_NTFY="false"
    USE_IRC="false"
    CURRENT_USER="vlp"
    USER_MESSAGE=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -ntfy)
                USE_NTFY="true"
                shift
                ;;
            -irc)
                USE_IRC="true"
                shift
                ;;
            -u)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: -u requires a username argument." >&2
                    exit 1
                fi
                CURRENT_USER="$2"
                shift 2
                ;;
            -*)
                echo "Error: Unknown flag '$1'." >&2
                echo "Usage: $0 [-ntfy|-irc] [-u <username>] \"Your question here\"" >&2
                exit 1
                ;;
            *)
                # Everything that's not a flag is the user message
                USER_MESSAGE="$1"
                shift
                ;;
        esac
    done
}

# Main logic
main() {
    check_deps
    parse_args "$@"
    load_config "${USE_NTFY}"
    validate_inputs "${USE_NTFY}" "${USE_IRC}" "${USER_MESSAGE}"

    # Read the role from the file
    # We use cat to read the whole file content
    local system_prompt
    system_prompt=$(cat "${ROLE_FILE}")

    # Prepend the current user's identity so the LLM knows who it's talking to
    local full_message="[L'utilisateur qui te parle est ${CURRENT_USER}] ${USER_MESSAGE}"

    # Escape both prompts to ensure valid JSON
    # This handles newlines, quotes, and special characters safely
    local escaped_system
    local escaped_user

    escaped_system=$(printf '%s' "${system_prompt}" | escape_json)
    escaped_user=$(printf '%s' "${full_message}" | escape_json)

    # Send the request
    local response
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
    local answer
    answer=$(printf '%s' "${response}" | jq -r '.choices[0].message.content // empty')

    if [[ -z "${answer}" ]]; then
        echo "Error: Could not extract answer. API might have returned an error." >&2
        echo "Raw response: ${response}" >&2
        exit 1
    fi

    # Output: send to ntfy/irc service if requested, otherwise print to terminal
    if [[ "${USE_NTFY}" == "true" ]]; then
        send_ntfy_alert "${answer}"
    elif [[ "${USE_IRC}" == "true" ]]; then
        send_irc_message "${answer}"
    else
        printf '%s\n' "${answer}"
    fi
}

main "$@"
