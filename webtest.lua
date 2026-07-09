-- ============================================================
-- ★★★ ТЕСТОВЫЙ СКРИПТ ВЫДАЧИ В PIM (ИСПРАВЛЕННЫЙ) ★★★
-- Сохраните как /home/test_pim_export.lua
-- Запустите: lua /home/test_pim_export.lua11111
-- ============================================================

local component = require("component")
local event = require("event")
local computer = require("computer")

print("")
print("═══════════════════════════════════════════════════════════════")
print("  ТЕСТ ВЫДАЧИ ПРЕДМЕТА В PIM")
print("═══════════════════════════════════════════════════════════════")
print("")

-- 1. Проверяем компоненты
print("1. ПРОВЕРКА КОМПОНЕНТОВ")
print("")

-- ME интерфейс
if not component.isAvailable("me_interface") then
    print("❌ ME интерфейс НЕ ДОСТУПЕН!")
    return
end
local me = component.me_interface
print("✅ ME интерфейс доступен")

-- PIM
local pimAddr = nil
for addr in component.list("pim") do
    pimAddr = addr
    break
end
if not pimAddr then
    print("❌ PIM НЕ НАЙДЕН!")
    return
end
local pim = component.proxy(pimAddr)
print("✅ PIM найден: " .. pimAddr)

-- Проверяем, кто стоит на PIM
local owner = pim.getOwner()
if owner then
    print("   Владелец PIM: " .. owner)
else
    print("   ⚠️ На PIM никого нет! Встаньте на PIM")
    print("   Нажмите любую клавишу после того как встанете...")
    event.pull("key_down")
    owner = pim.getOwner()
    if owner then
        print("   ✅ Теперь на PIM: " .. owner)
    else
        print("   ❌ Всё ещё никого нет на PIM")
        return
    end
end

print("")
print("2. ВВОД ДАННЫХ")
print("")

io.write("  Internal name (например GraviSuite:vajra): ")
local internalName = io.read()
internalName = internalName:match("^%s*(.-)%s*$")

if not internalName or internalName == "" then
    print("   Используем GraviSuite:vajra")
    internalName = "GraviSuite:vajra"
end

io.write("  Damage (Enter для 0): ")
local dmgInput = io.read()
local damage = 0
if dmgInput and dmgInput ~= "" then
    damage = tonumber(dmgInput) or 0
end

io.write("  Количество (Enter для 1): ")
local qtyInput = io.read()
local testQty = 1
if qtyInput and qtyInput ~= "" then
    testQty = tonumber(qtyInput) or 1
end

print("")
print("   Тестируем: " .. internalName .. " (damage: " .. damage .. ") x" .. testQty)
print("")

-- 3. Проверяем наличие предмета в ME
print("3. ПОИСК В ME")
print("")

local fingerprint = { id = internalName, dmg = damage }
local items = me.getItemsInNetwork()
local foundItem = nil

for _, item in ipairs(items) do
    if item.name == internalName and (item.damage or 0) == damage then
        foundItem = item
        break
    end
end

if not foundItem then
    print("❌ Предмет НЕ НАЙДЕН в ME системе!")
    print("")
    print("   Похожие предметы в ME:")
    local count = 0
    for _, item in ipairs(items) do
        if string.find(item.name, internalName:match("[^:]+$") or "") then
            count = count + 1
            if count <= 10 then
                print("     " .. item.name .. " (damage: " .. (item.damage or 0) .. ") - " .. (item.size or 0) .. " шт.")
            end
        end
    end
    if count == 0 then
        print("     Нет похожих предметов. Первые 10 в ME:")
        for i = 1, math.min(10, #items) do
            local item = items[i]
            print("     " .. item.name .. " (damage: " .. (item.damage or 0) .. ") - " .. (item.size or 0) .. " шт.")
        end
    end
    return
end

print("✅ Предмет найден!")
print("   Количество в ME: " .. (foundItem.size or 0) .. " шт.")

if (foundItem.size or 0) < testQty then
    print("⚠️ В ME меньше предметов чем нужно для теста!")
    testQty = foundItem.size or 0
    if testQty == 0 then
        print("❌ Нет предметов для теста")
        return
    end
    print("   Будем тестировать с " .. testQty .. " шт.")
end

print("")
print("4. ПРОВЕРКА ИНВЕНТАРЯ")
print("")

local freeSlots = 0
local slotContents = {}

for slot = 1, 36 do
    local stack = pim.getStackInSlot(slot)
    if stack and stack.size and stack.size > 0 then
        slotContents[slot] = { name = stack.name, size = stack.size, damage = stack.damage or 0 }
    else
        freeSlots = freeSlots + 1
    end
end

print("   Свободных слотов: " .. freeSlots)

if freeSlots == 0 then
    print("❌ ИНВЕНТАРЬ ПОЛОН! Освободите место.")
    print("   Нажмите любую клавишу для выхода...")
    event.pull("key_down")
    return
end

print("   Предметы в инвентаре:")
for slot, data in pairs(slotContents) do
    print("     Слот " .. slot .. ": " .. data.name .. " x" .. data.size)
end

print("")
print("5. ТЕСТОВАЯ ВЫДАЧА")
print("")

-- ★★★ ПРОБУЕМ РАЗНЫЕ СПОСОБЫ ВЫДАЧИ ★★★
local successResult = false

-- Способ 1: Стандартная выдача с направлением "up"
print("   Способ 1: exportItem с направлением 'up'")
local success, result = pcall(function()
    return me.exportItem(fingerprint, "up", testQty)
end)
if success and result and type(result) == "number" and result > 0 then
    print("   ✅ УСПЕШНО! Выдано " .. result .. " шт.")
    print("   Направление 'up' работает!")
    print("")
    print("   ИСПОЛЬЗУЙТЕ В КОДЕ: PULL_DIRECTION = \"up\"")
    successResult = true
else
    print("   ❌ Не работает. Результат: " .. tostring(result))
end

-- Способ 2: Выдача в слот PIM (слот 0 = весь инвентарь)
if not successResult then
    print("")
    print("   Способ 2: exportItem в слот 0 (весь инвентарь)")
    local success, result = pcall(function()
        return me.exportItem(fingerprint, 0, testQty)
    end)
    if success and result and type(result) == "number" and result > 0 then
        print("   ✅ УСПЕШНО! Выдано " .. result .. " шт.")
        print("   Способ со слотом 0 работает!")
        print("")
        print("   ИСПОЛЬЗУЙТЕ В КОДЕ: me.exportItem(fingerprint, 0, toTake)")
        successResult = true
    else
        print("   ❌ Не работает. Результат: " .. tostring(result))
    end
end

-- Способ 3: Выдача в конкретный свободный слот
if not successResult then
    print("")
    print("   Способ 3: exportItem в свободный слот")
    for slot = 1, 36 do
        local stack = pim.getStackInSlot(slot)
        if not stack or stack.size == 0 then
            print("     Пробуем слот " .. slot)
            local success, result = pcall(function()
                return me.exportItem(fingerprint, slot, testQty)
            end)
            if success and result and type(result) == "number" and result > 0 then
                print("   ✅ УСПЕШНО! Выдано " .. result .. " шт. в слот " .. slot)
                print("")
                print("   ИСПОЛЬЗУЙТЕ В КОДЕ: me.exportItem(fingerprint, slot, toTake)")
                print("   где slot - номер свободного слота")
                successResult = true
                break
            else
                print("     ❌ Не работает. Результат: " .. tostring(result))
            end
        end
    end
end

-- Способ 4: Выдача с force = true (если есть)
if not successResult then
    print("")
    print("   Способ 4: exportItem с force = true")
    local success, result = pcall(function()
        return me.exportItem(fingerprint, "up", testQty, true)
    end)
    if success and result and type(result) == "number" and result > 0 then
        print("   ✅ УСПЕШНО! Выдано " .. result .. " шт.")
        successResult = true
    else
        print("   ❌ Не работает. Результат: " .. tostring(result))
    end
end

-- Если ничего не сработало
if not successResult then
    print("")
    print("❌ НИ ОДИН СПОСОБ НЕ СРАБОТАЛ!")
    print("")
    print("Возможные причины:")
    print("  1. ME интерфейс не подключён к сети хранения")
    print("  2. Предмет не может быть выдан через ME (NBT, особый предмет)")
    print("  3. Проблема с PIM (не настроен на приём)")
    print("  4. В инвентаре нет места для этого конкретного предмета")
    print("  5. Нужно использовать другой метод выдачи")
    print("")
    print("Нажмите любую клавишу для выхода...")
    event.pull("key_down")
    return
end

-- Если успешно
print("")
print("═══════════════════════════════════════════════════════════════")
print("  ✅ ТЕСТ ЗАВЕРШЁН УСПЕШНО!")
print("═══════════════════════════════════════════════════════════════")
print("")

-- Проверяем, что предмет появился в инвентаре
print("ПРОВЕРКА ИНВЕНТАРЯ ПОСЛЕ ВЫДАЧИ:")
for slot = 1, 36 do
    local stack = pim.getStackInSlot(slot)
    if stack and stack.size and stack.size > 0 then
        print("  Слот " .. slot .. ": " .. stack.name .. " x" .. stack.size)
    end
end

print("")
print("Нажмите любую клавишу для выхода...")
event.pull("key_down")
