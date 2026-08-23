local ffi = require 'ffi'
local vector = require 'vector'

local inspect = require 'gamesense/inspect'

local base64 = require 'gamesense/base64'
local clipboard = require 'gamesense/clipboard'

local c_entity = require 'gamesense/entity'
local csgo_weapons = require 'gamesense/csgo_weapons'

local trace = require 'gamesense/trace'

local function DUMMY(...)
    return ...
end

if not LPH_OBFUSCATED then
    LPH_NO_VIRTUALIZE = DUMMY

	LPH_JIT = DUMMY
	LPH_JIT_MAX = DUMMY

    LPH_ENCSTR = DUMMY
	LPH_ENCNUM = DUMMY
end

local function round(x)
    return math.floor(x + 0.5)
end

local function contains(list, value)
    for i = 1, #list do
        if list[i] == value then
            return i
        end
    end

    return nil
end

local function get_user()
    local lp = entity.get_local_player()

    if not lp then
        return "unknown"
    end

    return entity.get_player_name(lp) or "unknown"
end

local script do
    script = {}

    script.name = "revelation"
    script.user = get_user()
    script.build = "dev"
end

local utils do
    utils = { }

    function utils.clamp(x, min, max)
        return math.max(min, math.min(x, max))
    end

    function utils.lerp(a, b, t)
        return a + t * (b - a)
    end

    function utils.inverse_lerp(a, b, x)
        return (x - a) / (b - a)
    end

    function utils.map(x, in_min, in_max, out_min, out_max, should_clamp)
        if should_clamp then
            x = utils.clamp(x, in_min, in_max)
        end

        local rel = utils.inverse_lerp(in_min, in_max, x)
        local value = utils.lerp(out_min, out_max, rel)

        return value
    end

    function utils.normalize(x, min, max)
        local d = max - min

        while x < min do
            x = x + d
        end

        while x > max do
            x = x - d
        end

        return x
    end

    function utils.trim(str)
        return str
    end

    function utils.from_hex(hex)
        hex = string.gsub(hex, '#', '')

        local r = tonumber(string.sub(hex, 1, 2), 16)
        local g = tonumber(string.sub(hex, 3, 4), 16)
        local b = tonumber(string.sub(hex, 5, 6), 16)
        local a = tonumber(string.sub(hex, 7, 8), 16)

        return r, g, b, a or 255
    end

    function utils.to_hex(r, g, b, a)
        return string.format('%02x%02x%02x%02x', r, g, b, a)
    end

    function utils.event_callback(event_name, callback, value)
        assert(callback ~= nil, 'Callback is nil')

        local fn = value and client.set_event_callback
            or client.unset_event_callback

        fn(event_name, callback)
    end

    function utils.get_eye_position(ent)
        local origin_x, origin_y, origin_z = entity.get_origin(ent)
        local offset_x, offset_y, offset_z = entity.get_prop(ent, 'm_vecViewOffset')

        if origin_x == nil or offset_x == nil then
            return nil
        end

        local eye_pos_x = origin_x + offset_x
        local eye_pos_y = origin_y + offset_y
        local eye_pos_z = origin_z + offset_z

        return eye_pos_x, eye_pos_y, eye_pos_z
    end

    function utils.closest_ray_point(a, b, p, should_clamp)
        local ray_delta = p - a
        local line_delta = b - a

        local lengthsqr = line_delta.x * line_delta.x + line_delta.y * line_delta.y
        local dot_product = ray_delta.x * line_delta.x + ray_delta.y * line_delta.y

        local t = dot_product / lengthsqr

        if should_clamp then
            if t <= 0.0 then
                return a
            end

            if t >= 1.0 then
                return b
            end
        end

        return a + t * line_delta
    end

    function utils.extrapolate(pos, vel, ticks)
        return pos + vel * (ticks * globals.tickinterval())
    end

    function utils.random_int(min, max)
        if min > max then
            min, max = max, min
        end

        return client.random_int(min, max)
    end

    function utils.random_float(min, max)
        if min > max then
            min, max = max, min
        end

        return client.random_float(min, max)
    end

    function utils.find_signature(module_name, pattern, offset)
        local match = client.find_signature(module_name, pattern)

        if match == nil then
            return nil
        end

        if offset ~= nil then
            local address = ffi.cast('char*', match)
            address = address + offset

            return address
        end

        return match
    end
end

local software do
    software = { }

    software.ragebot = {
        weapon_type = ui.reference(
            'Rage', 'Weapon type', 'Weapon type'
        ),

        aimbot = {
            enabled = {
                ui.reference('Rage', 'Aimbot', 'Enabled')
            },

            double_tap = {
                ui.reference('Rage', 'Aimbot', 'Double tap')
            },

            minimum_hit_chance = ui.reference(
                'Rage', 'Aimbot', 'Minimum hit chance'
            ),

            minimum_damage = ui.reference(
                'Rage', 'Aimbot', 'Minimum damage'
            ),

            minimum_damage_override = {
                ui.reference('Rage', 'Aimbot', 'Minimum damage override')
            },

            prefer_safe_point = ui.reference(
                'Rage', 'Aimbot', 'Prefer safe point'
            ),

            quick_stop = {
                ui.reference('Rage', 'Aimbot', 'Quick stop')
            }
        },

        other = {
            accuracy_boost = ui.reference(
                'Rage', 'Other', 'Accuracy boost'
            ),

            remove_recoil = ui.reference(
                'Rage', 'Other', 'Remove recoil'
            ),

            delay_shot = ui.reference(
                'Rage', 'Other', 'Delay shot'
            ),

            quick_peek_assist = {
                ui.reference('Rage', 'Other', 'Quick peek assist')
            },

            duck_peek_assist = ui.reference(
                'Rage', 'Other', 'Duck peek assist'
            )
        }
    }

    software.antiaimbot = {
        angles = {
            enabled = ui.reference(
                'AA', 'Anti-aimbot angles', 'Enabled'
            ),

            pitch = {
                ui.reference('AA', 'Anti-aimbot angles', 'Pitch')
            },

            yaw_base = ui.reference(
                'AA', 'Anti-aimbot angles', 'Yaw base'
            ),

            yaw = {
                ui.reference('AA', 'Anti-aimbot angles', 'Yaw')
            },

            yaw_jitter = {
                ui.reference('AA', 'Anti-aimbot angles', 'Yaw jitter')
            },

            body_yaw = {
                ui.reference('AA', 'Anti-aimbot angles', 'Body yaw')
            },

            freestanding_body_yaw = ui.reference(
                'AA', 'Anti-aimbot angles', 'Freestanding body yaw'
            ),

            edge_yaw = ui.reference(
                'AA', 'Anti-aimbot angles', 'Edge yaw'
            ),

            freestanding = {
                ui.reference('AA', 'Anti-aimbot angles', 'Freestanding')
            },

            roll = ui.reference(
                'AA', 'Anti-aimbot angles', 'Roll'
            )
        },

        fake_lag = {
            enabled = {
                ui.reference('AA', 'Fake lag', 'Enabled')
            },

            amount = ui.reference(
                'AA', 'Fake lag', 'Amount'
            ),

            variance = ui.reference(
                'AA', 'Fake lag', 'Variance'
            ),

            limit = ui.reference(
                'AA', 'Fake lag', 'Limit'
            ),
        },

        other = {
            slow_motion = {
                ui.reference('AA', 'Other', 'Slow motion')
            },

            on_shot_antiaim = {
                ui.reference('AA', 'Other', 'On shot anti-aim')
            },

            leg_movement = ui.reference(
                'AA', 'Other', 'Leg movement'
            )
        }
    }

    software.visuals = {
        effects = {
            remove_scope_overlay = ui.reference(
                'Visuals', 'Effects', 'Remove scope overlay'
            )
        }
    }

    software.misc = {
        miscellaneous = {
            ping_spike = {
                ui.reference('Misc', 'Miscellaneous', 'Ping spike')
            }
        },

        movement = {
            air_strafe = ui.reference(
                'Misc', 'Movement', 'Air strafe'
            )
        },

        settings = {
            menu_color = ui.reference(
                'Misc', 'Settings', 'Menu color'
            )
        }
    }

    function software.get_color(to_hex)
        if to_hex then
            return utils.to_hex(ui.get(software.misc.settings.menu_color))
        end

        return ui.get(software.misc.settings.menu_color)
    end

    function software.get_override_damage()
        return ui.get(software.ragebot.aimbot.minimum_damage_override[3])
    end

    function software.get_minimum_damage()
        return ui.get(software.ragebot.aimbot.minimum_damage)
    end

    function software.is_slow_motion()
        return ui.get(software.antiaimbot.other.slow_motion[1])
            and ui.get(software.antiaimbot.other.slow_motion[2])
    end

    function software.is_duck_peek_active()
        return ui.get(software.ragebot.other.duck_peek_assist)
    end

    function software.is_double_tap_active()
        return ui.get(software.ragebot.aimbot.double_tap[1])
            and ui.get(software.ragebot.aimbot.double_tap[2])
    end

    function software.is_override_minimum_damage()
        return ui.get(software.ragebot.aimbot.minimum_damage_override[1])
            and ui.get(software.ragebot.aimbot.minimum_damage_override[2])
    end

    function software.is_on_shot_antiaim_active()
        return ui.get(software.antiaimbot.other.on_shot_antiaim[1])
            and ui.get(software.antiaimbot.other.on_shot_antiaim[2])
    end

    function software.is_duck_peek_assist()
        return ui.get(software.ragebot.other.duck_peek_assist)
    end

    function software.is_quick_peek_assist()
        return ui.get(software.ragebot.other.quick_peek_assist[1])
            and ui.get(software.ragebot.other.quick_peek_assist[2])
    end
end

local color do
    color = ffi.typeof [[
        struct {
            unsigned char r;
            unsigned char g;
            unsigned char b;
            unsigned char a;
        }
    ]]

    local M = { } do
        M.__index = M

        function M.lerp(a, b, t)
            return color(
                a.r + t * (b.r - a.r),
                a.g + t * (b.g - a.g),
                a.b + t * (b.b - a.b),
                a.a + t * (b.a - a.a)
            )
        end

        function M:unpack()
            return self.r, self.g, self.b, self.a
        end

        function M:clone()
            return color(self:unpack())
        end

        function M:to_hex()
            return string.format(
                '%02X%02X%02X%02X',
                self:unpack()
            )
        end

        function M:__tostring()
            return string.format(
                '%i, %i, %i, %i',
                self:unpack()
            )
        end
    end

    ffi.metatype(color, M)
end

local detours do
    detours = { }

    local function copy(dst, src, len)
        return ffi.copy(ffi.cast('void*', dst), ffi.cast('const void*', src), len)
    end

    local jmp_ecx = client.find_signature('engine.dll', '\xFF\xE1')

    local get_proc_addr = ffi.cast('uint32_t**', ffi.cast('uint32_t', client.find_signature('engine.dll', '\xFF\x15\xCC\xCC\xCC\xCC\xA3\xCC\xCC\xCC\xCC\xEB\x05')) + 2)[0][0]
    local get_module_handle = ffi.cast('uint32_t**', ffi.cast('uint32_t', client.find_signature('engine.dll', '\xFF\x15\xCC\xCC\xCC\xCC\x85\xC0\x74\x0B')) + 2)[0][0]

    local fn_get_proc_addr = ffi.cast('uint32_t(__fastcall*)(unsigned int, unsigned int, uint32_t, const char*)', jmp_ecx)
    local fn_get_module_handle = ffi.cast('uint32_t(__fastcall*)(unsigned int, unsigned int, const char*)', jmp_ecx)

    local function proc_bind(module_name, function_name, typedef)
        local ctype = ffi.typeof(typedef)

        local module_handle = fn_get_module_handle(get_module_handle, 0, module_name)
        local proc_address = fn_get_proc_addr(get_proc_addr, 0, module_handle, function_name)

        local call_fn = ffi.cast(ctype, jmp_ecx)

        return function(...)
            return call_fn(proc_address, 0, ...)
        end
    end

    local native_VirtualProtect = proc_bind(
        'kernel32.dll', 'VirtualProtect', ffi.typeof(
            'int(__fastcall*)(unsigned int, unsigned int, void* lpAddress, unsigned long dwSize, unsigned long flNewProtect, unsigned long* lpflOldProtect)'
        )
    )

    local function virtual_protect(lpAddress, dwSize, flNewProtect, lpflOldProtect)
        return native_VirtualProtect(ffi.cast('void*', lpAddress), dwSize, flNewProtect, lpflOldProtect)
    end

    local hooks = { }

    function detours.new(ctype, callback, hook_addr, size)
        size = size or 5

        local hook = {
            call = ffi.cast(ctype, hook_addr),
            status = false
        }

        local old_prot = ffi.new('unsigned long[1]')
        local org_bytes = ffi.new('uint8_t[?]', size)

        copy(org_bytes, hook_addr, size)

        local detour_addr = tonumber(ffi.cast('intptr_t', ffi.cast('void*', ffi.cast(ctype, callback))))

        local hook_bytes = ffi.new('uint8_t[?]', size, 0x90)
        hook_bytes[0] = 0xE9

        ffi.cast('int32_t*', hook_bytes + 1)[0] = detour_addr - hook_addr - 5

        local function set_status(enable)
            if hook.status ~= enabled then
                hook.status = enable
                virtual_protect(hook_addr, size, 0x40, old_prot)
                copy(hook_addr, enable and hook_bytes or org_bytes, size)
                virtual_protect(hook_addr, size, old_prot[0], old_prot)
            end
        end

        function hook.start() set_status(true) end
        function hook.stop() set_status(false) end

        hook:start()

        table.insert(hooks, hook)

        return setmetatable(hook, {
            __call = function(self, ...)
                self:stop()
                local res = self.call(...)
                self:start()
                return res
            end
        })
    end

    function detours.unhook_all()
        for _, hook in ipairs(hooks) do
            hook:stop()
        end
    end

    client.set_event_callback('shutdown', detours.unhook_all)
end

local iinput do
    iinput = { }

	--- https://gitlab.com/KittenPopo/csgo-2018-source/-/blob/main/game/client/iinput.h

	local vector_t = ffi.typeof [[
		struct {
			float x;
			float y;
			float z;
		}
	]]

	local cusercmd_t = ffi.typeof([[
		struct {
			void     *vfptr;
			int      command_number;
			int      tickcount;
			$        viewangles;
			$        aimdirection;
			float    forwardmove;
			float    sidemove;
			float    upmove;
			int      buttons;
			uint8_t  impulse;
			int      weaponselect;
			int      weaponsubtype;
			int      random_seed;
			short    mousedx;
			short    mousedy;
			bool     hasbeenpredicted;
			$        headangles;
			$        headoffset;
			char	 pad_0x4C[0x18];
		}
	]], vector_t, vector_t, vector_t, vector_t)

    local signature = {
        'client.dll', '\xB9\xCC\xCC\xCC\xCC\x8B\x40\x38\xFF\xD0\x84\xC0\x0F\x85', 1
    }

	local vtable_addr = utils.find_signature(unpack(signature))
    local vtable_ptr = ffi.cast('uintptr_t***', vtable_addr)[0]

    local native_GetUserCmd = ffi.cast(ffi.typeof('$*(__thiscall*)(void*, int nSlot, int sequence_number)', cusercmd_t), vtable_ptr[0][8])

    function iinput.get_usercmd(slot, command_number)
        if command_number == 0 then
            return nil
        end

        return native_GetUserCmd(vtable_ptr, slot, command_number)
    end
end

local event_system do
    event_system = { }

    local function find(list, value)
        for i = 1, #list do
            if value == list[i] then
                return i
            end
        end

        return nil
    end

    local EventList = { } do
        EventList.__index = EventList

        function EventList:new()
            return setmetatable({
                list = { },
                count = 0
            }, self)
        end

        function EventList:__len()
            return self.count
        end

        function EventList:set(callback)
            if not find(self.list, callback) then
                self.count = self.count + 1
                table.insert(self.list, callback)
            end

            return self
        end

        function EventList:unset(callback)
            local index = find(self.list, callback)

            if index ~= nil then
                self.count = self.count - 1
                table.remove(self.list, index)
            end

            return self
        end

        function EventList:fire(...)
            local list = self.list

            for i = 1, #list do
                list[i](...)
            end

            return self
        end
    end

    local EventBus = { } do
        local function __index(list, k)
            local value = rawget(list, k)

            if value == nil then
                value = EventList:new()
                rawset(list, k, value)
            end

            return value
        end

        function EventBus:new()
            return setmetatable({ }, {
                __index = __index
            })
        end
    end

    function event_system:new()
        return EventBus:new()
    end
end

local logging_system do
    logging_system = { }

    local SOUND_SUCCESS = 'ui\\beepclear.wav'
    local SOUND_FAILURE = 'resource\\warning.wav'

    local play = cvar.play

    local function display_tag(r, g, b)
        client.color_log(r, g, b, script.name, '\0')
        client.color_log(255, 255, 255, ' ✦ ', '\0')
    end

    function logging_system.success(msg)
        display_tag(135, 135, 245)

        client.color_log(255, 255, 255, msg)
        play:invoke_callback(SOUND_SUCCESS)
    end

    function logging_system.error(msg)
        display_tag(250, 50, 75)

        client.color_log(255, 255, 255, msg)
        play:invoke_callback(SOUND_FAILURE)
    end
end

local config_system do
    config_system = { }

    local KEY = 'irEa5PqmVkMlw2Nj8B43dfnoeI9tHxzK1DX0JF6ULGAWcQuCTZpvh7syRgbYSO+/='

    local item_list = { }
    local item_data = { }

    local function get_key_values(arr)
        local list = { }

        if arr ~= nil then
            for i = 1, #arr do
                list[arr[i]] = i
            end
        end

        return list
    end

    function config_system.push(tab, name, item)
        if item_data[tab] == nil then
            item_data[tab] = { }
        end

        local data = {
            tab = tab,
            name = name,
            item = item
        }

        item_data[tab][name] = item
        table.insert(item_list, data)

        return item
    end

    function config_system.encode(data)
        local ok, result = pcall(json.stringify, data)

        if not ok then
            return false, result
        end

        ok, result = pcall(base64.encode, result, KEY)

        if not ok then
            return false, result
        end

        result = string.gsub(
            result, '[%+%/%=]', {
                ['+'] = 'g2134',
                ['/'] = 'g2634',
                ['='] = '_'
            }
        )

        result = string.format(
            'revelation: %s', result
        )

        return true, result
    end

    function config_system.decode(str)
        -- prefix detect + windows 11 notepad fix
        local matched, pad = str:match 'revelation: ([%w%+%/]+)(_*)'

        if matched == nil then
            return false, 'Config not supported'
        end

        -- enq, what the fuck...
        pad = pad and string.rep('=', #pad) or ''

        local data = string.gsub(matched, 'g2%d%d34', {
            ['g2134'] = '+',
            ['g2634'] = '/'
        })

        local ok, result = pcall(base64.decode, data .. pad, KEY)

        if not ok then
            return false, result
        end

        ok, result = pcall(json.parse, result)

        if not ok then
            return false, result
        end

        return true, result
    end

    function config_system.import(data, categories)
        if data == nil then
            return false, 'config is empty'
        end

        local keys = get_key_values(categories)

        for k, v in pairs(data) do
            if categories ~= nil and keys[k] == nil then
                goto continue
            end

            local items = item_data[k]

            if items == nil then
                goto continue
            end

            for m, n in pairs(v) do
                local item = items[m]

                if item ~= nil then
                    item:set(unpack(n))
                end
            end

            ::continue::
        end

        return true, nil
    end

    function config_system.export(categories)
        local list = { }

        local keys = get_key_values(categories)

        for k, v in pairs(item_data) do
            if categories ~= nil and keys[k] == nil then
                goto continue
            end

            local values = { }

            for m, n in pairs(v) do
                if n.type ~= 'hotkey' then
                    values[m] = n.value
                end
            end

            list[k] = values
            ::continue::
        end

        return list
    end
end

local locker_system do
    locker_system = { }

    local LEVELS = {
        ['dev'] = -1,
        ['elite'] = -1,
        ['primary'] = 0,
        ['united'] = 1
    }

    local LEVEL = LEVELS[
        script.build
    ]

    local list = { }

    local function update_items()
        for i = 1, #list do
            local data = list[i]

            data.item:set(unpack(data.value))
            data.item:set_enabled(false)
        end
    end

    function locker_system.force_update()
        update_items()
    end

    function locker_system.is_locked(level)
        -- debug check
        if LEVEL == -1 then
            return false
        end

        -- if not in debug
        if level == -1 then
            return true
        end

        return level >= LEVEL
    end

    function locker_system.push(level, item, ...)
        if not locker_system.is_locked(level) then
            return item
        end

        local value = { ... }

        if select('#', ...) == 0 then
            value = { false }
        end

        table.insert(list, {
            item = item,
            value = value
        })

        item:set(unpack(value))
        item:set_enabled(false)

        item:set_callback(
            update_items
        )

        return item
    end

    client.delay_call(
        0, update_items
    )

    client.set_event_callback(
        'post_config_load',
        update_items
    )
end

local shot_system do
    shot_system = { }

    local event_bus = event_system:new()

    local shot_list = { }

    local function create_shot_data(player)
        local tick = globals.tickcount()

        local eye_pos = vector(
            utils.get_eye_position(player)
        )

        local data = {
            tick = tick,

            player = player,
            victim = nil,

            eye_pos = eye_pos,
            impacts = { },

            damage = nil,
            hitgroup = nil
        }

        return data
    end

    local function on_weapon_fire(e)
        local userid = client.userid_to_entindex(e.userid)

        if userid == nil then
            return
        end

        table.insert(shot_list, create_shot_data(userid))
    end

    local function on_player_hurt(e)
        local userid = client.userid_to_entindex(e.userid)
        local attacker = client.userid_to_entindex(e.attacker)

        if userid == nil or attacker == nil then
            return
        end

        for i = #shot_list, 1, -1 do
            local data = shot_list[i]

            if data.player == attacker then
                data.victim = userid

                data.damage = e.dmg_health
                data.hitgroup = e.hitgroup

                break
            end
        end
    end

    local function on_bullet_impact(e)
        local userid = client.userid_to_entindex(e.userid)

        if userid == nil then
            return
        end

        for i = #shot_list, 1, -1 do
            local data = shot_list[i]

            if data.player == userid then
                local pos = vector(e.x, e.y, e.z)
                table.insert(data.impacts, pos)

                break
            end
        end
    end

    local function on_net_update_start()
        local me = entity.get_local_player()

        if me == nil then
            return
        end

        local head_pos = nil do
            if entity.is_alive(me) then
                head_pos = vector(entity.hitbox_position(me, 0))
            end
        end

        for i = 1, #shot_list do
            local data = shot_list[i]

            local impact_count = #data.impacts

            if impact_count == 0 then
                goto continue
            end

            local eye_pos = data.eye_pos
            local end_pos = data.impacts[impact_count]

            event_bus.player_shot:fire {
                tick = data.tick,

                player = data.player,
                victim = data.victim,

                eye_pos = eye_pos,
                end_pos = end_pos,

                damage = data.damage,
                hitgroup = data.hitgroup
            }

            if head_pos ~= nil and entity.is_enemy(data.player) then
                local closest_point = utils.closest_ray_point(
                    eye_pos, end_pos, head_pos, true
                )

                local distancesqr = head_pos:distsqr(closest_point)

                if distancesqr <= 80 * 80 then
                    local distance = math.sqrt(distancesqr)

                    event_bus.enemy_shot:fire {
                        tick = data.tick,
                        distance = distance,

                        player = data.player,
                        victim = data.victim,

                        eye_pos = eye_pos,
                        end_pos = end_pos,

                        damage = data.damage,
                        hitgroup = data.hitgroup
                    }
                end
            end

            ::continue::
        end

        for i = 1, #shot_list do
            shot_list[i] = nil
        end
    end

    function shot_system.get_event_bus()
        return event_bus
    end

    client.set_event_callback('weapon_fire', on_weapon_fire)
    client.set_event_callback('player_hurt', on_player_hurt)
    client.set_event_callback('bullet_impact', on_bullet_impact)
    client.set_event_callback('net_update_start', on_net_update_start)
end

local menu do
    menu = { }

    local event_bus = event_system:new()

    local Item = { } do
        Item.__index = Item

        local function pack(ok, ...)
            if not ok then
                return nil
            end

            return ...
        end

        local function get_value_array(ref)
            return { pack(pcall(ui.get, ref)) }
        end

        local function get_key_values(arr)
            local list = { }

            for i = 1, #arr do
                list[arr[i]] = i
            end

            return list
        end

        local function update_item_values(item, initial)
            local value = get_value_array(item.ref)

            item.value = value

            if initial then
                item.default = value
            end

            if item.type == 'multiselect' then
                item.key_values = get_key_values(unpack(value))
            end
        end

        function Item:new(ref)
            return setmetatable({
                ref = ref,
                type = nil,

                list = { },
                value = { },
                default = { },
                key_values = { },

                callbacks = { }
            }, self)
        end

        function Item:init(...)
            local function callback()
                update_item_values(self, false)
                self:fire_events()

                event_bus.item_changed:fire(self)
            end

            self.type = ui.type(self.ref)

            if self.type ~= 'label' then
                update_item_values(self, true)
                pcall(ui.set_callback, self.ref, callback)
            end

            if self.type == 'multiselect' or self.type == 'list' then
                self.list = select(4, ...)
            end

            if self.type == 'button' then
                local fn = select(4, ...)

                if fn ~= nil then
                    self:set_callback(fn)
                end
            end

            event_bus.item_init:fire(self)
        end

        function Item:get(key)
            if self.type == 'hotkey' or self.type == 'textbox' then
                return ui.get(self.ref)
            end

            if key ~= nil then
                return self.key_values[key] ~= nil
            end

            return unpack(self.value)
        end

        function Item:set(...)
            ui.set(self.ref, ...)
            update_item_values(self, false)
        end

        function Item:update(...)
            ui.update(self.ref, ...)
        end

        function Item:reset()
            pcall(ui.set, self.ref, unpack(self.default))
        end

        function Item:set_enabled(value)
            return ui.set_enabled(self.ref, value)
        end

        function Item:set_visible(value)
            return ui.set_visible(self.ref, value)
        end

        function Item:set_callback(callback, force_call)
            local index = contains(self.callbacks, callback)

            if index == nil then
                table.insert(self.callbacks, callback)
            end

            if force_call then
                callback(self)
            end

            return self
        end

        function Item:unset_callback(callback)
            local index = contains(self.callbacks, callback)

            if index ~= nil then
                table.remove(self.callbacks, index)
            end

            return self
        end

        function Item:fire_events()
            local list = self.callbacks

            for i = 1, #list do
                list[i](self)
            end
        end
    end

    function menu.new(fn, ...)
        local ref = fn(...)

        local item = Item:new(ref) do
            item:init(...)
        end

        return item
    end

    function menu.get_event_bus()
        return event_bus
    end
end

local menu_logic do
    menu_logic = { }

    local item_data = { }
    local item_list = { }

    local logic_events = event_system:new()

    function menu_logic.get_event_bus()
        return logic_events
    end

    function menu_logic.set(item, value)
        if item == nil or item.ref == nil then
            return
        end

        item_data[item.ref] = value
    end

    function menu_logic.force_update()
        for i = 1, #item_list do
            local item = item_list[i]

            if item == nil then
                goto continue
            end

            local ref = item.ref

            if ref == nil then
                goto continue
            end

            local value = item_data[ref]

            if value == nil then
                goto continue
            end

            item:set_visible(value)
            item_data[ref] = false

            ::continue::
        end
    end

    local menu_events = menu.get_event_bus() do
        local function on_item_init(item)
            item_data[item.ref] = false
            item:set_visible(false)

            table.insert(item_list, item)
        end

        local function on_item_changed(...)
            logic_events.update:fire(...)
            menu_logic.force_update()
        end

        menu_events.item_init:set(on_item_init)
        menu_events.item_changed:set(on_item_changed)
    end
end


local windows do
    windows = { }

    local data = { }
    local queue = { }

    local mouse_pos = vector()
    local mouse_pos_prev = vector()

    local mouse_down = false
    local mouse_clicked = false

    local mouse_down_duration = 0

    local mouse_delta = vector()
    local mouse_clicked_pos = vector()

    local hovered_window
    local foreground_window

    local c_window = { } do
        function c_window:new(name)
            local window = { }

            window.name = name

            window.pos = vector()
            window.size = vector()

            window.anchor = vector(0.0, 0.0)

            window.updated = false
            window.dragging = false

            window.item_x = menu.new(ui.new_string, string.format('%s_x', name))
            window.item_y = menu.new(ui.new_string, string.format('%s_y', name))

            data[name] = window
            queue[#queue + 1] = window

            return setmetatable(
                window, self
            )
        end

        function c_window:set_pos(pos)
            local screen = vector(
                client.screen_size()
            )

            local is_screen_invalid = (
                screen.x == 0 and
                screen.y == 0
            )

            if is_screen_invalid then
                return
            end

            local new_pos = pos:clone()

            new_pos.x = utils.clamp(new_pos.x, 0, screen.x - self.size.x)
            new_pos.y = utils.clamp(new_pos.y, 0, screen.y - self.size.y)

            self.pos = new_pos
        end

        function c_window:set_size(size)
            local screen = vector(
                client.screen_size()
            )

            local is_screen_invalid = (
                screen.x == 0 and
                screen.y == 0
            )

            if is_screen_invalid then
                return
            end

            local size_delta = size - self.size

            self.size = size
            self:set_pos(self.pos - size_delta * self.anchor)
        end

        function c_window:set_anchor(anchor)
            self.anchor = anchor
        end

        function c_window:is_hovering()
            return self.hovering
        end

        function c_window:is_dragging()
            return self.dragging
        end

        function c_window:update()
            self.updated = true
        end

        c_window.__index = c_window
    end

    local function is_collided(point, a, b)
        return point.x >= a.x and point.y >= a.y
            and point.x <= b.x and point.y <= b.y
    end

    local function update_mouse_inputs()
        local cursor = vector(ui.mouse_position())
        local is_down = client.key_state(0x01)

        local delta_time = globals.frametime()

        mouse_pos = cursor
        mouse_delta = mouse_pos - mouse_pos_prev

        mouse_pos_prev = mouse_pos

        mouse_down = is_down
        mouse_clicked = is_down and mouse_down_duration < 0

        mouse_down_duration = is_down and (mouse_down_duration < 0 and 0 or mouse_down_duration + delta_time) or -1

        if mouse_clicked then
            mouse_clicked_pos = mouse_pos
        end
    end

    local function appear_all_windows()
        for i = 1, #queue do
            local window = queue[i]

            local pos = window.pos
            local size = window.size

            local r, g, b, a = 0, 0, 0, 100

            renderer.rectangle(pos.x, pos.y, size.x, size.y, r, g, b, a)
        end
    end

    local function find_hovered_window()
        local found_window = nil

        if ui.is_menu_open() then
            for i = 1, #queue do
                local window = queue[i]

                local pos = window.pos
                local size = window.size

                if not window.updated then
                    goto continue
                end

                if not is_collided(mouse_pos, pos, pos + size) then
                    goto continue
                end

                found_window = window

                ::continue::
            end
        end

        hovered_window = found_window
    end

    local function find_foreground_window()
        if mouse_down then
            if mouse_clicked and hovered_window ~= nil then
                for i = 1, #queue do
                    local window = queue[i]

                    if window == hovered_window then
                        table.remove(queue, i)
                        table.insert(queue, window)

                        break
                    end
                end

                foreground_window = hovered_window
                return
            end

            return
        end

        foreground_window = nil
    end

    local function update_all_windows()
        for i = 1, #queue do
            local window = queue[i]

            window.updated = false

            window.hovering = false
            window.dragging = false
        end
    end

    local function update_hovered_window()
        if hovered_window == nil then
            return
        end

        hovered_window.hovering = true
    end

    local function update_foreground_window()
        if foreground_window == nil then
            return
        end

        local new_position = foreground_window.pos + mouse_delta

        foreground_window:set_pos(new_position)
        foreground_window.dragging = true
    end

    local function save_windows_settings()
        local screen = vector(
            client.screen_size()
        )

        for i = 1, #queue do
            local window = queue[i]

            local x = window.pos.x / screen.x
            local y = window.pos.y / screen.y

            window.item_x:set(tostring(x))
            window.item_y:set(tostring(y))
        end
    end

    local function load_windows_settings()
        local screen = vector(
            client.screen_size()
        )

        for i = 1, #queue do
            local window = queue[i]

            local x = tonumber(window.item_x:get())
            local y = tonumber(window.item_y:get())

            if x ~= nil and y ~= nil then
                window:set_pos(screen * vector(x, y))
            end
        end
    end

    local function on_paint_ui()
        -- appear_all_windows()
        update_mouse_inputs()

        find_hovered_window()
        find_foreground_window()

        update_all_windows()

        update_hovered_window()
        update_foreground_window()
    end

    local function on_setup_command(cmd)
        local should_update = (
            hovered_window ~= nil or
            foreground_window ~= nil
        )

        if should_update then
            cmd.in_attack = 0
            cmd.in_attack2 = 0
        end
    end

    function windows.new(name, x, y)
        local window = data[name]
            or c_window:new(name)

        window:set_pos(vector(x, y))

        return window
    end

    function windows.save_settings()
        save_windows_settings()
    end

    function windows.load_settings()
        load_windows_settings()
    end

    client.delay_call(0, function()
        client.set_event_callback(
            'paint_ui', on_paint_ui
        )

        client.set_event_callback(
            'setup_command',
            on_setup_command
        )

        client.set_event_callback(
            'pre_config_save',
            save_windows_settings
        )

        client.set_event_callback(
            'post_config_load',
            load_windows_settings
        )
    end)
end

local text_anims do
    text_anims = { }

    local function u8(str)
        local chars = { }
        local count = 0

        for c in string.gmatch(str, '.[\128-\191]*') do
            count = count + 1
            chars[count] = c
        end

        return chars, count
    end

    function text_anims.gradient(str, time, r1, g1, b1, a1, r2, g2, b2, a2)
        local list = { }

        local strbuf, strlen = u8(str)
        local div = 1 / (strlen - 1)

        local delta_r = r2 - r1
        local delta_g = g2 - g1
        local delta_b = b2 - b1
        local delta_a = a2 - a1

        for i = 1, strlen do
            local char = strbuf[i]

            local t = time do
                t = t % 2

                if t > 1 then
                    t = 2 - t
                end
            end

            local r = r1 + t * delta_r
            local g = g1 + t * delta_g
            local b = b1 + t * delta_b
            local a = a1 + t * delta_a

            local hex = utils.to_hex(r, g, b, a)

            table.insert(list, '\a')
            table.insert(list, hex)
            table.insert(list, char)

            time = time + div
        end

        return table.concat(list)
    end
end

local text_fmt do
    text_fmt = { }

    local function decompose(str)
        local result, len = { }, #str

        local i, j = str:find('\a', 1)

        if i == nil then
            table.insert(result, {
                str, nil
            })
        end

        if i ~= nil and i > 1 then
            table.insert(result, {
                str:sub(1, i - 1), nil
            })
        end

        while i ~= nil do
            local hex = nil

            if str:sub(j + 1, j + 7) == 'DEFAULT' then
                j = j + 8
            else
                hex = str:sub(j + 1, j + 8)
                j = j + 9
            end

            local m, n = str:find('\a', j + 1)

            if m == nil then
                if j <= len then
                    table.insert(result, {
                        str:sub(j), hex
                    })
                end

                break
            end

            table.insert(result, {
                str:sub(j, m - 1), hex
            })

            i, j = m, n
        end

        return result
    end

    function text_fmt.color(str)
        local list = decompose(str)
        local len = #list

        return list, len
    end
end

local const do
    const = { }

    const.states = {
        'Default',
        'Standing',
        'Moving',
        'Slow Walk',
        'Jumping',
        'Jumping+',
        'Crouch',
        'Move-Crouch',
        'Legit AA',
        'Fakelag',
        'Dormant',
        'Manual AA',
        'Freestanding'
    }
end

local localplayer do
    localplayer = { }

    local pre_flags = 0
    local post_flags = 0

    localplayer.is_moving = false
    localplayer.is_onground = false
    localplayer.is_crouched = false

    localplayer.duck_amount = 0.0
    localplayer.velocity2d_sqr = 0

    localplayer.is_peeking = false
    localplayer.is_vulnerable = false

    localplayer.delta = 0

    -- from @enq
    local function is_peeking(player)
        local should, vulnerable = false, false
        local velocity = vector(entity.get_prop(player, 'm_vecVelocity'))

        local eye = vector(client.eye_position())
        local peye = utils.extrapolate(eye, velocity, 14)

        local enemies = entity.get_players(true)

        for i = 1, #enemies do
            local enemy = enemies[i]

            local esp_data = entity.get_esp_data(enemy)

            if esp_data == nil then
                goto continue
            end

            if bit.band(esp_data.flags, bit.lshift(1, 11)) ~= 0 then
                vulnerable = true
                goto continue
            end

            local head = vector(entity.hitbox_position(enemy, 0))
            local phead = utils.extrapolate(head, velocity, 4)
            local entindex, damage = client.trace_bullet(player, peye.x, peye.y, peye.z, phead.x, phead.y, phead.z)

            if damage ~= nil and damage > 0 then
                should = true
                break
            end

            ::continue::
        end

        return should, vulnerable
    end

    local function get_delta(player)
        local player_info = c_entity(player)

        if player_info == nil then
            return 0
        end

        local animstate = player_info:get_anim_state()

        if animstate == nil then
            return 0
        end

        local eye_yaw = animstate.eye_angles_y
        local feet_yaw = animstate.goal_feet_yaw

        local delta = eye_yaw - feet_yaw

        delta = utils.normalize(delta, -180, 180)
        delta = utils.clamp(delta, -60, 60)

        return delta
    end

    local function on_pre_predict_command(cmd)
        local me = entity.get_local_player()

        if me == nil then
            return
        end

        pre_flags = entity.get_prop(me, 'm_fFlags')
    end

    local function on_predict_command(cmd)
        local me = entity.get_local_player()

        if me == nil then
            return
        end

        post_flags = entity.get_prop(me, 'm_fFlags')
    end

    local function on_setup_command(cmd)
        local me = entity.get_local_player()

        if me == nil then
            return
        end

        local peeking, vulnerable = is_peeking(me)

        local is_onground = bit.band(pre_flags, 1) ~= 0
            and bit.band(post_flags, 1) ~= 0

        local velocity = vector(entity.get_prop(me, 'm_vecVelocity'))
        local duck_amount = entity.get_prop(me, 'm_flDuckAmount')

        local velocity2d_sqr = velocity:length2dsqr()

        localplayer.is_moving = velocity2d_sqr > 5 * 5
        localplayer.is_onground = is_onground

        localplayer.is_peeking = peeking
        localplayer.is_vulnerable = vulnerable

        if cmd.chokedcommands == 0 then
            localplayer.is_crouched = duck_amount > 0.5
            localplayer.duck_amount = duck_amount

            localplayer.delta = get_delta(me)
        end

        localplayer.velocity2d_sqr = velocity2d_sqr
    end

    client.set_event_callback('pre_predict_command', on_pre_predict_command)
    client.set_event_callback('predict_command', on_predict_command)
    client.set_event_callback('setup_command', on_setup_command)
end

local exploit do
    exploit = { }

    local BREAK_LAG_COMPENSATION_DISTANCE_SQR = 64 * 64

    local max_tickbase = 0
    local run_command_number = 0

    local data = {
        old_origin = vector(),
        old_simtime = 0.0,

        shift = false,
        breaking_lc = false,

        defensive = {
            force = false,
            left = 0,
            max = 0,
        },

        lagcompensation = {
            distance = 0.0,
            teleport = false
        }
    }

    local function update_tickbase(me)
        data.shift = globals.tickcount() > entity.get_prop(me, 'm_nTickBase')
    end

    local function update_teleport(old_origin, new_origin)
        local delta = new_origin - old_origin
        local distance = delta:lengthsqr()

        local is_teleport = distance > BREAK_LAG_COMPENSATION_DISTANCE_SQR

        data.breaking_lc = is_teleport

        data.lagcompensation.distance = distance
        data.lagcompensation.teleport = is_teleport
    end

    local function update_lagcompensation(me)
        local old_origin = data.old_origin
        local old_simtime = data.old_simtime

        local origin = vector(entity.get_origin(me))
        local simtime = toticks(entity.get_prop(me, 'm_flSimulationTime'))

        if old_simtime ~= nil then
            local delta = simtime - old_simtime

            if delta < 0 or delta > 0 and delta <= 64 then
                update_teleport(old_origin, origin)
            end
        end

        data.old_origin = origin
        data.old_simtime = simtime
    end

    local function update_defensive_tick(me)
        local tickbase = entity.get_prop(me, 'm_nTickBase')

        if math.abs(tickbase - max_tickbase) > 64 then
            -- nullify highest tickbase if the difference is too big
            max_tickbase = 0
        end

        local defensive_ticks_left = 0

        -- defensive effect can be achieved because the lag compensation is made so that
        -- it doesn't write records if the current simulation time is less than/equals highest acknowledged simulation time
        -- https://gitlab.com/KittenPopo/csgo-2018-source/-/blame/main/game/server/player_lagcompensation.cpp#L723

        if tickbase > max_tickbase then
            max_tickbase = tickbase
        elseif max_tickbase > tickbase then
            defensive_ticks_left = math.min(14, math.max(0, max_tickbase - tickbase - 1))
        end

        if defensive_ticks_left > 0 then
            data.breaking_lc = true
            data.defensive.left = defensive_ticks_left

            if data.defensive.max == 0 then
                data.defensive.max = defensive_ticks_left
            end
        else
            data.defensive.left = 0
            data.defensive.max = 0
        end
    end

    function exploit.get()
        return data
    end

    local function on_predict_command(cmd)
        local me = entity.get_local_player()

        if me == nil then
            return
        end

        if cmd.command_number == run_command_number then
            update_defensive_tick(me)
            run_command_number = nil
        end
    end

    local function on_run_command(e)
        local me = entity.get_local_player()

        if me == nil then
            return
        end

        update_tickbase(me)

        run_command_number = e.command_number
    end

    local function on_net_update_start()
        local me = entity.get_local_player()

        if me == nil then
            return
        end

        update_lagcompensation(me)
    end

    client.set_event_callback('predict_command', on_predict_command)
    client.set_event_callback('run_command', on_run_command)

    client.set_event_callback('net_update_start', on_net_update_start)
end

local statement do
    statement = { }

    local list = { }
    local count = 0

    local function add(state)
        count = count + 1
        list[count] = state
    end

    local function clear_list()
        for i = 1, count do
            list[i] = nil
        end

        count = 0
    end

    local function update_onground()
        if not localplayer.is_onground then
            return
        end

        if localplayer.is_moving then
            add 'Moving'

            if localplayer.is_crouched then
                return
            end

            if software.is_slow_motion() then
                add 'Slow Walk'
            end

            return
        end

        add 'Standing'
    end

    local function update_crouched()
        if not localplayer.is_crouched then
            return
        end

        add 'Crouch'

        if localplayer.is_moving then
            add 'Move-Crouch'
        end
    end

    local function update_in_air()
        if localplayer.is_onground then
            return
        end

        add 'Jumping'

        if localplayer.is_crouched then
            add 'Jumping+'
        end
    end

    function statement.get()
        return list
    end

    local function on_setup_command()
        clear_list()

        update_onground()
        update_crouched()
        update_in_air()
    end

    client.set_event_callback(
        'setup_command',
        on_setup_command
    )
end

local ref do
    ref = { }

    local function new_key(str, key)
        if str:find '\n' == nil then
            str = str .. '\n'
        end

        return str .. key
    end

    local function lock_unselection(item, default_value)
        local old_value = item:get()

        if #old_value == 0 then
            if default_value == nil then
                if item.type == 'multiselect' then
                    default_value = item.list
                elseif item.type == 'list' then
                    default_value = { }

                    for i = 1, #item.list do
                        default_value[i] = i
                    end
                end
            end

            old_value = default_value
            item:set(default_value)
        end

        item:set_callback(function()
            local value = item:get()

            if #value > 0 then
                old_value = value
            else
                item:set(old_value)
            end
        end)
    end

    local general = { } do
        local categories = {
            '\u{E28F}  Configs',
            '\u{E148}  Ragebot',
            '\u{E149}  Anti-Aim',
            '\u{E2B1}  Visuals',
            '\u{E115}  Misc'
        }

        general.label = menu.new(
            ui.new_label, 'AA', 'Fake lag', 'revelation'
        )

        general.category = menu.new(
            ui.new_combobox, 'AA', 'Fake lag', '\n revelation.category', categories
        )

        general.empty_bag = menu.new(
            ui.new_label, 'AA', 'Fake lag', '\n o0o0o0o0o0oo0oooo00o0ooo0ooo0o0o0o0o'
        )

        general.line = menu.new(
            ui.new_label, 'AA', 'Fake lag', '\n revelation.line'
        )

        general.welcome_text = menu.new(
            ui.new_label, 'AA', 'Fake lag', '\n revelation.welcome_text'
        )

        general.build_name = menu.new(
            ui.new_label, 'AA', 'Fake lag', '\n revelation.build_name'
        )

        local function update_welcome_text(item)
            local hex = utils.to_hex(
                ui.get(item)
            )

            general.welcome_text:set(string.format(
                '\a%s\u{E13D}  \aC8C8C8FFWelcome, \a%s%s', hex, hex, script.user
            ))

            general.build_name:set(string.format(
                '\a%s\u{E1CB}  \aC8C8C8FFYour build is \a%s%s', hex, hex, script.build
            ))
        end

        ui.set_callback(software.misc.settings.menu_color, update_welcome_text)
        update_welcome_text(software.misc.settings.menu_color)

        client.set_event_callback('paint_ui', function()
            if not ui.is_menu_open() then
                return
            end

            local min, max = 660, 750
            local width = ui.menu_size()

            local content_region = utils.map(width, min, max, 0, 1, true)

            local r1, g1, b1, a1 = 80, 80, 80, 255
            local r2, g2, b2, a2 = software.get_color()

            local name = string.format(
                '%s', 'revelation'
            )

            local text = text_anims.gradient(
                name, -globals.realtime(),
                r1, g1, b1, a1, r2, g2, b2, a2
            )

            -- content fill
            text = string.rep('\u{0020}', utils.lerp(20, 27, content_region)) .. text

            general.label:set(text)

            local underline = text_anims.gradient(
                '‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾', -globals.realtime(),
                r1, g1, b1, a1, r2, g2, b2, a2
            )

            general.line:set(underline)
        end)
    end

    local config = { } do
        local DB_NAME = 'revelation#db'
        local DB_DATA = database.read(DB_NAME) or { }

        local config_data = { }
        local config_list = { }

        local config_defaults = {
            [1] = {
                name = 'Default',
                data = 'revelation: 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__'
            },

            [2] = {
                name = 'unmatched',
                data = 'revelation: zpks9o27enZvV0GYV6PvHqf0xPOpeoBGtpgsenZ7I4Vbnv57wPhcV62cenghenHuIngDe6ZFIEVbnsIDtm2Fo4TXeUfctqfhoyBpen2FHUwuIngDe6ZFIEVbnsIDtm2Fo4TXeyfvxqOQoy20tyrFl6fuenkcIn8XNFQhHUfFo4TXIsPQIo2FtU2FosFuIqF0eoBCHXg89ngUVP2T9nQFl62LengUIfO0tsZCHXVbnsIDtm2Fo4TXIqfXxnxKHqPuInTuesOctyVXNFcp23dcw0d7laV724Tp23fxlEkJen7DIsfK9ngJ9n2DxqOpl6ICtU8XNFcXBqf6eofcxEkxlEkGt6BGesPhtykvl6O6IU2FxEVbnvFxlEks9nfytnOJInTuI6OsV0Gtw3iTwPhcV627HyBCtfOvesOTI4gUeoiXNFcZwFhcVUBL9okJoyrFHU2CtXgJ9o2heng0I4VbnvdTo4TXx6FFxs7CIqfcl6fuenkcIn8XNFQhHUfFo4TXxsPhIokQeokWl62CtqOpV0GtwETp23dcw0d7laV72fhcVUxDxqfptnPp9pgJ9o2TtqPgV0Gtzy7xlEkUen7FHsfuHsfK9ngJ9n2DxqOplJ7GtXR1BqPQenxFl62LengUIfO0tsZCHXVbnsIDtm2Fo4TXxsOptqBKtnPp9sfplU2hznZFV0GtVJ2pty2vVFhcV6IDHyBKtqPJIqfpl6fuenkcIn8XNFQ6enZvIfhcVUIGIoxQtsBFtEgCHmrCHsFhIfOWt6F6IfOLengJV0GtI6PcHsfxlEkytykcIPOQeokWIoVuHyrpInPJV0Gtw0d7laVTwETTlaV72fhcV6xDtnfvIngvIfOGt6BGesPhtyVu4qFJI4r39qOhHpg0tsZCHFOT9n2WIoVXNFcTlaV724Tp23dcw0d7o4TXxsOptqBKtnPp9sfpl6BFeoBLV0Gtw3iTla5TwETp23dcw0d7o4TXe6OQeFOGt6BGesPhtyVuIsOCIPO0tsZCHXVbnv5y24TZ2vdcw0d7laV72fhcV6xDtnfvIngvIfOGt6BGesPhtyVuI6OctqOyosFuoyBL9okJHqfpHsOuV0GtI6PcHsfxlEkUen7FHsfuHsfK9ngJ9n2DxqOplJDGxEra9qPuesduesDDt6xFos2CtqOpV0GtI6PcHsfxlEkUen7FHsfuHsfK9ngJ9n2DxqOplJID9sd1Bmf09pg0tsZCHFOT9n2WIoVXNFcTlaV724Tp23dcw0d7o4TXx6fcts2GxmFKxsPpt6FuIpgFt6PXtqfJV0Gtxmk7IfhcVUxCH6ZJos7DH6QFHXgTH6fJ9n2h9nOuosfpH6OpV0Gtw0d7la5p24TZw0dcw0d7o4TXtnPuxnPcosPpH6OyHpg0tsZCHFODes2FtU8XNFcp23dcw0d7laV724TpwarxlEkh9qFpIPOTIokvtsRutnOJI4Vbnpk39ngUtqdXo4TXIsPQIo2FtU2FosFuIqF0eoBCHXgEtsBgV5PGt4gFt6PXtqfJV0Gtxmk7IfhcV6xDtnfvIngvIfOGt6BGesPhtyVuBUkFIo2hengJ9ngUl627HyBCtfOuen7FV0GtVXkxlEkGt6BGesPhtykvl6fuenkcIn8XNFQhHUfFo4TXxsOptqBKtnPp9sfpl0SXNFcp23dcw0d7laV724Tp23fxlEkyeoBFH67DH6cue6P09sxptyfuIPO0tsZCHXVbnvV724Tp23dcw0d7la8vo4TXxsPhIokQeokWlUrCHsFh9nOuV0GtVJ27HyBCt4kxlEkXts7XosFuIqF0eoBCHXgXenBKesOctyVXNFcpw0icwvic23icw0d7o4TXxsOptqBKtnPp9sfplUfuH6fU9o2hIokFIPOv9qOhV0Gtw3iTla5TwETp23dcw0d7o4TXeyfvxqOQoy20tyrFl67CIqdXNFcX8ykCHywXo4TX9ngJ9n2DxqOpHpg0tsZCHFODes2FtU8XNFcp23dcw3eZla5sw4Tp23fxlEkDt6FQeoBGtsgKeUkFenQFHXgGtFOD9okKtqfUHpVbnpkjI6eXo4TXIsPQIo2FtU2FosFuIqF0eoBCHXgEtsBgV5PGt4g0tsZCHFOT9n2WIoVXNFcTlaV724Tp23dcw0d7o4TXIsPQIo2FtU2FosFuIqF0eoBCHXg3enIFVPrC9nghl627HyBCtfOuen7FV0GtVXkxlEkUen7FHsfuHsfK9ngJ9n2DxqOplJIpInfvxqPuIqFuIpgFt6PXtqfJV0Gtxmk7IfhcV6Pu9n7DxqFCtFOXH6fD9sfplUrGxq2LosOuosZDt68XNFQ6enZvIfhcV6xDtnfvIngvIfOGt6BGesPhtyVudqFuIpr3HqFWI4gFt6PXtqfJV0Gtxmk7IfhcVUBL9okJoyrFHU2CtXgJxnPcosBGHyBDt62FV0GtwvrxlEkUen7FHsfuHsfK9ngJ9n2DxqOplJDGxEra9qPuesdueyfvxqOQosgDtndXNFcXVFhcV6BDtnPUIfOQeokWIoVuIngDe6ZFIEVbnyBpxnfxlEkDt6FQeoBGtsgKeUkFenQFHXgGtFOD9okKHyBDxqF0oyIDtmfFV0Gtw3iTo4TXIsPQIo2FtU2FosFuIqF0eoBCHXgqH6fFHyBDt6BGt6HuesOctykKHqF09sfpV0GtwETp23dcw0d7laV72fhcV6Pu9n7DxqFCtFOXH6fD9sfpl6OuIykCxngJosGGxmBFHFOQ9ngKx6PcxndXNFc7wPhcV6xDtnfvIngvIfOGt6BGesPhtyVu4qFJI4r39qOhHpg09qPuIsfKesOctyVXNFQ6enZvIfhcV6Pu9n7DxqFCtFOXH6fD9sfpl6fDHUBLHofD9sdXNFQ6enZvIfhcV6kCtnkK9ngJ9n2DxqOpl6fuenkcIn8XNFQ6enZvIfhcV6xDtnfvIngvIfOGt6BGesPhtyVuBUkFIo2hengJ9ngUl62LengUIfO0tsZCHXVbnsIDtm2Fo4TXeyfvxqOQoy20tyrFl6Pu9n7DxqFCtFOvHqfFIEVbnvdso4TXIsPQIo2FtU2FosFuIqF0eoBCHXg3enIFVPrC9nghl62LengUIfO0tsZCHXVbnsIDtm2Fo4TXeo2TIn2hoykDxqFCl6fuenkcIn8XNFQhHUfFo4TX9ngJ9n2DxqOpHpg0tsZCHFOvIn2Ct6BDHUJXNFcp23dcw0d7laV724Tp23fxlEk0xo2hts7KHs2CHqduesOctyVXNFcp23dcw0d7laV724Tp23fxlEkUen7FHsfuHsfK9ngJ9n2DxqOplJkCImJ18nFQl62LengUIfO0tsZCHXVbnsIDtm2Fo4TXIqPQenxFosFuIqF0eoBCHXgFt6PXtqfJV0GtI6PcHsfxlEkytykcIPOQeokWIoVu9qFhV0Gtw31TlaVvwETvwETp23fxlEkQeng7enZKeokptyxvl62CtqOpoy2FesOuIqPpz4VbnvV724Tp23dcw0d7laVTwPhcV6xDtnfvIngvIfOGt6BGesPhtyVu3nFulXr5en7DIsduesOctykKHqF09sfpV0GtwETp23dcw0d7laV72fhcV6xDtnfvIngvIfOGt6BGesPhtyVuBqO7e6ZFVPBDHEg0tsZCHFOT9n2WIoVXNFcTlaV724Tp23dcw0d7o4TXIqPQenxFosFuIqF0eoBCHXgJ9o2TtqPgV0GtVJPcxsPgHprjtXkxlEkUen7FHsfuHsfK9ngJ9n2DxqOplJID9sd1Bmf09pg0xo2hts7Kt6PQI4VbnpVXo4TX9ngJ9n2DxqOpHpgvxmFcI4Vbnpk5InIDxnZhVFhcVU20tyrFosPu9n7DxqFCtXgFt6PXtqfJV0Gtxmk7IfhcV6xDtnfvIngvIfOGt6BGesPhtyVuIngDe6ZFIEVbnsIDtm2Fo4TXeUfctqfhoyBpen2FHUwuImfpeoBGtsRXNFcpwPhcV6xDtnfvIngvIfOGt6BGesPhtyVu4qFhV52Leng0I4gFt6PXtqfJV0Gtxmk7IfhcV6xDtnfvIngvIfOGt6BGesPhtyVu3nFulXr5en7DIsduIngDe6ZFIEVbnyBpxnfxlEkUen7FHsfuHsfK9ngJ9n2DxqOplJBCxnkcI4rdeoiueyfvxqOQosgDtndXNFcXVFhcV6Pu9n7DxqFCtFOXH6fD9sfpl6fuenkcIn8XNFQhHUfFo4TXx6FFxs7CIqfcl6O6IU2FxPObV0Gtl35TwPhcV6xDtnfvIngvIfOGt6BGesPhtyVuB6PWI4r5xn2Wl62LengUIfO0tsZCHXVbnsIDtm2Fo4TXtnPuxnPcosPpH6OyHpgvxmFcI4VbnpkrtmBFH6gDxqFsI4kxlEkJen7DIsfKtnPp9sfpl62CtqOpV0Gtw0d7laV724Tp23dcw0d7o4TXIqPQenxFosFuIqF0eoBCHXg0tsZCHXVbnvicw0d7laV724Tp23fxlEkUen7FHsfuHsfK9ngJ9n2DxqOplJID9sd1Bmf09pgFt6PXtqfJV0Gtxmk7IfhcV6BFeUfUoyrDt6fcl6fuenkcIn8XNFQ6enZvIfhcV6xDtnfvIngvIfOGt6BGesPhtyVuBqO7e6ZFVPBDHEgFt6PXtqfJV0Gtxmk7IfhcV6xDtnfvIngvIfOGt6BGesPhtyVudqFuIpr3HqFWI4g0tsZCHFOT9n2WIoVXNFcTlaV724Tp23dcw0d7o4TXtnPuxnPcosPpH6OyHpgFt6PXtqfJV0Gtxmk7IfhcV6xDtnfvIngvIfOGt6BGesPhtyVuBqO7e6ZFVPBDHEg09qPuIsfKesOctyVXNFQ6enZvIfhcVUBL9okJoyrFHU2CtXgFt6PXtqfJV0Gtxmk7IfhcV6Pu9n7DxqFCtFOXH6fD9sfpl6fDHUBLHofD9sfKx6PcxndXNFcZwarxlEkXxnZcIoBKxmkDesfpHpg0tsZCHXVbnvV724Tp23dcw0d7laV72fhcV627HyBCtfOvesOTI4gDt6xcI4VbnphZwv2xlEkUen7FHsfuHsfK9ngJ9n2DxqOplF2DI6d1dqOGtU8uIngDe6ZFIEVbnyBpxnfxlEkJen7DIsfK9ngJ9n2DxqOpl6Pu9n7DxqFCtXVbnpkktU2henghVFhcV6xDtnfvIngvIfOGt6BGesPhtyVudqFuIpr3HqFWI4g0xo2hts7Kt6PQI4VbnpVXo4TXIsPQIo2FtU2FosFuIqF0eoBCHXgV9nBFVP2LtyBvl6fuenkcIn8XNFQhHUfFo4TXx6FFxs7CIqfcl6O6IU2FxPOgV0Gtl35TwPhcV627HyBCtfOvesOTI4gcIngUxq1XNFc7wPhcV6xDtnfvIngvIfOGt6BGesPhtyVu4qFJI4r39qOhHpg0xo2hts7Kt6PQI4VbnpVXo4TXxsOptqBKtnPp9sfplU2LtyxKtnFvH7OpInPvtsRXNFQhHUfFo4TXxqDGH6BKHqfpHsOulU2Gt6xcIfOJ9o2heng0I4VbnvwTo4TXengGtnPh9nOuoskpInPWIoVuenBAxo2hosZFenRXNFcZwarxlEks9nfytnOJInTutsI6Hsfhoy1XNFcZwarxlEkytykcIPOQeokWIoVuIngDe6ZFIEVbnyBpxnfxlEkhH6Pv9mBDtqcuIngDe6ZFIEVbnsIDtm2Fo4TXxsOptqBKtnPp9sfplU2Gz6dXNFc7o4TXengGtnPh9nOuoskpInPWIoVutsgUH6O7t6BKtqfUHpVbnpkM9oBhIoVXo4TXxsPhIokQeokWl6fuenkcIn8XNFcXBqf6eofcxEkxlEkDt6FQeoBGtsgKeUkFenQFHXgCt6xptyfuIPOA9oBhIokKtnPRoyIDtmfFV0Gt23rxlEkUen7FHsfuHsfK9ngJ9n2DxqOplJ7GtXR1BqPQenxFl627HyBCtfOuen7FV0GtVXkxlEksInZCesFhzfOyeoku9ngUl62CtqOpV0Gtw35Ro4TXIsPQIo2FtU2FosFuIqF0eoBCHXgEtsBgV5PGt4g0xo2hts7Kt6PQI4VbnpVXo4TXIsPQIo2FtU2FosFuIqF0eoBCHXgV9o818sDDt62Fl62CtqOpoyrGesQFHXVbnvicw0d7laV724Tp23fxlEkUen7FHsfuHsfK9ngJ9n2DxqOplF2DI6d1dqOGtU8uesOctykKHqF09sfpV0GtwETp23dcw0d7laV72f7OlEkQ9o20V0GYV6k7znkCxEgvIn2Ct6BDHUJXNFcX3sI6VFhcV6k7znkCxEgCxqDFHXVbnyQOo4TXeUfge6Ohl6xpIngDIqfvV0Gtzy7xlEkXxoFXty8uIngDe6ZFIEVbnsIDtm2Fo4TXeUfge6OhlUrp9n7DHUJXNFcX3sI6VFhcV62CtU2CtqfKI6Fcxqfpl6fuenkcIn8XNFQ6enZvIf7OlEkDtUBGenFQV0GYVJG7torGt6HbIqf6Ingv9oIFoyFDx7OQtsBGI6FFHXVbnpkjI6eXo4TX4UfQHqFuIvGJInIFtU2Gx6fKznPyoykDt6BCtnFbIfOCI6IvIo8XNFQ6enZvIfhcVJ2ptyf09aGJInIFtU2Gx6fKe6OJzfOgeoxKtsI6HsfhV0GtwPhcVF2hengJ9ngUN6BFI6fuHsFsIfOJInZDzfSZV0GtNPhcVJ7Cx6FuIvGJInIFtU2Gx6fKen2h9oIDxqFCtXVbnpkdxsFc9nxLxEkxlEk5tykQenghN6BFI6fuHsFsIfOT9oB09POCI6IvIoBKwXVbnvrxlEk3xqPuIqFuIvGJInIFtU2Gx6fKznPyosZFIU8XNFcTo4TXdsZCxproenZWNUFDx7Op9nxLxEVbnvrxlEkMxn7T9ngUMvGJInIFtU2Gx6fKtnOJ9nIGIokKIqfceoFKwXVbnpkM9oBhIoVXo4TX8ykCxn2LN6BFI6fuHsFsIfOgeoHXNFcXdyBDxqF0VFhcVJ2ptyf09aGJInIFtU2Gx6fKznPyosO6IU2FxPSpV0Gtw0DxlEk5InIDxnZhN6BFI6fuHsFsIfOT9oB09POCI6IvIoBKwXVbnvrxlEk5tykQenghN6fuenkcIn8XNFQ6enZvIfhcVJIpInfvxqPuIqFuIvGJInIFtU2Gx6fKe6OJzfOgeoxKtsI6HsfhV0GtwPhcVF2ctyH1fsPc9vGgeoxKtsI6HsfhV0GtwPhcVJ7DtUfDtErr83GgeoxK96FhxqfpV0GtVJ2FtUBFHXkxlEkMxn7T9ngUMvGJInIFtU2Gx6fKHsfuHsFh9oIGxmJXNFcZwarxlEk2eng7enT18d5bIqf6Ingv9oIFoyrGxq2LosO6IU2FxPSZV0Gtw32xlEkwInxGxErr83GJInIFtU2Gx6fKIqfceoFKwXVbnvPxlEk3xqPuIqFuIvGJInZDzfOXtsBgovVXNFc7o4TXBqf6eofcxaGJInIFtU2Gx6fKznPyoy2TInfJV0Gtw0rxlEk2tyIGt6HbznPyosO6IU2FxEVbnvBxlEk3tqOyVPxDtqcbIqf6Ingv9oIFoyFDx7OCI6IvIoBKwXVbnv8po4TX3nOs9ngUN6BFI6fuHsFsIfOgeoHXNFcXdyBDxqF0VFhcVJG7torGt6HbIqf6Ingv9oIFoyFDxpVbnpk3HqFuVFhcVF2ctyH1fsPc9vGJInIFtU2Gx6fKHqFhesDKtsI6HsfhovVXNFchwFhcVF2ctyH1fsPc9vGA9oBhIokKtsI6HsfhV0GtwPhcVJ2ptyf09aGJInIFtU2Gx6fKznPyoykDt6BCtnFbIfOCI6IvIo8XNFQ6enZvIfhcVJBFI6P7tm8bznPyosO6IU2FxEVbnvrxlEkwInxGxErr83GJInIFtU2Gx6fKtnOJ9nIGIokKtsI6HsfhV0Gtw31To4TX3nPuxnPcV5PrN6BFI6fuHsFsIfOgeoHXNFcXdyBDxqF0VFhcVJG7torGt6HbIqf6Ingv9oIFoyFDx7OCI6IvIoBKw4VbnphpwFhcVJ7DtUfDtErr83GJInIFtU2Gx6fKHqFhesDKxqFQI4VbnvPxlEk3xqPuIqFuIvGJInIFtU2Gx6fKznPyosO6IU2FxPSZV0Gtl3DxlEk3xqPuIqFuIvGJInIFtU2Gx6fKznPyoy2TInfJV0Gtw0rxlEkMxn7T9ngUMvGJInIFtU2Gx6fKHqFhesDKHyrFIn8XNFcpwPhcVF2hengJ9ngUNUFDxpVbnpVZNaiXo4TX4UfQHqFuIvGJInIFtU2Gx6fKHqFhes1XNFcXd6PuIqOQVFhcV6PuxqFD9nhuHsfhxqFuIywuHsP6IfOLInPJl6fuenkcIn8XNFQhHUfFo4TX4UfQHqFuIpcbIqf6Ingv9oIFoyrGxq2LV0GtVF2yeoJXo4TX3qfU9o818d5bIqf6Ingv9oIFosICH62FoskpInPWosZ0V0GtI6PcHsfxlEkMxn7T9ngUMvGJInIFtU2Gx6fKznPyosO6IU2FxPSZV0Gtl3dho4TXBUkFIo2hengJ9ngUN6BFI6fuHsFsIfOQtsBGI6FFHFOCI6IvIo8XNFcTo4TX4UfQHqFuIpcbIqf6Ingv9oIFoyrGxq2LosO6IU2FxPSpV0Gt2akxlEk2tyIGt6HbIUkFIo2hengJ9ngUoskCImFKznPyV0GtI6PcHsfxlEkwInxGxErr83GA9oBhIokKtsI6HsfhV0Gt2vxxlEk3tqOyVPxDtqcbIqf6Ingv9oIFoyrGxq2LV0GtVF2yeoJXo4TX3nOs9ngUN6BFI6fuHsFsIfOgeoxKHyrFIn8XNFcpwPhcVJZFIsFhV5PrN6fuenkcIn8XNFQhHUfFo4TX3nOsI47aH6O7es1bIqf6Ingv9oIFoyFDxpVbnpk3HqFuVFhcVF2hengJ9ngUN6BFI6fuHsFsIfOgeoxKtnOJ9nIGIoVXNFcX8sfuxqfpVFhcVJ2ptyf09aGgeoxKeo2gt62FIEVbnsIDtm2Fo4TX4UfQHqFuIpcbIqf6Ingv9oIFoyFDx7OcInIhV0Gtl3Vho4TX3nOs9ngUN6BFI6fuHsFsIfOgeoxKtqf6xEVbnvrxlEkqH6fFHyBDt6BGt6HbIqf6Ingv9oIFoyFDx7OCI6IvIoBKw4VbnphRNfhcVF2hengJ9ngUN6BFI6fuHsFsIfOXtsBgoyFDx7OCI6IvIo8XNFcTo4TX8ykCxn2LN6BFI6fuHsFsIfOgeoxKtsI6HsfhV0GtwPhcVJ7Cx6FuIvGJInIFtU2Gx6fKIUkFIo2hengJ9ngUoskCImFKznPyV0GtI6PcHsfxlEk5InIDxnZhN6BFI6fuHsFsIfOQtsBGI6FFHFOJInZDzfSpV0GtVJO6IXkxlEk5InIDxnZhNUrGxq2LV0GtVJBFI6P7tm8Xo4TXBUkFIo2hengJ9ngUN6fuenkcIn8XNFQhHUfFo4TX3qfU9o818d5bznPyosGGxmBFHXVbnpkaInghIoVXo4TX3nOs9ngUN6kCImFKznPyV0GtVJGGxmBFHXkxlEk2eng7enT18d5bIqf6Ingv9oIFoskCImFKznPyosO6IU2FxEVbnvrxlEkMxn7T9ngUN6BFI6fuHsFsIfOgeoxKtsI6HsfhV0GtwveTo4TX3nOs9ngUN6BFI6fuHsFsIfOT9oB09POpengJts7Gz6fKtsI6HsfhV0GtI6PcHsfxlEk2eng7enT18d5bIqf6Ingv9oIFoyrGxq2LV0GtVF2heoBGepkxlEk5InIDxnZhN6BFI6fuHsFsIfOJInZDzfSZV0GtwfhcVJG7torGt6Hbe6OJzfOgeoHXNFcX46FhxqfpVFhcVJG7torGt6HbIqf6Ingv9oIFosBFtqPgovVXNFcZ2PhcVJIpInfvxqPuIqFuIvGT9oB09POCI6IvIo8XNFcTo4TX3qfU9o818d5bznPyosPvzng0In8XNFQhHUfFo4TX4UfQHqFuIvGJInIFtU2Gx6fKtnOJ9nIGIokKtsI6HsfhV0GtwPhcVF2hengJ9ngUN6BFI6fuHsFsIfOT9oB09EVbnpkM9oBhIoVXo4TX3qfU9o818d5bznPyosZFIU8XNFcQ2fhcVJG7torGt6HbIqf6Ingv9oIFoyrGxq2LoykDt6BCtnFbIfOCI6IvIo8XNFQ6enZvIfhcVJBCH67DtU8bIqf6Ingv9oIFoyFDx7OCI6IvIoBKwXVbnvrxlEk3tqOyVPxDtqcbznPyosPvzng0In8XNFQ6enZvIfhcVJ7Cx6FuIvGA9oBhIokKtsI6HsfhV0Gt2vrxlEkMxn7T9ngUN6BFI6fuHsFsIfOXtsBgoyFDx7OCI6IvIo8XNFcTo4TXBqf6eofcxaGJInIFtU2Gx6fKHsfuHsFh9oIGxmJXNFcZwarxlEkMxn7T9ngUMvGJInZDzfOXtsBgovVXNFcZo4TX4UfQHqFuIvGJInIFtU2Gx6fKznPyoy2TInfJV0GtwvBxlEk5InIDxnZhN6BFI6fuHsFsIfO6H6fFHyBDt6BGt6xKe6OJzfOgeoHXNFQ6enZvIfhcVJBFI6P7tm8bznPyV0GtV05RwErwdXkxlEkMxn7T9ngUN6BFI6fuHsFsIfOgeoxKtqf6xEVbnvrxlEkMxn7T9ngUN6BFI6fuHsFsIfOT9oB09POCI6IvIoBKw4VbnphpwFhcVJ2ptyf09aGJInIFtU2Gx6fKHqFhesDKxqFQI4VbnvPxlEk2tyIGt6HbIqf6Ingv9oIFoyrGxq2Loy2TInfJV0Gtw0rxlEk2eng7enT18d5bIqf6Ingv9oIFosP0xqFseoBGtsRXNFcXfmxGtqFU9m8Xo4TX4UfQHqFuIvGXtsBgoyFDx7OCI6IvIo8XNFcR27hcVJ7Cx6FuIvGJInIFtU2Gx6fKe6OJzfOgeoxKtsI6HsfhV0GtwPhcV6IpInfvxqPuIqFuIpgFt6PXtqfJV0Gtxmk7IfhcVJ2ptyf09aGJInZDzfOXtsBgovVXNFcZo4TXdsZCxproenZWN6BFI6fuHsFsIfO6H6fFHyBDt6BGt6xKe6OJzfOgeoHXNFQ6enZvIfhcVF2ctyH1fsPc9vGJInZDzfOXtsBgov5XNFcZo4TX4UfQHqFuIvGgeoxK96FhxqfpV0GtVJ2FtUBFHXkxlEkMxn7T9ngUNUFDx7ODHyFuesfJV0GtI6PcHsfxlEk2tyIFld2ptyf09aGgeoxKH6FU9m8XNFcTo4TXBqOptnPuxaGJInIFtU2Gx6fKznPyoy2TInfJV0Gtw0rxlEk3tqOyVPxDtqcbIqf6Ingv9oIFoyFDx7OCI6IvIoBKw4VbnphRNfhcVF2ctyH1fsPc9vGJInIFtU2Gx6fKen2h9oIDxqFCtXVbnpkdxsFc9nxLxEkxlEk2tyIGt6HbIqf6Ingv9oIFoyFDx7OCI6IvIoBKw4VbnveRo4TX4UfQHqFuIvGgeoHXNFcXw31TV5Z4VFhcVJG7torGt6HWNUFDx7Op9nxLxEVbnv5vo4TX3nOs9ngUN6BFI6fuHsFsIfOFt6PXtqfJV0GtI6PcHsfxlEk2eng7enT18d5bIUkFIo2hengJ9ngUoskCImFKznPyV0GtI6PcHsfxlEkwInxGxErr83GJInIFtU2Gx6fKznPyV0GtVF2heoBGepkxlEk2tyIFld2ptyf09aGJInIFtU2Gx6fKtnOJ9nIGIokKtsI6HsfhV0GtwPhcVJZFIsFhV5PrNUFDxpVbnpVZNaiXo4TXBUkFIo2hengJ9ngUN6BFI6fuHsFsIfOQtsBGI6FFHFOJInZDzfSpV0GtVF2heoBGepkxlEkMxn7T9ngUMvGJInIFtU2Gx6fKIqfceoFKw4VbnvkxlEkMxn7T9ngUN6GGxmBFHFOCI6IvIo8XNFc72FhcVJBCH67DtU8bIqf6Ingv9oIFosBFtqPgov5XNFcZo4TXBUkFIo2hengJ9ngUN6BFI6fuHsFsIfOT9oB09POCI6IvIoBKw4VbnphRNfhcVJ7DtUfDtErr83GJInIFtU2Gx6fKHqFhesDKH6PuIqOQ9oGFosO6IU2FxEVbnsIDtm2Fo4TXdsZCxproenZWNUrGxq2LV0GtVJBFI6P7tm8Xo4TXengh9nPGt4gvIoBh9ngUHpgvenIFosDFen8uHyBDxqfvV0Gtnpklt6F6I4VcVFBDHsfpVXTXBqFvxqPuesdXofhcVF2hengJ9ngUNUFDx7Op9nxLxEVbnv5po4TXBUkFIo2hengJ9ngUN6BFI6fuHsFsIfOJInZDzfSZV0GtwfhcVJBFI6P7tm8be6OJzfOgeoxKtsI6HsfhV0GtwPhcVF2hengJ9ngUN6BFI6fuHsFsIfO6H6fFHyBDt6BGt6xKe6OJzfOgeoHXNFQ6enZvIfhcVJ7Cx6dQ8ykCxn2LN6BFI6fuHsFsIfOgeoxKH6FU9m8XNFcTo4TX4UfQHqFuIvGJInIFtU2Gx6fKHqFhesDKxqFQI4VbnvPxlEkMxn7T9ngUMvGgeoxK96FhxqfpV0GtVJ2FtUBFHXkxlEkMxn7T9ngUMvGT9oB09POCI6IvIo8XNFcTo4TX3nOsI47aH6O7es1bHqFhes1XNFcXBqf6eofcxEkxlEk5InIDxnZhN6BFI6fuHsFsIfODeyBGx6Ph9nOuV0GtVF2FtU2GxqFs9oBgVFhcVJZFIsFhV5PrN6BFI6fuHsFsIfOT9oB09POh9n7FV0GtwfhcVJ2ptyf09aGgeoxK96FhxqfpV0GtVJ2FtUBFHXkxlEkqenQFtqPUNUrGxq2LV0GtVJBFI6P7tm8Xo4TXBUkFIo2hengJ9ngUN6BFI6fuHsFsIfODeyBGx6Ph9nOuV0GtVFBy9nZGIsDhVFhcVJBFI6P7tm8bIqf6Ingv9oIFoyFDx7OCI6IvIoBKwXVbnvrxlEk3tqOyVPxDtqcbIqf6Ingv9oIFoyFDx7OQtsBGI6FFHXVbnpkaInghIoVXo4TX8ykCxn2LN6GGxmBFHFOCI6IvIo8XNFcQ23FxlEk2tyIFld2ptyf09aGJInIFtU2Gx6fKHqFhesDKHyrFIn8XNFcpwPhcVF2ctyH1fsPc9vGJInIFtU2Gx6fKznPyosO6IU2FxEVbnvrxlEkMxn7T9ngUMvGJInIFtU2Gx6fKHqFhesDKxqFQI4VbnvPxlEkMxn7T9ngUMvG6H6fFHyBDt6BGt6xKe6OJzfOgeoHXNFQ6enZvIfhcVF2ctyH1fsPc9vGJInIFtU2Gx6fKznPyosZFIU8XNFcTo4TX3nOsI47aH6O7es1bIqf6Ingv9oIFosBFtqPgovVXNFcZo4TXdyBDt6BGt6HbIqf6Ingv9oIFoyFDx7Op9nxLxEVbnvrxlEk2eng7enT18d5bIqf6Ingv9oIFosfuenkcIn8XNFQ6enZvIfhcVJBCH67DtU8bIqf6Ingv9oIFoyrGxq2LV0GtVJO6IXkxlEk5tykQenghN6BFI6fuHsFsIfOvIngv9oBGx6Fhz4Vbnv5TwPhcVJG7torGt6HbHqFhesDKtsI6HsfhV0GtwPhcVJBFI6P7tm8bznPyoykGIsDhV0Gt2arxlEk2tyIGt6Hbe6OJzfOgeoxKtsI6HsfhV0Gt20FxlEk3tqOyVPxDtqcbIqf6Ingv9oIFos7CIqF69nfposO6IU2FxEVbnv5RwPhcVF2hengJ9ngUN6BFI6fuHsFsIfOT9oB09POpengJts7Gz6fKtsI6HsfhV0Gtxmk7IfhcVJ7DtUfDtErr83GJInIFtU2Gx6fKIUkFIo2hengJ9ngUoskCImFKznPyV0GtI6PcHsfxlEkaH6O7es1bIqf6Ingv9oIFoyFDx7OvHqfFIEVbnvVTo4TXBUkFIo2hengJ9ngUN6IpInfvxqPuIqFuI7OXtsBgoyFDxpVbnsIDtm2Fo4TX3nPuxnPcV5PrN6BFI6fuHsFsIfOJInZDzfSZV0GtwfhcV67DtUfDtPOgeoHuIngDe6ZFIEVbnyBpxnfxlEk2eng7enT18d5be6OJzfOgeoxKtsI6HsfhV0GtwPhcVJ7Cx6FuIvGJInIFtU2Gx6fKtnOJ9nIGIokKIqfceoFKwXVbnpkM9oBhIoVXo4TXdsZCxproenZWN6BFI6fuHsFsIfOFt6PXtqfJV0GtI6PcHsfxlEkMxn7T9ngUMvGJInIFtU2Gx6fKIngDe6ZFIEVbnsIDtm2Fo4TXBqOptnPuxaGJInIFtU2Gx6fKI6OpesfKeUkFenQKtqwXNFQ6enZvIfhcVF2ctyH1fsPc9vGJInZDzfOXtsBgovVXNFcZo4TXdyBDt6BGt6HbIqf6Ingv9oIFoyFDx7OpengJts7Gz6fKtsI6HsfhV0GtI6PcHsfxlEk3xqPuIqFuIvGJInIFtU2Gx6fKznPyosO6IU2FxEVbnvrxlEk2eng7enT18d5bznPyosO6IU2FxEVbnvrxlEkMxn7T9ngUMvGJInIFtU2Gx6fKHqFhesDKtsI6Hsfhov5XNFcQ23BxlEk3tqOyVPxDtqcbIqf6Ingv9oIFoskCImFKznPyosO6IU2FxEVbnv5RwPhcVJ7DtUfDtErr83GJInIFtU2Gx6fKznPyoy2TInfJV0Gtw0rxlEk5InIDxnZhN6BFI6fuHsFsIfO6tyk0IfOXH6fD97OcepVbnsIDtm2Fo4TX3nOs9ngUN6BFI6fuHsFsIfOgeoxKH6PuIqOQ9oGFosO6IU2FxEVbnsIDtm2Fo4TX8ykCxn2LN6BFI6fuHsFsIfOT9oB09EVbnpk3xsPgVFhcVJ2ptyf09aGJInIFtU2Gx6fKIngDe6ZFIEVbnsIDtm2Fo4TX4UfQHqFuIpcbHqFhes1XNFcXBqf6eofcxEkxlEk3xqPuIqFuIvG6H6fFHyBDt6BGt6xKe6OJzfOgeoHXNFQ6enZvIfhcVF2ctyH1fsPc9vGJInIFtU2Gx6fKIqfceoFKw4VbnvxxlEk5tykQenghN6GGxmBFHFOCI6IvIo8XNFcTo4TX3nOs9ngUN6BFI6fuHsFsIfOgeoxKtsI6HsfhV0GtwveTo4TXBqOptnPuxaGgeoxKtsI6HsfhV0GtwPhcVJ7DtUfDtErr83GJInIFtU2Gx6fKznPyosO6IU2FxPSpV0Gt20BxlEk2tyIFld2ptyf09aGJInIFtU2Gx6fKen2h9oIDxqFCtXVbnpkdxsFc9nxLxEkxlEk3xqPuIqFuIvGJInIFtU2Gx6fKHqFhesDKxqFQI4VbnvPxlEkaH6O7es1bIUkFIo2hengJ9ngUoskCImFKznPyV0GtI6PcHsfxlEk5InIDxnZhN6BFI6fuHsFsIfOQtsBGI6FFHFOCI6IvIo8XNFcTo4TX8ykCxn2LNUFDx7Op9nxLxEVbnvrxlEk5tykQenghN6BFI6fuHsFsIfOgeoxKtnOJ9nIGIoVXNFcX3sI6VFhcVJ7Cx6FuIvGJInIFtU2Gx6fKHqFhesDKtsI6HsfhovVXNFcRNfhcVJID9sfcenHbznPyoykGIsDhV0GtwPhcVF2hengJ9ngUN6kCImFKznPyV0GtVJGGxmBFHXkxlEk5InIDxnZhN6BFI6fuHsFsIfOgeoxKH6FU9m8XNFcTo4TX8ykCxn2LN6BFI6fuHsFsIfOJInZDzfSZV0GtwfhcVF2ctyH1fsPc9vGXtsBgoyFDxpVbnpkjI6eXo4TX3nPuxnPcV5PrNUFDx7Op9nxLxEVbnvrxlEk2eng7enT18d5bIqf6Ingv9oIFosBFtqPgovVXNFcZo4TX3nOsI47aH6O7es1bIqf6Ingv9oIFoyFDx7OCI6IvIoBKw4VbnphRNfhcVJG7torGt6HWNUFDx7ODHyFuesfJV0GtI6PcHsfxlEk5tykQenghN6BFI6fuHsFsIfOQtsBGI6FFHFOJInZDzfSpV0GtVJO6IXkxlEkaH6O7es1bznPyV0GtV05RwEkxlEkqenQFtqPUN6kCImFKznPyV0GtVJO6IXkxlEkwInxGxErr83GJInIFtU2Gx6fKIngDe6ZFIEVbnsIDtm2Fo4TX3nPuxnPcV5PrN6BFI6fuHsFsIfOQtsBGI6FFHFOJInZDzfSpV0GtVF2heoBGepkxlEk2tyIGt6HbznPyV0GtV05RwEkxlEkMxn7T9ngUMvGgeoxKtqf6xEVbnvBxlEk2tyIGt6HbIqf6Ingv9oIFosBFtqPgov5XNFcso4TXdyBDt6BGt6HbIqf6Ingv9oIFos7CIqF69nfposBFtqPgovVXNFcX46FhxqfpVFhcVF2hengJ9ngUNUrGxq2LosO6IU2FxEVbnv1go4TX4UfQHqFuIvGJInZDzfOXtsBgovVXNFcZo4TX4UfQHqFuIpcbIngDe6ZFIEVbnyBpxnfxlEkaH6O7es1bIqf6Ingv9oIFoyFDx7Op9nxLxEVbnv1po4TX8ykCxn2LN6BFI6fuHsFsIfODeyBGx6Ph9nOuV0GtVFBy9nZGIsDhVFhcVJBCH67DtU8bIqfceoFKe6OJzfSpV0GtwfhcVJG7torGt6HWN6BFI6fuHsFsIfOgeoxKtsI6HsfhV0GtwPhcVJ7Cx6FuIvGJInZDzfOXtsBgov5XNFcpo4TXBqf6eofcxaGgeoxKeo2gt62FIEVbnyBpxnfxlEk3xqPuIqFuIvGgeoxKtqf6xEVbnphpwFhcVJG7torGt6HbznPyoykGIsDhV0Gt2fhcVJBFI6P7tm8bIqf6Ingv9oIFosfuenkcIn8XNFQ6enZvIfhcVJZFIsFhV5PrN6BFI6fuHsFsIfOT9oB09EVbnpk3xsPgVFhcVF2ctyH1fsPc9vGJInIFtU2Gx6fKHqFhesDKxqFQI4VbnvPxlEk2tyIGt6HbIqf6Ingv9oIFoyFDx7OCI6IvIoBKwXVbnv1go4TXBqOptnPuxaGJInIFtU2Gx6fKznPyosO6IU2FxPSZV0GtwPhcVJ7DtUfDtErr83GT9oB09EVbnpk5InIDxnZhVFhcVJBCH67DtU8bIqf6Ingv9oIFosfuenkcIn8XNFQ6enZvIfhcVJG7torGt6HbIngDe6ZFIEVbnyBpxnfxlEkqH6fFHyBDt6BGt6HbIqf6Ingv9oIFoy2FtU2GxqFs9oBgV0Gtw3iTo4TX3nOs9ngUN6BFI6fuHsFsIfOgeoxKtnOJ9nIGIoVXNFcX8sfuxqfpVFhcVJID9sfcenHbznPyosO6IU2FxEVbnvrxlEk5tykQenghNUFDx7OcInIhV0GtwPhcVF2ctyH1fsPc9vGJInIFtU2Gx6fKHqFhesDKtsI6Hsfhov5XNFcQNaFxlEkMxn7T9ngUN6BFI6fuHsFsIfOgeoxKH6FU9m8XNFcTo4TX4UfQHqFuIpcbe6OJzfOgeoHXNFcX46FhxqfpVFhcVF2hengJ9ngUN6BFI6fuHsFsIfOT9oB09POCI6IvIoBKwXVbnphgo4TX3nOsI47aH6O7es1bznPyosPvzng0In8XNFQ6enZvIfhcVJ7Cx6FuIvGJInIFtU2Gx6fKHsfuHsFh9oIGxmJXNFcZo4TX3qfU9o818d5bIqfceoFKe6OJzfSZV0GtwfhcVJ7Cx6FuIvGgeoxKH6FU9m8XNFcTo4TXBqOptnPuxaGgeoHXNFcXw31TVFhcVJBFI6P7tm8bIqf6Ingv9oIFoyrGxq2LV0GtVJO6IXkxlEk2tyIGt6HbIqf6Ingv9oIFosICH62FoskpInPWosZ0V0GtI6PcHsfxlEk5InIDxnZhN6BFI6fuHsFsIfOgeoHXNFcX3sI6VFhcVJ7DtUfDtErr83GJInIFtU2Gx6fKznPyoykGIsDhV0GtwPhcVJBFI6P7tm8b96FhxqfposO6IU2FxEVbnph72PhcVJBFI6P7tm8bIqf6Ingv9oIFoyFDx7OCI6IvIoBKw4VbnvrxlEk5InIDxnZhN6BFI6fuHsFsIfOgeoxKtqf6xEVbnvrxlEk3tqOyVPxDtqcbIqf6Ingv9oIFoyFDxpVbnpk3xqPh9nwXo4TX3nOsI47aH6O7es1bIqfceoFKe6OJzfSZV0GtwfhcVJ2ptyf09aGgeoxKtsI6HsfhV0GtwPhcVJBCH67DtU8bIqf6Ingv9oIFoskCImFKznPyosO6IU2FxEVbnvrxlEk3xqPuIqFuIvGgeoxKeo2gt62FIEVbnsIDtm2Fo4TX4UfQHqFuIpcbIqf6Ingv9oIFoyFDx7OvHqfFIEVbnvVTo4TXBqf6eofcxaGJInIFtU2Gx6fKHqFhesDKtsI6Hsfhov5XNFcTo4TX3nOsI47aH6O7es1bznPyosZFIU8XNFcTo4TXdsZCxproenZWNUFDx7OA9oBhIoVXNFcX3sI6VFhcVJZFIsFhV5PrN6BFI6fuHsFsIfOJInZDzfSZV0GtwfhcVF2hengJ9ngUN6BFI6fuHsFsIfOFt6PXtqfJV0GtI6PcHsfxlEk5tykQenghN6BFI6fuHsFsIfOT9oB09POvHqfFIEVbnvVTo4TXdyBDt6BGt6HbIqf6Ingv9oIFos7CIqF69nfposO6IU2FxEVbnv5RwPhcVJ7Cx6FuIvGJInIFtU2Gx6fKtnOJ9nIGIokKtsI6HsfhV0Gtw31To4TX3qfU9o818d5bIqf6Ingv9oIFoyFDx7OCI6IvIo8XNFcv20rxlEk2tyIFld2ptyf09aGJInIFtU2Gx6fKIngDe6ZFIEVbnsIDtm2Fo4TX3nOs9ngUN6fuenkcIn8XNFQhHUfFo4TXB6PWInZDIvGFt6PXtqfJV0GtI6PcHsfxlEk5tykQenghN6IpInfvxqPuIqFuI7OXtsBgoyFDxpVbnsIDtm2Fo4TX3qfU9o818d5bIqf6Ingv9oIFoskCImFKznPyosO6IU2FxEVbnvrxlEkwInxGxErr83GJInIFtU2Gx6fKznPyoykDt6BCtnFbIfOCI6IvIo8XNFQ6enZvIfhcVF2ctyH1fsPc9vGgeoxKtqf6xEVbnvrxlEkaH6O7es1bIqf6Ingv9oIFoy2FtU2GxqFs9oBgV0Gt2aPxlEk5InIDxnZhN6kCImFKznPyV0GtVJGGxmBFHXkxlEkaH6O7es1bIqf6Ingv9oIFoyrGxq2LosO6IU2FxPSZV0Gtl31go4TX4UfQHqFuIpcbIqf6Ingv9oIFoyFDx7OCI6IvIoBKwXVbnv8po4TXdsZCxproenZWN6BFI6fuHsFsIfOvIngv9oBGx6Fhz4Vbnv5TwPhcVF2hengJ9ngUN6BFI6fuHsFsIfOJInZDzfSpV0GtNPhcVJZFIsFhV5PrN6BFI6fuHsFsIfOgeoxKH6FU9m8XNFcTo4TXtnPuxnPcoyFDxpgXtsBgosIpInfvxqPuIqFuIpVbnyBpxnfxlEk3tqOyVPxDtqcbe6OJzfOgeoxKtsI6HsfhV0GtwPhcVJ2ptyf09aGJInIFtU2Gx6fKHqFhesDKtsI6HsfhovVXNFcpNPhcVJBCH67DtU8bIqf6Ingv9oIFoyrGxq2LoykDt6BCtnFbIfOCI6IvIo8XNFQ6enZvIfhcVJZFIsFhV5PrN6BFI6fuHsFsIfOT9oB09POpengJts7Gz6fKtsI6HsfhV0GtI6PcHsfxlEkaH6O7es1bIqfceoFKe6OJzfSZV0GtwfhcVJID9sfcenHbznPyosGGxmBFHXVbnpkjI6eXo4TX3qfU9o818d5bIqf6Ingv9oIFoyrGxq2LosO6IU2FxPSZV0Gt2aBxlEk2tyIFld2ptyf09aGJInIFtU2Gx6fKHsfuHsFh9oIGxmJXNFcZwarxlEk2eng7enT18d5bIqf6Ingv9oIFoyFDx7OpengJts7Gz6fKtsI6HsfhV0GtI6PcHsfxlEk5tykQenghN6BFI6fuHsFsIfO6H6fFHyBDt6BGt6xKe6OJzfOgeoHXNFQ6enZvIfhcVF2hengJ9ngUN6kCImFKznPyosO6IU2FxEVbnvPxlEkaH6O7es1bIqf6Ingv9oIFoyFDx7OQtsBGI6FFHXVbnpkaInghIoVXo4TX3nOs9ngUN6BFI6fuHsFsIfOgeoxKH6FU9m8XNFcTo4TXBqf6eofcxaGJInIFtU2Gx6fKe6OJzfOgeoxKtsI6HsfhV0GtwPhcVJBCH67DtU8bIqfceoFKe6OJzfSZV0GtwfhcVJID9sfcenHbznPyosZFIU8XNFcTo4TXBqOptnPuxaGJInIFtU2Gx6fKHqFhesDKtsI6Hsfhov5XNFcTo4TX4UfQHqFuIpcbIqf6Ingv9oIFoskCImFKznPyosO6IU2FxEVbnvrxlEkqH6fFHyBDt6BGt6HbIqf6Ingv9oIFoyrGxq2LoyBGtndXNFcZo4TX3nPuxnPcV5PrN6BFI6fuHsFsIfOT9oB09POvHqfFIEVbnvVTo4TXBqOptnPuxaGXtsBgoyFDx7OCI6IvIo8XNFcTo4TX3nOsI47aH6O7es1bIqf6Ingv9oIFoyFDx7OpengJts7Gz6fKtsI6HsfhV0GtI6PcHsfxlEk3xqPuIqFuIvGgeoxK96FhxqfpV0GtVJ2FtUBFHXkxlEk5InIDxnZhN6BFI6fuHsFsIfOgeoxKH6PuIqOQ9oGFosO6IU2FxEVbnsIDtm2Fo4TX4UfQHqFuIvGJInIFtU2Gx6fKIUkFIo2hengJ9ngUoskCImFKznPyV0GtI6PcHsfxlEkaH6O7es1bIqf6Ingv9oIFosIpInfvxqPuIqFuI7OXtsBgoyFDxpVbnsIDtm2Fo4TX3qfU9o818d5bIUkFIo2hengJ9ngUoskCImFKznPyV0GtI6PcHsfxlEkqenQFtqPUN6kCImFKznPyosO6IU2FxEVbnvrxlEkqH6fFHyBDt6BGt6HbHqFhes1XNFcXBqf6eofcxEkxlEk5InIDxnZhNUFDx7OcInIhV0Gtl3wvo4TX3qfU9o818d5bIqf6Ingv9oIFoyFDx7OQtsBGI6FFHXVbnpkaInghIoVXo4TX4UfQHqFuIpcbznPyV0GtV05RwErwdXkxlEk3xqPuIqFuIvGFt6PXtqfJV0Gtxmk7IfhcVJBFI6P7tm8bznPyosGGxmBFHXVbnpkaInghIoVXo4TX3nOsI47aH6O7es1bIngDe6ZFIEVbnyBpxnfxlEk2tyIFld2ptyf09aGT9oB09POCI6IvIo8XNFcTo4TX4UfQHqFuIpcbznPyosO6IU2FxEVbnvrxlEk2eng7enT18d5bIqf6Ingv9oIFosICH62FoskpInPWosZ0V0Gtxmk7IfhcVJZFIsFhV5PrN6BFI6fuHsFsIfOT9oB09POCI6IvIoBKwXVbnv1go4TX4UfQHqFuIpcbIqfceoFKe6OJzfSZV0GtwfhcVJ2ptyf09aGXtsBgoyFDxpVbnpkM9oBhIoVXo4TXdsZCxproenZWNUrGxq2LosO6IU2FxEVbnvrxlEkaH6O7es1bIqf6Ingv9oIFos7CIqF69nfposBFtqPgovVXNFcX46FhxqfpVFhcVJBCH67DtU8bHqFhesDKtsI6HsfhV0GtwPhcVJBCH67DtU8bznPyoykGIsDhV0GtwPhcVJ2ptyf09aGT9oB09EVbnpk5InIDxnZhVFhcVF2hengJ9ngUN6BFtqPgoskCImFKw4VbnvBxlEkMxn7T9ngUMvGJInIFtU2Gx6fKHqFhesDKH6PuIqOQ9oGFosO6IU2FxEVbnyBpxnfxlEk2tyIGt6HbznPyosZFIU8XNFcTo4TXIqf6Ingv9oIFosIc9n2Wl6fuenkcIn8XNFQ6enZvIfhcVJG7torGt6HWN6BFI6fuHsFsIfOgeoxKtnOJ9nIGIoVXNFcX8sfuxqfpVFhcVJG7torGt6HbIqf6Ingv9oIFoyFDx7OCI6IvIoBKwXVbnvVvo4TX4UfQHqFuIpcbe6OJzfOgeoxKtsI6HsfhV0GtwPhcVJBCH67DtU8bIqf6Ingv9oIFoyFDx7Op9nxLxEVbnvrxlEk2eng7enT18d5bIqfceoFKe6OJzfSpV0GtwfhcVF2ctyH1fsPc9vGJInIFtU2Gx6fKznPyoykDt6BCtnFbIfOCI6IvIo8XNFQ6enZvIfhcVJZFIsFhV5PrNUFDx7OCI6IvIo8XNFcQwFhcVJ7Cx6FuIvGJInIFtU2Gx6fKHqFhes1XNFcX46FhxqfpVFhcVJ7Cx6FuIvGT9oB09EVbnpk5InIDxnZhVFhcVJZFIsFhV5PrN6BFI6fuHsFsIfOgeoxKHyrFIn8XNFcpwPhcVJG7torGt6HbHqFhes1XNFcXBqf6eofcxEkxlEk2tyIFld2ptyf09aGXtsBgoyFDx7OCI6IvIo8XNFcywPhcV6PstsFJoskDesQvxqPXl6fuenkcIn8XNFQhHUfFo4TX8ykCxn2LN6kCImFKznPyosO6IU2FxEVbnphh2fhcVJ7Cx6dQ8ykCxn2LN6IpInfvxqPuIqFuI7OXtsBgoyFDxpVbnsIDtm2Fo4TXBUkFIo2hengJ9ngUN6BFI6fuHsFsIfOJInZDzfSpV0GtwfhcVJBFI6P7tm8bIqf6Ingv9oIFoyrGxq2LoykDt6BCtnFbIfOCI6IvIo8XNFQ6enZvIfhcVJ7Cx6dQ8ykCxn2LN6BFI6fuHsFsIfOXtsBgoyFDx7OCI6IvIo8XNFcTo4TX3nOsI47aH6O7es1bIqf6Ingv9oIFoyFDx7OQtsBGI6FFHXVbnpkjI6eXo4TXBUkFIo2hengJ9ngUN6BFI6fuHsFsIfOgeoHXNFcXdyBDxqF0VFhcVF2ctyH1fsPc9vG6H6fFHyBDt6BGt6xKe6OJzfOgeoHXNFQ6enZvIfhcVJBCH67DtU8bIqf6Ingv9oIFoyFDx7OpengJts7Gz6fKtsI6HsfhV0GtI6PcHsfxlEk3xqPuIqFuIvGgeoxKtsI6HsfhV0GtwPhcVJ7Cx6dQ8ykCxn2LN6BFtqPgoskCImFKwXVbnvPxlEkqH6fFHyBDt6BGt6HbIqf6Ingv9oIFosfuenkcIn8XNFQ6enZvIfhcVJ7Cx6dQ8ykCxn2LN6BFI6fuHsFsIfO6tyk0IfOXH6fD97OcepVbnsIDtm2Fo4TXBUkFIo2hengJ9ngUN6BFI6fuHsFsIfOgeoxKHyrFIn8XNFcpwPhcVJ2ptyf09aGJInIFtU2Gx6fKHqFhesDKHyrFIn8XNFcpwPhcVJIpInfvxqPuIqFuIvGJInIFtU2Gx6fKznPyosZFIU8XNFcTo4TX3nOsI47aH6O7es1bIqf6Ingv9oIFoyFDx7OcInIhV0GtwPhcVJ7DtUfDtErr83GJInIFtU2Gx6fKHsfuHsFh9oIGxmJXNFcZwarxlEkMxn7T9ngUNUFDx7OcInIhV0GtwPhcVJG7torGt6HbIUkFIo2hengJ9ngUoskCImFKznPyV0GtI6PcHsfxlEkMxn7T9ngUMvGJInIFtU2Gx6fKen2h9oIDxqFCtXVbnpkdxsFc9nxLxEkxlEk3tqOyVPxDtqcbIqf6Ingv9oIFosBFtqPgovVXNFcRo4TXdyBDt6BGt6Hb96FhxqfposO6IU2FxEVbnve7o4TX3nOsI47aH6O7es1bIqf6Ingv9oIFoyrGxq2LoyBGtndXNFcZo4TXBUkFIo2hengJ9ngUN6BFI6fuHsFsIfOgeoxKtnOJ9nIGIoVXNFcX3sI6VFhcVJ7DtUfDtErr83GJInIFtU2Gx6fKHqFhesDKtsI6HsfhovVXNFcs2PhcVJG7torGt6HbIqf6Ingv9oIFoyrGxq2LosO6IU2FxPSpV0Gtw02xlEk2tyIFld2ptyf09aGXtsBgoyFDxpVbnpkM9oBhIoVXo4TX4UfQHqFuIvGJInIFtU2Gx6fKen2h9oIDxqFCtXVbnpkdxsFc9nxLxEkxlEk5tykQenghN6BFI6fuHsFsIfOgeoHXNFcX3sI6VFhcVJ7Cx6dQ8ykCxn2LN6BFI6fuHsFsIfOT9oB09POCI6IvIoBKwXVbnvrxlEk2tyIFld2ptyf09aGgeoHXNFcXw31TVFhcV6BGHsPXtqfpHpgFt6PXtqfJV0GtI6PcHsfxlEk2eng7enT18d5bznPyosZFIU8XNFcTo4TXBqf6eofcxaGJInIFtU2Gx6fKznPyos7CIqF69nfpV0GtVJO6IXkxlEk2tyIFld2ptyf09aGJInIFtU2Gx6fKznPyoy2TInfJV0Gtw32xlEkMxn7T9ngUMvGA9oBhIokKtsI6HsfhV0Gt23PxlEkMxn7T9ngUN6BFI6fuHsFsIfOT9oB09POvHqfFIEVbnvVTo4TX4UfQHqFuIpcbIqf6Ingv9oIFosBFtqPgovVXNFcpo4TX4UfQHqFuIpcbIqf6Ingv9oIFoyFDxpVbnpk3xqPh9nw13PVXo4TXBqf6eofcxaGJInZDzfOXtsBgov5XNFcZo4TX3nOsI47aH6O7es1bIqf6Ingv9oIFosIpInfvxqPuIqFuI7OXtsBgoyFDxpVbnsIDtm2Fo4TX3nOsI47aH6O7es1bIqf6Ingv9oIFoyrGxq2LosO6IU2FxPSZV0Gtl31go4TXdsZCxproenZWN6BFI6fuHsFsIfOgeoxKHyrFIn8XNFcpwPhcVF2ctyH1fsPc9vGJInIFtU2Gx6fKtnOJ9nIGIokKIqfceoFKwXVbnpkM9oBhIoVXo4TXBUkFIo2hengJ9ngUN6BFI6fuHsFsIfOT9oB09POCI6IvIoBKwXVbnv1go4TXtnPuxnPcoyFDxpgJ9o2De6ZFoyFDx7OQtsBGI6FFHUwXNFQhHUfFo4TX3qfU9o818d5bznPyoykGIsDhV0Gt20IxlEk3xqPuIqFuIvGJInIFtU2Gx6fKznPyV0GtVF2heoBGepkxlEkwInxGxErr83GJInIFtU2Gx6fKHsfuHsFh9oIGxmJXNFcv2PhcVJZFIsFhV5PrN6kCImFKznPyV0GtVJGGxmBFHXkxlEkwInxGxErr83GXtsBgoyFDx7OCI6IvIo8XNFcTo4TXBqOptnPuxaGJInIFtU2Gx6fKIqfceoFKwXVbnvPxlEk5InIDxnZhN6BFtqPgoskCImFKwXVbnvPxlEkqH6fFHyBDt6BGt6HbIqf6Ingv9oIFoyrGxq2LV0GtVF2yeoJXo4TXdsZCxproenZWNUFDxpVbnpVZNaiXo4TX3qfU9o818d5bIqfceoFKe6OJzfSpV0GtwfhcVJ7Cx6dQ8ykCxn2LNUFDx7OA9oBhIoVXNFcX8sfuxqfpVFhcVJBFI6P7tm8bIqf6Ingv9oIFosBFtqPgovVXNFcZo4TX3nOs9ngUNUrGxq2LosO6IU2FxEVbnvrxlEkaH6O7es1bIqf6Ingv9oIFosBFtqPgovVXNFcZo4TX4UfQHqFuIvGJInIFtU2Gx6fKHsfuHsFh9oIGxmJXNFcZwarxlEkwInxGxErr83GJInIFtU2Gx6fKen2h9oIDxqFCtXVbnpk3Ingv9oBGx6Fhz4kxlEk3tqOyVPxDtqcbIqf6Ingv9oIFoyrGxq2LoykDt6BCtnFbIfOCI6IvIo8XNFQ6enZvIfhcVF2hengJ9ngUN6BFI6fuHsFsIfODeyBGx6Ph9nOuV0GtVF2FtU2GxqFs9oBgVFhcVJBCH67DtU8bIqf6Ingv9oIFoyFDx7OCI6IvIo8XNFcTo4TXdsZCxproenZWN6fuenkcIn8XNFQhHUfFo4TX3qfU9o818d5bIqf6Ingv9oIFoyFDx7OcInIhV0GtwPhcVJ2ptyf09aGJInIFtU2Gx6fKI6OpesfKeUkFenQKtqwXNFQ6enZvIfhcVJZFIsFhV5PrN6BFI6fuHsFsIfOgeoxKtsI6Hsfhov5XNFch2PhcVJ2ptyf09aGJInIFtU2Gx6fKznPyosZFIU8XNFcQNaxxlEk3xqPuIqFuIvGJInIFtU2Gx6fKHqFhesDKHyrFIn8XNFcpwPhcVJZFIsFhV5PrN6BFI6fuHsFsIfOQtsBGI6FFHFOJInZDzfSpV0GtVF2heoBGepkxlEk2eng7enT18d5b96FhxqfposO6IU2FxEVbnphho4TXBUkFIo2hengJ9ngUN6kCImFKznPyV0GtVJGGxmBFHXkxlEk2tyIFld2ptyf09aGJInIFtU2Gx6fKHqFhes1XNFcXdyxDz4kxlEkwInxGxErr83GJInIFtU2Gx6fKIUkFIo2hengJ9ngUoskCImFKznPyV0GtI6PcHsfxlEkqH6fFHyBDt6BGt6HbIqfceoFKe6OJzfSZV0GtwfhcVJIpInfvxqPuIqFuIvGJInIFtU2Gx6fKIUkFIo2hengJ9ngUoskCImFKznPyV0GtI6PcHsfxlEkqH6fFHyBDt6BGt6HbIqf6Ingv9oIFoyrGxq2Loy2TInfJV0Gtw0rxlEkaH6O7es1bIqf6Ingv9oIFoyrGxq2LoykDt6BCtnFbIfOCI6IvIo8XNFQ6enZvIfhcVJZFIsFhV5PrN6BFI6fuHsFsIfOgeoxKtsI6HsfhovVXNFcRNfhcVJIpInfvxqPuIqFuIvGXtsBgoyFDx7OCI6IvIo8XNFcQw31To4TX3nOsI47aH6O7es1bIqf6Ingv9oIFosBFtqPgov5XNFcZo4TXB6PWInZDIvGgeoHXNFcXw31TVFhcVJG7torGt6HWN6BFI6fuHsFsIfOgeoxKH6PuIqOQ9oGFosO6IU2FxEVbnsIDtm2Fo4TX3nOs9ngUNUFDx7ODHyFuesfJV0GtI6PcHsfxlEkwInxGxErr83GJInIFtU2Gx6fKHqFhesDKHyrFIn8XNFcpwPhcVJBCH67DtU8bIqf6Ingv9oIFoyFDx7OcInIhV0GtwPhcVJ7DtUfDtErr83GJInIFtU2Gx6fKznPyosZFIU8XNFcTo4TXB6PWInZDIvGA9oBhIokKtsI6HsfhV0GtwPhcVJ7Cx6dQ8ykCxn2LN6BFI6fuHsFsIfOgeoxKtsI6HsfhovVXNFcTo4TXBUkFIo2hengJ9ngUN6BFI6fuHsFsIfOgeoxKH6PuIqOQ9oGFosO6IU2FxEVbnsIDtm2Fo4TXBUkFIo2hengJ9ngUN6BFI6fuHsFsIfOT9oB09POpengJts7Gz6fKtsI6HsfhV0GtI6PcHsfxlEkMxn7T9ngUN6BFI6fuHsFsIfOQtsBGI6FFHFOJInZDzfSpV0GtVJGGxmBFHXkxlEk3tqOyVPxDtqcbIqf6Ingv9oIFosICH62FoskpInPWosZ0V0GtI6PcHsfxlEk5InIDxnZhN6BFI6fuHsFsIfOT9oB09POh9n7FV0GtwfhcVJ2ptyf09aGJInIFtU2Gx6fKtnOJ9nIGIokKtsI6HsfhV0Gtw31To4TX3nOsI47aH6O7es1b96FhxqfposO6IU2FxEVbnvd7o4TXB6PWInZDIvGT9oB09POCI6IvIo8XNFcTo4TXB6PWInZDIvGgeoxKeo2gt62FIEVbnsIDtm2Fo4TX4UfQHqFuIpcbIqf6Ingv9oIFosIpInfvxqPuIqFuI7OXtsBgoyFDxpVbnsIDtm2Fo4TXBqOptnPuxaGgeoxKeo2gt62FIEVbnsIDtm2Fo4TXBqOptnPuxaGXtsBgoyFDxpVbnpkjI6eXo4TXBqOptnPuxaGJInIFtU2Gx6fKHqFhesDKxqFQI4VbnvPxlEk3xqPuIqFuIvGJInIFtU2Gx6fKI6OpesfKeUkFenQKtqwXNFQ6enZvIfhcVJ7Cx6dQ8ykCxn2LNUFDx7OCI6IvIo8XNFcso4TX3nOsI47aH6O7es1bIqf6Ingv9oIFos7CIqF69nfposBFtqPgovVXNFcXdyBDxqF0VFhcVJ7DtUfDtErr83GJInIFtU2Gx6fKtnOJ9nIGIokKtsI6HsfhV0Gtw31To4TX3nOs9ngUN6BFtqPgoskCImFKwXVbnvBxlEk3tqOyVPxDtqcbIqf6Ingv9oIFoyFDx7Op9nxLxEVbnvrxlEkMxn7T9ngUN6BFtqPgoskCImFKw4VbnvPxlEk2eng7enT18d5bIngDe6ZFIEVbnyBpxnfxlEk2tyIFld2ptyf09aGJInIFtU2Gx6fKHqFhesDKH6PuIqOQ9oGFosO6IU2FxEVbnsIDtm2Fo4TX3nPuxnPcV5PrN6BFtqPgoskCImFKw4VbnvPxlEk2eng7enT18d5bHqFhesDKtsI6HsfhV0GtwPhcVJIpInfvxqPuIqFuIvGJInZDzfOXtsBgovVXNFcZo4TXBqf6eofcxaG6H6fFHyBDt6BGt6xKe6OJzfOgeoHXNFQ6enZvIfhcVJ7DtUfDtErr83GgeoxKeo2gt62FIEVbnsIDtm2Fo4TX8ykCxn2LNUrGxq2LosO6IU2FxEVbnvrxlEk3xqPuIqFuIvGJInIFtU2Gx6fKHqFhesDKtsI6Hsfhov5XNFcQNPhcVJBFI6P7tm8bIqf6Ingv9oIFoyFDx7OCI6IvIo8XNFcTo4TXBqf6eofcxaGT9oB09POCI6IvIo8XNFcTo4TX4UfQHqFuIpcbIqf6Ingv9oIFos7CIqF69nfposO6IU2FxEVbnv5RwPhcVJ7DtUfDtErr83GXtsBgoyFDxpVbnpk3xqPh9nwXo4TX4UfQHqFuIvGJInIFtU2Gx6fKIngDe6ZFIEVbnsIDtm2Fo4TXdsZCxproenZWN6BFI6fuHsFsIfOT9oB09POvHqfFIEVbnvVTo4TX3nPuxnPcV5PrNUFDxpVbnpVZNaiXo4TX3nOs9ngUNUFDx7OA9oBhIoVXNFcX8sfuxqfpVFhcVJIpInfvxqPuIqFuIvGJInIFtU2Gx6fKI6OpesfKeUkFenQKtqwXNFQ6enZvIfhcVJ7Cx6FuIvGJInIFtU2Gx6fKHqFhesDKxqFQI4VbnvPxlEk2eng7enT18d5bIqf6Ingv9oIFoyFDx7OQtsBGI6FFHXVbnpkaInghIoVXo4TXBqOptnPuxaGgeoxK96FhxqfpV0GtVJO6IXkxlEkaH6O7es1bIqf6Ingv9oIFoyFDx7OCI6IvIoBKw4VbnphRNfhcVJ2ptyf09aGFt6PXtqfJV0Gtxmk7IfhcVJG7torGt6HbIqf6Ingv9oIFosBFtqPgov5XNFcZ2PhcVJ7DtUfDtErr83GJInIFtU2Gx6fKznPyosO6IU2FxEVbnvwT27hcVJID9sfcenHbIUkFIo2hengJ9ngUoskCImFKznPyV0GtI6PcHsfxlEkqH6fFHyBDt6BGt6HbIqf6Ingv9oIFoyFDx7OCI6IvIo8XNFcZN3kxlEkMxn7T9ngUMvGJInIFtU2Gx6fKznPyoykGIsDhV0Gtw0PxlEk5tykQenghN6BFI6fuHsFsIfODeyBGx6Ph9nOuV0GtVF2FtU2GxqFs9oBgVFhcVJBFI6P7tm8bIqf6Ingv9oIFoyrGxq2Loy2TInfJV0Gtw0rxlEk5tykQenghN6BFI6fuHsFsIfOQtsBGI6FFHFOCI6IvIo8XNFcTo4TXdyBDt6BGt6HbIqf6Ingv9oIFoyFDx7OCI6IvIoBKwXVbnphgo4TXBqOptnPuxaGT9oB09EVbnpk5InIDxnZhVFhcVJ7Cx6FuIvGJInIFtU2Gx6fKIqfceoFKwXVbnvxxlEkMxn7T9ngUMvGJInIFtU2Gx6fKI6OpesfKeUkFenQKtqwXNFQ6enZvIfhcVJIpInfvxqPuIqFuIvGJInIFtU2Gx6fKznPyosO6IU2FxPSpV0GtNaFxlEk2eng7enT18d5bIqf6Ingv9oIFoyFDx7OCI6IvIoBKw4Vbnv5vo4TXBUkFIo2hengJ9ngUN6BFI6fuHsFsIfOgeoxKH6FU9m8XNFcTo4TX8ykCxn2LNUFDx7OcInIhV0GtwPhcVJ7Cx6FuIvGJInIFtU2Gx6fKHqFhesDKtsI6Hsfhov5XNFcsNPhcVF2hengJ9ngUN6BFI6fuHsFsIfOvIngv9oBGx6Fhz4Vbnv5TwPhcVJG7torGt6HbIqf6Ingv9oIFosICH62FoskpInPWosZ0V0GtI6PcHsfxlEk3xqPuIqFuIvGT9oB09EVbnpk5InIDxnZhVFhcVJ7Cx6dQ8ykCxn2LN6BFI6fuHsFsIfOgeoxKtsI6HsfhV0GtwveTo4TX4UfQHqFuIvGgeoxKtsI6HsfhV0Gt2f7OlEk4enxFe6OhV0GYV6P7xqOK9qFJIfOv9qOhHpgFt6PXtqfJV0GtI6PcHsfxlEkDxoBCosDGIqfKHsDCxmwuHyBDxqfvV0Gtnpk3tqOyVPxDtqcXlEkaH6O7es1XlEk2tyIFld2ptyf09Ekxo4TXeofht7OL9nBFoy2LtyBvlUxFeorCtUwXNFQtVJP7xqS1dsgGHqfpHpVcVJPodEVcVF20tyfhVXTXBqfvIokhV5fDIsZFVXTXdqFvxqOcHpVcVF22BpVcVFkGI6ZFHpkxoohcVUkDIsfXty8XNUcXenFKHqfF9pgJtyBKHyrDtXVbnvfxlEkD9n7htsOcH7Q4NEr4IoICtmIFHFhutofcxqFTtsFuxm2t3nOsI47aH6O7esDxlUIDtmfFV0Gt23rxlEkD9n7htsOcH7Q5Io2FHU81BnPUtqfxl677tmBGHqOGtUBvnh7Cx6dQ8ykCxn2Lo4gsenZ7I4VbnvdTo4TXenFQxqOCtm2tBqfvIokhV5fDIsZFo4gXtsBgosPGt4gFt6PXtqfJV0GtI6PcHsfxlEkD9n7htsOcH7Qrf7rxl6kCImFKenFQlU2Ftqf0xEVbnyQOo4TXesOpH6f0xqFCtXgJ9o2De6ZFosID9sfK9ngJ9n2DxqOpV0GtI6PcHsfxlEkD9n7htsOcH7Qrf7rxl6P0eyfpen2goskCty2hl6fuenkcIn8XNFQ6enZvIfhcV6PGtoBCtsZvn723BpiTNPhutofcxqFTtsFuxm2t3nOs9ngUo4gsenZ7I4VbnvdTo4TXenFQxqOCtm2tBv23Bv51oES1dh2rdXhpwPhutofcxqFTtsFuxm2t8ykCxn2Lo4gsenZ7I4VbnvdTo4TXenFQxqOCtm2td72mVaiRo4gXtsBgosPGt4gvInZFey8XNFQYKfhcV6PGtoBCtsZvnhPodPhuHsP6IfOTtsFuxmwu9qfDtmBLV0Gt23rxlEk0tykpIn2h9nOul6fuenkcIn8XNFQhHUfFo4TXenFQxqOCtm2tBqfvIokhV5fDIsZFo4gQxnZh9orC9nghHpgFt6PXtqfJV0GtI6PcHsfxlEkD9n7htsOcH7Q9Iofvo4gQxnZh9orC9nghH7Q2tyIGt6xxlUIDtmfFV0Gt23rxlEkD9n7htsOcH7Q9Iofvo4gQxnZh9orC9nghH7Q3tqOyVPxDtqQxlUIDtmfFV0Gt23rxlEkD9n7htsOcH7Q89o2htsZxl6kCImFKenFQlU2Ftqf0xEVbnyQOo4TX9nghIokTtsZDxqfKHmkFIqF0xEgFt6PXtqfJV0GtI6PcHsfxlEkD9n7htsOcH7Q89o2htsZxl677tmBGHqOGtUBvn72hengJ9ngUo4gsenZ7I4VbnvdTo4TXenFQxqOCtm2tBqfvIokhV5fDIsZFo4gvenIFoyrC9nghHpgvInZFey8XNFQYKfhcV6PGtoBCtsZvn7GFxo2xl6kCImFKenFQl6DFenZh9EVbnvdTo4TXenFQxqOCtm2td72mVaiRo4gXtsBgosPGt4gFt6PXtqfJV0GtI6PcHsfxlEkD9n7htsOcH7Q9Iofvo4gvenIFoyrC9nghHpgFt6PXtqfJV0GtI6PcHsfxlEkD9n7htsOcH7Q9Iofvo4gvenIFoyrC9nghHpgvInZFey8XNFQYKfhcV6GGxmBFHFO69o1uIngDe6ZFIEVbnyBpxnfxlEkD9n7htsOcH7Qmw72mw4rHlpr38hP4l3VTo4gDes27H6P0zfOXtsOvxEgsenZ7I4VbnpkwtyHXo4TXenFQxqOCtm2td72mVaiRo4gQxnZh9orC9nghHpgFt6PXtqfJV0GtI6PcHsfxlEk0tykpIn2h9nOul67GtFOsenZ7I4VbnvkxlEkD9n7htsOcH7Q5Io2FHU81BnPUtqfxl677tmBGHqOGtUBvnh2ptyf09Phux6PcxndXNFc7wPhcV6PGtoBCtsZvn723BpiTNPhutofcxqFTtsFuxm2tdsZCxproenZWo4gsenZ7I4VbnvdTo4TXenFQxqOCtm2tBqfvIokhV5fDIsZFo4gvenIFoyrC9nghHpgLInPcxq1XNFc7wPhcV6PGtoBCtsZvnhHvdhHZVPTCVP2a8fVQw0rxl677tmBGHqOGtUBvn72hengJ9ngUo4gsenZ7I4VbnvdTo4TXenFKHqfF9pgQtsBFV0GtVJBFI6P7tm8Xo4TXenFQxqOCtm2t8fx8o4gQxnZh9orC9nghH7Q3tqOyVPxDtqQxlUIDtmfFV0Gt23rxlEkGtUBFHUrCtqPhIfOTH6fJ9n2hl6BGHsPXtqfKtq2KH6fvxqOp9ngUV0GtI6PcHsfxlEkD9n7htsOcH7Q3dhH1waDxl6P0eyfpen2goskCty2hl6fuenkcIn8XNFQhHUfFo4TXenFQxqOCtm2td72mVaiRo4gvenIFoyrC9nghHpgFt6PXtqfJV0GtI6PcHsfxlEkD9n7htsOcH7Q9Iofvo4gvenIFoyrC9nghHpgLInPcxq1XNFc7wPhcV6PGtoBCtsZvn7rGHyBCtPhuHsP6IfOTtsFuxmwuHsfcIn2hV0Gtzy7xlEkD9n7htsOcH7Q3dhH1waDxlU2DI6fKHqOGtUBvlU2Ftqf0xEVbnyQOo4TXenFQxqOCtm2tdqFvxqOco4gvenIFoyrC9nghHpgLInPcxq1XNFc7wPhcV6PGtoBCtsZvn723BpiTNPhutofcxqFTtsFuxm2t3nOsI47aH6O7esDxlUIDtmfFV0Gt23rxlEkD9n7htsOcH7Q3dhH1waDxlU2DI6fKHqOGtUBvl6DFenZh9EVbnvdTo4TX9nghIokTtsZDxqfKHmkFIqF0xEgXtyDKesOctyVXNFch2pTZw3Hcw0VZlaV72fhcV6PGtoBCtsZvn7VRVPkFx6Ocx6fpo4gQxnZh9orC9nghH7Q3xqPuIqFuI7hux6PcxndXNFc7wPhcV6PGtnkCxPOctsxvlU2Ftqf0xEVbn7cX36Oh9nIgVXTXds2pInfuVXTX8sOuHsOcI4kxo4TXenFQxqOCtm2t8fx8o4gXtsBgosPGt4gLInPcxq1XNFc7wPhcV6PGoyrFIncu9ngJ9n2DxqOpH7O0tsZCHXVbnvV724Tp23dcw0d7laV72fhcV6PGtoBCtsZvnhHvdhHZVPTCVP2a8fVQw0rxl6kCImFKenFQlU2Ftqf0xEVbnyQOo4TXenFQxqOCtm2td011d6fstsZsIokxl6kCImFKenFQl6DFenZh9EVbnvdTo4TXenFQxqOCtm2tBv23Bv51oES1dh2rdXhpwPhutofcxqFTtsFuxmwuIngDe6ZFIEVbnsIDtm2Fo4TXenFQxqOCtm2tn6f7H7huen20xokDeyFKe6OCHy8uIngDe6ZFIEVbnsIDtm2Fo4TXenFQxqOCtm2tBqfvIokhV5fDIsZFo4gDes27H6P0zfOXtsOvxEgFt6PXtqfJV0GtI6PcHsfxlEkD9fOTInfWl67Toy20enZFosDFen8XNFcywPhcV6PGtoBCtsZvn7VRVPkFx6Ocx6fpo4gvenIFoyrC9nghHpgLInPcxq1XNFc7wPhcV6PGtoBCtsZvn7rGHyBCtPhuen20xokDeyFKe6OCHy8ux6PcxndXNFcX3qOyVFhcV6FuxqfpHqOceoBFoyrpInBGey8uH6fuIqfposkCzEVbnsIDtm2Fo4TXenFQe6OhosZCIywuImfpeoBGtsRXNFchwPhcV6PGtoBCtsZvnhPodPhue6OJzfOD9nhuIngDe6ZFIEVbnsIDtm2Fo4TXenFQxqOCtm2tn6f7H7hue6OJzfOD9nhuHsfcIn2hV0Gtzy7xlEkGtUBFHUrCtqPhIfOTH6fJ9n2hl6ZCxsfpoyBLengK2arQHpVbnsIDtm2Fo4TXenFQxqOCtm2tBv23Bv51oES1dh2rdXhpwPhue6OJzfOD9nhu9qfDtmBLV0Gt23rxlEkD9n7htsOcH7Qrf7rxlU2DI6fKHqOGtUBvlU2Ftqf0xEVbnyQOo4TXenFQxqOCtm2t8fx8o4gQxnZh9orC9nghH7Q2tyIGt6xxlUIDtmfFV0Gt23rxlEkD9fOTInfWl6BCxPODtnO7tU8XNFcvo4TXenFQxqOCtm2td72mVaiRo4gDes27H6P0zfOXtsOvxEgsenZ7I4Vbnpk2eoDGtofQVFhcV6PGoyrFIncutorKHs2DtqfKesDFHy8XNFcywPhcV6PGtoBCtsZvn7rGHyBCtPhutofcxqFTtsFuxm2t3nOs9ngUo4gsenZ7I4VbnvdTo4TXenFQxqOCtm2t8fx8o4gQxnZh9orC9nghH7Q2tyIFld2ptyf09Phux6PcxndXNFc7wPhcV6PGtoBCtsZvn7VRVPkFx6Ocx6fpo4gXtsBgosPGt4gFt6PXtqfJV0GtI6PcHsfxlEkD9n7htsOcH7Q3dhH1waDxl6kCImFKenFQl6DFenZh9EVbnvdTo4TXenFQxqOCtm2tn6f7H7huen20xokDeyFKe6OCHy8ux6PcxndXNFcX3qOyVFhcV6PGoyrFIncuIngDe6ZFIEVbnsIDtm2Fo4TXH6f09qPpIsfKI6FRl6fuenkcIn8XNFQhHUfFo4TXenFQxqOCtm2tdqFvxqOco4gvenIFoyrC9nghHpgFt6PXtqfJV0GtI6PcHsfxlEkD9n7htsOcH7Q3dhH1waDxl677tmBGHqOGtUBvnh2ptyf09Phux6PcxndXNFc7wPhcV6PGtoBCtsZvnhHvdhHZVPTCVP2a8fVQw0rxlU2DI6fKHqOGtUBvl6DFenZh9EVbnvdTo4TXenFQxqOCtm2td011d6fstsZsIokxlU2DI6fKHqOGtUBvl6fuenkcIn8XNFQ6enZvIfhcV6PGtoBCtsZvnhBFHsfpxErPenxcIfhutofcxqFTtsFuxm2tdsZCxproenZWo4gsenZ7I4VbnvdTo4TXenFQxqOCtm2t8fx8o4gQxnZh9orC9nghHpgFt6PXtqfJV0GtI6PcHsfxlEkD9n7htsOcH7Q89o2htsZxl677tmBGHqOGtUBvn72ctyH1fsPc97hux6PcxndXNFc7wPhcV6PGtoBCtsZvnhBFHsfpxErPenxcIfhuHsP6IfOTtsFuxmwuIngDe6ZFIEVbnsIDtm2Fo4TXenFQxqOCtm2tn6f7H7hue6OJzfOD9nhuIngDe6ZFIEVbnsIDtm2Fo4TXenFQxqOCtm2td011d6fstsZsIokxl6kCImFKenFQlU2Ftqf0xEVbnyQOo4TXenFQxqOCtm2t8fx8o4gQxnZh9orC9nghH7Q3xqPuIqFuI7hux6PcxndXNFc7wPhcV6PGtoBCtsZvnhHvdhHZVPTCVP2a8fVQw0rxl6kCImFKenFQl6fuenkcIn8XNFQ6enZvIfhcV6PGtoBCtsZvn723BpiTNPhutofcxqFTtsFuxm2tdyBDt6BGt6xxlUIDtmfFV0Gt23rxlEkD9n7htsOcH7Q9Iofvo4gQxnZh9orC9nghH7Q3xqPuIqFuI7hux6PcxndXNFc7wPhcV6PGtnkCxPOctsxvl6fuenkcIn8XNFQ6enZvIfhcV6PGtoBCtsZvn7VRVPkFx6Ocx6fpo4gQxnZh9orC9nghH7Q3tqOyVPxDtqQxlUIDtmfFV0Gt23rxlEkAxn7Toy20tyfhl6fuenkcIn8XNFQhHUfFo4TXenFQxqOCtm2tBqfvIokhV5fDIsZFo4gXtsBgosPGt4gvInZFey8XNFQYKfhcV6PGtoBCtsZvnhPodPhuHsP6IfOTtsFuxmwuIngDe6ZFIEVbnsIDtm2Fo4TXenFQxqOCtm2tdqFvxqOco4gQxnZh9orC9nghH7QaH6O7esDxlUIDtmfFV0Gt23rxlEkD9fOTInfWlUBDH6xFxPOc9n7XHpVbnsIDtm2Fo4TXenFQxqOCtm2td011d6fstsZsIokxl6P0eyfpen2goskCty2hl6fuenkcIn8XNFQ6enZvIfhcV6PGtoBCtsZvn7rGHyBCtPhue6OJzfOD9nhuIngDe6ZFIEVbnsIDtm2Fo4TXenFQxqOCtm2tBqfvIokhV5fDIsZFo4gQxnZh9orC9nghH7Q2tyIGt6xxlUIDtmfFV0Gt23rxlEkD9n7htsOcH7Q89o2htsZxl677tmBGHqOGtUBvl6fuenkcIn8XNFQ6enZvIfhcV6PGtoBCtsZvnhHvdhHZVPTCVP2a8fVQw0rxl6P0eyfpen2goskCty2hl6fuenkcIn8XNFQ6enZvIfhcV6PGtoBCtsZvn7GFxo2xl677tmBGHqOGtUBvl6fuenkcIn8XNFQ6enZvIfhcV6PGtoBCtsZvn7VRVPkFx6Ocx6fpo4gDes27H6P0zfOXtsOvxEgsenZ7I4VbnpkwtyHXo4TXenFQe6OhosZCIywuesOctykKtnFvHpVbnvV724TZw0dcw3dTlaV72fhcV6PGtoBCtsZvnhHvdhHZVPTCVP2a8fVQw0rxl677tmBGHqOGtUBvnh7Cx6FuI7hux6PcxndXNFc7wPhcV6PGtoBCtsZvnhHvdhHZVPTCVP2a8fVQw0rxlU2DI6fKHqOGtUBvlU2Ftqf0xEVbnyQOo4TXenFQxqOCtm2tBqfvIokhV5fDIsZFo4gXtsBgosPGt4gLInPcxq1XNFc7wPhcV62CHUkFeyBGtsRutnPRoyIDtmfFV0GtwFhcV6PGtoBCtsZvn7VRVPkFx6Ocx6fpo4gQxnZh9orC9nghHpgFt6PXtqfJV0GtI6PcHsfxlEkD9n7htsOcHpgFt6PXtqfJV0Gtxmk7IfhcV6PGtoBCtsZvn7VRVPkFx6Ocx6fpo4gQxnZh9orC9nghH7Q2tyIGt6xxlUIDtmfFV0Gt23rxlEkD9n7htsOcH7Qmw72mw4rHlpr38hP4l3VTo4gQxnZh9orC9nghH7Q2tyIFld2ptyf09Phux6PcxndXNFc7wPhcV6PGtoBCtsZvnhHvdhHZVPTCVP2a8fVQw0rxl677tmBGHqOGtUBvn72ctyH1fsPc97hux6PcxndXNFc7wPhcV6PGtoBCtsZvn7rGHyBCtPhuen20xokDeyFKe6OCHy8uIngDe6ZFIEVbnsIDtm2Fo4TXenFQe6OhosZCIywutsI6HsfhV0Gtw0iTo4TXenFKHqfF9pgJtyBKtsI6HsfhV0GtNPhcV6PGtoBCtsZvn7VRVPkFx6Ocx6fpo4gQxnZh9orC9nghH7QaH6O7esDxlUIDtmfFV0Gt23rxlEkD9n7XtyBKtqOUHpg0tsZCHFOL9o8XNFcZ23icw0d7la5p24Tp23fxlEkD9n7htsOcH7Qmw72mw4rHlpr38hP4l3VTo4gvenIFoyrC9nghHpgFt6PXtqfJV0GtI6PcHsfxlEkD9n7htsOcH7Q4NEr4IoICtmIFHFhuHsP6IfOTtsFuxmwuHsfcIn2hV0Gtzy7xlEkD9n7htsOcH7Qrf7rxl677tmBGHqOGtUBvnh2ptyf09Phux6PcxndXNFc7wPhcV6PGtoBCtsZvn7rGHyBCtPhutofcxqFTtsFuxm2t3nOsI47aH6O7esDxlUIDtmfFV0Gt23rxlEkJInIFtU2Gx6fKI6FRl6fuenkcIn8XNFQ6enZvIfhcV6PGtnkCxPOctsxvl6xctyHXNFcZwarxlEkD9n7htsOcH7Q9Iofvo4gQxnZh9orC9nghH7QaH6O7esDxlUIDtmfFV0Gt23rxlEk0tykpIn2h9nOul67CIqdXNFcXBoDTIokGtnfuxqPcVFhcV6PGtoBCtsZvnhPodPhuen20xokDeyFKe6OCHy8ux6PcxndXNFcX3qOyVFhcV6PGtoBCtsZvnhBFHsfpxErPenxcIfhutofcxqFTtsFuxm2tdyBDt6BGt6xxlUIDtmfFV0Gt23rxlEkD9n7htsOcH7Q89o2htsZxl6kCImFKenFQl6DFenZh9EVbnvdTo4TXenFQxqOCtm2tn6f7H7hutofcxqFTtsFuxm2t3nOsI47aH6O7esDxlUIDtmfFV0Gt23rxlEkD9n7htsOcH7Q5Io2FHU81BnPUtqfxl6P0eyfpen2goskCty2hlUIDtmfFV0GtVJZCxpkxK4TXI6PWInZDIpVbzpk6enQFtqPUl6fuenkcIn8XNFQhHUfFo4TXI6PWInZDIpgDtnO7tU8XNFcXBmFuen7GepkxlEk6enQFtqPUlUIDH6FDt62FV0GtwPhcV6ID9sfcenHutqFQ9o8XNFcZw77OK8__'
            }
        }

        for i = 1, #DB_DATA do
            config_data[i] = DB_DATA[i]
        end

        for i = #config_defaults, 1, -1 do
            local list = config_defaults[i]

            if list.data == nil then
                goto continue
            end

            local ok, result = config_system.decode(list.data)

            if not ok then
                -- config is not valid
                table.remove(config_defaults, i)

                goto continue
            end

            list.data = result
            ::continue::
        end

        local function create_config(name, data, is_default)
            local list = { }

            list.name = name
            list.data = data
            list.default = is_default

            return list
        end

        local function find_by_name(list, name)
            for i = 1, #list do
                local data = list[i]

                if data.name == name then
                    return data, i
                end
            end

            return nil, -1
        end

        local function save_config_data()
            database.write(DB_NAME, config_data)
        end

        local function update_config_list()
            for i = 1, #config_list do
                config_list[i] = nil
            end

            for i = 1, #config_defaults do
                local list = config_defaults[i]

                local cell = create_config(
                    list.name, list.data, true
                )

                table.insert(config_list, cell)
            end

            for i = 1, #config_data do
                local list = config_data[i]

                local cell = create_config(
                    list.name, list.data, false
                )

                cell.data_index = i

                table.insert(config_list, cell)
            end
        end

        local function get_render_list()
            local result = { }

            for i = 1, #config_list do
                local list = config_list[i]

                local name = list.name

                if list.default then
                    name = string.format(
                        '✦ %s', name
                    )
                end

                table.insert(result, name)
            end

            return result
        end

        local function find_config(name)
            return find_by_name(
                config_list, name
            )
        end

        local function load_config(name)
            local list, idx = find_config(name)

            if list == nil or idx == -1 then
                return
            end

            local ok, result = config_system.import(list.data)

            if not ok then
                return logging_system.error(string.format(
                    'failed to import %s config: %s', name, result
                ))
            end

            logging_system.success(string.format(
                'successfully loaded %s config', name
            ))
        end

        local function save_config(name)
            local cfg_data = config_system.export()

            local list, idx = find_config(name)

            if list == nil or idx == -1 then
                table.insert(config_data, create_config(
                    name, cfg_data, false
                ))

                save_config_data()
                update_config_list()

                config.list:update(
                    get_render_list()
                )

                return logging_system.success(string.format(
                    'successfully created %s config', name
                ))
            end

            if list.default then
                return logging_system.error(string.format(
                    'cannot modify %s config', name
                ))
            end

            list.data = cfg_data

            if list.data_index ~= nil then
                local data_cell = config_data[
                    list.data_index
                ]

                if data_cell ~= nil then
                    data_cell.data = cfg_data
                end
            end

            save_config_data()
            update_config_list()

            logging_system.success(string.format(
                'successfully modified %s config', name
            ))
        end

        local function delete_config(name)
            local list, idx = find_config(name)

            if list == nil or idx == -1 then
                return
            end

            if list.default then
                return logging_system.error(string.format(
                    'cannot delete %s config', name
                ))
            end

            local data_index = list.data_index

            if data_index == nil then
                return
            end

            table.remove(config_data, data_index)

            save_config_data()
            update_config_list()

            config.list:update(
                get_render_list()
            )

            local next_input = ''

            local index = math.min(
                config.list:get() + 1,
                #config_list
            )

            local data = config_list[index]

            if data ~= nil then
                next_input = data.name
            end

            config.input:set(next_input)

            logging_system.success(string.format(
                'successfully deleted %s config', name
            ))
        end

        config.list = menu.new(
            ui.new_listbox, 'AA', 'Anti-aimbot angles', '\n config.list', { }
        )

        config.input = menu.new(
            ui.new_textbox, 'AA', 'Anti-aimbot angles', '\n config.input', ''
        )

        config.load_button = menu.new(
            ui.new_button, 'AA', 'Anti-aimbot angles', '\u{E10B}  Load', function()
                local name = utils.trim(
                    config.input:get()
                )

                if name == '' then
                    return
                end

                load_config(name)
            end
        )

        config.save_button = menu.new(
            ui.new_button, 'AA', 'Anti-aimbot angles', '\u{E105}  Save', function()
                local name = utils.trim(
                    config.input:get()
                )

                if name == '' then
                    return
                end

                save_config(name)
            end
        )

        config.delete_button = menu.new(
            ui.new_button, 'AA', 'Anti-aimbot angles', '\u{E107}  Delete', function()
                local name = utils.trim(
                    config.input:get()
                )

                if name == '' then
                    return
                end

                delete_config(name)
            end
        )

        config.export_button = menu.new(
            ui.new_button, 'AA', 'Anti-aimbot angles', '\u{E16D}  Export', function()
                local ok, result = config_system.encode(
                    config_system.export()
                )

                if not ok then
                    return
                end

                clipboard.set(result)

                logging_system.success 'exported config to clipboard'
            end
        )

        config.import_button = menu.new(
            ui.new_button, 'AA', 'Anti-aimbot angles', '\u{E132}  Import', function()
                local ok, result = config_system.decode(
                    clipboard.get()
                )

                if not ok then
                    return
                end

                config_system.import(result)

                logging_system.success 'imported config from clipboard'
            end
        )

        update_config_list()

        config.list:update(
            get_render_list()
        )

        config.list:set_callback(function(item)
            local index = item:get()

            if index == nil then
                return
            end

            local list = config_list[index + 1]

            if list == nil then
                return
            end

            config.input:set(list.name)
        end)

        ref.config = config
    end

    local ragebot = { } do
	
				
        local ai_peek = { } do
            ai_peek.enabled = config_system.push(
                'ragebot', 'ai_peek.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('AI peek', 'ai_peek')
                )
            )

            ai_peek.indicators_color = config_system.push(
                'ragebot', 'ai_peek.indicators_color', menu.new(
                    ui.new_color_picker, 'AA', 'Anti-aimbot angles', new_key('Indicators color', 'ai_peek'), 255, 255, 255, 255
                )
            )

            ai_peek.mode = config_system.push(
                'ragebot', 'ai_peek.mode', menu.new(
                    ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('Mode', 'ai_peek'), {
                        'Default',
                        'Advanced'
                    }
                )
            )

            ai_peek.dot_offset = config_system.push(
                'ragebot', 'ai_peek.dot_offset', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Dot offset', 'ai_peek'), 0, 20, 8, true, 'u', 1
                )
            )

            ai_peek.dot_span = config_system.push(
                'ragebot', 'ai_peek.dot_span', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Dot span', 'ai_peek'), 0, 60, 5, true, 'u', 1
                )
            )

            ai_peek.dot_amount = config_system.push(
                'ragebot', 'ai_peek.dot_amount', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Dot amount', 'ai_peek'), 0, 8, 3, true, 'u', 1
                )
            )

            ai_peek.mp_scale_head = config_system.push(
                'ragebot', 'ai_peek.mp_scale_head', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Head scale', 'ai_peek'), 0, 100, 70, true, '%', 1
                )
            )

            ai_peek.mp_scale_chest = config_system.push(
                'ragebot', 'ai_peek.mp_scale_chest', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Chest scale', 'ai_peek'), 0, 100, 70, true, '%', 1
                )
            )

            ai_peek.target_limbs = config_system.push(
                'ragebot', 'ai_peek.target_limbs', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Target limbs', 'ai_peek')
                )
            )

            locker_system.push(-1, ai_peek.enabled)

            ragebot.ai_peek = ai_peek
        end

        local correction = { } do
            correction.enabled = config_system.push(
                'ragebot', 'correction.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Jitter correction', 'correction')
                )
            )

            correction.mode = config_system.push(
                'ragebot', 'correction.mode', menu.new(
                    ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('\n mode', 'correction'), {
                        'Default',
                        'Experimental'
                    }
                )
            )

            correction.min_value = config_system.push(
                'ragebot', 'correction.min_value', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Min value', 'correction'), 1, 60, 2
                )
            )

            correction.max_value = config_system.push(
                'ragebot', 'correction.max_value', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Max value', 'correction'), 1, 60, 2
                )
            )

            correction.disable_fake_indicator = config_system.push(
                'ragebot', 'correction.disable_fake_indicator', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Disable fake indicator', 'correction')
                )
            )

            locker_system.push(-1, correction.enabled)

            ragebot.correction = correction
        end

        local interpolate_predict = { } do
            interpolate_predict.enabled = config_system.push(
                'ragebot', 'interpolate_predict.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Interpolate predict', 'interpolate_predict')
                )
            )

            interpolate_predict.hotkey = config_system.push(
                'ragebot', 'interpolate_predict.hotkey', menu.new(
                    ui.new_hotkey, 'AA', 'Anti-aimbot angles', new_key('Hotkey', 'interpolate_predict'), true
                )
            )

            interpolate_predict.render_box = config_system.push(
                'ragebot', 'interpolate_predict.render_box', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Render box', 'interpolate_predict')
                )
            )

            interpolate_predict.box_color = config_system.push(
                'ragebot', 'interpolate_predict.box_color', menu.new(
                    ui.new_color_picker, 'AA', 'Anti-aimbot angles', new_key('Box color', 'interpolate_predict'), 47, 117, 221, 255
                )
            )

            interpolate_predict.lower_than_40ms = config_system.push(
                'ragebot', 'interpolate_predict.lower_than_40ms', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Lower than 40ms', 'interpolate_predict')
                )
            )

            interpolate_predict.disable_lc_restoring = config_system.push(
                'ragebot', 'interpolate_predict.disable_lc_restoring', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('\ab6b665ffDisable lc restoring', 'interpolate_predict')
                )
            )

            locker_system.push(-1, interpolate_predict.enabled)

            ragebot.interpolate_predict = interpolate_predict
        end

        local aimtools = { } do
            local weapons = {
                'G3SG1 / SCAR-20',
                'SSG 08',
                'AWP',
                'R8 Revolver',
                'Desert Eagle',
                'Pistol',
                'Zeus'
            }

            local states = {
                'Standing',
                'Moving',
                'Slow Walk',
                'Crouch',
                'Move-Crouch'
            }

            aimtools.enabled = config_system.push(
                'ragebot', 'aimtools.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Aim tools', 'aimtools')
                )
            )

            aimtools.weapon = menu.new(
                ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('Weapon', 'aimtools'), weapons
            )

            for i = 1, #weapons do
                local weapon = weapons[i]

                local key = 'aimtools[' .. weapon .. ']'

                local items = { } do
                    local body_aim = { } do
                        body_aim.enabled = config_system.push(
                            'ragebot', key .. '.body_aim.enabled', menu.new(
                                ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Body aim', key)
                            )
                        )

                        body_aim.select = config_system.push(
                            'ragebot', key .. '.body_aim.select', menu.new(
                                ui.new_multiselect, 'AA', 'Anti-aimbot angles', new_key('Select', key), {
                                    'Enemy health < X',
                                    'Enemy higher than you'
                                }
                            )
                        )

                        body_aim.health = config_system.push(
                            'ragebot', key .. '.body_aim.health', menu.new(
                                ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Health', key), 20, 100, 50, true, '%'
                            )
                        )

                        items.body_aim = body_aim
                    end

                    local safe_points = { } do
                        safe_points.enabled = config_system.push(
                            'ragebot', key .. '.safe_points.enabled', menu.new(
                                ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Safe points', key)
                            )
                        )

                        safe_points.select = config_system.push(
                            'ragebot', key .. '.safe_points.select', menu.new(
                                ui.new_multiselect, 'AA', 'Anti-aimbot angles', new_key('Select', key), {
                                    'Enemy health < X',
                                    'Enemy higher than you'
                                }
                            )
                        )

                        safe_points.health = config_system.push(
                            'ragebot', key .. '.safe_points.health', menu.new(
                                ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Health', key), 20, 100, 50, true, '%'
                            )
                        )

                        items.safe_points = safe_points
                    end

                    local multipoints = { } do
                        multipoints.enabled = config_system.push(
                            'ragebot', key .. '.multipoints.enabled', menu.new(
                                ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Multipoints', key)
                            )
                        )

                        for j = 1, #states do
                            local state = states[j]

                            local key = key .. '.multipoints[' .. state .. ']'

                            multipoints[state] = config_system.push(
                                'ragebot', key .. '.value', menu.new(
                                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key(state, key), 25, 100, 50, true, '%'
                                )
                            )
                        end

                        items.multipoints = multipoints
                    end

                    local accuracy_boost = { } do
                        accuracy_boost.enabled = config_system.push(
                            'ragebot', key .. '.accuracy_boost.enabled', menu.new(
                                ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Accuracy boost', key)
                            )
                        )

                        accuracy_boost.value = config_system.push(
                            'ragebot', key .. '.accuracy_boost.value', menu.new(
                                ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('\n accuracy_boost.value', key), {
                                    'Low',
                                    'Medium',
                                    'High',
                                    'Maximum'
                                }
                            )
                        )

                        items.accuracy_boost = accuracy_boost
                    end
                end

                aimtools[weapon] = items
            end

            aimtools.weapons = weapons
            aimtools.states = states

            locker_system.push(0, aimtools.enabled)

            ragebot.aimtools = aimtools
        end

        local aimbot_logs = { } do
            aimbot_logs.enabled = config_system.push(
                'ragebot', 'aimbot_logs.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Aimbot logs', 'aimbot_logs')
                )
            )

            aimbot_logs.select = config_system.push(
                'ragebot', 'aimbot_logs.select', menu.new(
                    ui.new_multiselect, 'AA', 'Anti-aimbot angles', new_key('Log selection', 'aimbot_logs'), {
                        'Notify',
                        'Screen',
                        'Console'
                    }
                )
            )

            aimbot_logs.color_hit = config_system.push(
                'ragebot', 'aimbot_logs.color_hit', menu.new(
                    ui.new_color_picker, 'AA', 'Anti-aimbot angles', '\n aimbot_logs.color_hit', 150, 255, 125, 255
                )
            )

            aimbot_logs.color_miss = config_system.push(
                'ragebot', 'aimbot_logs.color_miss', menu.new(
                    ui.new_color_picker, 'AA', 'Anti-aimbot angles', '\n aimbot_logs.color_miss', 255, 125, 150, 255
                )
            )

            aimbot_logs.glow = config_system.push(
                'ragebot', 'aimbot_logs.glow', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Glow', 'aimbot_logs'), 0, 125, 100, true, '%'
                )
            )

            aimbot_logs.offset = config_system.push(
                'ragebot', 'aimbot_logs.offset', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Offset', 'aimbot_logs'), 30, 325, 200, true, 'px', 2
                )
            )

            aimbot_logs.duration = config_system.push(
                'ragebot', 'aimbot_logs.duration', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Duration', 'aimbot_logs'), 30, 80, 40, true, 's.', 0.1
                )
            )

            lock_unselection(aimbot_logs.select)

            ragebot.aimbot_logs = aimbot_logs
        end

        local defensive_fix = { } do
            defensive_fix.enabled = config_system.push(
                'ragebot', 'defensive_fix.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Defensive enhancements', 'defensive_fix')
                )
            )

            locker_system.push(1, defensive_fix.enabled)

            ragebot.defensive_fix = defensive_fix
        end

        local recharge_fix = { } do
            recharge_fix.enabled = config_system.push(
                'ragebot', 'recharge_fix.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Unsafe charge', 'recharge_fix')
                )
            )

            ragebot.recharge_fix = recharge_fix
        end

        local jitter_fix = { } do
            jitter_fix.enabled = config_system.push(
                'ragebot', 'jitter_fix.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('                      <<<maybe use>>>', 'jitter_fix')
                )
            )

            locker_system.push(1, jitter_fix.enabled)

            ragebot.jitter_fix = jitter_fix
        end

        local auto_hide_shots = { } do
            local weapon_list = {
                'Auto Snipers',
                'AWP',
                'Scout',
                'Desert Eagle',
                'Pistols',
                'SMG',
                'Rifles'
            }

            local state_list = {
                'Standing',
                'Moving',
                'Slow Walk',
                'Air',
                'Air-Crouch',
                'Crouch',
                'Move-Crouch',
            }

            auto_hide_shots.enabled = config_system.push(
                'Ragebot', 'auto_hide_shots.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Auto hide shots', 'auto_hide_shots')
                )
            )

            auto_hide_shots.weapons = config_system.push(
                'Ragebot', 'auto_hide_shots.weapons', menu.new(
                    ui.new_multiselect, 'AA', 'Anti-aimbot angles', new_key('Weapons', 'auto_hide_shots'), weapon_list
                )
            )

            auto_hide_shots.states = config_system.push(
                'Ragebot', 'auto_hide_shots.states', menu.new(
                    ui.new_multiselect, 'AA', 'Anti-aimbot angles', new_key('States', 'auto_hide_shots'), state_list
                )
            )

            lock_unselection(auto_hide_shots.weapons)

            lock_unselection(auto_hide_shots.states, {
                'Slow Walk',
                'Crouch',
                'Move-Crouch'
            })

            ragebot.auto_hide_shots = auto_hide_shots
        end

        local jump_scout = { } do
            jump_scout.enabled = config_system.push(
                'ragebot', 'jump_scout.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Allow Jump scout', 'jump_scout')
                )
            )

            ragebot.jump_scout = jump_scout
        end

        ref.ragebot = ragebot
    end

    local antiaim = { } do
        local function create_defensive_items(name)
            local items = { }

            local function hash(key)
                return name .. ':defensive_' .. key
            end

            local function fmt_key(key)
                return new_key(fmt(key), hash(key))
            end

            items.force_break_lc = config_system.push(
                'antiaim', hash 'force_break_lc', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key(
                        'Force break lc', hash 'force_break_lc'
                    )
                )
            )

            items.enabled = config_system.push(
                'antiaim', hash 'enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key(
                        'Defensive anti-aim', hash 'enabled'
                    )
                )
            )

            items.activation = config_system.push(
                'antiaim', hash 'activation', menu.new(
                    ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('Activation', hash 'activation'), {
                        'Sensitivity',
                        'Twilight'
                    }
                )
            )

            items.sensitivity = config_system.push(
                'antiaim', hash 'sensitivity', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('\n', hash 'sensitivity'), 1, 100, 100, true, '%'
                )
            )

            items.pitch = config_system.push(
                'antiaim', hash 'pitch', menu.new(
                    ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('Pitch', hash 'pitch'), {
                        'Off',
                        'Static',
                        'Jitter',
                        'Spin',
                        'Sway',
                        'Random',
                        'Timed'
                    }
                )
            )

            items.pitch_label_1 = menu.new(
                ui.new_label, 'AA', 'Anti-aimbot angles', 'From'
            )

            items.pitch_offset_1 = config_system.push(
                'antiaim', hash 'pitch_offset_1', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('\n', hash 'pitch_offset_1'), -89, 89, 0, true, '°'
                )
            )

            items.pitch_label_2 = menu.new(
                ui.new_label, 'AA', 'Anti-aimbot angles', 'To'
            )

            items.pitch_offset_2 = config_system.push(
                'antiaim', hash 'pitch_offset_2', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('\n', hash 'pitch_offset_2'), -89, 89, 0, true, '°'
                )
            )

            items.pitch_speed = config_system.push(
                'antiaim', hash 'pitch_speed', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Speed', hash 'pitch_speed'), -50, 50, 20, true, nil, 0.1
                )
            )

            items.pitch_time = config_system.push(
                'antiaim', hash 'pitch_time', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Time', hash 'pitch_speed'), 1, 200, 1, true, nil, 0.1
                )
            )

            items.pitch_randomize_offset = config_system.push(
                'antiaim', hash 'pitch_randomize_offset', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Randomize offset', hash 'pitch_randomize_offset')
                )
            )

            items.yaw = config_system.push(
                'antiaim', hash 'yaw', menu.new(
                    ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('Yaw', hash 'yaw'), {
                        'Off',
                        'Static',
                        'Static LR',
                        'Spin',
                        'Sway',
                        'Random',
                        'Cycle'
                    }
                )
            )

            items.yaw_left = config_system.push(
                'antiaim', hash 'yaw_left', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Yaw left', hash 'yaw_left'), -180, 180, 0, true, '°'
                )
            )

            items.yaw_right = config_system.push(
                'antiaim', hash 'yaw_right', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Yaw right', hash 'yaw_right'), -180, 180, 0, true, '°'
                )
            )

            items.yaw_offset = config_system.push(
                'antiaim', hash 'yaw_offset', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('\n', hash 'yaw_offset'), 0, 360, 0, true, '°'
                )
            )

            items.yaw_speed = config_system.push(
                'antiaim', hash 'yaw_speed', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Speed', hash 'yaw_speed'), -50, 50, 20, true, '', 0.1
                )
            )

            items.yaw_randomize_offset = config_system.push(
                'antiaim', hash 'yaw_randomize_offset', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Randomize offset', hash 'yaw_randomize_offset')
                )
            )

            items.yaw_modifier = config_system.push(
                'antiaim', hash 'yaw_modifier', menu.new(
                    ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('Yaw modifier', hash 'yaw_modifier'), {
                        'Off',
                        'Offset',
                        'Center',
                        'Skitter'
                    }
                )
            )


            items.yaw_label_1 = menu.new(
                ui.new_label, 'AA', 'Anti-aimbot angles', 'From'
            )

            items.yaw_offset_1 = config_system.push(
                'antiaim', hash 'yaw_offset_1', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('\n', hash 'pitch_offset_1'), -89, 89, 0, true, '°'
                )
            )

            items.yaw_label_2 = menu.new(
                ui.new_label, 'AA', 'Anti-aimbot angles', 'To'
            )

            items.yaw_offset_2 = config_system.push(
                'antiaim', hash 'yaw_offset_2', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('\n', hash 'pitch_offset_2'), -89, 89, 0, true, '°'
                )
            )


            items.modifier_offset = config_system.push(
                'antiaim', hash 'modifier_offset', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('\n', hash 'modifier_offset'), -180, 180, 0, true, '°'
                )
            )

            items.body_yaw = config_system.push(
                'antiaim', hash 'modifier_delay_2', menu.new(
                    ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('Body yaw', hash 'body_yaw'), {
                        'Off',
                        'Opposite',
                        'Static',
                        'Jitter'
                    }
                )
            )

            items.body_yaw_offset = config_system.push(
                'antiaim', hash 'body_yaw_offset', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('\n', hash 'body_yaw_offset'), -180, 180, 0, true, '°'
                )
            )

            items.freestanding_body_yaw = config_system.push(
                'antiaim', hash 'freestanding_body_yaw', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Freestanding body yaw', hash 'freestanding_body_yaw')
                )
            )

            items.delay_1 = config_system.push(
                'antiaim', hash 'delay_1', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Delay from', hash 'delay_1'), 1, 14, 0, true, 't'
                )
            )

            items.delay_2 = config_system.push(
                'antiaim', hash 'delay_2', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Delay to', hash 'delay_2'), 1, 14, 0, true, 't'
                )
            )

            return items
        end

        local function create_builder_items(name, std_key)
            local items = { }

            local is_default = name == 'Default'
            local is_legit_aa = name == 'Legit AA'

            local function hash(key)
                return name .. ':' .. key
            end

            local function fmt_key(key)
                return new_key(fmt(key), hash(key))
            end

            if std_key ~= nil then
                function hash(key)
                    return name .. ':' .. key .. ':' .. std_key
                end
            end

            if not is_default then
                local enabled_name = string.format(
                    'Redefine %s', name
                )

                items.enabled = config_system.push(
                    'antiaim', hash 'enabled', menu.new(
                        ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key(
                            enabled_name, hash 'enabled'
                        )
                    )
                )
            end

            if not is_legit_aa then
                items.pitch = config_system.push(
                    'antiaim', hash 'pitch', menu.new(
                        ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('Pitch', hash 'pitch'), {
                            'Off',
                            'Default',
                            'Up',
                            'Down',
                            'Minimal',
                            'Random',
                            'Custom'
                        }
                    )
                )

                items.pitch_offset = config_system.push(
                    'antiaim', hash 'pitch_offset', menu.new(
                        ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('\n', hash 'pitch_offset'), -89, 89, 0, true, '°'
                    )
                )

                items.pitch:set 'Default'
            end

            if name ~= 'Freestanding' then
                items.yaw = config_system.push(
                    'antiaim', hash 'yaw', menu.new(
                        ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('Yaw', hash 'yaw'), {
                            'Off',
                            '180',
                            '180 LR',
                            'Spin',
                            'Static',
                            '180 Z',
                            'Crosshair'
                        }
                    )
                )

                items.yaw_offset = config_system.push(
                    'antiaim', hash 'yaw_offset', menu.new(
                        ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('\n', hash 'yaw_offset'), -180, 180, 0, true, '°'
                    )
                )

                items.yaw_left = config_system.push(
                    'antiaim', hash 'yaw_left', menu.new(
                        ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Yaw left', hash 'yaw_left'), -180, 180, 0, true, '°'
                    )
                )

                items.yaw_right = config_system.push(
                    'antiaim', hash 'yaw_right', menu.new(
                        ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Yaw right', hash 'yaw_right'), -180, 180, 0, true, '°'
                    )
                )

                items.yaw_asynced = config_system.push(
                    'antiaim', hash 'yaw_asynced', menu.new(
                        ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Asynced', hash 'yaw_asynced')
                    )
                )

                items.yaw_jitter = config_system.push(
                    'antiaim', hash 'yaw_jitter', menu.new(
                        ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('Yaw jitter', hash 'yaw_jitter'), {
                            'Off',
                            'Offset',
                            'Center',
                            'Random',
                            'Skitter'
                        }
                    )
                )

                items.jitter_offset = config_system.push(
                    'antiaim', hash 'jitter_offset', menu.new(
                        ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('\n', hash 'jitter_offset'), -180, 180, 0, true, '°'
                    )
                )

                items.yaw:set '180'
            end

            items.body_yaw = config_system.push(
                'antiaim', hash 'body_yaw', menu.new(
                    ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('Body yaw', hash 'body_yaw'), {
                        'Off',
                        'Opposite',
                        'Static',
                        'Jitter'
                    }
                )
            )

            items.body_yaw_offset = config_system.push(
                'antiaim', hash 'body_yaw_offset', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('\n', hash 'body_yaw_offset'), -180, 180, 0, true, '°'
                )
            )

            items.freestanding_body_yaw = config_system.push(
                'antiaim', hash 'freestanding_body_yaw', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key(
                        'Freestanding body yaw', hash 'freestanding_body_yaw'
                    )
                )
            )

            if name ~= 'Fakelag' then
                items.delay_body_1 = config_system.push(
                    'antiaim', hash 'delay_body_1', menu.new(
                        ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Delay from', hash 'delay_body_1'), 1, 14, 0, true, 't'
                    )
                )

                items.delay_body_2 = config_system.push(
                    'antiaim', hash 'delay_body_2', menu.new(
                        ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Delay to', hash 'delay_body_2'), 1, 14, 0, true, 't'
                    )
                )
            end

            return items
        end

        antiaim.select = menu.new(
            ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('\n Select', 'antiaim'), {
                'Builder',
                'Settings'
            }
        )

        local builder = { } do
            builder.state = menu.new(
                ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('State', 'builder'), const.states
            )

            for i = 1, #const.states do
                local state = const.states[i]

                local items = create_builder_items(state)

                if state ~= 'Fakelag' then
                    items.separator = menu.new(
                        ui.new_label, 'AA', 'Anti-aimbot angles', new_key('\n', 'separator')
                    )

                    items.defensive = create_defensive_items(state)
                end

                builder[state] = items
            end

            antiaim.builder = builder
        end

        local settings = { } do
            local disablers = { } do
                disablers.enabled = config_system.push(
                    'antiaim', 'disablers.enabled', menu.new(
                        ui.new_checkbox, 'AA', 'Fake lag', new_key('Spin if', 'Spin if')
                    )
                )

                disablers.select = menu.new(
                    ui.new_multiselect, 'AA', 'Fake lag', new_key('\n Select', 'Spin if'), {
                        'Warmup',
                        'No enemies'
                    }
                )

                lock_unselection(disablers.select)

                settings.disablers = disablers
            end

            local avoid_backstab = { } do
                avoid_backstab.enabled = config_system.push(
                    'antiaim', 'avoid_backstab.enabled', menu.new(
                        ui.new_checkbox, 'AA', 'Fake lag', new_key('Avoid backstab', 'avoid_backstab')
                    )
                )

                settings.avoid_backstab = avoid_backstab
            end

            local freestanding = { } do
                freestanding.enabled = config_system.push(
                    'antiaim', 'freestanding.enabled', menu.new(
                        ui.new_checkbox, 'AA', 'Fake lag', new_key('Freestanding', 'freestanding')
                    )
                )

                freestanding.hotkey = config_system.push(
                    'antiaim', 'freestanding.hotkey', menu.new(
                        ui.new_hotkey, 'AA', 'Fake lag', new_key('Hotkey', 'freestanding'), true
                    )
                )

                settings.freestanding = freestanding
            end

            

            local safe_head = { } do
                safe_head.enabled = config_system.push(
                    'antiaim', 'antiaim.settings.safe_head.enabled', menu.new(
                        ui.new_checkbox, 'AA', 'Fake lag', new_key('Safe head', 'safe_head')
                    )
                )

                safe_head.states = config_system.push(
                    'antiaim', 'antiaim.settings.safe_head.states', menu.new(
                        ui.new_multiselect, 'AA', 'Fake lag', new_key('States', 'safe_head'), {
                            'Knife',
                            'Taser',
                            'Above enemy',
                            'Distance'
                        }
                    )
                )

                locker_system.push(1, safe_head.enabled)

                lock_unselection(safe_head.states)

                settings.safe_head = safe_head
            end

            local defensive_flick = { } do
                defensive_flick.enabled = config_system.push(
                    'antiaim', 'defensive_flick.enabled', menu.new(
                        ui.new_checkbox, 'AA', 'Fake lag', new_key('Defensive flick', 'defensive_flick')
                    )
                )

                locker_system.push(1, defensive_flick.enabled)

                defensive_flick.states = config_system.push(
                    'antiaim', 'defensive_flick.inverter', menu.new(
                        ui.new_multiselect, 'AA', 'Fake lag', new_key('States', 'defensive_flick'), {
                            'Standing',
                            'Slow Walk',
                            'Jumping',
                            'Jumping+',
                            'Crouch',
                            'Move-Crouch'
                        }
                    )
                )

                defensive_flick.inverter = config_system.push(
                    'antiaim', 'defensive_flick.inverter', menu.new(
                        ui.new_hotkey, 'AA', 'Fake lag', new_key('Inverter', 'defensive_flick')
                    )
                )

                lock_unselection(defensive_flick.states, {
                    'Standing',
                    'Crouch'
                })

                settings.defensive_flick = defensive_flick
            end

            antiaim.settings = settings
        end

        ref.antiaim = antiaim
    end

    local visuals = { } do
        local aspect_ratio = { } do
            local tooltips = {
                [125] = '5:4',
                [133] = '4:3',
                [160] = '16:10',
                [177] = '16:9'
            }

            aspect_ratio.enabled = config_system.push(
                'visuals', 'aspect_ratio.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Aspect ratio', 'aspect_ratio')
                )
            )

            aspect_ratio.value = config_system.push(
                'visuals', 'aspect_ratio.value', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('\n', 'aspect_ratio'), 0, 200, 133, true, '', 0.01, tooltips
                )
            )

            visuals.aspect_ratio = aspect_ratio
        end

        local third_person = { } do
            third_person.enabled = config_system.push(
                'visuals', 'third_person.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Third person', 'third_person')
                )
            )

            third_person.distance = config_system.push(
                'visuals', 'third_person.distance', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Distance', 'third_person'), 30, 100, 58
                )
            )

            third_person.mode = config_system.push(
                'visuals', 'third_person.mode', menu.new(
                    ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('Mode', 'third_person'), {
                        'Single',
                        'Dual'
                    }
                )
            )

            third_person.single_distance = config_system.push(
                'visuals', 'third_person.single_distance', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('\n single_distance', 'third_person'), -100, 100, 30, true, '%'
                )
            )

            third_person.dual_distance = config_system.push(
                'visuals', 'third_person.dual_distance', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('\n dual_distance', 'third_person'), -100, 100, 30, true, '%'
                )
            )

            visuals.third_person = third_person
        end

        local viewmodel = { } do
            viewmodel.enabled = config_system.push(
                'visuals', 'viewmodel.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Viewmodel', 'viewmodel')
                )
            )

            viewmodel.fov = config_system.push(
                'visuals', 'viewmodel.fov', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Field of fov', 'viewmodel'), 0, 1000, 680, true, '°', 0.1
                )
            )

            viewmodel.offset_x = config_system.push(
                'visuals', 'viewmodel.offset_x', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Offset X', 'viewmodel'), -100, 100, 25, true, '', 0.1
                )
            )

            viewmodel.offset_y = config_system.push(
                'visuals', 'viewmodel.offset_y', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Offset Y', 'viewmodel'), -100, 100, 25, true, '', 0.1
                )
            )

            viewmodel.offset_z = config_system.push(
                'visuals', 'viewmodel.offset_z', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Offset Z', 'viewmodel'), -100, 100, 25, true, '', 0.1
                )
            )

            viewmodel.opposite_knife_hand = config_system.push(
                'visuals', 'viewmodel.opposite_knife_hand', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Opposite knife hand', 'viewmodel')
                )
            )

            viewmodel.separator = menu.new(
                ui.new_label, 'AA', 'Anti-aimbot angles', '\n'
            )

            visuals.viewmodel = viewmodel
        end

        local scope_animation = { } do
            scope_animation.enabled = config_system.push(
                'visuals', 'scope_animation.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Scope animation', 'scope_animation')
                )
            )

            visuals.scope_animation = scope_animation
        end

        local custom_scope = { } do
            custom_scope.enabled = config_system.push(
                'visuals', 'custom_scope.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Custom scope', 'custom_scope')
                )
            )

            custom_scope.mode = config_system.push(
                'visuals', 'custom_scope.mode', menu.new(
                    ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('Mode', 'custom_scope'), {
                        'Plus',
                        'Cross'
                    }
                )
            )

            custom_scope.color = config_system.push(
                'visuals', 'custom_scope.color', menu.new(
                    ui.new_color_picker, 'AA', 'Anti-aimbot angles', new_key('Color', 'custom_scope'), 0, 255, 255, 255
                )
            )

            custom_scope.gap = config_system.push(
                'visuals', 'custom_scope.gap', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Gap', 'custom_scope'), 0, 100, 10, true, 'px'
                )
            )

            custom_scope.length = config_system.push(
                'visuals', 'custom_scope.length', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Length', 'custom_scope'), 0, 200, 50, true, 'px'
                )
            )

            custom_scope.angle = config_system.push(
                'visuals', 'custom_scope.angle', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Angle', 'custom_scope'), -360 , 360, 0, true, '°'
                )
            )

            custom_scope.animation_speed = config_system.push(
                'visuals', 'custom_scope.animation_speed', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Animation speed', 'custom_scope'), 1, 100, 25, true, '%'
                )
            )

            visuals.custom_scope = custom_scope
        end

        local world_marker = { } do
            local function create_color(name, value)
                local result = { }

                result.label = menu.new(
                    ui.new_label, 'AA', 'Anti-aimbot angles', new_key(name .. ' color', 'world_marker')
                )

                result.picker = config_system.push(
                    'visuals', 'world_marker.' .. name:lower():gsub('\x20', '_'), menu.new(
                        ui.new_color_picker, 'AA', 'Anti-aimbot angles', new_key(name, 'world_marker'), value:unpack()
                    )
                )

                return result
            end

            world_marker.enabled = config_system.push(
                'visuals', 'world_marker.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('World marker', 'world_marker')
                )
            )

            world_marker.style = config_system.push(
                'visuals', 'world_marker.style', menu.new(
                    ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('Style', 'world_marker'), {
                        'Cross',
                        'Plus'
                    }
                )
            )

            world_marker.size = config_system.push(
                'visuals', 'world_marker.size', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Size', 'world_marker'), 3, 10, 5
                )
            )

            world_marker.show_miss_reason = config_system.push(
                'visuals', 'world_marker.show_miss_reason', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Show miss reason', 'show_miss_reason')
                )
            )

            world_marker['hit'] = create_color('Hit', color(180, 230, 30, 255))
            world_marker['?'] = create_color('?', color(255, 0, 0, 255))
            world_marker['spread'] = create_color('Spread', color(255, 200, 0, 255))
            world_marker['prediction error'] = create_color('Prediction error', color(255, 125, 125, 255))
            world_marker['death'] = create_color('Death', color(100, 100, 255, 255))
            world_marker['unregistered shot'] = create_color('Unregistered shot', color(100, 100, 255, 255))

            visuals.world_marker = world_marker
        end

        local damage_marker = { } do
            damage_marker.enabled = config_system.push(
                'visuals', 'damage_marker.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Damage marker', 'damage_marker')
                )
            )

            damage_marker.color = config_system.push(
                'visuals', 'damage_marker.color', menu.new(
                    ui.new_color_picker, 'AA', 'Anti-aimbot angles', new_key('Color', 'damage_marker'), 0, 255, 255, 255
                )
            )

            visuals.damage_marker = damage_marker
        end

        local watermark = { } do
            watermark.select = config_system.push(
                'visuals', 'watermark.enabled', menu.new(
                    ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('Watermark', 'watermark'), {
                        'Off','Default'
                    }
                )
            )

            watermark.color = config_system.push(
                'visuals', 'watermark.color', menu.new(
                    ui.new_color_picker, 'AA', 'Anti-aimbot angles', new_key('Color', 'watermark'), 0, 255, 255, 255
                )
            )

            watermark.display = config_system.push(
                'visuals', 'watermark.display', menu.new(
                    ui.new_multiselect, 'AA', 'Anti-aimbot angles', new_key('Display', 'watermark'), {
                        'Username',
                        'FPS',
                        'Ping',
                        'Time'
                    }
                )
            )

            watermark.position = config_system.push(
                'visuals', 'watermark.position', menu.new(
                    ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('Position', 'watermark'), {
                        'Top Left',
                        'Top Center',
                        'Top Right',
                        'Bottom Left',
                        'Bottom Center',
                        'Bottom Right',
                        'Center Left',
                        'Center Right',
                        'Custom'
                    }
                )
            )

            watermark.position:set 'Bottom Center'

            visuals.watermark = watermark
        end

        local indicators = { } do
            indicators.enabled = config_system.push(
                'visuals', 'indicators.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Indicators', 'indicators')
                )
            )

            indicators.style = config_system.push(
                'visuals', 'indicators.style', menu.new(
                    ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('Style', 'indicators'), {
                        'Default',
                        'Sparkles'
                    }
                )
            )

            indicators.color_accent = config_system.push(
                'visuals', 'indicators.color_accent', menu.new(
                    ui.new_color_picker, 'AA', 'Anti-aimbot angles', new_key('Color accent', 'indicators'), 0, 255, 255, 255
                )
            )

            indicators.color_secondary = config_system.push(
                'visuals', 'indicators.color_secondary', menu.new(
                    ui.new_color_picker, 'AA', 'Anti-aimbot angles', new_key('Color secondary', 'indicators'), 255, 255, 255, 255
                )
            )

            indicators.offset = config_system.push(
                'visuals', 'indicators.offset', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Offset', 'indicators'), 3, 40, 11, true, 'px', 2
                )
            )

            visuals.indicators = indicators
        end

        local damage_indicator = { } do
            damage_indicator.enabled = config_system.push(
                'visuals', 'damage_indicator.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Damage indicator', 'damage_indicator')
                )
            )

            damage_indicator.color = config_system.push(
                'visuals', 'damage_indicator.color', menu.new(
                    ui.new_color_picker, 'AA', 'Anti-aimbot angles', new_key('Color', 'damage_indicator'), 0, 255, 255, 255
                )
            )

            damage_indicator.font = config_system.push(
                'visuals', 'damage_indicator.font', menu.new(
                    ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('Font', 'damage_indicator'), {
                        'Default',
                        'Pixel'
                    }
                )
            )

            damage_indicator.display = config_system.push(
                'visuals', 'damage_indicator.display', menu.new(
                    ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('Display', 'damage_indicator'), {
                        'Always On',
                        'Always On (50%)',
                        'Hotkey'
                    }
                )
            )

            damage_indicator.animation = config_system.push(
                'visuals', 'damage_indicator.animation', menu.new(
                    ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('Animation', 'damage_indicator'), {
                        'Instant',
                        'Smooth'
                    }
                )
            )

            visuals.damage_indicator = damage_indicator
        end

        local manual_arrows = { } do
            manual_arrows.enabled = config_system.push(
                'visuals', 'manual_arrows.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Manual arrows', 'manual_arrows')
                )
            )

            manual_arrows.style = config_system.push(
                'visuals', 'manual_arrows.style', menu.new(
                    ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('Style', 'manual_arrows'), {
                        'Default',
                        'Alternative'
                    }
                )
            )

            manual_arrows.color_accent = config_system.push(
                'visuals', 'manual_arrows.color_accent', menu.new(
                    ui.new_color_picker, 'AA', 'Anti-aimbot angles', new_key('Color accent', 'manual_arrows'), 255, 255, 255, 200
                )
            )

            manual_arrows.color_secondary = config_system.push(
                'visuals', 'manual_arrows.color_secondary', menu.new(
                    ui.new_color_picker, 'AA', 'Anti-aimbot angles', new_key('Color secondary', 'manual_arrows'), 255, 255, 255, 200
                )
            )

            visuals.manual_arrows = manual_arrows
        end

        local velocity_warning = { } do
            velocity_warning.enabled = config_system.push(
                'visuals', 'velocity_warning.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Velocity warning', 'velocity_warning')
                )
            )

            velocity_warning.color = config_system.push(
                'visuals', 'velocity_warning.color', menu.new(
                    ui.new_color_picker, 'AA', 'Anti-aimbot angles', new_key('Color', 'velocity_warning'), 0, 255, 255, 255
                )
            )

            velocity_warning.offset = config_system.push(
                'visuals', 'velocity_warning.color', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Offset', 'velocity_warning'), 30, 250, 125, true, 'px', 2
                )
            )

            visuals.velocity_warning = velocity_warning
        end

        local debug_panel = { } do
            debug_panel.enabled = config_system.push(
                'visuals', 'debug_panel.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Debug panel', 'debug_panel')
                )
            )

            debug_panel.color = config_system.push(
                'visuals', 'debug_panel.color', menu.new(
                    ui.new_color_picker, 'AA', 'Anti-aimbot angles', new_key('Color', 'debug_panel'), 255, 255, 255, 255
                )
            )

            visuals.debug_panel = debug_panel
        end

        local bomb_indicator = { } do
            bomb_indicator.enabled = config_system.push(
                'visuals', 'bomb_indicator.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Bomb indicator', 'bomb_indicator')
                )
            )

            bomb_indicator.good_label = menu.new(
                ui.new_label, 'AA', 'Anti-aimbot angles', 'Good color'
            )

            bomb_indicator.good_color = config_system.push(
                'visuals', 'bomb_indicator.good_color', menu.new(
                    ui.new_color_picker, 'AA', 'Anti-aimbot angles', new_key('Good color picker', 'bomb_indicator'), 175, 175, 255, 255
                )
            )

            bomb_indicator.bad_label = menu.new(
                ui.new_label, 'AA', 'Anti-aimbot angles', 'Bad color'
            )

            bomb_indicator.bad_color = config_system.push(
                'visuals', 'bomb_indicator.bad_color', menu.new(
                    ui.new_color_picker, 'AA', 'Anti-aimbot angles', new_key('Bad color picker', 'bomb_indicator'), 220, 30, 50, 255
                )
            )

            visuals.bomb_indicator = bomb_indicator
        end

        local gamesense_indicator = { } do
            local names = {
                'Safe Point',
                'Body Aim',
                'Ping Spike',
                'Double Tap',
                'Fake Duck',
                'Freestanding',
                'Hide Shots',
                'Min. Damage',
                'Hit Chance'
            }

            local function get_listbox_list()
                local result = { }

                for i = 1, #names do
                    local name = names[i]

                    local items = gamesense_indicator[name]

                    if items == nil then
                        goto continue
                    end

                    local col, state = color(255, 255, 255, 200), 'Disabled'

                    if items.enabled:get() then
                        col = color(software.get_color())
                        state = 'Enabled'
                    end

                    table.insert(result, string.format(
                        '%s ~ \a%s%s', name, col:to_hex(), state
                    ))

                    ::continue::
                end

                return result
            end

            local function update_listbox()
                if gamesense_indicator.listbox ~= nil then
                    gamesense_indicator.listbox:update(
                        get_listbox_list()
                    )
                end
            end

            gamesense_indicator.enabled = config_system.push(
                'visuals', 'gamesense_indicator.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Gamesense indicator', 'gamesense_indicator')
                )
            )

            gamesense_indicator.follow_in_thirdperson = config_system.push(
                'visuals', 'gamesense_indicator.follow_in_thirdperson', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Follow in thirdperson', 'gamesense_indicator')
                )
            )

            gamesense_indicator.listbox = menu.new(
                ui.new_listbox, 'AA', 'Anti-aimbot angles', new_key('Listbox', 'gamesense_indicator'), { }
            )

            for i = 1, #names do
                local name = names[i]

                local key = 'gamesense_indicator.' .. name

                local items = { } do
                    items.enabled = config_system.push(
                        'visuals', 'gamesense_indicator.' .. name .. '.enabled', menu.new(
                            ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key(name .. ' indicator', key)
                        )
                    )

                    items.custom_name = config_system.push(
                        'visuals', 'gamesense_indicator.' .. name .. '.custom_name', menu.new(
                            ui.new_textbox, 'AA', 'Anti-aimbot angles', new_key('Custom name', key)
                        )
                    )

                    items.change_color = config_system.push(
                        'visuals', 'gamesense_indicator.' .. name .. '.change_color', menu.new(
                            ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Change color', key)
                        )
                    )

                    items.color_picker = config_system.push(
                        'visuals', 'gamesense_indicator.' .. name .. '.color_picker', menu.new(
                            ui.new_color_picker, 'AA', 'Anti-aimbot angles', new_key('Color', key), 0, 255, 255, 255
                        )
                    )

                    items.enabled:set(true)
                    items.enabled:set_callback(update_listbox)
                end

                gamesense_indicator[name] = items
            end

            update_listbox()
            gamesense_indicator.names = names

            visuals.gamesense_indicator = gamesense_indicator
        end

        local bullet_tracers = { } do
            bullet_tracers.enabled = config_system.push(
                'visuals', 'bullet_tracers.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Bullet tracers', 'bullet_tracers')
                )
            )

            bullet_tracers.color = config_system.push(
                'visuals', 'bullet_tracers.color', menu.new(
                    ui.new_color_picker, 'AA', 'Anti-aimbot angles', new_key('Color', 'bullet_tracers'), 255, 255, 255, 255
                )
            )

            bullet_tracers.duration = config_system.push(
                'visuals', 'bullet_tracers.duration', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Duration', 'bullet_tracers'), 5, 50, 20, true, 's', 0.1
                )
            )

            visuals.bullet_tracers = bullet_tracers
        end

        ref.visuals = visuals
    end

    local misc = { } do
        local clantag = { } do
            clantag.enabled = config_system.push(
                'visuals', 'clantag.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Clantag', 'clantag')
                )
            )

            misc.clantag = clantag
        end

        local trashtalk = { } do
            trashtalk.enabled = config_system.push(
                'visuals', 'trashtalk.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Trashtalk', 'trashtalk')
                )
            )

            misc.trashtalk = trashtalk
        end

        local fast_ladder = { } do
            fast_ladder.enabled = config_system.push(
                'visuals', 'fast_ladder.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Fast ladder', 'fast_ladder')
                )
            )

            misc.fast_ladder = fast_ladder
        end

        local animation_breaker = { } do
            animation_breaker.enabled = config_system.push(
                'visuals', 'animation_breaker.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Animation breaker', 'animation_breaker')
                )
            )

            animation_breaker.in_air_legs = config_system.push(
                'visuals', 'animation_breaker.in_air_legs', menu.new(
                    ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('In-air legs', 'animation_breaker'), {
                        'Off',
                        'Static',
                        'Moonwalk'
                    }
                )
            )

            animation_breaker.in_air_static_value = config_system.push(
                'visuals', 'animation_breaker.in_air_static_value', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('\n in_air.static.value', 'animation_breaker'), 0, 100, 100, true, '%'
                )
            )

            animation_breaker.onground_legs = config_system.push(
                'visuals', 'animation_breaker.onground_legs', menu.new(
                    ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('On-ground legs', 'animation_breaker'), {
                        'Off',
                        'Static',
                        'Jitter',
                        'Moonwalk'
                    }
                )
            )

            animation_breaker.onground_jitter_min_value = config_system.push(
                'visuals', 'animation_breaker.onground_jitter_min_value', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Min. value', 'animation_breaker'), 0, 100, 50, true, '%'
                )
            )

            animation_breaker.onground_jitter_max_value = config_system.push(
                'visuals', 'animation_breaker.onground_jitter_max_value', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Max. value', 'animation_breaker'), 0, 100, 50, true, '%'
                )
            )

            animation_breaker.adjust_lean = config_system.push(
                'visuals', 'animation_breaker.adjust_lean', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Adjust lean', 'animation_breaker'), 0, 100, 0, true, '%', 1, {
                        [0] = 'Off'
                    }
                )
            )

            animation_breaker.pitch_on_land = config_system.push(
                'visuals', 'animation_breaker.pitch_on_land', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Pitch on land', 'animation_breaker')
                )
            )

            animation_breaker.earthquake = config_system.push(
                'visuals', 'animation_breaker.earthquake', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Earthquake', 'animation_breaker')
                )
            )

            animation_breaker.earthquake_value = config_system.push(
                'visuals', 'animation_breaker.earthquake_value', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('\n earthquake.value', 'animation_breaker'), 1, 100, 100, true, '%'
                )
            )

            misc.animation_breaker = animation_breaker
        end

        local walking_on_quick_peek = { } do
            walking_on_quick_peek.enabled = config_system.push(
                'visuals', 'walking_on_quick_peek.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Walking on quick peek', 'walking_on_quick_peek')
                )
            )

            misc.walking_on_quick_peek = walking_on_quick_peek
        end

        ref.misc = misc
    end

    local fakelag = { } do
        local HOTKEY_MODE = {
            [0] = 'Always on',
            [1] = 'On hotkey',
            [2] = 'Toggle',
            [3] = 'Off hotkey'
        }

        local function get_hotkey_value(_, mode, key)
            return HOTKEY_MODE[mode], key or 0
        end

        fakelag.enabled = config_system.push(
            'fakelag', 'fakelag.enabled', menu.new(
                ui.new_checkbox, 'AA', 'Fake lag', new_key('Enabled', 'fakelag')
            )
        )

        fakelag.hotkey = config_system.push(
            'fakelag', 'fakelag.hotkey', menu.new(
                ui.new_hotkey, 'AA', 'Fake lag', new_key('Hotkey', 'fakelag'), true
            )
        )

        fakelag.amount = config_system.push(
            'fakelag', 'fakelag.amount', menu.new(
                ui.new_combobox, 'AA', 'Fake lag', new_key('Amount', 'fakelag'), {
                    'Dynamic',
                    'Maximum',
                    'Fluctuate'
                }
            )
        )

        fakelag.variance = config_system.push(
            'fakelag', 'fakelag.variance', menu.new(
                ui.new_slider, 'AA', 'Fake lag', new_key('Variance', 'fakelag'), 0, 100, 0, true, '%'
            )
        )

        fakelag.limit = config_system.push(
            'fakelag', 'fakelag.limit', menu.new(
                ui.new_slider, 'AA', 'Fake lag', new_key('Limit', 'fakelag'), 1, 15, 13
            )
        )

        fakelag.enabled:set(ui.get(software.antiaimbot.fake_lag.enabled[1]))
        fakelag.hotkey:set(get_hotkey_value(ui.get(software.antiaimbot.fake_lag.enabled[2])))

        fakelag.amount:set(ui.get(software.antiaimbot.fake_lag.amount))

        fakelag.variance:set(ui.get(software.antiaimbot.fake_lag.variance))
        fakelag.limit:set(ui.get(software.antiaimbot.fake_lag.limit))

        ref.fakelag = fakelag
    end

    local scene do
        local set_antiaimbot_angles do
            local ref = software.antiaimbot.angles

            function set_antiaimbot_angles(value)
                local pitch_value = ui.get(ref.pitch[1])
                local yaw_value = ui.get(ref.yaw[1])
                local body_yaw_value = ui.get(ref.body_yaw[1])

                ui.set_visible(ref.enabled, value)
                ui.set_visible(ref.pitch[1], value)

                if pitch_value == 'Custom' then
                    ui.set_visible(ref.pitch[2], value)
                end

                ui.set_visible(ref.yaw_base, value)
                ui.set_visible(ref.yaw[1], value)

                if yaw_value ~= 'Off' then
                    local yaw_jitter_value = ui.get(ref.yaw_jitter[1])

                    ui.set_visible(ref.yaw[2], value)
                    ui.set_visible(ref.yaw_jitter[1], value)

                    if yaw_jitter_value ~= 'Off' then
                        ui.set_visible(ref.yaw_jitter[2], value)
                    end
                end

                ui.set_visible(ref.body_yaw[1], value)

                if body_yaw_value ~= 'Off' then
                    if body_yaw_value ~= 'Opposite' then
                        ui.set_visible(ref.body_yaw[2], value)
                    end

                    ui.set_visible(ref.freestanding_body_yaw, value)
                end

                ui.set_visible(ref.edge_yaw, value)

                ui.set_visible(ref.freestanding[1], value)
                ui.set_visible(ref.freestanding[2], value)

                ui.set_visible(ref.roll, value)
            end
        end

        local set_antiaimbot_fakelag do
            local ref = software.antiaimbot.fake_lag

            function set_antiaimbot_fakelag(value)
                ui.set_visible(ref.enabled[1], value)
                ui.set_visible(ref.enabled[2], value)

                ui.set_visible(ref.amount, value)
                ui.set_visible(ref.variance, value)
                ui.set_visible(ref.limit, value)
            end
        end

        local function update_builder_items(items)
            local defensive = items.defensive

            if items.enabled ~= nil then
                menu_logic.set(items.enabled, true)

                if not items.enabled:get() then
                    return
                end
            end

            if items.pitch ~= nil then
                menu_logic.set(items.pitch, true)

                if items.pitch:get() == 'Custom' then
                    menu_logic.set(items.pitch_offset, true)
                end
            end

            if items.yaw ~= nil then
                menu_logic.set(items.yaw, true)

                if items.yaw:get() ~= 'Off' then
                    if items.yaw:get() == '180 LR' then
                        menu_logic.set(items.yaw_left, true)
                        menu_logic.set(items.yaw_right, true)

                        menu_logic.set(items.yaw_asynced, true)
                    else
                        menu_logic.set(items.yaw_offset, true)
                    end

                    menu_logic.set(items.yaw_jitter, true)

                    if items.yaw_jitter:get() ~= 'Off' then
                        menu_logic.set(items.jitter_offset, true)
                    end
                end
            end

            menu_logic.set(items.body_yaw, true)

            if items.body_yaw:get() ~= 'Off' then
                if items.body_yaw:get() ~= 'Opposite' then
                    menu_logic.set(items.body_yaw_offset, true)
                end

                menu_logic.set(items.freestanding_body_yaw, true)

                if items.body_yaw:get() == 'Jitter' then
                    menu_logic.set(items.delay_body_1, true)
                    menu_logic.set(items.delay_body_2, true)
                end
            end

            if items.separator ~= nil then
                menu_logic.set(items.separator, true)
            end

            if defensive ~= nil then
                if defensive.force_break_lc ~= nil then
                    menu_logic.set(defensive.force_break_lc, true)
                end

                menu_logic.set(defensive.enabled, true)

                if defensive.enabled:get() then
                    menu_logic.set(defensive.pitch, true)

                    if defensive.pitch:get() ~= 'Off' then
                        menu_logic.set(defensive.pitch_offset_1, true)

                        if defensive.pitch:get() ~= 'Static' then
                            menu_logic.set(defensive.pitch_label_1, true)
                            menu_logic.set(defensive.pitch_label_2, true)

                            menu_logic.set(defensive.pitch_offset_2, true)
                        end

                        if defensive.pitch:get() == 'Spin' then
                            menu_logic.set(defensive.pitch_speed, true)
                        end

                        if defensive.pitch:get() == 'Timed' then
                            menu_logic.set(defensive.pitch_time, true)
                        end

                        if defensive.pitch:get() == 'Sway' then
                            menu_logic.set(defensive.pitch_randomize_offset, true)
                        end
                    end

                    menu_logic.set(defensive.yaw, true)

                    if defensive.yaw:get() ~= 'Off' then
                        if defensive.yaw:get() ~= 'Cycle' then
                            if defensive.yaw:get() == 'Static LR' then
                                menu_logic.set(defensive.yaw_left, true)
                                menu_logic.set(defensive.yaw_right, true)
                            else
                                menu_logic.set(defensive.yaw_offset, true)
                            end

                            if defensive.yaw:get() == 'Spin' then
                                menu_logic.set(defensive.yaw_speed, true)
                            end

                            if defensive.yaw:get() == 'Sway' then
                                menu_logic.set(defensive.yaw_randomize_offset, true)
                                menu_logic.set(defensive.yaw_left, true)
                                menu_logic.set(defensive.yaw_right, true)
                                menu_logic.set(defensive.yaw_offset, false)
                            end
                        end

                        menu_logic.set(defensive.yaw_modifier, true)

                        if defensive.yaw_modifier:get() ~= 'Off' then
                            menu_logic.set(defensive.modifier_offset, true)
                        end
                    end

                    menu_logic.set(defensive.body_yaw, true)

                    if defensive.body_yaw:get() ~= 'Off' then
                        if defensive.body_yaw:get() ~= 'Opposite' then
                            menu_logic.set(defensive.body_yaw_offset, true)
                        end

                        menu_logic.set(defensive.freestanding_body_yaw, true)

                        if defensive.body_yaw:get() == 'Jitter' then
                            menu_logic.set(defensive.delay_1, true)
                            menu_logic.set(defensive.delay_2, true)
                        end
                    end

                    local activation = defensive.activation:get()
                    menu_logic.set(defensive.activation, true)

                    if activation == 'Sensitivity' then
                        menu_logic.set(defensive.sensitivity, true)
                    end
                end
            end
        end

        local function force_update_scene()
            menu_logic.set(general.label, true)

            local category = general.category:get()
            menu_logic.set(general.category, true)

            if category ~= '\u{E148}  Ragebot' and category ~= '\u{E149}  Anti-Aim' then
                menu_logic.set(general.welcome_text, true)
                menu_logic.set(general.build_name, true)
                menu_logic.set(general.empty_bag, true)
                menu_logic.set(general.line, true)
            end

            if category == '\u{E28F}  Configs' then
                menu_logic.set(config.list, true)
                menu_logic.set(config.input, true)

                menu_logic.set(config.load_button, true)
                menu_logic.set(config.save_button, true)
                menu_logic.set(config.delete_button, true)
                menu_logic.set(config.import_button, true)
                menu_logic.set(config.export_button, true)
            end

            if category == '\u{E148}  Ragebot' then
                local is_ai_peek = ragebot.ai_peek.enabled:get() do
                    menu_logic.set(ragebot.ai_peek.enabled, true)

                    if is_ai_peek then
                        menu_logic.set(ragebot.ai_peek.indicators_color, true)
                        menu_logic.set(ragebot.ai_peek.mode, true)

                        menu_logic.set(ragebot.ai_peek.dot_offset, true)
                        menu_logic.set(ragebot.ai_peek.dot_span, true)
                        menu_logic.set(ragebot.ai_peek.dot_amount, true)

                        if ragebot.ai_peek.mode:get() == 'Advanced' then
                            menu_logic.set(ragebot.ai_peek.mp_scale_head, true)
                            menu_logic.set(ragebot.ai_peek.mp_scale_chest, true)

                            menu_logic.set(ragebot.ai_peek.target_limbs, true)
                        end
                    end
                end

                local is_correction = ragebot.correction.enabled:get() do
                    menu_logic.set(ragebot.correction.enabled, true)

                    if is_correction then
                        menu_logic.set(ragebot.correction.mode, true)

                        if ragebot.correction.mode:get() ~= 'Experimental' then
                            menu_logic.set(ragebot.correction.min_value, true)
                            menu_logic.set(ragebot.correction.max_value, true)
                            menu_logic.set(ragebot.correction.disable_fake_indicator, true)
                        end
                    end
                end

                local is_interpolate_predict = ragebot.interpolate_predict.enabled:get() do
                    menu_logic.set(ragebot.interpolate_predict.enabled, true)
                    menu_logic.set(ragebot.interpolate_predict.hotkey, true)

                    if is_interpolate_predict then
                        menu_logic.set(ragebot.interpolate_predict.render_box, true)
                        menu_logic.set(ragebot.interpolate_predict.box_color, true)
                        menu_logic.set(ragebot.interpolate_predict.lower_than_40ms, true)
                        menu_logic.set(ragebot.interpolate_predict.disable_lc_restoring, true)
                    end
                end

                local is_aimbot_logs = ragebot.aimbot_logs.enabled:get() do
                    menu_logic.set(ragebot.aimbot_logs.enabled, true)

                    if is_aimbot_logs then
                        menu_logic.set(ragebot.aimbot_logs.select, true)

                        if ragebot.aimbot_logs.select:get 'Screen' then
                            menu_logic.set(ragebot.aimbot_logs.color_hit, true)
                            menu_logic.set(ragebot.aimbot_logs.color_miss, true)

                            menu_logic.set(ragebot.aimbot_logs.glow, true)
                            menu_logic.set(ragebot.aimbot_logs.offset, true)
                            menu_logic.set(ragebot.aimbot_logs.duration, true)
                        end
                    end
                end

                local is_aimtools = ragebot.aimtools.enabled:get() do
                    menu_logic.set(ragebot.aimtools.enabled, true)

                    if is_aimtools then
                        menu_logic.set(ragebot.aimtools.weapon, true)

                        local weapon = ragebot.aimtools.weapon:get()
                        local items = ragebot.aimtools[weapon]

                        if items ~= nil then
                            menu_logic.set(items.body_aim.enabled, true)

                            if items.body_aim.enabled:get() then
                                menu_logic.set(items.body_aim.select, true)

                                if items.body_aim.select:get 'Enemy health < X' then
                                    menu_logic.set(items.body_aim.health, true)
                                end
                            end

                            menu_logic.set(items.safe_points.enabled, true)

                            if items.safe_points.enabled:get() then
                                menu_logic.set(items.safe_points.select, true)

                                if items.safe_points.select:get 'Enemy health < X' then
                                    menu_logic.set(items.safe_points.health, true)
                                end
                            end

                            menu_logic.set(items.multipoints.enabled, true)

                            if items.multipoints.enabled:get() then
                                for i = 1, #ragebot.aimtools.states do
                                    local state = ragebot.aimtools.states[i]

                                    menu_logic.set(items.multipoints[state], true)
                                end
                            end

                            menu_logic.set(items.accuracy_boost.enabled, true)

                            if items.accuracy_boost.enabled:get() then
                                menu_logic.set(items.accuracy_boost.value, true)
                            end
                        end
                    end
                end

                menu_logic.set(ragebot.recharge_fix.enabled, true)
                menu_logic.set(ragebot.jitter_fix.enabled, true)

                local is_auto_hide_shots = ragebot.auto_hide_shots.enabled:get() do
                    menu_logic.set(ragebot.auto_hide_shots.enabled, true)

                    if is_auto_hide_shots then
                        menu_logic.set(ragebot.auto_hide_shots.weapons, true)
                        menu_logic.set(ragebot.auto_hide_shots.states, true)
                    end
                end

                menu_logic.set(ragebot.jump_scout.enabled, true)
                menu_logic.set(ragebot.defensive_fix.enabled, true)

                menu_logic.set(ref.fakelag.enabled, true)
                menu_logic.set(ref.fakelag.hotkey, true)
                menu_logic.set(ref.fakelag.amount, true)
                menu_logic.set(ref.fakelag.variance, true)
                menu_logic.set(ref.fakelag.limit, true)
            end

            if category == '\u{E149}  Anti-Aim' then
                local builder do
                    local ref = antiaim.builder

                    local state = ref.state:get()
                    menu_logic.set(ref.state, true)

                    local items = ref[state]

                    if items ~= nil then
                        update_builder_items(items)
                    end
                end

                local settings do
                    local ref = antiaim.settings

                    local is_disablers = ref.disablers.enabled:get() do
                        menu_logic.set(ref.disablers.enabled, true)

                        if is_disablers then
                            menu_logic.set(ref.disablers.select, true)
                        end
                    end

                    menu_logic.set(ref.avoid_backstab.enabled, true)

                    local is_safe_head = ref.safe_head.enabled:get() do
                        menu_logic.set(ref.safe_head.enabled, true)

                        if is_safe_head then
                            menu_logic.set(ref.safe_head.states, true)
                        end
                    end

                    menu_logic.set(ref.freestanding.enabled, true)
                    menu_logic.set(ref.freestanding.hotkey, true)

                    local is_defensive_flick = ref.defensive_flick.enabled:get() do
                        menu_logic.set(ref.defensive_flick.enabled, true)

                        if is_defensive_flick then
                            menu_logic.set(ref.defensive_flick.states, true)
                            menu_logic.set(ref.defensive_flick.inverter, true)
                        end
                    end
                end
            end

            if category == '\u{E2B1}  Visuals' then
                local is_aspect_ratio = visuals.aspect_ratio.enabled:get() do
                    menu_logic.set(visuals.aspect_ratio.enabled, true)

                    if is_aspect_ratio then
                        menu_logic.set(visuals.aspect_ratio.value, true)
                    end
                end

                local is_third_person = visuals.third_person.enabled:get() do
                    menu_logic.set(visuals.third_person.enabled, true)

                    if is_third_person then
                        menu_logic.set(visuals.third_person.distance, true)

                        menu_logic.set(visuals.third_person.mode, true)
                        menu_logic.set(visuals.third_person.single_distance, true)

                        if visuals.third_person.mode:get() == 'Dual' then
                            menu_logic.set(visuals.third_person.dual_distance, true)
                        end
                    end
                end

                local is_viewmodel = visuals.viewmodel.enabled:get() do
                    menu_logic.set(visuals.viewmodel.enabled, true)

                    if is_viewmodel then
                        menu_logic.set(visuals.viewmodel.fov, true)
                        menu_logic.set(visuals.viewmodel.offset_x, true)
                        menu_logic.set(visuals.viewmodel.offset_y, true)
                        menu_logic.set(visuals.viewmodel.offset_z, true)
                        menu_logic.set(visuals.viewmodel.opposite_knife_hand, true)
                    end
                end

                menu_logic.set(visuals.scope_animation.enabled, true)

                local is_custom_scope = visuals.custom_scope.enabled:get() do
                    menu_logic.set(visuals.custom_scope.enabled, true)

                    if is_custom_scope then
                        menu_logic.set(visuals.custom_scope.mode, true)

                        menu_logic.set(visuals.custom_scope.color, true)
                        menu_logic.set(visuals.custom_scope.gap, true)
                        menu_logic.set(visuals.custom_scope.size, true)
                        menu_logic.set(visuals.custom_scope.length, true)

                        if visuals.custom_scope.mode:get() == 'Cross' then
                            menu_logic.set(visuals.custom_scope.angle, true)
                        end

                        menu_logic.set(visuals.custom_scope.animation_speed, true)
                    end
                end

                local is_world_marker = visuals.world_marker.enabled:get() do
                    menu_logic.set(visuals.world_marker.enabled, true)

                    if is_world_marker then
                        menu_logic.set(visuals.world_marker.style, true)
                        menu_logic.set(visuals.world_marker.size, true)

                        menu_logic.set(visuals.world_marker.show_miss_reason, true)

                        menu_logic.set(visuals.world_marker['hit'].label, true)
                        menu_logic.set(visuals.world_marker['hit'].picker, true)

                        menu_logic.set(visuals.world_marker['?'].label, true)
                        menu_logic.set(visuals.world_marker['?'].picker, true)

                        menu_logic.set(visuals.world_marker['spread'].label, true)
                        menu_logic.set(visuals.world_marker['spread'].picker, true)

                        menu_logic.set(visuals.world_marker['prediction error'].label, true)
                        menu_logic.set(visuals.world_marker['prediction error'].picker, true)

                        menu_logic.set(visuals.world_marker['death'].label, true)
                        menu_logic.set(visuals.world_marker['death'].picker, true)

                        menu_logic.set(visuals.world_marker['unregistered shot'].label, true)
                        menu_logic.set(visuals.world_marker['unregistered shot'].picker, true)
                    end
                end

                local is_damage_marker = visuals.damage_marker.enabled:get() do
                    menu_logic.set(visuals.damage_marker.enabled, true)

                    if is_damage_marker then
                        menu_logic.set(visuals.damage_marker.color, true)
                    end
                end

                local watermark_value = visuals.watermark.select:get() do
                    menu_logic.set(visuals.watermark.select, true)

                    menu_logic.set(visuals.watermark.color, true)

                    if visuals.watermark.select:get() ~= 'Modern' then
                        menu_logic.set(visuals.watermark.display, true)
                    end

                    menu_logic.set(visuals.watermark.position, true)
                end

                local is_indicators = visuals.indicators.enabled:get() do
                    menu_logic.set(visuals.indicators.enabled, true)

                    if is_indicators then
                        menu_logic.set(visuals.indicators.style, true)

                        menu_logic.set(visuals.indicators.color_accent, true)
                        menu_logic.set(visuals.indicators.color_secondary, true)

                        menu_logic.set(visuals.indicators.offset, true)
                    end
                end

                local is_damage_indicator = visuals.damage_indicator.enabled:get() do
                    menu_logic.set(visuals.damage_indicator.enabled, true)
                    menu_logic.set(visuals.damage_indicator.color, true)

                    if is_damage_indicator then
                        menu_logic.set(visuals.damage_indicator.font, true)
                        menu_logic.set(visuals.damage_indicator.display, true)
                        menu_logic.set(visuals.damage_indicator.animation, true)
                    end
                end

                local is_manual_arrows = visuals.manual_arrows.enabled:get() do
                    menu_logic.set(visuals.manual_arrows.enabled, true)

                    if is_manual_arrows then
                        menu_logic.set(visuals.manual_arrows.style, true)

                        menu_logic.set(visuals.manual_arrows.color_accent, true)

                        if visuals.manual_arrows.style:get() == 'Alternative' then
                            menu_logic.set(visuals.manual_arrows.color_secondary, true)
                        end
                    end
                end

                local is_velocity_warning = visuals.velocity_warning.enabled:get() do
                    menu_logic.set(visuals.velocity_warning.enabled, true)
                    menu_logic.set(visuals.velocity_warning.color, true)

                    if is_velocity_warning then
                        menu_logic.set(visuals.velocity_warning.offset, true)
                    end
                end

                menu_logic.set(visuals.debug_panel.enabled, true)
                menu_logic.set(visuals.debug_panel.color, true)

                local is_bomb_indicator = visuals.bomb_indicator.enabled:get() do
                    menu_logic.set(visuals.bomb_indicator.enabled, true)

                    if is_bomb_indicator then
                        menu_logic.set(visuals.bomb_indicator.good_label, true)
                        menu_logic.set(visuals.bomb_indicator.good_color, true)

                        menu_logic.set(visuals.bomb_indicator.bad_label, true)
                        menu_logic.set(visuals.bomb_indicator.bad_color, true)
                    end
                end

                local is_gamesense_indicator = visuals.gamesense_indicator.enabled:get() do
                    menu_logic.set(visuals.gamesense_indicator.enabled, true)

                    if is_gamesense_indicator then
                        menu_logic.set(visuals.gamesense_indicator.follow_in_thirdperson, true)
                        menu_logic.set(visuals.gamesense_indicator.listbox, true)

                        local selected = visuals.gamesense_indicator.names[
                            (visuals.gamesense_indicator.listbox:get() or 0) + 1
                        ]

                        if selected ~= nil then
                            local items = visuals.gamesense_indicator[selected]

                            if items ~= nil then
                                menu_logic.set(items.enabled, true)

                                if items.enabled:get() then
                                    menu_logic.set(items.custom_name, true)

                                    menu_logic.set(items.change_color, true)
                                    menu_logic.set(items.color_picker, true)
                                end
                            end
                        end
                    end
                end

                local is_bullet_tracers = visuals.bullet_tracers.enabled:get() do
                    menu_logic.set(visuals.bullet_tracers.enabled, true)
                    menu_logic.set(visuals.bullet_tracers.color, true)

                    if is_bullet_tracers then
                        menu_logic.set(visuals.bullet_tracers.duration, true)
                    end
                end
            end

            if category == '\u{E115}  Misc' then
                menu_logic.set(misc.clantag.enabled, true)
                menu_logic.set(misc.trashtalk.enabled, true)

                menu_logic.set(misc.fast_ladder.enabled, true)

                local is_animation_breaker = misc.animation_breaker.enabled:get() do
                    menu_logic.set(misc.animation_breaker.enabled, true)

                    if is_animation_breaker then
                        menu_logic.set(misc.animation_breaker.in_air_legs, true)

                        if misc.animation_breaker.in_air_legs:get() == 'Static' then
                            menu_logic.set(misc.animation_breaker.in_air_static_value, true)
                        end

                        menu_logic.set(misc.animation_breaker.onground_legs, true)

                        if misc.animation_breaker.onground_legs:get() == 'Jitter' then
                            menu_logic.set(misc.animation_breaker.onground_jitter_min_value, true)
                            menu_logic.set(misc.animation_breaker.onground_jitter_max_value, true)
                        end

                        menu_logic.set(misc.animation_breaker.adjust_lean, true)
                        menu_logic.set(misc.animation_breaker.pitch_on_land, true)
                        --menu_logic.set(misc.animation_breaker.old_desync, true)
                        menu_logic.set(misc.animation_breaker.earthquake, true)

                        if misc.animation_breaker.earthquake:get() then
                            menu_logic.set(misc.animation_breaker.earthquake_value, true)
                        end
                    end
                end

                menu_logic.set(misc.walking_on_quick_peek.enabled, true)
            end
        end

        local function on_shutdown()
            set_antiaimbot_angles(true)
            set_antiaimbot_fakelag(true)
        end

        local function on_paint_ui()
            set_antiaimbot_angles(false)
            set_antiaimbot_fakelag(false)
        end

        local logic_events = menu_logic.get_event_bus() do
            logic_events.update:set(force_update_scene)

            force_update_scene()
            menu_logic.force_update()
        end

        client.set_event_callback('shutdown', on_shutdown)
        client.set_event_callback('paint_ui', on_paint_ui)
    end
end

local override do
    override = { }

    local item_data = { }

    local e_hotkey_mode = {
        [0] = 'Always on',
        [1] = 'On hotkey',
        [2] = 'Toggle',
        [3] = 'Off hotkey'
    }

    local function get_value(item)
        local type = ui.type(item)
        local value = { ui.get(item) }

        if type == 'hotkey' then
            local mode = e_hotkey_mode[value[2]]
            local keycode = value[3] or 0

            return { mode, keycode }
        end

        return value
    end

    function override.get(item)
        local value = item_data[item]

        if value == nil then
            return nil
        end

        return unpack(value)
    end

    function override.set(item, ...)
        if item_data[item] == nil then
            item_data[item] = get_value(item)
        end

        ui.set(item, ...)
    end

    function override.unset(item)
        local value = item_data[item]

        if value == nil then
            return
        end

        ui.set(item, unpack(value))
        item_data[item] = nil
    end
end

local ragebot do
    ragebot = { }

    local item_data = { }

    local ref_weapon_type = ui.reference(
        'Rage', 'Weapon type', 'Weapon type'
    )

    local e_hotkey_mode = {
        [0] = 'Always on',
        [1] = 'On hotkey',
        [2] = 'Toggle',
        [3] = 'Off hotkey'
    }

    local function get_value(item)
        local type = ui.type(item)
        local value = { ui.get(item) }

        if type == 'hotkey' then
            local mode = e_hotkey_mode[value[2]]
            local keycode = value[3] or 0

            return { mode, keycode }
        end

        return value
    end

    function ragebot.set(item, ...)
        local weapon_type = ui.get(ref_weapon_type)

        if item_data[item] == nil then
            item_data[item] = { }
        end

        local data = item_data[item]

        if data[weapon_type] == nil then
            data[weapon_type] = {
                type = weapon_type,
                value = get_value(item)
            }
        end

        ui.set(item, ...)
    end

    function ragebot.unset(item)
        local data = item_data[item]

        if data == nil then
            return
        end

        local weapon_type = ui.get(ref_weapon_type)

        for k, v in pairs(data) do
            ui.set(ref_weapon_type, v.type)
            ui.set(item, unpack(v.value))

            data[k] = nil
        end

        ui.set(ref_weapon_type, weapon_type)
        item_data[item] = nil
    end
end

local motion do
    motion = { }

    local function linear(t, b, c, d)
        return c * t / d + b
    end

    local function get_deltatime()
        return globals.frametime()
    end

    local function solve(easing_fn, prev, new, clock, duration)
        if clock <= 0 then return new end
        if clock >= duration then return new end

        prev = easing_fn(clock, prev, new - prev, duration)

        if type(prev) == 'number' then
            if math.abs(new - prev) < 0.001 then
                return new
            end

            local remainder = prev % 1.0

            if remainder < 0.001 then
                return math.floor(prev)
            end

            if remainder > 0.999 then
                return math.ceil(prev)
            end
        end

        return prev
    end

    function motion.interp(a, b, t, easing_fn)
        easing_fn = easing_fn or linear

        if type(b) == 'boolean' then
            b = b and 1 or 0
        end

        return solve(easing_fn, a, b, get_deltatime(), t)
    end
end

local render do
    render = { }

    local function sign(x)
        if x > 0 then
            return 1
        end

        if x < 0 then
            return -1
        end

        return 0
    end

    local function interpolate_colors(color1, color2, factor)
        local temp_array, temp_array_count = { }, 1
        local color3 = { color1[1], color1[2], color1[3], color1[4] }

        for i = 1, 4 do
            temp_array[temp_array_count] = tonumber(('%.0f'):format(
                color3[i] + factor * (color2[i] - color1[i])
            ))

            temp_array_count = temp_array_count + 1
        end

        return temp_array
    end

    local function interpolate_colors_range(color1, color2, steps)
        local factor = 1 / (steps - 1)
        local temp_array, temp_array_count = { }, 1

        for i = 0, steps-1 do
            temp_array[temp_array_count] = interpolate_colors(color1, color2, factor*i)
            temp_array_count = temp_array_count + 1
        end

        return temp_array
    end

    function render.glow(x, y, w, h, r, g, b, a, radius, steps, range)
        steps = math.max(2, steps)
        range = range or 1.0

        local outline_thickness = 1

        local colors = interpolate_colors_range(
            { r, g, b, 0 },
            { r, g, b, a * range },
            steps
        )

        for i = 1, steps do
            renderer.circle_outline(x + radius, y + radius, colors[i][1], colors[i][2], colors[i][3], colors[i][4], radius+outline_thickness+(steps-i), 180, 0.25, 1)
            renderer.circle_outline(x + w - radius, y + radius, colors[i][1], colors[i][2], colors[i][3], colors[i][4], radius+outline_thickness+(steps-i), 270, 0.25, 1)
            renderer.circle_outline(x + w - radius, y + h - radius, colors[i][1], colors[i][2], colors[i][3], colors[i][4], radius+outline_thickness+(steps-i), 0, 0.25, 1)
            renderer.circle_outline(x + radius, y + h - radius, colors[i][1], colors[i][2], colors[i][3], colors[i][4], radius+outline_thickness+(steps-i), 90, 0.25, 1)

            renderer.rectangle(x + w + i - 1, y + radius, 1, h - 2 * radius, colors[steps-i+1][1], colors[steps-i+1][2], colors[steps-i+1][3], colors[steps-i+1][4])
            renderer.rectangle(x - i, y + radius, 1, h - 2 * radius, colors[steps-i+1][1], colors[steps-i+1][2], colors[steps-i+1][3], colors[steps-i+1][4])

            renderer.rectangle(x + radius, y - i, w - 2 * radius, 1, colors[steps-i+1][1], colors[steps-i+1][2], colors[steps-i+1][3], colors[steps-i+1][4])
            renderer.rectangle(x + radius, y + h + i - 1, w - 2 * radius, 1, colors[steps-i+1][1], colors[steps-i+1][2], colors[steps-i+1][3], colors[steps-i+1][4])
        end
    end

    function render.rectangle_outline(x, y, w, h, r, g, b, a, thickness, radius)
        if thickness == nil or thickness == 0 then
            thickness = 1
        end

        if radius == nil then
            radius = 0
        end

        local wt = sign(w) * thickness
        local ht = sign(h) * thickness

        local pad = radius == 1 and 1 or 0

        local pad_2 = pad * 2
        local radius_2 = radius * 2

        renderer.circle_outline(x + radius, y + radius, r, g, b, a, radius, 180, 0.25, thickness)
        renderer.circle_outline(x + radius, y + h - radius, r, g, b, a, radius, 90, 0.25, thickness)
        renderer.circle_outline(x + w - radius, y + radius, r, g, b, a, radius, 270, 0.25, thickness)
        renderer.circle_outline(x + w - radius, y + h - radius, r, g, b, a, radius, 0, 0.25, thickness)

        renderer.rectangle(x, y + radius, wt, h - radius_2, r, g, b, a)
        renderer.rectangle(x + w, y + radius, -wt, h - radius_2, r, g, b, a)

        renderer.rectangle(x + pad + radius, y, w - pad_2 - radius_2, ht, r, g, b, a)
        renderer.rectangle(x + pad + radius, y + h, w - pad_2 - radius_2, -ht, r, g, b, a)
    end

    function render.rectangle(x, y, w, h, r, g, b, a, radius)
        radius = math.min(radius, w / 2, h / 2)

        local radius_2 = radius * 2

        renderer.rectangle(x + radius, y, w - radius_2, h, r, g, b, a)
        renderer.rectangle(x, y + radius, radius, h - radius_2, r, g, b, a)
        renderer.rectangle(x + w - radius, y + radius, radius, h - radius_2, r, g, b, a)

        renderer.circle(x + radius, y + radius, r, g, b, a, radius, 180, 0.25)
        renderer.circle(x + radius, y + h - radius, r, g, b, a, radius, 270, 0.25)
        renderer.circle(x + w - radius, y + radius, r, g, b, a, radius, 90, 0.25)
        renderer.circle(x + w - radius, y + h - radius, r, g, b, a, radius, 0, 0.25)
    end

    function render.modern_box(x, y, w, h, r, g, b, a, radius, thickness)
        radius = math.max(0, radius or 0)

        renderer.rectangle(x + radius, y, w - radius * 2, thickness, r, g, b, a)

        renderer.gradient(x, y + radius, thickness, h - radius * 2, r, g, b, a, r, g, b, 0, false)
        renderer.gradient(x + w - thickness, y + radius, thickness, h - radius * 2, r, g, b, a, r, g, b, 0, false)

        if radius > 0 then
            renderer.circle_outline(x + radius, y + radius, r, g, b, a, radius, 180, 0.25, thickness)
            renderer.circle_outline(x + w - radius, y + radius, r, g, b, a, radius, 270, 0.25, thickness)
        end
    end
end

local features do
    local rage do
        rage = { }

        local ai_peek do
            local ref = ref.ragebot.ai_peek

            local FLAG_BREAK_LC = bit.lshift(2, 16)

            local ref_quick_peek_assist = { ui.reference('RAGE', 'Other', 'Quick peek assist') }

            local ref_minimum_damage = { ui.reference('RAGE', 'Aimbot', 'Minimum damage') }
            local ref_minimum_damage_override = { ui.reference('RAGE', 'Aimbot', 'Minimum damage override') }

            -- god forbid this hardcode shit please dont send me into hell ????
            local tick_to_distance = {
                0,
                0.33566926072059,
                0.90550823109139,
                1.7094571925458,
                2.7475758645732,
                4.0198045277169,
                5.5243356897069,
                7.2423273783409,
                9.1564213090631,
                11.250673856852,
                13.510480438002,
                15.922361837797,
                18.473989413581,
                21.153990043142,
                23.951936812474,
                26.858254779359,
                29.864120158319,
                32.961441695549,
                36.142785057665,
                39.401338315411,
                42.730817707458,
                46.125502156263,
                49.580063421207,
                53.08964170921,
                56.649735547569,
                60.256252190999,
                63.905432011078,
                67.59383918326,
                71.318242246617,
                75.075708340563,
                78.863628408227,
                82.67942790961,
                86.520915828495,
                90.385926351936,
                94.272651987509,
                98.17890171902,
                102.08515145053,
                105.99140118205,
                109.89765091356,
                113.80390064508,
                117.7101503766,
                121.61640010812,
                125.52264983965,
                129.42889957117,
                133.3351493027,
                137.24139903422,
                141.14764876575,
                145.05389849727,
                148.9601482288,
                152.86639796033,
                156.77264769186,
                160.67889742339,
                164.58514715492,
                168.49139688645,
                172.39764661798,
                176.30389634951,
                180.21014608104,
                184.11639581258,
                188.02264554411,
                191.92889527564,
                195.83514500718,
                199.74139473871,
                203.64764447024,
                207.55389420178,
            }

            local enemy_lc_data = { }
            local debug_visuals = { }

            local visuals = {
                found_point = nil,
                peeking_points = { }
            }

            local e_hitboxes = {
                ['head']    = 1,
                ['stomach'] = 2,
                ['chest']   = 3,
                ['limbs']   = 4
            }

            local hitboxes = {
                { 0 },
                { 2, 3, 4 },
                { 5, 6 },
                {
                    13, 14, 15, 16, 17, 18, -- arms
                    7, 8, 9, 10, -- legs
                    11, 1, -- feet
                },
            }

            local cache = {
                last_seen = 0,
                autopeek_position = vector( 0, 0, 0 ),
                found_position = vector( 0, 0, 0 ),
                found_position_dist = 1,
            }

            local closest_enemy = nil

            local function create_new_record(player)
                local data = { }

                data.player = player

                data.origin = vector(
                    entity.get_origin(player)
                )

                data.breaking_lc = false
                data.last_simtime = 0

                data.defensive = false
                data.defensive_active_until = 0

                function data.update()
                    local esp_data = entity.get_esp_data(data.player)
                    local esp_flags = esp_data.flags

                    local origin = vector(
                        entity.get_origin(player)
                    )

                    local simtime = toticks(
                        entity.get_prop(player, 'm_flSimulationTime')
                    )

                    local delta_simtime = simtime - data.last_simtime
                    data.defensive = bit.band(esp_flags, FLAG_BREAK_LC) ~= 0

                    if delta_simtime < 0 then
                        data.defensive_active_until = globals.tickcount() + math.abs(delta_simtime)
                    else
                        local delta_origin = origin - data.origin
                        local delta_lengthsqr = delta_origin:length2dsqr()

                        data.breaking_lc = delta_lengthsqr > 4096
                        data.origin = origin
                    end

                    data.last_simtime = simtime
                end

                enemy_lc_data[player] = data

                return data
            end

            local function can_hit_in_x_ticks(wanted_pos_distance, max_speed, ticks)
                local distance_mult = max_speed / 250

                local wanted_distance = wanted_pos_distance * distance_mult
                local max_distance = tick_to_distance[ticks] * distance_mult

                return wanted_distance <= max_distance
            end

            local function debug_visualize(positions, name)
                if type(positions) ~= 'table' then
                    positions = { positions }
                end

                debug_visuals[name] = positions
            end

            local function set_visual_peeking_points(points)
                visuals.peeking_points = points
            end

            local function get_min_dmg()
                if ui.get(ref_minimum_damage_override[1]) and ui.get(ref_minimum_damage_override[2]) then
                    return ui.get(ref_minimum_damage_override[3])
                end

                return ui.get(ref_minimum_damage[1])
            end

            local function reset_cache()
                cache.last_seen = 0
                cache.found_position = vector(0, 0, 0)
            end

            local function is_mp_available( )
                return ref.mode:get() == 'Advanced'
            end

            local function get_closest_enemy()
                local screen_center = vector(client.screen_size()) / 2

                local smallest_distance = math.huge
                local closest_enemy_found = nil

                local enemies = entity.get_players(true)

                for i = 1, #enemies do
                    local enemy = enemies[i]

                    if enemy == nil then
                        goto continue
                    end

                    --* only check for enemies that are alive and not dormant
                    if not entity.is_alive(enemy) or entity.is_dormant(enemy) then
                        goto continue
                    end

                    local enemy_position = vector(
                        entity.get_prop(enemy, 'm_vecOrigin')
                    )

                    local x, y = renderer.world_to_screen(
                        enemy_position:unpack()
                    )

                    local enemy_screen = vector(x, y, 0)

                    if enemy_screen.x == nil or enemy_screen.y == nil then
                        goto continue
                    end

                    local distance = (enemy_screen - screen_center):length()

                    if distance < smallest_distance then
                        smallest_distance = distance
                        closest_enemy_found = enemy
                    end

                    ::continue::
                end

                closest_enemy = closest_enemy_found
            end

            local function get_multipoint(ent, hitbox_center, scale)
                local me = entity.get_local_player()

                local me_pos = vector(entity.get_prop(me, 'm_vecOrigin'))
                local target_pos = vector(entity.get_prop(ent, 'm_vecOrigin'))

                local delta = target_pos - me_pos
                local angles = vector(delta:angles())

                local max_check_dist = 5
                local mp_poses = { }

                for side = -1, 1, 2 do
                    local rad = math.rad(
                        angles.y + (90 * side)
                    )

                    local x = math.cos(rad)
                    local y = math.sin(rad)

                    local mp_start = hitbox_center + vector(
                        x * max_check_dist, y * max_check_dist
                    )

                    local diff = hitbox_center - mp_start

                    local frac = client.trace_line(
                        me, mp_start.x, mp_start.y, mp_start.z,
                        hitbox_center.x, hitbox_center.y, hitbox_center.z
                    )

                    local mp_pos = hitbox_center + (diff * (1 - frac)) * scale

                    table.insert(mp_poses, mp_pos)
                end

                return mp_poses
            end

            local function get_head_multipoint(ent, hitbox_center, scale)
                local me = entity.get_local_player()

                local side_mp = get_multipoint(
                    ent, hitbox_center, scale
                )

                local max_check_dist = -5

                local mp_start = hitbox_center + vector(0, 0, max_check_dist)
                local diff = hitbox_center - mp_start

                local frac = client.trace_line(
                    me, mp_start.x, mp_start.y, mp_start.z,
                    hitbox_center.x, hitbox_center.y, hitbox_center.z
                )

                local mp_pos = hitbox_center + (diff * (1 - frac)) * scale
                table.insert(side_mp, mp_pos)

                return side_mp
            end

            local function get_player_points(player)
                local points = { }

                local extra_calc = is_mp_available()

                local find = {
                    head = true,
                    chest = true,
                    stomach = true,
                    limbs = extra_calc and ref.target_limbs:get()
                }

                local mp = {
                    head = extra_calc,
                    chest = extra_calc,
                    stomach = extra_calc,
                    limbs = false
                }

                local mp_scale = {
                    head = ref.mp_scale_head:get() / 100,
                    chest = ref.mp_scale_chest:get() / 100,
                    stomach = ref.mp_scale_chest:get() / 100,
                    limbs = 0
                }

                if find.head then
                    local head_hitboxes = hitboxes[e_hitboxes['head']]

                    for i = 1, #head_hitboxes do
                        local head = vector(entity.hitbox_position(player, head_hitboxes[i]))

                        if not mp.head then
                            table.insert(points, head)
                        else
                            local multipoints = get_head_multipoint(player, head, mp_scale.head)

                            for mp_idx = 1, #multipoints do
                                table.insert(points, multipoints[mp_idx])
                            end
                        end
                    end
                end

                if find.chest then
                    local chest_hitboxes = hitboxes[e_hitboxes['chest']]
                    for i = 1, #chest_hitboxes do
                        local chest = vector(entity.hitbox_position(player, chest_hitboxes[i]))

                        if not mp.chest then
                            table.insert(points, chest)
                        else
                            local multipoints = get_multipoint(player, chest, mp_scale.chest)

                            for mp_idx = 1, #multipoints do
                                table.insert(points, multipoints[mp_idx])
                            end
                        end
                    end
                end

                if find.stomach then
                    local stomach_hitboxes = hitboxes[e_hitboxes['stomach']]

                    for i = 1, #stomach_hitboxes do
                        local stomach = vector(entity.hitbox_position(player, stomach_hitboxes[i]))

                        if not mp.stomach then
                            table.insert(points, stomach)
                        else
                            local multipoints = get_multipoint(player, stomach, mp_scale.stomach)

                            for mp_idx = 1, #multipoints do
                                table.insert(points, multipoints[mp_idx])
                            end
                        end
                    end
                end

                if find.limbs then
                    local limbs_hitboxes = hitboxes[e_hitboxes['limbs']]

                    for i = 1, #limbs_hitboxes do
                        local limb = vector(entity.hitbox_position(player, limbs_hitboxes[i]))
                        table.insert(points, limb)
                    end
                end

                return points
            end

            local function get_peeking_points(me)
                local me_origin = vector(entity.get_prop(me, 'm_vecOrigin'))
                local me_eye_pos = vector(client.eye_position())

                local _, yaw = client.camera_angles()
                local head_height = me_eye_pos.z - me_origin.z

                local start_offset = ref.dot_offset:get()
                local dots = ref.dot_amount:get()
                local total_distance = ref.dot_span:get()
                local gap = total_distance / dots

                local dot_positions = { }

                for i = -1, 1, 2 do
                    local dot_yaw = yaw + (90 * i)
                    local yaw_rad = math.rad(dot_yaw)

                    local forwardvector = vector(math.cos(yaw_rad), math.sin(yaw_rad), 0)

                    for dot_iter = 1, dots do
                        local dot_position = me_eye_pos + (forwardvector * (gap * dot_iter)) + (forwardvector * start_offset)
                        local trace_res = trace.line(dot_position, dot_position + vector(0, 0, -200), { mask = 'MASK_SOLID_BRUSHONLY' })
                        local trace_fraction = trace_res.fraction

                        if trace_fraction < 1 then
                            local end_pos = trace_res.end_pos + vector(0, 0, head_height)
                            if (end_pos.z - me_origin.z) > 40 then
                                dot_iter = dots
                            end
                            dot_position = end_pos
                        end

                        local trace_res = trace.line(me_eye_pos, dot_position, { skip = entity.get_players(), mask = 'MASK_SOLID' })
                        if trace_res.fraction == 1 then
                            table.insert(dot_positions, dot_position)
                        else
                            local last_dot_pos = me_eye_pos + ((forwardvector * (gap * dot_iter)) + (forwardvector * start_offset)) * trace_res.fraction - forwardvector * 19
                            last_dot_pos.z = dot_position.z
                            table.insert(dot_positions, last_dot_pos)
                            break
                        end
                    end
                end

                return dot_positions
            end

            local function can_hit_from_positions(lp, positions, target, target_hitpoints)
                local minimum_damage = get_min_dmg()

                for i = 1, #positions do
                    local position = positions[i]
                    visuals.found_point = i

                    for j = 1, #target_hitpoints do
                        local hitpoint = target_hitpoints[j]
                        local hit_entity, simulated_dmg = client.trace_bullet(lp, position.x, position.y, position.z, hitpoint.x, hitpoint.y, hitpoint.z, false)
                        local hit_player_name = entity.get_player_name(hit_entity)
                        local target_health = entity.get_prop(hit_entity, 'm_iHealth')

                        if hit_entity == target then
                            local wanted_dmg = minimum_damage

                            if minimum_damage > 100 then
                                wanted_dmg = target_health + (minimum_damage - 100)
                            end

                            if simulated_dmg >= target_health or simulated_dmg > wanted_dmg then
                                cache.found_position = position
                                cache.found_position_dist = (cache.autopeek_position - cache.found_position):length2d()

                                client.log(string.format(
                                    '[serene ai] peeking %s(%i) for sim: %i',
                                    hit_player_name, hit_entity, simulated_dmg
                                ))

                                return true
                            end
                        elseif hit_entity ~= nil and entity.is_alive(hit_entity) then
                            local wanted_dmg = minimum_damage

                            if minimum_damage > 100 then
                                wanted_dmg = target_health + (minimum_damage - 100)
                            end

                            if simulated_dmg >= target_health or simulated_dmg > wanted_dmg then
                                cache.found_position = position

                                client.log(string.format(
                                    '[serene ai] peeking %s(%i)[NON-TARGET!] for sim: %i',
                                    hit_player_name, hit_entity, simulated_dmg
                                ))

                                return true
                            end
                        end
                    end
                end

                visuals.found_point = nil
                return false
            end

            local function ready_to_shoot(lp, cmd)
                local slowdown = entity.get_prop(lp, 'm_flVelocityModifier') < 0.9
                local has_user_input = cmd.in_moveleft == 1 or cmd.in_moveright == 1 or cmd.in_back == 1 or cmd.in_forward == 1 or cmd.in_jump == 1
                local wep = entity.get_player_weapon(entity.get_local_player())

                local next_shot_ready = false

                if wep ~= nil then
                    local reloading = entity.get_prop(wep, 'm_bInReload') == 1
                    local next_attack_ready = entity.get_prop(wep, 'm_flNextPrimaryAttack') < globals.curtime()

                    if not reloading and next_attack_ready then
                        next_shot_ready = true
                    end
                end

                local can_normally_shoot = next_shot_ready

                return not ((slowdown or has_user_input or not next_shot_ready) and not can_normally_shoot)
            end

            local function move_to_pos(cmd, lp, lp_pos, new_pos)
                local distance = lp_pos:dist(new_pos) + 5
                local unit_vec = (new_pos - lp_pos):normalized()

                new_pos = lp_pos + unit_vec * (distance + 5)

                if cmd.forwardmove == 0 and cmd.sidemove == 0 and cmd.in_forward == 0 and cmd.in_back == 0 and cmd.in_moveleft == 0 and cmd.in_moveright == 0 then
                    if distance >= 0.5 then
                        local fwd1 = new_pos - lp_pos
                        local pos1 = new_pos + fwd1:normalized()*10
                        local fwd = pos1 - lp_pos
                        local pitch, yaw = fwd:angles()

                        if yaw == nil then
                            return
                        end

                        cmd.move_yaw = yaw
                        cmd.in_speed = 0

                        cmd.in_moveleft, cmd.in_moveright = 0, 0
                        cmd.sidemove = 0

                        if distance > 8 then
                            cmd.forwardmove = 450
                        else
                            local wishspeed = math.min(450, math.max(1.1+entity.get_prop(lp, "m_flDuckAmount") * 10, distance * 9))
                            local vel = vector(entity.get_prop(lp, "m_vecAbsVelocity")):length2d()
                            if vel >= math.min(250, wishspeed)+15 then
                                cmd.forwardmove = 0
                                cmd.in_forward = 0
                            else
                                cmd.forwardmove = math.max(6, vel >= math.min(250, wishspeed) and wishspeed * 0.9 or wishspeed)
                                cmd.in_forward = 1
                            end
                        end
                    end
                end
            end

            local function handle_peek(cmd)
                local lp = entity.get_local_player()
                local lp_pos = vector(client.eye_position())

                cache.found_position.z = lp_pos.z

                move_to_pos(cmd, lp, lp_pos, cache.found_position)
            end

            local function handle_retreat(cmd)
                local lp = entity.get_local_player()
                local lp_pos = vector(client.eye_position())

                move_to_pos(cmd, lp, lp_pos, cache.autopeek_position)
            end

            local function is_doubletap_charged()
                local m_nTickBase = entity.get_prop(entity.get_local_player(), 'm_nTickBase')
                local client_latency = client.latency()
                local shift = math.floor(m_nTickBase - globals.tickcount() - 3 - toticks(client_latency) * .5 + .7 * (client_latency * 10))

                local wanted = -11

                return shift <= wanted
            end

            local debug = {
                state = 'disabled',
                step = 0,
                visual_step = 0,
            }

            local function set_state(new_state)
                debug.state = new_state
            end

            local e_visual_steps = {
                IDLE = 0,
                FINDING_TARGET = 1,
                SEARCHING_HITPOINTS = 2,
                CHECKING_HITPOINTS = 3,
                PEEKING = 4,
                RETREATING = 5,
                WAITING_FOR_SHOT = 6,
                NO_ENEMIES = 7,
                DT_NOT_CHARGED = 8,
            }

            local visual_texts = {
                [ e_visual_steps.IDLE ] = 'freezed',
                [ e_visual_steps.FINDING_TARGET ] = 'waiting',
                [ e_visual_steps.SEARCHING_HITPOINTS ] = 'waiting',
                [ e_visual_steps.CHECKING_HITPOINTS ] = 'ensuring hitpoints',
                [ e_visual_steps.PEEKING ] = 'peeking',
                [ e_visual_steps.RETREATING ] = 'waiting',
                [ e_visual_steps.WAITING_FOR_SHOT ] = 'waiting for shot',
                [ e_visual_steps.NO_ENEMIES ] = 'waiting',
                [ e_visual_steps.DT_NOT_CHARGED ] = '[!] dt not fully charged [!]',
            }

            local e_steps = {
                IDLE = 0,
                FINDING_TARGET = 1,
                SEARCHING_HITPOINTS = 2,
                CHECKING_HITPOINTS = 3,
                PEEKING = 4,
                RETREATING = 5,
            }

            local function set_step(step)
                debug.step = step
            end

            local function set_visual_step(step)
                debug.visual_step = step
            end

            local peeking_points = { }

            local function gpt_peek( cmd )
                local me = entity.get_local_player()

                if me == nil then
                    return
                end

                local pos = vector(entity.get_prop(me, 'm_vecOrigin'))
                local autopeek_state = ui.get(ref_quick_peek_assist[2])

                if not autopeek_state then
                    cache.autopeek_position = pos
                    peeking_points = get_peeking_points(me)

                    reset_cache()
                    set_state('disabled')
                    set_step(e_steps.IDLE)
                    set_visual_step(e_visual_steps.IDLE)

                    return
                end

                set_visual_peeking_points(peeking_points)
                set_state('idle')

                local distance = (cache.autopeek_position - cache.found_position):length2d()

                local can_run = can_hit_in_x_ticks(distance, 250, 24)
                local can_shoot = ready_to_shoot(me, cmd)

                if (cache.last_seen + 24) >= globals.tickcount() and can_run and can_shoot then
                    handle_peek(cmd)
                    set_state('peeking')
                    set_step(e_steps.PEEKING)
                    set_visual_step(e_visual_steps.PEEKING)
                    return
                end

                if ( cache.autopeek_position - pos ):length2d( ) > 5 then
                    handle_retreat(cmd)
                    set_state('retreating')

                    set_step(e_steps.RETREATING)
                    set_visual_step(e_visual_steps.RETREATING)

                    return
                end

                if not can_shoot then
                    set_step(e_steps.IDLE)
                    set_visual_step(e_visual_steps.WAITING_FOR_SHOT)

                    return
                end

                local targets = { closest_enemy }

                if next(targets) == nil then
                    reset_cache()

                    set_state('idle')
                    set_step(e_steps.IDLE)
                    set_visual_step(e_visual_steps.NO_ENEMIES)

                    return
                end

                if can_shoot then
                    set_step(e_steps.FINDING_TARGET)
                    set_visual_step(e_visual_steps.FINDING_TARGET)
                end

                local g_can_hit = false
                local g_can_peek = false

                for idx = 1, #targets do
                    local target = targets[idx]

                    if not entity.is_alive(target) or entity.is_dormant(target) then
                        goto continue
                    end

                    local target_data = enemy_lc_data[target]

                    if target_data == nil then
                        target_data = create_new_record(target)
                    end

                    target_data.update()

                    local is_lc = target_data.breaking_lc
                    local is_defensive =  target_data.defensive
                    local can_peek = not is_lc and not is_defensive

                    local hitpoints = get_player_points(target)
                    debug_visualize(hitpoints, target)

                    set_step(e_steps.SEARCHING_HITPOINTS)
                    set_visual_step(e_visual_steps.SEARCHING_HITPOINTS)


                    if not can_peek then
                        set_step(e_steps.CHECKING_HITPOINTS)
                        set_visual_step(e_visual_steps.CHECKING_HITPOINTS)

                        goto continue
                    end

                    local can_hit = can_hit_from_positions(
                        me, peeking_points, target, hitpoints
                    )

                    if can_hit then
                        g_can_hit = true
                        g_can_peek = true

                        break
                    end

                    ::continue::
                end

                local dt_charged = is_doubletap_charged()

                if not dt_charged then
                    set_step(e_steps.FINDING_TARGET)
                    set_visual_step(e_visual_steps.DT_NOT_CHARGED)
                end

                if g_can_hit and g_can_peek and dt_charged then
                    cache.last_seen = globals.tickcount()
                elseif not g_can_peek and not dt_charged then
                    set_state('can\'t peek')
                elseif not dt_charged then
                    set_state('dt not charged')
                end
            end

            local visual_progressbar = {
                lerped_pos = vector( 0, 0, 0 ),
                gap = 30,
                radius = 5,
                pad = vector( 3, 2, 0 )
            }

            local func = {
                RGBAtoHEX = function(redArg, greenArg, blueArg, alphaArg)
                    return string.format('%.2x%.2x%.2x%.2x', redArg, greenArg, blueArg, alphaArg)
                end,
            }

            local animate_text = function(time, string, r, g, b, a)
                local t_out, t_out_iter = { }, 1

                local mainClr = { }

                mainClr.r, mainClr.g, mainClr.b, mainClr.a = ref.indicators_color:get()

                local r_add = (mainClr.r - r)
                local g_add = (mainClr.g - g)
                local b_add = (mainClr.b - b)
                local a_add = (mainClr.a - a)

                for i = 1, #string do
                    local iter = (i - 1) / (#string - 1) + time

                    t_out[t_out_iter] = '\a' .. func.RGBAtoHEX( r + r_add * math.abs(math.cos( iter )), g + g_add * math.abs(math.cos( iter )), b + b_add * math.abs(math.cos( iter )), a + a_add * math.abs(math.cos( iter )) )
                    t_out[t_out_iter + 1] = string:sub( i, i )

                    t_out_iter = t_out_iter + 2
                end

                return t_out
            end

            local function render_screen_bar()
                local lp = entity.get_local_player()
                if not lp then return end

                for target, tbl in pairs(debug_visuals) do
                    if entity.is_alive(target) and not entity.is_dormant(target) then
                        for i = 1, #tbl do
                            local position = tbl[i]
                            local s_x, s_y = renderer.world_to_screen(position.x, position.y, position.z)
                            if s_x ~= nil and s_y ~= nil then
                                renderer.circle(s_x, s_y, 255, 255, 255, 150, 2, 0, 1)
                            end
                        end
                    end
                end

                local step = debug.step
                if step == e_steps.RETREATING then
                    set_step(e_steps.IDLE)
                    step = debug.step
                end

                local screen = { client.screen_size() }
                screen = vector(screen[1] / 2, screen[2] - 100, 0)

                local active_pos = vector(screen.x + ((step - 2) * visual_progressbar.gap), screen.y, 0)

                if visual_progressbar.lerped_pos.x == 0 then
                    visual_progressbar.lerped_pos = active_pos
                end

                visual_progressbar.lerped_pos = visual_progressbar.lerped_pos:lerp(active_pos, 0.1)
                visual_progressbar.x = visual_progressbar.lerped_pos.x + visual_progressbar.radius * 2

                local lp_pos = vector(entity.get_prop(lp, 'm_vecOrigin'))
                local dist_to_point = (lp_pos - cache.found_position):length2d()
                local progress_to_point = (cache.found_position_dist - dist_to_point) / cache.found_position_dist

                if progress_to_point < 0 then
                    progress_to_point = 0
                end

                if progress_to_point > 1 then
                    progress_to_point = 1
                end

                local screen = vector(
                    client.screen_size()
                )

                for i = -2, 2, 1 do
                    local draw_step = i + 2

                    local mainClr = {}
                    mainClr.r, mainClr.g, mainClr.b, mainClr.a = 55, 55, 55, 255

                    local text = animate_text(globals.curtime(), "cd+" and visual_texts[debug.visual_step]:lower(), mainClr.r, mainClr.g, mainClr.b, 255)

                    if draw_step == debug.step then
                        renderer.text(screen.x / 2, visual_progressbar.lerped_pos.y / 2, 255, 255, 255, 255, 'cd', 0, unpack(text))
                    end
                end
            end

            local visual_points = {
                last_pressed = 0,
                last_state = false,
                animation_time = .2,
            }

            local function ease_in_back( time )
                local c1 = 1.70158
                local c3 = c1 + 1

                return c3 * time * time * time - c1 * time * time
            end

            local function render_peeking_point(pos, state)
                renderer.circle(pos.x, pos.y, 255, 255, 255, 255, 3, 0, 1)

                if state then
                    renderer.circle_outline(pos.x, pos.y, 0, 255, 0, 255, 3, 0, 1, 2)
                end
            end

            local function render_peeking_points()
                local me = entity.get_local_player()
                local preview = me and ui.is_menu_open()

                if preview then
                    visuals.peeking_points = get_peeking_points(me)
                end

                local ap_state = ui.get(ref_quick_peek_assist[2])

                if ap_state ~= visual_points.last_state then
                    visual_points.last_pressed = globals.curtime()
                    visual_points.last_state = ap_state
                end

                local diff = globals.curtime() - visual_points.last_pressed
                diff = math.min(diff, visual_points.animation_time)

                local animation_factor = ease_in_back(diff / visual_points.animation_time)

                if not ap_state then
                    animation_factor = 1 - animation_factor
                end

                if preview then
                    animation_factor = 1
                end

                if not ap_state and animation_factor <= 0.1 then return end

                local points = visuals.peeking_points

                local lp_pos = vector(entity.get_origin(me))

                for i = 1, #points do
                    local point = points[i]

                    local pos = vector(point.x, point.y, point.z)
                    local pos_diff = pos - lp_pos

                    pos_diff.x = pos_diff.x * animation_factor
                    pos_diff.y = pos_diff.y * animation_factor

                    pos = lp_pos + pos_diff

                    pos = vector(renderer.world_to_screen(pos.x, pos.y, pos.z))

                    if pos.x ~= nil and pos.y ~= nil then
                        render_peeking_point(pos, visuals.found_point == i)
                    end
                end
            end

            local function on_setup_command(cmd)
                gpt_peek(cmd)
            end

            local function on_aim_fire()
                -- reset the last_seen variable since
                -- we just shot and want to retreat
                cache.last_seen = 0
            end

            local function on_paint()
                render_peeking_points()

                if not ui.get(ref_quick_peek_assist[2]) then
                    return
                end

                get_closest_enemy()
                render_screen_bar()
            end

            local callbacks do
                local function on_enabled(item)
                    local value = item:get()

                    if not value then
                        reset_cache()
                    end

                    utils.event_callback('paint', on_paint, value)
                    utils.event_callback('aim_fire', on_aim_fire, value)
                    utils.event_callback('setup_command', on_setup_command, value)
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end

        local correction do
            correction = { }

            local info = { }

            function correction.get_player_info(player)
                return info[player]
            end

            if not locker_system.is_locked(-1) then
                local ref = ref.ragebot.correction

                local function unset_player_body_yaw(entindex)
                    plist.set(entindex, 'Force body yaw', false)
                    plist.set(entindex, 'Force body yaw value', 0)
                end

                local function set_player_body_yaw(entindex, value)
                    plist.set(entindex, 'Force body yaw', true)
                    plist.set(entindex, 'Force body yaw value', value)
                end

                local function get_enemies()
                    local player_resource = entity.get_player_resource()

                    if player_resource == nil then
                        return nil
                    end

                    local list = { }

                    for i = 1, globals.maxplayers() do
                        local is_connected = entity.get_prop(
                            player_resource, 'm_bConnected', i
                        )

                        if is_connected ~= 1 then
                            goto continue
                        end

                        local is_alive = entity.get_prop(
                            player_resource, 'm_bAlive', i
                        )

                        if not is_alive or not entity.is_enemy(i) then
                            goto continue
                        end

                        table.insert(list, i)
                        ::continue::
                    end

                    return list
                end

                local function reset_player_list()
                    local enemies = get_enemies()

                    if enemies == nil then
                        return
                    end

                    for i = 1, #enemies do
                        unset_player_body_yaw(enemies[i])
                    end
                end

                local default = { } do
                    local records = { }
                    local data_angles = { }

                    local hitgroups = {
                        [0]  = 'generic',
                        [1]  = 'head',
                        [2]  = 'chest',
                        [3]  = 'stomach',
                        [4]  = 'left arm',
                        [5]  = 'right arm',
                        [6]  = 'left leg',
                        [7]  = 'right leg',
                        [8]  = 'neck',
                        [10] = 'gear'
                    }

                    local function get_server_time(player)
                        return entity.get_prop(player, 'm_nTickBase') * globals.tickinterval()
                    end

                    local function get_simulation_time(player)
                        return entity.get_prop(player, 'm_flSimulationTime')
                    end

                    local function new_record()
                        local record = {
                            is_simtime_update = false,

                            is_jittering = false,
                            is_jittering_prev = false,

                            server_tick = 0,

                            prev_simtime = 0,
                            simtime = 0,

                            prev_eye_yaw = 0,
                            eye_angles = vector(),

                            prev_rotation = 0,
                            rotation = vector(),

                            prev_delta = 0,
                            delta = 0,

                            fakelag_ticks = 0,
                            choked_ticks = 0
                        }

                        return record
                    end

                    local function update_records(player)
                        records[player] = records[player]
                            or new_record()

                        local record = records[player]

                        local simtime = get_simulation_time(player)
                        local server_tick = get_server_time(player)

                        local rotation = vector(entity.get_prop(player, 'm_angRotation'))
                        local eye_angles = vector(entity.get_prop(player, 'm_angEyeAngles'))

                        record.server_tick = server_tick

                        record.old_simtime = record.simtime
                        record.simtime = simtime

                        record.is_simtime_update = record.simtime ~= record.old_simtime

                        if record.is_simtime_update then
                            record.fakelag_ticks = record.choked_ticks
                            record.choked_ticks = 0

                            record.prev_eye_yaw = record.eye_angles.y
                            record.eye_angles = eye_angles

                            record.prev_rotation = record.rotation.y
                            record.rotation = rotation

                            record.prev_delta = record.delta
                            record.delta = utils.normalize(record.eye_angles.y - record.prev_eye_yaw, -180, 180)

                            record.is_prev_jittering = record.is_jittering

                            record.is_jittering = (record.delta > 0 and record.prev_delta < 0)
                                or (record.delta < 0 and record.prev_delta > 0)
                        else
                            record.choked_ticks = record.choked_ticks + 1
                        end

                        info[player] = {
                            yaw = record.eye_angles.y,
                            yaw_delta = record.delta,
                            simtime_delta = toticks(record.simtime - record.old_simtime)
                        }
                    end

                    local function update_correction(player)
                        local record = records[player]

                        if record == nil then
                            return
                        end

                        local tickcount = globals.tickcount()

                        local jitter_side = -1

                        if record.delta > 0 then
                            jitter_side = 1
                        end

                        local server_tick = toticks(record.server_tick)
                        local latency_tick = toticks(client.real_latency())

                        local arrival_tick = server_tick + latency_tick + 1
                        local current_tick = arrival_tick - server_tick - 1

                        local ticks_to_predict_before_arrival = math.min(math.max(arrival_tick - current_tick, 0) + (tickcount - record.server_tick), 8)

                        for tick = 1, ticks_to_predict_before_arrival do
                            jitter_side = -jitter_side
                        end

                        local avg_body_yaw = jitter_side * math.random(
                            ref.min_value:get(), ref.max_value:get()
                        )

                        set_player_body_yaw(player, utils.clamp(avg_body_yaw, -60, 60))

                        data_angles[player] = math.floor(
                            utils.clamp(avg_body_yaw, -60, 60)
                        )
                    end

                    client.register_esp_flag('', 255, 255, 255, function(player)
                        if not locker_system.is_locked(-1) then

                            if not ref.enabled:get() then
                                return
                            end

                            if ref.disable_fake_indicator:get() then
                                return
                            end

                            local angle = data_angles[player]

                            if angle == nil then
                                return
                            end

                            if angle > 1 then
                                return true, 'R'
                            end

                            if angle < -1 then
                                return true, 'L'
                            end
                        end
                    end)

                    local function on_shutdown()
                        local enemies = entity.get_players(true)

                        for i = 1, #enemies do
                            unset_player_body_yaw(enemies[i])
                        end
                    end

                    local function on_net_update()
                        local enemies = entity.get_players(true)

                        for i = 1, #enemies do
                            local enemy = enemies[i]

                            update_records(enemy)
                            update_correction(enemy)
                        end
                    end

                    local function on_aim_hit(e)
                        local target = e.target

                        if not target then
                            return
                        end

                        local group = hitgroups[e.hitgroup] or '?'

                        local str = string.format(
                            '{JITTER CORRECTION} registered shot at %s in %s for %s damage (animlayered: true, desync: %s°, riptided fix: true, predicted localtickbase: -%sticks)',
                            entity.get_player_name(e.target), group, e.damage, data_angles[target], math.random(2, 5)
                        )

                        print(str)
                    end

                    local function update_event_callbacks(value)
                        utils.event_callback('shutdown', on_shutdown, value)
                        utils.event_callback('aim_hit', on_aim_hit, value)
                        utils.event_callback('net_update_end', on_net_update, value)
                    end

                    function default:set_active(value)
                        update_event_callbacks(value)
                    end
                end

                local experimental = { } do
                    local types = { }

                    local records = {
                        cur = { },
                        prev = { },
                        pre_prev = { },
                        pre_pre_prev = { }
                    }

                    local desync_state = { }

                    local function normalize_angle(angle)
                        while angle > 180 do angle = angle - 360 end
                        while angle < -180 do angle = angle + 360 end
                        return angle
                    end

                    local function calculate_angle(from_vec, to_vec)
                        local delta = to_vec - from_vec
                        local angle = math.atan(delta.y / delta.x)

                        angle = normalize_angle(angle * 180 / math.pi)

                        if delta.x >= 0 then
                            angle = normalize_angle(angle + 180)
                        end

                        return angle
                    end

                    local function update_records(local_player)
                        local players = entity.get_players(true)

                        if #players == 0 then
                            records = {
                                cur = { },
                                prev = { },
                                pre_prev = { },
                                pre_pre_prev = { }
                            }

                            return nil
                        end

                        for _, player in ipairs(players) do
                            if entity.is_alive(player) and not entity.is_dormant(player) then
                                local sim_time = 0

                                local esp_flags = entity.get_esp_data(player).flags or 0

                                if bit.band(esp_flags, bit.lshift(1, 17)) ~= 0 then
                                    sim_time = toticks(entity.get_prop(player, "m_flSimulationTime")) - 14
                                else
                                    sim_time = toticks(entity.get_prop(player, "m_flSimulationTime"))
                                end

                                if records.cur[player] == nil or sim_time - records.cur[player].simtime >= 1 then
                                    records.pre_pre_prev[player] = records.pre_prev[player]
                                    records.pre_prev[player] = records.prev[player]
                                    records.prev[player] = records.cur[player]

                                    local local_pos = vector(entity.get_prop(local_player, "m_vecOrigin"))
                                    local eye_angles = vector(entity.get_prop(player, "m_angEyeAngles"))
                                    local player_pos = vector(entity.get_prop(player, "m_vecOrigin"))

                                    local yaw_delta = math.floor(normalize_angle(eye_angles.y - calculate_angle(local_pos, player_pos)))
                                    local duck_amount = entity.get_prop(player, "m_flDuckAmount")
                                    local is_on_ground = bit.band(entity.get_prop(player, "m_fFlags"), 1) == 1
                                    local velocity_2d = vector(entity.get_prop(player, 'm_vecVelocity')):length2d()

                                    local stance

                                    if is_on_ground then
                                        if duck_amount == 1 then
                                            stance = "duck"
                                        elseif velocity_2d > 1.2 then
                                            stance = "running"
                                        else
                                            stance = "standing"
                                        end
                                    else
                                        stance = "air"
                                    end

                                    local weapon = entity.get_player_weapon(player)
                                    local last_shot_time = entity.get_prop(weapon, "m_fLastShotTime")

                                    if records.cur[player] ~= nil then
                                        info[player] = {
                                            yaw = eye_angles.y,
                                            yaw_delta = eye_angles.y - records.cur[player].eye_yaw,
                                            simtime_delta = sim_time - records.cur[player].simtime
                                        }
                                    end

                                    records.cur[player] = {
                                        id = player,
                                        origin = vector(entity.get_origin(player)),
                                        eye_yaw = eye_angles.y,
                                        pitch = eye_angles.x,
                                        yaw = yaw_delta,
                                        yaw_backwards = math.floor(normalize_angle(calculate_angle(local_pos, player_pos))),
                                        simtime = sim_time,
                                        stance = stance,
                                        esp_flags = esp_flags,
                                        last_shot_time = last_shot_time
                                    }

                                    types[player] = {
                                        ["duck"] = {},
                                        ["running"] = {},
                                        ["standing"] = {},
                                        ["air"] = {}
                                    }
                                end
                            end
                        end
                    end

                    local function analyze_desync_targets(local_player)
                        if not entity.is_alive(local_player) then
                            return
                        end

                        local enemies = entity.get_players(true)

                        if #enemies == 0 then
                            return
                        end

                        for _, enemy in ipairs(enemies) do
                            if not entity.is_alive(enemy) or entity.is_dormant(enemy) then
                                goto continue
                            end

                            if not (records.cur[enemy] and records.prev[enemy] and records.pre_prev[enemy] and records.pre_pre_prev[enemy]) then
                                goto continue
                            end

                            local yaw_now = records.cur[enemy].yaw
                            local yaw_prev = records.prev[enemy].yaw
                            local yaw_delta = math.abs(normalize_angle(yaw_now - yaw_prev))

                            local pitch_now = records.cur[enemy].pitch
                            local pitch_prev = records.prev[enemy].pitch

                            local shot_tick = 0

                            if records.cur[enemy].last_shot_time then
                                local time_since_shot = globals.curtime() - records.cur[enemy].last_shot_time
                                local ticks = time_since_shot / globals.tickinterval()
                                shot_tick = ticks <= math.floor(0.2 / globals.tickinterval())
                            end

                            local aa_type = nil

                            if shot_tick and math.abs(pitch_now - pitch_prev) > 30 and pitch_now < pitch_prev then
                                aa_type = "ON SHOT"
                            elseif math.abs(pitch_now) > 60 then
                                local yaw_diff_1 = normalize_angle(yaw_now - records.prev[enemy].yaw)
                                local yaw_diff_2 = normalize_angle(yaw_now - records.pre_prev[enemy].yaw)
                                local yaw_diff_3 = normalize_angle(yaw_prev - records.pre_pre_prev[enemy].yaw)

                                if yaw_delta > 30 and math.abs(yaw_diff_2) < 15 and math.abs(yaw_diff_3) < 15 then
                                    aa_type = "[!!]"
                                elseif math.abs(yaw_diff_1) > 15 or math.abs(yaw_diff_2) > 15 then
                                    aa_type = "[!!!]"
                                end
                            end

                            if aa_type then
                                local stance = records.cur[enemy].stance

                                if stance and #types[enemy][stance] < 20 then
                                    table.insert(types[enemy][stance], aa_type)

                                    if (aa_type == "[!!!]" and yaw_delta > 5) or aa_type == "[!!]" then
                                        table.insert(types[enemy][stance], yaw_delta)
                                    end
                                end
                            end

                            if pitch_now >= 78 and pitch_prev > 78 then
                                if aa_type == "[!!]" then
                                    local diff = normalize_angle(yaw_now - yaw_prev)

                                    plist.set(enemy, "Force body yaw", true)
                                    plist.set(enemy, "Force body yaw value", diff > 0 and 60 or -60)
                                elseif aa_type == "[!!!]" then
                                    local diff = normalize_angle(yaw_now - yaw_prev)

                                    plist.set(enemy, "Force body yaw", true)
                                    plist.set(enemy, "Force body yaw value", diff > 0 and 0 or -60)
                                else
                                    plist.set(enemy, "Force body yaw", false)
                                    plist.set(enemy, "Force body yaw value", 0)
                                end
                            end

                            desync_state[enemy] = {
                                anti_aim_type = aa_type,
                                yaw_delta = normalize_angle(yaw_now - yaw_prev)
                            }

                            ::continue::
                        end
                    end

                    local function on_shutdown()
                        local enemies = get_enemies()

                        if enemies == nil then
                            return
                        end

                        for i = 1, #enemies do
                            unset_player_body_yaw(enemies[i])
                        end
                    end

                    local function on_net_update()
                        local me = entity.get_local_player()

                        if not me then
                            return
                        end

                        update_records(me)
                        analyze_desync_targets(me)
                    end

                    local function update_event_callbacks(value)
                        utils.event_callback('shutdown', on_shutdown, value)
                        utils.event_callback('net_update_end', on_net_update, value)
                    end

                    function experimental:set_active(value)
                        update_event_callbacks(value)
                    end
                end

                local callbacks do
                    local function on_mode(item)
                        local value = item:get()

                        default:set_active(value == 'Default')
                        experimental:set_active(value == 'Experimental')
                    end

                    local function on_enabled(item)
                        local value = item:get()

                        if not value then
                            default:set_active(false)
                            experimental:set_active(false)
                        end

                        if value then
                            ref.mode:set_callback(on_mode, true)
                        else
                            ref.mode:unset_callback(on_mode)
                        end
                    end

                    ref.enabled:set_callback(
                        on_enabled, true
                    )
                end
            end

            rage.correction = correction
        end

        local interpolate_predict do
            local ref = ref.ragebot.interpolate_predict

            local cl_interp = cvar.cl_interp
            local cl_interpolate = cvar.cl_interpolate
            local cl_interp_ratio = cvar.cl_interp_ratio

            local sv_lagcompensationforcerestore = cvar.sv_lagcompensationforcerestore

            local is_changed = false

            local aim_info = { }
            local box_queue = { }

            local function should_update()
                return ref.hotkey:get()
            end

            local function clear_box_queue()
                for i = 1, #box_queue do
                    box_queue[i] = nil
                end
            end

            local function get_target_box(target, history)
                history = math.max(-history, 0)

                local result = { }

                local origin = vector(entity.get_prop(target, 'm_vecOrigin'))
                local velocity = vector(entity.get_prop(target, 'm_vecVelocity'))

                local pos = utils.extrapolate(origin, velocity, history)

                local mins = pos + vector(entity.get_prop(target, 'm_vecMins'))
                local maxs = pos + vector(entity.get_prop(target, 'm_vecMaxs'))

                result[1] = vector(mins.x, mins.y, mins.z)
                result[2] = vector(mins.x, maxs.y, mins.z)
                result[3] = vector(maxs.x, maxs.y, mins.z)
                result[4] = vector(maxs.x, mins.y, mins.z)
                result[5] = vector(mins.x, mins.y, maxs.z)
                result[6] = vector(mins.x, maxs.y, maxs.z)
                result[7] = vector(maxs.x, maxs.y, maxs.z)
                result[8] = vector(maxs.x, mins.y, maxs.z)

                return result
            end

            local function reset_ragebot()
                override.unset(software.ragebot.other.accuracy_boost)
                override.unset(software.ragebot.other.remove_recoil)
                override.unset(software.ragebot.other.delay_shot)

                override.unset(software.misc.miscellaneous.ping_spike[1])

                ragebot.unset(software.ragebot.aimbot.quick_stop[1])
                ragebot.unset(software.ragebot.aimbot.prefer_safe_point)
                ragebot.unset(software.ragebot.aimbot.minimum_hit_chance)
            end

            local function update_ragebot()
                override.set(software.ragebot.other.accuracy_boost, 'Low')
                override.set(software.ragebot.other.remove_recoil, false)
                override.set(software.ragebot.other.delay_shot, false)

                override.set(software.misc.miscellaneous.ping_spike[1], false)

                ragebot.set(software.ragebot.aimbot.quick_stop[1], false)
                ragebot.set(software.ragebot.aimbot.prefer_safe_point, false)
                ragebot.set(software.ragebot.aimbot.minimum_hit_chance, 0)
            end

            local function reset_values()
                if is_changed then
                    is_changed = false

                    cl_interp:set_int(0.31)
                    cl_interpolate:set_int(1)
                    cl_interp_ratio:set_int(2)

                    sv_lagcompensationforcerestore:set_int(1)
                end

                reset_ragebot()
            end

            local function update_values()
                if not is_changed then
                    is_changed = true

                    if ref.lower_than_40ms:get() then
                        cl_interp:set_int(0)
                        cl_interpolate:set_int(0)
                        cl_interp_ratio:set_int(1)
                    else
                        cl_interp:set_int(0)
                        cl_interpolate:set_int(1)
                        cl_interp_ratio:set_int(2)
                    end

                    sv_lagcompensationforcerestore:set_int(
                        ref.disable_lc_restoring:get() and 0 or 1
                    )
                end

                if localplayer.is_onground and localplayer.is_crouched and not localplayer.is_moving then
                    update_ragebot()
                else
                    reset_ragebot()
                end
            end

            local function draw_box_3d(points, r, g, b, a)
                local edges = {
                    { 1, 2 }, { 2, 3 }, { 3, 4 }, { 4, 1 },
                    { 5, 6 }, { 6, 7 }, { 7, 8 }, { 8, 5 },
                    { 1, 5 }, { 2, 6 }, { 3, 7 }, { 4, 8 }
                }

                for i = 1, #edges do
                    local point_a = points[edges[i][1]]
                    local point_b = points[edges[i][2]]

                    if point_a ~= nil and point_b ~= nil then
                        local p1 = vector(renderer.world_to_screen(point_a.x, point_a.y, point_a.z))
                        local p2 = vector(renderer.world_to_screen(point_b.x, point_b.y, point_b.z))

                        if p1.x ~= 0 and p1.y ~= 0 and p2.x ~= 0 and p2.y ~= 0 then
                            renderer.line(p1.x, p1.y, p2.x, p2.y, r, g, b, a)
                        end
                    end
                end
            end

            local function draw_predict_boxes(r, g, b, a)
                local dt = globals.frametime()

                for i = #box_queue, 1, -1 do
                    local data = box_queue[i]

                    data.time = data.time - dt

                    if data.time <= 0 then
                        data.alpha = motion.interp(
                            data.alpha, 0.0, 0.05
                        )

                        if data.alpha <= 0.0 then
                            table.remove(box_queue, i)
                        end
                    end
                end

                for i = 1, #box_queue do
                    local data = box_queue[i]

                    draw_box_3d(data.box, r, g, b, a * data.alpha)
                end
            end

            local function draw_player_flag()
                local r, g, b = software.get_color(false)
                local text = 'PR'

                local alpha = math.abs(math.cos(globals.curtime() * 1))
                local hex = utils.to_hex(r, g, b, 255 * alpha)

                renderer.indicator(r, g, b, 255, '\a', hex, text)
            end

            local function on_shutdown()
                reset_values()
            end

            local function on_pre_config_save()
                reset_values()
            end

            local function on_paint()
                if should_update() then
                    draw_player_flag()
                end
            end

            local function on_box_paint()
                draw_predict_boxes(ref.box_color:get())
            end

            local function on_setup_command(e)
                if not should_update() then
                    reset_values()
                else
                    update_values()
                end
            end

            local function on_aim_fire(e)
                local target = e.target

                if target == nil then
                    return
                end

                local updated = should_update()

                local history = globals.tickcount() - e.tick
                local box = get_target_box(target, history)

                if history >= 0 then
                    updated = false
                end

                aim_info[e.id] = {
                    box = box,

                    updated = updated,
                    history = history
                }
            end

            local function on_aim_hit(e)
                local target = e.target

                if target == nil then
                    return
                end

                local data = aim_info[e.id]

                if data == nil then
                    return
                end

                if data.updated then
                    table.insert(box_queue, {
                        time = 1.0,
                        alpha = 1.0,

                        box = data.box
                    })
                end
            end

            local callbacks do
                local function on_render_box(item)
                    local value = item:get()

                    if not value then
                        clear_box_queue()
                    end

                    utils.event_callback(
                        'paint',
                        on_box_paint,
                        value
                    )

                    utils.event_callback(
                        'aim_fire',
                        on_aim_fire,
                        value
                    )

                    utils.event_callback(
                        'aim_hit',
                        on_aim_hit,
                        value
                    )
                end

                local function on_lower_than_40ms()
                    is_changed = false
                end

                local function on_disable_lc_restoring()
                    is_changed = false
                end

                local function on_enabled(item)
                    local value = item:get()

                    if not value then
                        reset_values()
                    end

                    if not value then
                        clear_box_queue()

                        utils.event_callback('paint', on_box_paint, false)
                        utils.event_callback('aim_fire', on_aim_fire, false)
                        utils.event_callback('aim_hit', on_aim_hit, false)
                    end

                    if value then
                        ref.render_box:set_callback(on_render_box, true)
                        ref.lower_than_40ms:set_callback(on_lower_than_40ms, true)
                        ref.disable_lc_restoring:set_callback(on_disable_lc_restoring, true)
                    else
                        ref.render_box:unset_callback(on_render_box)
                        ref.lower_than_40ms:unset_callback(on_lower_than_40ms)
                        ref.disable_lc_restoring:unset_callback(on_disable_lc_restoring)
                    end

                    utils.event_callback(
                        'shutdown',
                        on_shutdown,
                        value
                    )

                    utils.event_callback(
                        'pre_config_save',
                        on_pre_config_save,
                        value
                    )

                    utils.event_callback(
                        'paint',
                        on_paint,
                        value
                    )

                    utils.event_callback(
                        'setup_command',
                        on_setup_command,
                        value
                    )
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end

        local air_autostop do
            local HEIGHT_PEAK = 18

            local cl_sidespeed = cvar.cl_sidespeed

            local item_enabled = ui.new_checkbox(
                'Rage', 'Aimbot', 'Air autostop *revelation*'
            )

            local item_air_autoscope = ui.new_checkbox(
                'Rage', 'Aimbot', 'Air autoscope'
            )

            local item_on_peak_of_height = ui.new_checkbox(
                'Rage', 'Aimbot', 'On peak of height'
            )

            local item_distance = ui.new_slider(
                'Rage', 'Aimbot', 'Distance', 0, 1000, 350, true, 'u', 1, {
                    [0] = '∞'
                }
            )

            local item_delay = ui.new_slider(
                'Rage', 'Aimbot', 'Delay', 0, 16, 0, true, 't', 1, {
                    [0] = 'Off'
                }
            )

            local item_minimum_damage = ui.new_slider(
                'Rage', 'Aimbot', 'Minimum damage', -1, 130, -1, true, 'hp', 1, (function()
                    local hint = {
                        [-1] = 'Inherited'
                    }

                    for i = 1, 30 do
                        hint[100 + i] = string.format(
                            'HP + %d', i
                        )
                    end

                    return hint
                end)()
            )

            local stop_tick = -1
            local prediction_data = nil

            local function entity_is_ready(ent)
                return globals.curtime() >= entity.get_prop(ent, 'm_flNextAttack')
            end

            local function entity_can_fire(ent)
                return globals.curtime() >= entity.get_prop(ent, 'm_flNextPrimaryAttack')
            end

            function create_data(flags, velocity)
                local data = { }

                data.flags = flags or 0
                data.velocity = velocity or vector()

                return data
            end

            local function get_highest_damage(player, target)
                local eye_pos = nil

                if player == entity.get_local_player() then
                    eye_pos = vector(client.eye_position())
                else
                    eye_pos = vector(utils.get_eye_position(player))
                end

                local head = vector(entity.hitbox_position(target, 0))
                local stomach = vector(entity.hitbox_position(target, 3))

                local _, head_damage = client.trace_bullet(player, eye_pos.x, eye_pos.y, eye_pos.z, head.x, head.y, head.z)
                local _, stomach_damage = client.trace_bullet(player, eye_pos.x, eye_pos.y, eye_pos.z, stomach.x, stomach.y, stomach.z)

                return math.max(head_damage, stomach_damage)
            end

            local function update_autostop(cmd, minimum)
                local me = entity.get_local_player()

                if me == nil or prediction_data == nil then
                    return
                end

                local velocity = prediction_data.velocity
                local speed = velocity:length2d()

                if minimum ~= nil and speed < minimum then
                    return
                end

                local direction = vector(velocity:angles())
                local real_view = vector(client.camera_angles())

                direction.y = real_view.y - direction.y

                local forward = vector():init_from_angles(
                    direction:unpack()
                )

                local negative_side_move = -cl_sidespeed:get_float()
                local negative_direction = negative_side_move * forward

                cmd.in_speed = 1

                cmd.forwardmove = negative_direction.x
                cmd.sidemove = negative_direction.y
            end

            local function on_predict_command(cmd)
                local me = entity.get_local_player()

                if me == nil then
                    return
                end

                local flags = entity.get_prop(me, 'm_fFlags')
                local velocity = vector(entity.get_prop(me, 'm_vecVelocity'))

                prediction_data = create_data(flags, velocity)
            end

            local function on_setup_command(cmd)
                local me = entity.get_local_player()
                local threat = client.current_threat()

                if me == nil or threat == nil then
                    return
                end

                local wpn = entity.get_player_weapon(me)

                if wpn == nil or not entity_is_ready(me) or not entity_can_fire(wpn) then
                    return
                end

                local origin = vector(client.eye_position())
                local pos = vector(entity.get_origin(threat))

                pos.z = pos.z + 60

                local distance = pos:dist(origin)
                local max_distance = ui.get(item_distance)

                if max_distance ~= 0 and distance > max_distance then
                    return
                end

                local velocity = vector(entity.get_prop(me, 'm_vecVelocity'))
                local animstate = c_entity(me):get_anim_state()

                if animstate == nil or animstate.on_ground then
                    return
                end

                local tick = cmd.command_number
                local delay = ui.get(item_delay)

                local is_delaying = delay ~= 0
                local check_peak = ui.get(item_on_peak_of_height)

                local is_scoped = entity.get_prop(me, 'm_bIsScoped') ~= 0
                local is_force = is_delaying and (stop_tick > tick) or true

                local is_peaking = check_peak and (math.abs(velocity.z) < HEIGHT_PEAK) or true
                local is_downgoing = origin.z < animstate.last_origin_z

                if not is_force then
                    if is_downgoing or not is_peaking then
                        return
                    end

                    if is_delaying then
                        stop_tick = tick + delay
                    end
                end

                local max_damage = software.is_override_minimum_damage()
                    and software.get_override_damage()
                    or software.get_minimum_damage()

                local damage = get_highest_damage(me, threat)
                local health = entity.get_prop(threat, 'm_iHealth')

                if max_damage > 100 then
                    max_damage = health + (max_damage - 100)
                end

                if damage < max_damage then
                    return
                end

                local data = csgo_weapons(wpn)

                local max_speed = is_scoped
                    and data.max_player_speed_alt
                    or data.max_player_speed

                max_speed = max_speed * 0.34

                if ui.get(item_air_autoscope) then
                    if data.type == 'sniperrifle' and not is_scoped then
                        cmd.in_attack2 = 1
                    end
                end

                update_autostop(cmd, max_speed)
            end

            local callbacks do
                local function on_enabled(item)
                    local value = ui.get(item)

                    ui.set_visible(item_air_autoscope, value)
                    ui.set_visible(item_on_peak_of_height, value)
                    ui.set_visible(item_distance, value)
                    ui.set_visible(item_delay, value)
                    ui.set_visible(item_minimum_damage, value)

                    utils.event_callback('predict_command', on_predict_command, value)
                    utils.event_callback('setup_command', on_setup_command, value)
                end

                ui.set_callback(item_enabled, on_enabled)
                on_enabled(item_enabled)
            end
        end

        local aimtools do
            local ref = ref.ragebot.aimtools

            local ref_multipoint_scale = ui.reference(
                'Rage', 'Aimbot', 'Multi-point scale'
            )

            local ref_accuracy_boost = ui.reference(
                'Rage', 'Other', 'Accuracy boost'
            )

            local WEAPON_DEAGLE = 1
            local WEAPON_REVOLVER = 64
            local WEAPON_AWP = 9
            local WEAPON_SSG08 = 40
            local WEAPON_TASER = 31

            local manipulation do
                manipulation = { }

                local item_data = { }

                function manipulation.set(entindex, item_name, ...)
                    if item_data[entindex] == nil then
                        item_data[entindex] = { }
                    end

                    if item_data[entindex][item_name] == nil then
                        item_data[entindex][item_name] = {
                            plist.get(entindex, item_name)
                        }
                    end

                    plist.set(entindex, item_name, ...)
                end

                function manipulation.unset(entindex, item_name)
                    local entity_data = item_data[entindex]

                    if entity_data == nil then
                        return
                    end

                    local item_values = entity_data[item_name]

                    if item_values == nil then
                        return
                    end

                    plist.set(entindex, item_name, unpack(item_values))

                    entity_data[item_name] = nil
                end

                function manipulation.override(entindex, item_name, ...)
                    if ... ~= nil then
                        manipulation.set(entindex, item_name, ...)
                    else
                        manipulation.unset(entindex, item_name)
                    end
                end
            end

            local function is_enemy_higher_than_me(enemy)
                local me = entity.get_local_player()

                local enemy_origin = vector(entity.get_origin(enemy))
                local my_origin = vector(entity.get_origin(me))

                local distance = enemy_origin.z - my_origin.z

                return distance > 32
            end

            local function get_weapon_type(weapon)
                local weapon_info = csgo_weapons(weapon)

                if weapon_info == nil then
                    return nil
                end

                local weapon_idx = weapon_info.idx
                local weapon_type = weapon_info.type

                if weapon_type == 'pistol' then
                    if weapon_idx == WEAPON_DEAGLE then
                        return 'Desert Eagle'
                    end

                    if weapon_idx == WEAPON_REVOLVER then
                        return 'R8 revolver'
                    end

                    return 'Pistol'
                end

                if weapon_type == 'sniperrifle' then
                    if weapon_idx == WEAPON_AWP then
                        return 'AWP'
                    end

                    if weapon_idx == WEAPON_SSG08 then
                        return 'SSG 08'
                    end

                    return 'G3SG1 / SCAR-20'
                end

                if weapon_idx == WEAPON_TASER then
                    return 'Zeus'
                end

                return nil
            end

            local function get_body_aim_value(enemy, items)
                if not items.body_aim.enabled:get() then
                    return false
                end

                if items.body_aim.select:get 'Enemy health < X' then
                    local health = entity.get_prop(enemy, 'm_iHealth')

                    if health < items.body_aim.health:get() then
                        return true
                    end
                end

                if items.body_aim.select:get 'Enemy higher than you' then
                    if is_enemy_higher_than_me(enemy) then
                        return true
                    end
                end

                return false
            end

            local function get_safe_point_value(enemy, items)
                if not items.safe_points.enabled:get() then
                    return false
                end

                if items.safe_points.select:get 'Enemy health < X' then
                    local health = entity.get_prop(enemy, 'm_iHealth')

                    if health < items.safe_points.health:get() then
                        return true
                    end
                end

                if items.safe_points.select:get 'Enemy higher than you' then
                    if is_enemy_higher_than_me(enemy) then
                        return true
                    end
                end

                return false
            end

            local function get_multipoints_value(enemy, items)
                if not items.multipoints.enabled:get() then
                    return nil
                end

                local states = statement.get()
                local state = states[#states]

                local value = items.multipoints[state]

                if value == nil then
                    return nil
                end

                return value:get()
            end

            local function get_accuracy_boost_value(enemy, items)
                if not items.accuracy_boost.enabled:get() then
                    return nil
                end

                return items.accuracy_boost.value:get()
            end

            local function reset_player_list()
                local enemies = entity.get_players(true)

                for i = 1, #enemies do
                    local enemy = enemies[i]

                    manipulation.unset(enemy, 'Override prefer body aim')
                    manipulation.unset(enemy, 'Override safe point')
                end
            end

            local function update_aim_tools()
                local me = entity.get_local_player()

                if me == nil then
                    return false
                end

                local weapon = entity.get_player_weapon(me)

                if weapon == nil then
                    return false
                end

                local enemies = entity.get_players(true)
                local weapon_type = get_weapon_type(weapon)

                local items = ref[weapon_type]

                if items == nil then
                    return false
                end

                for i = 1, #enemies do
                    local enemy = enemies[i]

                    local body_aim = get_body_aim_value(enemy, items)
                    local safe_point = get_safe_point_value(enemy, items)
                    local multipoints = get_multipoints_value(enemy, items)
                    local accuracy_boost = get_accuracy_boost_value(enemy, items)

                    if safe_point then
                        manipulation.set(enemy, 'Override safe point', 'On')
                    else
                        manipulation.unset(enemy, 'Override safe point')
                    end

                    if body_aim then
                        manipulation.set(enemy, 'Override prefer body aim', 'Force')
                    else
                        manipulation.unset(enemy, 'Override prefer body aim')
                    end

                    if multipoints ~= nil then
                        ragebot.set(ref_multipoint_scale, multipoints)
                    else
                        ragebot.unset(ref_multipoint_scale)
                    end

                    if accuracy_boost ~= nil then
                        override.set(ref_accuracy_boost, accuracy_boost)
                    else
                        override.unset(ref_accuracy_boost)
                    end
                end

                return true
            end

            local function on_shutdown()
                reset_player_list()
            end

            local function on_run_command()
                if not update_aim_tools() then
                    reset_player_list()
                end
            end

            local callbacks do
                local function on_enabled(item)
                    local value = item:get()

                    if not value then
                        reset_player_list()
                    end

                    utils.event_callback('shutdown', on_shutdown, value)
                    utils.event_callback('run_command', on_run_command, value)
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end

        local defensive_fix do
            local ref = ref.ragebot.defensive_fix

            local ref_doubletap = {
                ui.reference('Rage', 'Aimbot', 'Double tap')
            }

            local function extrapolate(pos, velocity, ticks)
                return pos + velocity * (globals.tickinterval() * ticks)
            end

            local function is_double_tap()
                return ui.get(ref_doubletap[1])
                    and ui.get(ref_doubletap[2])
            end

            local function is_player_peeking(ticks)
                local me = entity.get_local_player()

                if me == nil then
                    return
                end

                local enemies = entity.get_players(true)

                -- if has no visible enemies
                if next(enemies) == nil then
                    return false
                end

                local eye_pos = extrapolate(
                    vector(client.eye_position()),
                    vector(entity.get_prop(me, 'm_vecVelocity')),
                    ticks
                )

                for i = 1, #enemies do
                    local enemy = enemies[i]

                    local head_pos = extrapolate(
                        vector(entity.hitbox_position(enemy, 0)),
                        vector(entity.get_prop(enemy, 'm_vecVelocity')),
                        ticks
                    )

                    local _, damage = client.trace_bullet(me, eye_pos.x, eye_pos.y, eye_pos.z, head_pos.x, head_pos.y, head_pos.z)

                    if damage > 0 then
                        return true
                    end
                end

                return false
            end

            local function should_update()
                if not is_double_tap() then
                    return false
                end

                if not is_player_peeking(17) then
                    return false
                end

                return true
            end

            local function on_setup_command(cmd)
                if not should_update() then
                    should_print = true
                    return
                end

                cmd.force_defensive = true
                if should_print == true then
                    print('[dbg] invaliding client ticks: '..entity.get_prop(entity.get_local_player(), 'm_nTickBase'))
                    should_print = false
                end
            end

            local callbacks do
                local function on_enabled(item)
                    utils.event_callback(
                        'setup_command',
                        on_setup_command,
                        item:get()
                    )
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end

        local recharge_fix do
            local ref = ref.ragebot.recharge_fix

            local prev_state = false

            local ref_enabled = {
                ui.reference('Rage', 'Aimbot', 'Enabled')
            }

            local ref_double_tap = {
                ui.reference('Rage', 'Aimbot', 'Double tap')
            }

            local ref_on_shot_antiaim = {
                ui.reference('AA', 'Other', 'On shot anti-aim')
            }

            local function is_double_tap_active()
                return ui.get(ref_double_tap[1])
                    and ui.get(ref_double_tap[2])
            end

            local function is_on_shot_antiaim_active()
                return ui.get(ref_on_shot_antiaim[1])
                    and ui.get(ref_on_shot_antiaim[2])
            end

            local function is_tickbase_changed(player)
                return (globals.tickcount() - entity.get_prop(player, 'm_nTickBase')) > 0
            end

            local function should_change()
                local me = entity.get_local_player()

                if me == nil then
                    return false
                end

                local state = is_double_tap_active()
                local charged = is_tickbase_changed(me)

                if prev_state ~= state then
                    if state and not charged then
                        return true
                    end

                    prev_state = state
                end

                if is_on_shot_antiaim_active() then
                    return not is_tickbase_changed(me)
                end

                return false
            end

            local function on_shutdown()
                ragebot.unset(ref_enabled[1])
            end

            local function on_setup_command()
                if should_change() then
                    ragebot.set(ref_enabled[1], false)
                else
                    ragebot.unset(ref_enabled[1])
                end
            end

            local callbacks do
                local function on_enabled(item)
                    local value = item:get()

                    if not value then
                        ragebot.unset(ref_enabled[1])
                    end

                    utils.event_callback('shutdown', on_shutdown, value)
                    utils.event_callback('run_command', on_setup_command, value)
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end

        local jitter_fix do
            local ref = ref.ragebot.jitter_fix

            local ref_antiaim_correction = ui.reference(
                'Rage', 'Other', 'Anti-aim correction'
            )

            local player_data = { }

            local function erase_player_data()
                for k in pairs(player_data) do
                    player_data[k] = nil
                end
            end

            local function unset_player_body_yaw(entindex)
                plist.set(entindex, 'Force body yaw', false)
                plist.set(entindex, 'Force body yaw value', 0)
            end

            local function set_player_body_yaw(entindex, value)
                plist.set(entindex, 'Force body yaw', true)
                plist.set(entindex, 'Force body yaw value', value)
            end

            local function get_max_desync_delta(animstate)
                local duck_amount = animstate.duck_amount

                local stop_to_full_running_fraction = animstate.stop_to_full_running_fraction

                local speed_fraction = math.max(0, math.min(animstate.feet_speed_forwards_or_sideways, 1))
                local speed_factor = math.max(0, math.min(animstate.feet_speed_unknown_forwards_or_sideways, 1))

                local value = ((stop_to_full_running_fraction * -0.30000001) - 0.19999999) * speed_fraction + 1

                if duck_amount > 0 then
                    value = value + ((duck_amount * speed_factor) * (0.5 - value))
                end

                return animstate.max_yaw * value
            end

            local function get_enemies()
                local player_resource = entity.get_player_resource()

                if player_resource == nil then
                    return nil
                end

                local list = { }

                for i = 1, globals.maxplayers() do
                    local is_connected = entity.get_prop(
                        player_resource, 'm_bConnected', i
                    )

                    if is_connected ~= 1 then
                        goto continue
                    end

                    local is_alive = entity.get_prop(
                        player_resource, 'm_bAlive', i
                    )

                    if not is_alive or not entity.is_enemy(i) then
                        goto continue
                    end

                    table.insert(list, i)
                    ::continue::
                end

                return list
            end

            local function reset_player_list()
                local enemies = get_enemies()

                if enemies == nil then
                    return
                end

                for i = 1, #enemies do
                    unset_player_body_yaw(enemies[i])
                end
            end

            local function on_shutdown()
                override.unset(ref_antiaim_correction)

                reset_player_list()
                erase_player_data()
            end

            local function on_aim_miss(e)
                local target = e.target

                if target == nil then
                    return
                end

                local data = player_data[target]

                if data == nil then
                    return
                end

                local is_forced_body_yaw = plist.get(
                    target, 'Force body yaw'
                )

                if not is_forced_body_yaw then
                    return
                end

                local is_valid_reason = (
                    e.reason == '?' or
                    e.reason == 'resolver' or
                    e.reason == 'correction'
                )

                if not is_valid_reason then
                    return
                end

                data.misses = data.misses + 1
            end

            local function on_player_spawn(e)
                local me = entity.get_local_player()
                local userid = client.userid_to_entindex(e.userid)

                if me ~= userid then
                    return
                end

                erase_player_data()
            end

            local function on_net_update_end()
                local me = entity.get_local_player()

                if me == nil then
                    return
                end

                override.set(ref_antiaim_correction, true)

                local enemies = get_enemies()

                if enemies == nil then
                    return
                end

                local my_origin = vector(
                    entity.get_origin(me)
                )

                for i = 1, #enemies do
                    local enemy = enemies[i]

                    local player_info = c_entity.new(enemy)

                    if player_info == nil then
                        goto continue
                    end

                    if not player_data[enemy] then
                        player_data[enemy] = {
                            misses = 0,
                            last_yaw = 0,
                            last_yaw_update_time = 0
                        }
                    end

                    local data = player_data[enemy]

                    if data == nil then
                        goto continue
                    end

                    local is_correction_active = plist.get(
                        enemy, 'Correction active'
                    )

                    if not is_correction_active or data.misses > 2 then
                        unset_player_body_yaw(enemy)

                        goto continue
                    end

                    local animstate = player_info:get_anim_state()

                    if animstate == nil then
                        goto continue
                    end

                    local head_center_position = vector(
                        entity.hitbox_position(enemy, 0)
                    )

                    local targets = vector((head_center_position - my_origin):angles())
                    local yaw = utils.normalize(targets.y - animstate.eye_angles_y + 180, -180, 180)

                    if data.last_yaw ~= yaw then
                        if math.abs(data.last_yaw - yaw) >= 20 and math.abs(data.last_yaw - yaw) <= 340 then
                            data.last_yaw_update_time = globals.tickcount() + 15
                        end

                        data.last_yaw = yaw
                    end

                    local is_jitter = data.last_yaw_update_time > globals.tickcount()

                    if not is_jitter then
                        unset_player_body_yaw(enemy)

                        goto continue
                    end

                    local mod = data.misses == 0 and 1 or -1
                    local side = utils.clamp(yaw, -1, 1) * mod

                    local max_desync = get_max_desync_delta(animstate)
                    set_player_body_yaw(enemy, max_desync * side)

                    ::continue::
                end
            end

            local callbacks do
                local function on_enabled(item)
                    local value = item:get()

                    if not value then
                        reset_player_list()
                        erase_player_data()
                    end

                    utils.event_callback('shutdown', on_shutdown, value)

                    utils.event_callback('aim_miss', on_aim_miss, value)
                    utils.event_callback('player_spawn', on_player_spawn, value)

                    utils.event_callback('net_update_end', on_net_update_end, value)
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end

        local auto_hide_shots do
            local ref = ref.ragebot.auto_hide_shots

            local ref_duck_peek_assist = ui.reference(
                'Rage', 'Other', 'Duck peek assist'
            )

            local ref_quick_peek_assist = {
                ui.reference('Rage', 'Other', 'Quick peek assist')
            }

            local ref_double_tap = {
                ui.reference('Rage', 'Aimbot', 'Double tap')
            }

            local ref_on_shot_antiaim = {
                ui.reference('AA', 'Other', 'On shot anti-aim')
            }

            local function get_state()
                if not localplayer.is_onground then
                    if localplayer.is_crouched then
                        return 'Air-Crouch'
                    end

                    return 'Air'
                end

                if localplayer.is_crouched then
                    if localplayer.is_moving then
                        return 'Move-Crouch'
                    end

                    return 'Crouch'
                end

                if localplayer.is_moving then
                    if software.is_slow_motion() then
                        return 'Slow Walk'
                    end

                    return 'Moving'
                end

                return 'Standing'
            end

            local function get_weapon_type(weapon)
                local weapon_info = csgo_weapons(weapon)

                if weapon_info == nil then
                    return nil
                end

                local weapon_type = weapon_info.type
                local weapon_index = weapon_info.idx

                if weapon_type == 'smg' then
                    return 'SMG'
                end

                if weapon_type == 'rifle' then
                    return 'Rifles'
                end

                if weapon_type == 'pistol' then
                    if weapon_index == 1 then
                        return 'Desert Eagle'
                    end

                    if weapon_index == 64 then
                        return 'Revolver R8'
                    end

                    return 'Pistols'
                end

                if weapon_type == 'sniperrifle' then
                    if weapon_index == 40 then
                        return 'Scout'
                    end

                    if weapon_index == 9 then
                        return 'AWP'
                    end

                    return 'Auto Snipers'
                end

                return nil
            end

            local function restore_values()
                ragebot.unset(ref_double_tap[1])

                override.unset(ref_on_shot_antiaim[1])
                override.unset(ref_on_shot_antiaim[2])
            end

            local function update_values()
                ragebot.set(ref_double_tap[1], false)

                override.set(ref_on_shot_antiaim[1], true)
                override.set(ref_on_shot_antiaim[2], 'Always on')
            end

            local function should_update()
                if ui.get(ref_duck_peek_assist) then
                    return false
                end

                local is_quick_peek_assist = (
                    ui.get(ref_quick_peek_assist[1]) and
                    ui.get(ref_quick_peek_assist[2])
                )

                if is_quick_peek_assist then
                    return false
                end

                if not ui.get(ref_double_tap[2]) then
                    return false
                end

                local me = entity.get_local_player()

                if me == nil then
                    return false
                end

                local weapon = entity.get_player_weapon(me)

                if weapon == nil then
                    return false
                end

                local weapon_type = get_weapon_type(weapon)

                if weapon_type == nil or not ref.weapons:get(weapon_type) then
                    return false
                end

                local state = get_state()

                if not ref.states:get(state) then
                    return false
                end

                return true
            end

            local function on_shutdown()
                restore_values()
            end

            local function on_setup_command()
                if should_update() then
                    update_values()
                else
                    restore_values()
                end
            end

            local callbacks do
                local function on_enabled(item)
                    local value = item:get()

                    if not value then
                        restore_values()
                    end

                    utils.event_callback(
                        'shutdown',
                        on_shutdown,
                        value
                    )

                    utils.event_callback(
                        'setup_command',
                        on_setup_command,
                        value
                    )
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end

        local jump_scout do
            local ref = ref.ragebot.jump_scout

            local function should_update()
                local me = entity.get_local_player()

                if me == nil then
                    return false
                end

                local weapon = entity.get_player_weapon(me)

                if weapon == nil then
                    return false
                end

                local weapon_info = csgo_weapons(weapon)

                if weapon_info == nil then
                    return nil
                end

                -- is weapon scout
                if weapon_info.idx ~= 40 then
                    return false
                end

                if localplayer.velocity2d_sqr > (10 * 10) then
                    return false
                end

                return true
            end

            local function restore_values()
                override.unset(software.misc.movement.air_strafe)
            end

            local function on_shutdown()
                restore_values()
            end

            local function on_paint_ui()
                restore_values()
            end

            local function on_setup_command(cmd)
                if should_update() then
                    override.set(software.misc.movement.air_strafe, false)
                else
                    override.unset(software.misc.movement.air_strafe)
                end
            end

            local callbacks do
                local function on_enabled(item)
                    local value = item:get()

                    if not value then
                        restore_values()
                    end

                    utils.event_callback('shutdown', on_shutdown, value)
                    utils.event_callback('paint_ui', on_paint_ui, value)
                    utils.event_callback('setup_command', on_setup_command, value)
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end

        local aimbot_logs do
            local ref = ref.ragebot.aimbot_logs

            local ref_draw_console_output = ui.reference(
                'Misc', 'Miscellaneous', 'Draw console output'
            )

            local ref_log_misses_due_to_spread = ui.reference(
                'Rage', 'Other', 'Log misses due to spread'
            )

            local PADDING_W = 8
            local PADDING_H = 6

            local GAP_BETWEEN = 4

            local e_hitgroup = {
                [0]  = 'generic',
                [1]  = 'head',
                [2]  = 'chest',
                [3]  = 'stomach',
                [4]  = 'left arm',
                [5]  = 'right arm',
                [6]  = 'left leg',
                [7]  = 'right leg',
                [8]  = 'neck',
                [10] = 'gear'
            }

            local hurt_weapons = {
                ['c4'] = 'bombed',
                ['knife'] = 'knifed',
                ['decoy'] = 'decoyed',
                ['inferno'] = 'burned',
                ['molotov'] = 'harmed',
                ['flashbang'] = 'harmed',
                ['hegrenade'] = 'naded',
                ['incgrenade'] = 'harmed',
                ['smokegrenade'] = 'harmed'
            }

            local log_glow = 0
            local log_offset = 0
            local log_duration = 5

            local fire_data = { }

            local draw_queue = { }
            local notify_queue = { }

            local function remove_hex(str)
                local result = string.gsub(
                    str, '\a%x%x%x%x%x%x%x%x', ''
                )

                return result
            end

            local function clear_draw_queue()
                for i = 1, #draw_queue do
                    draw_queue[i] = nil
                end
            end

            local function clear_notify_queue()
                for i = 1, #notify_queue do
                    notify_queue[i] = nil
                end
            end

            local function add_log(r, g, b, a, text)
                if not ref.select:get 'Screen' then
                    return
                end

                local time = log_duration

                local id = #draw_queue + 1
                local color = { r, g, b, a }

                text = remove_hex(text)

                draw_queue[id] = {
                    text = text,
                    color = color,

                    time = time,
                    alpha = 0.0
                }

                return id
            end

            local function notify_log(r, g, b, a, text)
                if not ref.select:get 'Notify' then
                    return
                end

                local list, count = text_fmt.color(text)

                for i = 1, count do
                    local value = list[i]

                    local hex = value[2]

                    if hex == nil then
                        hex = utils.to_hex(r, g, b, a)
                    end

                    value[2] = color(utils.from_hex(hex))
                end

                table.insert(notify_queue, {
                    time = 7.0,
                    alpha = 1.0,

                    list = list,
                    count = count
                })

                if #notify_queue > 7 then
                    table.remove(notify_queue, 1)
                end

                ui.set(ref_draw_console_output, false)
                ui.set(ref_log_misses_due_to_spread, false)
            end

            local function console_log(r, g, b, text)
                if not ref.select:get 'Console' then
                    return
                end

                local list, count = text_fmt.color(text)

                for i = 1, count do
                    local value = list[i]

                    local str = value[1]
                    local hex = value[2]

                    if i ~= count then
                        str = str .. '\0'
                    end

                    if hex == nil then
                        client.color_log(
                            r, g, b, str
                        )

                        goto continue
                    end

                    local hex_r, hex_g, hex_b = utils.from_hex(hex)

                    client.color_log(
                        hex_r, hex_g, hex_b, str
                    )

                    ::continue::
                end
            end

            local function format_text(text, hex_a, hex_b)
                local result = string.gsub(text, '${(.-)}', string.format(
                    '\a%s%%1\a%s', hex_a, hex_b
                ))

                if result:sub(1, 1) ~= '\a' then
                    result = '\a' .. hex_b .. result
                end

                return result
            end

            local function draw_box(x, y, w, h, r1, g1, b1, a1, r2, g2, b2, a2, alpha)
                local radius = 8

                if log_glow > 0 then
                    local glow_alpha = utils.map(
                        log_glow, 0.0, 1.5, 0, a2 * 0.5, true
                    )

                    render.glow(x, y, w, h, r2, g2, b2, glow_alpha * alpha, radius, round(8 * log_glow))
                end

                render.rectangle(x, y, w, h, r1, g1, b1, a1 * alpha, radius)
            end

            local function paint_notify()
                local dt = globals.frametime()
                local position = vector(8, 5)

                for i = #notify_queue, 1, -1 do
                    local data = notify_queue[i]

                    data.time = data.time - dt

                    if data.time <= 0.0 then
                        data.alpha = motion.interp(
                            data.alpha, 0.0, 0.075
                        )

                        if data.alpha <= 0.0 then
                            table.remove(notify_queue, i)
                        end
                    end
                end

                for i = 1, #notify_queue do
                    local data = notify_queue[i]

                    local list = data.list
                    local count = data.count
                    local alpha = data.alpha

                    local text_pos = position:clone()

                    for j = 1, count do
                        local value = list[j]

                        local text = value[1]
                        local col = value[2]

                        local text_size = vector(renderer.measure_text(flags, text))

                        renderer.text(text_pos.x, text_pos.y, col.r, col.g, col.b, col.a * alpha, flags, nil, text)

                        text_pos.x = text_pos.x + text_size.x
                    end

                    position.y = position.y + 14 * alpha
                end
            end

            local function paint_screen()
                local r0, g0, b0, a0 = 18, 18, 18, 225

                local time = globals.realtime()

                local dt = globals.frametime()
                local len = #draw_queue

                local screen_size = vector(
                    client.screen_size()
                )

                local position = screen_size / 2 do
                    position.y = position.y + log_offset
                end

                local icon_text = '✨'
                local icon_flags = ''

                local icon_size = vector(renderer.measure_text(icon_flags, icon_text))

                for i = len, 1, -1 do
                    local data = draw_queue[i]

                    local is_life = data.time > 0 and (len - i) < 6

                    data.alpha = motion.interp(
                        data.alpha, is_life, 0.075
                    )

                    if is_life then
                        data.time = data.time - dt
                    else
                        if data.alpha <= 0.0 then
                            table.remove(draw_queue, i)
                        end
                    end
                end

                local flags = ''

                for i = 1, #draw_queue do
                    local data = draw_queue[i]

                    local r, g, b, a = unpack(data.color)
                    local text, alpha = data.text, data.alpha

                    local text_size = vector(renderer.measure_text(flags, text))
                    local box_size = text_size + vector(PADDING_W, PADDING_H) * 2

                    if icon_text ~= nil then
                        box_size.x = box_size.x + icon_size.x + GAP_BETWEEN
                    end

                    local box_pos = position - box_size / 2

                    local text_pos = box_pos + vector(PADDING_W, PADDING_H)
                    local icon_pos = vector(text_pos.x, box_pos.y + (box_size.y - icon_size.y) / 2)

                    draw_box(box_pos.x, box_pos.y, box_size.x + 5, box_size.y, r0, g0, b0, a0, r, g, b, a * 0.34, alpha / 4)

                    if icon_text ~= nil then
                        renderer.text(
                            icon_pos.x, icon_pos.y - 1,
                            r, g, b, a * alpha,
                            icon_flags, nil, icon_text
                        )

                        text_pos.x = text_pos.x + icon_size.x + GAP_BETWEEN
                    end

                    text_pos.y = box_pos.y + (box_size.y - text_size.y) / 2

                    text = text_anims.gradient(
                        text, time,
                        255, 255, 255, 200 * alpha,
                        r, g, b, a * alpha
                    )

                    -- text = update_text_alpha(
                    --     text, alpha
                    -- )

                    renderer.text(
                        text_pos.x, text_pos.y,
                        255, 255, 255, 200 * alpha,
                        flags, nil, text
                    )

                    position.y = position.y - round((box_size.y + 8) * alpha)
                end
            end

            local function on_aim_hit(e)
                local data = fire_data[e.id]

                if data == nil then
                    return
                end

                local target = e.target

                if target == nil then
                    return
                end

                local r, g, b, a = ref.color_hit:get()

                local player_name = entity.get_player_name(target)
                local player_health = entity.get_prop(target, 'm_iHealth')

                local hit_chance = e.hit_chance or 0
                local aim_history = data.history or 0

                local damage = e.damage or 0
                local aim_damage = data.aim.damage or 0

                local hitgroup = e_hitgroup[e.hitgroup] or '?'
                local aim_hitgroup = e_hitgroup[data.aim.hitgroup] or '?'

                local damage_mismatch = (aim_damage - damage) > 0
                local hitgroup_mismatch = aim_hitgroup ~= hitgroup

                local details = { } do
                    table.insert(details, string.format('hc: ${%d%%}', hit_chance))
                    table.insert(details, string.format('bt: ${%dt}', aim_history))
                end

                local screen_text do
                    if player_health == 0 then
                        screen_text = string.format(
                            'Killed ${%s} in ${%s} for ${%s} damage (%s)',
                            player_name, hitgroup, damage, table.concat(details, ' ∙ ')
                        )
                    else
                        screen_text = string.format(
                            'Hit ${%s} in ${%s} for ${%s} damage (${%d} hp remaining ∙ %s)',
                            player_name, hitgroup, damage, player_health, table.concat(details, ' ∙ ')
                        )
                    end
                end

                local console_text do
                    local damage_text = string.format('${%d}', damage)
                    local hitgroup_text = string.format('${%s}', hitgroup)

                    if damage_mismatch then
                        damage_text = string.format(
                            '%s(${%d})', damage_text, aim_damage
                        )
                    end

                    if hitgroup_mismatch then
                        hitgroup_text = string.format(
                            '%s(${%s})', hitgroup_text, aim_hitgroup
                        )
                    end

                    local details = { } do
                        table.insert(details, string.format('hc: ${%d%%}', hit_chance))
                        table.insert(details, string.format('bt: ${%dt}', aim_history))
                    end

                    if player_health == 0 then
                        console_text = string.format(
                            'Killed ${%s} in ${%s} for ${%s} damage (%s)',
                            player_name, hitgroup, damage, table.concat(details, ' ∙ ')
                        )
                    else
                        console_text = string.format(
                            'Hit ${%s} in ${%s} for ${%s} damage (${%d} hp remaining ∙ %s)',
                            player_name, hitgroup, damage, player_health, table.concat(details, ' ∙ ')
                        )
                    end
                end

                screen_text = format_text(
                    screen_text, utils.to_hex(r, g, b, a), 'c8c8c8ff'
                )

                console_text = format_text(
                    console_text, utils.to_hex(r, g, b, a), 'c8c8c8ff'
                )

                add_log(r, g, b, a, screen_text)
                notify_log(255, 255, 255, 255, console_text)
                console_log(255, 255, 255, console_text)
            end

            local function on_aim_miss(e)
                local data = fire_data[e.id]

                if data == nil then
                    return
                end

                local target = e.target

                if target == nil then
                    return
                end

                local r, g, b, a = ref.color_miss:get()

                local player_name = entity.get_player_name(target)

                local miss_reason = e.reason or '?'
                local hit_chance = e.hit_chance or 0

                local aim_damage = data.aim.damage or 0
                local aim_history = data.history or 0

                local aim_hitgroup = e_hitgroup[data.aim.hitgroup] or '?'

                local details = { } do
                    table.insert(details, string.format('hc: ${%d%%}', hit_chance))
                    table.insert(details, string.format('bt: ${%dt}', aim_history))
                end

                local screen_text do
                    screen_text = string.format(
                        'Missed ${%s} in ${%s} due to ${%s} (%s)',
                        player_name, aim_hitgroup, miss_reason, table.concat(details, ' ∙ ')
                    )
                end

                local console_text do
                    local details = { } do
                        table.insert(details, string.format('hc: ${%d%%}', hit_chance))
                        table.insert(details, string.format('history: ${%dt}', aim_history))
                    end

                    console_text = string.format(
                        'Missed ${%s} in ${%s} due to ${%s} (%s)',
                        player_name, aim_hitgroup, miss_reason, table.concat(details, ' ∙ ')
                    )
                end

                screen_text = format_text(
                    screen_text, utils.to_hex(r, g, b, a), 'c8c8c8ff'
                )

                console_text = format_text(
                    console_text, utils.to_hex(r, g, b, a), 'c8c8c8ff'
                )

                add_log(r, g, b, a, screen_text)
                notify_log(255, 255, 255, 255, console_text)
                console_log(255, 255, 255, console_text)
            end

            local function on_aim_fire(e)
                local safe = plist.get(e.target, 'Override safe point')
                local history = globals.tickcount() - e.tick

                fire_data[e.id] = {
                    aim = e,

                    safe = safe == 'On',
                    history = history
                }
            end

            local function on_player_hurt(e)
                local me = entity.get_local_player()

                local userid = client.userid_to_entindex(e.userid)
                local attacker = client.userid_to_entindex(e.attacker)

                if attacker ~= me or userid == me then
                    return
                end

                local weapon = e.weapon
                local action = hurt_weapons[weapon]

                if action == nil then
                    return
                end

                local r, g, b, a = ref.color_hit:get()

                local player_name = entity.get_player_name(userid)
                local player_health = entity.get_prop(userid, 'm_iHealth')

                local damage = e.dmg_health

                local screen_text do
                    screen_text = string.format(
                        '%s ${%s} for ${%d} dmg',
                        action, player_name, damage
                    )
                end

                local console_text do
                    console_text = string.format(
                        '%s ${%s} for ${%d} dmg',
                        action, player_name, damage
                    )
                end

                screen_text = format_text(
                    screen_text, utils.to_hex(r, g, b, a), 'c8c8c8ff'
                )

                console_text = format_text(
                    console_text, utils.to_hex(r, g, b, a), 'c8c8c8ff'
                )

                add_log(r, g, b, a, screen_text)
                notify_log(255, 255, 255, 255, console_text)
                console_log(255, 255, 255, console_text)
            end

            local callbacks do
                local function on_glow(item)
                    log_glow = item:get() * 0.01
                end

                local function on_offset(item)
                    log_offset = item:get() * 2
                end

                local function on_duration(item)
                    log_duration = item:get() * 0.1
                end

                local function on_select(item)
                    local is_notify = item:get 'Notify'
                    local is_screen = item:get 'Screen'

                    if is_screen then
                        ref.glow:set_callback(on_glow, true)
                        ref.offset:set_callback(on_offset, true)
                        ref.duration:set_callback(on_duration, true)
                    else
                        ref.glow:unset_callback(on_glow)
                        ref.offset:unset_callback(on_offset)
                        ref.duration:unset_callback(on_duration)
                    end

                    if not is_notify then
                        clear_notify_queue()
                    end

                    if not is_screen then
                        clear_draw_queue()
                    end

                    utils.event_callback('paint', paint_notify, is_notify)
                    utils.event_callback('paint', paint_screen, is_screen)
                end

                local function on_enabled(item)
                    local value = item:get()

                    if value then
                        ref.select:set_callback(on_select, true)
                    else
                        ref.select:unset_callback(on_select)
                    end

                    if not value then
                        ref.glow:unset_callback(on_glow)
                        ref.offset:unset_callback(on_offset)
                        ref.duration:unset_callback(on_duration)

                        utils.event_callback('paint', paint_notify, false)
                        utils.event_callback('paint', paint_screen, false)

                        clear_draw_queue()
                        clear_notify_queue()
                    end

                    utils.event_callback('aim_hit', on_aim_hit, value)
                    utils.event_callback('aim_miss', on_aim_miss, value)
                    utils.event_callback('aim_fire', on_aim_fire, value)
                    utils.event_callback('player_hurt', on_player_hurt, value)
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end
    end

    local antiaim = { } do
        local inverts = 0
        local inverted = false

        local delay_ptr = {
            default = 0,
            defensive = 0
        }

        local skitter = {
            -1, 1, 0,
            -1, 1, 0,
            -1, 0, 1,
            -1, 0, 1
        }

        local buffer = { } do
            local ref = software.antiaimbot.angles

            local function override_value(item, ...)
                if ... == nil then
                    return
                end

                override.set(item, ...)
            end

            local Buffer = { } do
                Buffer.__index = Buffer

                function Buffer:clear()
                    for k in pairs(self) do
                        self[k] = nil
                    end
                end

                function Buffer:copy(target)
                    for k, v in pairs(target) do
                        self[k] = v
                    end
                end

                function Buffer:unset()
                    override.unset(ref.roll)

                    override.unset(ref.freestanding[2])
                    override.unset(ref.freestanding[1])

                    override.unset(ref.edge_yaw)

                    override.unset(ref.freestanding_body_yaw)

                    override.unset(ref.body_yaw[2])
                    override.unset(ref.body_yaw[1])

                    override.unset(ref.yaw[2])
                    override.unset(ref.yaw[1])

                    override.unset(ref.yaw_jitter[2])
                    override.unset(ref.yaw_jitter[1])

                    override.unset(ref.yaw_base)

                    override.unset(ref.pitch[2])
                    override.unset(ref.pitch[1])

                    override.unset(ref.enabled)
                end

                function Buffer:set()
                    if self.pitch_offset ~= nil then
                        self.pitch_offset = utils.clamp(
                            self.pitch_offset, -89, 89
                        )
                    end

                    if self.yaw_offset ~= nil then
                        self.yaw_offset = utils.normalize(
                            self.yaw_offset, -180, 180
                        )
                    end

                    if self.jitter_offset ~= nil then
                        self.jitter_offset = utils.normalize(
                            self.jitter_offset, -180, 180
                        )
                    end

                    if self.body_yaw_offset ~= nil then
                        self.body_yaw_offset = utils.clamp(
                            self.body_yaw_offset, -180, 180
                        )
                    end

                    override_value(ref.enabled, self.enabled)

                    override_value(ref.pitch[1], self.pitch)
                    override_value(ref.pitch[2], self.pitch_offset)

                    override_value(ref.yaw_base, self.yaw_base)

                    override_value(ref.yaw[1], self.yaw)
                    override_value(ref.yaw[2], self.yaw_offset)

                    override_value(ref.yaw_jitter[1], self.yaw_jitter)
                    override_value(ref.yaw_jitter[2], self.jitter_offset)

                    override_value(ref.body_yaw[1], self.body_yaw)
                    override_value(ref.body_yaw[2], self.body_yaw_offset)

                    override_value(ref.freestanding_body_yaw, self.freestanding_body_yaw)

                    override_value(ref.edge_yaw, self.edge_yaw)

                    if self.freestanding == true then
                        override_value(ref.freestanding[1], true)
                        override_value(ref.freestanding[2], 'Always on')
                    elseif self.freestanding == false then
                        override_value(ref.freestanding[1], false)
                        override_value(ref.freestanding[2], 'On hotkey')
                    end

                    override_value(ref.roll, self.roll)
                end
            end

            setmetatable(buffer, Buffer)
            antiaim.buffer = buffer
        end

        local defensive = { } do
            local pitch_inverted = false
            local modifier_delay_ticks = 0

            local timed = {
                curtime = 0,
                pitch = 0,
                delay = 1
            }

            local cycles = { } do
                local total_ticks = 0

                local pattern = {
                    { value = 15, ticks = 30 },
                    { value = 0, ticks = 13 },
                    { value = -31, ticks = 23 },
                    { value = 0, ticks = 9 }
                }

                for i = 1, #pattern do
                    total_ticks = total_ticks + pattern[i].ticks
                end

                cycles.pattern = pattern
                cycles.total_ticks = total_ticks
                cycles.last_start_tick = 0
            end

            local function get_timered_value(min, max, speed)
                local t = globals.curtime() * speed

                local range = max - min
                local progress = t % range

                return min + progress
            end

            local function update_pitch_inverter()
                pitch_inverted = not pitch_inverted
            end

            local function update_modifier_inverter()
                modifier_delay_ticks = modifier_delay_ticks + 1
            end

            local function update_pitch(buffer, items)
                if items.pitch == nil then
                    return
                end

                local value = items.pitch:get()
                local speed = items.pitch_speed:get()

                local pitch_offset_1 = items.pitch_offset_1:get()
                local pitch_offset_2 = items.pitch_offset_2:get()

                if value == 'Off' then
                    return
                end

                local can_be_randomized = (
                    value == 'Sway'
                )

                if can_be_randomized and items.pitch_randomize_offset:get() then
                    pitch_offset_1 = utils.random_int(-89, 89)
                    pitch_offset_2 = utils.random_int(-89, 89)
                end

                if value == 'Static' then
                    buffer.pitch = 'Custom'
                    buffer.pitch_offset = pitch_offset_1

                    return
                end

                if value == 'Jitter' then
                    local offset = pitch_inverted
                        and pitch_offset_2
                        or pitch_offset_1

                    buffer.pitch = 'Custom'
                    buffer.pitch_offset = offset

                    return
                end

                if value == 'Spin' then
                    local time = globals.curtime() * speed * 0.1

                    local offset = utils.lerp(
                        pitch_offset_1,
                        pitch_offset_2,
                        time % 1
                    )

                    buffer.pitch = 'Custom'
                    buffer.pitch_offset = offset

                    return
                end

                if value == 'Sway' then
                    local time = globals.curtime() * speed * 0.1
                    local t = math.abs(time % 2.0 - 1.0)

                    local offset = utils.lerp(
                        pitch_offset_1,
                        pitch_offset_2,
                        t
                    )

                    buffer.pitch = 'Custom'
                    buffer.pitch_offset = offset

                    return
                end

                if value == 'Random' then
                    buffer.pitch = 'Custom'

                    buffer.pitch_offset = utils.random_int(
                        pitch_offset_1, pitch_offset_2
                    )

                    return
                end

                if value == 'Timed' then
                    if globals.curtime() - timed.curtime >= timed.delay then
                        timed.pitch = get_timered_value(
                            pitch_offset_1,
                            pitch_offset_2,
                            items.pitch_time:get() * 60 * 0.1
                        )

                        timed.curtime = globals.curtime()
                    end

                    buffer.pitch = 'Custom'
                    buffer.pitch_offset = timed.pitch

                    return
                end
            end

            local function update_yaw_modifier(buffer, items)
                if items.yaw_modifier == nil then
                    return
                end

                local value = items.yaw_modifier:get()
                local offset = items.modifier_offset:get()

                if value == 'Off' then
                    return
                end

                if value == 'Offset' then
                    buffer.yaw_offset = buffer.yaw_offset + (
                        inverted and 0 or offset
                    )

                    return
                end

                if value == 'Center' then
                    if buffer.body_yaw == 'Jitter' then
                        buffer.yaw_left = buffer.yaw_left - offset * 0.5
                        buffer.yaw_right = buffer.yaw_right + offset * 0.5
                    else
                        buffer.yaw_offset = buffer.yaw_offset + 0.5 * (
                            inverted and -offset or offset
                        )
                    end

                    return
                end

                if value == 'Skitter' then
                    local index = inverts % #skitter
                    local multiplier = skitter[index + 1]

                    buffer.yaw_offset = buffer.yaw_offset + (
                        offset * multiplier
                    )

                    return
                end
            end

            local function update_yaw(buffer, items)
                if items.yaw == nil then
                    return
                end

                local value = items.yaw:get()
                local speed = items.yaw_speed:get()

                local yaw_offset = items.yaw_offset:get()

                local yaw_left = items.yaw_left:get()
                local yaw_right = items.yaw_right:get()

                if value == 'off' then
                    return
                end

                local can_be_randomized = (
                    value == 'Sway'
                )

                if can_be_randomized and items.yaw_randomize_offset:get() then
                    yaw_left = utils.random_int(-180, 180)
                    yaw_right = utils.random_int(-180, 180)
                end

                buffer.freestanding = false

                buffer.yaw_left = 0
                buffer.yaw_right = 0

                buffer.yaw_offset = 0

                buffer.yaw_jitter = 'Off'
                buffer.jitter_offset = nil

                if value == 'Static' then
                    buffer.yaw = '180'
                    buffer.yaw_offset = yaw_offset
                end

                if value == 'Spin' then
                    local time = globals.curtime() * speed * 0.1
                    local offset = yaw_offset * 0.5

                    offset = 180 + utils.lerp(
                        -offset, offset, time % 1
                    )

                    buffer.yaw = '180'
                    buffer.yaw_offset = offset
                end

                if value == 'Sway' then
                    local time = globals.curtime() * speed * 0.1
                    local t = math.abs(time % 2.0 - 1.0)

                    local offset = utils.lerp(
                        yaw_left,
                        yaw_right,
                        t
                    )
                    buffer.yaw = '180'
                    buffer.yaw_offset = offset
                end

                if value == 'Random' then
                    local offset = math.abs(
                        yaw_offset * 0.5
                    )

                    offset = 180 + utils.random_int(
                        -offset, offset
                    )

                    buffer.yaw = '180'
                    buffer.yaw_offset = offset
                end

                if value == 'Static LR' then
                    buffer.yaw = '180'
                    buffer.yaw_offset = 0

                    buffer.yaw_left = buffer.yaw_left + yaw_left
                    buffer.yaw_right = buffer.yaw_right + yaw_right
                end

                if value == 'Cycle' then
                    local current_tick = globals.tickcount()
                    local cycle_tick = (current_tick - cycles.last_start_tick) % cycles.total_ticks

                    local tick_sum = 0

                    for i = 1, #cycles.pattern do
                        local state = cycles.pattern[i]

                        tick_sum = tick_sum + state.ticks

                        if cycle_tick < tick_sum then
                            buffer.yaw_offset = state.value
                            break
                        end
                    end
                end

                update_yaw_modifier(buffer, items)
            end

            local function update_body_yaw(buffer, items)
                if items.body_yaw == nil then
                    return
                end

                local value = items.body_yaw:get()
                local offset = items.body_yaw_offset:get()

                if value == 'Off' then
                    return
                end

                buffer.body_yaw = value
                buffer.body_yaw_offset = offset

                buffer.delay = nil

                local should_update_delay = (
                    value == 'Jitter'
                    and items.delay_1 ~= nil
                    and items.delay_2 ~= nil
                )

                if should_update_delay then
                    local delay = utils.random_int(
                        items.delay_1:get(),
                        items.delay_2:get()
                    )

                    buffer.delay = math.max(1, delay)
                end
            end

            function defensive:update(cmd)
                if cmd.chokedcommands == 0 then
                    update_pitch_inverter()
                    update_modifier_inverter()
                end
            end

            function defensive:apply(cmd, items)
                if items.force_break_lc ~= nil and items.force_break_lc:get() then
                    cmd.force_defensive = true
                end

                local is_exploit_active = software.is_double_tap_active()
                    or software.is_on_shot_antiaim_active()

                local is_duck_peek_active = software.is_duck_peek_assist()

                if not is_exploit_active or is_duck_peek_active then
                    return false
                end

                local exploit_data = exploit.get()
                local defensive_data = exploit_data.defensive

                if defensive_data.left == 0 then
                    return false
                end

                local is_defensive = true

                local activation = items.activation:get()

                if activation == 'Sensitivity' then
                    local sensitivity = items.sensitivity:get() * 0.02
                    local tick_cap = defensive_data.max * sensitivity

                    is_defensive = (defensive_data.max - defensive_data.left) < tick_cap
                end

                if not items.enabled:get() or not is_defensive then
                    return false
                end

                local buffer_ctx = { }

                update_body_yaw(buffer_ctx, items)
                update_pitch(buffer_ctx, items)
                update_yaw(buffer_ctx, items)

                buffer.defensive = buffer_ctx

                if activation == 'Twilight' then
                    cmd.force_defensive = cmd.command_number % 7 == 0
                end

                return true
            end
        end

        local fakelag_clone = { } do
            local ref = ref.fakelag

            local HOTKEY_MODE = {
                [0] = 'Always on',
                [1] = 'On hotkey',
                [2] = 'Toggle',
                [3] = 'Off hotkey'
            }

            local function get_hotkey_value(_, mode, key)
                return HOTKEY_MODE[mode], key or 0
            end

            local function on_paint_ui()
                ui.set(software.antiaimbot.fake_lag.enabled[1], ref.enabled:get())
                ui.set(software.antiaimbot.fake_lag.enabled[2], get_hotkey_value(ref.hotkey:get()))

                ui.set(software.antiaimbot.fake_lag.amount, ref.amount:get())

                ui.set(software.antiaimbot.fake_lag.variance, ref.variance:get())
                ui.set(software.antiaimbot.fake_lag.limit, ref.limit:get())
            end

            client.set_event_callback('paint_ui', on_paint_ui)
        end

        local builder = { } do
            local ref = ref.antiaim.builder

            local function is_dormant()
                return next(entity.get_players(true)) == nil
            end

            local function update_pitch(items)
                if items.pitch == nil then
                    return
                end

                buffer.pitch = items.pitch:get()
                buffer.pitch_offset = items.pitch_offset:get()
            end

            local function update_yaw(items)
                if items.yaw == nil then
                    return
                end

                buffer.yaw = items.yaw:get()
                buffer.yaw_offset = items.yaw_offset:get()

                if buffer.yaw == '180 LR' then
                    local yaw_left = items.yaw_left:get()
                    local yaw_right = items.yaw_right:get()

                    if items.yaw_asynced:get() then
                        yaw_left = utils.random_int(yaw_left, yaw_left - math.random(11,30))
                        yaw_right = utils.random_int(yaw_right, yaw_right - math.random(11,30))
                    end

                    buffer.yaw = '180'
                    buffer.yaw_offset = 0

                    buffer.yaw_left = yaw_left
                    buffer.yaw_right = yaw_right
                end
            end

            local function update_jitter(items)
                if items.yaw_jitter == nil then
                    return
                end

                buffer.yaw_jitter = items.yaw_jitter:get()
                buffer.jitter_offset = items.jitter_offset:get()
            end

            local function update_not_defensive_body_yaw(items)
                if items.body_yaw == nil then
                    return
                end

                buffer.body_yaw = items.body_yaw:get()
                --print(buffer.body_yaw)
                buffer.body_yaw_offset = items.body_yaw_offset:get()
                buffer.freestanding_body_yaw = items.freestanding_body_yaw:get()

                if items.delay_body_1 ~= nil and items.delay_body_2 ~= nil then
                    local delay = utils.random_int(
                        items.delay_body_1:get(),
                        items.delay_body_2:get()
                    )

                    buffer.delay = math.max(1, delay)
                end
            end

            function builder:get(state)
                return ref[state]
            end

            function builder:is_active_ex(items)
                return items.enabled == nil
                    or items.enabled:get()
            end

            function builder:is_active(state)
                local items = self:get(state)

                if items == nil then
                    return false
                end

                return self:is_active_ex(items)
            end

            function builder:apply_ex(items)
                if items == nil then
                    return false
                end

                buffer.enabled = true

                update_pitch(items)
                update_yaw(items)
                update_jitter(items)
                update_not_defensive_body_yaw(items)

                return true
            end

            function builder:apply(state)
                local items = self:get(state)

                if items == nil then
                    return false, nil
                end

                if not self:is_active_ex(items) then
                    return false, items
                end

                self:apply_ex(items)
                return true, items
            end

            function builder:update(cmd)
                if not exploit.get().shift then
                    local state, items = self:apply 'Fakelag'

                    if state and items ~= nil then
                        return state, items
                    end
                end

                if is_dormant() then
                    local state, items = self:apply 'Dormant'

                    if state and items ~= nil then
                        return state, items
                    end
                end

                local states = statement.get()
                local state = states[#states]

                if state == nil then
                    return false, nil
                end

                local active, items = self:apply(state)

                if not active or items == nil then
                    local _, new_items = self:apply 'Default'

                    if new_items ~= nil then
                        items = new_items
                    end
                end

                return true, items
            end
        end

        local legit_aa = { } do
            local is_interact_traced = false

            local function should_update(cmd, items)
                local me = entity.get_local_player()

                if me == nil then
                    return false
                end

                local weapon = entity.get_player_weapon(me)

                if weapon == nil then
                    return false
                end

                local weapon_info = csgo_weapons(weapon)

                if weapon_info == nil then
                    return false
                end

                local team = entity.get_prop(me, 'm_iTeamNum')
                local my_origin = vector(entity.get_origin(me))

                local is_weapon_bomb = weapon_info.idx == 49

                local is_defusing = entity.get_prop(me, 'm_bIsDefusing') == 1
                local is_rescuing = entity.get_prop(me, 'm_bIsGrabbingHostage') == 1

                local in_bomb_site = entity.get_prop(me, 'm_bInBombZone') == 1

                if is_defusing or is_rescuing then
                    return false
                end

                if in_bomb_site and is_weapon_bomb then
                    return false
                end

                if team == 3 and cmd.pitch > 15 then
                    local bombs = entity.get_all 'CPlantedC4'

                    for i = 1, #bombs do
                        local bomb = bombs[i]

                        local origin = vector(
                            entity.get_origin(bomb)
                        )

                        local delta = origin - my_origin
                        local distancesqr = delta:lengthsqr()

                        if distancesqr < (62 * 62) then
                            return false
                        end
                    end
                end

                local camera = vector(client.camera_angles())
                local forward = vector():init_from_angles(camera:unpack())

                local eye_pos = vector(client.eye_position())
                local end_pos = eye_pos + forward * 128

                local fraction, entindex = client.trace_line(
                    me, eye_pos.x, eye_pos.y, eye_pos.z, end_pos.x, end_pos.y, end_pos.z
                )

                if fraction ~= 1 then
                    if entindex == -1 then
                        return true
                    end

                    local classname = entity.get_classname(entindex)

                    if classname == 'CWorld' then
                        return true
                    end

                    if classname == 'CFuncBrush' then
                        return true
                    end

                    if classname == 'CCSPlayer' then
                        return true
                    end

                    if classname == 'CHostage' then
                        local origin = vector(entity.get_origin(entindex))
                        local distance = eye_pos:distsqr(origin)

                        if distance < (84 * 84) then
                            return false
                        end
                    end

                    if not is_interact_traced then
                        is_interact_traced = true
                        return false
                    end
                end

                return true
            end

            function legit_aa:update(cmd)
                if cmd.in_use == 0 then
                    is_interact_traced = false

                    return false
                end

                local items = builder:get 'Legit AA'

                if items == nil then
                    return false
                end

                if items.override ~= nil and not items.override:get() then
                    return false
                end

                if not should_update(cmd, items) then
                    return false
                end

                buffer.pitch = 'Custom'
                buffer.pitch_offset = cmd.pitch

                buffer.yaw_base = 'at target'

                builder:apply_ex(items)

                if items ~= nil and items.defensive ~= nil then
                    defensive:apply(cmd, items.defensive)
                end

                buffer.yaw_offset = buffer.yaw_offset + 180
                buffer.freestanding = false

                cmd.in_use = 0

                return true
            end
        end

        local safe_head = { } do
            local ref = ref.antiaim.settings.safe_head

            local WEAPONTYPE_KNIFE = 0
            local FAR_DISTANCE_SQR = 1200 * 1200

            local function is_weapon_taser(weapon)
                local weapon_info = csgo_weapons(weapon)

                if weapon_info == nil then
                    return false
                end

                return weapon_info.idx == 31
            end

            local function is_weapon_knife(weapon)
                local weapon_info = csgo_weapons(weapon)

                if weapon_info == nil then
                    return false
                end

                -- is weapon taser
                if weapon_info.idx == 31 then
                    return false
                end

                return weapon_info.weapon_type_int == WEAPONTYPE_KNIFE
            end

            local function get_state()
                local me = entity.get_local_player()

                if me == nil then
                    return nil
                end

                local weapon = entity.get_player_weapon(me)

                if weapon == nil then
                    return nil
                end

                local threat = client.current_threat()

                if threat == nil then
                    return nil
                end

                local is_knife = is_weapon_knife(weapon)
                local is_taser = is_weapon_taser(weapon)

                local in_air = not localplayer.is_onground
                local is_moving = localplayer.is_moving
                local is_crouched = localplayer.is_crouched

                local my_origin = vector(entity.get_origin(me))
                local threat_origin = vector(entity.get_origin(threat))

                local delta = my_origin - threat_origin
                local lengthsqr = delta:lengthsqr()

                if is_knife and in_air and is_crouched and ref.states:get 'Knife' then
                    return 'Knife'
                end

                if is_taser and in_air and is_crouched and ref.states:get 'Taser' then
                    return 'Taser'
                end

                if delta.z > 50 and (not is_moving or is_crouched) and ref.states:get 'Above enemy' then
                    return 'Above enemy'
                end

                if lengthsqr > FAR_DISTANCE_SQR and (not is_moving and is_crouched) and ref.states:get 'Distance' then
                    return 'Distance'
                end

                return nil
            end

            local function update_safe_head_buffer(cmd, state)

                local state, items = builder:apply 'Safe Head'

                if state and items ~= nil then
                    if cmd ~= nil and items.defensive ~= nil then
                        defensive:apply(cmd, items.defensive)
                    end

                    return true
                end

                -- there you can make state
                -- presets, if you want it

                buffer.pitch = 'Default'
                buffer.yaw_base = 'At targets'

                buffer.yaw = '180'
                buffer.yaw_offset = 10

                buffer.yaw_left = 0
                buffer.yaw_right = 0

                buffer.yaw_jitter = 'Off'
                buffer.jitter_offset = 0

                buffer.body_yaw = 'Static'
                buffer.body_yaw_offset = 0
                buffer.freestanding_body_yaw = false

                buffer.edge_yaw = false
                buffer.roll = 0

                buffer.defensive = nil

                return true
            end

            function safe_head:update(cmd)
                if not ref.enabled:get() then
                    return false
                end

                local state = get_state()

                if state == nil then
                    return false
                end

                return update_safe_head_buffer(cmd, state)
            end
        end

        local disablers = { } do
            local ref = ref.antiaim.settings.disablers

            local function is_warmup()
                local game_rules = entity.get_game_rules()

                if game_rules == nil then
                    return false
                end

                local warmup_period = entity.get_prop(
                    game_rules, 'm_bWarmupPeriod'
                )

                return warmup_period == 1
            end

            local function is_no_enemies()
                local me = entity.get_local_player()

                if me == nil then
                    return false
                end

                local my_team = entity.get_prop(me, 'm_iTeamNum')
                local player_resource = entity.get_player_resource()

                for i = 1, globals.maxplayers() do
                    local is_connected = entity.get_prop(
                        player_resource, 'm_bConnected', i
                    )

                    if is_connected ~= 1 then
                        goto continue
                    end

                    local player_team = entity.get_prop(
                        player_resource, 'm_iTeam', i
                    )

                    if me == i or player_team == my_team then
                        goto continue
                    end

                    local is_alive = entity.get_prop(
                        player_resource, 'm_bAlive', i
                    )

                    if is_alive == 1 then
                        return false
                    end

                    ::continue::
                end

                return true
            end

            local function should_disable()
                if ref.select:get 'Warmup' and is_warmup() then
                    return true
                end

                if ref.select:get 'No enemies' and is_no_enemies() then
                    return true
                end

                return false
            end

            function disablers:update(cmd)
                if not ref.enabled:get() then
                    return
                end

                if should_disable() then
                    buffer.pitch = 'Custom'
                    buffer.pitch_offset = 0
                    buffer.yaw = "Spin"
                    buffer.yaw_offset = 25
                    buffer.yaw_base = 'at target'
                    buffer.yaw_jitter = "Off"
                    buffer.jitter_offset = 0
                    buffer.body_yaw = 'Static'
                    buffer.body_yaw_offset = 0
                end
            end
        end

        local avoid_backstab = { } do
            local ref = ref.antiaim.settings.avoid_backstab

            local WEAPONTYPE_KNIFE = 0
            local MAX_DISTANCE_SQR = 400 * 400

            local function is_weapon_knife(weapon)
                local weapon_info = csgo_weapons(weapon)

                if weapon_info == nil then
                    return false
                end

                -- is weapon taser
                if weapon_info.idx == 31 then
                    return false
                end

                return weapon_info.weapon_type_int == WEAPONTYPE_KNIFE
            end

            local function is_player_weapon_knife(player)
                local weapon = entity.get_player_weapon(player)

                if weapon == nil then
                    return false
                end

                return is_weapon_knife(weapon)
            end

            local function get_backstab_angle(player)
                local best_delta = nil
                local best_target = nil
                local best_distancesqr = math.huge

                local origin = vector(
                    entity.get_origin(player)
                )

                local enemies = entity.get_players(true)

                for i = 1, #enemies do
                    local enemy = enemies[i]

                    if not is_player_weapon_knife(enemy) then
                        goto continue
                    end

                    local enemy_origin = vector(
                        entity.get_origin(enemy)
                    )

                    local delta = enemy_origin - origin
                    local distancesqr = delta:lengthsqr()

                    best_delta = delta
                    best_target = enemy
                    best_distancesqr = distancesqr

                    ::continue::
                end

                return best_target, best_distancesqr, best_delta
            end

            function avoid_backstab:update()
                if not ref.enabled:get() then
                    return false
                end

                local me = entity.get_local_player()

                if me == nil then
                    return false
                end

                local target, distancesqr, delta = get_backstab_angle(me)

                if target == nil or distancesqr > MAX_DISTANCE_SQR then
                    return false
                end

                local angle = vector(
                    delta:angles()
                )

                buffer.enabled = true
                buffer.yaw_base = 'at target'

                buffer.yaw = 'Static'
                buffer.yaw_offset = angle.y

                buffer.freestanding_body_yaw = false

                buffer.edge_yaw = false
                buffer.freestanding = false

                buffer.roll = 0

                return true
            end
        end

        local manual_yaw = { } do
            local ref = ref.antiaim.settings.manual_yaw

            local current_dir = nil
            local hotkey_data = { }

            local dir_rotations = {
                ['left'] = -90,
                ['right'] = 90,
                ['forward'] = 180,
                ['backward'] = 0
            }

            local function get_hotkey_state(old_state, state, mode)
                if mode == 1 or mode == 2 then
                    return old_state ~= state
                end

                return false
            end

            local function update_hotkey_state(data, state, mode)
                local active = get_hotkey_state(
                    data.state, state, mode
                )

                data.state = state
                return active
            end

            local function update_hotkey_data(id, dir)
                if hotkey_data[id] == nil then
                    hotkey_data[id] = {
                        state = false
                    }
                end

                local changed = update_hotkey_state(
                    hotkey_data[id], ui.get(id)
                )

                if not changed then
                    return
                end

                if current_dir == dir then
                    current_dir = nil
                else
                    current_dir = dir
                end
            end


            function manual_yaw:update(cmd)
                local angle = dir_rotations[
                    current_dir
                ]

                if angle == nil then
                    return false
                end

                local yaw = buffer.yaw_offset or 0

                buffer.enabled = true

                buffer.yaw_offset = yaw + angle

                buffer.edge_yaw = false
                buffer.freestanding = false

                buffer.roll = 0

                if ref.disable_yaw_modifiers:get() then
                    buffer.yaw_offset = yaw + angle

                    buffer.yaw_left = 0
                    buffer.yaw_right = 0

                    buffer.yaw_jitter = 'Off'
                    buffer.jitter_offset = 0
                end

                if ref.body_freestanding:get() then
                    buffer.body_yaw = 'Static'
                    buffer.body_yaw_offset = 180
                    buffer.freestanding_body_yaw = true
                end

                local state, items = builder:apply 'Manual AA'

                if state and items ~= nil then
                    buffer.yaw_offset = buffer.yaw_offset + angle

                    if items.defensive ~= nil then
                        if defensive:apply(cmd, items.defensive) then
                            local yaw_offset = buffer.defensive.yaw_offset

                            if yaw_offset ~= nil then
                                buffer.defensive.yaw_offset = yaw_offset + angle
                            end
                        end
                    end
                end

                buffer.yaw_base = 'at target'

                return true
            end

            antiaim.manual_yaw = manual_yaw
        end

        local freestanding = { } do
            local ref = ref.antiaim.settings.freestanding

            local last_ack_defensive_side = nil
            local freestanding_side = nil

            local function is_value_near(value, target)
                return math.abs(target - value) <= 2.0
            end

            local function get_target_yaw(player)
                local threat = client.current_threat()

                if threat == nil then
                    return nil
                end

                local player_origin = vector(
                    entity.get_origin(player)
                )

                local threat_origin = vector(
                    entity.get_origin(threat)
                )

                local delta = threat_origin - player_origin
                local _, yaw = delta:angles()

                return yaw - 180
            end

            local function get_approximated_side(yaw)
                if is_value_near(yaw, -90) then
                    return -90
                end

                if is_value_near(yaw, 90) then
                    return 90
                end

                return nil
            end

            local function get_side()
                local me = entity.get_local_player()

                if me == nil then
                    return nil
                end

                local entity_data = c_entity(me)

                if entity_data == nil then
                    return nil
                end

                local animstate = entity_data:get_anim_state()

                if animstate == nil then
                    return nil
                end

                local target_yaw = get_target_yaw(me)

                if target_yaw == nil then
                    return nil
                end

                return get_approximated_side(
                    utils.normalize(animstate.eye_angles_y - target_yaw, -180, 180)
                )
            end

            local function is_enabled()
                if not ref.enabled:get() then
                    return false
                end

                if not ref.hotkey:get() then
                    return false
                end

                return true
            end

            local function update_freestanding_options(cmd)
                local items = builder:get 'Freestanding'

                if not builder:is_active_ex(items) then
                    items = nil
                end

                if freestanding_side ~= nil then
                    buffer.pitch = 'Default'

                    -- if ref.options:get 'disable yaw modifiers' then
                    --     buffer.yaw_left = 0
                    --     buffer.yaw_right = 0

                    --     buffer.yaw_jitter = 'Off'
                    --     buffer.jitter_offset = 0
                    -- end

                    -- if ref.options:get 'body freestanding' then
                    --     buffer.body_yaw = 'Static'
                    --     buffer.body_yaw_offset = 180
                    --     buffer.freestanding_body_yaw = true
                    -- end

                    if items ~= nil then
                        builder:apply_ex(items)
                    end
                end

                if localplayer.is_vulnerable then
                    if items ~= nil and items.defensive ~= nil then
                        if defensive:apply(cmd, items.defensive) then
                            local yaw_offset = buffer.defensive.yaw_offset

                            if yaw_offset ~= nil and last_ack_defensive_side ~= nil then
                                buffer.defensive.yaw_offset = yaw_offset + last_ack_defensive_side
                            end
                        else
                            if freestanding_side ~= nil then
                                last_ack_defensive_side = freestanding_side
                            end
                        end
                    end
                end
            end

            function freestanding:update(cmd)
                if not is_enabled() then
                    freestanding_side = nil
                    return
                end

                if cmd.chokedcommands == 0 then
                    freestanding_side = get_side()
                end

                buffer.freestanding = true
                update_freestanding_options(cmd)
            end
        end

        local defensive_flick = { } do
            local ref = ref.antiaim.settings.defensive_flick

            local function get_state()
                if not localplayer.is_onground then
                    if localplayer.is_crouched then
                        return 'Jumping+'
                    end

                    return 'Jumping'
                end

                if localplayer.is_crouched then
                    if localplayer.is_moving then
                        return 'Move-Crouch'
                    end

                    return 'Crouch'
                end

                if localplayer.is_moving then
                    if software.is_slow_motion() then
                        return 'Slow Walk'
                    end

                    return 'Moving'
                end

                return 'Standing'
            end

            local function should_update()
                if not ref.enabled:get() then
                    return false
                end

                local me = entity.get_local_player()

                if me == nil then
                    return false
                end

                local weapon = entity.get_player_weapon(me)

                if weapon == nil then
                    return false
                end

                local weapon_info = csgo_weapons(weapon)

                if weapon_info == nil or weapon_info.is_revolver then
                    return false
                end

                local exp_data = exploit.get()

                if not exp_data.shift then
                    return false
                end

                return ref.states:get(get_state())
            end

            function defensive_flick:update(cmd)
                if not should_update() then
                    return
                end

                local inverter = ref.inverter:get()
                local defensive = exploit.get().defensive

                local is_defensive_active = defensive.left ~= 0
                cmd.force_defensive = cmd.command_number % 7 == 0

                buffer.pitch = is_defensive_active and 'Custom' or 'Default'
                buffer.pitch_offset = is_defensive_active and 0 or 180

                buffer.yaw_base = 'At targets'

                buffer.yaw = '180'
                buffer.yaw_offset = is_defensive_active and utils.random_int(89, 120) or 0

                buffer.yaw_left = 0
                buffer.yaw_right = 0

                buffer.yaw_jitter = 'Off'
                buffer.jitter_offset = 0

                buffer.body_yaw = 'Static'
                buffer.body_yaw_offset = is_defensive_active and -1 or 1

                buffer.freestanding_body_yaw = false

                buffer.edge_yaw = false
                buffer.freestanding = false

                buffer.roll = 0

                if inverter then
                    buffer.yaw_offset = -buffer.yaw_offset
                    -- buffer.body_yaw_offset = -buffer.body_yaw_offset
                end
            end
        end

        local function update_defensive(cmd)
            local list = buffer.defensive

            local exp_data = exploit.get()
            local defensive = exp_data.defensive

            local is_valid = (
                list ~= nil and
                defensive.left > 0
            )

            if not is_valid then
                return false
            end

            buffer:copy(list)
            return true
        end

        local function update_inverter(mode)
            if exploit.get().shift then
                local delay = math.max(
                    1, buffer.delay or 1
                )

                delay_ptr[mode] = delay_ptr[mode] + 1

                if delay_ptr[mode] < delay then
                    return
                end
            end

            local should_invert = true

            if buffer.body_yaw == 'Random' then
                should_invert = utils.random_int(0, 1) == 0
            end

            inverts = inverts + 1

            if should_invert then
                inverted = not inverted
            end

            delay_ptr[mode] = 0
        end

        local function update_antiaims(cmd)
            buffer.freestanding = false

            defensive:update(cmd)

            local state, items = builder:update(cmd)

            if legit_aa:update(cmd) then
                return
            end

            if manual_yaw:update(cmd) then
                return
            end

            if avoid_backstab:update() then
                return
            end

            if state and items ~= nil and items.defensive ~= nil then
                defensive:apply(cmd, items.defensive)
            end

            freestanding:update(cmd)
            safe_head:update(cmd)
            defensive_flick:update(cmd)

            disablers:update(cmd)
        end

        local function update_yaw_offset()
            if buffer.body_yaw_offset == nil then
                return
            end

            if buffer.yaw_left ~= nil and buffer.yaw_right ~= nil then
                local yaw = buffer.yaw_offset or 0

                if buffer.body_yaw_offset < 0 then
                    buffer.yaw_offset = yaw + buffer.yaw_left
                end

                if buffer.body_yaw_offset > 0 then
                    buffer.yaw_offset = yaw + buffer.yaw_right
                end

                return
            end
        end

        local function update_yaw_jitter()
            if buffer.yaw_jitter == 'Offset' then
                local yaw = buffer.yaw_offset or 0
                local offset = buffer.jitter_offset

                buffer.yaw_jitter = 'Off'
                buffer.jitter_offset = 0

                buffer.yaw_offset = yaw + (inverted and offset or 0)

                return
            end

            if buffer.yaw_jitter == 'Center' then
                local yaw = buffer.yaw_offset or 0
                local offset = buffer.jitter_offset

                if not inverted then
                    offset = -offset
                end

                buffer.yaw_jitter = 'Off'
                buffer.jitter_offset = 0

                buffer.yaw_offset = yaw + offset / 2

                return
            end

            if buffer.yaw_jitter == 'Skitter' then
                local index = inverts % #skitter
                local multiplier = skitter[index + 1]

                local yaw = buffer.yaw_offset or 0
                local offset = buffer.jitter_offset

                buffer.yaw_jitter = 'Off'
                buffer.jitter_offset = 0

                buffer.yaw_offset = yaw + (offset * multiplier)

                return
            end

            if buffer.yaw_jitter == 'Spin' then
                local time = globals.curtime() * 3

                local yaw = buffer.yaw_offset or 0
                local offset = buffer.jitter_offset

                buffer.yaw_jitter = 'Off'
                buffer.jitter_offset = 0

                buffer.yaw_offset = yaw + utils.lerp(
                    -offset, offset, time % 1
                )

                return
            end
        end

        local function update_body_yaw()
            if buffer.body_yaw == 'Jitter' then
                local offset = buffer.body_yaw_offset

                if offset == 0 then
                    offset = 1
                end

                if not inverted then
                    offset = -offset
                end

                buffer.body_yaw = 'Static'
                buffer.body_yaw_offset = offset
            end

            if buffer.body_yaw == 'Random' then
                local offset = buffer.body_yaw_offset

                if offset == 0 then
                    offset = 1
                end

                buffer.body_yaw = 'Static'
                buffer.body_yaw_offset = inverted and offset or -offset
            end
        end

        local function update_buffer(cmd)
            local mode = 'default'

            if update_defensive(cmd) then
                mode = 'defensive'
            end

            if cmd.chokedcommands == 0 then
                update_inverter(mode)
            end

            update_body_yaw()
            update_yaw_jitter()
            update_yaw_offset()
        end

        local function on_shutdown()
            buffer:clear()
            buffer:unset()
        end

        local function on_setup_command(cmd)
            buffer:clear()
            buffer:unset()

            update_antiaims(cmd)
            update_buffer(cmd)

            buffer:set()
        end

        client.set_event_callback('shutdown', on_shutdown)
        client.set_event_callback('setup_command', on_setup_command)
    end

    local visuals = { } do
        local aspect_ratio do
            local ref = ref.visuals.aspect_ratio

            local r_aspectratio = cvar.r_aspectratio

            local function shutdown_aspect_ratio()
                r_aspectratio:set_raw_float(
                    tostring(r_aspectratio:get_string())
                )
            end

            local function on_shutdown()
                shutdown_aspect_ratio()
            end

            local function update_event_callbacks(value)
                if not value then
                    shutdown_aspect_ratio()
                end

                utils.event_callback(
                    'shutdown',
                    on_shutdown,
                    value
                )
            end

            local callbacks do
                local function on_value(item)
                    r_aspectratio:set_raw_float(
                        item:get() * 0.01
                    )
                end

                local function on_enabled(item)
                    local value = item:get()

                    if value then
                        ref.value:set_callback(on_value, true)
                    else
                        ref.value:unset_callback(on_value)
                    end

                    update_event_callbacks(value)
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end

        local third_person do
            local ref = ref.visuals.third_person
            local cam_idealdist = cvar.cam_idealdist

            local dist_value = 15

            local function restore_values()
                cam_idealdist:set_float(tonumber(cam_idealdist:get_string()))
            end

            local function update_values(value)
                cam_idealdist:set_raw_float(value)
            end

            local function on_shutdown()
                cam_idealdist:set_raw_float(dist_value)
            end

            local function on_paint_ui()
                local me = entity.get_local_player()

                if me == nil then
                    return
                end

                local weapon = entity.get_player_weapon(me)

                if weapon == nil then
                    return
                end

                local is_scoped = entity.get_prop(me, 'm_bIsScoped')
                local zoom_level = entity.get_prop(weapon, 'm_zoomLevel')

                local modifier, distance = 0, ref.distance:get()

                if is_scoped == 1 then
                    modifier = zoom_level == 2
                        and ref.dual_distance:get()
                        or ref.single_distance:get()
                end

                dist_value = motion.interp(
                    dist_value, distance - distance * modifier / 100, 0.2
                )

                update_values(dist_value)
            end

            local callbacks do
                local function on_enabled(item)
                    local value = item:get()

                    if not value then
                        restore_values()
                    end

                    utils.event_callback(
                        'shutdown',
                        on_shutdown,
                        value
                    )

                    utils.event_callback(
                        'paint_ui',
                        on_paint_ui,
                        value
                    )
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end

        local viewmodel do
            local ref = ref.visuals.viewmodel

            local viewmodel_fov = cvar.viewmodel_fov

            local viewmodel_offset_x = cvar.viewmodel_offset_x
            local viewmodel_offset_y = cvar.viewmodel_offset_y
            local viewmodel_offset_z = cvar.viewmodel_offset_z

            local cl_righthand = cvar.cl_righthand

            local function get_weapon_info()
                local me = entity.get_local_player()

                if me == nil then
                    return nil
                end

                local weapon = entity.get_player_weapon(me)

                if weapon == nil then
                    return nil
                end

                return csgo_weapons(weapon)
            end

            local function update_knife_hand(is_knife)
                local is_right = cl_righthand:get_string() == '1'

                if is_right then
                    cl_righthand:set_raw_int(is_knife and 0 or 1)
                else
                    cl_righthand:set_raw_int(is_knife and 1 or 0)
                end
            end

            local function shutdown_viewmodel()
                viewmodel_fov:set_float(tonumber(viewmodel_fov:get_string()))

                viewmodel_offset_x:set_float(tonumber(viewmodel_offset_x:get_string()))
                viewmodel_offset_y:set_float(tonumber(viewmodel_offset_y:get_string()))
                viewmodel_offset_z:set_float(tonumber(viewmodel_offset_z:get_string()))

                cl_righthand:set_int(cl_righthand:get_string() == '1' and 1 or 0)
            end

            local function on_shutdown()
                shutdown_viewmodel()
            end

            local function on_pre_render(cmd)
                local weapon_info = get_weapon_info()

                if weapon_info == nil then
                    return
                end

                local weapon_index = weapon_info.idx

                if old_weaponindex ~= weapon_index then
                    weapon_index = old_weaponindex

                    -- update opposite knife in hand
                    update_knife_hand(weapon_info.type == 'knife')
                end
            end

            local function update_event_callbacks(value)
                if not value then
                    shutdown_viewmodel()

                    utils.event_callback(
                        'pre_render',
                        on_pre_render,
                        false
                    )
                end

                utils.event_callback(
                    'shutdown',
                    on_shutdown,
                    value
                )
            end

            local callbacks do
                local function on_fov(item)
                    viewmodel_fov:set_raw_float(
                        item:get() * 0.1
                    )
                end

                local function on_offset_x(item)
                    viewmodel_offset_x:set_raw_float(
                        item:get() * 0.1
                    )
                end

                local function on_offset_y(item)
                    viewmodel_offset_y:set_raw_float(
                        item:get() * 0.1
                    )
                end

                local function on_offset_z(item)
                    viewmodel_offset_z:set_raw_float(
                        item:get() * 0.1
                    )
                end

                local function on_opposite_knife_hand(item)
                    local value = item:get()

                    if value then
                        local weapon_info = get_weapon_info()

                        if weapon_info ~= nil then
                            update_knife_hand(weapon_info.type == 'knife')
                        end
                    else
                        cl_righthand:set_raw_int(cl_righthand:get_string() == '1' and 1 or 0)
                    end

                    utils.event_callback(
                        'pre_render',
                        on_pre_render,
                        value
                    )
                end

                local function on_enabled(item)
                    local value = item:get()

                    if not value then
                        shutdown_viewmodel()
                    end

                    if value then
                        ref.fov:set_callback(on_fov, true)

                        ref.offset_x:set_callback(on_offset_x, true)
                        ref.offset_y:set_callback(on_offset_y, true)
                        ref.offset_z:set_callback(on_offset_z, true)

                        ref.opposite_knife_hand:set_callback(
                            on_opposite_knife_hand, true
                        )
                    else
                        ref.fov:unset_callback(on_fov)

                        ref.offset_x:unset_callback(on_offset_x)
                        ref.offset_y:unset_callback(on_offset_y)
                        ref.offset_z:unset_callback(on_offset_z)

                        ref.opposite_knife_hand:unset_callback(
                            on_opposite_knife_hand
                        )
                    end

                    update_event_callbacks(value)
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end

        local scope_animation do
            local ref = ref.visuals.scope_animation

            local fov_value = nil

            local function on_override_view(e)
                if fov_value == nil then
                    fov_value = e.fov
                end

                fov_value = motion.interp(
                    fov_value, e.fov, 0.035
                )

                e.fov = fov_value
            end

            local callbacks do
                local function on_enabled(item)
                    local value = item:get()

                    if not value then
                        fov_value = nil
                    end

                    utils.event_callback(
                        'override_view',
                        on_override_view,
                        value
                    )
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end

        local custom_scope do
            local ref = ref.visuals.custom_scope

            local alpha_value = 0.0
            local angle_value = 0.0

            local function rotate(x, y, cx, cy, angle)
                local rad = math.rad(angle)

                local cos = math.cos(rad)
                local sin = math.sin(rad)

                local dx = x - cx
                local dy = y - cy

                local result_x = cx + dx * cos - dy * sin
                local result_y = cy + dx * sin + dy * cos

                return result_x, result_y
            end

            local function render_gradient_line(x1, y1, x2, y2, r1, g1, b1, a1, r2, g2, b2, a2, segments)
                local step = 1 / segments

                for i = 0, segments - 1 do
                    local t1 = i * step
                    local t2 = (i + 1) * step

                    local r = r1 + (r2 - r1) * t1
                    local g = g1 + (g2 - g1) * t1
                    local b = b1 + (b2 - b1) * t1
                    local a = a1 + (a2 - a1) * t1

                    local x_start = x1 + (x2 - x1) * t1
                    local y_start = y1 + (y2 - y1) * t1

                    local x_end = x1 + (x2 - x1) * t2
                    local y_end = y1 + (y2 - y1) * t2

                    renderer.line(x_start, y_start, x_end, y_end, r, g, b, a)
                end
            end

            local function draw_rotated_gradient_line(cx, cy, x1, y1, x2, y2, r1, g1, b1, a1, r2, g2, b2, a2, angle)
                local x1, y1 = rotate(x1, y1, cx, cy, angle)
                local x2, y2 = rotate(x2, y2, cx, cy, angle)

                render_gradient_line(x1, y1, x2, y2, r1, g1, b1, a1, r2, g2, b2, a2, 10)
            end

            local function on_paint()
                override.set(software.visuals.effects.remove_scope_overlay, false)
            end

            local function on_paint_ui()
                local me = entity.get_local_player()

                if me == nil or not entity.is_alive(me) then
                    return
                end

                override.set(software.visuals.effects.remove_scope_overlay, true)

                local angle = ref.angle:get()
                local speed = 1 / ref.animation_speed:get()

                local is_scoped = entity.get_prop(me, 'm_bIsScoped')

                alpha_value = motion.interp(
                    alpha_value, is_scoped == 1, speed
                )

                angle_value = motion.interp(
                    angle_value, is_scoped == 0 and 0 or angle, speed * 2.5
                )

                if alpha_value == 0.0 then
                    return
                end

                local screen = vector(
                    client.screen_size()
                )

                local center = screen * 0.5

                local col = color(ref.color:get())

                local gap = math.floor(ref.gap:get())
                local length = math.floor(ref.length:get())

                local color_a = col:clone()
                local color_b = col:clone()

                color_a.a = color_a.a * alpha_value
                color_b.a = 0

                local mode = ref.mode:get()

                if mode == 'Plus' then
                    renderer.gradient(
                        center.x, center.y - gap, 1, -length,
                        color_a.r, color_a.g, color_a.b, color_a.a,
                        color_b.r, color_b.g, color_b.b, color_b.a,
                        false
                    )

                    renderer.gradient(
                        center.x, center.y + gap + 1, 1, length,
                        color_a.r, color_a.g, color_a.b, color_a.a,
                        color_b.r, color_b.g, color_b.b, color_b.a,
                        false
                    )

                    renderer.gradient(
                        center.x - gap, center.y, -length, 1,
                        color_a.r, color_a.g, color_a.b, color_a.a,
                        color_b.r, color_b.g, color_b.b, color_b.a,
                        true
                    )

                    renderer.gradient(
                        center.x + gap + 1, center.y, length, 1,
                        color_a.r, color_a.g, color_a.b, color_a.a,
                        color_b.r, color_b.g, color_b.b, color_b.a,
                        true
                    )

                    return
                end

                if mode == 'Cross' then
                    draw_rotated_gradient_line(
                        center.x, center.y,

                        center.x, center.y - gap,
                        center.x + 1, center.y - gap - length,

                        color_a.r, color_a.g, color_a.b, color_a.a,
                        color_b.r, color_b.g, color_b.b, color_b.a,
                        angle_value
                    )

                    draw_rotated_gradient_line(
                        center.x, center.y,

                        center.x, center.y + gap,
                        center.x + 1, center.y + gap + length,

                        color_a.r, color_a.g, color_a.b, color_a.a,
                        color_b.r, color_b.g, color_b.b, color_b.a,
                        angle_value
                    )

                    draw_rotated_gradient_line(
                        center.x, center.y,

                        center.x - gap, center.y,
                        center.x - gap - length, center.y + 1,

                        color_a.r, color_a.g, color_a.b, color_a.a,
                        color_b.r, color_b.g, color_b.b, color_b.a,
                        angle_value
                    )

                    draw_rotated_gradient_line(
                        center.x, center.y,

                        center.x + gap, center.y,
                        center.x + gap + length, center.y + 1,

                        color_a.r, color_a.g, color_a.b, color_a.a,
                        color_b.r, color_b.g, color_b.b, color_b.a,
                        angle_value
                    )
                end
            end

            local function update_event_callbacks(value)
                if not value then
                    override.unset(software.visuals.effects.remove_scope_overlay)
                end

                utils.event_callback(
                    'paint',
                    on_paint,
                    value
                )

                utils.event_callback(
                    'paint_ui',
                    on_paint_ui,
                    value
                )
            end

            local callbacks do
                local function on_enabled(item)
                    update_event_callbacks(item:get())
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end

        local world_marker do
            local ref = ref.visuals.world_marker

            local queue = { }
            local aim_data = { }

            local function draw_plus(x, y, size, r, g, b, a)
                renderer.line(x - size, y, x - size * 2, y, r, g, b, a)
                renderer.line(x + size, y, x + size * 2, y, r, g, b, a)
                renderer.line(x, y - size, x, y - size * 2, r, g, b, a)
                renderer.line(x, y + size, x, y + size * 2, r, g, b, a)
            end

            local function draw_cross(x, y, size, r, g, b, a)
                renderer.line(x - size * 2, y - size * 2, x - size, y - size, r, g, b, a)
                renderer.line(x - size * 2, y + size * 2, x - size, y + size, r, g, b, a)
                renderer.line(x + size * 2, y - size * 2, x + size, y - size, r, g, b, a)
                renderer.line(x + size * 2, y + size * 2, x + size, y + size, r, g, b, a)
            end

            local function get_drawing()
                local style = ref.style:get()

                if style == 'Plus' then
                    return draw_plus
                end

                if style == 'Cross' then
                    return draw_cross
                end

                return nil
            end

            local function on_paint()
                local drawing = get_drawing()

                if drawing == nil then
                    return
                end

                local size = ref.size:get()
                local dt = globals.frametime()

                for i = #queue, 1, -1 do
                    local data = queue[i]

                    data.time = data.time - dt

                    if data.time <= 0.0 then
                        data.alpha = motion.interp(
                            data.alpha, 0.0, 0.05
                        )

                        if data.alpha <= 0.0 then
                            table.remove(queue, i)
                        end
                    end
                end

                for i = 1, #queue do
                    local data = queue[i]

                    local x, y = renderer.world_to_screen(
                        data.pos:unpack()
                    )

                    if x == nil or y == nil then
                        goto continue
                    end

                    local col

                    if data.type == 'hit' then
                        col = color(ref['hit'].picker:get())
                    end

                    if data.type == 'miss' then
                        local color_data = ref[data.reason]

                        col = color(255, 0, 0, 255)

                        if color_data ~= nil then
                            col = color(color_data.picker:get())

                            if ref.show_miss_reason:get() then
                                local flags, text = 'd', data.reason

                                local text_size = vector(
                                    renderer.measure_text(
                                        flags, text
                                    )
                                )

                                renderer.text(x + size * 2 + 1, y - text_size.y / 2 - 1, col.r, col.g, col.b, col.a * data.alpha, flags, nil, text)
                            end
                        end
                    end

                    drawing(x, y, size, col.r, col.g, col.b, col.a * data.alpha)

                    ::continue::
                end
            end

            local function on_aim_fire(e)
                aim_data[e.id] = vector(
                    e.x, e.y, e.z
                )
            end

            local function on_aim_hit(e)
                local pos = aim_data[e.id]

                if pos == nil then
                    return
                end

                table.insert(queue, {
                    type = 'hit',
                    reason = nil,
                    pos = pos,
                    time = 1.5,
                    alpha = 1.0
                })
            end

            local function on_aim_miss(e)
                local pos = aim_data[e.id]

                if pos == nil then
                    return
                end

                table.insert(queue, {
                    type = 'miss',
                    reason = e.reason,
                    pos = pos,
                    time = 1.5,
                    alpha = 1.0
                })
            end

            local function on_round_start()
                for i = 1, #queue do
                    queue[i] = nil
                end
            end

            local function update_event_callbacks(value)
                utils.event_callback('paint', on_paint, value)
                utils.event_callback('aim_hit', on_aim_hit, value)
                utils.event_callback('aim_miss', on_aim_miss, value)
                utils.event_callback('aim_fire', on_aim_fire, value)
                utils.event_callback('round_start', on_round_start, value)
            end

            local callbacks do
                local function on_enabled(item)
                    update_event_callbacks(item:get())
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end

        local damage_marker do
            local ref = ref.visuals.damage_marker

            local queue = { }
            local aim_data = { }

            local function on_paint()
                local dt = globals.frametime()
                local r, g, b, a = ref.color:get()

                for i = #queue, 1, -1 do
                    local data = queue[i]

                    data.time = data.time - dt
                    data.pos.z = data.pos.z + dt * 35

                    data.value = motion.interp(
                        data.value, 1.0, 0.1
                    )

                    if data.time <= 0.0 then
                        data.alpha = motion.interp(
                            data.alpha, 0.0, 0.05
                        )

                        if data.alpha <= 0.0 then
                            table.remove(queue, i)
                        end
                    end
                end

                for i = 1, #queue do
                    local data = queue[i]

                    local x, y = renderer.world_to_screen(data.pos:unpack())

                    if x == nil or y == nil then
                        goto continue
                    end

                    local damage = math.floor(
                        data.damage * data.value
                    )

                    renderer.text(x, y, r, g, b, a * data.alpha, 'bc', nil, damage)

                    ::continue::
                end
            end

            local function on_aim_fire(e)
                aim_data[e.id] = vector(
                    e.x, e.y, e.z
                )
            end

            local function on_aim_hit(e)
                local pos = aim_data[e.id]

                if pos == nil then
                    return
                end

                table.insert(queue, {
                    pos = pos,
                    time = 3.0,

                    value = 0.0,
                    alpha = 1.0,

                    damage = e.damage
                })
            end

            local function on_round_start()
                for i = 1, #queue do
                    queue[i] = nil
                end
            end

            local function update_event_callbacks(value)
                utils.event_callback('paint', on_paint, value)

                utils.event_callback('aim_hit', on_aim_hit, value)
                utils.event_callback('aim_fire', on_aim_fire, value)

                utils.event_callback('round_start', on_round_start, value)
            end

            local callbacks do
                local function on_enabled(item)
                    update_event_callbacks(item:get())
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end

        local watermark do
            local ref = ref.visuals.watermark

            local window = windows.new(
                'watermark', 0, 0
            )

            local update_time = 0.0

            local last_fps = math.floor(
                1 / globals.frametime()
            )

            local function update_frametime()
                local dt = globals.frametime()

                update_time = update_time - dt

                if update_time <= 0 then
                    update_time = 1.0
                    last_fps = math.floor(1 / dt)
                end
            end

            local function get_position(window, width, height)
                local value = ref.position:get()

                if value == 'Custom' then
                    return window.pos:clone(), true
                end

                local position = vector()

                local screen = vector(
                    client.screen_size()
                )

                local y_value, x_value = value:match '(%w+)%s+(%w+)'

                if value == 'Center' then
                    y_value = 'Center'
                    x_value = 'Center'
                end

                if y_value == 'Top' then
                    position.y = 8
                end

                if y_value == 'Center' then
                    position.y = (screen.y - height) / 2
                end

                if y_value == 'Bottom' then
                    position.y = screen.y - height - 8
                end

                if x_value == 'Left' then
                    position.x = 8
                end

                if x_value == 'Center' then
                    position.x = (screen.x - width) / 2
                end

                if x_value == 'Right' then
                    position.x = screen.x - width - 8
                end

                return position, false
            end

            local default = { } do
                local function get_text(limiter)
                    local result = ''

                    local buffer = { } do
                        table.insert(buffer, string.format(
                            '%s / %s', script.name, script.build
                        ))

                        if ref.display:get 'Username' then
                            table.insert(buffer, script.user)
                        end

                        if ref.display:get 'FPS' then
                            table.insert(buffer, string.format(
                                '%d fps', last_fps
                            ))
                        end

                        if ref.display:get 'Ping' then
                            table.insert(buffer, string.format(
                                '%d ms', client.latency() * 1000
                            ))
                        end

                        if ref.display:get 'Time' then
                            table.insert(buffer, string.format(
                                '%02d:%02d', client.system_time()
                            ))
                        end
                    end

                    if next(buffer) ~= nil then
                        result = result .. limiter .. '  '

                        result = result .. table.concat(
                            buffer, string.format(
                                '  %s  ', limiter
                            )
                        )

                        result = result  .. '  ' .. limiter
                    end

                    return result
                end

                function default.on_paint_ui()
                    local text = get_text '@'

                    local r, g, b, a = ref.color:get()

                    local text_size = vector(
                        renderer.measure_text('', text)
                    )

                    local box_size = text_size + vector(12, 8)

                    local position, unlocked = get_position(
                        window, box_size.x, box_size.y
                    )

                    window:set_size(box_size)

                    if not unlocked then
                        window:set_pos(position)
                    end

                    local text_pos = position + (box_size - text_size) * 0.5

                    render.rectangle(position.x, position.y, box_size.x, box_size.y, 0, 0, 0, 200, 5)
                    renderer.text(text_pos.x, text_pos.y, r, g, b, a, '', nil, text)

                    if unlocked then
                        window:update()
                    end
                end
            end

            local alternative = { } do
                local function get_text(r0, g0, b0, a0)
                    local buffer = { } do
                        local time = globals.realtime() * 0.5

                        local r1, g1, b1, a1 = 80, 80, 80, 255
                        local r2, g2, b2, a2 = ref.color:get()

                        table.insert(buffer, string.format(
                            '%s\a%s', text_anims.gradient(
                                script.name .. ' ' .. script.build,
                                time, r1, g1, b1, a1, r2, g2, b2, a2
                            ), utils.to_hex(r0, g0, b0, a0)
                        ))

                        if ref.display:get 'Username' then
                            table.insert(buffer, script.user)
                        end

                        if ref.display:get 'FPS' then
                            table.insert(buffer, string.format(
                                '%d fps', last_fps
                            ))
                        end

                        if ref.display:get 'Ping' then
                            table.insert(buffer, string.format(
                                'delay: %dms', client.latency() * 1000
                            ))
                        end

                        if ref.display:get 'Time' then
                            table.insert(buffer, string.format(
                                '%02d:%02d:%02d', client.system_time()
                            ))
                        end
                    end

                    return table.concat(buffer, '   ')
                end

                function alternative.on_paint_ui()
                    local r0, g0, b0, a0 = 255, 255, 255, 255
                    local text = get_text(r0, g0, b0, a0)

                    local text_size = vector(
                        renderer.measure_text('', text)
                    )

                    local box_size = text_size + vector(8, 10)

                    local position, unlocked = get_position(
                        window, box_size.x, box_size.y
                    )

                    window:set_size(box_size)

                    if not unlocked then
                        window:set_pos(position)
                    end

                    local text_pos = position + (box_size - text_size) * 0.5

                    renderer.rectangle(position.x, position.y, box_size.x, box_size.y, 32, 32, 32, 50)
                    renderer.text(text_pos.x, text_pos.y, r0, g0, b0, a0, '', nil, text)

                    if unlocked then
                        window:update()
                    end
                end
            end

            local modern = { } do
                local function get_text(r0, g0, b0, a0)
                    local buffer = { } do
                        table.insert(buffer, string.format(
                            '›› %s anti aim technology', script.name
                        ))

                        table.insert(buffer, string.format(
                            '›› user: %s', script.user
                        ))

                        table.insert(buffer, string.format(
                            '›› build: %s', script.build
                        ))
                    end

                    return table.concat(buffer, '\n')
                end

                function modern.on_paint_ui()
                    local r0, g0, b0, a0 = 255, 255, 255, 255
                    local r1, g1, b1, a1 = ref.color:get()

                    local text = get_text(r0, g0, b0, a0)

                    local text_size = vector(
                        renderer.measure_text('', text)
                    )

                    local box_size = text_size + vector(10, 10)

                    local position, unlocked = get_position(
                        window, box_size.x, box_size.y
                    )

                    window:set_size(box_size)

                    if not unlocked then
                        window:set_pos(position)
                    end

                    local text_pos = position + (box_size - text_size) * 0.5

                    renderer.blur(position.x, position.y, box_size.x, box_size.y)

                    render.glow(position.x, position.y, box_size.x, box_size.y, r1, g1, b1, a1, 5, 8, 0.1)
                    render.modern_box(position.x, position.y, box_size.x, box_size.y, r1, g1, b1, a1, 5, 1)

                    renderer.text(text_pos.x, text_pos.y, r0, g0, b0, a0, '', nil, text)

                    if unlocked then
                        window:update()
                    end
                end
            end

            local callbacks do
                local function on_select(item)
                    local value = item:get()

                    utils.event_callback('paint_ui', default.on_paint_ui, value == 'Default')
                    utils.event_callback('paint_ui', alternative.on_paint_ui, value == 'Alternative')
                    utils.event_callback('paint_ui', modern.on_paint_ui, value == 'Modern')
                end

                ref.select:set_callback(
                    on_select, true
                )
            end

            client.set_event_callback('paint_ui', update_frametime)
        end

        local indicators do
            local ref = ref.visuals.indicators

            local y_offset = 0

            local TITLE_NAME = script.name:upper()
            local BUILD_NAME = script.build:upper()

            local draw_sparkles_indicators do
                local stars = {
                    { '★', -1, 7, 0.6 },
                    { '⋆', -8, 3, 0.2 },
                    { '✨', -2, 8, 0.7 },
                    { '✦', -2, 12, 0.5 },
                    { '★', -3, 8, 0.4 },
                    { '⋆', -5, 4, 0.3 },
                    { '✨', -3, 6, 0.7 },
                    { '⋆', -4, 5, 0.2 }
                }

                local alpha_value = 0.0
                local align_value = 0.0

                local dt_value = 0.0
                local dmg_value = 0.0
                local osaa_value = 0.0

                local function get_state()
                    if not localplayer.is_onground then
                        if localplayer.is_crouched then
                            return 'jump+'
                        end

                        return 'jump'
                    end

                    if localplayer.is_crouched then
                        return 'crouch'
                    end

                    if localplayer.is_moving then
                        if software.is_slow_motion() then
                            return 'slow'
                        end

                        return 'move'
                    end

                    return 'stand'
                end

                local function draw_stars(position, r, g, b, a)
                    local time = globals.realtime()

                    local dpi = 1.0

                    local x, y = position.x, position.y - 3

                    local sizes, len = { }, #stars
                    local width, height = 0, 0

                    for i = 1, len do
                        local data = stars[i]

                        local measure = vector(
                            renderer.measure_text('', data[1])
                        )

                        width = width + (measure.x + data[2]) * dpi
                        height = math.max(height, measure.y + data[3])

                        sizes[i] = measure
                    end

                    x = round(x - (width * 0.5) * (1 - align_value))

                    for i = 1, len do
                        local star = stars[i]
                        local size = sizes[i]

                        local text = star[1]

                        local offset_x = star[2]
                        local offset_y = star[3]

                        local phase = star[4]

                        local phase_value = math.sin(time * phase) do
                            phase_value = phase_value * 0.5 + 0.5
                            phase_value = phase_value * 0.7 + 0.3
                        end

                        renderer.text(
                            x + offset_x, y + offset_y,
                            r, g, b, a * phase_value,
                            '', nil, text
                        )

                        x = x + (size.x + offset_x) * dpi
                    end

                    position.y = position.y + height * 0.58 * dpi
                end

                local function draw_state(position, r, g, b, a, alpha)
                    local text, flags = get_state():upper(), '-'

                    local measure = vector(
                        renderer.measure_text(flags, text)
                    )

                    local x, y = position.x, position.y do
                        x = round(x - (measure.x * 0.5) * (1 - align_value))
                    end

                    renderer.text(x, y, r, g, b, a * alpha, flags, nil, text)

                    position.y = position.y + round(measure.y)
                end

                local function get_pulse(a, b)
                    local time = 0.6 + globals.realtime() * 3.0
                    local pulse = math.abs(math.sin(time))

                    return utils.lerp(a, b, pulse)
                end

                local function draw_title(position, r1, g1, b1, a1, r2, g2, b2, a2)
                    local text, flags = script.name:upper(), '-'

                    local measure = vector(
                        renderer.measure_text(flags, text)
                    )

                    local time = -globals.realtime()

                    text = text_anims.gradient(
                        text, time * 1.5,
                        r1, g1, b1, a1,
                        r2, g2, b2, a2
                    )

                    local x, y = position.x, position.y do
                        x = round(x - (measure.x * 0.5) * (1 - align_value))
                    end

                    local pulse = get_pulse(0.25, 1.0)

                    renderer.text(x, y, r1, g1, b1, a1, flags, nil, text)

                    position.y = position.y + measure.y
                end

                local function draw_double_tap(position, r, g, b, a, alpha)
                    local text, flags = 'DT', '-'

                    local measure = vector(
                        renderer.measure_text(flags, text)
                    )

                    local x, y = position.x, position.y do
                        x = round(x - (measure.x * 0.5) * (1 - align_value))
                    end

                    if software.is_duck_peek_assist() then
                        a = a * 0.5
                    end

                    renderer.text(x, y, r, g, b, a * alpha, flags, nil, text)

                    position.y = position.y + round(measure.y * alpha)
                end

                local function draw_minimum_damage(position, r, g, b, a, alpha)
                    local text, flags = 'DMG', '-'

                    local measure = vector(
                        renderer.measure_text(flags, text)
                    )

                    local x, y = position.x, position.y do
                        x = round(x - (measure.x * 0.5) * (1 - align_value))
                    end

                    renderer.text(x, y, r, g, b, a * alpha, flags, nil, text)

                    position.y = position.y + round(measure.y * alpha)
                end

                local function draw_onshot_antiaim(position, r, g, b, a, alpha)
                    local text, flags = 'HS', '-'

                    local measure = vector(
                        renderer.measure_text(flags, text)
                    )

                    local x, y = position.x, position.y do
                        x = round(x - (measure.x * 0.5) * (1 - align_value))
                    end

                    renderer.text(x, y, r, g, b, a * alpha, flags, nil, text)

                    position.y = position.y + round(measure.y * alpha)
                end

                local function update_values(me)
                    local is_alive = entity.is_alive(me)
                    local is_scoped = entity.get_prop(me, 'm_bIsScoped')

                    local is_double_tap = software.is_double_tap_active()
                    local is_min_damage = software.is_override_minimum_damage()
                    local is_onshot_aa = software.is_on_shot_antiaim_active()

                    alpha_value = motion.interp(alpha_value, is_alive, 0.04)
                    align_value = motion.interp(align_value, is_scoped == 1, 0.04)

                    dt_value = motion.interp(dt_value, is_double_tap, 0.04)
                    dmg_value = motion.interp(dmg_value, is_min_damage, 0.04)
                    osaa_value = motion.interp(osaa_value, is_onshot_aa, 0.04)
                end

                local function draw_indicators()
                    local screen = vector(client.screen_size())
                    local position = screen * 0.5

                    local r1, g1, b1, a1 = ref.color_accent:get()
                    local r2, g2, b2, a2 = ref.color_secondary:get()

                    position.x = position.x + round(10 * align_value)
                    position.y = position.y + y_offset

                    a1 = a1 * alpha_value
                    a2 = a2 * alpha_value

                    draw_stars(position, r1, g1, b1, a1 * 0.75)

                    draw_title(position, r1, g1, b1, a1, r2, g2, b2, a2)
                    draw_state(position, 188, 188, 188, 255, alpha_value)

                    draw_double_tap(position, 188, 188, 188, 255, dt_value * alpha_value)
                    draw_onshot_antiaim(position, 188, 188, 188, 255 * (1 - dt_value * 0.5), (1 - dt_value) * osaa_value * alpha_value)
                    draw_minimum_damage(position, 188, 188, 188, 255, dmg_value * alpha_value)
                end

                function draw_sparkles_indicators()
                    local me = entity.get_local_player()

                    if me == nil then
                        return
                    end

                    update_values(me)

                    if alpha_value > 0 then
                        draw_indicators()
                    end
                end
            end

            local draw_default_indicators do
                local old_exploit = ''

                local alpha_value = 0.0
                local align_value = 0.0

                local state_width = 0

                local dt_value = 0.0
                local dmg_value = 0.0
                local osaa_value = 0.0
                local exploit_value = 0.0

                local function is_holding_grenade(player)
                    local weapon = entity.get_player_weapon(player)

                    if weapon == nil then
                        return false
                    end

                    local weapon_info = csgo_weapons(weapon)

                    if weapon_info == nil then
                        return false
                    end

                    local weapon_type = weapon_info.type

                    if weapon_type ~= 'grenade' then
                        return false
                    end

                    return true
                end

                local function get_pulse(a, b)
                    local time = 0.6 + globals.realtime() * 3.0
                    local pulse = math.abs(math.sin(time))

                    return utils.lerp(a, b, pulse)
                end

                local function get_state()
                    if not localplayer.is_onground then
                        return '-AIR-'
                    end

                    if localplayer.is_crouched then
                        return '-CROUCH-'
                    end

                    if localplayer.is_moving then
                        if software.is_slow_motion() then
                            return '-WALKING-'
                        end

                        return '-MOVING-'
                    end

                    return '-STANDING-'
                end

                local function get_exploit_text()
                    if software.is_double_tap_active() then
                        old_exploit = 'DT'
                    elseif software.is_on_shot_antiaim_active() then
                        old_exploit = 'HIDE'
                    end

                    return old_exploit
                end

                local function update_text_alpha(text, alpha)
                    local result = text:gsub('\a(%x%x%x%x%x%x)(%x%x)', function(rgb, a)
                        return '\a' .. rgb .. string.format('%02x', tonumber(a, 16) * alpha)
                    end)

                    return result
                end

                local function draw_title(position, r1, g1, b1, a1, r2, g2, b2, a2, alpha)
                    local flags, pad = '-', 1

                    local title1, title2 = TITLE_NAME, "DEV"

                    local measure1 = vector(renderer.measure_text(flags, title1))
                    local measure2 = vector(renderer.measure_text(flags, title2))

                    local width = measure1.x + measure2.x + pad
                    local height = math.max(measure1.y, measure2.y)

                    local x, y = position:unpack() do
                        x = round(x - (2 + width * 0.5) * (1 - align_value))
                    end

                    local pulse = get_pulse(0.25, 1.0)

                    renderer.text(x, y, r2, g2, b2, a2 * alpha, flags, nil, title1)
                    x = x + measure1.x + pad

                    renderer.text(x, y, r1, g1, b1, a1 * alpha * pulse, flags, nil, title2)
                    position.y = position.y + height
                end

                local function draw_state(position, r, g, b, a, alpha)
                    local text, flags = get_state(), '-'

                    local measure = vector(
                        renderer.measure_text(flags, text)
                    )

                    measure.x = measure.x + 1

                    if measure.x < state_width then
                        state_width = measure.x
                    else
                        state_width = motion.interp(
                            state_width, measure.x, 0.045
                        )
                    end

                    local x, y = position:unpack() do
                        x = round(x - (2 + state_width * 0.5) * (1 - align_value))
                    end

                    renderer.text(x, y, r, g, b, a * alpha, flags, round(state_width), text)
                    position.y = position.y + measure.y
                end

                local function draw_exploit(position, alpha, global_alpha)
                    local exp = exploit.get()
                    local def = exp.defensive

                    local text, flags = get_exploit_text(), '-'
                    local status, r, g, b, a = 'IDLE', 255, 255, 255, 200

                    if exploit_value == 1 then
                        if def.left > 0 then
                            status = 'ACTIVE'
                            r, g, b, a = 120, 255, 255, 255
                        else
                            status = 'READY'
                            r, g, b, a = 192, 255, 109, 255
                        end
                    elseif exploit_value == 0 then
                        status = 'WAITING'
                        r, g, b, a = 255, 64, 64, 128
                    else
                        status = 'CHARGING'

                        r = utils.lerp(255, 192, exploit_value)
                        g = utils.lerp(64, 255, exploit_value)
                        b = utils.lerp(64, 145, exploit_value)
                        a = 255
                    end

                    text = string.format(
                        '\a%s%s \a%s%s',
                        utils.to_hex(255, 255, 255, a), text,
                        utils.to_hex(r, g, b, a), status
                    )

                    local global_text = update_text_alpha(text, global_alpha * alpha)
                    local alpha_text = update_text_alpha(global_text, 0.5 * alpha)

                    local measure = vector(renderer.measure_text(flags, text)) do
                        measure.x = measure.x + 1
                    end

                    local width = round(measure.x * alpha)
                    local height = round(measure.y * alpha)

                    local charge_width = round(width * exploit_value)

                    local x, y = position:unpack() do
                        x = round(x - (1 + width * 0.5) * (1 - align_value))
                    end

                    if charge_width ~= 0 then
                        renderer.text(x, y, r, g, b, a * alpha * global_alpha, flags, charge_width, global_text)
                    end

                    if width ~= 0 then
                        renderer.text(x, y, r, g, b, a * alpha * global_alpha, flags, width, alpha_text)
                    end

                    position.y = position.y + height
                end

                local function draw_minimum_damage(position, alpha, global_alpha)
                    local text, flags = 'DMG', '-'

                    local measure = vector(
                        renderer.measure_text(flags, text)
                    )

                    measure.x = measure.x + 1

                    local width = round(measure.x)
                    local height = round(measure.y * alpha)

                    if width == 0 then
                        return
                    end

                    local x, y = position:unpack() do
                        x = round(x - (2 + width * 0.5) * (1 - align_value))
                    end

                    renderer.text(x, y, 255, 255, 255, 255 * alpha * global_alpha, flags, width, text)
                    position.y = position.y + height
                end

                local function update_values(me)
                    local exp = exploit.get()

                    local is_alive = entity.is_alive(me)
                    local is_scoped = entity.get_prop(me, 'm_bIsScoped')

                    local is_grenade = is_holding_grenade(me)

                    local is_double_tap = software.is_double_tap_active()
                    local is_min_damage = software.is_override_minimum_damage()
                    local is_onshot_aa = software.is_on_shot_antiaim_active()

                    local alpha = 0.0

                    if is_alive then
                        alpha = is_grenade and 0.5 or 1.0
                    end

                    alpha_value = motion.interp(alpha_value, alpha, 0.04)
                    align_value = motion.interp(align_value, is_scoped == 1, 0.04)

                    dt_value = motion.interp(dt_value, is_double_tap, 0.03)
                    dmg_value = motion.interp(dmg_value, is_min_damage, 0.03)
                    osaa_value = motion.interp(osaa_value, is_onshot_aa, 0.03)
                    exploit_value = motion.interp(exploit_value, exp.shift, 0.025)

                    if not exp.shift then
                        exploit_value = 0
                    end
                end

                local function draw_indicators()
                    local screen = vector(client.screen_size())
                    local position = screen * 0.5

                    local r1, g1, b1, a1 = ref.color_accent:get()
                    local r2, g2, b2, a2 = ref.color_secondary:get()

                    position.x = position.x + round(10 * align_value)
                    position.y = position.y + y_offset

                    draw_title(position, r1, g1, b1, a1, r2, g2, b2, a2, alpha_value)
                    draw_exploit(position, math.max(dt_value, osaa_value), alpha_value)
                    draw_state(position, 255, 255, 255, 255, alpha_value)
                    draw_minimum_damage(position, dmg_value, alpha_value)
                end

                function draw_default_indicators()
                    local me = entity.get_local_player()

                    if me == nil then
                        return
                    end

                    update_values(me)

                    if alpha_value > 0 then
                        draw_indicators()
                    end
                end
            end

            local callbacks do
                local function on_style(item)
                    local value = item:get()

                    utils.event_callback('paint_ui', draw_default_indicators, value == 'Default')
                    utils.event_callback('paint_ui', draw_sparkles_indicators, value == 'Sparkles')
                end

                local function on_offset(item)
                    y_offset = item:get() * 2
                end

                local function on_enabled(item)
                    local value = item:get()

                    if value then
                        ref.style:set_callback(on_style, true)
                        ref.offset:set_callback(on_offset, true)
                    else
                        ref.style:unset_callback(on_style)
                        ref.offset:unset_callback(on_offset)
                    end

                    if not value then
                        utils.event_callback('paint_ui', draw_default_indicators, false)
                        utils.event_callback('paint_ui', draw_sparkles_indicators, false)
                    end
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end

        local damage_indicator do
            local ref = ref.visuals.damage_indicator

            local ref_minimum_damage = ui.reference(
                'Rage', 'Aimbot', 'Minimum damage'
            )

            local ref_override_damage = {
                ui.reference('Rage', 'Aimbot', 'Minimum damage override')
            }

            local font_map = {
                ['Default'] = '',
                ['Pixel'] = '-'
            }

            local window do
                local screen = vector(
                    client.screen_size()
                )

                window = windows.new(
                    'damage_indicator',
                    screen.x * 0.5 + 8,
                    screen.y * 0.5 - 8
                )

                window:set_anchor(
                    vector(0.0, 1.0)
                )
            end

            local alpha_value = 0.0
            local damage_value = 0.0

            local function is_minimum_damage_override()
                return ui.get(ref_override_damage[1])
                    and ui.get(ref_override_damage[2])
            end

            local function get_ragebot_damage(override)
                if override then
                    return ui.get(ref_override_damage[3])
                end

                return ui.get(ref_minimum_damage)
            end

            local function get_wish_alpha(override)
                local mode = ref.display:get()

                if mode == 'Always On' then
                    return 1.0
                end

                if mode == 'Always On (50%)' then
                    return override and 1.0 or 0.5
                end

                if mode == 'Hotkey' then
                    return override and 1.0 or 0.0
                end

                return 0.0
            end

            local function get_drawing_flags()
                return font_map[ref.font:get()] or ''
            end

            local function get_drawing_text(damage)
                damage_value = motion.interp(
                    damage_value, damage, 0.05
                )

                if damage == 0 then
                    return 'AUTO'
                end

                if ref.animation:get() == 'Smooth' then
                    damage = damage_value
                end

                return tostring(math.floor(damage + 0.5))
            end

            local function on_paint_ui()
                local me = entity.get_local_player()

                if me == nil then
                    return
                end

                local position = window.pos:clone()

                local is_overriding = is_minimum_damage_override()
                local damage = get_ragebot_damage(is_overriding)

                local flags = get_drawing_flags()
                local text = get_drawing_text(damage)

                alpha_value = motion.interp(
                    alpha_value, get_wish_alpha(is_overriding), 0.05
                )

                if alpha_value <= 0.0 then
                    return
                end

                local text_size = vector(
                    renderer.measure_text(
                        flags, text
                    )
                )

                local text_color = color(
                    ref.color:get()
                )

                text_color.a = text_color.a * alpha_value

                renderer.text(position.x, position.y, text_color.r, text_color.g, text_color.b, text_color.a, flags, nil, text)

                window:set_size(text_size)
                window:update()
            end

            local callbacks do
                local function on_enabled(item)
                    utils.event_callback('paint_ui', on_paint_ui, item:get())
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end

        local manual_arrows do
            local ref = ref.visuals.manual_arrows

            local draw_default do
                local PADDING = 58

                local left_value = 0
                local right_value = 0
                local forward_value = 0

                local scope_align = 0

                local function update_values(me)
                    local value = antiaim.manual_yaw:get()

                    local is_alive = entity.is_alive(me)
                    local is_scoped = entity.get_prop(me, 'm_bIsScoped')

                    left_value = motion.interp(left_value, is_alive and value == 'left', 0.05)
                    right_value = motion.interp(right_value, is_alive and value == 'right', 0.05)
                    forward_value = motion.interp(forward_value, is_alive and value == 'forward', 0.05)

                    scope_align = motion.interp(scope_align, is_scoped, 0.05)
                end

                local function draw_left_arrow(x, y, r, g, b, a, alpha)
                    if alpha <= 0 then
                        return
                    end

                    local flags, text = '+', '<'

                    local text_size = vector(
                        renderer.measure_text(
                            flags, text
                        )
                    )

                    x = x - round(text_size.x - 1)
                    y = y - round(text_size.y / 2)

                    renderer.text(x, y, r, g, b, a * alpha, flags, nil, text)
                end

                local function draw_right_arrow(x, y, r, g, b, a, alpha)
                    if alpha <= 0 then
                        return
                    end

                    local flags, text = '+', '>'

                    local text_size = vector(
                        renderer.measure_text(
                            flags, text
                        )
                    )

                    y = y - round(text_size.y / 2)

                    renderer.text(x, y, r, g, b, a * alpha, flags, nil, text)
                end

                local function draw_forward_arrow(x, y, r, g, b, a, alpha)
                    if alpha <= 0 then
                        return
                    end

                    local flags, text = '+', '^'

                    local text_size = vector(
                        renderer.measure_text(
                            flags, text
                        )
                    )

                    x = x - round(text_size.x / 2)
                    y = y - round(text_size.y * 0.5)

                    renderer.text(x, y, r, g, b, a * alpha, flags, nil, text)
                end

                local function draw_arrows()
                    local r, g, b, a = ref.color_accent:get()

                    local screen_size = vector(
                        client.screen_size()
                    )

                    local position = screen_size / 2

                    draw_left_arrow(position.x - PADDING * left_value, position.y, r, g, b, a, left_value)
                    draw_right_arrow(position.x + PADDING * right_value, position.y, r, g, b, a, right_value)

                    draw_forward_arrow(position.x, position.y - PADDING * forward_value, r, g, b, a, forward_value)
                end

                function draw_default()
                    local me = entity.get_local_player()

                    if me == nil then
                        return
                    end

                    update_values(me)
                    draw_arrows()
                end
            end

            local draw_alternative do
                local PADDING = 40

                local function draw_arrows()
                    local screen_size = vector(
                        client.screen_size()
                    )

                    local position = screen_size / 2

                    local color_accent = color(ref.color_accent:get())
                    local color_secondary = color(ref.color_secondary:get())

                    local desync_angle = antiaim.buffer.body_yaw_offset

                    local x_offset = PADDING
                    local rect_size = 2

                    local width = 13
                    local height = 9

                    local color_inactive = color(35, 35, 35, 150)

                    local left_manual = manual_value == 'left' and color_accent or color_inactive
                    local right_manual = manual_value == 'right' and color_accent or color_inactive

                    local left_desync = (desync_angle ~= nil and desync_angle < 0) and color_secondary or color_inactive
                    local right_desync = (desync_angle ~= nil and desync_angle > 0) and color_secondary or color_inactive

                    local left_x = position.x - x_offset - (rect_size + 2)
                    local right_x = position.x + x_offset + (rect_size + 2)

                    left_desync = left_desync:clone()
                    right_desync = right_desync:clone()

                    renderer.triangle(left_x - width, position.y, left_x, position.y - height, left_x, position.y + height, left_manual:unpack())
                    renderer.triangle(right_x + width, position.y, right_x, position.y - height, right_x, position.y + height, right_manual:unpack())

                    renderer.rectangle(left_x + rect_size + 2, position.y - height, -rect_size, height * 2, left_desync:unpack())
                    renderer.rectangle(right_x - rect_size - 2, position.y - height, rect_size, height * 2, right_desync:unpack())
                end

                function draw_alternative()
                    local me = entity.get_local_player()

                    if me == nil or not entity.is_alive(me) then
                        return
                    end

                    draw_arrows()
                end
            end

            local callbacks do
                local function on_style(item)
                    local value = item:get()

                    utils.event_callback('paint_ui', draw_default, value == 'Default')
                    utils.event_callback('paint_ui', draw_alternative, value == 'Alternative')
                end

                local function on_enabled(item)
                    local value = item:get()

                    if value then
                        ref.style:set_callback(on_style, true)
                    else
                        ref.style:unset_callback(on_style)
                    end

                    if not value then
                        utils.event_callback('paint_ui', draw_default, false)
                        utils.event_callback('paint_ui', draw_alternative, false)
                    end
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end

        local velocity_warning do
            local ref = ref.visuals.velocity_warning

            local alpha_value = 0

            local function draw_bar(x, y, w, h, r, g, b, a, alpha)
                render.glow(x, y, w, h, r, g, b, a * alpha * 0.075, 1, 8)
                renderer.rectangle(x, y, w, h, 0, 0, 0, a / 2 * alpha)
            end

            local function on_paint()
                local me = entity.get_local_player()

                if me == nil then
                    return
                end

                local screen_size = vector(
                    client.screen_size()
                )

                local position = vector(
                    screen_size.x * 0.5,
                    ref.offset:get() * 2
                )

                local is_alive = entity.is_alive(me)
                local is_menu_open = ui.is_menu_open()

                local velocity_modifier = entity.get_prop(
                    me, 'm_flVelocityModifier'
                )

                if not is_alive then
                    velocity_modifier = 1.0
                end

                local should_interp = is_menu_open or (is_alive and velocity_modifier < 1.0)

                alpha_value = motion.interp(alpha_value, should_interp, 0.05)

                if alpha_value <= 0 then
                    return
                end

                local fill_color = color(
                    ref.color:get()
                )

                local text_color = color(
                    255, 255, 255, 200
                )

                text_color.a = text_color.a * alpha_value

                local flags, text = '', string.format(
                    'Your velocity is reduced by %d%%',
                    (1 - velocity_modifier) * 100
                )

                local text_size = vector(
                    renderer.measure_text(flags, text)
                )

                local text_pos = position + vector(
                    -text_size.x * 0.5 + 1, 0
                )

                renderer.text(text_pos.x, text_pos.y, text_color.r, text_color.g, text_color.b, text_color.a, flags, nil, text)

                position.y = position.y + text_size.y + 7

                if fill_color.a > 0 then
                    local rect_size = vector(180, 4)

                    local rect_pos = position + vector(
                        -rect_size.x * 0.5, 0
                    )

                    draw_bar(
                        rect_pos.x, rect_pos.y, rect_size.x, rect_size.y,
                        fill_color.r, fill_color.g, fill_color.b, fill_color.a,
                        alpha_value
                    )

                    renderer.rectangle(
                        rect_pos.x + 1, rect_pos.y + 1, (rect_size.x - 2) * velocity_modifier, rect_size.y - 2,
                        fill_color.r, fill_color.g, fill_color.b, fill_color.a * alpha_value
                    )
                end
            end

            local callbacks do
                local function on_enabled(item)
                    local value = item:get()

                    utils.event_callback(
                        'paint',
                        on_paint,
                        value
                    )
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end

        local debug_panel do
            local ref_correction = ref.ragebot.correction
            local ref = ref.visuals.debug_panel

            local window do
                local screen = vector(
                    client.screen_size()
                )

                window = windows.new(
                    'debug_panel',
                    10, screen.y * 0.5
                )
            end

            local function on_paint()
                local position = window.pos:clone()

                local buffer = { } do
                    local threat = client.current_threat()

                    table.insert(buffer, string.format('%s.lua ~ %s', script.name, script.user))
                    table.insert(buffer, string.format('version: %s', script.build))

                    table.insert(buffer, '')

                    table.insert(buffer, string.format('exploit: %s', exploit.get().shift))
                    table.insert(buffer, string.format('defensive: %s', exploit.get().defensive.left > 0))

                    table.insert(buffer, '')

                    table.insert(buffer, string.format('desync angle: %d', localplayer.delta))

                    if threat ~= nil then
                        local name = entity.get_player_name(threat)

                        table.insert(buffer, '')
                        table.insert(buffer, string.format('target: %s', name))

                        local correction = rage.correction.get_player_info(threat)

                        if correction ~= nil and ref_correction.enabled:get() then
                            table.insert(buffer, string.format('- yaw: %.2f', correction.yaw))
                            table.insert(buffer, string.format('- yaw delta: %.2f', correction.yaw_delta))
                            table.insert(buffer, string.format('- simtime delta: %d', correction.simtime_delta))
                        end
                    end
                end

                local flags, text = '', table.concat(buffer, '\n')

                local text_size = vector(
                    renderer.measure_text(flags, text)
                )

                local text_color = color(ref.color:get())

                renderer.text(position.x, position.y, text_color.r, text_color.g, text_color.b, text_color.a, flags, nil, text)

                window:set_size(text_size)
                window:update()
            end

            local callbacks do
                local function on_enabled(item)
                    utils.event_callback('paint', on_paint, item:get())
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end

        local bomb_indicator do
            local ref = ref.visuals.bomb_indicator

            local alpha_value = 0

            local window do
                local screen = vector(
                    client.screen_size()
                )

                window = windows.new(
                    'bomb_indicator',
                    screen.x * 0.5,
                    screen.y * 0.15
                )

                window:set_anchor(
                    vector(0.5, 0.0)
                )

                window:set_size(
                    vector(180, 38)
                )
            end

            local function draw_bar(x, y, w, h, r, g, b, a, alpha)
                render.glow(x, y, w, h, r, g, b, a * alpha * 0.075, 1, 8)
                renderer.rectangle(x, y, w, h, 0, 0, 0, a / 2 * alpha)
            end

            local function get_planted_bomb()
                return entity.get_all 'CPlantedC4' [1]
            end

            local function on_paint()
                local me = entity.get_local_player()

                if me == nil then
                    return
                end

                local bomb = get_planted_bomb()

                local is_bomb_ticking = bomb ~= nil and
                    entity.get_prop(bomb, 'm_bBombTicking') == 1

                local should_draw = ui.is_menu_open() or is_bomb_ticking

                alpha_value = motion.interp(
                    alpha_value, should_draw, 0.05
                )

                if alpha_value <= 0.0 then
                    return
                end

                local position = window.pos:clone()

                local bomb_site = bomb ~= nil and entity.get_prop(bomb, 'm_nBombSite') or 0
                local bomb_defuser = bomb ~= nil and entity.get_prop(bomb, 'm_hBombDefuser') or nil

                local time_remaining = 0.0
                local fill_percentage = 1.0

                local bar_color = color()

                local text = string.format(
                    'Bomb planted at %s site',
                    bomb_site == 0 and 'A' or 'B'
                )

                if bomb ~= nil then
                    local is_defused = entity.get_prop(bomb, 'm_bBombDefused')

                    if is_defused == 0 then
                        local length = entity.get_prop(bomb, 'm_flTimerLength')
                        local blow_time = entity.get_prop(bomb, 'm_flC4Blow')

                        time_remaining = math.max(0.0, blow_time - globals.curtime())
                        fill_percentage = time_remaining / length
                    end
                end

                local good_color = color(ref.good_color:get())
                local bad_color = color(ref.bad_color:get())

                bar_color = bad_color:lerp(good_color, fill_percentage)

                if bomb_defuser ~= nil then
                    text = string.format(
                        'Bomb defused by %s',
                        entity.get_player_name(bomb_defuser)
                    )

                    local length = entity.get_prop(bomb, 'm_flDefuseLength')
                    local blow_time = entity.get_prop(bomb, 'm_flC4Blow')
                    local count_down = entity.get_prop(bomb, 'm_flDefuseCountDown')

                    time_remaining = math.max(0, count_down - globals.curtime())
                    fill_percentage = time_remaining / length

                    if count_down < blow_time then
                        bar_color = color(40, 80, 255, 255)
                    else
                        bar_color = color(255, 40, 40, 255)
                    end
                end

                local timer_text = string.format(
                    '%.1fs.', time_remaining
                )

                local text_size = vector(
                    renderer.measure_text(flags, text)
                )

                local timer_size = vector(
                    renderer.measure_text(flags, timer_text)
                )

                local bar_size = vector(180, 4)

                local max_size = vector(
                    math.max(text_size.x, bar_size.x, timer_size.x),
                    text_size.y + bar_size.y + 5 + timer_size.y + 5
                )

                local render_pos = position:clone()

                local text_render do
                    local text_pos = render_pos + vector(
                        (max_size.x - text_size.x) / 2, 0
                    )

                    local text_color = color(
                        255, 255, 255, 255
                    )

                    text_color.a = text_color.a * alpha_value

                    renderer.text(text_pos.x, text_pos.y, text_color.r, text_color.g, text_color.b, text_color.a, '', nil, text)

                    render_pos.y = render_pos.y + text_size.y + 5
                end

                local bar_render do
                    local bar_pos = render_pos + vector(
                        (max_size.x - bar_size.x) / 2, 0
                    )

                    bar_color.a = bar_color.a * alpha_value

                    draw_bar(bar_pos.x, bar_pos.y, bar_size.x, bar_size.y, bar_color.r, bar_color.g, bar_color.b, bar_color.a, alpha_value)

                    renderer.rectangle(
                        bar_pos.x + 1, bar_pos.y + 1, (bar_size.x - 2) * fill_percentage, bar_size.y - 2,
                        bar_color.r, bar_color.g, bar_color.b, bar_color.a
                    )

                    render_pos.y = render_pos.y + bar_size.y + 5
                end

                local timer_render do
                    local text_pos = render_pos + vector(
                        (max_size.x - timer_size.x) / 2, 0
                    )

                    local timer_color = color(
                        255, 255, 255, 255
                    )

                    timer_color.a = timer_color.a * alpha_value

                    renderer.text(text_pos.x, text_pos.y, timer_color.r, timer_color.g, timer_color.b, timer_color.a, '', nil, timer_text)
                end

                window:set_size(max_size)
                window:update()
            end

            local callbacks do
                local function on_enabled(item)
                    local value = item:get()

                    utils.event_callback(
                        'paint',
                        on_paint,
                        value
                    )
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end

        local gamesense_indicator do
            local ref_aa_freestanding = ref.antiaim.settings.freestanding
            local ref = ref.visuals.gamesense_indicator

            local ref_third_person = {
                ui.reference('Visuals', 'Effects', 'Force third person (alive)')
            }

            local PARAMETERS do
                local ref_force_safe_point = ui.reference(
                    'Rage', 'Aimbot', 'Force safe point'
                )

                local ref_force_body_aim = ui.reference(
                    'Rage', 'Aimbot', 'Force body aim'
                )

                local ref_ping_spike = {
                    ui.reference('Misc', 'Miscellaneous', 'Ping spike')
                }

                local ref_double_tap = {
                    ui.reference('Rage', 'Aimbot', 'Double tap')
                }

                local ref_on_shot_antiaim = {
                    ui.reference('AA', 'Other', 'On shot anti-aim')
                }

                local ref_duck_peek_assist = ui.reference(
                    'Rage', 'Other', 'Duck peek assist'
                )

                local ref_freestanding = {
                    ui.reference('AA', 'Anti-aimbot angles', 'Freestanding')
                }

                local ref_minimum_damage_override = {
                    ui.reference('Rage', 'Aimbot', 'Minimum damage override')
                }

                PARAMETERS = {
                    ['Safe Point'] = {
                        is_active = function()
                            return ui.get(ref_force_safe_point)
                        end,

                        get_text = function()
                            return 'SAFE'
                        end,

                        get_color = function()
                            return color(255, 255, 255, 200)
                        end
                    },

                    ['Body Aim'] = {
                        is_active = function()
                            return ui.get(ref_force_body_aim)
                        end,

                        get_text = function()
                            return 'BODY'
                        end,

                        get_color = function()
                            return color(255, 255, 255, 200)
                        end
                    },

                    ['Ping Spike'] = {
                        is_active = function()
                            return ui.get(ref_ping_spike[1])
                                and ui.get(ref_ping_spike[2])
                        end,

                        get_text = function(self)
                            return 'PING'
                        end,

                        get_color = function()
                            return color(150, 200, 25, 200)
                        end
                    },

                    ['Double Tap'] = {
                        is_active = function()
                            if ui.get(ref_duck_peek_assist) then
                                return false
                            end

                            return ui.get(ref_double_tap[1])
                                and ui.get(ref_double_tap[2])
                        end,

                        get_text = function(self)
                            return 'DT'
                        end,

                        get_color = function()
                            return exploit.get().shift
                                and color(255, 255, 255, 200)
                                or color(255, 0, 50, 255)
                        end
                    },

                    ['Fake Duck'] = {
                        is_active = function()
                            return ui.get(ref_duck_peek_assist)
                        end,

                        get_text = function(self)
                            return 'DUCK'
                        end,

                        get_color = function()
                            return color(255, 255, 255, 200)
                        end
                    },

                    ['Freestanding'] = {
                        is_active = function()
                            return ref_aa_freestanding.enabled:get()
                                and ref_aa_freestanding.hotkey:get()
                        end,

                        get_text = function(self)
                            return 'FS'
                        end,

                        get_color = function()
                            return color(255, 255, 255, 200)
                        end
                    },

                    ['Hide Shots'] = {
                        is_active = function()
                            if ui.get(ref_duck_peek_assist) then
                                return false
                            end

                            local is_double_tap = (
                                ui.get(ref_double_tap[1])
                                and ui.get(ref_double_tap[2])
                            )

                            if is_double_tap then
                                return false
                            end

                            return ui.get(ref_on_shot_antiaim[1])
                                and ui.get(ref_on_shot_antiaim[2])
                        end,

                        get_text = function(self)
                            return 'OSAA'
                        end,

                        get_color = function()
                            return color(255, 255, 255, 200)
                        end
                    },

                    ['Min. Damage'] = {
                        is_active = function()
                            return ui.get(ref_minimum_damage_override[1])
                                and ui.get(ref_minimum_damage_override[2])
                        end,

                        get_text = function(self)
                            return 'MD'
                        end,

                        get_color = function()
                            return color(255, 255, 255, 200)
                        end
                    },

                    ['Hit Chance'] = {
                        is_active = function()
                            return true
                        end,

                        get_text = function(self)
                            return 'HC'
                        end,

                        get_color = function()
                            return color(255, 255, 255, 200)
                        end
                    }
                }
            end

            local data_values = { }

            local x_value = nil
            local y_value = nil

            local function is_third_person()
                return ui.get(ref_third_person[1])
                    and ui.get(ref_third_person[2])
            end

            local function get_color(params, items)
                if items.change_color:get() then
                    return color(items.color_picker:get())
                end

                return params:get_color()
            end

            local function get_text(params, items)
                local value = items.custom_name:get()

                if value == '' then
                    value = params:get_text()
                end

                return value
            end

            local function draw_shadow(x, y, w, h)
                local half_width = math.floor(w / 2)

                renderer.gradient(x, y, half_width, h, 0, 0, 0, 0, 0, 0, 0, 55, true)
                renderer.gradient(x + half_width, y, w - half_width, h, 0, 0, 0, 55, 0, 0, 0, 0, true)
            end

            local function on_paint()
                local me = entity.get_local_player()

                if me == nil or not entity.is_alive(me) then
                    return
                end

                local flags = '+d'

                local screen = vector(
                    client.screen_size()
                )

                local draw_pos = vector(
                    5, screen.y * 0.759
                )

                if ref.follow_in_thirdperson:get() and is_third_person() then
                    local x, y = renderer.world_to_screen(
                        entity.hitbox_position(me, 3)
                    )

                    if x ~= nil and y ~= nil then
                        draw_pos.x = x - 250
                        draw_pos.y = y
                    end
                end

                if x_value == nil then
                    x_value = draw_pos.x
                end

                if y_value == nil then
                    y_value = draw_pos.y
                end

                x_value = motion.interp(x_value, draw_pos.x, 0.05)
                y_value = motion.interp(y_value, draw_pos.y, 0.05)

                local position = vector(
                    x_value, y_value
                )

                for i = 1, #ref.names do
                    local name = ref.names[i]

                    local items = ref[name]
                    local params = PARAMETERS[name]

                    if items == nil or params == nil then
                        goto continue
                    end

                    if data_values[name] == nil then
                        data_values[name] = {
                            alpha = 0.0
                        }
                    end

                    local data = data_values[name]

                    local should_draw = (
                        items.enabled:get()
                        and params:is_active()
                    )

                    data.alpha = motion.interp(
                        data.alpha, should_draw, 0.05
                    )

                    if data.alpha <= 0.0 then
                        goto continue
                    end

                    local col = get_color(params, items)
                    local text = get_text(params, items)

                    local text_size = vector(
                        renderer.measure_text(flags, text)
                    )

                    local text_pos = position + vector(24, 2)
                    local fade_size = text_size + vector(50, 4)

                    if should_draw then
                        draw_shadow(position.x, position.y, fade_size.x, fade_size.y)
                        renderer.text(text_pos.x, text_pos.y, col.r, col.g, col.b, col.a, flags, nil, text)
                    end

                    position.y = position.y - (fade_size.y + 8) * data.alpha

                    ::continue::
                end
            end

            local function on_indicator(e)
                -- dummy callback
            end

            local callbacks do
                local function on_enabled(item)
                    local value = item:get()

                    utils.event_callback('paint', on_paint, value)
                    utils.event_callback('indicator', on_indicator, value)
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end

        local bullet_tracers do
            local ref = ref.visuals.bullet_tracers

            local queue = { }

            local function on_paint()
                local curtime = globals.curtime()
                local r, g, b, a = ref.color:get()

                for i = #queue, 1, -1 do
                    local data = queue[i]

                    local should_appear = (
                        curtime < data.end_time
                    )

                    data.alpha = motion.interp(
                        data.alpha, should_appear, 0.1
                    )

                    if not should_appear and data.alpha <= 0.0 then
                        table.remove(queue, i)
                    end
                end

                for i = 1, #queue do
                    local data = queue[i]

                    local x1, y1 = renderer.world_to_screen(data.start_pos:unpack())
                    local x2, y2 = renderer.world_to_screen(data.end_pos:unpack())

                    if x1 ~= nil and x2 ~= nil then
                        renderer.line(x1, y1, x2, y2, r, g, b, a * data.alpha)
                    end
                end
            end

            local function on_bullet_impact(e)
                local me = entity.get_local_player()
                local userid = client.userid_to_entindex(e.userid)

                if me ~= userid then
                    return
                end

                table.insert(queue, {
                    start_pos = vector(client.eye_position()),
                    end_pos = vector(e.x, e.y, e.z),
                    end_time = globals.curtime() + ref.duration:get() * 0.1,
                    alpha = 0.0
                })
            end

            local callbacks do
                local function on_enabled(item)
                    local value = item:get()

                    utils.event_callback('paint', on_paint, value)
                    utils.event_callback('bullet_impact', on_bullet_impact, value)
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end
    end

    local misc = { } do
        local clantag do
            local ref = ref.misc.clantag

            local old_text = nil

            local animation = { } do
                local name = 'revelation'
                local build = script.build

                table.insert(animation, 'a')
                table.insert(animation, 'al')
                table.insert(animation, 'alt')
                table.insert(animation, 'alth')
                table.insert(animation, 'althe')
                table.insert(animation, 'revelation')
                table.insert(animation, '~ revelation')
                table.insert(animation, 'd ~ revelation')
                table.insert(animation, 'de ~ revelation')
                table.insert(animation, 'dev ~ revelation')

                for _ = 1, 6 do
                    table.insert(animation, 'revelation')
                end

                local name_len = #name
                local build_len = #build

                local name_seq = name_len
                local build_seq = build_len * 2

                local full_seq = math.max(
                    name_seq, build_seq
                )

                for i = 1, full_seq do
                    local left = ''
                    local right = ''

                    if i > 1 and i <= build_len + 1 then
                        left = build:sub(1, i - 1)
                    end

                    if i > build_len + 1 and i <= build_seq then
                        left = build:sub(i - build_len, build_len)
                    end

                    if i <= name_seq then
                        right = name:sub(i, name_len)
                    end

                    table.insert(animation, string.format('%s ~ %s', left, right))
                end
            end

            local function set_clan_tag(text)
                if old_text ~= text then
                    old_text = text

                    client.set_clan_tag(text)

                    client.delay_call(0.3, function()
                        if old_text == text then
                            client.set_clan_tag(text)
                        end
                    end)
                end
            end

            local function unset_clan_tag()
                client.set_clan_tag('')

                client.delay_call(
                    0.3, client.set_clan_tag, ''
                )

                old_text = nil
            end

            local function on_shutdown()
                unset_clan_tag()
            end

            local function on_net_update_start()
                local len = #animation

                local time = globals.curtime() * 5
                local index = (math.floor(time) % len) + 1

                set_clan_tag(animation[index])
            end

            local callbacks do
                local function on_enabled(item)
                    local value = item:get()

                    if not value then
                        unset_clan_tag()
                    end

                    utils.event_callback(
                        'shutdown',
                        on_shutdown,
                        value
                    )

                    utils.event_callback(
                        'net_update_start',
                        on_net_update_start,
                        value
                    )
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end

        local trashtalk do
            local ref = ref.misc.trashtalk

            local PHRASES = {
                kill = {
                    1, {
                        { 'god bless no stress ты опущен by revelation хуесос' },
                        { 'owned by s1l3nceeeer corporation' },
                        { 'еду в москов сити' },
                        { 'depre??ed' },
                        { 'ceo moscow' },
                        { 'закуриваю вишневы чап','1' },
                        { '#ONLYLUCK'},
                    }
                },

                death = {
                    1, {
                        { '??' },
                    }
                }
            }

            local b = 0

            local function shuffle(t)
                for i = #t, 2, -1 do
                    local j = math.random(i)
                    t[i], t[j] = t[j], t[i]
                end
            end

            local function process_phrases(list)
                if list == nil then
                    return
                end

                local table = list[2][list[1]]

                list[1] = list[1] + 1

                if list[1] == #list[2] then
                    list[1] = 1
                    shuffle(list[2])
                end

                b = b + 1

                local a = b

                for i = 1, #table do
                    client.delay_call(i * 2, function()
                        if b == a then
                            client.exec('say "' .. table[i] .. '"')
                        end
                    end)
                end
            end

            local function on_player_death(e)
                local game_rules = entity.get_game_rules()

                if game_rules == nil then
                    return
                end

                local is_warmup_period = entity.get_prop(game_rules, 'm_bWarmupPeriod')

                if is_warmup_period == 1 then
                    return
                end

                local me = entity.get_local_player()

                local userid = client.userid_to_entindex(e.userid)
                local attacker = client.userid_to_entindex(e.attacker)

                if me ~= attacker or me == userid then
                    return
                end

                local list = nil

                if attacker == me then
                    list = PHRASES.kill
                elseif userid == me then
                    list = PHRASES.death
                end

                process_phrases(list)
            end

            local callbacks do
                local function on_enabled(item)
                    local value = item:get()

                    utils.event_callback(
                        'player_death',
                        on_player_death,
                        value
                    )
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end

            math.randomseed(client.unix_time())

            shuffle(PHRASES.kill[2])
            shuffle(PHRASES.death[2])
        end

        local fast_ladder do
            local ref = ref.misc.fast_ladder

            local MOVETYPE_LADDER = 9

            local function is_throwing_grenade(weapon)
                local weapon_info = csgo_weapons(weapon)

                if weapon_info.weapon_type_int ~= 9 then
                    return false
                end

                local throw_time = entity.get_prop(weapon, 'm_fThrowTime')

                if throw_time == 0 then
                    return false
                end

                return true
            end

            local function on_setup_command(cmd)
                local me = entity.get_local_player()

                if me == nil then
                    return
                end

                local weapon = entity.get_player_weapon(me)

                if weapon ~= nil and is_throwing_grenade(weapon) then
                    return
                end

                local movetype = entity.get_prop(me, 'm_movetype')

                if movetype ~= MOVETYPE_LADDER then
                    return
                end

                local pitch = client.camera_angles()

				cmd.yaw = round(cmd.yaw)
				cmd.roll = 0

				if cmd.forwardmove > 0 and pitch < 45 then
					cmd.pitch = 89
					cmd.in_moveright, cmd.in_moveleft, cmd.in_forward, cmd.in_back = 1, 0, 0, 1

					if cmd.sidemove == 0 then cmd.yaw = cmd.yaw + 90 end
					if cmd.sidemove < 0 then cmd.yaw = cmd.yaw + 150 end
					if cmd.sidemove > 0 then cmd.yaw = cmd.yaw + 30 end
				elseif cmd.forwardmove < 0 then
					cmd.pitch = 89
					cmd.in_moveleft, cmd.in_moveright, cmd.in_forward, cmd.in_back = 1, 0, 1, 0

					if cmd.sidemove == 0 then cmd.yaw = cmd.yaw + 90 end
					if cmd.sidemove > 0 then cmd.yaw = cmd.yaw + 150 end
					if cmd.sidemove < 0 then cmd.yaw = cmd.yaw + 30 end
				end
            end

            local callbacks do
                local function on_enabled(item)
                    utils.event_callback(
                        'setup_command',
                        on_setup_command,
                        item:get()
                    )
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end

        local animation_breaker do
            local ref = ref.misc.animation_breaker

            local MOVETYPE_WALK = 2

            local ANIMATION_LAYER_MOVEMENT_MOVE = 6
            local ANIMATION_LAYER_LEAN = 12

            local function update_onground(player)
                local entity_info = c_entity(player)

                if entity_info == nil then
                    return
                end

                if localplayer.is_onground then
                    local value = ref.onground_legs:get()

                    if value == 'Static' then
                        override.set(software.antiaimbot.other.leg_movement, 'Always slide')
                        entity.set_prop(player, 'm_flPoseParameter', 0, 0)

                        return
                    end

                    if value == 'Jitter' then
                        local mul = utils.random_float(
                            ref.onground_jitter_min_value:get() * 0.01,
                            ref.onground_jitter_max_value:get() * 0.01
                        )

                        override.set(software.antiaimbot.other.leg_movement, 'Always slide')
                        entity.set_prop(player, 'm_flPoseParameter', 1, globals.tickcount() % 4 > 1 and mul or 1)

                        return
                    end

                    if value == 'Moonwalk' then
                        override.set(software.antiaimbot.other.leg_movement, 'Never slide')
                        entity.set_prop(player, 'm_flPoseParameter', 0, 7)

                        local layer_move = entity_info:get_anim_overlay(
                            ANIMATION_LAYER_MOVEMENT_MOVE
                        )

                        if layer_move == nil then
                            return
                        end

                        layer_move.weight = 1

                        return
                    end
                end

                override.unset(software.antiaimbot.other.leg_movement)
            end

            local function update_in_air(player)
                local value = ref.in_air_legs:get()

                if value == 'off' then
                    return
                end

                if localplayer.is_onground then
                    return
                end

                if value == 'Static' then
                    entity.set_prop(player, 'm_flPoseParameter', ref.in_air_static_value:get() * 0.01, 6)

                    return
                end

                if value == 'Moonwalk' then
                    if not localplayer.is_moving then
                        return
                    end

                    local entity_info = c_entity(player)

                    if entity_info == nil then
                        return
                    end

                    local layer_move = entity_info:get_anim_overlay(
                        ANIMATION_LAYER_MOVEMENT_MOVE
                    )

                    if layer_move == nil then
                        return
                    end

                    layer_move.weight = 1

                    return
                end
            end

            local function update_earthquake(player)
                if not ref.earthquake:get() then
                    return
                end

                local entity_info = c_entity(player)

                if entity_info == nil then
                    return
                end

                local layer_lean = entity_info:get_anim_overlay(
                    ANIMATION_LAYER_LEAN
                )

                if layer_lean == nil then
                    return
                end

                layer_lean.weight = utils.lerp(
                    layer_lean.weight,
                    utils.random_float(0, 1),
                    ref.earthquake_value:get() * 0.01
                )
            end

            local function update_body_lean(player)
                local value = ref.adjust_lean:get()

                if value == 0 then
                    return
                end

                local entity_info = c_entity(player)

                if entity_info == nil then
                    return
                end

                local layer_lean = entity_info:get_anim_overlay(
                    ANIMATION_LAYER_LEAN
                )

                if layer_lean == nil then
                    return
                end

                local me = entity.get_local_player()

                if me == nil or not entity.is_alive(me) then
                    return
                end

                local x_velocity = entity.get_prop(me, "m_vecVelocity[0]")

                if math.abs(x_velocity) >= 3 then
                    layer_lean.weight = value * 2
                end
            end

            local function update_pitch_on_land(player)
                if not ref.pitch_on_land:get() then
                    return
                end

                if not localplayer.is_onground then
                    return
                end

                local entity_info = c_entity(player)

                if entity_info == nil then
                    return
                end

                local animstate = entity_info:get_anim_state()

                if animstate == nil or not animstate.hit_in_ground_animation then
                    return
                end

                entity.set_prop(player, 'm_flPoseParameter', 0.5, 12)
            end

            local function on_pre_render()
                local me = entity.get_local_player()

                if me == nil then
                    return
                end

                local movetype = entity.get_prop(
                    me, 'm_movetype'
                )

                if movetype == MOVETYPE_WALK then
                    update_onground(me)
                    update_in_air(me)
                    update_pitch_on_land(me)
                end

                update_body_lean(me)
                update_earthquake(me)
            end

            local callbacks do
                local function on_enabled(item)
                    local value = item:get()

                    if not value then
                        override.unset(software.antiaimbot.other.leg_movement)
                    end

                    utils.event_callback('pre_render', on_pre_render, value)
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end

        local walking_on_quick_peek do
            local ref = ref.misc.walking_on_quick_peek

            local MOVETYPE_WALK = 2

            local IN_FORWARD   = bit.lshift(1, 3)
            local IN_BACK      = bit.lshift(1, 4)
            local IN_MOVELEFT  = bit.lshift(1, 9)
            local IN_MOVERIGHT = bit.lshift(1, 10)

            local function on_finish_command(e)
                if not software.is_quick_peek_assist() then
                    return
                end

                local me = entity.get_local_player()

                if me == nil then
                    return
                end

                local movetype = entity.get_prop(
                    me, 'm_movetype'
                )

                if movetype ~= MOVETYPE_WALK then
                    return
                end

                local cmd = iinput.get_usercmd(
                    0, e.command_number
                )

                if cmd == nil then
                    return
                end

                cmd.buttons = bit.band(cmd.buttons, bit.bnot(IN_FORWARD))
                cmd.buttons = bit.band(cmd.buttons, bit.bnot(IN_BACK))
                cmd.buttons = bit.band(cmd.buttons, bit.bnot(IN_MOVELEFT))
                cmd.buttons = bit.band(cmd.buttons, bit.bnot(IN_MOVERIGHT))
            end

            local callbacks do
                local function on_enabled(item)
                    utils.event_callback(
                        'finish_command',
                        on_finish_command,
                        item:get()
                    )
                end

                ref.enabled:set_callback(
                    on_enabled, true
                )
            end
        end
    end
end
