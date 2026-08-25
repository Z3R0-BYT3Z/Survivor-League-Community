require "SurvivorLeagueCommunity_Config"
require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISTextEntryBox"

local SL = SurvivorLeagueCommunity
local panel
local currentBoardPage = 1
local lastReportedKills = -1
local lastAcknowledgedKills = -1
local pendingReportedKills = nil
local lastKillReportAt = 0
local killPollTicks = 0
local playerReadyPending = true
local playerReadyAttempts = 0
local playerReadyTicks = 0
local pendingJoinMessages = {}
local joinMessageRetryTicks = 0
local lastBoardRequestAt = 0
local protocolCompatible = false
local openAfterHandshake = false
local Appearance = SL.getAppearance(nil)
local C = Appearance.palette

local function refreshAppearance(player)
    Appearance = SL.getAppearance(player or (getPlayer and getPlayer()))
    C = Appearance.palette
end

local function closeBoard(target)
    target:setVisible(false); target:removeFromUIManager(); panel = nil; currentBoardPage = 1
end

local function reportLocalKills(force)
    if not SL.getOptions().allowClientKillReports then return end
    local player = getPlayer()
    if not player then return end
    local kills = 0
    local ok = pcall(function() kills = math.max(0, math.floor(tonumber(player:getZombieKills()) or 0)) end)
    if not ok then return end
    if kills ~= lastAcknowledgedKills then pendingReportedKills = kills end
    if pendingReportedKills == nil then return end
    local now = SL.now()
    local interval = math.max(1, tonumber(SL.getOptions().clientKillReportIntervalSeconds) or 15)
    if not force and lastKillReportAt > 0 and (now - lastKillReportAt) < interval then return end
    if force or pendingReportedKills ~= lastReportedKills then
        kills = pendingReportedKills
        lastReportedKills = kills
        lastKillReportAt = now
        sendClientCommand(SL.MODULE, "ReportKills", { kills = kills, force = force == true })
    end
end

local function beginPlayerReady(playerIndex, player)
    local p = player or (getSpecificPlayer and getSpecificPlayer(playerIndex)) or getPlayer()
    if not p then return false end
    protocolCompatible = false
    playerReadyPending = true
    playerReadyAttempts = 0
    playerReadyTicks = 0
    sendClientCommand(SL.MODULE, "PlayerReady", { protocol = SL.PROTOCOL_VERSION, version = SL.VERSION })
    return true
end

function SL.requestScoreCorrection(username, seasonKills, totalKills, streakKills, reason)
    if not protocolCompatible then return false end
    sendClientCommand(SL.MODULE, "CorrectScore", {
        username = tostring(username or ""),
        seasonKills = tonumber(seasonKills) or 0,
        totalKills = tonumber(totalKills) or 0,
        streakKills = tonumber(streakKills) or 0,
        reason = tostring(reason or "manual correction"),
    })
    return true
end

local function refreshBoard()
    if not protocolCompatible then return end
    local now = SL.now()
    if lastBoardRequestAt > 0 and (now - lastBoardRequestAt) < 2 then return end
    lastBoardRequestAt = now
    reportLocalKills(true)
    sendClientCommand(SL.MODULE, "RequestLeaderboard", {})
end

local function countdown(payload)
    local endsAt = tonumber(payload and payload.endsAt) or 0
    local serverNow = tonumber(payload and payload.serverNow)
    local seconds
    if serverNow then
        local receivedAt = tonumber(payload.clientReceivedAt) or SL.now()
        local elapsed = math.max(0, SL.now() - receivedAt)
        seconds = math.max(0, (endsAt - serverNow) - elapsed)
    else
        -- Compatibility with older servers that do not provide serverNow.
        seconds = math.max(0, endsAt - SL.now())
    end
    return string.format("%dd %02dh %02dm remaining", math.floor(seconds/86400), math.floor((seconds%86400)/3600), math.floor((seconds%3600)/60))
end

local LeaderboardPanel = ISPanel:derive("SurvivorLeagueCommunityCommandCenter")

local function utf8Characters(value)
    local text, characters, index = tostring(value or ""), {}, 1
    while index <= #text do
        local byte = text:byte(index)
        local width = byte < 0x80 and 1 or (byte < 0xE0 and 2 or (byte < 0xF0 and 3 or 4))
        if index + width - 1 > #text then break end
        characters[#characters + 1] = text:sub(index, index + width - 1)
        index = index + width
    end
    return characters
end

local function rankColor(rank)
    if rank == 1 then return C.accent end
    if rank == 2 then return C.silver end
    if rank == 3 then return C.bronze end
    return C.text
end

local function shortText(value, maximum)
    local text = tostring(value or "")
    maximum = tonumber(maximum) or 36
    local characters = utf8Characters(text)
    if #characters <= maximum then return text end
    local output = {}
    for index = 1, math.max(1, maximum - 3) do output[index] = characters[index] end
    return table.concat(output) .. "..."
end

-- Project Zomboid's UI fonts do not reliably render decorative Unicode
-- characters. Measure the configured font and clip before drawing so long
-- player names and reward descriptions remain inside their panels.
local function textWidth(value, font)
    local text = tostring(value or "")
    local width = #text * 7
    pcall(function()
        width = getTextManager():MeasureStringX(font or UIFont.Small, text)
    end)
    return tonumber(width) or (#text * 7)
end

local function fontHeight(font)
    local height = 18
    pcall(function() height = getTextManager():getFontHeight(font or UIFont.Small) end)
    return math.max(1, tonumber(height) or 18)
end

local function drawTextCenteredInBox(self, value, x, y, width, height, color, font)
    font = font or UIFont.Small
    local textY = y + math.floor((height - fontHeight(font)) / 2)
    self:drawTextCentre(tostring(value or ""), x + (width / 2), textY, color[1], color[2], color[3], color[4] or 1, font)
end

local function fitText(value, maximumWidth, font)
    local text = tostring(value or "")
    maximumWidth = math.max(12, tonumber(maximumWidth) or 12)
    font = font or UIFont.Small
    if textWidth(text, font) <= maximumWidth then return text end
    local characters = utf8Characters(text)
    local suffix, low, high, best = "...", 0, #characters, ""
    while low <= high do
        local middle = math.floor((low + high) / 2)
        local candidate = table.concat(characters, "", 1, middle) .. suffix
        if textWidth(candidate, font) <= maximumWidth then
            best = candidate
            low = middle + 1
        else
            high = middle - 1
        end
    end
    return best ~= "" and best or suffix
end

local function wrapTwoLines(value, maximumWidth, font)
    local text = tostring(value or "")
    if textWidth(text, font) <= maximumWidth then return text, nil end
    local first, second = "", ""
    for word in string.gmatch(text, "%S+") do
        local candidate = first == "" and word or (first .. " " .. word)
        if first == "" or textWidth(candidate, font) <= maximumWidth then first = candidate
        else second = second == "" and word or (second .. " " .. word) end
    end
    return fitText(first, maximumWidth, font), second ~= "" and fitText(second, maximumWidth, font) or nil
end

local function drawCorners(self, x, y, w, h, color)
    local r, g, b, a = color[1], color[2], color[3], color[4] or 1
    local n = 16
    self:drawRect(x, y, n, 2, a, r, g, b); self:drawRect(x, y, 2, n, a, r, g, b)
    self:drawRect(x+w-n, y, n, 2, a, r, g, b); self:drawRect(x+w-2, y, 2, n, a, r, g, b)
    self:drawRect(x, y+h-2, n, 2, a, r, g, b); self:drawRect(x, y+h-n, 2, n, a, r, g, b)
    self:drawRect(x+w-n, y+h-2, n, 2, a, r, g, b); self:drawRect(x+w-2, y+h-n, 2, n, a, r, g, b)
end

function LeaderboardPanel:new(payload)
    refreshAppearance(getPlayer and getPlayer())
    local screenW, screenH = getCore():getScreenWidth(), getCore():getScreenHeight()
    local width = math.min(1180, screenW - 24)
    local height = math.min(680, screenH - 24)
    local o = ISPanel.new(self, math.max(12, (screenW-width)/2), math.max(12, (screenH-height)/2), width, height)
    o.payload = payload or { rows={}, rewards={}, history={}, myStats={} }
    o.backgroundColor = {r=C.bg[1],g=C.bg[2],b=C.bg[3],a=C.bg[4]}
    o.borderColor = {r=C.accent[1],g=C.accent[2],b=C.accent[3],a=0.92}
    o.moveWithMouse = true
    o.currentPage = math.max(1, currentBoardPage)
    o.activeTab = "leaderboard"
    return o
end

function LeaderboardPanel:getRowsPerPage()
    -- The game scales UIFont sizes independently of screen resolution. A
    -- fixed ten-row page therefore overlaps pagination and the stats strip at
    -- larger UI/font scales. Derive the page size from the actual rendered
    -- row height and the space reserved for the leaderboard.
    local top = 148
    local bottom = self.height - 168
    local firstRowY = top + 46
    local rowH = math.max(31, fontHeight(UIFont.Medium) + 8)
    return math.max(3, math.floor((bottom - firstRowY) / rowH))
end

function LeaderboardPanel:getPageCount()
    return math.max(1, math.ceil(#(self.payload.rows or {}) / self:getRowsPerPage()))
end

function LeaderboardPanel:updateControls()
    local ranking = self.activeTab == "leaderboard"
    if self.previousPage then self.previousPage:setVisible(ranking); self.previousPage.enable = self.currentPage > 1 end
    if self.nextPage then self.nextPage:setVisible(ranking); self.nextPage.enable = self.currentPage < self:getPageCount() end
    if self.settleButton then self.settleButton:setVisible(self.activeTab == "admin" and self.payload.isAdmin == true) end
    if self.recoveryPreviewButton then self.recoveryPreviewButton:setVisible(self.activeTab == "admin" and self.payload.isAdmin == true) end
    for _, control in ipairs(self.adminControls or {}) do
        control:setVisible(self.activeTab == "admin" and self.payload.isAdmin == true)
    end
    for key, button in pairs(self.tabButtons or {}) do
        local selected = key == self.activeTab
        button.backgroundColor = selected and {r=C.panel[1],g=C.panel[2],b=C.panel[3],a=0.98} or {r=C.bg[1],g=C.bg[2],b=C.bg[3],a=0.65}
        button.borderColor = selected and {r=C.accent[1],g=C.accent[2],b=C.accent[3],a=1} or {r=C.line[1],g=C.line[2],b=C.line[3],a=0.9}
    end
    for _, button in ipairs(self.commandButtons or {}) do
        button.backgroundColorMouseOver = {r=C.accent[1],g=C.accent[2],b=C.accent[3],a=0.14}
        if not button.internal then
            button.backgroundColor = {r=C.bg[1],g=C.bg[2],b=C.bg[3],a=0.65}
            button.borderColor = {r=C.line[1],g=C.line[2],b=C.line[3],a=0.9}
        end
    end
end

function LeaderboardPanel:setPage(page)
    self.currentPage = math.max(1, math.min(tonumber(page) or 1, self:getPageCount()))
    currentBoardPage = self.currentPage
    self:updateControls()
end

function LeaderboardPanel:onPreviousPage() self:setPage(self.currentPage - 1) end
function LeaderboardPanel:onNextPage() self:setPage(self.currentPage + 1) end
function LeaderboardPanel:onClose() closeBoard(self) end
function LeaderboardPanel:onRefresh() refreshBoard() end
function LeaderboardPanel:onSettleSeason()
    local now = SL.now()
    if not self.settleArmedAt or (now - self.settleArmedAt) > 10 then
        self.settleArmedAt = now
        self.settleButton:setTitle("CONFIRM: SETTLE CURRENT SEASON")
        return
    end
    self.settleArmedAt = nil
    self.settleButton:setTitle("SETTLE SEASON NOW")
    sendClientCommand(SL.MODULE, "SettleNow", {})
end

function LeaderboardPanel:onRecoveryPreview()
    sendClientCommand(SL.MODULE, "PreviewLegacyRecovery", {})
    self.recoveryPreviewButton:setTitle("EXPORT REQUESTED - CHECK SERVER LOG")
end

function LeaderboardPanel:onCorrectScore()
    local username = self.adminUsername and self.adminUsername:getText() or ""
    if username == "" then return end
    SL.requestScoreCorrection(
        username,
        self.adminSeason and self.adminSeason:getText() or "0",
        self.adminTotal and self.adminTotal:getText() or "0",
        self.adminStreak and self.adminStreak:getText() or "0",
        self.adminReason and self.adminReason:getText() or "in-game admin correction"
    )
    self.correctScoreButton:setTitle("CORRECTION REQUESTED")
end

function LeaderboardPanel:onTab(button)
    self.activeTab = tostring(button.internal or "leaderboard")
    self:updateControls()
end

function LeaderboardPanel:onCycleTheme()
    if not Appearance.allowOverride then return end
    local player = getPlayer and getPlayer()
    if not player then return end
    local data = player:getModData()
    data.SurvivorLeagueCommunityTheme = (Appearance.index % 3) + 1
    refreshAppearance(player)
    self.backgroundColor = {r=C.bg[1],g=C.bg[2],b=C.bg[3],a=C.bg[4]}
    self.borderColor = {r=C.accent[1],g=C.accent[2],b=C.accent[3],a=0.92}
    self.themeButton:setTitle("THEME: "..string.upper(Appearance.id))
    self:updateControls()
end

function LeaderboardPanel:addCommandButton(x, y, w, h, title, callback)
    local button = ISButton:new(x, y, w, h, title, self, callback)
    button:initialise()
    button.font = UIFont.Small
    button.backgroundColor = {r=C.bg[1],g=C.bg[2],b=C.bg[3],a=0.65}
    button.backgroundColorMouseOver = {r=C.accent[1],g=C.accent[2],b=C.accent[3],a=0.14}
    button.borderColor = {r=C.line[1],g=C.line[2],b=C.line[3],a=0.9}
    self:addChild(button)
    self.commandButtons = self.commandButtons or {}
    self.commandButtons[#self.commandButtons + 1] = button
    return button
end

function LeaderboardPanel:addAdminEntry(x, y, w, value, numeric)
    local entry = ISTextEntryBox:new(tostring(value or ""), x, y, w, 28)
    entry:initialise()
    -- Build 42 may not create the Java text-entry object until the parent
    -- panel is instantiated. Calling setOnlyNumbers here crashes refresh.
    -- Numeric values are still normalized and validated before submission.
    self:addChild(entry)
    self.adminControls[#self.adminControls + 1] = entry
    return entry
end

function LeaderboardPanel:createChildren()
    ISPanel.createChildren(self)
    self.commandButtons = {}
    self.tabButtons = {}
    self.adminControls = {}
    local tabs = {
        {"leaderboard", "LEADERBOARD", 132},
        {"stats", "MY STATS", 120},
        {"history", "SEASON HISTORY", 152},
        {"rewards", "REWARDS", 116},
    }
    if self.payload.isAdmin == true then tabs[#tabs + 1] = {"admin", "ADMIN", 92} end
    local gap, totalWidth = 8, 0
    for _, tab in ipairs(tabs) do
        tab[3] = math.max(72, textWidth(tab[2], UIFont.Small) + 12)
        totalWidth = totalWidth + tab[3]
    end
    totalWidth = totalWidth + ((#tabs - 1) * gap)
    local tabStart, tabEnd = 318, self.width - 210
    local available = math.max(380, tabEnd - tabStart)
    if totalWidth > available then
        local scale = available / totalWidth
        totalWidth = 0
        for _, tab in ipairs(tabs) do
            tab[3] = math.max(64, math.floor(tab[3] * scale))
            totalWidth = totalWidth + tab[3]
        end
        totalWidth = totalWidth + ((#tabs - 1) * gap)
    end
    local tabX = math.max(tabStart, tabEnd - totalWidth)
    for _, tab in ipairs(tabs) do
        local button = self:addCommandButton(tabX, 96, tab[3], 34, tab[2], LeaderboardPanel.onTab)
        button.internal = tab[1]
        self.tabButtons[tab[1]] = button
        tabX = tabX + tab[3] + gap
    end
    self.closeButton = self:addCommandButton(self.width-52, 12, 36, 32, "X", LeaderboardPanel.onClose)
    if Appearance.allowOverride then
        self.themeButton = self:addCommandButton(self.width-250, 12, 174, 32, "THEME: "..string.upper(Appearance.id), LeaderboardPanel.onCycleTheme)
    end
    self.refresh = self:addCommandButton(self.width-304, self.height-52, 142, 32, "REFRESH", LeaderboardPanel.onRefresh)
    local leaderboardCenter = 20 + math.floor((self.width * 0.64) / 2)
    self.previousPage = self:addCommandButton(leaderboardCenter-72, self.height-150, 46, 28, "<", LeaderboardPanel.onPreviousPage)
    self.nextPage = self:addCommandButton(leaderboardCenter+26, self.height-150, 46, 28, ">", LeaderboardPanel.onNextPage)
    local panelX, panelW = 220, self.width-440
    local formX, formW, fieldGap = panelX+42, panelW-84, 10
    local numericW = math.max(72, math.floor(formW*0.13))
    local usernameW = formW-(numericW*3)-(fieldGap*3)
    self.adminFormX, self.adminUsernameW, self.adminNumericW, self.adminFieldGap = formX, usernameW, numericW, fieldGap
    self.adminUsername = self:addAdminEntry(formX, 350, usernameW, "", false)
    self.adminSeason = self:addAdminEntry(formX+usernameW+fieldGap, 350, numericW, "0", true)
    self.adminTotal = self:addAdminEntry(formX+usernameW+fieldGap+numericW+fieldGap, 350, numericW, "0", true)
    self.adminStreak = self:addAdminEntry(formX+usernameW+fieldGap+numericW+fieldGap+numericW+fieldGap, 350, numericW, "0", true)
    local actionW = 220
    local reasonW = formW-actionW-fieldGap
    self.adminReason = self:addAdminEntry(formX, 410, reasonW, "in-game admin correction", false)
    self.correctScoreButton = self:addCommandButton(formX+reasonW+fieldGap, 410, actionW, 28, "APPLY SCORE CORRECTION", LeaderboardPanel.onCorrectScore)
    self.adminControls[#self.adminControls + 1] = self.correctScoreButton
    self.recoveryPreviewButton = self:addCommandButton(math.floor(self.width/2)-310, 466, 300, 34, "EXPORT LEGACY/CURRENT SCORES", LeaderboardPanel.onRecoveryPreview)
    self.settleButton = self:addCommandButton(math.floor(self.width/2)+10, 466, 300, 34, "SETTLE SEASON NOW", LeaderboardPanel.onSettleSeason)
    self:updateControls()
end

function LeaderboardPanel:drawHeader()
    self:drawRect(0, 0, self.width, 66, C.bg[4], C.bg[1], C.bg[2], C.bg[3])
    self:drawRect(0, 65, self.width, 1, 0.85, C.line[1], C.line[2], C.line[3])
    self:drawText(fitText(string.upper(Appearance.title).." // "..string.upper(Appearance.subtitle), self.width-280, UIFont.Small), 20, 14, C.muted[1],C.muted[2],C.muted[3],1,UIFont.Small)
    local statusText = "STATUS: ONLINE"
    self:drawText(statusText, 20, 40, C.live[1],C.live[2],C.live[3],1,UIFont.Small)
    local trackingX = 20 + textWidth(statusText, UIFont.Small) + 24
    self:drawText(fitText("HOST-VALIDATED TRACKING | "..tostring(self.payload.playerCount or 0).." REGISTERED SURVIVORS", self.width-trackingX-210, UIFont.Small), trackingX, 40, C.muted[1],C.muted[2],C.muted[3],1,UIFont.Small)
    self:drawTextRight("BUILD 42", self.width-68, 14, C.muted[1],C.muted[2],C.muted[3],1,UIFont.Small)
    self:drawText(fitText(string.upper(Appearance.title), 300, UIFont.Large), 20, 78, C.text[1],C.text[2],C.text[3],1,UIFont.Large)
    self:drawText(fitText(string.upper(Appearance.subtitle), 300, UIFont.Small), 22, 108, C.muted[1],C.muted[2],C.muted[3],1,UIFont.Small)
    self:drawTextRight("Season #"..tostring(self.payload.seasonId or "?"), self.width-24, 76, C.text[1],C.text[2],C.text[3],1,UIFont.Medium)
    self:drawTextRight(fitText(countdown(self.payload), 190, UIFont.Small), self.width-24, 104, C.accent[1],C.accent[2],C.accent[3],1,UIFont.Small)
end

function LeaderboardPanel:drawLeaderboard()
    local leftX, top, leftW = 20, 148, math.floor(self.width * 0.64)
    local rightX, rightW = leftX + leftW + 16, self.width - (leftX + leftW + 36)
    local bottom = self.height - 168
    self:drawRect(leftX, top, leftW, bottom-top, 0.72, C.panel[1],C.panel[2],C.panel[3])
    self:drawRectBorder(leftX, top, leftW, bottom-top, 0.8, C.line[1],C.line[2],C.line[3])
    drawCorners(self,leftX,top,leftW,bottom-top,C.accent)
    local rankX, rankW = leftX+12, math.floor(leftW*0.08)
    local survivorX, survivorW = rankX+rankW, math.floor(leftW*0.39)
    local seasonX, seasonW = survivorX+survivorW, math.floor(leftW*0.18)
    local totalX, totalW = seasonX+seasonW, math.floor(leftW*0.18)
    local streakX, streakW = totalX+totalW, (leftX+leftW-12)-totalX-totalW
    self:drawTextCentre("RANK",rankX+(rankW/2),top+16,C.muted[1],C.muted[2],C.muted[3],1,UIFont.Small)
    self:drawText("SURVIVOR",survivorX+6,top+16,C.muted[1],C.muted[2],C.muted[3],1,UIFont.Small)
    self:drawTextCentre("SEASON",seasonX+(seasonW/2),top+16,C.muted[1],C.muted[2],C.muted[3],1,UIFont.Small)
    self:drawTextCentre("TOTAL",totalX+(totalW/2),top+16,C.muted[1],C.muted[2],C.muted[3],1,UIFont.Small)
    self:drawTextCentre("STREAK",streakX+(streakW/2),top+16,C.muted[1],C.muted[2],C.muted[3],1,UIFont.Small)
    self:drawRect(leftX+12,top+39,leftW-24,1,0.7,C.line[1],C.line[2],C.line[3])
    local rows = self.payload.rows or {}
    local rowsPerPage = self:getRowsPerPage()
    self.currentPage = math.max(1, math.min(self.currentPage, self:getPageCount()))
    currentBoardPage = self.currentPage
    local firstRank = ((self.currentPage-1)*rowsPerPage)+1
    local lastRank = math.min(#rows, firstRank+rowsPerPage-1)
    local rowH = math.max(31, fontHeight(UIFont.Medium)+8)
    for rank=firstRank,lastRank do
        local visible = rank-firstRank
        local row, y = rows[rank], top+46+(visible*rowH)
        local mine = tostring(row.username or "") == tostring(self.payload.username or "")
        -- Keep player highlighting neutral. Pink is reserved for borders,
        -- rank markers, and active controls in the original Command Center UI.
        local fill = mine and {0.095,0.095,0.112,0.98} or ((visible%2==0) and C.rowA or C.rowB)
        local accent = rankColor(rank)
        self:drawRect(leftX+12,y,leftW-24,rowH-2,fill[4],fill[1],fill[2],fill[3])
        local rankBoxW = math.max(42, rankW-10)
        self:drawRectBorder(rankX+5,y+3,rankBoxW,rowH-8,0.85,accent[1],accent[2],accent[3])
        drawTextCenteredInBox(self,tostring(rank),rankX+5,y+3,rankBoxW,rowH-8,accent,UIFont.Medium)
        self:drawText(fitText(row.displayName or row.username,survivorW-12,UIFont.Medium),survivorX+6,y+6,C.text[1],C.text[2],C.text[3],1,UIFont.Medium)
        self:drawTextCentre(tostring(row.kills or 0),seasonX+(seasonW/2),y+6,C.text[1],C.text[2],C.text[3],1,UIFont.Medium)
        self:drawTextCentre(tostring(row.totalKills or 0),totalX+(totalW/2),y+6,C.text[1],C.text[2],C.text[3],1,UIFont.Medium)
        self:drawTextCentre(tostring(row.streakKills or 0),streakX+(streakW/2),y+6,C.text[1],C.text[2],C.text[3],1,UIFont.Medium)
    end
    self:drawTextCentre(tostring(self.currentPage).." / "..tostring(self:getPageCount()),leftX+(leftW/2),self.height-143,C.text[1],C.text[2],C.text[3],1,UIFont.Small)
    self:drawRect(rightX,top,rightW,bottom-top,0.72,C.panel[1],C.panel[2],C.panel[3])
    self:drawRectBorder(rightX,top,rightW,bottom-top,0.8,C.line[1],C.line[2],C.line[3])
    drawCorners(self,rightX,top,rightW,bottom-top,C.accent)
    local rewardTitleY = top+12
    local rewardQualifierY = rewardTitleY+fontHeight(UIFont.Small)+7
    local rewardDividerY = rewardQualifierY+fontHeight(UIFont.Small)+7
    self:drawTextCentre("SEASON REWARDS",rightX+(rightW/2),rewardTitleY,C.text[1],C.text[2],C.text[3],1,UIFont.Small)
    self:drawTextCentre(fitText("Minimum "..tostring(self.payload.minimumKills or 0).." kills to qualify",rightW-28,UIFont.Small),rightX+(rightW/2),rewardQualifierY,C.muted[1],C.muted[2],C.muted[3],1,UIFont.Small)
    self:drawRect(rightX+14,rewardDividerY,rightW-28,1,0.7,C.line[1],C.line[2],C.line[3])
    local labels={"1ST","2ND","3RD"}
    for place=1,3 do
        local y, accent = rewardDividerY+12+((place-1)*90), rankColor(place)
        self:drawRect(rightX+16,y,rightW-32,76,0.84,C.rowB[1],C.rowB[2],C.rowB[3])
        self:drawRectBorder(rightX+16,y,rightW-32,76,0.85,accent[1],accent[2],accent[3])
        self:drawRectBorder(rightX+30,y+16,62,42,0.95,accent[1],accent[2],accent[3])
        drawTextCenteredInBox(self,labels[place],rightX+30,y+16,62,42,accent,UIFont.Medium)
        self:drawText(fitText((self.payload.rewards or {})[place] or "No reward configured",rightW-132,UIFont.Small),rightX+106,y+27,C.text[1],C.text[2],C.text[3],1,UIFont.Small)
    end
end

function LeaderboardPanel:drawStats()
    local stats = self.payload.myStats or {}
    local x, y, w, h = 20, 154, self.width-40, self.height-232
    self:drawRect(x,y,w,h,0.72,C.panel[1],C.panel[2],C.panel[3]); self:drawRectBorder(x,y,w,h,0.8,C.line[1],C.line[2],C.line[3]); drawCorners(self,x,y,w,h,C.accent)
    self:drawTextCentre(tostring(stats.displayName or self.payload.username or "SURVIVOR"),self.width/2,y+28,C.text[1],C.text[2],C.text[3],1,UIFont.Large)
    local cards={{"YOUR RANK",stats.rank or 0},{"SEASON KILLS",stats.kills or 0},{"TOTAL KILLS",stats.totalKills or 0},{"CURRENT STREAK",stats.streakKills or 0},{"BEST STREAK",stats.bestStreak or 0}}
    local cardW=(w-72)/5
    for i,card in ipairs(cards) do
        local cx=x+16+((i-1)*(cardW+10)); self:drawRect(cx,y+90,cardW,112,0.86,C.rowB[1],C.rowB[2],C.rowB[3]); self:drawRectBorder(cx,y+90,cardW,112,0.75,C.line[1],C.line[2],C.line[3]); self:drawTextCentre(card[1],cx+(cardW/2),y+112,C.muted[1],C.muted[2],C.muted[3],1,UIFont.Small); self:drawTextCentre(tostring(card[2]),cx+(cardW/2),y+146,C.text[1],C.text[2],C.text[3],1,UIFont.Large)
    end
    local milestone=stats.nextMilestone
    self:drawTextCentre(milestone and ("NEXT KILL-STREAK MILESTONE: "..tostring(milestone.kills).." KILLS") or "ALL CONFIGURED MILESTONES COMPLETED",self.width/2,y+252,C.accent[1],C.accent[2],C.accent[3],1,UIFont.Medium)
end

function LeaderboardPanel:drawHistory()
    local x,y,w,h=20,154,self.width-40,self.height-232
    self:drawRect(x,y,w,h,0.72,C.panel[1],C.panel[2],C.panel[3]); self:drawRectBorder(x,y,w,h,0.8,C.line[1],C.line[2],C.line[3]); drawCorners(self,x,y,w,h,C.accent)
    self:drawText("SEASON",x+24,y+20,C.muted[1],C.muted[2],C.muted[3],1,UIFont.Small); self:drawText("1ST PLACE",x+170,y+20,C.muted[1],C.muted[2],C.muted[3],1,UIFont.Small); self:drawText("2ND PLACE",x+500,y+20,C.muted[1],C.muted[2],C.muted[3],1,UIFont.Small); self:drawText("3RD PLACE",x+820,y+20,C.muted[1],C.muted[2],C.muted[3],1,UIFont.Small)
    for i,entry in ipairs(self.payload.history or {}) do
        if i>10 then break end
        local yy=y+52+((i-1)*36); self:drawRect(x+14,yy,w-28,32,(i%2==1) and 0.75 or 0.5,C.rowA[1],C.rowA[2],C.rowA[3]); self:drawText("#"..tostring(entry.seasonId or "?"),x+28,yy+7,C.text[1],C.text[2],C.text[3],1,UIFont.Medium)
        for place=1,3 do local winner=(entry.winners or {})[place]; local xx=place==1 and x+170 or (place==2 and x+500 or x+820); self:drawText(winner and (shortText(winner.displayName or winner.username,20).." - "..tostring(winner.kills or 0).." kills") or "No qualifier",xx,yy+8,C.text[1],C.text[2],C.text[3],1,UIFont.Small) end
    end
    if #(self.payload.history or {})==0 then self:drawTextCentre("No completed seasons yet",self.width/2,y+160,C.muted[1],C.muted[2],C.muted[3],1,UIFont.Medium) end
end

function LeaderboardPanel:drawRewards()
    local x,y,w,h=20,154,self.width-40,self.height-232
    self:drawRect(x,y,w,h,0.72,C.panel[1],C.panel[2],C.panel[3]); self:drawRectBorder(x,y,w,h,0.8,C.line[1],C.line[2],C.line[3]); drawCorners(self,x,y,w,h,C.accent)
    self:drawTextCentre("SEASON PODIUM REWARDS | MINIMUM "..tostring(self.payload.minimumKills or 0).." KILLS",self.width/2,y+20,C.text[1],C.text[2],C.text[3],1,UIFont.Medium)
    local labels={"1ST","2ND","3RD"}
    for place=1,3 do local yy=y+54+((place-1)*72); local accent=rankColor(place); local rewardW=math.floor(w*0.43); self:drawRect(x+28,yy,rewardW,58,0.84,C.rowB[1],C.rowB[2],C.rowB[3]); self:drawRectBorder(x+28,yy,rewardW,58,0.9,accent[1],accent[2],accent[3]); self:drawText(labels[place],x+46,yy+18,accent[1],accent[2],accent[3],1,UIFont.Medium); local line1,line2=wrapTwoLines((self.payload.rewards or {})[place] or "No reward configured",rewardW-96,UIFont.Small); self:drawText(line1,x+112,yy+(line2 and 10 or 20),C.text[1],C.text[2],C.text[3],1,UIFont.Small); if line2 then self:drawText(line2,x+112,yy+30,C.text[1],C.text[2],C.text[3],1,UIFont.Small) end end
    local streakX=x+math.floor(w*0.48); self:drawText("KILL-STREAK REWARDS | ONCE PER LIFE",streakX,y+54,C.text[1],C.text[2],C.text[3],1,UIFont.Small)
    for i,reward in ipairs(self.payload.killStreakRewards or {}) do
        if i>5 then break end
        local yy=y+82+((i-1)*48); local enabled=reward.enabled==true
        self:drawRect(streakX,yy,w-math.floor(w*0.48)-24,40,0.78,C.rowB[1],C.rowB[2],C.rowB[3])
        self:drawRectBorder(streakX,yy,w-math.floor(w*0.48)-24,40,0.75,enabled and 0.30 or C.line[1],enabled and 0.90 or C.line[2],enabled and 0.55 or C.line[3])
        local textY=yy+math.max(3,math.floor((40-fontHeight(UIFont.Small))/2))
        local tierText="TIER "..tostring(reward.tier or i).." | "..tostring(reward.kills or 0).." KILLS"
        local summaryWidth=math.max(120,math.floor((w-math.floor(w*0.48)-24)*0.48))
        self:drawText(fitText(tierText,260,UIFont.Small),streakX+12,textY,enabled and 0.30 or C.muted[1],enabled and 0.90 or C.muted[2],enabled and 0.55 or C.muted[3],1,UIFont.Small)
        self:drawTextRight(enabled and fitText(reward.summary,summaryWidth,UIFont.Small) or "DISABLED",x+w-36,textY,C.text[1],C.text[2],C.text[3],1,UIFont.Small)
    end
end

function LeaderboardPanel:drawAdmin()
    local x,y,w,h=220,154,self.width-440,390
    self:drawRect(x,y,w,h,0.78,C.panel[1],C.panel[2],C.panel[3]); self:drawRectBorder(x,y,w,h,0.9,C.line[1],C.line[2],C.line[3]); drawCorners(self,x,y,w,h,C.accent)
    self:drawTextCentre("ADMINISTRATOR CONTROLS",self.width/2,y+24,C.text[1],C.text[2],C.text[3],1,UIFont.Medium)
    self:drawTextCentre("Authorized access: administrator only",self.width/2,y+56,0.30,0.90,0.55,1,UIFont.Small)
    self:drawText("Season length",x+42,y+94,C.muted[1],C.muted[2],C.muted[3],1,UIFont.Small); self:drawTextRight(tostring(self.payload.seasonDays or 0).." days",x+w-42,y+94,C.text[1],C.text[2],C.text[3],1,UIFont.Small)
    self:drawText("Podium qualification",x+42,y+120,C.muted[1],C.muted[2],C.muted[3],1,UIFont.Small); self:drawTextRight(tostring(self.payload.minimumKills or 0).." kills",x+w-42,y+120,C.text[1],C.text[2],C.text[3],1,UIFont.Small)
    self:drawText("Registered survivors",x+42,y+146,C.muted[1],C.muted[2],C.muted[3],1,UIFont.Small); self:drawTextRight(tostring(self.payload.playerCount or #(self.payload.rows or {})),x+w-42,y+146,C.text[1],C.text[2],C.text[3],1,UIFont.Small)
    local formX=self.adminFormX or x+42
    local usernameW=self.adminUsernameW or 220
    local numericW=self.adminNumericW or 82
    local gap=self.adminFieldGap or 10
    self:drawText("ACCOUNT USERNAME",formX,328,C.muted[1],C.muted[2],C.muted[3],1,UIFont.Small)
    self:drawText("SEASON",formX+usernameW+gap,328,C.muted[1],C.muted[2],C.muted[3],1,UIFont.Small)
    self:drawText("TOTAL",formX+usernameW+gap+numericW+gap,328,C.muted[1],C.muted[2],C.muted[3],1,UIFont.Small)
    self:drawText("STREAK",formX+usernameW+gap+numericW+gap+numericW+gap,328,C.muted[1],C.muted[2],C.muted[3],1,UIFont.Small)
    self:drawText("AUDIT REASON",formX,388,C.muted[1],C.muted[2],C.muted[3],1,UIFont.Small)
    self:drawTextCentre("Recovery export is read-only; settling resets season kills but preserves lifetime totals.",self.width/2,516,C.muted[1],C.muted[2],C.muted[3],1,UIFont.Small)
end

function LeaderboardPanel:drawYourStatsStrip()
    local stats=self.payload.myStats or {}; local y=self.height-112; local w=math.floor((self.width-64)/5); local cards={{"YOUR RANK",stats.rank or 0},{"SEASON KILLS",stats.kills or 0},{"TOTAL KILLS",stats.totalKills or 0},{"CURRENT STREAK",stats.streakKills or 0},{"BEST STREAK",stats.bestStreak or 0}}
    self:drawText("YOUR STATS",20,y-24,C.text[1],C.text[2],C.text[3],1,UIFont.Small)
    for i,card in ipairs(cards) do local x=20+((i-1)*(w+6)); self:drawRect(x,y,w,58,0.78,C.panel[1],C.panel[2],C.panel[3]); self:drawRectBorder(x,y,w,58,0.65,C.line[1],C.line[2],C.line[3]); self:drawTextCentre(card[1],x+(w/2),y+8,C.muted[1],C.muted[2],C.muted[3],1,UIFont.Small); self:drawTextCentre(tostring(card[2]),x+(w/2),y+29,C.text[1],C.text[2],C.text[3],1,UIFont.Medium) end
end

function LeaderboardPanel:prerender()
    ISPanel.prerender(self)
    self:drawHeader()
    if self.activeTab=="leaderboard" then self:drawLeaderboard() elseif self.activeTab=="stats" then self:drawStats() elseif self.activeTab=="history" then self:drawHistory() elseif self.activeTab=="rewards" then self:drawRewards() else self:drawAdmin() end
    if self.activeTab=="leaderboard" then self:drawYourStatsStrip() end
    self:drawText("ONLINE",20,self.height-29,C.live[1],C.live[2],C.live[3],1,UIFont.Small)
    local interfaceKey = SL.getOptions().interfaceKey
    local closeText = interfaceKey == 64 and "F6 / X TO CLOSE" or ("KEY "..tostring(interfaceKey).." / X TO CLOSE")
    self:drawTextRight(closeText,self.width-24,self.height-29,C.muted[1],C.muted[2],C.muted[3],1,UIFont.Small)
end

local function showBoard(payload)
    if panel then panel:removeFromUIManager() end
    payload = payload or {}; payload.clientReceivedAt = SL.now()
    panel = LeaderboardPanel:new(payload); panel:initialise(); panel:addToUIManager()
end

local function showServerChatMessage(message)
    local displayed = false
    pcall(function()
        local chatClass = ChatManager
        if not chatClass and luajava and luajava.bindClass then
            chatClass = luajava.bindClass("zombie.chat.ChatManager")
        end
        local chat = chatClass and chatClass.getInstance and chatClass.getInstance()
        if chat and (not chat.isWorking or chat:isWorking()) then
            chat:showServerChatMessage(message)
            displayed = true
        end
    end)
    return displayed
end

-- Adds a local chat-line on every connected client without using
-- showServerChatMessage(), whose ServerChatMessage is rendered as a red
-- server alert by Build 42. The server already broadcasts JoinAnnouncement
-- to every client, so this remains a server-wide in-game chat message.
local function showChatOnlyMessage(author, message)
    local displayed = false
    pcall(function()
        local chatClass = ChatManager
        if not chatClass and luajava and luajava.bindClass then
            chatClass = luajava.bindClass("zombie.chat.ChatManager")
        end
        local chat = chatClass and chatClass.getInstance and chatClass.getInstance()
        if chat and (not chat.isWorking or chat:isWorking()) then
            chat:addMessage(tostring(author or "Survivor League"), tostring(message or ""))
            displayed = true
        end
    end)
    return displayed
end

local function showJoinAnnouncement(args)
    local message = tostring(args and args.message or "A survivor has connected.")
    print("[SurvivorLeagueCommunityJoin] " .. message)
    if not showChatOnlyMessage("Survivor League", message) then
        table.insert(pendingJoinMessages, { message = message, attempts = 0 })
    end
end

local function retryPendingJoinAnnouncements(player)
    if #pendingJoinMessages == 0 then return end
    if player and getPlayer() and player ~= getPlayer() then return end

    joinMessageRetryTicks = joinMessageRetryTicks + 1
    if joinMessageRetryTicks % 30 ~= 0 then return end

    local pending = pendingJoinMessages[1]
    pending.attempts = pending.attempts + 1
    if showChatOnlyMessage("Survivor League", pending.message) then
        table.remove(pendingJoinMessages, 1)
    elseif pending.attempts >= 20 then
        print("[SurvivorLeagueCommunityJoin] Chat unavailable; discarded queued announcement")
        table.remove(pendingJoinMessages, 1)
    end
end

local function showDeathAnnouncement(args)
    local player = getPlayer()
    local message = tostring(args and args.message or "A survivor has died.")
    print("[SurvivorLeagueDeath] " .. message)
    if not args or args.showChat ~= false then showServerChatMessage(message) end
    if args and args.showHalo == true and player then pcall(function() player:setHaloNote(message) end) end
end

local function onServerCommand(module, command, args)
    if module ~= SL.MODULE then return end

    if command == "Leaderboard" then
        showBoard(args)
    elseif command == "JoinAnnouncement" then
        showJoinAnnouncement(args)
    elseif command == "DeathAnnouncement" then
        showDeathAnnouncement(args)
    elseif command == "RecoveryPreviewResult" then
        local message
        if args and args.ok == true then
            message = "Recovery export completed: "..tostring(args.canonical or 0).." current and "..tostring(args.legacy or 0).." legacy records. Check the server log."
        else
            message = "Recovery export failed: "..tostring(args and args.reason or "unknown error")
        end
        print("[SurvivorLeagueCommunityRecovery] "..message)
        showServerChatMessage(message)
    elseif command == "PlayerReadyAck" then
        if tonumber(args and args.protocol) == SL.PROTOCOL_VERSION and tonumber(args and args.version) == SL.VERSION then
            protocolCompatible = true
            playerReadyPending = false
            print("[SurvivorLeagueCommunity] Client/server handshake accepted; F6 ready")
            if openAfterHandshake then
                openAfterHandshake = false
                refreshBoard()
            end
        end
    elseif command == "KillReportAck" then
        local acknowledged = math.max(0, math.floor(tonumber(args and args.kills) or 0))
        if args and args.accepted == true then
            lastAcknowledgedKills = acknowledged
            if pendingReportedKills == acknowledged then pendingReportedKills = nil end
        else
            lastReportedKills = -1
        end
    elseif command == "ProtocolMismatch" then
        protocolCompatible = false
        playerReadyPending = false
        showServerChatMessage("Survivor League client/server versions do not match. Update the mod before using the Command Center.")
    elseif command == "MilestoneReward" then
        showServerChatMessage(
            "Kill-streak reward received: tier #"
                .. tostring(args.tier)
                .. " at "
                .. tostring(args.threshold)
                .. " kills"
        )
    elseif command == "RewardGranted" then
        showServerChatMessage(
            "Survivor League reward received: place #"
                .. tostring(args.place)
        )
    elseif command == "ScoreCorrectionResult" then
        showServerChatMessage(args and args.ok and ("Survivor League score corrected for "..tostring(args.username)) or ("Score correction failed: "..tostring(args and args.reason or "unknown")))
    elseif command == "ScoreReset"
        and getPlayer()
        and args.username == SL.playerKey(getPlayer())
    then
        showServerChatMessage("Kill streak reset on death. Season and total kills preserved.")
    elseif command == "SeasonSettled" then
        showServerChatMessage("Survivor League season settled. A new season has begun.")
    end
end

local function reportPlayerReady(playerIndex, player)
    beginPlayerReady(playerIndex, player)
end

local function retryPlayerReady(player)
    if not playerReadyPending then return end
    if player and getPlayer() and player ~= getPlayer() then return end
    if not getPlayer() then return end
    playerReadyTicks = playerReadyTicks + 1
    if playerReadyTicks % 300 ~= 0 then return end
    playerReadyAttempts = playerReadyAttempts + 1
    sendClientCommand(SL.MODULE, "PlayerReady", { protocol = SL.PROTOCOL_VERSION, version = SL.VERSION })
end

local function onKeyPressed(key)
    if key ~= SL.getOptions().interfaceKey then return end
    if not protocolCompatible then
        openAfterHandshake = true
        beginPlayerReady(nil, getPlayer and getPlayer())
        return
    end
    if panel then closeBoard(panel) else refreshBoard() end
end

local function reportLocalDeath(player)
    if not SL.getOptions().allowClientDeathReports then return end
    local p = player or getPlayer()
    if not p then return end
    reportLocalKills(true)
    print("[SurvivorLeagueDeathRelay] Reporting local death to server")
    local kills = 0
    pcall(function() kills = math.max(0, math.floor(tonumber(p:getZombieKills()) or 0)) end)
    sendClientCommand(SL.MODULE, "ReportDeath", { kills = kills })
    lastReportedKills = -1
    lastAcknowledgedKills = -1
    pendingReportedKills = nil
    lastKillReportAt = 0
end

local function pollLocalKills(player)
    if player and getPlayer() and player ~= getPlayer() then return end
    killPollTicks = killPollTicks + 1
    if killPollTicks % 120 == 0 then reportLocalKills(false) end
end

Events.OnServerCommand.Add(onServerCommand)
Events.OnKeyPressed.Add(onKeyPressed)
print("[SurvivorLeagueCommunity] Client loaded; interfaceKey="..tostring(SL.getOptions().interfaceKey))
Events.OnPlayerUpdate.Add(pollLocalKills)
Events.OnPlayerUpdate.Add(retryPlayerReady)
Events.OnPlayerUpdate.Add(retryPendingJoinAnnouncements)
if Events.OnPlayerDeath then Events.OnPlayerDeath.Add(reportLocalDeath) end
if Events.OnCreatePlayer then Events.OnCreatePlayer.Add(reportPlayerReady) end
