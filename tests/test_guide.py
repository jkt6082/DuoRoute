import os
exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'test_addon.py')).read().split("print('\\nTop zones")[0])
A.eval('RunTimers')(200)
A.execute('''
local DR = DuoRoute
local r = DR.Guide.Route()
print("route", r and #r.steps, r and r.endLevel, r and r.duo)
local function has(t, v) for _, x in ipairs(t) do if x == v then return true end end end
local function remove(t, v) for i = #t, 1, -1 do if t[i] == v then table.remove(t, i) end end end
for n = 1, 60 do
  local st = r.steps[r.cursor or 1]
  if not st then print("no step"); break end
  if n <= 14 or n % 10 == 0 then print(string.format("cursor %d  %s  %s", r.cursor, st.kind, (DR.StepText(st):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))) end
  if st.kind == "accept" then ME.log[#ME.log + 1] = st.id
  elseif st.kind == "obj" or st.kind == "work" then
    -- finishing the last objective completes the quest
    local q = DR.Q[st.id]; local last = true
    for j = r.cursor + 1, #r.steps do local s2 = r.steps[j]; if s2.id == st.id and (s2.kind == "obj" or s2.kind == "work") then last = false end end
    if last then ME.done[#ME.done + 1] = st.id else st.skipped = true end
  elseif st.kind == "turnin" then
    remove(ME.log, st.id); remove(ME.done, st.id); ME.completed[#ME.completed + 1] = st.id
    FireEvent("QUEST_TURNED_IN", st.id, 5000, 0)
  elseif st.kind == "travel" then ME.mapID = DR.UiMapForArea(st.area)
  elseif st.kind == "train" then FireEvent("TRAINER_SHOW") end
  if st.x then ME.x, ME.y = st.x / 100, st.y / 100 end
  FireEvent("QUEST_LOG_UPDATE")
  RunTimers(5)
  DR.RefreshMe(true)
  DR.Guide.Refresh()
end
print("final cursor", r.cursor, "waypoint", LASTWP and LASTWP.m, LASTWP and LASTWP.x)
''')
