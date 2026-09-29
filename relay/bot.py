"""Read a GTX server log and publish Survivor League events to Discord."""
import asyncio
import os
from pathlib import Path

import discord
from discord import app_commands

from league import connect, ingest, leaderboard


def required(name):
    value = os.getenv(name, "").strip()
    if not value:
        raise RuntimeError(f"Missing {name}")
    return value


class LogSource:
    def __init__(self):
        self.path = required("LOG_PATH")
        self.mode = os.getenv("LOG_SOURCE", "local").lower()
        self.ssh = None
        self.sftp = None

    def open(self):
        if self.mode == "local":
            return
        if self.mode != "sftp":
            raise ValueError("LOG_SOURCE must be local or sftp")
        import paramiko
        self.ssh = paramiko.SSHClient()
        self.ssh.load_system_host_keys()
        self.ssh.set_missing_host_key_policy(paramiko.RejectPolicy())
        self.ssh.connect(required("SFTP_HOST"), port=int(os.getenv("SFTP_PORT", "22")), username=required("SFTP_USER"),
                         password=os.getenv("SFTP_PASSWORD") or None, key_filename=os.getenv("SFTP_KEY_FILE") or None,
                         timeout=15, auth_timeout=15)
        self.sftp = self.ssh.open_sftp()

    def close(self):
        if self.sftp:
            self.sftp.close()
        if self.ssh:
            self.ssh.close()
        self.sftp = self.ssh = None

    def read(self, offset):
        if self.mode == "sftp":
            if not self.sftp:
                self.open()
            size = self.sftp.stat(self.path).st_size
            handle = self.sftp.open(self.path, "rb")
        else:
            size = Path(self.path).stat().st_size
            handle = open(self.path, "rb")
        try:
            if offset > size:
                offset = 0  # The configured log was truncated or replaced.
            handle.seek(offset)
            data = handle.read(min(size - offset, 1024 * 1024))
            return offset, data
        finally:
            handle.close()

    def size(self):
        if self.mode == "sftp":
            if not self.sftp:
                self.open()
            return self.sftp.stat(self.path).st_size
        return Path(self.path).stat().st_size


class Relay(discord.Client):
    def __init__(self, db):
        super().__init__(intents=discord.Intents.default(), allowed_mentions=discord.AllowedMentions.none())
        self.tree = app_commands.CommandTree(self)
        self.db = db
        self.guild_id = int(required("DISCORD_GUILD_ID"))
        self.channel_id = int(required("DISCORD_EVENT_CHANNEL_ID"))
        self.log = LogSource()
        self.poll_seconds = max(5, int(os.getenv("POLL_SECONDS", "10")))
        self.worker = None

    async def setup_hook(self):
        guild = discord.Object(id=self.guild_id)
        group = app_commands.Group(name="league", description="Survivor League standings")

        @group.command(name="leaderboard", description="Show the current top ten")
        async def board(interaction: discord.Interaction):
            meta, rows = leaderboard(self.db)
            if not meta:
                await interaction.response.send_message("League snapshot is pending. Check the mod version and relay log access.", ephemeral=True)
                return
            lines = [f"**Survivor League · Season {meta[0]}**"]
            lines += [f"{rank}. {discord.utils.escape_markdown(name)} — {kills} season · {total} total" for rank, name, kills, total, _, _ in rows]
            lines.append(f"Season ends <t:{meta[2]}:R>" if meta[2] else "Season end unavailable")
            await interaction.response.send_message("\n".join(lines)[:1900], ephemeral=True)

        @group.command(name="player", description="Find a player's league record")
        async def player(interaction: discord.Interaction, name: str):
            row = self.db.execute("SELECT rank,display_name,kills,total,streak,best FROM standings WHERE lower(username)=lower(?) OR lower(display_name)=lower(?) LIMIT 1", (name[:48], name[:48])).fetchone()
            if row is None:
                await interaction.response.send_message("No matching player in the latest snapshot.", ephemeral=True)
                return
            rank, display, kills, total, streak, best = row
            await interaction.response.send_message(f"**#{rank} {discord.utils.escape_markdown(display)}** · Season {kills} · Total {total} · Streak {streak} · Best {best}", ephemeral=True)

        @group.command(name="season", description="Show the current season end")
        async def season(interaction: discord.Interaction):
            meta, rows = leaderboard(self.db, 0)
            message = f"Season {meta[0]} ends <t:{meta[2]}:F> (<t:{meta[2]}:R>)." if meta and meta[2] else "League snapshot is pending."
            await interaction.response.send_message(message, ephemeral=True)

        self.tree.add_command(group, guild=guild)
        await self.tree.sync(guild=guild)
        self.worker = asyncio.create_task(self.run_relay())

    async def close(self):
        if self.worker:
            self.worker.cancel()
        self.log.close()
        await super().close()

    def scan(self):
        source = self.log.path
        db = connect(str(self.db_path))
        try:
            row = db.execute("SELECT offset FROM cursors WHERE source=?", (source,)).fetchone()
            if row is None:
                # Existing log history is not an event backlog. The next snapshot arrives within a minute.
                with db:
                    db.execute("INSERT INTO cursors VALUES (?,?)", (source, self.log.size()))
                return
            offset, data = self.log.read(row[0])
            for line in data.splitlines(keepends=True):
                if not line.endswith(b"\n"):
                    break
                next_offset = offset + len(line)
                ingest(db, source, offset, line.decode("utf-8", errors="replace"), next_offset)
                offset = next_offset
        finally:
            db.close()

    async def publish(self):
        await self.wait_until_ready()
        channel = self.get_channel(self.channel_id) or await self.fetch_channel(self.channel_id)
        for event_id, kind, body in self.db.execute("SELECT id,kind,body FROM outbox WHERE sent=0 ORDER BY rowid LIMIT 25").fetchall():
            if kind == "SurvivorLeagueKill":
                continue  # Frequent deltas are captured by the snapshot, not posted as spam.
            label = {"SurvivorLeagueDeath": "☠️ Survivor lost", "SurvivorLeagueCommunityJoin": "👋 Survivor joined", "SurvivorLeagueCommunityAudit": "🏆 Season settled"}.get(kind, "Survivor League")
            await channel.send(f"**{label}**\n{discord.utils.escape_markdown(body[:1600])}")
            with self.db:
                self.db.execute("UPDATE outbox SET sent=1 WHERE id=?", (event_id,))
        with self.db:
            self.db.execute("UPDATE outbox SET sent=1 WHERE kind='SurvivorLeagueKill' AND sent=0")

    async def run_relay(self):
        while not self.is_closed():
            try:
                await asyncio.to_thread(self.scan)
                await self.publish()
            except asyncio.CancelledError:
                raise
            except Exception as exc:
                print(f"Relay poll failed: {type(exc).__name__}: {exc}", flush=True)
                self.log.close()
            await asyncio.sleep(self.poll_seconds)


if __name__ == "__main__":
    db_path = Path(required("DATABASE_PATH"))
    db_path.parent.mkdir(parents=True, exist_ok=True)
    relay = Relay(connect(str(db_path)))
    relay.db_path = db_path
    relay.run(required("DISCORD_TOKEN"))
