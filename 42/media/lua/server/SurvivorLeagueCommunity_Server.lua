local announcedConnections = {}
local lastJoinMessageIndex = nil

require "SurvivorLeagueCommunity_Config"
require "SurvivorLeagueCommunity_Localization"

local SL = SurvivorLeagueCommunity
local runtime = {}
local announceDeath
local announceKills
local hoursSurvived
local displayNameFor
local recentDeaths = {}
local clientKillReportTimes = {}
local clientDeathReportTimes = {}
local leaderboardRequestTimes = {}
local compatibleClients = {}
local sessionTokens = {}
local reportSequences = {}
local serverPollTicks = {}
local pendingRewardPollTicks = {}
local invalidRewardTokensLogged = {}
local leaderboardQueue = {}
local leaderboardQueueOrder = {}
local leaderboardQueueWindow = { second = -1, processed = 0 }

-- Project Zomboid can load Lua before the multiplayer transport is ready.
-- Keep every notification best-effort so an early startup event never aborts
-- season initialization or reward persistence.
local function safeServerCommand(...)
    if type(sendServerCommand) ~= "function" then return false end
    local ok, err = pcall(sendServerCommand, ...)
    if not ok then
        print("[SurvivorLeagueCommunityWarning] Deferred server command: " .. tostring(err))
        return false
    end
    return true
end

local function utf8Prefix(value, maximumCharacters)
    local text, index, count, last = tostring(value or ""), 1, 0, 0
    while index <= #text and count < maximumCharacters do
        local byte = text:byte(index)
        local width = byte < 0x80 and 1 or (byte < 0xE0 and 2 or (byte < 0xF0 and 3 or 4))
        if index + width - 1 > #text then break end
        last, index, count = index + width - 1, index + width, count + 1
    end
    return text:sub(1, last), index <= #text
end

local function sanitizeName(value)
    local text = tostring(value or "Survivor"):gsub("[%c]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then text = "Survivor" end
    local prefix, truncated = utf8Prefix(text, 48)
    if truncated then prefix = utf8Prefix(text, 45) .. "..." end
    text = prefix
    return text
end

local function radioEvent(kind, text, source)
    if MeeksRadio and MeeksRadio.ServerAPI and MeeksRadio.ServerAPI.broadcast then
        pcall(MeeksRadio.ServerAPI.broadcast, 101200, kind, text, source or "SurvivorLeagueCommunity")
    end
end

local function rewardWarning(player, category, value, detail)
    print(
        "[SurvivorLeagueCommunityRewardWarning]"
            .. " | Username: " .. tostring(SL.playerKey(player) or "unknown")
            .. " | Category: " .. tostring(category or "unknown")
            .. " | Value: " .. tostring(value or "")
            .. " | Reason: " .. tostring(detail or "delivery failed")
    )
end

local function newSessionToken(key)
    local random = ZombRand and ZombRand(1000000000) or math.random(1, 999999999)
    return tostring(SL.now()) .. ":" .. tostring(random) .. ":" .. tostring(key or "player")
end

local function validateClientReport(player, args, command)
    local key = SL.playerKey(player)
    local token = tostring(args and args.token or "")
    local sequence = math.floor(tonumber(args and args.sequence) or 0)
    if not key or token == "" or token ~= sessionTokens[key] then
        print("[SurvivorLeagueCommunitySecurity] Rejected report | user="..tostring(key).." | command="..tostring(command).." | reason=invalid-token")
        return false
    end
    if sequence <= (tonumber(reportSequences[key]) or 0) then
        print("[SurvivorLeagueCommunitySecurity] Rejected report | user="..tostring(key).." | command="..tostring(command).." | reason=replayed-sequence")
        return false
    end
    reportSequences[key] = sequence
    return true
end

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

    local message = randomJoinMessage(displayNameFor(player, SL.getOptions().nameFormat))
    if not message or message == "" then return end

    announcedConnections[key] = now

    print("[SurvivorLeagueCommunityJoin] " .. message)

    safeServerCommand(SurvivorLeagueCommunity.MODULE, "JoinAnnouncement", {
        message = message,
        username = key,
    })
end

local function resetStreak(record)
    record.streakKills = 0
    record.streakMilestonesGranted = {}
    record.streakMilestoneDelivery = {}
end

local function copyValue(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do result[copyValue(key, seen)] = copyValue(child, seen) end
    return result
end

local function existingModData(key)
    if not ModData or not ModData.get then return nil end
    local ok, value = pcall(ModData.get, key)
    return ok and value or nil
end

local function tableHasEntries(value)
    if type(value) ~= "table" then return false end
    for _ in pairs(value) do return true end
    return false
end

local function activeDataset(value)
    if type(value) ~= "table" then return false end
    if tableHasEntries(value.scores) then return true end
    if tableHasEntries(value.pending) then return true end
    if tableHasEntries(value.history) then return true end
    return value.seasonId ~= nil or value.startedAt ~= nil or value.endsAt ~= nil
end

local function migrationScore(value)
    return math.max(0, math.min(2147483647, math.floor(tonumber(value) or 0)))
end

local migrationChecked = false
local function migrateLegacyMeeks(canonical)
    if migrationChecked then return end
    migrationChecked = true
    if canonical.legacyReconciliationVersion then
        SurvivorLeagueCommunity.USE_LEGACY_SETTINGS = canonical.useLegacyMeeksSettings == true
        return
    end
    local legacy = existingModData("SurvivorLeagueData")
    local canonicalActive, legacyActive = activeDataset(canonical), activeDataset(legacy)
    if not legacyActive then
        canonical.legacyReconciliationVersion = 1
        canonical.legacyReconciledAt = SL.now()
        canonical.legacyReconciliationSummary = { imported = 0, baselined = 0, duplicate = 0, canonicalNewer = 0, review = 0 }
        print("[SurvivorLeagueCommunityMigration] COMPLETE no active legacy dataset was found; one-time reconciliation marker saved")
        return
    end
    if not canonicalActive and legacyActive then
        for key, value in pairs(legacy) do canonical[key] = copyValue(value) end
        canonical.migratedFrom = "SurvivorLeagueData"
        canonical.migrationVersion = 1
        canonical.migratedAt = SL.now()
        canonical.legacyReconciliationVersion = 1
        canonical.legacyReconciledAt = canonical.migratedAt
        canonical.useLegacyMeeksSettings = true
        SurvivorLeagueCommunity.USE_LEGACY_SETTINGS = true
        local count = 0
        for _ in pairs(canonical.scores or {}) do count = count + 1 end
        canonical.legacyReconciliationSummary = { imported = count, baselined = 0, duplicate = 0, canonicalNewer = 0, review = 0 }
        print("[SurvivorLeagueCommunityMigration] SUCCESS imported "..tostring(count).." records from SurvivorLeagueData; legacy data was preserved")
        return
    end

    -- Both datasets are active. Reconcile them once without ever deleting or
    -- modifying the legacy table. Full score snapshots make the operation
    -- auditable and recoverable from the server save.
    canonical.scores = canonical.scores or {}
    local legacyScores = type(legacy.scores) == "table" and legacy.scores or {}
    local runAt = SL.now()
    canonical.legacyReconciliationBackupV1 = {
        createdAt = runAt,
        canonicalScores = copyValue(canonical.scores),
        legacyScores = copyValue(legacyScores),
    }

    local function identity(value)
        return string.lower(sanitizeName(value or ""))
    end

    local canonicalByIdentity = {}
    for key, record in pairs(canonical.scores) do
        record = type(record) == "table" and record or {}
        canonicalByIdentity[identity(record.username or key)] = { key = key, record = record }
        canonicalByIdentity[identity(key)] = { key = key, record = record }
    end

    local summary = { imported = 0, baselined = 0, duplicate = 0, canonicalNewer = 0, review = 0 }
    local review = {}
    for legacyKey, legacyRecord in pairs(legacyScores) do
        legacyRecord = type(legacyRecord) == "table" and legacyRecord or {}
        local legacyUsername = legacyRecord.username or legacyKey
        local match = canonicalByIdentity[identity(legacyUsername)] or canonicalByIdentity[identity(legacyKey)]

        if not match then
            local imported = copyValue(legacyRecord)
            imported.username = imported.username or legacyKey
            imported.displayName = imported.displayName or imported.username
            imported.kills = migrationScore(imported.kills)
            imported.totalKills = migrationScore(imported.totalKills or imported.kills)
            imported.streakKills = migrationScore(imported.streakKills)
            imported.bestStreak = migrationScore(imported.bestStreak)
            canonical.scores[legacyKey] = imported
            canonicalByIdentity[identity(imported.username)] = { key = legacyKey, record = imported }
            canonicalByIdentity[identity(legacyKey)] = { key = legacyKey, record = imported }
            summary.imported = summary.imported + 1
            print("[SurvivorLeagueCommunityMigration] IMPORTED legacy-only player | user=" .. tostring(imported.username)
                .. " | season=" .. tostring(imported.kills) .. " | total=" .. tostring(imported.totalKills))
        else
            local current = match.record
            local currentSeason = migrationScore(current.kills)
            local currentTotal = migrationScore(current.totalKills or current.kills)
            local currentHistorical = math.max(0, currentTotal - currentSeason)
            local legacySeason = migrationScore(legacyRecord.kills)
            local legacyTotal = migrationScore(legacyRecord.totalKills or legacyRecord.kills)

            if currentSeason == legacySeason and currentTotal == legacyTotal then
                summary.duplicate = summary.duplicate + 1
            elseif currentHistorical >= legacyTotal then
                summary.canonicalNewer = summary.canonicalNewer + 1
            elseif legacySeason == 0 and legacyTotal > currentHistorical then
                local correctedTotal = migrationScore(legacyTotal + currentSeason)
                current.totalKills = correctedTotal
                current.bestStreak = math.max(migrationScore(current.bestStreak), migrationScore(legacyRecord.bestStreak))
                current.legacyBaselineImported = legacyTotal
                current.legacyBaselineImportedAt = runAt
                summary.baselined = summary.baselined + 1
                print("[SurvivorLeagueCommunityMigration] BASELINED player | user=" .. tostring(current.username or match.key)
                    .. " | historical=" .. tostring(currentHistorical) .. "->" .. tostring(legacyTotal)
                    .. " | season=" .. tostring(currentSeason) .. " | total=" .. tostring(currentTotal) .. "->" .. tostring(correctedTotal))
            else
                summary.review = summary.review + 1
                review[#review + 1] = {
                    username = tostring(current.username or match.key),
                    canonicalSeason = currentSeason,
                    canonicalTotal = currentTotal,
                    legacySeason = legacySeason,
                    legacyTotal = legacyTotal,
                }
                print("[SurvivorLeagueCommunityMigration] REVIEW ambiguous overlap; no score changed | user="
                    .. tostring(current.username or match.key)
                    .. " | canonicalSeason=" .. tostring(currentSeason) .. " | canonicalTotal=" .. tostring(currentTotal)
                    .. " | legacySeason=" .. tostring(legacySeason) .. " | legacyTotal=" .. tostring(legacyTotal))
            end
        end
    end

    canonical.legacyReconciliationReview = review
    canonical.legacyReconciliationSummary = summary
    canonical.legacyReconciliationVersion = 1
    canonical.legacyReconciledAt = runAt
    canonical.migrationConflict = summary.review > 0
    canonical.migrationConflictAt = summary.review > 0 and runAt or nil
    print("[SurvivorLeagueCommunityMigration] COMPLETE one-time reconciliation"
        .. " | imported=" .. tostring(summary.imported)
        .. " | baselined=" .. tostring(summary.baselined)
        .. " | duplicate=" .. tostring(summary.duplicate)
        .. " | canonicalNewer=" .. tostring(summary.canonicalNewer)
        .. " | review=" .. tostring(summary.review)
        .. " | legacy data preserved")
end

local function data()
    local d = ModData.getOrCreate(SL.DATA_KEY)
    migrateLegacyMeeks(d)
    d.version = SL.VERSION
    d.seasonId = d.seasonId or 1
    d.startedAt = d.startedAt or SL.now()
    d.endsAt = d.endsAt or (d.startedAt + SL.getOptions().seasonDays * 86400)
    d.scores = d.scores or {}
    d.pending = d.pending or {}
    d.history = d.history or {}
    d.archive = d.archive or {}
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

local function accountName(player)
    local ok, value = pcall(function() return player and player:getUsername() end)
    if ok and value and tostring(value) ~= "" then return tostring(value) end
    return tostring(player and player:getDisplayName() or "unknown")
end

displayNameFor = function(player, mode, characterOverride)
    local account = sanitizeName(accountName(player))
    local character = sanitizeName(characterOverride or characterName(player))
    mode = math.max(1, math.min(3, tonumber(mode) or 1))
    if mode == 2 then return account end
    if mode == 3 and character ~= account then return character .. " (" .. account .. ")" end
    return character
end

local function recordFor(player)
    local key = SL.playerKey(player)
    if not key then return nil, nil end
    local d = data()
    local r = d.scores[key]
    if not r then
        r = { username = key, displayName = displayNameFor(player, SL.getOptions().nameFormat), kills = 0, totalKills = 0 }
        d.scores[key] = r
    end
    if r.totalKills == nil then r.totalKills = tonumber(r.kills) or 0 end
    if r.streakKills == nil then r.streakKills = 0 end
    r.streakMilestonesGranted = r.streakMilestonesGranted or {}
    r.streakMilestoneDelivery = r.streakMilestoneDelivery or {}
    r.displayName = displayNameFor(player, SL.getOptions().nameFormat)
    r.lastSeenAt = SL.now()
    return key, r
end

local function sortedScores()
    local rows = {}
    for _, r in pairs(data().scores) do
        rows[#rows + 1] = {
            username = sanitizeName(r.username),
            displayName = sanitizeName(r.displayName),
            kills = tonumber(r.kills) or 0,
            totalKills = tonumber(r.totalKills) or tonumber(r.kills) or 0,
            streakKills = tonumber(r.streakKills) or 0,
            bestStreak = tonumber(r.bestStreak) or tonumber(r.streakKills) or 0,
        }
    end
    local tiePolicy = SL.getOptions().seasonTiePolicy
    table.sort(rows, function(a, b)
        if a.kills == b.kills then
            if tiePolicy == 2 and a.totalKills ~= b.totalKills then return a.totalKills > b.totalKills end
            if tiePolicy == 3 and a.bestStreak ~= b.bestStreak then return a.bestStreak > b.bestStreak end
            return string.lower(a.username) < string.lower(b.username)
        end
        return a.kills > b.kills
    end)
    return rows
end

local function parseItems(spec, maximumCount, context)
    local items = {}
    local limit = math.max(1, tonumber(maximumCount) or 100)
    for token in string.gmatch(tostring(spec or ""), "[^,;]+") do
        local itemType, count = token:match("^%s*([%w_%.%-]+)%s*:%s*(%d+)%s*$")
        if itemType then
            local requested = math.max(1, tonumber(count) or 1)
            if requested > limit then
                print("[SurvivorLeagueCommunityWarning] Clamped reward quantity for " .. tostring(itemType) .. " from " .. tostring(requested) .. " to " .. tostring(limit))
            end
            items[#items + 1] = { itemType = itemType, count = math.min(requested, limit) }
        else
            local invalid = tostring(token or ""):match("^%s*(.-)%s*$") or ""
            local warningKey = tostring(context or "reward") .. "|" .. invalid
            if invalid ~= "" and not invalidRewardTokensLogged[warningKey] then
                invalidRewardTokensLogged[warningKey] = true
                print("[SurvivorLeagueRewardError] Ignored malformed item token '" .. invalid
                    .. "' in " .. tostring(context or "reward") .. "; expected Module.Item:quantity")
            end
        end
    end
    return items
end

local function validateItems(items, context)
    for _, item in ipairs(items or {}) do
        local ok, scriptItem = pcall(function()
            return ScriptManager and ScriptManager.instance and ScriptManager.instance:getItem(item.itemType)
        end)
        if not ok or not scriptItem then
            print("[SurvivorLeagueRewardError] Invalid item " .. tostring(item.itemType) .. " in " .. tostring(context or "reward"))
            return false
        end
    end
    return true
end

local function resolvePerk(perkName, xp, context)
    if (tonumber(xp) or 0) <= 0 then return true, nil end
    if not perkName or perkName == "" then
        print("[SurvivorLeagueRewardError] Missing XP perk in " .. tostring(context or "reward"))
        return false, nil
    end
    local ok, perk = pcall(function() return Perks.FromString(perkName) end)
    if not ok or not perk then
        print("[SurvivorLeagueRewardError] Invalid XP perk " .. tostring(perkName) .. " in " .. tostring(context or "reward"))
        return false, nil
    end
    return true, perk
end

local function grantItems(player, items, progress, context)
    if not validateItems(items, context) then return false, progress or {} end
    local success = true
    progress = progress or {}
    for index, item in ipairs(items or {}) do
        local delivered = math.max(0, tonumber(progress[index]) or 0)
        for _ = delivered + 1, item.count do
            local ok, granted = pcall(function() return player:getInventory():AddItem(item.itemType) end)
            if not ok or not granted then
                success = false
                rewardWarning(player, "item", item.itemType, ok and "inventory rejected item" or granted)
                break
            end
            delivered = delivered + 1
            progress[index] = delivered
        end
    end
    return success, progress
end

local function grantXP(player, perkName, amount, context)
    amount = math.max(0, tonumber(amount) or 0)
    if amount <= 0 then return true end
    local valid, perk = resolvePerk(perkName, amount, context)
    if not valid then return false end
    local ok = pcall(function() player:getXp():AddXP(perk, amount) end)
    if not ok then rewardWarning(player, "perk", perkName, "XP delivery failed") end
    return ok
end

local function winnerReward(row, place, opts, seasonId)
    return {
        rewardId = "season:" .. tostring(seasonId) .. ":place:" .. tostring(place),
        seasonId = seasonId,
        place = place,
        kills = row.kills,
        items = parseItems(opts.items[place], opts.maximumRewardItemCount, "season "..tostring(seasonId).." place "..tostring(place)),
        xp = opts.xp[place] or 0,
        xpPerk = opts.xpPerk,
        addTrait = opts.addTrait[place] or "",
        removeTrait = opts.removeTrait[place] or "",
    }
end

local function queueWinner(d, row, place, reward)
    d.pending[row.username] = d.pending[row.username] or {}
    for _, existing in ipairs(d.pending[row.username]) do
        if existing.rewardId == reward.rewardId then return end
    end
    d.pending[row.username][#d.pending[row.username] + 1] = reward
end

local function settleSeason(reason, actor)
    local d = data()
    local opts = SL.getOptions()
    local rows = sortedScores()
    local winners = {}
    local rewards = {}
    local settlingSeason = d.seasonId
    print("[SurvivorLeagueCommunityAudit] Settlement started | season=" .. tostring(d.seasonId) .. " | reason=" .. tostring(reason or "timer") .. " | actor=" .. tostring(actor or "server") .. " | registered=" .. tostring(#rows))
    for place = 1, math.min(3, #rows) do
        if rows[place].kills >= opts.minimumKills then
            winners[#winners + 1] = rows[place]
            rewards[#rewards + 1] = { row = rows[place], place = place,
                reward = winnerReward(rows[place], place, opts, settlingSeason) }
        end
    end
    -- Persist an idempotent marker before mutating rewards/history. A retry
    -- after an interrupted save reuses stable reward IDs instead of duplicating them.
    d.settlementInProgress = settlingSeason
    ModData.transmit(SL.DATA_KEY)
    for _, queued in ipairs(rewards) do queueWinner(d, queued.row, queued.place, queued.reward) end
    for index = #d.history, 1, -1 do
        if tonumber(d.history[index].seasonId) == tonumber(settlingSeason) then table.remove(d.history, index) end
    end
    d.history[#d.history + 1] = { seasonId = settlingSeason, startedAt = d.startedAt, endedAt = SL.now(), winners = winners }
    while #d.history > 12 do table.remove(d.history, 1) end
    d.seasonId = d.seasonId + 1
    d.startedAt = SL.now()
    d.endsAt = d.startedAt + opts.seasonDays * 86400
    for _, record in pairs(d.scores) do record.kills = 0 end
    d.lastSettledSeason = settlingSeason
    d.settlementInProgress = nil
    runtime = {}
    ModData.transmit(SL.DATA_KEY)
    print("[SurvivorLeagueSeason] Settled Season #" .. tostring(d.seasonId - 1) .. "; Season #" .. tostring(d.seasonId) .. " ends at " .. tostring(d.endsAt))
    print("[SurvivorLeagueCommunityAudit] Settlement completed | settledSeason=" .. tostring(d.seasonId - 1) .. " | nextSeason=" .. tostring(d.seasonId) .. " | winners=" .. tostring(#winners) .. " | queuedWinnerRewards=" .. tostring(#winners))
    safeServerCommand(SL.MODULE, "SeasonSettled", { seasonId = d.seasonId - 1 })
    local podium = {}
    for place, row in ipairs(winners) do podium[#podium+1] = "#"..place.." "..tostring(row.name or row.username).." ("..tostring(row.kills)..")" end
    radioEvent("event", "Survivor League Season #"..tostring(d.seasonId-1).." results: "..(#podium>0 and table.concat(podium, ", ") or "no qualifying winners"), "SURVIVOR_LEAGUE_SEASON")
end

local seasonSettlementInProgress = false

local function checkSeasonSettlement(trigger)
    local opts = SL.getOptions()
    if not opts.enabled or seasonSettlementInProgress then return false end

    local d = data()
    local endsAt = tonumber(d.endsAt) or 0
    if endsAt > 0 and SL.now() < endsAt then return false end

    seasonSettlementInProgress = true
    print("[SurvivorLeagueCommunityAudit] Automatic settlement triggered | season=" .. tostring(d.seasonId) .. " | trigger=" .. tostring(trigger or "timer") .. " | endsAt=" .. tostring(endsAt))
    local ok, err = pcall(settleSeason, "automatic:" .. tostring(trigger or "timer"), "server")
    seasonSettlementInProgress = false
    if not ok then
        print("[SurvivorLeagueCommunityError] Season settlement failed: " .. tostring(err))
        return false
    end
    return true
end

local function resolveTrait(traitId)
    if not traitId or traitId == "" then return true, nil end
    local ok, trait = pcall(function()
        return CharacterTrait.get(ResourceLocation.of(traitId))
    end)
    if not ok or not trait then
        print("[SurvivorLeagueRewardError] Invalid trait " .. tostring(traitId))
        return false, nil
    end
    return true, trait
end

local function applyTrait(player, trait, add)
    if not trait then return true end
    local ok = pcall(function()
        local traits = player:getCharacterTraits()
        if add then traits:add(trait) else traits:remove(trait) end
    end)
    return ok
end

local function checkKillMilestones(player, record)
    local milestones = SL.getOptions().killStreakRewards or {}
    record.streakMilestonesGranted = record.streakMilestonesGranted or {}
    record.streakMilestoneDelivery = record.streakMilestoneDelivery or {}
    for _, reward in ipairs(milestones) do
        local tierId = tonumber(reward.id) or 0
        local threshold = math.max(1, tonumber(reward.kills) or 1)
        if reward.enabled and (record.streakKills or 0) >= threshold and not record.streakMilestonesGranted[tierId] then
            local context = "kill-streak tier " .. tostring(tierId)
            local delivery = record.streakMilestoneDelivery[tierId] or {}
            local now = SL.now()
            if (tonumber(delivery.nextRetryAt) or 0) > now then
                record.streakMilestoneDelivery[tierId] = delivery
            else
            if not delivery.items then
                delivery.items, delivery.itemProgress = grantItems(
                    player,
                    parseItems(reward.items, SL.getOptions().maximumRewardItemCount, context),
                    delivery.itemProgress,
                    context
                )
            end
            if not delivery.xp then delivery.xp = grantXP(player, reward.xpPerk, reward.xp, context) end
            record.streakMilestoneDelivery[tierId] = delivery
            if delivery.items and delivery.xp then
                record.streakMilestonesGranted[tierId] = true
                record.streakMilestoneDelivery[tierId] = nil
                safeServerCommand(player, SL.MODULE, "MilestoneReward", {
                    tier = tierId,
                    threshold = threshold,
                    items = reward.items,
                    xp = reward.xp,
                })
                radioEvent("community", tostring(player:getUsername()).." reached Survivor League milestone "..tostring(threshold).." kills.", "SURVIVOR_LEAGUE_MILESTONE")
            else
                delivery.nextRetryAt = now + 60
                rewardWarning(player, "milestone", tierId, "reward remains pending for retry")
            end
            end
        end
    end
end

local function grantPending(player)
    local key = SL.playerKey(player)
    local d = data()
    local pending = key and d.pending[key]
    if not pending or #pending == 0 then return end
    local remaining = {}
    for _, reward in ipairs(pending) do
        local now = SL.now()
        if (tonumber(reward.nextRetryAt) or 0) > now then
            remaining[#remaining + 1] = reward
        else
            local context = "season " .. tostring(reward.seasonId or "?") .. " place " .. tostring(reward.place or "?")
            local removeValid, removeTrait = resolveTrait(reward.removeTrait)
            local addValid, addTrait = resolveTrait(reward.addTrait)
            reward.delivery = reward.delivery or {}
            if not reward.delivery.items then
                reward.delivery.items, reward.delivery.itemProgress = grantItems(
                    player, reward.items or {}, reward.delivery.itemProgress, context
                )
            end
            if not reward.delivery.xp then reward.delivery.xp = grantXP(player, reward.xpPerk, reward.xp, context) end
            if not reward.delivery.removeTrait and removeValid then
                reward.delivery.removeTrait = applyTrait(player, removeTrait, false)
            end
            if not reward.delivery.addTrait and addValid then
                reward.delivery.addTrait = applyTrait(player, addTrait, true)
            end
            local delivered = reward.delivery.items and reward.delivery.xp
                and reward.delivery.removeTrait and reward.delivery.addTrait
            if delivered then
                reward.delivery = nil
                reward.nextRetryAt = nil
                safeServerCommand(player, SL.MODULE, "RewardGranted", reward)
            else
                reward.nextRetryAt = now + 60
                remaining[#remaining + 1] = reward
                rewardWarning(player, "podium reward", reward.place, "reward remains pending for retry")
            end
        end
    end
    d.pending[key] = #remaining > 0 and remaining or nil
    ModData.transmit(SL.DATA_KEY)
end

local function observePlayer(player)
    local key, record = recordFor(player)
    if not key then return end
    local current = safeKills(player)
    local currentHours = hoursSurvived and hoursSurvived(player) or 0
    local state = runtime[key]
    if record.clientKillSync and not SL.getOptions().allowClientKillReports then
        -- Resume server-first tracking without importing the current
        -- character's existing kills when hosted fallback is disabled.
        record.clientKillSync = nil
        record.lastClientKills = nil
        record.lastVanillaKills = current
        runtime[key] = {
            lastKills = current,
            lastHours = currentHours,
            lastCharacter = characterName(player),
        }
        return
    end
    if record.clientKillSync and SL.getOptions().allowClientKillReports then
        if not state then
            runtime[key] = { lastKills = tonumber(record.lastClientKills) or 0, lastHours = currentHours, lastCharacter = characterName(player) }
            return
        end
        if currentHours < (state.lastHours or 0) then
            if announceDeath then
                recentDeaths[key] = SL.now()
                announceDeath(record, player, SL.getOptions(), state.lastHours, state.lastCharacter)
            end
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
        resetStreak(record)
    elseif current > state.lastKills then
        local gained = current - state.lastKills
        record.kills = (record.kills or 0) + gained
        record.totalKills = (record.totalKills or 0) + gained
        record.streakKills = (record.streakKills or 0) + gained
        record.bestStreak = math.max(tonumber(record.bestStreak) or 0, record.streakKills)
        if announceKills then announceKills(key, record, player, gained) end
        checkKillMilestones(player, record)
    end
    state.lastKills = current
    state.lastHours = currentHours
    state.lastCharacter = characterName(player)
    record.lastVanillaKills = current
end

local function killReportAck(player, current, accepted, reason)
    safeServerCommand(player, SL.MODULE, "KillReportAck", {
        kills = math.max(0, math.floor(tonumber(current) or 0)),
        accepted = accepted == true,
        reason = tostring(reason or ""),
    })
end

local function observeReportedKills(player, reported, force)
    local key, record = recordFor(player)
    if not key then return end
    local opts = SL.getOptions()
    if not opts.allowClientKillReports then
        print("[SurvivorLeagueCommunityWarning] Rejected disabled client kill report for " .. tostring(key))
        killReportAck(player, reported, false, "disabled")
        return
    end

    local now = SL.now()
    local lastReport = tonumber(clientKillReportTimes[key]) or 0
    local verifiedDead = false
    if force == true then pcall(function() verifiedDead = player:isDead() == true end) end
    if not verifiedDead and lastReport > 0 and (now - lastReport) < opts.clientReportMinimumSeconds then
        print("[SurvivorLeagueCommunityWarning] Rejected rate-limited kill report for " .. tostring(key))
        killReportAck(player, reported, false, "rate-limited")
        return
    end

    local numericReport = tonumber(reported)
    if numericReport == nil then
        print("[SurvivorLeagueCommunityWarning] Rejected malformed kill report for " .. tostring(key))
        killReportAck(player, record.lastClientKills or 0, false, "malformed")
        return
    end
    local current = math.max(0, math.floor(numericReport))
    local previous = tonumber(record.lastClientKills)
    local gained = 0

    record.clientKillSync = true
    if previous == nil then
        -- The first accepted report establishes a baseline. Existing kills
        -- must never be imported as new league or milestone progress.
        gained = 0
    elseif current < previous then
        resetStreak(record)
    else
        gained = current - previous
    end

    local elapsed = lastReport > 0 and math.max(1, now - lastReport) or opts.clientReportMinimumSeconds
    local configuredLimit = math.max(1, math.ceil(opts.clientKillMaxPerMinute * elapsed / 60))
    local allowedDelta = math.min(opts.maximumClientKillDelta, configuredLimit)
    if gained > allowedDelta then
        print("[SurvivorLeagueCommunityWarning] Rejected implausible kill delta for " .. tostring(key) .. ": " .. tostring(gained) .. " (limit " .. tostring(allowedDelta) .. ")")
        -- Re-baseline without awarding the rejected increase so one suspicious
        -- report cannot permanently prevent later legitimate synchronization.
        record.lastClientKills = current
        record.lastVanillaKills = current
        clientKillReportTimes[key] = now
        killReportAck(player, current, false, "implausible-delta")
        return
    end

    clientKillReportTimes[key] = now
    record.lastClientKills = current
    record.lastVanillaKills = current
    if gained > 0 then
        record.kills = (record.kills or 0) + gained
        record.totalKills = (record.totalKills or 0) + gained
        record.streakKills = (record.streakKills or 0) + gained
        record.bestStreak = math.max(tonumber(record.bestStreak) or 0, record.streakKills)
        if announceKills then announceKills(key, record, player, gained) end
        checkKillMilestones(player, record)
    end

    local state = runtime[key] or {}
    state.lastKills = current
    state.lastHours = hoursSurvived and hoursSurvived(player) or 0
    state.lastCharacter = characterName(player)
    runtime[key] = state
    ModData.transmit(SL.DATA_KEY)
    killReportAck(player, current, true, "accepted")
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
        "Character: " .. sanitizeName(characterName(player)),
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
    local deathText = displayNameFor(player, opts.nameFormat, characterOverride) .. " died"
    if opts.deathIncludeSurvivalTime then
        deathText = deathText .. " after surviving " .. survivalText(survived)
    end
    local parts = { "[" .. opts.deathPrefix .. "]", deathText }
    if opts.deathIncludeSeasonKills then parts[#parts + 1] = "Season Kills: " .. tostring(record.kills or 0) end
    if opts.deathIncludeTotalKills then parts[#parts + 1] = "Total Kills: " .. tostring(record.totalKills or 0) end
    local message = table.concat(parts, " | ")

print("[SurvivorLeagueDeath] " .. message)

safeServerCommand(SL.MODULE, "DeathAnnouncement", {
    message = message,
    showChat = opts.deathChatAnnouncements,
    showHalo = opts.deathHaloAnnouncements,
})
end

local function captureFinalAuthoritativeKills(player, key, record)
    local opts = SL.getOptions()
    if record.clientKillSync and opts.allowClientKillReports then return end
    local current = safeKills(player)
    local state = runtime[key]
    local previous = state and tonumber(state.lastKills) or tonumber(record.lastVanillaKills)
    if previous ~= nil and current > previous then
        local gained = current - previous
        record.kills = (record.kills or 0) + gained
        record.totalKills = (record.totalKills or 0) + gained
        record.streakKills = (record.streakKills or 0) + gained
        record.bestStreak = math.max(tonumber(record.bestStreak) or 0, record.streakKills)
        if announceKills then announceKills(key, record, player, gained) end
        checkKillMilestones(player, record)
    end
    record.lastVanillaKills = current
    if state then state.lastKills = current end
end

local function onPlayerDeath(player)
    if not SL.getOptions().enabled then return end
    local key, record = recordFor(player)
    local now = SL.now()
    if key and recentDeaths[key] and now - recentDeaths[key] < 10 then return end
    if key then recentDeaths[key] = now end
    if record then
        captureFinalAuthoritativeKills(player, key, record)
        -- Survival time is always derived from the server player object.
        announceDeath(record, player, SL.getOptions())
        record.lastVanillaKills = 0
        record.lastClientKills = nil
        resetStreak(record)
    end
    if key then runtime[key] = nil end
    ModData.transmit(SL.DATA_KEY)
    safeServerCommand(SL.MODULE, "ScoreReset", { username = key })
end

local function onClientDeathReport(player, reportedKills)
    local opts = SL.getOptions()
    local key = SL.playerKey(player)
    if not key then return end
    if not opts.allowClientDeathReports then
        print("[SurvivorLeagueCommunityWarning] Rejected disabled client death report for " .. tostring(key))
        return
    end
    local now = SL.now()
    local lastReport = tonumber(clientDeathReportTimes[key]) or 0
    if lastReport > 0 and (now - lastReport) < opts.deathReportMinimumSeconds then
        print("[SurvivorLeagueCommunityWarning] Rejected duplicate client death report for " .. tostring(key))
        return
    end
    local verifiedDead = false
    pcall(function() verifiedDead = player:isDead() == true end)
    if not verifiedDead then
        print("[SurvivorLeagueCommunityWarning] Rejected unverified client death report for " .. tostring(key))
        return
    end
    clientDeathReportTimes[key] = now
    -- Never trust client-provided survival duration.
    if opts.allowClientKillReports then observeReportedKills(player, reportedKills, true) end
    onPlayerDeath(player)
end

local function rewardSummary(place, opts)
    local parts = {}
    if (opts.xp[place] or 0) > 0 then parts[#parts + 1] = tostring(opts.xp[place]) .. " XP" end
    local items = parseItems(opts.items[place], opts.maximumRewardItemCount, "season reward summary "..tostring(place))
    for i = 1, math.min(2, #items) do
        local shortName = tostring(items[i].itemType):gsub("^.-%.", "")
        parts[#parts + 1] = shortName .. " x" .. tostring(items[i].count)
    end
    if #parts == 0 then return "No reward configured" end
    return table.concat(parts, " + ")
end

local function killStreakRewardSummaries(opts)
    local summaries = {}
    for _, reward in ipairs(opts.killStreakRewards or {}) do
        local parts = {}
        local xp = math.max(0, tonumber(reward.xp) or 0)
        if xp > 0 then
            parts[#parts + 1] = tostring(xp) .. " " .. tostring(reward.xpPerk or "XP") .. " XP"
        end
        local items = parseItems(reward.items, opts.maximumRewardItemCount, "kill-streak reward summary "..tostring(reward.id))
        for _, item in ipairs(items) do
            local shortName = tostring(item.itemType):gsub("^.-%.", "")
            parts[#parts + 1] = shortName .. " x" .. tostring(item.count)
        end
        summaries[#summaries + 1] = {
            tier = tonumber(reward.id) or (#summaries + 1),
            enabled = reward.enabled == true,
            kills = math.max(1, tonumber(reward.kills) or 1),
            summary = #parts > 0 and table.concat(parts, " + ") or "No reward configured",
        }
    end
    return summaries
end

local function isAdmin(player)
    local level = tostring(player and player:getAccessLevel() or ""):lower()
    return level == "admin"
end

local function canPerform(player, action)
    if isAdmin(player) then return true end
    local role = tostring(player and player:getAccessLevel() or ""):lower()
    local opts = SL.getOptions()
    if role ~= "moderator" and role ~= "overseer" then return false end
    if action == "view-status" then return opts.moderatorViewStatus end
    if action == "manage-scores" then return opts.moderatorManageScores end
    if action == "manage-rewards" then return opts.moderatorManageRewards end
    if action == "manage-seasons" then return opts.moderatorManageSeasons end
    return false
end

local function clampScore(value)
    return math.max(0, math.min(2147483647, math.floor(tonumber(value) or 0)))
end

local function recoverySnapshot(dataset)
    local rows = {}
    local scores = type(dataset) == "table" and dataset.scores or nil
    if type(scores) ~= "table" then return rows end
    for key, record in pairs(scores) do
        record = type(record) == "table" and record or {}
        rows[#rows + 1] = {
            key = sanitizeName(key),
            username = sanitizeName(record.username or key),
            displayName = sanitizeName(record.displayName or record.username or key),
            seasonKills = clampScore(record.kills),
            totalKills = clampScore(record.totalKills or record.kills),
            streakKills = clampScore(record.streakKills),
            bestStreak = clampScore(record.bestStreak or record.streakKills),
            lastVanillaKills = clampScore(record.lastVanillaKills),
        }
    end
    table.sort(rows, function(a, b) return string.lower(a.key) < string.lower(b.key) end)
    return rows
end

local function previewLegacyRecovery(actor)
    local actorKey = actor and SL.playerKey(actor) or "server-console"
    if actor and not canPerform(actor, "view-status") then
        print("[SurvivorLeagueCommunityAudit] Unauthorized recovery preview rejected | actor=" .. tostring(actorKey))
        return false, "not-authorized"
    end
    local canonicalRows = recoverySnapshot(existingModData(SL.DATA_KEY))
    local legacyRows = recoverySnapshot(existingModData("SurvivorLeagueData"))
    print("[SurvivorLeagueCommunityRecovery] BEGIN READ-ONLY EXPORT | actor=" .. tostring(actorKey)
        .. " | canonicalRecords=" .. tostring(#canonicalRows)
        .. " | legacyRecords=" .. tostring(#legacyRows))
    local function emit(source, rows)
        for _, row in ipairs(rows) do
            print("[SurvivorLeagueCommunityRecovery] source=" .. source
                .. " | key=" .. tostring(row.key)
                .. " | username=" .. tostring(row.username)
                .. " | displayName=" .. tostring(row.displayName)
                .. " | season=" .. tostring(row.seasonKills)
                .. " | total=" .. tostring(row.totalKills)
                .. " | streak=" .. tostring(row.streakKills)
                .. " | best=" .. tostring(row.bestStreak)
                .. " | vanillaBaseline=" .. tostring(row.lastVanillaKills))
        end
    end
    emit("canonical", canonicalRows)
    emit("legacy", legacyRows)
    print("[SurvivorLeagueCommunityRecovery] END READ-ONLY EXPORT | no scores changed")
    return true, { canonical = #canonicalRows, legacy = #legacyRows }
end

SL.AdminAPI = SL.AdminAPI or {}
SL.AdminAPI.previewLegacyRecovery = previewLegacyRecovery

local function correctScore(actor, targetUsername, seasonKills, totalKills, streakKills, reason)
    local actorKey = actor and SL.playerKey(actor) or "server-console"
    if actor and not canPerform(actor, "manage-scores") then
        print("[SurvivorLeagueCommunityAudit] Unauthorized score correction rejected | actor=" .. tostring(actorKey))
        return false, "not-authorized"
    end
    local requestedTarget = tostring(targetUsername or "")
    local target = requestedTarget
    local d = data()
    local record = d.scores[target]
    if not record then
        local sanitizedTarget = sanitizeName(requestedTarget)
        for key, candidate in pairs(d.scores) do
            if sanitizeName(key) == sanitizedTarget or sanitizeName(candidate.username) == sanitizedTarget then
                target, record = key, candidate
                break
            end
        end
    end
    if not record then
        print("[SurvivorLeagueCommunityAudit] Score correction rejected | actor=" .. tostring(actorKey) .. " | target=" .. tostring(target) .. " | reason=unknown-player")
        return false, "unknown-player"
    end
    local beforeSeason = clampScore(record.kills)
    local beforeTotal = clampScore(record.totalKills)
    local beforeStreak = clampScore(record.streakKills)
    local correctedSeason = clampScore(seasonKills)
    local correctedTotal = math.max(correctedSeason, clampScore(totalKills))
    local correctedStreak = math.min(correctedSeason, clampScore(streakKills))
    record.kills = correctedSeason
    record.totalKills = correctedTotal
    record.streakKills = correctedStreak
    record.bestStreak = math.max(clampScore(record.bestStreak), correctedStreak)

    -- Keep an online target's vanilla baseline aligned with the corrected
    -- score. Without this, a pending client report can immediately award an
    -- already-earned kill a second time after the correction.
    local livePlayer = compatibleClients[target]
    local correctedBaseline = nil
    if livePlayer and SL.playerKey(livePlayer) == target then
        correctedBaseline = safeKills(livePlayer)
        record.lastVanillaKills = correctedBaseline
        if record.clientKillSync or SL.getOptions().allowClientKillReports then
            record.clientKillSync = true
            record.lastClientKills = correctedBaseline
            clientKillReportTimes[target] = SL.now()
        end
        local state = runtime[target] or {}
        state.lastKills = correctedBaseline
        state.lastHours = hoursSurvived and hoursSurvived(livePlayer) or 0
        state.lastCharacter = characterName(livePlayer)
        runtime[target] = state
    end
    print("[SurvivorLeagueCommunityScoreCorrection] actor=" .. tostring(actorKey)
        .. " | target=" .. tostring(target)
        .. " | season=" .. tostring(beforeSeason) .. "->" .. tostring(correctedSeason)
        .. " | total=" .. tostring(beforeTotal) .. "->" .. tostring(correctedTotal)
        .. " | streak=" .. tostring(beforeStreak) .. "->" .. tostring(correctedStreak)
        .. " | vanillaBaseline=" .. tostring(correctedBaseline or "unchanged-offline")
        .. " | reason=" .. sanitizeName(reason or "manual correction"))
    ModData.transmit(SL.DATA_KEY)
    return true, record
end

local function archivePlayer(actor, targetUsername, restore)
    if actor and not canPerform(actor, "manage-scores") then return false, "not-authorized" end
    local d = data()
    local target = tostring(targetUsername or "")
    if target == "" then return false, "missing-player" end
    if restore == true then
        local archived = d.archive[target]
        if not archived then return false, "not-archived" end
        if d.scores[target] then return false, "active-record-exists" end
        d.scores[target], d.archive[target] = archived.record, nil
        print("[SurvivorLeagueCommunityAudit] Player restored | target=" .. sanitizeName(target))
    else
        local record = d.scores[target]
        if not record then return false, "unknown-player" end
        if compatibleClients[target] then return false, "player-online" end
        d.archive[target] = { record=record, archivedAt=SL.now(), archivedBy=actor and SL.playerKey(actor) or "server-console" }
        d.scores[target] = nil
        print("[SurvivorLeagueCommunityAudit] Player archived | target=" .. sanitizeName(target))
    end
    ModData.transmit(SL.DATA_KEY)
    return true
end

SL.AdminAPI.archivePlayer = archivePlayer

SL.AdminAPI = SL.AdminAPI or {}
SL.AdminAPI.correctScore = correctScore

local function nextMilestoneFor(record, opts)
    local current = tonumber(record and record.streakKills) or 0
    local nextTier
    for _, reward in ipairs(opts.killStreakRewards or {}) do
        local threshold = tonumber(reward.kills) or 0
        if reward.enabled and threshold > current and (not nextTier or threshold < nextTier.kills) then
            nextTier = { tier = tonumber(reward.id) or 0, kills = threshold }
        end
    end
    return nextTier
end

local function normalizeSearch(value)
    local text = tostring(value or ""):gsub("[%c]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    return utf8Prefix(text, 48):lower()
end

local function accessRole(player)
    local level = tostring(player and player:getAccessLevel() or ""):lower()
    if level == "admin" then return "admin" end
    if level == "moderator" or level == "overseer" then return level end
    return "player"
end

local function pendingDiagnostics(d, username)
    local total, mine, retrying = 0, 0, 0
    for key, rewards in pairs(d.pending or {}) do
        for _, reward in ipairs(rewards or {}) do
            total = total + 1
            if key == username then mine = mine + 1 end
            if (tonumber(reward.nextRetryAt) or 0) > 0 then retrying = retrying + 1 end
        end
    end
    return { total = total, mine = mine, retrying = retrying }
end

local function settlementPreview(rows, opts)
    local winners = {}
    for place = 1, math.min(3, #rows) do
        local row = rows[place]
        if row.kills >= opts.minimumKills then
            winners[#winners + 1] = { place=place, username=row.username, displayName=row.displayName, kills=row.kills }
        end
    end
    return winners
end

local sendBoard
sendBoard = function(player, request)
    -- Hosted co-op builds do not always emit server OnPlayerUpdate reliably.
    -- Refresh here so requesting the board also registers and syncs the player.
    observePlayer(player)
    checkSeasonSettlement()
    local d = data()
    local allRows = sortedScores()
    local opts = SL.getOptions()
    local username = SL.playerKey(player)
    local myRecord = username and d.scores[username] or nil
    local myRank = 0
    for index, row in ipairs(allRows) do
        if tostring(row.username) == tostring(username) then myRank = index break end
    end
    request = type(request) == "table" and request or {}
    local pageSize = math.max(5, math.min(25, math.floor(tonumber(request.pageSize) or 10)))
    local search = normalizeSearch(request.search)
    local filtered = {}
    for rank, row in ipairs(allRows) do
        local haystack = (tostring(row.username or "") .. " " .. tostring(row.displayName or "")):lower()
        if search == "" or string.find(haystack, search, 1, true) then
            local copy = copyValue(row)
            copy.rank = rank
            filtered[#filtered + 1] = copy
        end
    end
    local pageCount = math.max(1, math.ceil(#filtered / pageSize))
    local page = math.max(1, math.min(pageCount, math.floor(tonumber(request.page) or 1)))
    local first = ((page - 1) * pageSize) + 1
    local history = {}
    for index = #d.history, math.max(1, #d.history - 9), -1 do
        local entry = d.history[index]
        local winners = {}
        for place, winner in ipairs(entry.winners or {}) do
            winners[place] = {
                username = winner.username,
                displayName = winner.displayName,
                kills = tonumber(winner.kills) or 0,
            }
        end
        history[#history + 1] = {
            seasonId = tonumber(entry.seasonId) or index,
            startedAt = tonumber(entry.startedAt) or 0,
            endedAt = tonumber(entry.endedAt) or 0,
            winners = winners,
        }
    end
    local payload = {
        seasonId = d.seasonId,
        startedAt = d.startedAt,
        endsAt = d.endsAt,
        serverNow = SL.now(),
        username = username,
        isAdmin = isAdmin(player),
        accessRole = accessRole(player),
        canViewDiagnostics = canPerform(player, "view-status"),
        canManageScores = canPerform(player, "manage-scores"),
        canManageRewards = canPerform(player, "manage-rewards"),
        canManageSeasons = canPerform(player, "manage-seasons"),
        playerCount = #allRows,
        filteredCount = #filtered,
        page = page,
        pageCount = pageCount,
        pageSize = pageSize,
        firstRank = filtered[first] and filtered[first].rank or 0,
        search = search,
        minimumKills = opts.minimumKills,
        seasonDays = opts.seasonDays,
        leaderboardSize = opts.leaderboardSize,
        nameFormat = opts.nameFormat,
        myStats = {
            rank = myRank,
            kills = tonumber(myRecord and myRecord.kills) or 0,
            totalKills = tonumber(myRecord and myRecord.totalKills) or 0,
            streakKills = tonumber(myRecord and myRecord.streakKills) or 0,
            bestStreak = tonumber(myRecord and myRecord.bestStreak) or tonumber(myRecord and myRecord.streakKills) or 0,
            displayName = tostring(myRecord and myRecord.displayName or username or "Survivor"),
            nextMilestone = nextMilestoneFor(myRecord, opts),
        },
        history = history,
        rewards = { rewardSummary(1, opts), rewardSummary(2, opts), rewardSummary(3, opts) },
        killStreakRewards = killStreakRewardSummaries(opts),
        tiePolicy = opts.seasonTiePolicy,
        settlementPreview = settlementPreview(allRows, opts),
        rewardDiagnostics = pendingDiagnostics(d, username),
        rows = {},
    }
    for i = first, math.min(#filtered, first + pageSize - 1) do
        payload.rows[#payload.rows + 1] = filtered[i]
    end
    safeServerCommand(player, SL.MODULE, "Leaderboard", payload)
end

local function enqueueBoard(player, request)
    local key = SL.playerKey(player)
    if not key then return end
    if not leaderboardQueue[key] then leaderboardQueueOrder[#leaderboardQueueOrder + 1] = key end
    leaderboardQueue[key] = { player=player, request=copyValue(request or {}) }
end

local function processLeaderboardQueue()
    local now, limit = SL.now(), SL.getOptions().leaderboardUpdatesPerSecond
    if leaderboardQueueWindow.second ~= now then
        leaderboardQueueWindow.second, leaderboardQueueWindow.processed = now, 0
    end
    while leaderboardQueueWindow.processed < limit and #leaderboardQueueOrder > 0 do
        local key = table.remove(leaderboardQueueOrder, 1)
        local queued = leaderboardQueue[key]
        leaderboardQueue[key] = nil
        if queued and compatibleClients[key] == queued.player then
            leaderboardQueueWindow.processed = leaderboardQueueWindow.processed + 1
            sendBoard(queued.player, queued.request)
        end
    end
end

SL.ServerAPI = SL.ServerAPI or {}
SL.ServerAPI.getSnapshot = function()
    local d, rows = data(), sortedScores()
    return {
        generatedAt = SL.now(), seasonId = d.seasonId, startedAt = d.startedAt,
        endsAt = d.endsAt, rows = copyValue(rows), history = copyValue(d.history),
    }
end

local function onClientCommand(module, command, player, args)
    if module ~= SL.MODULE then return end
    local opts = SL.getOptions()
    if not opts.enabled then return end
    local clientKey = SL.playerKey(player)
    if command == "PlayerReady" then
        local protocol = tonumber(args and args.protocol)
        local version = tonumber(args and args.version)
        if protocol ~= SL.PROTOCOL_VERSION or version ~= SL.VERSION then
            if clientKey then compatibleClients[clientKey] = nil end
            print("[SurvivorLeagueCommunityAudit] Protocol rejected | user=" .. tostring(clientKey) .. " | client=" .. tostring(protocol) .. "/" .. tostring(version) .. " | server=" .. tostring(SL.PROTOCOL_VERSION) .. "/" .. tostring(SL.VERSION))
            safeServerCommand(player, SL.MODULE, "ProtocolMismatch", { protocol = SL.PROTOCOL_VERSION, version = SL.VERSION })
            return
        end
        if not clientKey then return end
        compatibleClients[clientKey] = player
        sessionTokens[clientKey] = newSessionToken(clientKey)
        reportSequences[clientKey] = 0
        print("[SurvivorLeagueCommunityAudit] Protocol accepted | user=" .. tostring(clientKey) .. " | protocol=" .. tostring(protocol) .. " | version=" .. tostring(version))
        grantPending(player)
        announceJoin(player)
        safeServerCommand(player, SL.MODULE, "PlayerReadyAck", { protocol = SL.PROTOCOL_VERSION, version = SL.VERSION, token=sessionTokens[clientKey] })
        return
    end
    if not clientKey or compatibleClients[clientKey] ~= player then
        print("[SurvivorLeagueCommunityAudit] Command rejected before protocol verification | user=" .. tostring(clientKey) .. " | command=" .. tostring(command))
        return
    end
    if command == "RequestLeaderboard" then
        local key, now = SL.playerKey(player), SL.now()
        local previous = key and tonumber(leaderboardRequestTimes[key]) or 0
        if key and (previous == 0 or (now - previous) >= 2) then
            leaderboardRequestTimes[key] = now
            enqueueBoard(player, args)
        end
    end
    if command == "ReportKills" and validateClientReport(player, args, command) then observeReportedKills(player, args and args.kills, args and args.force == true) end
    if command == "PreviewLegacyRecovery" then
        local ok, result = previewLegacyRecovery(player)
        safeServerCommand(player, SL.MODULE, "RecoveryPreviewResult", {
            ok = ok,
            reason = type(result) == "string" and result or nil,
            canonical = type(result) == "table" and result.canonical or 0,
            legacy = type(result) == "table" and result.legacy or 0,
        })
        return
    end
    if command == "CorrectScore" then
        if not canPerform(player, "manage-scores") then
            print("[SurvivorLeagueCommunityAudit] Unauthorized score correction rejected | actor=" .. tostring(clientKey))
        else
            local ok, result = correctScore(player, args and args.username, args and args.seasonKills, args and args.totalKills, args and args.streakKills, args and args.reason)
            safeServerCommand(player, SL.MODULE, "ScoreCorrectionResult", { ok = ok, reason = type(result) == "string" and result or nil, username = args and args.username })
            if ok then sendBoard(player) end
        end
        return
    end
    if command == "RetryPendingRewards" then
        if not canPerform(player, "manage-rewards") then
            safeServerCommand(player, SL.MODULE, "AdminActionResult", { ok=false, action=command, reason="not-authorized" })
        else
            local target = tostring(args and args.username or clientKey or "")
            for _, reward in ipairs(data().pending[target] or {}) do reward.nextRetryAt = 0 end
            local live = compatibleClients[target]
            if live then grantPending(live) end
            safeServerCommand(player, SL.MODULE, "AdminActionResult", { ok=true, action=command, username=target })
            sendBoard(player, args)
        end
        return
    end
    if command == "ArchivePlayer" or command == "RestorePlayer" then
        local ok, reason = archivePlayer(player, args and args.username, command == "RestorePlayer")
        safeServerCommand(player, SL.MODULE, "AdminActionResult", { ok=ok, action=command, reason=reason, username=args and args.username })
        if ok then sendBoard(player, args) end
        return
    end
    if command == "SettleNow" then
        if not canPerform(player, "manage-seasons") then
            print("[SurvivorLeagueCommunityAudit] Unauthorized settlement rejected | user=" .. tostring(clientKey))
        elseif seasonSettlementInProgress then
            print("[SurvivorLeagueCommunityAudit] Admin settlement rejected; settlement already active | user=" .. tostring(clientKey))
        else
            print("[SurvivorLeagueCommunityAudit] Admin settlement requested | user=" .. tostring(clientKey) .. " | season=" .. tostring(data().seasonId))
            seasonSettlementInProgress = true
            local ok, err = pcall(settleSeason, "admin-command", clientKey)
            seasonSettlementInProgress = false
            if not ok then print("[SurvivorLeagueCommunityError] Admin settlement failed: " .. tostring(err)) end
        end
    end
    if command == "ReportDeath" and validateClientReport(player, args, command) then
        onClientDeathReport(player, args and args.kills)
    end
end

local function onPlayerUpdate(player)
    if not SL.getOptions().enabled then return end
    local key = player and SL.playerKey(player)
    if not key then return end
    serverPollTicks[key] = (tonumber(serverPollTicks[key]) or 0) + 1
    if serverPollTicks[key] % 120 ~= 0 then return end
    observePlayer(player)
    if compatibleClients[key] == player then
        pendingRewardPollTicks[key] = (tonumber(pendingRewardPollTicks[key]) or 0) + 1
        if pendingRewardPollTicks[key] % 5 == 0 then grantPending(player) end
    end
    checkSeasonSettlement()
end

local function cleanupPlayer(player)
    local key = player and SL.playerKey(player)
    if not key then return end
    runtime[key] = nil
    serverPollTicks[key] = nil
    pendingRewardPollTicks[key] = nil
    clientKillReportTimes[key] = nil
    clientDeathReportTimes[key] = nil
    leaderboardRequestTimes[key] = nil
    compatibleClients[key] = nil
    sessionTokens[key] = nil
    reportSequences[key] = nil
    leaderboardQueue[key] = nil
    -- Do not clear the timestamp: reconnecting is exactly what the duplicate
    -- announcement cooldown is intended to suppress.
    recentDeaths[key] = nil
end

local function validateConfiguration()
    local opts, warnings = SL.getOptions(), 0
    if opts.minimumKills < 0 or opts.seasonDays < 1 then
        warnings = warnings + 1
        print("[SurvivorLeagueCommunityConfig] Invalid season settings were clamped to safe values")
    end
    for place = 1, 3 do
        parseItems(opts.items[place], opts.maximumRewardItemCount, "startup podium reward " .. tostring(place))
        resolvePerk(opts.xpPerk, opts.xp[place], "startup podium reward " .. tostring(place))
    end
    local previousThreshold = 0
    for _, reward in ipairs(opts.killStreakRewards or {}) do
        if reward.enabled and reward.kills <= previousThreshold then
            warnings = warnings + 1
            print("[SurvivorLeagueCommunityConfig] Kill-streak thresholds should be strictly increasing; tier=" .. tostring(reward.id))
        end
        if reward.enabled then previousThreshold = reward.kills end
    end
    print("[SurvivorLeagueCommunityConfig] Validation complete | warnings=" .. tostring(warnings)
        .. " | tiePolicy=" .. tostring(opts.seasonTiePolicy))
end

Events.OnClientCommand.Add(onClientCommand)
Events.OnPlayerUpdate.Add(onPlayerUpdate)
if Events.OnTick then Events.OnTick.Add(processLeaderboardQueue) end
if Events.OnPlayerDeath then Events.OnPlayerDeath.Add(onPlayerDeath) end
if Events.OnPlayerDisconnect then Events.OnPlayerDisconnect.Add(cleanupPlayer) end
Events.OnInitGlobalModData.Add(function() data() end)
if Events.OnServerStarted then Events.OnServerStarted.Add(function()
    validateConfiguration()
    checkSeasonSettlement("server-start")
end) end
if Events.EveryOneMinute then Events.EveryOneMinute.Add(function() checkSeasonSettlement("one-minute") end) end
