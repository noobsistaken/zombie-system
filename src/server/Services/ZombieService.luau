-- Author: noobs

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Janitor = require(ReplicatedStorage.Packages.Janitor)
local Net = require(ServerScriptService.Net)
local SpatialHash = require(ReplicatedStorage.Shared.Modules.SpatialHash)
local SwarmMath = require(ReplicatedStorage.Shared.Modules.SwarmMath)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

export type ZombieData = {
    Id: number,
    Position: Vector3,
    Velocity: Vector3,
    Health: number,
    DeathTime: number?,
    JustSpawned: boolean?,
}

export type NetworkPacket = {
    P: Vector3, -- Position
    H: number, -- Health (0 = dead)
}

local Config = GameConfig.Zombies
local DEAD_BROADCAST_TIME = 1.0

local ZombieService = {}
local ServiceJanitor = Janitor.new()
local started = false

local Zombies: { [number]: ZombieData } = {}
local ZombieCount: number = 0
local NextId: number = 1

local CELL_SIZE = 10
local grid = SpatialHash.new(CELL_SIZE)
local neighborBuffer: { SwarmMath.EntityState } = {}

local SNAPSHOT_INTERVAL = 0.1
local lastSnapshotTime = 0

local RESPAWN_DELAY = 3.0
local RespawnQueue: { number } = {}

local STEERING_SKIP_DISTANCE = 100

local function GetRandomSpawnPosition(): Vector3
    local angle = math.random() * math.pi * 2
    local radius = math.random() * Config.SpawnRadius
    return Vector3.new(math.cos(angle) * radius, Config.SpawnHeight, math.sin(angle) * radius)
end

@native
local function GetSwarmTarget(): Vector3?
    local players = Players:GetPlayers()
    if #players == 0 then
        return nil
    end
    if #players == 1 then
        local character = players[1].Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        return if root and root:IsA("BasePart") then root.Position else nil
    end

    local centroid = Vector3.zero
    local count = 0
    for _, zombie in Zombies do
        if zombie.Health > 0 then
            centroid += zombie.Position
            count += 1
        end
    end

    if count > 0 then
        centroid /= count
    end

    local closestPos: Vector3? = nil
    local closestDist = math.huge

    for _, player in players do
        local character = player.Character
        if character then
            local root = character:FindFirstChild("HumanoidRootPart")
            if root and root:IsA("BasePart") then
                local dist = (root.Position - centroid).Magnitude
                if dist < closestDist then
                    closestDist = dist
                    closestPos = root.Position
                end
            end
        end
    end

    return closestPos
end

function ZombieService:SpawnZombie(position: Vector3?): ZombieData?
    if ZombieCount >= Config.MaxCount then
        return nil
    end

    local spawnPos = position or GetRandomSpawnPosition()

    local zombie: ZombieData = {
        Id = NextId,
        Position = spawnPos,
        Velocity = Vector3.zero,
        Health = 1,
        DeathTime = nil,
        JustSpawned = true,
    }

    NextId += 1
    ZombieCount += 1
    Zombies[zombie.Id] = zombie

    return zombie
end

function ZombieService:KillZombie(zombieId: number): boolean
    local zombie = Zombies[zombieId]
    if not zombie or not (zombie.Health > 0) then
        return false
    end

    zombie.Health = 0
    zombie.DeathTime = os.clock()
    ZombieCount -= 1
    return true
end

function ZombieService:RespawnZombie(zombieId: number)
    if self:KillZombie(zombieId) then
        table.insert(RespawnQueue, os.clock() + RESPAWN_DELAY)
    end
end

function ZombieService:GetZombieById(zombieId: number): ZombieData?
    return Zombies[zombieId]
end

function ZombieService:GetZombieAtPosition(position: Vector3, radius: number): ZombieData?
    for _, zombie in Zombies do
        if zombie.Health > 0 then
            local dist = (zombie.Position - position).Magnitude
            if dist < radius then
                return zombie
            end
        end
    end
    return nil
end

local function BuildSnapshot(): { [number]: NetworkPacket }
    local snapshot: { [number]: NetworkPacket } = {}
    local now = os.clock()

    for id, zombie in Zombies do
        if zombie.Health > 0 then
            snapshot[id] = {
                P = zombie.Position,
                H = 1,
            }
        elseif zombie.DeathTime and (now - zombie.DeathTime) < DEAD_BROADCAST_TIME then
            snapshot[id] = {
                P = zombie.Position,
                H = 0,
            }
        end
    end

    return snapshot
end

local function CleanupDeadZombies()
    local now = os.clock()

    for id, zombie in Zombies do
        if zombie.Health <= 0 and zombie.DeathTime and (now - zombie.DeathTime) >= DEAD_BROADCAST_TIME then
            Zombies[id] = nil
        end
    end
end

local function ProcessRespawnQueue()
    local now = os.clock()
    local i = 1
    while i <= #RespawnQueue do
        local unlockTime = RespawnQueue[i]
        if now >= unlockTime then
            table.remove(RespawnQueue, i)
            ZombieService:SpawnZombie()
        else
            i += 1
        end
    end
end

@native
local function GetSteeringNeighbors(zombie: ZombieData): { SwarmMath.EntityState }
    return grid:GetNearby(zombie.Position, neighborBuffer)
end

@native
local function UpdateZombies(target: Vector3, dt: number)
    grid:Clear()
    for _, zombie in Zombies do
        if zombie.Health > 0 then
            grid:Insert(zombie)
        end
    end

    for _, zombie in Zombies do
        if zombie.Health <= 0 then
            continue
        end

        local distToTarget = (zombie.Position - target).Magnitude
        local hasVelocity = zombie.Velocity.Magnitude > 0.1

        -- Distant zombies keep their velocity until they need to steer again.
        if not (distToTarget > STEERING_SKIP_DISTANCE and hasVelocity) then
            local neighbors = GetSteeringNeighbors(zombie)
            local force = SwarmMath.CalculateSteering(zombie, neighbors, target, Config.NeighborRadius)
            local _, velocity = SwarmMath.ApplyForce(zombie, force, dt)
            zombie.Velocity = Vector3.new(velocity.X, 0, velocity.Z)
        end

        local position = zombie.Position + zombie.Velocity * dt
        zombie.Position = Vector3.new(position.X, Config.SpawnHeight, position.Z)
    end
end

local function Heartbeat(dt: number)
    local target = GetSwarmTarget()
    local now = os.clock()

    CleanupDeadZombies()
    ProcessRespawnQueue()

    if target then
        UpdateZombies(target, dt)
    end

    if now - lastSnapshotTime >= SNAPSHOT_INTERVAL then
        lastSnapshotTime = now
        local snapshot = BuildSnapshot()
        Net.ZombieSnapshot.FireAll(snapshot)
    end
end

function ZombieService.start()
    if started then
        return
    end
    started = true

    for _ = 1, Config.MaxCount do
        ZombieService:SpawnZombie()
    end

    print("[ZombieService] Spawned", Config.MaxCount, "zombies (explicit state)")

    ServiceJanitor:Add(RunService.Heartbeat:Connect(Heartbeat), "Disconnect")

    ServiceJanitor:Add(
        task.spawn(function()
            while true do
                task.wait(3)
                local entityCount = 0
                local aliveCount = 0
                for _, zombie in Zombies do
                    entityCount += 1
                    if zombie.Health > 0 then
                        aliveCount += 1
                    end
                end
                local snapshot = BuildSnapshot()
                local snapshotSize = 0
                for _ in snapshot do
                    snapshotSize += 1
                end
                print(
                    string.format(
                        "[SERVER] Entities: %d | Alive: %d | Queue: %d | Snapshot: %d",
                        entityCount,
                        aliveCount,
                        #RespawnQueue,
                        snapshotSize
                    )
                )
            end
        end),
        true
    )
end

function ZombieService:Destroy()
    ServiceJanitor:Destroy()
end

return ZombieService
