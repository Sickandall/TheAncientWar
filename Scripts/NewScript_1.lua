-- Define the bird object
local bird = {}

-- Initialize the bird
function bird:init()
    -- Load bird sprite and set initial position
    self.sprite = Sprite("path_to_bird_sprite.png")
    self.x = 100  -- Initial X position
    self.y = 100  -- Initial Y position
    self.speed = 5  -- Speed of the bird
    self.direction = math.random(0, 360)  -- Initial direction (random)
end

-- Update the bird's logic
function bird:update()
    -- Move the bird in its current direction
    self.x = self.x + math.cos(math.rad(self.direction)) * self.speed
    self.y = self.y + math.sin(math.rad(self.direction)) * self.speed

    -- Check if the bird is out of bounds and wrap around the screen
    if self.x > Screen.width then
        self.x = 0
    elseif self.x < 0 then
        self.x = Screen.width
    end

    if self.y > Screen.height then
        self.y = 0
    elseif self.y < 0 then
        self.y = Screen.height
    end

    -- Update bird's animation frame based on movement
    if self.speed > 0 then
        self.sprite:playAnimation("flying_animation")
    else
        self.sprite:playAnimation("idle_animation")
    end
end

-- Draw the bird
function bird:draw()
    self.sprite:draw(self.x, self.y)
end

-- Handle bird's interactions with other objects or player input
function bird:onInteract()
    -- Add logic for bird's interactions here
end

-- Create an instance of the bird object
local myBird = bird

-- Initialize the bird
myBird:init()

-- Update function (called every frame)
function update()
    myBird:update()
end

-- Draw function (called every frame)
function draw()
    myBird:draw()
end

-- Handle mouse click event (for interactions)
function onMouseClick(x, y, button)
    if button == Mouse.LEFT then
        myBird:onInteract()
    end
end
