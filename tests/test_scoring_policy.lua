SurvivorLeagueCommunity = {}
dofile("42/media/lua/shared/SurvivorLeagueCommunity_ScoringPolicy.lua")

local evaluate = SurvivorLeagueCommunity.ScoringPolicy.evaluateClientReport

local function expect(label, expectedDecision, expectedGain, ...)
    local decision, gained = evaluate(...)
    assert(decision == expectedDecision, label .. ": expected " .. expectedDecision .. ", got " .. tostring(decision))
    assert(gained == expectedGain, label .. ": expected gain " .. tostring(expectedGain) .. ", got " .. tostring(gained))
end

expect("first report is baseline", "baseline", 0, nil, 400, 15, 120, 500, 0, false, 3)
expect("lower counter resets", "reset", 0, 400, 2, 15, 120, 500, 0, false, 3)
expect("normal fallback accepted", "accept", 2, 10, 12, 15, 120, 500, 0, false, 3)
expect("rate spike quarantined", "quarantine-rate", 40, 10, 50, 15, 120, 500, 0, false, 3)
expect("unreliable zero server ignored", "accept", 2, 10, 12, 15, 120, 500, 0, false, 3)
expect("reliable server mismatch quarantined", "quarantine-server", 4, 10, 14, 15, 120, 500, 9, true, 3)
expect("reliable server tolerance accepted", "accept", 2, 10, 12, 15, 120, 500, 9, true, 3)
expect("server-confirmed reconnect catch-up accepted", "accept", 731, 141, 872, 15, 120, 500, 872, true, 3)

print("Scoring policy tests passed")
