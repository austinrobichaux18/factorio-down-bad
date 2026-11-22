--Down Bad runtime: corrects anything built facing south, gates logistic requests so bots only carry items
--north/east/west, and optionally stops players moving south. Tests: tests/run.sh (appends tests/test.lua).
--Initial code modified from LoupAndSnoop's Rubia mod, with permission.

--Given a valid adjustable inserter entity, apply adjustments that will work with adjustable inserter mods.
--Return true if an edit was made.
local function try_adjust_inserter(entity)
    local old_pickup_vector = {
        x = entity.pickup_position.x - entity.position.x,
        y = entity.pickup_position.y - entity.position.y
    }

    local old_drop_vector = {
        x = entity.drop_position.x - entity.position.x,
        y = entity.drop_position.y - entity.position.y
    }

    -- Only modify inserters that pick up north and drop south (including diagonals)
    if old_pickup_vector.y < 0 and old_drop_vector.y > 0 then

        local old_pickup = entity.pickup_position
        entity.pickup_position = entity.drop_position
        entity.drop_position = old_pickup

        return true
    end

    return false
end


---Remove the last undo item from the given player index, if there is one.
---@param player_index uint?
local function squash_undo_actions(player_index)
    if not player_index then return end
    local player = game.players[player_index]
    if not player then return end
    local stack = player.undo_redo_stack

    if stack.get_undo_item_count() < 2 then return end
    local undo1 = stack.get_undo_item(1)
    local undo2 = stack.get_undo_item(2)

    if not undo1 or not undo2 then return end

    --Squash them together
    for _, action in pairs(undo1) do
        table.insert(undo2, action)
    end
    --Remove the last one
    stack.remove_undo_item(1)
end

---Take a disallowed entity away: back into the building player's inventory, or spilled on the ground
---(robot/script builds) so the item isn't lost.
---@param entity LuaEntity
---@param player_index uint?
local function remove_entity(entity, player_index)
    local player = player_index and game.get_player(player_index)
    if player then
        player.mine_entity(entity, true)
        squash_undo_actions(player_index)
    elseif entity.type == "entity-ghost" then
        entity.destroy()
    else
        local surface, position, force = entity.surface, entity.position, entity.force
        local inventory = game.create_inventory(4)
        entity.mine{inventory = inventory, force = true}
        surface.spill_inventory{position = position, inventory = inventory, enable_looted = true, force = force}
        inventory.destroy()
    end
end

---Rotate this entity once if the input function says its orientation is invalid; remove it if that doesn't help.
---@param entity LuaEntity
---@param player_index uint?
---@param is_orientation_invalid function Takes in a LuaEntity, and returns TRUE if the orientation is INVALID.
local function force_orientation_condition(entity, player_index, is_orientation_invalid)
    if not is_orientation_invalid(entity) then return end --Done without issues

    entity.rotate{by_player=player_index}
    squash_undo_actions(player_index)

    if not is_orientation_invalid(entity) then return end --Done without issues

    remove_entity(entity, player_index)
end


local function is_inserter_facing_south(entity)
    return entity.drop_position.y > entity.pickup_position.y + 0.5
end

local function is_entity_facing_south(entity)
    return entity.direction == defines.direction.south
end

local function is_rail_facing_east(entity)
    return entity.direction == defines.direction.east
end

--For all of these, direction is the direction items (or fluid) move.
local entity_not_allowed_south = {
    ["transport-belt"] = true,
    ["underground-belt"] = true,
    ["splitter"] = true,
    ["lane-splitter"] = true,
    ["loader"] = true,
    ["loader-1x1"] = true,
    ["linked-belt"] = true,
    ["pump"] = true,
    ["mining-drill"] = true,
}

local function array_to_hashset(array)
  local hashset = {}
  for _, value in pairs(array) do
    hashset[value]=1
  end
  return hashset
end

--Requester points the mod never touches: they move around or are needed for progression.
local maintain_requester_types = array_to_hashset(
    {"character", "spider-vehicle", "cargo-landing-pad", "space-platform-hub"})

--Provider points that don't count as delivery sources for the logistics rule (mobile, or robot/repair-pack supply).
local ignored_source_types = array_to_hashset(
    {"character", "spider-vehicle", "car", "roboport"})

--Track pieces. Only east-west straight rail is allowed; rail signals, train stops and supports are fine.
local rail_track_types = array_to_hashset(
    {"straight-rail", "half-diagonal-rail", "curved-rail-a", "curved-rail-b", "legacy-straight-rail",
     "legacy-curved-rail", "elevated-straight-rail", "elevated-half-diagonal-rail", "elevated-curved-rail-a",
     "elevated-curved-rail-b", "rail-ramp"})

--Entity types scanned for requester points when the mod is added to (or updated in) an existing save.
local requester_scan_types = {"logistic-container", "rocket-silo", "car", "cargo-wagon"}

---Disable a requester point and hand it to update_requesters(), which enables it if the logistics rule allows.
local function register_requester(entity)
    local point = entity.get_requester_point()
    if not point or maintain_requester_types[entity.type] then return end
    point.enabled = false
    storage.requesters = storage.requesters or {}
    storage.requesters[entity.unit_number] = entity
end

---@param entity LuaEntity Entity to correct
---@param player_index uint? Index of the player who built/rotated it; nil for robot and script builds.
local function direction_correction(entity, player_index)
    if not entity or not entity.valid then return end

    local entity_type = entity.type
    if entity_type == "entity-ghost" then
        entity_type = entity.ghost_type
    end

    --Ghosts have no requester point; robots building them raise on_robot_built_entity.
    if entity.type ~= "entity-ghost" then register_requester(entity) end

    if rail_track_types[entity_type] then
        if not (entity_type == "straight-rail" and is_rail_facing_east(entity)) then
            remove_entity(entity, player_index)
        end
        return
    end

    if entity_not_allowed_south[entity_type] then
        force_orientation_condition(entity, player_index, is_entity_facing_south)
        return
    end

    --Inserters are their own beast.
    if entity_type == "inserter" then
        local true_prototype = entity.type == "entity-ghost" and entity.ghost_prototype or entity.prototype
        if true_prototype.allow_custom_vectors then
            try_adjust_inserter(entity)
        else
            force_orientation_condition(entity, player_index, is_inserter_facing_south)
        end
    end
end

---Northernmost supply source in a network: `chests` = providers/storage and anything else providing,
---`buffers` = buffer chests (they only supply requesters set to request from buffers).
---Requester chests have a provider point too (for trash); it can't supply requesters, so it doesn't count.
local function network_sources(network)
    local sources = {chests = math.huge, buffers = math.huge}
    for _, point in pairs(network.provider_points) do
        local owner = point.owner
        local mode = owner.valid and owner.prototype.logistic_mode
        if owner.valid and not ignored_source_types[owner.type] and mode ~= "requester" then
            local key = (mode == "buffer") and "buffers" or "chests"
            sources[key] = math.min(sources[key], owner.position.y)
        end
    end
    return sources
end

---The y a requester must not be south of: buffers count only for a requester chest that requests from buffers,
---or for non-chest requesters (rocket silos etc.), to be safe.
local function requester_limit(entity, sources)
    local mode = entity.prototype.logistic_mode
    if mode == "buffer" or (mode == "requester" and not entity.request_from_buffers) then
        return sources.chests
    end
    return math.min(sources.chests, sources.buffers)
end

---Logistics rule: bots may never carry items south to a requester. A requester (or buffer) is enabled only while
---it is level with or north of every chest in its network that could supply it.
---Disabled points drop out of network.requester_points, so the mod tracks requesters in storage.requesters.
local function update_requesters()
    local sources_by_network = {}
    for unit_number, entity in pairs(storage.requesters or {}) do
        local point = entity.valid and entity.get_requester_point()
        if not point then
            storage.requesters[unit_number] = nil
        else
            local network = entity.surface.find_logistic_network_by_position(entity.position, entity.force)
            if network then
                local sources = sources_by_network[network.network_id]
                if not sources then
                    sources = network_sources(network)
                    sources_by_network[network.network_id] = sources
                end
                local allowed = entity.position.y <= requester_limit(entity, sources)
                if point.enabled ~= allowed then point.enabled = allowed end
            end
        end
    end
end

local function register_existing_requesters()
    for _, surface in pairs(game.surfaces) do
        for _, entity in pairs(surface.find_entities_filtered{type = requester_scan_types}) do
            register_requester(entity)
        end
    end
end

local function lore_print(player)
    if math.random(1, 100) == 1 then
        player.print({
            "",
            "[color=red][REDACTED][/color]: ",
            {"down-bad-lore." .. math.random(1, 99)}
        })
    end
end

---Player movement rule. Returns true if the mover had stepped south and was pushed back.
---@param mover LuaEntity The character, or the car/spidertron the player is driving.
---@param last MapPosition? Last allowed position on this surface.
local function push_back_south_step(mover, last)
    if not last or mover.position.y <= last.y then return false end
    local surface = mover.surface
    local current = mover.position
    --Keep sideways movement if that spot is free, else go back to the last spot the mover stood on.
    local target = {x = current.x, y = last.y}
    local found = surface.find_non_colliding_position(mover.name, target, 0.5, 0.05)
    if not found or found.y > last.y then found = last end
    mover.teleport(found)
    if mover.type == "car" then mover.speed = 0 end
    surface.create_trivial_smoke{name = "fire-smoke", position = {x = current.x, y = current.y + 1}}
    return true
end

local function player_positions(player_index)
    storage.player_positions = storage.player_positions or {}
    storage.player_positions[player_index] = storage.player_positions[player_index] or {}
    return storage.player_positions[player_index]
end

local function on_built(event)
    direction_correction(event.entity or event.destination, event.player_index)
end

for _, e in pairs({"on_built_entity", "on_robot_built_entity", "on_space_platform_built_entity",
                   "script_raised_built", "script_raised_revive", "on_entity_cloned",
                   "on_player_flipped_entity", "on_player_rotated_entity"}) do
    script.on_event(defines.events[e], on_built)
end

script.on_nth_tick(180, update_requesters)

script.on_event(defines.events.on_player_joined_game, function(event)
    local player = game.get_player(event.player_index)
    if not player then return end
    player.print({"player-join-world.1"})
    if settings.global["down-bad-allow-players-move-down"].value then
        player.print({"player-join-world.2"})
    else
        player.print({"player-join-world.3"})
    end
end)

script.on_init(function()
    storage.player_positions = storage.player_positions or {}
    register_existing_requesters()
end)
script.on_configuration_changed(register_existing_requesters)

--A respawn or surface change starts tracking fresh, so arriving south of the last spot isn't undone.
local function forget_position(event)
    local player = game.get_player(event.player_index)
    if player then player_positions(event.player_index)[player.surface.index] = nil end
end
script.on_event(defines.events.on_player_respawned, forget_position)
script.on_event(defines.events.on_player_changed_surface, forget_position)

--Prevents player from moving south if the setting is disabled.
script.on_event(defines.events.on_player_changed_position, function(event)
    if settings.global["down-bad-allow-players-move-down"].value then return end

    local player = game.get_player(event.player_index)
    if not player or not player.character or player.controller_type ~= defines.controllers.character then
        return --Remote view, editor, god mode, dead.
    end

    local mover = player.vehicle or player.character
    if mover.train then return end --Trains only run east-west.

    local data = player_positions(event.player_index)
    local surface_index = player.surface.index
    if push_back_south_step(mover, data[surface_index]) then
        lore_print(player)
        return
    end
    data[surface_index] = {x = mover.position.x, y = mover.position.y}
end)
