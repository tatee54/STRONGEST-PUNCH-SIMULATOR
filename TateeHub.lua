local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService   = game:GetService("TeleportService")
local HttpService       = game:GetService("HttpService")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local ContentProvider   = game:GetService("ContentProvider")
task.spawn(function()
	pcall(function() ContentProvider:PreloadAsync({ "rbxassetid://70589572494155" }) end)
end)

local player = Players.LocalPlayer
while not player do
	task.wait()
	player = Players.LocalPlayer
end

local env = (getgenv and getgenv()) or _G
do
	local old = env.TateeHubGui
	if old then
		local okCheck, running = pcall(function()
			local pg = player:FindFirstChild("PlayerGui")
			return pg ~= nil and old.Parent == pg
		end)
		if okCheck and running then
			warn("[TateeHub] สคริปต์รันอยู่แล้ว -> ไม่รันซ้ำ")
			return
		end
		pcall(function() old:Destroy() end)
	end
end

local FOLDER = "TateeHub"
do
	if makefolder and isfolder and not isfolder(FOLDER) then
		pcall(makefolder, FOLDER)
	end
end

local IMAGE_ID    = "70589572494155"
local SCRIPT_URL  = "https://raw.githubusercontent.com/tatee54/STRONGEST-PUNCH-SIMULATOR/refs/heads/main/Script"
local SAVE_FILE   = FOLDER .. "/TateeHub_settings.json"

local PULL_RANGE      = 700
local NOHOP_MAX_STAGE = 10
local HOP_STAGE_MIN   = 11
local HOP_RARITY      = 1
local MIN_STAGE       = 20
local LOAD_GRACE      = 12
local EMPTY_TIMEOUT   = 8

local PULL_TIME_FAST    = 0.1
local PULL_TIME_SLOW    = 0.3
local MIN_ITEMS_STAGE20 = 50

local HOP_MIN_PLAYERS = 3
local HOP_MAX_PAGES   = 3
local HOP_RANDOM      = true
local HOP_COOLDOWN    = 3

env.TateeHubRunId = (env.TateeHubRunId or 0) + 1
local runId = env.TateeHubRunId
local function alive() return env.TateeHubRunId == runId end

local settings = { running = false, autoExec = false, hopping = false, hopTime = 0 }

local function loadSettings()
	if isfile and readfile and isfile(SAVE_FILE) then
		local ok, data = pcall(function()
			return HttpService:JSONDecode(readfile(SAVE_FILE))
		end)
		if ok and type(data) == "table" then
			settings.running  = data.running == true
			settings.autoExec = data.autoExec == true
			settings.hopping  = data.hopping == true
			settings.hopTime  = tonumber(data.hopTime) or 0
		end
	end
end

local function saveSettings()
	if writefile then
		pcall(function() writefile(SAVE_FILE, HttpService:JSONEncode(settings)) end)
	end
end

loadSettings()

local queueFn = queue_on_teleport
	or queueonteleport
	or (syn and syn.queue_on_teleport)
	or (fluxus and fluxus.queue_on_teleport)

local queued = false

local function buildBootstrap()
	return table.concat({
		'repeat task.wait() until game:GetService("Players").LocalPlayer',
		'local ok = false',
		'for _ = 1, 3 do',
		'if ok then break end',
		string.format('ok = pcall(function() loadstring(game:HttpGet(%q))() end)', SCRIPT_URL),
		'if not ok then task.wait(3) end',
		'end',
		'if not ok then warn("[TateeHub] AutoExec โหลดสคริปต์ไม่สำเร็จ") end',
	}, "\n")
end

local function queueSelf()
	if queued or not settings.autoExec then return end
	if not queueFn then
		warn("[AutoExec] executor นี้ไม่มี queue_on_teleport (ให้วางสคริปต์ในโฟลเดอร์ autoexec ของ executor แทน)")
		return
	end
	local ok, err = pcall(queueFn, buildBootstrap())
	if ok then
		queued = true
	else
		warn("[AutoExec] queue ล้มเหลว:", err)
	end
end

player.OnTeleport:Connect(function(state)
	if not alive() then return end
	if state == Enum.TeleportState.Failed then
		queued = false
		return
	end
	settings.hopping = true
	settings.hopTime = os.time()
	if writefile then
		pcall(function() writefile(SAVE_FILE, HttpService:JSONEncode(settings)) end)
	end
	queueSelf()
end)

local running        = false
local remote         = nil
task.spawn(function()
	remote = ReplicatedStorage:WaitForChild("RemoteEvent", 30)
end)
local dropItems      = {}
local lastSeenItem   = os.clock()
local serverJoinTime = os.clock()
local currentStage   = nil

local function getBasePart(obj)
	if not obj then return nil end
	if obj:IsA("BasePart") then return obj end
	if obj:IsA("Model") then
		return obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
	end
	return obj:FindFirstChildWhichIsA("BasePart", true)
end

local function scanItems()
	local newDropItems = {}

	local mapFolder    = workspace:FindFirstChild("Map")
	local stagesFolder = mapFolder and mapFolder:FindFirstChild("Stages")
	local boostsFolder = stagesFolder and stagesFolder:FindFirstChild("Boosts")

	if boostsFolder then
		for _, stageFolder in ipairs(boostsFolder:GetChildren()) do
			for _, obj in ipairs(stageFolder:GetChildren()) do
				local cleanName = obj.Name:gsub("^%s+", ""):gsub("%s+$", "")
				local stageStr, rarityStr = cleanName:match("MAP_(%d+)_(%d+)")
				local stage  = tonumber(stageStr)
				local rarity = tonumber(rarityStr)

				if stage and rarity then
					local part = getBasePart(obj)
					if part then
						newDropItems[part] = { rarity = rarity, stage = stage }
					end
				end
			end
		end
	end

	if next(newDropItems) then
		dropItems = newDropItems
	end
end

local isHopping   = false
local lastHopTime = 0
local visitedJobs = {}
visitedJobs[game.JobId] = true

TeleportService.TeleportInitFailed:Connect(function()
	if not alive() then return end
	isHopping = false
	queued = false
	settings.hopping = false
	saveSettings()
end)

local function fetchServers(placeId)
	local allServers = {}
	local cursor = nil

	for _ = 1, HOP_MAX_PAGES do
		local url = "https://games.roblox.com/v1/games/" .. placeId
			.. "/servers/Public?sortOrder=Desc&limit=100"
		if cursor then url = url .. "&cursor=" .. cursor end

		local ok, result = pcall(function()
			local body
			if syn and syn.request then
				body = syn.request({ Url = url, Method = "GET" }).Body
			elseif request then
				body = request({ Url = url, Method = "GET" }).Body
			else
				body = game:HttpGet(url)
			end
			return HttpService:JSONDecode(body)
		end)

		if not ok or not result or not result.data then break end
		for _, s in ipairs(result.data) do table.insert(allServers, s) end

		cursor = result.nextPageCursor
		if not cursor then break end
	end

	return allServers
end

local function ServerHop()
	if isHopping or not running then return end
	if os.clock() - lastHopTime < HOP_COOLDOWN then return end

	isHopping = true
	lastHopTime = os.clock()
	print("[HOP] กำลังหาเซิร์ฟ... (ด่าน " .. tostring(currentStage) .. ")")

	local placeId = game.PlaceId
	local servers = fetchServers(placeId)

	local function collect(minPlayers)
		local list = {}
		for _, s in ipairs(servers) do
			if s.id ~= game.JobId and not visitedJobs[s.id]
				and s.playing < s.maxPlayers and s.playing >= minPlayers then
				table.insert(list, s)
			end
		end
		return list
	end

	local candidates = collect(HOP_MIN_PLAYERS)
	if #candidates == 0 then candidates = collect(1) end

	if #candidates == 0 then
		print("[HOP] ไม่เจอเซิร์ฟใหม่ ล้างประวัติแล้วลองใหม่")
		visitedJobs = {}
		visitedJobs[game.JobId] = true
		candidates = collect(1)
	end

	if #candidates == 0 then
		print("[HOP] ไม่เจอเซิร์ฟว่างเลย ลองใหม่ภายหลัง")
		isHopping = false
		return
	end

	local target
	if HOP_RANDOM then
		target = candidates[math.random(1, #candidates)]
	else
		table.sort(candidates, function(a, b) return a.playing > b.playing end)
		target = candidates[1]
	end

	print(string.format("[HOP] ไปเซิร์ฟ %s (%d/%d คน)", target.id, target.playing, target.maxPlayers))
	visitedJobs[target.id] = true

	settings.running = running
	settings.hopping = true
	settings.hopTime = os.time()
	saveSettings()
	queued = false
	queueSelf()

	local tpOk = pcall(function()
		TeleportService:TeleportToPlaceInstance(placeId, target.id, player)
	end)
	if not tpOk then
		settings.hopping = false
		queued = false
		saveSettings()
	end

	task.wait(3)
	serverJoinTime = os.clock()
	lastSeenItem = os.clock()
	isHopping = false
end

local function pullItem(item, info, rootPart, pullTime)
	local itemName  = item.Name
	local itemRef   = item
	local startTime = os.clock()

	pcall(function()
		itemRef.Anchored   = false
		itemRef.CanCollide = false
		itemRef.CFrame     = rootPart.CFrame * CFrame.new(0, 0, -1)
	end)

	if firetouchinterest and itemRef.Parent then
		pcall(function() firetouchinterest(rootPart, itemRef, 0) end)
	end

	local elapsed = os.clock() - startTime
	if elapsed < pullTime then task.wait(pullTime - elapsed) end

	pcall(function()
		if itemRef.Parent then itemRef.CFrame = rootPart.CFrame end
	end)
	if firetouchinterest and itemRef.Parent then
		pcall(function() firetouchinterest(rootPart, itemRef, 1) end)
	end

	pcall(function()
		if itemRef and itemRef.Parent then itemRef:Destroy() end
	end)

	dropItems[item] = nil
	print("[DROP]", itemName, "stage", info.stage, "rarity", info.rarity)
end

local function countStage20Items(rootPart)
	local count = 0
	for item, info in pairs(dropItems) do
		if item and item.Parent and info.stage >= MIN_STAGE
			and (item.Position - rootPart.Position).Magnitude <= PULL_RANGE then
			count = count + 1
		end
	end
	return count
end

task.spawn(function()
	while alive() do
		task.wait(0.7)
		if running and remote then
			pcall(function() remote:FireServer({"Activate_Punch"}) end)
			pcall(function() remote:FireServer({"UpgradeCurrentPet"}) end)
		end
	end
end)

task.spawn(function()
	while alive() do
		task.wait(0.3)
		if running and remote then
			pcall(function() remote:FireServer({"WarpPlrToOtherMap", "Next"}) end)
		end
	end
end)

task.spawn(function()
	while alive() do
		task.wait(0.7)
		if running then scanItems() end
	end
end)

player.CharacterAdded:Connect(function()
	if not alive() then return end
	dropItems = {}
	currentStage = nil
	serverJoinTime = os.clock()
	lastSeenItem = os.clock()
	task.spawn(function()
		local t = 0
		while t < 5 and alive() do
			if running then scanItems() end
			task.wait(0.2)
			t = t + 0.2
		end
	end)
end)

task.spawn(function()
	while alive() do
		task.wait(0.05)
		if not running then continue end

		local character = player.Character
		if not character then continue end
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if not rootPart then
			lastSeenItem = os.clock()
			continue
		end

		local bestItem, bestInfo, bestDist = nil, nil, math.huge
		for item, info in pairs(dropItems) do
			if item and item.Parent then
				local d = (item.Position - rootPart.Position).Magnitude
				if d <= PULL_RANGE then
					if not bestInfo
						or info.rarity > bestInfo.rarity
						or (info.rarity == bestInfo.rarity and d < bestDist) then
						bestItem, bestInfo, bestDist = item, info, d
					end
				end
			else
				dropItems[item] = nil
			end
		end

		if bestItem then
			if bestInfo.stage ~= currentStage then
				currentStage = bestInfo.stage
				print("[STAGE] ตอนนี้อยู่ด่าน", currentStage)
			end
			lastSeenItem = os.clock()

			if currentStage >= MIN_STAGE then
				local remaining = countStage20Items(rootPart)
				if remaining < MIN_ITEMS_STAGE20 then
					print("[STAGE20] ของเหลือ " .. remaining .. " ชิ้น → ย้ายเซิร์ฟ")
					task.spawn(ServerHop)
				else
					for item, info in pairs(dropItems) do
						if not running then break end
						if item and item.Parent and info.stage >= MIN_STAGE
							and (item.Position - rootPart.Position).Magnitude <= PULL_RANGE then
							pullItem(item, info, rootPart, PULL_TIME_SLOW)
						end
					end
				end
			elseif currentStage <= NOHOP_MAX_STAGE then
				pullItem(bestItem, bestInfo, rootPart, PULL_TIME_FAST)
			else
				if currentStage >= HOP_STAGE_MIN and bestInfo.rarity <= HOP_RARITY then
					task.spawn(ServerHop)
				end
				pullItem(bestItem, bestInfo, rootPart, PULL_TIME_SLOW)
			end
		else
			local canHop = (currentStage == nil) or (currentStage > NOHOP_MAX_STAGE)
			if canHop
				and os.clock() - serverJoinTime > LOAD_GRACE
				and os.clock() - lastSeenItem > EMPTY_TIMEOUT then
				task.spawn(ServerHop)
			end
		end
	end
end)

local gui = Instance.new("ScreenGui")
gui.Name = "TateeGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 999
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")
env.TateeHubGui = gui

local GREEN = Color3.fromRGB(50, 200, 100)
local RED   = Color3.fromRGB(200, 50, 50)
local MINT  = Color3.fromRGB(0, 255, 170)

local function makeDraggable(obj)
	local dragging, dragStart, startPos = false, nil, nil
	local moved = false

	obj.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			moved = false
			dragStart = input.Position
			startPos = obj.Position
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			local d = input.Position - dragStart
			if d.Magnitude > 5 then moved = true end
			obj.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
				startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	return function() return moved end
end

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 200, 0, 172)
main.Position = UDim2.new(0.5, -100, 0.4, 0)
main.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
main.BorderSizePixel = 0
main.Active = true
main.Parent = gui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 14)

local stroke = Instance.new("UIStroke")
stroke.Color = MINT
stroke.Thickness = 2
stroke.Parent = main

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 30)
title.Position = UDim2.new(0, 0, 0, 6)
title.BackgroundTransparency = 1
title.Text = "Tatee 67"
title.Font = Enum.Font.Cartoon
title.TextSize = 22
title.TextColor3 = MINT
title.Parent = main

local function makeToggleButton(text, posY)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, 160, 0, 30)
	b.Position = UDim2.new(0.5, -80, 0, posY)
	b.BackgroundColor3 = RED
	b.Text = text .. " : OFF"
	b.Font = Enum.Font.Cartoon
	b.TextSize = 18
	b.TextColor3 = Color3.fromRGB(255, 255, 255)
	b.AutoButtonColor = false
	b.Parent = main
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 10)
	return b
end

local function setToggleLook(btn, text, on)
	btn.Text = text .. (on and " : ON" or " : OFF")
	TweenService:Create(btn, TweenInfo.new(0.25), {
		BackgroundColor3 = on and GREEN or RED
	}):Play()
end

local startBtn = makeToggleButton("Start", 40)
local autoBtn  = makeToggleButton("Auto Execute", 76)

local credit = Instance.new("TextLabel")
credit.Size = UDim2.new(1, 0, 0, 24)
credit.Position = UDim2.new(0, 0, 0, 142)
credit.BackgroundTransparency = 1
credit.Text = "YouTube tatee 67"
credit.Font = Enum.Font.Cartoon
credit.TextSize = 16
credit.TextColor3 = Color3.fromRGB(255, 80, 80)
credit.Parent = main

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -10, 0, 30)
statusLabel.Position = UDim2.new(0, 5, 0, 108)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = ""
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextSize = 11
statusLabel.TextWrapped = true
statusLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
statusLabel.Parent = main

local function refreshStatus()
	if not settings.autoExec then
		statusLabel.Text = ""
		return
	end
	local msg, good
	if not queueFn then
		msg, good = "AutoExec: executor has no queue_on_teleport", false
	else
		msg, good = "AutoExec: READY", true
	end
	statusLabel.Text = msg
	statusLabel.TextColor3 = good and GREEN or Color3.fromRGB(255, 120, 120)
end

local function setRunning(on)
	running = on
	settings.running = on
	if on then
		serverJoinTime = os.clock()
		lastSeenItem = os.clock()
		scanItems()
	end
	setToggleLook(startBtn, "Start", on)
	saveSettings()
end

startBtn.MouseButton1Click:Connect(function()
	setRunning(not running)
end)

local function setAutoExec(on)
	settings.autoExec = on
	setToggleLook(autoBtn, "Auto Execute", on)
	saveSettings()
	refreshStatus()
end

autoBtn.MouseButton1Click:Connect(function()
	setAutoExec(not settings.autoExec)
end)

local circle = Instance.new("ImageButton")
circle.Size = UDim2.new(0, 50, 0, 50)
circle.Position = UDim2.new(0, 20, 0, 50)
circle.BackgroundTransparency = 1
circle.BorderSizePixel = 0
circle.AutoButtonColor = false
circle.ClipsDescendants = true
circle.ScaleType = Enum.ScaleType.Crop
circle.Parent = gui

local circleAspect = Instance.new("UIAspectRatioConstraint")
circleAspect.AspectRatio = 1
circleAspect.Parent = circle

Instance.new("UICorner", circle).CornerRadius = UDim.new(0.5, 0)

local circleStroke = Instance.new("UIStroke")
circleStroke.Color = MINT
circleStroke.Thickness = 2
circleStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
circleStroke.Parent = circle

local fallbackT = Instance.new("TextLabel")
fallbackT.Size = UDim2.new(1, 0, 1, 0)
fallbackT.BackgroundTransparency = 1
fallbackT.Text = "T"
fallbackT.Font = Enum.Font.Cartoon
fallbackT.TextSize = 36
fallbackT.TextColor3 = MINT
fallbackT.Visible = (IMAGE_ID == "")
fallbackT.Parent = circle

local IMAGE_FILE = FOLDER .. "/TateeHub_logo_v2.png"
local getAsset   = getcustomasset or getsynasset or (syn and syn.getcustomasset)

local LOGO_B64 = [=[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]=]

local function b64decode(data)
	local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	local map = {}
	for i = 1, #chars do map[chars:byte(i)] = i - 1 end
	local out, n = {}, 0
	local buf, bits = 0, 0
	for i = 1, #data do
		local v = map[data:byte(i)]
		if v then
			buf = buf * 64 + v
			bits = bits + 6
			if bits >= 8 then
				bits = bits - 8
				local p = 2 ^ bits
				local byte = math.floor(buf / p)
				buf = buf - byte * p
				n = n + 1
				out[n] = string.char(byte)
			end
		end
	end
	return table.concat(out)
end

local imageDone = false
local probes    = {}

local function applyImage(img)
	if imageDone then return end
	imageDone = true
	circle.Image = img
	circle.ImageTransparency = 0
	circle.ImageColor3 = Color3.fromRGB(255, 255, 255)
	fallbackT.Visible = false
end

local function addProbe(url)
	if imageDone or not url or url == "" then return end
	local p = Instance.new("ImageLabel")
	p.Size = UDim2.new(0, 2, 0, 2)
	p.BackgroundTransparency = 1
	p.ImageTransparency = 0.99
	p.Image = url
	p.Parent = gui
	table.insert(probes, p)
end

local function startFallbackRace()
	if IMAGE_ID == "" then return end
	addProbe("rbxassetid://" .. IMAGE_ID)
	addProbe("rbxthumb://type=Asset&id=" .. IMAGE_ID .. "&w=150&h=150")
	addProbe("http://www.roblox.com/asset/?id=" .. IMAGE_ID)
	task.spawn(function()
		pcall(function()
			local objs = game:GetObjects("rbxassetid://" .. IMAGE_ID)
			local o = objs and objs[1]
			if o then
				local tex
				if o:IsA("Decal") or o:IsA("Texture") then
					tex = o.Texture
				elseif o:IsA("ImageLabel") or o:IsA("ImageButton") then
					tex = o.Image
				end
				addProbe(tex)
				o:Destroy()
			end
		end)
	end)
end

local usingLocal = false
if writefile and getAsset then
	local okW = pcall(function() writefile(IMAGE_FILE, b64decode(LOGO_B64)) end)
	if okW then
		local ok, asset = pcall(getAsset, IMAGE_FILE)
		if ok and asset and asset ~= "" then
			circle.Image = asset
			circle.ImageTransparency = 0
			circle.ImageColor3 = Color3.fromRGB(255, 255, 255)
			fallbackT.Visible = false
			usingLocal = true
		end
	end
end

task.spawn(function()
	local t, raced = 0, false
	if not usingLocal then
		startFallbackRace()
		raced = true
	end
	while not imageDone and t < 60 and alive() do
		if circle.IsLoaded then
			imageDone = true
			fallbackT.Visible = false
			break
		end
		if usingLocal and not raced and t > 2 then
			raced = true
			startFallbackRace()
		end
		for _, p in ipairs(probes) do
			if p.IsLoaded then
				applyImage(p.Image)
				break
			end
		end
		task.wait(0.03)
		t = t + 0.03
	end
	for _, p in ipairs(probes) do pcall(function() p:Destroy() end) end
	if not imageDone then
		fallbackT.Visible = true
		warn("[GUI] แสดงรูปไม่ได้ (executor ไม่มี writefile/getcustomasset และโหลดจาก ID ไม่สำเร็จ)")
	end
end)

makeDraggable(main)
local circleMoved = makeDraggable(circle)

circle.MouseButton1Click:Connect(function()
	if circleMoved() then return end
	main.Visible = not main.Visible
end)

local justHopped = settings.hopping and (os.time() - (settings.hopTime or 0)) < 300

if not justHopped then
	settings.running  = false
	settings.autoExec = false
end

settings.hopping = false
saveSettings()

setToggleLook(startBtn, "Start", false)
setToggleLook(autoBtn, "Auto Execute", settings.autoExec)
refreshStatus()

if justHopped and settings.running then
	task.spawn(function()
		local t = 0
		while not remote and t < 10 do
			task.wait(0.1)
			t = t + 0.1
		end
		if alive() then setRunning(true) end
	end)
end
