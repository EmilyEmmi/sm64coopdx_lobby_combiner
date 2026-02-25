_G.lobbyCombiner = {}

lobbyCombiner.toggle_player_list = function(enabled)
    playerListEnabled = enabled
end

lobbyCombiner.toggle_player_locations = function(enabled)
    playerListLocations = enabled
end

lobbyCombiner.toggle_location_popups = function(enabled)
    locationPopups = enabled
end

local custom_events = {}
custom_events.remote_player_changed_area = {}
custom_events.remote_allow_pvp_attack = {}
custom_events.remote_on_pvp_attack = {}

function handle_custom_event(event, ...)
    if custom_events[event] and #custom_events[event] ~= 0 then
        for i, func in ipairs(custom_events[event]) do
            local result = func(...)
            if result ~= nil then
                return result
            end
        end
    end
    return true
end

lobbyCombiner.hook_custom_event = function(event, func, priority)
    if custom_events[event] then
        local spot = (#custom_events + 1)
        if priority then spot = 1 end
        table.insert(custom_events[event], spot, func)
    end
end