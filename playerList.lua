-- Custom player list

playerListEnabled = true
playerListLocations = true
expandByDefault = false

function on_hud_render()
    if not didFirstJoinStuff then return end

    gServerSettings.enablePlayerList = 0
    if djui_attempting_to_open_playerlist() and playerListEnabled then
        -- base square
        local bodyHeight = (16 * 32) + (16 - 1) * 4;
        djui_hud_set_resolution(RESOLUTION_DJUI)
        djui_hud_set_font(FONT_MENU)
        local DjuiTheme = djui_menu_get_theme()
        local color1 = DjuiTheme.threePanels.borderColor
        local color2 = DjuiTheme.threePanels.rectColor
        djui_hud_set_color(color1.r, color1.g, color1.b, color1.a)
        local screenWidth = djui_hud_get_screen_width()
        local screenHeight = djui_hud_get_screen_height()
        local width = 710
        local height = bodyHeight + (32 + 16) + 32 + 32
        local borderWidth = 8
        local x = (screenWidth - width) / 2
        local y = (screenHeight - height) / 2
        djui_hud_render_rect(x, y, borderWidth, height)
        djui_hud_render_rect(x+borderWidth, y, width-borderWidth*2, borderWidth)
        djui_hud_render_rect(x+width-borderWidth, y, borderWidth, height)
        djui_hud_render_rect(x+borderWidth, y+height-borderWidth, width-borderWidth*2, borderWidth)
        djui_hud_set_color(color2.r, color2.g, color2.b, color2.a)
        width = width - borderWidth * 2
        height = height - borderWidth * 2
        x = (screenWidth - width) / 2
        y = (screenHeight - height) / 2
        djui_hud_render_rect(x, y, width, height)

        -- title
        local text = djui_language_get("PLAYER_LIST", "PLAYERS")
        local tWidth = djui_hud_measure_text(text)
        djui_hud_print_text_rainbow(text, x + (width - tWidth) / 2, y + 6, 1, 255, DjuiTheme.panels.hudFontHeader)

        -- players
        djui_hud_set_font(djui_menu_get_font())
        width = width - 32
        local totalColumns = TOTAL_LOBBY_COUNT
        if not expandByDefault then
            local playerCount = 0
            for i=0,MAX_PLAYERS_TOTAL-1 do
                local a = extraMarioData[i]
                local connected = false
                if a.isLocal then
                    ---@type NetworkPlayer
                    local np = gNetworkPlayers[a.localIndex]
                    local gIndex = network_global_index_from_local(a.localIndex)
                    local isHost = (gIndex == 0)
                    connected = (gServerSettings.headlessServer == 0 or (not isHost)) and (a.localIndex == 0 or np.connected)
                else
                    connected = (a.connected ~= 0)
                end
                if connected then
                    playerCount = playerCount + 1
                end
            end
            totalColumns = math.clamp((playerCount - 1) // MAX_PLAYERS + 1, 1, totalColumns)
        end

        local panelHDist = 8
        local panelWidth = width / totalColumns - panelHDist / 2
        height = 32
        y = y + 80
        
        local renderCount = 0

        local startIndex = MAX_PLAYERS * LOBBY_ID -- always start with host
        for i=0,MAX_PLAYERS_TOTAL-1 do
            local a = extraMarioData[(i + startIndex) % MAX_PLAYERS_TOTAL]
            local connected = false
            local name = ""
            local course, level, area, act = 0, 0, 0, 0
            local char = 0
            local isFake = false
            if a.isLocal then
                ---@type NetworkPlayer
                local np = gNetworkPlayers[a.localIndex]
                local gIndex = network_global_index_from_local(a.localIndex)
                local isHost = (gIndex == 0)
                name = network_get_player_text_color_string(a.localIndex) .. np.name
                course, level, area, act = np.currCourseNum, np.currLevelNum, np.currAreaIndex, np.currActNum
                connected = (gServerSettings.headlessServer == 0 or (not isHost)) and (a.localIndex == 0 or np.connected)
                char = gMarioStates[a.localIndex].character.type
            else
                name = a.name or "???"
                level, area, act = a.level, a.area, a.act
                course = get_level_course_num(level)
                connected = (a.connected ~= 0)
                char = a.char or 0
                isFake = true
            end
            if connected then
                local row = renderCount // totalColumns
                local column = renderCount % totalColumns
                local startX = (screenWidth - width) / 2 + (column * (panelWidth + panelHDist))
                x = startX
                local v = 32
                if (row % 2) ~= (column % 2) then
                    -- checkerboard pattern
                    v = v - 16
                end
                djui_hud_set_color(v, v, v, 128)
                djui_hud_render_rect(x, y, panelWidth, height)

                -- head
                if isFake then
                    djui_hud_set_color(255, 255, 255, 100)
                else
                    djui_hud_set_color(255, 255, 255, 255)
                end
                local character = gCharacters[char or 0] or gCharacters[0]
                local tex = character.hudHeadTexture
                djui_hud_render_texture(tex, x, y, 2, 2)

                local maxPlayerWidth = panelWidth
                if playerListLocations then
                    maxPlayerWidth = maxPlayerWidth / 2
                end
                djui_hud_set_color(255, 255, 255, 255)
                x = x + 40
                text = name
                while djui_hud_measure_text(remove_color(text)) > maxPlayerWidth - 24 do
                    text = text:sub(1, -2)
                end
                djui_hud_print_text_with_color(text, x, y, 1)

                -- description
                --[[text = np.description
                tWidth = djui_hud_measure_text(text)
                x = (screenWidth + width) / 2 - tWidth - 16
                djui_hud_set_color(np.descriptionR, np.descriptionG, np.descriptionB, np.descriptionA)
                djui_hud_print_text_with_color(text, x, y, 1)]]

                -- level
                if playerListLocations then
                    text = get_level_name(course, level, area)
                    text = convert_to_abbreviation(text)
                    if act == 99 then
                        text = text .. " " -- Star character
                    elseif act ~= 0 then
                        text = text .. " #" .. act
                    end
                    tWidth = djui_hud_measure_text(text)
                    x = startX + panelWidth - tWidth - 16
                    djui_hud_set_color(255, 255, 255, 255)
                    djui_hud_print_text_with_color(text, x, y, 1)
                end
                
                renderCount = renderCount + 1
                if renderCount % totalColumns == 0 then
                    y = y + 36
                end
            end
        end

        -- mods list base square
        local activeModNum = #gActiveMods + 1
        bodyHeight = (activeModNum * 32) + (activeModNum - 1) * 4;
        djui_hud_set_resolution(RESOLUTION_DJUI)
        djui_hud_set_font(FONT_MENU)
        djui_hud_set_color(color1.r, color1.g, color1.b, color1.a)
        width = 280
        height = bodyHeight + (32 + 16) + 32 + 32
        x = (screenWidth + 710) / 2 + 8
        y = (screenHeight - height) / 2
        djui_hud_render_rect(x, y, borderWidth, height)
        djui_hud_render_rect(x+borderWidth, y, width-borderWidth*2, borderWidth)
        djui_hud_render_rect(x+width-borderWidth, y, borderWidth, height)
        djui_hud_render_rect(x+borderWidth, y+height-borderWidth, width-borderWidth*2, borderWidth)
        djui_hud_set_color(color2.r, color2.g, color2.b, color2.a)
        width = width - 16
        height = height - 16
        x = x + 8
        y = (screenHeight - height) / 2
        djui_hud_render_rect(x, y, width, height)

        -- mods list title
        text = djui_language_get("PLAYER_LIST", "MODS")
        tWidth = djui_hud_measure_text(text)
        djui_hud_print_text_rainbow(text, x + (width - tWidth) / 2, y + 6, 1, 255, DjuiTheme.panels.hudFontHeader)

        -- mods list mods
        djui_hud_set_font(djui_menu_get_font())
        width = width - 32
        height = 32
        y = y + 80
        for i=0,activeModNum-1 do
            local mod = gActiveMods[i]
            x = (screenWidth + 710) / 2 + 32
            local v = 32 - (i % 2) * 16
            djui_hud_set_color(v, v, v, 128)
            djui_hud_render_rect(x, y, width, height)
            djui_hud_set_color(220, 220, 220, 255)
            text = mod.name
            while djui_hud_measure_text(remove_color(text)) > width do
                text = text:sub(1, -2)
            end
            djui_hud_print_text_with_color(text, x, y, 1)
            y = y + 36
        end
    end
end

-- print text in red, green, blue, yellow for each character
local sRainbowColors = {
    {0xff, 0x30, 0x30},
    {0x40, 0xe7, 0x40},
    {0x40, 0xb0, 0xff},
    {0xff, 0xef, 0x40},
}
function djui_hud_print_text_rainbow(text, x, y, scale, alpha_, hudFont)
    if not text then return end
    if hudFont then
        djui_hud_set_font(FONT_HUD)
        djui_hud_set_color(255, 255, 255, 255)
        djui_hud_print_text(text, x+8*scale, y+16*scale, scale*2.8)
        return
    end
    local alpha = alpha_ or 255
    for i = 1, text:len() do
        local char = text:sub(i,i)
        local width = djui_hud_measure_text(char) * scale
        local color = sRainbowColors[(i-1) % 4+1]
        djui_hud_set_color(color[1], color[2], color[3], alpha)
        djui_hud_print_text(char, x, y, scale)
        x = x + width
    end
end

-- prints text on the screen... with color!
function djui_hud_print_text_with_color(text, x, y, scale, alpha)
    --djui_hud_set_color(255, 255, 255, alpha or 255)
    local space = 0
    local color = ""
    local render = ""
    local r, g, b, a = 255, 255, 255, 255
    text, color, render = remove_color(text, true)
    while render do
        djui_hud_print_text(render, x + space, y, scale);
        space = space + djui_hud_measure_text(render) * scale
        r, g, b, a = convert_color(color)
        if r then djui_hud_set_color(r, g, b, alpha or a) end
        text, color, render = remove_color(text, true)
    end
    djui_hud_print_text(text, x + space, y, scale);
end

-- removes color string
function remove_color(text, get_color)
    local start = text:find("\\")
    local next = 1
    while (next ~= nil) and (start ~= nil) do
        start = text:find("\\")
        if start ~= nil then
            next = text:find("\\", start + 1)
            if next == nil then
                next = text:len() + 1
            end

            if get_color then
                local color = text:sub(start, next)
                local render = text:sub(1, start - 1)
                text = text:sub(next + 1)
                return text, color, render
            else
                text = text:sub(1, start - 1) .. text:sub(next + 1)
            end
        end
    end
    return text
end

-- converts hex string to RGB values
function convert_color(text)
    if text:sub(2, 2) ~= "#" then
      return nil
    end
    text = text:sub(3, -2)
    local rstring, gstring, bstring = "", "", ""
    if text:len() ~= 3 and text:len() ~= 6 then return 255, 255, 255, 255 end
    if text:len() == 6 then
      rstring = text:sub(1, 2) or "ff"
      gstring = text:sub(3, 4) or "ff"
      bstring = text:sub(5, 6) or "ff"
    else
      rstring = text:sub(1, 1) .. text:sub(1, 1)
      gstring = text:sub(2, 2) .. text:sub(2, 2)
      bstring = text:sub(3, 3) .. text:sub(3, 3)
    end
    local r = tonumber("0x" .. rstring) or 255
    local g = tonumber("0x" .. gstring) or 255
    local b = tonumber("0x" .. bstring) or 255
    return r, g, b, 255 -- alpha is no longer writeable
end

-- converts text to sm64 style abbreviation (ex: Bowser In The Sky becomes BitS)
function convert_to_abbreviation(text)
    local ab = ""
    local start, send = string.find(text, "%a+")
    while start ~= nil do
        local word = text:sub(start, send):upper()
        if word ~= "OF" and word ~= "THE" and word ~= "IN" and word ~= "S" and word ~= "OVER" and word ~= "OMB" then
            ab = ab .. word:sub(1, 1)
        elseif ab ~= "" and word ~= "S" then
            ab = ab .. word:sub(1, 1):lower()
        end
        start, send = string.find(text, "%a+", send + 1)
    end
    return ab
end

-- do hook last
function on_mods_loaded()
    hook_event(HOOK_ON_HUD_RENDER, on_hud_render)
end
hook_event(HOOK_ON_MODS_LOADED , on_mods_loaded)