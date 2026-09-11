-- Author: noobs

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local SwarmMath = {}

export type EntityState = {
    Position: Vector3,
    Velocity: Vector3,
}

local Config = GameConfig.Swarm

@native
local function ClampMagnitude(v: Vector3, maxMag: number): Vector3
    local mag = v.Magnitude
    if mag > maxMag then
        return v.Unit * maxMag
    end
    return v
end

@native
function SwarmMath.GetSeparationVector(agent: EntityState, neighbors: { EntityState }, radius: number?): Vector3
    local effectiveRadius = radius or Config.SeparationRadius
    local radiusSquared = effectiveRadius * effectiveRadius
    local steering = Vector3.zero
    local count = 0

    for _, neighbor in neighbors do
        local offset = agent.Position - neighbor.Position
        local distanceSquared = offset:Dot(offset)

        if effectiveRadius > 0 and distanceSquared > 0 and distanceSquared < radiusSquared then
            local pushForce = offset / distanceSquared
            steering += pushForce
            count += 1
        end
    end

    if count > 0 then
        steering /= count
        if steering.Magnitude > 0 then
            steering = steering.Unit * Config.MaxSpeed - agent.Velocity
            steering = ClampMagnitude(steering, Config.MaxForce)
        end
    end

    return steering * Config.SeparationWeight
end

@native
function SwarmMath.GetSeekVector(agent: EntityState, target: Vector3): Vector3
    local desired = target - agent.Position

    if desired.Magnitude == 0 then
        return Vector3.zero
    end

    desired = desired.Unit * Config.MaxSpeed

    local steering = desired - agent.Velocity
    steering = ClampMagnitude(steering, Config.MaxForce)

    return steering * Config.SeekWeight
end

@native
function SwarmMath.CalculateSteering(
    agent: EntityState,
    neighbors: { EntityState },
    target: Vector3,
    neighborRadius: number?
): Vector3
    local radius = math.min(Config.SeparationRadius, neighborRadius or Config.SeparationRadius)
    local separation = SwarmMath.GetSeparationVector(agent, neighbors, radius)
    local seek = SwarmMath.GetSeekVector(agent, target)

    local combined = separation + seek
    return ClampMagnitude(combined, Config.MaxForce)
end

@native
function SwarmMath.ApplyForce(agent: EntityState, force: Vector3, dt: number): (Vector3, Vector3)
    local newVelocity = agent.Velocity + force * dt
    newVelocity = ClampMagnitude(newVelocity, Config.MaxSpeed)

    local newPosition = agent.Position + newVelocity * dt

    return newPosition, newVelocity
end

return SwarmMath
