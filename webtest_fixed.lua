-- ============================================================
-- ВЫДАЧА ЧЕРЕЗ ЛЮБОЙ ДОСТУПНЫЙ ИНВЕНТАРЬ
-- ============================================================

local component = require("component")
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

function findAnyInventory()
    -- Ищем ЛЮБОЙ инвентарь
    for addr in component.list("inventory") do
        local inv = component.proxy(addr)
        if inv and inv.getInventorySize and inv.getInventorySize() > 0 then
            return inv, addr
        end
    end
    return nil, nil
end

-- ============================================================
-- ВЫДАЧА В ЛЮБОЙ ИНВЕНТАРЬ
-- ============================================================

function giveToInventory(itemId, qty, damage)
    print("\n📦 ВЫДАЧА: " .. itemId .. " x" .. qty)
    print("═" .. string.rep("═", 50))
    
    local me = findME()
    if not me then
        print("❌ ME не найден!")
        return false
    end
    
    local inv, invAddr = findAnyInventory()
    if not inv then
        print("❌ Нет доступных инвентарей!")
        print("\n💡 Поставьте сундук рядом с компьютером")
        return false
    end
    
    print("✅ Найден инвентарь: " .. invAddr)
    local size = inv.getInventorySize and inv.getInventorySize() or 27
    print("  Размер: " .. size .. " слотов")
    
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
    
    if itemData and (itemData.charge or itemData.enchantments or itemData.hasTag) then
        print("⚠️ У предмета есть NBT-данные, они сохранятся")
    end
    
    -- Извлекаем из ME
    local toExtract = math.min(qty, available)
    local fingerprint = { id = itemId, dmg = damage or 0 }
    local extracted = 0
    
    print("\n⏳ Извлечение из ME...")
    
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
    
    -- Кладём в инвентарь
    print("\n⏳ Помещение в инвентарь...")
    local placed = 0
    
    for slot = 1, size do
        if placed >= extracted then break end
        
        local stack = inv.getStackInSlot and inv.getStackInSlot(slot)
        if not stack or (stack.size or stack.qty or 0) == 0 then
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
            
            local result = inv.setStackInSlot and inv.setStackInSlot(slot, stackData)
            if result then
                local added = stackData.size or 0
                placed = placed + added
                print("  ✅ Помещено в слот " .. slot .. ": " .. added .. " шт.")
            end
        end
    end
    
    print("\n📊 Итого в инвентаре: " .. placed .. " шт.")
    
    -- Показываем что попало
    print("\n🔍 Проверка:")
    for slot = 1, math.min(size, 10) do
        local stack = inv.getStackInSlot and inv.getStackInSlot(slot)
        if stack and (stack.size or stack.qty or 0) > 0 then
            local name = stack.label or stack.displayName or stack.name or "?"
            local qty2 = stack.size or stack.qty or 0
            local hasCharge = stack.charge and " [заряд: " .. stack.charge .. "]" or ""
            local hasEnchant = stack.enchantments and " [зачарован]" or ""
            print("  Слот " .. slot .. ": " .. name .. " x" .. qty2 .. hasCharge .. hasEnchant)
        end
    end
    
    return placed > 0
end

-- ============================================================
-- ПЕРЕМЕЩЕНИЕ ИЗ ИНВЕНТАРЯ В PIM
-- ============================================================

function moveToPIM()
    print("\n📦 ПЕРЕМЕЩЕНИЕ В PIM")
    print("═" .. string.rep("═", 50))
    
    local inv, invAddr = findAnyInventory()
    if not inv then
        print("❌ Нет доступных инвентарей!")
        return false
    end
    
    local pimAddr = findPIM()
    if not pimAddr then
        print("❌ PIM не найден!")
        return false
    end
    
    print("✅ Инвентарь: " .. invAddr)
    local size = inv.getInventorySize and inv.getInventorySize() or 27
    
    -- Показываем содержимое
    print("\n📦 Содержимое инвентаря:")
    local count = 0
    for slot = 1, size do
        local stack = inv.getStackInSlot and inv.getStackInSlot(slot)
        if stack and (stack.size or stack.qty or 0) > 0 then
            count = count + 1
            local name = stack.label or stack.displayName or stack.name or "?"
            local qty = stack.size or stack.qty or 0
            local hasCharge = stack.charge and " [заряд]" or ""
            print("  Слот " .. slot .. ": " .. name .. " x" .. qty .. hasCharge)
        end
    end
    
    if count == 0 then
        print("  (пусто)")
        return false
    end
    
    -- Перемещаем в PIM
    print("\n⏳ Перемещение...")
    local moved = 0
    
    for slot = 1, size do
        local stack = inv.getStackInSlot and inv.getStackInSlot(slot)
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
            
            -- Пробуем разные способы
            local result = 0
            
            -- Способ 1: pushItem из инвентаря
            if inv.pushItem then
                result = inv.pushItem("up", slot, amount)
            end
            
            -- Способ 2: moveItem
            if type(result) ~= "number" or result == 0 then
                if inv.moveItem then
                    result = inv.moveItem(slot, pimAddr, targetSlot, amount)
                end
            end
            
            -- Способ 3: pushItem в PIM
            if type(result) ~= "number" or result == 0 then
                result = component.invoke(pimAddr, "pushItem", "down", slot, amount)
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
-- ГЛАВНОЕ МЕНЮ
-- ============================================================

function main()
    print("\n" .. string.rep("═", 50))
    print("🧪 ВЫДАЧА NBT-ПРЕДМЕТОВ (ЛЮБОЙ ИНВЕНТАРЬ)")
    print(string.rep("═", 50))
    
    -- Проверяем наличие инвентаря
    local inv, addr = findAnyInventory()
    if inv then
        print("\n✅ Найден инвентарь: " .. addr)
    else
        print("\n❌ Нет доступных инвентарей!")
        print("  Поставьте сундук рядом с компьютером")
    end
    
    while true do
        print("\nВыберите действие:")
        print("  [1] Показать все предметы в ME")
        print("  [2] Выдать в инвентарь (с NBT)")
        print("  [3] Переместить из инвентаря в PIM")
        print("  [4] ВСЁ СРАЗУ (выдать + переместить)")
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
            
            print("Введите количество:")
            local qty = tonumber(io.read()) or 1
            
            print("Введите damage (0 если не знаете):")
            local damage = tonumber(io.read()) or 0
            
            giveToInventory(itemId, qty, damage)
            
        elseif choice == "3" then
            moveToPIM()
            
        elseif choice == "4" then
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
            
            if giveToInventory(itemId, qty, damage) then
                print("\n✅ Предметы в инвентаре. Перемещаем в PIM...")
                moveToPIM()
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
    print("\n❌ ОШИБКА:")
    print("  " .. tostring(err))
    print(debug.traceback())
end
