local rt = require("rust-tools")
local utils = require("rust-tools.utils.utils")

local M = {}

-- TODO : Remove me
function tprint(tbl, indent)
    if not indent then indent = 0 end
    local toprint = string.rep(" ", indent) .. "{\r\n"
    indent = indent + 2
    for k, v in pairs(tbl) do
        toprint = toprint .. string.rep(" ", indent)
        if (type(k) == "number") then
            toprint = toprint .. "[" .. k .. "] = "
        elseif (type(k) == "string") then
            toprint = toprint .. k .. "= "
        end
        if (type(v) == "number") then
            toprint = toprint .. v .. ",\r\n"
        elseif (type(v) == "string") then
            toprint = toprint .. "\"" .. v .. "\",\r\n"
        elseif (type(v) == "table") then
            toprint = toprint .. tprint(v, indent + 2) .. ",\r\n"
        else
            toprint = toprint .. "\"" .. tostring(v) .. "\",\r\n"
        end
    end
    toprint = toprint .. string.rep(" ", indent - 2) .. "}"
    return toprint
end

local function get_params()
    return {
        textDocument = vim.lsp.util.make_text_document_params(),
        position = nil, -- get em all
    }
end

local function build_label(args)
    local ret = ""
    for _, value in ipairs(args.cargoArgs) do
        ret = ret .. value .. " "
    end

    for _, value in ipairs(args.cargoExtraArgs or {}) do
        ret = ret .. value .. " "
    end

    if not vim.tbl_isempty(args.executableArgs) then
        ret = ret .. "-- "
        for _, value in ipairs(args.executableArgs) do
            ret = ret .. value .. " "
        end
    end
    return ret
end

local function get_options(result)
    local option_strings = {}
    for _, debuggable in ipairs(result) do
        local label = build_label(debuggable.args)
        local str = label
        table.insert(option_strings, str)
    end

    return option_strings
end

local function is_valid_test(args)
    local is_not_cargo_check = args.cargoArgs[1] ~= "check"
    return is_not_cargo_check
end

-- rust-analyzer doesn't actually support giving a list of debuggable targets,
-- so work around that by manually removing non debuggable targets (only cargo
-- check for now).
-- This function also makes it so that the debuggable commands are more
-- debugging friendly. For example, we move cargo run to cargo build, and cargo
-- test to cargo test --no-run.
local function sanitize_results_for_debugging(result)
    local ret = {}

    ret = vim.tbl_filter(function(value)
        return is_valid_test(value.args)
    end, result)

    for _, value in ipairs(ret) do
        rt.utils.sanitize_command_for_debugging(value.args.cargoArgs)
    end

    return ret
end

local function handler(_, result)
    if result == nil then
        return
    end
    result = sanitize_results_for_debugging(result)

    local options = get_options(result)
    vim.ui.select(
        options,
        { prompt = "Debuggables", kind = "rust-tools/debuggables" },
        function(_, choice)
            if choice == nil then
                return
            end

            local args = result[choice].args
            vim.ui.input({ prompt = "Enter custom arguments: " }, function(input)
                args.custom_args = utils.split_str(input, " ")
            end)
            rt.dap.start(args)

            rt.cached_commands.set_last_debuggable(args)
        end
    )
end

-- Sends the request to rust-analyzer to get the runnables and handles them
-- The opts provided here are forwarded to telescope, other than use_telescope
-- which is used to check whether we want to use telescope or the vanilla vim
-- way for input
function M.debuggables()
    rt.utils.request(0, "experimental/runnables", get_params(), handler)
end

return M
