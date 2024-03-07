-- @description Nihilboy Make contextual menus under mouse cursor
-- @version 1.0.3
-- @author nihilboy
-- @about
--   # Nihilboy Contextual Menus Builder
--   A UI-script for making menus fast interactively, that are contextual under mouse cursor.
--   ### Prerequisites
--   ReaImGui, js_ReaScriptAPI
-- @changelog
--  + fixed properly identify top/bottom item views
--  + corrected typo in regions timeline table
--  + properly handle empty input on load button
--  + added shift button range selection
--  + better hightlight AddAction button
--  + Automatically open/close next/previous context tree
--  + properly format action name to cut unwanted strings
--  + fixed add action from midi action list
--  + Added functionality to load last opened menu on startup


-----------------------Copied from Dear ImGui Demo-------------------------------------------------------------
local ImGui = {}
for name, func in pairs(reaper) do
    name = name:match('^ImGui_(.+)$')
    if name then ImGui[name] = func end
end

local ctx
local FLT_MIN, FLT_MAX = ImGui.NumericLimits_Float()
local IMGUI_VERSION, IMGUI_VERSION_NUM, REAIMGUI_VERSION = ImGui.GetVersion()

local script = { open = true, }

function script.loop()
    script.open = script.ShowMainWindow(true)
    if script.open then
        reaper.defer(script.loop)
    end
end

if select(2, reaper.get_action_context()) == debug.getinfo(1, 'S').source:sub(2) then
    ctx = ImGui.CreateContext("nihilboy's contextual menus")
    reaper.defer(script.loop)
end

-------------------------global inits-----------------------------------
local contexts = {
    "Arrange View",
    "TCP View",
    "MCP View",
    "Transport View",
    "Envelope View",
    "Ruler View",
    "Ruler - Region Lane View",
    "Ruler - Marker Lane View",
    "Ruler - Tempo Lane View",
    "Ruler - Timeline Lane View",
    "Midi Editor View",
    "Midi Editor - Piano Roll View",
    "Midi Editor - Notes Area View",
    "Midi Editor - CC Lane View",
    "Media Item View",
    "Media Item Top View",
    "Media Item Bottom View",

    -- ... [other context names]
}

local contextData = {
    ["Arrange View"] = { menu = {} },
    ["TCP View"] = { menu = {} },
    ["MCP View"] = { menu = {} },
    ["Transport View"] = { menu = {} },
    ["Envelope View"] = { menu = {} },
    ["Ruler View"] = { menu = {} },
    ["Ruler - Region Lane View"] = { menu = {} },
    ["Ruler - Marker Lane View"] = { menu = {} },
    ["Ruler - Tempo Lane View"] = { menu = {} },
    ["Ruler - Timeline Lane View"] = { menu = {} },
    ["Midi Editor View"] = { menu = {} },
    ["Midi Editor - Piano Roll View"] = { menu = {} },
    ["Midi Editor - Notes Area View"] = { menu = {} },
    ["Midi Editor - CC Lane View"] = { menu = {} },
    ["Media Item View"] = { menu = {} },
    ["Media Item Top View"] = { menu = {} },
    ["Media Item Bottom View"] = { menu = {} },
}

local fileDropped = {}
local selectedRows = {}
local selectedActionItemIndex = nil
local selectedActionId = nil
local selectedRowIndex = {}
local isAddActionButtonClicked = false

local currentContext = nil

-- Variables for tooltip handling
local scriptGeneratedTime = 0  -- Initialize the time tracking variable
local tooltipDuration = 3      -- Duration to display the tooltip (in seconds)
local scriptGeneratedMessage   -- Variable to hold the message for the tooltip
local configLoadedTime = 0     -- Initialize the time tracking variable for config loading
local configLoadedMessage = "" -- Variable to hold the message for the tooltip

local lastClickedIndex = nil   -- Variable to keep track of the last clicked item index

--------------------------------
local selectedContext = nil
local isActionSelectionActive = false
------------------------------------------------
-----------------------Utils--------------------------------------------------------------------
-------------------------Creates a help marker in the ImGui-------------------------------------
function script.HelpMarker(desc)
    ImGui.TextDisabled(ctx, '(?)')
    if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_DelayShort()) and ImGui.BeginTooltip(ctx) then
        ImGui.PushTextWrapPos(ctx, ImGui.GetFontSize(ctx) * 35.0)
        ImGui.Text(ctx, desc)
        ImGui.PopTextWrapPos(ctx)
        ImGui.EndTooltip(ctx)
    end
end

-------------------------Converts RGBA into a single 32-bit integer ----------------------------
local function rgba(r, g, b, a)
    a = a or 255
    return ((r << 24) | (g << 16) | (b << 8) | a) & 0xFFFFFFFF
end
--------------------------creates a custom-color-state buttons----------------------------------
local function createStyledButton(ctx, label, buttonWidth, buttonHeight, bgColor, hoverColor, activeColor, textColor)
    ImGui.PushStyleColor(ctx, ImGui.Col_Button(), bgColor)         -- Background color
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(), hoverColor) -- Hover color
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive(), activeColor) -- Active color
    ImGui.PushStyleColor(ctx, ImGui.Col_Text(), textColor)         -- Text color
    local buttonPressed = ImGui.Button(ctx, label, buttonWidth, buttonHeight)
    ImGui.PopStyleColor(ctx, 4)                                    -- Pop all 4 color styles
    return buttonPressed
end
--------------------------converts a Lua table into a string representation--------------------
local function tableToString(tbl, indent)
    if not indent then indent = 0 end
    if type(tbl) ~= 'table' then return tostring(tbl) end
    local formatString = string.rep(" ", indent) .. "{\n"
    indent = indent + 4
    for k, v in pairs(tbl) do
        local keyString = string.rep(" ", indent)
        if type(k) == "string" then
            keyString = keyString .. "[" .. string.format("%q", k) .. "] = "
        else
            keyString = keyString .. "[" .. tostring(k) .. "] = "
        end
        if type(v) == "table" then
            formatString = formatString .. keyString .. tableToString(v, indent) .. ",\n"
        else
            if type(v) == "string" then
                formatString = formatString .. keyString .. string.format("%q", v) .. ",\n"
            else
                formatString = formatString .. keyString .. tostring(v) .. ",\n"
            end
        end
    end
    return formatString .. string.rep(" ", indent - 4) .. "}"
end
--------------------converts a string representation of a table back into a Lua table-----------
local function stringToTable(str)
    local func, err
    if loadstring then -- Lua 5.1
        func, err = loadstring("return " .. str)
    else             -- Lua 5.2 and later
        func, err = load("return " .. str)
    end
    if not func then
        error("Error parsing string to table: " .. err)
    else
        return func()
    end
end

local function initializeContextData(context)
    if not contextData[context].menu.info then
        contextData[context].menu.info = {
            color1 = 0xFF0033,
            color2 = 0x66B30080,
            names                  = {
                'Submenu', 'Action', 'Separator', 'Next Level', 'Previous Level', 'Root Level', 'Clear All',
                'Remove Last'
            },
            clickedItems           = {},
            currentIndentLevel     = 0,
            selectedIndices        = {},
            showIndentationNumbers = true,

        }
        selectedRows[context] = {}
    end
end

for context, _ in pairs(contextData) do
    selectedRowIndex[context] = nil
end

for _, context in ipairs(contexts) do
    initializeContextData(context)
end

---------------------------------Build menu script functions-------------------------------------------
-- Function to build the menu data based on clicked items and their indentation
local function buildMenuDataForContext(clickedItems)
    local menuData = {}
    local submenuStack = {} -- Stack to keep track of nested submenus
    for _, item in ipairs(clickedItems) do
        local currentLevel = item.indent
        local currentItem = nil
        if item.type == "Submenu" then
            currentItem = { name = item.buffers.Title, isSubmenu = true, items = {} }
        elseif item.type == "Action" then
            currentItem = { name = item.buffers.ActionName, cmd = item.buffers.ActionID }
        elseif item.type == "Separator" then
            currentItem = { separator = true }
        end
        -- Remove submenus from the stack that are at a higher or same level
        while #submenuStack > 0 and submenuStack[#submenuStack].level >= currentLevel do
            table.remove(submenuStack)
        end
        -- Add the current item to the appropriate submenu or the main menu
        if #submenuStack > 0 then
            table.insert(submenuStack[#submenuStack].item.items, currentItem)
        else
            table.insert(menuData, currentItem)
        end
        -- If the current item is a submenu, push it onto the stack
        if currentItem and item.type == "Submenu" then
            table.insert(submenuStack, { item = currentItem, level = currentLevel })
        end
    end
    return menuData
end
------------------------------
-- Function to update contextsData with the built menu data
local function updateContextsData()
    for context, data in pairs(contextData) do
        data.menuItems = buildMenuDataForContext(data.menu.info.clickedItems)
    end
end
--------------------------------------------------
local function formatMenuItem(item, indentLevel)
    local indent = string.rep(" ", indentLevel * 4)
    local itemString = indent
    if item.separator then
        itemString = itemString .. "{separator = true}"
    elseif item.isSubmenu then
        local submenuItemsString = "{\n"
        for _, subItem in ipairs(item.items) do
            submenuItemsString = submenuItemsString .. formatMenuItem(subItem, indentLevel + 1) .. ",\n"
        end
        submenuItemsString = submenuItemsString .. indent .. "}"
        itemString = itemString ..
        "{name = \"" .. (item.name or "Unnamed Submenu") .. "\", isSubmenu = true, items = " .. submenuItemsString .. "}"
    else
        itemString = itemString ..
        "{name = \"" .. (item.name or "Unnamed Item") .. "\", cmd = \"" .. (item.cmd or "NoCmd") .. "\"}"
    end
    return itemString
end
-------------------------------------------------
local function menuItemsToString(menuItems, indentLevel)
    indentLevel = indentLevel or 0
    local menuString = "{\n"
    for _, item in ipairs(menuItems) do
        menuString = menuString .. formatMenuItem(item, indentLevel + 1) .. ",\n"
    end
    menuString = menuString .. string.rep(" ", indentLevel * 4) .. "}"
    return menuString
end
-------------------------------------------------------
local function getContextsDataString()
    local contextsDataString = ""
    for context, data in pairs(contextData) do
        if data.menu and data.menu.info then
            local menuItemsString = menuItemsToString(data.menuItems)
            local formattedContext = context:gsub(" ", ""):gsub("-", "")
            contextsDataString = contextsDataString ..
            "local " .. formattedContext .. "MenuItems = \n" .. menuItemsString .. "\n\n"
        else
            local formattedContext = context:gsub(" ", "")
            contextsDataString = contextsDataString .. formattedContext .. "_Menu_Items: not initialized.\n\n"
        end
    end
    return contextsDataString
end

--------------- Function to generate the final script, built menu tables + code --------------------------------------
local function generateFinalScript()
    local menuDataString = getContextsDataString()
    local additionalCode = [[
    local function getMaxDepth(items, currentLevel, maxLevel)
      currentLevel = currentLevel or 0
      maxLevel = maxLevel or { value = 0 }
      for _, item in ipairs(items) do
        if item.isSubmenu and item.items then
          getMaxDepth(item.items, currentLevel + 1, maxLevel)
        end
      end
      if currentLevel > maxLevel.value then
        maxLevel.value = currentLevel
      end
      return maxLevel.value
    end

    local function buildMenuString(items, level)
      local menuString = ""
      for _, item in ipairs(items) do
        if item.isSubmenu and item.items then
          menuString = menuString .. ">" .. item.name .. "|"
          menuString = menuString .. buildMenuString(item.items)
          menuString = menuString .. "<|"
        elseif item.separator then
          menuString = menuString .. "|"
        else
          local tgl = reaper.GetToggleCommandStateEx(0,item.cmd);
          if tgl == 1 then tgl = '✓' else tgl = '' end;
          menuString = menuString .. " " .. tostring(tgl) .. " " .. item.name .. "|"
        end
      end
      return menuString
    end

    local function executeMenuItemAction(cmd, isMidiEditorAction)
      if isMidiEditorAction then
        local midiEditor = reaper.MIDIEditor_GetActive()
        if midiEditor then
          local commandId = reaper.NamedCommandLookup(cmd)
          reaper.MIDIEditor_OnCommand(midiEditor, commandId)
        else
          reaper.ShowConsoleMsg("No active MIDI editor found.\n")
        end
      else
        local commandId = reaper.NamedCommandLookup(cmd)
        reaper.Main_OnCommand(commandId, 0)
      end
    end

    local function showMenuAndExecuteAction(items, isMidiEditorAction)
      local maxDepth = getMaxDepth(items)
      local menuString = buildMenuString(items, maxDepth)
      local input = gfx.showmenu(menuString)
      local flatMenuItems = {}
      local function flattenItems(items)
        for _, item in ipairs(items) do
          if item.isSubmenu and item.items then
            flattenItems(item.items)
          elseif not item.separator then
            table.insert(flatMenuItems, item)
          end
        end
      end
      flattenItems(items)
      if input > 0 then
        local selectedItem = flatMenuItems[input]
        if selectedItem and not selectedItem.separator and selectedItem.cmd then
          executeMenuItemAction(selectedItem.cmd, isMidiEditorAction)
        end
      end
    end
    -------------------------locate item level------------
    function GetMediaItemPosition(item)
        -- Get the position of the item in the arrange view
        local _, itemTop = reaper.JS_Window_GetRect(item)
        local itemHeight = reaper.GetMediaItemInfo_Value(item, 'I_LASTH')
        return itemTop, itemHeight
    end

    function GetMousePositionOverItem()
        local mouseX, mouseY = reaper.GetMousePosition()
        local item = reaper.GetItemFromPoint(mouseX, mouseY, false)
        local status = "No item under cursor."

        if item then
            local itemTop, itemHeight = GetMediaItemPosition(item)
            local itemMiddleY = itemTop + (itemHeight / 2)

            if mouseY < itemMiddleY then
                status = "Top"
            else
                status = "Bottom"
            end
        end

        return status
    end

       function GetArrangeViewTop()
           local main_hwnd = reaper.GetMainHwnd() -- Main window handle
           local trackview_hwnd = reaper.JS_Window_FindChildByID(main_hwnd, 1000)
           local _, _, top = reaper.JS_Window_GetRect(trackview_hwnd)
           return top
       end

       function GetArrangeViewScroll()
           local main_hwnd = reaper.GetMainHwnd()
           local trackview_hwnd = reaper.JS_Window_FindChildByID(main_hwnd, 1000)
           local _, position = reaper.JS_Window_GetScrollInfo(trackview_hwnd, "v")
           return position
       end

       function GetTrackHeight(track)
           return reaper.GetMediaTrackInfo_Value(track, "I_WNDH")
       end

       function GetItemGlobalTop(item)
           local itemTop = reaper.GetMediaItemInfo_Value(item, 'I_LASTY')
           local itemTrack = reaper.GetMediaItem_Track(item)
           local trackIndex = reaper.GetMediaTrackInfo_Value(itemTrack, 'IP_TRACKNUMBER') - 1

           local arrangeTop = GetArrangeViewTop()
           local arrangeScroll = GetArrangeViewScroll()
           local cumulativeTrackHeight = 0
           for i = 0, trackIndex - 1 do
               cumulativeTrackHeight = cumulativeTrackHeight + GetTrackHeight(reaper.GetTrack(0, i))
           end

           return arrangeTop + itemTop - arrangeScroll + cumulativeTrackHeight
       end

       function GetMousePositionOverItem()
           local mouseX, mouseY = reaper.GetMousePosition()
           local item = reaper.GetItemFromPoint(mouseX, mouseY, false)
           local status = "No item under cursor."

           if item then
               local itemGlobalTop = GetItemGlobalTop(item)
               local itemHeight = reaper.GetMediaItemInfo_Value(item, 'I_LASTH')
               local itemMiddleY = itemGlobalTop + itemHeight / 2

               if mouseY < itemMiddleY then
                   status = 1 -- Top half
               else
                   status = nil -- Bottom half
               end
           end

           return status
       end

    -- find if a table is empty
    local function isTableEmpty(t)
      return next(t) == nil
    end

     --function to simulate left click
    local function simulateclick()
      x, y = reaper.GetMousePosition()
      w = reaper.JS_Window_FromPoint(x, y)
      if w then
        x, y = reaper.JS_Window_ScreenToClient(w, x, y)
        reaper.JS_WindowMessage_Post(w, "WM_LBUTTONDOWN", 1, 0, x, y)
        reaper.JS_WindowMessage_Post(w, "WM_LBUTTONUP", 0, 0, x, y)
      end
    end

    --function to delay showing menu so not interfere with click simulation
    local function showDelayedMenu(menuItems, isMidiEditorAction)
      reaper.defer(function()
        showMenuAndExecuteAction(menuItems, isMidiEditorAction)
      end)
    end
    ----------------------------------------------
    local function showContextMenu()
      local cursorContext, segment, details = reaper.BR_GetMouseCursorContext()
      local midiEditor = reaper.MIDIEditor_GetActive()
      local envelope = reaper.BR_GetMouseCursorContext_Envelope()
      local item, take = reaper.BR_GetMouseCursorContext_Item()
      local _, _, _, ccLane, _, ccLaneId  = reaper.BR_GetMouseCursorContext_MIDI()
      local item_position = GetMousePositionOverItem()

      if midiEditor then
        if segment == "piano" then
          if not isTableEmpty(MidiEditorPianoRollViewMenuItems,true) then
            showMenuAndExecuteAction(MidiEditorPianoRollViewMenuItems,true)
          else
            showMenuAndExecuteAction(MidiEditorViewMenuItems,true)
          end
        elseif segment == "notes" then
          if not isTableEmpty(MidiEditorNotesAreaViewMenuItems,true) then
            showMenuAndExecuteAction(MidiEditorNotesAreaViewMenuItems,true)
          else
            showMenuAndExecuteAction(MidiEditorViewMenuItems,true)
          end
        elseif segment == "notes" then
          if not isTableEmpty(MidiEditorNotesAreaViewMenuItems,true) then
            showMenuAndExecuteAction(MidiEditorNotesAreaViewMenuItems,true)
          else
            showMenuAndExecuteAction(MidiEditorViewMenuItems,true)
          end
        elseif ccLaneId ~= nil and ccLaneId >= 0 then
          if not isTableEmpty(MidiEditorCCLaneViewMenuItems,true) then
            simulateclick()
            showDelayedMenu(MidiEditorCCLaneViewMenuItems, true)
          else
            showMenuAndExecuteAction(MidiEditorViewMenuItems,true)
          end
        else
          showMenuAndExecuteAction(MidiEditorViewMenuItems,true)
        end
      elseif cursorContext == "tcp" then
        showMenuAndExecuteAction(TCPViewMenuItems)
      elseif cursorContext == "mcp" then
        showMenuAndExecuteAction(MCPViewMenuItems)
      elseif cursorContext == "transport" then
        showMenuAndExecuteAction(TransportViewMenuItems)
      elseif cursorContext == "ruler" then
        if segment == "region_lane" then
          if not isTableEmpty(RulerRegionLaneViewMenuItems) then
            showMenuAndExecuteAction(RulerRegionLaneViewMenuItems)
          else
            showMenuAndExecuteAction(RulerViewMenuItems)
          end
        elseif segment == "marker_lane" then
          if not isTableEmpty(RulerMarkerLaneViewMenuItems) then
            showMenuAndExecuteAction(RulerMarkerLaneViewMenuItems)
          else
            showMenuAndExecuteAction(RulerViewMenuItems)
          end
        elseif segment == "tempo_lane" then
          if not isTableEmpty(RulerTempoLaneViewMenuItems) then
            showMenuAndExecuteAction(RulerTempoLaneViewMenuItems)
          else
            showMenuAndExecuteAction(RulerViewMenuItems)
          end
        elseif segment == "timeline" then
          if not isTableEmpty(RulerTimelineLaneViewMenuItems) then
            showMenuAndExecuteAction(RulerTimelineLaneViewMenuItems)
          else
            showMenuAndExecuteAction(RulerViewMenuItems)
          end
        else
          showMenuAndExecuteAction(RulerViewMenuItems)
        end
      elseif envelope then
        showMenuAndExecuteAction(EnvelopeViewMenuItems)
     elseif item then
         local topMenuAvailable = not isTableEmpty(MediaItemTopViewMenuItems)
         local bottomMenuAvailable = not isTableEmpty(MediaItemBottomViewMenuItems)

         if topMenuAvailable or bottomMenuAvailable then
             if item_position then -- top position
                 if topMenuAvailable then
                     showMenuAndExecuteAction(MediaItemTopViewMenuItems)
                 else
                     showMenuAndExecuteAction(MediaItemViewMenuItems)
                 end
             else -- bottom position
                 if bottomMenuAvailable then
                     showMenuAndExecuteAction(MediaItemBottomViewMenuItems)
                 else
                     showMenuAndExecuteAction(MediaItemViewMenuItems)
                 end
             end
         else -- both top and bottom menus are empty
             if not isTableEmpty(MediaItemViewMenuItems) then
                 showMenuAndExecuteAction(MediaItemViewMenuItems)
             end
         end
      elseif cursorContext == "arrange" then
        showMenuAndExecuteAction(ArrangeViewMenuItems)
      end
    end

    local function deferShowMenu()
      showContextMenu()
    end

    reaper.defer(showContextMenu)
    ]]

    return menuDataString .. additionalCode
end
-------------------------------------------------
-- Function to convert an item from tbl format to clickedItems format
local function convertTblItemToClickedItem(tblItem, indentLevel, clickedItems)
    indentLevel = indentLevel or 0
    local clickedItem = {
        type = tblItem.isSubmenu and "Submenu" or (tblItem.separator and "Separator" or "Action"),
        buffers = {},
        indent = indentLevel
    }

    if clickedItem.type == "Action" then
        clickedItem.buffers.ActionName = tblItem.name
        clickedItem.buffers.ActionID = tblItem.cmd
    elseif clickedItem.type == "Submenu" then
        clickedItem.buffers.Title = tblItem.name
        table.insert(clickedItems, clickedItem)
        for _, subItem in ipairs(tblItem.items or {}) do
            convertTblItemToClickedItem(subItem, indentLevel + 1, clickedItems)
        end
        return
    elseif clickedItem.type == "Separator" then
        clickedItem.buffers.Separator = ''
    end
    table.insert(clickedItems, clickedItem)
end
-------------------------------------------------
local function updateClickedItemsFromContext(context, tbl)
    if not contextData[context] then
        reaper.ShowConsoleMsg("Context data not found for: " .. context)
        return
    end
    local menu = contextData[context].menu
    if not menu or not menu.info then
        reaper.ShowConsoleMsg("Menu info not initialized for: " .. context)
        return
    end
    menu.info.clickedItems = {}
    for _, item in ipairs(tbl) do
        convertTblItemToClickedItem(item, 0, menu.info.clickedItems)
    end
end
-------------------------------------------------
local function parseMenuItems(scriptPath, contexts)
    local file = io.open(scriptPath, "r")
    if not file then return nil, "Unable to open file" end
    local scriptContent = file:read("*a")
    file:close()
    for _, context in ipairs(contexts) do
        local formattedContext = context:gsub(" ", ""):gsub("-", "")
        local tableName = formattedContext .. "MenuItems"
        local pattern = "local " .. tableName .. "%s*=%s*(%b{})"
        local tableContent = scriptContent:match(pattern)
        if not tableContent then
            -- If one of the context tables is not found in the script
            return false,
                "Menu items not found for context: " .. context .. ". Please load a menu generated from this builder"
        end
        local tbl, err = stringToTable(tableContent)
        if not tbl then
            -- If the string to table conversion fails
            return false, "Error parsing table for context: " .. context .. ". Error: " .. err
        end
        updateClickedItemsFromContext(context, tbl)
    end
    return true -- Success
end
-------------------------------------------------
-- Function to load the menu items from a script file------------------------------------------------------------
local function loadScriptAtPath(scriptPath)
    local loadResult, loadError = parseMenuItems(scriptPath, contexts)
    if loadResult then
        configLoadedMessage = "Configuration of menus loaded from " .. scriptPath
    else
        configLoadedMessage = loadError or "Error loading configuration from " .. scriptPath
    end
    configLoadedTime = os.time()   -- Update the load time
end

local scriptName = "Nihilboy_Contextual_Menus.lua"
-- Read the path from the Contextual_Menus_Startup file and load the script
local startupFilePath = reaper.GetResourcePath() .. "/Scripts/Contextual_Menus_Startup"
local startupFile = io.open(startupFilePath, "r")
if startupFile then
    local lastGeneratedScriptPath = startupFile:read("*a")
    --reaper.ShowConsoleMsg("file read \n")

    startupFile:close()
    if lastGeneratedScriptPath and lastGeneratedScriptPath ~= "" then
        --reaper.ShowConsoleMsg(lastGeneratedScriptPath)
        loadScriptAtPath(lastGeneratedScriptPath:gsub("[\r\n]", ""), context)
        scriptName = lastGeneratedScriptPath:gsub("[\r\n]", ""):match("([^/\\]+)$")
        --parseMenuItems(lastGeneratedScriptPath:gsub("[\r\n]", ""), contexts)
        configLoadedTime = os.time()
    end
end


-----------------------------------------------------------------------------------------------------

function script.ShowMainWindow(open)
    local rv = nil

    -- We specify a default position/size in case there's no data in the .ini file.
    -- We only do it to make the demo applications a little more welcoming, but typically this isn't required.
    local main_viewport = ImGui.GetMainViewport(ctx)
    local work_pos = { ImGui.Viewport_GetWorkPos(main_viewport) }
    ImGui.SetNextWindowPos(ctx, work_pos[1] + 20, work_pos[2] + 20, ImGui.Cond_FirstUseEver())
    ImGui.SetNextWindowSize(ctx, 550, 780, ImGui.Cond_FirstUseEver())

    if script.set_dock_id then
        ImGui.SetNextWindowDockID(ctx, script.set_dock_id)
        script.set_dock_id = nil
    end


    -- Main body of the Demo window starts here.
    rv, open = ImGui.Begin(ctx, "Nihilboy's Contextual Menus", open, window_flags)
    -- Early out if the window is collapsed
    if not rv then return open end
    ImGui.PushItemWidth(ctx, ImGui.GetFontSize(ctx) * -12)

    -- Center the "Contexts" title
    local windowWidth = ImGui.GetContentRegionAvail(ctx)
    local title = "Contexts"
    local titleWidth = ImGui.CalcTextSize(ctx, title)
    ImGui.SameLine(ctx, (windowWidth - titleWidth) * 0.5)
    ImGui.Text(ctx, title)
    ImGui.Spacing(ctx)

    -----------------tabs with button-----------------------

    local numTabsPerLine = 5 -- Number of tabs per line
    local tabWidth = 220 -- Width of each tab
    local tabHeight = 20 -- Height of each tab
    local lineSpacing = 1 -- Vertical spacing between lines of tabs
    local lineCount = math.ceil(#contexts / numTabsPerLine)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding(), 5.0)
    for line = 1, lineCount do
        --ImGui.Separator(ctx)  -- Add a separator between lines of tabs
        -- Calculate the position to center the buttons within the line
        local totalButtonWidth = numTabsPerLine * tabWidth
        local startX = (ImGui.GetWindowWidth(ctx) - totalButtonWidth - 120 - (numTabsPerLine - 1) * lineSpacing) / 2
        ImGui.SetCursorPosX(ctx, startX) -- Set the starting X position
        for i = 1, numTabsPerLine do
            local tabIndex = (line - 1) * numTabsPerLine + i
            if tabIndex <= #contexts then
                local context = contexts[tabIndex]
                local isButtonActive = (selectedContext == context)
                if isButtonActive then
                    ImGui.PushStyleColor(ctx, ImGui.Col_Button(), rgba(51, 204, 255))
                else
                    ImGui.PushStyleColor(ctx, ImGui.Col_Button(), rgba(51, 0, 255))
                end
                ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(), rgba(51, 153, 255))
                ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive(), rgba(51, 204, 255))
                if ImGui.Button(ctx, context, tabWidth, tabHeight) then
                    if isButtonActive then
                        selectedContext = nil                -- Toggle off if already active
                    else
                        selectedContext = context            -- Toggle on
                        currentContext = context
                    end
                end
                if string.match(context, "-") or string.find(context, "Top") or string.find(context, "Bottom") then
                    ImGui.SameLine(ctx)
                    script.HelpMarker("Adding menu here overrides the parent context in that part of the parent context region")
                end
                ImGui.PopStyleColor(ctx, 3)
                if i < numTabsPerLine then
                    ImGui.SameLine(ctx)
                end
            end
        end
        -- Add vertical spacing between lines of tabs
        if line < lineCount then
            --ImGui.Dummy(ctx, 0, lineSpacing)
            ImGui.Separator(ctx)
        end
    end
    ImGui.PopStyleVar(ctx)
    -- After the tab loop use the selectedContext to determine which context menus to show
    if selectedContext then
        ImGui.NewLine(ctx)
        ImGui.NewLine(ctx)
        ImGui.PushStyleColor(ctx, ImGui.Col_Button(), rgba(214, 0, 0))
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(), rgba(214, 0, 0))
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive(), rgba(214, 0, 0))
        ImGui.Button(ctx, "Menu for " .. selectedContext, windowWidth, buttonHeight)
        ImGui.PopStyleColor(ctx, 3)
        script.ShowContextMenus(selectedContext)
    end

    ImGui.Spacing(ctx)
    ImGui.Separator(ctx)
    ImGui.Spacing(ctx)
    -------------script name box--------------------------------------------------------------------
    -- Calculate center position for the label and textbox
    local windowWidth = ImGui.GetContentRegionAvail(ctx)
    local label = "Script Name:"
    local labelWidth = ImGui.CalcTextSize(ctx, label)
    local totalWidth = labelWidth + 200
    -- Center the label
    ImGui.SameLine(ctx, (windowWidth - totalWidth) * 0.2)
    ImGui.Text(ctx, label)
    -- Center the textbox
    ImGui.SameLine(ctx)
    rv, scriptName = ImGui.InputText(ctx, "##ScriptName", scriptName, 200)
    --rv, scriptName = ImGui.InputTextWithHint(ctx, '##input text (w/ hint)', '',scriptName)
    ImGui.SameLine(ctx); script.HelpMarker('Name your contextual menus lua script')
    ImGui.NewLine(ctx)
    -- Center the "Build Menus" button
    local windowWidth = ImGui.GetContentRegionAvail(ctx)
    local buttonWidth = 100
    ImGui.SameLine(ctx, (windowWidth - buttonWidth) * 0.5)

    --------- build menus button---------------------------------------------------------------------------------------
    if createStyledButton(ctx, "Build Menus", buttonWidth, 20, rgba(255, 0, 0), rgba(255, 85, 85), rgba(170, 0, 0), rgba(255, 255, 255)) then
        updateContextsData()
        local finalScript = generateFinalScript()
        local filePath = reaper.GetResourcePath() .. "/Scripts/" .. scriptName
        local file = io.open(filePath, "w")
        if file then
            file:write(finalScript)
            file:close()
            scriptGeneratedMessage = "Menu script generated at: " .. filePath
            -- Create or overwrite the Contextual_Menus_Startup file
            local startupFilePath = reaper.GetResourcePath() .. "/Scripts/Contextual_Menus_Startup"
            local startupFile = io.open(startupFilePath, "w")
            if startupFile then
                startupFile:write(filePath:gsub('\\', '/') .. '\n')
                startupFile:close()
            end
        else
            scriptGeneratedMessage = "Error: Unable to write to file."
        end
        scriptGeneratedTime = os.time()
        -- Check if the script is already added
        local scriptIsAdded = reaper.AddRemoveReaScript(true, 0, filePath, true)
        local scriptIsAdded = reaper.AddRemoveReaScript(true, 32060, filePath, true)
        --------------------------------------------------------------------------------------------------------
    end
    -- Tooltip display logic
    if os.time() - scriptGeneratedTime <= tooltipDuration then
        ImGui.SetTooltip(ctx, scriptGeneratedMessage)
    end
    ImGui.SameLine(ctx)
    script.HelpMarker('Click here when finish making your menus, to generate the contextual menu script \n It is automatically imported in Main and Midi Editor actions lists. Just add a shortcut')
    ---------------------dragndrop file and load script config button -----------------------
    ImGui.NewLine(ctx)
    ImGui.NewLine(ctx)
    ImGui.NewLine(ctx)
    ImGui.SameLine(ctx, (windowWidth - 600) * 0.5)
    if ImGui.BeginChildFrame(ctx, '##drop_files', 600, 20) then
        if #fileDropped == 0 then
            ImGui.Text(ctx, 'Drag and drop a generated contextual menu script here...')
        else
            ImGui.Text(ctx, fileDropped[1])
            --ImGui.SameLine(ctx)
            --if ImGui.SmallButton(ctx, 'Clear') then
            --  menu.info.files = {}
            --end
        end
        ImGui.EndChildFrame(ctx)
    end
    if ImGui.BeginDragDropTarget(ctx) then
        local rv, count = ImGui.AcceptDragDropPayloadFiles(ctx)
        if rv then
            fileDropped = {}
            local filename
            rv, filename = ImGui.GetDragDropPayloadFile(ctx, 0)
            table.insert(fileDropped, filename)
        end
        ImGui.EndDragDropTarget(ctx)
    end
    ImGui.SameLine(ctx); script.HelpMarker('Drag and drop a generated contextual menu script here to load its menus back inside the Builder')
    ------------------------------Load button--------------------
    ImGui.NewLine(ctx)
    ImGui.SameLine(ctx, (windowWidth - buttonWidth) * 0.5)
    if createStyledButton(ctx, "Load config", buttonWidth, 20, rgba(255, 0, 0), rgba(255, 85, 85), rgba(170, 0, 0), rgba(255, 255, 255)) then
        if fileDropped[1] then
            local loadResult, loadError = parseMenuItems(fileDropped[1], contexts)
            if loadResult then
                configLoadedMessage = "Configuration of menus loaded"
                -- Create or overwrite the Contextual_Menus_Startup file
                local startupFilePath = reaper.GetResourcePath() .. "/Scripts/Contextual_Menus_Startup"
                local startupFile = io.open(startupFilePath, "w")
                if startupFile then
                    startupFile:write(fileDropped[1]:gsub('\\', '/') .. '\n')
                    startupFile:close()
                end
            else
                configLoadedMessage = loadError or "Error loading configuration"
            end
        else
            configLoadedMessage = "No file selected. Please drag and drop a file first."
        end
        configLoadedTime = os.time() -- Update the load time
    end
    -- Tooltip display logic for config loading
    if os.time() - configLoadedTime <= tooltipDuration then
        ImGui.SetTooltip(ctx, configLoadedMessage)
    end
    ImGui.SameLine(ctx); script.HelpMarker('Loads menus from generated script back in the Builder for modifications')
    -----------------------------------------------------
    ImGui.End(ctx)
    return open
end

--------------------------------------------------------------------------------------------------------------------------
function script.ShowContextMenus(context)
    initializeContextData(context)
    local menu = contextData[context].menu
    local rv
    ImGui.NewLine(ctx)
    for _, name in ipairs({ 'Submenu', 'Action', 'Separator' }) do
        ImGui.SameLine(ctx)
        if createStyledButton(ctx, name, 110, 20, rgba(153, 0, 204), rgba(153, 102, 204), rgba(153, 153, 204), rgba(255, 255, 255)) then
            local newItem = { type = name, buffers = {}, indent = menu.info.currentIndentLevel }
            if name == "Submenu" then
                newItem.buffers = { Title = '' }
                menu.info.currentIndentLevel = menu.info.currentIndentLevel + 1
            elseif name == "Action" then
                newItem.buffers = { ActionName = '', ActionID = '' }
                newItem.indent = menu.info.currentIndentLevel
            elseif name == "Separator" then
                newItem.buffers = { Separator = '' }
                newItem.indent = menu.info.currentIndentLevel
            end
            -- Clear all previous selections
            for j = 1, #menu.info.clickedItems do
                menu.info.selectedIndices[j] = false
            end
            table.insert(menu.info.clickedItems, newItem)
            -- Select the newly added item
            menu.info.selectedIndices[#menu.info.clickedItems] = true

            if name == "Action" then
                selectedActionItemIndex = #menu.info.clickedItems
            end
        end
    end
    ImGui.SameLine(ctx); script.HelpMarker('Click on a menu item to add to the menu')
    -----------Next Level, Previous Level, Root Level---------------------------------------------------------------------
    ImGui.NewLine(ctx)
    --ImGui.SameLine(ctx)
    for _, name in ipairs({ 'Next Level', 'Previous Level', 'Root Level' }) do
        ImGui.SameLine(ctx)
        if createStyledButton(ctx, name, 110, 20, rgba(102, 0, 255), rgba(102, 153, 255), rgba(102, 204, 255), rgba(255, 255, 255)) then
            if name == "Next Level" then
                menu.info.currentIndentLevel = menu.info.currentIndentLevel + 1
            elseif name == "Previous Level" then
                menu.info.currentIndentLevel = math.max(menu.info.currentIndentLevel - 1, 0)
            elseif name == "Root Level" then
                menu.info.currentIndentLevel = 0
            end
        end
    end
    ImGui.SameLine(ctx); script.HelpMarker('Click these first, to place the next menu items \n in the corresponding layer')
    -------------Clear All and Remove Last--------------------------------------------------------------------------------
    ImGui.NewLine(ctx)
    for _, name in ipairs({ 'Clear All', 'Remove Last' }) do
        ImGui.SameLine(ctx)
        if createStyledButton(ctx, name, 110, 20, rgba(204, 0, 51), rgba(204, 102, 51), rgba(204, 153, 51), rgba(255, 255, 255)) then
            if name == "Clear All" then
                menu.info.clickedItems = {}
                menu.info.currentIndentLevel = 0
            elseif name == "Remove Last" then
                if #menu.info.clickedItems > 0 then
                    table.remove(menu.info.clickedItems)
                    if #menu.info.clickedItems > 0 then
                        currentIndentLevel = menu.info.clickedItems[#menu.info.clickedItems].indent
                    else
                        menu.info.currentIndentLevel = 0
                    end
                end
            end
        end
    end
    ----------------------delete button--------------------------------------------------------------------------------------
    local function deleteSelectedItems(context)
        local menu = contextData[context].menu
        -- Temporary table to hold non-selected items
        local updatedItems = {}
        -- Loop through all items and add non-selected ones to updatedItems
        for i, item in ipairs(menu.info.clickedItems) do
            if not menu.info.selectedIndices[i] then
                table.insert(updatedItems, item)
            end
        end
        -- Update the clickedItems with the items that were not selected
        menu.info.clickedItems = updatedItems
    end

    ImGui.SameLine(ctx)
    if createStyledButton(ctx, "Delete", 110, 20, rgba(204, 0, 51), rgba(204, 102, 51), rgba(204, 153, 51), rgba(255, 255, 255)) then
        deleteSelectedItems(context)
        -- Update currentIndentLevel to the max indent of remaining items
        local maxIndent = 0
        for _, item in ipairs(menu.info.clickedItems) do
            maxIndent = math.max(maxIndent, item.indent)
        end
        menu.info.currentIndentLevel = maxIndent
    end
    ImGui.SameLine(ctx); script.HelpMarker('Clear All: clears all entries and return to root level \n Remove Last: removes last added entry and remains at current level \n Delete: Deletes selected line(s). \n Use Ctrl + Left-Click to select multiple lines')
    --------------------copy paste buttons-----------------------------------------------------------------------------------
    ImGui.NewLine(ctx)
    ImGui.SameLine(ctx)
    if createStyledButton(ctx, "Copy", 110, 20, rgba(0, 145, 228), rgba(92, 205, 255), rgba(0, 72, 167), rgba(255, 255, 255)) then
        copiedItems = {}
        for i, item in ipairs(menu.info.clickedItems) do
            if menu.info.selectedIndices[i] then
                local copiedItem = { type = item.type, buffers = {}, indent = item.indent }
                for k, v in pairs(item.buffers) do
                    copiedItem.buffers[k] = v
                end
                table.insert(copiedItems, copiedItem)
            end
        end
    end

    ImGui.SameLine(ctx)
    if createStyledButton(ctx, "Paste", 110, 20, rgba(0, 145, 228), rgba(92, 205, 255), rgba(0, 72, 167), rgba(255, 255, 255)) then
        if #copiedItems > 0 then
            -- Get the base indent level of the first copied item
            local baseIndent = copiedItems[1].indent
            -- Calculate the difference between the current indent level and the base indent
            local indentDiff = menu.info.currentIndentLevel - baseIndent
            for _, item in ipairs(copiedItems) do
                -- Deep copy the item again to avoid reference issues
                local pastedItem = {
                    type = item.type,
                    buffers = {},
                    indent = math.max(0, item.indent + indentDiff) -- Adjust indent level
                }
                for k, v in pairs(item.buffers) do
                    pastedItem.buffers[k] = v
                end
                table.insert(menu.info.clickedItems, pastedItem)
            end
        end
    end
    ImGui.SameLine(ctx); script.HelpMarker('Select line(s) you want to copy \n click Copy, go to the context you want to copy \n and click Paste')
    ----------up down right left  buttons-----------------------------------------------------------------------------------
    -- "Up" Button
    ImGui.NewLine(ctx)
    ImGui.SameLine(ctx)
    if createStyledButton(ctx, "Up", 110, 20, rgba(51, 153, 0), rgba(51, 204, 0), rgba(51, 102, 0), rgba(255, 255, 255)) then
        local items = menu.info.clickedItems
        local indices = menu.info.selectedIndices
        for i = 2, #items do
            if indices[i] and not indices[i - 1] then
                items[i], items[i - 1] = items[i - 1], items[i]
                indices[i], indices[i - 1] = indices[i - 1], indices[i]
            end
        end
    end
    -- "Down" Button
    ImGui.SameLine(ctx)
    if createStyledButton(ctx, "Down", 110, 20, rgba(51, 153, 0), rgba(51, 204, 0), rgba(51, 102, 0), rgba(255, 255, 255)) then
        local items = menu.info.clickedItems
        local indices = menu.info.selectedIndices
        for i = #items - 1, 1, -1 do
            if indices[i] and not indices[i + 1] then
                items[i], items[i + 1] = items[i + 1], items[i]
                indices[i], indices[i + 1] = indices[i + 1], indices[i]
            end
        end
    end
    -- "Left" Button
    ImGui.SameLine(ctx)
    if createStyledButton(ctx, "Left", 110, 20, rgba(51, 153, 0), rgba(51, 204, 0), rgba(51, 102, 0), rgba(255, 255, 255)) then
        local items = menu.info.clickedItems
        local indices = menu.info.selectedIndices
        for i = 1, #items do
            if indices[i] then
                items[i].indent = math.max(items[i].indent - 1, 0) -- Ensure indentation doesn't go below 0
            end
        end
    end
    -- "Right" Button
    local maxIndentLevel = 10
    ImGui.SameLine(ctx)
    if createStyledButton(ctx, "Right", 110, 20, rgba(51, 153, 0), rgba(51, 204, 0), rgba(51, 102, 0), rgba(255, 255, 255)) then
        local items = menu.info.clickedItems
        local indices = menu.info.selectedIndices
        for i = 1, #items do
            if indices[i] then
                items[i].indent = math.min(items[i].indent + 1, maxIndentLevel)
            end
        end
    end
    ImGui.SameLine(ctx); script.HelpMarker('Moves selected line(s) (it keeps their original indentation)')
    ---------------add action button--------------------------------------------------------------------------------------
    local function getActionNameByCommandId(commandId, sectionId)
        local actionName = nil
        local actionCommandId = nil
        local index = 0
        repeat
            actionCommandId, actionName = reaper.CF_EnumerateActions(sectionId, index, "")
            if actionCommandId == commandId then
                return actionName
            end
            index = index + 1
        until actionCommandId == 0
        return nil -- Action name not found
    end

    local function getCommandIdByActionId(actionId)
        return reaper.ReverseNamedCommandLookup(actionId)
    end

    local function checkForActionSelection(currentContext, sectionId)
        local selectedActionId = reaper.PromptForAction(0, 0, sectionId)
        if selectedActionId == -1 then
            -- The action window is no longer available, stop checking
            isActionSelectionActive = false
            return
        elseif selectedActionId > 0 then
            -- An action has been selected
            local actionName
            local commandIdString = getCommandIdByActionId(selectedActionId)
            if commandIdString ~= nil and commandIdString:match("%D") then
                -- It's a custom/extension command (contains non-numeric characters)
                actionName = getActionNameByCommandId(selectedActionId, sectionId)
                -- Remove prefix "<string>: " if it exists
                actionName = string.gsub(actionName, "^[^:]+: ", "")
                -- Remove the ".lua" extension if it exists
                actionName = string.gsub(actionName, "%.lua$", "")
                commandId = "_" .. commandIdString
            else
                -- It's a native REAPER command
                actionName = reaper.CF_GetCommandText(0, selectedActionId)
                commandId = tostring(selectedActionId)
            end
            if selectedActionItemIndex and actionName then
                local item = menu.info.clickedItems[selectedActionItemIndex]
                if item and item.type == "Action" and currentContext == context then
                --if item and item.type == "Action" then
                    item.buffers.ActionID = commandId
                    item.buffers.ActionName = actionName
                    isActionSelectionActive = false
                end
            end
            
            reaper.PromptForAction(-1, 0, sectionId) -- Close the action list session
           else
        reaper.defer(function() checkForActionSelection(currentContext, sectionId) end) -- Continue checking
        end
    end

    if isActionSelectionActive then
        local buttonPosX, buttonPosY = ImGui.GetItemRectMin(ctx)
        local buttonHeight = ImGui.GetItemRectSize(ctx)
        local tooltipX = buttonPosX - 330
        local tooltipY = buttonPosY + buttonHeight
        ImGui.SetNextWindowPos(ctx, tooltipX, tooltipY)
        ImGui.BeginTooltip(ctx)
        ImGui.Text(ctx, "Double-click an Action in the Actions List to insert it in the selected line")
        ImGui.EndTooltip(ctx)
    end
    ImGui.NewLine(ctx)
    ImGui.SameLine(ctx)
    local isAddActionButtonActive = false

    local normalBgColor = rgba(255, 236, 0)
    local activeBgColor = rgba(231, 174, 0)
    local hoverColor = rgba(253, 255, 37)
    local textColor = rgba(0, 0, 0)
    -- Choose the background color based on the action selection process
    local bgColor = isActionSelectionActive and activeBgColor or normalBgColor
    -- Apply style
    ImGui.PushStyleColor(ctx, ImGui.Col_Button(), bgColor)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(), hoverColor)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive(), activeBgColor)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text(), textColor)
    -- Render the button
    if ImGui.Button(ctx, "Add Action", 110, 20) and not isActionSelectionActive then
        --isActionSelectionActive = true
        isActionSelectionActive = not isActionSelectionActive -- Toggle the active state
            if isActionSelectionActive then
        local sectionId = 0
        if currentContext and currentContext:find("^Midi") then
            sectionId = 32060                     -- MIDI editor action list
        end
        reaper.PromptForAction(1, 0, sectionId)   -- Open action list
        reaper.defer(function() checkForActionSelection(currentContext, sectionId) end)
        end
    end
    ImGui.PopStyleColor(ctx, 4)
    ImGui.SameLine(ctx); script.HelpMarker('Select an action line, click this then double click on action window to select the action you want \n this will copy action description and command id to "Action Name" and "Action ID" fields')
    ImGui.NewLine(ctx)
    if ImGui.Checkbox(ctx, "Show Indentation Level Numbers", menu.info.showIndentationNumbers) then
        menu.info.showIndentationNumbers = not menu.info.showIndentationNumbers
    end
    ---------------------render child window and table --------------------------------------------------------------------------
    do
        local window_flags = ImGui.WindowFlags_None()
        ImGui.PushStyleVar(ctx, ImGui.StyleVar_ChildRounding(), 5.0)
        if ImGui.BeginChild(ctx, 'ChildR', 0, 560, true, window_flags) then
            if ImGui.BeginTable(ctx, 'split', 3, ImGui.TableFlags_Resizable()) then
                ImGui.TableSetupColumn(ctx, "Column 1", ImGui.TableColumnFlags_WidthFixed(), 200)

                for i, item in ipairs(menu.info.clickedItems) do
                    ImGui.TableNextRow(ctx)
                    --local indentString = string.rep("  " .. (i-1).. "  ", item.indent)
                    -- Generate indentation string with numbers for each level
                    local indentString = ""
                    if menu.info.showIndentationNumbers then
                        for j = 1, item.indent - 1 do
                            indentString = indentString .. "     " -- Just spaces for previous levels
                        end
                        if item.indent > 0 then
                            indentString = indentString .. "  " .. item.indent .. "  " -- The current level number
                        end
                        --for j = 1, item.indent do
                        --  indentString = indentString .. "  " .. j .. "  "  -- Adjust spacing as needed
                        --end
                    else
                        indentString = string.rep("     ", item.indent) -- Just spaces for indentation without numbers
                    end

                    ImGui.TableNextColumn(ctx)
                    ImGui.Text(ctx, indentString .. item.type)

                    ImGui.TableNextColumn(ctx)

                    if item.type == "Submenu" then
                        rv, item.buffers.Title = ImGui.InputText(ctx, "Title##" .. i, item.buffers.Title)
                        ImGui.TableNextColumn(ctx) -- Empty column for alignment
                    elseif item.type == "Action" then
                        rv, item.buffers.ActionName = ImGui.InputText(ctx, "ActionName##" .. i, item.buffers.ActionName)
                        ImGui.TableNextColumn(ctx)
                        rv, item.buffers.ActionID = ImGui.InputText(ctx, "ActionID##" .. i, item.buffers.ActionID)
                    elseif item.type == "Separator" then
                        rv, item.buffers.ActionName = ImGui.Text(ctx, "-------------------")
                        ImGui.TableNextColumn(ctx)
                        rv, item.buffers.ActionName = ImGui.Text(ctx, "-------------------")
                    end

                    ImGui.TableSetColumnIndex(ctx, 0) -- Go back to the first column
                    if ImGui.Selectable(ctx, "##select" .. i, menu.info.selectedIndices[i], ImGui.SelectableFlags_SpanAllColumns()) then
                        if ImGui.IsKeyDown(ctx, ImGui.Mod_Ctrl()) then
                            -- CTRL key logic: toggle individual item
                            menu.info.selectedIndices[i] = not menu.info.selectedIndices[i]
                            lastClickedIndex = i
                        elseif ImGui.IsKeyDown(ctx, ImGui.Mod_Shift()) and lastClickedIndex then
                            -- SHIFT key logic: select a range of items
                            local startIdx = math.min(i, lastClickedIndex)
                            local endIdx = math.max(i, lastClickedIndex)
                            for j = startIdx, endIdx do
                                menu.info.selectedIndices[j] = true
                            end
                        else
                            -- No modifier key: clear selection and select current item
                            for j = 1, #menu.info.clickedItems do
                                menu.info.selectedIndices[j] = false
                            end
                            menu.info.selectedIndices[i] = true
                            lastClickedIndex = i
                        end

                        -- Action item selection logic
                        if item.type == "Action" then
                            selectedActionItemIndex = i
                        end
                    end
                end
                ImGui.EndTable(ctx)
            end
            ImGui.EndChild(ctx)
        end
        ImGui.PopStyleVar(ctx)
    end
end
