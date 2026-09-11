local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local workspaceMoves = {}
local workspaceRays = {}
local cameraRays = {}

roblox.implementMethod("Model", "PivotTo", function(model, cframe)
    model.WorldPivot = cframe
end)
roblox.implementMethod("Workspace", "Raycast", function(workspace, origin, direction, params)
    local runtime = workspaceRays[workspace]
    table.insert(runtime.Raycasts, { Origin = origin, Direction = direction, Params = params })
    return if runtime.HitPart then { Instance = runtime.HitPart } else nil
end)
roblox.implementMethod("Camera", "ViewportPointToRay", function(camera)
    return cameraRays[camera]
end)
roblox.implementMethod("Workspace", "BulkMoveTo", function(workspace, parts, cframes, mode)
    table.insert(workspaceMoves[workspace], { Parts = parts, CFrames = cframes, Mode = mode })
    for index, part in parts do
        part.CFrame = cframes[index]
    end
end)

local function signal()
    local listeners = {}
    local event = { Calls = {} }

    function event:Connect(callback)
        listeners[callback] = true
        return {
            Disconnect = function()
                listeners[callback] = nil
            end,
        }
    end

    function event:Fire(...)
        table.insert(self.Calls, table.pack(...))
        for callback in listeners do
            callback(...)
        end
    end

    event.FireAll = event.Fire
    return event
end

local function newRuntime(sourceRoot)
    local runtime = { Time = 10, Players = {}, Services = {}, Controllers = {} }
    local cache = {}
    local function netEvent()
        local event = signal()
        return {
            Calls = event.Calls,
            On = function(callback)
                local connection = event:Connect(callback)
                return function()
                    connection:Disconnect()
                end
            end,
            Fire = function(...)
                event:Fire(...)
            end,
            FireAll = function(...)
                event:Fire(...)
            end,
        },
            event
    end
    local snapshots, snapshotSignal = netEvent()
    local hits = netEvent()
    runtime.Snapshots = snapshotSignal
    runtime.Net = {
        ZombieSnapshot = snapshots,
        HitConfirmed = hits,
        Shoot = {
            SetCallback = function(callback)
                runtime.ShootCallback = callback
                return function()
                    runtime.ShootCallback = nil
                end
            end,
        },
    }
    cache.Net = runtime.Net
    local replicatedStorage = {
        Packages = { Janitor = "Janitor" },
        Net = "Net",
        Shared = {
            GameConfig = "shared/GameConfig",
            Modules = {
                SpatialHash = "shared/Modules/SpatialHash",
                SwarmMath = "shared/Modules/SwarmMath",
            },
        },
    }
    function replicatedStorage:FindFirstChild(name)
        return self[name]
    end
    local players = { PlayerRemoving = signal() }
    function players:GetPlayers()
        return runtime.Players
    end

    runtime.Heartbeat = signal()
    runtime.RenderStepped = signal()
    local services = {
        ReplicatedStorage = replicatedStorage,
        ServerScriptService = { Net = "Net" },
        Players = players,
        RunService = { Heartbeat = runtime.Heartbeat, RenderStepped = runtime.RenderStepped },
    }
    local janitor = {}
    function janitor.new()
        local entries = {}
        return {
            Add = function(_, object, method)
                table.insert(entries, { object, method })
                return object
            end,
            Destroy = function()
                for _, entry in entries do
                    if entry[2] == true then
                        if type(entry[1]) == "function" then
                            entry[1]()
                        end
                    else
                        entry[1][entry[2]](entry[1])
                    end
                end
                table.clear(entries)
            end,
        }
    end
    cache.Janitor = janitor

    function runtime:Load(path)
        if cache[path] ~= nil then
            return cache[path]
        end
        local controllerName = path:match("^client/Controllers/(.+)$")
        if controllerName and self.Controllers[controllerName] then
            return self.Controllers[controllerName]
        end
        local environment = {
            Vector3 = roblox.Vector3,
            Vector2 = roblox.Vector2,
            CFrame = roblox.CFrame,
            Color3 = roblox.Color3,
            Instance = roblox.Instance,
            Enum = roblox.Enum,
            workspace = runtime.Workspace,
            RaycastParams = {
                new = function()
                    return {}
                end,
            },
            script = {
                Parent = {
                    ZombieService = "server/Services/ZombieService",
                    ZombieController = "client/Controllers/ZombieController",
                    ViewmodelController = "client/Controllers/ViewmodelController",
                    Parent = {
                        Modules = {
                            ProjectileVisuals = "client/Modules/ProjectileVisuals",
                            Spring = "client/Modules/Spring",
                        },
                    },
                },
            },
            game = {
                GetService = function(_, name)
                    return assert(services[name], name)
                end,
            },
            os = {
                clock = function()
                    return self.Time
                end,
            },
            print = function() end,
            task = {
                spawn = function()
                    return coroutine.create(function() end)
                end,
            },
            require = function(modulePath)
                return self:Load(modulePath)
            end,
        }
        local source = fs.readFile(sourceRoot .. "/" .. path .. ".luau")
        local module = luau.load(source, { debugName = path, environment = environment })()
        cache[path] = module
        if controllerName then
            self.Controllers[controllerName] = module
        end
        return module
    end

    function runtime:Player(position)
        local character = roblox.Instance.new("Model")
        for _, name in { "Head", "HumanoidRootPart" } do
            local part = roblox.Instance.new("Part")
            part.Name = name
            part.Position = position
            part.Parent = character
        end
        local player = { Character = character }
        table.insert(self.Players, player)
        return player
    end

    function runtime:RemovePlayer(player)
        local index = table.find(self.Players, player)
        if index then
            table.remove(self.Players, index)
        end
        players.PlayerRemoving:Fire(player)
    end

    function runtime:SetupRendering()
        self.Workspace = roblox.Instance.new("Workspace")
        self.Moves = {}
        workspaceMoves[self.Workspace] = self.Moves
        local assets = roblox.Instance.new("Folder")
        replicatedStorage.Assets = assets
        local template = roblox.Instance.new("Model")
        template.Name = "zombie"
        template.Parent = assets
        for _, name in { "HumanoidRootPart", "Head" } do
            local part = roblox.Instance.new("Part")
            part.Name = name
            part.Parent = template
            local decal = roblox.Instance.new("Decal")
            decal.Parent = part
        end
    end

    function runtime:SetupInput()
        self.InputBegan = signal()
        self.InputEnded = signal()
        services.UserInputService = {
            InputBegan = self.InputBegan,
            InputEnded = self.InputEnded,
            GetMouseLocation = function()
                return roblox.Vector2.zero
            end,
        }
        self.Camera = roblox.Instance.new("Camera")
        self.Camera.CFrame = roblox.CFrame.new(0, 3, 0)
        self.Camera.Focus = roblox.CFrame.new(1, 3, 0)
        self.Workspace.CurrentCamera = self.Camera
        cameraRays[self.Camera] = { Origin = roblox.Vector3.new(0, 3, 0), Direction = roblox.Vector3.new(1, 0, 0) }
        self.Raycasts = {}
        workspaceRays[self.Workspace] = self
        self.Shots = {}
        self.Net.Shoot.Call = function(params)
            table.insert(self.Shots, params)
            return { catch = function() end }
        end
        self.Controllers.ViewmodelController = { ApplyRecoil = function() end }
        self:Load("client/Modules/ProjectileVisuals").start()
    end

    return runtime
end

return newRuntime
