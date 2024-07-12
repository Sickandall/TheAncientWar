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

-- Internal custom properties
local ABCP = require(script:GetCustomProperty("API"))
local COMPONENT_ROOT = script:GetCustomProperty("ComponentRoot"):WaitForObject()
local ZONE_TRIGGER = script:GetCustomProperty("ZoneTrigger"):WaitForObject()
local VISUAL_GEOMETRY = script:GetCustomProperty("VisualGeometry"):WaitForObject()
local SERVER_SCRIPT = script:GetCustomProperty("ServerScript"):WaitForObject()

-- User exposed properties
local NAME = COMPONENT_ROOT:GetCustomProperty("Name")
local CAPTURE_TIME = COMPONENT_ROOT:GetCustomProperty("CaptureTime")
local DECAY_SPEED = COMPONENT_ROOT:GetCustomProperty("DecaySpeed")
local MULTIPLY_WITH_PLAYERS = COMPONENT_ROOT:GetCustomProperty("MultiplyWithPlayers")
local CHANGE_COLOR_WHEN_DISABLED = COMPONENT_ROOT:GetCustomProperty("ChangeColorWhenDisabled")
local DISABLED_COLOR = COMPONENT_ROOT:GetCustomProperty("DisabledColor")
local ATTACKING_TEAM = COMPONENT_ROOT:GetCustomProperty("AttackingTeam")
local ORDER = COMPONENT_ROOT:GetCustomProperty("Order")

-- Check user properties
if CAPTURE_TIME <= 0.0 then
    CAPTURE_TIME = 1.0
end

if DECAY_SPEED < 0.0 then
    DECAY_SPEED = 0.0
end

if ATTACKING_TEAM ~= 1 and ATTACKING_TEAM ~= 2 then
    ATTACKING_TEAM = 1
end

-- Variables
-- This can be derived from other values, so doesn't need to be replicated. However, we care when it changes to
-- broadcast events and change colors.
local owningTeam = 0

local previousEnabledState = true

local teamColoredGeometry = {}              -- We manually set isTeamColorUsed = false when the point is neutral
local otherGeometry = {}                    -- We darken these when the point is disabled

-- float GetCaptureSpeed()
-- Returns how fast the point is being captured or uncaptured
function GetCaptureSpeed()
    if not SERVER_SCRIPT:GetCustomProperty("IsEnabled") then
        return 0.0
    end

    local friendliesPresent = SERVER_SCRIPT:GetCustomProperty("FriendliesPresent")
    local enemiesPresent = SERVER_SCRIPT:GetCustomProperty("EnemiesPresent")

    -- Contested
    if enemiesPresent > 0 and friendliesPresent > 0 then
        return 0.0
    end

    -- Empty
    if enemiesPresent == 0 and friendliesPresent == 0 then
        return -DECAY_SPEED
    end

    local multiplier = 1
    
    if enemiesPresent > 0 then
        -- Only enemies, we are moving backwards
        multiplier = -1

        if MULTIPLY_WITH_PLAYERS then
            multiplier = -1 * enemiesPresent
        end
    else
        if MULTIPLY_WITH_PLAYERS then
            multiplier = friendliesPresent
        end
    end

    return multiplier / CAPTURE_TIME
end

-- float GetCaptureProgress()
-- Returns the current progress in [0.0, 1.0].
function GetCaptureProgress()
    local timeElapsed = math.max(0.0, time() - SERVER_SCRIPT:GetCustomProperty("LastUpdateTime"))
    local captureProgress = SERVER_SCRIPT:GetCustomProperty("LastCaptureProgress") + timeElapsed * GetCaptureSpeed()
    return CoreMath.Clamp(captureProgress, 0.0, 1.0)
end

-- int GetDefendingTeam()
-- Returns which team is not attacking this poiint
function GetDefendingTeam()
	if ATTACKING_TEAM == 1 then
		return 2
	else
		return 1
	end
end

-- int GetOwningTeam()
-- Returns which team currently owns the point
function GetOwningTeam()
	if GetCaptureProgress() == 1.0 then
		return ATTACKING_TEAM
	else
		return GetDefendingTeam()
	end
end

-- bool IsPlayerPresent(Player)
-- Returns if the given player is on this point
function IsPlayerPresent(player)
    return ZONE_TRIGGER:IsOverlapping(player)
end

-- table GetState()
-- Returns a state table as defined by the API
function GetState()
    local result = {}

    result.id = COMPONENT_ROOT.id
    result.name = NAME
    result.worldPosition = COMPONENT_ROOT:GetWorldPosition()
    result.progressedTeam = ATTACKING_TEAM
    result.owningTeam = owningTeam
    result.captureProgress = GetCaptureProgress()
    result.captureThreshold = 1.0
    result.friendliesPresent = SERVER_SCRIPT:GetCustomProperty("FriendliesPresent")
    result.enemiesPresent = SERVER_SCRIPT:GetCustomProperty("EnemiesPresent")
    result.isEnabled = SERVER_SCRIPT:GetCustomProperty("IsEnabled")
    result.attackingTeam = ATTACKING_TEAM
    result.order = ORDER

    return result
end

-- nil SetGeometryTeam(int)
-- Sets the geometry to match the team color, including a neutral state
function SetGeometryTeam(team)
    for _, object in pairs(teamColoredGeometry) do
        if team == 0 then
            object.isTeamColorUsed = false
        else
            object.isTeamColorUsed = true
        end

        object.team = team
    end
end

-- nil SetGeometryEnabledColor(bool)
-- Colors geometry to match enabled state
function SetGeometryEnabledColor(enabled)
    for _, object in pairs(otherGeometry) do
        if enabled then
            object:ResetColor()
        else
            object:SetColor(DISABLED_COLOR)
        end
    end
end

-- nil GetAncestors(CoreObject, table)
-- Fills in table with all ancestors of the given object
function GetAncestors(root, result)
    for _, child in pairs(root:GetChildren()) do
        table.insert(result, child)
        GetAncestors(child, result)
    end

    return result
end

-- table CategorizeVisualGeometry()
-- Finds all objects in the visual geometry folder and categorize them by if they use team color
function CategorizeVisualGeometry()
    local objects = {}
    GetAncestors(VISUAL_GEOMETRY, objects)

    for _, object in pairs(objects) do
        if object.isTeamColorUsed then
            table.insert(teamColoredGeometry, object)
        elseif object.ResetColor then               -- We only support changing the color of things we can reset
            table.insert(otherGeometry, object)
        end
    end
end

-- nil Tick(float)
-- Handles firing events and changing the visual state
function Tick(deltaTime)
    -- Check for owner changed
    local newOwner = GetOwningTeam()

    if newOwner ~= owningTeam then
        Events.Broadcast("CapturePointOwnerChanged", COMPONENT_ROOT.id, owningTeam, newOwner)
        owningTeam = newOwner
        SetGeometryTeam(owningTeam)
    end

    -- Check for enabled state changed
    if CHANGE_COLOR_WHEN_DISABLED then
        local isEnabled = SERVER_SCRIPT:GetCustomProperty("IsEnabled")

        if isEnabled ~= previousEnabledState then
            SetGeometryEnabledColor(isEnabled)
            Events.Broadcast("CapturePointEnabledStateChanged", COMPONENT_ROOT.id, previousEnabledState, isEnabled)

            previousEnabledState = isEnabled
        end
    end
end

CategorizeVisualGeometry()
SetGeometryTeam(GetOwningTeam())

local functionTable = {}
functionTable.GetState = GetState
functionTable.IsPlayerPresent = IsPlayerPresent

ABCP.RegisterCapturePoint(COMPONENT_ROOT.id, functionTable)
