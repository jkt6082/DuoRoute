-- DuoRoute: on-screen arrow that points to your next waypoint
local ADDON, DR = ...
local PATH = "Interface\\AddOns\\" .. ADDON .. "\\"
local Arrow = {}
DR.Arrow = Arrow

local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
local frame, tex, distText, label
local target          -- { uiMap, x, y (0-1), title }

local function Build()
  frame = CreateFrame("Button", "DuoRouteArrowFrame", UIParent)
  frame:SetSize(64, 64)
  frame:SetFrameStrata("HIGH")
  frame:SetMovable(true); frame:EnableMouse(true); frame:SetClampedToScreen(true)
  frame:RegisterForDrag("LeftButton")
  frame:RegisterForClicks("RightButtonUp")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    DuoRouteDB.ui.arrowPoint = { p, rp, x, y }
  end)
  frame:SetScript("OnClick", function()
    DuoRouteDB.arrowHidden = true
    frame:Hide()
    DR.Msg("Arrow hidden. Type /duo arrow to bring it back.")
  end)
  frame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(target and target.title or "DuoRoute arrow")
    GameTooltip:AddLine("Drag to move. Right-click to hide.", 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
  local pt = DuoRouteDB.ui.arrowPoint
  if pt then frame:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4]) else frame:SetPoint("TOP", 0, -140) end

  tex = frame:CreateTexture(nil, "ARTWORK")
  tex:SetAllPoints()
  tex:SetTexture(PATH .. "arrow.tga")

  distText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  distText:SetPoint("TOP", frame, "BOTTOM", 0, -2)
  label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  label:SetPoint("TOP", distText, "BOTTOM", 0, -2)
  label:SetWidth(240)
  label:SetWordWrap(true); label:SetMaxLines(2)

  local acc = 0
  frame:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 0.03 then return end
    acc = 0
    Arrow.Update()
  end)
  frame:Hide()
end

-- Where the target is, in yards east/south of you on your current map
local function Offset()
  local map = C_Map.GetBestMapForUnit("player")
  if not map then return nil end
  local pos = C_Map.GetPlayerMapPosition(map, "player")
  if not pos then return nil end
  local px, py = pos:GetXY()
  local tx, ty
  if target.uiMap == map then
    tx, ty = target.x, target.y
  else
    local ok, cont, wpos = pcall(C_Map.GetWorldPosFromMapPos, target.uiMap, CreateVector2D(target.x, target.y))
    if ok and cont and wpos then
      local ok2, _, mp = pcall(C_Map.GetMapPosFromWorldPos, cont, wpos, map)
      if ok2 and mp then tx, ty = mp:GetXY() end
    end
  end
  if not tx then return nil end
  local w, h = C_Map.GetMapWorldSize(map)
  if not w or w == 0 then return nil end
  return (tx - px) * w, (ty - py) * h
end

function Arrow.Update()
  if not target then frame:Hide(); return end
  local facing = GetPlayerFacing and GetPlayerFacing()
  local dx, dy
  if facing then dx, dy = Offset() end
  if not dx then
    -- inside instances the game doesn't give addons your position
    tex:SetAlpha(0.3); distText:SetText(""); return
  end
  tex:SetAlpha(1)
  local dist = math.sqrt(dx * dx + dy * dy)
  if dist < 12 then
    tex:SetTexture(PATH .. "check.tga")
    tex:SetRotation(0)
    distText:SetText("|cff66ff66You're here|r")
    return
  end
  tex:SetTexture(PATH .. "arrow.tga")
  local bearing = atan2(dx, -dy)          -- clockwise from north
  tex:SetRotation(-(bearing + facing))    -- facing counts counter-clockwise from north
  if dist >= 1000 then distText:SetText(string.format("%.1fk yd", dist / 1000))
  else distText:SetText(string.format("%d yd", math.floor(dist + 0.5))) end
end

function Arrow.SetTarget(uiMap, x, y, title)
  if not uiMap or not x then return end
  if not frame then Build() end
  target = { uiMap = uiMap, x = x, y = y, title = title }
  label:SetText(title or "")
  if not DuoRouteDB.arrowHidden then frame:Show() end
end

function Arrow.Clear()
  target = nil
  if frame then frame:Hide() end
end

function Arrow.Toggle()
  if not frame then Build() end
  DuoRouteDB.arrowHidden = not DuoRouteDB.arrowHidden
  if DuoRouteDB.arrowHidden then frame:Hide()
  elseif target then frame:Show() end
  DR.Msg("Arrow " .. (DuoRouteDB.arrowHidden and "hidden" or "shown"))
end
