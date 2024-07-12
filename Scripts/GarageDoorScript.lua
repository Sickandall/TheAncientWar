local trigger = script.parent
local door = script:GetCustomProperty('Door'):WaitForObject()

local isOpen = false

local initialRotation = door:GetWorldRotation()

function UpdateLabel()
    if (isOpen) then
        trigger.interactionLabel = 'Close'
    else
        trigger.interactionLabel = 'Open'
    end
end

function OnInteracted(whichTrigger, whichCharacter)
    isOpen = not isOpen

    if (isOpen) then
        local tPos = trigger:GetWorldPosition()
        local dPos = door:GetWorldPosition()
        dPos = Vector3.New(dPos.x, dPos.y, tPos.z)

        local vChar = (tPos - whichCharacter:GetWorldPosition()):GetNormalized()
        local vDoor = (tPos - dPos):GetNormalized()
        local crossProduct = vChar ^ vDoor

        -- Figuring out which side of the door the player is
        if (crossProduct.z >= 0) then
            door:RotateTo(initialRotation + Rotation.New(-90, 0, 0), 0.5)
        else
            door:RotateTo(initialRotation + Rotation.New(90, 0, 0), 0.5)
        end
    else
        door:RotateTo(initialRotation, 0.5)
    end

    UpdateLabel()
end

trigger.interactedEvent:Connect(OnInteracted)

UpdateLabel()
