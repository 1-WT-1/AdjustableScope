local ModVersion = "0.1.0"
local UEHelpers = require("UEHelpers")

print(string.format("[AdjustableScope] v%s Initializing...", ModVersion))

local ScriptDir = debug.getinfo(1).source:match("@?(.*[\\/])") or ""


-- Helpers
local function IsValid(obj)
    if not obj then return false end
    if type(obj) == "userdata" and type(obj.IsValid) == "function" then
        return obj:IsValid()
    end
    return false
end

local function GetVelocityInMetersPerSec(rawVel)
    if not rawVel or type(rawVel) ~= "number" or rawVel <= 0 then return 800.0 end
    return (rawVel > 5000) and (rawVel / 100.0) or rawVel
end

local _print = print
local print = function(msg)
    _print(tostring(msg) .. "\n")
end


-- State Variables
local CfgSteppedZoomMode = true
local ZoomStep = 1.0
local DynamicMinZoom = 0.5
local DynamicMaxZoom = 32.0

local CfgZoomStages = {}
local CfgZeroStages = {}

local function ParseStageString(str)
    local list = {}
    if not str or str == "" then return nil end
    for numStr in str:gmatch("[^,]+") do
        local n = tonumber(numStr:match("^%s*(.-)%s*$"))
        if n and n >= 0 then
            table.insert(list, n)
        end
    end
    if #list > 0 then
        table.sort(list)
        return list
    end
    return nil
end

local CurrentZeroIndex = 1
local CurrentZoomLevel = nil
local BaseMagnification = nil
local LastWeaponName = nil
local CurrentZoomStageIndex = 1
local ActiveZoomStages = nil
local ActiveZeroStages = nil
local WasAiming = false
local DualZeroMode = false -- false = dual controls Zoom, true = dual controls Zero

local HUDInjected = false
local ScopeTextBlock = nil
local ScopeHorizontalBox = nil

-- DEFAULT 
-- Dedicated keys
local CfgDedicatedZoomIn  = "OEM_PLUS"
local CfgDedicatedZoomOut = "OEM_MINUS"
local CfgDedicatedZeroUp  = "PAGE_UP"
local CfgDedicatedZeroDown = "PAGE_DOWN"

-- Dual-use keys
local CfgDualUp     = "XBUTTON_TWO"
local CfgDualDown   = "XBUTTON_ONE"
local CfgDualSwitch = "CAPS_LOCK"

-- Reset key
local CfgClearKey = "F1"

-- Whether to remember zoom/zero state when leaving ADS (true = remember, false = clear on exit)
local CfgSaveStateOnADS = true

-- Zeroing settings
local CfgEnableZeroing = true
local CfgIgnoreRockets = true
local CfgMaxPitchAngle = 3.5

-- HUD overlay settings
local CfgShowHUD = true
local CfgShowWithoutEquippedHUD = true

-- Audio feedback settings
local CfgEnableSound = true
local CfgSoundVolume = 0.5

-- Debug logging setting
local CfgDebug = false

local function dprint(msg)
    if CfgDebug then
        print(msg)
    end
end

local function LoadConfig()
    local configPath = ScriptDir .. "../config.ini"
    local file = io.open(configPath, "r")
    if not file then
        configPath = ScriptDir .. "config.ini"
        file = io.open(configPath, "r")
    end
    if not file then return end
    
    local section = nil
    for line in file:lines() do
        if not line:match("^%s*[#;]") and line:match("%S") then
            local s = line:match("^%s*%[([^%]]+)%]")
            if s then
                section = s
            else
                local key, val = line:match("^%s*([^=]+)%s*=%s*(.*)")
                if key and val then
                    key = key:match("^%s*(.-)%s*$")
                    val = val:gsub("%s+[#;].*$", ""):match("^%s*(.-)%s*$")
                    local num = tonumber(val)
                    if key == "Debug" then
                        CfgDebug = (val:lower() == "true" or val == "1")
                    end
                    if section == "ZoomSettings" then
                        if key == "UseSteppedZoom" or key == "SteppedZoomMode" then
                            CfgSteppedZoomMode = (val:lower() ~= "false" and val ~= "0")
                        end
                        if (key == "DynamicZoomStep" or key == "ZoomStep") and num then ZoomStep = num end
                        if (key == "DynamicMinZoom" or key == "MinZoom") and num then DynamicMinZoom = num end
                        if (key == "DynamicMaxZoom" or key == "MaxZoom") and num then DynamicMaxZoom = num end
                    elseif section == "ZoomStages" then
                        local threshold = tonumber(key)
                        local parsed = ParseStageString(val)
                        if threshold and parsed then
                            table.insert(CfgZoomStages, { threshold = threshold, values = parsed })
                        end
                    elseif section == "ZeroStages" then
                        local threshold = tonumber(key)
                        local parsed = ParseStageString(val)
                        if threshold and parsed then
                            table.insert(CfgZeroStages, { threshold = threshold, values = parsed })
                        end
                    elseif section == "ZeroingSettings" then
                        if key == "EnableZeroing" then
                            CfgEnableZeroing = (val:lower() ~= "false" and val ~= "0")
                        end
                        if key == "IgnoreRockets" then
                            CfgIgnoreRockets = (val:lower() ~= "false" and val ~= "0")
                        end
                        if key == "MaxPitchAngle" and num then
                            CfgMaxPitchAngle = num
                        end
                    elseif section == "Audio" then
                        if key == "EnableSound" then
                            CfgEnableSound = (val:lower() ~= "false" and val ~= "0")
                        end
                        if key == "SoundVolume" and num then
                            CfgSoundVolume = num
                        end
                    elseif section == "HUD" then
                        if key == "ShowHUD" then
                            CfgShowHUD = (val:lower() ~= "false" and val ~= "0")
                        end
                        if key == "ShowWithoutEquippedHUD" or key == "ShowWithoutHUD" then
                            CfgShowWithoutEquippedHUD = (val:lower() ~= "false" and val ~= "0")
                        end
                    elseif section == "Keybinds" then
                        local valLower = val:lower()
                        local keyVal = (val ~= "" and valLower ~= "none" and valLower ~= "off" and valLower ~= "disabled" and valLower ~= "nil") and val or nil
                        if key == "DedicatedZoomInKey"  then CfgDedicatedZoomIn  = keyVal end
                        if key == "DedicatedZoomOutKey" then CfgDedicatedZoomOut = keyVal end
                        if key == "DedicatedZeroUpKey"  then CfgDedicatedZeroUp  = keyVal end
                        if key == "DedicatedZeroDownKey" then CfgDedicatedZeroDown = keyVal end
                        if key == "DualUpKey"     then CfgDualUp     = keyVal end
                        if key == "DualDownKey"   then CfgDualDown   = keyVal end
                        if key == "DualSwitchKey" then CfgDualSwitch = keyVal end
                        if key == "ClearKey"      then CfgClearKey   = keyVal end
                        if key == "SaveStateOnADS" then
                            CfgSaveStateOnADS = (val:lower() ~= "false" and val ~= "0")
                        end
                    end
                end
            end
        end
    end
    file:close()
    
    table.sort(CfgZoomStages, function(a, b) return a.threshold < b.threshold end)
    table.sort(CfgZeroStages, function(a, b) return a.threshold < b.threshold end)
    
    print(string.format("[AdjustableScope] Loaded config: ZoomStep=%.1f | Dedicated: ZoomIn=%s ZoomOut=%s ZeroUp=%s ZeroDown=%s | Dual: Up=%s Down=%s Switch=%s",
        ZoomStep,
        CfgDedicatedZoomIn or "NONE", CfgDedicatedZoomOut or "NONE",
        CfgDedicatedZeroUp or "NONE", CfgDedicatedZeroDown or "NONE",
        CfgDualUp or "NONE", CfgDualDown or "NONE", CfgDualSwitch or "NONE"))
end

LoadConfig()

-- HUD Visibility Check
local function IsInGameHUDActive(Pawn)
    if not CfgShowHUD then return false end
    if CfgShowWithoutEquippedHUD then return true end
    
    local hasHUD = false
    local succ, err = pcall(function()
        local HUD = FindFirstOf("HUD_Widget_C")
        if IsValid(HUD) then
            local R81 = HUD.RetainerBox_81
            if IsValid(R81) then
                hasHUD = (R81:GetVisibility() == 0)
            end
        end
    end)
    if not succ then
        print("[AdjustableScope ERROR] IsInGameHUDActive failed: " .. tostring(err))
    end
    return hasHUD
end
local function TryInjectHUD()
    if HUDInjected and IsValid(ScopeTextBlock) then return end
    
    local HUD = FindFirstOf("HUD_Widget_C")
    if not IsValid(HUD) then return end
    
    local succ, err = pcall(function()

        local WidgetTree = HUD.WidgetTree
        if not IsValid(WidgetTree) then
            print("[AdjustableScope ERROR] TryInjectHUD: WidgetTree is invalid")
            return
        end

        local SourceTB = HUD.TextBlock_AmmoCounter
        if not IsValid(SourceTB) then
            print("[AdjustableScope ERROR] TryInjectHUD: TextBlock_AmmoCounter is invalid")
            return
        end

        local TextBlockClass = StaticFindObject("/Script/UMG.TextBlock")
        if not IsValid(TextBlockClass) then
            print("[AdjustableScope ERROR] TryInjectHUD: UMG.TextBlock class not found")
            return
        end

        local TargetCanvas = WidgetTree.RootWidget
        local R81 = HUD.RetainerBox_81
        if IsValid(R81) and R81.GetContent then
            local SizeBox = R81:GetContent()
            if IsValid(SizeBox) and SizeBox.GetContent then
                local CanvasEffects = SizeBox:GetContent()
                if IsValid(CanvasEffects) then
                    TargetCanvas = CanvasEffects
                end
            end
        end

        -- Destroy leftovers
        local succCleanup, errCleanup = pcall(function()
            if not IsValid(TargetCanvas) or not TargetCanvas.GetChildrenCount then return end
            local count = TargetCanvas:GetChildrenCount()
            if count and type(count) == "number" and count > 0 then
                for i = count - 1, 0, -1 do
                    local child = TargetCanvas:GetChildAt(i)
                    if IsValid(child) then
                        local name = child:GetFullName()
                        if name and (name:find("ScopeHorizontalBox") or name:find("ScopeStatusText")) then
                            child:RemoveFromParent()
                        end
                    end
                end
            end
        end)
        if not succCleanup then
            dprint("[AdjustableScope DEBUG] TryInjectHUD leftover cleanup notice: " .. tostring(errCleanup))
        end
        
        local succTB, errTB = pcall(function()
            local TB = StaticConstructObject(TextBlockClass, WidgetTree, FName("ScopeStatusText"))
            if not IsValid(TB) then
                print("[AdjustableScope ERROR] TryInjectHUD: Failed to construct ScopeStatusText")
                return
            end

            local fontInfo = SourceTB.Font
            if fontInfo then
                fontInfo.Size = 15
                TB:SetFont(fontInfo)
            end
            TB:SetColorAndOpacity(SourceTB.ColorAndOpacity)
            TB:SetText(FText("ZOOM: -- | ZERO: ---"))

            local HBoxClass = StaticFindObject("/Script/UMG.HorizontalBox")
            if IsValid(HBoxClass) then
                local HBox = StaticConstructObject(HBoxClass, WidgetTree, FName("ScopeHorizontalBox"))
                if IsValid(HBox) then
                    local HSlot = TargetCanvas:AddChildToCanvas(HBox)
                    if IsValid(HSlot) then
                        HSlot:SetAnchors({Minimum = {X = 0.5, Y = 0.82}, Maximum = {X = 0.5, Y = 0.82}})
                        HSlot:SetAlignment({X = 0.5, Y = 0.5})
                        HSlot:SetPosition({X = 0.0, Y = 0.0})
                        HSlot:SetSize({X = 350.0, Y = 40.0})
                        
                        local TSlot = HBox:AddChildToHorizontalBox(TB)
                        if IsValid(TSlot) and TSlot.SetVerticalAlignment then
                            TSlot:SetVerticalAlignment(1)
                        end
                        
                        ScopeTextBlock = TB
                        ScopeHorizontalBox = HBox
                        HUDInjected = true
                        print("[AdjustableScope] HUD overlay injected successfully.")
                    end
                else
                    print("[AdjustableScope ERROR] TryInjectHUD: Failed to construct ScopeHorizontalBox")
                end
            else
                print("[AdjustableScope ERROR] TryInjectHUD: UMG.HorizontalBox class not found")
            end
        end)
        if not succTB then
            print("[AdjustableScope ERROR] TryInjectHUD UI construction failed: " .. tostring(errTB))
        end
    end)
    if not succ then
        print("[AdjustableScope ERROR] TryInjectHUD failed: " .. tostring(err))
    end
end

local function UpdateHUDText()
    if not ScopeTextBlock or not ScopeTextBlock:IsValid() then return end
    local zoomVal = CurrentZoomLevel or 1.0
    local zeroVal = (ActiveZeroStages and ActiveZeroStages[CurrentZeroIndex]) or 0
    local zeroStr = (zeroVal == 0) and "NO" or string.format("%dm", zeroVal)
    local str
    if DualZeroMode then
        str = string.format("ZOOM: %.1fx  |  [ZERO: %s]", zoomVal, zeroStr)
    else
        str = string.format("[ZOOM: %.1fx]  |  ZERO: %s", zoomVal, zeroStr)
    end
    pcall(function() ScopeTextBlock:SetText(FText(str)) end)
end

local function SetHUDVisible(visible)
    if IsValid(ScopeHorizontalBox) then
        pcall(function() ScopeHorizontalBox:SetVisibility(visible and 0 or 2) end)
    end
end


-- Audio 
local HardcodedClickSoundPath = "/Game/Assets/Sounds/UI_Sounds/Click_Standard_05.Click_Standard_05"
local CachedClickSound = nil

local function PlayClickSound(direction, hitLimit)
    if not CfgEnableSound then return end
    pcall(function()
        if not IsValid(CachedClickSound) then
            CachedClickSound = StaticFindObject(HardcodedClickSoundPath)
        end
        if IsValid(CachedClickSound) then
            local PC = nil
            pcall(function() PC = UEHelpers.GetPlayerController() end)
            if PC and PC.ClientPlaySound then
                local pitch = 1.0
                if hitLimit then
                    pitch = 0.5 -- Dull thud for hitting the limit
                else
                    if direction and direction > 0 then pitch = 1.08
                    elseif direction and direction < 0 then pitch = 0.92 end
                end
                PC:ClientPlaySound(CachedClickSound, CfgSoundVolume, pitch)
            end
        end
    end)
end

-- Config Scope Zoom Stages
local ActiveZoomStages = { 1.0 }
local CurrentZoomStageIndex = 1

local function GenerateZoomStagesForWeapon(weapon, pawn)
    local base = BaseMagnification or (weapon and weapon.Magnification) or (pawn and pawn.WepMagnification) or 1.0
    if base < 1.0 then base = 1.0 end
    local isScoped = (weapon and weapon.Scope == true)

    local activeMultipliers = { 1.0, 1.5, 2.0 } -- default fallback
    for _, configStage in ipairs(CfgZoomStages) do
        if not isScoped or base <= configStage.threshold then
            activeMultipliers = configStage.values
            break
        end
    end

    local stages = {}
    local seen = {}

    for _, mult in ipairs(activeMultipliers) do
        local stg = math.floor(base * mult * 10) / 10.0
        if not seen[stg] then
            seen[stg] = true
            table.insert(stages, stg)
        end
    end

    if #stages == 0 then
        table.insert(stages, base)
    end

    table.sort(stages)
    return stages
end

local function GenerateZeroStagesForWeapon(weapon, pawn)
    local base = BaseMagnification or (weapon and weapon.Magnification) or (pawn and pawn.WepMagnification) or 1.0
    if base < 1.0 then base = 1.0 end
    local isScoped = (weapon and weapon.Scope == true)

    local stages = { 0, 100, 200, 300, 400, 500 } -- default fallback
    for _, configStage in ipairs(CfgZeroStages) do
        if not isScoped or base <= configStage.threshold then
            stages = configStage.values
            break
        end
    end

    if #stages == 0 then
        stages = { 0 }
    end
    
    return stages
end


-- Zoom & Zero 
local function ApplyScopeZoom(Pawn, Direction)
    pcall(function()
        local weapon = Pawn.EquipedItem
        if not weapon or not weapon:IsValid() then return end

        local hitLimit = false
        if CfgSteppedZoomMode then
            local oldIndex = CurrentZoomStageIndex
            CurrentZoomStageIndex = CurrentZoomStageIndex + Direction
            if CurrentZoomStageIndex < 1 then CurrentZoomStageIndex = 1 end
            if CurrentZoomStageIndex > #ActiveZoomStages then CurrentZoomStageIndex = #ActiveZoomStages end
            
            hitLimit = (oldIndex == CurrentZoomStageIndex)
            CurrentZoomLevel = ActiveZoomStages[CurrentZoomStageIndex]
        else
            local base = BaseMagnification or DynamicMinZoom
            local oldZoom = CurrentZoomLevel or base
            local newZoom = oldZoom + (Direction * ZoomStep)
            if newZoom < DynamicMinZoom then newZoom = DynamicMinZoom end
            if newZoom > DynamicMaxZoom then newZoom = DynamicMaxZoom end
            
            hitLimit = (oldZoom == newZoom)
            CurrentZoomLevel = newZoom
        end

        Pawn.WepMagnification = CurrentZoomLevel
        if Pawn.FovZoom then
            Pawn:FovZoom()
        end
        
        print(string.format("[AdjustableScope] Scope Zoom -> %.1fx (Stage %d/%d)",
            CurrentZoomLevel, CurrentZoomStageIndex, #ActiveZoomStages))
            
        PlayClickSound(Direction, hitLimit)
        UpdateHUDText()
    end)
end

local function GetDynamicHeightOverBore(weapon)
    local hobMeters = 0.07 -- Default 7cm fallback
    if not IsValid(weapon) then return hobMeters end
    
    local succ, err = pcall(function()
        local aimOffset = weapon.AimOffset
        local aimOffsetZ = nil
        if aimOffset and aimOffset.Translation then
            aimOffsetZ = aimOffset.Translation.Z
        end
        
        local arrowDiffZ = nil
        if IsValid(weapon.Arrow_Muzzle) and IsValid(weapon.Arrow_Aim) then
            local mWorld = weapon.Arrow_Muzzle:K2_GetComponentLocation()
            local aWorld = weapon.Arrow_Aim:K2_GetComponentLocation()
            local upVector = weapon:GetActorUpVector()
            
            if mWorld and aWorld and upVector then
                local dx = aWorld.X - mWorld.X
                local dy = aWorld.Y - mWorld.Y
                local dz = aWorld.Z - mWorld.Z
                arrowDiffZ = (dx * upVector.X) + (dy * upVector.Y) + (dz * upVector.Z)
            end
        end
        
        local finalCm = 7.0
        if arrowDiffZ and arrowDiffZ > 0 and arrowDiffZ < 50.0 then
            finalCm = arrowDiffZ
        elseif aimOffsetZ and aimOffsetZ > 0 and aimOffsetZ < 50.0 then
            finalCm = aimOffsetZ
        end
        
        hobMeters = finalCm / 100.0
    end)
    
    if not succ then
        print("[AdjustableScope ERROR] Failed to calculate dynamic HoB: " .. tostring(err))
    end
    
    return hobMeters
end

local function CalculateZeroPitch(MuzzleVelocity, ZeroDistanceMeters, DragCoeff, HeightOverBoreMeters)
    local v = GetVelocityInMetersPerSec(MuzzleVelocity)
    local d = ZeroDistanceMeters
    if d <= 0 or v <= 0 then return 0.0 end
    
    local g = 9.81
    local t = d / v
    
    local k = (DragCoeff and type(DragCoeff) == "number" and DragCoeff > 0) and DragCoeff or 0.00012
    
    local maxDist = v / k
    if d >= maxDist * 0.99 then
        d = maxDist * 0.99
    end
    
    local effectiveTime = -math.log(1 - (k * d / v)) / k
    
    local drop = 0.5 * g * (effectiveTime * effectiveTime)
    
    local totalVerticalAdj = drop + (HeightOverBoreMeters or 0.07)
    
    local pitchRad = math.atan(totalVerticalAdj / ZeroDistanceMeters)
    local pitchDeg = math.deg(pitchRad)
    
    dprint(string.format("[AdjustableScope DRAG] Dist: %dm | BaseVel: %.1fm/s | HoB: %.1fcm | FlightTime: %.3fs | ZeroPitch: +%.2f deg",
        ZeroDistanceMeters, v, (HeightOverBoreMeters or 0.07) * 100, effectiveTime, pitchDeg))
        
    return pitchDeg
end

local function ApplyScopeZeroing(Pawn, Direction)
    if not Pawn or not Pawn:IsValid() then return end
    
    if not ActiveZeroStages then return end
    
    local oldIndex = CurrentZeroIndex
    CurrentZeroIndex = CurrentZeroIndex + Direction
    if CurrentZeroIndex < 1 then CurrentZeroIndex = 1 end
    if CurrentZeroIndex > #ActiveZeroStages then CurrentZeroIndex = #ActiveZeroStages end
    
    local hitLimit = (oldIndex == CurrentZeroIndex)
    local targetDist = ActiveZeroStages[CurrentZeroIndex]
    
    pcall(function()
        local weapon = Pawn.EquipedItem
        if IsValid(weapon) then
            pcall(function()
                local aimOffset = weapon.AimOffset
                if aimOffset and aimOffset.Translation then
                    dprint(string.format("[AdjustableScope HoB DEBUG] AimOffset Z: %.2f", aimOffset.Translation.Z))
                end
                if IsValid(weapon.Arrow_Muzzle) and IsValid(weapon.Arrow_Aim) then
                    local mLoc = weapon.Arrow_Muzzle:K2_GetComponentLocation()
                    local aLoc = weapon.Arrow_Aim:K2_GetComponentLocation()
                    dprint(string.format("[AdjustableScope HoB DEBUG] MuzzleZ: %.2f | AimZ: %.2f | Diff: %.2f", mLoc.Z, aLoc.Z, aLoc.Z - mLoc.Z))
                end
            end)
            if targetDist == 0 then
                print("[AdjustableScope] Zero -> NO (game default, no pitch applied)")
            else
                local muzzleVel = weapon.Muzzle_Velocity
                local dynamicHob = GetDynamicHeightOverBore(weapon)
                local pitchOffset = CalculateZeroPitch(muzzleVel, targetDist, nil, dynamicHob)
                print(string.format("[AdjustableScope] Zero Changed -> %dm | MuzzleVel: %.1f m/s | Applied Pitch: +%.2f deg | HoB: %.1fcm | Weapon: %s",
                    targetDist, GetVelocityInMetersPerSec(muzzleVel), pitchOffset, dynamicHob * 100, weapon:GetFullName()))
            end
            PlayClickSound(Direction, hitLimit)
            UpdateHUDText()
        else
            dprint("[AdjustableScope DEBUG] Pawn has no valid EquipedItem!")
        end
    end)
end


-- Keybind Registration
local function GetAimingPawn()
    local PC = nil
    pcall(function() PC = UEHelpers.GetPlayerController() end)
    if not PC or not IsValid(PC.Pawn) then return nil end
    local Pawn = PC.Pawn
    local isAiming = false
    pcall(function() isAiming = (Pawn.Aiming == true) end)
    if not isAiming then return nil end
    return Pawn
end

local function GetKey(name)
    if name and name ~= "" and Key and Key[name] then return Key[name] end
    return nil
end

local function Bind(key, fn)
    if key then pcall(function() RegisterKeyBind(key, fn) end) end
end

-- Dedicated keys
Bind(GetKey(CfgDedicatedZoomIn),   function() ApplyScopeZoom(GetAimingPawn(), 1) end)
Bind(GetKey(CfgDedicatedZoomOut),  function() ApplyScopeZoom(GetAimingPawn(), -1) end)
Bind(GetKey(CfgDedicatedZeroUp),   function() ApplyScopeZeroing(GetAimingPawn(), 1) end)
Bind(GetKey(CfgDedicatedZeroDown), function() ApplyScopeZeroing(GetAimingPawn(), -1) end)

-- Dual-use keys
Bind(GetKey(CfgDualSwitch), function()
    local Pawn = GetAimingPawn()
    if not Pawn then return end
    DualZeroMode = not DualZeroMode
    print(string.format("[AdjustableScope] Dual Mode -> %s", DualZeroMode and "ZERO" or "ZOOM"))
    PlayClickSound(0)
    UpdateHUDText()
end)

Bind(GetKey(CfgDualUp), function()
    local Pawn = GetAimingPawn()
    if not Pawn then return end
    if DualZeroMode then ApplyScopeZeroing(Pawn, 1)
    else ApplyScopeZoom(Pawn, 1) end
end)

Bind(GetKey(CfgDualDown), function()
    local Pawn = GetAimingPawn()
    if not Pawn then return end
    if DualZeroMode then ApplyScopeZeroing(Pawn, -1)
    else ApplyScopeZoom(Pawn, -1) end
end)

local function ResetToDefaultBaseStage()
    if not BaseMagnification or not ActiveZoomStages then return end
    CurrentZoomStageIndex = 1
    for idx, stg in ipairs(ActiveZoomStages) do
        if math.abs(stg - BaseMagnification) < 0.1 then
            CurrentZoomStageIndex = idx
            break
        end
    end
    CurrentZoomLevel = ActiveZoomStages[CurrentZoomStageIndex] or BaseMagnification
end

--Clear key
Bind(GetKey(CfgClearKey), function()
    local Pawn = GetAimingPawn()
    if Pawn and BaseMagnification then
        CurrentZeroIndex = 1
        ResetToDefaultBaseStage()
        pcall(function()
            Pawn.WepMagnification = CurrentZoomLevel
            if Pawn.FovZoom then Pawn:FovZoom() end
        end)
        print("[AdjustableScope] Clear -> Zoom reset to default base stage (1.0x multiplier), Zero reset to NO")
        PlayClickSound(-1)
        UpdateHUDText()
    end
end)


-- Main Game Thread Loop
LoopInGameThreadWithDelay(16, function()
    local PC = nil
    pcall(function() PC = UEHelpers.GetPlayerController() end)
    if not IsValid(PC) then return true end
    
    local Pawn = PC.Pawn
    if not IsValid(Pawn) then return true end
    
    local isAiming = false
    pcall(function() isAiming = (Pawn.Aiming == true) end)
    
    if isAiming then
        if not WasAiming then
            WasAiming = true
            TryInjectHUD()
            
            local succWep, errWep = pcall(function()
                local weapon = Pawn.EquipedItem
                local wName = IsValid(weapon) and weapon:GetFullName() or "None"
                
                if wName ~= LastWeaponName then
                    LastWeaponName = wName
                    BaseMagnification = Pawn.WepMagnification or 1.0
                    ActiveZoomStages = GenerateZoomStagesForWeapon(weapon, Pawn)
                    ActiveZeroStages = GenerateZeroStagesForWeapon(weapon, Pawn)
                    ResetToDefaultBaseStage()
                    CurrentZeroIndex = 1
                end
            end)
            if not succWep then
                print("[AdjustableScope ERROR] Main Loop weapon check failed: " .. tostring(errWep))
            end
            
            -- Re-apply current saved zoom level when entering ADS
            if CurrentZoomLevel and ActiveZoomStages and CfgSaveStateOnADS then
                local succZ, errZ = pcall(function()
                    Pawn.WepMagnification = CurrentZoomLevel
                    if Pawn.FovZoom then Pawn:FovZoom() end
                end)
                if not succZ then
                    print("[AdjustableScope ERROR] Main Loop zoom re-apply failed: " .. tostring(errZ))
                end
            end
            
            if IsInGameHUDActive(Pawn) then
                SetHUDVisible(true)
                UpdateHUDText()
            else
                SetHUDVisible(false)
            end
        end
    else
        if WasAiming then
            WasAiming = false
            SetHUDVisible(false)

            if not CfgSaveStateOnADS then
                -- wipe saved zoom and zeroing on ADS exit
                CurrentZeroIndex = 1
                ResetToDefaultBaseStage()
                dprint("[AdjustableScope] ADS exit: state cleared (SaveStateOnADS = false)")
            end

            -- Restore base FOV on exiting ADS
            if BaseMagnification then
                local succFov, errFov = pcall(function()
                    Pawn.WepMagnification = BaseMagnification
                    if Pawn.FovZoom then Pawn:FovZoom() end
                end)
                if not succFov then
                    print("[AdjustableScope ERROR] Main Loop base FOV restore failed: " .. tostring(errFov))
                end
            end
        end
    end
    
    return true
end)

-- Cleanup
local function ResetModState()
    if IsValid(ScopeHorizontalBox) then
        pcall(function() ScopeHorizontalBox:RemoveFromParent() end)
    end
    HUDInjected = false
    ScopeTextBlock = nil
    ScopeHorizontalBox = nil
    WasAiming = false
    CurrentZoomLevel = nil
    BaseMagnification = nil
    PendingZoomDelta = 0
    PendingZeroDelta = 0
end

RegisterHook("/Script/Engine.PlayerController:ClientRestart", function()
    ResetModState()
end)

RegisterHook("/Script/Engine.PlayerController:ClientTravel", function()
    ResetModState()
end)


local function IsOwnedByLocalPlayer(Obj)
    local objName = "Unknown"
    pcall(function() objName = Obj:GetFullName() end)
    local className = objName:match("^([^%s]+)") or objName

    local PC = nil
    pcall(function() PC = UEHelpers.GetPlayerController() end)
    local Pawn = PC and PC.Pawn
    if not IsValid(Pawn) or not IsValid(Obj) then
        print(string.format("[AdjustableScope ERROR] IsOwnedByLocalPlayer: Invalid Pawn or Obj (%s)", className))
        return false
    end
    
    local inst = nil
    pcall(function() inst = Obj.Instigator end)
    
    if IsValid(inst) then
        local instName = ""
        local pawnName = ""
        pcall(function() instName = inst:GetFullName() end)
        pcall(function() pawnName = Pawn:GetFullName() end)
        
        if instName == pawnName and instName ~= "" then
            return true
        else
            print(string.format("[AdjustableScope ERROR] Bullet rejected (%s): Instigator mismatch. Inst: %s | Pawn: %s", className, instName, pawnName))
        end
    else
        print(string.format("[AdjustableScope ERROR] Bullet rejected (%s): No valid Instigator property found on spawn.", className))
    end
    
    return false
end

local function HandleNewProjectile(Actor)
    local status, err = pcall(function()
        if not IsValid(Actor) then return end
        local fullPath = Actor:GetFullName()
        local className = fullPath:match("^([^%s]+)") or "Unknown"

        dprint("[AdjustableScope DEBUG] Bullet spawn detected: " .. className)

        if not CfgEnableZeroing or CurrentZeroIndex <= 1 then return end

        if not IsOwnedByLocalPlayer(Actor) then return end

        local PC = nil
        pcall(function() PC = UEHelpers.GetPlayerController() end)
        local Pawn = PC and PC.Pawn
        if not IsValid(Pawn) then
            print(string.format("[AdjustableScope ERROR] Bullet rejected (%s): Invalid Pawn", className))
            return
        end
        
        local isAiming = false
        pcall(function() isAiming = (Pawn.Aiming == true) end)
        if not isAiming then
            dprint("[AdjustableScope DEBUG] Bullet fired while hipfiring -> Skipping zero pitch boost")
            return
        end
        
        -- Rocket / Submunition check (case-insensitive)
        local lowerPath = fullPath:lower()
        if lowerPath:find("bomblet") or (CfgIgnoreRockets and (lowerPath:find("rocket") or lowerPath:find("rpg") or lowerPath:find("missile"))) then
            dprint(string.format("[AdjustableScope DEBUG] Submunition or rocket projectile detected (%s) -> Skipping zero pitch boost", className))
            return
        end
        
        local targetDist = (ActiveZeroStages and ActiveZeroStages[CurrentZeroIndex]) or 0
        if targetDist == 0 then return end -- 0 skip bullet boost

        local vel = nil
        pcall(function() vel = Actor.Velocity end)
        
        local vX, vY, vZ = 0, 0, 0
        if vel then
            vX = type(vel.X) == "number" and vel.X or 0
            vY = type(vel.Y) == "number" and vel.Y or 0
            vZ = type(vel.Z) == "number" and vel.Z or 0
        end

        -- If horizontal velocity is 0, the engine hasn't fully launched the bullet yet
        if vX == 0 and vY == 0 then
            local succRot, errRot = pcall(function()
                local rot = Actor:K2_GetActorRotation()
                local weapon = Pawn.EquipedItem
                if rot then
                    local speedCmS = 0
                    
                    -- read intended speed
                    local succSpeed, errSpeed = pcall(function()
                        if Actor.ProjectileMovement and Actor.ProjectileMovement.InitialSpeed and type(Actor.ProjectileMovement.InitialSpeed) == "number" and Actor.ProjectileMovement.InitialSpeed > 0 then
                            speedCmS = Actor.ProjectileMovement.InitialSpeed
                            dprint(string.format("[AdjustableScope DEBUG] Read InitialSpeed from ProjectileMovement: %.1f", speedCmS))
                        end
                    end)
                    if not succSpeed then
                        print(string.format("[AdjustableScope ERROR] (%s) InitialSpeed check failed: %s", className, tostring(errSpeed)))
                    end
                    
                    -- Fallback to the weapon's base stats if we couldn't read InitialSpeed
                    if speedCmS == 0 then
                        if IsValid(weapon) and weapon.Muzzle_Velocity then
                            speedCmS = GetVelocityInMetersPerSec(weapon.Muzzle_Velocity) * 100.0
                            dprint(string.format("[AdjustableScope DEBUG] Fell back to weapon.Muzzle_Velocity: %.1f", speedCmS))
                        else
                            print(string.format("[AdjustableScope ERROR] (%s) Could not read weapon.Muzzle_Velocity fallback!", className))
                        end
                    end
                    
                    if speedCmS > 0 then
                        local pRad = math.rad(rot.Pitch)
                        local yRad = math.rad(rot.Yaw)
                        local cp = math.cos(pRad)
                        vX = cp * math.cos(yRad) * speedCmS
                        vY = cp * math.sin(yRad) * speedCmS
                        vZ = math.sin(pRad) * speedCmS
                        dprint(string.format("[AdjustableScope DEBUG] Reconstructed missing velocity from spawn rotation (Speed: %.1f cm/s)", speedCmS))
                    else
                        print(string.format("[AdjustableScope ERROR] (%s) Failed to reconstruct velocity: Speed was 0.", className))
                    end
                else
                    print(string.format("[AdjustableScope ERROR] (%s) Failed to reconstruct velocity: Actor:K2_GetActorRotation() returned nil.", className))
                end
            end)
            if not succRot then
                print(string.format("[AdjustableScope ERROR] (%s) Velocity reconstruction failed: %s", className, tostring(errRot)))
            end
        end

        if vX == 0 and vY == 0 and vZ == 0 then
            print(string.format("[AdjustableScope ERROR] Bullet rejected (%s): Velocity vector is 0,0,0 and couldn't be reconstructed.", className))
            return
        end
        
        local M = math.sqrt(vX * vX + vY * vY + vZ * vZ)
        local vXy = math.sqrt(vX * vX + vY * vY)

        if vXy == 0 or M == 0 then
            print(string.format("[AdjustableScope ERROR] Bullet rejected (%s): Magnitudes zero. (X: %.4f, Y: %.4f, Z: %.4f, vXy: %.4f, M: %.4f)", className, vX, vY, vZ, vXy, M))
            return
        end
        
        dprint("[AdjustableScope DEBUG] Bullet accepted! Calculating pitch...")
        local actualVelMetersPerSec = M / 100.0

        -- Fallback if initial velocity is near zero (dropped item)
        if actualVelMetersPerSec < 10.0 then
            local weapon = Pawn.EquipedItem
            if IsValid(weapon) and weapon.Muzzle_Velocity then
                actualVelMetersPerSec = GetVelocityInMetersPerSec(weapon.Muzzle_Velocity)
            else
                actualVelMetersPerSec = 800.0
            end
        end

        -- Extract bullet drag coefficient
        local bulletDrag = nil
        pcall(function()
            if Actor.DragConstantTerm and type(Actor.DragConstantTerm) == "number" then
                bulletDrag = Actor.DragConstantTerm
            end
        end)
        local weapon = Pawn.EquipedItem
        local dynamicHob = GetDynamicHeightOverBore(weapon)
        local pitchOffset = CalculateZeroPitch(actualVelMetersPerSec, targetDist, bulletDrag, dynamicHob)

        -- Pitch clamp
        if pitchOffset > CfgMaxPitchAngle then
            pitchOffset = CfgMaxPitchAngle
        end

        local currentPitch = math.atan(vel.Z / vXy)
        local rad = math.rad(pitchOffset)
        local newPitch = currentPitch + rad

        local newZ = M * math.sin(newPitch)
        local newVxy = M * math.cos(newPitch)
        local scaleXY = newVxy / vXy

        local oldZ = vel.Z
        Actor.Velocity = { X = vel.X * scaleXY, Y = vel.Y * scaleXY, Z = newZ }
        dprint(string.format("[AdjustableScope BULLET BOOST] Zero: %dm | Speed: %.1f m/s | Pitch: +%.2f deg | Vel.Z: %.1f -> %.1f | Proj: %s",
            targetDist, actualVelMetersPerSec, pitchOffset, oldZ, newZ, Actor:GetFullName()))
    end)
    if not status then
        print(string.format("[AdjustableScope ERROR] (%s) HandleNewProjectile failed: %s", className or "Unknown", tostring(err)))
    end
end


-- Projectile Hook
NotifyOnNewObject("/Script/Engine.Actor", function(Actor)
    local succ, err = pcall(function()
        local name = Actor:GetFullName()
        local lowerName = name:lower()
        if lowerName:find("proj") or lowerName:find("bullet") then
            -- Wait 1 tick for the engine to finish initializing object
            ExecuteWithDelay(1, function()
                if IsValid(Actor) then
                    HandleNewProjectile(Actor)
                end
            end)
        end
    end)
    if not succ then
        print("[AdjustableScope ERROR] NotifyOnNewObject crashed: " .. tostring(err))
    end
end)

print(string.format("[AdjustableScope] v%s Loaded Successfully.", ModVersion))
