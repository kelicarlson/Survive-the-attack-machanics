--[[ 
    PROJECT: TITAN LAVA SURVIVAL (Annotated Edition)
    ARCHITECT: Gemini
    
    ARCHITECTURE OVERVIEW:
    This script utilizes a "Service-Controller" pattern mixed with OOP.
    1. LavaProjectile: A class responsible for its own physics and hit detection.
    2. ArenaManager: Handles map geometry and complex CFrame math for the tilting mechanic.
    3. GameController: A singleton that manages the game loop state (Intermission -> Round -> End).
]]

-- SERVICES
-- distinct services handle specific engine domains.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")   -- Used for per-frame logic (Heartbeat)
local TweenService = game:GetService("TweenService") -- Used for smooth interpolations
local PhysicsService = game:GetService("PhysicsService") -- Used to manage collision groups
local Debris = game:GetService("Debris") -- specific service for cleaning up objects after a set time

-- CONSTANTS & CONFIG
-- Centralized configuration allows game designers to tune balance without touching logic code.
local CONFIG = {
    ROUND_TIME = 45,        -- Short rounds keep engagement high
    INTERMISSION = 10,      -- Buffer time for players to load/chat
    ARENA_HEIGHT = 100,     -- High altitude ensures players who fall hit the "void" kill-plane eventually
    LAVA_SPAWN_RATE = 0.5,  -- Initial difficulty (seconds between spawns)
}

-- COLLISION GROUPS SETUP
-- We use strings to identify groups. This is better than hardcoding IDs.
local CG_PLAYER = "Players"
local CG_LAVA = "Lava"
local CG_MAP = "Map"

-- LOGIC: Why use pcall? 
-- PhysicsService registration can fail if the group already exists (e.g., if the script re-runs).
-- pcall (Protected Call) prevents the script from crashing if these groups already exist.
pcall(function()
    PhysicsService:RegisterCollisionGroup(CG_PLAYER)
    PhysicsService:RegisterCollisionGroup(CG_LAVA)
    PhysicsService:RegisterCollisionGroup(CG_MAP)
    
    -- LOGIC: Anti-Griefing Mechanism
    -- By setting player-vs-player collisions to false, we prevent players from pushing 
    -- each other off the platform (a common frustration in survival games).
    PhysicsService:CollisionGroupSetCollidable(CG_PLAYER, CG_PLAYER, false)
    
    -- LOGIC: Physics Optimization
    -- Lava rocks shouldn't collide with each other. If they did, they might stack mid-air 
    -- or cause physics lag calculations. We want them to pass through each other.
    PhysicsService:CollisionGroupSetCollidable(CG_LAVA, CG_LAVA, false)
end)

-------------------------------------------------------------------------
-- CLASS: LAVA PROJECTILE (OOP + Physics)
-------------------------------------------------------------------------
-- This table acts as the class definition.
local LavaProjectile = {}
LavaProjectile.__index = LavaProjectile

-- CONSTRUCTOR: Creates a new instance of a lava rock
function LavaProjectile.new(spawnPos)
    local self = setmetatable({}, LavaProjectile)
    
    -- 1. Visual Representation
    self.Part = Instance.new("Part")
    self.Part.Name = "MagmaCore"
    self.Part.Shape = Enum.PartType.Ball
    self.Part.Material = Enum.Material.Neon
    self.Part.Color = Color3.fromRGB(255, 60, 20)
    self.Part.Size = Vector3.new(4, 4, 4)
    self.Part.Position = spawnPos
    self.Part.CanCollide = true
    self.Part.CollisionGroup = CG_LAVA
    self.Part.Parent = workspace

    -- 2. Physics Constraints (Why separate from Anchored?)
    -- Standard .Anchored = false gravity is boring. 
    -- By using Attachments and VectorForces, we can customize the weight and spin.
    local attachment = Instance.new("Attachment", self.Part)
    
    -- LOGIC: AngularVelocity (Chaos Factor)
    -- This applies torque to the object. A spinning object looks more dangerous and dynamic
    -- than a static falling block. It creates visual "noise" that excites the player.
    local angularVel = Instance.new("AngularVelocity")
    angularVel.Attachment0 = attachment
    angularVel.AngularVelocity = Vector3.new(math.random(-5,5), math.random(-5,5), math.random(-5,5))
    angularVel.MaxTorque = 100000 -- High torque ensures it spins despite its mass
    angularVel.Parent = self.Part

    -- LOGIC: VectorForce (Custom Gravity)
    -- We multiply workspace gravity by 1.5 to make the lava fall faster than a player can jump.
    -- This makes the game harder; you cannot "out-float" the lava.
    local force = Instance.new("VectorForce")
    force.Attachment0 = attachment
    force.Force = Vector3.new(0, -self.Part:GetMass() * workspace.Gravity * 1.5, 0)
    force.RelativeTo = Enum.ActuatorRelativeTo.World
    force.Parent = self.Part

    -- 3. Event Handling (Memory Management)
    -- We store the connection in 'self._maid'. This is a coding pattern that reminds us
    -- that this connection needs to be cleaned up if the object is destroyed manually.
    self._maid = self.Part.Touched:Connect(function(hit)
        self:OnTouch(hit)
    end)
    
    -- Garbage Collection: Ensure the part deletes itself after 8 seconds to prevent lag.
    Debris:AddItem(self.Part, 8)
    
    return self
end

function LavaProjectile:OnTouch(hit)
    -- Sanity check: If the part was already destroyed by another event, stop.
    if not self.Part or not self.Part.Parent then return end

    -- LOGIC: Hit Detection
    -- We check for a Humanoid. If found, we kill the player instantly.
    local humanoid = hit.Parent:FindFirstChild("Humanoid")
    if humanoid then
        humanoid.Health = 0
        
        -- Visual Feedback: Add fire to the rock to indicate a "hit".
        local fire = Instance.new("Fire", self.Part)
        fire.Size = 10
        fire.Heat = 20
        
    elseif hit.Name == "ArenaFloor" then
        -- If it hits the floor, we trigger the explosion method.
        self:Explode()
    end
end

function LavaProjectile:Explode()
    -- LOGIC: Optimization
    -- We use a BlastRadius of 0. This creates the visual/sound of an explosion
    -- without calculating physics force on surrounding parts, saving CPU power.
    local explosion = Instance.new("Explosion")
    explosion.Position = self.Part.Position
    explosion.BlastRadius = 0 
    explosion.BlastPressure = 0
    explosion.Parent = workspace
    
    self.Part:Destroy()
end

-------------------------------------------------------------------------
-- CLASS: ARENA MANAGER (Procedural Generation + CFrame Math)
-------------------------------------------------------------------------
local ArenaManager = {}
ArenaManager.__index = ArenaManager

function ArenaManager.new()
    local self = setmetatable({}, ArenaManager)
    
    -- Organization: Keep the workspace clean by grouping map parts.
    self.Folder = Instance.new("Folder")
    self.Folder.Name = "GameEnvironment"
    self.Folder.Parent = workspace
    
    self.ArenaFloor = nil
    self.IsTilting = false
    
    return self
end

function ArenaManager:BuildLobby()
    -- Standard part creation for the waiting area
    local floor = Instance.new("Part")
    floor.Name = "LobbyFloor"
    floor.Size = Vector3.new(50, 2, 50)
    floor.Position = Vector3.new(0, 0, 0)
    floor.Anchored = true
    floor.Material = Enum.Material.Plastic
    floor.Color = Color3.fromRGB(0, 170, 255)
    floor.Parent = self.Folder
    
    -- Invisible spawn location to handle player spawning logic automatically
    local spawn = Instance.new("SpawnLocation")
    spawn.Position = Vector3.new(0, 5, 0)
    spawn.Anchored = true
    spawn.Transparency = 1
    spawn.Parent = self.Folder
    
    return floor
end

function ArenaManager:BuildArena()
    local floor = Instance.new("Part")
    floor.Name = "ArenaFloor"
    floor.Size = Vector3.new(60, 4, 60)
    floor.Position = Vector3.new(0, CONFIG.ARENA_HEIGHT, 0)
    floor.Anchored = true 
    floor.Material = Enum.Material.Slate
    floor.Color = Color3.fromRGB(255, 100, 0)
    floor.CollisionGroup = CG_MAP
    floor.Parent = self.Folder
    
    self.ArenaFloor = floor
    return floor
end

-- LOGIC: The Tilting Mechanic
-- This function uses a coroutine (task.spawn) to run a loop independently of the main game loop.
function ArenaManager:StartTilting()
    self.IsTilting = true
    task.spawn(function()
        local t = 0
        while self.IsTilting and self.ArenaFloor do
            -- Increment time variable 't'
            t = t + 0.02
            
            -- MATH EXPLANATION: Sine Waves
            -- math.sin(t) returns a value between -1 and 1.
            -- By mapping this to rotation, we create a smooth back-and-forth rocking motion.
            -- We use different speeds (t vs t*0.7) for X and Z axes to prevent the movement 
            -- from feeling too perfect/circular. It feels random/chaotic.
            local angleX = math.sin(t) * math.rad(5) 
            local angleZ = math.cos(t * 0.7) * math.rad(5)
            
            -- Combine position and rotation into a single CFrame
            local targetCFrame = CFrame.new(0, CONFIG.ARENA_HEIGHT, 0) * CFrame.Angles(angleX, 0, angleZ)
            
            -- Tweening: Instead of snapping the part to the new CFrame, we tween it.
            -- This ensures players standing on it move smoothly rather than glitching.
            local tweenInfo = TweenInfo.new(0.1, Enum.EasingStyle.Linear)
            TweenService:Create(self.ArenaFloor, tweenInfo, {CFrame = targetCFrame}):Play()
            
            -- Wait for approx 1 frame (60fps)
            task.wait(1/60)
        end
        
        -- Reset to flat when tilting stops
        if self.ArenaFloor then
            TweenService:Create(self.ArenaFloor, TweenInfo.new(1), {CFrame = CFrame.new(0, CONFIG.ARENA_HEIGHT, 0)}):Play()
        end
    end)
end

function ArenaManager:StopTilting()
    self.IsTilting = false
end

-------------------------------------------------------------------------
-- CLASS: GAME CONTROLLER (State Machine)
-------------------------------------------------------------------------
local GameController = {
    Arena = ArenaManager.new(),
    State = "Waiting",
    Active = true
}

function GameController:Init()
    -- 1. Build the physical world
    self.Arena:BuildLobby()
    self.Arena:BuildArena()
    
    -- 2. Bind Player events
    Players.PlayerAdded:Connect(function(plr)
        self:SetupPlayer(plr)
    end)
    
    -- 3. Start the infinite game loop in a separate thread so it doesn't block other scripts
    task.spawn(function() self:GameLoop() end)
end

function GameController:SetupPlayer(player)
    -- LOGIC: Character Handling
    -- When a character spawns, we must recursively set the CollisionGroup of every part
    -- of their body (arms, legs, head) to "Players" so the PhysicsService rules apply.
    player.CharacterAdded:Connect(function(char)
        for _, part in pairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CollisionGroup = CG_PLAYER
            end
        end
        
        -- UI Creation (Done on Server for simplicity in this example)
        local gui = Instance.new("ScreenGui", player:WaitForChild("PlayerGui"))
        gui.Name = "StatusUI"
        local label = Instance.new("TextLabel", gui)
        label.Size = UDim2.new(0, 300, 0, 50)
        label.Position = UDim2.new(0.5, -150, 0, 10)
        label.Name = "Status"
        label.Font = Enum.Font.GothamBold
        label.TextSize = 20
        label.BackgroundTransparency = 0.5
        label.BackgroundColor3 = Color3.new(0,0,0)
        label.TextColor3 = Color3.new(1,1,1)
        
        local corner = Instance.new("UICorner", label)
        corner.CornerRadius = UDim.new(0, 8)
    end)
end

-- Helper to update the text on every player's screen
function GameController:UpdateUI(message)
    for _, plr in pairs(Players:GetPlayers()) do
        if plr:FindFirstChild("PlayerGui") and plr.PlayerGui:FindFirstChild("StatusUI") then
            plr.PlayerGui.StatusUI.Status.Text = message
        end
    end
end

-- Moves players between Lobby and Arena
function GameController:TeleportAll(targetCFrame)
    for _, plr in pairs(Players:GetPlayers()) do
        if plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") then
            -- Only teleport living players
            if plr.Character.Humanoid.Health > 0 then
                -- Add +5 Y height so they don't spawn stuck inside the floor
                plr.Character.HumanoidRootPart.CFrame = targetCFrame + Vector3.new(0, 5, 0)
            end
        end
    end
end

function GameController:GameLoop()
    while self.Active do
        -- == PHASE 1: INTERMISSION ==
        self.State = "Intermission"
        self.Arena:StopTilting() -- Ensure arena is stable
        
        -- Simple countdown loop
        for i = CONFIG.INTERMISSION, 1, -1 do
            self:UpdateUI("Next Round in: " .. i)
            task.wait(1)
        end
        
        -- == PHASE 2: ROUND START ==
        self.State = "Active"
        self:UpdateUI("Teleporting...")
        task.wait(1)
        
        -- Move players to the arena
        self:TeleportAll(self.Arena.ArenaFloor.CFrame)
        
        -- LOGIC: Start the environmental hazard (tilting)
        self.Arena:StartTilting() 
        
        local timer = CONFIG.ROUND_TIME
        local nextSpawn = 0
        
        -- == PHASE 3: ROUND ACTIVE (Heartbeat Loop) ==
        -- LOGIC: Why Heartbeat? 
        -- Standard 'while wait(1) do' is inaccurate. It drifts over time.
        -- RunService.Heartbeat fires every physics frame. By subtracting 'dt' (delta time),
        -- we get a highly accurate timer that handles lag gracefully.
        while timer > 0 do
            local dt = RunService.Heartbeat:Wait()
            timer = timer - dt
            nextSpawn = nextSpawn - dt
            
            -- LOGIC: Survivor Check
            -- We iterate through players to see who is still on the platform.
            local survivors = 0
            for _, p in pairs(Players:GetPlayers()) do
                if p.Character and p.Character.Humanoid.Health > 0 then
                    -- Distance check: If they are > 100 studs away from center, they fell off.
                    if (p.Character.HumanoidRootPart.Position - self.Arena.ArenaFloor.Position).Magnitude < 100 then
                        survivors = survivors + 1
                    end
                end
            end
            
            self:UpdateUI("Survive! Time: " .. math.floor(timer) .. " | Alive: " .. survivors)
            
            -- LOGIC: Spawning System
            if nextSpawn <= 0 then
                nextSpawn = CONFIG.LAVA_SPAWN_RATE
                
                -- Randomize position, but keep Y high (80 studs up)
                local offset = Vector3.new(math.random(-25, 25), 80, math.random(-25, 25))
                local spawnPos = self.Arena.ArenaFloor.Position + offset
                
                -- Create the rock
                LavaProjectile.new(spawnPos)
                
                -- LOGIC: Dynamic Difficulty
                -- As the timer gets lower (less than 15s), we decrease the spawn cooldown.
                -- This creates a frantic "climax" to the round.
                if timer < 15 then nextSpawn = 0.2 end
            end
            
            -- If everyone died, end the loop early to save time.
            if survivors == 0 then break end
        end
        
        -- == PHASE 4: ROUND OVER ==
        self:UpdateUI("Round Over!")
        self.Arena:StopTilting()
        task.wait(3) -- Give players a moment to realize who won
        self:TeleportAll(CFrame.new(0, 5, 0)) -- Send back to Lobby
    end
end

-------------------------------------------------------------------------
-- INITIALIZE
-------------------------------------------------------------------------
-- Kick off the singleton controller
GameController:Init()
