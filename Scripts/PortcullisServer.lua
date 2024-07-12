--[[
Copyright 2020 Manticore Games, Inc. 

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
Doors operate in the relative space of the root of the component. In that space, they move in the +Z direction. The Door
root should have position (0.0, 0.0, 0.0).
This broadcasts custom events DoorOpened(CoreObject) and DoorClosed(CoreObject)
--]]

-- Internal custom properties
local COMPONENT_ROOT = script:GetCustomProperty("ComponentRoot"):WaitForObject()
local DOOR_ROOT = script:GetCustomProperty("DoorRoot"):WaitForObject()
local TRIGGER = script:GetCustomProperty("Trigger"):WaitForObject()
local LEVER_ROOT = script:GetCustomProperty("LeverRoot"):WaitForObject()
local WINCH_ROOT = script:GetCustomProperty("WinchRoot"):WaitForObject()

-- User exposed properties
local OPEN_LABEL = COMPONENT_ROOT:GetCustomProperty("OpenLabel")	-- Only used without AutoOpen
local CLOSE_LABEL = COMPONENT_ROOT:GetCustomProperty("CloseLabel")	-- Only used without AutoOpen
local OPEN_DISTANCE = COMPONENT_ROOT:GetCustomProperty("OpenDistance")
local SPEED = COMPONENT_ROOT:GetCustomProperty("Speed")
local RESET_ON_ROUND_START = COMPONENT_ROOT:GetCustomProperty("ResetOnRoundStart")

-- Check user properties
if SPEED <= 0.0 then
    warn("Speed must be positive")
    SPEED = 450.0
end

-- Constants
local USE_DEBOUNCE_TIME = 0.1			-- Time after using that a player can't use again

-- Variables
-- Offset is 1.0 for fully opened, 0.0 for closed
local targetDoorOffset = 0.0
local playerLastUseTimes = {}			-- Player -> float
local autoCloseTime = 0.0

-- float GetDoorOffset()
-- Gives you the current offset of the door
function GetDoorOffset()
	return DOOR_ROOT:GetPosition().z / OPEN_DISTANCE
end

-- nil SetCurrentOffset(float)
-- Snap instantly to the given offset
function SetCurrentOffset(offset)
	targetDoorOffset = offset
	DOOR_ROOT:SetPosition(Vector3.New(0.0, 0.0, OPEN_DISTANCE * offset))
	WINCH_ROOT:SetRotation(Rotation.New(0.0, 0.0, 0.0))
end

-- nil SetTargetOffset(float)
-- Sets the offset that the door should move to (at SPEED)
function SetTargetOffset(offset)
	targetDoorOffset = offset
	local t = OPEN_DISTANCE * math.abs(targetDoorOffset - GetDoorOffset()) / SPEED
	DOOR_ROOT:MoveTo(Vector3.New(0.0, 0.0, OPEN_DISTANCE * offset), t, true)

	Task.Spawn(function()
		if offset > GetDoorOffset() then
			WINCH_ROOT:RotateContinuous(Vector3.New(0.0, SPEED / 100.0, 0.0),true)
		else
			WINCH_ROOT:RotateContinuous(Vector3.New(0.0, -SPEED / 100.0, 0.0),true)
		end

		Task.Wait(t)
		WINCH_ROOT:StopRotate()
	end)
end

-- nil ResetDoor()
-- Instantly snaps the door to the closed state
function ResetDoor()
	SetCurrentOffset(0.0)
	LEVER_ROOT:SetRotation(Rotation.New(0, 10.0, 0))
end

-- nil OpenDoor(Player)
-- Opens the door
function OpenDoor(player)
	SetTargetOffset(1.0)
	LEVER_ROOT:RotateTo(Rotation.New(0, -40, 0), 0.3, true)
	Events.Broadcast("DoorOpened", COMPONENT_ROOT)
end

-- nil CloseDoor()
-- Closes the door, even if it was only partially open
function CloseDoor()
	SetTargetOffset(0.0)
	LEVER_ROOT:RotateTo(Rotation.New(0, 10, 0), 0.3, true)
end

-- nil OnInteracted(Trigger, CoreObject)
-- Handles the player using the door if AutoOpen is false
function OnInteracted(trigger, player)
	if playerLastUseTimes[player] and playerLastUseTimes[player] + USE_DEBOUNCE_TIME > time() then
		return
	end

	playerLastUseTimes[player] = time()

	if GetDoorOffset() == 0.0 then									-- Door is closed
		OpenDoor(player)

		TRIGGER.interactionLabel = CLOSE_LABEL
	else															-- Door is open or moving, clsoe it
		CloseDoor()
	end
end

-- nil OnRoundStart()
-- Handles the roundStartEvent
function OnRoundStart()
	ResetDoor()
end

-- nil Tick(float)
-- Handle changing interaction label back to open
function Tick(deltaTime)
	if targetDoorOffset == 0.0 and GetDoorOffset() == 0.0 then
		TRIGGER.interactionLabel = OPEN_LABEL

		Events.Broadcast("DoorClosed", COMPONENT_ROOT)
	end
end

-- Initialize
TRIGGER.interactedEvent:Connect(OnInteracted)

if RESET_ON_ROUND_START then
	Game.roundStartEvent:Connect(OnRoundStart)
end
