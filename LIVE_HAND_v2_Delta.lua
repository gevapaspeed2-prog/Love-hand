-- LIVE HAND v2.0 | TWO HANDS + DEPTH | Delta Executor
-- Replace nothing: this script is already configured for live-hand.onrender.com.
-- Needs executor HTTP request support: request / http_request / syn.request.

local SERVER = "https://live-hand.onrender.com"
local POLL_RATE = 0.075
local SMOOTHING = 0.38
local WIDTH_SCALE = 3.0
local HEIGHT_SCALE = 3.0
local DEPTH_SCALE = 4.2
local FORWARD = 2.15
local BASE_HEIGHT = 1.35

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local HttpService = game:GetService("HttpService")

local httpRequest = request or http_request or (syn and syn.request)
if not httpRequest then
    warn("[LIVE HAND v2] HTTP request API unavailable in this executor.")
    return
end

local folder = Instance.new("Folder")
folder.Name = "LIVE_HAND_V2_LOCAL"
folder.Parent = workspace

local function makePart(parent, name, size, color, shape, material)
    local p = Instance.new("Part")
    p.Name = name
    p.Size = size
    p.Color = color
    p.Material = material or Enum.Material.SmoothPlastic
    p.Anchored = true
    p.CanCollide = false
    p.CanTouch = false
    p.CanQuery = false
    p.CastShadow = false
    p.Shape = shape or Enum.PartType.Block
    p.TopSurface = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth
    p.Parent = parent
    return p
end

local links = {
    {1,2},{2,3},{3,4},{4,5},
    {1,6},{6,7},{7,8},{8,9},
    {6,10},{10,11},{11,12},{12,13},
    {10,14},{14,15},{15,16},{16,17},
    {14,18},{18,19},{19,20},{20,21},
    {1,18}
}

local rigs = {}
local colors = {
    Right = Color3.fromRGB(110, 220, 255),
    Left = Color3.fromRGB(255, 145, 205)
}

local function createRig(label)
    local rigFolder = Instance.new("Folder")
    rigFolder.Name = label .. "_HAND"
    rigFolder.Parent = folder
    local rig = {folder=rigFolder, joints={}, bones={}, palm=nil, smooth={}, visible=false}
    local color = colors[label]
    for i=1,21 do
        rig.joints[i] = makePart(rigFolder, "Joint"..i, Vector3.new(0.16,0.16,0.16), color, Enum.PartType.Ball)
        rig.smooth[i] = nil
    end
    for i=1,#links do
        rig.bones[i] = makePart(rigFolder, "Bone"..i, Vector3.new(0.105,0.2,0.105), color, Enum.PartType.Cylinder)
    end
    -- Palm shell gives the hand a visible 3D volume instead of a flat wireframe.
    rig.palm = makePart(rigFolder, "Palm", Vector3.new(0.8,0.18,0.95), Color3.fromRGB(220,185,158), Enum.PartType.Block)
    return rig
end

rigs.Right = createRig("Right")
rigs.Left = createRig("Left")

local function hideRig(rig)
    for _,p in ipairs(rig.joints) do p.Transparency=1 end
    for _,p in ipairs(rig.bones) do p.Transparency=1 end
    rig.palm.Transparency=1
    rig.visible=false
end

local function showPart(p)
    p.Transparency=0
end

local function setBone(part, a, b)
    local delta=b-a
    local length=delta.Magnitude
    if length < 0.005 then
        part.Transparency=1
        return
    end
    part.Size=Vector3.new(0.105,length,0.105)
    part.CFrame=CFrame.lookAt((a+b)/2,b)*CFrame.Angles(math.pi/2,0,0)
    showPart(part)
end

local function findRoot()
    local char=player.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart")
end

local latest=nil
local busy=false
local lastPoll=0
local function poll()
    if busy then return end
    busy=true
    task.spawn(function()
        local ok,response=pcall(function()
            return httpRequest({
                Url=SERVER.."/pose",
                Method="GET",
                Headers={["Cache-Control"]="no-cache"}
            })
        end)
        if ok and response then
            local body=response.Body or response.body
            if body then
                local decodedOk,decoded=pcall(function() return HttpService:JSONDecode(body) end)
                if decodedOk then latest=decoded end
            end
        end
        busy=false
    end)
end

local function updateRig(rig, hand, root, side)
    if not hand or type(hand.points)~="table" or #hand.points~=21 then
        hideRig(rig)
        return
    end

    local base=root.CFrame
    local positions={}
    for i,p in ipairs(hand.points) do
        -- MediaPipe z supplies relative depth. This makes curled fingertips move
        -- toward/away from the camera rather than staying on a 2D sheet.
        local x=(0.5-(tonumber(p.x) or 0.5))*WIDTH_SCALE
        local y=(0.55-(tonumber(p.y) or 0.5))*HEIGHT_SCALE
        local z=(tonumber(p.z) or 0)*DEPTH_SCALE
        local offset=Vector3.new(x,BASE_HEIGHT+y,-FORWARD-z)
        local world=(base*CFrame.new(offset)).Position

        if rig.smooth[i] then
            rig.smooth[i]=rig.smooth[i]:Lerp(world,SMOOTHING)
        else
            rig.smooth[i]=world
        end
        positions[i]=rig.smooth[i]
        rig.joints[i].Position=positions[i]
        showPart(rig.joints[i])
    end

    for i,link in ipairs(links) do
        setBone(rig.bones[i],positions[link[1]],positions[link[2]])
    end

    -- Orient a chunky palm between wrist and middle-finger base, using the
    -- index-to-pinky direction as the palm width axis.
    local wrist=positions[1]
    local indexBase=positions[6]
    local pinkyBase=positions[18]
    local middleBase=positions[10]
    local up=(middleBase-wrist)
    local right=(indexBase-pinkyBase)
    if up.Magnitude>0.02 and right.Magnitude>0.02 then
        up=up.Unit
        right=(right-up*right:Dot(up)).Unit
        local back=right:Cross(up).Unit
        local center=(wrist+middleBase)/2
        local width=(indexBase-pinkyBase).Magnitude*1.12
        local length=(middleBase-wrist).Magnitude*1.12
        rig.palm.Size=Vector3.new(math.max(0.35,width),0.20,math.max(0.45,length))
        rig.palm.CFrame=CFrame.fromMatrix(center,right,up,back)
        showPart(rig.palm)
    end
    rig.visible=true
end

local function findHands()
    local result={Right=nil,Left=nil}
    if not latest or type(latest.hands)~="table" then return result end
    for _,hand in ipairs(latest.hands) do
        local key=(hand.handedness=="Left") and "Left" or "Right"
        result[key]=hand
    end
    return result
end

RunService.RenderStepped:Connect(function()
    local now=os.clock()
    if now-lastPoll>=POLL_RATE then
        lastPoll=now
        poll()
    end
    local root=findRoot()
    if not root then
        hideRig(rigs.Right);hideRig(rigs.Left)
        return
    end
    local hands=findHands()
    updateRig(rigs.Right,hands.Right,root,"Right")
    updateRig(rigs.Left,hands.Left,root,"Left")
end)

player.CharacterAdded:Connect(function()
    task.wait(1)
    for _,rig in pairs(rigs) do
        for i=1,21 do rig.smooth[i]=nil end
    end
end)

print("[LIVE HAND v2] Two-hand 3D tracking active. Open the tracker page and start camera.")
