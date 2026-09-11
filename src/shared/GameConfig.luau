-- Author: noobs

local GameConfig = {}

GameConfig.Zombies = {
    MaxCount = 100,
    SpawnRadius = 80,
    SpawnHeight = 3,
    NeighborRadius = 8,
    HitboxScale = 1.5,
}

GameConfig.Swarm = {
    SeekWeight = 1.0,
    SeparationWeight = 1.5,
    SeparationRadius = 4,
    MaxSpeed = 8,
    MaxForce = 15,
}

GameConfig.Weapon = {
    FireRate = 10,
    MaxRaycastDistance = 200,
    RateLimitPerSecond = 10,
}

GameConfig.Tracer = {
    Speed = 250,
    Gravity = 30,
    Lifetime = 1.5,
    Color = Color3.fromRGB(255, 180, 50),
    Thickness = 0.08,
}

GameConfig.Viewmodel = {
    Offset = CFrame.new(0.5, -0.5, -1.5),
    SwayAmount = 0.05,
    SwaySpeed = 8,
    BobAmount = 0.03,
    BobSpeed = 8,
    RecoilForce = Vector3.new(0, 0.2, 0.05),
}

return GameConfig
