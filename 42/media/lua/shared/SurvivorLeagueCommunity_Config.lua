SurvivorLeagueCommunity = SurvivorLeagueCommunity or {}
SurvivorLeagueCommunity.MODULE = "SurvivorLeagueCommunity"
SurvivorLeagueCommunity.DATA_KEY = "SurvivorLeagueCommunityData"
SurvivorLeagueCommunity.VERSION = 9
SurvivorLeagueCommunity.PROTOCOL_VERSION = 2

SurvivorLeagueCommunity.THEMES = {
    [1] = { id="ProjectZomboid", title="SURVIVOR LEAGUE", bg={0.035,0.035,0.045,0.97}, panel={0.065,0.065,0.080,0.96}, rowA={0.085,0.085,0.100,0.92}, rowB={0.055,0.055,0.068,0.92}, accent={0.92,0.92,0.92,1.0}, silver={0.77,0.79,0.82,1.0}, bronze={0.77,0.48,0.27,1.0}, text={0.92,0.92,0.95,1.0}, muted={0.58,0.59,0.64,1.0}, line={0.20,0.20,0.24,0.85}, live={0.30,0.90,0.55,1.0} },
    [2] = { id="MeeksProtocol", title="MEEKS PROTOCOL", bg={0.025,0.015,0.025,0.97}, panel={0.075,0.030,0.065,0.96}, rowA={0.125,0.045,0.100,0.94}, rowB={0.075,0.028,0.065,0.94}, accent={1.00,0.10,0.55,1.0}, silver={1.00,0.72,0.87,1.0}, bronze={0.86,0.49,0.20,1.0}, text={0.98,0.92,0.96,1.0}, muted={0.70,0.46,0.61,1.0}, line={0.34,0.12,0.27,0.90}, live={0.30,0.90,0.55,1.0} },
    [3] = { id="Military", title="SURVIVOR LEAGUE", bg={0.035,0.045,0.025,0.97}, panel={0.075,0.085,0.050,0.96}, rowA={0.105,0.115,0.070,0.94}, rowB={0.060,0.070,0.040,0.94}, accent={0.48,0.62,0.25,1.0}, silver={0.72,0.74,0.64,1.0}, bronze={0.62,0.47,0.24,1.0}, text={0.83,0.82,0.67,1.0}, muted={0.53,0.55,0.43,1.0}, line={0.24,0.30,0.14,0.90}, live={0.56,0.72,0.30,1.0} },
}

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

local function sandboxRoot()
    local canonical = SandboxVars and SandboxVars.SurvivorLeagueCommunity or {}
    local legacy = SandboxVars and SandboxVars.SurvivorLeague or nil
    if SurvivorLeagueCommunity.USE_LEGACY_SETTINGS == true
        and canonical.LegacyMeeksSettingsFallback ~= false
        and type(legacy) == "table" then
        return legacy
    end
    return canonical
end

function SurvivorLeagueCommunity.getJoinAnnouncements()
    local root = sandboxRoot()
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
    local root = sandboxRoot()
    local options = {
        enabled = root.Enabled ~= false,
        interfaceKey = math.max(0, math.min(255, tonumber(root.InterfaceKey) or 64)),
        interfaceTheme = math.max(1, math.min(3, tonumber(root.InterfaceTheme) or 1)),
        interfaceTitle = cleanSandboxString(root.InterfaceTitle) or "",
        interfaceSubtitle = cleanSandboxString(root.InterfaceSubtitle) or "COMMAND CENTER",
        allowPlayerThemeOverride = root.AllowPlayerThemeOverride == true,
        legacyMeeksSettingsFallback = root.LegacyMeeksSettingsFallback ~= false,
        seasonDays = math.max(1, tonumber(root.SeasonDays) or 7),
        minimumKills = math.max(0, tonumber(root.MinimumKills) or 25),
        -- Retained for saved Sandbox preset compatibility. Pagination now
        -- deliberately exposes every registered score, so this value is not
        -- used to truncate server results.
        deprecatedLeaderboardSize = math.max(3, tonumber(root.LeaderboardSize) or 10),
        leaderboardSize = math.max(3, tonumber(root.LeaderboardSize) or 10),
        nameFormat = math.max(1, math.min(3, tonumber(root.NameFormat) or 1)),
        allowClientKillReports = root.AllowClientKillReports == true,
        clientKillReportIntervalSeconds = math.max(1, tonumber(root.ClientKillReportIntervalSeconds) or 15),
        clientKillMaxPerMinute = math.max(1, tonumber(root.ClientKillMaxPerMinute) or 120),
        clientReportMinimumSeconds = math.max(1, tonumber(root.ClientKillReportIntervalSeconds) or 15),
        maximumClientKillDelta = 500,
        maximumRewardItemCount = 100,
        allowClientDeathReports = root.AllowClientDeathReports == true,
        deathAnnouncements = root.DeathAnnouncements ~= false,
        deathChatAnnouncements = root.DeathChatAnnouncements ~= false,
        deathHaloAnnouncements = root.DeathHaloAnnouncements == true,
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

function SurvivorLeagueCommunity.getAppearance(player)
    local options = SurvivorLeagueCommunity.getOptions()
    local selected = options.interfaceTheme
    if options.allowPlayerThemeOverride and player and player.getModData then
        local data = player:getModData()
        local override = tonumber(data and data.SurvivorLeagueCommunityTheme)
        if override and SurvivorLeagueCommunity.THEMES[override] then selected = override end
    end
    local palette = SurvivorLeagueCommunity.THEMES[selected] or SurvivorLeagueCommunity.THEMES[1]
    local title = options.interfaceTitle ~= "" and options.interfaceTitle or palette.title
    local subtitle = options.interfaceSubtitle ~= "" and options.interfaceSubtitle or "COMMAND CENTER"
    return { index=selected, id=palette.id, title=title, subtitle=subtitle, palette=palette, allowOverride=options.allowPlayerThemeOverride }
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
