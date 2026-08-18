local announcedConnections = {}
local lastJoinMessageIndex = nil

require "SurvivorLeagueCommunity_Config"

local SL = SurvivorLeagueCommunity
local runtime = {}
local pollTicks = 0
local announceDeath
local announceKills
local hoursSurvived
local recentDeaths = {}
local MAX_CLIENT_KILL_DELTA = 500 -- absolute emergency ceiling; time-based limits are stricter

local function replaceName(template, name)
    return tostring(template or ""):gsub("{name}", function()
        return tostring(name or "Survivor")
    end)
end

local function randomJoinMessage(name)
    local config = SL.getJoinAnnouncements()
    local messages = config.messages or {}

    if #messages == 0 then return nil end

    local index = ZombRand and (ZombRand(#messages) + 1) or math.random(#messages)

    if #messages > 1 and index == lastJoinMessageIndex then
        index = (index % #messages) + 1
    end

    lastJoinMessageIndex = index

    local message = replaceName(messages[index], name)
    local prefix = tostring(config.prefix or "")

    if prefix ~= "" then
        message = "[" .. prefix .. "] " .. message
    end

    return message
end

local function announceJoin(player)
    local config = SL.getJoinAnnouncements()
    if config.enabled == false or not player then return end

    local key = SL.playerKey(player)
    if not key then return end

    local now = SL.now()
    local cooldown = math.max(0, tonumber(config.duplicateCooldownSeconds) or 60)
    local lastAnnounced = tonumber(announcedConnections[key]) or 0
    if lastAnnounced > 0 and (now - lastAnnounced) < cooldown then return end

    local message = randomJoinMessage(player:getDisplayName())
    if not message or message == "" then return end

    announcedConnections[key] = now

    print("[SurvivorLeagueCommunityJoin] " .. message)

    sendServerCommand(SurvivorLeagueCommunity.MODULE, "JoinAnnouncement", {
        message = message,
        username = key,
    })
end

local function resetStreak(record)
    record.streakKills = 0
    record.streakMilestonesGranted = {}
end

local function data()
    local d = ModData.getOrCreate(SL.DATA_KEY)
    d.version = d.version or SL.VERSION
    d.seasonId = d.seasonId or 1
    d.startedAt = d.startedAt or SL.now()
    d.endsAt = d.endsAt or (d.startedAt + SL.getOptions().seasonDays * 86400)
    d.scores = d.scores or {}
    d.pending = d.pending or {}
    d.history = d.history or {}
    return d
end

local function safeKills(player)
    local ok, value = pcall(function() return player:getZombieKills() end)
    if not ok then return 0 end
    return math.max(0, tonumber(value) or 0)
end

local function characterName(player)
    local fallback = tostring(player and player:getDisplayName() or "unknown")
    local ok, value = pcall(function()
        local descriptor = player:getDescriptor()
        local first = tostring(descriptor:getForename() or "")
        local last = tostring(descriptor:getSurname() or "")
        local full = (first .. " " .. last):gsub("^%s+", ""):gsub("%s+$", "")
        if full ~= "" then return full end
        return fallback
    end)
    if ok and value and tostring(value) ~= "" then return tostring(value) end
    return fallback
end

local function recordFor(player)
    local key = SL.playerKey(player)
    if not key then return nil, nil end
    local d = data()
    local r = d.scores[key]
    if not r then
        r = { username = key, displayName = tostring(player:getDisplayName() or key), kills = 0, totalKills = 0 }
        d.scores[key] = r
    end
    if r.totalKills == nil then r.totalKills = tonumber(r.kills) or 0 end
    if r.streakKills == nil then r.streakKills = 0 end
    r.streakMilestonesGranted = r.streakMilestonesGranted or {}
    r.displayName = tostring(player:getDisplayName() or key)
    return key, r
end

local function sortedScores()
    local rows = {}
    for _, r in pairs(data().scores) do
        rows[#rows + 1] = { username = r.username, displayName = r.displayName, kills = tonumber(r.kills) or 0, totalKills = tonumber(r.totalKills) or tonumber(r.kills) or 0 }
    end
    table.sort(rows, function(a, b)
        if a.kills == b.kills then return a.username < b.username end
        return a.kills > b.kills
    end)
    return rows
end

local function parseItems(spec)
    local items = {}
    for token in string.gmatch(tostring(spec or ""), "[^,;]+") do
        local itemType, count = token:match("^%s*([%w_%.%-]+)%s*:%s*(%d+)%s*$")
        if itemType then items[#items + 1] = { itemType = itemType, count = math.max(1, tonumber(count) or 1) } end
    end
    return items
end

local function queueWinner(row, place, opts)
    local d = data()
    d.pending[row.username] = d.pending[row.username] or {}
    d.pending[row.username][#d.pending[row.username] + 1] = {
        seasonId = d.seasonId,
        place = place,
        kills = row.kills,
        items = parseItems(opts.items[place]),
        xp = opts.xp[place] or 0,
        xpPerk = opts.xpPerk,
        addTrait = opts.addTrait[place] or "",
        removeTrait = opts.removeTrait[place] or "",
    }
end

local function settleSeason()
    local d = data()
    local opts = SL.getOptions()
    local rows = sortedScores()
    local winners = {}
    for place = 1, math.min(3, #rows) do
        if rows[place].kills >= opts.minimumKills then
            queueWinner(rows[place], place, opts)
            winners[#winners + 1] = rows[place]
        end
    end
    d.history[#d.history + 1] = { seasonId = d.seasonId, startedAt = d.startedAt, endedAt = SL.now(), winners = winners }
    while #d.history > 12 do table.remove(d.history, 1) end
    d.seasonId = d.seasonId + 1
    d.startedAt = SL.now()
    d.endsAt = d.startedAt + opts.seasonDays * 86400
    for _, record in pairs(d.scores) do record.kills = 0 end
    runtime = {}
    ModData.transmit(SL.DATA_KEY)
    sendServerCommand(SL.MODULE, "SeasonSettled", { seasonId = d.seasonId - 1 })
end

local function changeTrait(player, traitId, add)
    if not traitId or traitId == "" then return end
    pcall(function()
        local trait = CharacterTrait.get(ResourceLocation.of(traitId))
        if not trait then return end
        local traits = player:getCharacterTraits()
        if add then traits:add(trait) else traits:remove(trait) end
    end)
end

local function checkKillMilestones(player, record)
    local milestones = SL.getOptions().killStreakRewards or {}
    record.streakMilestonesGranted = record.streakMilestonesGranted or {}
    for _, reward in ipairs(milestones) do
        local tierId = tonumber(reward.id) or 0
        local threshold = math.max(1, tonumber(reward.kills) or 1)
        if reward.enabled and (record.streakKills or 0) >= threshold and not record.streakMilestonesGranted[tierId] then
            record.streakMilestonesGranted[tierId] = true
            for _, item in ipairs(parseItems(reward.items)) do
                for _ = 1, item.count do
                    pcall(function() player:getInventory():AddItem(item.itemType) end)
                end
            end
            if (reward.xp or 0) > 0 and reward.xpPerk and reward.xpPerk ~= "" then
                pcall(function()
                    local perk = Perks.FromString(reward.xpPerk)
                    if perk then player:getXp():AddXP(perk, reward.xp) end
                end)
            end
            sendServerCommand(player, SL.MODULE, "MilestoneReward", {
                tier = tierId,
                threshold = threshold,
                items = reward.items,
                xp = reward.xp,
            })
        end
    end
end

local function grantPending(player)
    local key = SL.playerKey(player)
    local d = data()
    local pending = key and d.pending[key]
    if not pending or #pending == 0 then return end
    for _, reward in ipairs(pending) do
        for _, item in ipairs(reward.items or {}) do
            for _ = 1, item.count do
                pcall(function() player:getInventory():AddItem(item.itemType) end)
            end
        end
        if (reward.xp or 0) > 0 then
            pcall(function()
                local perk = Perks.FromString(reward.xpPerk)
                if perk then player:getXp():AddXP(perk, reward.xp) end
            end)
        end
        changeTrait(player, reward.removeTrait, false)
        changeTrait(player, reward.addTrait, true)
        sendServerCommand(player, SL.MODULE, "RewardGranted", reward)
    end
    d.pending[key] = nil
    ModData.transmit(SL.DATA_KEY)
end

local function observePlayer(player)
    local key, record = recordFor(player)
    if not key then return end
    local current = safeKills(player)
    local currentHours = hoursSurvived and hoursSurvived(player) or 0
    local state = runtime[key]
    if record.clientKillSync then
        if not state then
            runtime[key] = { lastKills = tonumber(record.lastClientKills) or 0, lastHours = currentHours, lastCharacter = characterName(player) }
            return
        end
        if currentHours < (state.lastHours or 0) then
            if announceDeath then
                recentDeaths[key] = SL.now()
                announceDeath(record, player, SL.getOptions(), state.lastHours, state.lastCharacter)
            end
            record.kills = 0
            record.lastClientKills = 0
            resetStreak(record)
        end
        state.lastHours = currentHours
        state.lastCharacter = characterName(player)
        return
    end
    if not state then
        local previous = tonumber(record.lastVanillaKills)
        if previous and current < previous then
            record.kills = 0
            resetStreak(record)
        elseif not previous and current < (tonumber(record.kills) or 0) then
            -- Migration repair for scores created before lastVanillaKills was
            -- persisted. A fresh survivor at zero cannot retain a larger score.
            record.kills = 0
            resetStreak(record)
        end
        record.lastVanillaKills = current
        runtime[key] = { lastKills = current, lastHours = currentHours, lastCharacter = characterName(player) }
        return
    end
    if current < state.lastKills or currentHours < (state.lastHours or 0) then
        -- A new survivor on the same account starts with lower vanilla stats.
        -- Announce the prior survivor when server OnPlayerDeath was missed.
        if announceDeath then
            recentDeaths[key] = SL.now()
            announceDeath(record, player, SL.getOptions(), state.lastHours, state.lastCharacter)
        end
        record.kills = 0
        resetStreak(record)
    elseif current > state.lastKills then
        local gained = current - state.lastKills
        record.kills = (record.kills or 0) + gained
        record.totalKills = (record.totalKills or 0) + gained
        record.streakKills = (record.streakKills or 0) + gained
        if announceKills then announceKills(key, record, player, gained) end
        checkKillMilestones(player, record)
    end
    state.lastKills = current
    state.lastHours = currentHours
    state.lastCharacter = characterName(player)
    record.lastVanillaKills = current
end

local function warnClientReport(key, reason, previous, submitted)
    print(
        "[SurvivorLeagueWarning] Rejected client report"
            .. " | Username: " .. tostring(key or "unknown")
            .. " | Previous: " .. tostring(previous)
            .. " | Submitted: " .. tostring(submitted)
            .. " | Reason: " .. tostring(reason)
    )
end

local function observeReportedKills(player, reported)
    local opts = SL.getOptions()
    if not opts.enabled or not opts.allowClientKillReports then return end

    local key, record = recordFor(player)
    if not key then return end

    local current = math.max(0, math.floor(tonumber(reported) or 0))
    local previous = tonumber(record.lastClientKills)
    local now = SL.now()
    local state = runtime[key] or {}
    local lastReportAt = tonumber(state.lastClientReportAt)

    record.clientKillSync = true

    -- The first accepted report establishes a baseline. Existing character
    -- kills must never be imported as new league kills or milestone progress.
    if previous == nil then
        record.lastClientKills = current
        record.lastVanillaKills = current
        state.lastKills = current
        state.lastHours = hoursSurvived and hoursSurvived(player) or 0
        state.lastCharacter = characterName(player)
        state.lastClientReportAt = now
        runtime[key] = state
        return
    end

    if current < previous then
        record.kills = 0
        resetStreak(record)
        record.lastClientKills = current
        record.lastVanillaKills = current
        state.lastKills = current
        state.lastHours = hoursSurvived and hoursSurvived(player) or 0
        state.lastCharacter = characterName(player)
        state.lastClientReportAt = now
        runtime[key] = state
        ModData.transmit(SL.DATA_KEY)
        return
    end

    local gained = current - previous
    if gained <= 0 then return end

    local elapsed = lastReportAt and math.max(0, now - lastReportAt) or opts.clientKillReportIntervalSeconds
    if elapsed < opts.clientKillReportIntervalSeconds then
        warnClientReport(key, "rate limit", previous, current)
        return
    end

    local timeLimit = math.max(1, math.ceil(opts.clientKillMaxPerMinute * elapsed / 60))
    local allowed = math.min(MAX_CLIENT_KILL_DELTA, timeLimit)
    if gained > allowed then
        warnClientReport(key, "implausible delta; allowed " .. tostring(allowed), previous, current)
        return
    end

    record.lastClientKills = current
    record.lastVanillaKills = current
    record.kills = (record.kills or 0) + gained
    record.totalKills = (record.totalKills or 0) + gained
    record.streakKills = (record.streakKills or 0) + gained
    if announceKills then announceKills(key, record, player, gained) end
    checkKillMilestones(player, record)

    state.lastKills = current
    state.lastHours = hoursSurvived and hoursSurvived(player) or 0
    state.lastCharacter = characterName(player)
    state.lastClientReportAt = now
    runtime[key] = state
    ModData.transmit(SL.DATA_KEY)
end

hoursSurvived = function(player)
    local ok, value = pcall(function() return player:getHoursSurvived() end)
    if not ok then return 0 end
    return math.max(0, tonumber(value) or 0)
end

local function survivalText(hours)
    local rawHours = math.max(0, tonumber(hours) or 0)
    local totalMinutes = math.floor(rawHours * 60)
    local totalHours = math.floor(totalMinutes / 60)
    local days = math.floor(totalHours / 24)
    local hoursLeft = totalHours % 24
    local minutesLeft = totalMinutes % 60
    if days > 0 then return tostring(days) .. "d " .. tostring(hoursLeft) .. "h " .. tostring(minutesLeft) .. "m" end
    if totalHours > 0 then return tostring(totalHours) .. "h " .. tostring(minutesLeft) .. "m" end
    return tostring(minutesLeft) .. "m"
end

announceKills = function(key, record, player, gained)
    gained = math.max(0, tonumber(gained) or 0)
    if gained <= 0 then return end
    local parts = {
        "[SURVIVOR LEAGUE // KILL DELTA]",
        "Username: " .. tostring(key or record.username or "unknown"),
        "Character: " .. characterName(player),
        "Kills Gained: " .. tostring(gained),
        "Season Kills: " .. tostring(record.kills or 0),
        "Total Kills: " .. tostring(record.totalKills or 0),
    }
    print("[SurvivorLeagueKill] " .. table.concat(parts, " | "))
end

announceDeath = function(record, player, opts, survivedOverride, characterOverride)
    local survived = tonumber(survivedOverride)
    if survived == nil then survived = hoursSurvived(player) end
    if not opts.deathAnnouncements or survived < opts.deathMinimumHours then return end
    local deathText = tostring(characterOverride or characterName(player)) .. " died"
    if opts.deathIncludeSurvivalTime then
        deathText = deathText .. " after surviving " .. survivalText(survived)
    end
    local parts = { "[" .. opts.deathPrefix .. "]", deathText }
    if opts.deathIncludeSeasonKills then parts[#parts + 1] = "Season Kills: " .. tostring(record.kills or 0) end
    if opts.deathIncludeTotalKills then parts[#parts + 1] = "Total Kills: " .. tostring(record.totalKills or 0) end
    local message = table.concat(parts, " | ")

print("[SurvivorLeagueDeath] " .. message)

sendServerCommand(SL.MODULE, "DeathAnnouncement", {
    message = message,
})
end

local function onPlayerDeath(player, survivedOverride)
    if not SL.getOptions().enabled then return end
    local key, record = recordFor(player)
    local now = SL.now()
    if key and recentDeaths[key] and now - recentDeaths[key] < 10 then return end
    if key then recentDeaths[key] = now end
    if record then
        announceDeath(record, player, SL.getOptions(), survivedOverride)
        record.kills = 0
        record.lastVanillaKills = 0
        record.lastClientKills = nil
        resetStreak(record)
    end
    if key then runtime[key] = nil end
    ModData.transmit(SL.DATA_KEY)
    sendServerCommand(SL.MODULE, "ScoreReset", { username = key })
end

local function rewardSummary(place, opts)
    local parts = {}
    if (opts.xp[place] or 0) > 0 then parts[#parts + 1] = tostring(opts.xp[place]) .. " XP" end
    local items = parseItems(opts.items[place])
    for i = 1, math.min(2, #items) do
        local shortName = tostring(items[i].itemType):gsub("^.-%.", "")
        parts[#parts + 1] = shortName .. " x" .. tostring(items[i].count)
    end
    if #parts == 0 then return "No reward configured" end
    return table.concat(parts, " + ")
end

local function sendBoard(player)
    -- Hosted co-op builds do not always emit server OnPlayerUpdate reliably.
    -- Refresh here so requesting the board also registers and syncs the player.
    observePlayer(player)
    local d = data()
    local rows = sortedScores()
    local opts = SL.getOptions()
    local payload = {
        seasonId = d.seasonId, endsAt = d.endsAt,
        username = SL.playerKey(player),
        rewards = { rewardSummary(1, opts), rewardSummary(2, opts), rewardSummary(3, opts) },
        rows = {},
    }
    for i = 1, #rows do payload.rows[i] = rows[i] end
    sendServerCommand(player, SL.MODULE, "Leaderboard", payload)
end

local function isAdmin(player)
    local level = tostring(player and player:getAccessLevel() or ""):lower()
    return level == "admin" or level == "moderator" or level == "overseer"
end

local function onClientCommand(module, command, player, args)
    if module ~= SL.MODULE then return end
    local opts = SL.getOptions()
    if not opts.enabled then return end

    if command == "RequestLeaderboard" then sendBoard(player) end
    if command == "ReportKills" then observeReportedKills(player, args and args.kills) end
    if command == "SettleNow" and isAdmin(player) then settleSeason() end
    if command == "ReportDeath" and opts.allowClientDeathReports then
        local verifiedDead = false
        pcall(function() verifiedDead = player:isDead() == true end)
        if verifiedDead then
            onPlayerDeath(player, tonumber(args and args.survived))
        else
            warnClientReport(SL.playerKey(player), "unverified death report", "alive", "dead")
        end
    end
    if command == "PlayerReady" then
        grantPending(player)
        announceJoin(player)
        sendServerCommand(player, SL.MODULE, "PlayerReadyAck", {})
    end
end

local function onPlayerUpdate(player)
 if player then grantPending(player) end
    if not SL.getOptions().enabled then return end
    pollTicks = pollTicks + 1
    if pollTicks % 120 ~= 0 then return end
    observePlayer(player)
    if SL.now() >= data().endsAt then settleSeason() end
end

local function onConnected(playerIndex, player)
    if not SL.getOptions().enabled then return end
    local p = player or (getSpecificPlayer and getSpecificPlayer(playerIndex))

    if p then
        grantPending(p)
        announceJoin(p)
    end
end

Events.OnClientCommand.Add(onClientCommand)
Events.OnPlayerUpdate.Add(onPlayerUpdate)
if Events.OnPlayerDeath then Events.OnPlayerDeath.Add(onPlayerDeath) end
if Events.OnCreatePlayer then Events.OnCreatePlayer.Add(onConnected) end
Events.OnInitGlobalModData.Add(function() data() end)
