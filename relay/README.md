# Survivor League Discord Relay (preview)

The Build 42 server mod writes a complete standings snapshot to its console log once per minute. This optional Python service reads that log locally or through read-only SFTP and posts join, death, and season settlement notices. `/league leaderboard`, `/league player`, and `/league season` read only the latest complete snapshot. It does not issue RCON commands or grant rewards.

## Requirements

- Survivor League server mod with the snapshot export in this checkout, installed on the game server after a backup and restart.
- Python 3.11+ on the VPS, Discord bot token and a Discord channel with Send Messages permission.
- Read-only access to the **game server console log** through SFTP, or an existing read-only log sync to the VPS. RCON alone cannot read these league snapshots.
- SFTP host key installed in the service account's `known_hosts` before starting. The service rejects unknown host keys.

## Install on Ubuntu

```bash
sudo install -d -m 750 -o "$USER" /opt/survivor-league-relay /var/lib/survivor-league-relay
python3 -m venv /opt/survivor-league-relay/.venv
/opt/survivor-league-relay/.venv/bin/pip install -r relay/requirements.txt
cp relay/bot.py relay/league.py /opt/survivor-league-relay/
cp relay/.env.example /opt/survivor-league-relay/.env
chmod 600 /opt/survivor-league-relay/.env
```

Edit the private `.env`. Put actual secrets only there; never in the Git repository or Workshop package. A log already synchronized to the VPS can use `LOG_SOURCE=local` with `LOG_PATH` pointing to the local file, omitting SFTP variables. The SFTP path must identify a current log file and be readable by the account. On first start the relay begins at the end of the existing log, and the next minute's snapshot initializes the commands. The channel receives only new events.

Start manually with:

```bash
cd /opt/survivor-league-relay
set -a; . ./.env; set +a
exec .venv/bin/python bot.py
```

For a persistent service, configure systemd with `WorkingDirectory=/opt/survivor-league-relay`, `EnvironmentFile=/opt/survivor-league-relay/.env`, `ExecStart=/opt/survivor-league-relay/.venv/bin/python /opt/survivor-league-relay/bot.py`, `Restart=on-failure`, and an unprivileged `User=` with read access to its private files. Invite the bot with `bot` and `applications.commands` scopes; grant Send Messages in the chosen channel.

The SQLite outbox retains unsent events across Discord outages. A crash after Discord accepts a post but before SQLite marks it sent can result in one duplicate notification. Log snapshots are accepted only after their declared row count and end marker arrive.
