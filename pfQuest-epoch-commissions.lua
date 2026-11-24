-- pfQuest Epoch Commission Tracker
-- Compatible with the WoW 3.3.5 client and pfQuest 7.x database APIs.

local ADDON_ID = "PFQUEST_EPOCH_COMMISSIONS"
local TITLE_PREFIX = "Commission for"
local ROW_HEIGHT = 34
local ROW_COUNT = 7

-- WotLK race masks used by the supplied pfQuest-wotlk database.
-- Alliance: Human, Dwarf, Night Elf, Gnome, Draenei.
-- Horde: Orc, Undead, Tauren, Troll, Blood Elf.
local ALLIANCE_RACE_MASK = 77 + 1024
local HORDE_RACE_MASK = 178 + 512

local fallbackProfessionNames = {
  [129] = "First Aid",
  [164] = "Blacksmithing",
  [165] = "Leatherworking",
  [171] = "Alchemy",
  [182] = "Herbalism",
  [185] = "Cooking",
  [186] = "Mining",
  [197] = "Tailoring",
  [202] = "Engineering",
  [333] = "Enchanting",
  [356] = "Fishing",
  [393] = "Skinning",
}

local cfg
local professions = {}
local commissionQuests = {}
local visibleQuests = {}
local questMaps = {}
local serverCompleted = {}
local ui
local initialized = false
local syncRequested = false
local refreshAt
local pendingMarkerRebuild = false

local function Print(message)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpf|r Commission Tracker: " .. message)
  end
end

local function GetProfessionName(skillID)
  local name = pfDB and pfDB.professions and pfDB.professions.loc and pfDB.professions.loc[skillID]
  if not name and pfDB and pfDB.professions and pfDB.professions.enUS then
    name = pfDB.professions.enUS[skillID]
  end
  return name or fallbackProfessionNames[skillID] or ("Profession " .. tostring(skillID))
end

local function GetQuestRaceMask(quest)
  local raceMask = tonumber(quest and quest.data and quest.data.race) or 0

  -- pfQuest resolves a missing/zero quest race mask from the faction of its
  -- starting NPC or object. Use that same database logic so faction filtering
  -- works even when the quest record itself has no explicit race field.
  if quest and pfDatabase and pfDatabase.GetRaceMaskByID then
    local ok, resolvedMask = pcall(pfDatabase.GetRaceMaskByID, pfDatabase, quest.id, "quests")
    if ok and tonumber(resolvedMask) then
      raceMask = tonumber(resolvedMask)
    end
  end

  return raceMask
end

local function MaskHasFaction(raceMask, factionMask)
  -- A zero race mask is a neutral/shared commission. Include it in both
  -- Alliance + Neutral and Horde + Neutral views.
  if not raceMask or raceMask == 0 then return true end
  if not bit or not bit.band then return true end
  return bit.band(raceMask, factionMask) ~= 0
end

local function GetQuestFactionLabel(quest)
  local raceMask = GetQuestRaceMask(quest)
  if raceMask == 0 then return "Neutral" end

  local alliance = MaskHasFaction(raceMask, ALLIANCE_RACE_MASK)
  local horde = MaskHasFaction(raceMask, HORDE_RACE_MASK)
  if alliance and horde then return "Alliance & Horde" end
  if alliance then return "Alliance" end
  if horde then return "Horde" end
  return "Other" -- e.g. a custom race mask unknown to pfQuest
end

local function HasRaceAndClass(quest)
  if not quest or not quest.data then return false end
  local data = quest.data

  local _, className = UnitClass("player")
  local playerClass = pfDatabase.GetBitByClass and pfDatabase:GetBitByClass(className)

  local factionSelection = cfg and cfg.faction or "MY"
  if factionSelection ~= "ALL" then
    local faction = factionSelection
    if factionSelection == "MY" then
      faction = UnitFactionGroup("player")
    end

    local factionMask
    if faction == "ALLIANCE" or faction == "Alliance" then
      factionMask = ALLIANCE_RACE_MASK
    elseif faction == "HORDE" or faction == "Horde" then
      factionMask = HORDE_RACE_MASK
    end

    if factionMask and not MaskHasFaction(GetQuestRaceMask(quest), factionMask) then
      return false
    end
  end

  local classMask = tonumber(data.class)
  if classMask and classMask ~= 0 and playerClass and bit and bit.band(classMask, playerClass) ~= playerClass then
    return false
  end
  return true
end

local function GetFactionOptionLabel(value)
  if value == "MY" then
    local faction = UnitFactionGroup("player")
    return faction and ("My Faction (" .. faction .. ") + Neutral") or "My Faction + Neutral"
  elseif value == "ALLIANCE" then
    return "Alliance + Neutral"
  elseif value == "HORDE" then
    return "Horde + Neutral"
  end
  return "All (Alliance + Horde + Neutral)"
end

local function MergeCompletedIDs(completed)
  if type(completed) ~= "table" then return 0 end

  local count = 0
  pfQuest_history = pfQuest_history or {}

  local newlyCompleted = {}
  for questID in pairs(completed) do
    questID = tonumber(questID) or questID
    if type(questID) == "number" then
      newlyCompleted[questID] = true
      serverCompleted[questID] = true
      if not pfQuest_history[questID] then
        pfQuest_history[questID] = { time(), UnitLevel("player") }
        count = count + 1
      end
    end
  end

  -- Respect the quest database's mutually-exclusive quest links.
  local questDB = pfDB and pfDB.quests and pfDB.quests.data
  if questDB then
    for questID in pairs(newlyCompleted) do
      local data = questDB[questID]
      if data and data.close then
        for _, closedID in pairs(data.close) do
          closedID = tonumber(closedID) or closedID
          if type(closedID) == "number" then
            serverCompleted[closedID] = true
            if not pfQuest_history[closedID] then
              pfQuest_history[closedID] = { time(), UnitLevel("player") }
            end
          end
        end
      end
    end
  end

  return count
end

local function MergeSavedCompletionSnapshot()
  local saved = pfQuest_CompletedQuestData
  if type(saved) ~= "table" or type(saved.data) ~= "table" then return end
  if saved.characterName and saved.characterName ~= UnitName("player") then return end
  if saved.realm and saved.realm ~= GetRealmName() then return end
  MergeCompletedIDs(saved.data)
end

local function IsCompleted(questID, closedIDs)
  return (pfQuest_history and pfQuest_history[questID]) or
    serverCompleted[questID] or (closedIDs and closedIDs[questID])
end

local function BuildClosedQuestSet()
  local closed = {}
  local questDB = pfDB and pfDB.quests and pfDB.quests.data
  if not questDB then return closed end

  for questID in pairs(pfQuest_history or {}) do
    local data = questDB[tonumber(questID) or questID]
    if data and data.close then
      for _, closedID in pairs(data.close) do
        closed[tonumber(closedID) or closedID] = true
      end
    end
  end
  for questID in pairs(serverCompleted) do
    local data = questDB[questID]
    if data and data.close then
      for _, closedID in pairs(data.close) do
        closed[tonumber(closedID) or closedID] = true
      end
    end
  end
  return closed
end

local function DiscoverCommissions()
  professions = {}
  commissionQuests = {}

  local questDB = pfDB and pfDB.quests and pfDB.quests.data
  local questNames = pfDB and pfDB.quests and pfDB.quests.loc
  if not questDB or not questNames then return end

  for questID, data in pairs(questDB) do
    local localized = questNames[questID]
    local title = localized and localized.T
    local skillID = data and tonumber(data.skill)

    if title and string.find(title, "^" .. TITLE_PREFIX) and skillID then
      local professionName = GetProfessionName(skillID)
      professions[skillID] = professionName
      local quest = {
        id = tonumber(questID) or questID,
        title = title,
        skill = skillID,
        profession = professionName,
        skillMin = tonumber(data.skillmin) or 0,
        questLevel = tonumber(data.lvl) or 0,
        data = data,
      }
      quest.faction = GetQuestFactionLabel(quest)
      commissionQuests[quest.id] = quest
    end
  end

  local ordered = {}
  for skillID, name in pairs(professions) do
    table.insert(ordered, { id = skillID, name = name })
  end
  table.sort(ordered, function(a, b) return string.lower(a.name) < string.lower(b.name) end)
  professions = ordered
end

local function IsProfessionSelected(skillID)
  return cfg and cfg.professions and cfg.professions[skillID] == true
end

local function InitializeProfessionSelection()
  -- Migrate the previous single-dropdown setting to a checkbox selection.
  -- The old default was ALL, so characters without a prior choice keep seeing
  -- every profession after upgrading.
  if type(cfg.professions) ~= "table" then
    cfg.professions = {}
    local previous = cfg.profession
    if previous and tostring(previous) ~= "ALL" then
      local skillID = tonumber(previous)
      if skillID then cfg.professions[skillID] = true end
    else
      for _, prof in ipairs(professions) do
        cfg.professions[prof.id] = true
      end
    end
  end

  -- SavedVariables can retain string keys from hand-edited configurations.
  -- Normalize them to the numeric IDs used by the quest database.
  local normalized = {}
  for _, prof in ipairs(professions) do
    if cfg.professions[prof.id] == true or cfg.professions[tostring(prof.id)] == true then
      normalized[prof.id] = true
    end
  end
  cfg.professions = normalized
  cfg.profession = nil
end

local function SetAllProfessions(selected)
  cfg.professions = cfg.professions or {}
  for _, prof in ipairs(professions) do
    cfg.professions[prof.id] = selected and true or nil
  end
end

local function GetFilteredQuests()
  local filtered = {}
  local closed = BuildClosedQuestSet()
  local includeCompleted = cfg.showCompleted == true

  for questID, quest in pairs(commissionQuests) do
    local matchesProfession = IsProfessionSelected(quest.skill)
    local completed = IsCompleted(questID, closed)

    if matchesProfession and HasRaceAndClass(quest) and (includeCompleted or not completed) then
      table.insert(filtered, quest)
    end
  end

  table.sort(filtered, function(a, b)
    if a.profession ~= b.profession then
      return string.lower(a.profession) < string.lower(b.profession)
    end
    if a.skillMin ~= b.skillMin then return a.skillMin < b.skillMin end
    return string.lower(a.title) < string.lower(b.title)
  end)

  return filtered
end

local function CommissionNodeClick()
  if IsShiftKeyDown() then
    -- Shift-click hides this commission's pins, but must not record the quest
    -- as completed in pfQuest_history.
    if this and this.title then
      pfMap:DeleteNode(ADDON_ID, this.title)
    end
    return
  end
  pfMap.NodeClick()
end

local function AddQuestMarkers(quest)
  local maps = {}
  local meta = { addon = ADDON_ID, func = CommissionNodeClick }
  local oldCurrentGivers = pfQuest_config.currentquestgivers

  -- SearchQuestID normally obeys pfQuest's "current quest givers" option.
  -- The commission tracker needs both the issuer and destination pins, so
  -- temporarily enable them only for this database search.
  pfQuest_config.currentquestgivers = "1"
  local ok, result = pcall(function()
    return pfDatabase:SearchQuestID(quest.id, meta, maps)
  end)
  pfQuest_config.currentquestgivers = oldCurrentGivers

  if ok and type(result) == "table" then
    questMaps[quest.id] = result
    return result
  end

  questMaps[quest.id] = maps
  return maps
end

local function NormalizeMarkerLevels()
  local addonNodes = pfMap and pfMap.nodes and pfMap.nodes[ADDON_ID]
  if not addonNodes then return end

  -- The Epoch continent-map overlay applies pfQuest's normal level filters.
  -- Commission pins are deliberately global: show all unfinished commissions,
  -- including low-level and high-level destinations.
  for _, zoneNodes in pairs(addonNodes) do
    for _, node in pairs(zoneNodes) do
      for _, data in pairs(node) do
        data.qlvl = 0
        data.qmin = 0
        data.lvl = 0
        data.min = 0
        data.questid = nil
        data.func = CommissionNodeClick
      end
    end
  end
end

local function BuildMarkers(list)
  questMaps = {}
  pfMap:DeleteNode(ADDON_ID)

  if not cfg.showPins then
    pendingMarkerRebuild = false
    if WorldMapFrame and WorldMapFrame:IsShown() then pfMap:UpdateNodes() end
    return
  end

  for _, quest in ipairs(list) do
    AddQuestMarkers(quest)
  end

  NormalizeMarkerLevels()
  pendingMarkerRebuild = false

  if WorldMapFrame and WorldMapFrame:IsShown() then
    pfMap:UpdateNodes()
  else
    pfMap.queue_update = GetTime()
  end
end

local function GetMapForQuest(questID)
  local maps = questMaps[questID]
  if not maps then return nil end
  return pfDatabase:GetBestMap(maps)
end

local function GetSummary(list)
  local counts = {}
  for _, quest in ipairs(list) do
    counts[quest.skill] = (counts[quest.skill] or 0) + 1
  end

  local chunks = {}
  for _, prof in ipairs(professions) do
    if counts[prof.id] then
      table.insert(chunks, counts[prof.id] .. " " .. prof.name)
    end
  end
  return table.concat(chunks, "  |  ")
end

local function RefreshRows()
  if not ui then return end

  local list = visibleQuests
  FauxScrollFrame_Update(ui.scroll, table.getn(list), ROW_COUNT, ROW_HEIGHT)
  local offset = FauxScrollFrame_GetOffset(ui.scroll) or 0

  for i = 1, ROW_COUNT do
    local row = ui.rows[i]
    local quest = list[offset + i]

    if quest then
      row.quest = quest
      row.title:SetText(quest.title)
      local details = quest.profession .. "  |  " .. quest.faction .. "  |  "
      if quest.skillMin > 0 then details = details .. "Skill " .. quest.skillMin else details = details .. "Any skill rank" end
      if quest.questLevel > 0 then details = details .. "  |  Quest level " .. quest.questLevel end
      if pfQuest.questlog and pfQuest.questlog[quest.id] then details = details .. "  |cffffff66[In log]|r" end
      row.details:SetText(details)
      row:Show()
    else
      row.quest = nil
      row:Hide()
    end
  end

  if ui.count then
    local n = table.getn(list)
    local completedText = cfg.showCompleted and "including completed" or "unfinished only"
    ui.count:SetText(n .. " commissions  |  " .. completedText .. "  |  " .. GetFactionOptionLabel(cfg.faction))
  end
  if ui.summary then ui.summary:SetText(GetSummary(list)) end
end

local function RefreshAll(rebuildMarkers)
  if not initialized then return end
  visibleQuests = GetFilteredQuests()
  RefreshRows()
  if rebuildMarkers then
    BuildMarkers(visibleQuests)
  end
end

local function ResetScrollPosition()
  if ui and ui.scroll and FauxScrollFrame_SetOffset then
    FauxScrollFrame_SetOffset(ui.scroll, 0)
  end
end

local function ScheduleRefresh(delay, rebuildMarkers)
  refreshAt = GetTime() + (delay or 1.25)
  if rebuildMarkers then pendingMarkerRebuild = true end
end

local function CreateUI()
  if ui then return end

  local frame = CreateFrame("Frame", "pfQuestCommissionTrackerFrame", UIParent)
  frame:SetWidth(650)
  frame:SetHeight(620)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  frame:SetFrameStrata("DIALOG")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
  frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
  })
  frame:Hide()

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", frame, "TOP", 0, -18)
  title:SetText("Epoch Commission Tracker")

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -7, -7)

  local factionDropdown = CreateFrame("Frame", "pfQuestCommissionFactionDropdown", frame, "UIDropDownMenuTemplate")
  factionDropdown:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -32)
  UIDropDownMenu_SetWidth(factionDropdown, 245)

  local professionHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  professionHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, -68)
  professionHeader:SetText("Professions (select any combination)")

  local selectAll = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  selectAll:SetWidth(78)
  selectAll:SetHeight(20)
  selectAll:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -112, -63)
  selectAll:SetText("Select all")

  local selectNone = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  selectNone:SetWidth(78)
  selectNone:SetHeight(20)
  selectNone:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -22, -63)
  selectNone:SetText("Clear")

  local professionChecks = {}
  local perColumn = math.max(1, math.ceil(table.getn(professions) / 2))
  for index, prof in ipairs(professions) do
    local zeroIndex = index - 1
    local column = math.floor(zeroIndex / perColumn)
    local rowIndex = zeroIndex % perColumn
    local check = CreateFrame("CheckButton", "pfQuestCommissionProfession" .. prof.id, frame, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", frame, "TOPLEFT", 20 + column * 315, -86 - rowIndex * 21)
    -- Keep the actual checkbutton square. Giving the CheckButton the full
    -- label width stretches UICheckButtonTemplate's normal texture into a
    -- long black bar (the visual defect seen in WoW 3.3.5). Extend only its
    -- hit rectangle so clicking the profession name still toggles it.
    check:SetWidth(24)
    check:SetHeight(22)
    check:SetHitRectInsets(0, -260, 0, 0)
    local label = getglobal(check:GetName() .. "Text")
    if label then
      label:SetText(prof.name)
      label:SetWidth(260)
      label:SetJustifyH("LEFT")
    end
    check.skillID = prof.id
    check:SetScript("OnClick", function(self)
      cfg.professions[self.skillID] = self:GetChecked() and true or nil
      ResetScrollPosition()
      RefreshAll(true)
    end)
    professionChecks[prof.id] = check
  end

  selectAll:SetScript("OnClick", function()
    SetAllProfessions(true)
    for skillID, check in pairs(professionChecks) do check:SetChecked(true) end
    ResetScrollPosition()
    RefreshAll(true)
  end)
  selectNone:SetScript("OnClick", function()
    SetAllProfessions(false)
    for skillID, check in pairs(professionChecks) do check:SetChecked(false) end
    ResetScrollPosition()
    RefreshAll(true)
  end)

  local showPins = CreateFrame("CheckButton", "pfQuestCommissionShowPins", frame, "UICheckButtonTemplate")
  showPins:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, -218)
  getglobal(showPins:GetName() .. "Text"):SetText("Show map markers")
  showPins:SetScript("OnClick", function(self)
    cfg.showPins = self:GetChecked() and true or false
    BuildMarkers(visibleQuests)
  end)

  local showCompleted = CreateFrame("CheckButton", "pfQuestCommissionShowCompleted", frame, "UICheckButtonTemplate")
  showCompleted:SetPoint("TOPLEFT", frame, "TOPLEFT", 220, -218)
  getglobal(showCompleted:GetName() .. "Text"):SetText("Include completed")
  showCompleted:SetScript("OnClick", function(self)
    cfg.showCompleted = self:GetChecked() and true or false
    ResetScrollPosition()
    RefreshAll(true)
  end)

  local count = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  count:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, -249)
  count:SetWidth(600)
  count:SetJustifyH("LEFT")

  local summary = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  summary:SetPoint("TOPLEFT", count, "BOTTOMLEFT", 0, -5)
  summary:SetWidth(600)
  summary:SetJustifyH("LEFT")

  local divider = frame:CreateTexture(nil, "ARTWORK")
  divider:SetTexture(1, 1, 1, .16)
  divider:SetHeight(1)
  divider:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -291)
  divider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -18, -291)

  local scroll = CreateFrame("ScrollFrame", "pfQuestCommissionScrollFrame", frame, "FauxScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -299)
  scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -40, 55)
  scroll:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, RefreshRows)
  end)

  local rows = {}
  for i = 1, ROW_COUNT do
    local row = CreateFrame("Button", "pfQuestCommissionRow" .. i, frame)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, -301 - ((i - 1) * ROW_HEIGHT))
    row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -42, -301 - ((i - 1) * ROW_HEIGHT))
    row:EnableMouse(true)

    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")

    row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 5, -2)
    row.title:SetPoint("TOPRIGHT", row, "TOPRIGHT", -3, -2)
    row.title:SetJustifyH("LEFT")

    row.details = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.details:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -1)
    row.details:SetPoint("TOPRIGHT", row, "TOPRIGHT", -3, -17)
    row.details:SetJustifyH("LEFT")

    row:SetScript("OnClick", function(self)
      if not self.quest then return end
      local mapID = GetMapForQuest(self.quest.id)
      if mapID then
        pfMap:ShowMapID(mapID)
      else
        Print("No indexed map coordinates are available for " .. self.quest.title .. ".")
      end
    end)

    row:SetScript("OnEnter", function(self)
      if not self.quest then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(self.quest.title, .3, 1, .8)
      GameTooltip:AddLine(self.quest.profession .. " (skill " .. self.quest.skillMin .. ")", 1, 1, 1)
      GameTooltip:AddLine("Faction: " .. self.quest.faction, 1, 1, 1)
      GameTooltip:AddLine("Quest ID: " .. self.quest.id, .7, .7, .7)
      GameTooltip:AddLine("Click to open the map at this commission's indexed locations.", .7, .7, .7, true)
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rows[i] = row
  end

  local sync = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  sync:SetWidth(130)
  sync:SetHeight(22)
  sync:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 20)
  sync:SetText("Sync completions")
  sync:SetScript("OnClick", function()
    if type(QueryQuestsCompleted) == "function" then
      QueryQuestsCompleted()
      Print("requested the server's completed-quest list.")
    else
      Print("this server/client does not expose QueryQuestsCompleted(); using pfQuest's local history.")
    end
  end)

  local mapAll = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  mapAll:SetWidth(115)
  mapAll:SetHeight(22)
  mapAll:SetPoint("BOTTOM", frame, "BOTTOM", 0, 20)
  mapAll:SetText("Open map")
  mapAll:SetScript("OnClick", function()
    local maps = {}
    for _, quest in ipairs(visibleQuests) do
      local questMapList = questMaps[quest.id]
      for mapID, score in pairs(questMapList or {}) do
        maps[mapID] = (maps[mapID] or 0) + (tonumber(score) or 1)
      end
    end
    local mapID = pfDatabase:GetBestMap(maps)
    if mapID then
      pfMap:ShowMapID(mapID)
    else
      Print("no indexed locations were found for this filter.")
    end
  end)

  local hide = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  hide:SetWidth(80)
  hide:SetHeight(22)
  hide:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 20)
  hide:SetText("Close")
  hide:SetScript("OnClick", function() frame:Hide() end)

  ui = {
    frame = frame,
    factionDropdown = factionDropdown,
    professionChecks = professionChecks,
    showPins = showPins,
    showCompleted = showCompleted,
    count = count,
    summary = summary,
    scroll = scroll,
    rows = rows,
  }

  for skillID, check in pairs(professionChecks) do
    check:SetChecked(cfg.professions[skillID] == true)
  end

  UIDropDownMenu_Initialize(factionDropdown, function(self, level)
    local options = { "MY", "ALLIANCE", "HORDE", "ALL" }
    for _, value in ipairs(options) do
      local info = UIDropDownMenu_CreateInfo()
      info.text = GetFactionOptionLabel(value)
      info.value = value
      info.checked = cfg.faction == value
      info.func = function()
        cfg.faction = value
        UIDropDownMenu_SetText(factionDropdown, GetFactionOptionLabel(value))
        ResetScrollPosition()
        RefreshAll(true)
      end
      UIDropDownMenu_AddButton(info, level)
    end
  end)

  UIDropDownMenu_SetText(factionDropdown, GetFactionOptionLabel(cfg.faction))
  showPins:SetChecked(cfg.showPins)
  showCompleted:SetChecked(cfg.showCompleted)
end

local function OpenTracker()
  if not initialized then
    Print("the Epoch quest database is still loading. Try again in a moment.")
    return
  end
  CreateUI()
  RefreshAll(false)
  ui.frame:Show()
end

local function SyncCompletedQuests()
  if syncRequested or type(QueryQuestsCompleted) ~= "function" then return end
  syncRequested = GetTime()
  local ok = pcall(QueryQuestsCompleted)
  if not ok then syncRequested = false end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("QUEST_LOG_UPDATE")
eventFrame:RegisterEvent("QUEST_FINISHED")
eventFrame:RegisterEvent("QUEST_QUERY_COMPLETE")
eventFrame:RegisterEvent("SKILL_LINES_CHANGED")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
  if event == "ADDON_LOADED" and arg1 ~= "pfQuest-epoch-commissions" then return end

  if event == "QUEST_QUERY_COMPLETE" then
    local completed = type(GetQuestsCompleted) == "function" and GetQuestsCompleted() or nil
    syncRequested = false
    if type(completed) == "table" then
      local count = MergeCompletedIDs(completed)
      ScheduleRefresh(.2, true)
      if count > 0 then
        Print("synced " .. count .. " newly completed quests from the server.")
      end
    end
    return
  end

  if event == "QUEST_LOG_UPDATE" or event == "QUEST_FINISHED" then
    ScheduleRefresh(1.5, true)
  elseif event == "SKILL_LINES_CHANGED" then
    ScheduleRefresh(1.0, false)
  elseif event == "PLAYER_ENTERING_WORLD" then
    ScheduleRefresh(2.0, true)
  end
end)

eventFrame:SetScript("OnUpdate", function(self)
  if not initialized then
    if not pfDatabase or not pfDatabase.localized or not pfDB or not pfDB.quests or not pfDB.quests.data then
      return
    end

    cfg = pfQuest_commission_config or {}
    cfg.faction = tostring(cfg.faction or "MY")
    if cfg.faction ~= "MY" and cfg.faction ~= "ALLIANCE" and cfg.faction ~= "HORDE" and cfg.faction ~= "ALL" then
      cfg.faction = "MY"
    end
    cfg.showPins = cfg.showPins ~= false
    cfg.showCompleted = cfg.showCompleted == true
    pfQuest_commission_config = cfg

    MergeSavedCompletionSnapshot()
    DiscoverCommissions()
    InitializeProfessionSelection()
    initialized = true
    visibleQuests = GetFilteredQuests()
    CreateUI()
    RefreshAll(true)

    if type(QueryQuestsCompleted) == "function" then
      SyncCompletedQuests()
    end
    return
  end

  if syncRequested and type(syncRequested) == "number" and GetTime() > syncRequested + 12 then
    syncRequested = false
  end

  if refreshAt and GetTime() >= refreshAt then
    refreshAt = nil
    if pendingMarkerRebuild then
      RefreshAll(true)
    else
      visibleQuests = GetFilteredQuests()
      RefreshRows()
    end
  end
end)

SLASH_PFQUESTCOMMISSIONS1 = "/commission"
SLASH_PFQUESTCOMMISSIONS2 = "/pfc"
SlashCmdList["PFQUESTCOMMISSIONS"] = function(message)
  message = string.lower(message or "")
  if message == "sync" then
    if type(QueryQuestsCompleted) == "function" then
      SyncCompletedQuests()
      Print("requested a completed-quest sync.")
    else
      Print("server completion queries are unavailable; unfinished status uses pfQuest's local history.")
    end
  elseif message == "refresh" then
    if initialized then
      MergeSavedCompletionSnapshot()
      RefreshAll(true)
      Print("commission list and map markers refreshed.")
    end
  else
    OpenTracker()
  end
end
