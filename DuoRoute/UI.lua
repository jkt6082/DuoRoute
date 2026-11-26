-- DuoRoute: planner window
local ADDON, DR = ...
local F = DR.F
local UI = {}
DR.UI = UI

local W, H = 560, 520
local ZONE_W = 190
local ROW_H = 32
local MAX_ROWS = 120

local frame, statusText, nextText, nextBtn, zoneButtons, scroll, content, rows, learnedText
local tabButtons = {}
local mode = "zones"          -- zones | dungeons | learned
local selectedArea
local lastPlan, lastNext

local CLASS_NAMES = { "Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Death Knight", "Shaman", "Mage",
  "Warlock", "Monk", "Druid" }

local function fmtXP(v)
  if v >= 1000 then return string.format("%.1fk", v / 1000) end
  return tostring(math.floor(v + 0.5))
end

local function ago(t)
  if not t then return "never" end
  local d = time() - t
  if d < 60 then return d .. "s ago" end
  if d < 3600 then return math.floor(d / 60) .. "m ago" end
  return math.floor(d / 3600) .. "h ago"
end

---------------------------------------------------------------------------
-- construction
---------------------------------------------------------------------------
local function MakeButton(parent, text, w, h)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w, h)
  b:SetText(text)
  return b
end

local function Build()
  local ok
  ok, frame = pcall(CreateFrame, "Frame", "DuoRouteFrame", UIParent, "BasicFrameTemplateWithInset")
  if not ok then frame = CreateFrame("Frame", "DuoRouteFrame", UIParent, "BackdropTemplate") end
  frame:SetSize(W, H)
  frame:SetFrameStrata("MEDIUM")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:SetClampedToScreen(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    DuoRouteDB.ui.point = { p, rp, x, y }
  end)
  local pt = DuoRouteDB.ui.point
  if pt then frame:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4]) else frame:SetPoint("CENTER") end
  tinsert(UISpecialFrames, "DuoRouteFrame")
  frame:Hide()

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  title:SetPoint("TOP", 0, -5)
  title:SetText("DuoRoute: duo quest planner")
  frame.title = title

  statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  statusText:SetPoint("TOPLEFT", 14, -32)
  statusText:SetPoint("RIGHT", -14, 0)
  statusText:SetJustifyH("LEFT")

  nextBtn = MakeButton(frame, "Go", 44, 20)
  nextBtn:SetPoint("TOPRIGHT", -12, -48)
  nextBtn:SetScript("OnClick", function()
    if lastNext then DR.SetWaypoint(lastNext.area, lastNext.x, lastNext.y, lastNext.e.q[F.NAME]) end
  end)
  nextText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  nextText:SetPoint("TOPLEFT", 14, -52)
  nextText:SetPoint("RIGHT", nextBtn, "LEFT", -6, 0)
  nextText:SetJustifyH("LEFT")

  -- tabs
  local tabs = { { "zones", "Zones" }, { "dungeons", "Dungeons" }, { "learned", "What it's learned" } }
  local prev
  for _, t in ipairs(tabs) do
    local b = MakeButton(frame, t[2], t[1] == "learned" and 130 or 90, 22)
    if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", 12, -74) end
    b:SetScript("OnClick", function() mode = t[1]; selectedArea = nil; UI.Refresh() end)
    tabButtons[t[1]] = b
    prev = b
  end
  local sync = MakeButton(frame, "Sync", 60, 22)
  sync:SetPoint("TOPRIGHT", -12, -74)
  local guideBtn = MakeButton(frame, "Guide", 60, 22)
  guideBtn:SetPoint("RIGHT", sync, "LEFT", -4, 0)
  guideBtn:SetScript("OnClick", function() DR.Guide.Toggle() end)
  sync:SetScript("OnClick", function() DR.Sync.Force(); DR.Msg("Sync sent.") end)

  -- zone list (left)
  zoneButtons = {}
  for i = 1, 9 do
    local b = CreateFrame("Button", nil, frame)
    b:SetSize(ZONE_W, 44)
    b:SetPoint("TOPLEFT", 12, -102 - (i - 1) * 46)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(1, 1, 1, 0.05)
    b.bg = bg
    b.t1 = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.t1:SetPoint("TOPLEFT", 6, -5); b.t1:SetPoint("RIGHT", -4, 0); b.t1:SetJustifyH("LEFT")
    b.t2 = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.t2:SetPoint("TOPLEFT", b.t1, "BOTTOMLEFT", 0, -3); b.t2:SetPoint("RIGHT", -4, 0); b.t2:SetJustifyH("LEFT")
    b:SetScript("OnClick", function(self) selectedArea = self.area; UI.Refresh() end)
    b:SetScript("OnEnter", function(self)
      local z = self.zone
      if not z then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(DR.ZoneName(z.area))
      GameTooltip:AddLine(string.format("Estimated quest XP here: %s (about %.1f levels)", fmtXP(z.value), z.levels or 0), 1, 1, 1)
      GameTooltip:AddLine(string.format("%d quests you can both do, %d already in a log, %d to pick up", z.both, z.inlog, z.pickups), 1, 1, 1)
      if z.share > 0 then GameTooltip:AddLine(z.share .. " quests can be shared between you", 0.4, 0.9, 1) end
      if z.rate then GameTooltip:AddLine(string.format("Your measured rate here: %s XP/hour", fmtXP(z.rate)), 0.6, 1, 0.6) end
      if z.here then GameTooltip:AddLine("You are in this zone", 0.6, 1, 0.6) end
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    zoneButtons[i] = b
  end

  -- quest list (right)
  local okScroll
  okScroll, scroll = pcall(CreateFrame, "ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  if not okScroll then
    scroll = CreateFrame("ScrollFrame", nil, frame)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
      local max = math.max(0, content:GetHeight() - self:GetHeight())
      self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - delta * ROW_H * 3)))
    end)
  end
  scroll:SetPoint("TOPLEFT", ZONE_W + 20, -102)
  scroll:SetPoint("BOTTOMRIGHT", -32, 12)
  content = CreateFrame("Frame", nil, scroll)
  content:SetSize(W - ZONE_W - 56, 10)
  scroll:SetScrollChild(content)
  rows = {}

  learnedText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  learnedText:SetPoint("TOPLEFT", 16, -106)
  learnedText:SetPoint("BOTTOMRIGHT", -16, 12)
  learnedText:SetJustifyH("LEFT"); learnedText:SetJustifyV("TOP")
end

local function Row(i)
  local r = rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, content)
  r:SetSize(content:GetWidth(), ROW_H)
  r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  r.t1 = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  r.t1:SetPoint("TOPLEFT", 4, -3); r.t1:SetPoint("RIGHT", -4, 0); r.t1:SetJustifyH("LEFT")
  r.t2 = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  r.t2:SetPoint("TOPLEFT", r.t1, "BOTTOMLEFT", 0, -2); r.t2:SetPoint("RIGHT", -4, 0); r.t2:SetJustifyH("LEFT")
  r:SetScript("OnClick", function(self, button)
    local e = self.e
    if not e then return end
    if button == "RightButton" then
      DuoRouteChar.ignored[e.id] = true
      DR.Msg("Hid", e.q[F.NAME], "(/duo unhide to bring hidden quests back)")
      UI.Refresh()
      return
    end
    local q = e.q
    if e.s1 == "active" or e.s2 == "active" then
      DR.SetWaypoint(q[F.FZ], q[F.FX], q[F.FY], q[F.NAME] .. " (turn in)")
    else
      DR.SetWaypoint(q[F.SZ], q[F.SX], q[F.SY], q[F.NAME])
    end
  end)
  r:SetScript("OnEnter", function(self)
    local e = self.e
    if not e then return end
    local q = e.q
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(q[F.NAME])
    GameTooltip:AddLine(string.format("Quest level %d (requires %d)", q[F.LVL], q[F.REQ]), 1, 1, 1)
    local labels = { avail = "can pick up", active = "in quest log", soon = "available soon", locked = "needs an earlier quest", na = "not available", done = "done" }
    GameTooltip:AddLine("You: " .. (labels[e.s1] or e.s1), 1, 1, 1)
    if e.s2 then GameTooltip:AddLine("Partner: " .. (labels[e.s2] or e.s2), 1, 1, 1) end
    if q[F.SZ] > 0 then
      GameTooltip:AddLine(string.format("Starts: %s, %s %.0f, %.0f", q[F.STARTER] ~= "" and q[F.STARTER] or "?", DR.ZoneName(q[F.SZ]), q[F.SX], q[F.SY]), 0.8, 0.8, 0.8)
    end
    if q[F.FZ] > 0 then
      GameTooltip:AddLine(string.format("Turn in: %s %.0f, %.0f", DR.ZoneName(q[F.FZ]), q[F.FX], q[F.FY]), 0.8, 0.8, 0.8)
    end
    if e.share == "give" then GameTooltip:AddLine("Share this quest with your partner", 0.4, 0.9, 1) end
    if e.share == "ask" then GameTooltip:AddLine("Ask your partner to share this quest", 0.4, 0.9, 1) end
    if DuoRouteChar.skipped[e.id] then GameTooltip:AddLine("You abandoned this before, so it's ranked lower", 1, 0.5, 0.3) end
    GameTooltip:AddLine("Left-click: waypoint.  Right-click: hide.", 0.5, 0.5, 0.5)
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  rows[i] = r
  return r
end

---------------------------------------------------------------------------
-- rendering
---------------------------------------------------------------------------
local TAGS = { both = "|cff66ff66Both|r", you = "|cffffd100You only|r", partner = "|cffaaaaaaPartner only|r" }

local function RenderEntries(entries)
  DR.SortEntries(entries)
  local n = math.min(#entries, MAX_ROWS)
  for i = 1, n do
    local e, r = entries[i], Row(i)
    local q = e.q
    local color = "|cffffffff"
    local state = ""
    if e.complete then color = "|cff33ff33"; state = "Ready to turn in. "
    elseif e.s1 == "active" or e.s2 == "active" then color = "|cffffd100"; state = "In log. " end
    if e.share == "give" then state = state .. "|cff66ccffShare it.|r "
    elseif e.share == "ask" then state = state .. "|cff66ccffAsk partner to share.|r " end
    r.t1:SetText(string.format("%s[%d] %s|r", color, q[F.LVL], q[F.NAME]))
    local where = ""
    if not (e.s1 == "active" or e.s2 == "active") and q[F.STARTER] ~= "" then
      where = q[F.STARTER]
      if q[F.SZ] ~= DR.WorkZone(q) then where = where .. " in " .. DR.ZoneName(q[F.SZ]) end
      where = where .. " · "
    end
    r.t2:SetText(string.format("%s%s%s · ~%s XP", state, where, TAGS[e.tag] or "", fmtXP(e.xp)))
    r.e = e
    r:Show()
  end
  for i = n + 1, #rows do rows[i]:Hide(); rows[i].e = nil end
  content:SetHeight(math.max(10, n * ROW_H))
end

local function RenderLearned()
  local c = DuoRouteChar
  local lines = {}
  local h = c.history
  lines[#lines + 1] = string.format("|cffffd100Quests turned in (tracked):|r %d", #h)
  local cal = DR.Calibration()
  if c.calib.n >= 5 then
    lines[#lines + 1] = string.format("|cffffd100Quest XP vs database:|r Forever quests are giving you %d%% of the listed XP. Estimates are adjusted to match.", math.floor(cal * 100 + 0.5))
  else
    lines[#lines + 1] = string.format("|cffffd100Quest XP vs database:|r needs %d more turn-ins to calibrate.", 5 - c.calib.n)
  end
  local skipped = 0
  for _ in pairs(c.skipped) do skipped = skipped + 1 end
  local ignored = 0
  for _ in pairs(c.ignored) do ignored = ignored + 1 end
  lines[#lines + 1] = string.format("|cffffd100Abandoned quests (ranked lower):|r %d     |cffffd100Hidden:|r %d", skipped, ignored)
  lines[#lines + 1] = " "
  lines[#lines + 1] = "|cffffd100Your XP per hour by zone|r (time counts only while you're earning XP):"
  local stats = {}
  for map, s in pairs(c.zoneStats) do
    if s.secs >= 300 then
      local info = C_Map.GetMapInfo(map)
      stats[#stats + 1] = { name = info and info.name or tostring(map), rate = s.xp / s.secs * 3600, mins = s.secs / 60 }
    end
  end
  table.sort(stats, function(a, b) return a.rate > b.rate end)
  if #stats == 0 then lines[#lines + 1] = "  Not enough data yet. Keep questing and check back." end
  for i = 1, math.min(12, #stats) do
    local s = stats[i]
    lines[#lines + 1] = string.format("  %s: %s XP/hr  (%d min)", s.name, fmtXP(s.rate), math.floor(s.mins))
  end
  lines[#lines + 1] = " "
  lines[#lines + 1] = "|cffffd100Last turn-ins|r"
  for i = #h, math.max(1, #h - 6), -1 do
    local e = h[i]
    local q = DR.Q[e.q]
    lines[#lines + 1] = string.format("  %s: %s XP", q and q[F.NAME] or ("Quest " .. e.q), fmtXP(e.xp))
  end
  learnedText:SetText(table.concat(lines, "\n"))
end

function UI.Refresh()
  if not frame or not frame:IsShown() then return end
  local me = DR.me
  local partner = DR.Sync.Partner()
  local status = string.format("You: %d %s", me.level or 0, CLASS_NAMES[me.classID or 0] or "")
  if partner then
    status = status .. string.format("     Partner: %s %d %s (%s%s)", Ambiguate(partner.name, "short"), partner.level or 0,
      CLASS_NAMES[partner.classID or 0] or "", partner.offline and "offline, data from " or "synced ", ago(partner.updated))
  elseif IsInGroup() then
    status = status .. "     |cffff8800Partner hasn't synced. They need DuoRoute installed too.|r"
  else
    status = status .. "     |cffaaaaaaNo partner (planning solo)|r"
  end
  statusText:SetText(status)
  local est = DR.Guide and DR.Guide.Route() and DR.Guide.EstimateText() or ""
  frame.title:SetText("DuoRoute" .. (est ~= "" and ("   |cffffd100To 60:|r " .. est) or ": duo quest planner"))

  local plan = DR.Plan()
  lastPlan = plan
  lastNext = DR.NextStep(plan)
  if lastNext then
    nextText:SetText(string.format("|cff66ff66Next:|r %s %s (%s)", lastNext.verb, lastNext.e.q[F.NAME],
      lastNext.verb == "Turn in" and "turn-in spot" or (lastNext.e.q[F.STARTER] ~= "" and lastNext.e.q[F.STARTER] or "quest giver")))
    nextBtn:Show()
  else
    nextText:SetText("|cffaaaaaaNext: pick a zone below to see where to go.|r")
    nextBtn:Hide()
  end

  for k, b in pairs(tabButtons) do b:SetEnabled(k ~= mode) end

  if mode == "learned" then
    for _, b in ipairs(zoneButtons) do b:Hide() end
    scroll:Hide()
    learnedText:Show()
    RenderLearned()
    return
  end
  learnedText:Hide()
  scroll:Show()

  local list = mode == "dungeons" and plan.dungeons or plan.zones
  if not selectedArea and list[1] then selectedArea = list[1].area end
  local selected
  for i, b in ipairs(zoneButtons) do
    local z = list[i]
    if z then
      b.zone, b.area = z, z.area
      local here = z.here and " |cff66ff66(here)|r" or ""
      local label = DR.ZoneName(z.area)
      if mode == "dungeons" and not DR.IsDungeon(z.area) then label = label .. " (dungeon quests)" end
      b.t1:SetText(string.format("%d. %s%s", i, label, here))
      if mode == "dungeons" then
        b.t2:SetText(string.format("%d quests (%d for both) · ~%s XP", #z.entries, z.both, fmtXP(z.value)))
      else
        b.t2:SetText(string.format("~%.1f levels · %d both · %d in log", z.levels or 0, z.both, z.inlog))
      end
      local sel = z.area == selectedArea
      b.bg:SetColorTexture(1, 0.82, 0, sel and 0.18 or 0.05)
      if sel then selected = z end
      b:Show()
    else
      b:Hide(); b.zone = nil
    end
  end
  if not selected then
    for _, z in ipairs(list) do if z.area == selectedArea then selected = z end end
  end
  RenderEntries(selected and selected.entries or {})
end

function UI.Toggle()
  if not frame then Build() end
  if frame:IsShown() then frame:Hide() else frame:Show(); DR.RefreshMe(false); UI.Refresh() end
end

---------------------------------------------------------------------------
-- slash command
---------------------------------------------------------------------------
SLASH_DUOROUTE1 = "/duo"
SLASH_DUOROUTE2 = "/duoroute"
SlashCmdList.DUOROUTE = function(msg)
  local cmd, arg = (msg or ""):match("^(%S*)%s*(.-)$")
  cmd = cmd:lower()
  if cmd == "" or cmd == "show" then
    UI.Toggle()
  elseif cmd == "guide" then
    DR.Guide.Toggle()
  elseif cmd == "reroute" then
    DR.Guide.Rebuild("command"); DR.Msg("Recalculating your route...")
  elseif cmd == "arrow" then
    DR.Arrow.Toggle()
  elseif cmd == "fp" then
    local n = 0
    for _ in pairs(DuoRouteChar.fp or {}) do n = n + 1 end
    DR.Msg(DuoRouteChar.fpScanned and (n .. " flight paths known.") or "Open any flight master's map once so DuoRoute can learn your flight paths.")
  elseif cmd == "autowp" then
    DuoRouteDB.autoWaypoint = DuoRouteDB.autoWaypoint == false
    DR.Msg("Automatic waypoints " .. (DuoRouteDB.autoWaypoint and "on" or "off"))
  elseif cmd == "sync" then
    DR.Sync.Force(); DR.Msg("Sync sent.")
  elseif cmd == "partner" then
    DuoRouteDB.forcedPartner = arg ~= "" and arg or nil
    DR.Msg(arg ~= "" and ("Only syncing with " .. arg) or "Syncing with whoever in your group has DuoRoute.")
  elseif cmd == "unhide" then
    wipe(DuoRouteChar.ignored); DR.Msg("Hidden quests restored."); UI.Refresh()
  elseif cmd == "forget" then
    wipe(DuoRouteChar.skipped); DR.Msg("Abandoned-quest history cleared."); UI.Refresh()
  elseif cmd == "debug" then
    DuoRouteDB.debug = not DuoRouteDB.debug; DR.Msg("debug", DuoRouteDB.debug and "on" or "off")
  else
    DR.Msg("/duo (planner) | guide | reroute | autowp | arrow | fp | sync | partner <name> | unhide | forget | debug")
  end
end
