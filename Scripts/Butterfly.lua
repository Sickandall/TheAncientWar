local butterfly = script.parent

function flapWings()
    butterfly:SetRotation(Vector3.UP * math.sin(time() * 10) * 10)
end

function moveUpAndDown()
    butterfly:SetPosition(butterfly:GetPosition() + Vector3.UP * math.sin(time() * 2))
end

function Tick(deltaTime)
    flapWings()
    moveUpAndDown()
end
