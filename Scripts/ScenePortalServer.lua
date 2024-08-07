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

-- Internal custom properties
local COMPONENT_ROOT = script:GetCustomProperty("ComponentRoot"):WaitForObject()
local TRIGGER = script:GetCustomProperty("Trigger"):WaitForObject()

-- User exposed properties
local DESTINATION_SCENE = COMPONENT_ROOT:GetCustomProperty("DestinationScene")

-- Check user properties
if DESTINATION_SCENE == "" then
	error([[DestinationScene missing or invalid. Specify the scene name.]])
end

-- nil OnBeginOverlap(Trigger, Object)
-- If the trigger is not interactible, portal any player who touches it to the destination scene
function OnBeginOverlap(trigger, other)
	if other:IsA("Player") and not trigger.isInteractable then
		other:TransferToScene(DESTINATION_SCENE)
	end
end

-- nil OnInteracted(Trigger, Player)
-- Portal any player who uses this to the destination scene
function OnInteracted(trigger, player)
	player:TransferToScene(DESTINATION_SCENE)
end

-- Initialize
TRIGGER.beginOverlapEvent:Connect(OnBeginOverlap)
TRIGGER.interactedEvent:Connect(OnInteracted)
