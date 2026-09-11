-- Author: noobs

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Janitor = require(ReplicatedStorage.Packages.Janitor)
local Net = require(ReplicatedStorage.Net)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

export type ZombieVisual = {
    Id: number,
    Model: Model,
    CurrentPos: Vector3,
    TargetPos: Vector3,
    Velocity: Vector3,
    IsNew: boolean,
    LastSeen: number,
    IsDead: boolean,
}

export type NetworkPacket = {
    P: Vector3,
    H: number,
}

local Config = GameConfig.Zombies
local LERP_SPEED = 15
local NETWORK_TIMEOUT = 5.0
local MAX_INFERRED_SPEED = 50
local SNAP_DISTANCE = 20

local ZombieController = {}
local started = false

local ControllerJanitor = Janitor.new()

local Visuals: { [number]: ZombieVisual } = {}
local LocalKills: { [number]: boolean } = {}
local snapshotCounter: number = 0

local zombieTemplate: Model? = nil
local zombieFolder: Folder? = nil

local function LoadTemplate()
    local Assets = ReplicatedStorage:FindFirstChild("Assets")
    if Assets then
        zombieTemplate = Assets:FindFirstChild("zombie")
    end

    if not zombieTemplate then
        warn("[ZombieController] No zombie template found!")
    end
end

local function CreateVisual(id: number, position: Vector3): ZombieVisual?
    if not zombieTemplate then
        return nil
    end

    local model = zombieTemplate:Clone()
    model.Name = "Zombie_" .. tostring(id)

    local rootPart = model:FindFirstChild("HumanoidRootPart")

    for _, part in model:GetDescendants() do
        if part:IsA("BasePart") then
            part.CanCollide = false
            part.CanTouch = false
            part.CanQuery = true
            part.Size = part.Size * Config.HitboxScale

            part.Anchored = part == rootPart
        end
    end

    if rootPart and rootPart:IsA("BasePart") then
        for _, part in model:GetDescendants() do
            if part:IsA("BasePart") and part ~= rootPart then
                local weld = Instance.new("WeldConstraint")
                weld.Part0 = rootPart
                weld.Part1 = part
                weld.Parent = part
            end
        end
    end

    model:PivotTo(CFrame.new(position))
    model.Parent = zombieFolder

    local visual: ZombieVisual = {
        Id = id,
        Model = model,
        CurrentPos = position,
        TargetPos = position,
        Velocity = Vector3.zero,
        IsNew = true,
        LastSeen = os.clock(),
        IsDead = false,
    }

    return visual
end

local function DestroyVisual(id: number)
    local visual = Visuals[id]
    if visual then
        if visual.Model then
            visual.Model:Destroy()
        end
        Visuals[id] = nil
    end
    LocalKills[id] = nil
end

local function SetVisualTransparency(visual: ZombieVisual, transparency: number)
    if not visual.Model then
        return
    end
    for _, part in visual.Model:GetDescendants() do
        if part:IsA("BasePart") then
            part.Transparency = transparency
            for _, child in part:GetChildren() do
                if child:IsA("Decal") then
                    child.Transparency = transparency
                end
            end
        end
    end
end

local function UpdateVisual(visual: ZombieVisual, position: Vector3, now: number)
    -- Snapshots contain positions only; infer a bounded velocity for facing.
    local timeDelta = now - visual.LastSeen
    if timeDelta > 0.01 and timeDelta < 1.0 then
        local velocity = (position - visual.TargetPos) / timeDelta
        if velocity.Magnitude > MAX_INFERRED_SPEED then
            velocity = velocity.Unit * MAX_INFERRED_SPEED
        end
        visual.Velocity = velocity
    else
        visual.Velocity = Vector3.zero
    end

    visual.TargetPos = position
    visual.LastSeen = now
    visual.IsNew = false
    visual.IsDead = false
    SetVisualTransparency(visual, 0)
end

local function OnSnapshot(snapshot: { [number]: NetworkPacket })
    local now = os.clock()
    local receivedCount = 0

    for id, packet in snapshot do
        receivedCount += 1
        local position = packet.P
        local health = packet.H

        if LocalKills[id] then
            if health == 0 then
                DestroyVisual(id)
            end
            continue
        end

        local visual = Visuals[id]

        if health == 0 then
            if visual then
                DestroyVisual(id)
            end
            continue
        end

        if visual then
            UpdateVisual(visual, position, now)
        else
            local newVisual = CreateVisual(id, position)
            if newVisual then
                newVisual.LastSeen = now
                Visuals[id] = newVisual
            end
        end
    end

    snapshotCounter = snapshotCounter + 1
    if snapshotCounter % 30 == 0 then
        local visualCount = 0
        for _ in Visuals do
            visualCount += 1
        end
        print(string.format("[CLIENT] Received: %d | Visuals: %d", receivedCount, visualCount))
    end
end

local function MoveVisual(visual: ZombieVisual, dt: number)
    if visual.IsNew then
        visual.CurrentPos = visual.TargetPos
        visual.IsNew = false
        return
    end

    local offset = visual.TargetPos - visual.CurrentPos
    local distance = offset.Magnitude
    if distance <= SNAP_DISTANCE and distance > 0.01 then
        local step = math.min(LERP_SPEED * dt, distance)
        visual.CurrentPos = visual.CurrentPos + offset.Unit * step
    else
        visual.CurrentPos = visual.TargetPos
    end
end

local function OnRenderStepped(dt: number)
    local now = os.clock()

    local parts: { BasePart } = {}
    local cframes: { CFrame } = {}

    for id, visual in Visuals do
        if not visual.Model then
            continue
        end

        if LocalKills[id] then
            continue
        end

        if (now - visual.LastSeen) >= NETWORK_TIMEOUT then
            DestroyVisual(id)
            continue
        end

        MoveVisual(visual, dt)

        local finalPos = Vector3.new(visual.CurrentPos.X, Config.SpawnHeight, visual.CurrentPos.Z)
        local rootPart = visual.Model:FindFirstChild("HumanoidRootPart")

        if rootPart and rootPart:IsA("BasePart") then
            local targetCFrame: CFrame
            if visual.Velocity.Magnitude > 0.1 then
                targetCFrame = CFrame.lookAt(finalPos, finalPos + visual.Velocity)
            else
                targetCFrame = CFrame.new(finalPos)
            end

            table.insert(parts, rootPart)
            table.insert(cframes, targetCFrame)
        end
    end

    if #parts > 0 then
        workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
    end
end

function ZombieController:ProcessLocalHit(id: number)
    local visual = Visuals[id]
    if visual then
        SetVisualTransparency(visual, 1)
        LocalKills[id] = true
    end
end

function ZombieController.start()
    if started then
        return
    end
    started = true

    local folder = Instance.new("Folder")
    folder.Name = "Zombies"
    folder.Parent = workspace
    zombieFolder = folder
    ControllerJanitor:Add(folder, "Destroy")

    LoadTemplate()

    ControllerJanitor:Add(Net.ZombieSnapshot.On(OnSnapshot), true)

    ControllerJanitor:Add(RunService.RenderStepped:Connect(OnRenderStepped), "Disconnect")

    print("[ZombieController] Started (explicit death state)")
end

function ZombieController:GetVisualAtPosition(position: Vector3, radius: number): ZombieVisual?
    for _, visual in Visuals do
        if visual.Model and not LocalKills[visual.Id] then
            local dist = (visual.CurrentPos - position).Magnitude
            if dist < radius then
                return visual
            end
        end
    end
    return nil
end

function ZombieController:Destroy()
    ControllerJanitor:Destroy()
    for id in Visuals do
        DestroyVisual(id)
    end
end

return ZombieController
