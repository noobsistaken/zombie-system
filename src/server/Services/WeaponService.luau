-- Author: noobs

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Janitor = require(ReplicatedStorage.Packages.Janitor)
local Net = require(ServerScriptService.Net)
local ZombieService = require(script.Parent.ZombieService)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

export type ShootParams = {
    Origin: Vector3,
    Direction: Vector3,
    HitZombieId: number?,
}

local Config = GameConfig.Weapon
local MAX_ORIGIN_DISTANCE = 10
local HIT_RADIUS = 5

local WeaponService = {}
local started = false

local ServiceJanitor = Janitor.new()
local PlayerCooldowns: { [Player]: number } = {}

local function CheckRateLimit(player: Player): boolean
    local now = os.clock()
    local lastShot = PlayerCooldowns[player] or 0
    local minInterval = 1 / Config.RateLimitPerSecond

    if now - lastShot < minInterval then
        return false
    end

    PlayerCooldowns[player] = now
    return true
end

local function ValidateOrigin(player: Player, origin: Vector3): boolean
    local character = player.Character
    if not character then
        return false
    end

    local head = character:FindFirstChild("Head")
    if not head or not head:IsA("BasePart") then
        return false
    end

    local distance = (origin - head.Position).Magnitude

    return distance <= MAX_ORIGIN_DISTANCE
end

local function IsNearShot(position: Vector3, params: ShootParams): boolean
    local direction = params.Direction.Unit
    local distanceAlongRay = (position - params.Origin):Dot(direction)
    if not (distanceAlongRay > 0 and distanceAlongRay < Config.MaxRaycastDistance) then
        return false
    end

    local closestPoint = params.Origin + direction * distanceAlongRay
    return (position - closestPoint).Magnitude < HIT_RADIUS
end

function WeaponService:Shoot(player: Player, params: ShootParams): boolean
    if not CheckRateLimit(player) then
        return false
    end

    if not ValidateOrigin(player, params.Origin) then
        return false
    end

    if params.Direction.Magnitude < 0.1 then
        return false
    end

    local zombieId = params.HitZombieId
    if not zombieId then
        return false
    end

    local zombie = ZombieService:GetZombieById(zombieId)
    if not zombie or not IsNearShot(zombie.Position, params) then
        return false
    end

    ZombieService:RespawnZombie(zombieId)
    Net.HitConfirmed.Fire(player, zombie.Position)
    return true
end

function WeaponService.start()
    if started then
        return
    end
    started = true

    ServiceJanitor:Add(
        Net.Shoot.SetCallback(function(player: Player, params: ShootParams)
            return WeaponService:Shoot(player, params)
        end),
        true
    )

    ServiceJanitor:Add(
        Players.PlayerRemoving:Connect(function(player: Player)
            PlayerCooldowns[player] = nil
        end),
        "Disconnect"
    )

    print("[WeaponService] Started")
end

function WeaponService:Destroy()
    ServiceJanitor:Destroy()
end

return WeaponService
