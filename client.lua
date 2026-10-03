local Core = exports.vorp_core:GetCore()
local Menu = exports.vorp_menu:GetMenuData()
-- várias natives do RedM devolvem 0/1 em vez de false/true, e em Lua o 0 é VERDADEIRO
local function Bool(v) return v == true or v == 1 end

local STYLE_DEFAULT = 1664425300

-- estado do transporte
local mission = nil        -- dados do servidor (id, dest, cowCount, leader, members)
local members = {}
local cowNets = {}
local cowBlips = {}        -- [net] = blip
local destBlip = nil
local lastDeliver = 0

-- estado da manada (só no cliente do líder)
local isLeader = false
local herdCows = {}        -- handles das vacas
local herdOffsets = {}     -- [cow] = { x, y } posição fixa na formação
local herdAnchor = nil
local herdHeading = nil    -- { x, y } rumo da manada (vetor unitário)
local lastOrder = {}       -- [vaca] = { pos, speed } última ordem dada (evita reordenar à toa)
local herdDebug = nil      -- { x, y, z, hx, hy, mode, turn } (desenhado no jogo)
local debugOn = Config.HerdDebug and Config.HerdDebug.enabled or false
local herdGear = 1         -- marcha atual (1 caminhando, 2 trotando)

local function Notify(msg, ms)
    Core.NotifyRightTip(msg, ms or 4000)
end

local function LoadModel(model)
    local hash = joaat(model)
    if not IsModelValid(hash) then
        print(("^1[ov_estradadaboiada] Modelo inválido: %s^7"):format(model))
        return nil
    end
    RequestModel(hash, false)
    local tries = 0
    while not HasModelLoaded(hash) and tries < 200 do Wait(10) tries = tries + 1 end
    return HasModelLoaded(hash) and hash or nil
end

-- procura o chão logo acima primeiro (nas cidades, de muito alto pega o telhado)
local function GroundZ(x, y, z)
    for _, offset in ipairs({ 3.0, 50.0 }) do
        local ok, found, gz = pcall(GetGroundZFor_3dCoord, x, y, z + offset, false)
        if ok and found and gz and gz ~= 0.0 then return gz end
    end
    return z
end

-- rota GPS até um ponto (no RedM não existe SetBlipRoute)
local function GpsRoute(to)
    pcall(ClearGpsMultiRoute)
    if not to then return end
    StartGpsMultiRoute(joaat("COLOR_YELLOW"), true, true)
    AddPointToGpsMultiRoute(to.x, to.y, to.z, false)
    SetGpsMultiRouteRender(true)
end

local function RemoveBlipSafe(blip)
    if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
    return nil
end

local function EntFromNet(net)
    if not net or not Bool(NetworkDoesNetworkIdExist(net)) then return nil end
    local ent = NetworkGetEntityFromNetworkId(net)
    if ent and ent ~= 0 and DoesEntityExist(ent) then return ent end
end

-- posição do membro do grupo mais perto de um ponto (quem "toca" a manada)
local function ClosestMemberCoords(point)
    local best, bestDist = nil, math.huge
    for _, serverId in ipairs(members) do
        local player = GetPlayerFromServerId(serverId)
        if player and player ~= -1 then
            local ped = GetPlayerPed(player)
            if ped and ped ~= 0 and DoesEntityExist(ped) then
                local c = GetEntityCoords(ped)
                local d = #(c - point)
                if d < bestDist then best, bestDist = c, d end
            end
        end
    end
    return best or GetEntityCoords(PlayerPedId())
end

-- navegação com desvio de obstáculos; linha reta só se a native não existir
local function MoveCowTo(cow, x, y, z, speed)
    if pcall(TaskGoToCoordAnyMeans, cow, x, y, z, speed, 0, false, 786603, 0.0) then return end
    pcall(TaskGoStraightToCoord, cow, x, y, z, speed, 5000, 0.0, 0.0)
end

-- =========================================================
-- Capataz: NPC + blip + prompt
-- =========================================================
local npcs = {}            -- [curral] = ped
local prompt, promptGroup = 0, GetRandomIntInRange(0, 0xffffff)
local deliverPrompt, deliverGroup = 0, GetRandomIntInRange(0, 0xffffff)
local menuOpen = false

local function MakePrompt(group, text)
    local p = UiPromptRegisterBegin()
    UiPromptSetControlAction(p, Config.Prompt.key)
    UiPromptSetText(p, VarString(10, 'LITERAL_STRING', text))
    UiPromptSetEnabled(p, true)
    UiPromptSetVisible(p, true)
    UiPromptSetStandardMode(p, true)
    UiPromptSetGroup(p, group, 0)
    UiPromptRegisterEnd(p)
    return p
end

local function SpawnNpc(i)
    local pos = Config.Corrals[i].npc
    local hash = LoadModel(Config.NpcModel)
    if not hash then return end
    local ped = CreatePed(hash, pos.x, pos.y, GroundZ(pos.x, pos.y, pos.z), pos.w, false, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    if not ped or ped == 0 then return end
    SetRandomOutfitVariation(ped, true)
    PlaceEntityOnGroundProperly(ped)
    SetEntityCanBeDamaged(ped, false)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    FreezeEntityPosition(ped, true)
    npcs[i] = ped
end

CreateThread(function()
    repeat Wait(1000) until LocalPlayer.state.IsInSession

    prompt = MakePrompt(promptGroup, Config.Prompt.text)
    deliverPrompt = MakePrompt(deliverGroup, "Entregar o gado")

    for _, corral in ipairs(Config.Corrals) do
        local blip = BlipAddForCoords(STYLE_DEFAULT, corral.coords.x, corral.coords.y, corral.coords.z)
        SetBlipSprite(blip, Config.Blip.sprite, true)
        SetBlipName(blip, ("%s - %s"):format(Config.Blip.name, corral.name))
    end

    while true do
        local sleep = 1000
        local ped = PlayerPedId()
        local me = GetEntityCoords(ped)
        local near = nil

        for i, corral in ipairs(Config.Corrals) do
            local dist = #(me - vector3(corral.npc.x, corral.npc.y, corral.npc.z))
            if dist < Config.NpcSpawnDistance then
                if not npcs[i] then SpawnNpc(i) end
            elseif npcs[i] then
                DeleteEntity(npcs[i])
                npcs[i] = nil
            end
            if dist <= Config.Prompt.distance then near = i end
        end

        if not near then menuOpen = false end

        if near and not menuOpen and not Bool(IsEntityDead(ped)) then
            sleep = 0
            local title = ("%s - %s"):format(Config.Prompt.title, Config.Corrals[near].name)
            UiPromptSetActiveGroupThisFrame(promptGroup, VarString(10, 'LITERAL_STRING', title), 0, 0, 0, 0)
            if UiPromptHasStandardModeCompleted(prompt, 0) then
                TriggerServerEvent('ov_boiada:openMenu', near)
                Wait(500)
            end
        end

        Wait(sleep)
    end
end)

-- =========================================================
-- Menu: destino -> quantidade (ou cancelar)
-- =========================================================
local function CloseMenu(menu)
    menu.close(true, true, true)
    menuOpen = false
end

local OpenDestinationMenu

local function OpenCowCountMenu(fromIndex, destIndex, cooldownLeft)
    local dest = Config.Corrals[destIndex]
    local price = Config.PricePerCow(fromIndex, destIndex)
    local elements = {}
    for count = Config.CowCountMin, Config.CowCountMax, Config.CowCountStep do
        local total = count * price
        elements[#elements + 1] = {
            label = ("%d cabeças de gado"):format(count),
            value = count,
            desc = ("Se todas chegarem vivas: $%.2f<br>Em grupo o total aumenta %d%% por vaqueiro extra."):format(total, Config.Group.bonusPerMember * 100),
            descPrice = { amount = total, icon = "money", text = "Total estimado" },
        }
    end

    Menu.Open('default', GetCurrentResourceName(), 'ov_boiada_count',
        { title = "Transporte de Gado", subtext = ("%s - $%.2f por cabeça"):format(dest.name, price),
          align = "top-left", elements = elements, maxVisibleItems = 6, hideRadar = true, soundOpen = true },
        function(data, menu)
            CloseMenu(menu)
            TriggerServerEvent('ov_boiada:start', fromIndex, destIndex, data.current.value)
        end,
        function(_, menu)
            menu.close(false, true, false)
            OpenDestinationMenu(fromIndex, cooldownLeft)
        end)
    menuOpen = true
end

OpenDestinationMenu = function(fromIndex, cooldownLeft)
    local elements = {}
    for i, dest in ipairs(Config.Corrals) do
        if Config.ValidRoute(fromIndex, i) then
            elements[#elements + 1] = {
                label = dest.name,
                value = i,
                desc = ("Distância aproximada: %.1f km<br>Tempo limite: %d min%s"):format(Config.Distance(fromIndex, i) / 1000,
                    Config.TimeLimit(fromIndex, i), cooldownLeft > 0 and ("<br><br>Disponível em %d min"):format(cooldownLeft) or ""),
                descPrice = { amount = Config.PricePerCow(fromIndex, i), icon = "money", text = "Por cabeça" },
            }
        end
    end
    table.sort(elements, function(a, b) return a.descPrice.amount < b.descPrice.amount end)
    if #elements == 0 then
        elements[1] = { label = "Nenhum comprador por perto", value = "none", desc = "Nenhum curral na distância certa daqui." }
    end

    Menu.Open('default', GetCurrentResourceName(), 'ov_boiada_dest',
        { title = "Transporte de Gado", subtext = ("Saindo de %s - escolha o destino"):format(Config.Corrals[fromIndex].name),
          align = "top-left", elements = elements, maxVisibleItems = 6, hideRadar = true, soundOpen = true },
        function(data, menu)
            if data.current.value == "none" then return CloseMenu(menu) end
            menu.close(false, true, false)
            OpenCowCountMenu(fromIndex, data.current.value, cooldownLeft)
        end,
        function(_, menu) CloseMenu(menu) end)
    menuOpen = true
end

RegisterNetEvent('ov_boiada:showMenu', function(fromIndex, hasMission, cooldownLeft)
    Menu.CloseAll()
    if hasMission then
        Menu.Open('default', GetCurrentResourceName(), 'ov_boiada_cancel',
            { title = "Transporte de Gado", subtext = "Você já está num transporte", align = "top-left",
              elements = {
                  { label = "Cancelar transporte", value = "cancel", desc = "As vacas são recolhidas e ninguém recebe nada." },
                  { label = "Continuar", value = "close" },
              }, hideRadar = true, soundOpen = true },
            function(data, menu)
                CloseMenu(menu)
                if data.current.value == "cancel" then TriggerServerEvent('ov_boiada:cancel') end
            end,
            function(_, menu) CloseMenu(menu) end)
        menuOpen = true
    else
        OpenDestinationMenu(fromIndex, cooldownLeft)
    end
end)

-- =========================================================
-- Estado do transporte (todos os membros)
-- =========================================================
local function Cleanup()
    destBlip = RemoveBlipSafe(destBlip)
    pcall(ClearGpsMultiRoute)
    for net, b in pairs(cowBlips) do cowBlips[net] = RemoveBlipSafe(b) end
    cowBlips = {}

    if isLeader then
        for _, cow in ipairs(herdCows) do
            if DoesEntityExist(cow) then
                SetEntityAsMissionEntity(cow, false, true)
                DeleteEntity(cow)
            end
        end
    end

    mission, members, cowNets = nil, {}, {}
    isLeader, herdCows, herdOffsets, herdAnchor, herdGear = false, {}, {}, nil, 1
    herdHeading, herdDebug = nil, nil
    lastOrder = {}
end

RegisterNetEvent('ov_boiada:joined', function(data)
    Cleanup()
    mission = data
    members = data.members
    isLeader = data.leader == GetPlayerServerId(PlayerId())

    local dest = Config.Corrals[data.dest]
    destBlip = BlipAddForCoords(STYLE_DEFAULT, dest.coords.x, dest.coords.y, dest.coords.z)
    SetBlipSprite(destBlip, joaat("blip_code_waypoint"), true)
    SetBlipName(destBlip, ("Entregar gado - %s"):format(dest.name))
    GpsRoute(dest.coords)

    Notify(("Leve %d cabeças de gado até %s. Chegue por trás da manada para tocá-la; [Q] troca a marcha (caminhar/trotar). (%d min)")
        :format(data.cowCount, dest.name, data.timeLimit), 8000)
    if #members > 1 then
        Notify(("Comitiva formada com %d vaqueiros."):format(#members), 5000)
    end
end)

RegisterNetEvent('ov_boiada:members', function(list) members = list end)
RegisterNetEvent('ov_boiada:cows', function(nets) cowNets = nets end)

RegisterNetEvent('ov_boiada:finish', function(message)
    if message then Notify(message, 7000) end
    Cleanup()
end)

-- =========================================================
-- Marchas [Q]: 1 = caminhando, 2 = trotando (todas iguais)
-- =========================================================
RegisterNetEvent('ov_boiada:setGear', function(g)
    herdGear = g
    local gear = Config.Herd.gears[g]
    if gear then Notify(gear.label, 2500) end
end)

RegisterKeyMapping('boiada_marcha', 'Boiada: trocar a marcha da manada', 'keyboard', Config.Herd.gearKey)
RegisterCommand('boiada_marcha', function()
    if not mission then return end
    TriggerServerEvent('ov_boiada:gear')
end, false)

-- =========================================================
-- Líder: soltar o gado
-- =========================================================
RegisterNetEvent('ov_boiada:spawnHerd', function(data)
    local hash = LoadModel(Config.CowModel)
    if not hash then
        TriggerServerEvent('ov_boiada:spawnFailed', data.id)
        return
    end

    local start = Config.Corrals[data.from].coords
    local nets = {}
    herdCows, herdOffsets = {}, {}

    for _ = 1, data.cowCount do
        local angle = math.random() * math.pi * 2
        local dist = math.random(2, math.floor(Config.SpawnRadius))
        local x, y = start.x + math.cos(angle) * dist, start.y + math.sin(angle) * dist
        local cow = CreatePed(hash, x, y, GroundZ(x, y, start.z), math.random(0, 359) + 0.0, true, true, false, false)

        if cow and cow ~= 0 then
            local tries = 0
            while not DoesEntityExist(cow) and tries < 50 do Wait(20) tries = tries + 1 end

            SetEntityAsMissionEntity(cow, true, true)
            SetBlockingOfNonTemporaryEvents(cow, true)
            -- gado treinado: não foge de susto nem dispara sozinho
            pcall(SetPedFleeAttributes, cow, 0, false)
            pcall(Citizen.InvokeNative, 0xAEB97D84CDF3C00B, cow, false) -- _SET_ANIMAL_IS_WILD: domesticado
            SetPedCanBeTargetted(cow, false)
            SetRandomOutfitVariation(cow, true)

            local net = NetworkGetNetworkIdFromEntity(cow)
            pcall(Citizen.InvokeNative, 0x407091CF6037118E, net) -- NETWORK_DISABLE_PROXIMITY_MIGRATION: o líder continua dono das vacas
            nets[#nets + 1] = net

            herdCows[#herdCows + 1] = cow
            herdOffsets[cow] = {
                x = (math.random() - 0.5) * Config.Herd.formationRadius * 2,
                y = (math.random() - 0.5) * Config.Herd.formationRadius * 2,
            }
        end
    end
    SetModelAsNoLongerNeeded(hash)

    if #herdCows == 0 then
        TriggerServerEvent('ov_boiada:spawnFailed', data.id)
        return
    end

    herdAnchor = start
    -- rumo inicial: na direção do curral de destino
    local dest = Config.Corrals[data.dest].coords
    local dx, dy = dest.x - start.x, dest.y - start.y
    local dl = math.sqrt(dx * dx + dy * dy)
    herdHeading = dl > 0.01 and { x = dx / dl, y = dy / dl } or { x = 0.0, y = 1.0 }
    TriggerServerEvent('ov_boiada:spawned', data.id, nets)
end)

-- =========================================================
-- Líder: loop da manada (âncora) + trava de segurança
-- =========================================================
-- centro de verdade da manada (média das vacas vivas)
local function HerdCenter()
    local sx, sy, sz, n = 0.0, 0.0, 0.0, 0
    for _, cow in ipairs(herdCows) do
        if DoesEntityExist(cow) and not Bool(IsEntityDead(cow)) then
            local c = GetEntityCoords(cow)
            sx, sy, sz, n = sx + c.x, sy + c.y, sz + c.z, n + 1
        end
    end
    if n == 0 then return nil end
    return vector3(sx / n, sy / n, sz / n)
end

-- só manda a vaca andar se o destino mudou de verdade (reordenar toda hora faz ela engasgar)
local function OrderCow(cow, target, speed, force)
    local last = lastOrder[cow]
    if not force and last and last.speed == speed and #(last.pos - target) < 1.0 then return end
    lastOrder[cow] = { pos = target, speed = speed }
    MoveCowTo(cow, target.x, target.y, target.z, speed)
end

CreateThread(function()
    while true do
        Wait(Config.Herd.checkInterval)

        if isLeader and herdAnchor then
            local H = Config.Herd
            local center = HerdCenter() or herdAnchor
            local pusher = ClosestMemberCoords(center)
            local dist = #(vector2(pusher.x, pusher.y) - vector2(center.x, center.y))
            local mode, turn, moving = "ninguém tocando", 0.0, false

            -- disparada anda sozinha; fora dela, só anda com alguém perto
            if dist < H.pushRange then
                moving = true
                local fx, fy = herdHeading.x, herdHeading.y
                local rx, ry = pusher.x - center.x, pusher.y - center.y
                local len = math.sqrt(rx * rx + ry * ry)
                if len > 0.01 then
                    -- onde quem toca está em relação ao RUMO (medido do CENTRO das vacas):
                    -- -1 atrás, 0 lado, 1 frente
                    local nx, ny = rx / len, ry / len
                    local along = nx * fx + ny * fy
                    local rate
                    if along < H.rearCone then rate, mode = H.turnRear, "por trás"
                    elseif along < H.frontCone then rate, mode = H.turnSide, "pela lateral"
                    else rate, mode = H.turnFront, "pela frente" end
                    -- a manada quer ir pra LONGE de quem toca; o rumo vira até 'rate' graus nessa direção
                    local cur = math.deg(math.atan(fy, fx))
                    local want = math.deg(math.atan(-ny, -nx))
                    local diff = ((want - cur + 540) % 360) - 180
                    turn = math.max(-rate, math.min(rate, diff))
                    local r = math.rad(turn)
                    fx, fy = fx * math.cos(r) - fy * math.sin(r), fx * math.sin(r) + fy * math.cos(r)
                    local fl = math.sqrt(fx * fx + fy * fy)
                    herdHeading = { x = fx / fl, y = fy / fl }
                end
            end

            -- velocidade: a da marcha [Q], IGUAL pra todas as vacas.
            -- A âncora fica SEMPRE um pouco à frente do centro das vacas (não dispara sozinha).
            local gear = H.gears[herdGear] or H.gears[1]
            local speed, lead = gear.speed, moving and gear.lead or 0.0
            local ax, ay = center.x + herdHeading.x * lead, center.y + herdHeading.y * lead
            herdAnchor = vector3(ax, ay, GroundZ(ax, ay, center.z))

            if moving then
                for _, cow in ipairs(herdCows) do
                    if DoesEntityExist(cow) and not Bool(IsEntityDead(cow)) then
                        local o = herdOffsets[cow]
                        OrderCow(cow, vector3(herdAnchor.x + o.x, herdAnchor.y + o.y, herdAnchor.z), speed)
                    end
                end
            end

            -- debug: o líder calcula e manda pros outros do grupo verem também
            herdDebug = {
                x = center.x, y = center.y, z = center.z, hx = herdHeading.x, hy = herdHeading.y,
                mode = mode, turn = turn, px = pusher.x, py = pusher.y, pz = pusher.z, moving = moving, gear = herdGear,
            }
            if debugOn and mission and #members > 1 then
                TriggerServerEvent('ov_boiada:debug', mission.id, herdDebug)
            end
        end
    end
end)

-- trava de segurança: vaca que se afastou do CENTRO da manada volta trotando
CreateThread(function()
    while true do
        Wait(Config.Herd.leashCheckInterval)

        if isLeader and herdAnchor then
            local center = HerdCenter()
            for _, cow in ipairs(herdCows) do
                if center and DoesEntityExist(cow) and not Bool(IsEntityDead(cow))
                    and #(GetEntityCoords(cow) - center) > Config.Herd.leashDistance then
                    local o = herdOffsets[cow]
                    -- volta na MESMA velocidade das outras (correr assusta a manada)
                    local gear = Config.Herd.gears[herdGear] or Config.Herd.gears[1]
                    OrderCow(cow, vector3(herdAnchor.x + o.x, herdAnchor.y + o.y, herdAnchor.z), gear.speed, true)
                end
            end
        end
    end
end)

-- =========================================================
-- Todos: blips nas vacas + entrega
-- =========================================================
local function CountCows(dest)
    local alive, inside, insideNets = 0, 0, {}
    for _, net in ipairs(cowNets) do
        local cow = EntFromNet(net)
        if cow and not Bool(IsEntityDead(cow)) then
            alive = alive + 1
            if #(GetEntityCoords(cow) - dest.coords) <= Config.CorralRadius then
                inside = inside + 1
                insideNets[#insideNets + 1] = net
            end
        end
    end
    return alive, inside, insideNets
end

CreateThread(function()
    while true do
        local sleep = 1000

        if mission and #cowNets > 0 then
            local dest = Config.Corrals[mission.dest]

            -- blips das vacas (some quando a vaca morre)
            if Config.CowBlips then
                for _, net in ipairs(cowNets) do
                    local cow = EntFromNet(net)
                    local blip = cowBlips[net]
                    if cow and not Bool(IsEntityDead(cow)) then
                        if not (blip and DoesBlipExist(blip)) then
                            cowBlips[net] = BlipAddForEntity(joaat("BLIP_STYLE_FRIENDLY"), cow)
                        end
                    elseif blip then
                        cowBlips[net] = RemoveBlipSafe(blip)
                    end
                end
            end

            local alive, inside, insideNets = CountCows(dest)

            -- líder: todas mortas = falhou
            if isLeader and #herdCows > 0 and alive == 0 then
                local anyExists = false
                for _, cow in ipairs(herdCows) do
                    if DoesEntityExist(cow) then anyExists = true break end
                end
                if anyExists then TriggerServerEvent('ov_boiada:allDead', mission.id) end
            end

            -- todas as vivas no curral: entrega automática (só o líder, que
            -- enxerga todas as vacas; os outros podem ver só parte delas)
            if isLeader and alive > 0 and inside == alive and GetGameTimer() - lastDeliver > 5000 then
                lastDeliver = GetGameTimer()
                TriggerServerEvent('ov_boiada:deliver', mission.id, insideNets)

            -- algumas no curral: prompt para entregar só essas
            elseif inside > 0 and #(GetEntityCoords(PlayerPedId()) - dest.coords) <= Config.CorralRadius + 10.0 then
                sleep = 0
                local title = ("Curral de %s: %d de %d vaca(s)"):format(dest.name, inside, alive)
                UiPromptSetActiveGroupThisFrame(deliverGroup, VarString(10, 'LITERAL_STRING', title), 0, 0, 0, 0)
                if UiPromptHasStandardModeCompleted(deliverPrompt, 0) and GetGameTimer() - lastDeliver > 3000 then
                    lastDeliver = GetGameTimer()
                    TriggerServerEvent('ov_boiada:deliver', mission.id, insideNets)
                end
            end
        end

        Wait(sleep)
    end
end)

-- =========================================================
-- DEBUG no jogo: como a manada "pensa"
-- =========================================================
RegisterNetEvent('ov_boiada:debugState', function(d) if not isLeader then herdDebug = d end end)

RegisterCommand('boiada_debug', function()
    debugOn = not debugOn
    Notify(debugOn and "Debug da manada LIGADO." or "Debug da manada desligado.", 3000)
end, false)

local MARKER_CYLINDER = 0x94FDAE17
local function Disc(x, y, z, radius, r, g, b, a)
    Citizen.InvokeNative(0x2A32FAA57B937173, MARKER_CYLINDER, x, y, z - 0.25, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        radius * 2.0, radius * 2.0, 0.35, r, g, b, a, false, false, 2, false, nil, nil, false) -- _DRAW_MARKER
end

local function Text3D(x, y, z, text)
    local ok, sx, sy = GetScreenCoordFromWorldCoord(x, y, z)
    if not ok then return end
    BgSetTextScale(0.32, 0.32)
    BgSetTextColor(255, 255, 255, 230)
    -- centraliza "na mão" (~0,0055 da tela por letra nessa escala)
    BgDisplayText(VarString(10, "LITERAL_STRING", text), sx - #text * 0.0028, sy)
end

CreateThread(function()
    while true do
        local d = herdDebug
        if debugOn and mission and d then
            local HD = Config.HerdDebug
            -- verde: área da manada
            Disc(d.x, d.y, d.z, HD.herdRadius, 40, 220, 80, 70)
            -- azul: rumo (pontinhos) e o próximo ponto aonde ela vai
            for k = 1, 5 do
                local f = HD.lookAhead * k / 6
                local px, py = d.x + d.hx * f, d.y + d.hy * f
                Disc(px, py, GroundZ(px, py, d.z), 0.25, 60, 140, 255, 180)
            end
            local tx, ty = d.x + d.hx * HD.lookAhead, d.y + d.hy * HD.lookAhead
            Disc(tx, ty, GroundZ(tx, ty, d.z), 1.2, 60, 140, 255, 120)
            Text3D(d.x, d.y, d.z + 2.5, ("Manada: %s | marcha %d"):format(d.mode or "?", d.gear or 1))
            -- vermelho: onde está quem toca + quanto e pra que lado a manada vai virar
            if d.px then
                Disc(d.px, d.py, GroundZ(d.px, d.py, d.pz), 1.0, 230, 50, 50, 150)
                local t = d.turn or 0
                local side = math.abs(t) < 0.5 and "segue reto" or ("vira %.0f° p/ %s"):format(math.abs(t), t > 0 and "esquerda" or "direita")
                Text3D(d.px, d.py, d.pz + 1.2, d.moving and side or "longe demais: manada parada")
            end
            Wait(0)
        else
            Wait(500)
        end
    end
end)

-- =========================================================
-- /mycoords: imprime sua posição (para ajustar configs)
-- =========================================================
RegisterCommand('mycoords', function()
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    local msg = ("vector3(%.2f, %.2f, %.2f) | heading: %.1f"):format(c.x, c.y, c.z, GetEntityHeading(ped))
    print(("[mycoords] %s"):format(msg))
    TriggerEvent('chat:addMessage', { args = { "Coords", msg } })
end, false)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, p in pairs(npcs) do if DoesEntityExist(p) then DeleteEntity(p) end end
    if prompt ~= 0 then UiPromptDelete(prompt) end
    if deliverPrompt ~= 0 then UiPromptDelete(deliverPrompt) end
    Cleanup()
end)
