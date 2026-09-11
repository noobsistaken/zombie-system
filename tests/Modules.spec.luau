local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)
local SpatialHash = require(ReplicatedStorage.Shared.Modules.SpatialHash)
local SwarmMath = require(ReplicatedStorage.Shared.Modules.SwarmMath)
local Spring = require(StarterPlayer.StarterPlayerScripts.Client.Modules.Spring)

local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

describe("spatial hash", function()
    it("queries neighboring cells across zero and excludes distant cells", function()
        local grid = SpatialHash.new(10)
        local negative = { Position = Vector3.new(-0.1, 3, -0.1) }
        local adjacent = { Position = Vector3.new(19.9, 3, 19.9) }
        local distant = { Position = Vector3.new(20, 3, 0) }
        grid:Insert(negative)
        grid:Insert(adjacent)
        grid:Insert(distant)
        local neighbors = grid:GetNearby(Vector3.zero)
        expect(#neighbors).toBe(2)
        expect(neighbors[1]).toBe(negative)
        expect(neighbors[2]).toBe(adjacent)
    end)

    it("rebuilds without retaining old entries", function()
        local grid = SpatialHash.new(2)
        grid:Insert({ Position = Vector3.zero })
        local moved = { Position = Vector3.new(100, 3, 0) }
        grid:Rebuild({ moved })
        expect(#grid:GetNearby(Vector3.zero)).toBe(0)
        expect(grid:GetNearby(moved.Position)[1]).toBe(moved)
        grid:Clear()
        expect(#grid:GetNearby(moved.Position)).toBe(0)
    end)

    it("reuses a query buffer without changing a previously returned list", function()
        local grid = SpatialHash.new(10)
        local first = { Position = Vector3.new(-10, 0, -10) }
        local distant = { Position = Vector3.new(100, 0, -100) }
        grid:Rebuild({ first, distant })
        local retained = grid:GetNearby(first.Position)
        local buffer = { distant }
        expect(grid:GetNearby(first.Position, buffer)).toBe(buffer)
        expect(#buffer).toBe(1)
        expect(buffer[1]).toBe(first)
        grid:GetNearby(distant.Position, buffer)
        expect(#buffer).toBe(1)
        expect(buffer[1]).toBe(distant)
        expect(retained[1]).toBe(first)
        grid:Clear()
        grid:GetNearby(first.Position, buffer)
        expect(#buffer).toBe(0)
    end)
end)

describe("steering", function()
    it("respects the search radius without expanding separation range", function()
        local agent = { Position = Vector3.zero, Velocity = Vector3.zero }
        local neighbor = { Position = Vector3.new(2, 0, 0), Velocity = Vector3.zero }
        expect(SwarmMath.CalculateSteering(agent, { neighbor }, Vector3.zero, 2)).toBe(Vector3.zero)
        neighbor.Position = Vector3.new(1.9999, 0, 0)
        expect(SwarmMath.CalculateSteering(agent, { neighbor }, Vector3.zero, 2)).toBe(Vector3.new(-12, 0, 0))
        neighbor.Position = Vector3.new(5, 0, 0)
        expect(SwarmMath.CalculateSteering(agent, { neighbor }, Vector3.zero, 8)).toBe(Vector3.zero)
    end)

    it("seeks at the configured speed and ignores coincident separation", function()
        local agent = { Position = Vector3.zero, Velocity = Vector3.zero }
        expect(SwarmMath.GetSeekVector(agent, Vector3.zero)).toBe(Vector3.zero)
        expect(SwarmMath.GetSeekVector(agent, Vector3.new(10, 0, 0))).toBe(Vector3.new(8, 0, 0))
        expect(SwarmMath.GetSeparationVector(agent, { agent })).toBe(Vector3.zero)
    end)

    it("clamps force and velocity without changing the input state", function()
        local agent = { Position = Vector3.zero, Velocity = Vector3.zero }
        local neighbor = { Position = Vector3.new(-1, 0, 0), Velocity = Vector3.zero }
        expect(SwarmMath.CalculateSteering(agent, { neighbor }, Vector3.new(10, 0, 0))).toBe(Vector3.new(15, 0, 0))
        local position, velocity = SwarmMath.ApplyForce(agent, Vector3.new(100, 0, 0), 1)
        expect(position).toBe(Vector3.new(8, 0, 0))
        expect(velocity).toBe(position)
        expect(agent.Position).toBe(Vector3.zero)
    end)
end)

describe("spring", function()
    it("integrates independently for each instance", function()
        local moving = Spring.new(2, 10)
        local still = Spring.new()
        moving:SetTarget(Vector3.new(1, 0, 0))
        expect((moving:Update(0.1) - Vector3.new(0.1, 0, 0)).Magnitude < 0.00001).toBe(true)
        expect((moving:Update(0.1) - Vector3.new(0.27, 0, 0)).Magnitude < 0.00001).toBe(true)
        expect(still:Update(0.1)).toBe(Vector3.zero)
    end)

    it("limits impulse velocity", function()
        local spring = Spring.new()
        spring:Impulse(Vector3.new(1000, 0, 0))
        spring:Update(0)
        expect(spring.Velocity).toBe(Vector3.new(50, 0, 0))
    end)
end)
