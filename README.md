# botbot_script

A Bash script that sends messages to a conversational AI agent (botbot) via the [Infomaniak AI API](https://www.infomaniak.com/), with optional push notifications via [ntfy](https://ntfy.sh/).

## Requirements

- `bash` (≥ 4)
- [`curl`](https://curl.se/)
- [`jq`](https://stedolan.github.io/jq/)
- A valid [Infomaniak AI API token](https://manager.infomaniak.com/)
- An ntfy server (only required if using the `-ntfy` flag)

## Configuration

The script reads credentials from `~/.config/botbot/config.json`. Create it with the following structure:

```json
{
  "llm": [
    {
      "infomaniak": "your_infomaniak_api_token_here"
    }
  ],
  "ntfy": "your_ntfy_password_here"
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
./botbot.sh [-ntfy] [-u <username>] "Your message here"
```

### Flags

| Flag              | Required | Description                                                        |
|-------------------|----------|--------------------------------------------------------------------|
| `-ntfy`           | No       | Send the agent's reply to the configured ntfy topic instead of stdout |
| `-u <username>`   | No       | Identify yourself to the agent (default: `vlp`)                   |
| `"message"`       | Yes      | The message to send to the agent                                   |

### Output

By default the script prints the agent's reply to stdout. With `-ntfy`, the reply is pushed to the configured ntfy topic instead.

## Examples

**Ask a question as the default user:**

```bash
./botbot.sh "Quelle est la météo à Paris ?"
```

**Ask a question as a specific user:**

```bash
./botbot.sh -u albane "Raconte-moi une blague."
```

**Send the reply to ntfy instead of stdout:**

```bash
./botbot.sh -ntfy -u garance "C'est quoi le programme ce soir ?"
```

## License

This project is maintained by [0x766C70](https://github.com/0x766C70).
