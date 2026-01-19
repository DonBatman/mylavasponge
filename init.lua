local states = {
    {
        id = "dry", desc = "Dry Lava Sponge", tex = "mylavasponge_sponge.png", size = 0.5, 
        inv = true, next_state = nil, dry_time = 0, drip_count = 0, steam_count = 0, lava_yield = 0
    },
    {
        id = "warm", desc = "Warm Lava Sponge", tex = "mylavasponge_sponge2.png", size = 0.7, 
        inv = false, next_state = "dry", dry_time = 45, drip_count = 2, steam_count = 1, lava_yield = 1
    },
    {
        id = "hot", desc = "Hot Lava Sponge", tex = "mylavasponge_sponge3.png", size = 0.85, 
        inv = false, next_state = "warm", dry_time = 60, drip_count = 8, steam_count = 3, lava_yield = 2
    },
    {
        id = "full", desc = "Full Lava Sponge", tex = "mylavasponge_sponge4.png", size = 1.0, 
        inv = false, next_state = "hot", dry_time = 90, drip_count = 25, steam_count = 10, lava_yield = 3
    },
}

local function is_touching_lava(pos)
    local sides = {
        {x = pos.x + 1, y = pos.y,     z = pos.z},
        {x = pos.x - 1, y = pos.y,     z = pos.z},
        {x = pos.x,     y = pos.y + 1, z = pos.z},
        {x = pos.x,     y = pos.y - 1, z = pos.z},
        {x = pos.x,     y = pos.y,     z = pos.z + 1},
        {x = pos.x,     y = pos.y,     z = pos.z - 1},
    }
    for _, s_pos in ipairs(sides) do
        local node = core.get_node(s_pos)
        if core.get_item_group(node.name, "lava") ~= 0 then
            return true
        end
    end
    return false
end

local function absorb_lava(pos)
    if not is_touching_lava(pos) then
        return false
    end

    local radius = 1
    local nodes = core.find_nodes_in_area(
        {x = pos.x - radius, y = pos.y - radius, z = pos.z - radius},
        {x = pos.x + radius, y = pos.y + radius, z = pos.z + radius},
        {"group:lava"}
    )
    
    if #nodes > 0 then
        for _, p in ipairs(nodes) do
            core.remove_node(p)
        end
        core.set_node(pos, {name = "mylavasponge:sponge_full"})
        return true
    end
    return false
end

local state_data = {}
for _, s in ipairs(states) do state_data["mylavasponge:sponge_" .. s.id] = s end

for _, state in ipairs(states) do
    local box_size = state.size / 2
    local groups = {dig_immediate = 3, lavasponge = 1, fire = 1,igniter = 1}
    if state.id == "dry" then groups.lavasponge_dry = 1 end
    if not state.inv then groups.not_in_creative_inventory = 1 end

    core.register_node("mylavasponge:sponge_" .. state.id, {
        description = state.desc,
        tiles = {state.tex},
        drawtype = "nodebox",
        paramtype = "light",
        groups = groups,
        node_box = {
            type = "fixed",
            fixed = {-box_size, -0.5, -box_size, box_size, -0.5 + state.size, box_size},
        },
        
        on_construct = function(pos)
            if state.id == "dry" then
                absorb_lava(pos)
            elseif state.next_state then
                core.get_node_timer(pos):start(2)
            end
        end,

        on_neighbor_update = function(pos, node, neighbor_pos)
            if state.id == "dry" then
                absorb_lava(pos)
            end
        end,

        on_punch = function(pos, node, puncher, pointed_thing)
            if not puncher or not state.next_state then return end
            
            local held_item = puncher:get_wielded_item()
            if held_item:get_name() == "bucket:bucket_empty" then
                core.set_node(pos, {name = "mylavasponge:sponge_" .. state.next_state})
                
                held_item:take_item()
                puncher:set_wielded_item(held_item)
                
                local inv = puncher:get_inventory()
                local lava_bucket = ItemStack("bucket:bucket_lava")
                if inv:room_for_item("main", lava_bucket) then
                    inv:add_item("main", lava_bucket)
                else
                    core.add_item(puncher:get_pos(), lava_bucket)
                end
                
                core.sound_play("default_water_footstep", {pos = pos, gain = 0.5})
            end
        end,

        on_timer = function(pos, elapsed)
            --local surrounding = core.find_nodes_in_area(vector.subtract(pos, 1), vector.add(pos, 1), {"group:lava"})
            --if #surrounding > 0 then
            --    core.set_node(pos, {name = "mylavasponge:dried_leaves"})
            --    return false
            --end

            if not state.next_state then return false end

            local meta = core.get_meta(pos)
            local neighbors = core.find_nodes_in_area(vector.subtract(pos, 1), vector.add(pos, 1), {"air"})
            
            if #neighbors > 0 then
                meta:set_int("is_drying", 1)
                local current_dry = (meta:get_float("dry_progress") or 0) + elapsed
                if current_dry >= state.dry_time then
                    core.set_node(pos, {name = "mylavasponge:sponge_" .. state.next_state})
                    return false
                end
                meta:set_float("dry_progress", current_dry)
            else
                meta:set_int("is_drying", 0)
            end
            return true
        end,

        on_blast = function(pos, intensity)
            core.remove_node(pos)
            return {"mylavasponge:sponge_" .. state.id}
        end,
    })

    if state.lava_yield > 0 then
        core.register_craft({
            type = "cooking",
            output = "mylavasponge:sponge_dry",
            recipe = "mylavasponge:sponge_" .. state.id,
            cooktime = 3,
            replacements = {
                {"mylavasponge:sponge_" .. state.id, "default:lava_source " .. state.lava_yield}
            }
        })
    end
end

core.register_abm({
    label = "Sponge Absorption Check",
    nodenames = {"mylavasponge:sponge_dry"},
    neighbors = {"group:lava"},
    interval = 1.0,
    chance = 1,
    action = function(pos, node)
        absorb_lava(pos)
    end,
})

core.register_abm({
    label = "Sponge Effects",
    nodenames = {"group:lavasponge"},
    interval = 1.0,
    chance = 1,
    action = function(pos, node)
        local data = state_data[node.name]
        if not data then return end
        if data.drip_count > 0 then
            core.add_particlespawner({
                amount = data.drip_count,
                time = 1,
                minpos = {x=pos.x-0.2, y=pos.y-0.4, z=pos.z-0.2},
                maxpos = {x=pos.x+0.2, y=pos.y-0.1, z=pos.z+0.2},
                minvel = {x=0, y=-1, z=0},
                maxvel = {x=0, y=-2, z=0},
                minacc = {x=0, y=-9.8, z=0},
                maxacc = {x=0, y=-9.8, z=0},
                minexptime = 0.5,
                maxexptime = 1.0,
                minsize = 1,
                maxsize = 2,
                texture = "mylavasponge_drip.png",
            })
        end
        local meta = core.get_meta(pos)
        if meta:get_int("is_drying") == 1 and data.steam_count > 0 then
            core.add_particlespawner({
                amount = data.steam_count,
                time = 1,
                minpos = {x=pos.x-0.3, y=pos.y, z=pos.z-0.3},
                maxpos = {x=pos.x+0.3, y=pos.y+0.3, z=pos.z+0.3},
                minvel = {x=-0.1, y=0.2, z=-0.1},
                maxvel = {x=0.1, y=2.5, z=0.1},
                minexptime = 1,
                maxexptime = 2,
                minsize = 0.5,
                maxsize = 2,
                texture = "mylavasponge_evap.png",
            })
        end
    end,
})
if core.get_modpath("lucky_block") then
	lucky_block:add_blocks({
		{"dro", {"mylavasponge:sponge_dry"}, 4},
	})
end
