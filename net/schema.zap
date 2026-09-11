opt server_output = "generated/server.luau"
opt client_output = "generated/client.luau"
opt casing = "PascalCase"
opt write_checks = true
opt typescript = false
opt call_default = "ManyAsync"
opt yield_type = "promise"
opt async_lib = "require(game:GetService('ReplicatedStorage').Packages.Promise)"

type ZombiePacket = struct {
    P: Vector3,
    H: u8 (0..1),
}

event ZombieSnapshot = {
    from: Server,
    type: Reliable,
    data: map { [f64]: ZombiePacket },
}

funct Shoot = {
    call: Async,
    args: struct {
        Origin: Vector3,
        Direction: Vector3,
        HitZombieId: f64?,
    },
    rets: boolean,
}

event HitConfirmed = {
    from: Server,
    type: Reliable,
    data: Vector3,
}
