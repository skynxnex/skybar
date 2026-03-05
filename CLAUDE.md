# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**SkyBar** is a World of Warcraft addon that provides a customizable power bar with profiles, texture selection, and per-spec visibility. The addon targets **WoW Retail Interface 12.0+** (The War Within expansion and later).

## Architecture

SkyBar is a simple single-file addon (~1000 lines) with the following key features:

- **SavedVariables**:
  - `SkyBarDB` - Account-wide profile storage
  - `SkyBarCharDB` - Per-character active profile name
- **Profile System**: Multiple profiles with create/copy/rename/delete support
- **Per-spec Visibility**: Enable/disable bar for specific specializations
- **UI Frame**: Single draggable StatusBar with border, background, and text overlays
- **Settings UI**: Blizzard Settings integration with scrollable panel
- **Slash Commands**: `/skybar` and `/spb`

### Key Functions

- `ApplyLayout()` - Apply all visual settings (size, position, scale, alpha, texture, border) to the bar
- `UpdatePower()` - Update bar value and text from player power (handles all power types)
- `BuildOptionsPanel()` - Construct the scrollable settings UI and register with Blizzard Settings API
- `EnsureTables()` - Initialize SavedVariables with defaults and backfill missing values
- `SetActiveProfile(name)` - Switch to a different profile and apply its settings

### Profile System

Profiles are stored in `SkyBarDB.profiles[name]`. Each profile contains:
- Position: `point`, `relPoint`, `x`, `y`
- Size: `width`, `height`, `scale`, `alpha`
- Behavior: `locked`, `showText`
- Text: `textFormat` (CUR_MAX_PCT, CUR_MAX, PCT, CUR)
- Visual: `texturePath`, `textureKey`
- Border: `borderEnabled`, `borderEdgeSize`
- Background: `bgColor` (r, g, b, a)
- Per-spec: `specEnabled[specID]` (true/false map)

The active profile name is stored per-character in `SkyBarCharDB.activeProfile`.

## Development Environment

- **Language**: Lua 5.1 (WoW's embedded Lua environment)
- **No build system**: Code is loaded directly by the WoW client from the AddOns directory
- **Testing**: In-game testing only - edit code, then `/reload` in WoW
- **Debugging**: Use `DEFAULT_CHAT_FRAME:AddMessage()` for print debugging

### Testing Changes

1. Edit `SkyBar.lua` directly
2. In WoW, type `/reload` to reload the UI
3. Use slash commands or open settings panel to test functionality
4. Check for Lua errors with `/console scriptErrors 1` or use BugSack/BugGrabber addons

### Debugging Tools

- **Print debugging**: `Print(msg)` function outputs to chat with SkyBar prefix
- **Script errors**: `/console scriptErrors 1` to show errors in default UI
- **Recommended addons**: BugSack + BugGrabber for error collection and stack traces
- **Profile debugging**: `/skybar profile list` to see all profiles and active profile
- **Spec toggles**: `/skybar spec on|off <1-4>` to test per-spec visibility

## Slash Commands Reference

### General
- `/skybar` or `/skybar help` - Show all available commands
- `/skybar options` - Open settings panel
- `/skybar lock` - Toggle lock/unlock (disable/enable dragging)

### Visual Adjustments
- `/skybar width <px>` - Set bar width (min: 40)
- `/skybar height <px>` - Set bar height (min: 8)
- `/skybar scale <num>` - Set scale factor (0.5-3.0)
- `/skybar alpha <0-1>` - Set transparency (0.1-1.0)
- `/skybar text on|off` - Show/hide power text
- `/skybar textfmt <curmaxpct|curmax|pct|cur>` - Set text format

### Profile Management
- `/skybar profile list` - List all profiles and show active profile
- `/skybar profile set <name>` - Switch to a different profile
- `/skybar profile new <name>` - Create a new profile with default settings
- `/skybar profile copy <name>` - Copy current profile to new name
- `/skybar profile delete <name>` - Delete a profile (cannot delete 'Default')
- `/skybar profile rename <newName>` - Rename the active profile

### Per-Spec Visibility
- `/skybar spec on <1-4>` - Enable bar for specific spec index
- `/skybar spec off <1-4>` - Disable bar for specific spec index

## Code Patterns

### Event Handling

```lua
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(_, e)
  if e == "PLAYER_LOGIN" then
    EnsureTables()
    ApplyLayout()
    UpdatePower()
    -- Register additional events after login
    ev:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
    ev:RegisterUnitEvent("UNIT_MAXPOWER", "player")
    ev:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
  end
end)
```

### SavedVariables Initialization

```lua
-- On PLAYER_LOGIN:
if type(SkyBarDB) ~= "table" then
  SkyBarDB = { profiles = { Default = deepcopy(DEFAULTS) } }
end
DBRoot = SkyBarDB
-- Backfill missing values in active profile
for k, v in pairs(DEFAULTS) do
  if db[k] == nil then db[k] = deepcopy(v) end
end
```

### Frame Dragging

```lua
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
```

### LibSharedMedia Integration (Optional)

```lua
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true) or nil
if LSM then
  local textures = LSM:HashTable("statusbar")
  for name in pairs(textures) do
    local path = LSM:Fetch("statusbar", name)
    -- Add to texture picker
  end
end
```

### Border and Background with Insets

SkyBar uses a 3-pixel inset to prevent the statusbar fill and background from showing through rounded border corners:

```lua
local INSET = 3
local function ApplyInsets()
  -- Background texture insets
  bg:ClearAllPoints()
  bg:SetPoint("TOPLEFT", INSET, -INSET)
  bg:SetPoint("BOTTOMRIGHT", -INSET, INSET)

  -- StatusBar texture insets
  local tex = bar:GetStatusBarTexture()
  tex:ClearAllPoints()
  tex:SetPoint("TOPLEFT", bar, "TOPLEFT", INSET, -INSET)
  tex:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -INSET, INSET)
end
```

The border frame sits above everything with `SetFrameLevel(bar:GetFrameLevel() + 10)`.

## WoW API Compatibility Notes

### WoW 12.0+ Compatibility

- **Blizzard_Deprecated**: UIDropDownMenu and Options templates moved to this addon in 12.0. SkyBar loads it via `pcall(C_AddOns.LoadAddOn, "Blizzard_Deprecated")` on startup.
- **BackdropTemplate**: Required for frames using backdrops (mandatory since BfA 8.0)
- **ColorPicker**: Uses modern `ColorPickerFrame.SetupColorPickerAndShow` API with fallback to legacy fields
- **Settings API**: Modern clients use `Settings.RegisterCanvasLayoutCategory`, with graceful fallback
- **C_AddOns vs LoadAddOn**: Uses `C_AddOns.LoadAddOn` with fallback to global `LoadAddOn`

### Settings Panel Registration

```lua
-- Modern API (10.0+)
local category = Settings.RegisterCanvasLayoutCategory(optionsFrame, "SkyBar")
category.ID = "SkyBarCategory"
Settings.RegisterAddOnCategory(category)

-- Opening panel (try stable ID first, then name)
if Settings and Settings.OpenToCategory then
  Settings.OpenToCategory("SkyBarCategory")
  Settings.OpenToCategory("SkyBar")
elseif InterfaceOptionsFrame_OpenToCategory then
  InterfaceOptionsFrame_OpenToCategory("SkyBar")
end
```

### ColorPicker API

```lua
-- Modern API (preferred)
if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
  local info = {
    r = c.r, g = c.g, b = c.b,
    opacity = 1 - (c.a or 1),
    hasOpacity = true,
    swatchFunc = OnColorChanged,
    opacityFunc = OnColorChanged,
    cancelFunc = function(prev) -- restore on cancel -- end,
  }
  ColorPickerFrame:SetupColorPickerAndShow(info)
else
  -- Legacy fallback (set fields directly)
  ColorPickerFrame.func = OnColorChanged
  ColorPickerFrame.hasOpacity = true
  ColorPickerFrame:SetColorRGB(c.r, c.g, c.b)
  -- ...
end
```

### Power Type Handling

```lua
local function GetPowerColor()
  local index, token = UnitPowerType("player")
  local c = (token and PowerBarColor[token]) or PowerBarColor[index]
  if c then return c.r, c.g, c.b end
  return 0.0, 0.55, 1.0 -- default blue
end
```

### Safe Number Handling

WoW 12.0+ can return non-numeric "secret" values for some APIs. Use safe coercion:

```lua
local function AsNumber(v, fallback)
  if type(v) == "number" then return v end
  return fallback
end

local cur = AsNumber(UnitPower("player"), 0)
local max = AsNumber(UnitPowerMax("player"), 0)
```

## File Structure

```
SkyBar/
├── SkyBar.toc     -- Addon metadata (Interface version, SavedVariables, file list)
├── SkyBar.lua     -- Complete implementation (~1000 lines)
└── CLAUDE.md      -- This file
```

## Code Style

- **Indentation**: 2 spaces (no tabs)
- **Locals**: Declare functions and tables local unless they need to be global
- **Globals**: Only SavedVariables (`SkyBarDB`, `SkyBarCharDB`) should be global
- **Comments**: Use `-- Comment` for inline, `-- ===== Section =====` for section headers
- **Line length**: Keep under 120 characters where practical
- **Error handling**: Use `pcall()` for API calls that might fail across WoW versions

## UI Control Patterns

### Creating a Checkbox

```lua
local function CreateCheck(parent, label, getter, setter)
  local b = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  local lbl = b.text or b.Text -- Handle client version differences
  if lbl and lbl.SetText then lbl:SetText(label) end
  b:SetScript("OnClick", function(self) setter(self:GetChecked()) end)
  b._refresh = function() b:SetChecked(getter()) end
  return b
end
```

### Creating a Slider with Input Box

```lua
local function CreateSliderWithInput(parent, label, minV, maxV, step, getter, setter)
  local s = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
  s.Text:SetText(label)
  s.Low:SetText(tostring(minV))
  s.High:SetText(tostring(maxV))
  s:SetMinMaxValues(minV, maxV)
  s:SetValueStep(step)
  s:SetObeyStepOnDrag(true)

  local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  e:SetAutoFocus(false)
  e:SetSize(70, 22)
  e:SetPoint("LEFT", s, "RIGHT", 12, 0)

  -- Sync slider -> editbox
  s:SetScript("OnValueChanged", function(_, v)
    setter(v)
    if not e:HasFocus() then e:SetText(tostring(v)) end
  end)

  -- Sync editbox -> slider
  e:SetScript("OnEnterPressed", function(self)
    local num = tonumber(self:GetText())
    if num then
      setter(num)
      s:SetValue(num)
      self:ClearFocus()
    end
  end)

  return s, e
end
```

### Creating a Dropdown (UIDropDownMenu)

```lua
local dd = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
dd:SetWidth(180)

UIDropDownMenu_Initialize(dd, function(self, level)
  local info = UIDropDownMenu_CreateInfo()
  info.text = "Option 1"
  info.func = function() -- do something -- end
  info.checked = false
  UIDropDownMenu_AddButton(info, level)
end)

UIDropDownMenu_SetText(dd, "Current Selection")
```

## Recent Changes & Version History

- **2.0.1** (Current): Full profile system, border customization with insets, per-spec visibility, scrollable settings panel
- **2.0.0**: Major rewrite with profiles, Settings API compatibility, texture picker with LSM support
- **1.x**: Legacy SimplePowerBar versions (deprecated)

## Known Issues & Limitations

- **Texture Preview**: If LSM is not installed, only built-in textures are available
- **Spec Detection**: Requires at least one specialization; returns nil if none selected
- **Border Overlap**: 3-pixel inset prevents fill/background bleeding through rounded corners
- **Profile Rename**: Cannot rename "Default" profile (protected)
- **Settings Panel Scroll**: Content size calculated statically; very long spec lists may overflow

## Common Development Tasks

### Adding a New Text Format

1. Add to `TEXT_FORMATS` table:
   ```lua
   local TEXT_FORMATS = {
     CUR_MAX_PCT = "Current / Max (xx%)",
     CUR_MAX = "Current / Max",
     PCT = "Percent only",
     CUR = "Current only",
     NEW_FORMAT = "Your Format Label", -- Add here
   }
   ```

2. Add case to `FormatText()` function:
   ```lua
   elseif fmt == "NEW_FORMAT" then
     return ("%d energy"):format(cur)
   ```

3. Format will automatically appear in settings dropdown

### Adding a New Builtin Texture

Add to `BUILTIN_TEXTURES` table:
```lua
local BUILTIN_TEXTURES = {
  { key="StatusBar", label="Default StatusBar", path="Interface\\TARGETINGFRAME\\UI-StatusBar" },
  { key="NewTexture", label="My Texture", path="Interface\\Path\\To\\Texture" },
}
```

### Adding a New Slash Command

Add to `SlashCmdList.SKYBAR` function:
```lua
if cmd == "newcmd" and tonumber(a1) then
  db.newvalue = tonumber(a1)
  ApplyLayout()
  Print("New value set to " .. a1)
  return
end
```

Document in help text at top of slash command handler.
