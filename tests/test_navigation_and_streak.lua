local compile = loadstring or load
local function read(path)
    local f = assert(io.open(path, 'r')); local s=f:read('*a'); f:close(); return s
end
local client=read('42/media/lua/client/SurvivorLeagueCommunity_Client.lua')
local server=read('42/media/lua/server/SurvivorLeagueCommunity_Server.lua')
-- Exercise the actual queue and panel methods with game services stubbed.
local queue=assert(client:match('(local function flushBoardRequest%(%).*\n)local function countdown'))
local paging=assert(client:match('(function LeaderboardPanel:setPage%(page%).-function LeaderboardPanel:onNextPage%(%)[^\n]+)'))
local close=assert(client:match('(local function closeBoard%(target%).-\nend)'))
local show=assert(client:match('(local function showBoard%(payload%).-\nend)'))
local harness=[[
local clock=100
local sent={}
local SL={now=function() return clock end, MODULE='test'}
local protocolCompatible=true
local pendingBoardRequest=nil
local lastBoardRequestAt=0
local currentBoardPage=1
local currentBoardSearch=''
local boardRequestSequence=0
local latestAppliedBoardRequest=0
local rowsPerPageForHeight=function() return 7 end
local reportLocalKills=function() end
local getCore=function() return {getScreenHeight=function() return 720 end} end
local sendClientCommand=function(_,_,request) sent[#sent+1]=request end
local LeaderboardPanel={}
local panel
]]..queue..'\n'..paging..'\n'..close..'\n'..show..'\n'..[[
local function board(page)
 local o={currentPage=page}
 function o:getPageCount() return 6 end
 function o:getRowsPerPage() return 7 end
 function o:updateControls() end
 function o:removeFromUIManager() end
 function o:setVisible() end
 function o:initialise() end
 function o:addToUIManager() end
 return setmetatable(o,{__index=LeaderboardPanel})
end
function LeaderboardPanel:new(payload) return board(payload.page) end
panel=board(1)
refreshBoard(1,'',7)
assert(#sent==1)
panel:onNextPage()
assert(currentBoardPage==2 and panel.currentPage==1 and #sent==1)
showBoard({page=1,requestId=1})
assert(panel.currentPage==1 and currentBoardPage==2, 'superseded response accepted')
clock=102; flushBoardRequest()
assert(#sent==2 and sent[2].page==2)
showBoard({page=2,requestId=sent[2].requestId})
assert(panel.currentPage==2)
panel:onPreviousPage()
assert(currentBoardPage==1 and panel.currentPage==2)
clock=104; flushBoardRequest()
assert(#sent==3 and sent[3].page==1, 'rapid back click lost')
showBoard({page=1,requestId=sent[3].requestId})
assert(panel.currentPage==1)
panel:setPage(6); panel:onPreviousPage(); panel:onPreviousPage()
clock=106; flushBoardRequest()
assert(sent[4].page==4, 'latest queued navigation lost')
local late=sent[4].requestId
panel:onPreviousPage(); closeBoard(panel)
clock=108; flushBoardRequest()
assert(#sent==4 and panel==nil, 'closed board sent pending request')
showBoard({page=4,requestId=late})
assert(panel==nil, 'closed board reopened by late response')
]]
assert(compile(harness))()
local reset=assert(server:match('(local function resetStreak%(record%).-\nend)'))
local reconcile=assert(server:match('(local function reconcileCurrentLife%(record, current, key, source%).-\nend)'))
assert(compile("local SL={now=function() return 100 end}\n"..reset..'\n'..reconcile..'\n'..[[
local r={streakKills=250, bestStreak=200, totalKills=500}
resetStreak(r)
assert(r.bestStreak==250 and r.streakKills==0 and r.totalKills==500)
r.streakKills=20; resetStreak(r)
assert(r.bestStreak==250, 'later death reduced record')
r.streakKills=300; reconcileCurrentLife(r, 2, 'test', 'test')
assert(r.bestStreak==300, 'reconciliation lost previous high')
resetStreak(r)
assert(r.bestStreak==300)
]]))()
print('Navigation and best-streak regression tests passed')
