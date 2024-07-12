--[[
Copyright 2021 Manticore Games, Inc.

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

-- Get custom properties
local TURRET = script:GetCustomProperty("Turret"):WaitForObject()
local EYE_SEARCHING = script:GetCustomProperty("EyeSearching"):WaitForObject()
local EYE_ALERT = script:GetCustomProperty("EyeTargetAcquired"):WaitForObject()
local TURRET_SERVO_SFX = script:GetCustomProperty("ServoRotateSFX"):WaitForObject()
local GUN_SPIN_SFX = script:GetCustomProperty("MinigunLoopSFX"):WaitForObject()
local GUN_WINDDOWN_SFX = script:GetCustomProperty("MinigunWindDownSFX"):WaitForObject()
local ALARM_SFX = script:GetCustomProperty("AlarmSFX"):WaitForObject()

-- These IDs are used by AITurretServer to let the client know what activity the server chose
local SEARCHING_ACTIVITY_ID = 1
local ENGAGE_ACTIVITY_ID = 2
local REACQUIRE_ACTIVITY_ID = 3

-- Initialize variables
local activeActivityID = 0
local lastTickTurretRot = 0

function OnNetworkedPropertyChanged(owner, propertyName)
    if propertyName ~= "ActiveActivityId" then
        return
    end

    local nextActivity = TURRET:GetCustomProperty("ActiveActivityId")
    local prevActivity = activeActivityID

    if nextActivity == prevActivity then
        return
    end

    if prevActivity == SEARCHING_ACTIVITY_ID then
        EYE_SEARCHING.visibility = Visibility.FORCE_OFF
    elseif prevActivity == REACQUIRE_ACTIVITY_ID then
        EYE_ALERT.visibility = Visibility.FORCE_OFF
        ALARM_SFX:Stop()
        GUN_SPIN_SFX:Stop()
        GUN_WINDDOWN_SFX:Play()
    end

    if nextActivity == SEARCHING_ACTIVITY_ID then
        EYE_SEARCHING.visibility = Visibility.INHERIT
    elseif nextActivity == ENGAGE_ACTIVITY_ID then
        EYE_ALERT.visibility = Visibility.INHERIT
        ALARM_SFX:Play()
        GUN_SPIN_SFX:Play()
    end

    activeActivityID = nextActivity
end

-- Tick()
-- Check every frame if the turret's rotation is different than the previous frame. If true, play TURRET_SERVO_SFX.

function Tick()
	local currentTurretRot = TURRET:GetWorldRotation().z
	if currentTurretRot ~= lastTickTurretRot then
		TURRET_SERVO_SFX:Play()
	else
		TURRET_SERVO_SFX:Stop()
	end
	lastTickTurretRot = currentTurretRot
end


TURRET.networkedPropertyChangedEvent:Connect(OnNetworkedPropertyChanged)