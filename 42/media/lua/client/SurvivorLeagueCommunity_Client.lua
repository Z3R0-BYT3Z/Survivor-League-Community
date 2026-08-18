require "SurvivorLeagueCommunity_Config"
require "ISUI/ISPanel"
require "ISUI/ISButton"

local SL = SurvivorLeagueCommunity
local panel
local currentBoardPage = 1
local lastReportedKills = -1
local killPollTicks = 0
local playerReadyPending = true
local playerReadyAttempts = 0
local playerReadyTicks = 0
local C = {
    bg={0.035,0.035,0.045,0.97}, panel={0.065,0.065,0.080,0.96},
    rowA={0.085,0.085,0.100,0.92}, rowB={0.055,0.055,0.068,0.92},
    accent={0.92,0.92,0.92,1.0}, silver={0.77,0.79,0.82,1.0}, bronze={0.77,0.48,0.27,1.0},
    text={0.92,0.92,0.95,1.0}, muted={0.58,0.59,0.64,1.0}, line={0.20,0.20,0.24,0.85},
}

local function closeBoard(target)
    target:setVisible(false); target:removeFromUIManager(); panel = nil; currentBoardPage = 1
end

local function reportLocalKills(force)
    local opts = SL.getOptions()
    if not opts.enabled or not opts.allowClientKillReports then return end
    local player = getPlayer()
    if not player then return end
    local kills = 0
    local ok = pcall(function() kills = math.max(0, math.floor(tonumber(player:getZombieKills()) or 0)) end)
    if not ok then return end
    if force or kills ~= lastReportedKills then
        lastReportedKills = kills
        sendClientCommand(SL.MODULE, "ReportKills", { kills = kills })
    end
end

local function refreshBoard()
    if not SL.getOptions().enabled then return end
    reportLocalKills(true)
    sendClientCommand(SL.MODULE, "RequestLeaderboard", {})
end

local function countdown(endsAt)
    local seconds = math.max(0, (tonumber(endsAt) or 0) - SL.now())
    return string.format("%dd %02dh %02dm remaining", math.floor(seconds/86400), math.floor((seconds%86400)/3600), math.floor((seconds%3600)/60))
end

local LeaderboardPanel = ISPanel:derive("SurvivorLeagueCommunityPanel")

function LeaderboardPanel:new(payload)
    local screenW, screenH = getCore():getScreenWidth(), getCore():getScreenHeight()
    local width, height = 1040, 610
    local o = ISPanel.new(self, (screenW-width)/2, (screenH-height)/2, width, height)
    o.payload = payload or {rows={},rewards={}}
    o.backgroundColor = {r=C.bg[1],g=C.bg[2],b=C.bg[3],a=C.bg[4]}
    o.borderColor = {r=C.accent[1],g=C.accent[2],b=C.accent[3],a=0.9}
    o.frameTexture = getTexture("media/ui/SurvivorLeagueCommunity/leaderboard_frame.png")
    o.moveWithMouse = true
    o.currentPage = currentBoardPage
    return o
end

function LeaderboardPanel:getPageCount()
    local rowCount = #(self.payload.rows or {})
    if rowCount <= 3 then return 1 end
    return 1 + math.ceil((rowCount - 3) / 5)
end

function LeaderboardPanel:setPage(page)
    self.currentPage = math.max(1, math.min(tonumber(page) or 1, self:getPageCount()))
    currentBoardPage = self.currentPage
    if self.previousPage then self.previousPage.enable = self.currentPage > 1 end
    if self.nextPage then self.nextPage.enable = self.currentPage < self:getPageCount() end
end

function LeaderboardPanel:onPreviousPage()
    self:setPage(self.currentPage - 1)
end

function LeaderboardPanel:onNextPage()
    self:setPage(self.currentPage + 1)
end

function LeaderboardPanel:createChildren()
    ISPanel.createChildren(self)
    self.previousPage = ISButton:new(263,508,48,30,"<",self,LeaderboardPanel.onPreviousPage)
    self.previousPage:initialise()
    self.previousPage.backgroundColor={r=0,g=0,b=0,a=0.35}
    self.previousPage.backgroundColorMouseOver={r=0.92,g=0.92,b=0.92,a=0.12}
    self.previousPage.borderColor={r=0.92,g=0.92,b=0.92,a=0.8}
    self:addChild(self.previousPage)

    self.nextPage = ISButton:new(383,508,48,30,">",self,LeaderboardPanel.onNextPage)
    self.nextPage:initialise()
    self.nextPage.backgroundColor={r=0,g=0,b=0,a=0.35}
    self.nextPage.backgroundColorMouseOver={r=0.92,g=0.92,b=0.92,a=0.12}
    self.nextPage.borderColor={r=0.92,g=0.92,b=0.92,a=0.8}
    self:addChild(self.nextPage)

    self.refresh = ISButton:new(842,565,176,32,"",self,refreshBoard)
    self.refresh:initialise()
    self.refresh.backgroundColor={r=0,g=0,b=0,a=0}
    self.refresh.backgroundColorMouseOver={r=0.92,g=0.92,b=0.92,a=0.12}
    self.refresh.borderColor={r=0.92,g=0.92,b=0.92,a=0}
    self:addChild(self.refresh)
    self:setPage(self.currentPage)
end

local function rankColor(rank)
    if rank==1 then return C.accent elseif rank==2 then return C.silver elseif rank==3 then return C.bronze end
    return C.text
end

local function drawCorners(self,x,y,w,h,color)
    local r,g,b,a=color[1],color[2],color[3],color[4] or 1
    local n=18
    self:drawRect(x,y,n,2,a,r,g,b); self:drawRect(x,y,2,n,a,r,g,b)
    self:drawRect(x+w-n,y,n,2,a,r,g,b); self:drawRect(x+w-2,y,2,n,a,r,g,b)
    self:drawRect(x,y+h-2,n,2,a,r,g,b); self:drawRect(x,y+h-n,2,n,a,r,g,b)
    self:drawRect(x+w-n,y+h-2,n,2,a,r,g,b); self:drawRect(x+w-2,y+h-n,2,n,a,r,g,b)
end

function LeaderboardPanel:prerender()
    ISPanel.prerender(self)
    if self.frameTexture then self:drawTextureScaled(self.frameTexture,0,0,1040,610,1,1,1,1) end
    self:drawTextRight("Season #"..tostring(self.payload.seasonId or "?"),1008,102,C.text[1],C.text[2],C.text[3],1,UIFont.Medium)
    self:drawTextRight(countdown(self.payload.endsAt),1008,137,C.accent[1],C.accent[2],C.accent[3],1,UIFont.Small)
    local rows = self.payload.rows or {}
    local pageCount = self:getPageCount()
    self.currentPage = math.max(1, math.min(self.currentPage or 1, pageCount))
    local firstRank = self.currentPage == 1 and 1 or 4 + ((self.currentPage - 2) * 5)
    local rowsOnPage = self.currentPage == 1 and 3 or 5
    local lastRank = math.min(#rows, firstRank + rowsOnPage - 1)
    local rowH, rowTop = 40, 218
    for rank=firstRank,lastRank do
        local visibleIndex = rank - firstRank + 1
        local row, y = rows[rank], rowTop+(visibleIndex-1)*rowH
        local fill = (visibleIndex%2==1) and C.rowA or C.rowB
        local mine = tostring(row.username or "")==tostring(self.payload.username or "")
        local accent = rankColor(rank)
        if rank==1 then fill={0.12,0.12,0.12,0.94} end
        self:drawRect(34,y,626,rowH-3,fill[4],fill[1],fill[2],fill[3])
        self:drawRectBorder(34,y,626,rowH-3,mine and 1 or 0.35,mine and C.accent[1] or C.line[1],mine and C.accent[2] or C.line[2],mine and C.accent[3] or C.line[3])
        self:drawRectBorder(42,y+5,42,27,0.9,accent[1],accent[2],accent[3])
        self:drawTextCentre(tostring(rank),63,y+8,accent[1],accent[2],accent[3],1,UIFont.Medium)
        self:drawText(tostring(row.displayName or row.username),108,y+8,C.text[1],C.text[2],C.text[3],1,UIFont.Medium)
        if mine then self:drawText("YOUR RANK",285,y+10,C.accent[1],C.accent[2],C.accent[3],1,UIFont.Small) end
        self:drawTextRight(tostring(row.kills or 0),520,y+8,C.text[1],C.text[2],C.text[3],1,UIFont.Medium)
        self:drawTextRight(tostring(row.totalKills or 0),650,y+8,C.text[1],C.text[2],C.text[3],1,UIFont.Medium)
    end
    self:drawTextCentre(tostring(self.currentPage).." / "..tostring(pageCount),347,515,C.text[1],C.text[2],C.text[3],1,UIFont.Small)
    local labels={"1ST","2ND","3RD"}
    for place=1,3 do
        local y, accent = 225+(place-1)*96, rankColor(place)
        self:drawRect(704,y,300,78,0.82,C.rowB[1],C.rowB[2],C.rowB[3])
        self:drawRectBorder(704,y,300,78,0.8,accent[1],accent[2],accent[3])
        self:drawRectBorder(718,y+12,66,43,0.95,accent[1],accent[2],accent[3])
        self:drawTextCentre(labels[place],751,y+20,accent[1],accent[2],accent[3],1,UIFont.Large)
        self:drawText(tostring((self.payload.rewards or {})[place] or "No reward configured"),800,y+29,C.text[1],C.text[2],C.text[3],1,UIFont.Small)
    end
end

local function showBoard(payload)
    if panel then
        panel:removeFromUIManager()
    end

    panel = LeaderboardPanel:new(payload)
    panel:initialise()
    panel:addToUIManager()
end

local function showServerChatMessage(message)
    local displayed = false
    pcall(function()
        local chatClass = ChatManager
        if not chatClass and luajava and luajava.bindClass then
            chatClass = luajava.bindClass("zombie.chat.ChatManager")
        end
        local chat = chatClass and chatClass.getInstance and chatClass.getInstance()
        if chat then
            chat:showServerChatMessage(message)
            displayed = true
        end
    end)
    return displayed
end

local function showJoinAnnouncement(args)
    local player = getPlayer()
    local message = tostring(args and args.message or "A survivor has connected.")
    print("[SurvivorLeagueCommunityJoin] " .. message)
    if not showServerChatMessage(message) and player then
        pcall(function() player:setHaloNote(message) end)
    end
end

local function showDeathAnnouncement(args)
    local player = getPlayer()
    local message = tostring(args and args.message or "A survivor has died.")
    print("[SurvivorLeagueDeath] " .. message)
    showServerChatMessage(message)
    if player then pcall(function() player:setHaloNote(message) end) end
end

local function onServerCommand(module, command, args)
    if module ~= SL.MODULE then return end

    if command == "Leaderboard" then
        showBoard(args)
    elseif command == "JoinAnnouncement" then
        showJoinAnnouncement(args)
    elseif command == "DeathAnnouncement" then
        showDeathAnnouncement(args)
    elseif command == "PlayerReadyAck" then
        playerReadyPending = false
    elseif command == "MilestoneReward" and getPlayer() then
        getPlayer():Say(
            "Kill-streak reward received: tier #"
                .. tostring(args.tier)
                .. " at "
                .. tostring(args.threshold)
                .. " kills"
        )
    elseif command == "RewardGranted" and getPlayer() then
        getPlayer():Say(
            "Survivor League reward received: place #"
                .. tostring(args.place)
        )
    elseif command == "ScoreReset"
        and getPlayer()
        and args.username == SL.playerKey(getPlayer())
    then
        getPlayer():Say("Season kills reset on death. Total kills preserved.")
    elseif command == "SeasonSettled" and getPlayer() then
        getPlayer():Say("Survivor League season settled. A new season has begun.")
    end
end

local function reportPlayerReady(playerIndex, player)
    local p = player or (getSpecificPlayer and getSpecificPlayer(playerIndex)) or getPlayer()
    if not p then return end
    playerReadyPending = true
    playerReadyAttempts = 0
    playerReadyTicks = 0
end

local function retryPlayerReady(player)
    if not SL.getOptions().enabled then
        playerReadyPending = false
        return
    end
    if not playerReadyPending or playerReadyAttempts >= 10 then return end
    if player and getPlayer() and player ~= getPlayer() then return end
    if not getPlayer() then return end
    playerReadyTicks = playerReadyTicks + 1
    if playerReadyTicks % 60 ~= 0 then return end
    playerReadyAttempts = playerReadyAttempts + 1
    sendClientCommand(SL.MODULE, "PlayerReady", {})
end

local function onKeyPressed(key)
    if key~=64 or not SL.getOptions().enabled then return end
    if panel then closeBoard(panel) else refreshBoard() end
end

local function reportLocalDeath(player)
    local opts = SL.getOptions()
    if not opts.enabled or not opts.allowClientDeathReports then return end
    local p = player or getPlayer()
    if not p then return end
    local survived = 0
    pcall(function() survived = tonumber(p:getHoursSurvived()) or 0 end)
    reportLocalKills(true)
    print("[SurvivorLeagueDeathRelay] Reporting local death to server")
    sendClientCommand(SL.MODULE, "ReportDeath", { survived = survived })
    lastReportedKills = -1
end

local function pollLocalKills(player)
    if player and getPlayer() and player ~= getPlayer() then return end
    killPollTicks = killPollTicks + 1
    if killPollTicks % 120 == 0 then reportLocalKills(false) end
end

Events.OnServerCommand.Add(onServerCommand)
Events.OnKeyPressed.Add(onKeyPressed)
Events.OnPlayerUpdate.Add(pollLocalKills)
Events.OnPlayerUpdate.Add(retryPlayerReady)
if Events.OnPlayerDeath then Events.OnPlayerDeath.Add(reportLocalDeath) end
if Events.OnCreatePlayer then Events.OnCreatePlayer.Add(reportPlayerReady) end
