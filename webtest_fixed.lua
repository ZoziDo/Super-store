-- ============================================================
-- ВЫДАЧА NBT-ПРЕДМЕТОВ ЧЕРЕЗ СУНДУК (С ПРАВИЛЬНЫМИ СТОРОНАМИ)1
-- ============================================================

local component = require("component")
local serialization = require("serialization")

-- НАСТРОЙКА СТОРОН
-- Попробуйте эти варианты, если не работает
local CHEST_PUSH = "down"   -- Сторона, куда PIM выталкивает предметы
local CHEST_PULL = "up"     -- Сторона, откуда PIM забирает предметы

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

function findChest()
    -- Ищем любой инвентарь
    for addr in component.list("inventory") do
        local inv = component.proxy(addr)
        if inv and inv.getInventorySize and inv.getInventorySize() > 0 then
            print("✅ Найден сундук: " .. addr)
            return inv, addr
        end
    end
    
    -- Ищем конкретные типы
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
                print("✅ Найден сундук: " .. typeName)
                return chest, addr
            end
        end
    end
    
    print("❌ Сундук не найден!")
    return nil, nil
end

-- ============================================================
-- ПОКАЗАТЬ СТРУКТУРУ ПРЕДМЕТА
-- ============================================================

function showItemStructure(itemId, damage)
    local me = findME()
    if not me then
        print("❌ ME не найден!")
        return
    end
    
    print("\n🔍 СТРУКТУРА ПРЕДМЕТА: " .. itemId)
    print("═" .. string.rep("═", 50))
    
    local items = me.getItemsInNetwork()
    
    for _, item in ipairs(items) do
        if item.name == itemId and (item.damage or 0) == (damage or 0) then
            print("\n📦 Основные данные:")
            print("  Имя: " .. (item.name or "?"))
            print("  Label: " .. (item.label or "нет"))
            print("  Damage: " .. (item.damage or 0))
            print("  Количество: " .. (item.size or 0))
            print("  MaxSize: " .. (item.maxSize or 64))
            
            print("\n📋 NBT-ДАННЫЕ:")
            local hasNBT = false
            
            if item.charge then
                hasNBT = true
                print("  ⚡ Заряд: " .. item.charge .. " / " .. (item.maxCharge or item.charge))
            end
            
            if item.enchantments then
                hasNBT = true
                print("  ✨ Зачарования:")
                if type(item.enchantments) == "table" then
                    for k, v in pairs(item.enchantments) do
                        print("     " .. k .. ": " .. tostring(v))
                    end
                end
            end
            
            if item.hasTag then
                hasNBT = true
                print("  🏷️ Имеет тег: true")
            end
            
            if not hasNBT then
                print("  ❌ NBT-данных нет")
            else
                print("\n  ⚠️ Эти данные будут сохранены при выдаче через сундук!")
            end
            
            return
        end
    end
    
    print("❌ Предмет не найден!")
end

-- ============================================================
-- ВЫДАЧА ЧЕРЕЗ СУНДУК
-- ============================================================

function giveThroughChest(itemId, qty, damage)
    print("\n📦 ВЫДАЧА ЧЕРЕЗ СУНДУК: " .. itemId .. " x" .. qty)
    print("═" .. string.rep("═", 50))
    
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
    
    -- Проверяем наличие в ME
    local items = me.getItemsInNetwork()
    local available = 0
    local itemData = nil
    
    for _, item in ipairs(items) do
        if item.name == itemId and (item.damage or 0) == (damage or 0) then
            available = available + (item.size or 0)
            itemData = item
        end
    end
    
    if available == 0 then
        print("❌ Предмет не найден в ME!")
        return false
    end
    
    print("✅ В ME есть: " .. available .. " шт.")
    
    -- Извлекаем из ME
    local toExtract = math.min(qty, available)
    local fingerprint = { id = itemId, dmg = damage or 0 }
    local extracted = 0
    
    print("\n⏳ Извлечение из ME...")
    
    -- Пробуем извлечь
    local success, result = pcall(function()
        return me.exportItem(fingerprint, "down", toExtract)
    end)
    
    if success and result then
        if type(result) == "number" and result > 0 then
            extracted = result
            print("  ✅ Извлечено: " .. result .. " шт.")
        elseif type(result) == "boolean" and result == true then
            extracted = toExtract
            print("  ✅ Извлечено: " .. toExtract .. " шт.")
        else
            print("  ❌ Не удалось извлечь. Ответ: " .. tostring(result))
            return false
        end
    else
        print("  ❌ Ошибка: " .. tostring(result))
        return false
    end
    
    if extracted == 0 then
        print("❌ Не удалось извлечь из ME!")
        return false
    end
    
    -- Кладём в сундук
    print("\n⏳ Помещение в сундук...")
    
    local chestSize = chest.getInventorySize and chest.getInventorySize() or 27
    local placed = 0
    
    for slot = 1, chestSize do
        if placed >= extracted then break end
        
        local stack = chest.getStackInSlot and chest.getStackInSlot(slot)
        if not stack or (stack.size or stack.qty or 0) == 0 then
            -- Создаём предмет со всеми данными
            local stackData = {
                id = itemId,
                dmg = damage or 0,
                size = math.min(extracted - placed, 64)
            }
            
            -- Копируем NBT
            if itemData then
                for k, v in pairs(itemData) do
                    if type(k) == "string" and 
                       k ~= "name" and k ~= "damage" and k ~= "size" and 
                       k ~= "maxSize" and k ~= "isCraftable" and k ~= "transferLimit" then
                        stackData[k] = v
                    end
                end
            end
            
            local result = chest.setStackInSlot and chest.setStackInSlot(slot, stackData)
            if result then
                local added = stackData.size or 0
                placed = placed + added
                print("  ✅ Помещено в слот " .. slot .. ": " .. added .. " шт.")
            end
        end
    end
    
    print("\n📊 Итого в сундуке: " .. placed .. " шт.")
    return placed > 0
end

-- ============================================================
-- ВЫДАЧА ИЗ СУНДУКА В PIM
-- ============================================================

function moveFromChestToPIM()
    print("\n📦 ПЕРЕМЕЩЕНИЕ ИЗ СУНДУКА В PIM")
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
    
    -- Показываем что в сундуке
    print("\n📦 Содержимое сундука:")
    local chestSize = chest.getInventorySize and chest.getInventorySize() or 27
    local count = 0
    
    for slot = 1, chestSize do
        local stack = chest.getStackInSlot and chest.getStackInSlot(slot)
        if stack and (stack.size or stack.qty or 0) > 0 then
            count = count + 1
            local name = stack.label or stack.displayName or stack.name or "?"
            local size = stack.size or stack.qty or 0
            local hasCharge = stack.charge and " [заряд: " .. stack.charge .. "]" or ""
            local hasEnchant = stack.enchantments and " [зачарован]" or ""
            print("  Слот " .. slot .. ": " .. name .. " x" .. size .. hasCharge .. hasEnchant)
        end
    end
    
    if count == 0 then
        print("  (пусто)")
        return false
    end
    
    -- Перемещаем в PIM
    print("\n⏳ Перемещение в PIM...")
    local moved = 0
    
    for slot = 1, chestSize do
        local stack = chest.getStackInSlot and chest.getStackInSlot(slot)
        if stack and (stack.size or stack.qty or 0) > 0 then
            local amount = stack.size or stack.qty or 0
            
            -- Ищем свободный слот в PIM
            local targetSlot = nil
            for ps = 1, 36 do
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
            
            -- Пробуем pushItem с разными сторонами
            local result = 0
            
            -- Сначала пробуем стандартный способ
            if chest.pushItem then
                result = chest.pushItem(CHEST_PULL, slot, amount)
            end
            
            -- Если не сработало, пробуем через moveItem
            if type(result) ~= "number" or result == 0 then
                if chest.moveItem then
                    result = chest.moveItem(slot, pimAddr, targetSlot, amount)
                end
            end
            
            -- Если всё ещё не сработало, пробуем через инвентарь PIM
            if type(result) ~= "number" or result == 0 then
                result = component.invoke(pimAddr, "pushItem", CHEST_PUSH, slot, amount)
            end
            
            if type(result) == "number" and result > 0 then
                moved = moved + result
                print("  ✅ Перемещено в слот " .. targetSlot .. ": " .. result .. " шт.")
            end
        end
    end
    
    print("\n✅ Всего перемещено: " .. moved .. " шт.")
    return moved > 0
end

-- ============================================================
-- ПОКАЗАТЬ ВСЕ ПРЕДМЕТЫ В ME
-- ============================================================

function showAllItems()
    local me = findME()
    if not me then
        print("❌ ME не найден!")
        return
    end
    
    print("\n📦 ВСЕ ПРЕДМЕТЫ В ME:")
    print("═" .. string.rep("═", 50))
    
    local items = me.getItemsInNetwork()
    local groups = {}
    
    for _, item in ipairs(items) do
        local key = item.name .. ":" .. (item.damage or 0)
        if not groups[key] then
            groups[key] = {
                name = item.name,
                damage = item.damage or 0,
                count = 0,
                hasNBT = false,
                info = ""
            }
        end
        groups[key].count = groups[key].count + (item.size or 0)
        
        if item.charge then
            groups[key].hasNBT = true
            groups[key].info = "заряд: " .. item.charge
        end
        if item.enchantments then
            groups[key].hasNBT = true
            groups[key].info = groups[key].info .. " [зачарован]"
        end
        if item.hasTag then
            groups[key].hasNBT = true
        end
    end
    
    local i = 0
    for key, data in pairs(groups) do
        i = i + 1
        local nbt = data.hasNBT and " [ЕСТЬ NBT]" or ""
        local info = data.info ~= "" and " (" .. data.info .. ")" or ""
        print(string.format("  %d. %s (damage: %d) x%d%s%s", 
            i, data.name, data.damage, data.count, nbt, info))
    end
    
    print("\nВсего групп: " .. i)
end

-- ============================================================
-- ПОКАЗАТЬ СТОРОНЫ
-- ============================================================

function showSides()
    print("\n🔧 ТЕКУЩИЕ НАСТРОЙКИ СТОРОН:")
    print("═" .. string.rep("═", 50))
    print("  CHEST_PUSH = " .. CHEST_PUSH .. " (PIM выталкивает в эту сторону)")
    print("  CHEST_PULL = " .. CHEST_PULL .. " (PIM забирает из этой стороны)")
    print("\n💡 Если не работает, попробуйте изменить стороны в начале скрипта")
    print("   Возможные значения: up, down, north, south, west, east")
end

-- ============================================================
-- ГЛАВНОЕ МЕНЮ
-- ============================================================

function main()
    print("\n" .. string.rep("═", 50))
    print("🧪 ВЫДАЧА NBT-ПРЕДМЕТОВ ЧЕРЕЗ СУНДУК")
    print(string.rep("═", 50))
    
    -- Показываем настройки сторон
    showSides()
    
    while true do
        print("\nВыберите действие:")
        print("  [1] Показать все предметы в ME")
        print("  [2] Показать структуру предмета")
        print("  [3] Выдать в сундук (с NBT)")
        print("  [4] Переместить из сундука в PIM")
        print("  [5] ВСЁ СРАЗУ (выдать + переместить)")
        print("  [6] Проверить сундук")
        print("  [S] Показать настройки сторон")
        print("  [Q] Выход")
        
        local choice = io.read()
        
        if choice == "1" then
            showAllItems()
            
        elseif choice == "2" then
            print("\nВведите ID предмета (например: GraviSuite:vajra):")
            local itemId = io.read()
            if not itemId or itemId == "" then
                print("❌ Отменено")
                goto continue
            end
            
            print("Введите damage (0 если не знаете):")
            local damage = tonumber(io.read()) or 0
            
            showItemStructure(itemId, damage)
            
        elseif choice == "3" then
            print("\nВведите ID предмета:")
            local itemId = io.read()
            if not itemId or itemId == "" then
                print("❌ Отменено")
                goto continue
            end
            
            print("Введите количество:")
            local qty = tonumber(io.read()) or 1
            
            print("Введите damage (0 если не знаете):")
            local damage = tonumber(io.read()) or 0
            
            giveThroughChest(itemId, qty, damage)
            
        elseif choice == "4" then
            moveFromChestToPIM()
            
        elseif choice == "5" then
            print("\n🚀 ВЫДАЧА + ПЕРЕМЕЩЕНИЕ")
            print("Введите ID предмета:")
            local itemId = io.read()
            if not itemId or itemId == "" then
                print("❌ Отменено")
                goto continue
            end
            
            print("Введите количество:")
            local qty = tonumber(io.read()) or 1
            
            print("Введите damage (0 если не знаете):")
            local damage = tonumber(io.read()) or 0
            
            if giveThroughChest(itemId, qty, damage) then
                print("\n✅ Предметы в сундуке. Перемещаем в PIM...")
                moveFromChestToPIM()
            end
            
        elseif choice == "6" then
            local chest, addr = findChest()
            if chest then
                print("\n📦 СУНДУК НАЙДЕН!")
                print("  Адрес: " .. addr)
                local size = chest.getInventorySize and chest.getInventorySize() or 27
                print("  Размер: " .. size .. " слотов")
                
                -- Показываем содержимое
                local count = 0
                for slot = 1, math.min(size, 10) do
                    local stack = chest.getStackInSlot and chest.getStackInSlot(slot)
                    if stack and (stack.size or stack.qty or 0) > 0 then
                        count = count + 1
                        local name = stack.label or stack.displayName or stack.name or "?"
                        local qty = stack.size or stack.qty or 0
                        print("  Слот " .. slot .. ": " .. name .. " x" .. qty)
                    end
                end
                if count == 0 then
                    print("  (пусто)")
                end
            end
            
        elseif choice == "s" or choice == "S" then
            showSides()
            
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
    print("\n❌ ОШИБКА:")
    print("  " .. tostring(err))
    print(debug.traceback())
end
