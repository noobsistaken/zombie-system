-- Author: noobs

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Janitor = require(ReplicatedStorage.Packages.Janitor)
local Net = require(ReplicatedStorage.Net)
local ViewmodelController = require(script.Parent.ViewmodelController)
local ZombieController = require(script.Parent.ZombieController)
local ProjectileVisuals = require(script.Parent.Parent.Modules.ProjectileVisuals)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local WeaponConfig = GameConfig.Weapon
local TracerConfig = GameConfig.Tracer
local ZOOM_THRESHOLD = 1.5

local WeaponController = {}
local started = false

local ControllerJanitor = Janitor.new()

local isFiring = false
local lastFireTime = 0

local function IsInFirstPerson(): boolean
    local camera = workspace.CurrentCamera
    if not camera then
        return false
    end
    local dist = (camera.CFrame.Position - camera.Focus.Position).Magnitude
    return dist < ZOOM_THRESHOLD
end

local function PerformLocalRaycast(origin: Vector3, direction: Vector3): number?
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Include

    local zombieFolder = workspace:FindFirstChild("Zombies")
    if not zombieFolder then
        return nil
    end

    rayParams.FilterDescendantsInstances = { zombieFolder }

    local normalizedDir = direction.Unit * WeaponConfig.MaxRaycastDistance
    local result = workspace:Raycast(origin, normalizedDir, rayParams)

    if not result or not result.Instance then
        return nil
    end

    local zombieModel = result.Instance:FindFirstAncestorOfClass("Model")
    if not zombieModel then
        return nil
    end

    local idMatch = string.match(zombieModel.Name, "Zombie_(%d+)")
    return if idMatch then tonumber(idMatch) else nil
end

local function FireShot()
    if not IsInFirstPerson() then
        return
    end

    local camera = workspace.CurrentCamera
    if not camera then
        return
    end

    local mousePos = UserInputService:GetMouseLocation()
    local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)

    ProjectileVisuals.FireTracer(ray.Origin, ray.Direction, TracerConfig)

    ViewmodelController:ApplyRecoil()

    local hitZombieId = PerformLocalRaycast(ray.Origin, ray.Direction)

    -- Optimistic kill: hide instantly on client
    if hitZombieId then
        ZombieController:ProcessLocalHit(hitZombieId)
    end

    local params = {
        Origin = ray.Origin,
        Direction = ray.Direction,
        HitZombieId = hitZombieId,
    }

    Net.Shoot.Call(params):catch(function(err)
        warn("[WeaponController] Shoot error:", err)
    end)
end

local function OnRenderStepped()
    if not isFiring then
        return
    end

    local now = os.clock()
    if now - lastFireTime >= 1 / WeaponConfig.FireRate then
        lastFireTime = now
        FireShot()
    end
end

function WeaponController.start()
    if started then
        return
    end
    started = true

    -- Zap queues confirmations until a listener is attached.
    ControllerJanitor:Add(Net.HitConfirmed.On(function(_position: Vector3) end), true)

    ControllerJanitor:Add(
        UserInputService.InputBegan:Connect(function(input, gameProcessed)
            if gameProcessed then
                return
            end
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                isFiring = true
            end
        end),
        "Disconnect"
    )

    ControllerJanitor:Add(
        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                isFiring = false
            end
        end),
        "Disconnect"
    )

    ControllerJanitor:Add(RunService.RenderStepped:Connect(OnRenderStepped), "Disconnect")

    print("[WeaponController] Started")
end

function WeaponController:Destroy()
    ControllerJanitor:Destroy()
end

return WeaponController
