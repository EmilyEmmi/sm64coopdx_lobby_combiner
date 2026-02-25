-- Handles remote Marios.
-- There's a lot of unused garbage here because I tried too hard to make the fake marios accurate.

MODEL_TABLE = {
    [CT_MARIO] = E_MODEL_MARIO,
    [CT_LUIGI] = E_MODEL_LUIGI,
    [CT_TOAD] = E_MODEL_TOAD_PLAYER,
    [CT_WALUIGI] = E_MODEL_WALUIGI,
    [CT_WARIO] = E_MODEL_WARIO,
}

extraMarioStates = {}

-- Fake mario objects
---@param o Object
function fake_mario_init(o)
    o.oFlags = o.oFlags | OBJ_FLAG_UPDATE_GFX_POS_AND_ANGLE
    o.oOpacity = 255
    o.globalPlayerIndex = highest_global_from_local()
    o.oInteractType = INTERACT_PLAYER
    o.hitboxDownOffset = 0
    o.hitboxRadius = 37
    o.hitboxHeight = 160
    cur_obj_disable_rendering_and_become_intangible(o)
end

---@param o Object
function fake_mario_loop(o)
    o.globalPlayerIndex = highest_global_from_local()

    local index = o.oBehParams
    local a = extraMarioData[index]
    if not a then return end
    a.marioObj = o

    if not remote_player_is_active(a) then
        cur_obj_disable_rendering()
        return
    end

    if a.action & ACT_FLAG_SHORT_HITBOX ~= 0 then
        o.hitboxHeight = 100
    else
        o.hitboxHeight = 160
    end

    obj_set_pos(o, a.posX, a.posY, a.posZ)
    obj_set_angle(o, a.angleX, a.angleY, a.angleZ)
    if MODEL_TABLE[a.char] then
        obj_set_model_extended(o, MODEL_TABLE[a.char])
    end
    cur_obj_enable_rendering()

    if ((a.invincTimer >= 3) and (get_global_timer() & 1 ~= 0)) or (a.action == ACT_DISAPPEARED) then
        o.header.gfx.node.flags = o.header.gfx.node.flags | GRAPH_RENDER_INVISIBLE
    else
        o.header.gfx.node.flags = o.header.gfx.node.flags & ~GRAPH_RENDER_INVISIBLE
    end

    o.header.gfx.sharedChild.hookProcess = 0x34
    local animInfo = o.header.gfx.animInfo
    animInfo.curAnim = get_mario_vanilla_animation(a.animID)
    animInfo.animYTrans = a.animYTrans
    animInfo.animFrameAccelAssist = a.animFrameAccelAssist
    animInfo.animAccel = a.animAccel
end

id_bhvFakeMario = hook_behavior(nil, OBJ_LIST_GENACTOR, true, fake_mario_init, fake_mario_loop, "bhvFakeMario")

function handle_fake_mario_update(m)
    local test_m = gMarioStates[0] -- get_unused_mario_state()
    if test_m ~= m then return end

    -- Hijack this mario state to run our fake marios.
    -- We store mario's current information and transfer it back when we're done.
    -- Kinda risky...
    local m_temp = {}
    local prevChar = gNetworkPlayers[m.playerIndex].overrideModelIndex
    transfer_mario_state(m_temp, m)

    local o = obj_get_first_with_behavior_id(id_bhvFakeMario)
    while o do
        local index = o.oBehParams
        local a = extraMarioData[index]
        if not a then return end

        --[[local animInfo = o.header.gfx.animInfo
        local mAnimInfo = m.marioObj.header.gfx.animInfo
        mAnimInfo.curAnim = animInfo.curAnim
        mAnimInfo.animYTrans = animInfo.animYTrans
        mAnimInfo.animFrameAccelAssist = animInfo.animFrameAccelAssist
        mAnimInfo.animAccel = animInfo.animAccel
        mAnimInfo.animFrame = animInfo.animFrame]]

        local m_extra = extraMarioStates[index]
        if not m_extra then
            extraMarioStates[index] = {}
            m_extra = extraMarioStates[index]
        else
            transfer_mario_state(m, m_extra)
        end
        m.pos.x, m.pos.y, m.pos.z = a.posX, a.posY, a.posZ
        m.faceAngle.x, m.faceAngle.y, m.faceAngle.z = a.angleX, a.angleY, a.angleZ
        m.action = a.action
        gNetworkPlayers[m.playerIndex].overrideModelIndex = a.char
        copy_mario_state_to_object(m, m.marioObj)

        execute_mario_action(m.marioObj)

        a.posX, a.posY, a.posZ = m.pos.x, m.pos.y, m.pos.z
        a.angleX, a.angleY, a.angleZ = m.faceAngle.x, m.faceAngle.y, m.faceAngle.z
        a.action = m.action
        
        --[[animInfo.curAnim = mAnimInfo.curAnim
        animInfo.animYTrans = mAnimInfo.animYTrans
        animInfo.animFrameAccelAssist = mAnimInfo.animFrameAccelAssist
        animInfo.animAccel = mAnimInfo.animAccel
        animInfo.animFrame = mAnimInfo.animFrame]]

        --o.header.gfx.node.flags = m.marioObj.header.gfx.node.flags
        transfer_mario_state(m_extra, m)
        o = obj_get_next_with_same_behavior_id(o)
    end
    
    transfer_mario_state(m, m_temp)
    copy_mario_state_to_object(m, m.marioObj)
    gNetworkPlayers[m.playerIndex].overrideModelIndex = prevChar
end
--hook_event(HOOK_MARIO_UPDATE, handle_fake_mario_update)

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
    local a = extraMarioData[o.oBehParams]
    transfer_body_state(prevBodyState, m.marioBodyState)

    m.marioBodyState.punchState = 0
    m.marioBodyState.handState = MARIO_HAND_FISTS
    m.marioBodyState.eyeState = MARIO_EYES_OPEN
    m.marioBodyState.capState = MARIO_HAS_DEFAULT_CAP_ON
    m.marioBodyState.action = ACT_IDLE
    m.marioBodyState.modelState = 0
    vec3s_zero(m.marioBodyState.headAngle)
    vec3s_zero(m.marioBodyState.torsoAngle)

    -- Adjust mario visuals based on flags
    if (a.flags & MARIO_VANISH_CAP ~= 0) then
        m.marioBodyState.modelState = m.marioBodyState.modelState | MODEL_STATE_NOISE_ALPHA;
    end
    if (a.flags & (MARIO_METAL_CAP | MARIO_METAL_SHOCK) ~= 0) then
        m.marioBodyState.modelState = m.marioBodyState.modelState | MODEL_STATE_METAL;
    end
    if (a.flags & MARIO_CAP_IN_HAND ~= 0) then
        if (a.flags & MARIO_WING_CAP ~= 0) then
            m.marioBodyState.handState = MARIO_HAND_HOLDING_WING_CAP;
        else
            m.marioBodyState.handState = MARIO_HAND_HOLDING_CAP;
        end
    end
    if (a.flags & MARIO_CAP_ON_HEAD ~= 0) then
        if (a.flags & MARIO_WING_CAP ~= 0) then
            m.marioBodyState.capState = MARIO_HAS_WING_CAP_ON;
        else
            m.marioBodyState.capState = MARIO_HAS_DEFAULT_CAP_ON;
        end
    end

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
    local a = extraMarioData[o.oBehParams]
    vec3f_copy(a.torsoPos, m.marioBodyState.torsoPos)
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
