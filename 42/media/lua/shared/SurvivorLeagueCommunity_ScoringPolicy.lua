SurvivorLeagueCommunity = SurvivorLeagueCommunity or {}

local Policy = {}

function Policy.evaluateClientReport(previous, current, elapsed, maximumPerMinute, maximumDelta, serverCurrent, serverReliable, tolerance)
    current = math.max(0, math.floor(tonumber(current) or 0))
    if previous == nil then return "baseline", 0, current end
    previous = math.max(0, math.floor(tonumber(previous) or 0))
    if current < previous then return "reset", 0, current end

    elapsed = math.max(1, tonumber(elapsed) or 1)
    local rateLimit = math.max(1, math.ceil((tonumber(maximumPerMinute) or 1) * elapsed / 60))
    local allowedDelta = math.min(math.max(1, tonumber(maximumDelta) or 1), rateLimit)
    local gained = current - previous

    if serverReliable == true then
        serverCurrent = math.max(0, math.floor(tonumber(serverCurrent) or 0))
        tolerance = math.max(0, math.floor(tonumber(tolerance) or 0))
        if current > serverCurrent + tolerance then
            return "quarantine-server", gained, serverCurrent + tolerance
        end
        -- A large reconnect catch-up is trustworthy when the authoritative
        -- server counter independently confirms it. Apply the rate limit only
        -- to reports that do not have that server-side confirmation.
        return "accept", gained, allowedDelta
    end
    if gained > allowedDelta then return "quarantine-rate", gained, allowedDelta end
    return "accept", gained, allowedDelta
end

SurvivorLeagueCommunity.ScoringPolicy = Policy
return Policy
