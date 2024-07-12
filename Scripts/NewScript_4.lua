function OnPlayerDamaged(player, damage)
    print("player "..player.name.." received "..tostring(damage.amount).." damage")
    -- do something when player gets damage
	
end

function OnPlayerDied(player, damage)
    print("player "..player.name.." died and received "..tostring(damage.amount).." damage")
    -- do something when player dies
	
end

function OnPlayerSpawned(player, startObj, spawnKey)
    print("player "..player.name.." spawned at "..tostring(startObj).." with key "..spawnKey)
    -- do something if player spawned
	
end

function OnPlayerJoined(player)
	player.damagedEvent:Connect(OnPlayerDamaged)
	player.diedEvent:Connect(OnPlayerDied)
	player.spawnedEvent:Connect(OnPlayerSpawned)
end

Game.playerJoinedEvent:Connect(OnPlayerJoined)
