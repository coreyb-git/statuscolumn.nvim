local M = {}

-- TODO: fights with smoothscroll
vim.opt.smoothscroll = false

local cache = {}

local C_Update_Func = "%!v:lua.MyStatusColumn()"
local C_End_Cap = "│ "

local statuscolumn_on = true

local statuscolumn_use_cache = false

local saved = {} -- vim.o values

local function save_settings()
	saved = {
		statuscolumn = vim.o.statuscolumn,
		signcolumn = vim.o.signcolumn,
		numberwidth = vim.o.numberwidth,
	}
end

local function set_all_windows(value)
	local windows = vim.api.nvim_list_wins()
	for i = 1, #windows do
		local win = windows[i]
		local buf = vim.api.nvim_win_get_buf(win)
		if vim.bo[buf].buftype == "" then
			vim.wo[win].statuscolumn = value
		end
	end
end

local function update_statuscolumn_state()
	if statuscolumn_on then
		set_all_windows(C_Update_Func)
		vim.o.signcolumn = "yes:1"
		vim.o.numberwidth = 1
	else
		set_all_windows(saved.statuscolumn)
		vim.o.signcolumn = saved.signcolumn
		vim.o.numberwidth = saved.numberwidth
	end
end

local function build_line_string(dap, mark, diag, fold, git, win_id)
	local left = " "
	if dap then
		left = dap
	elseif mark then
		left = mark
	elseif diag then
		left = diag
	end

	local right = " "
	if fold then
		right = fold
	elseif git then
		right = git
	end

	local left_pad = " "
	local right_pad = " "
	local num = "%=%l"

	local no_numbers = false
	if (not vim.wo[win_id].number) and not vim.wo[win_id].relativenumber then
		no_numbers = true
	end
	if no_numbers then
		left_pad = ""
		right_pad = ""
		num = " "
	end
	return " " .. left .. left_pad .. num .. right_pad .. right .. C_End_Cap
end

local function toggle_statuscolumn()
	if not statuscolumn_on then
		save_settings()
		vim.notify("StatusColumn: On")
	else
		vim.notify("StatusColumn: Off")
	end
	statuscolumn_on = not statuscolumn_on
	update_statuscolumn_state()
end

-- Relieve pressure when scrolling

local function buftype_can_edit(args)
	local win_id = tonumber(args.match)
	if not win_id then
		return false
	end

	local bufnr = vim.api.nvim_win_get_buf(win_id)
	if vim.bo[bufnr].buftype == "" then
		return true
	end
	return false
end

-- Reset cache if changing buffer
vim.api.nvim_create_autocmd("BufEnter", {
	callback = function(args)
		cache = {}
	end,
})

-- Use cache while scrolling
vim.api.nvim_create_autocmd("WinScrolled", {
	callback = function(args)
		if (not statuscolumn_on) or (not buftype_can_edit(args)) then
			return
		end

		if statuscolumn_use_cache then
			return
		end

		statuscolumn_use_cache = true

		--		local winid = tonumber(args.match)
		--		vim.o.statuscolumn = build_line_string(nil, nil, nil, nil, nil, winid)
	end,
})

-- Go back to normal live values for final refresh
vim.api.nvim_create_autocmd("CursorHold", {
	callback = function(args)
		if (not statuscolumn_on) or (vim.bo[args.buf].buftype ~= "") then
			return
		end

		if statuscolumn_use_cache then
			statuscolumn_use_cache = false
			vim.o.statuscolumn = C_Update_Func -- force refresh
		end
	end,
})
----

local function get_line_signs(bufnr)
	-- v.lnum is 1-indexed, but extmarks are 0-indexed
	local row = vim.v.lnum - 1

	-- Query extmarks for the specific line we are rendering
	-- We ask for 'details' to get the 'sign_text'
	local marks = vim.api.nvim_buf_get_extmarks(bufnr, -1, { row, 0 }, { row, -1 }, { details = true })

	local highest_priority = -1

	local dap_icon = nil
	local diag_icon = nil
	local git_icon = nil

	for index, mark in ipairs(marks) do
		-- local namespace_id = mark[2]
		local details = mark[4] -- The 'details' table is the 4th element

		if details.sign_text then
			local trimmed_text = vim.trim(details.sign_text)
			local hl_group = details.sign_hl_group or ""

			local is_dapsign = hl_group:find("^Dap")
			local is_gitsign = hl_group:find("Git")
			local is_diagnosticsign = hl_group:find("Diagnostic")

			-- NOTE: testing other signs with this note.

			-- set default mark
			if (highest_priority < 0) and not is_gitsign then
				diag_icon = "%#" .. hl_group .. "#" .. trimmed_text .. "%*"
			end

			-- DAP breakpoint signs
			if is_dapsign then
				dap_icon = "%#" .. hl_group .. "#" .. trimmed_text .. "%*"
			end
			--

			-- diagnostic signs
			if is_diagnosticsign then
				if details.priority > highest_priority then
					highest_priority = details.priority
					diag_icon = "%#" .. hl_group .. "#" .. trimmed_text .. "%*"
				end
			end

			-- Track Git signs separately
			if is_gitsign then
				git_icon = "%#" .. hl_group .. "#" .. trimmed_text .. "%*"
			end
		end
	end

	return { dap_icon, diag_icon, git_icon }
end

local function get_line_mark(bufnr)
	-- Get all local marks (a-z)
	local marks = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
	for i = 1, #marks do
		local mark = marks:sub(i, i)
		local pos = vim.api.nvim_buf_get_mark(bufnr, mark) -- Returns {line, col}
		if pos[1] == vim.v.lnum then
			return mark
		end
	end
	return nil
end

local function get_fold()
	local lnum = vim.v.lnum
	-- 1. Is the line currently closed?
	-- foldclosed() returns the start line of the fold if closed, or -1
	local closed_start = vim.fn.foldclosed(lnum)
	if closed_start ~= -1 then
		if closed_start == lnum then
			return "" -- We are at the head of a closed fold
		end
		return nil -- We are inside a closed fold (usually not shown)
	end

	return nil -- No fold here
end

function _G.MyStatusColumn()
	local winid = vim.g.statusline_winid

	if not winid or winid == 0 then
		return ""
	end

	local bufnr = vim.api.nvim_win_get_buf(winid)

	local buftype = vim.api.nvim_get_option_value("buftype", { buf = bufnr })
	if buftype ~= "" then
		return ""
	end

	-- leave content empty for line-wrapped lines
	if vim.v.virtnum ~= 0 then
		return build_line_string(nil, nil, nil, nil, nil, winid)
	end

	if statuscolumn_use_cache then
		if cache[vim.v.lnum] ~= nil then
			return cache[vim.v.lnum]
		end
	end

	local signs = get_line_signs(bufnr)

	local dap = signs[1]
	local mark = get_line_mark(bufnr)
	local diag = signs[2]

	local fold = get_fold()
	local git = signs[3]

	local line_string = build_line_string(dap, mark, diag, fold, git, winid)

	cache[vim.v.lnum] = line_string

	return line_string
end

save_settings()
update_statuscolumn_state()

M.toggle = toggle_statuscolumn

return M
