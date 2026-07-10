-- ============================================================
-- ТЕСТ ВЫДАЧИ ПРЯМО ЧЕРЕЗ PIM (БЕЗ СУНДУКА)11
-- ============================================================

local component = require("component")
local event = require("event")
local serialization = require("serialization")

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
-- ВЫДАЧА ПРЯМО В PIM
-- ============================================================

function giveDirectToPIM(itemId, qty, damage)
    print("\n🧪 ТЕСТ: ВЫДАЧА ПРЯМО В PIM")
    print("═" .. string.rep("═", 50))
    print("  Предмет: " .. itemId)
    print("  Количество: " .. qty)
    print("  Damage: " .. (damage or 0))
    
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
    
    -- Логируем инвентарь ДО
    logInventory(pimAddr, "👤 ИНВЕНТАРЬ ИГРОКА ДО:")
    
    -- Проверяем свободные слоты
    local freeSlots = 0
    for slot = 1, 36 do
        local stack = component.invoke(pimAddr, "getStackInSlot", slot)
        if not stack or (stack.size or stack.qty or 0) == 0 then
            freeSlots = freeSlots + 1
        end
    end
    
    print("\n📊 Свободных слотов: " .. freeSlots)
    
    if freeSlots == 0 then
        print("❌ Нет свободных слотов!")
        return false
    end
    
    -- Проверяем наличие в ME
    print("\n🔍 Проверка ME...")
    local items = me.getItemsInNetwork()
    local available = 0
    local itemDetails = nil
    
    for _, item in ipairs(items) do
        if item.name == itemId and (item.damage or 0) == (damage or 0) then
            available = available + (item.size or 0)
            itemDetails = item
            print("  ✅ Найдено: " .. (item.size or 0) .. " шт.")
            if item.nbt or item.tag then
                print("  🔹 ЕСТЬ NBT-ДАННЫЕ!")
                -- Показываем структуру NBT
                local nbt = item.nbt or item.tag
                if type(nbt) == "table" then
                    print("  📋 NBT структура:")
                    for k, v in pairs(nbt) do
                        print("     " .. k .. ": " .. tostring(v))
                    end
                end
            end
            if item.damage then
                print("  🔹 Damage: " .. item.damage)
            end
        end
    end
    
    if available == 0 then
        print("❌ Предмет не найден в ME!")
        print("\n💡 Попробуйте один из этих ID:")
        local shown = 0
        for _, item in ipairs(items) do
            if shown < 20 then
                print("  " .. item.name .. " x" .. (item.size or 0))
                shown = shown + 1
            end
        end
        return false
    end
    
    -- Извлекаем из ME в PIM
    print("\n⏳ Выдача в PIM...")
    
    local toExtract = math.min(qty, available)
    local fingerprint = { id = itemId, dmg = damage or 0 }
    local extracted = 0
    local errors = {}
    
    while extracted < toExtract do
        if freeSlots <= 0 then
            print("⚠️ Закончились свободные слоты!")
            break
        end
        
        local toTake = math.min(toExtract - extracted, 64)
        print("  Попытка выдать " .. toTake .. " шт...")
        
        local success, result = pcall(function()
            return me.exportItem(fingerprint, "down", toTake)
        end)
        
        if success then
            if type(result) == "number" and result > 0 then
                extracted = extracted + result
                freeSlots = freeSlots - 1
                print("  ✅ Выдано: " .. result .. " шт.")
            elseif type(result) == "boolean" and result == true then
                extracted = extracted + toTake
                freeSlots = freeSlots - 1
                print("  ✅ Выдано: " .. toTake .. " шт.")
            elseif result == false or result == 0 then
                print("  ⚠️ Не удалось выдать (вернулось " .. tostring(result) .. ")")
                table.insert(errors, "Не удалось выдать: " .. tostring(result))
                break
            else
                print("  ⚠️ Странный ответ: " .. tostring(result))
                table.insert(errors, "Странный ответ: " .. tostring(result))
            end
        else
            print("  ❌ Ошибка: " .. tostring(result))
            table.insert(errors, tostring(result))
            break
        end
    end
    
    print("\n📊 Итого выдано: " .. extracted .. " из " .. toExtract)
    
    -- Логируем инвентарь ПОСЛЕ
    logInventory(pimAddr, "👤 ИНВЕНТАРЬ ИГРОКА ПОСЛЕ:")
    
    -- Анализ результата
    if extracted > 0 then
        print("\n✅ УСПЕШНО!")
        print("  Выдано " .. extracted .. " шт. в инвентарь игрока")
        
        -- Проверяем NBT сохранился ли
        for slot = 1, 36 do
            local stack = component.invoke(pimAddr, "getStackInSlot", slot)
            if stack and (stack.size or stack.qty or 0) > 0 then
                if stack.name == itemId and (stack.damage or 0) == (damage or 0) then
                    if stack.nbt or stack.tag then
                        print("  🔹 NBT-данные СОХРАНИЛИСЬ!")
                    else
                        print("  ⚠️ NBT-данные ПОТЕРЯНЫ!")
                    end
                    break
                end
            end
        end
    else
        print("\n❌ НЕ УДАЛОСЬ!")
        print("  Не удалось выдать ни одного предмета")
        if #errors > 0 then
            print("  Ошибки:")
            for _, err in ipairs(errors) do
                print("    - " .. err)
            end
        end
    end
    
    return extracted > 0
end

-- ============================================================
-- ТЕСТ С РАЗНЫМИ ДАННЫМИ
-- ============================================================

function testWithDamage()
    print("\n🧪 ТЕСТ: ПОИСК ПРЕДМЕТОВ С РАЗНЫМ DAMAGE")
    print("═" .. string.rep("═", 50))
    
    local me = findME()
    if not me then
        print("❌ ME не найден!")
        return
    end
    
    local items = me.getItemsInNetwork()
    local groups = {}
    
    for _, item in ipairs(items) do
        local key = item.name .. ":" .. (item.damage or 0)
        if not groups[key] then
            groups[key] = {
                name = item.name,
                damage = item.damage or 0,
                count = 0,
                hasNBT = false
            }
        end
        groups[key].count = groups[key].count + (item.size or 0)
        if item.nbt or item.tag then
            groups[key].hasNBT = true
        end
    end
    
    print("\n📊 Доступные предметы:")
    for key, data in pairs(groups) do
        local nbt = data.hasNBT and " [NBT]" or ""
        print(string.format("  %s (damage: %d) x%d%s", 
            data.name, data.damage, data.count, nbt))
    end
end

-- ============================================================
-- ГЛАВНОЕ МЕНЮ
-- ============================================================

function main()
    print("\n" .. string.rep("═", 50))
    print("🧪 ТЕСТ ВЫДАЧИ ЧЕРЕЗ PIM (БЕЗ СУНДУКА)")
    print(string.rep("═", 50))
    
    while true do
        print("\nВыберите действие:")
        print("  [1] Показать что в ME (с damage и NBT)")
        print("  [2] Выдать предмет в PIM")
        print("  [3] Тест: выдать с разным damage")
        print("  [4] Показать инвентарь игрока")
        print("  [5] Очистить инвентарь игрока")
        print("  [Q] Выход")
        
        local choice = io.read()
        
        if choice == "1" then
            testWithDamage()
            
        elseif choice == "2" then
            print("\nВведите ID предмета (например: diamond_sword):")
            local itemId = io.read()
            if not itemId or itemId == "" then
                print("❌ Отменено")
                goto continue
            end
            
            -- Добавляем minecraft: если нет
            if not itemId:find(":") then
                itemId = "minecraft:" .. itemId
            end
            
            print("Введите количество (по умолчанию 1):")
            local qty = tonumber(io.read()) or 1
            
            print("Введите damage (0 если не знаете):")
            local damage = tonumber(io.read()) or 0
            
            giveDirectToPIM(itemId, qty, damage)
            
        elseif choice == "3" then
            print("\n🧪 ТЕСТ С РАЗНЫМ DAMAGE")
            print("Введите ID предмета (например: diamond_sword):")
            local itemId = io.read()
            if not itemId or itemId == "" then
                print("❌ Отменено")
                goto continue
            end
            
            if not itemId:find(":") then
                itemId = "minecraft:" .. itemId
            end
            
            print("Введите количество (по умолчанию 1):")
            local qty = tonumber(io.read()) or 1
            
            -- Тест с damage 0
            print("\n📦 Тест с damage: 0")
            giveDirectToPIM(itemId, qty, 0)
            
            -- Тест с damage 1 (если есть)
            print("\n📦 Тест с damage: 1")
            giveDirectToPIM(itemId, qty, 1)
            
        elseif choice == "4" then
            local pimAddr = findPIM()
            if pimAddr then
                logInventory(pimAddr, "👤 ИНВЕНТАРЬ ИГРОКА")
            else
                print("❌ PIM не найден!")
            end
            
        elseif choice == "5" then
            local pimAddr = findPIM()
            if not pimAddr then
                print("❌ PIM не найден!")
                goto continue
            end
            
            print("⚠️ Очистить инвентарь игрока? (y/n):")
            local confirm = io.read()
            if confirm == "y" or confirm == "Y" then
                local cleared = 0
                for slot = 1, 36 do
                    local stack = component.invoke(pimAddr, "getStackInSlot", slot)
                    if stack and (stack.size or stack.qty or 0) > 0 then
                        component.invoke(pimAddr, "pushItem", "down", slot, 999)
                        cleared = cleared + 1
                    end
                end
                print("✅ Очищено слотов: " .. cleared)
            else
                print("❌ Отменено")
            end
            
        elseif choice == "q" or choice == "Q" then
            print("\n👋 Выход...")
            break
        end
        
        ::continue::
    end
end

-- ============================================================
-- ЗАПУСК
-- ============================================================

local ok, err = pcall(main)
if not ok then
    print("\n❌ КРИТИЧЕСКАЯ ОШИБКА:")
    print("  " .. tostring(err))
    print(debug.traceback())
end
