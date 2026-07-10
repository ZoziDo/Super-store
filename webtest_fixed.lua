-- ============================================================
-- ТЕСТОВЫЙ СКРИПТ ВЫДАЧИ ЧЕРЕЗ СУНДУК
-- ============================================================

local component = require("component")
local event = require("event")
local serialization = require("serialization")

-- Настройки
CHEST_SLOTS = 27
PIM_SLOTS = 36

-- ============================================================
-- ПОИСК УСТРОЙСТВ
-- ============================================================

function findChest()
    for addr in component.list("inventory") do
        local inv = component.proxy(addr)
        if inv and inv.getInventorySize and inv.getInventorySize() > 0 then
            return inv, addr
        end
    end
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
-- ФУНКЦИИ ЛОГИРОВАНИЯ
-- ============================================================

function logItem(name, size, damage, nbt)
    local hasNBT = nbt and " [ЕСТЬ NBT]" or ""
    print(string.format("  📦 %s x%d (damage: %d)%s", name, size, damage, hasNBT))
end

function logPIM()
    local pimAddr = findPIM()
    if not pimAddr then 
        print("❌ PIM не найден!")
        return 
    end
    
    print("\n👤 ИНВЕНТАРЬ ИГРОКА (PIM):")
    print("═" .. string.rep("═", 50))
    
    local count = 0
    for slot = 1, PIM_SLOTS do
        local stack = component.invoke(pimAddr, "getStackInSlot", slot)
        if stack and (stack.size or stack.qty or 0) > 0 then
            count = count + 1
            local name = stack.displayName or stack.label or stack.name or "?"
            local size = stack.size or stack.qty or 0
            local damage = stack.damage or 0
            local nbt = stack.nbt or stack.tag
            print(string.format("  Слот %2d:", slot))
            logItem(name, size, damage, nbt)
        end
    end
    
    if count == 0 then
        print("  (пусто)")
    else
        print("\n  Всего предметов: " .. count)
    end
end

function logChest()
    local chest, addr = findChest()
    if not chest then 
        print("❌ Сундук не найден!")
        return 
    end
    
    print("\n📦 СУНДУК (адрес: " .. addr .. "):")
    print("═" .. string.rep("═", 50))
    
    local chestSize = chest.getInventorySize and chest.getInventorySize() or CHEST_SLOTS
    local count = 0
    
    for slot = 1, chestSize do
        local stack = chest.getStackInSlot and chest.getStackInSlot(slot)
        if stack and (stack.size or stack.qty or 0) > 0 then
            count = count + 1
            local name = stack.displayName or stack.label or stack.name or "?"
            local size = stack.size or stack.qty or 0
            local damage = stack.damage or 0
            local nbt = stack.nbt or stack.tag
            print(string.format("  Слот %2d:", slot))
            logItem(name, size, damage, nbt)
        end
    end
    
    if count == 0 then
        print("  (пусто)")
    else
        print("\n  Всего предметов: " .. count)
    end
end

function logME(itemId, damage)
    local me = findME()
    if not me then
        print("❌ ME интерфейс не найден!")
        return
    end
    
    print("\n💾 ME СИСТЕМА (предмет: " .. itemId .. "):")
    print("═" .. string.rep("═", 50))
    
    local items = me.getItemsInNetwork()
    local found = false
    
    for _, item in ipairs(items) do
        if item.name == itemId and (item.damage or 0) == (damage or 0) then
            found = true
            local name = item.displayName or item.label or item.name or "?"
            local size = item.size or 0
            local dmg = item.damage or 0
            local nbt = item.nbt or item.tag
            print("  Найден предмет:")
            logItem(name, size, dmg, nbt)
        end
    end
    
    if not found then
        print("  ❌ Предмет не найден в ME!")
    end
end

-- ============================================================
-- ОСНОВНЫЕ ФУНКЦИИ
-- ============================================================

function testGiveFromMEtoChest(itemId, qty, damage)
    print("\n🧪 ТЕСТ: ВЫДАЧА ИЗ ME В СУНДУК")
    print("═" .. string.rep("═", 50))
    print("  Предмет: " .. itemId)
    print("  Количество: " .. qty)
    print("  Damage: " .. (damage or 0))
    
    local me = findME()
    if not me then
        print("❌ ME не найден!")
        return false
    end
    
    local chest, chestAddr = findChest()
    if not chest then
        print("❌ Сундук не найден!")
        return false
    end
    
    -- Логируем что есть в ME
    logME(itemId, damage)
    
    -- Проверяем наличие в ME
    local items = me.getItemsInNetwork()
    local available = 0
    for _, item in ipairs(items) do
        if item.name == itemId and (item.damage or 0) == (damage or 0) then
            available = available + (item.size or 0)
        end
    end
    
    if available == 0 then
        print("❌ Нет предметов в ME!")
        return false
    end
    
    print("  ✅ Доступно в ME: " .. available)
    
    -- Извлекаем из ME
    local fingerprint = { id = itemId, dmg = damage or 0 }
    local extracted = 0
    local toExtract = math.min(qty, available)
    
    print("  ⏳ Извлечение из ME...")
    
    while extracted < toExtract do
        local toTake = math.min(toExtract - extracted, 64)
        local success, result = pcall(function()
            return me.exportItem(fingerprint, "down", toTake)
        end)
        
        if success and result then
            if type(result) == "number" then
                extracted = extracted + result
                print("  ✅ Извлечено: " .. result)
            elseif type(result) == "boolean" and result == true then
                extracted = extracted + toTake
                print("  ✅ Извлечено: " .. toTake)
            end
        else
            print("  ⚠️ Ошибка: " .. tostring(result))
            break
        end
    end
    
    print("  📊 Итого извлечено: " .. extracted)
    
    if extracted == 0 then
        print("❌ Не удалось извлечь предметы!")
        return false
    end
    
    -- Кладём в сундук
    print("  ⏳ Помещение в сундук...")
    
    local chestSize = chest.getInventorySize and chest.getInventorySize() or CHEST_SLOTS
    local placed = 0
    
    for slot = 1, chestSize do
        if placed >= extracted then break end
        
        local stack = chest.getStackInSlot and chest.getStackInSlot(slot)
        if not stack or (stack.size or stack.qty or 0) == 0 then
            local stackData = {
                id = itemId,
                dmg = damage or 0,
                size = math.min(extracted - placed, 64)
            }
            
            local result = chest.setStackInSlot and chest.setStackInSlot(slot, stackData)
            if result then
                local added = stackData.size or 0
                placed = placed + added
                print(string.format("  ✅ Помещено в слот %d: %d шт.", slot, added))
            end
        end
    end
    
    print("  📊 Итого помещено в сундук: " .. placed)
    
    -- Проверяем результат
    logChest()
    
    return placed > 0
end

function testGiveFromChestToPIM()
    print("\n🧪 ТЕСТ: ВЫДАЧА ИЗ СУНДУКА В PIM")
    print("═" .. string.rep("═", 50))
    
    local chest, chestAddr = findChest()
    if not chest then
        print("❌ Сундук не найден!")
        return false
    end
    
    local pimAddr = findPIM()
    if not pimAddr then
        print("❌ PIM не найден!")
        return false
    end
    
    -- Логируем сундук
    print("  📦 Содержимое сундука:")
    logChest()
    
    -- Логируем PIM до
    print("  👤 Инвентарь игрока ДО:")
    logPIM()
    
    -- Перемещаем всё из сундука в PIM
    print("  ⏳ Перемещение из сундука в PIM...")
    
    local chestSize = chest.getInventorySize and chest.getInventorySize() or CHEST_SLOTS
    local moved = 0
    
    for slot = 1, chestSize do
        local stack = chest.getStackInSlot and chest.getStackInSlot(slot)
        if stack and (stack.size or stack.qty or 0) > 0 then
            local amount = stack.size or stack.qty or 0
            
            -- Ищем свободный слот в PIM
            local targetSlot = nil
            for ps = 1, PIM_SLOTS do
                local pstack = component.invoke(pimAddr, "getStackInSlot", ps)
                if not pstack or (pstack.size or pstack.qty or 0) == 0 then
                    targetSlot = ps
                    break
                end
            end
            
            if not targetSlot then
                print("  ⚠️ Нет свободных слотов в PIM!")
                break
            end
            
            local result = 0
            if chest.pushItem then
                result = chest.pushItem("up", slot, amount)
            elseif chest.moveItem then
                result = chest.moveItem(slot, pimAddr, targetSlot, amount)
            end
            
            if type(result) == "number" and result > 0 then
                moved = moved + result
                local name = stack.displayName or stack.label or stack.name or "?"
                print(string.format("  ✅ Перемещено в слот %d: %s x%d", targetSlot, name, result))
            end
        end
    end
    
    print("  📊 Итого перемещено: " .. moved)
    
    -- Логируем PIM после
    print("  👤 Инвентарь игрока ПОСЛЕ:")
    logPIM()
    
    return moved > 0
end

-- ============================================================
-- ТЕСТОВЫЙ СЦЕНАРИЙ
-- ============================================================

function runTest()
    print("\n" .. string.rep("═", 50))
    print("🧪 ЗАПУСК ТЕСТА ВЫДАЧИ NBT-ПРЕДМЕТОВ")
    print(string.rep("═", 50))
    
    -- 1. Проверяем что есть в ME
    print("\n1️⃣ ПРОВЕРКА ME:")
    local me = findME()
    if me then
        local items = me.getItemsInNetwork()
        print("  Всего предметов в ME: " .. #items)
        for i, item in ipairs(items) do
            if i <= 10 then -- Показываем первые 10
                local name = item.displayName or item.label or item.name or "?"
                local size = item.size or 0
                local damage = item.damage or 0
                local hasNBT = (item.nbt or item.tag) and " [NBT]" or ""
                print(string.format("  %d. %s x%d (damage: %d)%s", i, name, size, damage, hasNBT))
            end
        end
        if #items > 10 then
            print("  ... и ещё " .. (#items - 10) .. " предметов")
        end
    else
        print("  ❌ ME не найден!")
        return
    end
    
    -- 2. Запрашиваем предмет для теста
    print("\n2️⃣ ВВЕДИТЕ ДАННЫЕ ДЛЯ ТЕСТА:")
    print("  (Можно использовать: minecraft:diamond_sword, minecraft:bow, minecraft:enchanted_book)")
    print("  ID предмета:")
    local itemId = io.read()
    if not itemId or itemId == "" then
        print("  ❌ Отменено")
        return
    end
    
    print("  Количество:")
    local qty = tonumber(io.read()) or 1
    
    print("  Damage (0 если нет):")
    local damage = tonumber(io.read()) or 0
    
    -- 3. Выдаём в сундук
    print("\n3️⃣ ВЫДАЧА В СУНДУК:")
    local ok = testGiveFromMEtoChest(itemId, qty, damage)
    
    if not ok then
        print("  ❌ Не удалось выдать в сундук!")
        return
    end
    
    -- 4. Выдаём из сундука в PIM
    print("\n4️⃣ ВЫДАЧА ИЗ СУНДУКА В PIM:")
    ok = testGiveFromChestToPIM()
    
    if ok then
        print("\n✅ ТЕСТ УСПЕШНО ЗАВЕРШЁН!")
        print("  Предметы выданы в инвентарь игрока через сундук.")
        print("  Проверьте NBT-данные у предметов в инвентаре.")
    else
        print("\n❌ ТЕСТ НЕ УДАЛСЯ!")
        print("  Проверьте логи выше для диагностики.")
    end
end

-- ============================================================
-- ЗАПУСК
-- ============================================================

print("\n" .. string.rep("═", 50))
print("🧪 ТЕСТОВЫЙ СКРИПТ ВЫДАЧИ ЧЕРЕЗ СУНДУК")
print(string.rep("═", 50))
print("\nЧто делаем:")
print("  1. Проверяем что есть в ME")
print("  2. Вводим ID предмета для теста")
print("  3. Выдаём из ME в сундук (с сохранением NBT)")
print("  4. Выдаём из сундука в PIM (инвентарь игрока)")
print("  5. Показываем логи всех действий")
print("\nНажмите ENTER для начала...")
io.read()

-- Запускаем тест с защитой
local ok, err = pcall(runTest)
if not ok then
    print("\n❌ КРИТИЧЕСКАЯ ОШИБКА:")
    print("  " .. tostring(err))
    print(debug.traceback())
end

print("\nНажмите ENTER для выхода...")
io.read()
