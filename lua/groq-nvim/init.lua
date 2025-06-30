local Groq = {}
local curl = require('plenary.curl')
local json = vim.json

Groq.config = {
  api_url = "https://api.groq.com/openai/v1/chat/completions",
}

Groq.original_text = nil
Groq.original_range = nil

function Groq.setup(opts)
  Groq.config = vim.tbl_extend("force", Groq.config, opts or {})
  if not Groq.config.api_key then
    error("Groq API key not set. Please set it in the setup function.")
  end
  vim.api.nvim_create_user_command("GroqGenerate", Groq.generate_code, {nargs = 1})
  vim.api.nvim_create_user_command("GroqEdit", Groq.edit_code, {range = true, nargs = '?'})
  vim.api.nvim_create_user_command("GroqOptimize", Groq.optimize_code, {range = true})
end

local function call_groq_api_stream(messages, callback)
  local job_id = vim.fn.jobstart({"curl", "-sS", "-N",
    Groq.config.api_url,
    "-H", "Authorization: Bearer " .. Groq.config.api_key,
    "-H", "Content-Type: application/json",
    "-d", json.encode({
      model = Groq.config.model,
      messages = messages,
      stream = true
    })
  }, {
    on_stdout = function(_, data)
      for _, line in ipairs(data) do
        if line:sub(1, 6) == "data: " then
          local raw_data = line:sub(7)
          if raw_data ~= "[DONE]" then
            local success, parsed_data = pcall(json.decode, raw_data)
            if success and parsed_data.choices and parsed_data.choices[1].delta.content then
              callback(parsed_data.choices[1].delta.content)
            end
          end
        end
      end
    end,
    on_exit = function()
      callback(nil)
    end
  })
end

local function stream_and_insert(messages, row, col)
  local result = {}
  call_groq_api_stream(messages, function(content)
    if content then
      table.insert(result, content)
    else
      local text = table.concat(result, "")
      local new_lines = vim.split(text, "\n", true)
      vim.api.nvim_buf_set_lines(0, row - 1, row - 1, false, new_lines)
      vim.api.nvim_win_set_cursor(0, {row + #new_lines - 1, col})
    end
  end)
end

function Groq.generate_code(opts)
  local prompt = opts.args
  local messages = {
	  {role = "system", content = "You are a helpful senior coding assistant. Based on the users prompt, write the code. Consider code quality, adherence to best practices, readability and maintainability. Keep the code simple and elegant as possible, and follow best practices. Only generate the requested code with no additional formatting or text, including backticks. The code you generate is written directly to the current file so make sure it is valid code."},
	  {role = "user", content = prompt}
  }
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  stream_and_insert(messages, row, col)
end

function Groq.edit_code(opts)
  local start_line = opts.line1 - 1
  local end_line = opts.line2
  local selected_text = table.concat(vim.api.nvim_buf_get_lines(0, start_line, end_line, false), "\n")
  local prompt = opts.args
  local messages = {
	  {role = "system", content = "You are a helpful senior coding assistant. Based on the users prompt, and the selected code, rewrite the selection with any necessary edits based on the users prompt. Consider code quality, adherence to best practices, readability and maintainability. Keep the code simple and elegant as possible, and follow best practices. All of the selected code will be deleted so make sure you rewrite it by incorporating both the old code and the new changes. Only generate the requested code with no additional formatting or text, including backticks. The code you generate is written directly to the current file so make sure it is valid code."},
	  {role = "user", content = prompt .. selected_text}
  }
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  vim.api.nvim_buf_set_lines(0, start_line, end_line, false, {})
  stream_and_insert(messages, row, col)
end

function Groq.optimize_code(opts)
  local start_line = opts.line1 - 1
  local end_line = opts.line2
  local selected_text = table.concat(vim.api.nvim_buf_get_lines(0, start_line, end_line, false), "\n")
  local messages = {
    {role = "system", content = "You are a helpful senior coding assistant. Your task is to improve the selected code by optimizing its performance, readability, and maintainability. Keep the code simple and elegant as possible, and follow best practices. All of the selected code will be deleted so make sure you rewrite it by incorporating both the old code and the new changes. Only generate the requested code with no additional formatting or text, including backticks. The code you generate replaces the selected code, so make sure it is valid and complete."},
    {role = "user", content = selected_text}
  }
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  vim.api.nvim_buf_set_lines(0, start_line, end_line, false, {})
  stream_and_insert(messages, row, col)
end

return Groq
