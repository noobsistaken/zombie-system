-- Author: noobs

local ProjectileVisuals = require(script.Modules.ProjectileVisuals)
local ZombieController = require(script.Controllers.ZombieController)
local ViewmodelController = require(script.Controllers.ViewmodelController)
local WeaponController = require(script.Controllers.WeaponController)

ProjectileVisuals.start()
ZombieController.start()
ViewmodelController.start()
WeaponController.start()

script.Destroying:Connect(function()
    WeaponController:Destroy()
    ViewmodelController:Destroy()
    ZombieController:Destroy()
    ProjectileVisuals.Destroy()
end)
