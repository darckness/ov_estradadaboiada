VORPcore = exports.vorp_core:GetCore()

-- =========================================================
-- Helper à prova de falhas para criar blips.
-- Em alguns artifacts/builds de RedM mais antigos o alias
-- "AddBlipForCoord" não existe, então tentamos várias formas
-- de chamar o native até uma funcionar.
-- =========================================================
local warnedNoBlip = false
local function CreateWorldBlip(coords)
    -- 1) Native correto do RedM: usa um hash de ESTILO (não sprite numérico como no GTA5)
    do
        local ok, blip = pcall(BlipAddForCoords, `BLIP_STYLE_FRIENDLY`, coords.x, coords.y, coords.z)
        if ok and blip and blip ~= 0 then return blip end
    end

    -- 2) fallback: alias "amigável" do GTA5, caso mude de artifact/versão no futuro
    if type(AddBlipForCoord) == "function" then
        local ok, blip = pcall(AddBlipForCoord, coords)
        if ok and blip then return blip end
    end

    if type(AddBlipForCoord) == "function" then
        local ok, blip = pcall(AddBlipForCoord, coords.x, coords.y, coords.z)
        if ok and blip then return blip end
    end

    -- 3) via hash cru (Citizen.InvokeNative)
    local ok, blip = pcall(function()
        return Citizen.InvokeNative(0x554D9D53F696D002, coords.x, coords.y, coords.z)
    end)
    if ok and blip and blip ~= 0 then return blip end

    if not warnedNoBlip then
        warnedNoBlip = true
        print("^1[ov_cattletransport] Não consegui criar blip: nenhuma native de blip disponível nesta build do FXServer/RedM.^7")
        print("^1[ov_cattletransport] O restante da missão (spawn de vacas, entrega, pagamento) continua funcionando normalmente.^7")
    end
    return nil
end

local function RemoveWorldBlip(blip)
    if not blip then return end
    -- Tenta todas as formas possíveis - inofensivo tentar mais de uma,
    -- já que remover um blip que não existe mais não causa problema.
    pcall(function()
        if type(DoesBlipExist) == "function" and DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end)
    pcall(RemoveBlip, blip)
    pcall(Citizen.InvokeNative, 0x86A652570E5F25DD, blip)
end

local missionActive = false
local spawnedCows = {}
local herdOffsets = {} -- [cow] = {x=.., y=..} posição fixa de cada vaca relativa à âncora
local herdAnchor = nil -- vector3: ponto que representa "a manada"
local sprintUntil = 0 -- enquanto GetGameTimer() < isso, a manada está "disparada" (correndo)
local deliveryBlip = nil
local nearStart = false

-- Manda a vaca pra um ponto usando navegação com desvio de obstáculos
-- (usa o sistema de pathfinding do jogo, então ela contorna cercas,
-- árvores, etc. em vez de ficar presa). Cai pra linha reta só se essa
-- native não existir nesta build.
local function MoveCowTo(cow, x, y, z, speed)
    local ok = pcall(TaskGoToCoordAnyMeans, cow, x, y, z, speed, 0, false, 786603, 0.0)
    if ok then return end
    pcall(TaskGoStraightToCoord, cow, x, y, z, speed, 5000, 0.0, 0.0)
end

-- =========================================================
-- Tecla G para iniciar a missão (RegisterKeyMapping garante
-- que o bind padrão seja G, mesmo que o jogador troque outras
-- teclas nas configurações do jogo)
-- =========================================================
RegisterKeyMapping('cattletransport_start', 'Iniciar Transporte de Gado', 'keyboard', 'g')
RegisterCommand('cattletransport_start', function()
    if nearStart and not missionActive then
        TriggerServerEvent('ov_cattletransport:startMission')
    end
end, false)

-- =========================================================
-- Tecla para "disparar" a manada (correr por alguns segundos).
-- Sem isso, a manada só anda calma conforme você se aproxima.
-- =========================================================
RegisterKeyMapping('cattletransport_sprint', 'Disparar o Gado (correr)', 'keyboard', Config.Herd.sprintKey)
RegisterCommand('cattletransport_sprint', function()
    if not missionActive or not herdAnchor then return end

    local playerCoords = GetEntityCoords(PlayerPedId())
    if #(playerCoords - herdAnchor) > Config.Herd.sprintRange then
        VORPcore.NotifyRightTip("Chegue mais perto do gado para assustá-lo.", 3000)
        return
    end

    sprintUntil = GetGameTimer() + Config.Herd.sprintDuration
end, false)

-- =========================================================
-- Comando de utilidade: /mycoords
-- Imprime sua posição atual no chat e no console (F8),
-- para você achar as coordenadas certas de Valentine/Rhodes
-- e ajustar o config.lua. Pode remover depois de configurar.
-- =========================================================
RegisterCommand('mycoords', function()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    local msg = string.format("vector3(%.2f, %.2f, %.2f) | heading: %.1f", coords.x, coords.y, coords.z, heading)

    print(("[mycoords] %s"):format(msg))
    TriggerEvent('chat:addMessage', {
        args = { "Coords", msg }
    })
end, false)

-- =========================================================
-- Blip fixo em Valentine (ponto de início)
-- =========================================================
local startBlipHandle = nil
CreateThread(function()
    startBlipHandle = CreateWorldBlip(Config.StartPoint.coords)
    if startBlipHandle then
        pcall(SetBlipSprite, startBlipHandle, Config.StartPoint.blip.sprite, true)
        pcall(SetBlipScale, startBlipHandle, Config.StartPoint.blip.scale)
        pcall(SetBlipAsShortRange, startBlipHandle, false) -- sempre visível no mapa, não só de perto
        pcall(SetBlipName, startBlipHandle, Config.StartPoint.blip.label)
    end
end)

-- =========================================================
-- Comando de utilidade: /blipsprite <nome>
-- Testa um ícone (pelo nome, ex: BLIP_AMBIENT_HERD) no blip de
-- Valentine em tempo real. Remova depois de escolher o ícone certo.
-- =========================================================
RegisterCommand('blipsprite', function(source, args)
    if not startBlipHandle then
        print("^1[ov_cattletransport] Blip de Valentine ainda não foi criado.^7")
        return
    end
    local name = args[1]
    if not name then
        print("^3[ov_cattletransport] Uso: /blipsprite <nome, ex: BLIP_AMBIENT_HERD>^7")
        return
    end
    local hash = GetHashKey(name)
    local ok = pcall(SetBlipSprite, startBlipHandle, hash, true)
    print(("[ov_cattletransport] /blipsprite %s (hash %s) -> pcall ok: %s"):format(name, tostring(hash), tostring(ok)))
end, false)

-- =========================================================
-- Marker + texto de ajuda no ponto de início
-- =========================================================
CreateThread(function()
    while true do
        local sleep = 1000
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        local dist = #(coords - Config.StartPoint.coords)

        if dist < 15.0 then
            sleep = 0
            DrawMarker(1,
                Config.StartPoint.coords.x, Config.StartPoint.coords.y, Config.StartPoint.coords.z - 1.0,
                0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                1.5, 1.5, 1.0,
                255, 194, 14, 100,
                false, true, 2, false, nil, nil, false)

            if dist < 2.0 then
                if not nearStart and not missionActive then
                    -- Usamos o chat em vez dos natives de "help text" (indisponíveis nesta build)
                    TriggerEvent('chat:addMessage', {
                        args = { "Transporte de Gado", "Pressione G para iniciar o transporte de gado." }
                    })
                end
                nearStart = true
            else
                nearStart = false
            end
        else
            nearStart = false
        end

        Wait(sleep)
    end
end)

-- =========================================================
-- Início da missão: spawna as vacas e cria o blip de entrega
-- =========================================================
RegisterNetEvent('ov_cattletransport:beginClient', function()
    if missionActive then return end
    missionActive = true
    spawnedCows = {}
    herdOffsets = {}

    VORPcore.NotifyRightTip("Leve as vacas até Rhodes.", 5000)

    local cowModelHash = nil
    for _, name in ipairs(Config.CowModelCandidates) do
        local hash = GetHashKey(name)
        if IsModelValid(hash) and IsModelAPed(hash) then
            print(("^2[ov_cattletransport] Modelo de vaca válido encontrado: '%s' (hash %s). Atualize Config.CowModelCandidates para deixar só esse no topo.^7"):format(name, tostring(hash)))
            cowModelHash = hash
            break
        else
            print(("^3[ov_cattletransport] Testando modelo '%s' -> inválido, tentando o próximo...^7"):format(name))
        end
    end

    if not cowModelHash then
        print("^1[ov_cattletransport] Nenhum modelo de vaca da lista é válido nesta build. Missão cancelada.^7")
        VORPcore.NotifyRightTip("Erro: nenhum modelo de gado válido encontrado. Avise um admin.", 5000)
        missionActive = false
        TriggerServerEvent('ov_cattletransport:cancelMission')
        return
    end

    RequestModel(cowModelHash)
    local tries = 0
    while not HasModelLoaded(cowModelHash) and tries < 200 do
        Wait(10)
        tries = tries + 1
    end

    if not HasModelLoaded(cowModelHash) then
        print("^1[ov_cattletransport] O modelo de vaca não carregou a tempo. Missão cancelada.^7")
        VORPcore.NotifyRightTip("Erro ao carregar o gado. Tente novamente.", 5000)
        missionActive = false
        TriggerServerEvent('ov_cattletransport:cancelMission')
        return
    end

    for i = 1, Config.CowCount do
        local angle = math.random() * 6.28
        local dist = math.random(2, math.floor(Config.SpawnRadius))
        local x = Config.StartPoint.coords.x + math.cos(angle) * dist
        local y = Config.StartPoint.coords.y + math.sin(angle) * dist
        local z = Config.StartPoint.coords.z

        -- Acha a altura real do chão nesse ponto (o terreno pode variar
        -- dentro do raio de spawn), pra vaca não nascer enterrada ou flutuando.
        local pcallOk, foundGround, groundZ = pcall(GetGroundZFor_3dCoord, x, y, z + 50.0, false)
        if pcallOk and foundGround and groundZ and groundZ ~= 0.0 then
            z = groundZ
        end

        local cow = CreatePed(cowModelHash, x, y, z, 0.0, true, true)

        if not cow or cow == 0 or not DoesEntityExist(cow) then
            print(("^1[ov_cattletransport] Falha ao criar vaca #%d em (%.2f, %.2f, %.2f) [ground ajustado: %s] - handle: %s^7"):format(i, x, y, z, tostring(pcallOk and foundGround), tostring(cow)))
        else
            print(("^2[ov_cattletransport] Vaca #%d criada OK (handle %s) em (%.2f, %.2f, %.2f) [ground ajustado: %s]^7"):format(i, tostring(cow), x, y, z, tostring(pcallOk and foundGround)))
            SetEntityAsMissionEntity(cow, true, true)
            SetBlockingOfNonTemporaryEvents(cow, true)
            SetPedCanBeTargetted(cow, false)

            -- Alguns modelos de animal nascem "invisíveis" sem alpha/variação definidos.
            pcall(SetEntityVisible, cow, true, false)
            pcall(SetEntityAlpha, cow, 255, false)
            pcall(ResetEntityAlpha, cow)
            pcall(SetPedComponentVariation, cow, 0, 0, 0, 0)
            pcall(SetPedRandomComponentVariation, cow, 0)

            -- Posição fixa dessa vaca na formação, sorteada uma única vez.
            herdOffsets[cow] = {
                x = (math.random() - 0.5) * Config.Herd.formationRadius * 2,
                y = (math.random() - 0.5) * Config.Herd.formationRadius * 2,
            }
        end

        table.insert(spawnedCows, cow)
    end

    -- Âncora da manada começa no meio do ponto de spawn.
    herdAnchor = Config.StartPoint.coords

    SetModelAsNoLongerNeeded(cowModelHash)

    deliveryBlip = CreateWorldBlip(Config.DeliveryPoint.coords)
    if deliveryBlip then
        pcall(SetBlipSprite, deliveryBlip, Config.DeliveryPoint.blip.sprite, true)
        pcall(SetBlipScale, deliveryBlip, Config.DeliveryPoint.blip.scale)
        pcall(SetBlipAsShortRange, deliveryBlip, false)
        pcall(SetBlipRoute, deliveryBlip, true)
        pcall(SetBlipName, deliveryBlip, Config.DeliveryPoint.blip.label)
    end

    -- Loop de manada: a "âncora" avança quando você (a cavalo) chega
    -- perto por trás - direção recalculada a cada atualização, sem
    -- travar, então se você vier mais de um lado a manada desvia pro
    -- outro. Todas as vacas são sempre mandadas pra sua posição fixa em
    -- relação à âncora, na MESMA velocidade - por isso ficam compactas,
    -- na mesma direção e no mesmo ritmo, como um bloco só.
    CreateThread(function()
        while missionActive do
            Wait(Config.Herd.checkInterval)

            if herdAnchor then
                local sprinting = GetGameTimer() < sprintUntil
                local speed = sprinting and Config.Herd.sprintSpeed or Config.Herd.walkSpeed
                local stepDistance = sprinting and Config.Herd.sprintStepDistance or Config.Herd.walkStepDistance

                local playerCoords = GetEntityCoords(PlayerPedId())
                local dist = #(playerCoords - herdAnchor)

                -- Durante a disparada, a manada corre mesmo sem você por perto
                -- (ela já está assustada); fora disso, só anda se você chegar perto.
                if sprinting or dist < Config.Herd.pushRange then
                    local dir = herdAnchor - playerCoords
                    local len = #dir
                    local dirX, dirY
                    if len > 0.01 then
                        dirX, dirY = dir.x / len, dir.y / len
                    else
                        dirX, dirY = 0.0, 1.0
                    end

                    local newX = herdAnchor.x + dirX * stepDistance
                    local newY = herdAnchor.y + dirY * stepDistance
                    local newZ = herdAnchor.z

                    -- Reajusta a altura da âncora pro chão, já que ela "anda" pelo mapa.
                    local pcallOk, foundGround, groundZ = pcall(GetGroundZFor_3dCoord, newX, newY, newZ + 50.0, false)
                    if pcallOk and foundGround and groundZ and groundZ ~= 0.0 then
                        newZ = groundZ
                    end

                    herdAnchor = vector3(newX, newY, newZ)
                end

                for _, cow in ipairs(spawnedCows) do
                    if DoesEntityExist(cow) and not IsEntityDead(cow) then
                        local offset = herdOffsets[cow] or { x = 0.0, y = 0.0 }
                        MoveCowTo(cow, herdAnchor.x + offset.x, herdAnchor.y + offset.y, herdAnchor.z, speed)
                    end
                end
            end
        end
    end)

    -- Loop de verificação: as vacas chegaram no destino?
    CreateThread(function()
        while missionActive do
            Wait(Config.CheckInterval)

            local deliveredCount = 0
            local aliveCount = 0

            for _, cow in ipairs(spawnedCows) do
                if DoesEntityExist(cow) and not IsEntityDead(cow) then
                    aliveCount = aliveCount + 1
                    local cowCoords = GetEntityCoords(cow)
                    local distToDelivery = #(cowCoords - Config.DeliveryPoint.coords)
                    if distToDelivery <= Config.DeliveryPoint.radius then
                        deliveredCount = deliveredCount + 1
                    end
                end
            end

            if aliveCount == 0 then
                -- todas as vacas morreram: cancela a missão
                VORPcore.NotifyRightTip("Todas as vacas morreram. Missão cancelada.", 5000)
                missionActive = false
                RemoveWorldBlip(deliveryBlip)
                TriggerServerEvent('ov_cattletransport:cancelMission')

            elseif deliveredCount > 0 and deliveredCount >= aliveCount then
                -- todas as vacas vivas chegaram ao destino
                missionActive = false
                RemoveWorldBlip(deliveryBlip)

                for _, cow in ipairs(spawnedCows) do
                    if DoesEntityExist(cow) then
                        SetEntityAsMissionEntity(cow, false, true)
                        DeleteEntity(cow)
                    end
                end

                TriggerServerEvent('ov_cattletransport:completeMission', deliveredCount)
            end
        end
    end)
end)

-- Limpa as entidades caso o resource seja parado com a missão em andamento
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    for _, cow in ipairs(spawnedCows) do
        if DoesEntityExist(cow) then
            DeleteEntity(cow)
        end
    end
end)