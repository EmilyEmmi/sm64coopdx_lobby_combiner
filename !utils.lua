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
    "char",
    "charSound",
    "flags",
    "action",
    "actionArg",
    "actionState",
    "health",
    "invincTimer",
    "hurtCounter",
    "velX",
    "velY",
    "velZ",
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
    "flags",
    "action",
    "actionArg",
    "actionState",
    "health",
    "invincTimer",
    "hurtCounter",
    "velX",
    "velY",
    "velZ",
}

-- Type for each field (TODO: Test if <i4 works across OSes)
local extraDataByteType = {
    index = "<B", -- unsigned byte, equivalent to u8
    connected = "<B",
    posX = "<h", -- signed short (2^16, equivalent to s16)
    posY = "<h",
    posZ = "<h",
    angleX = "<h",
    angleY = "<h",
    angleZ = "<h",
    animID = "<h",
    animYTrans = "<h",
    animFrameAccelAssist = "<i4", -- signed long (2^32, equivalent to s32)
    animAccel = "<i4",
    charSound = "<h",
    char = "<B",
    level = "<h",
    area = "<h",
    act = "<h",
    flags = "<I4", -- u32
    action = "<I4",
    actionArg = "<I4",
    actionState = "<H", -- u16
    health = "<h",
    invincTimer = "<h",
    hurtCounter = "<B",
    velX = "<h",
    velY = "<h",
    velZ = "<h",
    name = "<z", -- zero-terminated string (arbituary length)
    msg = "<z",
}
-- Palette parts are all unsigned bytes, done automatically

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
        local packedStr = string.pack(byteType, value)
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
        local value = unpack(byteType)
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

function transfer_mario_state(to, from)
    if type(to) == "table" then
        to.playerIndex = from.playerIndex
        to.dialogId = from.dialogId
        to.marioObj = from.marioObj
        to.controller = {}
        to.marioBodyState = {}
        to.statusForCamera = {}
        to.pos = to.pos or gVec3fZero()
        to.nonInstantWarpPos = to.nonInstantWarpPos or gVec3fZero()
        to.vel = to.vel or gVec3fZero()
        to.faceAngle = to.faceAngle or gVec3sZero()
        to.angleVel = to.angleVel or gVec3sZero()
        to.wallNormal = to.wallNormal or gVec3fZero()
    end

    to.input = from.input
    to.numCoins = from.numCoins
    to.numStars = from.numStars
    to.numLives = from.numLives
    to.numKeys = from.numKeys
    to.health = from.health
    to.hurtCounter = from.hurtCounter
    to.healCounter = from.healCounter
    to.isSnoring = from.isSnoring
    to.freeze = from.freeze
    to.cap = from.cap
    to.capTimer = from.capTimer
    to.invincTimer = from.invincTimer
    to.skipWarpInteractionsTimer = from.skipWarpInteractionsTimer
    to.squishTimer = from.squishTimer
    to.bounceSquishTimer = from.bounceSquishTimer
    to.knockbackTimer = from.knockbackTimer
    to.wallKickTimer = from.wallKickTimer
    to.doubleJumpTimer = from.doubleJumpTimer
    to.specialTripleJump = from.specialTripleJump
    to.fadeWarpOpacity = from.fadeWarpOpacity
    to.wasNetworkVisible = from.wasNetworkVisible
    to.prevNumStarsForDialog = from.prevNumStarsForDialog
    to.unkB0 = from.unkB0
    to.action = from.action
    to.prevAction = from.prevAction
    to.actionArg = from.actionArg
    to.actionTimer = from.actionTimer
    to.actionState = from.actionState
    to.flags = from.flags
    to.quicksandDepth = from.quicksandDepth
    transfer_controller(to.controller, from.controller)
    transfer_body_state(to.marioBodyState, from.marioBodyState)
    to.character = from.character
    to.terrainSoundAddend = from.terrainSoundAddend
    vec3f_copy(to.pos, from.pos)
    vec3f_copy(to.nonInstantWarpPos, from.nonInstantWarpPos)
    vec3f_copy(to.vel, from.vel)
    to.slideVelX = from.slideVelX
    to.slideVelZ = from.slideVelZ
    to.forwardVel = from.forwardVel
    to.peakHeight = from.peakHeight
    to.intendedMag = from.intendedMag
    to.intendedYaw = from.intendedYaw
    to.framesSinceA = from.framesSinceA
    to.framesSinceB = from.framesSinceB
    vec3s_copy(to.faceAngle, from.faceAngle)
    vec3s_copy(to.angleVel, from.angleVel)
    to.slideYaw = from.slideYaw
    to.twirlYaw = from.twirlYaw
    to.heldObj = from.heldObj
    to.heldByObj = from.heldByObj
    to.interactObj = from.interactObj
    to.riddenObj = from.riddenObj
    to.usedObj = from.usedObj
    to.bubbleObj = from.bubbleObj
    to.collidedObjInteractTypes = from.collidedObjInteractTypes
    to.particleFlags = from.particleFlags
    to.animation = from.animation
    to.splineKeyframe = from.splineKeyframe
    to.splineKeyframeFraction = from.splineKeyframeFraction
    to.splineState = from.splineState
    to.curAnimOffset = from.curAnimOffset
    to.minimumBoneY = from.minimumBoneY
    to.wall = from.wall
    to.ceil = from.ceil
    to.floor = from.floor
    to.spawnInfo = from.spawnInfo
    -- to.area = from.area -- read-only, but we don't really need it
    transfer_player_camera_state(to.statusForCamera, from.statusForCamera)
    to.ceilHeight = from.ceilHeight
    to.floorHeight = from.floorHeight
    vec3f_copy(to.wallNormal, from.wallNormal)
    to.unkC4 = from.unkC4
    to.floorAngle = from.floorAngle
    to.waterLevel = from.waterLevel
    to.currentRoom = from.currentRoom
end

function transfer_body_state(to, from)
    if from == nil then from = {} end
    if type(to) == "table" then
        to.headAngle = to.headAngle or gVec3sZero()
        to.torsoAngle = to.torsoAngle or gVec3sZero()
        to.headPos = to.headPos or gVec3fZero()
        to.torsoPos = to.torsoPos or gVec3fZero()
        to.heldObjLastPosition = to.heldObjLastPosition or gVec3fZero()
    end

    to.capState = from.capState or 0
    to.eyeState = from.eyeState or 0
    to.handState = from.handState or 0
    to.punchState = from.punchState or 0
    to.modelState = from.modelState or 0
    to.allowPartRotation = from.allowPartRotation or 0
    to.grabPos = from.grabPos or 0
    to.wingFlutter = from.wingFlutter or 0
    to.action = from.action or 0
    to.mirrorMario = from.mirrorMario or false
    to.shadeR = from.shadeR or 0
    to.shadeG = from.shadeG or 0
    to.shadeB = from.shadeB or 0
    to.lightR = from.lightR or 0
    to.lightG = from.lightG or 0
    to.lightB = from.lightB or 0
    to.lightingDirX = from.lightingDirX or 0
    to.lightingDirY = from.lightingDirY or 0
    to.lightingDirZ = from.lightingDirZ or 0
    vec3s_copy(to.headAngle, from.headAngle)
    vec3s_copy(to.torsoAngle, from.torsoAngle)
    vec3f_copy(to.headPos, from.headPos)
    vec3f_copy(to.torsoPos, from.torsoPos)
    vec3f_copy(to.heldObjLastPosition, from.heldObjLastPosition)
end

function transfer_controller(to, from)
    if from == nil then from = {} end
    to.port = from.port or 0
    to.stickX = from.stickX or 0
    to.stickY = from.stickY or 0
    to.stickMag = from.stickMag or 0
    to.rawStickX = from.rawStickX or 0
    to.rawStickY = from.rawStickY or 0
    to.extStickX = from.extStickX or 0
    to.extStickY = from.extStickY or 0
    to.buttonDown = from.buttonDown or 0
    to.buttonPressed = from.buttonPressed or 0
    to.buttonReleased = from.buttonReleased or 0
end

function transfer_player_camera_state(to, from)
    if from == nil then from = {} end
    if type(to) == "table" then
        to.pos = to.pos or gVec3fZero()
        to.faceAngle = to.faceAngle or gVec3sZero()
        to.headRotation = to.headRotation or gVec3sZero()
    end
    
    to.action = from.action or 0
    vec3f_copy(to.pos, from.pos)
    vec3s_copy(to.faceAngle, from.faceAngle)
    vec3s_copy(to.headRotation, from.headRotation)
    to.unused = from.unused or 0
    to.cameraEvent = from.cameraEvent or 0
    to.usedObj = from.usedObj
end

function copy_mario_state_to_object(m, o)
    o.oVelX = m.vel.x
    o.oVelY = m.vel.y
    o.oVelZ = m.vel.z

    o.oPosX = m.pos.x
    o.oPosY = m.pos.y
    o.oPosZ = m.pos.z

    o.oMoveAnglePitch = o.header.gfx.angle.x
    o.oMoveAngleYaw = o.header.gfx.angle.y
    o.oMoveAngleRoll = o.header.gfx.angle.z

    o.oFaceAnglePitch = o.header.gfx.angle.x
    o.oFaceAngleYaw = o.header.gfx.angle.y;
    o.oFaceAngleRoll = o.header.gfx.angle.z

    o.oAngleVelPitch = m.angleVel.x
    o.oAngleVelYaw = m.angleVel.y
    o.oAngleVelRoll = m.angleVel.z
end

-- Lua recreation of execute_mario_action that works a bit differently
function custom_execute_mario_action(m, level, area, act)
    local gMarioState = m
    local gNetworkPlayerLocal = gNetworkPlayers[0]

    local inLoop = 1
    if not gMarioState then return 0 end
    if not gMarioState.marioObj then return 0 end
    if gMarioState.playerIndex >= MAX_PLAYERS then return 0 end

    if gMarioState.knockbackTimer > 0 then
        gMarioState.knockbackTimer = gMarioState.knockbackTimer - 1
    elseif gMarioState.knockbackTimer < 0 then
        gMarioState.knockbackTimer = gMarioState.knockbackTimer + 1
    end

    -- hide inactive players
    if gMarioState.playerIndex ~= 0 then
        local levelAreaMismatch = (gNetworkPlayerLocal == nil)
            or (act ~= gNetworkPlayerLocal.currActNum)
            or (level ~= gNetworkPlayerLocal.currLevelNum)
            or (area ~= gNetworkPlayerLocal.currAreaIndex)

        if levelAreaMismatch then
            gMarioState.marioObj.header.gfx.node.flags = gMarioState.marioObj.header.gfx.node.flags | GRAPH_RENDER_INVISIBLE
            gMarioState.marioObj.oIntangibleTimer = -1
            mario_stop_riding_and_holding(gMarioState)

            -- drop their held object
            if gMarioState.heldObj ~= nil then
                --LOG_INFO("dropping held object")
                local tmpPlayerIndex = gMarioState.playerIndex
                gMarioState.playerIndex = 0
                mario_drop_held_object(gMarioState)
                gMarioState.playerIndex = tmpPlayerIndex
            end

            -- no longer held by an object
            if gMarioState.heldByObj ~= nil then
                --LOG_INFO("dropping heldby object")
                gMarioState.heldByObj = nil
            end

            -- no longer riding object
            if gMarioState.riddenObj ~= nil then
                --LOG_INFO("dropping ridden object")
                local tmpPlayerIndex = gMarioState.playerIndex
                gMarioState.playerIndex = 0
                mario_stop_riding_object(gMarioState)
                gMarioState.playerIndex = tmpPlayerIndex
            end

            return 0
        end

        --[[if levelAreaMismatch and gMarioState.wasNetworkVisible then
            if np.fadeOpacity <= 2 then
                np.fadeOpacity = 0
            else
                np.fadeOpacity = np.fadeOpacity - 2
            end
            gMarioState.fadeWarpOpacity = np.fadeOpacity << 3
        elseif np.fadeOpacity < 32 then
            np.fadeOpacity = np.fadeOpacity + 2
            gMarioState.fadeWarpOpacity = np.fadeOpacity << 3
        end]]
    end

    if gMarioState.action ~= 0 then
        if gMarioState.action ~= ACT_BUBBLED then
            gMarioState.marioObj.header.gfx.node.flags = gMarioState.marioObj.header.gfx.node.flags & ~GRAPH_RENDER_INVISIBLE
        end
        --[[mario_reset_bodystate(gMarioState)
        update_mario_inputs(gMarioState)
        mario_handle_special_floors(gMarioState)
        mario_process_interactions(gMarioState)]]

        -- HACK: mute snoring even when we skip the waking up action
        if gMarioState.isSnoring and gMarioState.action ~= ACT_SLEEPING then
            stop_sound(get_character(gMarioState).soundSnoring1, gMarioState.marioObj.header.gfx.cameraToObject)
            stop_sound(get_character(gMarioState).soundSnoring2, gMarioState.marioObj.header.gfx.cameraToObject)
            stop_sound(get_character(gMarioState).soundSnoring3, gMarioState.marioObj.header.gfx.cameraToObject)
            gMarioState.isSnoring = false
        end

        -- If Mario is OOB, stop executing actions.
        if gMarioState.floor == nil and gMarioState.action ~= ACT_DEBUG_FREE_MOVE then
            return 0
        end

        -- don't update mario when in a cutscene
        if gMarioState.playerIndex == 0 then
            local gDialogID = get_dialog_id()
            if gMarioState.freeze > 0 then gMarioState.freeze = gMarioState.freeze - 1 end
            if gMarioState.freeze < 2 and gDialogID ~= DIALOG_NONE then gMarioState.freeze = 2 end
            if gMarioState.freeze < 2 and is_game_paused() then gMarioState.freeze = 2 end
        end

        -- drop held object if someone else is holding it
        if gMarioState.playerIndex == 0 and gMarioState.heldObj ~= nil then
            local inCutscene = (gMarioState.action & ACT_GROUP_MASK) ~= ACT_GROUP_CUTSCENE
            if not inCutscene and gMarioState.heldObj.heldByPlayerIndex ~= 0 then
                drop_and_set_mario_action(gMarioState, ACT_IDLE, 0)
            end
        end

        local hangPreventionIndex = 0

        -- The function can loop through many action shifts in one frame,
        -- which can lead to unexpected sub-frame behavior. Could potentially hang
        -- if a loop of actions were found, but there has not been a situation found.
        while inLoop ~= 0 do
            -- this block can get stuck in an infinite loop due to unexpected circumstances arising from networked players
            hangPreventionIndex = hangPreventionIndex + 1
            if hangPreventionIndex >= 64 then
                break
            end

            local actionGroup = gMarioState.action & ACT_GROUP_MASK
            if actionGroup == ACT_GROUP_STATIONARY then
                inLoop = mario_execute_stationary_action(gMarioState)
            elseif actionGroup == ACT_GROUP_MOVING then
                inLoop = mario_execute_moving_action(gMarioState)
            elseif actionGroup == ACT_GROUP_AIRBORNE then
                inLoop = mario_execute_airborne_action(gMarioState)
            elseif actionGroup == ACT_GROUP_SUBMERGED then
                inLoop = mario_execute_submerged_action(gMarioState)
            elseif actionGroup == ACT_GROUP_CUTSCENE then
                inLoop = mario_execute_cutscene_action(gMarioState)
            elseif actionGroup == ACT_GROUP_AUTOMATIC then
                inLoop = mario_execute_automatic_action(gMarioState)
            elseif actionGroup == ACT_GROUP_OBJECT then
                inLoop = mario_execute_object_action(gMarioState)
            end
        end

        --[[sink_mario_in_quicksand(gMarioState)
        squish_mario_model(gMarioState)
        set_submerged_cam_preset_and_spawn_bubbles(gMarioState)
        update_mario_health(gMarioState)
        update_mario_info_for_cam(gMarioState)
        mario_update_hitbox_and_cap_model(gMarioState)]]

        -- Both of the wind handling portions play wind audio only in
        -- non-Japanese releases.
        if gMarioState.floor and gMarioState.floor.type == SURFACE_HORIZONTAL_WIND then
            spawn_wind_particles(0, gMarioState.floor.force << 8)
            -- #ifndef VERSION_JP
            play_sound(SOUND_ENV_WIND2, gMarioState.marioObj.header.gfx.cameraToObject)
            -- #endif
        end

        if gMarioState.floor and gMarioState.floor.type == SURFACE_VERTICAL_WIND then
            spawn_wind_particles(1, 0)
            -- #ifndef VERSION_JP
            play_sound(SOUND_ENV_WIND2, gMarioState.marioObj.header.gfx.cameraToObject)
            -- #endif
        end

        play_infinite_stairs_music()
        gMarioState.marioObj.oInteractStatus = 0
        --queue_particle_rumble()

        -- Make remote players disappear when they enter a painting
        -- should use same lo...
        -- (never finished)
    end
end

function detect_remote_player_hitbox_overlap(m, remote, scale)
    if m.marioBodyState.mirrorMario then return 0 end

    local a = m.marioObj
    local b = remote.marioObj
    if a == nil or b == nil then return 0 end
    if a.oIntangibleTimer ~= 0 then return end

    local aTorso = m.marioBodyState.torsoPos
    local bTorso = remote.torsoPos
    local sp3C = aTorso.y - a.hitboxDownOffset;
    local sp38 = bTorso.y - b.hitboxDownOffset;
    local dx = aTorso.x - bTorso.x;
    local dz = aTorso.z - bTorso.z;
    local collisionRadius = (a.hitboxRadius + b.hitboxRadius) * 1.75; -- slightly increased from 1.5f for the sake of it
    local distance = math.sqrt(dx * dx + dz * dz);

    if (collisionRadius * scale > distance) then
        local sp20 = a.hitboxHeight + sp3C;
        local sp1C = b.hitboxHeight + sp38;

        if (sp3C > sp1C) then
            return 0
        end
        if (sp20 < sp38) then
            return 0
        end

        return 1
    end
    return 0
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

function construct_remote_player_popup(a, message, extra)
    local name = a.name .. "\\#dcdcdc\\"
    message = message:gsub("@", name)
    if extra then
        message = message:sub(1, -2) .. extra
    end
    djui_popup_create(message, 1)
end

-- Get an unused mario state. Uses the latest in the list, unless this is a headless server, in which case it uses that player instead
function get_unused_mario_state()
    if gServerSettings.headlessServer ~= 0 and not network_is_server() then
        return gMarioStates[1]
    end
    return gMarioStates[MAX_PLAYERS-1]
end

function remote_player_is_active(a)
    local np0 = gNetworkPlayers[0]
    return a.connected ~= 0 and (a.level == np0.currLevelNum and a.area == np0.currAreaIndex and a.act == np0.currActNum)
end

-- Lua recreation
function player_is_sliding(m)
    if (not m) then return 0 end
    if (m.action & (ACT_FLAG_BUTT_OR_STOMACH_SLIDE | ACT_FLAG_DIVING) ~= 0) then
        return 1
    end

    if m.action == ACT_CROUCH_SLIDE or
        m.action == ACT_SLIDE_KICK_SLIDE or
        m.action == ACT_BUTT_SLIDE_AIR or
        m.action == ACT_HOLD_BUTT_SLIDE_AIR then
            return 1
    end
    return 0
end

-- Lua recreation
function determine_player_damage_value(attacker, interaction)
    if (gServerSettings.pvpType == PLAYER_PVP_REVAMPED) then
        if (attacker.action == ACT_GROUND_POUND_LAND) then return 2;
        elseif (interaction & INT_GROUND_POUND ~= 0) then return 3;
        elseif (interaction & (INT_KICK | INT_SLIDE_KICK | INT_TRIP | INT_TWIRL) ~= 0) then return 2;
        elseif (interaction & INT_PUNCH ~= 0 and attacker.actionArg < 3) then return 2;
        elseif (attacker.action == ACT_FLYING) then return math.max((attacker.forwardVel - 40) / 20, 0) + 1;
        end
        return 1;
    else
        if (interaction & INT_GROUND_POUND_OR_TWIRL ~= 0) then return 3;
        elseif (interaction & INT_KICK ~= 0) then return 2;
        elseif (interaction & INT_ATTACK_SLIDE ~= 0) then return 1;
        end
        return 2;
    end
end

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