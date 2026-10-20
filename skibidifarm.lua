-- Skibidi Trick-or-Treat Plaza farm, fixed build
if getgenv().TTC_Loaded then return end
getgenv().TTC_Loaded = true

local CFG = {
    Farm = true,
    Mode = "Real",          -- "Real" = ждать реальное кд двери (30 мин) | "Random" = пауза 1-3 мин между ноками
    RandomMin = 60,
    RandomMax = 180,
    DoorCooldown = 1800,    -- успешный нок = 30 мин кд
    CooldownJitter = 5,
    RejectDelay = 8,        -- если нок не приняли (анимация у другого ака)
    JumpDelay = 0.25,
    KnockOffset = 4,
    FpsCap = 20,
    Render3DDisabled = true,
    Spread = true,          -- разные аки начинают с разных дверей
    AntiAfk = true,
    Unanchor = true,
    Optimize = true,        -- чистка визуала + мьют звуков (без повторного скана всего дерева)
    MemLimitMB = 700,       -- выше этого — принудительный collectgarbage (не чаще раза в 60с)
    Debug = false,
    AutoJoinPrivate = true,
    PrivateServerLink = "",
    PlazaPlaceId = 18711550363,
    LobbyPlaceId = 14279693118,
}
for k, v in pairs(getgenv().TTC_Config or {}) do
    if CFG[k] ~= nil then CFG[k] = v end
end
local uc0 = getgenv().TTC_Config
if type(uc0) == "table" and uc0.AutoPlaza ~= nil then CFG.AutoJoinPrivate = uc0.AutoPlaza end

local function S(n)
    local s = game:GetService(n)
    return cloneref and cloneref(s) or s
end
local Players = S("Players")
local RunService = S("RunService")
local ReplicatedStorage = S("ReplicatedStorage")
local TeleportService = S("TeleportService")
local VirtualUser = S("VirtualUser")
local HttpService = S("HttpService")
local TweenService = S("TweenService")
local pl = Players.LocalPlayer

local LOADER_URL = "https://raw.githubusercontent.com/SecretSpeedW/skibidi-loader/refs/heads/main/loaderskibidi.lua"
local CFGFILE = "skibidi_config.txt"
local function hasFileApi() return typeof(writefile) == "function" and typeof(isfile) == "function" end
if hasFileApi() and isfile(CFGFILE) and type(getgenv().TTC_Config) ~= "table" then
    local okr, raw = pcall(readfile, CFGFILE)
    if okr and typeof(raw) == "string" then
        local okj, t = pcall(function() return HttpService:JSONDecode(raw) end)
        if okj and type(t) == "table" then getgenv().TTC_Config = t end
    end
end
if type(getgenv().TTC_Config) == "table" and hasFileApi() then
    pcall(function() writefile(CFGFILE, HttpService:JSONEncode(getgenv().TTC_Config)) end)
end

-- авто-заход: приватка по ссылке -> проверка, что мы реально на приватной плазе
local JOINFILE = "skibidi_join.txt"

local function queueNext()
    if typeof(queue_on_teleport) ~= "function" then return end
    pcall(queue_on_teleport, string.format([[pcall(function() loadstring(game:HttpGet("%s"))() end)]], LOADER_URL))
end

local function notify(t, d)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", { Title = t, Text = d or "", Duration = 5 })
    end)
end

local function isPrivate()
    local ok, id = pcall(function() return game.PrivateServerId end)
    if ok and typeof(id) == "string" and id ~= "" then return true end
    local ok2, owner = pcall(function() return game.PrivateServerOwnerId end)
    return ok2 and typeof(owner) == "number" and owner ~= 0
end

local function readJoin()
    if hasFileApi() and isfile(JOINFILE) then
        local ok, raw = pcall(readfile, JOINFILE)
        if ok and typeof(raw) == "string" then
            local okj, t = pcall(function() return HttpService:JSONDecode(raw) end)
            if okj and type(t) == "table" then return t end
        end
    end
    return {}
end

local function writeJoin(t)
    if hasFileApi() then pcall(function() writefile(JOINFILE, HttpService:JSONEncode(t)) end) end
end

-- не больше 2 попыток за 10 минут на один код, чтобы не было петли телепортов
local function attemptAllowed(code)
    local st = readJoin()
    if st.code ~= code or (os.time() - (tonumber(st.t) or 0)) > 600 then
        st = { code = code, n = 0, t = os.time() }
    end
    if (tonumber(st.n) or 0) >= 2 then return false end
    st.n = (tonumber(st.n) or 0) + 1
    st.t = os.time()
    writeJoin(st)
    return true
end

local function clearAttempts()
    if hasFileApi() and isfile(JOINFILE) then pcall(delfile, JOINFILE) end
end

local function waitLeave(job, secs)
    local t0 = os.clock()
    while os.clock() - t0 < (secs or 4) do
        if game.JobId ~= job then return true end
        task.wait(0.2)
    end
    return game.JobId ~= job
end

local function doTeleport(fn, secs)
    local job = game.JobId
    local failed = false
    local con
    pcall(function() con = TeleportService.TeleportInitFailed:Connect(function() failed = true end) end)
    local ok, err = pcall(fn)
    if not ok then
        failed = true
        if CFG.Debug then print("TTC join err", tostring(err)) end
        if typeof(err) == "string" and (err:find("from the server", 1, true) or err:find("from a Server", 1, true)) then
            getgenv().TTC_NoPrivate = true
        end
    end
    local left = waitLeave(job, secs)
    if con then pcall(function() con:Disconnect() end) end
    return not failed
end

local function goPlaza(waitSec)
    local job = game.JobId
    local r = ReplicatedStorage:FindFirstChild("TeleportToPlaza")
    if not r then
        local okw, w = pcall(function() return ReplicatedStorage:WaitForChild("TeleportToPlaza", 4) end)
        if okw then r = w end
    end
    if r and r:IsA("RemoteEvent") then
        if pcall(function() r:FireServer() end) and waitLeave(job, waitSec or 12) then return true end
    end
    return doTeleport(function() TeleportService:Teleport(CFG.PlazaPlaceId, pl) end, 6)
end

local function joinPlaza()
    if not CFG.AutoJoinPrivate then return false end
    local link = tostring(CFG.PrivateServerLink or "")
    local pid = tonumber(link:match("games/(%d+)")) or CFG.PlazaPlaceId
    local code = link:match("privateServerLinkCode=([%w%-_]+)") or link:match("[?&]code=([%w%-_]+)")
    if not code and link ~= "" and not link:find("://", 1, true) then code = link:match("^([%w%-_]+)$") end

    local inPlaza = (game.PlaceId == CFG.PlazaPlaceId)
    local priv = isPrivate()

    -- уже на приватной плазе — работаем
    if inPlaza and (not code or priv) then
        if code then clearAttempts() end
        return false
    end

    local canTry = code and not getgenv().TTC_NoPrivate and attemptAllowed(code)

    queueNext()
    task.wait(0.4)

    -- в публичной плазе: пробуем приватную, не вышло — фармим эту
    if inPlaza then
        if not canTry then
            if code and getgenv().TTC_NoPrivate then notify("Приватка", "Экзекутор не даёт приватку — фармлю публичную") end
            return false
        end
        notify("Приватка", "Плаза публичная, захожу на приватную")
        if doTeleport(function() TeleportService:TeleportToPrivateServer(CFG.PlazaPlaceId, code, { pl }) end, 4) then
            return true
        end
        notify("Приватка", "Не вышло, остаюсь в публичной")
        return false
    end

    -- не в плазе: сначала приватка (если можно), потом плаза
    if canTry and not priv then
        notify("Приватка", "Захожу на приватный сервер")
        if doTeleport(function() TeleportService:TeleportToPrivateServer(pid, code, { pl }) end, 4) then
            return true
        end
    end
    if priv then notify("Приватка", "На приватке, захожу в плазу") end
    return goPlaza(20)
end
local job0 = game.JobId
if joinPlaza() then
    task.wait(3)
    if game.JobId ~= job0 then
        getgenv().TTC_Loaded = false
        return
    end
end

pcall(function() if setfpscap then setfpscap(CFG.FpsCap) end end)
if CFG.Render3DDisabled then pcall(function() RunService:Set3dRenderingEnabled(false) end) end

local Conn = {}
local function bind(c) if c then Conn[#Conn + 1] = c end return c end
local alive = true
local TOKEN = tostring(os.clock()) .. "_" .. tostring(math.random(1, 1e9))
getgenv().TTC_Token = TOKEN
local function live() return alive and getgenv().TTC_Token == TOKEN end

---------------------------------------------------------------- UI
local guiParent = (typeof(gethui) == "function" and gethui()) or game:GetService("CoreGui")
local old = guiParent:FindFirstChild("TTC_FarmUI")
if old then old:Destroy() end
local Root = Instance.new("ScreenGui")
Root.Name = "TTC_FarmUI"
Root.ResetOnSpawn = false
Root.IgnoreGuiInset = true
Root.DisplayOrder = 1e7
Root.Parent = guiParent

local Black = Instance.new("Frame")
Black.Size = UDim2.new(1, 0, 1, 0)
Black.BackgroundColor3 = Color3.new(0, 0, 0)
Black.BorderSizePixel = 0
Black.Visible = CFG.Render3DDisabled
Black.Parent = Root

local W = Instance.new("Frame")
W.Size = UDim2.new(0, 330, 0, 282)
W.Position = UDim2.new(0.5, -165, 0, 30)
W.BackgroundColor3 = Color3.fromRGB(16, 13, 22)
W.BorderSizePixel = 0
W.Active = true
W.Parent = Root
local uc = Instance.new("UICorner"); uc.CornerRadius = UDim.new(0, 10); uc.Parent = W
local us = Instance.new("UIStroke"); us.Color = Color3.fromRGB(150, 80, 255); us.Thickness = 1.5; us.Parent = W

local function label(text, y, h, size, color, bold)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Size = UDim2.new(1, -20, 0, h or 20)
    l.Position = UDim2.new(0, 10, 0, y)
    l.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
    l.TextSize = size or 13
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextColor3 = color or Color3.fromRGB(190, 190, 200)
    l.Text = text
    l.Parent = W
    return l
end
label("SKIBIDI FARM · TTC PLAZA", 8, 24, 15, Color3.fromRGB(255, 255, 255), true)
local StatusL = label("Загрузка...", 34, 20, 12, Color3.fromRGB(120, 255, 160))
local StatL = label("", 56, 20, 12)
local NextL = label("", 76, 20, 12, Color3.fromRGB(255, 200, 90))

local function button(text, y, color)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, -20, 0, 30)
    b.Position = UDim2.new(0, 10, 0, y)
    b.BackgroundColor3 = color
    b.Font = Enum.Font.GothamBold
    b.TextSize = 12
    b.TextColor3 = Color3.new(1, 1, 1)
    b.Text = text
    b.BorderSizePixel = 0
    b.Parent = W
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = b
    return b
end

local FarmBtn = button("ФАРМ: ВКЛ", 108, Color3.fromRGB(35, 150, 80))
local ModeBtn = button("РЕЖИМ: РЕАЛЬНОЕ КД", 144, Color3.fromRGB(70, 55, 140))
local RenderBtn = button("3D: ВЫКЛ", 180, Color3.fromRGB(70, 55, 140))
local OptBtn = button("ОПТИМИЗАЦИЯ: ВКЛ", 216, Color3.fromRGB(35, 120, 130))
local UnloadBtn = button("UNLOAD", 252, Color3.fromRGB(150, 45, 45))
UnloadBtn.Size = UDim2.new(1, -20, 0, 24)

-- drag
do
    local dragging, start, pos
    W.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging, start, pos = true, i.Position, W.Position
        end
    end)
    bind(W.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - start
            W.Position = UDim2.new(pos.X.Scale, pos.X.Offset + d.X, pos.Y.Scale, pos.Y.Offset + d.Y)
        end
    end))
    bind(W.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end))
end

---------------------------------------------------------------- state
local S_ = {
    knocks = 0, treats = 0, fails = 0,
    offset = 0, cooldownUntil = 0,
}
local Doors, DoorIndex = {}, {}
local pendDoor, pendCd = nil, nil

local function setStatus(t, c) StatusL.Text = t; if c then StatusL.TextColor3 = c end end
local function now() return os.clock() end

-- источник кд: тост сервера
local toasts = ReplicatedStorage:FindFirstChild("Toasts")
local display = toasts and toasts:FindFirstChild("Assets") and toasts.Assets:FindFirstChild("Remotes") and toasts.Assets.Remotes:FindFirstChild("Display")
if display then
    bind(display.OnClientEvent:Connect(function(...)
        for _, v in ipairs({ ... }) do
            if typeof(v) == "table" and typeof(v.ContentText) == "string" then
                local c = v.ContentText
                if c:lower():find("cooldown", 1, true) then
                    local h = tonumber(c:match("(%d+)%s*Hour"))
                    local m = tonumber(c:match("(%d+)%s*Minute"))
                    local s = tonumber(c:match("(%d+)%s*Second"))
                    local total = (h or 0) * 3600 + (m or 0) * 60 + (s or 0)
                    if total > 0 then
                        pendCd = total
                        if pendDoor and pendDoor.model and pendDoor.model.Parent then
                            pendDoor.cd = now() + total + 1
                        end
                    end
                elseif typeof(v.Title) == "string" and v.Title:lower():find("treat") then
                    S_.treats = S_.treats + 1
                end
            end
        end
    end))
end

local function refreshDoors()
    local oldCd = {}
    for _, d in ipairs(Doors) do oldCd[d.num] = d.cd end
    Doors, DoorIndex = {}, {}
    for _, v in ipairs(workspace:GetChildren()) do
        if v.Name:match("^Door%d+") then
            local n = tonumber(v.Name:match("%d+")) or 0
            local d = { model = v, num = n, cd = oldCd[n] or 0 }
            Doors[#Doors + 1] = d
            DoorIndex[n] = d
        end
    end
    table.sort(Doors, function(a, b) return a.num < b.num end)
end
refreshDoors()
bind(workspace.ChildAdded:Connect(function(c)
    if typeof(c.Name) == "string" and c.Name:match("^Door%d+") then task.defer(refreshDoors) end
end))

---------------------------------------------------------------- оптимизация (одноразовый скан + очередь новых объектов, без лика)
local Opt = { On = CFG.Optimize ~= false, Q = {}, Head = 1, LastGC = 0, Swept = false }
local PROTECT = { Camera = true, Terrain = true, SafetyFloor = true }

local function isProtected(inst)
    if not inst then return true end
    local n = inst.Name
    if PROTECT[n] then return true end
    if typeof(n) == "string" and n:match("^Door%d+") then return true end
    local ch = pl.Character
    if ch and (inst == ch or inst:IsDescendantOf(ch)) then return true end
    return false
end

local function strip(inst)
    pcall(function()
        if inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Smoke") or inst:IsA("Fire")
            or inst:IsA("Sparkles") or inst:IsA("Beam") or inst:IsA("Highlight") then
            inst.Enabled = false
        elseif inst:IsA("Decal") or inst:IsA("Texture") then
            inst.Transparency = 1
        elseif inst:IsA("Sound") then
            inst:Stop()
            inst:Destroy()
        elseif inst:IsA("BasePart") then
            inst.Material = Enum.Material.SmoothPlastic
            inst.CastShadow = false
            inst.Reflectance = 0
        end
    end)
end

local function sweep()
    if not Opt.On then return end
    Opt.Swept = true
    local Lighting = game:GetService("Lighting")
    pcall(function()
        for _, c in ipairs(workspace:GetChildren()) do
            if not isProtected(c) and not c:IsA("Model") and not c:IsA("Folder") then
                pcall(function() c:Destroy() end)
            end
        end
    end)
    for _, inst in ipairs(workspace:GetDescendants()) do strip(inst) end
    pcall(function()
        Lighting.GlobalShadows = false
        Lighting.FogEnd = 9e9
        Lighting.Brightness = 0.5
        for _, l in ipairs(Lighting:GetChildren()) do
            if l:IsA("PostEffect") or l:IsA("Atmosphere") or l:IsA("Sky") or l:IsA("Clouds") then
                pcall(function() l:Destroy() end)
            end
        end
    end)
    Opt.Q, Opt.Head = {}, 1
end

if Opt.On then
    sweep()
    bind(workspace.DescendantAdded:Connect(function(inst)
        if not Opt.On then return end
        if #Opt.Q > 3000 then return end
        Opt.Q[#Opt.Q + 1] = inst
    end))
end

---------------------------------------------------------------- память
local function memMB() return collectgarbage("count") / 1024 end
local function gcGuard()
    if now() - Opt.LastGC < 60 then return end
    if memMB() > CFG.MemLimitMB then
        Opt.LastGC = now()
        pcall(function() collectgarbage("collect") end)
    end
end

task.spawn(function()
    while live() do
        if Opt.On then
            local n = 0
            while Opt.Head <= #Opt.Q and n < 80 do
                local inst = Opt.Q[Opt.Head]
                Opt.Q[Opt.Head] = nil
                Opt.Head = Opt.Head + 1
                n = n + 1
                if inst and inst.Parent then
                    if inst.Parent == workspace and not isProtected(inst) and not inst:IsA("Model") and not inst:IsA("Folder") then
                        pcall(function() inst:Destroy() end)
                    else
                        strip(inst)
                    end
                end
            end
            if Opt.Head > #Opt.Q then Opt.Q, Opt.Head = {}, 1 end
        end
        gcGuard()
        task.wait(0.5)
    end
end)

local function getChar()
    local ch = pl.Character
    if not ch then return nil, nil end
    local hum = ch:FindFirstChildOfClass("Humanoid")
    local hrp = ch:FindFirstChild("HumanoidRootPart")
    if not hum or not hrp or hum.Health <= 0 then return nil, nil end
    return ch, hrp
end

if CFG.Unanchor then
    bind(RunService.Stepped:Connect(function()
        local ch, hrp = getChar()
        if hrp and hrp.Anchored then hrp.Anchored = false end
    end))
end

local function knock(d)
    local p = d.model:FindFirstChildWhichIsA("ProximityPrompt", true)
    if not p then return "gone" end
    local t = p.Parent
    if not p.Enabled then return "busy" end
    local ch, hrp = getChar()
    if not hrp or not t then return "nochar" end

    hrp.CFrame = t.CFrame * CFrame.new(0, CFG.KnockOffset, 0)
    hrp.AssemblyLinearVelocity = Vector3.zero
    task.wait(CFG.JumpDelay)
    ch, hrp = getChar()
    if not hrp or not p.Parent or not p.Enabled then return "busy" end

    pendCd = nil
    pendDoor = d
    if typeof(fireproximityprompt) == "function" then
        pcall(fireproximityprompt, p, 0)
    else
        pcall(function() p:InputHoldBegin(); task.wait(0.05); p:InputHoldEnd() end)
    end
    task.wait(0.45)

    if p.Parent and not p.Enabled then
        S_.knocks = S_.knocks + 1
        d.cd = now() + CFG.DoorCooldown + math.random(0, CFG.CooldownJitter)
        return "ok"
    end
    local dl = now() + 2.5
    while now() < dl and not pendCd do task.wait(0.1) end
    if pendCd then
        d.cd = now() + pendCd + 1
        return "cd"
    end
    d.cd = now() + CFG.RejectDelay
    return "reject"
end

local function pickReady()
    local ready = {}
    local t = now()
    for _, d in ipairs(Doors) do
        local p = d.model.Parent and d.model:FindFirstChildWhichIsA("ProximityPrompt", true)
        if p and p.Enabled and d.cd <= t then ready[#ready + 1] = d end
    end
    if #ready == 0 then return nil end
    local i = 1
    if CFG.Spread then
        i = (S_.offset % #ready) + 1
        S_.offset = (S_.offset + 1) % math.max(1, #Doors)
    end
    return ready[i]
end

local function nextCd()
    local t, best = now(), math.huge
    for _, d in ipairs(Doors) do
        if d.cd > t and d.cd - t < best then best = d.cd - t end
    end
    return best
end

local function updHud()
    local ready = 0
    for _, d in ipairs(Doors) do
        local p = d.model:FindFirstChildWhichIsA("ProximityPrompt", true)
        if p and p.Enabled and d.cd <= now() then ready = ready + 1 end
    end
    StatL.Text = string.format("Ноков: %d | Готово: %d/%d | RAM: %.0f MB", S_.knocks, ready, #Doors, memMB())
    local n = nextCd()
    NextL.Text = "Ближайшее кд: " .. (n == math.huge and "—" or (n > 60 and string.format("%d мин", math.ceil(n / 60)) or string.format("%d сек", math.ceil(n))))
end

---------------------------------------------------------------- buttons
FarmBtn.MouseButton1Click:Connect(function()
    CFG.Farm = not CFG.Farm
    FarmBtn.Text = CFG.Farm and "ФАРМ: ВКЛ" or "ФАРМ: ВЫКЛ"
    FarmBtn.BackgroundColor3 = CFG.Farm and Color3.fromRGB(35, 150, 80) or Color3.fromRGB(110, 45, 45)
    setStatus(CFG.Farm and "Работаю" or "Пауза")
end)
ModeBtn.MouseButton1Click:Connect(function()
    CFG.Mode = (CFG.Mode == "Real") and "Random" or "Real"
    ModeBtn.Text = CFG.Mode == "Real" and "РЕЖИМ: РЕАЛЬНОЕ КД" or "РЕЖИМ: РАНДОМ 1-3 МИН"
end)
RenderBtn.MouseButton1Click:Connect(function()
    CFG.Render3DDisabled = not CFG.Render3DDisabled
    Black.Visible = CFG.Render3DDisabled
    pcall(function() RunService:Set3dRenderingEnabled(not CFG.Render3DDisabled) end)
    RenderBtn.Text = CFG.Render3DDisabled and "3D: ВЫКЛ" or "3D: ВКЛ"
end)
OptBtn.MouseButton1Click:Connect(function()
    Opt.On = not Opt.On
    OptBtn.Text = Opt.On and "ОПТИМИЗАЦИЯ: ВКЛ" or "ОПТИМИЗАЦИЯ: ВЫКЛ"
    OptBtn.BackgroundColor3 = Opt.On and Color3.fromRGB(35, 120, 130) or Color3.fromRGB(70, 70, 80)
    if Opt.On and not Opt.Swept then sweep() end
    if not Opt.On then Opt.Q, Opt.Head = {}, 1 end
end)

local function unload()
    alive = false
    getgenv().TTC_Loaded = false
    if getgenv().TTC_Token == TOKEN then getgenv().TTC_Token = nil end
    Opt.On = false
    Opt.Q, Opt.Head = {}, 1
    for _, c in ipairs(Conn) do pcall(function() c:Disconnect() end) end
    Conn = {}
    pcall(function() RunService:Set3dRenderingEnabled(true) end)
    pcall(function() if setfpscap then setfpscap(0) end end)
    Root:Destroy()
end
UnloadBtn.MouseButton1Click:Connect(unload)
getgenv().TTC_Unload = unload
getgenv().TTC_State = S_
getgenv().TTC_CFG = CFG
getgenv().TTC_Doors = function() return Doors end
if CFG.Mode == "Random" then ModeBtn.Text = "РЕЖИМ: РАНДОМ 1-3 МИН" end
if not CFG.Optimize then
    OptBtn.Text = "ОПТИМИЗАЦИЯ: ВЫКЛ"
    OptBtn.BackgroundColor3 = Color3.fromRGB(70, 70, 80)
end

---------------------------------------------------------------- afk
if CFG.AntiAfk then
    local VIM = game:GetService("VirtualInputManager")
    bind(pl.Idled:Connect(function()
        pcall(function()
            VirtualUser:Button2Down(Vector2.zero, workspace.CurrentCamera.CFrame)
            task.wait(1)
            VirtualUser:Button2Up(Vector2.zero, workspace.CurrentCamera.CFrame)
        end)
    end))
    task.spawn(function()
        while live() do
            task.wait(60)
            if not live() then break end
            pcall(function()
                VIM:SendKeyEvent(true, "Space", false, game)
                task.wait(0.1)
                VIM:SendKeyEvent(false, "Space", false, game)
            end)
        end
    end)
end

---------------------------------------------------------------- main
S_.offset = math.random(0, math.max(1, #Doors))
task.spawn(function()
    local fpsTick = 0
    while live() do
        if not CFG.Farm then
            setStatus("Пауза", Color3.fromRGB(255, 200, 90))
            task.wait(0.4)
        else
            local ch, hrp = getChar()
            if not ch then
                setStatus("Жду персонажа...", Color3.fromRGB(255, 200, 90))
                task.wait(0.5)
            else
                if os.clock() > fpsTick then
                    pcall(function() if setfpscap then setfpscap(CFG.FpsCap) end end)
                    fpsTick = os.clock() + 2
                end
                local d = pickReady()
                if not d then
                    updHud()
                    local n = nextCd()
                    setStatus("Все двери на кд", Color3.fromRGB(255, 200, 90))
                    task.wait(math.min(2, math.max(0.2, n ~= math.huge and n or 1)))
                else
                    setStatus("Нок " .. d.model.Name, Color3.fromRGB(120, 255, 160))
                    local r = knock(d)
                    if CFG.Debug then print("TTC", d.model.Name, r, "ok=" .. S_.knocks, "cd=" .. math.floor(d.cd - now())) end
                    if r == "ok" then
                        setStatus("Открыл " .. d.model.Name, Color3.fromRGB(120, 255, 160))
                        if CFG.Mode == "Random" then
                            task.wait(math.random(CFG.RandomMin, CFG.RandomMax))
                        else
                            task.wait(0.1)
                        end
                    elseif r == "cd" then
                        setStatus("КД " .. d.model.Name, Color3.fromRGB(255, 160, 90))
                    elseif r == "reject" then
                        S_.fails = S_.fails + 1
                        d.cd = now() + CFG.RejectDelay + math.random(0, 3)
                        setStatus("Дверь занята, жду", Color3.fromRGB(255, 160, 90))
                        task.wait(0.6)
                    elseif r == "busy" then
                        d.cd = now() + 2
                        task.wait(0.4)
                    else
                        task.wait(0.3)
                    end
                    updHud()
                end
            end
        end
    end
end)
setStatus("Работаю", Color3.fromRGB(120, 255, 160))
