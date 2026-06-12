if API_TYPE == nil then
	ADDON:ImportAPI(8)
	X2Chat:DispatchChatMessage(CMF_SYSTEM, "Globals folder not found.")
	return
end

ADDON:ImportObject(OBJECT_TYPE.TEXT_STYLE)
ADDON:ImportObject(OBJECT_TYPE.BUTTON)
ADDON:ImportObject(OBJECT_TYPE.COLOR_DRAWABLE)
ADDON:ImportObject(OBJECT_TYPE.WINDOW)
ADDON:ImportObject(OBJECT_TYPE.LABEL)

ADDON:ImportAPI(API_TYPE.CHAT.id)
ADDON:ImportAPI(API_TYPE.UNIT.id)

-- ============================================================
-- Config
-- ============================================================
local WINDOW_W   = 500
local WINDOW_H   = 360
local HEADER_H   = 30
local TAB_H      = 26
local ROW_H      = 22
local FONT_SIZE  = 14
local PAD        = 5
local MAX_STORED = 300
local SETTINGS_FILE = "damagelog_pos.txt"
local SELF_NAME  = X2Unit:UnitName("player")

-- ============================================================
-- State
-- ============================================================
local logs        = { Out = {}, In = {} }
local activeTab   = "Out"
local scrollOffset = 0
local minimized   = false
local savePos
local MINIMIZED_H = HEADER_H + TAB_H + 2

local function loadPos()
	local s = { x = 200, y = 150, tab = "Out", w = WINDOW_W, h = WINDOW_H }
	local f = io.open(SETTINGS_FILE, "r")
	if not f then return s end
	for line in f:lines() do
		local k, v = line:match("^(%w+)=(.+)$")
		if k == "tab" then s[k] = v
		else local n = tonumber(v); if n then s[k] = n end end
	end
	f:close()
	return s
end

local cfg = loadPos()
activeTab = cfg.tab or "Out"

-- ============================================================
-- Tick filter
-- ============================================================
local function isTick(et)
	et = string.upper(et or "")
	return string.find(et, "PERIODIC", 1, true) ~= nil
		or string.find(et, "DOT",      1, true) ~= nil
		or string.find(et, "HOT",      1, true) ~= nil
		or string.find(et, "TICK",     1, true) ~= nil
		or string.find(et, "REGEN",    1, true) ~= nil
end

-- ============================================================
-- Helpers
-- ============================================================
local function fmtNum(n)
	n = math.floor(n)
	if n >= 1000000 then return string.format("%.1fM", n/1000000)
	elseif n >= 1000  then return string.format("%.1fk", n/1000)
	else return tostring(n) end
end

local function fmtTime()
	local t = os.time and os.time() or 0
	if t > 0 then return os.date("%H:%M:%S", t) end
	return string.format("%.0fs", os.clock())
end

local function trunc(s, maxLen)
	if string.len(s) <= maxLen then return s end
	return string.sub(s, 1, maxLen - 2) .. ".."
end

local function cleanAbility(name)
	if not name or name == "" or name == "HEALTH" then return "Melee" end
	if tonumber(name) ~= nil then return "Melee" end
	return name
end

local function pushLog(tab, entry)
	local buf = logs[tab]
	table.insert(buf, entry)
	if #buf > MAX_STORED then table.remove(buf, 1) end
end

-- ============================================================
-- Window
-- ============================================================
local win = UIParent:CreateWidget("window", "dmgLogWin", "UIParent")
win:SetExtent(cfg.w, cfg.h)
win:AddAnchor("TOPLEFT", "UIParent", cfg.x, cfg.y)
win:Show(true)
win:EnableDrag(true)

win:SetHandler("OnDragStart", function(self) self:StartMoving(); return true end)
win:SetHandler("OnDragStop",  function(self)
	self:StopMovingOrSizing()
	if savePos then savePos() end
end)

-- background
local bg = win:CreateColorDrawable(0.04, 0.04, 0.04, 0.90, "background")
bg:AddAnchor("TOPLEFT", win, 0, 0)
bg:AddAnchor("BOTTOMRIGHT", win, 0, 0)

-- header bar
local hdrBg = win:CreateColorDrawable(0.08, 0.10, 0.22, 0.97, "background")
hdrBg:AddAnchor("TOPLEFT", win, 0, 0)
hdrBg:SetExtent(WINDOW_W, HEADER_H)

local titleLbl = win:CreateChildWidget("label", "dmgLogTitle", 0, true)
titleLbl:AddAnchor("TOPLEFT", win, 7, 7)
titleLbl:SetExtent(260, HEADER_H - 6)
titleLbl.style:SetColor(0.9, 0.9, 0.9, 1)
titleLbl.style:SetFontSize(13)
titleLbl.style:SetAlign(ALIGN_LEFT)
titleLbl:SetText("Damage Log")
titleLbl:Show(true)

-- minimize button
local minBtn = win:CreateChildWidget("button", "dmgLogMin", 1, true)
minBtn:SetText("_")
minBtn:SetStyle("text_default")
minBtn:SetExtent(24, 18)
minBtn:AddAnchor("TOPRIGHT", win, -44, 6)
minBtn:Show(true)

-- clear button
local clearBtn = win:CreateChildWidget("button", "dmgLogClr", 1, true)
clearBtn:SetText("CLR")
clearBtn:SetStyle("text_default")
clearBtn:SetExtent(38, 18)
clearBtn:AddAnchor("TOPRIGHT", win, -4, 6)
clearBtn:Show(true)

-- tab strip
local tabStripBg = win:CreateColorDrawable(0.07, 0.07, 0.17, 0.97, "background")
tabStripBg:AddAnchor("TOPLEFT", win, 0, HEADER_H)
tabStripBg:SetExtent(WINDOW_W, TAB_H)

local tabOutBtn = win:CreateChildWidget("button", "dmgLogTabOut", 1, true)
tabOutBtn:SetText("Outgoing")
tabOutBtn:SetStyle("text_default")
tabOutBtn:SetExtent(90, TAB_H - 4)
tabOutBtn:AddAnchor("TOPLEFT", win, 4, HEADER_H + 2)
tabOutBtn:Show(true)

local tabInBtn = win:CreateChildWidget("button", "dmgLogTabIn", 1, true)
tabInBtn:SetText("Incoming")
tabInBtn:SetStyle("text_default")
tabInBtn:SetExtent(90, TAB_H - 4)
tabInBtn:AddAnchor("TOPLEFT", win, 98, HEADER_H + 2)
tabInBtn:Show(true)

local tabOutHL = win:CreateColorDrawable(0.2, 0.5, 0.9, 0.4, "background")
tabOutHL:SetExtent(90, TAB_H - 4)
tabOutHL:AddAnchor("TOPLEFT", win, 4, HEADER_H + 2)

local tabInHL = win:CreateColorDrawable(0.9, 0.3, 0.2, 0.4, "background")
tabInHL:SetExtent(90, TAB_H - 4)
tabInHL:AddAnchor("TOPLEFT", win, 98, HEADER_H + 2)

local sep = win:CreateColorDrawable(0.25, 0.25, 0.45, 1, "background")
sep:AddAnchor("TOPLEFT", win, 0, HEADER_H + TAB_H)
sep:SetExtent(WINDOW_W, 1)

-- scroll buttons
local scrUpBtn = win:CreateChildWidget("button", "dmgLogUp", 1, true)
scrUpBtn:SetText("^")
scrUpBtn:SetStyle("text_default")
scrUpBtn:SetExtent(20, 20)
scrUpBtn:AddAnchor("TOPRIGHT", win, -2, HEADER_H + TAB_H + 2)
scrUpBtn:Show(true)

local scrDnBtn = win:CreateChildWidget("button", "dmgLogDn", 1, true)
scrDnBtn:SetText("v")
scrDnBtn:SetStyle("text_default")
scrDnBtn:SetExtent(20, 20)
scrDnBtn:AddAnchor("BOTTOMRIGHT", win, -2, -18)
scrDnBtn:Show(true)

-- resize handle (bottom-right corner triangle)
local resizeBtn = win:CreateChildWidget("button", "dmgLogResize", 0, true)
resizeBtn:SetExtent(16, 16)
resizeBtn:AddAnchor("BOTTOMRIGHT", win, 0, 0)
resizeBtn:EnableDrag(true)
resizeBtn:Show(true)
local resizeIcon = resizeBtn:CreateColorDrawable(0.5, 0.5, 0.5, 0.7, "background")
resizeIcon:AddAnchor("TOPLEFT", resizeBtn, 0, 0)
resizeIcon:AddAnchor("BOTTOMRIGHT", resizeBtn, 0, 0)
resizeBtn:SetHandler("OnDragStart", function(self)
	if not minimized then win:StartSizing("BOTTOMRIGHT") end
	return true
end)
resizeBtn:SetHandler("OnDragStop", function(self)
	win:StopMovingOrSizing()
	if savePos then savePos() end
end)

-- ============================================================
-- Row labels (pre-allocate enough for a tall window)
-- ============================================================
local CONTENT_Y = HEADER_H + TAB_H + 2
local rowLabels = {}
for i = 1, 30 do
	local lbl = win:CreateChildWidget("label", "dmgLogRow"..i, 0, true)
	lbl:AddAnchor("TOPLEFT", win, PAD, CONTENT_Y + (i-1)*ROW_H)
	lbl:SetExtent(WINDOW_W - PAD*2 - 24, ROW_H)
	lbl.style:SetFontSize(FONT_SIZE)
	lbl.style:SetAlign(ALIGN_LEFT)
	lbl.style:SetOutline(true)
	lbl:Show(false)
	rowLabels[i] = lbl
end

-- ============================================================
-- Display
-- ============================================================
local function maxVisible()
	if minimized then return 0 end
	local h = win:GetHeight() or WINDOW_H
	return math.max(1, math.floor((h - CONTENT_Y - 20) / ROW_H))
end

local function refreshDisplay()
	local buf    = logs[activeTab]
	local total  = #buf
	local maxVis = maxVisible()
	local rowW   = (win:GetWidth() or WINDOW_W) - PAD*2 - 24

	scrollOffset = math.max(0, math.min(scrollOffset, math.max(0, total - maxVis)))

	local startIdx = math.max(1, total - maxVis - scrollOffset + 1)
	local endIdx   = math.max(0, total - scrollOffset)

	for i = 1, #rowLabels do
		local dataIdx = startIdx + (i - 1)
		local lbl = rowLabels[i]
		if not minimized and i <= maxVis and dataIdx >= 1 and dataIdx <= endIdx and buf[dataIdx] then
			local e = buf[dataIdx]
			lbl:SetExtent(rowW, ROW_H)
			lbl:SetText(e.text)
			lbl.style:SetColor(e.r, e.g, e.b, 1)
			lbl:Show(true)
		else
			lbl:Show(false)
		end
	end

	local tabName = (activeTab == "Out") and "Outgoing" or "Incoming"
	titleLbl:SetText(string.format("Damage Log  %s: %d", tabName, total))

	tabOutHL:SetVisible(activeTab == "Out")
	tabInHL:SetVisible(activeTab == "In")

	scrUpBtn:Show(not minimized)
	scrDnBtn:Show(not minimized)
	resizeBtn:Show(not minimized)
	minBtn:SetText(minimized and "+" or "_")
end

-- ============================================================
-- Minimize toggle
-- ============================================================
local savedH = cfg.h

local function toggleMinimize()
	minimized = not minimized
	if minimized then
		savedH = win:GetHeight() or WINDOW_H
		win:SetExtent(win:GetWidth() or WINDOW_W, MINIMIZED_H)
	else
		win:SetExtent(win:GetWidth() or WINDOW_W, savedH)
	end
	refreshDisplay()
	if savePos then savePos() end
end

-- ============================================================
-- Handlers
-- ============================================================
local function switchTab(t)
	activeTab = t
	scrollOffset = 0
	refreshDisplay()
	if savePos then savePos() end
end

tabOutBtn:SetHandler("OnClick", function() switchTab("Out") end)
tabInBtn:SetHandler("OnClick",  function() switchTab("In")  end)
minBtn:SetHandler("OnClick",    toggleMinimize)

clearBtn:SetHandler("OnClick", function()
	logs[activeTab] = {}
	scrollOffset = 0
	refreshDisplay()
end)

scrUpBtn:SetHandler("OnClick", function()
	scrollOffset = scrollOffset + 3
	refreshDisplay()
end)

scrDnBtn:SetHandler("OnClick", function()
	scrollOffset = math.max(0, scrollOffset - 3)
	refreshDisplay()
end)

function win:OnWheelUp()
	scrollOffset = scrollOffset + 3
	refreshDisplay()
end
win:SetHandler("OnWheelUp", win.OnWheelUp)

function win:OnWheelDown()
	scrollOffset = math.max(0, scrollOffset - 3)
	refreshDisplay()
end
win:SetHandler("OnWheelDown", win.OnWheelDown)

savePos = function()
	local x, y = win:GetOffset()
	local sc    = UIParent:GetUIScale() or 1.0
	local f     = io.open(SETTINGS_FILE, "w")
	if not f then return end
	f:write(string.format("x=%d\ny=%d\nw=%d\nh=%d\ntab=%s\n",
		math.floor((x or 0)/sc),
		math.floor((y or 0)/sc),
		math.floor((win:GetWidth()  or WINDOW_W)),
		math.floor((minimized and savedH or (win:GetHeight() or WINDOW_H))),
		activeTab))
	f:close()
end

-- keep header/tab drawables flush on resize
local resizeTimer = 0
function win:OnUpdate(dt)
	resizeTimer = resizeTimer + dt
	if resizeTimer < 150 then return end
	resizeTimer = 0
	local w = self:GetWidth() or WINDOW_W
	hdrBg:SetExtent(w, HEADER_H)
	tabStripBg:SetExtent(w, TAB_H)
	sep:SetExtent(w, 1)
end
win:SetHandler("OnUpdate", win.OnUpdate)

-- ============================================================
-- Combat events
-- ============================================================
local function hasCrit(s)
	return s ~= nil and string.find(string.upper(tostring(s)), "CRIT") ~= nil
end

-- maps eventType substring -> display label for non-damage hits
local MISS_TYPES = {
	{ pat = "DODGE",  label = "Evaded"  },
	{ pat = "PARRY",  label = "Parried" },
	{ pat = "BLOCK",  label = "Blocked" },
	{ pat = "MISS",   label = "Missed"  },
	{ pat = "IMMUNE", label = "Immune"  },
}

local function getMissLabel(et, m1, m2, m3, m4, m5)
	-- check trailing params first — they carry the specific miss reason
	local extras = { tostring(m1 or ""), tostring(m2 or ""), tostring(m3 or ""),
	                 tostring(m4 or ""), tostring(m5 or "") }
	local allExtra = string.upper(table.concat(extras, " "))

	if string.find(allExtra, "EVAD",  1, true) or string.find(allExtra, "DODGE", 1, true) then return "Evaded"  end
	if string.find(allExtra, "PARRY", 1, true) then return "Parried" end
	if string.find(allExtra, "BLOCK", 1, true) then return "Blocked" end
	if string.find(allExtra, "IMMUN", 1, true) then return "Immune"  end

	-- fall back to eventType
	local up = string.upper(et)
	for _, m in ipairs(MISS_TYPES) do
		if string.find(up, m.pat, 1, true) then return m.label end
	end
	return nil
end

local function onCombat(unitId, eventType, sourceName, targetName,
                        abilityId, abilityName, damageType, effectType,
                        isActive, more, more2, more3, more4, more5)
	if isTick(eventType) then return end

	local isMelee  = string.find(eventType, "MELEE_DAMAGE") ~= nil
	local isSpell  = string.find(eventType, "SPELL_DAMAGE") ~= nil
	local isHeal   = string.find(eventType, "SPELL_HEALED") ~= nil
	local missLabel = getMissLabel(eventType, more, more2, more3, more4, more5)

	-- ---- heals ----
	if isHeal then
		local ability = trunc(cleanAbility(abilityName), 16)
		local amount  = math.abs(tonumber(effectType) or 0)
		if amount < 1 then return end
		local ts = fmtTime()

		-- I healed someone else → their health bar (Outgoing)
		if sourceName == SELF_NAME and targetName ~= SELF_NAME then
			local tgt = trunc((targetName and targetName ~= "") and targetName or "?", 18)
			pushLog("Out", {
				text = string.format("%s  %s -> %s:  +%s", ts, ability, tgt, fmtNum(amount)),
				r = 0.3, g = 0.9, b = 0.4
			})
			if activeTab == "Out" then refreshDisplay() end
		end

		-- someone healed me → my health bar (Incoming)
		if targetName == SELF_NAME then
			local src = trunc((sourceName and sourceName ~= "") and sourceName or "?", 18)
			pushLog("In", {
				text = string.format("%s  %s (%s):  +%s", ts, src, ability, fmtNum(amount)),
				r = 0.3, g = 0.9, b = 0.4
			})
			if activeTab == "In" then refreshDisplay() end
		end
		return
	end

	if missLabel then
		local ability = trunc(cleanAbility(abilityName), 16)
		local ts = fmtTime()

		if sourceName == SELF_NAME then
			local tgt = trunc((targetName and targetName ~= "") and targetName or "?", 18)
			pushLog("Out", {
				text = string.format("%s  %s -> %s: %s", ts, ability, tgt, missLabel),
				r = 0.55, g = 0.55, b = 0.55
			})
			if activeTab == "Out" then refreshDisplay() end
		end

		if targetName == SELF_NAME then
			local src = trunc((sourceName and sourceName ~= "") and sourceName or "?", 18)
			pushLog("In", {
				text = string.format("%s  %s (%s): %s", ts, src, ability, missLabel),
				r = 0.55, g = 0.55, b = 0.55
			})
			if activeTab == "In" then refreshDisplay() end
		end
		return
	end

	if not isMelee and not isSpell then return end

	local isCrit = hasCrit(eventType) or hasCrit(more) or hasCrit(more2)
		or hasCrit(more3) or hasCrit(more4) or hasCrit(more5)

	local ability  = trunc(cleanAbility(abilityName), 16)
	local amount   = isSpell
		and math.abs(tonumber(effectType) or 0)
		or  math.abs(tonumber(abilityId)  or 0)

	-- find absorbed value in trailing params
	local absorbed = 0
	for _, p in ipairs({ more, more2, more3, more4, more5 }) do
		local n = tonumber(p)
		if n and n > 0 then absorbed = math.floor(n); break end
	end

	-- skip if no damage and nothing absorbed
	if amount < 1 and absorbed < 1 then return end

	local ts      = fmtTime()
	local critTag = isCrit and " CRIT!" or ""
	local absTag  = absorbed > 0 and string.format(" (%s abs)", fmtNum(absorbed)) or ""

	if sourceName == SELF_NAME then
		local tgt = trunc((targetName and targetName ~= "") and targetName or "?", 18)
		pushLog("Out", {
			text = string.format("%s  %s -> %s:  %s%s%s", ts, ability, tgt, fmtNum(amount), absTag, critTag),
			r = isCrit and 1.0 or 0.95,
			g = isCrit and 0.85 or 0.75,
			b = isCrit and 0.0  or 0.2
		})
		if activeTab == "Out" then refreshDisplay() end
	end

	if targetName == SELF_NAME then
		local src = trunc((sourceName and sourceName ~= "") and sourceName or "?", 18)
		pushLog("In", {
			text = string.format("%s  %s (%s):  %s%s%s", ts, src, ability, fmtNum(amount), absTag, critTag),
			r = 1.0,
			g = isCrit and 0.05 or 0.3,
			b = isCrit and 0.0  or 0.3
		})
		if activeTab == "In" then refreshDisplay() end
	end
end

UIParent:SetEventHandler(UIEVENT_TYPE.COMBAT_MSG, onCombat)

-- ============================================================
-- Init
-- ============================================================
refreshDisplay()
X2Chat:DispatchChatMessage(CMF_SYSTEM, "Damage Log loaded.")
