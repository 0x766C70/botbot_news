#!/usr/bin/env bash
set -euo pipefail

# Dependency checks
if ! command -v curl >/dev/null 2>&1; then
    echo "Error: 'curl' is required but not installed." >&2
    exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
    echo "Error: 'jq' is required but not installed." >&2
    exit 1
fi

# Configuration
MISTRAL_API_KEY="${MISTRAL_API_KEY:?MISTRAL_API_KEY is not set}"
CONV_ID="${4:-}"  # Utilisation de ${var:-} pour éviter les erreurs si vide
today=$(date +"%Y-%m-%d")
speaker="${1:-utilisateur}"  # Valeur par défaut
message="${3:-Bonjour}"      # Valeur par défaut

# Validation des paramètres
if [ $# -lt 3 ]; then
    echo "Usage: $0 <speaker> <brain> <message> [conversation_id]"
    exit 1
fi

LIBRARY_ID=""
case "$2" in
    "botbot_fdn")
        AGENT_ID="ag:00bd343b:20251002:botbot-fdn:7a3e7bdb"
        LIBRARY_ID="019d0fa1-1718-74ed-af19-cc625502bd86"
        ;;
    "botbot_mifa")
        AGENT_ID="ag:00bd343b:20251010:mifa-bot:d61e378c"
        ;;
    *)
        echo "Error: Unknown brain '$2'. Valid options: botbot_fdn, botbot_mifa" >&2
        exit 1
        ;;
esac

# Construction de la requête
if [ -n "$CONV_ID" ]; then
    API_URL="https://api.mistral.ai/v1/conversations/$CONV_ID"
    REQUEST_BODY=$(jq -n \
        --arg today "$today" \
        --arg speaker "$speaker" \
        --arg message "$message" \
        '{
            inputs: "Nous sommes le \($today) et ton interlocuteur est \($speaker). Il te dit: \($message)",
            stream: false,
            store: true,
            handoff_execution: "server"
        }')
else
    API_URL="https://api.mistral.ai/v1/conversations"
    REQUEST_BODY=$(jq -n \
        --arg today "$today" \
        --arg speaker "$speaker" \
        --arg message "$message" \
        --arg agent_id "$AGENT_ID" \
        --arg library_id "$LIBRARY_ID" \
        '{
            inputs: "Nous sommes le \($today) et ton interlocuteur est \($speaker). Il te dit: \($message)",
            stream: false,
            agent_id: $agent_id
        } + (if $library_id != "" then {tools: [{type: "document_library", library_ids: [$library_id]}]} else {} end)')
fi

# Exécution de la requête
response=$(curl -s --location "$API_URL" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -H "Authorization: Bearer $MISTRAL_API_KEY" \
    -d "$REQUEST_BODY")

# Vérification des erreurs API
if echo "$response" | jq -e '.object == "error"' >/dev/null 2>&1; then
    echo "Error: API returned an error: $(echo "$response" | jq -r '.message // "unknown error"')" >&2
    exit 1
fi

# Affichage du résultat
clean_text=$(echo "$response" | jq -r '.outputs[0].content')
clean_conv=$(echo "$response" | jq -r '.conversation_id')

jq_answer=$(jq -n \
    --arg reponse "$clean_text" \
    --arg conv "$clean_conv" \
    '{
        message: "\($reponse)",
        conv: "\($conv)"
    }')

echo "$jq_answer"
