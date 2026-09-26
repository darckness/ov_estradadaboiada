VORPcore = exports.vorp_core:GetCore()

local activeMissions = {}   -- [source] = { destinationKey = .., cowCount = .. } enquanto a missão está em andamento
local lastMissionTime = {}  -- [source] = os.time() da última missão concluída/cancelada

local function getCooldownRemaining(src)
    if Config.MissionCooldown <= 0 then return 0 end
    if not lastMissionTime[src] then return 0 end
    local elapsedMinutes = (os.time() - lastMissionTime[src]) / 60
    local remaining = Config.MissionCooldown - elapsedMinutes
    if remaining > 0 then
        return math.ceil(remaining)
    end
    return 0
end

RegisterNetEvent('ov_cattletransport:startMission', function(destinationKey, cowCount)
    local _source = source

    if activeMissions[_source] then
        TriggerClientEvent('vorp:TipRight', _source, "Você já está em uma missão de transporte de gado.", 4000)
        return
    end

    local remaining = getCooldownRemaining(_source)
    if remaining > 0 then
        TriggerClientEvent('vorp:TipRight', _source, ("Aguarde %d minuto(s) para iniciar outro transporte."):format(remaining), 4000)
        return
    end

    -- validação contra valores manipulados vindos do client (o menu já
    -- restringe isso, mas nunca confiamos só no client)
    local destination = Config.Destinations[destinationKey]
    if not destination then
        TriggerClientEvent('vorp:TipRight', _source, "Destino inválido.", 4000)
        return
    end

    cowCount = math.floor(tonumber(cowCount) or 0)
    if cowCount < Config.CowCountMin or cowCount > Config.CowCountMax then
        TriggerClientEvent('vorp:TipRight', _source, "Quantidade de gado inválida.", 4000)
        return
    end

    activeMissions[_source] = { destinationKey = destinationKey, cowCount = cowCount }
    TriggerClientEvent('ov_cattletransport:beginClient', _source, destinationKey, cowCount)
end)

RegisterNetEvent('ov_cattletransport:completeMission', function(deliveredCount)
    local _source = source
    local mission = activeMissions[_source]

    if not mission then return end

    local destination = Config.Destinations[mission.destinationKey]
    if not destination then
        activeMissions[_source] = nil
        return
    end

    -- validação básica contra valores manipulados vindos do client
    if type(deliveredCount) ~= "number" or deliveredCount <= 0 or deliveredCount > mission.cowCount then
        activeMissions[_source] = nil
        return
    end

    local user = VORPcore.getUser(_source)
    if not user then
        activeMissions[_source] = nil
        return
    end

    local character = user.getUsedCharacter
    local amount = math.floor(deliveredCount * destination.pricePerCow)

    -- currencyType 0 = dinheiro, 1 = ouro (conforme Config.Reward.currencyType)
    character.addCurrency(Config.Reward.currencyType, amount)

    TriggerClientEvent('vorp:TipRight', _source, ("Você recebeu $%d pela entrega de %d cabeça(s) de gado em %s."):format(amount, deliveredCount, destination.name), 5000)

    activeMissions[_source] = nil
    lastMissionTime[_source] = os.time()
end)

RegisterNetEvent('ov_cattletransport:cancelMission', function()
    local _source = source
    activeMissions[_source] = nil
    lastMissionTime[_source] = os.time()
end)

AddEventHandler('playerDropped', function()
    activeMissions[source] = nil
end)