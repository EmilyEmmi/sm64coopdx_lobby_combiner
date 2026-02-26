-- name: Lobby Synchronizer [v0.1B]
-- description: Cursed nonsense that allows multiple lobbies to communicate with each other. Has science gone too far?\n\nMod by EmilyEmmi. Check inside main.lua for usage instructions.

--[[
ATTENTION!

This mod does not simply "make lobbies bigger." It will NOT let you play any game mode with more players out of the box.
Current features include:
- Seeing players from other lobbies (including palette, sounds, and location)
- Seeing chat messages from other lobbies
- PVP interaction (but not head bounces yet)

Planned features (as of now) include:
- Nametags for remote players
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
TOTAL_LOBBY_COUNT = 4

-- Frames between each read/write to modFs. You may increase this if you, the host, are experiencing performance issues.
local FRAMES_TO_RELOAD = 2

didFirstJoinStuff = false
gGlobalSyncTable.lobbyID = 0

locationPopups = true

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
        local bytestring = create_player_bytestring(a)
        bytestring = string.pack("<I4", #bytestring) .. bytestring
        fullByteString = fullByteString .. bytestring
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
                        local bytes = string.unpack("<I4", lengthString)
                        if bytes == 0 then break end
                        local bytestring = file:read_bytes(bytes)
                        if bytestring and #bytestring ~= 0 then
                            local a = parse_player_bytestring(bytestring)
                            if a and (a.wasConnected ~= 0 or a.connected ~= 0) then
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
        if a.connected ~= 0 then
            a.name = network_get_player_text_color_string(m.playerIndex) .. np.name
        end
        a.wasConnected = a.connected

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
    a.flags = m.flags or 0
    a.action = m.action or 0
    a.actionArg = m.actionArg or 0
    a.actionState = m.actionState or 0
    a.health = m.health or 0
    a.invincTimer = m.invincTimer or 0
    a.hurtCounter = m.hurtCounter or 0
    a.velX, a.velY, a.velZ = math.floor(m.vel.x), math.floor(m.vel.y), math.floor(m.vel.z)

    -- Clear character sound after a few frames
    if a.charSound ~= -1 then
        marioSoundTimer = marioSoundTimer - 1
        if marioSoundTimer == 0 then
            marioSoundTimer = 5
            a.charSound = -1
        end
    end

    if (not network_is_server()) and (FRAMES_TO_RELOAD <= 1 or get_global_timer() % FRAMES_TO_RELOAD == 0) then
        local bytestring = create_player_bytestring(a, true)
        network_send_bytestring_to(1, false, bytestring)
    end
end

hook_event(HOOK_MARIO_UPDATE, mario_update)

-- Handle remote PVP
function on_interactions(m)
    if m.playerIndex ~= 0 then return end
    if gServerSettings.playerInteractions == PLAYER_INTERACTIONS_NONE then return end
    if not didFirstJoinStuff then return end

    local vanishFlags = (MARIO_VANISH_CAP | MARIO_CAP_ON_HEAD)
    if (m.action & ACT_FLAG_INTANGIBLE == 0 and m.flags & vanishFlags ~= vanishFlags
    and m.action ~= ACT_JUMBO_STAR_CUTSCENE and m.invincTimer == 0) then
        for i=0,MAX_PLAYERS_TOTAL-1 do
            local a = extraMarioData[i]
            if (remote_player_is_active(a) and (not a.isLocal)
            and a.action & ACT_FLAG_INTANGIBLE == 0 and a.invincTimer == 0) then
                interact_remote_player_pvp(a, m);
            end
        end
    end
end
hook_event(HOOK_ON_INTERACTIONS, on_interactions)

function interact_remote_player_pvp(a, victim)
    -- vanish cap players can't interact
    local vanishFlags = (MARIO_VANISH_CAP | MARIO_CAP_ON_HEAD);
    if ((a.flags & vanishFlags) == vanishFlags) then return 0 end

    -- don't attack each other on level load
    if (victim.area == nil or victim.area.localAreaTimer < 60) then return 0 end
    
    local revamped = (gServerSettings.pvpType == PLAYER_PVP_REVAMPED)
    local attackerVelLength = vec3f_length({x = a.velX, y = a.velY, z = a.velZ})

    -- Check pvp interaction by using spare mario state
    local attacker = get_unused_mario_state()
    local temp_mario = {}
    transfer_mario_state(temp_mario, attacker)
    attacker.action = a.action or 0
    attacker.actionArg = a.actionArg or 0
    attacker.actionState = a.actionState or 0
    attacker.invincTimer = a.invincTimer or 0
    attacker.hurtCounter = a.hurtCounter or 0
    attacker.flags = a.flags or 0
    attacker.forwardVel = attackerVelLength -- close enough, only used for wing cap attacks
    attacker.pos.x, attacker.pos.y, attacker.pos.z = a.posX, a.posY, a.posZ
    attacker.vel.x, attacker.vel.y, attacker.vel.z = a.velX, a.velY, a.velZ
    attacker.faceAngle.x, attacker.faceAngle.y, attacker.faceAngle.z = a.angleX, a.angleY, a.angleZ
    
    local result = passes_pvp_interaction_checks(attacker, victim)
    local result_lag = result
    local cVictim = victim
    if result ~= 0 and victim.playerIndex == 0 and not network_is_server() then
        -- Use lag compensation from host
        cVictim = lag_compensation_get_local_state(gNetworkPlayers[1])
        result_lag = passes_pvp_interaction_checks(attacker, cVictim)
    end

    if result == 0 then
        transfer_mario_state(attacker, temp_mario)
        return 0
    end

    -- make sure we overlap
    local overlapScale = 1
    if (revamped and a.action == ACT_GROUND_POUND_LAND) then
        overlapScale = overlapScale + 0.3
    end
    if (detect_remote_player_hitbox_overlap(cVictim, a, overlapScale) == 0) then
        transfer_mario_state(attacker, temp_mario)
        return 0
    end

    local attackerRolloutFlip = (a.action == ACT_FORWARD_ROLLOUT or a.action == ACT_BACKWARD_ROLLOUT) and (a.actionState == 1)
    local victimRolloutFlip = (victim.action == ACT_FORWARD_ROLLOUT or victim.action == ACT_BACKWARD_ROLLOUT) and (victim.actionState == 1)

    -- see if it was an attack
    local interaction = determine_interaction(attacker, cVictim.marioObj)

    -- Specfically override jump kicks to prevent low damage and low knockback kicks
    if (a.action == ACT_JUMP_KICK) then
        interaction = INT_KICK
    elseif (attackerRolloutFlip) then -- Allow rollouts to attack
        interaction = INT_HIT_FROM_BELOW
    end
    if ((interaction & INT_ANY_ATTACK == 0) or (interaction & INT_HIT_FROM_ABOVE ~= 0) or result_lag == 0) then
        transfer_mario_state(attacker, temp_mario)
        return 0
    end

    -- call the custom hook
    local allowAttack = handle_custom_event("remote_allow_pvp_attack", a, cVictim, interaction);
    if (not allowAttack) then
        -- Lua blocked the interaction
        return 0
    end

    -- determine if slide attack should be ignored
    if ((interaction & INT_ATTACK_SLIDE ~= 0) or player_is_sliding(cVictim) ~= 0) then
        -- determine the difference in velocities
        --Vec3f velDiff;
        --vec3f_dif(velDiff, attacker.vel, cVictim.vel);
        -- Allow groundpounds to always hit sliding/fast attacks
        if (revamped and a.action == ACT_GROUND_POUND) then
            -- do nothing
        else
            if (a.action == ACT_SLIDE_KICK_SLIDE or a.action == ACT_SLIDE_KICK) then
                -- if the difference vectors are not different enough, do not attack
                if (attackerVelLength < 15) then
                    transfer_mario_state(attacker, temp_mario)
                    return 0
                end
            else
                -- if the difference vectors are not different enough, do not attack
                if (attackerVelLength < 40) then
                    transfer_mario_state(attacker, temp_mario)
                    return 0
                end
            end

            local forceAllowAttack = false
            if (revamped) then
                -- Give slidekicks trade immunity by making them (almost) invincible
                -- Also give rollout flips immunity to dives
                if ((cVictim.action == ACT_SLIDE_KICK and a.action ~= ACT_SLIDE_KICK) or
                    (victimRolloutFlip and a.action == ACT_DIVE)) then
                    transfer_mario_state(attacker, temp_mario)
                    return 0
                elseif ((a.action == ACT_SLIDE_KICK) or
                           (victimRolloutFlip and cVictim.action == ACT_DIVE)) then
                    forceAllowAttack = true
                end
            end
            -- if the victim is going faster, do not attack
            if (vec3f_length(cVictim.vel) > attackerVelLength and not forceAllowAttack) then
                transfer_mario_state(attacker, temp_mario)
                return 0
            end
        end
    end

    -- determine if ground pound should be ignored
    if (a.action == ACT_GROUND_POUND) then
        -- not moving down yet?
        if (a.actionState == 0) then
            transfer_mario_state(attacker, temp_mario)
            return 0
        end
        victim.bounceSquishTimer = math.max(victim.bounceSquishTimer, 20);
    end

    if (victim.playerIndex == 0) then
        victim.interactObj = a.marioObj;
        if (interaction & INT_KICK ~= 0) then
            if (victim.action == ACT_FIRST_PERSON) then
                -- without this branch, the player will be stuck in first person
                raise_background_noise(2);
                set_camera_mode(victim.area.camera, -1, 1);
                victim.input = victim.input & ~INPUT_FIRST_PERSON;
            end
            set_mario_action(victim, ACT_FREEFALL, 0);
        end
        if ((victim.flags & MARIO_METAL_CAP) == 0) then
            attacker.marioObj.oDamageOrCoinValue = determine_player_damage_value(attacker, interaction)
            if (a.flags & MARIO_METAL_CAP ~= 0) then attacker.marioObj.oDamageOrCoinValue = attacker.marioObj.oDamageOrCoinValue * 2; end
        end
    end

    attacker.marioObj.oFaceAngleYaw = attacker.faceAngle.y
    victim.invincTimer = math.max(victim.invincTimer, 3);
    victim.interactObj = nil
    local prevFaceY = victim.faceAngle.y
    victim.invincTimer = 0
    local damaged = take_damage_and_knock_back(victim, attacker.marioObj);
    victim.faceAngle.y = prevFaceY

    -- Happens with the second part of the punch combo.
    -- This is a bit of a wonky fix
    if damaged == 0 then
        -- Switch to next normal action when punch so we get hit next frame.
        -- Could happen on last frame and look weird, hopefully that doesn't happen...
        if victim.action & ACT_FLAG_INVULNERABLE ~= 0 and attacker.flags & MARIO_PUNCHING ~= 0 then
            if victim.action & ACT_FLAG_AIR ~= 0 then
                set_mario_action(victim, ACT_FREEFALL, 0)
            else
                force_idle_state(victim)
            end
        end

        victim.interactObj = nil
        transfer_mario_state(attacker, temp_mario)
        attacker.marioObj.oFaceAngleYaw = attacker.faceAngle.y
        return 0
    end

    -- recalculate knockback strength; needed for punch combos
    local angleToObject = mario_obj_angle_to_object(victim, victim.interactObj);
    local facingDYaw = angleToObject - victim.faceAngle.y
    victim.faceAngle.y = angleToObject
    local sign = 1
    if (-0x4000 <= facingDYaw and facingDYaw <= 0x4000) then
        sign = -1
    else
        victim.faceAngle.y = victim.faceAngle.y + 0x8000;
    end
    local terrainIndex = 0
    if (victim.action & (ACT_FLAG_SWIMMING | ACT_FLAG_METAL_WATER) ~= 0) then
        terrainIndex = 2;
    elseif (victim.action & (ACT_FLAG_AIR | ACT_FLAG_ON_POLE | ACT_FLAG_HANGING) ~= 0) then
        terrainIndex = 1;
    end

    local scaler = 1
    local hasBeenPunched = false
    if (attacker.action == ACT_JUMP_KICK or attacker.flags & MARIO_KICKING ~= 0) then scaler = (revamped and 1.9) or 2.0
    elseif (attacker.action == ACT_DIVE) then scaler = 1.0 + (revamped and (attacker.forwardVel * 0.005) or 0)
    elseif ((attacker.flags & MARIO_PUNCHING) ~= 0) then
        scaler = (revamped and -0.1) or 1
        hasBeenPunched = revamped
    end
    if (attacker.flags & MARIO_METAL_CAP ~= 0) then scaler = scaler * 1.25 end
    if (victim.flags & MARIO_METAL_CAP ~= 0) then
        scaler = scaler * 0.5;
        if (scaler < 1) then scaler = 1; end
    end
    
    local mag = scaler * gServerSettings.playerKnockbackStrength * sign;
    victim.forwardVel = mag;
    if (sign > 0 and terrainIndex == 1) then mag = mag * -1 end

    victim.vel.x = (-mag * sins(victim.interactObj.oFaceAngleYaw)) * ((revamped and 1.1) or 1);
    victim.vel.y = (math.abs(mag)) * ((revamped and 0.9) or 1);
    victim.vel.z = (-mag * coss(victim.interactObj.oFaceAngleYaw)) * ((revamped and 1.1) or 1);
    victim.slideVelX = victim.vel.x;
    victim.slideVelZ = victim.vel.z;
    victim.knockbackTimer = PVP_ATTACK_KNOCKBACK_TIMER_DEFAULT
    if hasBeenPunched then
        victim.knockbackTimer = PVP_ATTACK_KNOCKBACK_TIMER_OVERRIDE
        victim.invincTimer = 0
    end
    victim.faceAngle.y = victim.interactObj.oFaceAngleYaw
    if sign ~= 1 then
        victim.faceAngle.y = victim.faceAngle.y + 0x8000
    end

    --[[if (gServerSettings.pvpType ~= PLAYER_PVP_REVAMPED or (a.flags & MARIO_PUNCHING == 0)) then
        bounce_back_from_attack(attacker, interaction);
    end]]
    victim.interactObj = nil;

    handle_custom_event("remote_on_pvp_attack", a, victim, interaction);
    transfer_mario_state(attacker, temp_mario)
    attacker.marioObj.oFaceAngleYaw = attacker.faceAngle.y
    return 0
end

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

function update_extra_player(a)
    if a == nil or a.isLocal then return end
    
    -- connection popups
    if a.wasConnected ~= a.connected then
        a.wasConnected = a.connected
        if a.connected ~= 0 then
            construct_remote_player_popup(a, djui_language_get("NOTIF", "CONNECTED"));
        elseif #a.name ~= 0 then
            construct_remote_player_popup(a, djui_language_get("NOTIF", "DISCONNECTED"));
        end
    end

    if a.connected == 0 then return end
    
    if a.prevLevel ~= a.level or a.prevArea ~= a.area or a.prevAct ~= a.act then
        if locationPopups and a.prevAct ~= 99 then
            local np0 = gNetworkPlayers[0]
            local course = get_level_course_num(a.level)
            local prevCourse = get_level_course_num(a.prevLevel)
            if prevCourse ~= course then
                local matchingLocal = (prevCourse == np0.currCourseNum) and (a.prevAct == np0.currActNum);

                if (matchingLocal and np0.currCourseNum ~= 0) then
                    construct_remote_player_popup(a, djui_language_get("NOTIF", "LEFT_THIS_LEVEL"));
                elseif (np0.currCourseNum == course and np0.currCourseNum ~= 0) then
                    construct_remote_player_popup(a, djui_language_get("NOTIF", "ENTERED_THIS_LEVEL"));
                else
                    construct_remote_player_popup(a, djui_language_get("NOTIF", "ENTERED"), get_level_name(course, a.level, a.area));
                end
            end
        end
        
        handle_custom_event("remote_player_changed_area", a, a.prevLevel, a.prevArea, a.prevAct, a.level, a.prevArea, a.prevAct)
        a.prevLevel, a.prevArea, a.prevAct = a.level, a.area, a.act
    end

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
        a.flags = 0
        a.action = 0
        a.actionArg = 0
        a.actionState = 0
        a.invincTimer = 0
        a.hurtCounter = 0
        a.health = 0
        a.velX = 0
        a.velY = 0
        a.velZ = 0
        a.name = ""
        a.msg = ""
        a.torsoPos = gVec3fZero()

        -- Palette parts
        for part = 0, PLAYER_PART_MAX - 1 do
            a["pal_" .. part .. "_r"] = 0
            a["pal_" .. part .. "_g"] = 0
            a["pal_" .. part .. "_b"] = 0
        end

        -- Non-sync fields
        a.prevLevel = 0
        a.prevArea = 0
        a.prevAct = 0
        a.prevMsg = ""
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