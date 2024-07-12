--[[
Copyright 2019 Manticore Games, Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
documentation files (the "Software"), to deal in the Software without restriction, including without limitation the
rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit
persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the
Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
--]]

--[[
This component makes a battle-royale style drop-in from a plane at beginning to the round. It also broadcasts the
following events, which are all server-only:

SkydivePlaneSpawned(CoreObject plane)
SkydivePlaneDespawned(CoreObject plane)     -- Fired just before the plane is destroyed so it can still be accessed
PlayerSkydiveStart(Player player)
PlayerParachuteOpened(Player player)
PlayerSkydiveEnd(Player player)
--]]

-- Internal custom properties
local COMPONENT_ROOT = script:GetCustomProperty("ComponentRoot"):WaitForObject()
local DROP_AREA = script:GetCustomProperty("DropArea"):WaitForObject()
local EJECT_ABILITY = script:GetCustomProperty("EjectAbility")
local PARACHUTE_ABILITY = script:GetCustomProperty("ParachuteAbility")
local SKYDIVE_PLAYER_SETTINGS = script:GetCustomProperty("SkydivePlayerSettings"):WaitForObject()
local PARACHUTE_PLAYER_SETTINGS = script:GetCustomProperty("ParachutePlayerSettings"):WaitForObject()

-- User exposed properties
local PLANE_TEMPLATE = COMPONENT_ROOT:GetCustomProperty("PlaneTemplate")
local PLANE_SPEED = COMPONENT_ROOT:GetCustomProperty("PlaneSpeed")
local OFF_CENTER_FACTOR = COMPONENT_ROOT:GetCustomProperty("OffCenterFactor")
local PRE_DROP_FACTOR = COMPONENT_ROOT:GetCustomProperty("PreDropFactor")
local POST_DROP_FACTOR = COMPONENT_ROOT:GetCustomProperty("PostDropFactor")
local JUMP_ABILITY_NAME = COMPONENT_ROOT:GetCustomProperty("JumpAbilityName")
local SKYDIVE_AIR_RESISTANCE = COMPONENT_ROOT:GetCustomProperty("SkydiveAirResistance")
local DEFAULT_PLAYER_SETTINGS = COMPONENT_ROOT:GetCustomProperty("DefaultPlayerSettings"):WaitForObject()
local ALLOW_PARACHUTING = COMPONENT_ROOT:GetCustomProperty("AllowParachuting")
local PARACHUTE_TEMPLATE = COMPONENT_ROOT:GetCustomProperty("ParachuteTemplate")
local PARACHUTE_ABILITY_NAME = COMPONENT_ROOT:GetCustomProperty("ParachuteAbilityName")
local PARACHUTE_AIR_RESISTANCE = COMPONENT_ROOT:GetCustomProperty("ParachuteAirResistance")
local PARACHUTE_OPEN_HEIGHT = COMPONENT_ROOT:GetCustomProperty("ParachuteOpenHeight")

-- Check user properties
if not PLANE_TEMPLATE then
    error("PlaneTemplate required")
end

if PLANE_SPEED <= 0.0 then
    warn("PlaneSpeed must be positive")
    PLANE_SPEED = 100.0
end

if OFF_CENTER_FACTOR < 0.0 or OFF_CENTER_FACTOR > 1.0 then
    warn("OffCenterFactor must be in the range [0.0, 1.0]")
    OFF_CENTER_FACTOR = CoreMath.Clamp(OFF_CENTER_FACTOR, 0.0, 1.0)
end

if PRE_DROP_FACTOR < 0.0 then
    warn("PreDropFactor cannot be negative")
    PRE_DROP_FACTOR = 0.0
end

if POST_DROP_FACTOR < 0.0 then
    warn("PlaneSpeed cannot be negative")
    POST_DROP_FACTOR = 0.0
end

if SKYDIVE_AIR_RESISTANCE < 0.0 then
    warn("SkydiveAirResistance cannot be negative")
    SKYDIVE_AIR_RESISTANCE = 0.0
end

if ALLOW_PARACHUTING and not PARACHUTE_TEMPLATE then
    error("ParachuteTemplate required if AllowParachuting")
end

if PARACHUTE_AIR_RESISTANCE < 0.0 then
    warn("ParachuteAirResistance cannot be negative")
    PARACHUTE_AIR_RESISTANCE = 0.0
end

-- The larger this is, the more expensive the raycasts are, so we put an upper bound on it
if PARACHUTE_OPEN_HEIGHT < 0.0 or PARACHUTE_OPEN_HEIGHT > 20000.0 then
    warn("ParachuteOpenHeight must be positive and at most 20000")
    PARACHUTE_OPEN_HEIGHT = CoreMath.Clamp(PARACHUTE_OPEN_HEIGHT, 300.0, 20000.0)
end

if DROP_AREA:GetWorldScale().x ~= DROP_AREA:GetWorldScale().y then
    warn("Drop Area must have x and y scale equal")
end

-- Constants
local DROP_AREA_RADIUS = DROP_AREA:GetWorldScale().x * 50.0
local SKYDIVE_BASE_GRAVITY = nil            -- Set when we apply the player settings object
local PARACHUTE_BASE_GRAVITY = nil          -- Set when we apply the player settings object
local LANDING_HEIGHT = 200.0                -- Height above the ground where we consider the player "landed"

-- Variables
local plane = nil
local planePathEndTime = 0.0
local previousInDropArea = false
local playersOnPlane = {}           -- Player -> true
local skydivingPlayers = {}         -- Player -> true   (Includes players with and without parachutes)
local playerGroundHeights = {}      -- Player -> float  (These are the results of traces, and somewhat slow to update)
local jumpAbilities = {}            -- Player -> Ability
local parachuteAbilities = {}       -- Player -> Ability
local parachutes = {}               -- Player -> CoreObject
local tickNumber = 0                -- Used to stagger ground height traces

-- nil EjectPlayer(Player)
-- Ejects the player out of the plane
function EjectPlayer(player)
    playersOnPlane[player] = nil

    if jumpAbilities[player] then
        jumpAbilities[player]:Destroy()
        jumpAbilities[player] = nil
    end

    skydivingPlayers[player] = true

    if ALLOW_PARACHUTING then
        parachuteAbilities[player] = World.SpawnAsset(PARACHUTE_ABILITY)
        parachuteAbilities[player].owner = player
        parachuteAbilities[player].executeEvent:Connect(OnExecuteParachute)
        parachuteAbilities[player].name = PARACHUTE_ABILITY_NAME
    end

    player:SetWorldPosition(plane:GetWorldPosition())
    player:SetWorldRotation(plane:GetWorldRotation())
    player:ResetVelocity()

    SKYDIVE_PLAYER_SETTINGS:ApplyToPlayer(player)
    SKYDIVE_BASE_GRAVITY = player.gravityScale

    Events.BroadcastToPlayer(player, "PlayerSkydiveStart_Internal")
    Events.Broadcast("PlayerSkydiveStart", player)

    player.canMount = false
    player:SetMounted(false)
end

-- nil OpenParachute(Player)
-- Opens the player's parachute
function OpenParachute(player)
    parachuteAbilities[player]:Destroy()
    parachuteAbilities[player] = nil

    parachutes[player] = World.SpawnAsset(PARACHUTE_TEMPLATE)
    parachutes[player]:AttachToPlayer(player, "root")

    PARACHUTE_PLAYER_SETTINGS:ApplyToPlayer(player)
    PARACHUTE_BASE_GRAVITY = player.gravityScale
end

-- nil ResetPlayerState(Player)
-- Resets the player to non-skydiving state and clears abilities
function ResetPlayerState(player)
    if skydivingPlayers[player] then
        Events.BroadcastToPlayer(player, "PlayerSkydiveEnd_Internal")
        Events.Broadcast("PlayerSkydiveEnd", player)
    end

    playersOnPlane[player] = nil
    skydivingPlayers[player] = nil

    if jumpAbilities[player] then
        jumpAbilities[player]:Destroy()
        jumpAbilities[player] = nil
    end

    if parachuteAbilities[player] then
        parachuteAbilities[player]:Destroy()
        parachuteAbilities[player] = nil
    end

    if parachutes[player] then
        parachutes[player]:Destroy()
        parachutes[player] = nil
    end

    DEFAULT_PLAYER_SETTINGS:ApplyToPlayer(player)
    player.canMount = true
end

-- nil OnRoundStart()
-- Handles spawning the plane
function OnRoundStart()
    local pathOffset = (math.random() * 2.0 - 1.0) * OFF_CENTER_FACTOR
    local pathAngle = 360.0 * math.random()
    local pathAngleRadians = pathAngle / 180.0 * math.pi
    local dropHalfLength = DROP_AREA_RADIUS * (1.0 - pathOffset ^ 2) ^ 0.5        -- Pythagorean theorem
    local planeForward = Vector3.New(math.cos(pathAngleRadians), math.sin(pathAngleRadians), 0.0)
    local planeRight = planeForward ^ Vector3.UP

    local planePathCenter = DROP_AREA:GetWorldPosition() + planeRight * pathOffset * DROP_AREA_RADIUS
    local planeStart = planePathCenter - planeForward * (dropHalfLength + DROP_AREA_RADIUS * PRE_DROP_FACTOR)
    local planeEnd = planePathCenter + planeForward * (dropHalfLength + DROP_AREA_RADIUS * POST_DROP_FACTOR)
    local travelTime = (planeEnd - planeStart).size / PLANE_SPEED / 100.0

    plane = World.SpawnAsset(PLANE_TEMPLATE, {position = planeStart, rotation = Rotation.New(0.0, 0.0, pathAngle)})
    plane:MoveTo(planeEnd, travelTime)

    planePathEndTime = time() + travelTime

    for _, player in pairs(Game.GetPlayers()) do
        playersOnPlane[player] = true
    end

    Events.BroadcastToAllPlayers("SkydivePlaneSpawned_Internal", plane.id)
    Events.Broadcast("SkydivePlaneSpawned", plane)
end

-- nil OnRoundEnd()
-- Clean up things in case the round ended very quickly
function OnRoundEnd()
    for _, player in pairs(Game.GetPlayers()) do
        ResetPlayerState(player)
    end

    if plane then
        Events.Broadcast("SkydivePlaneDespawned", plane)

        plane:Destroy()
        plane = nil
        planePathEndTime = 0.0
        previousInDropArea = false
    end
end

-- nil OnExecute(Ability)
-- Ejects a player when they press the binding
function OnExecuteEject(ability)
    EjectPlayer(ability.owner)
end

-- nil OnExecute(Ability)
-- Ejects a player when they press the binding
function OnExecuteParachute(ability)
    OpenParachute(ability.owner)
end

-- nil OnPlayerLeft(Player)
-- Cleans up the ability if a player leaves while in the plane
function OnPlayerLeft(player)
    ResetPlayerState(player)
end

-- nil Tick(float)
-- Handle the plane and skydiving players
function Tick(deltaTime)
    if plane then
        local inDropArea = (plane:GetWorldPosition() - DROP_AREA:GetWorldPosition()).size <= DROP_AREA_RADIUS

        if inDropArea ~= previousInDropArea then
            if inDropArea then                      -- Just entered the drop area
                for _, player in pairs(Game.GetPlayers()) do
                    if not player.isDead and playersOnPlane[player] then
                        jumpAbilities[player] = World.SpawnAsset(EJECT_ABILITY)
                        jumpAbilities[player].owner = player
                        jumpAbilities[player].executeEvent:Connect(OnExecuteEject)
                        jumpAbilities[player].name = JUMP_ABILITY_NAME
                    end
                end
            else                                    -- Just left the drop area
                for player, _ in pairs(jumpAbilities) do
                    EjectPlayer(player)
                end
            end

            previousInDropArea = inDropArea
        end

        -- Plane hit the end of it's path
        if planePathEndTime ~= 0.0 and time() >= planePathEndTime then
            Events.Broadcast("SkydivePlaneDespawned", plane)

            plane:Destroy()
            plane = nil
        end
    end

    -- Update ground height of one player, round robin style
    local players = Game.GetPlayers()
    
    if #players > 0 then
        local updatePlayer = players[tickNumber % #players + 1]
        playerGroundHeights[updatePlayer] = nil

        if skydivingPlayers[updatePlayer] then
            local elevation = nil
            local playerPosition = updatePlayer:GetWorldPosition()
            local rayEnd = playerPosition - Vector3.UP * math.max(PARACHUTE_OPEN_HEIGHT, LANDING_HEIGHT)
            local hitResult = World.Raycast(playerPosition, rayEnd, {ignorePlayers = true})

            if hitResult then
                playerGroundHeights[updatePlayer] = hitResult:GetImpactPosition().z
            end
        end
    end

    -- Update player gravity, update state
    for player, _ in pairs(skydivingPlayers) do
        local zVelocity = player:GetVelocity().z

        -- We divide the air resistance constants by 1000 to make them have reasonable scale
        if parachutes[player] then
            player.gravityScale = PARACHUTE_BASE_GRAVITY + PARACHUTE_AIR_RESISTANCE * zVelocity / 1000.0
        else
            player.gravityScale = SKYDIVE_BASE_GRAVITY + SKYDIVE_AIR_RESISTANCE * zVelocity / 1000.0
        end
        
        -- Get player elevation
        local elevation = nil

        if playerGroundHeights[player] then
            elevation = player:GetWorldPosition().z - playerGroundHeights[player]
        end

        -- Open parachute automatically
        if elevation and ALLOW_PARACHUTING and not parachutes[player] and elevation <= PARACHUTE_OPEN_HEIGHT then
            OpenParachute(player)
        end

        -- Check if they hit the ground
        if elevation and elevation <= LANDING_HEIGHT or player.isSwimming then
            ResetPlayerState(player)
        end
    end

    tickNumber = tickNumber + 1
end

-- Initialize
DROP_AREA.visibility = Visibility.FORCE_OFF

Game.roundStartEvent:Connect(OnRoundStart)
Game.roundEndEvent:Connect(OnRoundEnd)
Game.playerLeftEvent:Connect(OnPlayerLeft)
