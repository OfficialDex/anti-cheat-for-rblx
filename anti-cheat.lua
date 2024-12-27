local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local maxWalkSpeed, maxJumpHeight, maxHealth, maxGravity = 50, 50, 100, 196.2
local admins = {"zaxon1opn", "zinxxh", "txkumaki", "CRINGE_X3", "sahilku91", "unclegidieon", "Sanplayz9_YT", "itskh4ng"}
local bannedPlayers = {}
local whitelistedPlayers = {}
local authorizedStatChanges = {}
local playerLogs = {}
local remoteEventLogs = {}
local playerActions = {}
local environmentHash = HttpService:GenerateGUID(false)

local function hashData(data)
    return string.sub(HttpService:JSONEncode(data):gsub("%W", ""), 1, 32)
end

local function kick(player, reason)
    player:Kick("[Anti-Cheat] " .. reason)
end

local function logPlayer(player, reason)
    if not playerLogs[player.UserId] then
        playerLogs[player.UserId] = {}
    end
    table.insert(playerLogs[player.UserId], {time = os.time(), reason = reason})
end

local function logRemoteEvent(player, eventName, params)
    if not remoteEventLogs[eventName] then
        remoteEventLogs[eventName] = {}
    end
    table.insert(remoteEventLogs[eventName], {player = player.UserId, time = os.time(), params = params})
end

local function isAdmin(player)
    return table.find(admins, player.Name) ~= nil
end

local function whitelistPlayer(player)
    whitelistedPlayers[player.UserId] = true
    task.delay(120, function() whitelistedPlayers[player.UserId] = false end)
end

local function authorizeStatChange(player, stat, duration)
    if not authorizedStatChanges[player.UserId] then
        authorizedStatChanges[player.UserId] = {}
    end
    authorizedStatChanges[player.UserId][stat] = true
    task.delay(duration, function()
        if authorizedStatChanges[player.UserId] then
            authorizedStatChanges[player.UserId][stat] = nil
        end
    end)
end

local function detectStatAbuse(player, humanoid)
    if whitelistedPlayers[player.UserId] then return end
    local stats = {WalkSpeed = humanoid.WalkSpeed, JumpPower = humanoid.JumpPower, Health = humanoid.Health}
    for stat, value in pairs(stats) do
        local max = stat == "WalkSpeed" and maxWalkSpeed or stat == "JumpPower" and maxJumpHeight or maxHealth
        if value > max and not authorizedStatChanges[player.UserId]?.[stat] then
            logPlayer(player, "Stat abuse detected: " .. stat .. " = " .. value)
            kick(player, "Stat abuse: " .. stat)
        end
    end
end

local function detectTeleport(player)
    local rootPart = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return end
    local lastPosition = rootPart.Position
    while task.wait(0.5) do
        if not rootPart then break end
        local distanceMoved = (rootPart.Position - lastPosition).Magnitude
        if distanceMoved > 200 and not whitelistedPlayers[player.UserId] then
            logPlayer(player, "Teleport detected")
            kick(player, "Teleport detected")
        end
        lastPosition = rootPart.Position
    end
end

local function detectEnvironmentTampering()
    local originalGravity = Workspace.Gravity
    while task.wait(1) do
        if Workspace.Gravity ~= originalGravity then
            Workspace.Gravity = originalGravity
            environmentHash = hashData(Workspace:GetChildren())
        end
    end
end

local function detectScriptInjection()
    Workspace.DescendantAdded:Connect(function(descendant)
        if descendant:IsA("Script") or descendant:IsA("LocalScript") then
            logPlayer(Players:GetPlayerFromCharacter(descendant.Parent), "Script injection detected")
            descendant:Destroy()
        end
    end)
end

local function detectUnauthorizedTools(player)
    player.Backpack.ChildAdded:Connect(function(tool)
        if not whitelistedPlayers[player.UserId] and tool:IsA("Tool") then
            logPlayer(player, "Unauthorized tool added")
            kick(player, "Unauthorized tool detected")
        end
    end)
end

local function detectUnauthorizedUI(player)
    player.PlayerGui.ChildAdded:Connect(function(gui)
        if not whitelistedPlayers[player.UserId] and (gui:IsA("ScreenGui") or gui:IsA("BillboardGui")) then
            logPlayer(player, "Unauthorized GUI added")
            kick(player, "Unauthorized GUI detected")
        end
    end)
end

local function detectHealthTampering(player, humanoid)
    humanoid:GetPropertyChangedSignal("Health"):Connect(function()
        if humanoid.Health > maxHealth and not authorizedStatChanges[player.UserId]?.Health then
            logPlayer(player, "Health tampering detected")
            kick(player, "Health tampering detected")
        end
    end)
end

local function monitorPlayer(player)
    local character = player.Character
    if not character then return end
    local humanoid = character:FindFirstChild("Humanoid")
    if humanoid then
        detectHealthTampering(player, humanoid)
        task.spawn(function()
            while task.wait(0.5) do
                if not character.Parent then break end
                detectStatAbuse(player, humanoid)
            end
        end)
    end
    task.spawn(function() detectTeleport(player) end)
    detectUnauthorizedTools(player)
    detectUnauthorizedUI(player)
end

local function onPlayerAdded(player)
    if table.find(admins, player.Name) then return end
    player.CharacterAdded:Connect(function() monitorPlayer(player) end)
end

local function onPlayerRemoving(player)
    whitelistedPlayers[player.UserId] = nil
    authorizedStatChanges[player.UserId] = nil
end

RunService.Heartbeat:Connect(function()
    for _, player in ipairs(Players:GetPlayers()) do
        if not table.find(admins, player.Name) then
            local character = player.Character
            if character then
                local humanoid = character:FindFirstChild("Humanoid")
                if humanoid then detectStatAbuse(player, humanoid) end
            end
        end
    end
end)

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
task.spawn(detectEnvironmentTampering)
task.spawn(detectScriptInjection)
for _, player in ipairs(Players:GetPlayers()) do onPlayerAdded(player) end

local function adminCommands(player, command, args)
    if not isAdmin(player) then return end
    if command == "kick" then
        local targetPlayer = Players:FindFirstChild(args[1])
        if targetPlayer then
            kick(targetPlayer, args[2])
        end
    elseif command == "ban" then
        local targetPlayer = Players:FindFirstChild(args[1])
        if targetPlayer then
            bannedPlayers[targetPlayer.UserId] = true
            kick(targetPlayer, "Banned from the server")
        end
    elseif command == "unban" then
        local userId = tonumber(args[1])
        if userId then
            bannedPlayers[userId] = nil
        end
    elseif command == "log" then
        local targetPlayer = Players:FindFirstChild(args[1])
        if targetPlayer then
            for _, log in ipairs(playerLogs[targetPlayer.UserId] or {}) do
                player:SendNotification({Title = "Player Log", Text = "Time: " .. log.time .. " Reason: " .. log.reason})
            end
        end
    elseif command == "remoteLog" then
        for event, logs in pairs(remoteEventLogs) do
            for _, log in ipairs(logs) do
                player:SendNotification({Title = event, Text = "Player ID: " .. log.player .. " Time: " .. log.time})
            end
        end
    elseif command == "clearLogs" then
        playerLogs = {}
        remoteEventLogs = {}
        player:SendNotification({Title = "Logs Cleared", Text = "All logs have been cleared."})
    elseif command == "forceDisconnect" then
        local targetPlayer = Players:FindFirstChild(args[1])
        if targetPlayer then
            targetPlayer:Kick("Disconnected by Admin")
        end
    end
end

game.ReplicatedStorage.AdminCommands.OnServerEvent:Connect(adminCommands)

local function trackPlayerActions(player)
    local lastActionTime = os.time()
    while task.wait(1) do
        local action = {
            lastAction = lastActionTime,
            currentTime = os.time(),
            idleTime = os.time() - lastActionTime
        }
        playerActions[player.UserId] = action
        lastActionTime = os.time()
    end
end

Players.PlayerAdded:Connect(function(player)
    task.spawn(function()
        trackPlayerActions(player)
    end)
end)
