local T = {}

local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')
local pickers = require('telescope.pickers')
local finders = require('telescope.finders')
local conf = require('telescope.config').values


local default_opts = {
    task_terminal = "term",
    prompt_title = "Don't do it.",
    results_title = "Tasks",
    layout_strategy = 'center',
    width = 0.5,
    height = 0.4,
    border = true,
    borderchars = { '─', '│', '─', '│', '╭', '╮', '╯', '╰' },
    winblend = 10,
}

function T.setup(user_opts)
    default_opts = vim.tbl_extend('force', default_opts, user_opts or {})
end

function T.pick_task(opts)
    opts = vim.tbl_extend('force', default_opts, opts or {}) -- Merge local opts with global opts

    local function read_taskfile()
        local taskfile_path = "./Taskfile.yml"
        local taskfile = io.open(taskfile_path, "r")

        if not taskfile then
            print("Taskfile.yml not found")
            return nil
        end

        local tasks = {}
        local task_name = nil

        for line in taskfile:lines() do
            local name = line:match("^%s*'([^']+)'%s*:")
            if name then
                task_name = name
                tasks[task_name] = {}
            end

            local cmd = line:match("^%s*-%s*\"([^\"]+)\"")
            if cmd and task_name then
                table.insert(tasks[task_name], cmd)
            end
        end

        taskfile:close()
        return tasks
    end

    local tasks = read_taskfile()

    if not tasks then
        return
    end

    local task_list = {}
    for task, _ in pairs(tasks) do
        table.insert(task_list, task)
    end

    pickers.new({}, {
        prompt_title = opts.prompt_title,
        results_title = opts.results_title,
        finder = finders.new_table {
            results = task_list,
        },
        sorter = conf.generic_sorter({}),
        layout_strategy = opts.layout_strategy,
        layout_config = {
            width = opts.width,
            height = opts.height,
        },
        border = opts.border,
        borderchars = opts.borderchars,
        winblend = opts.winblend,
        attach_mappings = function(prompt_bufnr, map)

            local function run_task(selected_task)
                actions.close(prompt_bufnr)

                vim.cmd(opts.task_terminal)

                local command = "task " .. selected_task
                vim.api.nvim_feedkeys("i" .. command .. "\n", "n", false)
            end

            map("i", "<CR>", function(bufnr)
                local chosen_one = action_state.get_selected_entry(bufnr)
                run_task(chosen_one.value)
            end)

            map("n", "<CR>", function(bufnr)
                local chosen_one = action_state.get_selected_entry(bufnr)
                run_task(chosen_one.value)
            end)

            return true
        end
    }):find()
end

return T

