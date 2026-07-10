-- ============================================================
-- ДИАГНОСТИКА + ВЫДАЧА ЧЕРЕЗ СУНДУК
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

function findChest()
    for addr in component.list("inventory") do
        local inv = component.proxy(addr)
        if inv and inv.getInventorySize and inv.getInventorySize() > 0 then
            return inv, addr
        end
    end
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
            print("  Tier: " .. (item.tier or "нет"))
            
            -- Показываем NBT
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
            
            if item.maxDamage then
                hasNBT = true
                print("  ❤️ Макс. урон: " .. item.maxDamage)
            end
            
            if item.canProvideEnergy ~= nil then
                hasNBT = true
                print("  ⚡ Даёт энергию: " .. tostring(item.canProvideEnergy))
            end
            
            if item.hasTag then
                hasNBT = true
                print("  🏷️ Имеет тег: true")
            end
            
            if not hasNBT then
                print("  ❌ NBT-данных нет")
            end
            
            -- Полный объект
            print("\n📄 Полный объект:")
            print(serialization.serialize(item))
            
            return
        end
    end
    
    print("❌ Предмет не найден!")
end

-- ============================================================
-- ВЫДАЧА ЧЕРЕЗ СУНДУК (СОХРАНЯЕТ ВСЁ)
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
    
    -- Показываем NBT
    if itemData.charge or itemData.enchantments or itemData.hasTag then
        print("⚠️ У предмета есть NBT-данные (заряд, зачарования)")
        print("  ✅ Будут сохранены при выдаче через сундук")
    end
    
    -- Извлекаем из ME
    local toExtract = math.min(qty, available)
    local fingerprint = { id = itemId, dmg = damage or 0 }
    local extracted = 0
    
    print("\n⏳ Извлечение из ME...")
    
    while extracted < toExtract do
        local toTake = math.min(toExtract - extracted, 64)
        local success, result = pcall(function()
            return me.exportItem(fingerprint, "down", toTake)
        end)
        
        if success and result then
            if type(result) == "number" and result > 0 then
                extracted = extracted + result
                print("  ✅ Извлечено: " .. result .. " шт.")
            elseif type(result) == "boolean" and result == true then
                extracted = extracted + toTake
                print("  ✅ Извлечено: " .. toTake .. " шт.")
            else
                print("  ⚠️ Ошибка: " .. tostring(result))
                break
            end
        else
            print("  ❌ Ошибка: " .. tostring(result))
            break
        end
    end
    
    if extracted == 0 then
        print("❌ Не удалось извлечь из ME!")
        return false
    end
    
    -- Кладём в сундук (сохраняя все данные)
    print("\n⏳ Помещение в сундук...")
    
    local chestSize = chest.getInventorySize and chest.getInventorySize() or 27
    local placed = 0
    
    for slot = 1, chestSize do
        if placed >= extracted then break end
        
        local stack = chest.getStackInSlot and chest.getStackInSlot(slot)
        if not stack or (stack.size or stack.qty or 0) == 0 then
            -- Создаём полную копию предмета со всеми данными
            local stackData = {
                id = itemId,
                dmg = damage or 0,
                size = math.min(extracted - placed, 64)
            }
            
            -- Копируем все NBT-данные
            if itemData then
                if itemData.charge then
                    stackData.charge = itemData.charge
                end
                if itemData.maxCharge then
                    stackData.maxCharge = itemData.maxCharge
                end
                if itemData.enchantments then
                    stackData.enchantments = itemData.enchantments
                end
                if itemData.maxDamage then
                    stackData.maxDamage = itemData.maxDamage
                end
                if itemData.tier then
                    stackData.tier = itemData.tier
                end
                if itemData.label then
                    stackData.label = itemData.label
                end
                if itemData.hasTag then
                    stackData.hasTag = true
                end
                if itemData.canProvideEnergy ~= nil then
                    stackData.canProvideEnergy = itemData.canProvideEnergy
                end
                -- Копируем всё остальное
                for k, v in pairs(itemData) do
                    if type(k) == "string" and not stackData[k] and 
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
    
    -- Проверяем что попало в сундук
    print("\n🔍 Проверка сундука:")
    for slot = 1, math.min(chestSize, 10) do
        local stack = chest.getStackInSlot and chest.getStackInSlot(slot)
        if stack and (stack.size or stack.qty or 0) > 0 then
            local name = stack.label or stack.displayName or stack.name or "?"
            local size = stack.size or stack.qty or 0
            local hasCharge = stack.charge and " [заряд: " .. stack.charge .. "]" or ""
            local hasEnchant = stack.enchantments and " [зачарован]" or ""
            print("  Слот " .. slot .. ": " .. name .. " x" .. size .. hasCharge .. hasEnchant)
        end
    end
    
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
            print("  Слот " .. slot .. ": " .. name .. " x" .. size .. hasCharge)
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
            
            if chest.pushItem then
                local result = chest.pushItem("up", slot, amount)
                if type(result) == "number" and result > 0 then
                    moved = moved + result
                    print("  ✅ Перемещено в слот " .. targetSlot .. ": " .. result .. " шт.")
                end
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
    print("🧪 ВЫДАЧА NBT-ПРЕДМЕТОВ ЧЕРЕЗ СУНДУК")
    print(string.rep("═", 50))
    
    while true do
        print("\nВыберите действие:")
        print("  [1] Показать все предметы в ME")
        print("  [2] Показать структуру предмета")
        print("  [3] Выдать в сундук (с NBT)")
        print("  [4] Переместить из сундука в PIM")
        print("  [5] ВСЁ СРАЗУ (выдать + переместить)")
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
