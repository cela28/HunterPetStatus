-- HunterPetStatus (Retail 12.x)
-- Shows an icon when the hunter pet is missing or dead.

local addonName = ...

-- NOTE: Avoid caching SavedVariables too early.
-- In some load orders the engine may populate the global SavedVariables
-- after Lua files are parsed, which would make a cached local reference stale.
-- We bind DB on ADDON_LOADED for this addon.

HunterPetStatusDB = HunterPetStatusDB or {}

local DEFAULTS = {
  enabled = true,
  scale = 1.0,
  point = { 'CENTER', 'UIParent', 'CENTER', 0, 0 },
  displayMode = 'both', -- 'icon' | 'text' | 'both'
}

local function applyDefaults(dst, src)
  for k, v in pairs(src) do
    if dst[k] == nil then
      if type(v) == 'table' then
        local t = {}
        for i = 1, #v do t[i] = v[i] end
        dst[k] = t
      else
        dst[k] = v
      end
    end
  end
end

local DB -- bound on ADDON_LOADED

local function InitDB()
  HunterPetStatusDB = HunterPetStatusDB or {}
  applyDefaults(HunterPetStatusDB, DEFAULTS)
  DB = HunterPetStatusDB
end

local function IsAllowedHunterSpec()
  local _, class = UnitClass('player')
  if class ~= 'HUNTER' then return false end
  local spec = GetSpecialization()
  if not spec then return false end
  local specID = GetSpecializationInfo(spec)
  -- 253 = Beast Mastery, 255 = Survival
  return specID == 253 or specID == 255
end

-- BackdropTemplate is required for SetBackdrop / SetBackdropColor on modern Retail.
local f = CreateFrame('Frame', 'HunterPetStatusFrame', UIParent, 'BackdropTemplate')

f:SetSize(36, 36)
local tex = f:CreateTexture(nil, 'ARTWORK')
tex:SetAllPoints(f)
-- Default texture (overridden based on state)
tex:SetTexture('Interface\\Icons\\Ability_Hunter_BeastTaming')

local label = f:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
label:SetPoint('TOP', f, 'BOTTOM', 0, -2)
label:SetJustifyH('CENTER')

local function ApplyDisplayMode()
  if not DB then return end

  local mode = DB.displayMode or DEFAULTS.displayMode
  if mode == 'icon' then
    tex:Show()
    label:Hide()
    label:ClearAllPoints()
    label:SetPoint('TOP', f, 'BOTTOM', 0, -2)
    return
  end

  if mode == 'text' then
    tex:Hide()
    label:Show()
    label:ClearAllPoints()
    label:SetPoint('CENTER', f, 'CENTER', 0, 0)
    return
  end

  -- both (default)
  tex:Show()
  label:Show()
  label:ClearAllPoints()
  label:SetPoint('TOP', f, 'BOTTOM', 0, -2)
end

local FONT_PATH = 'Fonts\\FRIZQT__.TTF'
local function ApplyFont()
  local _, size, flags = label:GetFont()
  label:SetFont(FONT_PATH, size or 12, flags)
end

local function ApplyPosition()
  if not DB then return end
  f:ClearAllPoints()
  local p = DB.point or DEFAULTS.point
  local point, relTo, relPoint, x, y = p[1], p[2], p[3], p[4], p[5]
  local relFrame = UIParent
  if relTo == 'UIParent' or relTo == nil then relFrame = UIParent end
  f:SetPoint(point or 'CENTER', relFrame, relPoint or 'CENTER', x or 0, y or 0)
end

-- ApplyPosition is called after DB init on ADDON_LOADED

-- Dragging (unlock via slash command)
f:SetMovable(true)
f:EnableMouse(false)
f:RegisterForDrag('LeftButton')

f:SetScript('OnDragStart', function(self)
  if InCombatLockdown and InCombatLockdown() then return end
  self:StartMoving()
end)

f:SetScript('OnDragStop', function(self)
  self:StopMovingOrSizing()
  if not DB then return end
  local point, relTo, relPoint, x, y = self:GetPoint(1)
  DB.point = { point, 'UIParent', relPoint, math.floor(x + 0.5), math.floor(y + 0.5) }
end)

local function SetUnlocked(unlocked)
  if unlocked then
    f:EnableMouse(true)
    f:SetBackdrop({ bgFile = 'Interface\\Buttons\\WHITE8x8' })
    f:SetBackdropColor(0, 0, 0, 0.35)
  else
    f:EnableMouse(false)
    f:SetBackdrop(nil)
  end
end

local function UpdateState()
  if not DB then
    f:Hide()
    return
  end
  if not DB.enabled then
    f:Hide()
    return
  end

  if not IsAllowedHunterSpec() then
    f:Hide()
    return
  end

  -- Hide while mounted
  if IsMounted and IsMounted() then
    f:Hide()
    return
  end

  if not UnitExists('pet') then
    -- Pet missing: show Mend Pet icon
    tex:SetTexture(132161) -- ability_hunter_beastcall
    label:SetText('NO PET')
    ApplyDisplayMode()
    f:Show()
    return
  end

  if UnitIsDeadOrGhost('pet') then
    -- Pet dead: show Beast Soothe icon
    tex:SetTexture(132163) -- Ability_Hunter_BeastSoothe
    label:SetText('PET DEAD')
    ApplyDisplayMode()
    f:Show()
    return
  end

  f:Hide()
end

-- Events
f:RegisterEvent('ADDON_LOADED')
f:RegisterEvent('PLAYER_ENTERING_WORLD')
f:RegisterEvent('PLAYER_SPECIALIZATION_CHANGED')
f:RegisterEvent('PLAYER_MOUNT_DISPLAY_CHANGED')
f:RegisterEvent('UNIT_PET')
f:RegisterEvent('UNIT_HEALTH')
f:RegisterEvent('UNIT_FLAGS')
f:RegisterEvent('PET_BAR_UPDATE')
f:RegisterEvent('PET_UI_UPDATE')
f:RegisterEvent('UNIT_CONNECTION')

f:SetScript('OnEvent', function(self, event, arg1)
  if event == 'ADDON_LOADED' then
    if arg1 ~= addonName then return end
    InitDB()
    f:SetScale(DB.scale or DEFAULTS.scale)
    ApplyPosition()
    ApplyFont()
    ApplyDisplayMode()
    UpdateState()
    return
  end

  if event == 'UNIT_HEALTH' or event == 'UNIT_FLAGS' or event == 'UNIT_CONNECTION' then
    if arg1 ~= 'pet' then return end
  end
  UpdateState()
end)

-- Slash commands
SLASH_HUNTERPETSTATUS1 = '/hps'
SlashCmdList.HUNTERPETSTATUS = function(msg)
  msg = (msg or ''):lower()

  if msg == 'unlock' then
    SetUnlocked(true)
    print('|cff00ff00HunterPetStatus|r: unlocked (drag the icon).')
    return
  end

  if msg == 'lock' then
    SetUnlocked(false)
    print('|cff00ff00HunterPetStatus|r: locked.')
    return
  end

  if msg:match('^scale') then
    local n = tonumber(msg:match('scale%s+([%d%.]+)'))
    if n and n > 0.2 and n < 4 then
      DB.scale = n
      f:SetScale(n)
      print(string.format('|cff00ff00HunterPetStatus|r: scale set to %.2f', n))
    else
      print('|cff00ff00HunterPetStatus|r: usage /hps scale 1.0')
    end
    return
  end

  if msg == 'reset' then
    DB.point = { unpack(DEFAULTS.point) }
    DB.scale = DEFAULTS.scale
    DB.displayMode = DEFAULTS.displayMode
    f:SetScale(DB.scale)
    ApplyPosition()
    ApplyDisplayMode()
    SetUnlocked(false)
    print('|cff00ff00HunterPetStatus|r: reset position and scale.')
    UpdateState()
    return
  end

  if msg:match('^display') then
    local mode = msg:match('display%s+(%S+)')
    if not mode or mode == '' then
      print(string.format('|cff00ff00HunterPetStatus|r: display mode is %s', tostring(DB.displayMode or DEFAULTS.displayMode)))
      print('|cff00ff00HunterPetStatus|r: usage /hps display icon | text | both')
      return
    end
    mode = mode:lower()
    if mode == 'icon' or mode == 'text' or mode == 'both' then
      DB.displayMode = mode
      ApplyDisplayMode()
      UpdateState()
      print(string.format('|cff00ff00HunterPetStatus|r: display mode set to %s', mode))
    else
      print('|cff00ff00HunterPetStatus|r: usage /hps display icon | text | both')
    end
    return
  end

  if msg == 'off' then
    DB.enabled = false
    UpdateState()
    print('|cff00ff00HunterPetStatus|r: disabled.')
    return
  end

  if msg == 'on' then
    DB.enabled = true
    UpdateState()
    print('|cff00ff00HunterPetStatus|r: enabled.')
    return
  end

  print('|cff00ff00HunterPetStatus|r commands:')
  print('  /hps unlock  - unlock icon for dragging')
  print('  /hps lock    - lock icon')
  print('  /hps scale 1.0')
  print('  /hps reset')
  print('  /hps display icon|text|both')
  print('  /hps on | off')
end

-- Initial
-- UpdateState is run after DB init on ADDON_LOADED
