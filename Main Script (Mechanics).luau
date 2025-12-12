--[[ 
	GAME: ULTIMATE LAVA SURVIVAL
	AUTHOR: Gemini
	
	HOW TO PLAY:
	1. Wait in the Blue Lobby during Intermission.
	2. The game teleports you to the Orange Arena.
	3. Avoid the falling red blocks.
	4. If you die, you return to the Lobby until the next round.
	5. Last longer to get a higher score!
]]

-- SERVICES
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

-- CONFIGURATION SETTINGS
local ROUND_DURATION = 45       -- How long a round lasts
local INTERMISSION_DURATION = 10 -- Time between rounds
local ARENA_SIZE = 60           -- Size of the play area
local LOBBY_SIZE = 40           -- Size of the waiting area
local ARENA_HEIGHT = 100        -- How high up the main arena is
local BASE_LAVA_SPEED = 0.8     -- Starting spawn rate (seconds)

-- GLOBAL VARIABLES
local GameStatus = "Waiting..."
local isRoundActive = false

-------------------------------------------------------------------------
-- 1. MAP GENERATION (LOBBY & ARENA)
-------------------------------------------------------------------------

-- Folder to hold map parts
local mapFolder = Instance.new("Folder")
mapFolder.Name = "GameMap"
mapFolder.Parent = workspace

-- Function to create a walled platform
local function createPlatform(name, position, size, color, material)
	-- The Floor
	local floor = Instance.new("Part")
	floor.Name = name .. "_Floor"
	floor.Size = Vector3.new(size, 1, size)
	floor.Position = position
	floor.Anchored = true
	floor.Color = color
	floor.Material = material
	floor.Parent = mapFolder

	-- Invisible Walls (To stop falling off)
	local wallHeight = 20
	local wallThickness = 1

	local walls = {
		Vector3.new(position.X + size/2, position.Y + wallHeight/2, position.Z), -- Right
		Vector3.new(position.X - size/2, position.Y + wallHeight/2, position.Z), -- Left
		Vector3.new(position.X, position.Y + wallHeight/2, position.Z + size/2), -- Front
		Vector3.new(position.X, position.Y + wallHeight/2, position.Z - size/2), -- Back
	}

	local sizes = {
		Vector3.new(wallThickness, wallHeight, size),
		Vector3.new(wallThickness, wallHeight, size),
		Vector3.new(size, wallHeight, wallThickness),
		Vector3.new(size, wallHeight, wallThickness)
	}

	for i = 1, 4 do
		local w = Instance.new("Part")
		w.Name = "Wall"
		w.Transparency = 1 -- Invisible
		w.Anchored = true
		w.Position = walls[i]
		w.Size = sizes[i]
		w.Parent = mapFolder
	end

	return floor
end

-- Generate the Lobby (Blue) at (0, 0, 0)
local lobbyFloor = createPlatform(
	"Lobby", 
	Vector3.new(0, 0, 0), 
	LOBBY_SIZE, 
	Color3.fromRGB(0, 150, 255), 
	Enum.Material.Plastic
)

-- Generate the Arena (Orange) high in the sky
local arenaFloor = createPlatform(
	"Arena", 
	Vector3.new(0, ARENA_HEIGHT, 0), 
	ARENA_SIZE, 
	Color3.fromRGB(255, 120, 0), 
	Enum.Material.Slate
)

-- Add a SpawnLocation to the lobby so players join there naturally
local spawnPoint = Instance.new("SpawnLocation")
spawnPoint.Position = Vector3.new(0, 5, 0)
spawnPoint.Anchored = true
spawnPoint.CanCollide = false
spawnPoint.Transparency = 1
spawnPoint.Parent = workspace

-------------------------------------------------------------------------
-- 2. UI GENERATION (SCRIPTED GUI)
-------------------------------------------------------------------------

local function createPlayerUI(player)
	-- Check if they already have it
	if player:WaitForChild("PlayerGui"):FindFirstChild("GameHUD") then return end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "GameHUD"
	screenGui.ResetOnSpawn = false -- Keep UI when they die
	screenGui.Parent = player:WaitForChild("PlayerGui")

	-- Status Label (Top Center)
	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "StatusLabel"
	statusLabel.Size = UDim2.new(0, 400, 0, 50)
	statusLabel.Position = UDim2.new(0.5, -200, 0, 10) -- Centered
	statusLabel.BackgroundTransparency = 0.5
	statusLabel.BackgroundColor3 = Color3.new(0, 0, 0)
	statusLabel.TextColor3 = Color3.new(1, 1, 1)
	statusLabel.Font = Enum.Font.FredokaOne
	statusLabel.TextSize = 24
	statusLabel.Text = "Welcome!"
	statusLabel.BorderSizePixel = 0
	statusLabel.Parent = screenGui

	-- Rounded Corners for look
	local uiCorner = Instance.new("UICorner")
	uiCorner.CornerRadius = UDim.new(0, 8)
	uiCorner.Parent = statusLabel
end

-- Helper to update everyone's UI
local function updateAllUI(text)
	GameStatus = text
	for _, player in pairs(Players:GetPlayers()) do
		if player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("GameHUD") then
			player.PlayerGui.GameHUD.StatusLabel.Text = text
		end
	end
end

-------------------------------------------------------------------------
-- 3. PLAYER HANDLING
-------------------------------------------------------------------------

Players.PlayerAdded:Connect(function(player)
	-- Leaderstats
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	stats.Parent = player

	local score = Instance.new("IntValue")
	score.Name = "Score"
	score.Value = 0
	score.Parent = stats

	-- Give UI
	createPlayerUI(player)

	-- Character Logic
	player.CharacterAdded:Connect(function(char)
		-- Ensure they spawn at lobby
		local hrp = char:WaitForChild("HumanoidRootPart")
		hrp.CFrame = CFrame.new(lobbyFloor.Position + Vector3.new(0, 5, 0))
	end)
end)

-------------------------------------------------------------------------
-- 4. GAME MECHANICS (LAVA & EFFECTS)
-------------------------------------------------------------------------

local function spawnExplosion(position)
	-- Create a visual explosion using parts/particles
	local expPart = Instance.new("Part")
	expPart.Size = Vector3.new(1,1,1)
	expPart.Position = position
	expPart.Anchored = true
	expPart.Transparency = 1
	expPart.CanCollide = false
	expPart.Parent = workspace

	local explosion = Instance.new("Explosion")
	explosion.Position = position
	explosion.BlastRadius = 0 -- Visual only, don't blow up map
	explosion.BlastPressure = 0
	explosion.Parent = workspace

	Debris:AddItem(expPart, 1)
end

local function spawnLava()
	local lava = Instance.new("Part")
	lava.Name = "DeadlyLava"
	lava.Size = Vector3.new(math.random(4, 8), math.random(4, 8), math.random(4, 8))
	lava.Color = Color3.fromRGB(255, 50, 50)
	lava.Material = Enum.Material.Neon
	lava.CanCollide = false -- Let it pass through players slightly

	-- Random Position above arena
	local range = ARENA_SIZE / 2 - 2
	local x = arenaFloor.Position.X + math.random(-range, range)
	local z = arenaFloor.Position.Z + math.random(-range, range)
	lava.Position = Vector3.new(x, arenaFloor.Position.Y + 60, z)

	lava.Parent = workspace

	-- Add Physics manually slightly to ensure it falls
	lava.Anchored = false

	-- Touch Logic
	lava.Touched:Connect(function(hit)
		if hit.Parent:FindFirstChild("Humanoid") then
			hit.Parent.Humanoid.Health = 0
		elseif hit.Name == "Arena_Floor" then
			spawnExplosion(lava.Position)
			lava:Destroy()
		end
	end)

	Debris:AddItem(lava, 5)
end

local function teleportPlayers(locationCFrame)
	for _, player in pairs(Players:GetPlayers()) do
		if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
			local hum = player.Character.Humanoid
			if hum.Health > 0 then
				player.Character.HumanoidRootPart.CFrame = locationCFrame + Vector3.new(0, 5, 0)
			end
		end
	end
end

-------------------------------------------------------------------------
-- 5. MAIN GAME LOOP
-------------------------------------------------------------------------

while true do
	isRoundActive = false

	-- === INTERMISSION PHASE ===
	for i = INTERMISSION_DURATION, 1, -1 do
		updateAllUI("Intermission: " .. i .. "s")
		wait(1)
	end

	-- === TELEPORT PHASE ===
	updateAllUI("TELEPORTING TO ARENA!")
	wait(1)
	teleportPlayers(arenaFloor.CFrame)

	-- === ROUND START PHASE ===
	isRoundActive = true
	local timer = ROUND_DURATION
	local currentSpawnRate = BASE_LAVA_SPEED

	-- Loop specifically for the round duration
	while timer > 0 do
		-- Check if anyone is actually alive in the arena
		local survivors = 0
		for _, p in pairs(Players:GetPlayers()) do
			if p.Character and p.Character.Humanoid.Health > 0 then
				-- Check distance to ensure they are in arena, not lobby
				if (p.Character.HumanoidRootPart.Position - arenaFloor.Position).Magnitude < ARENA_SIZE then
					survivors = survivors + 1
					-- Add Score
					p.leaderstats.Score.Value = p.leaderstats.Score.Value + 5
				end
			end
		end

		-- Update UI
		updateAllUI("SURVIVE! Time: " .. math.floor(timer) .. " | Alive: " .. survivors)

		-- Spawn Lava multiple times based on difficulty
		spawnLava()
		-- As time goes on, spawn extra lava
		if timer < 20 then spawnLava() end 
		if timer < 10 then spawnLava() end

		-- Wait based on current difficulty
		wait(currentSpawnRate)

		-- Decrement timer by the wait amount roughly
		timer = timer - currentSpawnRate

		-- Increase difficulty (speed) slightly
		if currentSpawnRate > 0.3 then
			currentSpawnRate = currentSpawnRate - 0.01
		end

		-- Early Exit if everyone died
		if survivors == 0 and #Players:GetPlayers() > 0 then
			updateAllUI("EVERYONE DIED!")
			wait(2)
			break
		end
	end

	-- === ROUND END PHASE ===
	isRoundActive = false
	updateAllUI("Round Over! Returning to Lobby...")
	wait(2)

	-- Send everyone back to lobby
	teleportPlayers(lobbyFloor.CFrame)

	-- Clean up any remaining lava
	for _, child in pairs(workspace:GetChildren()) do
		if child.Name == "DeadlyLava" then
			child:Destroy()
		end
	end
end
