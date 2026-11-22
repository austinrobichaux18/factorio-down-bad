--Headless tests. tests/run.sh appends this file to control.lua, so the mod's locals are in scope.
--Results are logged as "DOWNBAD-TEST ..." lines; run.sh turns them into an exit code.
---@diagnostic disable: undefined-global

local results = {pass = 0, fail = 0}
local function check(name, ok, detail)
    if ok then
        results.pass = results.pass + 1
        log("DOWNBAD-TEST PASS " .. name)
    else
        results.fail = results.fail + 1
        log("DOWNBAD-TEST FAIL " .. name .. (detail and (": " .. detail) or ""))
    end
end

local S = defines.direction.south

local function setup(surface)
    local tiles = {}
    for x = -10, 110 do for y = -20, 130 do tiles[#tiles + 1] = {name = "refined-concrete", position = {x, y}} end end
    surface.set_tiles(tiles)
    for _, e in pairs(surface.find_entities_filtered{area = {{-10, -20}, {110, 130}}}) do e.destroy() end
end

local function make(surface, args)
    args.force = args.force or "player"
    return surface.create_entity(args)
end

local function test_directions(surface)
    local x = 0
    for _, name in pairs({"transport-belt", "underground-belt", "splitter", "lane-splitter", "loader-1x1",
                          "linked-belt", "pump", "burner-mining-drill"}) do
        x = x + 4
        local e = make(surface, {name = name, position = {x, 0}, direction = S})
        if not e then
            check("dir " .. name, false, "could not create")
        else
            direction_correction(e, nil)
            check("dir " .. name, e.valid and e.direction ~= S, e.valid and ("direction " .. e.direction) or "removed")
        end
    end

    local ghost = make(surface, {name = "entity-ghost", inner_name = "transport-belt", position = {40, 0}, direction = S})
    direction_correction(ghost, nil)
    check("dir ghost belt", ghost.valid and ghost.direction ~= S)

    local north_belt = make(surface, {name = "transport-belt", position = {44, 0}, direction = defines.direction.north})
    direction_correction(north_belt, nil)
    check("dir north belt untouched", north_belt.valid and north_belt.direction == defines.direction.north)

    for i, d in pairs({defines.direction.north, S}) do
        local ins = make(surface, {name = "inserter", position = {50 + i * 3, 0}, direction = d})
        direction_correction(ins, nil)
        check("inserter dir " .. d, ins.valid and not is_inserter_facing_south(ins),
              ins.valid and ("drop " .. serpent.line(ins.drop_position)) or "removed")
    end
end

local function test_rails(surface)
    local east = make(surface, {name = "straight-rail", position = {11, 21}, direction = defines.direction.east})
    direction_correction(east, nil)
    check("rail east kept", east.valid)

    local signal = make(surface, {name = "rail-signal", position = {11.5, 19.5}, direction = defines.direction.east})
    if signal then
        direction_correction(signal, nil)
        check("rail signal kept", signal.valid)
    else
        check("rail signal kept", false, "could not create")
    end

    local north = make(surface, {name = "straight-rail", position = {31, 31}, direction = defines.direction.north})
    direction_correction(north, nil)
    local spilled = surface.find_entities_filtered{name = "item-on-ground", position = {31, 31}, radius = 4}
    check("rail north removed and spilled", not north.valid and #spilled > 0, "spilled " .. #spilled)

    local curve = make(surface, {name = "curved-rail-a", position = {51, 31}})
    if curve then
        direction_correction(curve, nil)
        check("curved rail removed", not curve.valid)
    end
end

local function test_logistics(surface)
    make(surface, {name = "roboport", position = {50, 100}})
    make(surface, {name = "electric-energy-interface", position = {54, 100}})
    make(surface, {name = "medium-electric-pole", position = {52, 98}})
    local c = {}
    c.provider = make(surface, {name = "passive-provider-chest", position = {50.5, 95.5}})
    c.req_north = make(surface, {name = "requester-chest", position = {44.5, 90.5}})
    c.req_level = make(surface, {name = "requester-chest", position = {40.5, 95.5}})
    c.req_south = make(surface, {name = "requester-chest", position = {44.5, 110.5}})
    c.buffer_north = make(surface, {name = "buffer-chest", position = {56.5, 85.5}})
    for _, e in pairs(c) do direction_correction(e, nil) end
    check("new requester starts disabled", c.req_north.get_requester_point().enabled == false)
    return c
end

local function check_logistics(c)
    update_requesters()
    check("requester north of providers enabled", c.req_north.get_requester_point().enabled)
    check("requester level with providers enabled", c.req_level.get_requester_point().enabled)
    check("requester south of a provider disabled", not c.req_south.get_requester_point().enabled)
    check("buffer north of providers enabled", c.buffer_north.get_requester_point().enabled)
    --The buffer is north of req_north: counts only once req_north requests from buffers.
    c.req_north.request_from_buffers = true
    update_requesters()
    check("buffer counts as a source when requesting from buffers", not c.req_north.get_requester_point().enabled)
    c.req_north.request_from_buffers = false
    update_requesters()
    --A provider further north now makes the north requester a southward delivery.
    local p2 = c.provider.surface.create_entity{name = "passive-provider-chest", position = {48.5, 80.5}, force = "player"}
    update_requesters()
    check("requester disabled once a provider is north of it", not c.req_north.get_requester_point().enabled)
    p2.destroy()
    update_requesters()
    check("requester re-enabled when that provider is gone", c.req_north.get_requester_point().enabled)
end

local function overlaps(a, b)
    return a.left_top.x < b.right_bottom.x and b.left_top.x < a.right_bottom.x
       and a.left_top.y < b.right_bottom.y and b.left_top.y < a.right_bottom.y
end

local function test_movement(surface)
    check("no history: no push", not push_back_south_step(make(surface, {name = "character", position = {80.5, 0.5}}), nil))

    local ch = make(surface, {name = "character", position = {90.5, 0.5}})
    local last = {x = 90.5, y = 0.5}
    ch.teleport({90.7, 0.9})
    local pushed = push_back_south_step(ch, last)
    check("push back keeps sideways move", pushed and ch.position.y <= last.y and math.abs(ch.position.x - 90.7) < 0.1,
          serpent.line(ch.position))

    --Sliding sideways would end inside a wall: must not land in it.
    local wall = make(surface, {name = "stone-wall", position = {101.5, 0.5}})
    local ch2 = make(surface, {name = "character", position = {100.5, 0.5}})
    local last2 = {x = 100.5, y = 0.5}
    ch2.teleport({101.2, 1.6})
    push_back_south_step(ch2, last2)
    check("push back avoids walls", ch2.position.y <= last2.y and not overlaps(ch2.bounding_box, wall.bounding_box),
          serpent.line(ch2.position))

    local car = make(surface, {name = "car", position = {70, 0}})
    car.speed = 0.2
    car.teleport({70, 1})
    push_back_south_step(car, {x = 70, y = 0})
    check("car pushed back and stopped", car.position.y <= 0 and car.speed == 0, serpent.line(car.position))
end

script.on_event(defines.events.on_tick, function(event)
    local surface = game.surfaces[1]
    if event.tick == 0 then
        surface.request_to_generate_chunks({50, 50}, 5)
        surface.force_generate_chunk_requests()
        setup(surface)
        test_directions(surface)
        test_rails(surface)
        storage.test_chests = test_logistics(surface)
        test_movement(surface)
    elseif event.tick == 5 then
        check_logistics(storage.test_chests)
        log("DOWNBAD-TEST DONE pass=" .. results.pass .. " fail=" .. results.fail)
    end
end)
