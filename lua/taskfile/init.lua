-- task_picker.lua
local T = {}

-- Require necessary Telescope modules
local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')
local pickers = require('telescope.pickers')
local finders = require('telescope.finders')
local conf = require('telescope.config').values
local previewers = require('telescope.previewers')
local entry_display = require('telescope.pickers.entry_display')


-- Default options for the picker
local default_opts = {
    task_terminal = "terminal", -- Command to open terminal (adjust as needed)
    prompt_title = "Task Picker",
    results_title = "Tasks",
    layout_strategy = 'horizontal',
    layout_config = {
        width = 0.6,
        height = 0.5,
        preview_width = 0.4,
        preview_height = 0.3,
    },
    border = true,
    borderchars = { '─', '│', '─', '│', '╭', '╮', '╯', '╰' },
    winblend = 10,
    highlight = { -- New highlight options
        TaskName = {
            fg = "#000000",      -- Matte black text
            bg = "#FFA500",      -- Faded orange background
            gui = "bold",        -- Bold text
        },
        TaskDescription = {
            fg = "#a0a0a0",      -- Faded grey text
            bg = "NONE",         -- No background
            gui = "NONE",        -- No special formatting
        },
    },
}

-- Setup function to allow user to override default options
function T.setup(user_opts)
    default_opts = vim.tbl_deep_extend('force', default_opts, user_opts or {})

    -- Apply custom highlight groups
    local colors = default_opts.highlight

    -- Define TaskName highlight group
    vim.api.nvim_set_hl(0, "TaskName", {
        fg = colors.TaskName.fg or "#ffffff",
        bg = colors.TaskName.bg or "#007acc",
        bold = colors.TaskName.gui == "bold",
        italic = colors.TaskName.gui == "italic",
    })

    -- Define TaskDescription highlight group
    vim.api.nvim_set_hl(0, "TaskDescription", {
        fg = colors.TaskDescription.fg or "#c0c0c0",
        bg = colors.TaskDescription.bg or "NONE",
        bold = colors.TaskDescription.gui == "bold",
        italic = colors.TaskDescription.gui == "italic",
    })
end

-- Function to check if yq is installed
local function is_yq_installed()
    local handle = io.popen("yq --version 2>&1")
    if not handle then
        return false
    end
    local result = handle:read("*a")
    handle:close()
    return result and result:match("^yq") ~= nil
end

-- Function to read and parse Taskfile.yml using yq
local function read_taskfile(taskfile_path)
    if not taskfile_path then
        vim.notify("Taskfile path is not provided.", vim.log.levels.ERROR)
        return nil
    end

    if not is_yq_installed() then
        vim.notify("yq is not installed or not found in PATH.", vim.log.levels.ERROR)
        return nil
    end

    -- Verify that Taskfile.yml exists
    local file = io.open(taskfile_path, "r")
    if not file then
        vim.notify("Taskfile.yml not found at " .. taskfile_path, vim.log.levels.ERROR)
        return nil
    end
    file:close()

    -- Parse the YAML file's tasks section into JSON
    local handle = io.popen(string.format("yq eval -o=json '.tasks' %s", taskfile_path))
    if not handle then
        vim.notify("Failed to execute yq command.", vim.log.levels.ERROR)
        return nil
    end

    local result = handle:read("*a")
    handle:close()

    if not result or result == "" then
        vim.notify("yq returned an empty result.", vim.log.levels.ERROR)
        return nil
    end

    -- Decode the JSON result into a Lua table
    local success, parsed = pcall(vim.fn.json_decode, result)
    if not success then
        vim.notify("Failed to decode JSON from yq output: " .. tostring(parsed), vim.log.levels.ERROR)
        return nil
    end

    if type(parsed) ~= "table" or vim.tbl_isempty(parsed) then
        vim.notify("No tasks found in Taskfile.yml.", vim.log.levels.WARN)
        return nil
    end

    return parsed
end

-- Function to create a display for each entry using entry_display
local function make_display(entry, context)
    local displayer = entry_display.create({
        separator = " ",
        items = {
            { width = 30 }, -- Task name column
            { remaining = true }, -- Description column
        },
    })

    return displayer({
        { entry.value, "TaskName" },
        { " - " .. (entry.display_desc or ""), "TaskDescription" },
    })
end

-- Function to pick and run a task
function T.pick_task(opts)
    opts = vim.tbl_deep_extend('force', default_opts, opts or {})

    local taskfile_path = opts.taskfile_path or "./Taskfile.yml"
    local tasks = read_taskfile(taskfile_path)

    if not tasks then
        return
    end

    -- Prepare the task list for Telescope
    local task_list = {}
    for task_name, task_data in pairs(tasks) do
        -- Ensure task_data is a table
        if type(task_data) ~= "table" then
            vim.notify(string.format("Invalid task data for '%s'. Expected a table.", task_name), vim.log.levels.WARN)
            goto continue
        end

        local desc = task_data.desc or ""
        local cmds = task_data.cmds or {}

        -- Validate cmds is a table
        if type(cmds) ~= "table" then
            vim.notify(string.format("Invalid cmds for task '%s'. Expected a table of commands.", task_name), vim.log.levels.WARN)
            cmds = {}
        end

        local display_desc = desc
        local display = display_desc ~= "" and display_desc or ""

        table.insert(task_list, {
            name = task_name,
            display_desc = display_desc,
            cmds = cmds,
        })

        ::continue::
    end

    if vim.tbl_isempty(task_list) then
        vim.notify("No valid tasks available to display.", vim.log.levels.WARN)
        return
    end

    -- Define a custom previewer to display cmds
    local cmd_previewer = previewers.new_buffer_previewer({
        define_preview = function(self, entry, status)
            local cmds = entry.cmds
            if cmds and #cmds > 0 then
                local content = table.concat(cmds, "\n")
                vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, vim.split(content, "\n"))
            else
                vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, { "No commands available." })
            end
        end,
    })

    -- Create and find the Telescope picker
    pickers.new({}, {
        prompt_title = opts.prompt_title,
        results_title = opts.results_title,
        finder = finders.new_table {
            results = task_list,
            entry_maker = function(entry)
                return {
                    value = entry.name,
                    display = make_display,
                    ordinal = entry.name .. (entry.display_desc or ""),
                    cmds = entry.cmds,
                    display_desc = entry.display_desc,
                }
            end
        },
        sorter = conf.generic_sorter(opts),
        layout_strategy = opts.layout_strategy,
        layout_config = opts.layout_config,
        border = opts.border,
        borderchars = opts.borderchars,
        winblend = opts.winblend,
        previewer = cmd_previewer,
        attach_mappings = function(prompt_bufnr, map)
            local function run_task(selected_task)
                actions.close(prompt_bufnr)

                -- Open the specified terminal
                vim.cmd(opts.task_terminal)

                -- Schedule the commands to run after the terminal is ready
                vim.defer_fn(function()
                    local term_buf = vim.api.nvim_get_current_buf()
                    -- Retrieve the job ID (channel ID) associated with the terminal buffer
                    local job_id = vim.b[term_buf].terminal_job_id

                    if not job_id then
                        vim.notify("Failed to retrieve terminal job ID.", vim.log.levels.ERROR)
                        return
                    end

                    -- Send each command to the terminal's job channel
                    for _, cmd in ipairs(selected_task.cmds) do
                        -- Ensure cmd is a string
                        if type(cmd) == "string" then
                            vim.api.nvim_chan_send(job_id, cmd .. "\n")
                        else
                            vim.notify("Encountered a non-string command. Skipping.", vim.log.levels.WARN)
                        end
                    end
                end, 100) -- Delay in milliseconds to ensure terminal is ready
            end

            -- Map <CR> to run the selected task in insert and normal modes
            map("i", "<CR>", function(bufnr)
                local selected = action_state.get_selected_entry(bufnr)
                if selected then
                    run_task(selected)
                else
                    vim.notify("No task selected.", vim.log.levels.WARN)
                end
            end)

            map("n", "<CR>", function(bufnr)
                local selected = action_state.get_selected_entry(bufnr)
                if selected then
                    run_task(selected)
                else
                    vim.notify("No task selected.", vim.log.levels.WARN)
                end
            end)

            return true
        end
    }):find()
end

return T

