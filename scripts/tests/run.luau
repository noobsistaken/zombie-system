local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local newRuntime = require("./runtime")
local Vector3 = roblox.Vector3
local sourceRoot = process.args[1] or "src"
local passed = 0

local function test(name, callback)
    callback()
    passed += 1
    print("PASS " .. name)
end

local function near(actual, expected)
    assert((actual - expected).Magnitude < 0.00001, tostring(actual) .. " ~= " .. tostring(expected))
end

local function count(entries)
    local total = 0
    for _ in entries do
        total += 1
    end
    return total
end

local compiled = 0
local function compileDirectory(path)
    for _, name in fs.readDir(path) do
        local child = path .. "/" .. name
        if fs.isDir(child) then
            compileDirectory(child)
        elseif name:match("%.luau$") then
            luau.compile(fs.readFile(child))
            compiled += 1
        end
    end
end
compileDirectory(sourceRoot)
print(string.format("Compiled %d source files", compiled))

test("spatial hash includes adjacent cells across zero and excludes distant cells", function()
    local grid = newRuntime(sourceRoot):Load("shared/Modules/SpatialHash").new(10)
    local negative = { Position = Vector3.new(-0.1, 0, -0.1) }
    local origin = { Position = Vector3.zero }
    local adjacent = { Position = Vector3.new(19.9, 0, 19.9) }
    local distant = { Position = Vector3.new(20, 0, 0) }
    for _, entity in { negative, origin, adjacent, distant } do
        grid:Insert(entity)
    end
    local nearby = grid:GetNearby(Vector3.zero)
    assert(#nearby == 3)
    assert(nearby[1] == negative and nearby[2] == origin and nearby[3] == adjacent)
    grid:Clear()
    assert(#grid:GetNearby(Vector3.zero) == 0)
    grid:Rebuild({ distant })
    assert(#grid:GetNearby(Vector3.zero) == 0)
    assert(grid:GetNearby(distant.Position)[1] == distant)
end)

test("spatial hash supports custom cell sizes and independent grids", function()
    local SpatialHash = newRuntime(sourceRoot):Load("shared/Modules/SpatialHash")
    local small = SpatialHash.new(2)
    local default = SpatialHash.new()
    local entity = { Position = Vector3.new(4, 0, 0) }
    small:Insert(entity)
    default:Insert(entity)
    assert(#small:GetNearby(Vector3.zero) == 0)
    assert(#default:GetNearby(Vector3.zero) == 1)
    small:Clear()
    assert(#default:GetNearby(Vector3.zero) == 1)
end)

test("spatial queries can reuse a buffer without retaining earlier results", function()
    local grid = newRuntime(sourceRoot):Load("shared/Modules/SpatialHash").new(10)
    local first = { Position = Vector3.new(-10, 0, -10) }
    local distant = { Position = Vector3.new(100, 0, -100) }
    grid:Rebuild({ first, distant })
    local retained = grid:GetNearby(first.Position)
    local buffer = { distant }
    assert(grid:GetNearby(first.Position, buffer) == buffer)
    assert(#buffer == 1 and buffer[1] == first)
    grid:GetNearby(distant.Position, buffer)
    assert(#buffer == 1 and buffer[1] == distant)
    assert(#retained == 1 and retained[1] == first)
    grid:Clear()
    grid:GetNearby(first.Position, buffer)
    assert(#buffer == 0)
end)

test("swarm seek, separation, and force limits", function()
    local swarm = newRuntime(sourceRoot):Load("shared/Modules/SwarmMath")
    local agent = { Position = Vector3.zero, Velocity = Vector3.zero }
    near(swarm.GetSeekVector(agent, Vector3.zero), Vector3.zero)
    near(swarm.GetSeekVector(agent, Vector3.new(10, 0, 0)), Vector3.new(8, 0, 0))
    near(swarm.GetSeparationVector(agent, { agent }), Vector3.zero)
    near(
        swarm.GetSeparationVector(agent, {
            { Position = Vector3.new(2, 0, 0), Velocity = Vector3.zero },
            { Position = Vector3.new(4, 0, 0), Velocity = Vector3.zero },
        }),
        Vector3.new(-12, 0, 0)
    )
    local force = swarm.CalculateSteering(agent, {
        { Position = Vector3.new(-1, 0, 0), Velocity = Vector3.zero },
    }, Vector3.new(10, 0, 0))
    near(force, Vector3.new(15, 0, 0))
    local position, velocity = swarm.ApplyForce(agent, Vector3.new(100, 0, 0), 1)
    near(velocity, Vector3.new(8, 0, 0))
    near(position, velocity)
    near(agent.Position, Vector3.zero)
end)

test("steering respects the smaller search radius and excludes its boundary", function()
    local swarm = newRuntime(sourceRoot):Load("shared/Modules/SwarmMath")
    local agent = { Position = Vector3.zero, Velocity = Vector3.zero }
    local neighbor = { Position = Vector3.new(2, 0, 0), Velocity = Vector3.zero }
    near(swarm.CalculateSteering(agent, { neighbor }, Vector3.zero, 2), Vector3.zero)
    neighbor.Position = Vector3.new(1.9999, 0, 0)
    near(swarm.CalculateSteering(agent, { neighbor }, Vector3.zero, 2), Vector3.new(-12, 0, 0))
    neighbor.Position = Vector3.new(5, 0, 0)
    near(swarm.CalculateSteering(agent, { neighbor }, Vector3.zero, 8), Vector3.zero)
    near(swarm.CalculateSteering(agent, { agent }, Vector3.zero, 8), Vector3.zero)
end)

test("spring integration, impulses, clamping, and instance isolation", function()
    local Spring = newRuntime(sourceRoot):Load("client/Modules/Spring")
    local spring = Spring.new(2, 10)
    local untouched = Spring.new()
    spring:SetTarget(Vector3.new(1, 0, 0))
    near(spring:Update(0.1), Vector3.new(0.1, 0, 0))
    near(spring:Update(0.1), Vector3.new(0.27, 0, 0))
    spring:Impulse(Vector3.new(1000, 0, 0))
    spring:Update(0)
    near(spring.Velocity, Vector3.new(50, 0, 0))
    near(untouched:Update(0.1), Vector3.zero)
    assert(untouched.Damping == 0.5 and untouched.Stiffness == 10)
end)

test("zombie capacity, radius boundary, and repeated kills", function()
    local runtime = newRuntime(sourceRoot)
    local config = runtime:Load("shared/GameConfig")
    config.Zombies.MaxCount = 2
    local service = runtime:Load("server/Services/ZombieService")
    local first = service:SpawnZombie(Vector3.new(0, 3, 0))
    local second = service:SpawnZombie(Vector3.new(20, 3, 0))
    assert(first.Id == 1 and second.Id == 2)
    assert(service:SpawnZombie() == nil)
    assert(service:GetZombieAtPosition(Vector3.new(5, 3, 0), 5) == nil)
    assert(service:GetZombieAtPosition(first.Position, 1) == first)
    assert(service:KillZombie(first.Id))
    assert(not service:KillZombie(first.Id))
    assert(not service:KillZombie(999))
    assert(service:GetZombieAtPosition(first.Position, 1) == nil)
    assert(service:SpawnZombie().Id == 3)
end)

test("snapshots, death broadcast expiry, and one delayed respawn without players", function()
    local runtime = newRuntime(sourceRoot)
    local config = runtime:Load("shared/GameConfig")
    config.Zombies.MaxCount = 1
    local service = runtime:Load("server/Services/ZombieService")
    service.start()
    local event = runtime.Net.ZombieSnapshot
    runtime.Heartbeat:Fire(0)
    local packet = event.Calls[1][1][1]
    assert(packet.H == 1 and count(packet) == 2)
    local position = packet.P
    runtime.Time = 10.05
    runtime.Heartbeat:Fire(0)
    assert(#event.Calls == 1)
    runtime.Time = 10.2
    service:RespawnZombie(1)
    service:RespawnZombie(1)
    runtime.Heartbeat:Fire(0)
    assert(event.Calls[2][1][1].H == 0)
    near(event.Calls[2][1][1].P, position)
    runtime.Time = 11.19
    runtime.Heartbeat:Fire(0)
    assert(event.Calls[#event.Calls][1][1].H == 0)
    runtime.Time = 11.2
    runtime.Heartbeat:Fire(0)
    assert(service:GetZombieById(1) == nil)
    runtime.Time = 13.19
    runtime.Heartbeat:Fire(0)
    assert(count(event.Calls[#event.Calls][1]) == 0)
    runtime.Time = 13.2
    runtime.Heartbeat:Fire(0)
    assert(service:GetZombieById(2) ~= nil)
    runtime.Time = 13.4
    runtime.Heartbeat:Fire(0)
    assert(count(event.Calls[#event.Calls][1]) == 1)
    assert(service:GetZombieById(3) == nil)
end)

test("expired deaths are all removed from a sparse zombie table", function()
    local runtime = newRuntime(sourceRoot)
    runtime:Load("shared/GameConfig").Zombies.MaxCount = 100
    local service = runtime:Load("server/Services/ZombieService")
    service.start()
    for id = 1, 100, 2 do
        assert(service:KillZombie(id))
    end
    runtime.Time += 1
    runtime.Heartbeat:Fire(1 / 60)
    for id = 1, 100 do
        if id % 2 == 1 then
            assert(service:GetZombieById(id) == nil)
        else
            assert(service:GetZombieById(id).Health == 1)
        end
    end
    service:Destroy()
end)

test("zombies seek the player nearest the swarm centroid", function()
    local runtime = newRuntime(sourceRoot)
    local config = runtime:Load("shared/GameConfig")
    config.Zombies.MaxCount = 0
    local service = runtime:Load("server/Services/ZombieService")
    service.start()
    config.Zombies.MaxCount = 2
    local first = service:SpawnZombie(Vector3.new(0, 3, 0))
    local second = service:SpawnZombie(Vector3.new(30, 3, 0))
    runtime:Player(Vector3.new(-10, 3, 0))
    runtime:Player(Vector3.new(35, 3, 0))
    runtime.Heartbeat:Fire(0.1)
    near(first.Velocity, Vector3.new(0.8, 0, 0))
    near(second.Velocity, Vector3.new(0.8, 0, 0))
    near(first.Position, Vector3.new(0.08, 3, 0))
end)

test("nearby zombies separate while distant moving zombies coast", function()
    local runtime = newRuntime(sourceRoot)
    local config = runtime:Load("shared/GameConfig")
    config.Zombies.MaxCount = 0
    local service = runtime:Load("server/Services/ZombieService")
    service.start()
    config.Zombies.MaxCount = 3
    local first = service:SpawnZombie(Vector3.new(0, 3, 0))
    service:SpawnZombie(Vector3.new(2, 3, 0))
    local distant = service:SpawnZombie(Vector3.new(-200, 3, 0))
    distant.Velocity = Vector3.new(2, 0, 1)
    runtime:Player(Vector3.new(10, 3, 0))
    runtime.Heartbeat:Fire(0.1)
    near(first.Velocity, Vector3.new(-0.4, 0, 0))
    near(distant.Velocity, Vector3.new(2, 0, 1))
    near(distant.Position, Vector3.new(-199.8, 3, 0.1))
end)

test("weapon ray validation boundaries and hit confirmation", function()
    for _, case in
        {
            { Position = Vector3.new(10, 3, 0), Expected = true },
            { Position = Vector3.new(10, 3, 4.99), Expected = true },
            { Position = Vector3.new(10, 3, 5), Expected = false },
            { Position = Vector3.new(-1, 3, 0), Expected = false },
            { Position = Vector3.new(200, 3, 0), Expected = false },
            { Position = Vector3.new(0, 3, 0), Expected = false },
        }
    do
        local runtime = newRuntime(sourceRoot)
        local zombies = runtime:Load("server/Services/ZombieService")
        local weapon = runtime:Load("server/Services/WeaponService")
        local player = runtime:Player(Vector3.new(0, 3, 0))
        local zombie = zombies:SpawnZombie(case.Position)
        local hit = weapon:Shoot(player, {
            Origin = Vector3.new(0, 3, 0),
            Direction = Vector3.new(2, 0, 0),
            HitZombieId = zombie.Id,
        })
        assert(hit == case.Expected, tostring(case.Position))
        assert(#runtime.Net.HitConfirmed.Calls == (if hit then 1 else 0))
        assert(zombie.Health == (if hit then 0 else 1))
    end
end)

test("weapon cooldown, invalid origin, missing target, and player cleanup", function()
    local runtime = newRuntime(sourceRoot)
    local zombies = runtime:Load("server/Services/ZombieService")
    local weapon = runtime:Load("server/Services/WeaponService")
    weapon.start()
    local player = runtime:Player(Vector3.new(0, 3, 0))
    local zombie = zombies:SpawnZombie(Vector3.new(10, 3, 0))
    local params = { Origin = Vector3.new(0, 3, 0), Direction = Vector3.new(1, 0, 0), HitZombieId = zombie.Id }
    assert(weapon:Shoot(player, params))
    assert(not weapon:Shoot(player, params))
    runtime.Time += 0.2
    params.Origin = Vector3.new(0, 30, 0)
    assert(not weapon:Shoot(player, params))
    params.Origin = Vector3.new(0, 3, 0)
    assert(not weapon:Shoot(player, params))
    runtime:RemovePlayer(player)
    assert(weapon:Shoot(player, params))
    runtime.Time += 0.2
    params.Direction = Vector3.zero
    assert(not weapon:Shoot(player, params))
    runtime.Time += 0.2
    params.Direction = Vector3.new(1, 0, 0)
    params.HitZombieId = nil
    assert(not weapon:Shoot(player, params))
    runtime.Time += 0.2
    params.HitZombieId = 999
    assert(not weapon:Shoot(player, params))
    weapon:Destroy()
end)

test("client snapshots create, interpolate, snap, and expire visuals", function()
    local runtime = newRuntime(sourceRoot)
    runtime:SetupRendering()
    local controller = runtime:Load("client/Controllers/ZombieController")
    controller.start()
    local start = Vector3.new(0, 3, 0)
    runtime.Snapshots:Fire({ [1] = { P = start, H = 1 } })
    local visual = controller:GetVisualAtPosition(start, 1)
    assert(visual and visual.Id == 1)
    local root = visual.Model:FindFirstChild("HumanoidRootPart")
    local head = visual.Model:FindFirstChild("Head")
    assert(root.Anchored and not head.Anchored)
    assert(not root.CanCollide and not root.CanTouch and root.CanQuery)
    assert(head:FindFirstChildOfClass("WeldConstraint").Part0 == root)
    runtime.RenderStepped:Fire(0.1)
    near(visual.CurrentPos, start)
    assert(runtime.Moves[1].Mode == roblox.Enum.BulkMoveMode.FireCFrameChanged)
    runtime.Time += 0.1
    runtime.Snapshots:Fire({ [1] = { P = Vector3.new(2, 3, 0), H = 1 } })
    near(visual.Velocity, Vector3.new(20, 0, 0))
    runtime.RenderStepped:Fire(0.1)
    near(visual.CurrentPos, Vector3.new(1.5, 3, 0))
    near(runtime.Moves[#runtime.Moves].CFrames[1].Position, visual.CurrentPos)
    runtime.Time += 0.1
    runtime.Snapshots:Fire({ [1] = { P = Vector3.new(100, 3, 0), H = 1 } })
    near(visual.Velocity, Vector3.new(50, 0, 0))
    runtime.RenderStepped:Fire(0.1)
    near(visual.CurrentPos, Vector3.new(100, 3, 0))
    runtime.Time += 1
    runtime.Snapshots:Fire({ [1] = { P = Vector3.new(100, 3, 0), H = 1 } })
    near(visual.Velocity, Vector3.zero)
    runtime.Snapshots:Fire({})
    assert(controller:GetVisualAtPosition(visual.CurrentPos, 1))
    runtime.Time += 5
    runtime.RenderStepped:Fire(0.1)
    assert(controller:GetVisualAtPosition(Vector3.new(100, 3, 0), 1) == nil)
    controller:Destroy()
end)

test("client local hits stay hidden until death confirmation", function()
    local runtime = newRuntime(sourceRoot)
    runtime:SetupRendering()
    local controller = runtime:Load("client/Controllers/ZombieController")
    controller.start()
    local position = Vector3.new(0, 3, 0)
    runtime.Snapshots:Fire({ [1] = { P = position, H = 1 } })
    local visual = controller:GetVisualAtPosition(position, 1)
    controller:ProcessLocalHit(1)
    assert(controller:GetVisualAtPosition(position, 1) == nil)
    for _, descendant in visual.Model:GetDescendants() do
        if descendant:IsA("BasePart") or descendant:IsA("Decal") then
            assert(descendant.Transparency == 1)
        end
    end
    runtime.Time += 0.1
    runtime.Snapshots:Fire({ [1] = { P = position, H = 1 } })
    runtime.RenderStepped:Fire(0.1)
    assert(#runtime.Moves == 0)
    runtime.Snapshots:Fire({ [1] = { P = position, H = 0 } })
    runtime.Snapshots:Fire({ [1] = { P = position, H = 1 } })
    assert(controller:GetVisualAtPosition(position, 1) ~= nil)
    runtime.Snapshots:Fire({ [1] = { P = position, H = 0 } })
    assert(controller:GetVisualAtPosition(position, 1) == nil)
    controller:Destroy()
end)

test("weapon input respects processed input, fire rate, release, and camera zoom", function()
    local runtime = newRuntime(sourceRoot)
    runtime:SetupRendering()
    runtime:SetupInput()
    local weapon = runtime:Load("client/Controllers/WeaponController")
    weapon.start()
    local click = { UserInputType = roblox.Enum.UserInputType.MouseButton1 }
    runtime.InputBegan:Fire(click, true)
    runtime.RenderStepped:Fire(0)
    assert(#runtime.Shots == 0)
    runtime.InputBegan:Fire(click, false)
    runtime.RenderStepped:Fire(0)
    assert(#runtime.Shots == 1)
    runtime.Time += 0.05
    runtime.RenderStepped:Fire(0)
    assert(#runtime.Shots == 1)
    runtime.Time += 0.1
    runtime.RenderStepped:Fire(0)
    assert(#runtime.Shots == 2)
    runtime.InputEnded:Fire(click)
    runtime.Time += 0.2
    runtime.RenderStepped:Fire(0)
    assert(#runtime.Shots == 2)
    runtime.Camera.Focus = roblox.CFrame.new(1.5, 3, 0)
    runtime.InputBegan:Fire(click, false)
    runtime.RenderStepped:Fire(0)
    assert(#runtime.Shots == 2)
    runtime.Camera.Focus = roblox.CFrame.new(1, 3, 0)
    runtime.RenderStepped:Fire(0)
    assert(#runtime.Shots == 2)
    runtime.Time += 0.2
    runtime.RenderStepped:Fire(0)
    assert(#runtime.Shots == 3)
    weapon:Destroy()
    runtime.Time += 0.2
    runtime.RenderStepped:Fire(0)
    assert(#runtime.Shots == 3)
end)

test("weapon raycasts forward zombie IDs and apply local hit feedback", function()
    local runtime = newRuntime(sourceRoot)
    runtime:SetupRendering()
    runtime:SetupInput()
    local zombies = runtime:Load("client/Controllers/ZombieController")
    zombies.start()
    runtime.Snapshots:Fire({ [42] = { P = Vector3.new(10, 3, 0), H = 1 } })
    local visual = zombies:GetVisualAtPosition(Vector3.new(10, 3, 0), 1)
    runtime.HitPart = visual.Model:FindFirstChild("Head")
    local recoilCount = 0
    runtime.Controllers.ViewmodelController = {
        ApplyRecoil = function()
            recoilCount += 1
        end,
    }
    local weapon = runtime:Load("client/Controllers/WeaponController")
    weapon.start()
    runtime.InputBegan:Fire({ UserInputType = roblox.Enum.UserInputType.MouseButton1 }, false)
    runtime.RenderStepped:Fire(0)
    assert(#runtime.Shots == 1 and runtime.Shots[1].HitZombieId == 42)
    assert(recoilCount == 1)
    assert(zombies:GetVisualAtPosition(Vector3.new(10, 3, 0), 1) == nil)
    near(runtime.Raycasts[1].Direction, Vector3.new(200, 0, 0))
    assert(runtime.Raycasts[1].Params.FilterType == roblox.Enum.RaycastFilterType.Include)
    assert(runtime.Raycasts[1].Params.FilterDescendantsInstances[1].Name == "Zombies")
    visual.Model.Name = "Unrelated"
    runtime.Time += 0.2
    runtime.RenderStepped:Fire(0)
    assert(#runtime.Shots == 2 and runtime.Shots[2].HitZombieId == nil)
    weapon:Destroy()
    zombies:Destroy()
end)

print(string.format("%d tests passed", passed))
