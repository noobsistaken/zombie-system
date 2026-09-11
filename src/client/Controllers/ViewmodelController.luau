-- Author: noobs

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local Janitor = require(ReplicatedStorage.Packages.Janitor)
local Spring = require(script.Parent.Parent.Modules.Spring)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local Config = GameConfig.Viewmodel
local ZOOM_THRESHOLD = 1.5

local ViewmodelController = {}
local started = false

local ControllerJanitor = Janitor.new()
local viewmodel: Model? = nil
local swaySpring: Spring.Spring
local bobSpring: Spring.Spring
local recoilSpring: Spring.Spring

local lastMousePos = Vector2.zero
local walkCycle = 0
local isFirstPerson = true

local function GetCamera(): Camera
    return workspace.CurrentCamera
end

local function IsInFirstPerson(): boolean
    local camera = workspace.CurrentCamera
    if not camera then
        return false
    end
    local dist = (camera.CFrame.Position - camera.Focus.Position).Magnitude
    return dist < ZOOM_THRESHOLD
end

local function GetPlayerVelocity(): Vector3
    local player = Players.LocalPlayer
    if not player then
        return Vector3.zero
    end

    local character = player.Character
    if not character then
        return Vector3.zero
    end

    local root = character:FindFirstChild("HumanoidRootPart")
    if not root or not root:IsA("BasePart") then
        return Vector3.zero
    end

    return root.AssemblyLinearVelocity
end

local function SetupViewmodel()
    local Assets = ReplicatedStorage:FindFirstChild("Assets")
    if not Assets then
        warn("[ViewmodelController] Assets folder not found!")
        return
    end

    local gunTemplate = Assets:FindFirstChild("tommy gun") or Assets:FindFirstChild("gun")
    if not gunTemplate then
        warn("[ViewmodelController] Gun model not found in Assets!")
        return
    end

    local cloned = gunTemplate:Clone()
    local model: Model

    if cloned:IsA("Tool") then
        model = Instance.new("Model")
        model.Name = "Viewmodel"

        for _, child in cloned:GetChildren() do
            if child:IsA("BasePart") or child:IsA("Model") then
                child.Parent = model
            end
        end

        local handle = cloned:FindFirstChild("Handle")
        if handle and handle:IsA("BasePart") then
            model.PrimaryPart = handle
        end

        cloned:Destroy()
    else
        model = cloned :: Model
        model.Name = "Viewmodel"
    end

    for _, part in model:GetDescendants() do
        if part:IsA("BasePart") then
            part.CanCollide = false
            part.CanQuery = false
            part.CanTouch = false
            part.CastShadow = false
            part.Anchored = true
        end
    end

    local modelFolder = workspace:FindFirstChild("ViewmodelFolder")
    if not modelFolder then
        modelFolder = Instance.new("Folder")
        modelFolder.Name = "ViewmodelFolder"
        modelFolder.Parent = workspace
    end

    model.Parent = modelFolder
    ControllerJanitor:Add(model, "Destroy")

    viewmodel = model

    print("[ViewmodelController] Viewmodel loaded")
end

local function OnRenderStepped(dt: number)
    if not viewmodel then
        return
    end

    local camera = GetCamera()
    if not camera then
        return
    end

    local inFirstPerson = IsInFirstPerson()

    if inFirstPerson and not isFirstPerson then
        local folder = workspace:FindFirstChild("ViewmodelFolder")
        if folder then
            viewmodel.Parent = folder
        end
        isFirstPerson = true
    elseif not inFirstPerson and isFirstPerson then
        viewmodel.Parent = nil
        isFirstPerson = false
    end

    if not inFirstPerson then
        return
    end

    local mousePos = UserInputService:GetMouseLocation()
    local mouseDelta = (mousePos - lastMousePos) * Config.SwayAmount
    lastMousePos = mousePos

    swaySpring:SetTarget(Vector3.new(-mouseDelta.X, mouseDelta.Y, 0))
    local sway = swaySpring:Update(dt)

    local velocity = GetPlayerVelocity()
    local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude

    if speed > 1 then
        walkCycle += dt * Config.BobSpeed * (speed / 16)
        local bobX = math.sin(walkCycle) * Config.BobAmount
        local bobY = math.abs(math.cos(walkCycle)) * Config.BobAmount
        bobSpring:SetTarget(Vector3.new(bobX, bobY, 0))
    else
        bobSpring:SetTarget(Vector3.zero)
        walkCycle = 0
    end
    local bob = bobSpring:Update(dt)

    recoilSpring:SetTarget(Vector3.zero)
    local recoil = recoilSpring:Update(dt)

    local combinedOffset = sway + bob + recoil
    local offsetCFrame = CFrame.new(combinedOffset)

    local primaryPart = viewmodel.PrimaryPart or viewmodel:FindFirstChildWhichIsA("BasePart")
    if primaryPart then
        viewmodel:PivotTo(camera.CFrame * Config.Offset * offsetCFrame)
    end
end

function ViewmodelController:ApplyRecoil()
    if recoilSpring then
        recoilSpring:Impulse(Config.RecoilForce)
    end
end

function ViewmodelController.start()
    if started then
        return
    end
    started = true
    swaySpring = Spring.new(5, Config.SwaySpeed)
    bobSpring = Spring.new(4, Config.BobSpeed)
    recoilSpring = Spring.new(3, 15)

    lastMousePos = UserInputService:GetMouseLocation()

    SetupViewmodel()

    ControllerJanitor:Add(RunService.RenderStepped:Connect(OnRenderStepped), "Disconnect")

    print("[ViewmodelController] Started")
end

function ViewmodelController:Destroy()
    ControllerJanitor:Destroy()
end

return ViewmodelController
