-- AseGit, a Version Control Script for Aseprite.

local spr = app.activeSprite
if not spr then
    app.alert("Please open a sprite first.")
    return
end

if not spr.filename or spr.filename == "" then
    app.alert("Please save your file at least once.")
    return
end

local fs = app.fs
local json = json or app.json
if not json then
    app.alert("JSON API not found, you may be using an old Aseprite version.")
    return
end

do
    local seed = os.time() + math.floor((os.clock() % 1) * 1000000)
    math.randomseed(seed)
end

-- Directory Helper
local function safeMakeDirectory(path)
    if fs.isDirectory(path) then
        return true
    end
    pcall(function() fs.makeDirectory(path) end)
    if not fs.isDirectory(path) then
        app.alert(string.format("AseGit: failed to create directory:\n%s\nPlease check permissions.", path))
        return false
    end
    return true
end

local spritePath = spr.filename
local parentDir = fs.filePath(spritePath)
local spriteName = fs.fileName(spritePath)
local safeTitle = fs.fileTitle(spriteName)


local mainRepoDir = fs.joinPath(parentDir, ".asegit")
local repoDir = fs.joinPath(mainRepoDir, safeTitle .. "_data")

local logFile = fs.joinPath(repoDir, "asegit_log.json")
local settingsFile = fs.joinPath(repoDir, "settings.json") 

local sessionStart = os.time()
local sessionEdits = 0

local historicalTime = 0
local historicalEdits = 0

local diffDlg = nil
local logDlg = nil
local mainDlg = nil
local timerObj = nil
local listenerObj = nil
local autoCommitTimer = nil

local settings = {}

if not safeMakeDirectory(mainRepoDir) then return end
if not safeMakeDirectory(repoDir) then return end

-- Helper Functions
local function getDefaultSettings()
    return {
        show_stats = true,
        show_commit = true,
        show_history = true,
        auto_commit_enabled = false,
        auto_commit_interval = 600,
        show_tag_entry = true,
        show_message_entry = true,
        show_diff_button = true,
        show_load_button = true,
        show_ref_button = true,
        show_log_button = true,
    }
end

local function loadSettings()
    local defaults = getDefaultSettings()
    
    if not fs.isFile(settingsFile) then
        return defaults
    end
    
    local file = io.open(settingsFile, "r")
    if not file then
        return defaults
    end
    
    local content = file:read("*all")
    file:close()
    
    local loaded = json.decode(content) or {}
    
    -- Merge loaded settings with defaults
    for key, defaultValue in pairs(defaults) do
        if loaded[key] == nil then
            loaded[key] = defaultValue
        end
    end
    
    return loaded
end

local function saveSettings(data)
    local file = io.open(settingsFile, "w")
    if not file then
        app.alert("AseGit: could not write settings file. Check permissions: " .. settingsFile)
        return false
    end
    file:write(json.encode(data))
    file:close()
    return true
end

settings = loadSettings()

local function loadLog()
    local log = {}
    if fs.isFile(logFile) then
        local file = io.open(logFile, "r")
        if file then
            local content = file:read("*all")
            file:close()
            if content and content ~= "" then
                log = json.decode(content) or {}
            end
        end
    end
    
    for i, entry in ipairs(log) do
        if not entry.short_id then
            entry.short_id = string.format("%06x", i)
        end
    end
    
    return log
end

local function saveLog(data)
    local file = io.open(logFile, "w")
    if not file then
        app.alert("AseGit: could not write log file. Check permissions: " .. logFile)
        return false
    end
    file:write(json.encode(data))
    file:close()
    return true
end

local function formatTime(seconds)
    if not seconds then
        return "00:00:00"
    end
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = seconds % 60
    return string.format("%02d:%02d:%02d", h, m, s)
end

local function recalcTotals()
    local log = loadLog()
    historicalTime = 0
    historicalEdits = 0
    for _, entry in ipairs(log) do
        historicalTime = historicalTime + (entry.session_time or 0)
        historicalEdits = historicalEdits + (entry.edits or 0)
    end
end

recalcTotals()

-- Data Handling
local historyLabels = {}
local historyData = {}

local function fetchHistoryData()
    local log = loadLog()
    local labels = {}
    local data = {}
    local maxRecent = 10
    local count = 0
    
    for i = #log, 1, -1 do
        if count >= maxRecent then
            break
        end
        
        local entry = log[i]
        
        local shortIdDisplay = entry.short_id and string.sub(entry.short_id, 1, 6) or ""
        local dateStr = os.date("%H:%M:%S | %d-%m-%Y", entry.timestamp)
        local tagDisplay = ""
        if entry.tag and entry.tag ~= "" then
            tagDisplay = string.format("[%s] ", entry.tag)
        end
        
        local label = string.format("%s%s (#%s | %s)", tagDisplay, entry.message, shortIdDisplay, dateStr)
        table.insert(labels, label)
        table.insert(data, entry)
        count = count + 1
    end
    return labels, data
end

historyLabels, historyData = fetchHistoryData()

local function updateHistoryUI()
    historyLabels, historyData = fetchHistoryData()
    if not mainDlg or not mainDlg.bounds then
        return
    end
    mainDlg:modify{ id="history_list", options=historyLabels }
    if #historyLabels > 0 then
        mainDlg:modify{ id="history_list", option=historyLabels[1] }
    end
end

-- Settings UI Helper
local function updateSettingsDisplay()
    if not mainDlg or not mainDlg.bounds then
        return
    end
    
    local showStats = settings.show_stats
    mainDlg:modify{ id="sep_stats", visible=showStats }
    mainDlg:modify{ id="stat_session", visible=showStats }
    mainDlg:modify{ id="stat_total", visible=showStats }

    local showCommit = settings.show_commit
    mainDlg:modify{ id="sep_commit", visible=showCommit }
    mainDlg:modify{ id="tag_entry", visible=showCommit and settings.show_tag_entry }
    mainDlg:modify{ id="message", visible=showCommit and settings.show_message_entry }
    mainDlg:modify{ id="btn_commit", visible=showCommit }

    local showHistory = settings.show_history
    mainDlg:modify{ id="sep_hist", visible=showHistory }
    mainDlg:modify{ id="history_list", visible=showHistory }
    mainDlg:modify{ id="btn_diff", visible=showHistory and settings.show_diff_button }
    mainDlg:modify{ id="btn_load", visible=showHistory and settings.show_load_button }
    mainDlg:modify{ id="btn_ref", visible=showHistory and settings.show_ref_button }
    mainDlg:modify{ id="btn_log", visible=showHistory and settings.show_log_button }
    
    mainDlg:show{ wait=false }
end

local function addMinimizeButton(dlg, widgetIds, keepVisibleIds)
    local isCollapsed = false
    dlg:button{
        text="➖",
        onclick=function()
            isCollapsed = not isCollapsed
            local label = isCollapsed and "➕" or "➖"
            dlg:modify{ id="min_btn", text=label }
            
            if isCollapsed then
                local keep = {}
                if keepVisibleIds then
                    for _, kid in ipairs(keepVisibleIds) do keep[kid] = true end
                end
                for _, id in ipairs(widgetIds) do
                    if keep[id] then
                        dlg:modify{ id=id, visible=true }
                    else
                        dlg:modify{ id=id, visible=false }
                    end
                end
            else
                for _, id in ipairs(widgetIds) do
                    dlg:modify{ id=id, visible=true }
                end
                updateSettingsDisplay()
            end
            
            if dlg.bounds then
                dlg:repaint()
            end
        end,
        id="min_btn"
    }
end

-- Settings & Commit Logic
local function generateRandomId(length)
    local chars = "abcdefghijklmnopqrstuvwxyz0123456789"
    local randomId = ""
    for i = 1, length do
        local rand = math.random(#chars)
        randomId = randomId .. chars:sub(rand, rand)
    end
    return randomId
end

local function performCommitInternal(message, tagOverride)
    local msg = message
    local tag = tagOverride
    
    if msg == "" then
        msg = string.format("Session commit")
    end

    local log = loadLog()
    local randomId = generateRandomId(6)
    local timestamp = os.time()
    
    local snapName = string.format("%s_%s.aseprite", safeTitle, randomId)
    local snapPath = fs.joinPath(repoDir, snapName)
    
        if spr and spr.filename then
            pcall(function() spr:saveCopyAs(snapPath) end)
        else
            pcall(function() app.activeSprite:saveCopyAs(snapPath) end)
        end
        if not fs.isFile(snapPath) then
            app.alert("AseGit: failed to save snapshot. Check disk space and permissions:\n" .. snapPath)
            return
        end

    table.insert(log, {
        id = timestamp,
        short_id = randomId,
        timestamp = timestamp,
        tag = tag,
        message = msg,
        filename = snapName,
        edits = sessionEdits,
        session_time = (os.time() - sessionStart)
    })
        if not saveLog(log) then
            app.alert("AseGit: snapshot saved but log file could not be updated. Check permissions: " .. logFile)
        end

    sessionEdits = 0
    sessionStart = os.time()
    recalcTotals()
    
    updateHistoryUI()
end

local function performManualCommit()
    local msg = mainDlg.data.message
    local tag = mainDlg.data.tag_entry
    performCommitInternal(msg, tag)
    mainDlg:modify{ id="message", text="" }
    mainDlg:modify{ id="tag_entry", text="" }
end

local function performAutoCommit()
    if sessionEdits == 0 then
        return
    end
    local msg = string.format("Auto commit")
    performCommitInternal(msg, "AUTO")
end

local function startAutoCommitTimer()
    if autoCommitTimer then
        autoCommitTimer:stop()
    end
    
    local interval = settings.auto_commit_interval or 600
    autoCommitTimer = Timer{
        interval=interval,
        ontick=function()
            if settings.auto_commit_enabled and sessionEdits > 0 then
                performAutoCommit()
            end
        end
    }
    
    if settings.auto_commit_enabled then
        autoCommitTimer:start()
    end
end

local function showSettingsUI()
    local settingsDlg = Dialog{ title="AseGit Settings" }
    local currentInterval = tostring(settings.auto_commit_interval or 600)

    settingsDlg:separator{ text="Section Visibility" }
    settingsDlg:check{ id="show_stats", text="Show Statistics Section", selected=settings.show_stats }
    settingsDlg:check{ id="show_commit", text="Show Commit Section", selected=settings.show_commit }
    settingsDlg:check{ id="show_history", text="Show History Section", selected=settings.show_history }
    settingsDlg:newrow()
    
    settingsDlg:separator{ text="Individual Visibility" }
    settingsDlg:check{ id="show_tag_entry", text="Show Tag Entry", selected=settings.show_tag_entry }
    settingsDlg:check{ id="show_message_entry", text="Show Message Entry", selected=settings.show_message_entry }
    settingsDlg:check{ id="show_diff_button", text="Show Visual Diff Button", selected=settings.show_diff_button }
    settingsDlg:newrow()
    
    settingsDlg:check{ id="show_load_button", text="Show Load File Button", selected=settings.show_load_button }
    settingsDlg:check{ id="show_ref_button", text="Show Add as Ref Button", selected=settings.show_ref_button }
    settingsDlg:check{ id="show_log_button", text="Show Full History Button", selected=settings.show_log_button }
    settingsDlg:newrow()
    
    settingsDlg:separator{ text="Auto Commit" }
    settingsDlg:check{ id="auto_commit_enabled", text="Enable Auto Commit", selected=settings.auto_commit_enabled }
    settingsDlg:newrow()
    settingsDlg:label{ text="Interval (seconds):" }
    settingsDlg:entry{ id="auto_commit_interval", text=currentInterval, width=80 }
    settingsDlg:newrow()

    settingsDlg:button{ text="Apply", onclick=function()
        local interval = tonumber(settingsDlg.data.auto_commit_interval)
        if not interval or interval < 60 then
            app.alert("Interval must be a number greater than or equal to 60 seconds (1 minute).")
            return
        end

        settings.show_stats = settingsDlg.data.show_stats
        settings.show_commit = settingsDlg.data.show_commit
        settings.show_history = settingsDlg.data.show_history
        settings.auto_commit_enabled = settingsDlg.data.auto_commit_enabled
        settings.auto_commit_interval = interval
        settings.show_tag_entry = settingsDlg.data.show_tag_entry
        settings.show_message_entry = settingsDlg.data.show_message_entry
        settings.show_diff_button = settingsDlg.data.show_diff_button
        settings.show_load_button = settingsDlg.data.show_load_button
        settings.show_ref_button = settingsDlg.data.show_ref_button
        settings.show_log_button = settingsDlg.data.show_log_button
        
        saveSettings(settings)
        updateSettingsDisplay()
        startAutoCommitTimer()
        settingsDlg:close()
    end }
    
    settingsDlg:button{ text="Cancel", onclick=function() settingsDlg:close() end }
    settingsDlg:show()
end

-- Visual Diff UI
local function showDiffUI(startIndex)
    if not startIndex or not historyData[startIndex] then
        return
    end
    
    if diffDlg then
        diffDlg:close()
        diffDlg = nil
    end

    local currentIndex = startIndex
    local snapImg = nil
    
    local currImg = Image(spr.width, spr.height, spr.colorMode)
    local frameNumber = 1
    if app.activeFrame then frameNumber = app.activeFrame.frameNumber end
    currImg:drawSprite(spr, frameNumber, 0, 0)
    
    local scale = 1
    if spr.width > 300 then
        scale = 300 / spr.width
    end
    local drawW = math.floor(spr.width * scale)
    local drawH = math.floor(spr.height * scale)
    
    if scale < 1 then
        currImg:resize(drawW, drawH)
    end

    local function loadSnapshot(idx)
        local entry = historyData[idx]
        local path = fs.joinPath(repoDir, entry.filename)
        
        if not fs.isFile(path) then
            snapImg = nil
            return
        end
        
        local snapSpr = app.open(path)
        if snapSpr then
            snapImg = Image(snapSpr.width, snapSpr.height, spr.colorMode)
            snapImg:drawSprite(snapSpr, 1, 0, 0)
            snapSpr:close()
            if scale < 1 then
                snapImg:resize(drawW, drawH)
            end
        end
    end

    loadSnapshot(currentIndex)

    diffDlg = Dialog{ title="Visual Diff" }
    local diffContentIds = {"diff_sep", "diff_cvs"}
    addMinimizeButton(diffDlg, diffContentIds)
    
    diffDlg:button{ text="< Newer", onclick=function()
        if currentIndex > 1 then
            currentIndex = currentIndex - 1
            loadSnapshot(currentIndex)
            diffDlg:repaint()
        end
    end }
    diffDlg:button{ text="Older >", onclick=function()
        if currentIndex < #historyData then
            currentIndex = currentIndex + 1
            loadSnapshot(currentIndex)
            diffDlg:repaint()
        end
    end }
    diffDlg:newrow()

    diffDlg:separator{ id="diff_sep", text="Comparison (Current vs Old)" }
    
    diffDlg:canvas{
        id="diff_cvs",
        width=drawW*2 + 20,
        height=drawH + 40,
        onpaint=function(ev)
            local gc = ev.context
            local entry = historyData[currentIndex]
            
            gc.color = Color{r=60, g=60, b=60}
            gc:fillRect(Rectangle(0, 0, ev.width, ev.height))

            gc.color = Color{r=16, g=194, b=108}
            gc:fillText("Current State", 0, 0)
            gc:drawImage(currImg, 0, 20)
            gc:strokeRect(Rectangle(0, 20, drawW, drawH))

            if entry and snapImg then
                local dateStr = os.date("%H:%M:%S", entry.timestamp)
                local msg = entry.message
                if #msg > 18 then
                    msg = string.sub(msg, 1, 16) .. "..."
                end
                local randomId = entry.short_id and string.sub(entry.short_id, 1, 6) or ""
                local label = string.format("#%s | %s (%s)", randomId, msg, dateStr)
                
                gc.color = Color{r=255, g=100, b=100}
                gc:fillText(label, drawW + 10, 0)
                gc:drawImage(snapImg, drawW + 10, 20)
                gc.color = Color{r=255, g=100, b=100}
                gc:strokeRect(Rectangle(drawW + 10, 20, drawW, drawH))
            else
                gc:fillText("File not found", drawW + 10, 20)
            end
        end
    }
    diffDlg:show{ wait=false }
end

-- Full History Log UI
local function showAseGitLog()
    if logDlg then
        logDlg:close()
        logDlg = nil
    end

    local log = loadLog()
    logDlg = Dialog{ title="Commit History" }
    
    local scrollY = 0
    local rowHeight = 45
    local visibleRows = 8
    local canvasHeight = visibleRows * rowHeight

    logDlg:canvas{
        id="gh_cvs",
        width=450,
        height=canvasHeight,
        onpaint=function(ev)
            local gc = ev.context
            gc.color = Color{r=60, g=60, b=60}
            gc:fillRect(Rectangle(0, 0, ev.width, ev.height))

            local y = 10 - scrollY
            gc.color = Color{r=100, g=100, b=100}
            gc:fillRect(Rectangle(20, 0, 2, #log * rowHeight + 100))

            for i = #log, 1, -1 do
                local e = log[i]
                gc.color = Color{r=88, g=166, b=255}
                gc:beginPath()
                gc:oval(Rectangle(16, y + 2, 10, 10))
                gc:fill()

                local textX = 40
                
                if e.tag and e.tag ~= "" then
                    local tagSize = gc:measureText(e.tag)
                    local tagW = tagSize.width + 10
                    
                    local tagColor = Color{r=24, g=154, b=91}
                    if e.tag == "AUTO" then
                        tagColor = Color{r=50, g=150, b=255}
                    end
                    
                    gc.color = tagColor
                    gc:fillRect(Rectangle(textX, y, tagW, 22))
                    gc.color = Color{r=255, g=255, b=255}
                    gc:fillText(e.tag, textX + 5, y + 2)
                    textX = textX + tagW + 10
                end

                gc.color = Color{r=255, g=255, b=255}
                local shortIdDisplay = e.short_id and string.sub(e.short_id, 1, 6) or ""
                
                local messageWithId = string.format("%s | #%s", e.message, shortIdDisplay)
                gc:fillText(messageWithId, textX, y)

                gc.color = Color{r=150, g=150, b=150}
                local dur = formatTime(e.session_time or 0)
                local edits = e.edits or 0
                
                local meta = string.format("%s | Time: %s | Edits: %d",
                    os.date("%H:%M:%S | %d-%m-%Y", e.timestamp),
                    dur,
                    edits
                )
                gc:fillText(meta, textX, y + 16)
                y = y + rowHeight
            end
        end,
        onwheel=function(ev)
            scrollY = scrollY + (ev.deltaY * 20)
            local maxScroll = (#log * rowHeight) - canvasHeight
            if scrollY < 0 then
                scrollY = 0
            end
            if scrollY > maxScroll + 20 then
                scrollY = maxScroll + 20
            end
            logDlg:repaint()
        end
    }

    logDlg:show{ wait=false }
end

-- Main Dialog UI
local function refreshContext()
    local newSpr = app.activeSprite
    if not newSpr then
        app.alert("No active sprite found.")
        return
    end
    
    if not newSpr.filename or newSpr.filename == "" then
        app.alert("Please save this sprite first to use AseGit.")
        return
    end
    
    if listenerObj and spr then
        spr.events:off(listenerObj)
    end
    
    spr = newSpr
    spritePath = spr.filename
    parentDir = fs.filePath(spritePath)
    spriteName = fs.fileName(spritePath)
    safeTitle = fs.fileTitle(spriteName)
    
    mainRepoDir = fs.joinPath(parentDir, ".asegit")
    repoDir = fs.joinPath(mainRepoDir, safeTitle .. "_data")
    logFile = fs.joinPath(repoDir, "asegit_log.json")
    settingsFile = fs.joinPath(repoDir, "settings.json")
    
    if not fs.isDirectory(mainRepoDir) then
        fs.makeDirectory(mainRepoDir)
    end
    if not fs.isDirectory(repoDir) then
        fs.makeDirectory(repoDir)
    end
    
    sessionStart = os.time()
    sessionEdits = 0
    
    settings = loadSettings()
    recalcTotals()
    
    listenerObj = spr.events:on('change', function()
        sessionEdits = sessionEdits + 1
    end)
    
    if mainDlg then
        mainDlg:modify{ title = "AseGit: " .. spriteName }
        updateHistoryUI()
        updateSettingsDisplay()
        
        mainDlg:modify{ id="tag_entry", text="" }
        mainDlg:modify{ id="message", text="" }
    end
    
    startAutoCommitTimer()
end


mainDlg = Dialog{
    title = "AseGit: " .. spriteName,
    onclose = function()
        if timerObj then
            timerObj:stop()
        end
        if autoCommitTimer then
            autoCommitTimer:stop()
        end
        if listenerObj then
            spr.events:off(listenerObj)
        end
        if diffDlg then
            diffDlg:close()
        end
        if logDlg then
            logDlg:close()
        end
    end
}

local function getSelectedEntryIndex()
    local indexStr = mainDlg.data.history_list
    if not indexStr or indexStr == "" then
        return nil
    end
    for i, label in ipairs(historyLabels) do
        if label == indexStr then
            return i
        end
    end
    return nil
end

local function getSelectedEntry()
    local idx = getSelectedEntryIndex()
    if idx then
        return historyData[idx]
    end
    return nil
end

local function importAsReference()
    local entry = getSelectedEntry()
    if not entry then
        return
    end
    
    local path = fs.joinPath(repoDir, entry.filename)
    if not fs.isFile(path) then
        app.alert("File missing!")
        return
    end

    local refSpr = app.open(path)
    app.activeSprite = spr
    
    local newLayer = spr:newLayer()
    newLayer.name = "Ref: " .. (entry.tag ~= "" and entry.tag or entry.message)
    newLayer.opacity = 128
    
    app.transaction(function()
        local refImage = Image(refSpr.width, refSpr.height, spr.colorMode)
        refImage:drawSprite(refSpr, 1, 0, 0)
        spr:newCel(newLayer, 1, refImage, Point(0, 0))
    end)
    
    refSpr:close()
    app.refresh()
end

local mainContentIds = {
    "sep_stats", "stat_session", "stat_total",
    "sep_commit", "tag_entry", "message", "btn_commit",
    "sep_hist", "history_list",
    "btn_diff", "btn_load", "btn_ref", "btn_log",
    "btn_refresh", "btn_settings"
}

addMinimizeButton(mainDlg, mainContentIds, {"btn_commit"})
mainDlg:button{ id="btn_refresh", text="Refresh", onclick=refreshContext }
mainDlg:button{ id="btn_settings", text="⚙️", onclick=showSettingsUI }
mainDlg:newrow()

mainDlg:separator{ id="sep_stats", text="Statistics" }
mainDlg:label{ id="stat_session", text="" }
mainDlg:label{ id="stat_total", text=".............." }
mainDlg:newrow()

mainDlg:separator{ id="sep_commit", text="Commit" }
mainDlg:entry{ id="tag_entry", label="Tag:", text="" }
mainDlg:entry{ id="message", label="Message:", text="" }
mainDlg:button{ id="btn_commit", text="Commit", onclick=performManualCommit }

mainDlg:separator{ id="sep_hist", text="History Actions" }
mainDlg:combobox{ id="history_list", options=historyLabels, label="Select:" }

mainDlg:button{ id="btn_diff", text="Visual Diff", onclick=function()
    local idx = getSelectedEntryIndex()
    if idx then
        showDiffUI(idx)
    else
        app.alert("Select a commit first")
    end
end }

mainDlg:button{ id="btn_load", text="Load File", onclick=function()
    local e = getSelectedEntry()
    if e then
        app.open(fs.joinPath(repoDir, e.filename))
    end
end }

mainDlg:newrow()
mainDlg:button{ id="btn_ref", text="Add as Ref Layer", onclick=importAsReference }
mainDlg:button{ id="btn_log", text="View Full History", onclick=showAseGitLog }

listenerObj = spr.events:on('change', function()
    sessionEdits = sessionEdits + 1
end)

timerObj = Timer{
    interval=1.0,
    ontick=function()
        local sessionDiff = os.time() - sessionStart
        local totalDiff = historicalTime + sessionDiff
        local totalEdits = historicalEdits + sessionEdits

        if mainDlg.bounds then
            local sStr = string.format("Session:  %s  -  Edits: %d", formatTime(sessionDiff), sessionEdits)
            local tStr = string.format("Total:  %s  -  Edits: %d", formatTime(totalDiff), totalEdits)
            
            mainDlg:modify{ id="stat_session", text=sStr }
            mainDlg:modify{ id="stat_total", text=tStr }
        else
            if timerObj then
                timerObj:stop()
            end
            if autoCommitTimer then
                autoCommitTimer:stop()
            end
            if listenerObj then
                spr.events:off(listenerObj)
            end
        end
    end
}

timerObj:start()
startAutoCommitTimer()

mainDlg:show{ wait=false }
updateSettingsDisplay()