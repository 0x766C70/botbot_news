# botbot_news

A Bash script that fetches unread RSS entries from a Miniflux server, summarizes them with an OpenAI-compatible LLM API (Infomaniak, Mistral, ...) and delivers the digest through [ntfy](https://ntfy.sh/).

## Requirements

- `bash` (≥ 4)
- [`curl`](https://curl.se/)
- [`jq`](https://stedolan.github.io/jq/)
- An API key for at least one LLM provider
- Access to the configured ntfy and Miniflux servers

## Configuration

The script reads settings from `~/.config/botbot/config.json`. Several LLMs can be defined; the first one is the default.

```json
{
  "llm": [
    {
      "name": "infomaniak",
      "endpoint": "https://api.infomaniak.com/2/ai/YOUR_PRODUCT_ID/openai/v1/chat/completions",
      "api_key": "your_infomaniak_api_token_here",
      "model": "qwen3"
    },
    {
      "name": "mistral",
      "endpoint": "https://api.mistral.ai/v1/chat/completions",
      "api_key": "your_mistral_api_key_here",
      "model": "mistral-small-latest"
    }
  ],
  "ntfy": "your_ntfy_password_here",
  "rss": {
    "token": "your_miniflux_api_token_here"
  }
}
```

An LLM entry may define an `agent` (agent ID, e.g. a Mistral agent with `endpoint` `https://api.mistral.ai/v1/agents/completions`) instead of `model`. The agent's own instructions are then used and only the RSS entries are sent.

The script exits with an error if the config file is missing or incomplete.

## Usage

```bash
./botbot.sh                 # uses the first LLM in config.json
./botbot.sh -llm mistral    # uses the LLM named "mistral"
```

| Argument         | Required | Description                                                  |
|------------------|----------|--------------------------------------------------------------|
| `-llm LLM_name`  | No       | Name of the LLM from `config.json`; defaults to the first one |

The script fetches unread entries, sends an LLM digest to the ntfy topic, then marks the fetched feeds as read.

## License

This project is maintained by [0x766C70](https://github.com/0x766C70).
