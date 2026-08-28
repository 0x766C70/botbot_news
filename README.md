# botbot_script

A Bash script that sends messages to a conversational AI agent (botbot) via the [Infomaniak AI API](https://www.infomaniak.com/), with optional push notifications via [ntfy](https://ntfy.sh/).

## Requirements

- `bash` (≥ 4)
- [`curl`](https://curl.se/)
- [`jq`](https://stedolan.github.io/jq/)
- A valid [Infomaniak AI API token](https://manager.infomaniak.com/)
- An ntfy server (only required if using the `-ntfy` flag)
- `ii` (only required if using the `-irc` flag)

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
./botbot.sh [-ntfy|-irc] [-u <username>] "Your message here"
./botbot.sh -rss [-ntfy|-irc]
```

### Flags

| Flag              | Required | Description                                                        |
|-------------------|----------|--------------------------------------------------------------------|
| `-ntfy`           | No       | Send the agent's reply to the configured ntfy topic instead of stdout |
| `-irc`            | No       | Send the agent's reply to `irc.geeknode.org` in `#fdn` via `ii`   |
| `-rss`            | No       | Fetch unread entries from the Miniflux server and send an LLM digest |
| `-u <username>`   | No       | Identify yourself to the agent (default: `vlp`)                   |
| `"message"`       | Yes*     | The message to send to the agent (*not required with `-rss`)       |

### Output

By default the script prints the agent's reply to stdout. With `-ntfy`, the reply is pushed to the configured ntfy topic instead. With `-irc`, the reply is written to the `ii` channel input at `~/irc/irc.geeknode.org/fdn/in`.

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

**Send the reply to IRC (`#fdn` on `irc.geeknode.org`):**

```bash
./botbot.sh -irc -u garance "C'est quoi le programme ce soir ?"
```

**Fetch an RSS digest to stdout:**

```bash
./botbot.sh -rss
```

**Fetch an RSS digest and push it to ntfy:**

```bash
./botbot.sh -rss -ntfy
```

**Fetch an RSS digest and post it to IRC:**

```bash
./botbot.sh -rss -irc
```

## License

This project is maintained by [0x766C70](https://github.com/0x766C70).
