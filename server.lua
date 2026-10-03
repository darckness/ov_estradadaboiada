local Core = exports.vorp_core:GetCore()

local missions = {}       -- [id] = transporte em andamento
local playerMission = {}  -- [source] = id
local lastDone = {}       -- [charid] = os.time() (cooldown por personagem)
local nextId = 0

local function Notify(src, msg, ms)
    Core.NotifyRightTip(src, msg, ms or 4000)
end

local function CharId(src)
    local user = Core.getUser(src)
    return user and user.getUsedCharacter.charIdentifier or nil
end

local function PlayerCoords(src)
    local ped = GetPlayerPed(src)
    return ped and ped ~= 0 and GetEntityCoords(ped) or nil
end

local function CooldownLeft(src)
    local cid = CharId(src)
    if Config.MissionCooldown <= 0 or not cid or not lastDone[cid] then return 0 end
    local left = Config.MissionCooldown * 60 - (os.time() - lastDone[cid])
    return left > 0 and math.ceil(left / 60) or 0
end

local function MemberList(m)
    local list = {}
    for src in pairs(m.members) do list[#list + 1] = src end
    return list
end

local function SendToMembers(m, event, ...)
    for src in pairs(m.members) do TriggerClientEvent(event, src, ...) end
end

local function DeleteCows(m)
    for _, net in ipairs(m.cowNets or {}) do
        local ent = NetworkGetEntityFromNetworkId(net)
        if ent and ent ~= 0 and DoesEntityExist(ent) then DeleteEntity(ent) end
    end
end

local function EndMission(m, message, applyCooldown)
    SendToMembers(m, 'ov_boiada:finish', message)
    DeleteCows(m)
    for src in pairs(m.members) do
        playerMission[src] = nil
        local cid = CharId(src)
        if applyCooldown and cid then lastDone[cid] = os.time() end
    end
    missions[m.id] = nil
end

local function NearNpc(src, index)
    local corral = Config.Corrals[index or 0]
    local c = PlayerCoords(src)
    if not corral or not c then return false end
    local n = corral.npc
    return #(c - vector3(n.x, n.y, n.z)) <= 6.0
end

-- =========================================================
-- Menu do capataz
-- =========================================================
RegisterNetEvent('ov_boiada:openMenu', function(index)
    local src = source
    if not NearNpc(src, index) then return end
    TriggerClientEvent('ov_boiada:showMenu', src, index, playerMission[src] ~= nil, CooldownLeft(src))
end)

-- =========================================================
-- Iniciar
-- =========================================================
RegisterNetEvent('ov_boiada:start', function(fromIndex, destIndex, cowCount)
    local src = source
    if not NearNpc(src, fromIndex) then return end

    if playerMission[src] then
        return Notify(src, "Você já está num transporte de gado.")
    end
    local left = CooldownLeft(src)
    if left > 0 then
        return Notify(src, ("Aguarde %d minuto(s) para iniciar outro transporte."):format(left))
    end

    cowCount = math.floor(tonumber(cowCount) or 0)
    if not Config.ValidRoute(fromIndex, destIndex) or cowCount < Config.CowCountMin or cowCount > Config.CowCountMax then return end
    local timeLimit = Config.TimeLimit(fromIndex, destIndex)

    nextId = nextId + 1
    local m = {
        id = nextId,
        from = fromIndex,
        dest = destIndex,
        price = Config.PricePerCow(fromIndex, destIndex),
        cowCount = cowCount,
        leader = src,
        members = { [src] = true },
        cowNets = {},
        expiresAt = os.time() + timeLimit * 60,
    }

    -- quem estiver perto entra no grupo
    local leaderCoords = PlayerCoords(src)
    local count = 1
    for _, id in ipairs(GetPlayers()) do
        local other = tonumber(id)
        if other ~= src and count < Config.Group.maxMembers and not playerMission[other] and CooldownLeft(other) == 0 then
            local c = PlayerCoords(other)
            if c and leaderCoords and #(c - leaderCoords) <= Config.Group.radius then
                m.members[other] = true
                count = count + 1
            end
        end
    end

    missions[m.id] = m
    for member in pairs(m.members) do playerMission[member] = m.id end

    local data = { id = m.id, from = fromIndex, dest = destIndex, cowCount = cowCount, leader = src, members = MemberList(m), timeLimit = timeLimit }
    SendToMembers(m, 'ov_boiada:joined', data)
    TriggerClientEvent('ov_boiada:spawnHerd', src, data) -- o líder cria as vacas e conduz a manada
end)

RegisterNetEvent('ov_boiada:spawned', function(id, nets)
    local src = source
    local m = missions[id]
    if not m or m.leader ~= src or type(nets) ~= "table" then return end
    m.cowNets = nets

    SetTimeout(1000, function()
        for _, net in ipairs(nets) do
            local ent = NetworkGetEntityFromNetworkId(net)
            if ent and ent ~= 0 then pcall(SetEntityOrphanMode, ent, 2) end
        end
    end)
    SendToMembers(m, 'ov_boiada:cows', nets)
end)

RegisterNetEvent('ov_boiada:spawnFailed', function(id)
    local m = missions[id]
    if m and m.leader == source then
        EndMission(m, "Não foi possível soltar o gado. Tente de novo.", false)
    end
end)

-- =========================================================
-- Disparada: qualquer membro pode assustar o gado (o líder executa)
-- =========================================================
-- debug: o líder manda como a manada está "pensando" pros outros do grupo verem
RegisterNetEvent('ov_boiada:debug', function(id, d)
    local m = missions[id]
    if not m or m.leader ~= source or type(d) ~= "table" then return end
    for src in pairs(m.members) do
        if src ~= m.leader then TriggerClientEvent('ov_boiada:debugState', src, d) end
    end
end)

-- [Q] troca a marcha da manada (qualquer vaqueiro do grupo); todos ficam sabendo
RegisterNetEvent('ov_boiada:gear', function()
    local m = missions[playerMission[source] or -1]
    if not m then return end
    m.gear = (m.gear or 1) % #Config.Herd.gears + 1
    SendToMembers(m, 'ov_boiada:setGear', m.gear)
end)

-- =========================================================
-- Entrega: o servidor confere a posição de cada vaca
-- =========================================================
RegisterNetEvent('ov_boiada:deliver', function(id, aliveNets)
    local src = source
    local m = missions[id]
    if not m or not m.members[src] or type(aliveNets) ~= "table" then return end

    local dest = Config.Corrals[m.dest]
    local radius = Config.CorralRadius
    local myCoords = PlayerCoords(src)
    if not myCoords or #(myCoords - dest.coords) > radius + 25.0 then return end

    local valid = {}
    for _, net in ipairs(m.cowNets) do valid[net] = true end

    local delivered = 0
    for _, net in ipairs(aliveNets) do
        if valid[net] then
            valid[net] = nil -- conta cada vaca uma vez só
            local ent = NetworkGetEntityFromNetworkId(net)
            if ent and ent ~= 0 and DoesEntityExist(ent) then
                if #(GetEntityCoords(ent) - dest.coords) <= radius + 3.0 then
                    delivered = delivered + 1
                end
            else
                delivered = delivered + 1 -- sem OneSync para conferir: confia no cliente
            end
        end
    end
    if delivered == 0 then return end

    local members = MemberList(m)
    local n = #members
    local total = delivered * m.price * (1 + Config.Group.bonusPerMember * (n - 1))
    local each = math.floor(total / n * 100) / 100

    for _, member in ipairs(members) do
        local user = Core.getUser(member)
        if user then user.getUsedCharacter.addCurrency(0, each) end
    end

    local msg = n > 1
        and ("%d de %d cabeça(s) entregues em %s. Cada vaqueiro recebeu $%.2f."):format(delivered, m.cowCount, dest.name, each)
        or ("%d de %d cabeça(s) entregues em %s. Você recebeu $%.2f."):format(delivered, m.cowCount, dest.name, each)
    EndMission(m, msg, true)
end)

RegisterNetEvent('ov_boiada:allDead', function(id)
    local m = missions[id]
    if m and m.leader == source then
        EndMission(m, "Todas as vacas morreram. Transporte cancelado.", true)
    end
end)

RegisterNetEvent('ov_boiada:cancel', function()
    local m = missions[playerMission[source] or -1]
    if m then EndMission(m, "O transporte de gado foi cancelado.", true) end
end)

-- =========================================================
-- Tempo limite / desconexão
-- =========================================================
CreateThread(function()
    while true do
        Wait(15000)
        local now = os.time()
        for _, m in pairs(missions) do
            if now >= m.expiresAt then
                EndMission(m, "O prazo acabou. O comprador desistiu do gado.", true)
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    local m = missions[playerMission[src] or -1]
    playerMission[src] = nil
    if not m then return end

    m.members[src] = nil
    if m.leader == src or not next(m.members) then
        EndMission(m, "O líder da boiada saiu. Transporte cancelado.", false)
    else
        SendToMembers(m, 'ov_boiada:members', MemberList(m))
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, m in pairs(missions) do DeleteCows(m) end
end)
