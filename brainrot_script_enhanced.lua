local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local StarterGui = game:GetService("StarterGui")
local BYPASS_KEY = "" 
local API_URL = "https://tealegret.onpella.app"
local HWID = game:GetService("RbxAnalyticsService"):GetClientId()
local Player = Players.LocalPlayer
local Settings = {
    targetGen = 1000000,
    espOn = true,
    autoHop = true,
    notify = true,
    scanDelay = 3,
    failThreshold = 10,
    filterHighestOnly = true,
    minBrainrotValue = 1000000,
    showUnlockTime = true,
    speedBoost = false,
    jumpBoost = false,
    speedValue = 50,
    jumpValue = 100,
    desyncEnabled = false
}
local function saveSettings()
    pcall(function()
        local requestFunc = syn and syn.request or http_request or request or HttpService.RequestAsync
        local requestData = {
            Url = API_URL .. "/api/settings/save",
            Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = HttpService:JSONEncode({
                hwid = HWID,
                settings = Settings
            })
        }
        if requestFunc == HttpService.RequestAsync then
            HttpService:RequestAsync(requestData)
        else
            requestFunc(requestData)
        end
    end)
end
local function loadSettings()
    local success, result = pcall(function()
        local requestFunc = syn and syn.request or http_request or request or HttpService.RequestAsync
        if requestFunc == HttpService.RequestAsync then
            return HttpService:RequestAsync({
                Url = API_URL .. "/api/settings/load/" .. HWID,
                Method = "GET"
            })
        else
            return requestFunc({
                Url = API_URL .. "/api/settings/load/" .. HWID,
                Method = "GET"
            })
        end
    end)
    if success and result and result.Success and result.StatusCode == 200 then
        local parseSuccess, data = pcall(function()
            return HttpService:JSONDecode(result.Body)
        end)
        if parseSuccess and data and data.settings then
            for k, v in pairs(data.settings) do
                Settings[k] = v
            end
            return true
        end
    end
    return false
end
local esp = {}
local brainrotData = nil
local found = false
local targetBrainrots = {}
local SELECTED_BRAINROT = "All"
local mainLoopRunning = false
local kickCheckRunning = false
local Window = nil
local ToggleButton = nil
local guiVisible = true
local unlockTimeESPs = {}
local desyncConnection = nil
local currentServerId = game.JobId
local function validateKey(key)
    local success, result = pcall(function()
        local requestFunc = syn and syn.request or http_request or request or HttpService.RequestAsync
        if not requestFunc then
            return {Success = false, StatusCode = 0, Body = '{"error": "No HTTP"}'}
        end
        if requestFunc == HttpService.RequestAsync then
            return HttpService:RequestAsync({
                Url = API_URL .. "/api/key/validate",
                Method = "POST",
                Headers = {["Content-Type"] = "application/json"},
                Body = HttpService:JSONEncode({key = key, hwid = HWID})
            })
        else
            return requestFunc({
                Url = API_URL .. "/api/key/validate",
                Method = "POST",
                Headers = {["Content-Type"] = "application/json"},
                Body = HttpService:JSONEncode({key = key, hwid = HWID})
            })
        end
    end)
    if success and result and result.Success and (result.StatusCode == 200 or result.StatusCode == "200") then
        local parseSuccess, data = pcall(function()
            return HttpService:JSONDecode(result.Body)
        end)
        if parseSuccess and data then
            return data.valid == true, (data.message or "Unknown")
        end
    end
    return false, "Connection failed"
end
local function startKickCheck()
    if kickCheckRunning then return end
    kickCheckRunning = true
    spawn(function()
        while kickCheckRunning do
            task.wait(5)
            local success, result = pcall(function()
                local requestFunc = syn and syn.request or http_request or request or HttpService.RequestAsync
                if requestFunc == HttpService.RequestAsync then
                    return HttpService:RequestAsync({
                        Url = API_URL .. "/api/check_kicked/" .. HWID,
                        Method = "GET"
                    })
                else
                    return requestFunc({
                        Url = API_URL .. "/api/check_kicked/" .. HWID,
                        Method = "GET"
                    })
                end
            end)
            if success and result and result.Success then
                local parseSuccess, data = pcall(function()
                    return HttpService:JSONDecode(result.Body)
                end)
                if parseSuccess and data and data.kicked then
                    kickCheckRunning = false
                    Player:Kick("HWID reset. Rejoin.")
                    break
                end
            end
        end
    end)
end
local function parseNumber(str)
    if not str or type(str) ~= "string" then return nil end
    str = str:lower():gsub("[,%s$]", "")
    local mul = 1
    if str:find("b$") then mul = 1e9; str = str:gsub("b$", "")
    elseif str:find("m$") then mul = 1e6; str = str:gsub("m$", "")
    elseif str:find("k$") then mul = 1e3; str = str:gsub("k$", "") end
    local num = str:gsub("[^%d%.]", "")
    local val = tonumber(num)
    return val and (val * mul) or nil
end
local function extractProd(text)
    if not text then return nil end
    local patterns = {
        "([%d$%,%.]+[%d%.]*[kKmMbB]?)%s*/?%s*[sSgG]en?",
        "([%d$%,%.]+[%d%.]*[kKmMbB]?)%s*[pP]er%s*[sS]ec?",
        "([%d$%,%.]+[%d%.]*[kKmMbB]?)%s*s",
        "([%d$%,%.]+)%s*/?%s*[sSgG]",
        "([%d$%,%.]+[%d%.]*[kKmMbB]?)",
        "([%d$%,%.]+)"
    }
    for _, p in ipairs(patterns) do
        local m = text:match(p)
        if m then return parseNumber(m) end
    end
    return nil
end
local function getProdFromGUI(model)
    if not model then return nil end
    for _, gui in pairs(model:GetDescendants()) do
        if gui:IsA("SurfaceGui") or gui:IsA("BillboardGui") or gui.ClassName == "GuiMain" then
            for _, lbl in pairs(gui:GetDescendants()) do
                if lbl:IsA("TextLabel") or lbl:IsA("TextButton") or lbl:IsA("TextBox") then
                    local val = extractProd(lbl.Text)
                    if val then return val end
                end
            end
        end
    end
    return nil
end
local function getOwner(model)
    if not model then return "???" end
    local cur = model
    while cur and cur.Parent do
        local o = cur:FindFirstChild("Owner") or cur:FindFirstChild("Creator")
        if o and o:IsA("StringValue") then return o.Value end
        if o and o:IsA("ObjectValue") and o.Value then return o.Value.Name end
        cur = cur.Parent
    end
    return "???"
end
local function isBrainrot(model)
    if not model or not model:IsA("Model") then return false end
    if model:FindFirstChild("Humanoid") then return false end
    return model:FindFirstChildWhichIsA("BasePart") ~= nil
end
local function toggleDesync()
    if not Settings.desyncEnabled then
        if desyncConnection then
            desyncConnection:Disconnect()
            desyncConnection = nil
        end
        if Player.Character and Player.Character:FindFirstChild("HumanoidRootPart") then
            Player.Character.HumanoidRootPart.Anchored = false
        end
        if Settings.notify then
            pcall(function()
                StarterGui:SetCore("SendNotification", {
                    Title = "Desync OFF",
                    Text = "Character movement normalized",
                    Duration = 3
                })
            end)
        end
    else
        if Player.Character and Player.Character:FindFirstChild("HumanoidRootPart") then
            local hrp = Player.Character.HumanoidRootPart
            desyncConnection = RunService.Heartbeat:Connect(function()
                if Settings.desyncEnabled and hrp and hrp.Parent then
                    hrp.Velocity = Vector3.new(math.random(-30, 30), math.random(-10, 10), math.random(-30, 30))
                end
            end)
        end
        if Settings.notify then
            pcall(function()
                StarterGui:SetCore("SendNotification", {
                    Title = "Desync ON",
                    Text = "Movement desynced - harder to hit!",
                    Duration = 3
                })
            end)
        end
    end
end
local function applyBoosts()
    if Player.Character and Player.Character:FindFirstChild("Humanoid") then
        local hum = Player.Character.Humanoid
        if Settings.speedBoost then
            hum.WalkSpeed = Settings.speedValue
        else
            hum.WalkSpeed = 16
        end
        if Settings.jumpBoost then
            pcall(function()
                if hum.UseJumpPower then
                    hum.JumpPower = Settings.jumpValue
                else
                    hum.JumpHeight = Settings.jumpValue / 5
                end
            end)
        else
            pcall(function()
                if hum.UseJumpPower then
                    hum.JumpPower = 50
                else
                    hum.JumpHeight = 7.2
                end
            end)
        end
    end
end
Player.CharacterAdded:Connect(function(char)
    char:WaitForChild("Humanoid")
    task.wait(0.5)
    applyBoosts()
    if Settings.desyncEnabled then
        if desyncConnection then
            desyncConnection:Disconnect()
            desyncConnection = nil
        end
        local hrp = char:WaitForChild("HumanoidRootPart")
        desyncConnection = RunService.Heartbeat:Connect(function()
            if Settings.desyncEnabled and hrp and hrp.Parent then
                hrp.Velocity = Vector3.new(math.random(-30, 30), math.random(-10, 10), math.random(-30, 30))
            end
        end)
    end
end)
local function addESP(part, name, prod, owner, unlockTime)
    if not Settings.espOn or not part or not part:IsA("BasePart") or esp[part] then return end
    local bg = Instance.new("BillboardGui")
    bg.Size = UDim2.new(0, 260, 0, 100)
    bg.StudsOffset = Vector3.new(0, 5, 0)
    bg.Adornee = part
    bg.Parent = part
    bg.AlwaysOnTop = true
    bg.LightInfluence = 0
    bg.Name = "BrainrotESP"
    local label = Instance.new("TextLabel", bg)
    label.Size = UDim2.new(1, 0, 0, 80)
    label.BackgroundTransparency = 1
    label.TextColor3 = Color3.fromRGB(255, 0, 0)
    label.TextStrokeTransparency = 0.3
    label.Font = Enum.Font.Code
    label.TextScaled = true
    label.Text = string.format("TARGET\n<%s>\n%.0f/s\n%s", name, prod, owner)
    local unlockLabel = Instance.new("TextLabel", bg)
    unlockLabel.Size = UDim2.new(1, 0, 0, 20)
    unlockLabel.Position = UDim2.new(0, 0, 0, 80)
    unlockLabel.BackgroundTransparency = 1
    unlockLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
    unlockLabel.TextStrokeTransparency = 0.3
    unlockLabel.Font = Enum.Font.Code
    unlockLabel.TextSize = 14
    unlockLabel.Text = "Unlock: Calculating..."
    local function updateUnlockTime()
        if unlockTime and unlockTime > os.time() then
            local timeLeft = unlockTime - os.time()
            if timeLeft > 0 then
                local hours = math.floor(timeLeft / 3600)
                local minutes = math.floor((timeLeft % 3600) / 60)
                local seconds = timeLeft % 60
                unlockLabel.Text = string.format("Unlock: %02d:%02d:%02d", hours, minutes, seconds)
            else
                unlockLabel.Text = "Unlock: Unlocked!"
            end
        else
            unlockLabel.Text = "Unlock: N/A"
        end
    end
    updateUnlockTime()
    spawn(function()
        while part and part.Parent and Settings.espOn do
            updateUnlockTime()
            task.wait(1)
        end
    end)
    esp[part] = {bg = bg, unlockTime = unlockTime}
end
local function clearESP()
    for part, data in pairs(esp) do
        if part and part.Parent and data.bg then
            pcall(function() data.bg:Destroy() end)
        end
    end
    esp = {}
    targetBrainrots = {}
    if Settings.notify then
        pcall(function()
            StarterGui:SetCore("SendNotification", {
                Title = "Cleared",
                Text = "All brainrot ESPs removed",
                Duration = 3,
                Icon = "rbxassetid://6031075938"
            })
        end)
    end
end
local function getFloorUnlockTime(plot, floorNum)
    local floorKey = "BlockEndTime" .. (floorNum == 1 and "FirstFloor" or floorNum == 2 and "SecondFloor" or "ThirdFloor")
    for _, obj in pairs(plot:GetDescendants()) do
        if obj.Name == floorKey and (obj:IsA("IntValue") or obj:IsA("NumberValue")) then
            return obj.Value
        end
    end
    local unlockTime = plot:GetAttribute(floorKey)
    if unlockTime then return unlockTime end
    return nil
end
local function addPlotBlockUnlockESP(part, floorNum, unlockTime)
    if not Settings.showUnlockTime or not part or not part:IsA("BasePart") then return end
    if unlockTimeESPs[part] then return end
    local bg = Instance.new("BillboardGui")
    bg.Size = UDim2.new(0, 200, 0, 50)
    bg.StudsOffset = Vector3.new(0, 3, 0)
    bg.Adornee = part
    bg.Parent = part
    bg.AlwaysOnTop = true
    bg.LightInfluence = 0
    bg.Name = "UnlockTimeESP"
    local label = Instance.new("TextLabel", bg)
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.TextColor3 = Color3.fromRGB(255, 165, 0)
    label.TextStrokeTransparency = 0.3
    label.Font = Enum.Font.GothamBold
    label.TextScaled = true
    label.Text = "Checking..."
    local function updateUnlockTime()
        if unlockTime and unlockTime > os.time() then
            local timeLeft = unlockTime - os.time()
            if timeLeft > 0 then
                local hours = math.floor(timeLeft / 3600)
                local minutes = math.floor((timeLeft % 3600) / 60)
                local seconds = timeLeft % 60
                label.Text = string.format("Floor %d LOCKED\n%02d:%02d:%02d", floorNum, hours, minutes, seconds)
                label.TextColor3 = Color3.fromRGB(255, 0, 0)
            else
                label.Text = string.format("Floor %d OPEN", floorNum)
                label.TextColor3 = Color3.fromRGB(0, 255, 0)
            end
        else
            if part.CanCollide then
                label.Text = string.format("Floor %d LOCKED", floorNum)
                label.TextColor3 = Color3.fromRGB(255, 0, 0)
            else
                label.Text = string.format("Floor %d OPEN", floorNum)
                label.TextColor3 = Color3.fromRGB(0, 255, 0)
            end
        end
    end
    updateUnlockTime()
    spawn(function()
        while part and part.Parent and Settings.showUnlockTime do
            updateUnlockTime()
            task.wait(1)
        end
    end)
    unlockTimeESPs[part] = {bg = bg, unlockTime = unlockTime}
end
local function clearPlotBlockESPs()
    for part, data in pairs(unlockTimeESPs) do
        if part and part.Parent and data.bg then
            pcall(function() data.bg:Destroy() end)
        end
    end
    unlockTimeESPs = {}
end
local function scanPlotBlocks()
    if not Settings.showUnlockTime then 
        clearPlotBlockESPs()
        return 
    end
    local plotsFolder = Workspace:FindFirstChild("Plots")
    if not plotsFolder then return end
    for _, plot in pairs(plotsFolder:GetChildren()) do
        if plot:IsA("Model") then
            local laserHitbox = plot:FindFirstChild("LaserHitbox")
            if laserHitbox then
                for _, hitbox in pairs(laserHitbox:GetChildren()) do
                    local floor = hitbox:GetAttribute("Floor")
                    if floor and floor >= 1 and floor <= 3 then
                        if not unlockTimeESPs[hitbox] then
                            local unlockTime = getFloorUnlockTime(plot, floor)
                            addPlotBlockUnlockESP(hitbox, floor, unlockTime)
                        end
                    end
                end
            end
        end
    end
end
local function scan()
    if not Settings.targetGen then return nil end
    local plotsFolder = Workspace:FindFirstChild("Plots") or Workspace
    if not plotsFolder then
        if Settings.notify then
            pcall(function()
                StarterGui:SetCore("SendNotification", {
                    Title = "Error",
                    Text = "No Plots folder found",
                    Duration = 5,
                    Icon = "rbxassetid://6031075938"
                })
            end)
        end
        return nil
    end
    local allBrainrots = {}
    for _, plot in pairs(plotsFolder:GetChildren()) do
        if plot:IsA("Model") then
            for _, obj in pairs(plot:GetDescendants()) do
                if obj:IsA("Model") and isBrainrot(obj) then
                    local name = obj.Name
                    local owner = getOwner(obj)
                    local prod = 0
                    if brainrotData and brainrotData[name] and brainrotData[name].Generation then
                        prod = brainrotData[name].Generation
                    end
                    local guiProd = getProdFromGUI(obj)
                    if guiProd and guiProd > prod then prod = guiProd end
                    local matchesFilter = (SELECTED_BRAINROT == "All" or name:lower():find(SELECTED_BRAINROT:lower(), 1, true))
                    if prod >= Settings.targetGen and matchesFilter then
                        table.insert(allBrainrots, {
                            model = obj,
                            name = name,
                            prod = prod,
                            owner = owner,
                            unlockTime = nil,
                            part = obj:FindFirstChild("HumanoidRootPart") or obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
                        })
                    end
                end
            end
        end
    end
    if Settings.filterHighestOnly and #allBrainrots > 0 then
        table.sort(allBrainrots, function(a, b) return a.prod > b.prod end)
        local maxProd = allBrainrots[1].prod
        local filtered = {}
        for _, br in ipairs(allBrainrots) do
            if br.prod >= maxProd * 0.9 then
                table.insert(filtered, br)
            end
        end
        allBrainrots = filtered
    end
    targetBrainrots = allBrainrots
    for _, br in ipairs(targetBrainrots) do
        if br.part and not esp[br.part] then
            addESP(br.part, br.name, br.prod, br.owner, br.unlockTime)
        end
    end
    if #targetBrainrots > 0 then
        found = true
        if Settings.notify then
            pcall(function()
                StarterGui:SetCore("SendNotification", {
                    Title = "TARGETS LOCKED",
                    Text = string.format("%d brainrots found ≥%.0f/s", #targetBrainrots, Settings.targetGen),
                    Duration = 10,
                    Icon = "rbxassetid://6031075938"
                })
            end)
        end
        return targetBrainrots
    end
    if #targetBrainrots == 0 and SELECTED_BRAINROT ~= "All" and Settings.notify then
        pcall(function()
            StarterGui:SetCore("SendNotification", {
                Title = "None Found",
                Text = string.format("No '%s' brainrots found with ≥%.0f/s", SELECTED_BRAINROT, Settings.targetGen),
                Duration = 5,
                Icon = "rbxassetid://6031075938"
            })
        end)
    end
    return nil
end


-- Executor detection function
local function detectExecutor()
    if syn then return "Synapse X"
    elseif KRNL_LOADED then return "KRNL"
    elseif Fluxus then return "Fluxus"
    elseif getexecutorname then return getexecutorname()
    elseif identifyexecutor then return identifyexecutor()
    else return "Unknown Executor" end
end

-- Send execution notification to Discord
local function sendExecutionNotification()
    pcall(function()
        local requestFunc = syn and syn.request or http_request or request or HttpService.RequestAsync
        local executorName = detectExecutor()
        local username = Player.Name
        
        local requestData = {
            Url = API_URL .. "/api/script/executed",
            Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = HttpService:JSONEncode({
                roblox_user = username,
                hwid = HWID,
                executor = executorName
            })
        }
        
        if requestFunc == HttpService.RequestAsync then
            HttpService:RequestAsync(requestData)
        else
            requestFunc(requestData)
        end
    end)
end
local function hop()
    if found then return end
    local servers = {}
    local success, result = pcall(function()
        return HttpService:JSONDecode(game:HttpGet(
            "https://games.roblox.com/v1/games/"..game.PlaceId.."/servers/Public?sortOrder=Asc&limit=100"
        ))
    end)
    if success and result and result.data then
        for _, s in pairs(result.data) do
            if s.playing and s.maxPlayers and s.id and s.playing > 1 and s.playing < s.maxPlayers * 0.9 and s.id ~= currentServerId then
                table.insert(servers, s.id)
            end
        end
    end
    if #servers > 0 then
        local randomServer = servers[math.random(#servers)]
        if Settings.notify then
            pcall(function()
                StarterGui:SetCore("SendNotification", {
                    Title = "Server Hopping",
                    Text = "Joining new server...",
                    Duration = 3
                })
            end)
        end
        TeleportService:TeleportToPlaceInstance(game.PlaceId, randomServer)
    else
        TeleportService:Teleport(game.PlaceId)
    end
end
local scanConnection = nil
local function startScanLoop()
    if scanConnection then
        pcall(function() scanConnection:Disconnect() end)
    end
    mainLoopRunning = true
    local fails = 0
    local lastScanTime = 0
    scanConnection = RunService.Heartbeat:Connect(function()
        if not mainLoopRunning or not Settings.targetGen then return end
        local currentTick = tick()
        if currentTick - lastScanTime < Settings.scanDelay then return end
        lastScanTime = currentTick
        local result = scan()
        if result then
            mainLoopRunning = false
            pcall(function() scanConnection:Disconnect() end)
        else
            if Settings.notify then
                pcall(function()
                    StarterGui:SetCore("SendNotification", {
                        Title = "Searching...",
                        Text = string.format("Looking for ≥%.0f/s", Settings.targetGen),
                        Duration = 2,
                        Icon = "rbxassetid://6031075938"
                    })
                end)
            end
            fails = fails + 1
            if fails >= Settings.failThreshold and Settings.autoHop then
                if Settings.notify then
                    pcall(function()
                        StarterGui:SetCore("SendNotification", {
                            Title = "Hopping...",
                            Text = string.format("No target after %d scans", fails),
                            Duration = 4,
                            Icon = "rbxassetid://6031075938"
                        })
                    end)
                end
                hop()
                fails = 0
                task.wait(10)
            end
        end
    end)
end
local function initMainUI()
    loadSettings()
    
    spawn(function()
        for i = 1, 3 do
            local success, data = pcall(function()
                local Datas = ReplicatedStorage:FindFirstChild("Datas")
                if not Datas then return end
                local Brainrot = Datas:FindFirstChild("Brainrot")
                if not Brainrot then return end
                return require(Brainrot)
            end)
            if success and data then
                brainrotData = data
                break
            end
            task.wait(2)
        end
    end)
    
    task.spawn(function()
        if Player.Character and Player.Character:FindFirstChild("Humanoid") then
            task.wait(1)
            applyBoosts()
            if Settings.desyncEnabled then
                toggleDesync()
            end
        end
    end)
    
    local successLib, Library = pcall(function()
        return loadstring(game:HttpGet("https://raw.githubusercontent.com/Mapple7777/UI-Librarys/main/UI-1/UI.lua"))()
    end)
    if not successLib or not Library then return end
    Window = Library:Create("Brainrot Finder v2.1", "Complete Edition")
    local FinderTab = Window:Tab("Auto Finder", true)
    FinderTab:Label("Target Generation (e.g. 10M, 1K)")
    FinderTab:Textbox("Target", tostring(Settings.targetGen), function(txt)
        local num = parseNumber(txt)
        if num then 
            Settings.targetGen = num
            saveSettings()
        end
    end)

    FinderTab:Label("Filter by Brainrot (leave 'All' to find any)")
    FinderTab:Textbox("Brainrot Name", SELECTED_BRAINROT, function(txt)
        SELECTED_BRAINROT = txt and txt ~= "" and txt or "All"
        if Settings.notify then
            pcall(function()
                StarterGui:SetCore("SendNotification", {
                    Title = "Filter Set",
                    Text = "Looking for: " .. SELECTED_BRAINROT,
                    Duration = 3,
                    Icon = "rbxassetid://6031075938"
                })
            end)
        end
    end)

    FinderTab:Button("List All Brainrots", function()
        if brainrotData then
            local brainrotList = {}
            for name, _ in pairs(brainrotData) do
                table.insert(brainrotList, name)
            end
            table.sort(brainrotList)
            local listText = table.concat(brainrotList, ", ")
            if #listText > 100 then
                listText = string.sub(listText, 1, 97) .. "..."
            end
            if Settings.notify then
                pcall(function()
                    StarterGui:SetCore("SendNotification", {
                        Title = "Available Brainrots",
                        Text = listText,
                        Duration = 10,
                        Icon = "rbxassetid://6031075938"
                    })
                end)
            end
        else
            if Settings.notify then
                pcall(function()
                    StarterGui:SetCore("SendNotification", {
                        Title = "Data Not Loaded",
                        Text = "Brainrot data not available yet",
                        Duration = 5,
                        Icon = "rbxassetid://6031075938"
                    })
                end)
            end
        end
    end)
    FinderTab:Button("Start Scanning", function()
        if not Settings.targetGen or Settings.targetGen < 1000 then
            if Settings.notify then
                pcall(function()
                    StarterGui:SetCore("SendNotification", {
                        Title = "Invalid",
                        Text = "Enter 1K+ target value first",
                        Duration = 5,
                        Icon = "rbxassetid://6031075938"
                    })
                end)
            end
            return
        end
        found = false
        targetBrainrots = {}
        clearESP()
        if Settings.notify then
            pcall(function()
                StarterGui:SetCore("SendNotification", {
                    Title = "Started!",
                    Text = string.format("Now searching ≥%.0f/s", Settings.targetGen),
                    Duration = 3,
                    Icon = "rbxassetid://6031075938"
                })
            end)
        end
        task.wait(0.5)
        startScanLoop()
    end)
    FinderTab:Button("Clear All ESPs", function()
        clearESP()
    end)
    FinderTab:Button("Desync Toggle", function()
        Settings.desyncEnabled = not Settings.desyncEnabled
        saveSettings()
        toggleDesync()
    end)
    FinderTab:Toggle("ESP", Settings.espOn, function(state)
        Settings.espOn = state
        if not state then clearESP() end
        saveSettings()
    end)
    FinderTab:Toggle("Auto Server Hop", Settings.autoHop, function(state)
        Settings.autoHop = state
        saveSettings()
    end)
    FinderTab:Toggle("Notifications", Settings.notify, function(state)
        Settings.notify = state
        saveSettings()
    end)
    FinderTab:Toggle("Filter: Highest Only", Settings.filterHighestOnly, function(state)
        Settings.filterHighestOnly = state
        saveSettings()
    end)
    local DetectTab = Window:Tab("Detect")
    DetectTab:Label("Plot Block Lock Detection")
    DetectTab:Label("Shows unlock countdown above locked floors")
    DetectTab:Toggle("Show Time Unlock", Settings.showUnlockTime, function(state)
        Settings.showUnlockTime = state
        if not state then
            clearPlotBlockESPs()
        else
            scanPlotBlocks()
        end
        saveSettings()
    end)
    DetectTab:Button("Refresh Unlock Times", function()
        clearPlotBlockESPs()
        scanPlotBlocks()
        if Settings.notify then
            pcall(function()
                StarterGui:SetCore("SendNotification", {
                    Title = "Refreshed",
                    Text = "Unlock times updated",
                    Duration = 3
                })
            end)
        end
    end)
    DetectTab:Button("Clear Unlock ESPs", function()
        clearPlotBlockESPs()
    end)
    local BoostsTab = Window:Tab("Boosts")
    BoostsTab:Label("Speed & Jump Boosts")
    BoostsTab:Toggle("Speed Boost", Settings.speedBoost, function(state)
        Settings.speedBoost = state
        saveSettings()
        applyBoosts()
    end)
    BoostsTab:Label("Speed Value")
    BoostsTab:Textbox("Speed", tostring(Settings.speedValue), function(txt)
        local num = tonumber(txt)
        if num and num > 0 and num <= 500 then 
            Settings.speedValue = num
            saveSettings()
            applyBoosts()
        end
    end)
    BoostsTab:Toggle("Jump Boost", Settings.jumpBoost, function(state)
        Settings.jumpBoost = state
        saveSettings()
        applyBoosts()
    end)
    BoostsTab:Label("Jump Power Value")
    BoostsTab:Textbox("Jump", tostring(Settings.jumpValue), function(txt)
        local num = tonumber(txt)
        if num and num > 0 and num <= 500 then 
            Settings.jumpValue = num
            saveSettings()
            applyBoosts()
        end
    end)
    BoostsTab:Button("Apply Boosts Now", function()
        applyBoosts()
        if Settings.notify then
            pcall(function()
                StarterGui:SetCore("SendNotification", {
                    Title = "Boosts Applied",
                    Text = string.format("Speed: %d | Jump: %d", Settings.speedValue, Settings.jumpValue),
                    Duration = 3
                })
            end)
        end
    end)
    local InfoTab = Window:Tab("Info")
    InfoTab:Label("Brainrot Finder v2.1")
    InfoTab:Label("✓ Auto-Save Settings")
    InfoTab:Label("✓ Smart Filtering")
    InfoTab:Label("✓ Plot Lock Detection")
    InfoTab:Label("✓ Desync System")
    InfoTab:Label("✓ Speed/Jump Boosts")
    InfoTab:Label("")
    InfoTab:Label("HWID: " .. HWID:sub(1, 16) .. "...")
    local btnGui = Instance.new("ScreenGui")
    btnGui.Name = "BrainrotToggle"
    btnGui.ResetOnSpawn = false
    btnGui.Parent = CoreGui
    ToggleButton = Instance.new("TextButton")
    ToggleButton.Size = UDim2.new(0, 60, 0, 60)
    ToggleButton.Position = UDim2.new(0, 10, 0.5, -30)
    ToggleButton.BackgroundColor3 = Color3.fromRGB(200, 0, 0)
    ToggleButton.BorderSizePixel = 0
    ToggleButton.Text = "BF"
    ToggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    ToggleButton.Font = Enum.Font.GothamBold
    ToggleButton.TextSize = 20
    ToggleButton.Parent = btnGui
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = ToggleButton
    ToggleButton.MouseButton1Click:Connect(function()
        guiVisible = not guiVisible
        -- Find and toggle the UI library ScreenGui
        pcall(function()
            for _, obj in pairs(CoreGui:GetChildren()) do
                if obj:IsA("ScreenGui") and obj:FindFirstChild("Main") then
                    obj.Enabled = guiVisible
                    break
                end
            end
        end)
    end)
    task.spawn(function()
        task.wait(0.5)
        applyBoosts()
        if Settings.desyncEnabled then
            local hrp = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
            if hrp and not desyncConnection then
                desyncConnection = RunService.Heartbeat:Connect(function()
                    if Settings.desyncEnabled and hrp and hrp.Parent then
                        hrp.Velocity = Vector3.new(math.random(-30, 30), math.random(-10, 10), math.random(-30, 30))
                    end
                end)
            end
        end
    end)
    
    -- Start plot block scanning loop
    task.spawn(function()
        while task.wait(2) do
            pcall(scanPlotBlocks)
        end
    end)
end

local function showKeyGUI()
    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "BrainrotKeySystem"
    ScreenGui.ResetOnSpawn = false
    ScreenGui.Parent = CoreGui
    local BG = Instance.new("Frame")
    BG.Size = UDim2.new(0, 360, 0, 230)
    BG.Position = UDim2.new(0.5, -180, 0.5, -115)
    BG.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    BG.BorderSizePixel = 0
    BG.Parent = ScreenGui
    local Title = Instance.new("TextLabel")
    Title.Size = UDim2.new(1, 0, 0, 40)
    Title.Position = UDim2.new(0, 0, 0, 10)
    Title.BackgroundTransparency = 1
    Title.Text = "BRAINROT FINDER v2.1"
    Title.TextColor3 = Color3.fromRGB(255, 0, 0)
    Title.Font = Enum.Font.GothamBold
    Title.TextSize = 22
    Title.Parent = BG
    local Sub = Instance.new("TextLabel")
    Sub.Size = UDim2.new(1, 0, 0, 30)
    Sub.Position = UDim2.new(0, 0, 0, 50)
    Sub.BackgroundTransparency = 1
    Sub.Text = "Enter Key (from Discord)"
    Sub.TextColor3 = Color3.fromRGB(180, 180, 180)
    Sub.Font = Enum.Font.Gotham
    Sub.TextSize = 16
    Sub.Parent = BG
    local Input = Instance.new("TextBox")
    Input.Size = UDim2.new(0, 300, 0, 40)
    Input.Position = UDim2.new(0.5, -150, 0, 90)
    Input.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    Input.BorderSizePixel = 0
    Input.TextColor3 = Color3.fromRGB(255, 255, 255)
    Input.PlaceholderText = "Enter key..."
    Input.Font = Enum.Font.Code
    Input.TextSize = 18
    Input.ClearTextOnFocus = false
    Input.Text = ""
    Input.Parent = BG
    local UnlockBtn = Instance.new("TextButton")
    UnlockBtn.Size = UDim2.new(0, 300, 0, 40)
    UnlockBtn.Position = UDim2.new(0.5, -150, 0, 140)
    UnlockBtn.BackgroundColor3 = Color3.fromRGB(200, 0, 0)
    UnlockBtn.BorderSizePixel = 0
    UnlockBtn.Text = "UNLOCK"
    UnlockBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    UnlockBtn.Font = Enum.Font.GothamBold
    UnlockBtn.TextSize = 18
    UnlockBtn.Parent = BG
    local function round(obj)
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = obj
    end
    round(BG); round(Input); round(UnlockBtn)
    local function shake()
        local original = BG.Position
        for i = 1, 6 do
            BG.Position = original + UDim2.new(0, math.random(-10, 10), 0, math.random(-5, 5))
            task.wait(0.05)
        end
        BG.Position = original
    end
    UnlockBtn.MouseButton1Click:Connect(function()
        local entered = (Input.Text or ""):match("^%s*(.-)%s*$") or ""
        if entered == "" then
            shake()
            return
        end
        UnlockBtn.Text = "VALIDATING..."
        Sub.Text = "Checking..."
        task.wait(0.1)
        local valid, message = validateKey(entered)
        if valid then
            Sub.Text = "Valid! Loading..."
            UnlockBtn.Text = "SUCCESS"
            task.wait(0.3)
            startKickCheck()
            sendExecutionNotification()
            local fadeInfo = TweenInfo.new(0.4)
            TweenService:Create(BG, fadeInfo, {BackgroundTransparency = 1}):Play()
            TweenService:Create(Input, fadeInfo, {BackgroundTransparency = 1, TextTransparency = 1}):Play()
            TweenService:Create(UnlockBtn, fadeInfo, {BackgroundTransparency = 1, TextTransparency = 1}):Play()
            TweenService:Create(Title, fadeInfo, {TextTransparency = 1}):Play()
            TweenService:Create(Sub, fadeInfo, {TextTransparency = 1}):Play()
            task.wait(0.5)
            ScreenGui:Destroy()
            initMainUI()
        else
            UnlockBtn.Text = "INVALID"
            Sub.Text = message or "Invalid key"
            task.wait(0.5)
            Input.Text = ""
            UnlockBtn.Text = "UNLOCK"
            Sub.Text = "Enter Key (from Discord)"
            shake()
        end
    end)
end

-- Check for bypass key first
if BYPASS_KEY and BYPASS_KEY ~= "" then
    local valid, message = validateKey(BYPASS_KEY)
    if valid then
        pcall(function()
            StarterGui:SetCore("SendNotification", {
                Title = "Bypass Valid",
                Text = "Loading script...",
                Duration = 3
            })
        end)
        startKickCheck()
        sendExecutionNotification()
        initMainUI()
    else
        showKeyGUI()
    end
else
    showKeyGUI()
end
