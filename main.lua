-- name: Lobby Synchronizer [v0.1B]
-- description: Cursed nonsense that allows multiple lobbies to communicate with each other. Has science gone too far?\n\nMod by EmilyEmmi. Check inside main.lua for usage instructions.

--[[
ATTENTION!

This mod does not simply "make lobbies bigger." It will NOT let you play any game mode with more players out of the box.
Current features include:
- Seeing players from other lobbies (including palette, sounds, and location)
- Seeing chat messages from other lobbies

Planned features (as of now) include:
- Nametags for remote players
- Player interaction between lobbies
- Toggleable save file synchronization
- Page-based player list?
- API features to allow game modes to be made for this mod
- (Maybe) Character Select support

HOW TO USE:
- Make an additional copy (or junction, if you know how) of this mod for each additional lobby you would like to host
    - Also change TOTAL_LOBBY_COUNT below
    - Name each copy in numbered order, for example "lobby_combiner_1", "lobby_combiner_2", etc.
- Create multiple lobbies, each one containing a SEPERATE copy of this mod. 
    - Since they will all have the same name, use the order in the mod list to tell them apart. 
        - Alternatively, you can manually change the name field at the top for each copy.
    - Since these are all seperate lobbies, they can have different mods and server settings if you'd like, for whatever reason.
    - You can also mix and match Direct Connection, Private, and Public lobbies, as long as they are all on the same device.
]]

-- How many lobbies you want to host total.
TOTAL_LOBBY_COUNT = 2

-- Frames between each read/write to modFs. You may increase this if you, the host, are experiencing performance issues.
local FRAMES_TO_RELOAD = 1

didFirstJoinStuff = false
gGlobalSyncTable.lobbyID = 0

-- Order that data is stored in both modFs and in bytestring packets
local extraDataOrder = {
    "index",
    "connected",
    "posX",
    "posY",
    "posZ",
    "angleX",
    "angleY",
    "angleZ",
    "animID",
    "animYTrans",
    "animFrameAccelAssist",
    "animAccel",
    "charSound",
    "char",
    "level",
    "area",
    "act",
    "name",
    "msg",
}
-- Palette parts
for part = 0, PLAYER_PART_MAX - 1 do
    table.insert(extraDataOrder, "pal_" .. part .. "_r")
    table.insert(extraDataOrder, "pal_" .. part .. "_g")
    table.insert(extraDataOrder, "pal_" .. part .. "_b")
end

-- Type for each field (TODO: Can <l can be converted to <i4 to actually work properly across OSes?)
local extraDataByteType = {
    index = "<B", -- unsigned byte
    connected = "<B",
    posX = "<h", -- signed short (2^16, equivalent to s16)
    posY = "<h",
    posZ = "<h",
    angleX = "<h",
    angleY = "<h",
    angleZ = "<h",
    animID = "<h",
    animYTrans = "<h",
    animFrameAccelAssist = "<l", -- signed long (2^32, equivalent to s32)
    animAccel = "<l",
    charSound = "<h",
    char = "<B",
    level = "<h",
    area = "<h",
    act = "<h",
    name = "<z", -- zero-terminated string (arbituary length)
    msg = "<z",
}
-- Palette parts are all unsigned bytes, done automatically

-- Fields that are sent to the host from other players in the lobby
-- Other fields are auto-set by the host
local extraDataOrderLess = {
    "index",
    "posX",
    "posY",
    "posZ",
    "angleX",
    "angleY",
    "angleZ",
    "animID",
    "animYTrans",
    "animFrameAccelAssist",
    "animAccel",
    "char",
    "charSound",
}

function update()
    if not didFirstJoinStuff then return end

    if network_is_server() then
        if FRAMES_TO_RELOAD > 1 and get_global_timer() % FRAMES_TO_RELOAD ~= 0 then return end
        handle_lobby_connection()
    end
end

hook_event(HOOK_UPDATE, update)

function handle_lobby_connection()
    -- set up info for each player
    local fullByteString = ""
    local startIndex = MAX_PLAYERS * LOBBY_ID
    for i = startIndex, startIndex + MAX_PLAYERS - 1 do
        local a = extraMarioData[i]
        if a.wasConnected ~= 0 or a.connected ~= 0 then
            a.wasConnected = a.connected
            local bytestring = create_player_bytestring(a)
            bytestring = string.pack("<L", #bytestring) .. bytestring
            fullByteString = fullByteString .. bytestring
        end
    end

    -- Store in modfs
    local modFs = mod_fs_get() or mod_fs_create()
    if not modFs then return end
    local file = modFs:get_file("lobbyData") or
    modFs:create_file("lobbyData", false)
    modFs:set_public(true)
    file:set_public(true)
    file:rewind()
    file:erase(file.size)
    file:write_bytes(fullByteString)
    modFs:save()

    for i = 0, TOTAL_LOBBY_COUNT do
        if i ~= LOBBY_ID then
            local modName = "lobby_combiner_"..tostring(i+1)
            local modFs = mod_fs_reload(modName) or mod_fs_get(modName)

            if modFs then
                local file = modFs:get_file("lobbyData")
                if file then
                    file:rewind()
                    while not file:is_eof() do
                        local lengthString = file:read_bytes(4) -- a long is 4 bytes
                        local bytes = string.unpack("<L", lengthString)
                        if bytes == 0 then break end
                        local bytestring = file:read_bytes(bytes)
                        if bytestring and #bytestring ~= 0 then
                            local a = parse_player_bytestring(bytestring)
                            if a and a.connected ~= 0 then
                                -- Send to other players
                                network_send_bytestring(false, bytestring)
                                update_extra_player(a)
                            end
                        end
                    end
                end
            end
        end
    end
end

function on_sync_valid()
    if not didFirstJoinStuff then
        on_server_loaded()
        didFirstJoinStuff = true
    end

    local startIndex = MAX_PLAYERS * LOBBY_ID
    local endIndex = startIndex + MAX_PLAYERS - 1
    for i = 0, MAX_PLAYERS_TOTAL - 1 do
        if i < startIndex or i > endIndex then
            spawn_non_sync_object(id_bhvFakeMario, E_MODEL_NONE, 0, 0, 0, function(o)
                o.oBehParams = i
            end)
        end
    end
end

hook_event(HOOK_ON_SYNC_VALID, on_sync_valid)

local marioSoundTimer = 5
---@param m MarioState
function mario_update(m)
    if not didFirstJoinStuff then return end

    local np = gNetworkPlayers[m.playerIndex]
    local gIndex = network_global_index_from_local(m.playerIndex)
    local extraIndex = gIndex + MAX_PLAYERS * LOBBY_ID
    local a = extraMarioData[extraIndex]

    -- auto-set fields that the host will always know (network fields)
    if network_is_server() then
        local isHost = (gIndex == 0)
        local isConnected = (gServerSettings.headlessServer == 0 or (not isHost)) and (m.playerIndex == 0 or np.connected)
        a.connected = (isConnected and 1) or 0

        a.level = np.currLevelNum
        a.area = np.currAreaIndex
        a.act = np.currActNum
        a.name = network_get_player_text_color_string(m.playerIndex) .. np.name

        -- Palette parts
        for part = 0, PLAYER_PART_MAX - 1 do
            local color = network_player_get_override_palette_color(np, part)
            a["pal_" .. part .. "_r"] = color.r or 0
            a["pal_" .. part .. "_g"] = color.g or 0
            a["pal_" .. part .. "_b"] = color.b or 0
        end
    end

    if m.playerIndex ~= 0 then return end

    -- Set up extra mario data
    local mGFX = m.marioObj.header.gfx
    a.posX = math.floor(mGFX.pos.x)
    a.posY = math.floor(mGFX.pos.y)
    a.posZ = math.floor(mGFX.pos.z)
    a.angleX = mGFX.angle.x
    a.angleY = mGFX.angle.y
    a.angleZ = mGFX.angle.z

    local animInfo = mGFX.animInfo
    a.animID = animInfo.animID
    a.animYTrans = animInfo.animYTrans
    a.animFrameAccelAssist = animInfo.animFrameAccelAssist
    a.animAccel = animInfo.animAccel

    a.char = m.character.type or 0

    -- Clear character sound after a few frames
    if a.charSound ~= -1 then
        marioSoundTimer = marioSoundTimer - 1
        if marioSoundTimer == 0 then
            marioSoundTimer = 5
            a.charSound = -1
        end
    end

    if not network_is_server() then
        local bytestring = create_player_bytestring(a, true)
        network_send_bytestring_to(1, false, bytestring)
    end
end

hook_event(HOOK_MARIO_UPDATE, mario_update)

-- set last chat message
function on_chat_message(m, msg)
    if not didFirstJoinStuff then return end

    local extraIndex = network_global_index_from_local(m.playerIndex) + MAX_PLAYERS * LOBBY_ID
    local a = extraMarioData[extraIndex]
    if a then
        a.msg = msg
    end
end

hook_event(HOOK_ON_CHAT_MESSAGE, on_chat_message)

CHAR_SOUND_TABLE = {
    [CHAR_SOUND_YAH_WAH_HOO] = "soundYahWahHoo",
    [CHAR_SOUND_HOOHOO] = "soundHoohoo",
    [CHAR_SOUND_YAHOO] = "soundYahoo",
    [CHAR_SOUND_UH] = "soundUh",
    [CHAR_SOUND_HRMM] = "soundHrmm",
    [CHAR_SOUND_WAH2] = "soundWah2",
    [CHAR_SOUND_WHOA] = "soundWhoa",
    [CHAR_SOUND_EEUH] = "soundEeuh",
    [CHAR_SOUND_ATTACKED] = "soundAttacked",
    [CHAR_SOUND_OOOF] = "soundOoof",
    [CHAR_SOUND_OOOF2] = "soundOoof2",
    [CHAR_SOUND_HERE_WE_GO] = "soundHereWeGo",
    [CHAR_SOUND_YAWNING] = "soundYawning",
    [CHAR_SOUND_SNORING1] = "soundSnoring1",
    [CHAR_SOUND_SNORING2] = "soundSnoring2",
    [CHAR_SOUND_WAAAOOOW] = "soundWaaaooow",
    [CHAR_SOUND_HAHA] = "soundHaha",
    [CHAR_SOUND_HAHA_2] = "soundHaha_2",
    [CHAR_SOUND_UH2] = "soundUh2",
    [CHAR_SOUND_UH2_2] = "soundUh2_2",
    [CHAR_SOUND_ON_FIRE] = "soundOnFire",
    [CHAR_SOUND_DYING] = "soundDying",
    [CHAR_SOUND_PANTING_COLD] = "soundPantingCold",
    [CHAR_SOUND_PANTING] = "soundPanting",
    [CHAR_SOUND_COUGHING1] = "soundCoughing1",
    [CHAR_SOUND_COUGHING2] = "soundCoughing2",
    [CHAR_SOUND_COUGHING3] = "soundCoughing3",
    [CHAR_SOUND_PUNCH_YAH] = "soundPunchYah",
    [CHAR_SOUND_PUNCH_HOO] = "soundPunchHoo",
    [CHAR_SOUND_MAMA_MIA] = "soundMamaMia",
    [CHAR_SOUND_GROUND_POUND_WAH] = "soundGroundPoundWah",
    [CHAR_SOUND_DROWNING] = "soundDrowning",
    [CHAR_SOUND_PUNCH_WAH] = "soundPunchWah",
    [CHAR_SOUND_YAHOO_WAHA_YIPPEE] = "soundYahooWahaYippee",
    [CHAR_SOUND_DOH] = "soundDoh",
    [CHAR_SOUND_GAME_OVER] = "soundGameOver",
    [CHAR_SOUND_HELLO] = "soundHello",
    [CHAR_SOUND_PRESS_START_TO_PLAY] = "soundPressStartToPlay",
    [CHAR_SOUND_TWIRL_BOUNCE] = "soundTwirlBounce",
    [CHAR_SOUND_SNORING3] = "soundSnoring3",
    [CHAR_SOUND_SO_LONGA_BOWSER] = "soundSoLongaBowser",
    [CHAR_SOUND_IMA_TIRED] = "soundImaTired",
    [CHAR_SOUND_LETS_A_GO] = "soundLetsAGo",
    [CHAR_SOUND_OKEY_DOKEY] = "soundOkeyDokey",
}

-- set last played character sound
function on_character_sound(m, charSound)
    if (not didFirstJoinStuff) or m.playerIndex ~= 0 then return end

    local extraIndex = network_global_index_from_local(m.playerIndex) + MAX_PLAYERS * LOBBY_ID
    local a = extraMarioData[extraIndex]
    if a then
        a.charSound = charSound
    end
end

hook_event(HOOK_CHARACTER_SOUND, on_character_sound)

MODEL_TABLE = {
    [CT_MARIO] = E_MODEL_MARIO,
    [CT_LUIGI] = E_MODEL_LUIGI,
    [CT_TOAD] = E_MODEL_TOAD_PLAYER,
    [CT_WALUIGI] = E_MODEL_WALUIGI,
    [CT_WARIO] = E_MODEL_WARIO,
}

-- Fake mario objects
---@param o Object
function fake_mario_init(o)
    o.oFlags = o.oFlags | OBJ_FLAG_UPDATE_GFX_POS_AND_ANGLE
    o.oOpacity = 255
    o.globalPlayerIndex = highest_global_from_local()
    cur_obj_disable_rendering_and_become_intangible(o)
end

---@param o Object
function fake_mario_loop(o)
    o.globalPlayerIndex = highest_global_from_local()

    local a = extraMarioData[o.oBehParams]
    if not a then return end

    local np0 = gNetworkPlayers[0]
    if a.connected == 0 or (a.level ~= np0.currLevelNum or a.area ~= np0.currAreaIndex or a.act ~= np0.currActNum) then
        cur_obj_disable_rendering()
        return
    end

    obj_set_pos(o, a.posX, a.posY, a.posZ)
    obj_set_angle(o, a.angleX, a.angleY, a.angleZ)
    if MODEL_TABLE[a.char] then
        obj_set_model_extended(o, MODEL_TABLE[a.char])
    end

    cur_obj_enable_rendering()

    o.header.gfx.sharedChild.hookProcess = 0x34
    local animInfo = o.header.gfx.animInfo
    animInfo.curAnim = get_mario_vanilla_animation(a.animID)
    if animInfo.curAnim == 0 then
        animInfo.curAnim = get_mario_vanilla_animation(MARIO_ANIM_A_POSE)
    end
    animInfo.animYTrans = a.animYTrans
    animInfo.animFrameAccelAssist = a.animFrameAccelAssist
    animInfo.animAccel = a.animAccel
end

id_bhvFakeMario = hook_behavior(nil, OBJ_LIST_GENACTOR, true, fake_mario_init, fake_mario_loop, "bhvFakeMario")

-- Converts string into a table using a determiner (but stop splitting after a certain amount)
function split(s, delimiter, limit_)
    local limit = limit_ or 999
    local result = {}
    local finalmatch = ""
    local i = 0
    for match in (s):gmatch(string.format("[^%s]+", delimiter)) do
        --djui_chat_message_create(match)
        i = i + 1
        if i >= limit then
            finalmatch = finalmatch .. match .. delimiter
        else
            table.insert(result, match)
        end
    end
    if i >= limit then
        finalmatch = string.sub(finalmatch, 1, string.len(finalmatch) - string.len(delimiter))
        table.insert(result, finalmatch)
    end
    return result
end

function create_player_bytestring(a, lessFields)
    local bytestring = string.pack("<B", BYTE_PACKET_PLAYER_INFO) -- ID
    .. string.pack("<B", (lessFields and 1) or 0) -- less fields flag
    
    local fieldTable = extraDataOrder
    if lessFields then
        fieldTable = extraDataOrderLess
    end
    for j, dataName in ipairs(fieldTable) do
        local value = a[dataName]
        local byteType = extraDataByteType[dataName] or "<B"
        local packedStr = ""
        if byteType ~= "<l" then
            packedStr = string.pack(byteType, value)
        else
            -- due to OS jank, use string for longs
            packedStr = string.pack("<z", tostring(value))
        end
        bytestring = bytestring .. packedStr
    end

    return bytestring
end

function parse_player_bytestring(bytestring)
    local offset = 1

    local function unpack(fmt)
        local value
        value, offset = string.unpack(fmt, bytestring, offset)
        return value
    end

    local packet_id  = unpack("<B") -- needed to offset
    local lessFields = unpack("<B") -- flag

    local fieldTable = extraDataOrder
    if lessFields ~= 0 then
        fieldTable = extraDataOrderLess
    end

    local extraIndex = -1
    local a
    for j, dataName in ipairs(fieldTable) do
        local byteType = extraDataByteType[dataName] or "<B"
        local value
        if byteType ~= "<l" then
            value = unpack(byteType)
        else
            -- due to OS jank, use string for longs
            value = unpack("<z")
            value = tonumber(value) or 0
        end
        if extraIndex ~= -1 and DEBUG_PACKET_INFO == extraIndex then
            djui_chat_message_create(tostring(extraIndex)..";"..tostring(dataName)..": "..tostring(value))
        end

        if dataName == "index" then
            extraIndex = value
            if not extraIndex then break end
            a = extraMarioData[extraIndex]
        elseif a and value ~= nil and type(a[dataName]) == type(value) then
            a[dataName] = value
        end
    end
    if DEBUG_PACKET_INFO == extraIndex then
        DEBUG_PACKET_INFO = -1
    end
    return a
end

function update_extra_player(a)
    if a == nil or a.isLocal then return end

    if a.msg and a.prevMsg ~= a.msg then
        a.prevMsg = a.msg
        djui_chat_message_create(a.name .. "\\#dcdcdc\\: " .. a.msg)
        play_sound(SOUND_MENU_MESSAGE_APPEAR, gGlobalSoundSource)
    end
    if a.charSound and a.prevSound ~= a.charSound then
        a.prevSound = a.charSound
        if a.charSound ~= -1 then
            -- Find associated fake mario
            local o = obj_get_first_with_behavior_id_and_field_s32(id_bhvFakeMario, 0x40, a.index)
            if o and o.header.gfx.node.flags & GRAPH_RENDER_ACTIVE ~= 0 then
                local pos = o.header.gfx.cameraToObject
                local character = gCharacters[a.char or 0] or gCharacters[0]
                local soundName = CHAR_SOUND_TABLE[a.charSound]
                if type(soundName) == "string" then
                    local sound = character[soundName]
                    if sound then
                        play_sound_with_freq_scale(sound, pos, character.soundFreqScale);
                    end
                end
            end
        end
    end
end

function on_byte_packet_player_info(bytestring, self)
    if not didFirstJoinStuff then return end
    
    local a = parse_player_bytestring(bytestring)
    update_extra_player(a)
end

BYTE_PACKET_PLAYER_INFO = 0
sBytePacketTable = {
    [BYTE_PACKET_PLAYER_INFO] = on_byte_packet_player_info
}

function on_packet_bytestring_receive(bytestring)
    local packet_id = string.unpack("<B", bytestring, 1)
    if sBytePacketTable[packet_id] ~= nil then
        sBytePacketTable[packet_id](bytestring, false)
    end
end

hook_event(HOOK_ON_PACKET_BYTESTRING_RECEIVE, on_packet_bytestring_receive)

-- Switch palette for mario
local prevColors = {}
local prevBodyState = {
    capState = 0,
    eyeState = 0,
    handState = 0,
    punchState = 0,
    modelState = 0,
    allowPartRotation = 0,
    grabPos = 0,
    wingFlutter = 0,
    action = 0,
    headAngle = gVec3sZero(),
    torsoAngle = gVec3sZero(),
    headPos = gVec3fZero(),
    torsoPos = gVec3fZero(),
    heldObjLastPosition = gVec3fZero(),
}
hook_event(HOOK_BEFORE_GEO_PROCESS, function(node, matStackIndex)
    if (node.hookProcess ~= 0x34) then return end

    local o = geo_get_current_object()
    if o == nil or obj_has_behavior_id(o, id_bhvFakeMario) == 0 then return end

    local index = network_local_index_from_global(o.globalPlayerIndex)
    local np = gNetworkPlayers[index]
    local m = gMarioStates[index]
    transfer_body_state(prevBodyState, m.marioBodyState)

    m.marioBodyState.punchState = 0
    m.marioBodyState.handState = MARIO_HAND_FISTS
    m.marioBodyState.eyeState = MARIO_EYES_OPEN
    m.marioBodyState.modelState = MODEL_STATE_NOISE_ALPHA
    m.marioBodyState.capState = MARIO_HAS_DEFAULT_CAP_ON
    m.marioBodyState.action = ACT_IDLE
    vec3s_zero(m.marioBodyState.headAngle)
    vec3s_zero(m.marioBodyState.torsoAngle)

    -- Store palette and replace with new one
    local a = extraMarioData[o.oBehParams]
    if not a then return end
    for part = 0, PLAYER_PART_MAX - 1 do
        prevColors[part] = network_player_get_override_palette_color(np, part)
        local color = { r = 0, g = 0, b = 0 }
        color.r = a["pal_" .. part .. "_r"] or 0
        color.g = a["pal_" .. part .. "_g"] or 0
        color.b = a["pal_" .. part .. "_b"] or 0
        network_player_set_override_palette_color(np, part, color)
    end
end)

hook_event(HOOK_ON_GEO_PROCESS, function(node, matStackIndex)
    if node.hookProcess ~= 0x34 then return end

    local o = geo_get_current_object()
    if obj_has_behavior_id(o, id_bhvFakeMario) == 0 then return end

    local index = network_local_index_from_global(o.globalPlayerIndex)
    local np = gNetworkPlayers[index]
    local m = gMarioStates[index]
    transfer_body_state(m.marioBodyState, prevBodyState)

    -- Reload stored palette and torso pos
    for part = 0, PLAYER_PART_MAX - 1 do
        local color = prevColors[part]
        if color then
            network_player_set_override_palette_color(np, part, color)
            prevColors[part] = nil
        end
    end
end)

function transfer_body_state(to, from)
    to.capState = from.capState
    to.eyeState = from.eyeState
    to.handState = from.handState
    to.punchState = from.punchState
    to.modelState = from.modelState
    to.allowPartRotation = from.allowPartRotation
    to.grabPos = from.grabPos
    to.wingFlutter = from.wingFlutter
    to.action = from.action
    vec3s_copy(to.headAngle, from.headAngle)
    vec3s_copy(to.torsoAngle, from.torsoAngle)
    vec3f_copy(to.headPos, from.headPos)
    vec3f_copy(to.torsoPos, from.torsoPos)
    vec3f_copy(to.heldObjLastPosition, from.heldObjLastPosition)
end

function highest_global_from_local()
    for i = MAX_PLAYERS - 1, 1, -1 do
        local np = gNetworkPlayers[i]
        if np and np.connected then
            return np.globalIndex
        end
    end
    return network_global_index_from_local(0)
end

function on_server_loaded()
    if network_is_server() then
        mod_fs_hide_errors(true)
        
        -- Check folder name for lobby num
        LOBBY_ID = 0
        for i=0,#gActiveMods do
            local mod = gActiveMods[i]
            local modNameOnlyNum = mod.relativePath:gsub("lobby_combiner_", "")
            if tonumber(modNameOnlyNum) then
                LOBBY_ID = tonumber(modNameOnlyNum) - 1
                break
            end
        end
        log_to_console("Lobby ID: " .. tostring(LOBBY_ID))
        print("Lobby ID: " .. tostring(LOBBY_ID))

        -- erase existing modFs
        local modFs = mod_fs_get()
        if modFs then
            modFs:clear()
            modFs:save()
        end

        gGlobalSyncTable.lobbyID = LOBBY_ID
    else
        LOBBY_ID = gGlobalSyncTable.lobbyID or 0
    end

    -- Set up table with additional information
    extraMarioData = {}
    MAX_PLAYERS_TOTAL = MAX_PLAYERS * TOTAL_LOBBY_COUNT
    local startIndex = MAX_PLAYERS * LOBBY_ID
    local endIndex = startIndex + MAX_PLAYERS - 1
    for i = 0, MAX_PLAYERS_TOTAL - 1 do
        extraMarioData[i] = {}
        local a = extraMarioData[i]
        a.index = i
        a.posX = 0
        a.posY = 0
        a.posZ = 0
        a.angleX = 0
        a.angleY = 0
        a.angleZ = 0
        a.animID = 0
        a.animYTrans = 0
        a.animFrameAccelAssist = 0
        a.animAccel = 0
        a.charSound = -1
        a.char = 0
        a.connected = 0
        a.level = 0
        a.area = 0
        a.act = 0
        a.name = " "
        a.msg = " "

        -- Palette parts
        for part = 0, PLAYER_PART_MAX - 1 do
            a["pal_" .. part .. "_r"] = 0
            a["pal_" .. part .. "_g"] = 0
            a["pal_" .. part .. "_b"] = 0
        end

        -- Non-sync fields
        a.prevMsg = " "
        a.prevSound = -1
        a.wasConnected = 1
        a.isLocal = (i >= startIndex and i <= endIndex)
        if a.isLocal then
            a.globalIndex = i - startIndex
            a.localIndex = network_local_index_from_global(a.globalIndex)
        else
            a.globalIndex = -1
            a.localIndex = -1
        end
    end
end

DEBUG_PACKET_INFO = -1
if network_is_server() then
    hook_chat_command("debug_packet", "[ID] - Get debug info for next player packet", function(msg)
        DEBUG_PACKET_INFO = tonumber(msg) or 0
        return true
    end)
end