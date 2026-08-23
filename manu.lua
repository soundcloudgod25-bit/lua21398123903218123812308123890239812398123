-- Standalone 1:1-style Lua port of the provided C++ menu.
-- Uses: renderer.*, ui.mouse_position, ui.is_menu_open, client.key_state, globals.frametime.

local hrisito_ui = {}

local VK_LBUTTON = 0x01
local VK_ESCAPE = 0x1B
local VK_INSERT = 0x2D

local LABEL_OFFSET = 15
local CHECKBOX_SIZE = 8
local SLIDER_X_OFFSET = 20
local SLIDER_HEIGHT = 8
local BUTTON_X_OFFSET = 20
local BUTTON_BOX_HEIGHT = 20
local BUTTON_ITEM_X_OFFSET = 10
local DROPDOWN_X_OFFSET = 20
local DROPDOWN_ITEM_X_OFFSET = 10
local DROPDOWN_ITEM_Y_OFFSET = 5
local DROPDOWN_BOX_HEIGHT = 20
local DROPDOWN_ITEM_HEIGHT = 16
local DROPDOWN_SEPARATOR = 2
local COLORPICKER_WIDTH = 20
local COLORPICKER_HEIGHT = 8
local COLORPICKER_PICKER_SIZE = 160
local KEYBIND_X_OFFSET = 20
local KEYBIND_BOX_HEIGHT = 20
local KEYBIND_ITEM_X_OFFSET = 10

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function round_to_step(v, step)
    if step == 0 then return v end
    return math.floor((v / step) + 0.5) * step
end

local function rgba(c, alpha)
    return c[1], c[2], c[3], alpha or c[4] or 255
end

local function color(r, g, b, a)
    return { r, g, b, a or 255 }
end

local function in_rect(mx, my, r)
    return mx >= r.x and my >= r.y and mx <= r.x + r.w and my <= r.y + r.h
end

local function rect(x, y, w, h, c)
    renderer.rectangle(x, y, w, 1, rgba(c))
    renderer.rectangle(x, y + h - 1, w, 1, rgba(c))
    renderer.rectangle(x, y, 1, h, rgba(c))
    renderer.rectangle(x + w - 1, y, 1, h, rgba(c))
end

local function filled(x, y, w, h, c)
    if w > 0 and h > 0 then
        renderer.rectangle(x, y, w, h, rgba(c))
    end
end

local function gradient(x, y, w, h, c1, c2, ltr)
    if w > 0 and h > 0 then
        renderer.gradient(x, y, w, h, c1[1], c1[2], c1[3], c1[4] or 255, c2[1], c2[2], c2[3], c2[4] or 255, ltr)
    end
end

local function text(x, y, c, flags, value, max_width)
    renderer.text(x, y, c[1], c[2], c[3], c[4] or 255, flags, max_width or 0, tostring(value or ""))
end

local function measure(value, flags)
    return renderer.measure_text(flags, tostring(value or ""))
end

local input = {
    down = {},
    pressed = {},
    mouse = { x = 0, y = 0 },
}

function input:update()
    self.mouse.x, self.mouse.y = ui.mouse_position()
    self.pressed = {}

    for key = 1, 254 do
        local is_down = client.key_state(key)
        self.pressed[key] = is_down and not self.down[key]
        self.down[key] = is_down
    end
end

function input:key_down(key)
    return self.down[key] == true
end

function input:key_pressed(key)
    return self.pressed[key] == true
end

local keynames = {
    [0x01] = "mouse1", [0x02] = "mouse2", [0x04] = "mouse3", [0x05] = "mouse4", [0x06] = "mouse5",
    [0x08] = "backspace", [0x09] = "tab", [0x0D] = "enter", [0x10] = "shift", [0x11] = "ctrl",
    [0x12] = "alt", [0x14] = "capslock", [0x1B] = "esc", [0x20] = "space", [0x21] = "pgup",
    [0x22] = "pgdown", [0x23] = "end", [0x24] = "home", [0x25] = "left", [0x26] = "up",
    [0x27] = "right", [0x28] = "down", [0x2D] = "insert", [0x2E] = "delete",
    [0x60] = "num 0", [0x61] = "num 1", [0x62] = "num 2", [0x63] = "num 3", [0x64] = "num 4",
    [0x65] = "num 5", [0x66] = "num 6", [0x67] = "num 7", [0x68] = "num 8", [0x69] = "num 9",
    [0x6A] = "num mult", [0x6B] = "num plus", [0x6D] = "num sub", [0x6E] = "num decimal", [0x6F] = "num divide",
    [0xBA] = ";", [0xBB] = "=", [0xBC] = ",", [0xBD] = "-", [0xBE] = ".", [0xBF] = "/", [0xC0] = "grave",
    [0xDB] = "[", [0xDC] = "\\", [0xDD] = "]",
}

for i = 0x30, 0x39 do keynames[i] = string.char(i) end
for i = 0x41, 0x5A do keynames[i] = string.char(i + 32) end
for i = 1, 24 do keynames[0x6F + i] = "f" .. i end

local Element = {}
Element.__index = Element

function Element:new(kind)
    local o = setmetatable({}, self)
    o.kind = kind
    o.parent = nil
    o.x, o.y, o.w, o.h = 0, 0, 220, 16
    o.base_h = o.h
    o.show = true
    o.use_label = true
    o.callbacks = {}
    o.show_callbacks = {}
    return o
end

function Element:AddCallback(fn)
    self.callback = fn
    return self
end

function Element:AddShowCallback(fn)
    table.insert(self.show_callbacks, fn)
    return self
end

function Element:update_visibility()
    self.show = true
    for _, fn in ipairs(self.show_callbacks) do
        if not fn() then
            self.show = false
            break
        end
    end
end

function Element:fire()
    if self.callback then self.callback(self) end
end

function Element:absolute()
    local area = self.parent.form:GetElementsRect()
    return area.x + self.x, area.y + self.y
end

local Checkbox = setmetatable({}, Element)
Checkbox.__index = Checkbox

function Checkbox:new(label, file_id, use_label, default_value)
    local o = Element.new(self, "checkbox")
    o.value = default_value == true
    o.label = use_label == false and "" or (label or "")
    o.file_id = file_id
    o.w, o.h, o.base_h = CHECKBOX_SIZE, CHECKBOX_SIZE, CHECKBOX_SIZE
    return o
end

function Checkbox:set(value)
    local changed = self.value ~= value
    self.value = value == true
    if changed then self:fire() end
end

function Checkbox:get()
    return self.value
end

function Checkbox:think()
    if self.label ~= "" then
        local tw = measure(self.label, nil)
        self.w = LABEL_OFFSET + tw
    end
end

function Checkbox:draw(alpha, accent)
    local x, y = self:absolute()
    rect(x, y, CHECKBOX_SIZE, CHECKBOX_SIZE, color(0, 0, 0, alpha))
    rect(x + 1, y + 1, CHECKBOX_SIZE - 2, CHECKBOX_SIZE - 2, color(0, 0, 0, alpha))

    if self.label ~= "" then
        text(x + LABEL_OFFSET, y - 3, color(205, 205, 205, alpha), nil, self.label)
    end

    if self.value then
        filled(x + 1, y + 1, CHECKBOX_SIZE - 2, CHECKBOX_SIZE - 2, color(accent[1], accent[2], accent[3], alpha))
        gradient(x + 1, y + 1, CHECKBOX_SIZE - 2, CHECKBOX_SIZE - 2, color(50, 50, 35, alpha), color(50, 50, 35, 0), false)
    else
        gradient(x + 1, y + 1, CHECKBOX_SIZE - 2, CHECKBOX_SIZE - 2, color(75, 75, 75, alpha), color(50, 50, 50, alpha), false)
    end
end

function Checkbox:click()
    self:set(not self.value)
end

local Slider = setmetatable({}, Element)
Slider.__index = Slider

function Slider:new(label, file_id, min_value, max_value, use_label, precision, value, step, suffix)
    local o = Element.new(self, "slider")
    o.label = use_label == false and "" or (label or "")
    o.file_id = file_id
    o.min = min_value or 0
    o.max = max_value or 100
    o.value = value or o.min
    o.step = step or 1
    o.precision = precision or 0
    o.suffix = suffix or ""
    o.drag = false
    o.fill = 0
    o.offset = o.label ~= "" and 15 or 0
    o.h, o.base_h = o.offset + SLIDER_HEIGHT, o.offset + SLIDER_HEIGHT
    return o
end

function Slider:set(value)
    local next_value = clamp(round_to_step(value, self.step), self.min, self.max)
    local changed = next_value ~= self.value
    self.value = next_value
    if changed then self:fire() end
end

function Slider:get()
    return self.value
end

function Slider:think()
    local x, y = self:absolute()
    local width = self.w - SLIDER_X_OFFSET
    local range = self.max - self.min
    local ratio = range == 0 and 0 or (self.value - self.min) / range
    self.fill = math.floor(clamp(ratio, 0, 1) * width)

    if self.drag then
        if input:key_down(VK_LBUTTON) then
            local next_value = self.min + ((input.mouse.x - (x + SLIDER_X_OFFSET)) / width) * range
            self:set(next_value)
        else
            self.drag = false
        end
    end
end

function Slider:draw(alpha, accent)
    local x, y = self:absolute()
    if self.label ~= "" then
        text(x + LABEL_OFFSET, y - 2, color(205, 205, 205, alpha), nil, self.label)
    end

    local bx, by, bw = x + SLIDER_X_OFFSET, y + self.offset, self.w - SLIDER_X_OFFSET
    rect(bx, by, bw, SLIDER_HEIGHT, color(0, 0, 0, alpha))
    gradient(bx + 1, by + 1, bw - 2, SLIDER_HEIGHT - 2, color(75, 75, 75, alpha), color(50, 50, 50, alpha), false)
    filled(bx + 1, by + 1, self.fill - 2, SLIDER_HEIGHT - 2, color(accent[1], accent[2], accent[3], alpha))
    gradient(bx + 1, by + 1, self.fill - 2, SLIDER_HEIGHT - 2, color(50, 50, 35, alpha), color(50, 50, 35, 0), false)

    local value_text = string.format("%." .. self.precision .. "f%s", self.value, self.suffix)
    local tw = measure(value_text, nil)
    text(bx + self.fill - math.floor(tw / 2), by + 1, color(255, 255, 255, alpha), nil, value_text)
end

function Slider:click()
    local x, y = self:absolute()
    local r = { x = x + SLIDER_X_OFFSET, y = y + self.offset, w = self.w - SLIDER_X_OFFSET, h = SLIDER_HEIGHT }
    if in_rect(input.mouse.x, input.mouse.y, r) then
        self.drag = true
        self:think()
    end
end

local Button = setmetatable({}, Element)
Button.__index = Button

function Button:new(label, callback)
    local o = Element.new(self, "button")
    o.label = label or ""
    o.callback = callback
    o.h, o.base_h = BUTTON_BOX_HEIGHT, BUTTON_BOX_HEIGHT
    return o
end

function Button:draw(alpha)
    local x, y = self:absolute()
    rect(x + BUTTON_X_OFFSET, y, self.w - BUTTON_X_OFFSET, BUTTON_BOX_HEIGHT, color(0, 0, 0, alpha))
    filled(x + BUTTON_X_OFFSET + 1, y + 1, self.w - BUTTON_X_OFFSET - 2, BUTTON_BOX_HEIGHT - 2, color(41, 41, 41, alpha))
    text(x + math.floor((BUTTON_X_OFFSET + self.w) / 2), y + 4, color(205, 205, 205, alpha), "c", self.label)
end

function Button:click()
    local x, y = self:absolute()
    local r = { x = x + BUTTON_X_OFFSET, y = y, w = self.w - BUTTON_X_OFFSET, h = BUTTON_BOX_HEIGHT }
    if in_rect(input.mouse.x, input.mouse.y, r) then self:fire() end
end

local Dropdown = setmetatable({}, Element)
Dropdown.__index = Dropdown

function Dropdown:new(label, file_id, items, use_label, active)
    local o = Element.new(self, "dropdown")
    o.label = use_label == false and "" or (label or "")
    o.file_id = file_id
    o.items = items or {}
    o.active = active or 1
    o.open = false
    o.anim_height = 0
    o.offset = o.label ~= "" and 15 or 0
    o.h, o.base_h = o.offset + DROPDOWN_BOX_HEIGHT, o.offset + DROPDOWN_BOX_HEIGHT
    return o
end

function Dropdown:set(index)
    local changed = self.active ~= index
    self.active = clamp(index, 1, #self.items)
    if changed then self:fire() end
end

function Dropdown:get()
    return self.active
end

function Dropdown:GetActiveItem()
    return self.items[self.active] or "error"
end

function Dropdown:think()
    local total = DROPDOWN_ITEM_HEIGHT * #self.items
    local step = total / 0.3 * globals.frametime()
    self.anim_height = clamp(self.anim_height + (self.open and step or -step), 0, total)

    if self.open then
        self.h = self.offset + DROPDOWN_BOX_HEIGHT + DROPDOWN_SEPARATOR + total
        if self.parent.form.active_element ~= self then self.open = false end
    else
        self.h = self.offset + DROPDOWN_BOX_HEIGHT
    end
end

local function arrow_down(x, y, alpha)
    renderer.triangle(x, y, x + 6, y, x + 3, y + 4, 152, 152, 152, alpha)
end

local function arrow_up(x, y, alpha)
    renderer.triangle(x, y + 4, x + 6, y + 4, x + 3, y, 152, 152, 152, alpha)
end

function Dropdown:draw(alpha, accent)
    local x, y = self:absolute()
    if self.label ~= "" then text(x + LABEL_OFFSET, y - 2, color(205, 205, 205, alpha), nil, self.label) end

    local bx, by, bw = x + DROPDOWN_X_OFFSET, y + self.offset, self.w - DROPDOWN_X_OFFSET
    rect(bx, by, bw, DROPDOWN_BOX_HEIGHT, color(0, 0, 0, alpha))
    filled(bx + 1, by + 1, bw - 2, DROPDOWN_BOX_HEIGHT - 2, color(41, 41, 41, alpha))
    if self.open then arrow_up(x + self.w - 11, by + 8, alpha) else arrow_down(x + self.w - 11, by + 8, alpha) end

    text(bx + DROPDOWN_ITEM_X_OFFSET, by + 4, color(152, 152, 152, alpha), nil, self:GetActiveItem(), bw - 22)

    if self.open and #self.items > 0 then
        local iy = by + DROPDOWN_BOX_HEIGHT + DROPDOWN_SEPARATOR
        rect(bx, iy, bw, self.anim_height + 1, color(0, 0, 0, alpha))
        filled(bx + 1, iy + 1, bw - 2, self.anim_height - 1, color(41, 41, 41, alpha))

        for i, item in ipairs(self.items) do
            local item_y = iy + (i - 1) * DROPDOWN_ITEM_HEIGHT
            if self.anim_height > (i - 1) * DROPDOWN_ITEM_HEIGHT then
                local c = i == self.active and color(accent[1], accent[2], accent[3], alpha) or color(152, 152, 152, alpha)
                text(bx + DROPDOWN_ITEM_X_OFFSET, item_y + DROPDOWN_ITEM_Y_OFFSET, c, nil, item, bw - 20)
            end
        end
    end
end

function Dropdown:click()
    local x, y = self:absolute()
    local bx, by, bw = x + DROPDOWN_X_OFFSET, y + self.offset, self.w - DROPDOWN_X_OFFSET
    local bar = { x = bx, y = by, w = bw, h = DROPDOWN_BOX_HEIGHT }

    if in_rect(input.mouse.x, input.mouse.y, bar) then
        self.open = true
        self.parent.form.active_element = self
        return
    end

    if self.open then
        for i = 1, #self.items do
            local item = { x = bx, y = by + DROPDOWN_BOX_HEIGHT + DROPDOWN_SEPARATOR + (i - 1) * DROPDOWN_ITEM_HEIGHT, w = bw, h = DROPDOWN_ITEM_HEIGHT }
            if in_rect(input.mouse.x, input.mouse.y, item) then
                self:set(i)
                return
            end
        end
    end
end

local MultiDropdown = setmetatable({}, Dropdown)
MultiDropdown.__index = MultiDropdown

function MultiDropdown:new(label, file_id, items, use_label, active)
    local o = Dropdown.new(self, label, file_id, items, use_label, 1)
    o.kind = "multidropdown"
    o.active = {}
    for _, index in ipairs(active or {}) do o.active[index] = true end
    return o
end

function MultiDropdown:get(index)
    return self.active[index] == true
end

function MultiDropdown:GetActiveIndices()
    local out = {}
    for i = 1, #self.items do
        if self.active[i] then table.insert(out, i) end
    end
    return out
end

function MultiDropdown:GetActiveItems()
    local out = {}
    for _, i in ipairs(self:GetActiveIndices()) do table.insert(out, self.items[i]) end
    return out
end

function MultiDropdown:clear()
    self.active = {}
    self:fire()
end

function MultiDropdown:empty()
    return #self:GetActiveIndices() == 0
end

function MultiDropdown:select(index)
    if index >= 1 and index <= #self.items and not self.active[index] then
        self.active[index] = true
        self:fire()
    end
end

function MultiDropdown:summary(width)
    local active = self:GetActiveItems()
    if #active == 0 then return "none" end
    if #active == 1 then return active[1] end

    local out = ""
    for i, item in ipairs(active) do
        local next_out = out .. (i > 1 and ", " or "") .. item
        local tw = measure(next_out .. "...", nil)
        if tw >= width then return out .. "..." end
        out = next_out
    end
    return out
end

function MultiDropdown:draw(alpha, accent)
    local x, y = self:absolute()
    local bx, by, bw = x + DROPDOWN_X_OFFSET, y + self.offset, self.w - DROPDOWN_X_OFFSET

    if self.label ~= "" then text(x + LABEL_OFFSET, y - 2, color(205, 205, 205, alpha), nil, self.label) end
    rect(bx, by, bw, DROPDOWN_BOX_HEIGHT, color(0, 0, 0, alpha))
    filled(bx + 1, by + 1, bw - 2, DROPDOWN_BOX_HEIGHT - 2, color(41, 41, 41, alpha))
    if self.open then arrow_up(x + self.w - 11, by + 8, alpha) else arrow_down(x + self.w - 11, by + 8, alpha) end
    text(bx + DROPDOWN_ITEM_X_OFFSET, by + 4, color(152, 152, 152, alpha), nil, self:summary(bw - 32), bw - 24)

    if self.open then
        local iy = by + DROPDOWN_BOX_HEIGHT + DROPDOWN_SEPARATOR
        rect(bx, iy, bw, self.anim_height + 1, color(0, 0, 0, alpha))
        filled(bx + 1, iy + 1, bw - 2, self.anim_height - 1, color(41, 41, 41, alpha))

        for i, item in ipairs(self.items) do
            local item_y = iy + (i - 1) * DROPDOWN_ITEM_HEIGHT
            if self.anim_height > (i - 1) * DROPDOWN_ITEM_HEIGHT then
                local c = self.active[i] and color(accent[1], accent[2], accent[3], alpha) or color(152, 152, 152, alpha)
                text(bx + DROPDOWN_ITEM_X_OFFSET, item_y + DROPDOWN_ITEM_Y_OFFSET, c, nil, item, bw - 20)
            end
        end
    end
end

function MultiDropdown:click()
    local x, y = self:absolute()
    local bx, by, bw = x + DROPDOWN_X_OFFSET, y + self.offset, self.w - DROPDOWN_X_OFFSET
    local bar = { x = bx, y = by, w = bw, h = DROPDOWN_BOX_HEIGHT }

    if in_rect(input.mouse.x, input.mouse.y, bar) then
        self.open = not self.open
        self.parent.form.active_element = self
        return
    end

    if self.open then
        for i = 1, #self.items do
            local item = { x = bx, y = by + DROPDOWN_BOX_HEIGHT + DROPDOWN_SEPARATOR + (i - 1) * DROPDOWN_ITEM_HEIGHT, w = bw, h = DROPDOWN_ITEM_HEIGHT }
            if in_rect(input.mouse.x, input.mouse.y, item) then
                self.active[i] = not self.active[i]
                self:fire()
                return
            end
        end
    end
end

local function hsl_to_rgb(h, s, l)
    local function hue_to_rgb(p, q, t)
        if t < 0 then t = t + 1 end
        if t > 1 then t = t - 1 end
        if t < 1 / 6 then return p + (q - p) * 6 * t end
        if t < 1 / 2 then return q end
        if t < 2 / 3 then return p + (q - p) * (2 / 3 - t) * 6 end
        return p
    end

    if s == 0 then return l * 255, l * 255, l * 255 end
    local q = l < 0.5 and l * (1 + s) or l + s - l * s
    local p = 2 * l - q
    return hue_to_rgb(p, q, h + 1 / 3) * 255, hue_to_rgb(p, q, h) * 255, hue_to_rgb(p, q, h - 1 / 3) * 255
end

local Colorpicker = setmetatable({}, Element)
Colorpicker.__index = Colorpicker

function Colorpicker:new(label, file_id, initial)
    local o = Element.new(self, "colorpicker")
    o.label = label or ""
    o.file_id = file_id
    o.value = initial or color(255, 255, 255, 255)
    o.open = false
    o.h, o.base_h = COLORPICKER_HEIGHT, COLORPICKER_HEIGHT
    return o
end

function Colorpicker:set(c)
    self.value = { c[1], c[2], c[3], c[4] or self.value[4] or 255 }
    self:fire()
end

function Colorpicker:get()
    return self.value[1], self.value[2], self.value[3], self.value[4]
end

function Colorpicker:draw(alpha)
    local x, y = self:absolute()
    text(x + LABEL_OFFSET, y - 2, color(205, 205, 205, alpha), nil, self.label)

    local px = x + self.w - COLORPICKER_WIDTH
    rect(px, y, COLORPICKER_WIDTH, COLORPICKER_HEIGHT, color(0, 0, 0, alpha))
    filled(px + 1, y + 1, COLORPICKER_WIDTH - 2, COLORPICKER_HEIGHT - 2, color(self.value[1], self.value[2], self.value[3], alpha))
    gradient(px + 1, y + 1, COLORPICKER_WIDTH - 2, COLORPICKER_HEIGHT - 2, color(50, 50, 35, alpha), color(50, 50, 35, 0), false)

    if self.open then
        local picker_y = y + COLORPICKER_HEIGHT + 2
        for i = 0, COLORPICKER_PICKER_SIZE - 1 do
            local r, g, b = hsl_to_rgb(i / COLORPICKER_PICKER_SIZE, 0.99, 0.5)
            renderer.gradient(px + i, picker_y, 1, COLORPICKER_PICKER_SIZE, r, g, b, alpha, 0, 0, 0, alpha, false)
        end
        rect(px, picker_y, COLORPICKER_PICKER_SIZE, COLORPICKER_PICKER_SIZE, color(0, 0, 0, alpha))
    end
end

function Colorpicker:think()
    if not self.open then return end

    local x, y = self:absolute()
    local px, py = x + self.w - COLORPICKER_WIDTH, y + COLORPICKER_HEIGHT + 2
    local picker = { x = px, y = py, w = COLORPICKER_PICKER_SIZE, h = COLORPICKER_PICKER_SIZE }

    if input:key_down(VK_LBUTTON) and in_rect(input.mouse.x, input.mouse.y, picker) then
        local hue = clamp((input.mouse.x - px) / COLORPICKER_PICKER_SIZE, 0, 1)
        local lum = 1 - clamp((input.mouse.y - py) / COLORPICKER_PICKER_SIZE, 0, 1)
        local r, g, b = hsl_to_rgb(hue, 0.99, lum * 0.5)
        self.value = color(math.floor(r), math.floor(g), math.floor(b), self.value[4] or 255)
    elseif not input:key_down(VK_LBUTTON) or self.parent.form.active_element ~= self then
        self.open = false
        self:fire()
    end
end

function Colorpicker:click()
    local x, y = self:absolute()
    local preview = { x = x + self.w - COLORPICKER_WIDTH, y = y, w = COLORPICKER_WIDTH, h = COLORPICKER_HEIGHT }
    if in_rect(input.mouse.x, input.mouse.y, preview) then
        self.open = true
        self.parent.form.active_element = self
    end
end

local Keybind = setmetatable({}, Element)
Keybind.__index = Keybind

function Keybind:new(label, file_id, key)
    local o = Element.new(self, "keybind")
    o.label = label or ""
    o.file_id = file_id
    o.key = key or -1
    o.set_mode = false
    o.old_set = false
    o.h, o.base_h = 15 + KEYBIND_BOX_HEIGHT, 15 + KEYBIND_BOX_HEIGHT
    return o
end

function Keybind:set(key)
    local changed = self.key ~= key
    self.key = key
    if changed then self:fire() end
end

function Keybind:get()
    return self.key
end

function Keybind:think()
    if self.set_mode then
        for key = 1, 254 do
            if input:key_pressed(key) then
                if key == VK_ESCAPE then self.key = -1 else self.key = key end
                self.set_mode = false
                self.old_set = true
                self:fire()
                return
            end
        end
    else
        self.old_set = false
    end
end

function Keybind:draw(alpha, accent)
    local x, y = self:absolute()
    text(x + KEYBIND_X_OFFSET, y - 2, color(205, 205, 205, alpha), nil, self.label)
    rect(x + KEYBIND_X_OFFSET, y + 15, self.w - KEYBIND_X_OFFSET, KEYBIND_BOX_HEIGHT, color(0, 0, 0, alpha))
    filled(x + KEYBIND_X_OFFSET + 1, y + 16, self.w - KEYBIND_X_OFFSET - 2, KEYBIND_BOX_HEIGHT - 2, color(41, 41, 41, alpha))

    if self.set_mode then
        text(x + KEYBIND_X_OFFSET + KEYBIND_ITEM_X_OFFSET, y + 19, color(accent[1], accent[2], accent[3], alpha), nil, "press key")
    elseif self.key >= 0 then
        text(x + KEYBIND_X_OFFSET + KEYBIND_ITEM_X_OFFSET, y + 19, color(152, 152, 152, alpha), nil, keynames[self.key] or ("[" .. self.key .. "]"))
    end
end

function Keybind:click()
    local x, y = self:absolute()
    local bind = { x = x + KEYBIND_X_OFFSET, y = y + 15, w = self.w - KEYBIND_X_OFFSET, h = KEYBIND_BOX_HEIGHT }
    if not self.set_mode and not self.old_set and in_rect(input.mouse.x, input.mouse.y, bind) then
        self.set_mode = true
        self.parent.form.active_element = self
    end
end


local Edit = setmetatable({}, Element)
Edit.__index = Edit

function Edit:new(label, file_id, value)
    local o = Element.new(self, "edit")
    o.label = label or ""
    o.file_id = file_id
    o.value = tostring(value or "")
    o.editing = false
    o.h, o.base_h = 15 + BUTTON_BOX_HEIGHT, 15 + BUTTON_BOX_HEIGHT
    return o
end

function Edit:set(value)
    local next_value = tostring(value or "")
    local changed = self.value ~= next_value
    self.value = next_value
    if changed then self:fire() end
end

function Edit:get()
    return self.value
end

function Edit:draw(alpha, accent)
    local x, y = self:absolute()
    text(x + BUTTON_X_OFFSET, y - 2, color(205, 205, 205, alpha), nil, self.label)
    rect(x + BUTTON_X_OFFSET, y + 15, self.w - BUTTON_X_OFFSET, BUTTON_BOX_HEIGHT, color(0, 0, 0, alpha))
    filled(x + BUTTON_X_OFFSET + 1, y + 16, self.w - BUTTON_X_OFFSET - 2, BUTTON_BOX_HEIGHT - 2, color(41, 41, 41, alpha))
    local shown = self.editing and (self.value .. "_") or self.value
    text(x + BUTTON_X_OFFSET + BUTTON_ITEM_X_OFFSET, y + 19, color(152, 152, 152, alpha), nil, shown, self.w - BUTTON_X_OFFSET - 12)
end

function Edit:click()
    local x, y = self:absolute()
    local r = { x = x + BUTTON_X_OFFSET, y = y + 15, w = self.w - BUTTON_X_OFFSET, h = BUTTON_BOX_HEIGHT }
    self.editing = in_rect(input.mouse.x, input.mouse.y, r)
end
local Tab = {}
Tab.__index = Tab

function Tab:new(title)
    return setmetatable({ title = title or "", elements = {}, form = nil, columns = { 0, 0 } }, self)
end

function Tab:SetTitle(title)
    self.title = title
    return self
end

function Tab:RegisterElement(element, column)
    column = (column or 0) + 1
    element.parent = self
    local elements_w = self.form and self.form:GetElementsRect().w or 480
    element.x = column == 1 and 20 or math.floor(elements_w / 2) + 10
    element.y = 20 + self.columns[column]
    element.w = math.floor(elements_w / 2) - 30
    element.column = column
    self.columns[column] = self.columns[column] + element.base_h + 12
    table.insert(self.elements, element)
    return element
end

function Tab:reflow()
    self.columns = { 0, 0 }
    local elements_w = self.form and self.form:GetElementsRect().w or 480

    for _, element in ipairs(self.elements) do
        local column = element.column or 1
        element.x = column == 1 and 20 or math.floor(elements_w / 2) + 10
        element.y = 20 + self.columns[column]
        element.w = math.floor(elements_w / 2) - 30
        self.columns[column] = self.columns[column] + element.base_h + 12
    end
end

function Tab:add(element, options)
    options = options or {}
    self:RegisterElement(element, options.column)

    if options.callback then
        element:AddCallback(options.callback)
    end

    if options.visible_if then
        element:AddShowCallback(options.visible_if)
    end

    return element
end

function Tab:checkbox(label, options)
    options = options or {}
    return self:add(Checkbox:new(label, options.id or label, options.use_label, options.default), options)
end

function Tab:slider(label, min_value, max_value, options)
    options = options or {}
    return self:add(Slider:new(
        label,
        options.id or label,
        min_value,
        max_value,
        options.use_label,
        options.precision,
        options.default,
        options.step,
        options.suffix
    ), options)
end

function Tab:button(label, callback, options)
    options = options or {}
    options.callback = callback or options.callback
    return self:add(Button:new(label), options)
end

function Tab:dropdown(label, items, options)
    options = options or {}
    return self:add(Dropdown:new(label, options.id or label, items, options.use_label, options.default), options)
end

function Tab:multidropdown(label, items, options)
    options = options or {}
    return self:add(MultiDropdown:new(label, options.id or label, items, options.use_label, options.default), options)
end

function Tab:colorpicker(label, options)
    options = options or {}
    return self:add(Colorpicker:new(label, options.id or label, options.default), options)
end

function Tab:keybind(label, options)
    options = options or {}
    return self:add(Keybind:new(label, options.id or label, options.default), options)
end

local Form = {}
Form.__index = Form

function Form:new(x, y, w, h, toggle_key)
    return setmetatable({
        open = true,
        opacity = 1,
        alpha = 255,
        key = toggle_key or VK_INSERT,
        x = x or 200,
        y = y or 160,
        w = w or 620,
        h = h or 430,
        tabs = {},
        active_tab = nil,
        active_element = nil,
        color = color(140, 180, 255, 255),
        dragging = false,
        drag_x = 0,
        drag_y = 0,
        visibility_checkbox = nil,
    }, self)
end

function Form:SetPosition(x, y)
    self.x, self.y = x, y
end

function Form:SetSize(w, h)
    self.w, self.h = w, h
end

function Form:SetToggle(key)
    self.key = key
end

function Form:SetVisibilityCheckbox(item)
    self.visibility_checkbox = item
    return item
end

function Form:CreateVisibilityCheckbox(tab, container, name)
    self.visibility_checkbox = ui.new_checkbox(tab or "LUA", container or "B", name or "Show custom menu")
    ui.set(self.visibility_checkbox, true)
    return self.visibility_checkbox
end

function Form:SetColor(r, g, b, a)
    self.color = color(r, g, b, a or 255)
end

function Form:RegisterTab(tab)
    tab.form = self
    tab:reflow()
    table.insert(self.tabs, tab)
    if not self.active_tab then self.active_tab = tab end
    return tab
end

function Form:tab(title)
    return self:RegisterTab(Tab:new(title))
end

function Form:GetClientRect()
    return { x = self.x + 6, y = self.y + 6, w = self.w - 12, h = self.h - 12 }
end

function Form:GetTabsRect()
    return { x = self.x + 20, y = self.y + 20, w = 100, h = self.h - 40 }
end

function Form:GetElementsRect()
    local tabs = self:GetTabsRect()
    return { x = tabs.x + tabs.w + 20, y = self.y + 20, w = self.w - tabs.w - 60, h = self.h - 40 }
end

function Form:process_input()
    if self.visibility_checkbox and not ui.get(self.visibility_checkbox) then
        self.open = false
        self.active_element = nil
        self.dragging = false
        return
    end

    if input:key_pressed(self.key) then self.open = not self.open end

    if not self.open and self.opacity <= 0 then return end

    if input:key_pressed(VK_LBUTTON) and self.alpha > 0 then
        local mx, my = input.mouse.x, input.mouse.y
        local tabs = self:GetTabsRect()

        for i, tab in ipairs(self.tabs) do
            local tab_rect = { x = tabs.x, y = tabs.y + (i - 1) * 16, w = tabs.w, h = 16 }
            if in_rect(mx, my, tab_rect) then
                self.active_tab = tab
                self.active_element = nil
                return
            end
        end

        local clicked_element = nil
        if self.active_tab then
            for i = #self.active_tab.elements, 1, -1 do
                local e = self.active_tab.elements[i]
                if e.show then
                    local ex, ey = e:absolute()
                    local bounds = { x = ex, y = ey, w = e.w, h = e.h }
                    if in_rect(mx, my, bounds) then
                        clicked_element = e
                        self.active_element = e
                        e:click()
                        break
                    end
                end
            end
        end

        if not clicked_element then
            local title = { x = self.x, y = self.y, w = self.w, h = 18 }
            if in_rect(mx, my, title) then
                self.dragging = true
                self.drag_x, self.drag_y = mx - self.x, my - self.y
            else
                self.active_element = nil
            end
        end
    elseif not input:key_down(VK_LBUTTON) then
        self.dragging = false
    end

    if self.dragging then
        self.x = input.mouse.x - self.drag_x
        self.y = input.mouse.y - self.drag_y
    end
end

function Form:think()
    if self.active_tab then
        for _, e in ipairs(self.active_tab.elements) do
            e:update_visibility()
            if e.show and e.think then e:think() end
        end
    end
end

function Form:draw()
    local step = (1 / 0.5) * globals.frametime()
    self.opacity = clamp(self.opacity + (self.open and step or -step), 0, 1)
    self.alpha = math.floor(255 * self.opacity)
    if self.alpha <= 0 then return end

    local a = self.alpha
    local accent = color(self.color[1], self.color[2], self.color[3], a)

    filled(self.x, self.y, self.w, self.h, color(12, 12, 12, a))
    rect(self.x, self.y, self.w, self.h, color(5, 5, 5, a))
    rect(self.x + 1, self.y + 1, self.w - 2, self.h - 2, color(60, 60, 60, a))
    rect(self.x + 2, self.y + 2, self.w - 4, self.h - 4, color(40, 40, 40, a))
    rect(self.x + 5, self.y + 5, self.w - 10, self.h - 10, color(60, 60, 60, a))

    local tabs = self:GetTabsRect()
    filled(tabs.x, tabs.y, tabs.w, tabs.h, color(17, 17, 17, a))
    rect(tabs.x, tabs.y, tabs.w, tabs.h, color(0, 0, 0, a))
    rect(tabs.x + 1, tabs.y + 1, tabs.w - 2, tabs.h - 2, color(48, 48, 48, a))

    for i, tab in ipairs(self.tabs) do
        local c = tab == self.active_tab and accent or color(152, 152, 152, a)
        text(tabs.x + 10, tabs.y + 5 + (i - 1) * 16, c, nil, tab.title)
    end

    if self.active_tab then
        local el = self:GetElementsRect()
        filled(el.x, el.y, el.w, el.h, color(17, 17, 17, a))
        rect(el.x, el.y, el.w, el.h, color(0, 0, 0, a))
        rect(el.x + 1, el.y + 1, el.w - 2, el.h - 2, color(48, 48, 48, a))

        for _, e in ipairs(self.active_tab.elements) do
            if e.show and e ~= self.active_element and e.draw then e:draw(a, accent) end
        end

        if self.active_element and self.active_element.show and self.active_element.draw then
            self.active_element:draw(a, accent)
        end
    end
end

function Form:paint()
    input:update()
    self:process_input()
    self:think()
    self:draw()
end

function Form:run()
    client.set_event_callback("paint", function()
        self:paint()
    end)
end

local palette = {
    burgundy = color(180, 60, 60, 255),
    white = color(255, 255, 255, 255),
    orange = color(255, 160, 60, 255),
}

local function register(tab, element, column)
    tab:RegisterElement(element, column or 0)
    return element
end

local form = Form:new(50, 50, 630, 500, VK_INSERT)
form:SetColor(180, 60, 60, 255)
form:CreateVisibilityCheckbox("LUA", "B", "show hrisito c++ menu")

local tab_aimbot = form:RegisterTab(Tab:new("aimbot"))
register(tab_aimbot, Checkbox:new("enable", "enable", true, false), 0)
register(tab_aimbot, Checkbox:new("silent aimbot", "silent", true, false), 0)
register(tab_aimbot, Dropdown:new("target selection", "selection", { "distance", "crosshair", "damage", "health", "lag", "height" }, true, 1), 0)
register(tab_aimbot, Checkbox:new("angle limit", "fov", true, false), 0)
register(tab_aimbot, Slider:new("", "fov_amount", 1, 180, false, 0, 180, 1, "°"), 0)
register(tab_aimbot, MultiDropdown:new("hitbox", "hitbox", { "head", "chest", "body", "arms", "legs" }, true, {}), 0)
register(tab_aimbot, MultiDropdown:new("hitbox history", "hitbox_history", { "head", "chest", "body", "arms", "legs" }, true, {}), 0)
register(tab_aimbot, MultiDropdown:new("multi-point", "multipoint", { "head", "chest", "body", "legs" }, true, {}), 0)
register(tab_aimbot, Slider:new("", "hitbox_scale", 1, 100, false, 0, 90, 1, "%"), 0)
register(tab_aimbot, Slider:new("body hitbox scale", "body_hitbox_scale", 1, 100, true, 0, 50, 1, "%"), 0)
register(tab_aimbot, Slider:new("minimal damage", "minimal_damage", 1, 100, true, 0, 40, 1, ""), 0)
register(tab_aimbot, Checkbox:new("scale damage on hp", "minimal_damage_hp", true, false), 0)
register(tab_aimbot, Checkbox:new("penetrate walls", "penetrate", true, false), 0)
register(tab_aimbot, Slider:new("", "penetrate_minimal_damage", 1, 100, false, 0, 30, 1, ""), 0)
register(tab_aimbot, Checkbox:new("scale penetration damage on hp", "penetrate_minimal_damage_hp", true, false), 0)
register(tab_aimbot, Checkbox:new("aimbot with knife", "knifebot", true, false), 0)
register(tab_aimbot, Checkbox:new("aimbot with taser", "zeusbot", true, false), 0)
register(tab_aimbot, Dropdown:new("auto scope", "zoom", { "off", "always", "hitchance fail" }, true, 1), 1)
register(tab_aimbot, Checkbox:new("compensate spread", "nospread", true, false), 1)
register(tab_aimbot, Checkbox:new("compensate recoil", "norecoil", true, false), 1)
register(tab_aimbot, Checkbox:new("hitchance", "hitchance", true, false), 1)
register(tab_aimbot, Slider:new("", "hitchance_amount", 1, 100, false, 0, 50, 1, "%"), 1)
register(tab_aimbot, Checkbox:new("predict fake-lag", "lagfix", true, false), 1)
register(tab_aimbot, Checkbox:new("correct anti-aim", "correct", true, false), 1)
register(tab_aimbot, MultiDropdown:new("prefer body aim", "baim1", { "always", "lethal", "lethal x2", "fake", "in air" }, true, {}), 1)
register(tab_aimbot, MultiDropdown:new("only body aim", "baim2", { "always", "health", "fake", "in air" }, true, {}), 1)
register(tab_aimbot, Slider:new("", "baim_hp", 1, 50, false, 0, 20, 1, "hp"), 1)
register(tab_aimbot, Keybind:new("body aim on key", "body aim on key", -1), 1)

local tab_anti_aim = form:RegisterTab(Tab:new("anti-aim"))
register(tab_anti_aim, Checkbox:new("enable", "enable", true, false), 0)
register(tab_anti_aim, Checkbox:new("edge", "edge", true, false), 0)
register(tab_anti_aim, Dropdown:new("", "mode", { "stand", "walk", "air" }, false, 1), 0)
register(tab_anti_aim, Dropdown:new("pitch", "pitch_stnd", { "off", "down", "up", "random", "ideal" }, true, 1), 0)
register(tab_anti_aim, Dropdown:new("yaw", "yaw_stnd", { "off", "direction", "jitter", "rotate", "random" }, true, 1), 0)
register(tab_anti_aim, Slider:new("", "jitter_range_stnd", 1, 180, false, 0, 45, 5, "°"), 0)
register(tab_anti_aim, Slider:new("", "rot_range_stnd", 0, 360, false, 0, 360, 5, "°"), 0)
register(tab_anti_aim, Slider:new("", "rot_speed_stnd", 1, 100, false, 0, 10, 1, "%"), 0)
register(tab_anti_aim, Slider:new("", "rand_update_stnd", 0, 1, false, 1, 0, 0.1, ""), 0)
register(tab_anti_aim, Dropdown:new("direction", "dir_stnd", { "auto", "backwards", "left", "right", "custom" }, true, 1), 0)
register(tab_anti_aim, Slider:new("", "dir_time_stnd", 0, 10, false, 0, 0, 1, "s"), 0)
register(tab_anti_aim, Slider:new("", "dir_custom_stnd", -180, 180, false, 0, 0, 5, "°"), 0)
register(tab_anti_aim, Dropdown:new("base angle", "base_angle_stand", { "off", "static", "away crosshair", "away distance" }, true, 1), 0)
register(tab_anti_aim, Checkbox:new("lock direction", "dir_lock", true, false), 0)
register(tab_anti_aim, Dropdown:new("fake body", "body_fake_stnd", { "off", "left", "right", "opposite", "z" }, true, 1), 0)
register(tab_anti_aim, Dropdown:new("pitch", "pitch_walk", { "off", "down", "up", "random", "ideal" }, true, 1), 0)
register(tab_anti_aim, Dropdown:new("yaw", "yaw_walk", { "off", "direction", "jitter", "rotate", "random" }, true, 1), 0)
register(tab_anti_aim, Slider:new("", "jitter_range_walk", 1, 180, false, 0, 45, 5, "°"), 0)
register(tab_anti_aim, Slider:new("", "rot_range_walk", 0, 360, false, 0, 360, 5, "°"), 0)
register(tab_anti_aim, Slider:new("", "rot_speed_walk", 1, 100, false, 0, 10, 1, "%"), 0)
register(tab_anti_aim, Slider:new("", "rand_update_walk", 0, 1, false, 1, 0, 0.1, ""), 0)
register(tab_anti_aim, Dropdown:new("direction", "dir_walk", { "auto", "backwards", "left", "right", "custom" }, true, 1), 0)
register(tab_anti_aim, Slider:new("", "dir_time_walk", 0, 10, false, 0, 0, 1, "s"), 0)
register(tab_anti_aim, Slider:new("", "dir_custom_walk", -180, 180, false, 0, 0, 5, "°"), 0)
register(tab_anti_aim, Dropdown:new("base angle", "base_angle_walk", { "off", "static", "away crosshair", "away distance" }, true, 1), 0)
register(tab_anti_aim, Dropdown:new("pitch", "pitch_air", { "off", "down", "up", "random", "ideal" }, true, 1), 0)
register(tab_anti_aim, Dropdown:new("yaw", "yaw_air", { "off", "direction", "jitter", "rotate", "random" }, true, 1), 0)
register(tab_anti_aim, Slider:new("", "jitter_range_air", 1, 180, false, 0, 45, 5, "°"), 0)
register(tab_anti_aim, Slider:new("", "rot_range_air", 0, 360, false, 0, 360, 5, "°"), 0)
register(tab_anti_aim, Slider:new("", "rot_speed_air", 1, 100, false, 0, 10, 1, "%"), 0)
register(tab_anti_aim, Slider:new("", "rand_update_air", 0, 1, false, 1, 0, 0.1, ""), 0)
register(tab_anti_aim, Dropdown:new("direction", "dir_air", { "auto", "backwards", "left", "right", "custom" }, true, 1), 0)
register(tab_anti_aim, Slider:new("", "dir_time_air", 0, 10, false, 0, 0, 1, "s"), 0)
register(tab_anti_aim, Slider:new("", "dir_custom_air", -180, 180, false, 0, 0, 5, "°"), 0)
register(tab_anti_aim, Dropdown:new("base angle", "base_angle_air", { "off", "static", "away crosshair", "away distance" }, true, 1), 0)
register(tab_anti_aim, Dropdown:new("fake body", "body_fake_air", { "off", "left", "right", "opposite" }, true, 1), 0)
register(tab_anti_aim, Dropdown:new("fake yaw", "fake_yaw", { "off", "default", "relative", "jitter", "rotate", "random", "local view" }, true, 1), 1)
register(tab_anti_aim, Slider:new("", "fake_relative", -90, 90, false, 0, 0, 5, "°"), 1)
register(tab_anti_aim, Slider:new("", "fake_jitter_range", 1, 90, false, 0, 0, 5, "°"), 1)
register(tab_anti_aim, Checkbox:new("fake-lag", "lag_enable", true, false), 1)
register(tab_anti_aim, MultiDropdown:new("", "lag_active", { "move", "air", "crouch" }, false, {}), 1)
register(tab_anti_aim, Dropdown:new("", "lag_mode", { "max", "break", "random", "break step" }, false, 1), 1)
register(tab_anti_aim, Slider:new("limit", "lag_limit", 2, 16, true, 0, 2, 1, ""), 1)
register(tab_anti_aim, Checkbox:new("on land", "lag_land", true, false), 1)

local tab_players = form:RegisterTab(Tab:new("players"))
register(tab_players, MultiDropdown:new("boxes", "box", { "enemy", "friendly" }, true, {}), 0)
register(tab_players, Colorpicker:new("box enemy color", "box_enemy", color(150, 200, 60, 255)), 0)
register(tab_players, Colorpicker:new("box friendly color", "box_friendly", color(255, 200, 0, 255)), 0)
register(tab_players, Checkbox:new("dormant enemies", "dormant", true, false), 0)
register(tab_players, Checkbox:new("enemy offscreen esp", "offscreen", true, false), 0)
register(tab_players, Colorpicker:new("offscreen esp color", "offscreen_color", palette.white), 0)
register(tab_players, MultiDropdown:new("name", "name", { "enemy", "friendly" }, true, {}), 0)
register(tab_players, Colorpicker:new("name color", "name_color", palette.white), 0)
register(tab_players, MultiDropdown:new("health", "health", { "enemy", "friendly" }, true, {}), 0)
register(tab_players, MultiDropdown:new("flags enemy", "flags_enemy", { "money", "armor", "scoped", "flashed", "reloading", "bomb" }, true, {}), 0)
register(tab_players, MultiDropdown:new("flags friendly", "flags_friendly", { "money", "armor", "scoped", "flashed", "reloading", "bomb" }, true, {}), 0)
register(tab_players, MultiDropdown:new("weapon", "weapon", { "enemy", "friendly" }, true, {}), 0)
register(tab_players, Dropdown:new("", "weapon_mode", { "text", "icon" }, false, 1), 0)
register(tab_players, Checkbox:new("ammo", "ammo", true, false), 0)
register(tab_players, Colorpicker:new("color", "ammo_color", palette.burgundy), 0)
register(tab_players, Checkbox:new("lby update", "lby_update", true, false), 0)
register(tab_players, Colorpicker:new("color", "lby_update_color", palette.orange), 0)
register(tab_players, MultiDropdown:new("skeleton", "skeleton", { "enemy", "friendly" }, true, {}), 1)
register(tab_players, Colorpicker:new("enemy color", "skeleton_enemy", color(255, 255, 255, 255)), 1)
register(tab_players, Colorpicker:new("friendly color", "skeleton_friendly", color(255, 255, 255, 255)), 1)
register(tab_players, MultiDropdown:new("glow", "glow", { "enemy", "friendly" }, true, {}), 1)
register(tab_players, Colorpicker:new("enemy color", "glow_enemy", color(150, 200, 60, 255)), 1)
register(tab_players, Colorpicker:new("friendly color", "glow_friendly", color(150, 200, 60, 255)), 1)
register(tab_players, Slider:new("", "glow_blend", 10, 100, false, 0, 60, 1, "%"), 1)
register(tab_players, MultiDropdown:new("chams enemy", "chams_enemy", { "visible", "invisible" }, true, {}), 1)
register(tab_players, Colorpicker:new("color visible", "chams_enemy_vis", color(150, 200, 60, 255)), 1)
register(tab_players, Colorpicker:new("color invisible", "chams_enemy_invis", color(60, 180, 225, 255)), 1)
register(tab_players, Slider:new("", "chams_enemy_blend", 10, 100, false, 0, 100, 1, "%"), 1)
register(tab_players, Checkbox:new("chams history", "chams_history", true, false), 1)
register(tab_players, Colorpicker:new("color", "chams_history_col", color(255, 255, 200, 255)), 1)
register(tab_players, Slider:new("", "chams_history_blend", 10, 100, false, 0, 100, 1, "%"), 1)
register(tab_players, MultiDropdown:new("chams friendly", "chams_friendly", { "visible", "invisible" }, true, {}), 1)
register(tab_players, Colorpicker:new("color visible", "chams_friendly_vis", color(255, 200, 0, 255)), 1)
register(tab_players, Colorpicker:new("color invisible", "chams_friendly_invis", color(255, 50, 0, 255)), 1)
register(tab_players, Slider:new("", "chams_friendly_blend", 10, 100, false, 0, 100, 1, "%"), 1)
register(tab_players, Checkbox:new("chams local", "chams_local", true, false), 1)
register(tab_players, Colorpicker:new("color", "chams_local_col", color(255, 255, 200, 255)), 1)
register(tab_players, Slider:new("", "chams_local_blend", 10, 100, false, 0, 100, 1, "%"), 1)
register(tab_players, Checkbox:new("blend when scoped", "chams_local_scope", true, false), 1)

local tab_visuals = form:RegisterTab(Tab:new("visuals"))
register(tab_visuals, Checkbox:new("dropped weapons", "items", true, false), 0)
register(tab_visuals, Checkbox:new("dropped weapons ammo", "ammo", true, false), 0)
register(tab_visuals, Colorpicker:new("color", "item_color", palette.white), 0)
register(tab_visuals, Checkbox:new("projectiles", "proj", true, false), 0)
register(tab_visuals, Colorpicker:new("color", "proj_color", palette.white), 0)
register(tab_visuals, MultiDropdown:new("projectile range", "proj_range", { "frag", "molly" }, true, {}), 0)
register(tab_visuals, Colorpicker:new("color", "proj_range_color", palette.burgundy), 0)
register(tab_visuals, MultiDropdown:new("planted c4", "planted_c4", { "on screen (2D)", "on bomb (3D)" }, true, {}), 0)
register(tab_visuals, Checkbox:new("do not render teammates", "disableteam", true, false), 0)
register(tab_visuals, Dropdown:new("world", "world", { "off", "night", "fullbright" }, true, 1), 0)
register(tab_visuals, Checkbox:new("transparent props", "transparent_props", true, false), 0)
register(tab_visuals, Checkbox:new("force enemies on radar", "enemy_radar", true, false), 0)
register(tab_visuals, Checkbox:new("remove visual recoil", "novisrecoil", true, false), 1)
register(tab_visuals, Checkbox:new("remove smoke grenades", "nosmoke", true, false), 1)
register(tab_visuals, Checkbox:new("remove fog", "nofog", true, false), 1)
register(tab_visuals, Checkbox:new("remove flashbangs", "noflash", true, false), 1)
register(tab_visuals, Checkbox:new("remove scope", "noscope", true, false), 1)
register(tab_visuals, Checkbox:new("override fov", "fov", true, false), 1)
register(tab_visuals, Slider:new("", "fov_amt", 60, 140, false, 0, 90, 1, "°"), 1)
register(tab_visuals, Checkbox:new("override fov when scoped", "fov_scoped", true, false), 1)
register(tab_visuals, Checkbox:new("override viewmodel fov", "viewmodel_fov", true, false), 1)
register(tab_visuals, Slider:new("", "viewmodel_fov_amt", 60, 140, false, 0, 90, 1, "°"), 1)
register(tab_visuals, Checkbox:new("show spectator list", "spectators", true, false), 1)
register(tab_visuals, Checkbox:new("force crosshair", "force_xhair", true, false), 1)
register(tab_visuals, Checkbox:new("visualize spread", "spread_xhair", true, false), 1)
register(tab_visuals, Colorpicker:new("visualize spread color", "spread_xhair_col", palette.burgundy), 1)
register(tab_visuals, Slider:new("", "spread_xhair_blend", 10, 100, false, 0, 100, 1, "%"), 1)
register(tab_visuals, Checkbox:new("penetration crosshair", "pen_xhair", true, false), 1)
register(tab_visuals, MultiDropdown:new("indicators", "indicators", { "lby", "lag compensation", "fake latency" }, true, {}), 1)
register(tab_visuals, Checkbox:new("grenade simulation", "tracers", true, false), 1)
register(tab_visuals, Checkbox:new("impact beams", "impact_beams", true, false), 1)
register(tab_visuals, Colorpicker:new("impact beams color", "impact_beams_color", palette.white), 1)
register(tab_visuals, Colorpicker:new("impact beams hurt color", "impact_beams_hurt_color", palette.white), 1)
register(tab_visuals, Slider:new("impact beams time", "impact_beams_time", 1, 10, true, 0, 1, 1, "s"), 1)
register(tab_visuals, Keybind:new("thirdperson", "thirdperson", -1), 1)

local tab_movement = form:RegisterTab(Tab:new("movement"))
register(tab_movement, Checkbox:new("automatic jump", "bhop", true, false), 0)
register(tab_movement, Checkbox:new("duck in air", "airduck", true, false), 0)
register(tab_movement, Checkbox:new("automatic strafe", "autostrafe", true, false), 0)
register(tab_movement, Keybind:new("c-strafe", "cstrafe", -1), 0)
register(tab_movement, Keybind:new("a-strafe", "astrafe", -1), 0)
register(tab_movement, Keybind:new("z-strafe", "zstrafe", -1), 0)
register(tab_movement, Slider:new("", "z_freq", 1, 100, false, 0, 50, 0.5, "hz"), 0)
register(tab_movement, Slider:new("", "z_dist", 1, 100, false, 0, 20, 0.5, "%"), 0)
register(tab_movement, Keybind:new("fake-walk", "fakewalk", -1), 1)
register(tab_movement, Keybind:new("automatic peek", "autopeek", -1), 1)
register(tab_movement, Checkbox:new("automatic stop always on", "auto_stop_always", true, false), 1)
register(tab_movement, Keybind:new("automatic stop", "autostop", -1), 1)

local tab_skins = form:RegisterTab(Tab:new("skins"))
register(tab_skins, Checkbox:new("enable", "skins_enable", true, false), 0)
register(tab_skins, Edit:new("paintkit id", "id_deagle", "3"), 0)
register(tab_skins, Checkbox:new("stattrak", "stattrak_deagle", true, false), 0)
register(tab_skins, Slider:new("quality", "quality_deagle", 1, 100, true, 0, 100, 1, "%"), 0)
register(tab_skins, Slider:new("seed", "seed_deagle", 0, 255, true, 0, 0, 1, ""), 0)
register(tab_skins, Edit:new("paintkit id", "id_elite", "3"), 0)
register(tab_skins, Checkbox:new("stattrak", "stattrak_elite", true, false), 0)
register(tab_skins, Slider:new("quality", "quality_elite", 1, 100, true, 0, 100, 1, "%"), 0)
register(tab_skins, Slider:new("seed", "seed_elite", 0, 255, true, 0, 0, 1, ""), 0)
register(tab_skins, Edit:new("paintkit id", "id_fiveseven", "3"), 0)
register(tab_skins, Checkbox:new("stattrak", "stattrak_fiveseven", true, false), 0)
register(tab_skins, Slider:new("quality", "quality_fiveseven", 1, 100, true, 0, 100, 1, "%"), 0)
register(tab_skins, Slider:new("seed", "seed_fiveseven", 0, 255, true, 0, 0, 1, ""), 0)
register(tab_skins, Edit:new("paintkit id", "id_glock", "3"), 0)
register(tab_skins, Checkbox:new("stattrak", "stattrak_glock", true, false), 0)
register(tab_skins, Slider:new("quality", "quality_glock", 1, 100, true, 0, 100, 1, "%"), 0)
register(tab_skins, Slider:new("seed", "seed_glock", 0, 255, true, 0, 0, 1, ""), 0)
register(tab_skins, Edit:new("paintkit id", "id_ak47", "3"), 0)
register(tab_skins, Checkbox:new("stattrak", "stattrak_ak47", true, false), 0)
register(tab_skins, Slider:new("quality", "quality_ak47", 1, 100, true, 0, 100, 1, "%"), 0)
register(tab_skins, Slider:new("seed", "seed_ak47", 0, 255, true, 0, 0, 1, ""), 0)
register(tab_skins, Edit:new("paintkit id", "id_aug", "3"), 0)
register(tab_skins, Checkbox:new("stattrak", "stattrak_aug", true, false), 0)
register(tab_skins, Slider:new("quality", "quality_aug", 1, 100, true, 0, 100, 1, "%"), 0)
register(tab_skins, Slider:new("seed", "seed_aug", 0, 255, true, 0, 0, 1, ""), 0)
register(tab_skins, Edit:new("paintkit id", "id_awp", "3"), 0)
register(tab_skins, Checkbox:new("stattrak", "stattrak_awp", true, false), 0)
register(tab_skins, Slider:new("quality", "quality_awp", 1, 100, true, 0, 100, 1, "%"), 0)
register(tab_skins, Slider:new("seed", "seed_awp", 0, 255, true, 0, 0, 1, ""), 0)
register(tab_skins, Edit:new("paintkit id", "id_famas", "3"), 0)
register(tab_skins, Checkbox:new("stattrak", "stattrak_famas", true, false), 0)
register(tab_skins, Slider:new("quality", "quality_famas", 1, 100, true, 0, 100, 1, "%"), 0)
register(tab_skins, Slider:new("seed", "seed_famas", 0, 255, true, 0, 0, 1, ""), 0)
register(tab_skins, Edit:new("paintkit id", "id_g3sg1", "3"), 0)
register(tab_skins, Checkbox:new("stattrak", "stattrak_g3sg1", true, false), 0)
register(tab_skins, Slider:new("quality", "quality_g3sg1", 1, 100, true, 0, 100, 1, "%"), 0)
register(tab_skins, Slider:new("seed", "seed_g3sg1", 0, 255, true, 0, 0, 1, ""), 0)
register(tab_skins, Edit:new("paintkit id", "id_galil", "3"), 0)
register(tab_skins, Checkbox:new("stattrak", "stattrak_galil", true, false), 0)
register(tab_skins, Slider:new("quality", "quality_galil", 1, 100, true, 0, 100, 1, "%"), 0)
register(tab_skins, Slider:new("seed", "seed_galil", 0, 255, true, 0, 0, 1, ""), 0)
register(tab_skins, Edit:new("paintkit id", "id_m249", "3"), 0)
register(tab_skins, Checkbox:new("stattrak", "stattrak_m249", true, false), 0)
register(tab_skins, Slider:new("quality", "quality_m249", 1, 100, true, 0, 100, 1, "%"), 0)
register(tab_skins, Slider:new("seed", "seed_m249", 0, 255, true, 0, 0, 1, ""), 0)
register(tab_skins, Edit:new("paintkit id", "id_m4a4", "3"), 0)
register(tab_skins, Checkbox:new("stattrak", "stattrak_m4a4", true, false), 0)
register(tab_skins, Slider:new("quality", "quality_m4a4", 1, 100, true, 0, 100, 1, "%"), 0)
register(tab_skins, Slider:new("seed", "seed_m4a4", 0, 255, true, 0, 0, 1, ""), 0)
register(tab_skins, Edit:new("paintkit id", "id_mac10", "3"), 0)
register(tab_skins, Checkbox:new("stattrak", "stattrak_mac10", true, false), 0)
register(tab_skins, Slider:new("quality", "quality_mac10", 1, 100, true, 0, 100, 1, "%"), 0)
register(tab_skins, Slider:new("seed", "seed_mac10", 0, 255, true, 0, 0, 1, ""), 0)
register(tab_skins, Edit:new("paintkit id", "id_p90", "3"), 0)
register(tab_skins, Checkbox:new("stattrak", "stattrak_p90", true, false), 0)
register(tab_skins, Slider:new("quality", "quality_p90", 1, 100, true, 0, 100, 1, "%"), 0)
register(tab_skins, Slider:new("seed", "seed_p90", 0, 255, true, 0, 0, 1, ""), 0)
register(tab_skins, Edit:new("paintkit id", "id_ump45", "3"), 0)
register(tab_skins, Checkbox:new("stattrak", "stattrak_ump45", true, false), 0)
register(tab_skins, Slider:new("quality", "quality_ump45", 1, 100, true, 0, 100, 1, "%"), 0)
register(tab_skins, Slider:new("seed", "seed_ump45", 0, 255, true, 0, 0, 1, ""), 0)
register(tab_skins, Edit:new("paintkit id", "id_xm1014", "3"), 0)
register(tab_skins, Checkbox:new("stattrak", "stattrak_xm1014", true, false), 0)
register(tab_skins, Slider:new("quality", "quality_xm1014", 1, 100, true, 0, 100, 1, "%"), 0)
register(tab_skins, Slider:new("seed", "seed_xm1014", 0, 255, true, 0, 0, 1, ""), 0)
register(tab_skins, Edit:new("paintkit id", "id_bizon", "3"), 0)
register(tab_skins, Checkbox:new("stattrak", "stattrak_bizon", true, false), 0)
register(tab_skins, Slider:new("quality", "quality_bizon", 1, 100, true, 0, 100, 1, "%"), 0)
register(tab_skins, Slider:new("seed", "seed_bizon", 0, 255, true, 0, 0, 1, ""), 0)
register(tab_skins, Edit:new("paintkit id", "id_mag7", "3"), 0)
register(tab_skins, Checkbox:new("stattrak", "stattrak_mag7", true, false), 0)
register(tab_skins, Slider:new("quality", "quality_mag7", 1, 100, true, 0, 100, 1, "%"), 0)
register(tab_skins, Slider:new("seed", "seed_mag7", 0, 255, true, 0, 0, 1, ""), 0)
register(tab_skins, Edit:new("paintkit id", "id_negev", "3"), 0)
register(tab_skins, Checkbox:new("stattrak", "stattrak_negev", true, false), 0)
register(tab_skins, Slider:new("quality", "quality_negev", 1, 100, true, 0, 100, 1, "%"), 0)
register(tab_skins, Slider:new("seed", "seed_negev", 0, 255, true, 0, 0, 1, ""), 0)
register(tab_skins, Edit:new("paintkit id", "id_sawedoff", "3"), 0)
register(tab_skins, Checkbox:new("stattrak", "stattrak_sawedoff", true, false), 0)
register(tab_skins, Slider:new("quality", "quality_sawedoff", 1, 100, true, 0, 100, 1, "%"), 0)
register(tab_skins, Slider:new("seed", "seed_sawedoff", 0, 255, true, 0, 0, 1, ""), 0)
register(tab_skins, Edit:new("paintkit id", "id_tec9", "3"), 0)
register(tab_skins, Checkbox:new("stattrak", "stattrak_tec9", true, false), 0)
register(tab_skins, Slider:new("quality", "quality_tec9", 1, 100, true, 0, 100, 1, "%"), 0)
register(tab_skins, Slider:new("seed", "seed_tec9", 0, 255, true, 0, 0, 1, ""), 0)
register(tab_skins, Edit:new("paintkit id", "id_p2000", "3"), 0)
register(tab_skins, Checkbox:new("stattrak", "stattrak_p2000", true, false), 0)
register(tab_skins, Slider:new("quality", "quality_p2000", 1, 100, true, 0, 100, 1, "%"), 0)
register(tab_skins, Slider:new("seed", "seed_p2000", 0, 255, true, 0, 0, 1, ""), 0)
register(tab_skins, Edit:new("paintkit id", "id_mp7", "3"), 0)
register(tab_skins, Checkbox:new("stattrak", "stattrak_mp7", true, false), 0)
register(tab_skins, Slider:new("quality", "quality_mp7", 1, 100, true, 0, 100, 1, "%"), 0)
register(tab_skins, Slider:new("seed", "seed_mp7", 0, 255, true, 0, 0, 1, ""), 0)
register(tab_skins, Edit:new("paintkit id", "id_mp9", "3"), 0)
register(tab_skins, Checkbox:new("stattrak", "stattrak_mp9", true, false), 0)
register(tab_skins, Slider:new("quality", "quality_mp9", 1, 100, true, 0, 100, 1, "%"), 0)
register(tab_skins, Slider:new("seed", "seed_mp9", 0, 255, true, 0, 0, 1, ""), 0)
register(tab_skins, Edit:new("paintkit id", "id_nova", "3"), 0)
register(tab_skins, Checkbox:new("stattrak", "stattrak_nova", true, false), 0)
register(tab_skins, Slider:new("quality", "quality_nova", 1, 100, true, 0, 100, 1, "%"), 0)
register(tab_skins, Slider:new("seed", "seed_nova", 0, 255, true, 0, 0, 1, ""), 0)
register(tab_skins, Edit:new("paintkit id", "id_p250", "3"), 0)
register(tab_skins, Checkbox:new("stattrak", "stattrak_p250", true, false), 0)
register(tab_skins, Slider:new("quality", "quality_p250", 1, 100, true, 0, 100, 1, "%"), 0)
register(tab_skins, Slider:new("seed", "seed_p250", 0, 255, true, 0, 0, 1, ""), 0)
register(tab_skins, Edit:new("paintkit id", "id_scar20", "3"), 0)
register(tab_skins, Checkbox:new("stattrak", "stattrak_scar20", true, false), 0)
register(tab_skins, Slider:new("quality", "quality_scar20", 1, 100, true, 0, 100, 1, "%"), 0)
register(tab_skins, Slider:new("seed", "seed_scar20", 0, 255, true, 0, 0, 1, ""), 0)
register(tab_skins, Edit:new("paintkit id", "id_sg553", "3"), 0)
register(tab_skins, Checkbox:new("stattrak", "stattrak_sg553", true, false), 0)
register(tab_skins, Slider:new("quality", "quality_sg553", 1, 100, true, 0, 100, 1, "%"), 0)
register(tab_skins, Slider:new("seed", "seed_sg553", 0, 255, true, 0, 0, 1, ""), 0)
register(tab_skins, Edit:new("paintkit id", "id_ssg08", "3"), 0)
register(tab_skins, Checkbox:new("stattrak", "stattrak_ssg08", true, false), 0)
register(tab_skins, Slider:new("quality", "quality_ssg08", 1, 100, true, 0, 100, 1, "%"), 0)
register(tab_skins, Slider:new("seed", "seed_ssg08", 0, 255, true, 0, 0, 1, ""), 0)
register(tab_skins, Edit:new("paintkit id", "id_m4a1s", "3"), 0)
register(tab_skins, Checkbox:new("stattrak", "stattrak_m4a1s", true, false), 0)
register(tab_skins, Slider:new("quality", "quality_m4a1s", 1, 100, true, 0, 100, 1, "%"), 0)
register(tab_skins, Slider:new("seed", "seed_m4a1s", 0, 255, true, 0, 0, 1, ""), 0)
register(tab_skins, Edit:new("paintkit id", "id_usps", "3"), 0)
register(tab_skins, Checkbox:new("stattrak", "stattrak_usps", true, false), 0)
register(tab_skins, Slider:new("quality", "quality_usps", 1, 100, true, 0, 100, 1, "%"), 0)
register(tab_skins, Slider:new("seed", "seed_usps", 0, 255, true, 0, 0, 1, ""), 0)
register(tab_skins, Edit:new("paintkit id", "id_cz75a", "3"), 0)
register(tab_skins, Checkbox:new("stattrak", "stattrak_cz75a", true, false), 0)
register(tab_skins, Slider:new("quality", "quality_cz75a", 1, 100, true, 0, 100, 1, "%"), 0)
register(tab_skins, Slider:new("seed", "seed_cz75a", 0, 255, true, 0, 0, 1, ""), 0)
register(tab_skins, Edit:new("paintkit id", "id_revolver", "3"), 0)
register(tab_skins, Checkbox:new("stattrak", "stattrak_revolver", true, false), 0)
register(tab_skins, Slider:new("quality", "quality_revolver", 1, 100, true, 0, 100, 1, "%"), 0)
register(tab_skins, Slider:new("seed", "seed_revolver", 0, 255, true, 0, 0, 1, ""), 0)
register(tab_skins, Edit:new("paintkit id", "id_bayonet", "3"), 0)
register(tab_skins, Checkbox:new("stattrak", "stattrak_bayonet", true, false), 0)
register(tab_skins, Slider:new("quality", "quality_bayonet", 1, 100, true, 0, 100, 1, "%"), 0)
register(tab_skins, Slider:new("seed", "seed_bayonet", 0, 255, true, 0, 0, 1, ""), 0)
register(tab_skins, Edit:new("paintkit id", "id_flip", "3"), 0)
register(tab_skins, Checkbox:new("stattrak", "stattrak_flip", true, false), 0)
register(tab_skins, Slider:new("quality", "quality_flip", 1, 100, true, 0, 100, 1, "%"), 0)
register(tab_skins, Slider:new("seed", "seed_flip", 0, 255, true, 0, 0, 1, ""), 0)
register(tab_skins, Edit:new("paintkit id", "id_gut", "3"), 0)
register(tab_skins, Checkbox:new("stattrak", "stattrak_gut", true, false), 0)
register(tab_skins, Slider:new("quality", "quality_gut", 1, 100, true, 0, 100, 1, "%"), 0)
register(tab_skins, Slider:new("seed", "seed_gut", 0, 255, true, 0, 0, 1, ""), 0)
register(tab_skins, Edit:new("paintkit id", "id_karambit", "3"), 0)
register(tab_skins, Checkbox:new("stattrak", "stattrak_karambit", true, false), 0)
register(tab_skins, Slider:new("quality", "quality_karambit", 1, 100, true, 0, 100, 1, "%"), 0)
register(tab_skins, Slider:new("seed", "seed_karambit", 0, 255, true, 0, 0, 1, ""), 0)
register(tab_skins, Edit:new("paintkit id", "id_m9", "3"), 0)
register(tab_skins, Checkbox:new("stattrak", "stattrak_m9", true, false), 0)
register(tab_skins, Slider:new("quality", "quality_m9", 1, 100, true, 0, 100, 1, "%"), 0)
register(tab_skins, Slider:new("seed", "seed_m9", 0, 255, true, 0, 0, 1, ""), 0)
register(tab_skins, Edit:new("paintkit id", "id_huntsman", "3"), 0)
register(tab_skins, Checkbox:new("stattrak", "stattrak_huntsman", true, false), 0)
register(tab_skins, Slider:new("quality", "quality_huntsman", 1, 100, true, 0, 100, 1, "%"), 0)
register(tab_skins, Slider:new("seed", "seed_huntsman", 0, 255, true, 0, 0, 1, ""), 0)
register(tab_skins, Edit:new("paintkit id", "id_falchion", "3"), 0)
register(tab_skins, Checkbox:new("stattrak", "stattrak_falchion", true, false), 0)
register(tab_skins, Slider:new("quality", "quality_falchion", 1, 100, true, 0, 100, 1, "%"), 0)
register(tab_skins, Slider:new("seed", "seed_falchion", 0, 255, true, 0, 0, 1, ""), 0)
register(tab_skins, Edit:new("paintkit id", "id_bowie", "3"), 0)
register(tab_skins, Checkbox:new("stattrak", "stattrak_bowie", true, false), 0)
register(tab_skins, Slider:new("quality", "quality_bowie", 1, 100, true, 0, 100, 1, "%"), 0)
register(tab_skins, Slider:new("seed", "seed_bowie", 0, 255, true, 0, 0, 1, ""), 0)
register(tab_skins, Edit:new("paintkit id", "id_butterfly", "3"), 0)
register(tab_skins, Checkbox:new("stattrak", "stattrak_butterfly", true, false), 0)
register(tab_skins, Slider:new("quality", "quality_butterfly", 1, 100, true, 0, 100, 1, "%"), 0)
register(tab_skins, Slider:new("seed", "seed_butterfly", 0, 255, true, 0, 0, 1, ""), 0)
register(tab_skins, Edit:new("paintkit id", "id_daggers", "3"), 0)
register(tab_skins, Checkbox:new("stattrak", "stattrak_daggers", true, false), 0)
register(tab_skins, Slider:new("quality", "quality_daggers", 1, 100, true, 0, 100, 1, "%"), 0)
register(tab_skins, Slider:new("seed", "seed_daggers", 0, 255, true, 0, 0, 1, ""), 0)
register(tab_skins, Dropdown:new("knife model", "skins_knife_model", { "off", "bayonet", "bowie", "butterfly", "falchion", "flip", "gut", "huntsman", "karambit", "m9 bayonet", "daggers" }, true, 1), 1)
register(tab_skins, Dropdown:new("glove model", "skins_glove_model", { "off", "bloodhound", "sport", "driver", "handwraps", "moto", "specialist" }, true, 1), 1)
register(tab_skins, Edit:new("glove paintkit id", "skins_glove_id", "2"), 1)

local tab_misc = form:RegisterTab(Tab:new("misc"))
register(tab_misc, MultiDropdown:new("auto buy items", "auto_buy1", { "galilar", "famas", "ak47", "m4a1", "m4a1_silencer", "ssg08", "aug", "sg556", "awp", "scar20", "g3sg1", "nova", "xm1014", "mag7", "m249", "negev", "mac10", "mp9", "mp7", "ump45", "p90", "bizon" }, true, {}), 0)
register(tab_misc, MultiDropdown:new("", "auto_buy2", { "glock", "hkp2000", "usp_silencer", "elite", "p250", "tec9", "fn57", "deagle" }, false, {}), 0)
register(tab_misc, MultiDropdown:new("", "auto_buy3", { "vest", "vesthelm", "taser", "defuser", "heavyarmor", "molotov", "incgrenade", "decoy", "flashbang", "hegrenade", "smokegrenade" }, false, {}), 0)
register(tab_misc, MultiDropdown:new("notifications", "notifications", { "matchmaking", "damage", "purchases", "bomb", "defuse" }, true, {}), 0)
register(tab_misc, Keybind:new("last tick defuse", "last_tick_defuse", -1), 0)
register(tab_misc, Keybind:new("fake latency", "fake_latency", -1), 0)
register(tab_misc, Slider:new("", "fake_latency_amt", 50, 800, false, 0, 200, 50, "ms"), 0)
register(tab_misc, Checkbox:new("auto-accept matchmaking", "autoaccept", true, false), 1)
register(tab_misc, Checkbox:new("unlock inventory in-game", "unlock_inventory", true, false), 1)
register(tab_misc, Checkbox:new("hitmarker", "hitmarker", true, false), 1)
register(tab_misc, Checkbox:new("ragdoll force", "ragdoll_force", true, false), 1)
register(tab_misc, Checkbox:new("reveal matchmaking ranks", "ranks", true, false), 1)
register(tab_misc, Checkbox:new("preserve killfeed", "killfeed", true, false), 1)

local tab_config = form:RegisterTab(Tab:new("config"))
register(tab_config, Colorpicker:new("menu color", "menu_color", palette.burgundy), 0)
register(tab_config, Dropdown:new("safety mode", "mode", { "matchmaking", "no-spread" }, true, 1), 1)
register(tab_config, Dropdown:new("configuration", "cfg", { "1", "2", "3", "4", "5", "6" }, true, 1), 1)
register(tab_config, Keybind:new("configuration key 1", "cfg_key1", -1), 1)
register(tab_config, Keybind:new("configuration key 2", "cfg_key2", -1), 1)
register(tab_config, Keybind:new("configuration key 3", "cfg_key3", -1), 1)
register(tab_config, Keybind:new("configuration key 4", "cfg_key4", -1), 1)
register(tab_config, Keybind:new("configuration key 5", "cfg_key5", -1), 1)
register(tab_config, Keybind:new("configuration key 6", "cfg_key6", -1), 1)
register(tab_config, Button:new("save", function() end), 1)
register(tab_config, Button:new("load", function() end), 1)

form:run()
_G.hrisito_menu = form

