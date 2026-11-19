-- LIVE HAND v1.0 | Delta Executor | Local visual hand
-- 1) Replace SERVER with your deployed Render URL (without trailing slash).
-- 2) Execute this script in Roblox after opening the tracker page in Chrome.
-- Requires executor HTTP request support (request / http_request / syn.request).

local SERVER = "https://YOUR-SERVICE.onrender.com"
local POLL_RATE = 0.09
local SCALE = 3.0
local DEPTH = 2.2
local HEIGHT = 1.35

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer

local httpRequest = request or http_request or (syn and syn.request)
if not httpRequest then
    warn("[LIVE HAND] Executor does not expose request/http_request.")
    return
end

local function getCharacter()
    return player.Character or player.CharacterAdded:Wait()
end

local character = getCharacter()
local root = character:WaitForChild("HumanoidRootPart")

player.CharacterAdded:Connect(function(char)
    character = char
    root = char:WaitForChild("HumanoidRootPart")
end)

local folder = Instance.new("Folder")
folder.Name = "LIVE_HAND_LOCAL"
folder.Parent = workspace

local function makePart(name, size, color, shape)
    local p = Instance.new("Part")
    p.Name = name
    p.Size = size
    p.Color = color
    p.Material = Enum.Material.SmoothPlastic
    p.Anchored = true
    p.CanCollide = false
    p.CanTouch = false
    p.CanQuery = false
    p.CastShadow = false
    if shape then p.Shape = shape end
    p.Parent = folder
    return p
end

local jointColor = Color3.fromRGB(225, 190, 160)
local lineColor = Color3.fromRGB(235, 205, 180)
local joints = {}
local bones = {}
for i = 1, 21 do
    joints[i] = makePart("Joint"..i, Vector3.new(0.13,0.13,0.13), jointColor, Enum.PartType.Ball)
end

local links = {
    {1,2},{2,3},{3,4},{4,5},
    {1,6},{6,7},{7,8},{8,9},
    {6,10},{10,11},{11,12},{12,13},
    {10,14},{14,15},{15,16},{16,17},
    {14,18},{18,19},{19,20},{20,21},
    {1,18}
}
for i = 1, #links do
    bones[i] = makePart("Bone"..i, Vector3.new(0.085,0.1,0.085), lineColor, Enum.PartType.Cylinder)
end

local function setBone(part, a, b)
    local delta = b - a
    local length = delta.Magnitude
    if length < 0.001 then return end
    part.Size = Vector3.new(0.085, length, 0.085)
    part.CFrame = CFrame.lookAt((a+b)/2, b) * CFrame.Angles(math.pi/2,0,0)
end

local latest = nil
local lastPoll = 0
local busy = false
local function fetchPose()
    if busy then return end
    busy = true
    task.spawn(function()
        local ok, response = pcall(function()
            return httpRequest({
                Url = SERVER .. "/pose",
                Method = "GET",
                Headers = {["Cache-Control"] = "no-cache"}
            })
        end)
        if ok and response then
            local body = response.Body or response.body
            if body then
                local decodedOk, decoded = pcall(function()
                    return game:GetService("HttpService"):JSONDecode(body)
                end)
                if decodedOk then latest = decoded end
            end
        end
        busy = false
    end)
end

local smoothed = {}
for i=1,21 do smoothed[i] = Vector3.zero end
local hasPose = false

RunService.RenderStepped:Connect(function()
    local now = os.clock()
    if now - lastPoll >= POLL_RATE then
        lastPoll = now
        fetchPose()
    end

    if not root or not root.Parent or not latest or not latest.detected
        or type(latest.points) ~= "table" or #latest.points ~= 21 then
        for _,p in ipairs(joints) do p.Transparency = 1 end
        for _,p in ipairs(bones) do p.Transparency = 1 end
        hasPose = false
        return
    end

    local alpha = 0.42
    local base = root.CFrame
    local points = {}
    for i, point in ipairs(latest.points) do
        -- Camera coordinates become a hand-shaped plane in front of the avatar.
        local x = (0.5 - point.x) * SCALE
        local y = (0.55 - point.y) * SCALE
        local z = -DEPTH
        local localPos = Vector3.new(x, HEIGHT + y, z)
        local worldPos = (base * CFrame.new(localPos)).Position
        if not hasPose then smoothed[i] = worldPos
        else smoothed[i] = smoothed[i]:Lerp(worldPos, alpha) end
        points[i] = smoothed[i]
        joints[i].Position = points[i]
        joints[i].Transparency = 0
    end
    for i, link in ipairs(links) do
        setBone(bones[i], points[link[1]], points[link[2]])
        bones[i].Transparency = 0
    end
    hasPose = true
end)

print("[LIVE HAND] Running. Set SERVER to your Render URL.")
