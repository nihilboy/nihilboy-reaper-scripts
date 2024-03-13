-- @description A Visual FX Browser for REAPER
-- @version 1.0.3
-- author nihilboy
-- @about
--   # Visual FX Browser
--   This script provides a visual interface for browsing and inserting FX, FX chains, and track templates in REAPER. It allows you to preview and insert FX, FX chains, and track templates from a visual interface. It also allows you to organize and manage FX, FX chains, and track templates.
--   ### Prerequisites
--   RealmGui, js_ReaScriptAPI
-- @changelog
--  + load and attach font in correct order when rendering

----------------------------------SEXAN FX BROWSER
local r = reaper
local os_separator = package.config:sub(1, 1)
local reaper_path = r.GetResourcePath()
local fx_browser_script_path = reaper_path .. "/Scripts/Sexan_Scripts/FX/Sexan_FX_Browser_ParserV7.lua"

function ThirdPartyDeps()
    local reapack_process
    local repos = {
        { name = "Sexan_Scripts",    url = 'https://github.com/GoranKovac/ReaScripts/raw/master/index.xml' },
    }

    for i = 1, #repos do
        local retinfo, url, enabled, autoInstall = r.ReaPack_GetRepositoryInfo(repos[i].name)
        if not retinfo then
            retval, error = r.ReaPack_AddSetRepository(repos[i].name, repos[i].url, true, 0)
            reapack_process = true
        end
    end

    -- ADD NEEDED REPOSITORIES
    if reapack_process then
        r.ReaPack_ProcessQueue(true)
        reapack_process = nil
    end
end

local function CheckDeps()
    ThirdPartyDeps()
    local deps = {}

    if not r.ImGui_GetVersion then
        deps[#deps + 1] = '"Dear Imgui"'
    end
    if not r.file_exists(fx_browser_script_path) then
        deps[#deps + 1] = '"FX Browser Parser V7"'
    end

    if #deps ~= 0 then
        r.ShowMessageBox("Need Additional Packages.\nPlease Install it in next window", "MISSING DEPENDENCIES", 0)
        r.ReaPack_BrowsePackages(table.concat(deps, " OR "))
        return true
    end
end

if CheckDeps() then return end
--------------------------------------------------------------------
-- Visual FX Browser Nihilboy
-------simplifying syntax for calling ImGui functions ImGui. instead of reaper.ImGui_
local ImGui = {}
for name, func in pairs(reaper) do
  name = name:match('^ImGui_(.+)$')
  if name then ImGui[name] = func end
end
--------------------SEXAN-------------------------------
if r.file_exists(fx_browser_script_path) then
    dofile(fx_browser_script_path)
end
------------------------------------
local ctx = ImGui.CreateContext('Visual FX Browser') -- Create a new ImGui context
local resource_path = reaper.GetResourcePath():gsub("\\", "/") -- Get the resource path
local scriptPath = resource_path .. "/Scripts/nihilboy-reaper-scripts/Visual-FX-Browser/" -- Store the path of the script
local screenshotsFolder =  scriptPath .. "Visual_FX_Browser_Screenshots/" --store path of the FX screenshots
local categoriesItemsData = scriptPath .. "Visual_FX_Browser_data.csv" --store path of the file to store categories and plugins
local fxBrowserConfigPath = scriptPath .. "Visual_FX_Browser_config" --store last use selections
local fileDropped = {} --for ttf file
local categories = {} -- store all info structure is like this :categories = {{name = "category name", favorite = true, default = true, items = {{type = "plugin/fxchain/tracktemplate", name = "item name", filePath = "path to file", index = number},..},...}"
local imageScale = 0.7 -- Initial scaling factor for images
local minScale = 0.1 -- Minimum scale 
local maxScale = 2.0 -- Maximum scale
local customFont = nil
local customFontsmall = nil
local customFontsmaller = nil
local font_path = nil
local closeAfterClick = false -- Flag to close the window after insert an item to the track
local searchQuery = "" -- Store user's search input
local selectedItems = {} 
local isDraggingItem = false
local payload = nil  --for drag n drop
local undoStack = {}
local draggedPluginName = ""
local hoveredPluginName = nil
local selectedFxChainName = ""
local selectedTrackTemplateName = ""
local selectedTrackTemplatePath = ""
local fxChainToLoad = nil
local newCategoryName = ""
local isWindowOpen = true

-- To keep track of loaded ImGui image objects, indexed by category
local loadedImages = {}
local selectedCategory = nil
local selectedCategoryName  = nil
local selectedCategoryIndex = nil
local selectedCategoryIsDefault = nil
local selectedCategoryImagePath = nil
-- Flag to indicate a font load request
local fontLoadRequested = false
local maxHeight = 250 -- Adjust as needed
local selectedCategories = {}
local rightClickedItem = nil
local padding = 5
local leftSectionWidth = 200
local useReaperTheme = true

local shouldDetachFonts = false
local clipboard = {}
local isProcessing = false
local currentItemIndex = 0
local totalItemsToProcess = 0
local stopProcessing = false
local openFloatingWindows = false -- This holds whether to open FX windows side by side or not
local nextWindowPosX = 0
local nextWindowPosY = 0
local maxHeightInRow = 0
local isFirstRow = true
local rowCounter = 0
local windowHeight = 0 -- This will be adjusted based on the tallest window in each row.
-- State variables for filter checkboxes
local showVST = true
local showVST3 = true
local showJS = true
local showCLAP = true
local searchAllCategories = false


-------------------------------Open Floating Windows Functions--------------------------------
-- Function to reset window placement for a new batch of FX windows
local function resetWindowPlacement()
    nextWindowPosX = 0
    nextWindowPosY = 0
    maxHeightInRow = 0
    isFirstRow = true
    local rowCounter = 0
end

-- Function to get screen dimensions
local function getScreenDimensions()
    local main_hwnd = reaper.GetMainHwnd() -- Get handle to the main REAPER window
    local _, left, top, right, bottom = reaper.JS_Window_GetClientRect(main_hwnd)
    return right - left, bottom - top
end

-- Function to get window size
local function getWindowSize(hwnd)
    local retval, left, top, right, bottom = reaper.JS_Window_GetClientRect(hwnd)
    if retval then
        return right - left, bottom - top -- width, height
    end
    return 0, 0 -- Default to 0 if size can't be obtained
end

-- arranges FX windows in an orderly grid-like pattern across the screen,
-- it defers the positioning attempt if the window hasn't opened yet
local function positionFXWindowDeferred(track, fxIndex, attemptCount)
    if not openFloatingWindows or attemptCount > 5 then return end
    local hwnd = reaper.TrackFX_GetFloatingWindow(track, fxIndex) -- Get the floating window handle
    if hwnd then
        local screenRight, screenBottom = getScreenDimensions() -- Get screen dimensions
        local windowWidth, windowHeight = getWindowSize(hwnd) -- Get window dimensions 
        -- Check if it's time to move to the next row
        if nextWindowPosX + windowWidth > screenRight then -- If the next window exceeds the screen width
            nextWindowPosX = 0 -- Reset to the left
            if isFirstRow or rowCounter % 2 == 0 then -- If it's the first row or an even row
                nextWindowPosY = nextWindowPosY + maxHeightInRow  -- Move to the next row
            else -- If it's an odd row
                nextWindowPosY = nextWindowPosY + 50 -- Slightly offset windows for visibility
            end
            rowCounter = rowCounter + 1 -- Increment row counter
            maxHeightInRow = windowHeight -- Reset max height for the new row
            isFirstRow = false -- No longer the first row
        else -- If the next window fits in the current row
            maxHeightInRow = math.max(maxHeightInRow, windowHeight) -- Update max height for the row
        end
        if nextWindowPosY + windowHeight > screenBottom then  -- If the next window exceeds the screen height
            resetWindowPlacement() -- Reset window placement
            rowCounter = 0 -- Resetting row counter
        end
        reaper.JS_Window_Move(hwnd, math.floor(nextWindowPosX), math.floor(nextWindowPosY)) -- Position the window
        nextWindowPosX = nextWindowPosX + windowWidth + 10 -- Update positions for the next window
    else
        reaper.defer(function() positionFXWindowDeferred(track, fxIndex, attemptCount + 1) end) -- Retry after a short delay
    end
end

local function openAndPositionFXWindow(track, fxIndex) 
    if not openFloatingWindows then return end
    reaper.TrackFX_Show(track, fxIndex, 3) -- Open the FX window
    positionFXWindowDeferred(track, fxIndex, 0) -- Start deferred positioning with 0 attempts initially
end

local function openAllFXWindowsInChain(track, startFxIndex)
    local fxCount = reaper.TrackFX_GetCount(track) -- Get the number of FX in the track
    for fxIndex = startFxIndex, fxCount - 1 do -- Iterate over the FX chain
        openAndPositionFXWindow(track, fxIndex) -- Open and position each FX window
    end
end
-----------------------------------------------------------------------------------------------
-- Function to load a FX/fx Chain/Track Template by name into the selected track(s) or in a new track
local function loadItemIntoTracks(itemName, itemType, createNewTrack, existingTrack)
    --add in new track 
        local fxIndex
        if createNewTrack then
            if not existingTrack then
                reaper.InsertTrackAtIndex(reaper.CountTracks(0), true) -- Insert a new track at the end of the track index
                existingTrack = reaper.GetTrack(0, reaper.CountTracks(0) - 1) -- Get the newly added track
            end
            if itemType == "plugin" then 
                local fxIndex  = reaper.TrackFX_AddByName(existingTrack, itemName, false, -1) -- Add the plugin to the track
                openAllFXWindowsInChain(existingTrack, fxIndex) -- Open all FX windows in the chain
            elseif itemType == "fxChain" then
                local fxChainPath = itemName .. ".RfxChain"
                local fxIndex = reaper.TrackFX_AddByName(existingTrack, fxChainPath, false, -1) -- Add the FX chain to the track
                openAllFXWindowsInChain(existingTrack, fxIndex) -- Open all FX windows in the chain
                
            elseif itemType == "trackTemplate" then
                local trackTemplatePath = reaper.GetResourcePath() ..  "/TrackTemplates/" .. itemName .. ".RTrackTemplate"
                reaper.Main_openProject(trackTemplatePath) 
            end      
        else
            
            local trackCount = reaper.CountSelectedTracks(0) -- Get the number of selected tracks
            for i = 0, trackCount - 1 do -- Iterate over the selected tracks
                local track = reaper.GetSelectedTrack(0, i) -- Get the selected track
                if itemType == "plugin"  then
                    local fxIndex = reaper.TrackFX_AddByName(track, itemName, false, -1) -- Add the plugin to the track
                    openAndPositionFXWindow(track, fxIndex) -- Open and position the FX window
                    resetWindowPlacement() 
                elseif itemType == "fxChain" then
                    local fxChainPath = itemName .. ".RfxChain"
                    local fxIndex = reaper.TrackFX_AddByName(track, fxChainPath, false, -1)
                    openAllFXWindowsInChain(track, fxIndex)
                elseif itemType == "trackTemplate" then
                    local trackTemplatePath = reaper.GetResourcePath() ..  "/TrackTemplates/" .. itemName .. ".RTrackTemplate"
                    reaper.Main_openProject(trackTemplatePath) -- Assuming itemName is a path to the track template file
                end
            end
        end    
    return existingTrack, fxIndex 
end

-------------------Utility functions------------------------------------
local function findItemTypeByName(items, itemName)
    for _, item in ipairs(items) do
        if item.name == itemName then
            return item.type 
        end
    end
    return nil 
end

local function findItemTypeByNameAndCategory(selectedCategory, itemName)
    if not selectedCategory or not itemName then return nil end

    for _, item in ipairs(selectedCategory.items) do
        if item.name == itemName then
            return item.type
        end
    end

    return nil -- Item not found within the selected category
end

-- Function to check if a file exists
local function fileExists(filePath)
    local file = io.open(filePath, "r")
    if file then
        file:close()
        return true
    else
        return false
    end
end

local function RGBAToNative(r, g, b, a)
    return (a<<24) | (r<<16) | (g<<8) | b
end

-- obtain theme-specific colors from REAPER and converting them into a format (RGBA) 
function GetReaperThemeColorRGBA(ini_key)
    local color = reaper.GetThemeColor(ini_key, 0)
    local r, g, b = reaper.ColorFromNative(color)
    -- Shift and combine RGB values into a single integer, assuming full opacity for alpha
    local rgba = (r << 24) | (g << 16) | (b << 8) | 0xFF
    return rgba
end

-------------Script Initialization Data functions--------------------------------    
local function readDataFromCSV(filePath)
    local categories = {}
    local file = io.open(filePath, "r")
    if not file then
        reaper.ShowMessageBox("Failed to open file for reading: " .. filePath, "Error", 0)
        return categories
    end
    for line in file:lines() do
        local categoryName, categoryIndex, isDefault, categoryImagePath, itemType, itemIndex, isFavorite, itemName, itemPath = line:match("([^*]+)%*(%d+)%*([^*]+)%*([^*]+)%*([^*]+)%*(%d+)%*([^*]+)%*([^*]+)%*([^*]+)")
        -- Convert strings "true"/"false" to boolean
        isDefault = isDefault == "true"
        isFavorite = isFavorite == "true"
        categoryIndex = tonumber(categoryIndex)
        itemIndex = tonumber(itemIndex)
        local foundCategory = nil

        for _, category in ipairs(categories) do
            if category.name == categoryName then
                foundCategory = category
                break
            end
        end

        if not foundCategory then
            
            foundCategory = {name = categoryName, index = categoryIndex, isDefault = isDefault, categoryImagePath = categoryImagePath, items = {}}
            table.insert(categories, foundCategory)
        end
        table.insert(foundCategory.items, {type = itemType, index = itemIndex, isFavorite = isFavorite, name = itemName, filePath = itemPath})
    end
    file:close()
    
    for _, category in ipairs(categories) do
        table.sort(category.items, function(a, b) return a.index < b.index end)
    end
    return categories
end

local function writeDataToCSV(filePath, categories)
    local file = io.open(filePath, "w") 
    if not file then
        reaper.ShowMessageBox("Failed to open file for writing: " .. filePath, "Error", 0)
        return
    end
    for _, category in ipairs(categories) do
        for _, item in ipairs(category.items) do
            local line = string.format('%s*%d*%s*%s*%s*%d*%s*%s*%s\n', category.name, category.index or 0, tostring(category.isDefault), category.categoryImagePath or nil, item.type, item.index, tostring(item.isFavorite), item.name, item.filePath)
            file:write(line)
        end
    end
    file:close() 
end

local function saveConfig(filePath, config)
    local file = io.open(filePath, "w")
    if file then
        -- Assuming config is a flat table with no nested tables
        for key, value in pairs(config) do
            file:write(key .. "," .. tostring(value) .. "\n")
        end
        file:close()
    else
        error("Could not open file for writing: " .. filePath)
    end
end

local function loadConfig(filePath)
    local config = {}
    local file = io.open(filePath, "r")
    if file then
        for line in file:lines() do
            local key, value = line:match("([^,]+),(.+)")
            if key and value then
                config[key] = value
            end
        end
        file:close()
    end
    return config
end
-------------------create images functions---------------------------------
----function to take screenshot of plugin window corrected by Edgemeal 
local function takeScreenshot(pluginName, track, fxIndex)
    local window = reaper.TrackFX_GetFloatingWindow(track, fxIndex )  -- Get the floating window handle 
    if window == nil then reaper.ShowConsoleMsg("Failed to find plugin in FloatingWindow\n") return end
    
    local retval, w, h = reaper.JS_Window_GetClientSize(window) -- * This returns whole window size!
    if retval == true then
        x=8 y=58 w=w-1 h=h-27 -- Offsets for Win10, ignore controls at top of FX window & boarders on 1080p screen, 100% scalling
        local srcDC = reaper.JS_GDI_GetWindowDC(window) -- Get the device context of the window
        local destBmp = reaper.JS_LICE_CreateBitmap(true, w, h) -- Create a bitmap to store the screenshot
        local destDC = reaper.JS_LICE_GetDC(destBmp) -- Get the device context of the bitmap
        reaper.JS_GDI_StretchBlit(destDC, 0, 0, w, h, srcDC, x, y, w, h) -- Copy/Crop window to bitmap
        local sanitizedPluginName = pluginName:gsub("[-'>,.:_/%s]", "_")
        local path = screenshotsFolder .. sanitizedPluginName   .. '.png' -- Construct the file path
        reaper.JS_LICE_WritePNG(path, destBmp, false) -- Save the bitmap as a PNG file
        reaper.JS_GDI_ReleaseDC(window, srcDC) -- Release the device context of the window
        reaper.JS_LICE_DestroyBitmap(destBmp) -- Destroy the bitmap 
        return
    end
end
-- function to create image with text for fxChains/TrackTemplates
local function createImageWithText(imageText)
   
    -- Dimensions for the bitmap
    local w, h = 398, 258  
    -- Create a bitmap
    local bitmap = reaper.JS_LICE_CreateBitmap(true, w, h)
    if not bitmap then return end -- Error handling if bitmap creation fails
    -- Fill the bitmap with a solid color (e.g., black background)
    local blackColor = RGBAToNative(0, 0, 0, 255) -- Black background
    reaper.JS_LICE_Clear(bitmap, blackColor)

    -- Create a font
    local fontHeight = 24
    local fontWeight = 700 -- Bold
    local fontAngle = 0
    local fontItalic = false
    local fontUnderline = false
    local fontStrikeOut = false
    local fontName = "Arial"
    local gdiFont = reaper.JS_GDI_CreateFont(fontHeight, fontWeight, fontAngle, fontItalic, fontUnderline, fontStrikeOut, fontName)

    -- Convert GDI font to LICE font
    local liceFont = reaper.JS_LICE_CreateFont()
    reaper.JS_LICE_SetFontFromGDI(liceFont, gdiFont, "")

    -- Set font color (white) and font background color (transparent)
    local textColor = RGBAToNative(255, 255, 255, 255) -- White color for text
    local bkColor = RGBAToNative(0, 0, 0, 0) -- Transparent background for text
    reaper.JS_LICE_SetFontColor(liceFont, textColor)
    reaper.JS_LICE_SetFontBkColor(liceFont, bkColor)

    -- Draw text on the bitmap
    --local textLen = string.len(imageText)
    --local x1, y1, x2, y2 = 10, 10, 390, 190 -- Text bounding box
    --reaper.JS_LICE_DrawText(bitmap, liceFont, imageText, textLen, x1, y1, x2, y2)

    -- Measure text and calculate positions
    local lines = {}
    for line in string.gmatch(imageText, "[^\n]+") do
        -- Check if the line contains a path
        local lastSlashIndex = line:match(".*/()")
        if lastSlashIndex then
            -- Extract the part after the last slash
            line = line:sub(lastSlashIndex)
        end
        table.insert(lines, line)
    end

    local totalTextHeight = 0
    for _, line in ipairs(lines) do
        local textWidth, textHeight = reaper.JS_LICE_MeasureText( line)
        totalTextHeight = totalTextHeight + textHeight
    end

    local startY = (h - fontHeight*2) / 2
    for _, line in ipairs(lines) do
        local textWidth, textHeight = reaper.JS_LICE_MeasureText(line)
        --reaper.ShowConsoleMsg("Text width: " .. tostring(textWidth) .. ", Text height: " .. tostring(textHeight) .. "\n")
        local startX = (w - 1.46*textWidth) / 2
        startX = math.floor(startX)
        startY = math.floor(startY)
        textWidth = math.floor(textWidth*1.46)
        --reaper.ShowConsoleMsg("X: " .. tostring(startX) .. ", Y: " .. tostring(startY) .. "\n")
        reaper.JS_LICE_DrawText(bitmap, liceFont, line, textWidth,startX, startY, startX+textWidth, startY+fontHeight)
        startY = startY + textHeight + fontHeight / 2 -- Adjust spacing between lines
    end




        -- Save the bitmap as PNG
    local sanitizedImageText = imageText:gsub("[-:_/%s]", "_")
    local outputPath = screenshotsFolder .. sanitizedImageText  .. '.png' -- Construct the file path
    reaper.JS_LICE_WritePNG(outputPath, bitmap, false)

    -- Release resources
    reaper.JS_LICE_DestroyBitmap(bitmap)
    reaper.JS_GDI_DeleteObject(gdiFont)
    reaper.JS_LICE_DestroyFont(liceFont)
    return outputPath
end

--function to wait for GUI to render
local function waitForGUIRendered(callback)
    local startTime = reaper.time_precise()
    local function check()
        if reaper.time_precise() - startTime < 2 then -- Wait for 2 seconds
            reaper.defer(check) -- Continue waiting
        else
            callback() -- Execute the callback function after the wait
        end
    end
    check()
end
-- Function to unload the plugin from the track and then delete the track
local function unloadPlugin(track, fxIndex)
    local success = reaper.TrackFX_Delete(track, fxIndex) -- Remove the plugin from the track
    if not success then
        reaper.ShowConsoleMsg("Failed to remove plugin from track\n")
        return false
    end
     --Delete the track
    local trackIndex = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
     reaper.DeleteTrack(reaper.GetTrack(0, trackIndex))
    return true
end
-- Combined function to load a plugin, wait, take a screenshot, and unload
local function loadAndCapturePlugin(pluginName, callback)
    --------------------TO BE DELETED
    -- Skip plugins with names starting with "CLAP:"
    if string.sub(pluginName, 1, 5) == "CLAP:" or pluginName:find("Spherix") then
        --reaper.ShowConsoleMsg("Skipping CLAP plugin: " .. pluginName .. "\n")
        if callback then
            callback() -- Ensure callback is still called to continue any process chain
        end
        return
    end


    ----------------------
    -- Load the plugin because it was not found in existing files
    local trackIndex = reaper.CountTracks(0) -- Add a track index
    reaper.InsertTrackAtIndex(trackIndex, true) -- Insert a new track at the end of the track index
    local track = reaper.GetTrack(0, trackIndex) -- Get the newly added track
    local fxIndex = reaper.TrackFX_AddByName(track, pluginName, false, 1) -- Add the plugin to the track
    if fxIndex == -1 then
        reaper.ShowConsoleMsg("Failed to load plugin: " .. pluginName .. "\n")    
        return
    end
    reaper.TrackFX_Show(track, fxIndex, 3) -- Show the plugin window
    -- Wait for the GUI to render, then take a screenshot and unload
    waitForGUIRendered( function() 
        takeScreenshot(pluginName, track, fxIndex) 
        unloadPlugin(track, fxIndex)
        if callback then
            callback()    
        end 
    end)   
end
-----------------------------------------------------------------------------
-- A function to update the categories table with a new item added
local function updateCategoriesWithItem(categoryName, itemType, itemName, itemPath)
    -- Check if the category exists
    local categoryFound = false
    for _, category in ipairs(categories) do
        if category.name == categoryName then
            categoryFound = true
            -- Check if the item already exists
            local itemExists = false
            for _, item in ipairs(category.items) do
                if item.name == itemName and item.filePath == itemPath then
                    itemExists = true
                    break
                end
            end
            if not itemExists then
                -- Item does not exist, so add it
                local nextIndex = #category.items + 1
                table.insert(category.items, {type = itemType, index = nextIndex, name = itemName, filePath = itemPath})
            end
            break
        end
    end
    if not categoryFound then
        -- Category does not exist, add a new category with the item
        categories[#categories + 1] = {name = categoryName, index = #categories + 1, isDefault = false, categoryImagePath = nil, items = {{type = itemType, index = 1, name = itemName, filePath = itemPath}}}
    end
end

-- function to handle addition of a new item depending its type 
local function handleItemAddition(categoryName, type, itemName, onComplete) 
    local sanitizedItemName = itemName:gsub("[-'>,.:_/%s]", "_")
    local filePath = screenshotsFolder .. sanitizedItemName .. '.png'
    if fileExists(filePath) then
        -- Screenshot exists, so just add the plugin to the category with the existing screenshot path
        updateCategoriesWithItem(categoryName, type, itemName, filePath)
        if onComplete then onComplete() end -- Call the callback if provided
    else
        if type == "plugin" then
            -- Screenshot does not exist, so capture it and then add to category
            loadAndCapturePlugin(itemName, function()
                -- Callback function after screenshot is taken
                local newScreenshotPath = screenshotsFolder .. itemName:gsub("[-'>,.:_/%s]", "_") .. ".png"
                updateCategoriesWithItem(categoryName, type, itemName, newScreenshotPath)
                if onComplete then onComplete() end -- Call the callback after async operation
            end)  
        else
            local newScreenshotPath = (type == "fxChain" and createImageWithText("FXCHAIN: \n" .. itemName)) or
                                      (type == "trackTemplate" and createImageWithText("TRACK TEMPLATE: \n" .. itemName))
            updateCategoriesWithItem(categoryName, type, itemName, newScreenshotPath)
            if onComplete then onComplete() end -- Call the callback
        end
    end
end
-------------------------------------------------------------------------------
-- Load the custom font requested in ImGui
local function loadAndAttachFonts()
    if fontLoadRequested then
        -- Load and attach new custom font if font_path is not nil
        if font_path then
            customFont = ImGui.CreateFont(font_path, 25)
            if customFont then
                ImGui.Attach(ctx, customFont)
            end
            customFontsmall = ImGui.CreateFont(font_path, 17)
            if customFontsmall then
                ImGui.Attach(ctx, customFontsmall)
            end
            customFontsmaller = ImGui.CreateFont(font_path, 16)
            if customFontsmaller then
                ImGui.Attach(ctx, customFontsmaller)
            end
        end
        fontLoadRequested = false
    elseif shouldDetachFonts then
        -- Detach custom fonts here and revert to default
        if customFont then ImGui.Detach(ctx, customFont) end
        if customFontsmall then ImGui.Detach(ctx, customFontsmall) end
        if customFontsmaller then ImGui.Detach(ctx, customFontsmaller) end
        -- Reset font variables
        customFont, customFontsmall, customFontsmaller = nil, nil, nil
        shouldDetachFonts = false
    end
end
--function for drag n drop  functionality from the browser to reaper
local function dragItemToReaper(selectedItems,item)
    if ImGui.BeginDragDropSource(ctx, ImGui.DragDropFlags_None()) then
       local selectedPluginCount = 0
       for _, isSelected in pairs(selectedItems) do
           if isSelected then selectedPluginCount = selectedPluginCount + 1 end
       end
       if selectedPluginCount > 0 then
           -- Handle multiple selected plugins
           payload = ""
           for itemName, isSelected in pairs(selectedItems) do
               if isSelected then
                   if payload ~= "" then payload = payload .. "," end -- Separator for multiple plugins
                   payload = payload .. itemName
               end
           end
       else
           -- Handle a single plugin (selected or just clicked)
           payload = item.name
       end
       ImGui.SetDragDropPayload(ctx, "PLUGIN_PAYLOAD", payload)
       ImGui.Text(ctx, "Dragging: " .. (selectedPluginCount > 1 and "Multiple Plugins" or payload))
       isDraggingItem = true
       ImGui.EndDragDropSource(ctx)
   end

   -- When the mouse is released, check if it's over a track and handle accordingly
   if ImGui.IsMouseReleased(ctx, ImGui.MouseButton_Left()) and isDraggingItem then
       local mouseX, mouseY = reaper.GetMousePosition()
       local track, info = reaper.GetThingFromPoint(mouseX, mouseY)
       -- Show message only if 'info' is not nil
        --if info ~= nil then
        --    reaper.ShowConsoleMsg("Info: " .. info .. "\n")  -- identify info return values
        --end
        local infoStart = string.sub(info or "", 1, 3)
        if track and (infoStart == 'tcp' or infoStart == 'mcp' or info == 'fx_chain') then
            
            -- Parse the payload for multiple plugins or use directly for a single plugin
            for itemName in string.gmatch(payload, '([^,]+)') do
                local itemType = findItemTypeByNameAndCategory(selectedCategory, itemName)
                
                if itemType == "plugin" then
                    local fxIndex = reaper.TrackFX_AddByName(track, itemName, false, -1)
                    openAndPositionFXWindow(track, fxIndex)
                elseif itemType == "fxChain" then
                    local fxIndex = reaper.TrackFX_AddByName(track, itemName .. ".RfxChain", false, -1)
                    openAndPositionFXWindow(track, fxIndex)
                elseif itemType == "trackTemplate" then
                    local trackTemplatePath = reaper.GetResourcePath() ..  "/TrackTemplates/" .. itemName .. ".RTrackTemplate"
                    reaper.Main_openProject(trackTemplatePath) -- Assuming itemName is a path to the track template file
                end
                --local fxIndex = reaper.TrackFX_AddByName(track, itemName, false, -1)
                --openAndPositionFXWindow(track, fxIndex)
            end
            if closeAfterClick then
                isWindowOpen = false
            end
        elseif info == 'arrange' then
            local item, take = reaper.GetItemFromPoint(mouseX, mouseY, true) -- true to allow locking
            if item and reaper.IsMediaItemSelected(item) then
                -- Add FX to the item take if the item is selected
                for itemName in string.gmatch(payload, '([^,]+)') do
                    local fxIndex = reaper.TakeFX_AddByName(take, itemName, -1)
                    openAndPositionFXWindow(track, fxIndex)
                end
            end
            if closeAfterClick then
                isWindowOpen = false
            end
        end     
        isDraggingItem = false -- Reset the flag after the drop is handled     
   end   
end

-- helper function to paste items from clipboard to the selected category when ctrl+V is pressed
local function pasteItemToCategory(itemName, targetCategoryName)
    local itemToCopy = nil

    -- Find the item and target category
    for _, category in ipairs(categories) do
        for _, item in ipairs(category.items) do
            if item.name == itemName then
                itemToCopy = item
                break
            end
        end
    end

    local targetCategory = nil
    for _, category in ipairs(categories) do
        if category.name == targetCategoryName then
            targetCategory = category
            break
        end
    end

    if itemToCopy and targetCategory then
        --reaper.ShowConsoleMsg("Pasting " .. itemName .. " to " .. targetCategoryName .. "\n")
        local newItemIndex = #targetCategory.items + 1
        local copiedItem = {
            type = itemToCopy.type,
            index = newItemIndex,
            name = itemToCopy.name,
            filePath = itemToCopy.filePath,
            isFavorite = itemToCopy.isFavorite
            
        }
        table.insert(targetCategory.items, copiedItem)
    end
end

-- function to handle keyboard shortcuts
local function keyboardShortcutItems(item, selectedCategory, selectedItems)
    if not selectedCategory then
        print("selectedCategory is nil")
        return 
    end
  local anyItemSelected = false
    for _, isSelected in pairs(selectedItems) do
        if isSelected then
            anyItemSelected = true
            break
        end
    end
  if ImGui.IsItemHovered(ctx) then
    local hoveredItemName = item.name
        local hoveredItemType = item.type
    ImGui.BeginTooltip(ctx)
    ImGui.Text(ctx, item.name) -- Display the plugin name as a tooltip
    ImGui.EndTooltip(ctx)
    if hoveredItemName then
            --key S will add hovered plugin or selected plugins in selected track(s)
      if ImGui.IsKeyPressed(ctx,  ImGui.Key_S()) then
        -- "S" key pressed with a plugin hovered
        if anyItemSelected then
          -- Load all selected plugins into current track
          for selectedItemName, isSelected in pairs(selectedItems) do
            if isSelected then
                            local selectedItemType = findItemTypeByName(selectedCategory.items, selectedItemName)
              loadItemIntoTracks(selectedItemName,selectedItemType, false) -- false to load into current track
            end
          end
        else
          -- No plugin selected, load only hovered plugin into current track
          loadItemIntoTracks(hoveredItemName,hoveredItemType, false)
        end
                if closeAfterClick then
                    isWindowOpen = false
                end
            -- key N will add hovered plugin or selected plugins in a new track
      elseif ImGui.IsKeyPressed(ctx,  ImGui.Key_N()) then
        if anyItemSelected then
          -- Load all selected plugins into a new track
          for selectedItemName, isSelected in pairs(selectedItems) do
            if isSelected then
                            local selectedItemType = findItemTypeByName(selectedCategory.items, selectedItemName)
              existingTrack = loadItemIntoTracks(selectedItemName,selectedItemType, true, existingTrack) -- Pass existingTrack
            end
          end
        else
          -- No plugin selected, load only hovered plugin into a new track
          loadItemIntoTracks(hoveredItemName, hoveredItemType, true)
        end
                if closeAfterClick then
                    isWindowOpen = false
                end
                -- key Del will delete selected plugins
      elseif ImGui.IsKeyPressed(ctx, ImGui.Key_Delete()) and anyItemSelected then
                for selectedItemName, isSelected in pairs(selectedItems) do    
                    if isSelected then
                        -- Delete the selected item from the category
                        for i = #selectedCategory.items, 1, -1 do
                            if selectedCategory.items[i].name == selectedItemName then    
                                table.remove(selectedCategory.items, i)
                                selectedItems[selectedItemName] = nil -- Unselect the item
                                break
                            end
                        end
                    end
                end
            end

            -- up down rright left
      --elseif if ImGui.IsKeyPressed(ctx, ImGui.Key_Z()) and ImGui.IsKeyDown(ctx, ImGui.Mod_Ctrl()) then
    end
    -- Copy operation (Ctrl+C)
    if ImGui.IsKeyPressed(ctx, ImGui.Key_C()) and ImGui.GetKeyMods(ctx) == ImGui.Mod_Ctrl() then
        clipboard = {} -- Clear clipboard for new copy operation
        --reaper.ShowConsoleMsg("Copy operation\n")
        
        for itemName, isSelected in pairs(selectedItems) do
            if isSelected then
                --reaper.ShowConsoleMsg("Copying " .. itemName .. " to clipboard\n")
                table.insert(clipboard, itemName) -- Add item name to clipboard
            end
        end
    end
    -- Paste operation (Ctrl+V) inside the child window
    if ImGui.IsKeyPressed(ctx, ImGui.Key_V()) and ImGui.GetKeyMods(ctx) == ImGui.Mod_Ctrl() then
        for _, itemName in ipairs(clipboard) do
            -- Check if item already exists in the category
            local exists = false
            for _, item in ipairs(selectedCategory.items) do
                if item.name == itemName then
                    exists = true
                    break
                end
            end
            if not exists then 
                pasteItemToCategory(itemName, selectedCategory.name)
            end
        end
        -- clear the clipboard after pasting
        -- clipboard = {}
    end
  end   
end

--used by rearrangeItems to reorder indexes in categories table
local function reorderItems(items, sourceIndexes, targetIndex)
    local movingItems = {}
    for _, srcIndex in ipairs(sourceIndexes) do
        table.insert(movingItems, items[srcIndex])
    end
    -- Remove items in reverse order to not mess up indexes
    for i = #sourceIndexes, 1, -1 do
        table.remove(items, sourceIndexes[i])
    end
    -- If targetIndex is beyond the last item, adjust it to be the last position
    if targetIndex > #items then
        targetIndex = #items + 1
    end
    -- Insert items back into their new positions
    local insertIndex = targetIndex
    for _, item in ipairs(movingItems) do
        table.insert(items, insertIndex, item)
        insertIndex = insertIndex + 1
    end
    -- Re-index items
    for i = 1, #items do
        items[i].index = i
    end
end

-- rearranging items in window by dragging
local function rearrangeItems(selectedCategory, selectedItems, item)
    if ImGui.GetKeyMods(ctx) == ImGui.Mod_Ctrl() then
        -- Determine if any item is selected
       local anyItemSelected = false
       for _, isSelected in pairs(selectedItems) do
           if isSelected then
               anyItemSelected = true
               break
           end
       end

       -- If the current item is being dragged with Ctrl and no item is selected, treat it as selected
       if not anyItemSelected then
           selectedItems[item.name] = true
       end
       -- Check if the current item is selected and Ctrl is pressed to start dragging
       if selectedItems[item.name] and ImGui.BeginDragDropSource(ctx,ImGui.DragDropFlags_None()) then
           local selectedIndexes = {}
           for _, catItem in ipairs(selectedCategory.items) do
               if selectedItems[catItem.name] then
                   table.insert(selectedIndexes, catItem.index)
               end
           end
           -- Convert the list of selected indexes to a string payload
           local payload = table.concat(selectedIndexes, ",")
           
           ImGui.SetDragDropPayload(ctx, "ITEMS_DRAG", payload)
           ImGui.Text(ctx, "Rearrange Selected: " .. item.name)
           ImGui.EndDragDropSource(ctx)
       end
       -- Reset the selection state if it was temporarily set for dragging
       if not anyItemSelected then
           selectedItems[item.name] = nil
       end
   end

   if ImGui.BeginDragDropTarget(ctx) then
       local retval, type, payload, is_preview, is_delivery = ImGui.GetDragDropPayload(ctx)
       if retval and type == "ITEMS_DRAG" then
        
        if ImGui.IsMouseReleased(ctx,0) then
           local sourceIndexes = {}
           for indexStr in string.gmatch(payload, "%d+") do
               table.insert(sourceIndexes, tonumber(indexStr))
           end
           table.sort(sourceIndexes) -- Ensure source indexes are in ascending order for consistent processing
   
           local targetIndex = item.index -- Drop target index
           reorderItems(selectedCategory.items, sourceIndexes, targetIndex)
       end
    end
       ImGui.EndDragDropTarget(ctx)
   end
end

-- draw the selected rectangle around the selected items
local function drawRectangleSelected(selectedItems, item, cursorPos, imgWidth, imgHeight)
    if selectedItems[item.name] then
        -- Get the draw list for the current window
        local draw_list = ImGui.GetWindowDrawList(ctx)
        -- Get cursor position to know where to draw the highlight 
        local highlightColor = 0xFF0000FF -- RGBA format, adjust the color as needed
        local thickness = 4.0 -- Adjust thickness as needed
        local scrollX, scrollY = ImGui.GetScrollX(ctx), ImGui.GetScrollY(ctx)
        -- Draw a rectangle around the plugin image for highlight
        local rectMinX = cursorPos[1] - scrollX
        local rectMinY = cursorPos[2] 
        local rectMaxX = rectMinX + imgWidth + 8
        local rectMaxY = rectMinY + imgHeight + 8 
        ImGui.DrawList_AddRect(draw_list,rectMinX, rectMinY,rectMaxX, rectMaxY,highlightColor, 0, 0, thickness)
    end 
end

-- used to update the category index in the categories table when use 
--Ctrl+Up or Ctrl+Down to move the selected category up or down
local function updateSelectedCategoryPosition(direction)
    local selectedIndex = nil
    for i, category in ipairs(categories) do
        if category.name == selectedCategoryName then
            selectedIndex = selectedCategoryIndex
            break
        end
    end

    if selectedIndex then
        local targetIndex = nil
        if direction == "up" and selectedIndex > 1 then
            targetIndex = selectedIndex - 1
        elseif direction == "down" and selectedIndex < #categories then
            targetIndex = selectedIndex + 1
        end

        if targetIndex then
            -- Move the category in the list
            local categoryToMove = table.remove(categories, selectedIndex)
            table.insert(categories, targetIndex, categoryToMove)

            -- Update selectedCategoryName and selectedCategoryIndex if needed
            selectedCategoryName = categories[targetIndex].name
            selectedCategoryIndex = targetIndex

            -- Reassign the index property for each category
            for i, category in ipairs(categories) do
                category.index = i
            end
        end
    end
end

-- used when load images for background or fxchains/track templates, to copy the image first in the screenshots folder
local function copyFileToScreenshotsFolder(sourcePath, screenshotsFolder)
    local fileName = sourcePath:match("^.+[/\\](.+)$")
    --reaper.ShowConsoleMsg("fileName: " .. tostring(fileName) .. "\n")
    --reaper.ShowConsoleMsg("sourcePath: " .. tostring(sourcePath) .. "\n")
    if not fileName then
        reaper.ShowMessageBox("Failed to extract file name from path.", "Error", 0)
        return nil
    end
    local destPath = screenshotsFolder  .. fileName
    local sourceFile, err1 = io.open(sourcePath, "rb")
    if not sourceFile then
        reaper.ShowMessageBox("Failed to open source file: " .. tostring(err1), "Error", 0)
        return nil
    end
    
    local destFile, err2 = io.open(destPath, "wb")
    if not destFile then
        reaper.ShowMessageBox("Failed to open destination file: " .. tostring(err2), "Error", 0)
        sourceFile:close()
        return nil
    end
    
    local content = sourceFile:read("*a") -- Read the entire content of the source file
    destFile:write(content)
    sourceFile:close()
    destFile:close()
    return destPath
end

-- used to open explorer window in reaper to load a .png image
local function selectImage()
    local retval, imagePath = reaper.GetUserFileNameForRead("", "Select Image", ".png")
    if retval then  
        imagePath = imagePath:gsub("\\", "/") -- Replace Windows path separators with Unix separators 
        return copyFileToScreenshotsFolder(imagePath, screenshotsFolder)
    else
        return nil -- User cancelled or no file selected
    end
end


-- function that manages an asynchronous queue of items to be processed one by one
local itemsToAddQueue = {}
local function processItemsToAddQueue()
    if stopProcessing then
        -- Prepare for possible continuation
        isProcessing = false
        stopProcessing = false
        -- Do not clear the queue or reset currentItemIndex to allow continuation
        return -- Exit the processing loop
    end

    if #itemsToAddQueue > 0 then
        isProcessing = true
        local item = itemsToAddQueue[1] -- Peek at the next item without dequeuing yet
        currentItemIndex = currentItemIndex + 1

        -- Process item (asynchronously)
        handleItemAddition(item.categoryName, item.itemType, item.itemName, function()
            -- Successfully processed, now dequeue and proceed
            table.remove(itemsToAddQueue, 1) -- Dequeue the processed item
            processItemsToAddQueue() -- Proceed to the next item
        end)
    else
        -- Done processing
        isProcessing = false
        stopProcessing = false -- Reset stopping flag for future operations
        currentItemIndex = 0
        totalItemsToProcess = 0
        itemsToAddQueue = {} -- Clear the queue for future operations
    end
end

-- function to add items to the queue
local function queueItemForAddition(categoryName, itemType, itemName)
    -- Add to the queue
    table.insert(itemsToAddQueue, {categoryName=categoryName, itemType=itemType, itemName=itemName})
    totalItemsToProcess = #itemsToAddQueue
end


--! SEXAN FX BROWSER
-----------------------SEXAN  FX BROWSER-----------------------------------
--local FX_LIST_TEST, CAT_TEST = GetFXTbl()

local FX_LIST_TEST, CAT_TEST = ReadFXFile()
if not FX_LIST_TEST or not CAT_TEST then
    FX_LIST_TEST, CAT_TEST = MakeFXFiles()
end
--CACHIN TO FILE

local function Lead_Trim_ws(s) return s:match '^%s*(.*)' end

local tsort = table.sort
function SortTable(tab, val1, val2)
    tsort(tab, function(a, b)
        if (a[val1] < b[val1]) then
            -- primary sort on position -> a before b
            return true
        elseif (a[val1] > b[val1]) then
            -- primary sort on position -> b before a
            return false
        else
            -- primary sort tied, resolve w secondary sort on rank
            return a[val2] < b[val2]
        end
    end)
end

local old_t = {}
local old_filter = ""
local function Filter_actions(filter_text)
    if old_filter == filter_text then return old_t end
    filter_text = Lead_Trim_ws(filter_text)
    local t = {}
    if filter_text == "" or not filter_text then return t end
    for i = 1, #FX_LIST_TEST do
        local name = FX_LIST_TEST[i]:lower() --:gsub("(%S+:)", "")
        local found = true
        for word in filter_text:gmatch("%S+") do
            if not name:find(word:lower(), 1, true) then
                found = false
                break
            end
        end
        if found then t[#t + 1] = { score = FX_LIST_TEST[i]:len() - filter_text:len(), name = FX_LIST_TEST[i] } end
    end
    if #t >= 2 then
        SortTable(t, "score", "name") -- Sort by key priority
    end
    old_t = t
    old_filter = filter_text
    return t
end

local function SetMinMax(Input, Min, Max)
    if Input >= Max then
        Input = Max
    elseif Input <= Min then
        Input = Min
    else
        Input = Input
    end
    return Input
end

local FILTER = ''
local function FilterBox()
    local MAX_FX_SIZE = 300
    r.ImGui_PushItemWidth(ctx, MAX_FX_SIZE)
    if r.ImGui_IsWindowAppearing(ctx) then r.ImGui_SetKeyboardFocusHere(ctx) end
    _, FILTER = r.ImGui_InputTextWithHint(ctx, '##input', "SEARCH FX", FILTER)
    local filtered_fx = Filter_actions(FILTER)
    local filter_h = #filtered_fx == 0 and 0 or (#filtered_fx > 40 and 20 * 17 or (17 * #filtered_fx))
    ADDFX_Sel_Entry = SetMinMax(ADDFX_Sel_Entry or 1, 1, #filtered_fx)
    if #filtered_fx ~= 0 then
        if r.ImGui_BeginChild(ctx, "##popupp", MAX_FX_SIZE, filter_h) then
            for i = 1, #filtered_fx do
                if r.ImGui_Selectable(ctx, filtered_fx[i].name, i == ADDFX_Sel_Entry) then
                        handleItemAddition(selectedCategoryName, "plugin", filtered_fx[i].name)
                    r.ImGui_CloseCurrentPopup(ctx)
                    LAST_USED_FX = filtered_fx[i].name
                    FILTER = ''
                end
            end
            r.ImGui_EndChild(ctx)
        end
        if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Enter()) then
            
                handleItemAddition(selectedCategoryName, "plugin", filtered_fx[ADDFX_Sel_Entry].name)
            LAST_USED_FX = filtered_fx[filtered_fx[ADDFX_Sel_Entry].name]
            ADDFX_Sel_Entry = nil
            FILTER = ''
            r.ImGui_CloseCurrentPopup(ctx)
        elseif r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_UpArrow()) then
            ADDFX_Sel_Entry = ADDFX_Sel_Entry - 1
        elseif r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_DownArrow()) then
            ADDFX_Sel_Entry = ADDFX_Sel_Entry + 1
        end
    end
    if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape()) then
        FILTER = ''
        r.ImGui_CloseCurrentPopup(ctx)
    end
    return #filtered_fx ~= 0
end







local selectedFXChainDirectory = nil -- Track the currently selected FX Chain directory
local selectedFXChainDirectoryName = nil -- Track the currently selected FX Chain directory
local function DrawChainTemplatesItems(tbl, basePath, itemType)
    
    basePath = basePath or ""
    for i, item in ipairs(tbl) do
        local currentPath = basePath
        if item.dir then
            -- It's a directory
            currentPath = basePath .. "/" .. item.dir
            currentPath = currentPath:gsub("\\", "/") -- Ensure forward slashes
            selectedFXChainDirectory = item
            selectedFXChainDirectoryName = item.dir
            if r.ImGui_BeginMenu(ctx, item.dir) then
                -- Recursive call to handle nested directories with the updated path
                DrawChainTemplatesItems(item, currentPath, itemType)
                r.ImGui_EndMenu(ctx)
            end

            if r.ImGui_IsItemClicked(ctx, 1) then -- Right-click
                -- Determine the appropriate popup ID based on item type
                local popupId = itemType == "fxChain" and "fxChainSubCategoryImportMenu" or "trackTemplateSubCategoryImportMenu"
                -- Open the corresponding popup
                r.ImGui_OpenPopup(ctx, popupId)
            end
        elseif type(item) == "string" then
            -- It's a file
            if r.ImGui_Selectable(ctx, item) then
                local filePath = basePath .. "/" .. item
                handleItemAddition(selectedCategoryName, itemType, filePath)
            end
        end
    end

     -- Handle right-click context menu for subcategory import
     local subCategoryPopupId = itemType == "fxChain" and "fxChainSubCategoryImportMenu" or "trackTemplateSubCategoryImportMenu"
     if r.ImGui_BeginPopupContextItem(ctx, subCategoryPopupId) then
         local label = "Import All from " .. (selectedFXChainDirectoryName or "this category")
         
         if r.ImGui_MenuItem(ctx, label) then
             local function importAllItems(currentTbl, currentPath)
                 for _, nestedItem in ipairs(currentTbl) do
                    if type(nestedItem) == "table" and nestedItem.dir then
                         local nestedPath = currentPath .. "/" .. nestedItem.dir
                         nestedPath = nestedPath:gsub("\\", "/")
                         importAllItems(nestedItem, nestedPath)
                     elseif type(nestedItem) == "string" then
                         local nestedFilePath = currentPath .. "/" .. nestedItem
                         nestedFilePath = nestedFilePath:gsub("\\", "/")
                         handleItemAddition(selectedCategoryName, itemType, nestedFilePath)
                     end
                 end
             end
             importAllItems(selectedFXChainDirectory, basePath)
         end
         r.ImGui_EndPopup(ctx)
     end
     
     
    
    -- Main category right-click context menu handling
    local mainCategoryPopupId = itemType == "fxChain" and "fxChainImportMenu" or "trackTemplateImportMenu"
    if r.ImGui_IsItemClicked(ctx, 1) and (itemType == "fxChain" or itemType == "trackTemplate") then
        -- Open the main category import menu
        r.ImGui_OpenPopup(ctx, mainCategoryPopupId)
    end
    if r.ImGui_BeginPopupContextItem(ctx, mainCategoryPopupId) then
        if r.ImGui_MenuItem(ctx, "Import All from " .. (itemType == "fxChain" and "FX CHAINS" or "TRACK TEMPLATES")) then
            -- Define a recursive function to process each item in the directory
            local function importAllItems(currentTbl, currentPath)
                for _, nestedItem in ipairs(currentTbl) do
                    if nestedItem.dir then
                        local nestedPath = currentPath .. "/" .. nestedItem.dir
                        importAllItems(nestedItem, nestedPath)
                    elseif type(nestedItem) == "string" then
                        local nestedFilePath = currentPath .. "/" .. nestedItem
                        handleItemAddition(selectedCategoryName, itemType, nestedFilePath)
                    end
                end
            end
    
            importAllItems(tbl, "")
        end
        r.ImGui_EndPopup(ctx)
    end
end



local browserSelectedItemNames = {}
local selectionStartIndex = nil -- Starting point of the selection
local selectionEndIndex = nil -- Ending point of the selection
local currentSubcategory = nil 
local currentSubcategoryName = nil
local menuOpenPreviousFrame = false

local function AdjustSelectionRange(tbl, startIndex, endIndex)
    -- Clear current selections
    for itemName, _ in pairs(browserSelectedItemNames) do
        browserSelectedItemNames[itemName] = nil
    end

    -- Set new selections based on range
    for k = startIndex, endIndex do
        local itemName = tbl[k]
        if itemName then
            browserSelectedItemNames[itemName] = true
        end
    end
end

local function DrawFXItems(tbl, main_cat_name)
    local menuOpenThisFrame = false
    for i = 1, #tbl do
        if r.ImGui_BeginMenu(ctx, tbl[i].name) then
            menuOpenThisFrame = true 
            if currentSubcategoryName ~= tbl[i].name then
                -- Subcategory has changed, clear selections and update currentSubcategory
                browserSelectedItemNames = {}
                selectionStartIndex = nil
                selectionEndIndex = nil
                currentSubcategoryName = tbl[i].name
                currentSubcategory = tbl[i]

            end
            
            for j = 1, #tbl[i].fx do
                if tbl[i].fx[j] then
                    local name = tbl[i].fx[j]
                    --if main_cat_name == "ALL PLUGINS" and tbl[i].name ~= "INSTRUMENTS" then
                        -- STRIP PREFIX IN "ALL PLUGINS" CATEGORIES EXCEPT INSTRUMENT WHERE THERE CAN BE MIXED ONES
                        --name = name:gsub("^(%S+:)", "")
                    --elseif main_cat_name == "DEVELOPER" then
                        -- STRIP SUFFIX (DEVELOPER) FROM THESE CATEGORIES
                        --name = name:gsub(' %(' .. Literalize(tbl[i].name) .. '%)', "")
                    --end
                    local isSelected = browserSelectedItemNames[name] == true
		    if useReaperTheme then
                        if isSelected then
                            ImGui.PushStyleColor(ctx, ImGui.Col_Text(), GetReaperThemeColorRGBA("col_vutop")) -- For background
                        end
                    end
                    local flags = r.ImGui_SelectableFlags_None() | r.ImGui_SelectableFlags_DontClosePopups() | r.ImGui_SelectableFlags_AllowItemOverlap()
                    if r.ImGui_Selectable(ctx, name, isSelected, flags) then
                        --! ADD YOUR CODE HERE FOR CLICK ACTION
                        local mods = r.ImGui_GetKeyMods(ctx)
                        if mods == r.ImGui_Mod_Ctrl() then
                            -- Ctrl+click: Toggle selection
                            browserSelectedItemNames[name] = not browserSelectedItemNames[name]
                            selectionStartIndex = j
                            selectionEndIndex = j
                        elseif mods == r.ImGui_Mod_Shift() then
                                            -- Shift+click: Adjust selection range based on the clicked item's position
                            if not selectionStartIndex or not selectionEndIndex then
                                -- If no selection has been made yet, initialize it with the clicked item
                                selectionStartIndex, selectionEndIndex = j, j
                                browserSelectedItemNames[name] = true
                            else
                                -- Determine if the clicked item is inside or outside the current selection range
                                local isInsideSelection = j >= selectionStartIndex and j <= selectionEndIndex

                                if isInsideSelection then
                                    -- Clicked inside the current selection range: Adjust the range to end at the clicked item
                                    -- Determine the closest end of the selection range to the clicked item
                                    local distanceToStart = math.abs(selectionStartIndex - j)
                                    local distanceToEnd = math.abs(selectionEndIndex - j)
                                    if distanceToStart < distanceToEnd then
                                        -- Closer to the start of the selection range: Adjust the end index
                                        selectionEndIndex = j
                                    else
                                        -- Closer to the end of the selection range or equal: Adjust the start index
                                        selectionStartIndex = j
                                    end
                                else
                                    -- Clicked outside the current selection range: Expand the range to include the clicked item
                                    selectionStartIndex = math.min(selectionStartIndex, j)
                                    selectionEndIndex = math.max(selectionEndIndex, j)
                                end
                                -- Update the selection based on the adjusted range
                                AdjustSelectionRange(tbl[i].fx, selectionStartIndex, selectionEndIndex)
                            end
                        else
                            if isSelected then
                                -- Import all selected items
                                for selectedName, _ in pairs(browserSelectedItemNames) do
                                    handleItemAddition(selectedCategoryName, "plugin", selectedName)
                                end
                                browserSelectedItemNames = {} -- Clear selections after import
                            else
                                -- Clicked on an unselected item: Import only this item
                                handleItemAddition(selectedCategoryName, "plugin", name)
                                browserSelectedItemNames = {} -- Clear selections
                                selectionStartIndex, selectionEndIndex = j, j
                            end
                        end
                        LAST_USED_FX = tbl[i].fx[j]
                    end
		    if useReaperTheme then
                        if isSelected then
                            ImGui.PopStyleColor(ctx, 1) -- Pop both the background and text colors if item was selected
                        end
                    end		
                end
            end
            r.ImGui_EndMenu(ctx)
            if r.ImGui_IsItemClicked(ctx, 1) then -- 1 for right-click
                -- Open a popup specific to the right-clicked item
                r.ImGui_OpenPopup(ctx, "subCategoryImportMenu")
            end   
        end   
    end
    -- Right-click context menu for subcategory
    if r.ImGui_BeginPopupContextItem(ctx, "subCategoryImportMenu") then
        if r.ImGui_MenuItem(ctx, "Import All from " .. currentSubcategoryName) then
            --reaper.ShowConsoleMsg("Importing all items from " .. currentSubcategoryName .. "\n")
            --reaper.ShowConsoleMsg("Total items: " .. #currentSubcategory.fx .. "\n")
            -- Import all items from this subcategory
            for j = 1, #currentSubcategory.fx do
                --reaper.ShowConsoleMsg("Importing " .. currentSubcategory.fx[j] .. "\n")
                --queueItemForAddition(currentSubcategoryName, "plugin", currentSubcategory.fx[j])
                handleItemAddition(selectedCategoryName, "plugin", currentSubcategory.fx[j])
            end
            --processItemsToAddQueue()
        end
        
        r.ImGui_EndPopup(ctx)
    end
    
    if menuOpenPreviousFrame and not menuOpenThisFrame then
        browserSelectedItemNames = {} -- Clear selections because the menu has closed
    end
    menuOpenPreviousFrame = menuOpenThisFrame 

    -- Context Menu for category right-click
    if r.ImGui_BeginPopup(ctx, "CategoryImportMenu") then
        if r.ImGui_MenuItem(ctx, "Import All from " .. main_cat_name) then
            for i = 1, #tbl do
                for j = 1, #tbl[i].fx do
                    queueItemForAddition(tbl[i].name, "plugin", tbl[i].fx[j])
                end
            end
            processItemsToAddQueue()
        end
    r.ImGui_EndPopup(ctx)
    end     
end

local function DrawFXList()
    local search = FilterBox()
    if search then return end
    for i, category in ipairs(CAT_TEST) do
        --reaper.ShowConsoleMsg(CAT_TEST[i].name .. "\n")
        if r.ImGui_BeginMenu(ctx, category.name) then

            if r.ImGui_IsItemClicked(ctx, 1) then -- Detect right-click
                -- Determine the appropriate popup ID for the main category
                local mainCategoryPopupId = category.name == "FX CHAINS" and "fxChainImportMenu" or
                                            category.name == "TRACK TEMPLATES" and "trackTemplateImportMenu" or
                                            "CategoryImportMenu" -- Fallback for other categories
                r.ImGui_OpenPopup(ctx, mainCategoryPopupId)
            end

            -- Determine the item type based on the category name
            local itemType = category.name == "FX CHAINS" and "fxChain" or
                             category.name == "TRACK TEMPLATES" and "trackTemplate" or
                             nil -- For other categories, handle accordingly

            if itemType == nil then 
                DrawFXItems(category.list, category.name)
            else
                DrawChainTemplatesItems(category.list, "", itemType)
            end
        r.ImGui_EndMenu(ctx)
        end
    end
end



--[[
    if r.ImGui_Selectable(ctx, "CONTAINER") then
        --! ADD YOUR CODE HERE FOR CLICK ACTION
       
        --r.TrackFX_AddByName(TRACK, "Container", false,
        --    -1000 - r.TrackFX_GetCount(TRACK))
        LAST_USED_FX = "Container"
    end
    if r.ImGui_Selectable(ctx, "VIDEO PROCESSOR") then
        --! ADD YOUR CODE HERE FOR CLICK ACTION
        
        --r.TrackFX_AddByName(TRACK, "Video processor", false,
        --    -1000 - r.TrackFX_GetCount(TRACK))
        LAST_USED_FX = "Video processor"
    end
    --if LAST_USED_FX then
      --  if r.ImGui_Selectable(ctx, "RECENT: " .. LAST_USED_FX) then
            --! ADD YOUR CODE HERE FOR CLICK ACTION
            
            --r.TrackFX_AddByName(TRACK, LAST_USED_FX, false,
            --    -1000 - r.TrackFX_GetCount(TRACK))
        --end
    --end
end
]]
--------------------------------------! SEXAN FX BROWSER

------------------------------load configurations/categories before displaying UI--------------------------------
-- Check operating system
local isWindows = package.config:sub(1,1) == '\\'

-- Create the directory if it doesn't exist
if isWindows then
    
    os.execute('mkdir "' .. screenshotsFolder .. '" >nul 2>nul')
else
    os.execute('mkdir -p "' .. screenshotsFolder .. '"')
end

if fileExists(categoriesItemsData) then
    categories = readDataFromCSV(categoriesItemsData)
    table.sort(categories, function(a, b) return a.index < b.index end)
else
    local file = io.open(categoriesItemsData, "w") -- Create file if it doesn't exist
    file:close()
end

if fileExists(fxBrowserConfigPath) then
    local config = loadConfig(fxBrowserConfigPath)
    font_path = config.font_path or nil
    if font_path ~= nil then
        fontLoadRequested = true
    end
    imageScale = config.imageScale or 0.7
    closeAfterClick = config['closeAfterClick'] == 'true'
    useReaperTheme = config['useReaperTheme'] == 'true'
    openFloatingWindows = config['openFloatingWindows'] == 'true'
    showVST = config['showVST'] == 'true' or true
    showVST3 = config['showVST3'] == 'true' or true
    showCLAP = config['showCLAP'] == 'true' or true
    showJS = config['showJS'] == 'true' or true
else
    local file = io.open(fxBrowserConfigPath, "w") -- Create file if it doesn't exist
    file:close()
end

for _, cat in ipairs(categories) do
    if cat.isDefault then
        selectedCategory = cat
        selectedCategoryName = cat.name
        break -- Found the default category, no need to continue
    end
end
------------------------------------------------------------------------------------------
local function displayUI()
    loadAndAttachFonts() -- Load and attach custom fonts if requested
    local numColorsPushed = 0 -- Reset counter for each frame/used when use Reaper theme
    if useReaperTheme then
            
            ImGui.PushStyleColor(ctx, ImGui.Col_TitleBg(), GetReaperThemeColorRGBA("col_main_bg2"))
            ImGui.PushStyleColor(ctx, ImGui.Col_TitleBgActive(), GetReaperThemeColorRGBA("col_main_bg"))
            ImGui.PushStyleColor(ctx, ImGui.Col_TitleBgCollapsed(), GetReaperThemeColorRGBA("col_transport_editbk"))
        
            ImGui.PushStyleColor(ctx, ImGui.Col_PopupBg(), GetReaperThemeColorRGBA("col_main_bg"))  -- Background of popups, menus, tooltips windows
            
            
            ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg(), GetReaperThemeColorRGBA("col_main_bg2"))  -- Main window background
            ImGui.PushStyleColor(ctx, ImGui.Col_ChildBg(), GetReaperThemeColorRGBA("col_main_bg2"))  -- Child window background

            ImGui.PushStyleColor(ctx, ImGui.Col_Text(), GetReaperThemeColorRGBA("col_toolbar_text"))  -- Main text color
            ImGui.PushStyleColor(ctx, ImGui.Col_TextDisabled(), GetReaperThemeColorRGBA("col_main_text"))

            ImGui.PushStyleColor(ctx, ImGui.Col_Button(), GetReaperThemeColorRGBA("col_buttonbg"))
            ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(), GetReaperThemeColorRGBA("col_toolbar_text_on"))  -- Button hovered
            ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive(), GetReaperThemeColorRGBA("toolbararmed_color"))  -- Button active

            ImGui.PushStyleColor(ctx, ImGui.Col_CheckMark(), GetReaperThemeColorRGBA("col_vutop"))  -- Checkbox marks

            ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg(), GetReaperThemeColorRGBA("col_tl_bg"))  -- Background of checkbox, radio button, plot, slider, text input
            ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered(), GetReaperThemeColorRGBA("col_main_3dhl"))  -- Background of checkbox when hovered
            ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive(), GetReaperThemeColorRGBA("col_main_3dsh"))  -- Background of checkbox when active or clicked
            -- Header (used for CollapsingHeader, TreeNode, etc.)
            ImGui.PushStyleColor(ctx, ImGui.Col_Header(), GetReaperThemeColorRGBA("col_toolbar_frame"))  -- Background of unselected header
            ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered(), GetReaperThemeColorRGBA("toolbararmed_color"))  -- Background of hovered header
            ImGui.PushStyleColor(ctx, ImGui.Col_HeaderActive(), GetReaperThemeColorRGBA("col_toolbar_text_on"))  -- Background of selected (active) header

            ImGui.PushStyleColor(ctx, ImGui.Col_Separator(), GetReaperThemeColorRGBA("io_3dsh"))  -- Separator lines
            ImGui.PushStyleColor(ctx, ImGui.Col_SeparatorHovered(), GetReaperThemeColorRGBA("io_3dhl"))  -- Separator lines when hovered
            ImGui.PushStyleColor(ctx, ImGui.Col_SeparatorActive(), GetReaperThemeColorRGBA("io_text"))  -- Separator lines when active

            ImGui.PushStyleColor(ctx, ImGui.Col_SliderGrab(), GetReaperThemeColorRGBA("col_vutop"))  -- Slider grab
            ImGui.PushStyleColor(ctx, ImGui.Col_SliderGrabActive(), GetReaperThemeColorRGBA("col_toolbar_text_on"))  -- Slider grab active

            ImGui.PushStyleColor(ctx, ImGui.Col_Border(), GetReaperThemeColorRGBA("col_border"))

            numColorsPushed = numColorsPushed + 24
    end  
    
    if not isWindowOpen then return end  -- If the window is closed, stop deferring the display UI function
    local window_flags = ImGui.WindowFlags_NoScrollbar() --ImGui.WindowFlags_None() -- Default window flags  
    local main_viewport = ImGui.GetMainViewport(ctx) -- Get the main viewport
    local work_pos = {ImGui.Viewport_GetWorkPos(main_viewport)} -- Get the work position of the main viewport
    ImGui.SetNextWindowPos(ctx, work_pos[1] + 20, work_pos[2] + 20, ImGui.Cond_FirstUseEver()) -- Set the window position
    ImGui.SetNextWindowSize(ctx, 550, 680, ImGui.Cond_FirstUseEver()) -- Set the window size
    local visible, open = ImGui.Begin(ctx, 'Visual FX Browser', true,window_flags) -- Begin the window
    isWindowOpen = open -- Update the window open state
    if visible then -- If the window is visible
        -- Theme application toggle
        
        
        local windowWidth, windowHeight = ImGui.GetContentRegionAvail(ctx) -- Get the available width and height
        local childHeight = windowHeight - 90 -- to fit in main window
        local rightSectionWidth = windowWidth - leftSectionWidth - padding 
        -------------------------- Slider for controlling image scale
        local sliderChanged
        sliderChanged, imageScale = ImGui.SliderDouble(ctx, "Image Scale", imageScale, minScale, maxScale, "%.2f")
        ImGui.SameLine(ctx)
        --move slider with middlebuttonclick+wheel-------------------------------------------------
        if ImGui.IsMouseDown(ctx, 2) then  -- 2 is the index for the middle mouse button
            local wheelDelta = ImGui.GetMouseWheel(ctx)
            
            if wheelDelta ~= 0 then
                imageScale = imageScale + wheelDelta * 0.05 -- Adjust the multiplier as needed for sensitivity
                imageScale = math.max(minScale, math.min(maxScale, imageScale))
                sliderChanged = true
            end
        end
        ----------------------------Screenshot folder button-----------------------------------------
        ImGui.NewLine(ctx)
        if ImGui.Button(ctx, "OPEN SCREENSHOTS FOLDER") then
            reaper.CF_ShellExecute(screenshotsFolder)  -- Open the screenshots folder
        end
        ImGui.SameLine(ctx)
        
        if r.ImGui_Button(ctx, "RESCAN PLUGIN LIST") then
            FX_LIST_TEST, CAT_TEST = MakeFXFiles()
         end
        ImGui.SameLine(ctx)
        
        _, closeAfterClick = ImGui.Checkbox(ctx, "Close on Entry", closeAfterClick) -- Checkbox to close the window after enter an item
        ImGui.SameLine(ctx)
        if ImGui.Checkbox(ctx, "Use REAPER Theme", useReaperTheme) then             -- checkbox to toggle apply reaper theme
            useReaperTheme = not useReaperTheme
        end
        ImGui.SameLine(ctx)
        
        if ImGui.Checkbox(ctx, "Open Floating Windows", openFloatingWindows) then
            openFloatingWindows = not openFloatingWindows
            
        end

        ImGui.SameLine(ctx)
        
        if ImGui.Button(ctx, "Sort Alphabetically") then
            table.sort(selectedCategory.items, function(a, b) return a.name < b.name end)
            for i, item in ipairs(selectedCategory.items) do
                item.index = i
            end
        end

        _, showVST = ImGui.Checkbox(ctx, "Show VST", showVST)
        ImGui.SameLine(ctx)
        _, showVST3 = ImGui.Checkbox(ctx, "Show VST3", showVST3)
        ImGui.SameLine(ctx)
        _, showJS = ImGui.Checkbox(ctx, "Show JS", showJS)
        ImGui.SameLine(ctx)
        _, showCLAP = ImGui.Checkbox(ctx, "Show CLAP", showCLAP)
        --[[
        if ImGui.Button(ctx, "Sort by item width") then
            table.sort(selectedCategory.items, function(a, b) return a.name < b.name end)
            for i, item in ipairs(selectedCategory.items) do
                item.index = i
            end
        end
        ]]
        
        ImGui.NewLine(ctx)
        --------------------------- Load custom font input-------------------------------------------
        ImGui.SameLine(ctx)
        if ImGui.BeginChildFrame(ctx, '##drop_files', 600, 20) then
            -- Display the path if it's already loaded or if a new file has been dropped
            if font_path ~= nil or #fileDropped > 0 then
                local displayPath = font_path
                if #fileDropped > 0 then
                    displayPath = fileDropped[1] -- Show the newly dropped file path
                end
                ImGui.Text(ctx, displayPath)
                ImGui.SameLine(ctx)
                -- Show the Clear button if there's a path to display
                if ImGui.SmallButton(ctx, 'Clear') then
                    fileDropped = {}
                    font_path = nil -- Clear the font path
                    shouldDetachFonts = true -- Request font detaching
                    fontLoadRequested = false -- Cancel any pending font load request
                end
                -- Show the Load button only if a new file has been dropped
                if #fileDropped > 0 then
                    ImGui.SameLine(ctx)
                    if ImGui.SmallButton(ctx, 'Load') then
                        font_path = fileDropped[1]
                        fontLoadRequested = true
                        fileDropped = {} -- Clear the dropped files list after loading
                    end
                end
            else
                -- Prompt to drag and drop if no font is loaded
                ImGui.Text(ctx, 'Drag and drop a ttf file for custom font or leave it blank to use the default...')
            end
            ImGui.EndChildFrame(ctx)
        end
        if ImGui.BeginDragDropTarget(ctx) then -- Drag and drop target for custom font
            local rv, count = ImGui.AcceptDragDropPayloadFiles(ctx)
            if rv then
                fileDropped = {}
                local filename
                rv, filename = ImGui.GetDragDropPayloadFile(ctx, 0)
                if filename:match("%.ttf$") then -- Check if the file is a TTF
                    font_path = filename:gsub("\\", "/") -- Set the custom font path
                
                else
                    font_path = nil -- Not a TTF, ignore or set to default
                end
                table.insert(fileDropped, filename) -- Store the file path
            end
            ImGui.EndDragDropTarget(ctx)
        end
        ---------------------------------------------------------------------------------------------
       
        ----------------------------- Left section for category selection
        if ImGui.BeginChild(ctx, 'CategoriesChild', leftSectionWidth, childHeight, true) then
            -----------Left window title--------------------------------------
            ImGui.PushFont(ctx, customFontsmall) -- Set the font for the category names
            ImGui.Text(ctx, "Categories") -- Title
            ImGui.PopFont(ctx)
            ImGui.Separator(ctx)
            -------------------------------------------------------------------

            ----------------- Add new category input text box -----------------
            local availableWidth = ImGui.GetContentRegionAvail(ctx) -- Get the available width
            ImGui.PushItemWidth(ctx, availableWidth) -- Set the width for the input text box to match the available width
            _, newCategoryName = ImGui.InputTextWithHint(ctx, "##AddCategory", "Add Category", newCategoryName, 256) -- Input text for adding a new category
            if ImGui.IsKeyPressed(ctx, ImGui.Key_Enter()) and newCategoryName ~= "" then
                -- Check to avoid duplicate categories by name
                local exists = false
                local highestIndex = 0
                for _, category in ipairs(categories) do
                    if category.name == newCategoryName then
                        exists = true
                    break
                    end
                    if category.index > highestIndex then
                        highestIndex = category.index
                    end
                end

                if not exists then
                    local newIndex = #categories + 1
                    -- Add new category with empty plugin list
                    table.insert(categories, {name = newCategoryName, index = highestIndex + 1, isDefault  = false, favorite = false, items = {}})
                    newCategoryName = "" -- Reset input text
                end
            end
            -------------------------------------------------------------------
            ----------categories list------------------------------------------
            
            

            if ImGui.BeginListBox(ctx, '##Categories', -1, -1) then -- Begin the list box for categories
                for i, category in ipairs(categories) do
                    --detect selected category-----------------------------------------------
                    ImGui.PushFont(ctx, customFontsmaller) -- Set the font for the category names
                    -- Check if the current category is the selected one
                    local isSelected = (category.name == selectedCategoryName)
                    -- Call Selectable and pass isSelected as the current state; capture the return to detect clicks
                    local clicked, _ = ImGui.Selectable(ctx, category.name .. "##" .. tostring(i), isSelected)
                    -- If this category was clicked, update the selectedCategoryName to reflect the new selection
                    if clicked then
                        selectedCategory = category
                        selectedCategoryName = category.name
                        selectedCategoryIndex = category.index 
                        selectedCategoryIsDefault = category.isDefault
                        selectedCategoryImagePath = category.categoryImagePath
                    
                        
                    end
                    ImGui.PopFont(ctx)
                    --------------------------------------------------------------
               
                     ------------ Right-click context menu for setting default category
                    if ImGui.BeginPopupContextItem(ctx, category.name) then
                        if ImGui.MenuItem(ctx, "Make Default") then
                            for _, cat in ipairs(categories) do
                                cat.isDefault = false -- Clear default flag on all categories
                            end
                            category.isDefault = true -- Set the selected category as default
                        end
                        if ImGui.MenuItem(ctx, "Delete") then
                            local foundIndex = nil
                            for i, cat in ipairs(categories) do
                                if cat.name == category.name then
                                    foundIndex = i
                                    table.remove(categories, i)
                                    break -- Found the category to be deleted
                                end
                            end
                            if foundIndex then
                                if categories[foundIndex] then
                                    -- Select the next category if available
                                    selectedCategory = categories[foundIndex]
                                    selectedCategoryName = categories[foundIndex].name
                                elseif categories[foundIndex - 1] then
                                    -- Otherwise, select the previous category if the deleted one was the last
                                    selectedCategory = categories[foundIndex - 1]
                                    selectedCategoryName = categories[foundIndex - 1].name
                                else
                                    -- If there are no more categories, reset selection
                                    selectedCategory = nil
                                    selectedCategoryName = nil
                                end
                            end
                        end

                        if ImGui.MenuItem(ctx,"Load category background image") then
                            -- Handle loading category background image for rightClickedItem
                            local imagePath = selectImage()
                            if imagePath then
                                --reaper.ShowConsoleMsg(imagePath)
                                
                                for _, cat in ipairs(categories) do
                                    if cat.name ==  category.name then
                                        
                                        --cat.categoryImagePath = imagePath
                                        imagePath = string.gsub(imagePath, "\\", "/")
                                        cat.categoryImagePath = imagePath
                                        selectedCategoryImagePath =  imagePath
                                        break
                                    end
                                end
                                -- Refresh/load the image as needed here
                            end
                        end
                    ImGui.EndPopup(ctx)
                    end
                    -----------------------------------------------------------------
                end
            ImGui.EndListBox(ctx)
            --local rightClickedOnSelectable = false
            end

            ----------rearranging categories-------------------------------------
            if selectedCategoryName then
                if ImGui.IsKeyPressed(ctx, ImGui.Key_UpArrow()) and ImGui.GetKeyMods(ctx) == ImGui.Mod_Ctrl() then
                    
                    updateSelectedCategoryPosition("up")
                elseif ImGui.IsKeyPressed(ctx, ImGui.Key_DownArrow()) and ImGui.GetKeyMods(ctx) == ImGui.Mod_Ctrl() then
                    updateSelectedCategoryPosition("down")
                end
            end
        ImGui.EndChild(ctx)
        end
        --------------------------------------------------------------------------------------------------
        ImGui.SameLine(ctx)    
        ----------------------------- Right section for displaying images
        if ImGui.BeginChild(ctx, 'ImagesChild', rightSectionWidth, childHeight, true) then

            if isProcessing then
                local progress = currentItemIndex / totalItemsToProcess
                local percentage = progress * 100 -- Calculate percentage
                ImGui.Text(ctx, string.format("Processing: %d/%d (%.2f%%)", currentItemIndex, totalItemsToProcess, percentage))
                ImGui.ProgressBar(ctx, progress, -1, 0, "")
                
                if ImGui.Button(ctx, "Stop") then
                    stopProcessing = true -- Signal to stop processing
                end
            else
                -- Display "Start" or "Continue" based on whether any processing has been done
                if  currentItemIndex > 0 then
                    if ImGui.Button(ctx, "Continue") then
                        if not isProcessing and (totalItemsToProcess == 0 or currentItemIndex < totalItemsToProcess) then
                            -- Set up for processing or continuing processing
                            isProcessing = true
                            stopProcessing = false
                            -- Continue processing from the current index or start anew
                            processItemsToAddQueue()
                        end
                    end
                end
            end

            --------- Search bar for filtering plugins----------------------------------------------------
            if ImGui.BeginChildFrame(ctx, '##drop_files', rightSectionWidth, 20) then
                _, searchQuery = ImGui.InputTextWithHint(ctx, "##SearchPlugins", "Search Bar", searchQuery, 256)
                ImGui.SameLine(ctx)
            --_, searchAllCategories = ImGui.Checkbox(ctx, "Search All", searchAllCategories)
                ImGui.EndChildFrame(ctx)
            end
            -------------------------------------------------------------
            if selectedCategoryName  then
                ------draw background image
                if selectedCategoryImagePath and selectedCategoryImagePath ~= "nil" then 
                    -- Retrieve the current position and size of the child window
                    local childPos = {ImGui.GetWindowPos(ctx)}
                    local childSize = {ImGui.GetWindowSize(ctx)}
                    local backgroundImage = ImGui.CreateImage(selectedCategoryImagePath)
                    local draw_list = ImGui.GetWindowDrawList(ctx)
                    ImGui.DrawList_AddImage(draw_list, backgroundImage, childPos[1], childPos[2], childPos[1] + childSize[1], childPos[2] + childSize[2], 0, 0, 1, 1)
                end
                
                ---------Title of Category window
                local textWidth = ImGui.CalcTextSize(ctx, selectedCategoryName .. " Category") 
                local textX = (rightSectionWidth - textWidth) * 0.5
                ImGui.SetCursorPosX(ctx, textX)
                ImGui.PushFont(ctx, customFont)
                ImGui.Text(ctx, selectedCategoryName )
                ImGui.PopFont(ctx)
                ImGui.Separator(ctx)
                ---------------------------
                if selectedCategory then
                    --sort by item.index
                    table.sort(selectedCategory.items, function(a, b) return a.index < b.index end)
                    local cumulativeWidth = 0
                    for i, item in ipairs(selectedCategory.items) do
                        local prefix = item.name:match("^(%w+):") -- Extract prefix from item name
                        local showItem = false -- Default to not showing
                         -- Decide to show the item based on the prefix and checkbox states
                        if prefix then
                            showItem = (prefix == "VST" and showVST) or
                                    (prefix == "VST3" and showVST3) or
                                    (prefix == "JS" and showJS) or
                                    (prefix == "CLAP" and showCLAP) or
                                    not prefix -- Always show items without these prefixes
                        else
                            -- Always show items without a recognized prefix
                            showItem = true
                        end
                        if (searchQuery == "" or item.name:lower():find(searchQuery:lower()) ) and showItem  then
                            --ImGui.PushID(ctx, item.name)
                            if item.filePath and fileExists(item.filePath) then
                                if not loadedImages[item.filePath] and fileExists(item.filePath) then  -- Ensure the file exists before loading
                                    loadedImages[item.filePath] = ImGui.CreateImage(item.filePath)   
                                end
                                local img = loadedImages[item.filePath]
                                if img and not ImGui.ValidatePtr(img, 'ImGui_Image*') then -- Check if image needs to be reloaded
									--reaper.ShowConsoleMsg(item.filePath)
                                    img = ImGui.CreateImage(item.filePath)
                                    loadedImages[item.filePath] = img -- Store the newly loaded image back in the table
                                end
                                if img then 
                                    local imgWidth, imgHeight = ImGui.Image_GetSize(img) 
                                    local baseScale = maxHeight / imgHeight
                                    local scale = baseScale * imageScale   
                                    imgWidth, imgHeight = imgWidth * scale, imgHeight * scale
                                    if cumulativeWidth + imgWidth + padding > rightSectionWidth - 150 then
                                        ImGui.NewLine(ctx)
                                        cumulativeWidth = 0
                                    end
                                    ImGui.PushID(ctx, i)
                                    local cursorPos = {ImGui.GetCursorScreenPos(ctx)}
                                    if ImGui.ImageButton(ctx, item.name, img, imgWidth, imgHeight, 0, 0, 1, 1, 0xFF0000FF, 0xFFFFFFFF) then
                                    local mods = ImGui.GetKeyMods(ctx)
                                        if mods == ImGui.Mod_Ctrl() then
                                            selectedItems[item.name] = not selectedItems[item.name]
                                        else
                                            local anyItemSelected = false
                                            for _, isSelected in pairs(selectedItems) do
                                                if isSelected then
                                                    anyItemSelected = true
                                                break
                                                end
                                            end
                                            if anyItemSelected then
                                                for selectedItemName, isSelected in pairs(selectedItems) do
                                                    if isSelected then
                                                        local selectedItemType = findItemTypeByName(selectedCategory.items, selectedItemName)
                                                        loadItemIntoTracks(selectedItemName,selectedItemType, false) -- false indicates not to create a new track
                                                    end
                                                end 
                                            else
                                                loadItemIntoTracks(item.name, item.type)
                                            end
                                            if closeAfterClick then
                                                isWindowOpen = false
                                            end
                                        end
                                end

                                    drawRectangleSelected(selectedItems, item, cursorPos , imgWidth, imgHeight)
                                    if ImGui.IsWindowHovered(ctx) and ImGui.IsMouseClicked(ctx, 0) and not ImGui.IsAnyItemHovered(ctx) then
                                        selectedItems = {}    
                                    end
                                    ImGui.PopID(ctx)
                                    dragItemToReaper(selectedItems,item)
                                    rearrangeItems(selectedCategory, selectedItems, item)
                                    keyboardShortcutItems(item, selectedCategory, selectedItems)
                                    cumulativeWidth = cumulativeWidth + imgWidth + padding
                                    if cumulativeWidth + imgWidth <= rightSectionWidth + 150  then
                                        ImGui.SameLine(ctx)
                                    end   
                                end     
                            end
                            --Right click menu of items
                            ImGui.PushID(ctx, i) -- Ensure unique ID for BeginPopupContextItem
                            if ImGui.BeginPopupContextItem(ctx) then
                                local anyItemSelected = false
                                for _, isSelected in pairs(selectedItems) do
                                    if isSelected then
                                        anyItemSelected = true
                                        break
                                    end
                                end
                                --Delete
                                if ImGui.MenuItem(ctx, "Delete                         Del") then
                                    -- Delete action
                                    if anyItemSelected then   
                                        for selectedItemName, isSelected in pairs(selectedItems) do
                    
                                            if isSelected then
                                                -- Delete the selected item from the category
                                                
                                                for i = #selectedCategory.items, 1, -1 do
                                                    if selectedCategory.items[i].name == selectedItemName then
                                                        
                                                        table.remove(selectedCategory.items, i)
                                                        selectedItems[selectedItemName] = nil -- Unselect the item
                                                        break
                                                    end
                                                end
                                            end
                                        end
                                    else
                                        table.remove(selectedCategory.items, i) -- Remove plugin from category
                                    end
                                    loadedImages[item.filePath] = nil
                                end
                                --insert in selected track(s)
                                if ImGui.MenuItem(ctx, "Insert in Selected Track(s)    S") then
                                    if anyItemSelected then
                                        -- Load all selected plugins into current track
                                        for selectedItemName, isSelected in pairs(selectedItems) do
                                            if isSelected then
                                                local selectedItemType = findItemTypeByName(selectedCategory.items, selectedItemName)
                                                loadItemIntoTracks(selectedItemName,selectedItemType, false) -- false to load into current track
                                            end
                                        end
                                    else
                                        -- No plugin selected, load only hovered plugin into current track
                                        loadItemIntoTracks(item.name, item.type, false)
                                    end
                                    if closeAfterClick then
                                        isWindowOpen = false
                                    end
                                end
                                --insert in new track
                                if ImGui.MenuItem(ctx,"Insert in New Track            N") then
                                    if anyItemSelected then
                                        -- Load all selected plugins into a new track
                                        for selectedItemName, isSelected in pairs(selectedItems) do
                                            if isSelected then
                                                local selectedItemType = findItemTypeByName(selectedCategory.items, selectedItemName)
                                                existingTrack = loadItemIntoTracks(selectedItemName,selectedItemType, true, existingTrack) -- Pass existingTrack
                                            end
                                        end
                                    else
                                        -- No plugin selected, load only hovered plugin into a new track
                                        loadItemIntoTracks(item.name, item.type, true)
                                    end
                                    if closeAfterClick then
                                        isWindowOpen = false
                                    end
                                end
                                --load image for item
                                if ImGui.MenuItem(ctx,"Load image") then
                                    -- Handle loading fxChain/Track Template image for rightClickedItem
                                    local imagePath = selectImage()
                                    if imagePath then
                                        -- Assuming rightClickedItem is the item you want to update
                                        item.filePath = imagePath
                                    end
                                end
                            ImGui.EndPopup(ctx)
                            end
                            ImGui.PopID(ctx)
                        ---------------------------------------------------------   
                        end
                    end
                end
                
                if ImGui.IsWindowHovered(ctx) and ImGui.IsMouseReleased(ctx,1) and not ImGui.IsAnyItemActive(ctx) and not ImGui.IsAnyItemHovered(ctx) then
                    ImGui.OpenPopup(ctx, 'FX LIST')
                end    
                if ImGui.BeginPopup(ctx, "FX LIST", r.ImGui_WindowFlags_NoMove()) then  
                    DrawFXList()
                ImGui.EndPopup(ctx)
                end
            end
        ImGui.EndChild(ctx)
        end
        if numColorsPushed > 0 then
            ImGui.PopStyleColor(ctx, numColorsPushed)
        end     
    ImGui.End(ctx)
    end 
    if not isWindowOpen then
        writeDataToCSV(categoriesItemsData, categories) -- Call your function to write to CSV
        local config = {
            font_path = font_path and font_path:gsub("\\", "/") or nil,
            closeAfterClick = closeAfterClick,
            imageScale = imageScale,
            useReaperTheme = useReaperTheme,
            openFloatingWindows = openFloatingWindows,
            showVST = showVST,
            showVST3 = showVST3,
            showJS = showJS,
            showCLAP = showCLAP
        }
        saveConfig(fxBrowserConfigPath, config)
        ImGui.DestroyContext(ctx) -- Clean up the ImGui context
    else
        reaper.defer(displayUI) -- Continue deferring the display UI function if the window is still open
    end
end
  
reaper.defer(displayUI)
