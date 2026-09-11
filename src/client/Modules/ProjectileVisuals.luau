-- Author: noobs

local RunService = game:GetService("RunService")

local ProjectileVisuals = {}

export type TracerConfig = {
    Speed: number,
    Gravity: number,
    Lifetime: number,
    Color: Color3,
    Thickness: number,
}

export type ActiveTracer = {
    Part: Part,
    Velocity: Vector3,
    TimeRemaining: number,
}

local activeTracers: { ActiveTracer } = {}
local renderConnection: RBXScriptConnection? = nil

local function CreateTracerPart(origin: Vector3, config: TracerConfig): Part
    local part = Instance.new("Part")
    part.Name = "Tracer"
    part.Size = Vector3.new(config.Thickness, config.Thickness, 2)
    part.Color = config.Color
    part.Material = Enum.Material.Neon
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    part.CastShadow = false
    part.Position = origin
    part.Parent = workspace

    return part
end

function ProjectileVisuals.FireTracer(origin: Vector3, direction: Vector3, config: TracerConfig)
    local normalizedDir = direction.Unit
    local velocity = normalizedDir * config.Speed

    local part = CreateTracerPart(origin, config)

    local tracer: ActiveTracer = {
        Part = part,
        Velocity = velocity,
        TimeRemaining = config.Lifetime,
    }

    table.insert(activeTracers, tracer)
end

local function UpdateTracers(dt: number)
    local i = 1
    while i <= #activeTracers do
        local tracer = activeTracers[i]

        tracer.Velocity = tracer.Velocity + Vector3.new(0, -30 * dt, 0)

        local newPos = tracer.Part.Position + tracer.Velocity * dt

        if tracer.Velocity.Magnitude > 0.1 then
            tracer.Part.CFrame = CFrame.lookAt(newPos, newPos + tracer.Velocity)
        else
            tracer.Part.Position = newPos
        end

        tracer.TimeRemaining -= dt

        if tracer.TimeRemaining <= 0 then
            tracer.Part:Destroy()
            table.remove(activeTracers, i)
        else
            i += 1
        end
    end
end

function ProjectileVisuals.start()
    if not renderConnection then
        renderConnection = RunService.RenderStepped:Connect(UpdateTracers)
    end
end

function ProjectileVisuals.Destroy()
    if renderConnection then
        renderConnection:Disconnect()
        renderConnection = nil
    end
    for _, tracer in activeTracers do
        tracer.Part:Destroy()
    end
    table.clear(activeTracers)
end

return ProjectileVisuals
