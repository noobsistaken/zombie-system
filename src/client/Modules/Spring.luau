-- Author: noobs

local Spring = {}
local MAX_VELOCITY = 50

export type Spring = {
    Position: Vector3,
    Velocity: Vector3,
    Target: Vector3,
    Damping: number,
    Stiffness: number,

    SetTarget: (self: Spring, target: Vector3) -> (),
    Impulse: (self: Spring, force: Vector3) -> (),
    Update: (self: Spring, dt: number) -> Vector3,
}

function Spring.new(damping: number?, stiffness: number?): Spring
    return {
        Position = Vector3.zero,
        Velocity = Vector3.zero,
        Target = Vector3.zero,
        Damping = damping or 0.5,
        Stiffness = stiffness or 10,
        SetTarget = Spring.SetTarget,
        Impulse = Spring.Impulse,
        Update = Spring.Update,
    }
end

function Spring.SetTarget(self: Spring, target: Vector3)
    self.Target = target
end

function Spring.Impulse(self: Spring, force: Vector3)
    self.Velocity = self.Velocity + force
end

function Spring.Update(self: Spring, dt: number): Vector3
    local displacement = self.Target - self.Position
    local springForce = displacement * self.Stiffness
    local dampingForce = self.Velocity * self.Damping
    local acceleration = springForce - dampingForce

    self.Velocity = self.Velocity + acceleration * dt
    if self.Velocity.Magnitude > MAX_VELOCITY then
        self.Velocity = self.Velocity.Unit * MAX_VELOCITY
    end

    self.Position = self.Position + self.Velocity * dt
    return self.Position
end

return Spring
