-- SkyBar 2.0.1
-- Movable power bar with profiles, texture picker (LSM if available), per-spec enable/disable,
-- border (on/off + edge size), background color, text formats, and a scrollable Settings panel.
-- Border sits above bar; background and fill are inset to avoid color showing through rounded corners.

local ADDON = ...
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true) or nil

-- ======================
-- WoW 12.0 compatibility
-- ======================
-- Some UI widgets (UIDropDownMenu, Options* templates) were moved behind Blizzard_Deprecated.
-- Load it if available so the settings UI doesn't error in newer clients.
do
  if C_AddOns and C_AddOns.LoadAddOn then
    pcall(C_AddOns.LoadAddOn, "Blizzard_Deprecated")
  elseif LoadAddOn then
    pcall(LoadAddOn, "Blizzard_Deprecated")
  end
end

-- ===== Border constants =====
local BORDER_EDGE_FILE = "Interface\\Tooltips\\UI-Tooltip-Border"
local DEFAULT_BORDER_COLOR = { r=0, g=0, b=0, a=1.0 } -- fully opaque to prevent bleed
local UNLOCKED_BORDER_COLOR = { r=1.0, g=0.85, b=0.0, a=1.0 } -- bright gold when unlocked

-- Text format keys and labels
local TEXT_FORMATS = {
  CUR_MAX_PCT = "Current / Max (xx%)",
  CUR_MAX     = "Current / Max",
  PCT         = "Percent only",
  CUR         = "Current only",
}

-- =======================
-- Defaults & DB handling
-- =======================
local DEFAULTS = {
  point = "CENTER", relPoint = "CENTER", x = 0, y = -150,
  width = 280, height = 22, scale = 1.0, alpha = 1.0,
  locked = false, showText = true,

  -- Text format
  textFormat = "CUR_MAX_PCT",

  -- Texture
  textureKey = "StatusBar",
  texturePath = "Interface\\TARGETINGFRAME\\UI-StatusBar",

  -- Border (simplified)
  borderEnabled = true,
  borderEdgeSize = 12,

  -- Background color
  bgColor = { r=0, g=0, b=0, a=0.35 },

  -- Per-spec enable map
  specEnabled = nil, -- [specID] = true/false (default true)
}

local DBRoot     -- account-wide
local CharDB     -- per-character: activeProfile
local db         -- active profile table

-- Safe deepcopy
local function deepcopy(t)
  if type(t) ~= "table" then return t end
  local n = {}
  for k, v in pairs(t) do n[k] = deepcopy(v) end
  return n
end

-- Spec helpers
local function GetActiveSpecID()
  local idx = GetSpecialization() -- 1..4 or nil
  if not idx then return nil end
  local id = select(1, GetSpecializationInfo(idx))
  return id
end

local function EnsureSpecMap()
  db.specEnabled = db.specEnabled or {}
  local num = GetNumSpecializations() or 0
  for i = 1, num do
    local specID = select(1, GetSpecializationInfo(i))
    if specID and db.specEnabled[specID] == nil then
      db.specEnabled[specID] = true
    end
  end
end

local function IsCurrentSpecEnabled()
  local specID = GetActiveSpecID()
  if not specID then return true end
  if not db.specEnabled then return true end
  local v = db.specEnabled[specID]
  return v == nil and true or not not v
end

local function EnsureTables()
  if type(SkyBarDB) ~= "table" then
    SkyBarDB = { profiles = { Default = deepcopy(DEFAULTS) } }
  end
  DBRoot = SkyBarDB
  DBRoot.profiles = DBRoot.profiles or { Default = deepcopy(DEFAULTS) }

  if type(SkyBarCharDB) ~= "table" then
    SkyBarCharDB = { activeProfile = "Default" }
  end
  CharDB = SkyBarCharDB

  local active = CharDB.activeProfile or "Default"
  if not DBRoot.profiles[active] then
    DBRoot.profiles[active] = deepcopy(DEFAULTS)
  end
  db = DBRoot.profiles[active]

  -- backfill
  for k, v in pairs(DEFAULTS) do
    if db[k] == nil then db[k] = deepcopy(v) end
  end
  db.bgColor        = (type(db.bgColor) == "table" and db.bgColor) or deepcopy(DEFAULTS.bgColor)
  db.borderEnabled  = (db.borderEnabled ~= false)
  db.borderEdgeSize = tonumber(db.borderEdgeSize) or DEFAULTS.borderEdgeSize
  if not TEXT_FORMATS[db.textFormat or ""] then db.textFormat = DEFAULTS.textFormat end
  EnsureSpecMap()
end

local function SetActiveProfile(name)
  if not DBRoot.profiles[name] then
    DBRoot.profiles[name] = deepcopy(DEFAULTS)
  end
  CharDB.activeProfile = name
  db = DBRoot.profiles[name]
  for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = deepcopy(v) end end
  if not TEXT_FORMATS[db.textFormat or ""] then db.textFormat = DEFAULTS.textFormat end
  EnsureSpecMap()
  return name
end

local function ListProfiles()
  local out = {}
  for k in pairs(DBRoot.profiles) do table.insert(out, k) end
  table.sort(out)
  return out
end

local function RenameProfile(oldName, newName)
  if not oldName or oldName == "" then return false, "No active profile" end
  newName = tostring(newName or ""):gsub("^%s+",""):gsub("%s+$","")
  if newName == "" then return false, "Enter a new name" end
  if oldName == "Default" then return false, "Cannot rename 'Default'" end
  if DBRoot.profiles[newName] then return false, ("Profile '%s' already exists"):format(newName) end
  local t = DBRoot.profiles[oldName]
  if not t then return false, "Profile not found" end
  DBRoot.profiles[newName] = t
  DBRoot.profiles[oldName] = nil
  SetActiveProfile(newName)
  return true
end

-- =========
-- Textures
-- =========
local BUILTIN_TEXTURES = {
  { key="StatusBar", label="Default StatusBar", path="Interface\\TARGETINGFRAME\\UI-StatusBar" },
  { key="RaidHP",    label="Raid HP Fill",      path="Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
  { key="White8",    label="White 8x8 (flat)",  path="Interface\\Buttons\\WHITE8x8" },
}

local function BuildTextureChoices()
  local list = {}
  if LSM then
    local ht = LSM:HashTable("statusbar")
    for name in pairs(ht) do
      local path = LSM:Fetch("statusbar", name)
      table.insert(list, { label = name, path = path, source = "LSM" })
    end
  end
  local seen = {}
  for _,v in ipairs(list) do seen[v.path] = true end
  for _,t in ipairs(BUILTIN_TEXTURES) do
    if not seen[t.path] then
      table.insert(list, { label = t.label, path = t.path, source = "Builtin" })
    end
  end
  table.sort(list, function(a,b) return tostring(a.label):lower() < tostring(b.label):lower() end)
  return list
end

-- =========
-- UI Frame
-- =========
local bar = CreateFrame("StatusBar", "SkyBar_Bar", UIParent)
bar:SetStatusBarTexture(DEFAULTS.texturePath)
bar:GetStatusBarTexture():SetDrawLayer("ARTWORK")
bar:SetMinMaxValues(0, 100)
bar:SetValue(0)
bar:SetFrameStrata("MEDIUM") -- reasonable strata for the bar

-- Background
local bg = bar:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints(true)

-- Insets to keep color away from the rounded border corners
local INSET = 3
local function ApplyInsets()
  -- Background insets
  if bg then
    bg:ClearAllPoints()
    bg:SetPoint("TOPLEFT", INSET, -INSET)
    bg:SetPoint("BOTTOMRIGHT", -INSET, INSET)
  end

  -- StatusBar texture insets (so fill doesn't sit under border corners)
  local tex = bar:GetStatusBarTexture()
  if tex then
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", bar, "TOPLEFT", INSET, -INSET)
    tex:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -INSET, INSET)
  end
end

-- Border frame (above everything)
local border = CreateFrame("Frame", nil, bar, "BackdropTemplate")
border:SetAllPoints(true)

-- Put border above everything and clip children
bar:SetClipsChildren(true)
border:SetFrameStrata("HIGH")
border:SetFrameLevel(bar:GetFrameLevel() + 10)
border:EnableMouse(false)

-- Apply initial insets after creation
ApplyInsets()

-- Value text
local txt = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
txt:SetPoint("CENTER")
txt:SetText("")

-- Unlock indicator (always visible when unlocked)
local unlockIndicator = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
unlockIndicator:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -4, -4)
unlockIndicator:SetText("✥")  -- sparkle symbol
unlockIndicator:SetTextColor(1.0, 0.85, 0.0, 1.0)  -- bright gold
unlockIndicator:Hide()

-- Dragging
bar:SetMovable(true)
bar:RegisterForDrag("LeftButton")
bar:SetScript("OnDragStart", function(self)
  if not db.locked then self:StartMoving() end
end)
bar:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  local p, _, rp, x, y = self:GetPoint(1)
  db.point, db.relPoint, db.x, db.y = p, rp, x, y
end)

local function Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff00c0ffSkyBar|r: "..tostring(msg))
end

-- Colors
local function GetPowerColor()
  local index, token = UnitPowerType("player")
  local c = (token and PowerBarColor[token]) or PowerBarColor[index]
  if c then return c.r, c.g, c.b end
  return 0.0, 0.55, 1.0
end

-- Text formatting
local function AsNumber(v, fallback)
  if type(v) == "number" then return v end
  -- Some modern client APIs can yield "secret" values or nil in edge cases;
  -- treat anything non-numeric as unavailable.
  return fallback
end

local function FormatText(cur, max)
  cur = AsNumber(cur, 0)
  max = AsNumber(max, 0)

  local fmt = db.textFormat or "CUR_MAX_PCT"
  if fmt == "CUR_MAX" then
    return ("%d / %d"):format(cur, max)
  elseif fmt == "PCT" then
    local pct = (max > 0) and ((cur / max) * 100) or 0
    return ("%.0f%%"):format(pct)
  elseif fmt == "CUR" then
    return ("%d"):format(cur)
  else -- CUR_MAX_PCT
    local pct = (max > 0) and ((cur / max) * 100) or 0
    return ("%d / %d (%.0f%%)"):format(cur, max, pct)
  end
end

-- Layout helpers
local function ApplyBorder()
  if db.borderEnabled then
    border:SetBackdrop({ edgeFile = BORDER_EDGE_FILE, edgeSize = db.borderEdgeSize })
    -- Use bright gold color when unlocked for visual feedback
    local c = (not db.locked) and UNLOCKED_BORDER_COLOR or DEFAULT_BORDER_COLOR
    border:SetBackdropBorderColor(c.r, c.g, c.b, c.a)
    border:Show()
  else
    border:Hide()
  end
end

local function ApplyTextureAndBG()
  local path = db.texturePath or DEFAULTS.texturePath
  if path and path ~= "" then bar:SetStatusBarTexture(path) end
  local c = db.bgColor or DEFAULTS.bgColor
  bg:SetColorTexture(c.r, c.g, c.b, c.a)
  -- Re-apply insets because SetStatusBarTexture can reset anchors
  ApplyInsets()
end

local function IsVisibleForSpec()
  return IsCurrentSpecEnabled()
end

local function UpdateVisibility()
  if IsVisibleForSpec() then bar:Show() else bar:Hide() end
end

local function ApplyLayout()
  if not db then return end
  bar:ClearAllPoints()
  bar:SetPoint(db.point, UIParent, db.relPoint, db.x, db.y)
  bar:SetSize(db.width, db.height)
  bar:SetScale(db.scale)
  bar:SetAlpha(db.alpha)
  bar:EnableMouse(not db.locked)
  txt:SetShown(db.showText)
  -- Show unlock indicator when unlocked
  if not db.locked then
    unlockIndicator:Show()
  else
    unlockIndicator:Hide()
  end
  ApplyTextureAndBG()
  ApplyBorder()
  UpdateVisibility()
  -- Ensure insets match the new size/scale
  ApplyInsets()
end

local function UpdatePower()
  if not IsVisibleForSpec() then
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    if db.showText then txt:SetText("") end
    return
  end
  local max = AsNumber(UnitPowerMax("player"), 0)
  if max == 0 then
    bar:SetMinMaxValues(0, 1); bar:SetValue(0); txt:SetText(""); return
  end
  local cur = AsNumber(UnitPower("player"), 0)
  bar:SetMinMaxValues(0, max)
  bar:SetValue(cur)
  local r,g,b = GetPowerColor()
  bar:SetStatusBarColor(r,g,b)
  if db.showText then
    txt:SetText(FormatText(cur, max))
  end
end

-- ============
-- Event wireup
-- ============
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(_, e)
  if e == "PLAYER_LOGIN" then
    EnsureTables()
    ApplyLayout()
    UpdatePower()

    ev:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
    ev:RegisterUnitEvent("UNIT_MAXPOWER", "player")
    ev:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")

    ev:SetScript("OnEvent", function(_, ev2, arg1)
      if ev2 == "PLAYER_SPECIALIZATION_CHANGED" then
        if arg1 == "player" or arg1 == nil then
          EnsureSpecMap()
          UpdateVisibility()
          UpdatePower()
        end
      elseif ev2 == "UNIT_POWER_FREQUENT" or ev2=="UNIT_MAXPOWER" or ev2=="UNIT_DISPLAYPOWER"
         or ev2=="PLAYER_ENTERING_WORLD" then
        UpdatePower()
      end
    end)

    Print(("Loaded. Active profile: |cff00ff00%s|r – /skybar options"):format(CharDB.activeProfile or "Default"))
  end
end)

-- ==================
-- Blizzard Settings (scrollable)
-- ==================
local optionsFrame

-- UI helpers
local function CreateCheck(parent, label, getter, setter)
  local b = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  -- Template label field name varies across client versions.
  local lbl = b.text or b.Text
  if lbl and lbl.SetText then lbl:SetText(label) end
  b:SetScript("OnClick", function(self) setter(self:GetChecked()) end)
  b._refresh = function() b:SetChecked(getter()) end
  return b
end

local function CreateLabeledSlider(parent, label, minV, maxV, step, getter, setter)
  local s = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
  s.Text:SetText(label)
  s.Low:SetText(tostring(minV)); s.High:SetText(tostring(maxV))
  s:SetMinMaxValues(minV, maxV)
  s:SetValueStep(step)
  s:SetObeyStepOnDrag(true)
  s:SetWidth(260)
  s:SetScript("OnValueChanged", function(_, v) setter(v) end)
  s._refresh = function() s:SetValue(getter()) end
  return s
end

local function CreateSliderWithInput(parent, label, minV, maxV, step, getter, setter)
  local s = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
  s.Text:SetText(label)
  s.Low:SetText(tostring(minV)); s.High:SetText(tostring(maxV))
  s:SetMinMaxValues(minV, maxV); s:SetValueStep(step); s:SetObeyStepOnDrag(true)
  s:SetWidth(260)

  local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  e:SetAutoFocus(false); e:SetSize(70, 22)
  e:SetNumeric(false); e:SetJustifyH("CENTER")
  e:SetPoint("LEFT", s, "RIGHT", 12, 0)

  local function clamp(val) if val < minV then val = minV end; if val > maxV then val = maxV end; return val end
  local function roundToStep(v) local n = math.floor((v / step) + 0.5) * step; if step >= 1 then n = math.floor(n + 0.0001) end; return n end

  s:SetScript("OnValueChanged", function(_, v)
    local val = roundToStep(v)
    setter(val)
    if not e:HasFocus() then e:SetText(tostring(val)) end
  end)

  e:SetScript("OnEnterPressed", function(self)
    local num = tonumber(self:GetText())
    if num then
      num = clamp(roundToStep(num))
      setter(num); s:SetValue(num); self:ClearFocus()
    else
      self:SetText(tostring(getter())); self:ClearFocus()
    end
  end)
  e:SetScript("OnEscapePressed", function(self) self:SetText(tostring(getter())); self:ClearFocus() end)

  s._refresh = function() local v = getter(); s:SetValue(v); if not e:HasFocus() then e:SetText(tostring(v)) end end
  e._refresh = function() if not e:HasFocus() then e:SetText(tostring(getter())) end end

  return s, e
end

local function CreateDropdown(parent, width)
  local dd = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
  dd:SetWidth(width or 180)
  return dd
end

local function CreateColorButton(parent, label, getter, setter)
  local btn = CreateFrame("Button", nil, parent)
  btn:SetSize(24, 24)
  btn.tex = btn:CreateTexture(nil, "BACKGROUND")
  btn.tex:SetAllPoints(true)

  local text = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  text:SetPoint("LEFT", btn, "RIGHT", 8, 0)
  text:SetText(label)

  local function safeColor()
    local c = getter and getter() or nil
    if type(c) ~= "table" or type(c.r) ~= "number" or type(c.g) ~= "number" or type(c.b) ~= "number" then
      return { r = 1, g = 1, b = 1, a = 1 }
    end
    if c.a == nil then c.a = 1 end
    return c
  end

  local function updateSwatch()
    local c = safeColor()
    btn.tex:SetColorTexture(c.r, c.g, c.b, c.a or 1)
  end

  btn:SetScript("OnClick", function()
    local c = safeColor()
    local function OnColorChanged()
      local r, g, b = ColorPickerFrame:GetColorRGB()
      local a = 1 - (OpacitySliderFrame and OpacitySliderFrame:GetValue() or 0)
      setter({ r = r, g = g, b = b, a = a })
      updateSwatch()
    end

    -- Modern API (preferred) with fallback to legacy fields.
    if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
      local info = {
        r = c.r, g = c.g, b = c.b,
        opacity = 1 - (c.a or 1),
        hasOpacity = true,
        swatchFunc = OnColorChanged,
        opacityFunc = OnColorChanged,
        cancelFunc = function(prev)
          if prev then
            setter({ r = prev.r, g = prev.g, b = prev.b, a = 1 - (prev.opacity or 0) })
          end
          updateSwatch()
        end,
      }
      ColorPickerFrame:SetupColorPickerAndShow(info)
    else
      ColorPickerFrame.func = OnColorChanged
      ColorPickerFrame.opacityFunc = OnColorChanged
      ColorPickerFrame.hasOpacity = true
      ColorPickerFrame.opacity = 1 - (c.a or 1)
      ColorPickerFrame:SetColorRGB(c.r, c.g, c.b)
      ColorPickerFrame.previousValues = { r = c.r, g = c.g, b = c.b, opacity = 1 - (c.a or 1) }
      ColorPickerFrame.cancelFunc = function(prev)
        setter({ r = prev.r, g = prev.g, b = prev.b, a = 1 - (prev.opacity or 0) })
        updateSwatch()
      end
      ColorPickerFrame:Hide()
      ColorPickerFrame:Show()
    end
  end)

  btn._refresh = updateSwatch
  updateSwatch()
  return btn, text
end

-- ===== Texture Picker (dropdown-like with inline preview) =====
local function CreateTexturePicker(parent, label, getter, setter)
  local title = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  title:SetText(label)

  local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  btn:SetText("Choose…")
  btn:SetSize(90, 22)

  local preview = CreateFrame("StatusBar", nil, parent)
  preview:SetSize(200, 14)
  preview:SetMinMaxValues(0, 100)
  preview:SetValue(60)
  preview.bg = preview:CreateTexture(nil, "BACKGROUND")
  preview.bg:SetAllPoints(true)
  preview.bg:SetColorTexture(0,0,0,0.25)

  local function refreshPreview()
    local path = getter()
    if path and path ~= "" then preview:SetStatusBarTexture(path) end
  end

  local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  panel:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
                      edgeFile = BORDER_EDGE_FILE, edgeSize = 12 })
  panel:SetSize(420, 260)
  panel:Hide()

  local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 8, -8)
  scroll:SetPoint("BOTTOMRIGHT", -30, 8)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(1,1)
  scroll:SetScrollChild(content)

  local rows = {}
  local function BuildRows()
    for _,r in ipairs(rows) do r:Hide() end
    wipe(rows)
    local choices = BuildTextureChoices()
    local y = -2
    local rowH = 28

    local function makeRow(choice)
      local r = CreateFrame("Button", nil, content, "BackdropTemplate")
      r:SetSize(360, rowH)
      r:SetPoint("TOPLEFT", 6, y)
      r:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
      r:SetBackdropColor(0,0,0,0.05)
      r:SetHighlightTexture("Interface\\FriendsFrame\\UI-FriendsFrame-HighlightBar-Blue","ADD")

      local sb = CreateFrame("StatusBar", nil, r)
      sb:SetPoint("LEFT", 8, 0)
      sb:SetSize(220, 12)
      sb:SetMinMaxValues(0,100); sb:SetValue(60)
      sb:SetStatusBarTexture(choice.path)
      local sbbg = sb:CreateTexture(nil, "BACKGROUND")
      sbbg:SetAllPoints(true); sbbg:SetColorTexture(0,0,0,0.25)

      local fs = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
      fs:SetPoint("LEFT", sb, "RIGHT", 10, 0)
      fs:SetText(choice.label .. (choice.source and (" |cff8899aa("..choice.source..")|r") or ""))

      r:SetScript("OnClick", function()
        setter(choice.path, choice.label)
        refreshPreview()
        panel:Hide()
      end)

      table.insert(rows, r)
      y = y - rowH
    end

    for _,choice in ipairs(choices) do makeRow(choice) end
    content:SetSize(360, math.max(1, -y))
  end

  BuildRows()
  if LSM and LSM.RegisterCallback then
    LSM.RegisterCallback(panel, "LibSharedMedia_Registered", function(_, mediatype)
      if mediatype == "statusbar" then BuildRows() end
    end)
  end

  btn:SetScript("OnClick", function()
    if panel:IsShown() then panel:Hide() else
      panel:ClearAllPoints()
      panel:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -4)
      panel:Show()
    end
  end)

  local api = { title = title, button = btn, preview = preview, panel = panel, Refresh = refreshPreview }
  refreshPreview()
  return api
end

local function RefreshPanel()
  if not optionsFrame or not optionsFrame.controls then return end
  for _,ctl in ipairs(optionsFrame.controls) do if ctl._refresh then ctl._refresh() end end
end

-- Build per-spec toggle group
local function BuildSpecToggles(parent, startY)
  local y = startY
  local header = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  header:SetPoint("TOPLEFT", 16, y)
  header:SetText("Enable per specialization:")
  y = y - 6

  local controls = {}
  local num = GetNumSpecializations() or 0
  for i=1, num do
    local specID, name, _, icon = GetSpecializationInfo(i)
    if specID then
      local chk = CreateCheck(parent, name, function()
        EnsureSpecMap()
        local v = db.specEnabled and db.specEnabled[specID]
        return v == nil and true or not not v
      end, function(v)
        EnsureSpecMap()
        db.specEnabled[specID] = not not v
        UpdateVisibility()
        UpdatePower()
      end)
      chk:SetPoint("TOPLEFT", 16, y - (i-1)*26)
      table.insert(controls, chk)

      local tex = parent:CreateTexture(nil, "ARTWORK")
      tex:SetSize(18, 18)
      tex:SetPoint("LEFT", chk, "LEFT", -22, 0)
      tex:SetTexture(icon or 0)
      table.insert(controls, { _refresh = function() tex:SetTexture(icon or 0) end })
    end
  end

  return controls, y - num*26 - 8
end

local function BuildOptionsPanel()
  if optionsFrame then return end

  optionsFrame = CreateFrame("Frame")
  optionsFrame.name = "SkyBar"
  optionsFrame:Hide()
  optionsFrame.controls = {}

  -- === Scroll container ===
  local scroll = CreateFrame("ScrollFrame", nil, optionsFrame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 6, -6)
  scroll:SetPoint("BOTTOMRIGHT", -28, 6)

  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(1, 1)
  scroll:SetScrollChild(content)

  local y = -16
  local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, y)
  title:SetText("SkyBar")

  -- Profile row
  y = y - 30
  local profileLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  profileLabel:SetPoint("TOPLEFT", 16, y)
  profileLabel:SetText("Profile:")

  local ddProfile = CreateDropdown(content)
  ddProfile:SetPoint("TOPLEFT", 70, y+10)

  local function RefreshProfileDrop()
    UIDropDownMenu_Initialize(ddProfile, function(self, level)
      local info = UIDropDownMenu_CreateInfo()
      for _,name in ipairs(ListProfiles()) do
        info.text = name
        info.func = function()
          SetActiveProfile(name); ApplyLayout(); UpdatePower(); RefreshPanel()
        end
        info.checked = (CharDB.activeProfile == name)
        UIDropDownMenu_AddButton(info, level)
      end
    end)
    UIDropDownMenu_SetText(ddProfile, CharDB.activeProfile or "Default")
  end

  -- Buttons under dropdown
  local btnNew = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
  btnNew:SetSize(80, 22); btnNew:SetPoint("TOPLEFT", ddProfile, "BOTTOMLEFT", 0, -4)
  btnNew:SetText("New")
  btnNew:SetScript("OnClick", function()
    local base = "Profile"; local i=1; while DBRoot.profiles[base..i] do i=i+1 end
    local name = base..i
    DBRoot.profiles[name] = deepcopy(DEFAULTS)
    SetActiveProfile(name); ApplyLayout(); UpdatePower(); RefreshProfileDrop(); RefreshPanel()
    Print("Created profile: "..name)
  end)

  local btnCopy = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
  btnCopy:SetSize(80, 22); btnCopy:SetPoint("LEFT", btnNew, "RIGHT", 6, 0)
  btnCopy:SetText("Copy")
  btnCopy:SetScript("OnClick", function()
    local from = CharDB.activeProfile or "Default"
    local base = from.."_Copy"; local i=1; while DBRoot.profiles[base..i] do i=i+1 end
    local name = base..i
    DBRoot.profiles[name] = deepcopy(DBRoot.profiles[from])
    SetActiveProfile(name); ApplyLayout(); UpdatePower(); RefreshProfileDrop(); RefreshPanel()
    Print("Copied to profile: "..name)
  end)

  local btnDel = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
  btnDel:SetSize(80, 22); btnDel:SetPoint("LEFT", btnCopy, "RIGHT", 6, 0)
  btnDel:SetText("Delete")
  btnDel:SetScript("OnClick", function()
    local cur = CharDB.activeProfile or "Default"
    if cur == "Default" then Print("Cannot delete 'Default'."); return end
    DBRoot.profiles[cur] = nil
    SetActiveProfile("Default")
    ApplyLayout(); UpdatePower(); RefreshProfileDrop(); RefreshPanel()
    Print("Deleted profile. Reverted to 'Default'.")
  end)

  -- Rename UI
  local nameBox = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
  nameBox:SetAutoFocus(false)
  nameBox:SetSize(180, 22)
  nameBox:SetPoint("LEFT", btnDel, "RIGHT", 12, 0)
  nameBox:SetText(CharDB.activeProfile or "Default")

  local btnRename = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
  btnRename:SetSize(80, 22)
  btnRename:SetPoint("LEFT", nameBox, "RIGHT", 6, 0)
  btnRename:SetText("Rename")
  btnRename:SetScript("OnClick", function()
    local cur = CharDB.activeProfile or "Default"
    local new = (nameBox:GetText() or ""):gsub("^%s+",""):gsub("%s+$","")
    local ok, err = RenameProfile(cur, new)
    if ok then
      ApplyLayout(); UpdatePower(); RefreshProfileDrop(); RefreshPanel()
      Print(("Renamed: '%s' → '%s'"):format(cur, new))
    else
      Print(err or "Could not rename profile.")
    end
  end)

  table.insert(optionsFrame.controls, { _refresh = function() nameBox:SetText(CharDB.activeProfile or "Default") end })

  -- Lock/Text
  y = y - 50
  local chkLock = CreateCheck(content, "Lock (disable dragging)", function() return db.locked end, function(v) db.locked = not not v; ApplyLayout() end)
  chkLock:SetPoint("TOPLEFT", 16, y)
  table.insert(optionsFrame.controls, chkLock)

  local chkText = CreateCheck(content, "Show text", function() return db.showText end, function(v) db.showText = not not v; ApplyLayout(); UpdatePower() end)
  chkText:SetPoint("LEFT", chkLock, "RIGHT", 200, 0)
  table.insert(optionsFrame.controls, chkText)

  -- Text Format dropdown
  y = y - 40
  local tfLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  tfLabel:SetPoint("TOPLEFT", 16, y)
  tfLabel:SetText("Text format:")

  local ddTF = CreateDropdown(content)
  ddTF:SetPoint("LEFT", tfLabel, "RIGHT", 10, 0)

  local function RefreshTFDrop()
    UIDropDownMenu_Initialize(ddTF, function(self, level)
      local info = UIDropDownMenu_CreateInfo()
      for key, label in pairs(TEXT_FORMATS) do
        info.text = label
        info.func = function()
          db.textFormat = key
          UpdatePower()
          UIDropDownMenu_SetText(ddTF, TEXT_FORMATS[db.textFormat] or TEXT_FORMATS.CUR_MAX_PCT)
        end
        info.checked = (db.textFormat == key)
        UIDropDownMenu_AddButton(info, level)
      end
    end)
    UIDropDownMenu_SetText(ddTF, TEXT_FORMATS[db.textFormat] or TEXT_FORMATS.CUR_MAX_PCT)
  end
  table.insert(optionsFrame.controls, { _refresh = RefreshTFDrop })

  -- Width
  y = y - 46
  local sWidth, iWidth = CreateSliderWithInput(
    content, "Width", 80, 800, 2,
    function() return db.width end,
    function(v) db.width = math.floor(v); ApplyLayout() end
  )
  sWidth:SetPoint("TOPLEFT", 16, y)
  table.insert(optionsFrame.controls, sWidth); table.insert(optionsFrame.controls, iWidth)

  -- Height
  y = y - 46
  local sHeight, iHeight = CreateSliderWithInput(
    content, "Height", 8, 80, 1,
    function() return db.height end,
    function(v) db.height = math.floor(v); ApplyLayout() end
  )
  sHeight:SetPoint("TOPLEFT", 16, y)
  table.insert(optionsFrame.controls, sHeight); table.insert(optionsFrame.controls, iHeight)

  -- X
  y = y - 46
  local sX, iX = CreateSliderWithInput(
    content, "Position X", -4000, 4000, 1,
    function() return db.x end,
    function(v) db.x = math.floor(v); ApplyLayout() end
  )
  sX:SetPoint("TOPLEFT", 16, y)
  table.insert(optionsFrame.controls, sX); table.insert(optionsFrame.controls, iX)

  -- Y
  y = y - 46
  local sY, iY = CreateSliderWithInput(
    content, "Position Y", -4000, 4000, 1,
    function() return db.y end,
    function(v) db.y = math.floor(v); ApplyLayout() end
  )
  sY:SetPoint("TOPLEFT", 16, y)
  table.insert(optionsFrame.controls, sY); table.insert(optionsFrame.controls, iY)

  -- Scale
  y = y - 50
  local sScale = CreateLabeledSlider(content, "Scale", 0.5, 3.0, 0.05,
    function() return db.scale end,
    function(v) db.scale = tonumber(string.format("%.2f", v)); ApplyLayout() end
  )
  sScale:SetPoint("TOPLEFT", 16, y)
  table.insert(optionsFrame.controls, sScale)

  -- Alpha
  y = y - 50
  local sAlpha = CreateLabeledSlider(content, "Alpha", 0.1, 1.0, 0.05,
    function() return db.alpha end,
    function(v) db.alpha = tonumber(string.format("%.2f", v)); ApplyLayout() end
  )
  sAlpha:SetPoint("TOPLEFT", 16, y)
  table.insert(optionsFrame.controls, sAlpha)

  -- ===== Texture Picker with preview =====
  y = y - 56
  local texPick = CreateTexturePicker(content, "Bar texture:", function() return db.texturePath end,
    function(newPath, _label)
      db.texturePath = newPath
      ApplyTextureAndBG()
    end
  )
  texPick.title:SetPoint("TOPLEFT", 16, y)
  texPick.button:SetPoint("LEFT", texPick.title, "RIGHT", 16, 0)
  texPick.preview:SetPoint("LEFT", texPick.button, "RIGHT", 12, 0)
  table.insert(optionsFrame.controls, { _refresh = texPick.Refresh })

  -- ===== Per-spec toggles =====
  y = y - 56
  local specControls; specControls, y = BuildSpecToggles(content, y)
  for _,c in ipairs(specControls) do table.insert(optionsFrame.controls, c) end

  -- ===== Border =====
  y = y - 10
  local chkBorder = CreateCheck(content, "Enable border", function() return db.borderEnabled end, function(v) db.borderEnabled = not not v; ApplyBorder() end)
  chkBorder:SetPoint("TOPLEFT", 16, y)
  table.insert(optionsFrame.controls, chkBorder)

  y = y - 40
  local sEdge, iEdge = CreateSliderWithInput(
    content, "Border edge size", 4, 32, 1,
    function() return db.borderEdgeSize end,
    function(v) db.borderEdgeSize = math.floor(v); ApplyBorder() end
  )
  sEdge:SetPoint("TOPLEFT", 16, y)
  table.insert(optionsFrame.controls, sEdge); table.insert(optionsFrame.controls, iEdge)

  -- ===== Background color =====
  y = y - 44
  local btnBGColor = CreateColorButton(content, "Background color", function() return db.bgColor end, function(c) db.bgColor = c; ApplyTextureAndBG() end)
  btnBGColor:SetPoint("TOPLEFT", 16, y)
  table.insert(optionsFrame.controls, btnBGColor)

  -- Reset
  y = y - 50
  local btnReset = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
  btnReset:SetSize(140, 24); btnReset:SetPoint("TOPLEFT", 16, y)
  btnReset:SetText("Reset layout")
  btnReset:SetScript("OnClick", function()
    for k,v in pairs(DEFAULTS) do db[k] = deepcopy(v) end
    EnsureSpecMap()
    ApplyLayout(); UpdatePower(); RefreshPanel()
    Print("Reset layout for active profile.")
  end)

  content:SetSize(1, math.abs(y) + 100)

  -- Register to Settings
  local category = Settings.RegisterCanvasLayoutCategory(optionsFrame, "SkyBar")
  category.ID = "SkyBarCategory"
  Settings.RegisterAddOnCategory(category)

  optionsFrame:SetScript("OnShow", function() RefreshProfileDrop(); RefreshPanel() end)
end

-- =================
-- Slash commands
-- =================
SLASH_SKYBAR1 = "/skybar"
SLASH_SKYBAR2 = "/spb" -- keep old alias for convenience
SlashCmdList.SKYBAR = function(msg)
  local cmd, a1, a2 = msg:match("^(%S+)%s*(%S*)%s*(.*)$")
  cmd = cmd and cmd:lower() or ""

  if cmd == "" or cmd == "help" then
    Print("Commands:")
    Print("/skybar options              – open settings")
    Print("/skybar lock                 – toggle lock")
    Print("/skybar width <px>           – set width")
    Print("/skybar height <px>          – set height")
    Print("/skybar scale <num>          – set scale e.g. 1.2")
    Print("/skybar alpha <0-1>          – set alpha e.g. 0.9")
    Print("/skybar text on|off          – show/hide text")
    Print("/skybar textfmt <curmaxpct|curmax|pct|cur> – text format")
    Print("/skybar profile list         – list profiles")
    Print("/skybar profile set <name>   – switch profile")
    Print("/skybar profile new <name>   – create profile")
    Print("/skybar profile copy <name>  – copy from active to <name>")
    Print("/skybar profile delete <name> – delete profile (not 'Default')")
    Print("/skybar profile rename <newName> – rename active profile")
    Print("/skybar spec on|off <index>  – enable/disable for spec 1-4")
    return
  end

  if cmd == "options" then
    BuildOptionsPanel()
    if Settings and Settings.OpenToCategory then
      -- Prefer stable category ID, fallback to name.
      Settings.OpenToCategory("SkyBarCategory")
      Settings.OpenToCategory("SkyBar")
    elseif InterfaceOptionsFrame_OpenToCategory then
      InterfaceOptionsFrame_OpenToCategory("SkyBar")
    end
    return
  end
  if cmd == "lock" then db.locked = not db.locked; ApplyLayout(); Print(db.locked and "Locked." or "Unlocked."); return end
  if cmd == "width" and tonumber(a1) then db.width = math.max(40, math.floor(tonumber(a1))); ApplyLayout(); return end
  if cmd == "height" and tonumber(a1) then db.height = math.max(8, math.floor(tonumber(a1))); ApplyLayout(); return end
  if cmd == "scale" and tonumber(a1) then db.scale = math.max(0.5, math.min(3.0, tonumber(a1))); ApplyLayout(); return end
  if cmd == "alpha" and tonumber(a1) then db.alpha = math.max(0.1, math.min(1.0, tonumber(a1))); ApplyLayout(); return end
  if cmd == "text" and (a1=="on" or a1=="off") then db.showText=(a1=="on"); ApplyLayout(); UpdatePower(); return end

  if cmd == "textfmt" and a1 ~= "" then
    local map = { curmaxpct="CUR_MAX_PCT", curmax="CUR_MAX", pct="PCT", cur="CUR" }
    local key = map[a1:lower()]
    if key then
      db.textFormat = key
      UpdatePower()
      Print("Text format: "..(TEXT_FORMATS[key] or key))
    else
      Print("Invalid text format. Use: curmaxpct | curmax | pct | cur")
    end
    return
  end

  if cmd == "profile" then
    local sub = a1 and a1:lower() or ""
    if sub == "list" then
      local names = table.concat(ListProfiles(), ", ")
      Print("Profiles: "..names..". Active: "..(CharDB.activeProfile or "Default")); return
    elseif sub == "set" and a2 ~= "" then
      SetActiveProfile(a2); ApplyLayout(); UpdatePower(); Print("Switched to profile: "..a2); return
    elseif sub == "new" and a2 ~= "" then
      if DBRoot.profiles[a2] then Print("Profile already exists."); return end
      DBRoot.profiles[a2] = deepcopy(DEFAULTS); SetActiveProfile(a2); ApplyLayout(); UpdatePower(); Print("Created profile: "..a2); return
    elseif sub == "copy" and a2 ~= "" then
      local from = CharDB.activeProfile or "Default"
      if DBRoot.profiles[a2] then Print("Profile already exists."); return end
      DBRoot.profiles[a2] = deepcopy(DBRoot.profiles[from]); SetActiveProfile(a2); ApplyLayout(); UpdatePower(); Print("Copied to profile: "..a2); return
    elseif sub == "delete" and a2 ~= "" then
      if a2 == "Default" then Print("Cannot delete 'Default'."); return end
      if not DBRoot.profiles[a2] then Print("Profile not found."); return end
      local wasActive = (CharDB.activeProfile == a2)
      DBRoot.profiles[a2] = nil
      if wasActive then SetActiveProfile("Default"); ApplyLayout(); UpdatePower() end
      Print("Deleted profile: "..a2); return
    elseif sub == "rename" and a2 ~= "" then
      local old = CharDB.activeProfile or "Default"
      local ok, err = RenameProfile(old, a2)
      if ok then
        ApplyLayout(); UpdatePower(); Print(("Renamed: '%s' → '%s'"):format(old, a2))
      else
        Print(err or "Could not rename.")
      end
      return
    end
  end

  if cmd == "spec" and (a1=="on" or a1=="off") and tonumber(a2) then
    EnsureSpecMap()
    local idx = tonumber(a2)
    local specID = select(1, GetSpecializationInfo(idx))
    if specID then
      db.specEnabled[specID] = (a1=="on")
      UpdateVisibility(); UpdatePower()
      Print(("Spec %d %s."):format(idx, a1=="on" and "enabled" or "disabled"))
    else
      Print("Invalid spec index (1-4).")
    end
    return
  end

  Print("Unknown command. /skybar help")
end

-- ============
-- Build panel
-- ============
C_Timer.After(2, function() BuildOptionsPanel() end)
