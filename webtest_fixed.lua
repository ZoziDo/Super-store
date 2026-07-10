-- ============================================================
-- ВРЕМЕННЫЙ СКРИПТ ВЫДАЧИ ПРЕДМЕТОВ ЧЕРЕЗ СУНДУК
-- Решает проблему с NBT-предметами (заряд, enchant и т.д.)
-- ============================================================

local component = require("component")
local event = require("event")
local gpu = component.gpu
local unicode = require("unicode")
local serialization = require("serialization")

-- Настройки
CHEST_SLOTS = 27  -- 27 для обычного сундука, 54 для двойного
PIM_SLOTS = 36    -- слоты игрока
PUSH_DIRECTION = "down"
PULL_DIRECTION = "up"

-- ============================================================
-- ПОИСК УСТРОЙСТВ
-- ============================================================

function findChest()
    -- Ищем любой инвентарь
    for addr in component.list("inventory") do
        local inv = component.proxy(addr)
        if inv and inv.getInventorySize and inv.getInventorySize() > 0 then
            writeDebugLog("✅ Найден сундук: " .. addr)
            return inv, addr
        end
    end
    
    -- Ищем конкретные типы сундуков
    local chestTypes = {
        "minecraft:chest", 
        "minecraft:trapped_chest",
        "minecraft:ender_chest",
        "minecraft:barrel",
        "minecraft:shulker_box"
    }
    
    for _, typeName in ipairs(chestTypes) do
        for addr in component.list(typeName) do
            local chest = component.proxy(addr)
            if chest then
                writeDebugLog("✅ Найден сундук: " .. typeName)
                return chest, addr
            end
        end
    end
    
    print("❌ Сундук не найден!")
    return nil, nil
end

function findPIM()
    for addr in component.list("pim") do
        return addr
    end
    return nil
end

function findME()
    for addr in component.list("me_interface") do
        return component.proxy(addr)
    end
    return nil
end

-- ============================================================
-- РАБОТА С ИНВЕНТАРЁМ
-- ============================================================

function getPIMInventory()
    local pimAddr = findPIM()
    if not pimAddr then return {} end
    
    local inventory = {}
    for slot = 1, PIM_SLOTS do
        local stack = component.invoke(pimAddr, "getStackInSlot", slot)
        if stack and (stack.size or stack.qty or 0) > 0 then
            table.insert(inventory, {
                slot = slot,
                name = stack.name or "unknown",
                damage = stack.damage or 0,
                size = stack.size or stack.qty or 0,
                nbt = stack.nbt or stack.tag or nil,
                displayName = stack.displayName or stack.label or stack.name or "?"
            })
        end
    end
    return inventory
end

function getChestInventory(chest)
    if not chest then return {} end
    
    local size = chest.getInventorySize and chest.getInventorySize() or CHEST_SLOTS
    local inventory = {}
    
    for slot = 1, size do
        local stack = chest.getStackInSlot and chest.getStackInSlot(slot)
        if stack and (stack.size or stack.qty or 0) > 0 then
            table.insert(inventory, {
                slot = slot,
                name = stack.name or "unknown",
                damage = stack.damage or 0,
                size = stack.size or stack.qty or 0,
                nbt = stack.nbt or stack.tag or nil,
                displayName = stack.displayName or stack.label or stack.name or "?"
            })
        end
    end
    return inventory
end

function moveFromChestToPIM(chest, chestSlot, amount)
    local pimAddr = findPIM()
    if not pimAddr then return 0 end
    
    -- Ищем свободный слот в PIM
    local targetSlot = nil
    for slot = 1, PIM_SLOTS do
        local stack = component.invoke(pimAddr, "getStackInSlot", slot)
        if not stack or (stack.size or stack.qty or 0) == 0 then
            targetSlot = slot
            break
        end
    end
    
    if not targetSlot then
        print("⚠️ Нет свободных слотов в инвентаре!")
        return 0
    end
    
    -- Перемещаем из сундука в PIM
    local moved = 0
    if chest.pushItem then
        moved = chest.pushItem(PULL_DIRECTION, chestSlot, amount)
    elseif chest.moveItem then
        moved = chest.moveItem(chestSlot, "pim", targetSlot, amount)
    else
        print("❌ Не удаётся переместить предмет!")
        return 0
    end
    
    return moved
end

function moveFromPIMToChest(pimSlot, amount)
    local pimAddr = findPIM()
    if not pimAddr then return 0 end
    
    local chest, chestAddr = findChest()
    if not chest then return 0 end
    
    -- Ищем свободный слот в сундуке
    local chestSize = chest.getInventorySize and chest.getInventorySize() or CHEST_SLOTS
    local targetSlot = nil
    for slot = 1, chestSize do
        local stack = chest.getStackInSlot and chest.getStackInSlot(slot)
        if not stack or (stack.size or stack.qty or 0) == 0 then
            targetSlot = slot
            break
        end
    end
    
    if not targetSlot then
        print("⚠️ Сундук полон!")
        return 0
    end
    
    -- Перемещаем из PIM в сундук
    local moved = component.invoke(pimAddr, "pushItem", PUSH_DIRECTION, pimSlot, amount)
    return moved
end

-- ============================================================
-- ОСНОВНЫЕ ФУНКЦИИ
-- ============================================================

function printInventory(title, inventory)
    print("\n📦 " .. title .. ":")
    print("═" .. string.rep("═", 50))
    
    if #inventory == 0 then
        print("   (пусто)")
        return
    end
    
    for _, item in ipairs(inventory) do
        local display = item.displayName or item.name or "?"
        local damage = item.damage or 0
        local hasNBT = item.nbt and " [NBT]" or ""
        print(string.format("   %2d. %s x%d (damage: %d)%s", 
            item.slot, 
            display, 
            item.size, 
            damage,
            hasNBT
        ))
    end
end

function showStatus()
    gpu.setBackground(0x0A0A0F)
    gpu.fill(1, 1, 80, 25, " ")
    
    gpu.setForeground(0x00E5C9)
    gpu.set(1, 1, "═" .. string.rep("═", 78))
    gpu.setForeground(0xFFFFFF)
    gpu.set(20, 2, "🔄 ВРЕМЕННЫЙ СКРИПТ ВЫДАЧИ ПРЕДМЕТОВ")
    gpu.setForeground(0x00E5C9)
    gpu.set(1, 3, "═" .. string.rep("═", 78))
    
    gpu.setForeground(0xAAAAAA)
    gpu.set(2, 5, "[1] Показать инвентарь PIM")
    gpu.set(2, 6, "[2] Показать содержимое сундука")
    gpu.set(2, 7, "[3] Переместить ВСЁ из сундука в PIM")
    gpu.set(2, 8, "[4] Переместить ВСЁ из PIM в сундук")
    gpu.set(2, 9, "[5] Выдать предмет из ME в сундук (с NBT)")
    gpu.set(2, 10, "[6] Выдать предмет из ME в PIM (прямая выдача)")
    gpu.set(2, 11, "[7] Очистить инвентарь PIM (всё в сундук)")
    gpu.set(2, 12, "[8] Очистить сундук (всё в ME)")
    gpu.set(2, 13, "[9] Проверить NBT-предметы в PIM")
    gpu.set(2, 14, "[0] Показать это меню")
    
    gpu.setForeground(0xFF4444)
    gpu.set(2, 16, "[Q] ВЫХОД")
    
    gpu.setForeground(0x00E5C9)
    gpu.set(1, 25, "═" .. string.rep("═", 78))
end

function clearPIMToChest()
    local pimAddr = findPIM()
    if not pimAddr then 
        print("❌ PIM не найден!")
        return 
    end
    
    local chest, chestAddr = findChest()
    if not chest then 
        print("❌ Сундук не найден!")
        return 
    end
    
    local moved = 0
    for slot = 1, PIM_SLOTS do
        local stack = component.invoke(pimAddr, "getStackInSlot", slot)
        if stack and (stack.size or stack.qty or 0) > 0 then
            local amount = stack.size or stack.qty or 0
            local result = component.invoke(pimAddr, "pushItem", PUSH_DIRECTION, slot, amount)
            if type(result) == "number" and result > 0 then
                moved = moved + result
            end
        end
    end
    
    print("✅ Перемещено " .. moved .. " предметов из PIM в сундук")
end

function clearChestToME()
    local chest, chestAddr = findChest()
    if not chest then 
        print("❌ Сундук не найден!")
        return 
    end
    
    local me = findME()
    if not me then
        print("❌ ME интерфейс не найден!")
        return
    end
    
    local chestSize = chest.getInventorySize and chest.getInventorySize() or CHEST_SLOTS
    local moved = 0
    
    for slot = 1, chestSize do
        local stack = chest.getStackInSlot and chest.getStackInSlot(slot)
        if stack and (stack.size or stack.qty or 0) > 0 then
            local name = stack.name or ""
            local damage = stack.damage or 0
            local amount = stack.size or stack.qty or 0
            
            local success, result = pcall(function()
                return me.importItem({id = name, dmg = damage}, "down", amount)
            end)
            
            if success and result then
                moved = moved + amount
            end
        end
    end
    
    print("✅ Перемещено " .. moved .. " предметов из сундука в ME")
end

function giveFromMEtoChest()
    print("\n📦 ВЫДАЧА ПРЕДМЕТА ИЗ ME В СУНДУК")
    print("Введите ID предмета (например: minecraft:diamond_sword):")
    
    local itemId = io.read()
    if not itemId or itemId == "" then
        print("❌ Отменено")
        return
    end
    
    print("Введите количество:")
    local qty = tonumber(io.read()) or 1
    
    print("Введите damage (0 если нет):")
    local damage = tonumber(io.read()) or 0
    
    local me = findME()
    if not me then
        print("❌ ME интерфейс не найден!")
        return
    end
    
    local chest, chestAddr = findChest()
    if not chest then 
        print("❌ Сундук не найден!")
        return 
    end
    
    -- Проверяем наличие предмета в ME
    local items = me.getItemsInNetwork()
    local available = 0
    for _, item in ipairs(items) do
        if item.name == itemId and (item.damage or 0) == damage then
            available = available + (item.size or 0)
        end
    end
    
    if available == 0 then
        print("❌ Предмет не найден в ME системе!")
        return
    end
    
    local toExtract = math.min(qty, available)
    print("📊 Доступно: " .. available .. ", будет выдано: " .. toExtract)
    
    -- Извлекаем из ME
    local fingerprint = { id = itemId, dmg = damage }
    local extracted = 0
    
    while extracted < toExtract do
        local toTake = math.min(toExtract - extracted, 64)
        local success, result = pcall(function()
            return me.exportItem(fingerprint, "down", toTake)
        end)
        
        if success and result then
            if type(result) == "number" then
                extracted = extracted + result
            elseif type(result) == "boolean" and result == true then
                extracted = extracted + toTake
            end
        else
            print("⚠️ Ошибка при извлечении: " .. tostring(result))
            break
        end
    end
    
    print("✅ Извлечено из ME: " .. extracted)
    
    -- Кладём в сундук (если есть что)
    if extracted > 0 then
        local chestSize = chest.getInventorySize and chest.getInventorySize() or CHEST_SLOTS
        local placed = 0
        
        for slot = 1, chestSize do
            if placed >= extracted then break end
            
            local stack = chest.getStackInSlot and chest.getStackInSlot(slot)
            if not stack or (stack.size or stack.qty or 0) == 0 then
                -- Создаём стак для сундука
                local stackData = {
                    id = itemId,
                    dmg = damage,
                    size = math.min(extracted - placed, 64)
                }
                -- Пытаемся положить
                local result = chest.setStackInSlot and chest.setStackInSlot(slot, stackData)
                if result then
                    placed = placed + (stackData.size or 0)
                end
            end
        end
        
        print("✅ Помещено в сундук: " .. placed)
        
        -- Если не всё поместилось, возвращаем в ME
        if placed < extracted then
            local returned = extracted - placed
            local success, result = pcall(function()
                return me.importItem(fingerprint, "down", returned)
            end)
            if success then
                print("↩️ Возвращено в ME: " .. returned)
            end
        end
    end
end

function giveFromMEtoPIM()
    print("\n📦 ВЫДАЧА ПРЕДМЕТА ИЗ ME В PIM (ПРЯМАЯ)")
    print("Введите ID предмета (например: minecraft:diamond_sword):")
    
    local itemId = io.read()
    if not itemId or itemId == "" then
        print("❌ Отменено")
        return
    end
    
    print("Введите количество:")
    local qty = tonumber(io.read()) or 1
    
    print("Введите damage (0 если нет):")
    local damage = tonumber(io.read()) or 0
    
    local me = findME()
    if not me then
        print("❌ ME интерфейс не найден!")
        return
    end
    
    local pimAddr = findPIM()
    if not pimAddr then
        print("❌ PIM не найден!")
        return
    end
    
    -- Проверяем место в PIM
    local freeSlots = 0
    for slot = 1, PIM_SLOTS do
        local stack = component.invoke(pimAddr, "getStackInSlot", slot)
        if not stack or (stack.size or stack.qty or 0) == 0 then
            freeSlots = freeSlots + 1
        end
    end
    
    if freeSlots == 0 then
        print("❌ Нет свободных слотов в PIM!")
        return
    end
    
    print("📊 Свободных слотов в PIM: " .. freeSlots)
    
    -- Извлекаем из ME
    local fingerprint = { id = itemId, dmg = damage }
    local extracted = 0
    
    while extracted < qty do
        if freeSlots <= 0 then
            print("⚠️ Закончились свободные слоты!")
            break
        end
        
        local toTake = math.min(qty - extracted, 64)
        local success, result = pcall(function()
            return me.exportItem(fingerprint, "down", toTake)
        end)
        
        if success and result then
            if type(result) == "number" then
                extracted = extracted + result
                freeSlots = freeSlots - 1
            elseif type(result) == "boolean" and result == true then
                extracted = extracted + toTake
                freeSlots = freeSlots - 1
            end
        else
            print("⚠️ Ошибка при извлечении: " .. tostring(result))
            break
        end
    end
    
    print("✅ Выдано в PIM: " .. extracted)
end

function checkNBTItems()
    local pimAddr = findPIM()
    if not pimAddr then
        print("❌ PIM не найден!")
        return
    end
    
    print("\n🔍 ПРОВЕРКА NBT-ПРЕДМЕТОВ В PIM")
    print("═" .. string.rep("═", 50))
    
    local found = 0
    for slot = 1, PIM_SLOTS do
        local stack = component.invoke(pimAddr, "getStackInSlot", slot)
        if stack and (stack.size or stack.qty or 0) > 0 then
            local hasNBT = stack.nbt or stack.tag
            if hasNBT then
                found = found + 1
                local name = stack.displayName or stack.label or stack.name or "?"
                local size = stack.size or stack.qty or 0
                local damage = stack.damage or 0
                print(string.format("   %2d. %s x%d (damage: %d) [ЕСТЬ NBT]",
                    slot, name, size, damage))
            end
        end
    end
    
    if found == 0 then
        print("✅ NBT-предметов не найдено")
    else
        print("\n⚠️ Найдено NBT-предметов: " .. found)
        print("   Эти предметы могут не выдаваться через PIM напрямую!")
        print("   Используйте функцию [5] для выдачи через сундук")
    end
end

-- ============================================================
-- ОСНОВНОЙ ЦИКЛ
-- ============================================================

function main()
    gpu.setResolution(80, 25)
    showStatus()
    
    print("\n🔄 Временный скрипт запущен")
    print("   Используйте цифровые клавиши для управления")
    
    while true do
        local ev = {event.pull(0.5)}
        
        if ev[1] == "key_down" then
            local key = ev[3]
            
            -- Цифровые клавиши
            if key == 49 then  -- 1
                local inv = getPIMInventory()
                printInventory("Инвентарь PIM", inv)
                
            elseif key == 50 then  -- 2
                local chest, addr = findChest()
                if chest then
                    local inv = getChestInventory(chest)
                    printInventory("Сундук (адрес: " .. addr .. ")", inv)
                end
                
            elseif key == 51 then  -- 3
                print("\n📦 Перемещение из сундука в PIM...")
                local chest, addr = findChest()
                if chest then
                    local inv = getChestInventory(chest)
                    local moved = 0
                    for _, item in ipairs(inv) do
                        local result = moveFromChestToPIM(chest, item.slot, item.size)
                        if result > 0 then
                            moved = moved + result
                        end
                    end
                    print("✅ Перемещено в PIM: " .. moved)
                end
                
            elseif key == 52 then  -- 4
                print("\n📦 Перемещение из PIM в сундук...")
                local inv = getPIMInventory()
                local moved = 0
                for _, item in ipairs(inv) do
                    local result = moveFromPIMToChest(item.slot, item.size)
                    if result > 0 then
                        moved = moved + result
                    end
                end
                print("✅ Перемещено в сундук: " .. moved)
                
            elseif key == 53 then  -- 5
                giveFromMEtoChest()
                
            elseif key == 54 then  -- 6
                giveFromMEtoPIM()
                
            elseif key == 55 then  -- 7
                clearPIMToChest()
                
            elseif key == 56 then  -- 8
                clearChestToME()
                
            elseif key == 57 then  -- 9
                checkNBTItems()
                
            elseif key == 48 then  -- 0
                showStatus()
                
            elseif key == 81 or key == 113 then  -- Q
                print("\n👋 Выход...")
                break
            end
            
            showStatus()
            
        elseif ev[1] == "touch" then
            -- Для удобства можно добавить обработку нажатий
            -- Но для простоты оставляем только клавиши
        end
    end
end

-- ============================================================
-- ЗАПУСК
-- ============================================================

-- Запускаем с защитой от ошибок
local ok, err = pcall(main)
if not ok then
    print("❌ Ошибка: " .. tostring(err))
    print(debug.traceback())
end
