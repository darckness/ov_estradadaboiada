VORPcore = exports.vorp_core:GetCore()

local activeMissions = {}   -- [source] = true enquanto a missão está em andamento
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

RegisterNetEvent('ov_estradadaboiada:startMission', function()
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

    activeMissions[_source] = true
    TriggerClientEvent('ov_estradadaboiada:beginClient', _source)
end)

RegisterNetEvent('ov_estradadaboiada:completeMission', function(deliveredCount)
    local _source = source

    if not activeMissions[_source] then return end

    -- validação básica contra valores manipulados vindos do client
    if type(deliveredCount) ~= "number" or deliveredCount <= 0 or deliveredCount > Config.CowCount then
        activeMissions[_source] = nil
        return
    end

    local user = VORPcore.getUser(_source)
    if not user then
        activeMissions[_source] = nil
        return
    end

    local character = user.getUsedCharacter
    local amount = math.floor(deliveredCount * Config.Reward.perCow)

    -- currencyType 0 = dinheiro, 1 = ouro (conforme Config.Reward.currencyType)
    character.addCurrency(Config.Reward.currencyType, amount)

    TriggerClientEvent('vorp:TipRight', _source, ("Você recebeu $%d pela entrega de %d cabeça(s) de gado."):format(amount, deliveredCount), 5000)

    activeMissions[_source] = nil
    lastMissionTime[_source] = os.time()
end)

RegisterNetEvent('ov_estradadaboiada:cancelMission', function()
    local _source = source
    activeMissions[_source] = nil
    lastMissionTime[_source] = os.time()
end)

AddEventHandler('playerDropped', function()
    activeMissions[source] = nil
end)
