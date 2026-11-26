-- DuoRoute: Zygor-style step viewer that follows your play
local ADDON, DR = ...
local F = DR.F
local Guide = {}
DR.Guide = Guide

local routes = {}          -- routes.solo, routes.duo
local route                -- the one being shown
local building
local frame, header, cur, curSub, nextLines, progress, goBtn, skipBtn, modeBtn
local lastStep

local CLASS_TIPS = {
  [1] = "Warrior: Arms for levelling. Chain-pull with Sweeping Strikes and keep bandages handy.",
  [2] = "Paladin: Retribution for levelling. Seal of Command plus Judgement, and tank packs with Consecration.",
  [3] = "Hunter: Beast Mastery levels fastest. Let your pet hold aggro and keep ammo stocked.",
  [4] = "Rogue: Combat for levelling. Use Sap and Gouge to split pulls.",
  [5] = "Priest: Shadow for levelling. Wand between Mind Blasts to save mana.",
  [7] = "Shaman: Enhancement for levelling. Windfury weapon and Searing Totem on packs.",
  [8] = "Mage: Frost for levelling. AoE-grind packs with Blizzard and Frost Nova.",
  [9] = "Warlock: Affliction levels fastest in Forever. Drain-tank with your Voidwalker and Life Tap freely.",
  [11] = "Druid: Feral for levelling. Cat form for solo, bear form for big pulls.",
}

local KIND_ICON = {
  accept = "|TInterface\\GossipFrame\\AvailableQuestIcon:14|t",
  turnin = "|TInterface\\GossipFrame\\ActiveQuestIcon:14|t",
  obj = "|TInterface\\Icons\\Ability_Hunter_SniperShot:14|t",
  work = "|TInterface\\Icons\\Ability_Hunter_SniperShot:14|t",
  travel = "|TInterface\\Minimap\\Tracking\\FlightMaster:14|t",
  fp = "|TInterface\\Minimap\\Tracking\\FlightMaster:14|t",
  train = "|TInterface\\Minimap\\Tracking\\Class:14|t",
}

local function Coords(st)
  if st.area and st.x then return string.format("%s %.1f, %.1f", DR.ZoneName(st.area), st.x, st.y) end
  if st.area then return DR.ZoneName(st.area) end
  return ""
end

-- Where a step wants you to end up (travel steps aim at the first thing you'll do there)
local function StepTarget(st)
  if st.x then return st.area, st.x, st.y end
  if st.kind == "travel" and route then
    for j = (route.cursor or 1) + 1, math.min(#route.steps, (route.cursor or 1) + 6) do
      local n = route.steps[j]
      if n.area == st.area and n.x then return n.area, n.x, n.y end
    end
    local ax, ay = DR.Travel.Anchor(st.area, DR.me.faction)
    return st.area, ax, ay
  end
  return st.area, nil, nil
end

-- Legs from where you are, when the step is in another zone (or is a travel step)
local function Directions(st)
  if not st or not st.area then return nil end
  local u = DR.UiMapForArea(st.area)
  if st.kind ~= "travel" and u == DR.me.mapID then return nil end
  if UnitOnTaxi and UnitOnTaxi("player") then return { { kind = "taxi", minutes = 0 } } end
  local area, x, y = StepTarget(st)
  return DR.Travel.Directions(area, x, y)
end
Guide.Directions = Directions

local function LegTarget(leg)
  if leg and leg.to and leg.to.area then return leg.to.area, leg.to.zx, leg.to.zy end
end

local function Waypoint(st, silent)
  if not st then return end
  local legs = Directions(st)
  if legs and legs[1] and legs[1].to then
    local a, x, y = LegTarget(legs[1])
    DR.SetWaypoint(a, x, y, DR.Travel.LegText(legs[1]), silent)
    return
  end
  local area, x, y = StepTarget(st)
  if x and area then DR.SetWaypoint(area, x, y, st.quest or st.text, silent) end
end

---------------------------------------------------------------------------
-- building (spread over frames so the game doesn't stutter)
---------------------------------------------------------------------------
local function PartnerOnline()
  local p = DR.Sync and DR.Sync.Partner()
  return p ~= nil and not p.offline and p.completed ~= nil and next(p.completed) ~= nil
end

local function PickRoute()
  local mode = DuoRouteDB.guideMode or "auto"
  if mode == "solo" then route = routes.solo
  elseif mode == "duo" then route = routes.duo or routes.solo
  else route = routes.duo or routes.solo end
end

function Guide.Rebuild(reason)
  if building then return end
  DR.RefreshMe(false)
  building = coroutine.create(function()
    local solo = DR.BuildRoute(true)
    local duo = PartnerOnline() and DR.BuildRoute(false) or nil
    return { solo = solo, duo = duo }
  end)
  local ticker
  ticker = C_Timer.NewTicker(0.01, function()
    local ok, result = coroutine.resume(building)
    if not ok then
      ticker:Cancel(); building = nil
      DR.Msg("Couldn't build the route:", tostring(result))
      return
    end
    if coroutine.status(building) == "dead" then
      ticker:Cancel(); building = nil
      routes = result
      PickRoute()
      lastStep = nil
      DR.Debug("routes built", reason or "")
      Guide.Refresh()
      if DR.UI then DR.UI.Refresh() end
    end
  end)
end

function Guide.Route() return route end
function Guide.CurrentStep() return route and route.steps[route.cursor or 1] end
function Guide.Routes() return routes end

function Guide.SetMode(mode)
  DuoRouteDB.guideMode = mode
  PickRoute()
  lastStep = nil
  Guide.Refresh()
end

-- "Duo 41h · Solo 52h" style summary, used by the guide and the planner
local function H(h)
  if not h then return "?" end
  if h < 1 then return math.floor(h * 60 + 0.5) .. "m" end
  return string.format("%.0fh", h)
end
Guide.H = H

function Guide.EstimateText()
  for _, r in pairs(routes) do DR.AdvanceRoute(r) end
  local parts = {}
  if routes.duo then parts[#parts + 1] = "Duo ~" .. H(DR.RouteHours(routes.duo)) end
  if routes.solo then parts[#parts + 1] = "Solo ~" .. H(DR.RouteHours(routes.solo)) end
  local pace = DR.PaceHours()
  if pace then parts[#parts + 1] = "your pace ~" .. H(pace) end
  return table.concat(parts, " · ")
end

---------------------------------------------------------------------------
-- window
---------------------------------------------------------------------------
local function Build()
  frame = CreateFrame("Frame", "DuoRouteGuideFrame", UIParent, "BackdropTemplate")
  frame:SetSize(360, 178)
  frame:SetFrameStrata("MEDIUM")
  frame:SetMovable(true); frame:EnableMouse(true); frame:SetClampedToScreen(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    DuoRouteDB.ui.guidePoint = { p, rp, x, y }
  end)
  if frame.SetBackdrop then
    frame:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    frame:SetBackdropColor(0.05, 0.05, 0.08, 0.85)
    frame:SetBackdropBorderColor(0.4, 0.6, 0.9, 0.9)
  end
  local pt = DuoRouteDB.ui.guidePoint
  if pt then frame:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4]) else frame:SetPoint("RIGHT", -60, 120) end

  header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  header:SetPoint("TOPLEFT", 10, -8); header:SetPoint("RIGHT", -76, 0); header:SetJustifyH("LEFT")
  header:SetScript("OnEnter", nil)

  cur = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  local est = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  est:SetPoint("TOPLEFT", 10, -24); est:SetPoint("RIGHT", -10, 0); est:SetJustifyH("LEFT")
  frame.est = est
  cur:SetPoint("TOPLEFT", 10, -42); cur:SetPoint("RIGHT", -10, 0); cur:SetJustifyH("LEFT")
  curSub = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  curSub:SetPoint("TOPLEFT", cur, "BOTTOMLEFT", 0, -3); curSub:SetPoint("RIGHT", -10, 0); curSub:SetJustifyH("LEFT")
  curSub:SetWordWrap(true); curSub:SetMaxLines(2)

  nextLines = {}
  for i = 1, 3 do
    local l = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    l:SetPoint("TOPLEFT", 14, -92 - (i - 1) * 14); l:SetPoint("RIGHT", -10, 0); l:SetJustifyH("LEFT")
    nextLines[i] = l
  end

  progress = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  progress:SetPoint("BOTTOMLEFT", 10, 9)

  local function Btn(text, w)
    local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    b:SetSize(w, 20); b:SetText(text)
    return b
  end
  local plan = Btn("Planner", 62); plan:SetPoint("BOTTOMRIGHT", -8, 6)
  plan:SetScript("OnClick", function() DR.UI.Toggle() end)
  local reroute = Btn("Reroute", 62); reroute:SetPoint("RIGHT", plan, "LEFT", -3, 0)
  reroute:SetScript("OnClick", function() DR.Msg("Recalculating your route..."); Guide.Rebuild("button") end)
  skipBtn = Btn("Skip", 44); skipBtn:SetPoint("RIGHT", reroute, "LEFT", -3, 0)
  skipBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  skipBtn:SetScript("OnClick", function(_, button)
    local st = route and route.steps[route.cursor or 1]
    if not st then return end
    local legs = Directions(st)
    if button == "RightButton" and legs then
      for _, l in ipairs(legs) do
        local fm = (l.to and l.to.fm) or (l.from and l.from.fm)
        if fm and (l.kind == "fly" or (l.kind == "walk" and l.to and l.to.fm)) then
          DR.Travel.Forget(fm[1])
          DR.Msg("Okay, you don't have the flight path at " .. fm[6] .. ". Rerouting.")
          Guide.Rebuild("flight path forgotten")
          return
        end
      end
    end
    if button == "RightButton" and st.id then
      DuoRouteChar.ignored[st.id] = true
      DR.Msg("Dropping " .. (DR.Q[st.id] and DR.Q[st.id][F.NAME] or "that quest") .. " from your route.")
      Guide.Rebuild("skip quest")
    else
      st.skipped = true
      Guide.Refresh()
    end
  end)
  skipBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Left-click: skip this step")
    GameTooltip:AddLine("Right-click: drop this quest from the route", 1, 1, 1)
    GameTooltip:AddLine("On a flight step, right-click if you don't have that flight path", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  skipBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  goBtn = Btn("Go", 36); goBtn:SetPoint("RIGHT", skipBtn, "LEFT", -3, 0)
  modeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  modeBtn:SetSize(64, 18)
  modeBtn:SetPoint("TOPRIGHT", -8, -6)
  modeBtn:SetScript("OnClick", function()
    if not routes.duo then DR.Msg("No duo route: your partner needs to be online and synced."); return end
    Guide.SetMode(route == routes.duo and "solo" or "duo")
  end)
  modeBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Switch between your solo and duo routes")
    GameTooltip:AddLine("Both stay up to date, so you can compare any time.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  modeBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  goBtn:SetScript("OnClick", function() Waypoint(route and route.steps[route.cursor or 1]) end)

  -- class tip on hover over the header area
  local tip = CreateFrame("Frame", nil, frame)
  tip:SetPoint("TOPLEFT", 4, -4); tip:SetPoint("TOPRIGHT", -4, -4); tip:SetHeight(18)
  tip:EnableMouse(true)
  tip:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Estimated time to 60")
    local solo, duo = routes.solo, routes.duo
    local function at(r, l)
      if not r or not r.levels[l] then return nil end
      return math.max(0, r.levels[l] - DR.RouteNow(r)) / 60
    end
    if duo and solo then
      GameTooltip:AddDoubleLine(" ", "Duo     Solo", 1, 1, 1, 1, 0.82, 0)
    end
    for l = (DR.me.level or 1) + 1, 60 do
      local d, so = at(duo, l), at(solo, l)
      if d or so then
        local right = duo and solo and string.format("%s     %s", H(d), H(so)) or H(d or so)
        GameTooltip:AddDoubleLine("Level " .. l, right, 1, 1, 1, 0.8, 0.8, 0.8)
      end
    end
    if duo and solo then
      local dh, sh = DR.RouteHours(duo), DR.RouteHours(solo)
      if dh and sh and sh > dh then
        GameTooltip:AddLine(string.format("Levelling together saves about %s.", H(sh - dh)), 0.4, 1, 0.4)
      end
    end
    local pace = DR.PaceHours()
    if pace then
      GameTooltip:AddLine(string.format("At your measured pace (%s XP/hr): ~%s to 60", math.floor(DR.MeasuredRate() / 100) / 10 .. "k", H(pace)), 0.6, 1, 0.6, true)
    else
      GameTooltip:AddLine("Your real pace shows here after about 30 minutes of levelling.", 0.6, 0.6, 0.6, true)
    end
    if route and route.endLevel < 60 then
      GameTooltip:AddLine("The plan runs out of quests at level " .. route.endLevel .. "; dungeons or grinding fill the rest.", 1, 0.6, 0.3, true)
    end
    local t = CLASS_TIPS[DR.me.classID or 0]
    if t then GameTooltip:AddLine(" "); GameTooltip:AddLine(t, 0.6, 0.9, 1, true) end
    GameTooltip:Show()
  end)
  tip:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function Guide.Refresh()
  if not frame or not frame:IsShown() then return end
  if not route then
    header:SetText("|cff66ccffDuoRoute Guide|r")
    frame.est:SetText("")
    cur:SetText(building and "Working out your fastest route..." or "No route yet. Press Reroute.")
    curSub:SetText(""); progress:SetText("")
    for i = 1, 3 do nextLines[i]:SetText("") end
    return
  end
  for _, r in pairs(routes) do DR.AdvanceRoute(r) end
  local st = route.steps[route.cursor or 1]
  local me = DR.me
  local pct = (me.xp or 0) / math.max(1, me.xpMax or 1) * 100
  header:SetText(string.format("|cff66ccffDuoRoute Guide|r  Level %d (%d%%)", me.level or 0, math.floor(pct)))
  frame.est:SetText("|cffffd100To 60:|r " .. Guide.EstimateText())
  modeBtn:SetText(route.duo and "Duo" or "Solo")
  modeBtn:SetEnabled(routes.duo ~= nil)
  if not st then
    if DR.Arrow then DR.Arrow.Clear() end
    cur:SetText(route.endLevel >= 60 and "Route complete!" or "Out of quests. Check the Dungeons tab, or press Reroute.")
    curSub:SetText(""); progress:SetText("")
    for i = 1, 3 do nextLines[i]:SetText("") end
    if not building and route.endLevel < 60 then C_Timer.After(2, function() Guide.Rebuild("end") end) end
    return
  end
  local legs = Directions(st)
  local legKey
  if legs and legs[1] and legs[1].kind == "taxi" then
    cur:SetText(KIND_ICON.travel .. " Flying... next: " .. DR.StepText(st))
    curSub:SetText("")
  elseif legs and #legs > 0 then
    local total = 0
    for _, l in ipairs(legs) do total = total + (l.minutes or 0) end
    local goalText = st.kind == "travel" and ("Head into " .. DR.ZoneName(st.area)) or nil
    local first = DR.Travel.LegText(legs[1], goalText)
    cur:SetText(KIND_ICON.travel .. " " .. first)
    local rest = {}
    for i = 2, math.min(#legs, 4) do rest[#rest + 1] = DR.Travel.LegText(legs[i], goalText) end
    local target = st.kind == "travel" and DR.ZoneName(st.area) or DR.StepText(st)
    local hint = ""
    if not DR.Travel.Scanned() then hint = " |cffff9933Talk to any flight master once so I can use your flight paths.|r" end
    curSub:SetText((#rest > 0 and ("then " .. table.concat(rest, ", then ") .. ". ") or "") ..
      string.format("|cffaaaaaa~%d min to reach: %s|r", math.max(1, math.floor(total + 0.5)), target) .. hint)
    local a, x, y = LegTarget(legs[1])
    legKey = tostring(a) .. ":" .. tostring(x) .. ":" .. tostring(y)
  else
    cur:SetText((KIND_ICON[st.kind] or "") .. " " .. DR.StepText(st))
    curSub:SetText(Coords(st))
  end
  for i = 1, 3 do
    local n = route.steps[route.cursor + i]
    nextLines[i]:SetText(n and ((KIND_ICON[n.kind] or "") .. " " .. DR.StepText(n)) or "")
  end
  progress:SetText(string.format("Step %d / %d", route.cursor, #route.steps))
  goBtn:SetEnabled(st.x ~= nil or st.kind == "travel" or (legs ~= nil and #legs > 0))
  local key = tostring(st) .. (legKey or "")
  if key ~= lastStep then
    lastStep = key
    if DuoRouteDB.autoWaypoint ~= false then Waypoint(st, true) end
  end
end

function Guide.Toggle(show)
  if not frame then Build() end
  if show == nil then show = not frame:IsShown() end
  if show then frame:Show(); DuoRouteDB.ui.guideHidden = nil; Guide.Refresh()
  else frame:Hide(); DuoRouteDB.ui.guideHidden = true end
end

---------------------------------------------------------------------------
-- events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_LEVEL_UP")
ev:RegisterEvent("TRAINER_SHOW")
ev:RegisterEvent("QUEST_TURNED_IN")
ev:RegisterEvent("QUEST_ACCEPTED")
-- Is this quest somewhere in what's left of the route?
local function InRoute(id)
  if not route then return false end
  for i = route.cursor or 1, #route.steps do
    if route.steps[i].id == id then return true end
  end
  return false
end

local pendingReplan
local function Replan(reason)
  if pendingReplan then return end
  pendingReplan = true
  C_Timer.After(2, function() pendingReplan = nil; Guide.Rebuild(reason) end)
end

ev:SetScript("OnEvent", function(_, event, a1, a2)
  if event == "PLAYER_LOGIN" then
    C_Timer.After(3, function()
      if not DuoRouteDB.ui.guideHidden then Guide.Toggle(true) end
      Guide.Rebuild("login")
    end)
  elseif event == "PLAYER_LEVEL_UP" then
    C_Timer.After(3, function() Guide.Rebuild("level up") end)
  elseif event == "TRAINER_SHOW" then
    DR.MarkTrained(); Guide.Refresh()
  elseif event == "QUEST_TURNED_IN" or event == "QUEST_ACCEPTED" then
    -- you did something the route didn't plan (an elite, a quest someone shared...):
    -- replan from where you are so follow-ups and new options show up right away
    local id = event == "QUEST_ACCEPTED" and (a2 or a1) or a1
    if type(id) == "number" and not InRoute(id) then Replan("off-route " .. id) end
  end
end)

-- called whenever your quest log or your partner's data changes
function Guide.OnStateChanged()
  if not route then return end
  local duo = PartnerOnline()
  if duo ~= (routes.duo ~= nil) and not building then
    Guide.Rebuild(duo and "partner joined" or "partner left")
    return
  end
  Guide.Refresh()
end
