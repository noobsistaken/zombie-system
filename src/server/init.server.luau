-- Author: noobs

local ZombieService = require(script.Services.ZombieService)
local WeaponService = require(script.Services.WeaponService)

ZombieService.start()
WeaponService.start()

game:BindToClose(function()
    WeaponService:Destroy()
    ZombieService:Destroy()
end)
