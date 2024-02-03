-- @description Nihilboy Make Visual FX Browser
-- @version 0.0.1
-- @author nihilboy
-- @about
--   # Visual FX Browser Builder nihilboy
--   A UI-script for making a Visual FX Browser.
--   ### Prerequisites
--   ReaImGui, js_ReaScriptAPI
local ImGui = {}
for name, func in pairs(reaper) do
    name = name:match('^ImGui_(.+)$')
    if name then ImGui[name] = func end
end

local ctx = ImGui.CreateContext("Visual FX Browser Builder")
local items = {} -- Stores both categories and FX plugin names
local lastSelectedIndex = nil -- Track the last selected item for shift-selection
local copiedItems = {} -- Global variable to store copied items
local imagePaths = {} -- Store image paths indexed by category
local resource_path = reaper.GetResourcePath():gsub("\\", "/")
local outputPath = resource_path .. "/Scripts/nihilboy-reaper-scripts/Visual-FX-Builder/Visual_FX_Browser.lua" --store path of the generated script
local totalPlugins = #items -- This should be the total count of plugins to process
local processedPlugins = 0 -- This will keep track of how many plugins have been processed
local screenshotsFolder =  resource_path .. "/Scripts/nihilboy-reaper-scripts/Visual-FX-Builder/Visual_FX_Browser_Screenshots/" --store path of the FX screenshots
local categories_plugins_data_file = resource_path .. "/Scripts/nihilboy-reaper-scripts/Visual-FX-Builder/Visual_FX_Browser_data" --store path of the file to store categories and plugins
local font_path = nil
local fileDropped = {} 
local pluginQueue = {}
local isProcessing = false
-----------------------------------------------------------------
-- Function to check if a folder exists and create it if it doesn't
local function ensureFolderExists(folderPath)
    local ok, err, code = os.execute('[ -d "' .. folderPath .. '" ] || mkdir -p "' .. folderPath .. '"')
    if not ok then
        return
    end
end

local function findFilesWindows(screenshotsFolder, pluginName)
    local command = 'dir "' .. screenshotsFolder:gsub("/", "\\") .. '\\*' .. pluginName .. '*.png" /b /s'
    local p = io.popen(command)
    if not p then return nil end

    local files = {}
    for file in p:lines() do
        reaper.ShowConsoleMsg(file .. "\n")
        table.insert(files, file)
    end
    p:close()

    return files
end

--function to wait for GUI to render
local function waitForGUIRendered(pluginName, callback)
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

function table.find(tbl, item)
    for i, value in ipairs(tbl) do
        if value == item then
            return i
        end
    end
    return nil
end

-- Function to check and add a path to imagePaths if it doesn't already exist in the category
local function addPathToCategory(category, path)
    if not imagePaths[category] then
        imagePaths[category] = {}
    end
    -- Check if the path already exists in the category to avoid duplicates
    if not table.find(imagePaths[category], path) then
        table.insert(imagePaths[category], path)
    end
end
--function to take screenshot
local function takeScreenshot(pluginName, folder, category)
   
    local _, Pluginwindow = reaper.JS_Window_ListFind("VST", false) -- Find the plugin window

    for Pluginwindow_addr in string.gmatch(Pluginwindow, '([^,]+)') do -- Loop through the returned addresses
        local window = reaper.JS_Window_HandleFromAddress(Pluginwindow_addr) -- Get the window handle
        local windowFocus = reaper.BR_Win32_SetFocus(window) -- Set focus to the window
        local _, windowList = reaper.JS_Window_ListAllChild(window) -- Get the list of child windows

        local i = 0

        for adr in windowList:gmatch("%w+") do -- Loop through the child windows
            local elm_hwnd = reaper.JS_Window_HandleFromAddress(adr) -- Get the handle of the child window
            local classname = reaper.JS_Window_GetClassName(elm_hwnd) -- Get the class name of the child window

            if classname == "reaperPluginHostWrapProc" or string.find(classname, "Afx:") then -- Check if the class name matches the plugin window
                local srcDC = reaper.JS_GDI_GetWindowDC(elm_hwnd) -- Get the device context of the window
                local retval, left, top, right, bottom = reaper.JS_Window_GetRect(elm_hwnd) -- Get the dimensions of the window

                if retval == true then
                    local w = right - left -- Calculate the width of the window
                    local h = bottom - top -- Calculate the height of the window
                    local destBmp = reaper.JS_LICE_CreateBitmap(true, w, h) -- Create a bitmap to store the screenshot
                    local destDC = reaper.JS_LICE_GetDC(destBmp) -- Get the device context of the bitmap
                    reaper.JS_GDI_StretchBlit(destDC, 0, 0, w, h, srcDC, 0, 0, w, h) -- Copy the window contents to the bitmap

                    local path = folder .. pluginName   .. '.png' -- Construct the file path
                    reaper.JS_LICE_WritePNG(path, destBmp, false) -- Save the bitmap as a PNG file
                    reaper.JS_GDI_ReleaseDC(elm_hwnd, srcDC) -- Release the device context of the window
                    reaper.JS_LICE_DestroyBitmap(destBmp) -- Destroy the bitmap
                        
                    if not imagePaths[category] then -- Add the path to imagePaths
                        imagePaths[category] = {} -- Create a new category if it doesn't exist
                    end
                    table.insert(imagePaths[category], path) -- Add the path to the category

                    return
                end
            end
            i = i + 1
        end
    end
    
end

-- Function to unload the plugin from the track and then delete the track
local function unloadPlugin(track, fxIndex)
    local success = reaper.TrackFX_Delete(track, fxIndex) -- Remove the plugin from the track
    if not success then
        reaper.ShowConsoleMsg("Failed to remove plugin from track\n")
        return false
    end
    -- Delete the track
    --local trackIndex = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
    -- reaper.DeleteTrack(reaper.GetTrack(0, trackIndex))
    return true
end


local trackIndex = reaper.CountTracks(0) -- Add a track index
reaper.InsertTrackAtIndex(trackIndex, true) -- Insert a new track at the end of the track index
local track = reaper.GetTrack(0, trackIndex) -- Get the newly added track

-- Combined function to load a plugin, wait, take a screenshot, and unload
local function loadAndCapturePlugin(pluginName, folder, category, callback)
    local path = screenshotsFolder ..  pluginName  ..  '.png'
    -- Check if the file already exists
    local file = io.open(path, "r")
    if file then  
        file:close()
        addPathToCategory(category, path)
        callback() -- Move to the next plugin if this one is already processed
        
        return
    else
        -- Check all files in the screenshot folder for a match with pluginName
        local pattern = "(.-)_(.+)%.png$"
        local files = findFilesWindows(screenshotsFolder, pluginName)
        for _, file in ipairs(files) do
            local fileCategory, fileName = file:match(pattern)
            reaper.ShowConsoleMsg(file .. "\n")
            if fileName == pluginName  then
                reaper.ShowConsoleMsg(file .. "\n")
                -- Rename file to match the new category
                local newPath = screenshotsFolder .. pluginName .. '.png'
                os.rename(file, newPath)
                addPathToCategory(category, newPath)
                callback() -- Process the next plugin since this one is already handled
                return
            end
        end
        
        -- Load the plugin because it was not found in existing files
        local fxIndex = reaper.TrackFX_AddByName(track, pluginName, false, 1) -- Add the plugin to the track
        if fxIndex == -1 then
            reaper.ShowConsoleMsg("Failed to load plugin: " .. pluginName .. "\n")
            callback() -- Move to the next plugin if loading failed
            return
        end
        reaper.TrackFX_Show(track, fxIndex, 3) -- Show the plugin window

        -- Wait for the GUI to render, then take a screenshot and unload
        waitForGUIRendered(pluginName, function() 
            takeScreenshot(pluginName, folder, category) 
            unloadPlugin(track, fxIndex) 
            callback() -- Process the next plugin in the queue
        end)
    end
end


local function addItem(type, name)
    if type == "Category" then
        -- Directly add a category
        table.insert(items, {type = type, name = "", indent = 0, selected = false})
    elseif type == "FX Plugin Name" then
        -- Check if there's at least one category in the items
        local categoryExists = false
        for _, item in ipairs(items) do
            if item.type == "Category" then
                categoryExists = true
                break
            end
        end
        -- Only add an FX Plugin Name if there's at least one category
        if categoryExists then
            table.insert(items, {type = type, name = "", indent = 1, selected = false})
        else
            reaper.ShowMessageBox("Please add a Category before adding an FX Plugin Name.", "Error", 0)
        end
    end
end

-- Function to generate and save the script
local function generateAndSaveScript(outputPath)

    local categoriesList = {}
    for category, _ in pairs(imagePaths) do 
        table.insert(categoriesList, category)  
    end
 
    --the script to be generated
    local scriptContent = [[
-- Generated Visual FX Browser Script
local ImGui = {}
for name, func in pairs(reaper) do
  name = name:match('^ImGui_(.+)$')
  if name then ImGui[name] = func end
end

local ctx
ctx = ImGui.CreateContext('Visual FX Browser')
]]
-- Add categories
scriptContent = scriptContent .. "local categories = { \"" .. table.concat(categoriesList, "\", \"") .. "\" }\n"
scriptContent = scriptContent .. "local images = {\n"

for category, paths in pairs(imagePaths) do
    --scriptContent = scriptContent ..  string.format("%q", category) .. " = {\n"
    scriptContent = scriptContent .. "  " .. category .. " = {\n"
    for _, path in ipairs(paths) do
        scriptContent = scriptContent .. "    \"" .. path .. "\",\n"
    end
    scriptContent = scriptContent .. "  },\n"
end

scriptContent = scriptContent .. "}\n\n"

if font_path then
    scriptContent = scriptContent .. "local font_path = \"" .. font_path .. "\"\n"
else
    scriptContent = scriptContent .. "local font_path = nil\n"
end
scriptContent = scriptContent .. [[
-- To keep track of loaded ImGui image objects, indexed by category
local loadedImages = {}
local selectedCategory = nil

-- Function to load a plugin FX by name into the selected track(s)
local function loadPluginFXIntoSelectedTracks(pluginName)
    local trackCount = reaper.CountSelectedTracks(0)
    for i = 0, trackCount - 1 do
        local track = reaper.GetSelectedTrack(0, i)
        -- This might need adjustment based on the actual plugin naming and identification
        reaper.TrackFX_AddByName(track, pluginName, false, -1)
    end
end

local imageScale = 0.3 -- Initial scaling factor
local minScale = 0.1 -- Minimum scale
local maxScale = 2.0 -- Maximum scale
local customFont = nil
local customFontsmall = nil
local customFontsmaller = nil

if font_path then
     customFont = ImGui.CreateFont(font_path, 25)
    ImGui.Attach(ctx, customFont)
     customFontsmall = ImGui.CreateFont(font_path, 17)
    ImGui.Attach(ctx, customFontsmall)
    customFontsmaller = ImGui.CreateFont(font_path, 16)
    ImGui.Attach(ctx, customFontsmaller)
	
end

local function displayUI()
    local window_flags = ImGui.WindowFlags_None()
    local main_viewport = ImGui.GetMainViewport(ctx)
    local work_pos = {ImGui.Viewport_GetWorkPos(main_viewport)}
    ImGui.SetNextWindowPos(ctx, work_pos[1] + 20, work_pos[2] + 20, ImGui.Cond_FirstUseEver())
    ImGui.SetNextWindowSize(ctx, 550, 680, ImGui.Cond_FirstUseEver())
   
  
    local visible, open = ImGui.Begin(ctx, 'Visual FX Browser', true,window_flags)
    if visible then
        local windowWidth, windowHeight = ImGui.GetContentRegionAvail(ctx)
        local leftSectionWidth = 200
        local padding = 5
        local rightSectionWidth = windowWidth - leftSectionWidth - padding

        -- Slider for controlling image scale
        local sliderChanged
        sliderChanged, imageScale = ImGui.SliderDouble(ctx, "Image Scale", imageScale, minScale, maxScale, "%.2f")
  
        -- Left section for category selection
        if ImGui.BeginChild(ctx, 'CategoriesChild', leftSectionWidth, windowHeight, true) then
            ImGui.PushFont(ctx, customFontsmall)
            ImGui.Text(ctx, "Plugin Categories")
            ImGui.PopFont(ctx)
          ImGui.Separator(ctx)
          if ImGui.BeginListBox(ctx, '##Categories', -1, -1) then
              for _, category in ipairs(categories) do
                ImGui.PushFont(ctx, customFontsmaller)
                  if ImGui.Selectable(ctx, category, selectedCategory == category) then
                      selectedCategory = category
                      -- Clear previously loaded images if category changed
                      loadedImages = {}
                  end
                  ImGui.PopFont(ctx)
              end
              ImGui.EndListBox(ctx)
          end
        end
        ImGui.EndChild(ctx)
        
        ImGui.SameLine(ctx)
        
        -- Right section for displaying images
        if ImGui.BeginChild(ctx, 'ImagesChild', rightSectionWidth, windowHeight, true) then
            if selectedCategory then
                local textWidth = ImGui.CalcTextSize(ctx, selectedCategory .. " Category")
                local textX = (rightSectionWidth - textWidth) * 0.5
                ImGui.SetCursorPosX(ctx, textX)
                ImGui.PushFont(ctx, customFont)
                ImGui.Text(ctx, selectedCategory )
                ImGui.PopFont(ctx)
                ImGui.Separator(ctx)
                local cumulativeWidth = 0
                local maxHeight = 150 -- Adjust as needed
  
                for index, imagePath in ipairs(images[selectedCategory]) do
                    if not loadedImages[imagePath] then
                        loadedImages[imagePath] = ImGui.CreateImage(imagePath)
                    end
                    local img = loadedImages[imagePath]
                    if img then
                        local imgWidth, imgHeight = ImGui.Image_GetSize(img)
                        local scale = math.min(maxHeight / imgHeight, 1)
                        local scale = imageScale
                        imgWidth, imgHeight = imgWidth * scale, imgHeight * scale
                        local pluginName = imagePath:match("([^/]+)%.png$")
                        if cumulativeWidth + imgWidth + padding > rightSectionWidth then
                            ImGui.NewLine(ctx)
                            cumulativeWidth = 0
                        end
                        local str_id = "image" .. tostring(index)
                        if ImGui.ImageButton(ctx, str_id, img, imgWidth, imgHeight, 0, 0, 1, 1, 0xFF0000FF, 0xFFFFFFFF) then  
                            if pluginName then
                                loadPluginFXIntoSelectedTracks(pluginName)
                            end
                        end
                        if ImGui.IsItemHovered(ctx) then
                            ImGui.BeginTooltip(ctx)
                            ImGui.Text(ctx, pluginName)
                            ImGui.EndTooltip(ctx)
                        end
                        cumulativeWidth = cumulativeWidth + imgWidth + padding
                        if cumulativeWidth + imgWidth <= rightSectionWidth then
                            ImGui.SameLine(ctx)
                        end
                    end
                end
            end
        end
        ImGui.EndChild(ctx)
        
        ImGui.End(ctx)
    end
    if open then
        reaper.defer(displayUI)
    else
        ImGui.DestroyContext(ctx)
    end
  end
  
  reaper.defer(displayUI)
]]

-- Save to file
local file = io.open(outputPath, "w")
if file then
    file:write(scriptContent)
    file:close()
    print("Script generated and saved to: " .. outputPath)
else
    print("Error saving script to: " .. outputPath)
end
local scriptIsAdded = reaper.AddRemoveReaScript(true, 0, outputPath, true)
end

-- Process the next plugin in the queue
local function processNextPlugin()
    if #pluginQueue == 0 then
        isProcessing = false
        generateAndSaveScript(outputPath) -- Call this once all plugins are processed
        return -- No more plugins to process
    end

    local nextPlugin = table.remove(pluginQueue, 1) -- Get the first plugin from the queue
    loadAndCapturePlugin(nextPlugin.name, screenshotsFolder, nextPlugin.category, processNextPlugin)
end

-- Helper function to check if table contains value
function tableContains(table, element)
    for _, value in pairs(table) do
        if value == element then
            return true
        end
    end
    return false
end


function determineScreenshotPath(category, pluginName)
    -- Your logic to determine the screenshot path
    local path = screenshotsFolder .. pluginName .. ".png"
    return path
end

local function processFXPlugins() 
    ensureFolderExists(screenshotsFolder) -- Make sure the folder exists

    -- Reset imagePaths for fresh start
    imagePaths = {}

    -- Reset or initialize the plugin queue
    pluginQueue = {}
    local currentCategory = "Uncategorized"

    -- Prepare categoriesList and images tables based on current UI state
    local categoriesList = {}
    local images = {}

    for _, item in ipairs(items) do
        if item.type == "Category" then
            currentCategory = item.name
            if not categoriesList[currentCategory] then
                categoriesList[currentCategory] = true -- Mark as processed
                images[currentCategory] = {} -- Initialize
            end
        elseif item.type == "FX Plugin Name" and item.name ~= "" then
            local screenshotPath = determineScreenshotPath(currentCategory, item.name)
            if not tableContains(images[currentCategory], screenshotPath) then
                images[currentCategory][screenshotPath] = true -- Mark as added
                -- Enqueue processing if necessary
                table.insert(pluginQueue, {name = item.name, category = currentCategory})
            end
        end
    end

    if #pluginQueue > 0 and not isProcessing then
        isProcessing = true
        processNextPlugin() -- Start processing
    else
        generateAndSaveScript(outputPath, categoriesList, images)
    end
end


local function writeCategoriesAndPlugins(dataPath, items)
    local file, err = io.open(dataPath, "w")
    if not file then
        reaper.ShowMessageBox("Failed to open file for writing: " .. err, "Error", 0)
        return
    end

    local currentCategory = ""
    for _, item in ipairs(items) do
        if not item or not item.type or not item.name then
            reaper.ShowConsoleMsg("Encountered an item with missing properties: " .. tostring(item) .. "\n")
        else
            if item.type == "Category" then
                currentCategory = item.name -- Update the current category
            elseif item.type == "FX Plugin Name" and currentCategory ~= "" then
                file:write(currentCategory .. " - " .. item.name .. "\n") -- Write the current category and plugin name
            end
        end
    end

    file:close()
end

function loadCategoriesAndPluginsFromFile(filePath)
    local file, err = io.open(filePath, "r")
    if not file then
        reaper.ShowMessageBox("Could not open file for reading: " .. err, "Error", 0)
        return
    end

    local currentCategory = ""
    local items = {}
    
    for line in file:lines() do
        local category, pluginName = line:match("^(.-)%s*-%s*(.*)$")
        if category and pluginName then
            if category ~= currentCategory then
                -- Add new category with indent 0
                table.insert(items, {type = "Category", name = category, indent = 0})
                currentCategory = category
            end
            -- Add plugin name under current category with indent 1
            table.insert(items, {type = "FX Plugin Name", name = pluginName, indent = 1})
        end
    end

    file:close()
    return items
end


--------------------------buttons------------------------------
local function handleSelection(index, item)
    local ctrlHeld = ImGui.IsKeyDown(ctx, ImGui.Mod_Ctrl()) -- Check if Ctrl is held
    local shiftHeld = ImGui.IsKeyDown(ctx, ImGui.Mod_Shift()) -- Check if Shift is held
    
    if ctrlHeld then
        -- Toggle selection state without affecting others
        item.selected = not item.selected
        lastSelectedIndex = index
    elseif shiftHeld and lastSelectedIndex then
        -- Select all items between the last selected and the current one
        local startIdx = math.min(lastSelectedIndex, index)
        local endIdx = math.max(lastSelectedIndex, index)
        for i = startIdx, endIdx do
            items[i].selected = true
        end
    else
        -- Standard selection: deselect all others
        for i, v in ipairs(items) do
            v.selected = false
        end
        item.selected = true
        lastSelectedIndex = index
    end
end

-- Function to deep copy an item
local function deepcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[deepcopy(orig_key)] = deepcopy(orig_value)
        end
        setmetatable(copy, deepcopy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

-- Helper function to convert RGBA to ImGui color
local function rgba(r, g, b, a)
    a = a or 255
    return ((r << 24) | (g << 16) | (b << 8) | a) & 0xFFFFFFFF
end

-- Function to create styled buttons
local function createStyledButton(ctx, label, buttonWidth, buttonHeight, bgColor, hoverColor, activeColor, textColor)
    ImGui.PushStyleColor(ctx, ImGui.Col_Button(), bgColor)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(), hoverColor)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive(), activeColor)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text(), textColor)
    local buttonPressed = ImGui.Button(ctx, label, buttonWidth, buttonHeight)
    ImGui.PopStyleColor(ctx,4)
    return buttonPressed
end

-- Function to delete selected items
local function deleteUnselectedItems()
    local updatedItems = {}
    for i, item in ipairs(items) do
        if not item.selected then 
            table.insert(updatedItems, item)
        end
    end
    items = updatedItems
end

-- Function to move selected items up
local function moveItemsUp()
    for i = 2, #items do -- Start from the second item
        if items[i].selected and not items[i-1].selected then
            -- Swap items
            items[i], items[i-1] = items[i-1], items[i]
            break -- Break after moving to prevent multiple moves
        end
    end
end

-- Function to move selected items down
local function moveItemsDown()
    for i = #items-1, 1, -1 do -- Start from the second last item
        if items[i].selected and not items[i+1].selected then
            -- Swap items
            items[i], items[i+1] = items[i+1], items[i]
            break -- Break after moving to prevent multiple moves
        end
    end
end

    
    -- Check and create the screenshots folder if it doesn't exist
    if not reaper.file_exists(screenshotsFolder) then
        -- Attempt to create the folder; adjust the command for your OS if necessary
        os.execute('mkdir "' .. screenshotsFolder:gsub('/', '\\') .. '"')
    end

    -- Check and create the data file if it doesn't exist
    local file = io.open(categories_plugins_data_file, "r")
    if not file then
        -- File doesn't exist, so create it
        file = io.open(categories_plugins_data_file, "w")
        file:close() -- Close the file after creating it
    else
        -- File exists, just close it
        file:close()
    end
   
    
---------------------- Main UI display functions
local function displayUI()
    
    

    local window_flags = ImGui.WindowFlags_None() -- Set window flags
    ImGui.SetNextWindowPos(ctx, 20, 20, ImGui.Cond_FirstUseEver()) -- Set window position
    ImGui.SetNextWindowSize(ctx, 550, 680, ImGui.Cond_FirstUseEver()) -- Set window size
    local buttonWidth = 180 
    local visible, open = ImGui.Begin(ctx, 'Visual FX Browser Builder', true)
    if visible then
        -- Buttons for adding category and FX name
        ImGui.SameLine(ctx)
        if createStyledButton(ctx, "Add Category", buttonWidth, 20, rgba(153, 0, 204), rgba(153, 102, 204), rgba(153, 153, 204), rgba(255, 255, 255)) then
           addItem("Category")
        end
        ImGui.SameLine(ctx)
        if createStyledButton(ctx, "Add FX Name", buttonWidth, 20, rgba(153, 0, 204), rgba(153, 102, 204), rgba(153, 153, 204), rgba(255, 255, 255)) then
            addItem("FX Plugin Name")
        end

        ImGui.NewLine(ctx)

        -- Buttons for "Clear All" and "Remove Last"
        for _, name in ipairs({ 'Clear All', 'Remove Last' }) do
            ImGui.SameLine(ctx)
            if createStyledButton(ctx, name, buttonWidth, 20, rgba(204, 0, 51), rgba(204, 102, 51), rgba(204, 153, 51), rgba(255, 255, 255)) then
                if name == "Clear All" then
                    items = {}
                elseif name == "Remove Last" then
                    if #items > 0 then
                        table.remove(items)
                    end
                end
            end
        end

        -- Delete button
        ImGui.SameLine(ctx)
        if createStyledButton(ctx, "Delete", buttonWidth, 20, rgba(204, 0, 51), rgba(204, 102, 51), rgba(204, 153, 51), rgba(255, 255, 255)) then
            deleteUnselectedItems() -- Call the function to delete unselected items
        end

        -- Copy and Paste buttons
        ImGui.NewLine(ctx)
        ImGui.SameLine(ctx)
        if createStyledButton(ctx, "Copy", buttonWidth, 20, rgba(0, 145, 228), rgba(92, 205, 255), rgba(0, 72, 167), rgba(255, 255, 255)) then
            copiedItems = {}
            for i, item in ipairs(items) do
                if item.selected then
                    table.insert(copiedItems, deepcopy(item))
                end
            end
        end

        ImGui.SameLine(ctx)
        if createStyledButton(ctx, "Paste", buttonWidth, 20, rgba(0, 145, 228), rgba(92, 205, 255), rgba(0, 72, 167), rgba(255, 255, 255)) then
            for _, item in ipairs(copiedItems) do
                table.insert(items, deepcopy(item))
            end
        end

        -- "Up" and "Down" buttons
        ImGui.NewLine(ctx)
        ImGui.SameLine(ctx)
        if createStyledButton(ctx, "Up", buttonWidth, 20, rgba(51, 153, 0), rgba(51, 204, 0), rgba(51, 102, 0), rgba(255, 255, 255)) then
            moveItemsUp()
        end
    
        ImGui.SameLine(ctx)
        if createStyledButton(ctx, "Down", buttonWidth, 20, rgba(51, 153, 0), rgba(51, 204, 0), rgba(51, 102, 0), rgba(255, 255, 255)) then
            moveItemsDown()
        end

        -- "Build Visual FX Browser" button
        ImGui.NewLine(ctx)
        ImGui.SameLine(ctx)
        if createStyledButton(ctx, "Build Visual FX Browser", buttonWidth, 20, rgba(255,141,0), rgba(255,167,0), rgba(255,116,0), rgba(255, 255, 255)) then
            writeCategoriesAndPlugins(categories_plugins_data_file,items)
            processFXPlugins()
            generateAndSaveScript(outputPath)
            
           
            

        end

        
-- Place this right after the "Build Visual FX Browser" button functionality
ImGui.NewLine(ctx)
local windowWidth = ImGui.GetContentRegionAvail(ctx)
ImGui.SameLine(ctx, (windowWidth - 600) * 0.5)
if ImGui.BeginChildFrame(ctx, '##drop_files', 600, 20) then
    if #fileDropped == 0 then
        ImGui.Text(ctx, 'Drag and drop a ttf file for custom font or leave it blank to use the default...')
    else
        ImGui.Text(ctx, fileDropped[1])
        
         ImGui.SameLine(ctx)
         if ImGui.SmallButton(ctx, 'Clear') then
             fileDropped = {}
         end
    end
    ImGui.EndChildFrame(ctx)
end
if ImGui.BeginDragDropTarget(ctx) then
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
        table.insert(fileDropped, filename)
    end
    ImGui.EndDragDropTarget(ctx)
end




        -- Table for displaying categories and FX names
        if ImGui.BeginChild(ctx, 'ChildR', 0, 560, true, window_flags) then -- Begin child window
            if ImGui.BeginTable(ctx, "categoriesTable", 2, ImGui.TableFlags_Resizable()) then -- Begin table
                ImGui.TableSetupColumn(ctx,"Type", ImGui.TableColumnFlags_WidthFixed(), 150) -- Set up columns
                ImGui.TableSetupColumn(ctx,"Name", ImGui.TableColumnFlags_WidthStretch())
                --ImGui.TableHeadersRow(ctx) 
                for i, item in ipairs(items) do
                    ImGui.TableNextRow(ctx)
                    ImGui.TableNextColumn(ctx)
                    local label = string.rep(" ", item.indent * 2) .. item.type -- Adjust indentation
                    if ImGui.Selectable(ctx, label .. "##" .. i, item.selected ) then
                        handleSelection(i, item)
                    end 
                    ImGui.TableNextColumn(ctx)
                    _, item.name = ImGui.InputText(ctx, "##" .. i, item.name)
                end
            ImGui.EndTable(ctx)
            end
        ImGui.EndChild(ctx)
        end
    end
    ImGui.End(ctx)
    
    if open then
        reaper.defer(displayUI)  -- Ensure the context remains open
    else
        ImGui.DestroyContext(ctx) -- Destroy the context when the window is closed
    end
end

local function initializeUI()
    -- Load items from file
    items = loadCategoriesAndPluginsFromFile(categories_plugins_data_file)

    -- Then defer displayUI, which now uses the freshly loaded 'items'
    reaper.defer(displayUI)
end

initializeUI()
--reaper.defer(displayUI) -- Call the displayUI function
