local LocalPlayer = game.Players.LocalPlayer
local SELL_TRESHOLD = getgenv().SellTreshold
if type(SELL_TRESHOLD) ~= "number" or not (SELL_TRESHOLD > 0) then SELL_TRESHOLD = nil end
local SellTreshold = (type(getgenv().SellTreshold) == "number" and getgenv().SellTreshold > 0) and getgenv().SellTreshold or 200
local Depth = getgenv().Depth or 205
getgenv().SellTreshold = SELL_TRESHOLD
getgenv().Depth = Depth
local SellArea = CFrame.new(-116, 13, 38)
local recovering = false
local areaTransit = false
local rebirthDigging = false
local collapseRecovering = false
local areaRunId = 0
local areaPhaseText = "off"
local lastAreaName = nil
local lastAreaTrackAt = 0
local Areas = {
	{ name = "Cyber",   moveTo = "CyberSpawn",  spawn = Vector3.new(21, 15, 30139),   walkEnd = Vector3.new(19, 13, 30051),   mine = Vector3.new(22, 12, 30037),   bridgeSize = Vector3.new(10, 1, 100), bridgePos = Vector3.new(21, 9.5, 30095) },
	{ name = "Spawn",   moveTo = nil,           spawn = Vector3.new(-86, 14, -12),    walkEnd = Vector3.new(-36, 14, -3),     mine = Vector3.new(-17, 12, -3) },
	{ name = "Space",   moveTo = "SpaceSpawn",  spawn = Vector3.new(-81, 15, 1569),   walkEnd = Vector3.new(-27, 12, 1568),   mine = Vector3.new(-15, 12, 1568) },
	{ name = "Candy",   moveTo = "CandySpawn",  spawn = Vector3.new(-27, 15, 3011),   walkEnd = Vector3.new(2, 13, 3009),     mine = Vector3.new(11, 12, 3010) },
	{ name = "Toy",     moveTo = "ToySpawn",    spawn = Vector3.new(10, 15, 5719),    walkEnd = Vector3.new(11, 13, 5699),    mine = Vector3.new(11, 12, 5687) },
	{ name = "Food",    moveTo = "FoodSpawn",   spawn = Vector3.new(61, 14, 8675),    walkEnd = Vector3.new(59, 13, 8719),    mine = Vector3.new(56, 12, 8732) },
	{ name = "Dino",    moveTo = "DinoSpawn",   spawn = Vector3.new(12, 15, 10581),   walkEnd = Vector3.new(12, 13, 10552),   mine = Vector3.new(14, 12, 10539) },
	{ name = "Sea",     moveTo = "SeaSpawn",    spawn = Vector3.new(14, 12, 10539),   walkEnd = Vector3.new(17, 13, 11969),   mine = Vector3.new(18, 12, 11949) },
	{ name = "Beach",   moveTo = "BeachSpawn",  spawn = Vector3.new(19, 14, 14437),   walkEnd = Vector3.new(15, 13, 14374),   mine = Vector3.new(15, 12, 14357) },
	{ name = "Cavern",  moveTo = "CavernSpawn", spawn = Vector3.new(19, 15, 18461),   walkEnd = Vector3.new(20, 13, 18400),   mine = Vector3.new(21, 12, 18382) },
	{ name = "MagicForest", moveTo = nil,       spawn = Vector3.new(15, 15, 22461),   walkEnd = Vector3.new(16, 13, 22420),   mine = Vector3.new(17, 12, 22409) },
}
local function DetectArea()
	local h = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	if not h then return nil end
	local best, bestd = nil, math.huge
	for _, a in ipairs(Areas) do
		local dx = h.Position.X - a.mine.X
		local dz = h.Position.Z - a.mine.Z
		local d = dx * dx + dz * dz
		if d < bestd then bestd = d best = a end
	end
	return best
end
local function FindAreaByName(name)
	if type(name) ~= "string" then return nil end
	for _, a in ipairs(Areas) do if a.name == name then return a end end
	return nil
end
local function TrackArea(force)
	if collapseRecovering or areaTransit then return end
	local now = os.clock()
	if not force and now - lastAreaTrackAt < 5 then return end
	lastAreaTrackAt = now
	pcall(function()
		local a = DetectArea()
		if a then lastAreaName = a.name end
	end)
end

local function Split(s, delimiter)
	local result = {};
	for match in (s..delimiter):gmatch("(.-)"..delimiter) do
		table.insert(result, match);
	end
	return result;
end

local function findDepthLabel()
	local sg = LocalPlayer.PlayerGui:FindFirstChild("ScreenGui")
	if not sg then return nil end
	local candidates = {}
	pcall(function()
		local t1 = sg:FindFirstChild("TopInfoFrame")
		if t1 and t1:FindFirstChild("Depth") then table.insert(candidates, t1.Depth) end
		local t2 = sg:FindFirstChild("TopInfo")
		if t2 and t2:FindFirstChild("Depth") then table.insert(candidates, t2.Depth) end
		local deep = sg:FindFirstChild("Depth", true)
		if deep then table.insert(candidates, deep) end
	end)
	for _, lbl in ipairs(candidates) do
		if lbl and lbl.Text and tonumber((Split(tostring(lbl.Text), " "))[1]) then return lbl end
	end
	return candidates[1]
end

local function GetCurrentDepth()
	local ok, val = pcall(function()
		local DepthLabel = findDepthLabel()
		if not DepthLabel or not DepthLabel.Text then return nil end
		local parts = Split(tostring(DepthLabel.Text), " ")
		return tonumber(parts[1])
	end)
	if ok then return val end
	return nil
end

local Leaderstats = LocalPlayer:WaitForChild("leaderstats", 10)
local Rebirths = Leaderstats and Leaderstats:WaitForChild("Rebirths", 10)

print("Loading Mining Simulator GUI (WindUI)")
pcall(function()
	local OldGui = LocalPlayer.PlayerGui:FindFirstChild("Nice Flex But OK")
	if OldGui then OldGui:Destroy() end
end)
pcall(function()
	if getgenv().__MS_Toggles then
		for k in pairs(getgenv().__MS_Toggles) do getgenv().__MS_Toggles[k] = false end
	end
	if getgenv().__MS_WindUIWindow then getgenv().__MS_WindUIWindow:Destroy() end
	getgenv().__MS_WindUIWindow = nil
	getgenv().__MS_BackpackRunning = false
	getgenv().__MS_ToolsRunning = false
	game:GetService("RunService"):UnbindFromRenderStep("MS_AutoRebirth")
end)

local Remote = nil
local function EnsureRemote()
	if Remote then return Remote end
	-- Priority 1: getsenv method (works in this game)
	pcall(function()
		local ClientScript = LocalPlayer.PlayerGui:FindFirstChild("ScreenGui") and LocalPlayer.PlayerGui.ScreenGui:FindFirstChild("ClientScript")
		if ClientScript and getsenv and getupvalue then
			local Data = getsenv(ClientScript).updatePasses
			local Values = getupvalue(Data, 8)
			if Values and typeof(Values["RemoteEvent"]) == "Instance" and Values["RemoteEvent"]:IsA("RemoteEvent") then
				Remote = Values["RemoteEvent"]
				print("[MS] Remote found via getsenv")
				return Remote
			end
		end
	end)
	-- Priority 2: Network InvokeServer (fallback)
	pcall(function()
		local Network = game:GetService("ReplicatedStorage"):WaitForChild("Network", 5)
		if Network then
			local a, b = Network:InvokeServer()
			if typeof(a) == "Instance" and a:IsA("RemoteEvent") then
				Remote = a
			elseif typeof(b) == "Instance" and b:IsA("RemoteEvent") then
				Remote = b
			end
		end
	end)
	return Remote
end
EnsureRemote()
pcall(function()
	local VU = game:GetService("VirtualUser")
	LocalPlayer.Idled:Connect(function()
		VU:CaptureController()
		VU:ClickButton2(Vector2.new())
	end)
	print("[MS] Anti-AFK on")
end)

local Toggles = getgenv().__MS_Toggles or {
	AutoSell = false,
	FastMine = false,
	AutoMine = false,
	AutoBackpack = false,
	AutoTools = false,
	AutoRebirth = false,
	RebirthOnly = false,
	LimitDepth = false
}
for k in pairs(Toggles) do Toggles[k] = false end
getgenv().__MS_Toggles = Toggles
getgenv().__MS_Gen = (getgenv().__MS_Gen or 0) + 1
local myGen = getgenv().__MS_Gen
local buyPause, buyPauseAt = false, 0
local lastMineSpot = nil
local sellTrip = false
local sellLoopGen = 0
local sellDbgAt = 0

local PlayerGui = LocalPlayer:WaitForChild("PlayerGui", 10)
local GameGui = PlayerGui:WaitForChild("ScreenGui", 10)
local StatsFrame2 = GameGui and GameGui:WaitForChild("StatsFrame", 10)
local InventoryAmount = StatsFrame2 and StatsFrame2:FindFirstChild("Inventory") and StatsFrame2.Inventory:FindFirstChild("Amount")
local CoinsAmount = Leaderstats and Leaderstats:WaitForChild("Coins", 10)

local function GetCoinsAmount()
	if not CoinsAmount then return 0 end
	local Amount = tostring(CoinsAmount.Value)
	Amount = Amount:gsub(',', '')
	return tonumber(Amount) or 0
end

local function resolveInventoryLabel()
	if InventoryAmount and InventoryAmount.Text then return InventoryAmount end
	pcall(function()
		local sg = LocalPlayer.PlayerGui:FindFirstChild("ScreenGui")
		if sg then
			local sf2 = sg:FindFirstChild("StatsFrame") or sg:FindFirstChild("StatsFrame2")
			local inv = sf2 and sf2:FindFirstChild("Inventory")
			local amt = inv and inv:FindFirstChild("Amount")
			if amt and amt.Text then InventoryAmount = amt return amt end
			local deepInv = sg:FindFirstChild("Inventory", true)
			local deepAmt = deepInv and deepInv:FindFirstChild("Amount")
			if deepAmt and deepAmt.Text then InventoryAmount = deepAmt return deepAmt end
		end
	end)
	return InventoryAmount
end

local function GetInventoryAmount()
	local lbl = resolveInventoryLabel()
	if not lbl or not lbl.Text then return 0, 0 end
	local Amount = tostring(lbl.Text)
	Amount = Amount:gsub('%s+', '')
	Amount = Amount:gsub(',', '')
	local Inventory = Amount:split("/")
	return tonumber(Inventory[1]) or 0, tonumber(Inventory[2]) or 0
end

local function StartAutoMine()
	-- 🔧 Reset stuck state
	pcall(function()
		areaRunId = areaRunId + 1
		areaTransit = false
		recovering = false
		collapseRecovering = false
		sellTrip = false

		local char = LocalPlayer.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hrp then hrp.Anchored = false end
		if hum then hum.WalkSpeed = 16; hum.JumpPower = 50 end

		local bridge = workspace:FindFirstChild("MS_AreaBridge")
		if bridge then bridge:Destroy() end
	end)

	-- 🚶 Walk forward 3.5 seconds
	task.spawn(function()
		local startTime = os.clock()
		while Toggles["AutoMine"] and (os.clock() - startTime) < 3.5 do
			local char = LocalPlayer.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp then
				hrp.CFrame = hrp.CFrame + hrp.CFrame.LookVector * 0.5
			end
			task.wait(0.05)
		end
	end)

	-- ⛏️ Then mine
	task.spawn(function()
		while Toggles["AutoMine"] do
			if areaTransit or recovering or collapseRecovering then task.wait(0.3)
			elseif buyPause then
				if os.clock() - buyPauseAt > 8 then buyPause = false else task.wait(0.3) end
			else
			if not Remote then EnsureRemote() end
			if Remote then
				local Character = LocalPlayer.Character
				local HumanoidRootPart = Character and Character:FindFirstChild("HumanoidRootPart")
				if HumanoidRootPart then
					local currentDepth = Toggles["LimitDepth"] and GetCurrentDepth() or nil
					if currentDepth == nil or currentDepth < Depth then
						local regionMin = HumanoidRootPart.CFrame + Vector3.new(-10,-10,-10)
						local regionMax = HumanoidRootPart.CFrame + Vector3.new(10,10,10)
						local region = Region3.new(regionMin.Position, regionMax.Position)
						local parts = workspace:FindPartsInRegion3WithWhiteList(region, {game.Workspace.Blocks}, 100)
						for _, block in pairs(parts) do
							if not Toggles["AutoMine"] then break end
							if areaTransit or recovering or collapseRecovering then break end
							Remote:FireServer("MineBlock",{{block.Parent}})
							task.wait()
						end
						if #parts > 0 then lastMineSpot = HumanoidRootPart.Position TrackArea() end
					else
						task.wait(0.5)
					end
				end
			else
				task.wait(1)
			end
			task.wait()
			end
		end
	end)
end

local function StartFastMine()
	task.spawn(function()
		while Toggles["FastMine"] do
			if areaTransit or recovering or collapseRecovering then task.wait(0.3)
			elseif buyPause then
				if os.clock() - buyPauseAt > 8 then buyPause = false else task.wait(0.3) end
			else
			if not Remote then EnsureRemote() end
			if Remote then
				local Character = LocalPlayer.Character
				local HumanoidRootPart = Character and Character:FindFirstChild("HumanoidRootPart")
				if HumanoidRootPart then
					local minp = HumanoidRootPart.CFrame.Position - Vector3.new(5, 5, 5)
					local maxp = HumanoidRootPart.CFrame.Position + Vector3.new(5, 5, 5)
					local region = Region3.new(minp, maxp)
					local parts = workspace:FindPartsInRegion3WithWhiteList(region, {game.Workspace.Blocks}, 50)
						for _, block in ipairs(parts) do
							if not Toggles["FastMine"] then break end
							if areaTransit or recovering or collapseRecovering then break end
							Remote:FireServer("MineBlock", {{block.Parent}})
							task.wait()
						end
						if #parts > 0 then lastMineSpot = HumanoidRootPart.Position TrackArea() end
					end
			else
				task.wait(1)
			end
			task.wait()
			end
		end
	end)
end

local function StartAutoSell()
	sellLoopGen = sellLoopGen + 1
	local gen = sellLoopGen
	task.spawn(function()
		print("[MS] AutoSell started")
		while Toggles["AutoSell"] and gen == sellLoopGen do
			local ok, err = pcall(function()
				if not Remote then EnsureRemote() end
				if (rebirthDigging and Toggles["AutoRebirth"]) or areaTransit or recovering or collapseRecovering then
					task.wait(0.5)
					return
				end
				if not Remote then task.wait(1) return end
				local Character = LocalPlayer.Character
				local HumanoidRootPart = Character and Character:FindFirstChild("HumanoidRootPart")
				if not HumanoidRootPart then task.wait(0.5) return end
				if sellTrip then task.wait(0.3) return end
				local curInv, curMax = GetInventoryAmount()
				if not curMax or curMax <= 0 then task.wait(0.5) return end
				local triggerAt = math.floor(curMax * 0.95)
				if curInv >= triggerAt then
					local SavedPosition = HumanoidRootPart.Position
					local sold = false
					sellTrip = true
					print("[MS] Selling: inv " .. tostring(curInv) .. "/" .. tostring(curMax) .. " trigger at " .. tostring(triggerAt))
					local sellStartTime = os.clock()
					while os.clock() - sellStartTime < 8 and not recovering and not collapseRecovering do
						local freshChar = LocalPlayer.Character
						local freshHRP = freshChar and freshChar:FindFirstChild("HumanoidRootPart")
						if not freshHRP then break end
						freshHRP.CFrame = SellArea
						task.wait(0.3)
						Remote:FireServer("SellItems", {{}})
						task.wait(0.4)
						local nowInv = GetInventoryAmount()
						if nowInv < triggerAt then
							sold = true
							break
						end
					end
					if sold then
						local freshChar = LocalPlayer.Character
						local freshHRP = freshChar and freshChar:FindFirstChild("HumanoidRootPart")
						if freshHRP then
							for _ = 1, 5 do
								freshHRP.CFrame = CFrame.new(SavedPosition)
								task.wait(0.3)
								freshChar = LocalPlayer.Character
								freshHRP = freshChar and freshChar:FindFirstChild("HumanoidRootPart")
								if freshHRP and (freshHRP.Position - SavedPosition).Magnitude <= 20 then break end
							end
						end
					end
					sellTrip = false
					print("[MS] Sell trip done: inv now " .. tostring(select(1, GetInventoryAmount())) .. " coins " .. tostring(GetCoinsAmount()))
				else
					if os.clock() - sellDbgAt > 15 then
						sellDbgAt = os.clock()
						print("[MS] AutoSell waiting: inv " .. tostring(curInv) .. "/" .. tostring(curMax) .. " | trigger " .. tostring(triggerAt) .. " | remote " .. tostring(Remote ~= nil))
					end
					task.wait(0.5)
				end
			end)
			if not ok then
				print("[MS] AutoSell error: " .. tostring(err))
				pcall(function() sellTrip = false end)
				task.wait(1)
			end
			task.wait()
		end
		print("[MS] AutoSell off")
	end)
end

local rebirthRunId = 0
local rebirthPhaseText = "off"
rebirthDigging = false
local function StartAutoRebirth()
	pcall(function() game:GetService("RunService"):UnbindFromRenderStep("MS_AutoRebirth") end)
	game:GetService("RunService"):BindToRenderStep("MS_AutoRebirth", Enum.RenderPriority.Camera.Value, function()
		if not Toggles["AutoRebirth"] then return end
		if not Remote then EnsureRemote() end
		if Rebirths and Remote then
			while Toggles["AutoRebirth"] and GetCoinsAmount() >= (10000000 * (Rebirths.Value + 1)) do
				Remote:FireServer("Rebirth",{{}})
				task.wait()
			end
		end
	end)
	rebirthRunId = rebirthRunId + 1
	local run = rebirthRunId
	task.spawn(function()
		rebirthPhaseText = "waiting to mine..."
		while Toggles["AutoRebirth"] and run == rebirthRunId do
			if game:IsLoaded()
				and LocalPlayer.Character
				and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
				and LocalPlayer:FindFirstChild("leaderstats") then
				break
			end
			task.wait(0.5)
		end
		EnsureRemote()
		rebirthPhaseText = "digging to " .. tostring(Depth) .. "..."
		rebirthDigging = true
		local nilStreak = 0
		while Toggles["AutoRebirth"] and run == rebirthRunId do
			if buyPause then task.wait(0.3)
			elseif areaTransit or recovering or collapseRecovering then task.wait(0.3)
			else
				if not Remote then EnsureRemote() end
				if not Remote then task.wait(1)
				else
					local Character = LocalPlayer.Character
					local HumanoidRootPart = Character and Character:FindFirstChild("HumanoidRootPart")
					if not HumanoidRootPart then task.wait(0.5)
					else
						local depthNow = GetCurrentDepth()
						if depthNow ~= nil and depthNow >= Depth then break end
						if depthNow == nil then
							nilStreak = nilStreak + 1
							if nilStreak > 60 then break end
						end
						local regionMin = HumanoidRootPart.CFrame + Vector3.new(-1,-10,-1)
						local regionMax = HumanoidRootPart.CFrame + Vector3.new(1,0,1)
						local region = Region3.new(regionMin.Position, regionMax.Position)
						local parts = workspace:FindPartsInRegion3WithWhiteList(region, {game.Workspace.Blocks}, 10)
						for _, block in pairs(parts) do
							if not Toggles["AutoRebirth"] or run ~= rebirthRunId then break end
							if areaTransit or recovering or collapseRecovering then break end
							Remote:FireServer("MineBlock",{{block.Parent}})
							task.wait()
						end
					end
				end
				task.wait()
			end
		end
		rebirthDigging = false
		rebirthPhaseText = "mining + selling..."
		while Toggles["AutoRebirth"] and run == rebirthRunId do
			if buyPause then task.wait(0.3)
			elseif areaTransit or recovering or collapseRecovering then task.wait(0.3)
			else
				if not Remote then EnsureRemote() end
				if not Remote then task.wait(1)
				else
					local Character = LocalPlayer.Character
					local HumanoidRootPart = Character and Character:FindFirstChild("HumanoidRootPart")
					if HumanoidRootPart then
						local minp = HumanoidRootPart.CFrame.Position - Vector3.new(5, 5, 5)
						local maxp = HumanoidRootPart.CFrame.Position + Vector3.new(5, 5, 5)
						local region = Region3.new(minp, maxp)
						local parts = workspace:FindPartsInRegion3WithWhiteList(region, {game.Workspace.Blocks}, 50)
						for _, block in ipairs(parts) do
							if not Toggles["AutoRebirth"] or run ~= rebirthRunId then break end
							if areaTransit or recovering or collapseRecovering then break end
							Remote:FireServer("MineBlock", {{block.Parent}})
							task.wait()
						end
						if #parts > 0 then lastMineSpot = HumanoidRootPart.Position TrackArea() end
						if sellTrip then task.wait(0.3) else
    local SavedPosition = HumanoidRootPart.Position
    local sold = false
    sellTrip = true
    local _, packMaxNow = GetInventoryAmount()
    local triggerAt = packMaxNow and math.floor(packMaxNow * 0.95) or 200
    local sellStartTime = os.clock()
    while os.clock() - sellStartTime < 8 and not recovering and not collapseRecovering do
        local nowInv = GetInventoryAmount()
        if nowInv < triggerAt then sold = true break end
        HumanoidRootPart.CFrame = SellArea
        task.wait(0.3)
        Remote:FireServer("SellItems", {{}})
        task.wait(0.4)
    end
    if sold then
        local freshChar = LocalPlayer.Character
        local freshHRP = freshChar and freshChar:FindFirstChild("HumanoidRootPart")
        if freshHRP then
            for _ = 1, 5 do
                freshHRP.CFrame = CFrame.new(SavedPosition)
                task.wait(0.3)
                freshChar = LocalPlayer.Character
                freshHRP = freshChar and freshChar:FindFirstChild("HumanoidRootPart")
                if freshHRP and (freshHRP.Position - SavedPosition).Magnitude <= 20 then break end
            end
        end
    end
    sellTrip = false
end
					end
				end
				task.wait()
			end
		end
		rebirthPhaseText = "off"
	end)
end

local function StopAutoRebirth()
	rebirthRunId = rebirthRunId + 1
	rebirthPhaseText = "off"
	rebirthDigging = false
	pcall(function() game:GetService("RunService"):UnbindFromRenderStep("MS_AutoRebirth") end)
end

local rebirthOnlyRunning = false
local function StartRebirthOnly()
	if rebirthOnlyRunning then return end
	rebirthOnlyRunning = true
	task.spawn(function()
		while Toggles["RebirthOnly"] and getgenv().__MS_Gen == myGen do
			if not Remote then
				EnsureRemote()
				task.wait(1)
			else
				pcall(function()
					while Rebirths and Toggles["RebirthOnly"] and GetCoinsAmount() >= (10000000 * (Rebirths.Value + 1)) do
						Remote:FireServer("Rebirth",{{}})
						task.wait()
					end
				end)
				task.wait(0.1)
			end
		end
		rebirthOnlyRunning = false
	end)
end

local gearToolText, gearPackText = "?", "?"
local lastBoughtToolText, lastBoughtPackText = "none yet", "none yet"
local lastToolTryText = ""

local ShopCache = { tools = nil, packs = nil, at = 0 }
local function requireShopModules()
	local ok, res = pcall(function()
		local mods = game:GetService("Lighting"):FindFirstChild("Assets") and game.Lighting.Assets:FindFirstChild("Modules")
		if not mods then return nil end
		local sm = mods:FindFirstChild("ShopModule")
		local ps = nil
		pcall(function()
			local sg = LocalPlayer.PlayerGui:FindFirstChild("ScreenGui")
			local cs = sg and sg:FindFirstChild("ClientScript")
			local cl = cs and cs:FindFirstChild("Client")
			local psm = cl and cl:FindFirstChild("PlayerState")
			if psm then ps = require(psm) end
		end)
		return {
			shop = sm and require(sm) or nil,
			player = ps,
			backpack = mods:FindFirstChild("BackpackModule") and require(mods.BackpackModule) or nil,
		}
	end)
	if ok then return res end
	return nil
end

local function playerDataTable()
	local ok, pd = pcall(function()
		local sg = LocalPlayer.PlayerGui:FindFirstChild("ScreenGui")
		local cs = sg and sg:FindFirstChild("ClientScript")
		local cl = cs and cs:FindFirstChild("Client")
		local psm = cl and cl:FindFirstChild("PlayerState")
		if psm then
			local m = require(psm)
			if type(m) == "table" and type(m.coins) == "number" then return m end
		end
		return nil
	end)
	if ok and pd then return pd end
	local ok2, found = pcall(function()
		local sg = LocalPlayer.PlayerGui:FindFirstChild("ScreenGui")
		local cs = sg and sg:FindFirstChild("ClientScript")
		if not cs or not getsenv then return nil end
		local env = getsenv(cs)
		if type(env) ~= "table" then return nil end
		for _, v in pairs(env) do
			if type(v) == "table" and type(v.coins) == "number" and type(v.equipped) == "table" then
				return v
			end
		end
		return nil
	end)
	if ok2 then return found end
	return nil
end

local function shopPrice(entry, category)
	if type(entry) ~= "table" or entry[2] == "Group" then return nil end
	local base = tonumber(entry[2])
	if not base then return nil end
	local ok, price = pcall(function()
		local pd = playerDataTable()
		local rb = pd and tonumber(pd.rebirths) or (Rebirths and tonumber(Rebirths.Value) or 0) or 0
		local v
		if entry.fixedPrice or rb == 0 or category == "Rebirth Shop" then
			v = math.ceil(base)
		else
			v = math.ceil(base * ((rb + 1) / 2))
		end
		local mult = tonumber(LocalPlayer:GetAttribute("GuildShopPriceMultiplier")) or 1
		return math.max(0, math.ceil(v * mult))
	end)
	if ok then return price end
	return math.ceil(base)
end

local function entryName(e, idx)
	if type(e) == "string" then return e end
	if type(e) == "table" then
		if type(e[1]) == "string" then return e[1] end
		for _, k in ipairs({"name", "Name", "id", "Id"}) do
			if type(e[k]) == "string" then return e[k] end
		end
	end
	return "item" .. tostring(idx)
end

local function isOwned(entry, pd)
	local name = entryName(entry)
	local ok, owned = pcall(function()
		if not pd then return false end
		for _, list in ipairs({pd.ownedItems, pd.permanentItems}) do
			if type(list) == "table" then
				for _, n in ipairs(list) do if n == name then return true end end
			end
		end
		if type(entry) == "table" and type(entry[3]) == "table" and pd.ownedPasses then
			if pd.ownedPasses[entry[3][2]] then return true end
		end
		return false
	end)
	return ok and owned or false
end

local function discoverShop()
	if (ShopCache.tools or ShopCache.packs) and os.clock() - ShopCache.at < 60 then return ShopCache end
	pcall(function()
		local m = requireShopModules()
		local sm = m and m.shop
		if type(sm) == "table" then
			local function looksLikeShopRow(e)
				if type(e) ~= "table" then return type(e) == "string" end
				if type(e[1]) ~= "string" or e[1] == "" then return false end
				return tonumber(e[2]) ~= nil or e[2] == "Group" or type(e[3]) == "table"
			end
			local function validList(t)
				if type(t) ~= "table" or #t <= 5 then return false end
				local good, checked = 0, 0
				for i = 1, math.min(#t, 20) do
					checked = checked + 1
					if looksLikeShopRow(t[i]) then good = good + 1 end
				end
				return checked > 0 and good / checked >= 0.7
			end
			local tools, packs = sm.Tools, sm.Backpack
			if validList(tools) then ShopCache.tools = tools else ShopCache.tools = nil end
			if validList(packs) then ShopCache.packs = packs else ShopCache.packs = nil end
		end
		ShopCache.at = os.clock()
		pcall(function()
			if not ShopCache._dumped then
				ShopCache._dumped = true
				local m2 = requireShopModules()
				local keys = {}
				if m2 and type(m2.shop) == "table" then
					for k in pairs(m2.shop) do table.insert(keys, tostring(k)) end
				end
				print("[MS] ShopModule keys: " .. table.concat(keys, ","))
				for _, kn in ipairs({"Tools", "Backpack"}) do
					local t = m2 and m2.shop and m2.shop[kn]
					print("[MS] " .. kn .. ": type=" .. type(t) .. " len=" .. tostring(t and #t or 0))
					if type(t) == "table" then
						for i = 1, math.min(3, #t) do
							local e = t[i]
							print("[MS] " .. kn .. "[" .. i .. "] type=" .. type(e) .. " [1]=" .. tostring(type(e) == "table" and e[1] or e) .. " [2]=" .. tostring(type(e) == "table" and e[2] or "-"))
						end
					end
				end
				local pd = playerDataTable()
				print("[MS] playerData: " .. tostring(pd ~= nil) .. " equipped=" .. tostring(pd and pd.equipped and table.concat(pd.equipped, "|") or "?"))
			end
		end)
	end)
	return ShopCache
end

local bestToolName
