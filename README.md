# botbot_news

A Bash script that sends messages to a conversational AI agent (botbot) via the [Infomaniak AI API](https://www.infomaniak.com/) and delivers replies through [ntfy](https://ntfy.sh/).

## Requirements

- `bash` (≥ 4)
- [`curl`](https://curl.se/)
- [`jq`](https://stedolan.github.io/jq/)
- A valid [Infomaniak AI API token](https://manager.infomaniak.com/)
- Access to the configured ntfy server

## Configuration

The script reads credentials from `~/.config/botbot/config.json`. Create it with the following structure:

```json
{
  "llm": [
    {
      "infomaniak": "your_infomaniak_api_token_here"
    }
  ],
  "ntfy": "your_ntfy_password_here",
  "rss": {
    "token": "your_miniflux_api_token_here"
  }
}
```

You can also override the Infomaniak token at runtime with the `INFOMANIAK_AI_TOKEN` environment variable:

```bash
export INFOMANIAK_AI_TOKEN="your_token_here"
```

The script will exit with an error if the config file is missing or incomplete.

### Role file

The agent's personality and instructions are loaded from `role.txt`, located in the same directory as the script. The script will exit with an error if this file is missing.

## Usage

```bash
./botbot.sh "Your message here"
./botbot.sh -rss
```

### Flags

| Argument    | Required | Description                                                        |
|-------------|----------|--------------------------------------------------------------------|
| `-rss`      | No       | Fetch unread entries from the Miniflux server, send an LLM digest, then mark fetched feeds as read |
| `"message"` | Yes*     | The message to send to the agent (*not required with `-rss`)       |

### Output

The script always sends the agent's reply or RSS digest to the configured ntfy topic. The user is always identified to the agent as `vlp`.

## Examples

**Ask a question:**

```bash
./botbot.sh "Quelle est la météo à Paris ?"
```

**Fetch an RSS digest and send it to ntfy:**

```bash
./botbot.sh -rss
```

## License

This project is maintained by [0x766C70](https://github.com/0x766C70).
