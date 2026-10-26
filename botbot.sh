#!/usr/bin/env bash
set -euo pipefail  # Exit on error, undefined vars, or pipe failures

# Configuration
API_URL=""          # Populated by load_config
API_TOKEN=""        # Populated by load_config
MODEL=""            # Populated by load_config
LLM_NAME=""         # Selected with -llm; defaults to the first llm
NTFY_URL="https://ntfy.766c70.com/botbot_talk"
NTFY_USER="botbot"
NTFY_PASS=""        # Populated by load_config
CONFIG_FILE="${HOME}/.config/botbot/config.json"
RSS_URL="https://rss.766c70.com"
RSS_TOKEN=""        # Populated by load_config

# Resolve the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

sleep $((RANDOM % 31))m

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
    if [[ -z "${API_URL}" || -z "${API_TOKEN}" || -z "${MODEL}" ]]; then
        echo "Error: LLM entry must define 'endpoint', 'api_key' and 'model'." >&2
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

    local prompt
    prompt="### RÔLE
Tu es un assistant de veille informative spécialisé dans la synthèse de flux RSS pour notifications mobiles (ntfy). Ta mission est de transformer une liste d'articles RSS en un message unique, concis et percutant.

### CONTRAINTES CRITIQUES (NON NÉGOCIABLES)
1. LIMITE D'APERÇU (MONTRE) : Les 220 premiers caractères du message doivent contenir l'essentiel (titre du sujet principal ou résumé ultra-court). C'est ce qui sera lu sur la montre sans ouvrir le message. Si ce contenu dépasse 220 caractères, tu dois le résumer davantage et s'il n'atteint pas 220 caractères, tu peux ajouter un ou deux mots pour le rendre plus percutant et atteindre au moins les 180 caractères.
2. LIMITE TOTALE (SYSTÈME) : La longueur totale du message ne doit JAMAIS dépasser 4096 octets (environ 4000 caractères). Si le contenu brut dépasse cette limite, tu dois tronquer ou résumer davantage les articles secondaires.
3. FORMAT : Texte brut ou Markdown léger. Pas de balises HTML lourdes.

### STRUCTURE DU MESSAGE OBLIGATOIRE

[PARTIE 1 : L'ACCROCHE - MAX 220 CARACTÈRES]
- Doit résumer l'information la plus importante ou donner le ton du flux.
- Doit être compréhensible seul.
- Se termine idéalement par un saut de ligne pour séparer visuellement de la suite.

[PARTIE 2 : LE DÉTAIL - POUR LE TÉLÉPHONE]
- Liste numérotée des autres articles importants.
- Format : \"1. Titre : Résumé en 1 phrase.\"
- Inclure les liens courts si la place le permet (sinon, privilégier le texte).
- S'arrêter immédiatement si la limite de 4096 octets est atteinte.

### PROCÉDURE DE GÉNÉRATION
1. Analyse tous les articles du flux RSS fourni.
2. Identifie l'article le plus pertinent pour l'accroche.
3. Rédige l'accroche (Partie 1) en comptant strictement les caractères (Max 220).
4. Rédige les résumés des autres articles (Partie 2).
5. CALCUL DE SÉCURITÉ : Vérifie la longueur totale du message.
   - Si Longueur < 1500 caractères : développe un ou plusieurs sujet ou ajoute un commentaire de synthèse pour enrichir le message.
   - Si Longueur > 3800 caractères (marge de sécurité pour les octets) : Réduis la longueur des résumés ou supprime les articles les moins pertinents jusqu'à respecter la limite indispensable.
6. Génère le message final.

### EXEMPLE DE SORTIE ATTENDUE

[URGENT] Nouvelle réglementation européenne sur l'IA adoptée ce matin. Impact majeur pour les techs.
---
1. Marchés : Le CAC40 rebondit de 2% suite à l'annonce.
2. Tech : OpenAI publie un nouveau modèle plus efficace.
3. Science : Découverte d'une exoplanète potentiellement habitable.

liens:
1. https://www.reference_news_1.com/article1
2. https://www.reference_news_2.com/article2
3. https://www.reference_news_3.com/article3

### INSTRUCTION FINALE
Ne génère jamais de texte d'introduction ou de conclusion hors du format demandé (ex: \"Voici le résumé\"). Renvoie UNIQUEMENT le contenu de la notification prêt à être envoyé via ntfy."$'\n\n'"${entries_text}"

    local escaped_user
    escaped_user=$(printf '%s' "${prompt}" | escape_json)

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
            \"model\": \"${MODEL}\"
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

    mark_rss_feeds_as_read "${entries_json}"
}

main "$@"
