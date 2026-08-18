SurvivorLeagueCommunity = SurvivorLeagueCommunity or {}
SurvivorLeagueCommunity.MODULE = "SurvivorLeagueCommunity"
SurvivorLeagueCommunity.DATA_KEY = "SurvivorLeagueCommunityData"
SurvivorLeagueCommunity.VERSION = 3

SurvivorLeagueCommunity.DEFAULT_JOIN_MESSAGES = {
    "{name} has arrived. Let the bad decisions begin.",
    "The zombies requested backup after seeing {name} log in.",
    "{name} has entered the apocalypse. Good luck to everyone else.",
    "Someone secure the generator. {name} just connected.",
    "{name} is online. The survival odds have been recalculated.",
}

local function cleanSandboxString(value)
    if value == nil then return nil end
    local text = tostring(value):match("^%s*(.-)%s*$") or ""
    if #text >= 2 then
        local first = text:sub(1, 1)
        local last = text:sub(-1)
        if (first == '"' and last == '"') or (first == "'" and last == "'") then
            text = text:sub(2, -2):match("^%s*(.-)%s*$") or ""
        end
    end
    return text
end

SurvivorLeagueCommunity.cleanSandboxString = cleanSandboxString

function SurvivorLeagueCommunity.getJoinAnnouncements()
    local root = SandboxVars and SandboxVars.SurvivorLeagueCommunity or {}
    local messages = {}
    for i = 1, 20 do
        local value = cleanSandboxString(root["JoinMessage" .. tostring(i)]) or ""
        if value ~= "" then messages[#messages + 1] = value end
    end
    if #messages == 0 then
        for i = 1, #SurvivorLeagueCommunity.DEFAULT_JOIN_MESSAGES do
            messages[#messages + 1] = SurvivorLeagueCommunity.DEFAULT_JOIN_MESSAGES[i]
        end
    end
    local prefix = cleanSandboxString(root.JoinPrefix)
    if prefix == nil then prefix = "SURVIVOR LEAGUE" end
    return {
        enabled = root.JoinAnnouncements ~= false,
        prefix = prefix,
        duplicateCooldownSeconds = math.max(0, tonumber(root.JoinDuplicateCooldown) or 60),
        messages = messages,
    }
end

function SurvivorLeagueCommunity.getOptions()
    local root = SandboxVars and SandboxVars.SurvivorLeagueCommunity or {}
    local options = {
        enabled = root.Enabled ~= false,
        seasonDays = math.max(1, tonumber(root.SeasonDays) or 7),
        minimumKills = math.max(0, tonumber(root.MinimumKills) or 25),
        leaderboardSize = math.max(3, tonumber(root.LeaderboardSize) or 10),
        allowClientKillReports = root.AllowClientKillReports == true,
        clientKillReportIntervalSeconds = math.max(1, tonumber(root.ClientKillReportIntervalSeconds) or 15),
        clientKillMaxPerMinute = math.max(1, tonumber(root.ClientKillMaxPerMinute) or 120),
        allowClientDeathReports = root.AllowClientDeathReports ~= false,
        deathAnnouncements = root.DeathAnnouncements ~= false,
        deathIncludeSurvivalTime = root.DeathIncludeSurvivalTime ~= false,
        deathIncludeSeasonKills = root.DeathIncludeSeasonKills ~= false,
        deathIncludeTotalKills = root.DeathIncludeTotalKills ~= false,
        deathMinimumHours = math.max(0, tonumber(root.DeathMinimumHours) or 0),
        deathPrefix = cleanSandboxString(root.DeathPrefix) or "SURVIVOR LOST",
        items = {
            cleanSandboxString(root.FirstItems) or "",
            cleanSandboxString(root.SecondItems) or "",
            cleanSandboxString(root.ThirdItems) or "",
        },
        xp = {
            tonumber(root.FirstXP) or 0,
            tonumber(root.SecondXP) or 0,
            tonumber(root.ThirdXP) or 0,
        },
        xpPerk = cleanSandboxString(root.XPPerk) or "Sprinting",
        addTrait = {
            cleanSandboxString(root.FirstAddTrait) or "",
            cleanSandboxString(root.SecondAddTrait) or "",
            cleanSandboxString(root.ThirdAddTrait) or "",
        },
        removeTrait = {
            cleanSandboxString(root.FirstRemoveTrait) or "",
            cleanSandboxString(root.SecondRemoveTrait) or "",
            cleanSandboxString(root.ThirdRemoveTrait) or "",
        },
    }

    -- Kill-streak rewards are independent from seasonal podium rewards.
    -- Each tier can be claimed once per survivor life and resets on death.
    options.killStreakRewards = {
        { id = 1, enabled = root.KillTier1Enabled ~= false, kills = math.max(1, tonumber(root.KillTier1Kills) or 100), items = cleanSandboxString(root.KillTier1Items) or "", xp = math.max(0, tonumber(root.KillTier1XP) or 0), xpPerk = cleanSandboxString(root.KillTier1XPPerk) or "Sprinting" },
        { id = 2, enabled = root.KillTier2Enabled ~= false, kills = math.max(1, tonumber(root.KillTier2Kills) or 250), items = cleanSandboxString(root.KillTier2Items) or "", xp = math.max(0, tonumber(root.KillTier2XP) or 0), xpPerk = cleanSandboxString(root.KillTier2XPPerk) or "Sprinting" },
        { id = 3, enabled = root.KillTier3Enabled ~= false, kills = math.max(1, tonumber(root.KillTier3Kills) or 500), items = cleanSandboxString(root.KillTier3Items) or "", xp = math.max(0, tonumber(root.KillTier3XP) or 0), xpPerk = cleanSandboxString(root.KillTier3XPPerk) or "Sprinting" },
        { id = 4, enabled = root.KillTier4Enabled ~= false, kills = math.max(1, tonumber(root.KillTier4Kills) or 750), items = cleanSandboxString(root.KillTier4Items) or "", xp = math.max(0, tonumber(root.KillTier4XP) or 0), xpPerk = cleanSandboxString(root.KillTier4XPPerk) or "Sprinting" },
        { id = 5, enabled = root.KillTier5Enabled ~= false, kills = math.max(1, tonumber(root.KillTier5Kills) or 1000), items = cleanSandboxString(root.KillTier5Items) or "", xp = math.max(0, tonumber(root.KillTier5XP) or 0), xpPerk = cleanSandboxString(root.KillTier5XPPerk) or "Sprinting" },
    }

    return options
end

function SurvivorLeagueCommunity.playerKey(player)
    if not player then return nil end
    local username = player:getUsername()
    if username and tostring(username) ~= "" then return tostring(username) end
    return tostring(player:getDisplayName() or "unknown")
end

function SurvivorLeagueCommunity.now()
    if getTimestamp then return tonumber(getTimestamp()) or 0 end
    return math.floor((tonumber(getTimestampMs and getTimestampMs()) or 0) / 1000)
end
