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
-- Get custom properties and set handler
local ACTIVITY_HANDLER = script.parent
if ACTIVITY_HANDLER == nil then
    error('Activity handler should be the parent of the AITurretServer')
    return
end

local TURRET = script:GetCustomProperty('Turret'):WaitForObject()
local TURRET_GUNS = script:GetCustomProperty('TurretGuns'):WaitForObject()
local TURRET_WEAPON = script:GetCustomProperty('Weapon'):WaitForObject()
local TURRET_SHOOT_ABILITY = TURRET_WEAPON:GetAbilities()[1]
local TRIGGER = script:GetCustomProperty('Trigger'):WaitForObject()
local EYE_SIGHT = script:GetCustomProperty('Sight'):WaitForObject()

-- Used to let the client know what activity the server has picked
local SEARCHING_ACTIVITY_ID = 1
local ENGAGE_ACTIVITY_ID = 2
local REACQUIRE_ACTIVITY_ID = 3

-- Initialize variables
local intruders = {} -- table of intruders that enters the turret perimeter
local target = nil -- object reference used to store the target the turret is engaged with

-- DebugPrint(message, activity)
-- Accepts a message and the activity the message comes from and prints a message to the console only if the Activity's debug property is enabled in the AI Debugger
function DebugPrint(message, activity)
    if activity.isDebugModeEnabled then
        print(message)
    end
end

-- SetActiveActivityID(activityID)
-- The ActiveActiveId is used by the client script so it can know what activity is active
function SetActiveActivityID(activityID)
    TURRET:SetNetworkedCustomProperty('ActiveActivityId', activityID)
end

-- IsTableEmpty(table)
-- Accepts a table and returns if the table is empty
function IsTableEmpty(table)
    if next(table) == nil then
        -- if next returns no entry, then there were no entries in the table and therefore table is empty
        return true
    end
    -- table is not empty
    return false
end

-- Searching(speed, time, deltaTime, activity)
-- Used in both the searching and reacquire activities to:
-- 	1. If there are no intruders within TRIGGER, the turret will spin in a random direction.
-- 	2. If there are potential targets, the turret will set target based on the closest target in line of sight.
local searchTimeElapsed = 0
local searchTimeRandomOffset = math.random() * 2 + 1
local direction = 1
function Searching(speed, switchDirectionTime, deltaTime, activity)
    if IsTableEmpty(intruders) then -- If there are no intruders.
        DebugPrint('--- No Intruders Detected ---', activity)
        searchTimeElapsed = searchTimeElapsed + deltaTime
        if searchTimeElapsed >= switchDirectionTime + searchTimeRandomOffset then
            TURRET:RotateContinuous(Rotation.New(0, 0, speed * direction)) -- Rotate the turret.
            direction = -direction -- Flip the direction for next time.
            searchTimeElapsed = 0
            searchTimeRandomOffset = math.random() * 2 + 1
        end
    elseif target == nil then
        DebugPrint('--- Attempting to Acquire Target ---', activity)
        local closestDist = 9999999999 -- Initialize a ridiculously long distance.
        local sightPosition = EYE_SIGHT:GetWorldPosition() -- Initialize where the sight object is this tick.
        for _, player in ipairs(intruders) do -- Iterate over intruders.
            if Object.IsValid(player) then
                DebugPrint('--- Attempting to Acquire Target: ' .. player.name .. ' ---', activity)

                local playerPosition = player:GetWorldPosition() -- Get the position of one of the intruders.
                local hitResult = World.Raycast(sightPosition, playerPosition) -- Raycast between the sight and the intruder.
                if hitResult then
                    -- Check if our ray hit the player
                    if hitResult.other == player then
                        -- If there's a hit, see if this intruder is closer than a previous intruder.
                        local pDist = (sightPosition - playerPosition).size
                        if pDist < closestDist then
                            target = player
                            closestDist = pDist
                        end
                    end
                else
                    -- If our ray hit nothing, assume it reached the player as nothing was blocking the ray
                    local pDist = (sightPosition - playerPosition).size
                    if pDist < closestDist then
                        target = player
                        closestDist = pDist
                    end
                end
            end
        end
        if Object.IsValid(target) then
            DebugPrint('--- Target Acquired: ' .. target.name .. ' ---', activity)
        end
    end
end

-- Searching Activity
-- This is the default state for the turret. If the turret has no target and is not trying to reacquire, it spins slowly.
local searchActivityTable = {}

function searchActivityTable.tick(activity, deltaTime)
    activity.priority = 100
end

function searchActivityTable.tickHighestPriority(activity, deltaTime)
    Searching(25, 5, deltaTime, activity)
end

function searchActivityTable.start(activity)
    DebugPrint('### Searching_Start ###', activity)
    Searching(25, 5, 5, activity)
    SetActiveActivityID(SEARCHING_ACTIVITY_ID)
end

function searchActivityTable.stop(activity)
    DebugPrint('### Searching_End ###', activity)
    TURRET:StopRotate()
end

-- Engage Activity
-- When there is a target, the turret engages. It attempts to maintain line of sight and fires its weapon if able.
local engageActivityTable = {}
local reacquireTime = 0
local engageHitResult = nil

function engageActivityTable.tick(activity, deltaTime)
    if Object.IsValid(target) then -- If there's a target, set the engage activity priority to the top.
        local targetOffset =
            (target:GetWorldPosition() - EYE_SIGHT:GetWorldPosition()):GetNormalized() * 100 + Vector3.UP * 50
        local hitResult = World.Raycast(EYE_SIGHT:GetWorldPosition(), target:GetWorldPosition() + targetOffset)
        if hitResult then
            if hitResult.other == target then
                activity.priority = 200
                engageHitResult = target
            else
                -- there was something in the way of our raycast to the player
                activity.priority = 0
                engageHitResult = nil
            end
        else -- nothing was in the way of the player
            activity.priority = 200
            engageHitResult = target
        end
    else -- if there is no target, deactivate this activity.
        activity.priority = 0
        engageHitResult = nil
    end
end

function engageActivityTable.tickHighestPriority(activity, deltaTime)
    DebugPrint('--- Engaging Target: ' .. target.name .. ' ---', activity)

    if engageHitResult then
        CoreDebug.DrawLine(EYE_SIGHT:GetWorldPosition(), engageHitResult:GetWorldPosition(), {thickness = 3})
        if engageHitResult == target then
            DebugPrint('--- Target Identified. Open Fire: ' .. target.name .. ' ---', activity)
            -- Only fire when the ability is ready
            if TURRET_SHOOT_ABILITY:GetCurrentPhase() == AbilityPhase.READY then
                TURRET_WEAPON:Attack()
                -- Alternate the barrel we shoot from
                TURRET_WEAPON:SetPosition(
                    Vector3.New(
                        TURRET_WEAPON:GetPosition().x,
                        TURRET_WEAPON:GetPosition().y * -1,
                        TURRET_WEAPON:GetPosition().z
                    )
                )
            end
        end
    end
end

function engageActivityTable.start(activity)
    DebugPrint('### Engage_Start ###', activity)
    TURRET:LookAtContinuous(target, true, math.pi * 2)
    TURRET_GUNS:LookAtContinuous(target, false, math.pi * 2)
    SetActiveActivityID(ENGAGE_ACTIVITY_ID)
end

function engageActivityTable.stop(activity)
    DebugPrint('### Engage_End ###', activity)
    reacquireTime = 10 -- when engagement is lost, initialize reacquireTime.
    TURRET_GUNS:StopRotate()
    TURRET_GUNS:RotateTo(Rotation.ZERO, 25, true)
end

-- Reacquire Activity
-- if reacquireTime is > 0 then attempt to reacquire, otherwise reenter the Searching activity. This is basically the exact same activity as Searching but with a more aggressive turret.
local reacquireActivityTable = {}

function reacquireActivityTable.tick(activity, deltaTime)
    if reacquireTime <= 0 then
        activity.priority = 0
    else
        activity.priority = 150
    end
end

function reacquireActivityTable.tickHighestPriority(activity, deltaTime)
    Searching(150, 1, deltaTime, activity)
    reacquireTime = reacquireTime - deltaTime
end

function reacquireActivityTable.start(activity)
    DebugPrint('### Reacquire_Start ###', activity)
    Searching(150, 1, 1, activity)
    SetActiveActivityID(REACQUIRE_ACTIVITY_ID)
end

function reacquireActivityTable.stop(activity)
    DebugPrint('### Reacquire_End ###', activity)
    TURRET:StopRotate()
end

-- OnIntruderDetected/Lost(trigger, player)
-- When players enter the turret trigger, add them to the intruders table. When they leave, remove them.
function OnIntruderDetected(trigger, player)
    if player and player:IsA('Player') then
        table.insert(intruders, player)
    end
end

function OnIntruderLost(trigger, player)
    if player and player:IsA('Player') then
        for i, p in ipairs(intruders) do
            if p == player then
                table.remove(intruders, i)
                if p == target then
                    target = nil
                end
                break
            end
        end
    end
end

-- Event subscriptions and Activity creation
TRIGGER.beginOverlapEvent:Connect(OnIntruderDetected)
TRIGGER.endOverlapEvent:Connect(OnIntruderLost)

local SEARCHING_ACTIVITY = ACTIVITY_HANDLER:AddActivity('Searching', searchActivityTable)
local ENGAGE_ACTIVITY = ACTIVITY_HANDLER:AddActivity('Engage', engageActivityTable)
local REACQUIRE_ACTIVITY = ACTIVITY_HANDLER:AddActivity('Reacquire', reacquireActivityTable)
