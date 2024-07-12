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
local COMPONENT_ROOT = script:GetCustomProperty("ComponentRoot"):WaitForObject()
local ELEVATION_TEXT = script:GetCustomProperty("ElevationText"):WaitForObject()
local SPEED_TEXT = script:GetCustomProperty("SpeedText"):WaitForObject()

-- User exposed properties
local SKYDIVE_CAMERA = COMPONENT_ROOT:GetCustomProperty("SkydiveCamera"):WaitForObject()
local LANDING_SOUND_TEMPLATE = COMPONENT_ROOT:GetCustomProperty("LandingSoundTemplate")

-- Constants
local LOCAL_PLAYER = Game.GetLocalPlayer()
local ELEVATION_CHECK_PERIOD = 0.5
local MIN_DISPLAY_HEIGHT = 800.0
local MAX_DISPLAY_HEIGHT = 100000.0

-- Variables
local lastGroundHeightCheck = time()
local lastGroundHeight = 0.0

-- nil OnSkydivePlaneSpawned(String)
-- Setup the plane camera on the player
function OnSkydivePlaneSpawned(planeID)
	while not World.FindObjectById(planeID) do
		Task.Wait()
	end

	local camera = World.FindObjectById(planeID):GetCustomProperty("Camera"):WaitForObject()

	LOCAL_PLAYER:SetOverrideCamera(camera)
end

-- nil OnSkydiveStart()
-- Clear the plane camera or replace with the skydive camera
function OnSkydiveStart()
	-- Add a short wait for visuals to line up correctly
	Task.Wait(0.2)

	-- Set our character to be looking where our view was while watching the plane
    LOCAL_PLAYER:SetLookWorldRotation(LOCAL_PLAYER:GetViewWorldRotation())

	if SKYDIVE_CAMERA then
		LOCAL_PLAYER:SetOverrideCamera(SKYDIVE_CAMERA)
	else
		LOCAL_PLAYER:ClearOverrideCamera()
	end
end

-- nil OnSkydiveEnd()
-- Clears the local player's override camera and plays a landing sound
function OnSkydiveEnd()
	LOCAL_PLAYER:ClearOverrideCamera()
	World.SpawnAsset(LANDING_SOUND_TEMPLATE, {position = LOCAL_PLAYER:GetWorldPosition()})
end

-- nil Tick(float)
-- Update UI elements
function Tick(deltaTime)
    local playerPosition = LOCAL_PLAYER:GetWorldPosition()

	-- Update ground height
	if time() > lastGroundHeightCheck + ELEVATION_CHECK_PERIOD then
		lastGroundHeightCheck = time()

        lastGroundHeight = nil
        local rayEnd = playerPosition - Vector3.UP * MAX_DISPLAY_HEIGHT
        local hitResult = World.Raycast(playerPosition, rayEnd, {ignorePlayers = true})

        if hitResult then
            lastGroundHeight = hitResult:GetImpactPosition().z
        end
	end

	-- Update elevation and speed displays
	ELEVATION_TEXT.text = ""
	SPEED_TEXT.text = ""

	if lastGroundHeight then
		local elevation = playerPosition.z - lastGroundHeight

		if elevation >= MIN_DISPLAY_HEIGHT then
			ELEVATION_TEXT.text = string.format("%dm", elevation // 100)
			SPEED_TEXT.text = string.format("%.1fm/s", math.abs(LOCAL_PLAYER:GetVelocity().z / 100.0))
		end
	end
end

Events.Connect("SkydivePlaneSpawned_Internal", OnSkydivePlaneSpawned)
Events.Connect("PlayerSkydiveStart_Internal", OnSkydiveStart)
Events.Connect("PlayerSkydiveEnd_Internal", OnSkydiveEnd)
