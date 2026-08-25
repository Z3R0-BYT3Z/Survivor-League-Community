require "SurvivorLeagueCommunity_Config"

local SL = SurvivorLeagueCommunity

-- Project Zomboid's getText() resolves the active game language and falls
-- back through Translate/EN. Sandbox option 2 deliberately pins the bundled
-- English fallback for servers that require one shared moderation vocabulary.
function SL.text(key, english, ...)
    local token = "UI_SurvivorLeagueCommunity_" .. tostring(key or "")
    local value = nil
    if SL.getOptions().localizationLanguage ~= 2 and type(getText) == "function" then
        local ok, translated = pcall(getText, token, ...)
        if ok and translated and tostring(translated) ~= token then value = tostring(translated) end
    end
    if value then return value end
    local fallback = tostring(english or key or "")
    local arguments = {...}
    for index, argument in ipairs(arguments) do
        fallback = fallback:gsub("%%" .. tostring(index), tostring(argument))
    end
    return fallback
end
