-- ============================================================
-- ТЕСТ ВЫДАЧИ ПРЯМО ЧЕРЕЗ PIM (БЕЗ ФЛУДА)4
-- ============================================================

local component = require("component")
local event = require("event")

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
-- ЛОГИРОВАНИЕ ИНВЕНТАРЯ
-- ============================================================

function logInventory(inv, title)
    print("\n" .. title)
    print("═" .. string.rep("═", 50))
    
    local count = 0
    for slot = 1, 36 do
        local stack = component.invoke(inv, "getStackInSlot", slot)
        if stack and (stack.size or stack.qty or 0) > 0 then
            count = count + 1
            local name = stack.displayName or stack.label or stack.name or "?"
            local size = stack.size or stack.qty or 0
            local damage = stack.damage or 0
            local hasNBT = (stack.nbt or stack.tag) and " [ЕСТЬ NBT]" or ""
            print(string.format("  Слот %2d: %s x%d (damage: %d)%s", 
                slot, name, size, damage, hasNBT))
        end
    end
    
    if count == 0 then
        print("  (пусто)")
    else
        print("\n  Всего предметов: " .. count)
    end
end

-- ============================================================
-- ВЫДАЧА ПРЯМО В PIM (ОДНА ПОПЫТКА)
-- ============================================================

function giveDirectToPIM(itemId, qty, damage)
    print("\n🧪 ВЫДАЧА В PIM: " .. itemId .. " x" .. qty .. " (damage: " .. (damage or 0) .. ")")
    print("═" .. string.rep("═", 50))
    
    local pimAddr = findPIM()
    if not pimAddr then
        print("❌ PIM не найден!")
        return false
    end
    
    local me = findME()
    if not me then
        print("❌ ME не найден!")
        return false
    end
    
    -- Проверяем свободные слоты
    local freeSlots = 0
    for slot = 1, 36 do
        local stack = component.invoke(pimAddr, "getStackInSlot", slot)
        if not stack or (stack.size or stack.qty or 0) == 0 then
            freeSlots = freeSlots + 1
        end
    end
    
    if freeSlots == 0 then
        print("❌ Нет свободных слотов в инвентаре!")
        return false
    end
    
    -- Проверяем наличие в ME
    local items = me.getItemsInNetwork()
    local available = 0
    local hasNBT = false
    
    for _, item in ipairs(items) do
        if item.name == itemId and (item.damage or 0) == (damage or 0) then
            available = available + (item.size or 0)
            if item.nbt or item.tag then
                hasNBT = true
            end
        end
    end
    
    if available == 0 then
        print("❌ Предмет не найден в ME!")
        print("\n💡 Доступные предметы в ME:")
        local shown = 0
        for _, item in ipairs(items) do
            if shown < 20 then
                print("  " .. item.name .. " x" .. (item.size or 0))
                shown = shown + 1
            end
        end
        return false
    end
    
    print("✅ Найдено в ME: " .. available .. " шт." .. (hasNBT and " [ЕСТЬ NBT]" or ""))
    
    -- Извлекаем из ME в PIM (одна попытка)
    local toExtract = math.min(qty, available, 64) -- максимум 64 за раз
    local fingerprint = { id = itemId, dmg = damage or 0 }
    
    print("⏳ Выдача...")
    
    local success, result = pcall(function()
        return me.exportItem(fingerprint, "down", toExtract)
    end)
    
    local extracted = 0
    
    if success then
        if type(result) == "number" and result > 0 then
            extracted = result
            print("✅ Выдано: " .. result .. " шт.")
        elseif type(result) == "boolean" and result == true then
            extracted = toExtract
            print("✅ Выдано: " .. toExtract .. " шт.")
        else
            print("❌ Не удалось выдать (ответ: " .. tostring(result) .. ")")
        end
    else
        print("❌ Ошибка: " .. tostring(result))
    end
    
    if extracted > 0 then
        -- Проверяем результат
        print("\n📊 РЕЗУЛЬТАТ:")
        for slot = 1, 36 do
            local stack = component.invoke(pimAddr, "getStackInSlot", slot)
            if stack and (stack.size or stack.qty or 0) > 0 then
                if stack.name == itemId and (stack.damage or 0) == (damage or 0) then
                    if stack.nbt or stack.tag then
                        print("  ✅ NBT-данные СОХРАНИЛИСЬ!")
                    else
                        print("  ⚠️ NBT-данные ПОТЕРЯНЫ!")
                    end
                    break
                end
            end
        end
    end
    
    return extracted > 0
end

-- ============================================================
-- ТЕСТОВЫЙ СЦЕНАРИЙ
-- ============================================================

function runTest()
    print("\n" .. string.rep("═", 50))
    print("🧪 ТЕСТ ВЫДАЧИ ЧЕРЕЗ PIM")
    print(string.rep("═", 50))
    
    -- Показываем что есть в ME
    local me = findME()
    if me then
        print("\n📦 СОДЕРЖИМОЕ ME:")
        local items = me.getItemsInNetwork()
        local groups = {}
        for _, item in ipairs(items) do
            local key = item.name .. ":" .. (item.damage or 0)
            if not groups[key] then
                groups[key] = { name = item.name, damage = item.damage or 0, count = 0, nbt = false }
            end
            groups[key].count = groups[key].count + (item.size or 0)
            if item.nbt or item.tag then
                groups[key].nbt = true
            end
        end
        
        local count = 0
        for key, data in pairs(groups) do
            if count < 30 then
                local nbt = data.nbt and " [NBT]" or ""
                print(string.format("  %s (damage: %d) x%d%s", 
                    data.name, data.damage, data.count, nbt))
                count = count + 1
            end
        end
    end
    
    -- Запрашиваем данные
    print("\n📝 ВВЕДИТЕ ДАННЫЕ ДЛЯ ТЕСТА:")
    print("  (Пример: diamond_sword, bow, enchanted_book)")
    
    print("  ID предмета:")
    local itemId = io.read()
    if not itemId or itemId == "" then
        print("❌ Отменено")
        return
    end
    
    if not itemId:find(":") then
        itemId = "minecraft:" .. itemId
    end
    
    print("  Количество (1-64):")
    local qty = tonumber(io.read()) or 1
    if qty > 64 then qty = 64 end
    
    print("  Damage (0 если не знаете):")
    local damage = tonumber(io.read()) or 0
    
    -- Выдаём
    giveDirectToPIM(itemId, qty, damage)
    
    -- Показываем инвентарь
    local pimAddr = findPIM()
    if pimAddr then
        logInventory(pimAddr, "👤 ИНВЕНТАРЬ ИГРОКА")
    end
end

-- ============================================================
-- ЗАПУСК
-- ============================================================

print("\n" .. string.rep("═", 50))
print("🧪 ТЕСТ ВЫДАЧИ ЧЕРЕЗ PIM (ОДНА ПОПЫТКА)")
print(string.rep("═", 50))
print("\nНажмите ENTER для начала...")
io.read()

local ok, err = pcall(runTest)
if not ok then
    print("\n❌ ОШИБКА:")
    print("  " .. tostring(err))
    print(debug.traceback())
end

print("\nНажмите ENTER для выхода...")
io.read()
