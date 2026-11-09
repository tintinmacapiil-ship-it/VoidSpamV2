-- ʟᴜғғʏ's Ragebot v2
-- Full integration: ragebot_ui.txt + ragebot_Hardened + FastMelee/FastFire
-- 480px UI | Sharp edges | Zero-freeze architecture
-- Toggle: RightBracket ] or toggle button

--!native
--!optimize 2

-- ═══════════════════════════════════════════════════════════════
-- SERVICES
-- ═══════════════════════════════════════════════════════════════
local repS = cloneref(game:GetService("ReplicatedStorage"))
local plrs = cloneref(game:GetService("Players"))
local runS = cloneref(game:GetService("RunService"))
local ws   = cloneref(game:GetService("Workspace"))
local uis  = cloneref(game:GetService("UserInputService"))
local tws  = cloneref(game:GetService("TweenService"))
local coreG = cloneref(game:GetService("CoreGui"))
local lplr = plrs.LocalPlayer

-- ═══════════════════════════════════════════════════════════════
-- MODULES
-- ═══════════════════════════════════════════════════════════════
local util             = require(repS.Modules.Utility)
local enum             = require(repS.Modules.EnumLibrary)
local ItemLibrary      = require(repS.Modules.ItemLibrary)
local FighterController  = require(lplr.PlayerScripts.Controllers.FighterController)
local SpectateController = require(lplr.PlayerScripts.Controllers:WaitForChild("SpectateController"))

-- ═══════════════════════════════════════════════════════════════
-- FAST MELEE + FAST FIRE (extracted-code_1.txt — full integration)
-- Zeros all cooldowns on the ItemLibrary.Items table directly
-- Runs immediately so it patches before any weapon is equipped
-- ═══════════════════════════════════════════════════════════════
local function applyFastMelee()
    if game.GameId ~= 6035872082 then return end
    local Items = ItemLibrary.Items
    if not Items then return end

    -- Gun exceptions (keep cooldown for ballistcs)
    local gunExceptions = {
        Sniper   = true,
        Crossbow = true,
        Bow      = true,
        RPG      = true,
    }

    for name, data in pairs(Items) do
        if typeof(data) == "table" then

            -- Fast Fire: zero spread/recoil, minimise gun cooldowns
            if not gunExceptions[name] then
                if data.ShootSpread       then data.ShootSpread       = 0     end
                if data.ShootAccuracy     then data.ShootAccuracy     = 0     end
                if data.ShootRecoil       then data.ShootRecoil       = 0     end
                if data.ShootCooldown     then data.ShootCooldown     = 0.001 end
                if data.ShootBurstCooldown then data.ShootBurstCooldown = 0.001 end
            end

            -- Fast Melee: zero every attack/swing/recovery timing
            if data.AttackCooldown  then data.AttackCooldown  = 0.001 end
            if data.SwingCooldown   then data.SwingCooldown   = 0.001 end
            if data.MeleeCooldown   then data.MeleeCooldown   = 0.001 end
            if data.Cooldown        then data.Cooldown        = 0.001 end
            if data.RecoveryTime    then data.RecoveryTime    = 0.001 end
            if data.ResetTime       then data.ResetTime       = 0.001 end
        end
    end
end

pcall(applyFastMelee)

-- ═══════════════════════════════════════════════════════════════
-- CONFIG
-- ═══════════════════════════════════════════════════════════════
getgenv().Config = {
    -- Ragebot core
    Enabled      = true,
    FireRate     = 0.0005,
    WeaponSlot   = "Melee",
    AntiDeflect  = true,
    DesyncMode   = "Head",   -- "Head" | "Body"
    TeamCheck    = true,
    -- FastMelee module
    FastMelee    = true,
    FastFire     = true,
}

-- ═══════════════════════════════════════════════════════════════
-- SLOT TABLE
-- ═══════════════════════════════════════════════════════════════
local slots = { Primary = 1, Secondary = 2, Melee = 3 }
local function getSlotNumber()
    return slots[getgenv().Config.WeaponSlot] or 3
end

-- ═══════════════════════════════════════════════════════════════
-- EQUIP ON SPAWN + KEEP-EQUIPPED LOOP (ragebot_Hardened)
-- ═══════════════════════════════════════════════════════════════
task.spawn(function()
    local lf = FighterController.LocalFighter
    while not lf do task.wait(0.1); lf = FighterController.LocalFighter end
    pcall(function() lf:EquipItem(getSlotNumber()) end)
end)

task.spawn(function()
    while true do
        task.wait(1)
        if not getgenv().Config.Enabled then continue end
        local lf = FighterController.LocalFighter
        if lf then pcall(function() lf:EquipItem(getSlotNumber()) end) end
    end
end)

-- ═══════════════════════════════════════════════════════════════
-- RE-APPLY FastMelee when weapons are potentially reloaded
-- ═══════════════════════════════════════════════════════════════
task.spawn(function()
    while true do
        task.wait(5)
        if getgenv().Config.FastMelee or getgenv().Config.FastFire then
            pcall(applyFastMelee)
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════
-- DEFLECTION TRACKER (ragebot_Hardened)
-- ═══════════════════════════════════════════════════════════════
local lastFire   = 0
local deflecting = {}
plrs.PlayerRemoving:Connect(function(p) deflecting[p] = nil end)

local function updateDeflection()
    if not FighterController or not FighterController.Objects then return end
    for _, fo in FighterController.Objects do
        local player = fo.Player
        if not player then continue end
        if not fo.Entity or not fo.Entity:IsAlive() or fo:Get("IsSpectating") then
            deflecting[player] = false; continue
        end
        local eq       = fo.EquippedItem
        local isKatana = eq and eq.ViewModel and eq.ViewModel.Name == "Katana"
        local isDefl   = false
        if isKatana then
            isDefl = (eq._attack_cooldown and eq._attack_cooldown > tick()) or false
        end
        deflecting[player] = isDefl
    end
end

-- ═══════════════════════════════════════════════════════════════
-- ENEMY CHECK (ragebot_ui.txt)
-- ═══════════════════════════════════════════════════════════════
local function isEnemy(player)
    if player == lplr then return false end
    if getgenv().Config.TeamCheck then
        local duel = SpectateController.CurrentDuelSubject
        local ld   = duel and duel:GetDueler(lplr)
        local lt   = ld and ld:Get("TeamID") or nil
        if lt and duel and duel.Duelers then
            for _, d in duel.Duelers do
                if d.Player == player then
                    return d:Get("TeamID") ~= lt
                end
            end
        end
        local pT = player:GetAttribute("TeamID")
        local lT = lplr:GetAttribute("TeamID")
        if pT and lT then return pT ~= lT end
    end
    return true
end

-- ═══════════════════════════════════════════════════════════════
-- CLOSEST TARGET (ragebot_ui.txt)
-- ═══════════════════════════════════════════════════════════════
local function getClosestTarget()
    local char = lplr.Character
    if not char then return nil, nil, nil end
    local myRoot = char:FindFirstChild("HumanoidRootPart")
    if not myRoot then return nil, nil, nil end
    local cp, cr, ch = nil, nil, nil
    local cd = 500
    for _, p in plrs:GetPlayers() do
        if not isEnemy(p) then continue end
        local pc = p.Character
        if not pc then continue end
        local pr = pc:FindFirstChild("HumanoidRootPart")
        local ph = pc:FindFirstChild("Head")
        local pm = pc:FindFirstChildWhichIsA("Humanoid")
        if not (pr and ph and pm and pm.Health > 0) then continue end
        local d = (myRoot.Position - pr.Position).Magnitude
        if d < cd then cd=d; cp=p; cr=pr; ch=ph end
    end
    return cp, cr, ch
end

-- ═══════════════════════════════════════════════════════════════
-- KNIFE VIEWMODEL CHECK (ragebot_Hardened)
-- ═══════════════════════════════════════════════════════════════
local function hasKnifeViewModel(tp)
    if not tp then return false end
    local vm = ws:FindFirstChild("ViewModels")
    if not vm then return false end
    for _, m in vm:GetChildren() do
        if m:IsA("Model")
           and string.find(m.Name, tp.Name, 1, true)
           and string.find(m.Name, "Knife",  1, true) then
            return true
        end
    end
    return false
end

-- ═══════════════════════════════════════════════════════════════
-- SHARED STATE for HUD and status label
-- ═══════════════════════════════════════════════════════════════
local curTarget     = nil
local curTargetHead = nil
local curTargetRoot = nil

-- ═══════════════════════════════════════════════════════════════
-- HEARTBEAT — HARDENED RAGEBOT CORE
-- (ragebot_Hardened.txt exact logic, desync mode from ragebot_ui.txt)
-- ALL heavy work here — NEVER in RenderStepped
-- ═══════════════════════════════════════════════════════════════
runS.Heartbeat:Connect(function()
    updateDeflection()

    local targetPlayer, targetRoot, targetHead = getClosestTarget()
    curTarget     = targetPlayer
    curTargetHead = targetHead
    curTargetRoot = targetRoot

    local desyncCF = nil

    if targetRoot and targetHead then
        local desyncPos
        if getgenv().Config.DesyncMode == "Body" then
            desyncPos = (targetRoot.CFrame * CFrame.new(0, 3, -20)).Position
        else
            if hasKnifeViewModel(targetPlayer) then
                desyncPos = (targetRoot.CFrame * CFrame.new(0, 8, -18)).Position
            else
                desyncPos = (targetRoot.CFrame * CFrame.new(0, 3, -20)).Position
            end
        end
        desyncCF = CFrame.lookAt(desyncPos, targetHead.Position)
    end

    if desyncCF and lplr.Character then
        local myRoot = lplr.Character:FindFirstChild("HumanoidRootPart")
        if myRoot then
            local oldCF  = myRoot.CFrame
            local oldVel = myRoot.Velocity
            local oldRV  = myRoot.RotVelocity
            myRoot.CFrame = desyncCF
            runS:BindToRenderStep("__restore", 101, function()
                if myRoot then
                    myRoot.CFrame      = oldCF
                    myRoot.Velocity    = oldVel
                    myRoot.RotVelocity = oldRV
                end
                runS:UnbindFromRenderStep("__restore")
            end)
        end
    end

    if not getgenv().Config.Enabled then return end
    if not targetPlayer or not targetHead or not targetRoot then return end
    if getgenv().Config.AntiDeflect and deflecting[targetPlayer] then return end
    if not lplr.Character or not lplr.Character:FindFirstChild("HumanoidRootPart") then return end
    if not FighterController or not FighterController.LocalFighter then return end
    local item = FighterController.LocalFighter.EquippedItem
    if not item then return end
    if tick() - lastFire < getgenv().Config.FireRate then return end
    lastFire = tick()

    local originPos = desyncCF and desyncCF.Position or targetRoot.Position
    local targetPos = targetHead.Position
    local aimCF     = CFrame.lookAt(originPos, targetPos)
    local targetCF  = targetHead.CFrame
    local objOffset = CFrame.new(0, 0, 0)

    local cameraData = {}
    cameraData[utf8.char(1)] = {
        [utf8.char(0)] = util:EncodeCFrame(aimCF),
        [utf8.char(1)] = util:EncodeCFrame(targetCF),
        [utf8.char(2)] = targetHead,
        [utf8.char(3)] = util:EncodeCFrame(objOffset),
    }

    repS.Remotes.Replication.Fighter.UseItem:FireServer(
        item:Get("ObjectID"),
        enum:ToEnum("StartShooting"),
        cameraData,
        nil
    )
end)

-- ═══════════════════════════════════════════════════════════════
-- UI PALETTE  (ragebot_ui.txt exact colours)
-- ═══════════════════════════════════════════════════════════════
local W, H       = 480, 440
local ACCENT     = Color3.fromRGB(108, 92, 255)
local ACCDIM     = Color3.fromRGB(40,  34, 100)
local BG         = Color3.fromRGB(10,  10,  15)
local SURF       = Color3.fromRGB(16,  16,  24)
local SURF2      = Color3.fromRGB(22,  22,  34)
local SURF3      = Color3.fromRGB(28,  28,  44)
local BORDER     = Color3.fromRGB(36,  36,  58)
local BORDER2    = Color3.fromRGB(50,  50,  80)
local TXT        = Color3.fromRGB(220, 218, 240)
local TXTM       = Color3.fromRGB(100, 98,  130)
local TXTD       = Color3.fromRGB(44,  42,  68)
local TGLON      = Color3.fromRGB(68,  210, 118)
local TGLOFF     = Color3.fromRGB(36,  36,  56)
local RED        = Color3.fromRGB(220, 70,  70)
local GREEN      = Color3.fromRGB(68,  210, 118)
local GOLD       = Color3.fromRGB(255, 195, 50)

-- ═══════════════════════════════════════════════════════════════
-- UI HELPERS  (ragebot_ui.txt exact implementations)
-- ═══════════════════════════════════════════════════════════════
local function Tw(obj, props, t)
    tws:Create(obj, TweenInfo.new(t or 0.12, Enum.EasingStyle.Quad), props):Play()
end

local function NewI(cls, props)
    local i = Instance.new(cls)
    for k, v in pairs(props) do i[k] = v end
    return i
end

local function Corner(p, r)
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 6); c.Parent = p
end

local function Stroke(p, col, th)
    local s = Instance.new("UIStroke")
    s.Color = col or BORDER; s.Thickness = th or 1
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; s.Parent = p
end

-- ═══════════════════════════════════════════════════════════════
-- SCREEN GUI
-- ═══════════════════════════════════════════════════════════════
if coreG:FindFirstChild("LuffysRagebotV2") then coreG:FindFirstChild("LuffysRagebotV2"):Destroy() end
if lplr.PlayerGui:FindFirstChild("LuffysRagebotV2") then lplr.PlayerGui:FindFirstChild("LuffysRagebotV2"):Destroy() end

local gui = NewI("ScreenGui", {
    Name="LuffysRagebotV2", ResetOnSpawn=false,
    ZIndexBehavior=Enum.ZIndexBehavior.Sibling,
    DisplayOrder=999,
})
pcall(function() gui.Parent = coreG end)
if not gui.Parent then gui.Parent = lplr.PlayerGui end

-- ── TOGGLE BUTTON (rectangle, no corner — sharp edges per spec) ──
local toggleBtn = NewI("TextButton", {
    Size=UDim2.new(0,120,0,30), Position=UDim2.new(0,8,0,48),
    BackgroundColor3=ACCENT, Text="ʟᴜғғʏ's Rage",
    TextColor3=TXT, TextSize=11, Font=Enum.Font.GothamBold,
    BorderSizePixel=0, ZIndex=20, Parent=gui,
})
-- sharp rectangle = NO UICorner, UIStroke only
NewI("UIStroke", {Color=BORDER2, Thickness=1, Parent=toggleBtn})

local keyHint = NewI("TextLabel", {
    Size=UDim2.new(0,120,0,14), Position=UDim2.new(0,8,0,80),
    BackgroundTransparency=1, Text="[ RightBracket ]",
    TextColor3=TXTD, TextSize=9, Font=Enum.Font.Gotham,
    ZIndex=20, Parent=gui,
})

-- ── MAIN WINDOW (480px, sharp rectangle) ──
local win = NewI("Frame", {
    Size=UDim2.new(0,W,0,H), Position=UDim2.new(0.5,-W/2,0.5,-H/2),
    BackgroundColor3=BG, BorderSizePixel=0, ZIndex=2, Parent=gui,
})
-- Sharp edges: NO UICorner on the window
Stroke(win, BORDER, 1)

-- glow
local glow = NewI("ImageLabel", {
    Size=UDim2.new(1,60,1,60), Position=UDim2.new(0,-30,0,-30),
    BackgroundTransparency=1, Image="rbxassetid://5028857472",
    ImageColor3=ACCENT, ImageTransparency=0.88,
    ScaleType=Enum.ScaleType.Stretch, ZIndex=1, Parent=win,
})

-- ── TITLE BAR ──
local titleBar = NewI("Frame", {
    Size=UDim2.new(1,0,0,38), BackgroundColor3=SURF,
    BorderSizePixel=0, ZIndex=3, Parent=win,
})
-- No corner on titleBar either — full sharp UI
-- Bottom fill to remove rounded overlap
NewI("Frame", {
    Size=UDim2.new(1,0,0,10), Position=UDim2.new(0,0,0,28),
    BackgroundColor3=SURF, BorderSizePixel=0, ZIndex=3, Parent=win,
})

-- accent line left
NewI("Frame", {
    Size=UDim2.new(0,3,1,-10), Position=UDim2.new(0,0,0,5),
    BackgroundColor3=ACCENT, BorderSizePixel=0, ZIndex=4, Parent=titleBar,
})

-- title
NewI("TextLabel", {
    Size=UDim2.new(1,-110,1,0), Position=UDim2.new(0,14,0,0),
    BackgroundTransparency=1, Text="ʟᴜғғʏ's Ragebot",
    TextColor3=TXT, TextSize=14, Font=Enum.Font.GothamBold,
    TextXAlignment=Enum.TextXAlignment.Left, ZIndex=4, Parent=titleBar,
})
NewI("TextLabel", {
    Size=UDim2.new(0,30,1,0), Position=UDim2.new(0,145,0,0),
    BackgroundTransparency=1, Text="v2",
    TextColor3=TXTD, TextSize=10, Font=Enum.Font.Gotham,
    TextXAlignment=Enum.TextXAlignment.Left, ZIndex=4, Parent=titleBar,
})

-- status dot
local statusDot = NewI("Frame", {
    Size=UDim2.new(0,8,0,8), Position=UDim2.new(1,-50,0.5,-4),
    BackgroundColor3=GREEN, BorderSizePixel=0, ZIndex=5, Parent=titleBar,
})
Corner(statusDot, 4)

local statusLbl = NewI("TextLabel", {
    Size=UDim2.new(0,36,1,0), Position=UDim2.new(1,-40,0,0),
    BackgroundTransparency=1, Text="ON",
    TextColor3=GREEN, TextSize=10, Font=Enum.Font.GothamBold,
    TextXAlignment=Enum.TextXAlignment.Left, ZIndex=5, Parent=titleBar,
})

-- close btn (sharp)
local closeBtn = NewI("TextButton", {
    Size=UDim2.new(0,22,0,22), Position=UDim2.new(1,-28,0.5,-11),
    BackgroundColor3=RED, Text="×", TextColor3=TXT,
    TextSize=14, Font=Enum.Font.GothamBold,
    BorderSizePixel=0, ZIndex=5, Parent=titleBar,
})
-- no Corner = sharp

-- ── DRAG ──
local drag, dragStart, winStart = false, nil, nil
titleBar.InputBegan:Connect(function(inp)
    if inp.UserInputType==Enum.UserInputType.MouseButton1 then
        drag=true; dragStart=inp.Position; winStart=win.Position
    end
end)
uis.InputChanged:Connect(function(inp)
    if drag and inp.UserInputType==Enum.UserInputType.MouseMovement then
        local d=inp.Position-dragStart
        win.Position=UDim2.new(winStart.X.Scale,winStart.X.Offset+d.X,winStart.Y.Scale,winStart.Y.Offset+d.Y)
    end
end)
uis.InputEnded:Connect(function(inp)
    if inp.UserInputType==Enum.UserInputType.MouseButton1 then drag=false end
end)

-- ── VISIBILITY ──
local uiVisible = true
local function SetVisible(v)
    uiVisible=v; win.Visible=v
    toggleBtn.BackgroundColor3 = v and ACCENT or SURF2
    toggleBtn.Text = v and "ʟᴜғғʏ's Rage" or "ʟᴜғғʏ's Rage ·"
end
closeBtn.MouseButton1Click:Connect(function() SetVisible(false) end)
toggleBtn.MouseButton1Click:Connect(function() SetVisible(not uiVisible) end)
uis.InputBegan:Connect(function(inp, gpe)
    if not gpe and inp.KeyCode==Enum.KeyCode.RightBracket then SetVisible(not uiVisible) end
end)

-- ── CONTENT SCROLL ──
local content = NewI("ScrollingFrame", {
    Size=UDim2.new(1,0,1,-38), Position=UDim2.new(0,0,0,38),
    BackgroundTransparency=1, BorderSizePixel=0,
    ScrollBarThickness=3, ScrollBarImageColor3=ACCENT,
    CanvasSize=UDim2.new(0,0,0,0), AutomaticCanvasSize=Enum.AutomaticSize.Y,
    ZIndex=2, Parent=win,
})
NewI("UIListLayout", {SortOrder=Enum.SortOrder.LayoutOrder, Padding=UDim.new(0,0), Parent=content})
NewI("UIPadding", {
    PaddingTop=UDim.new(0,12), PaddingLeft=UDim.new(0,14),
    PaddingRight=UDim.new(0,14), PaddingBottom=UDim.new(0,12),
    Parent=content,
})

-- ═══════════════════════════════════════════════════════════════
-- ELEMENT BUILDERS (ragebot_ui.txt exact implementations)
-- ═══════════════════════════════════════════════════════════════
local elemOrd = 0
local function MkOrd() elemOrd=elemOrd+1; return elemOrd end

local function MkSpacer(h)
    NewI("Frame",{Size=UDim2.new(1,0,0,h or 4),BackgroundTransparency=1,LayoutOrder=MkOrd(),Parent=content})
end

local function MkSection(label)
    local f = NewI("Frame",{Size=UDim2.new(1,0,0,28),BackgroundTransparency=1,LayoutOrder=MkOrd(),Parent=content})
    NewI("Frame",{Size=UDim2.new(1,0,0,1),Position=UDim2.new(0,0,0.5,0),BackgroundColor3=BORDER,BorderSizePixel=0,Parent=f})
    local bg = NewI("Frame",{Size=UDim2.new(0,#label*7+16,0,20),Position=UDim2.new(0,0,0.5,-10),BackgroundColor3=BG,BorderSizePixel=0,Parent=f})
    NewI("TextLabel",{Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,Text=label,TextColor3=ACCENT,TextSize=10,Font=Enum.Font.GothamBold,TextXAlignment=Enum.TextXAlignment.Left,Parent=bg})
    local dot=NewI("Frame",{Size=UDim2.new(0,4,0,4),Position=UDim2.new(0,-8,0.5,-2),BackgroundColor3=ACCENT,BorderSizePixel=0,Parent=bg})
    Corner(dot,2)
end

local function MkToggle(label, default, callback)
    local state = default
    local row = NewI("Frame",{Size=UDim2.new(1,0,0,36),BackgroundColor3=SURF,BorderSizePixel=0,LayoutOrder=MkOrd(),Parent=content})
    Corner(row,6); Stroke(row,BORDER,1)
    NewI("TextLabel",{Size=UDim2.new(1,-56,1,0),Position=UDim2.new(0,12,0,0),BackgroundTransparency=1,Text=label,TextColor3=TXT,TextSize=12,Font=Enum.Font.GothamBold,TextXAlignment=Enum.TextXAlignment.Left,ZIndex=3,Parent=row})
    local track=NewI("Frame",{Size=UDim2.new(0,40,0,20),Position=UDim2.new(1,-48,0.5,-10),BackgroundColor3=state and TGLON or TGLOFF,BorderSizePixel=0,ZIndex=3,Parent=row})
    Corner(track,10); Stroke(track,BORDER,1)
    local knob=NewI("Frame",{Size=UDim2.new(0,16,0,16),Position=state and UDim2.new(1,-18,0.5,-8) or UDim2.new(0,2,0.5,-8),BackgroundColor3=TXT,BorderSizePixel=0,ZIndex=4,Parent=track})
    Corner(knob,8)
    local function Apply(v)
        state=v
        Tw(track,{BackgroundColor3=v and TGLON or TGLOFF})
        Tw(knob,{Position=v and UDim2.new(1,-18,0.5,-8) or UDim2.new(0,2,0.5,-8)})
        if callback then pcall(callback,v) end
    end
    local cb=NewI("TextButton",{Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,Text="",BorderSizePixel=0,ZIndex=5,Parent=row})
    cb.MouseButton1Click:Connect(function() Apply(not state) end)
    cb.MouseEnter:Connect(function() Tw(row,{BackgroundColor3=SURF2}) end)
    cb.MouseLeave:Connect(function() Tw(row,{BackgroundColor3=SURF}) end)
    return {Set=function(_,v) Apply(v) end, Get=function() return state end}
end

local function MkSlider(label, min, max, default, rounding, callback)
    local val=math.clamp(default,min,max)
    local container=NewI("Frame",{Size=UDim2.new(1,0,0,52),BackgroundColor3=SURF,BorderSizePixel=0,LayoutOrder=MkOrd(),Parent=content})
    Corner(container,6); Stroke(container,BORDER,1)
    local topRow=NewI("Frame",{Size=UDim2.new(1,-16,0,24),Position=UDim2.new(0,8,0,4),BackgroundTransparency=1,ZIndex=3,Parent=container})
    NewI("TextLabel",{Size=UDim2.new(1,-52,1,0),BackgroundTransparency=1,Text=label,TextColor3=TXT,TextSize=12,Font=Enum.Font.GothamBold,TextXAlignment=Enum.TextXAlignment.Left,ZIndex=3,Parent=topRow})
    local vLbl=NewI("TextLabel",{Size=UDim2.new(0,48,1,0),Position=UDim2.new(1,-48,0,0),BackgroundTransparency=1,TextColor3=ACCENT,TextSize=12,Font=Enum.Font.GothamBold,TextXAlignment=Enum.TextXAlignment.Right,ZIndex=3,Parent=topRow})
    local track=NewI("Frame",{Size=UDim2.new(1,-16,0,6),Position=UDim2.new(0,8,0,36),BackgroundColor3=SURF3,BorderSizePixel=0,ZIndex=3,Parent=container})
    Corner(track,3)
    local pct=(val-min)/(max-min)
    local fill=NewI("Frame",{Size=UDim2.new(pct,0,1,0),BackgroundColor3=ACCENT,BorderSizePixel=0,ZIndex=4,Parent=track})
    Corner(fill,3)
    local knob=NewI("Frame",{Size=UDim2.new(0,14,0,20),Position=UDim2.new(pct,-7,0.5,-10),BackgroundColor3=TXT,BorderSizePixel=0,ZIndex=5,Parent=track})
    Corner(knob,7); Stroke(knob,ACCENT,1)
    local function fmtVal(v)
        if rounding and rounding>0 and rounding<1 then return string.format("%.4f",v) else return tostring(math.floor(v)) end
    end
    local function SetVal(v)
        v=math.clamp(v,min,max)
        if rounding==0 then v=math.round(v)
        elseif rounding then v=math.floor(v/rounding+0.5)*rounding end
        val=v; local p=(v-min)/(max-min)
        fill.Size=UDim2.new(p,0,1,0); knob.Position=UDim2.new(p,-7,0.5,-10)
        vLbl.Text=fmtVal(v); if callback then pcall(callback,v) end
    end
    SetVal(val)
    local sliding=false
    local tb=NewI("TextButton",{Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,Text="",BorderSizePixel=0,ZIndex=6,Parent=track})
    tb.MouseButton1Down:Connect(function(x,y)
        sliding=true
        SetVal(min+(max-min)*math.clamp((x-track.AbsolutePosition.X)/track.AbsoluteSize.X,0,1))
    end)
    uis.InputChanged:Connect(function(inp)
        if sliding and inp.UserInputType==Enum.UserInputType.MouseMovement then
            SetVal(min+(max-min)*math.clamp((inp.Position.X-track.AbsolutePosition.X)/track.AbsoluteSize.X,0,1))
        end
    end)
    uis.InputEnded:Connect(function(inp) if inp.UserInputType==Enum.UserInputType.MouseButton1 then sliding=false end end)
    return {Set=function(_,v) SetVal(v) end, Get=function() return val end}
end

local activeDD=nil
local function MkDropdown(label, values, default, callback)
    local selected=values[default] or values[1]
    local row=NewI("Frame",{Size=UDim2.new(1,0,0,36),BackgroundColor3=SURF,BorderSizePixel=0,LayoutOrder=MkOrd(),Parent=content})
    Corner(row,6); Stroke(row,BORDER,1)
    NewI("TextLabel",{Size=UDim2.new(1,-148,1,0),Position=UDim2.new(0,12,0,0),BackgroundTransparency=1,Text=label,TextColor3=TXT,TextSize=12,Font=Enum.Font.GothamBold,TextXAlignment=Enum.TextXAlignment.Left,ZIndex=3,Parent=row})
    local db=NewI("TextButton",{Size=UDim2.new(0,130,0,24),Position=UDim2.new(1,-136,0.5,-12),BackgroundColor3=SURF3,Text=selected,TextColor3=TXT,TextSize=11,Font=Enum.Font.Gotham,BorderSizePixel=0,ZIndex=3,Parent=row})
    Corner(db,5); Stroke(db,BORDER,1)
    local arr=NewI("TextLabel",{Size=UDim2.new(0,18,1,0),Position=UDim2.new(1,-18,0,0),BackgroundTransparency=1,Text="▾",TextColor3=TXTM,TextSize=10,Font=Enum.Font.GothamBold,ZIndex=4,Parent=db})
    local listFrame=NewI("Frame",{Size=UDim2.new(0,130,0,0),BackgroundColor3=SURF2,BorderSizePixel=0,Visible=false,ZIndex=50,Parent=gui})
    Corner(listFrame,6); Stroke(listFrame,ACCENT,1); listFrame.AutomaticSize=Enum.AutomaticSize.Y
    NewI("UIListLayout",{SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,1),Parent=listFrame})
    NewI("UIPadding",{PaddingTop=UDim.new(0,3),PaddingBottom=UDim.new(0,3),PaddingLeft=UDim.new(0,3),PaddingRight=UDim.new(0,3),Parent=listFrame})
    for i,opt in ipairs(values) do
        local ob=NewI("TextButton",{Size=UDim2.new(1,0,0,24),BackgroundColor3=SURF2,Text=opt,TextColor3=opt==selected and ACCENT or TXT,TextSize=11,Font=Enum.Font.Gotham,BorderSizePixel=0,LayoutOrder=i,ZIndex=51,Parent=listFrame})
        Corner(ob,4)
        ob.MouseEnter:Connect(function() Tw(ob,{BackgroundColor3=SURF3}) end)
        ob.MouseLeave:Connect(function() Tw(ob,{BackgroundColor3=SURF2}) end)
        ob.MouseButton1Click:Connect(function()
            selected=opt; db.Text=opt
            for _,c in ipairs(listFrame:GetChildren()) do
                if c:IsA("TextButton") then c.TextColor3=c.Text==opt and ACCENT or TXT end
            end
            listFrame.Visible=false; activeDD=nil; Tw(arr,{TextColor3=TXTM})
            if callback then pcall(callback,opt) end
        end)
    end
    db.MouseButton1Click:Connect(function()
        if activeDD and activeDD~=listFrame then activeDD.Visible=false end
        local open=listFrame.Visible; listFrame.Visible=not open
        if not open then
            local abs=db.AbsolutePosition; local sz=db.AbsoluteSize
            listFrame.Position=UDim2.new(0,abs.X,0,abs.Y+sz.Y+2)
            activeDD=listFrame; Tw(arr,{TextColor3=ACCENT})
        else activeDD=nil; Tw(arr,{TextColor3=TXTM}) end
    end)
    uis.InputBegan:Connect(function(inp)
        if inp.UserInputType==Enum.UserInputType.MouseButton1 and activeDD==listFrame then
            local mx,my=inp.Position.X,inp.Position.Y
            local lp2=listFrame.AbsolutePosition; local ls=listFrame.AbsoluteSize
            if not(mx>=lp2.X and mx<=lp2.X+ls.X and my>=lp2.Y and my<=lp2.Y+ls.Y) then
                listFrame.Visible=false; activeDD=nil; Tw(arr,{TextColor3=TXTM})
            end
        end
    end)
    return {Set=function(_,v) selected=v; db.Text=v; if callback then pcall(callback,v) end end, Get=function() return selected end}
end

-- ═══════════════════════════════════════════════════════════════
-- BUILD UI ELEMENTS
-- ═══════════════════════════════════════════════════════════════

-- ── RAGEBOT CORE ──
MkSection("RAGEBOT")
MkSpacer(4)

local toggleRef = MkToggle("Enabled", getgenv().Config.Enabled, function(v)
    getgenv().Config.Enabled=v
    statusDot.BackgroundColor3 = v and GREEN or RED
    statusLbl.Text = v and "ON" or "OFF"
    statusLbl.TextColor3 = v and GREEN or RED
    Tw(glow,{ImageColor3= v and ACCENT or RED})
end)

MkSpacer(4)
MkSlider("Fire Rate", 0.0001, 0.05, getgenv().Config.FireRate, 0.0001, function(v)
    getgenv().Config.FireRate=v
end)

MkSpacer(4)
MkDropdown("Weapon Slot", {"Primary","Secondary","Melee"}, 3, function(v)
    getgenv().Config.WeaponSlot=v
end)

MkSpacer(4)
MkDropdown("Desync Mode", {"Head","Body"}, 1, function(v)
    getgenv().Config.DesyncMode=v
end)

-- ── FILTERS ──
MkSpacer(8)
MkSection("FILTERS")
MkSpacer(4)

MkToggle("Anti-Deflect (Katana)", getgenv().Config.AntiDeflect, function(v)
    getgenv().Config.AntiDeflect=v
end)

MkSpacer(4)
MkToggle("Team Check", getgenv().Config.TeamCheck, function(v)
    getgenv().Config.TeamCheck=v
end)

-- ── FAST MELEE / FAST FIRE ──
MkSpacer(8)
MkSection("FAST MELEE / FAST FIRE")
MkSpacer(4)

MkToggle("Fast Melee (all weapons)", getgenv().Config.FastMelee, function(v)
    getgenv().Config.FastMelee=v
    if v then
        -- Re-patch immediately
        pcall(function()
            local Items = ItemLibrary.Items
            if not Items then return end
            for name, data in pairs(Items) do
                if typeof(data)=="table" then
                    if data.AttackCooldown then data.AttackCooldown=0.001 end
                    if data.SwingCooldown  then data.SwingCooldown=0.001 end
                    if data.MeleeCooldown  then data.MeleeCooldown=0.001 end
                    if data.Cooldown       then data.Cooldown=0.001 end
                    if data.RecoveryTime   then data.RecoveryTime=0.001 end
                    if data.ResetTime      then data.ResetTime=0.001 end
                end
            end
        end)
    end
end)

MkSpacer(4)
MkToggle("Fast Fire (guns, no spread)", getgenv().Config.FastFire, function(v)
    getgenv().Config.FastFire=v
    if v then
        pcall(function()
            local gunExc = {Sniper=true,Crossbow=true,Bow=true,RPG=true}
            local Items = ItemLibrary.Items
            if not Items then return end
            for name, data in pairs(Items) do
                if typeof(data)=="table" and not gunExc[name] then
                    if data.ShootSpread       then data.ShootSpread=0 end
                    if data.ShootAccuracy     then data.ShootAccuracy=0 end
                    if data.ShootRecoil       then data.ShootRecoil=0 end
                    if data.ShootCooldown     then data.ShootCooldown=0.001 end
                    if data.ShootBurstCooldown then data.ShootBurstCooldown=0.001 end
                end
            end
        end)
    end
end)

-- ── INFO / TARGET ──
MkSpacer(8)
MkSection("INFO")
MkSpacer(4)

-- Target display row
local tgtRow=NewI("Frame",{Size=UDim2.new(1,0,0,36),BackgroundColor3=SURF,BorderSizePixel=0,LayoutOrder=MkOrd(),Parent=content})
Corner(tgtRow,6); Stroke(tgtRow,BORDER,1)
NewI("TextLabel",{Size=UDim2.new(0,120,1,0),Position=UDim2.new(0,12,0,0),BackgroundTransparency=1,Text="Target",TextColor3=TXTM,TextSize=11,Font=Enum.Font.Gotham,TextXAlignment=Enum.TextXAlignment.Left,Parent=tgtRow})
local tgtVal=NewI("TextLabel",{Size=UDim2.new(1,-130,1,0),Position=UDim2.new(0,120,0,0),BackgroundTransparency=1,Text="none",TextColor3=TXTD,TextSize=11,Font=Enum.Font.GothamBold,TextXAlignment=Enum.TextXAlignment.Right,Parent=tgtRow})
NewI("UIPadding",{PaddingRight=UDim.new(0,10),Parent=tgtVal})

MkSpacer(4)

-- FastMelee status row
local fmRow=NewI("Frame",{Size=UDim2.new(1,0,0,36),BackgroundColor3=SURF,BorderSizePixel=0,LayoutOrder=MkOrd(),Parent=content})
Corner(fmRow,6); Stroke(fmRow,BORDER,1)
NewI("TextLabel",{Size=UDim2.new(0,160,1,0),Position=UDim2.new(0,12,0,0),BackgroundTransparency=1,Text="FastMelee Engine",TextColor3=TXTM,TextSize=11,Font=Enum.Font.Gotham,TextXAlignment=Enum.TextXAlignment.Left,Parent=fmRow})
local fmVal=NewI("TextLabel",{Size=UDim2.new(1,-170,1,0),Position=UDim2.new(0,160,0,0),BackgroundTransparency=1,Text="ACTIVE",TextColor3=GREEN,TextSize=11,Font=Enum.Font.GothamBold,TextXAlignment=Enum.TextXAlignment.Right,Parent=fmRow})
NewI("UIPadding",{PaddingRight=UDim.new(0,10),Parent=fmVal})

MkSpacer(4)

-- Deflect status row
local deRow=NewI("Frame",{Size=UDim2.new(1,0,0,36),BackgroundColor3=SURF,BorderSizePixel=0,LayoutOrder=MkOrd(),Parent=content})
Corner(deRow,6); Stroke(deRow,BORDER,1)
NewI("TextLabel",{Size=UDim2.new(0,160,1,0),Position=UDim2.new(0,12,0,0),BackgroundTransparency=1,Text="Target Deflecting",TextColor3=TXTM,TextSize=11,Font=Enum.Font.Gotham,TextXAlignment=Enum.TextXAlignment.Left,Parent=deRow})
local deVal=NewI("TextLabel",{Size=UDim2.new(1,-170,1,0),Position=UDim2.new(0,160,0,0),BackgroundTransparency=1,Text="NO",TextColor3=GREEN,TextSize=11,Font=Enum.Font.GothamBold,TextXAlignment=Enum.TextXAlignment.Right,Parent=deRow})
NewI("UIPadding",{PaddingRight=UDim.new(0,10),Parent=deVal})

MkSpacer(8)

-- ═══════════════════════════════════════════════════════════════
-- FIX: ONE RenderStepped for ALL display updates — no freeze
-- Target display, deflect display — PURE reads, no physics/raycasts
-- ═══════════════════════════════════════════════════════════════
local displayTick = 0
runS.Heartbeat:Connect(function()
    displayTick = displayTick + 1
    if displayTick % 6 ~= 0 then return end  -- ~10Hz, not 60Hz

    -- Target label
    if curTarget then
        tgtVal.Text      = curTarget.Name
        tgtVal.TextColor3 = GREEN
    else
        tgtVal.Text      = "none"
        tgtVal.TextColor3 = TXTD
    end

    -- Deflect label
    local isDeflecting = curTarget and deflecting[curTarget] or false
    deVal.Text       = isDeflecting and "YES" or "NO"
    deVal.TextColor3 = isDeflecting and RED or GREEN

    -- FastMelee status
    fmVal.Text       = (getgenv().Config.FastMelee or getgenv().Config.FastFire) and "ACTIVE" or "OFF"
    fmVal.TextColor3 = (getgenv().Config.FastMelee or getgenv().Config.FastFire) and GREEN or TXTD
end)

-- ═══════════════════════════════════════════════════════════════
-- DONE
-- ═══════════════════════════════════════════════════════════════
print("[ʟᴜғғʏ's Ragebot v2] Loaded")
print("[ʟᴜғғʏ's Ragebot v2] FastMelee + FastFire integrated from extracted-code_1.txt")
print("[ʟᴜғғʏ's Ragebot v2] Ragebot core from ragebot_ui.txt + ragebot_Hardened.txt")
print("[ʟᴜғғʏ's Ragebot v2] Toggle: RightBracket ] or button")
