-- /home/diagnose_item.lua
local component = require("component")
local event = require("event")
local serialization = require("serialization")

local me = component.me_interface
local pim = component.pim

print("=== ДИАГНОСТИКА ПРЕДМЕТА ===")
print("")

-- Введите имя предмета
io.write("Введите internalName (например GraviSuite:vajra): ")
local name = io.read()
name = name:match("^%s*(.-)%s*$")

io.write("Введите damage (0-15, Enter для 0): ")
local dmgInput = io.read()
local damage = 0
if dmgInput and dmgInput ~= "" then
    damage = tonumber(dmgInput) or 0
end

print("")
print("Ищем предмет: " .. name .. " (damage: " .. damage .. ")")
print("")

-- 1. Проверяем, есть ли предмет в ME
local allItems = me.getItemsInNetwork()
local foundItem = nil

for _, item in ipairs(allItems) do
    if item.name == name and (item.damage or 0) == damage then
        foundItem = item
        break
    end
end

if not foundItem then
    print("❌ Предмет НЕ НАЙДЕН в ME системе!")
    print("")
    print("Похожие предметы в ME:")
    for _, item in ipairs(allItems) do
        if string.find(item.name, name:match("[^:]+$") or "") then
            print("  " .. item.name .. " (damage: " .. (item.damage or 0) .. ") - " .. (item.size or 0) .. " шт.")
        end
    end
    return
end

print("✅ Предмет найден в ME системе!")
print("  Имя: " .. foundItem.name)
print("  Damage: " .. (foundItem.damage or 0))
print("  Количество: " .. (foundItem.size or 0))
print("")

-- 2. Проверяем, есть ли место в инвентаре
print("=== ПРОВЕРКА ИНВЕНТАРЯ ===")
local freeSlots = 0
for slot = 1, 36 do
    local stack = pim.getStackInSlot(slot)
    if not stack or stack.size == 0 then
        freeSlots = freeSlots + 1
    end
end
print("Свободных слотов в инвентаре: " .. freeSlots)

if freeSlots == 0 then
    print("❌ ИНВЕНТАРЬ ПОЛОН! Освободите место.")
    return
end

-- 3. Проверяем, что лежит в инвентаре
print("")
print("=== СОДЕРЖИМОЕ ИНВЕНТАРЯ ===")
for slot = 1, 36 do
    local stack = pim.getStackInSlot(slot)
    if stack and stack.size and stack.size > 0 then
        local name = stack.name or "?"
        local qty = stack.size or 0
        print("  Слот " .. slot .. ": " .. name .. " x" .. qty)
    end
end

-- 4. Пробуем выдать предмет разными способами
print("")
print("=== ТЕСТОВАЯ ВЫДАЧА ===")

local fingerprint = { id = name, dmg = damage }

-- Способ 1: Стандартная выдача
print("1. Стандартный exportItem (up):")
local success, result = pcall(function()
    return me.exportItem(fingerprint, "up", 1)
end)
if success then
    print("   Результат: " .. tostring(result))
    if result and result > 0 then
        print("   ✅ УСПЕШНО! Предмет выдан.")
        return
    end
else
    print("   ❌ Ошибка: " .. tostring(result))
end

-- Способ 2: С force = true
print("2. exportItem с force=true:")
local success, result = pcall(function()
    return me.exportItem(fingerprint, "up", 1, true)
end)
if success then
    print("   Результат: " .. tostring(result))
    if result and result > 0 then
        print("   ✅ УСПЕШНО! Предмет выдан с force.")
        return
    end
else
    print("   ❌ Ошибка: " .. tostring(result))
end

-- Способ 3: По одному предмету
print("3. exportItem по одному (1 шт):")
local success, result = pcall(function()
    return me.exportItem(fingerprint, "up", 1)
end)
if success then
    print("   Результат: " .. tostring(result))
    if result and result > 0 then
        print("   ✅ УСПЕШНО! Предмет выдан по одному.")
        return
    end
else
    print("   ❌ Ошибка: " .. tostring(result))
end

-- Способ 4: Проверка simulateExport
print("4. simulateExport (симуляция):")
local success, result = pcall(function()
    return me.simulateExport(fingerprint, "up", 1)
end)
if success then
    print("   Результат: " .. tostring(result))
    if result and result.size and result.size > 0 then
        print("   ✅ Можно выдать " .. result.size .. " шт.")
        -- Пробуем выдать через simulate
        local exportSuccess, exportResult = pcall(function()
            return me.exportItem(fingerprint, "up", 1)
        end)
        if exportSuccess and exportResult and exportResult > 0 then
            print("   ✅ УСПЕШНО! Предмет выдан через simulate.")
            return
        end
    end
else
    print("   ❌ Ошибка: " .. tostring(result))
end

-- Способ 5: Проверка NBT
print("5. Проверка NBT данных:")
local detailSuccess, detailResult = pcall(function()
    return me.getItemDetail(name, damage)
end)
if detailSuccess and detailResult then
    print("   displayName: " .. (detailResult.displayName or "?"))
    print("   maxSize: " .. (detailResult.maxSize or "?"))
    print("   hasNBT: " .. tostring(detailResult.hasNBT or false))
    if detailResult.hasNBT then
        print("   ⚠️ У предмета есть NBT данные! Это может мешать выдаче.")
        print("   Попробуйте использовать предмет без NBT.")
    end
else
    print("   ❌ Не удалось получить детали предмета")
end

-- Способ 6: Проверка других направлений
print("6. Проверка других направлений:")
local dirs = {"down", "north", "south", "west", "east"}
for _, dir in ipairs(dirs) do
    local success, result = pcall(function()
        return me.exportItem(fingerprint, dir, 1)
    end)
    if success and result and result > 0 then
        print("   ✅ Направление " .. dir .. " работает! Выдано " .. result .. " шт.")
        print("   Используйте в коде: PULL_DIRECTION = \"" .. dir .. "\"")
        return
    end
end

print("")
print("=== ВЫВОД ===")
print("❌ Предмет не удалось выдать ни одним способом.")
print("")
print("Возможные причины:")
print("  1. У предмета есть NBT данные (зачарования, энергия, имя)")
print("  2. Предмет не может быть выдан через ME интерфейс")
print("  3. Нет места в инвентаре (проверьте свободные слоты)")
print("  4. Проблема с направлением выдачи")
print("  5. Предмет повреждён (damage не совпадает)")

print("")
print("Нажмите любую клавишу для выхода...")
event.pull("key_down")
