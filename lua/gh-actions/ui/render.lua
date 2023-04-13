local Config = require('gh-actions.config')
local Buffer = require('gh-actions.ui.buffer')
local utils = require('gh-actions.utils')

---TODO: Shade background like https://github.com/akinsho/toggleterm.nvim/blob/2e477f7ee8ee8229ff3158e3018a067797b9cd38/lua/toggleterm/colors.lua

---@class GhActionsRenderLocation
---@field value any
---@field kind string
---@field from integer
---@field to integer

---@class GhActionsRender:Buffer
---@field store { get_state: fun(): GhActionsState }
---@field locations GhActionsRenderLocation[]
local GhActionsRender = {
  locations = {},
}

---@param run { status: string, conclusion: string }
---@return string
local function get_workflow_run_icon(run)
  if not run then
    return Config.options.icons.status.unknown
  end

  if run.status == 'completed' then
    return Config.options.icons.conclusion[run.conclusion] or run.conclusion
  end

  return Config.options.icons.status[run.status]
    or Config.options.icons.status.unknown
end

---@param run { status: string, conclusion: string }
---@param prefix string
---@return string|nil
local function get_status_highlight(run, prefix)
  if not run then
    return nil
  end

  if run.status == 'completed' then
    return 'GhActions'
      .. utils.string.upper_first(prefix)
      .. utils.string.upper_first(run.conclusion)
  end

  return 'GhActions'
    .. utils.string.upper_first(prefix)
    .. utils.string.upper_first(run.status)
end

---@param store { get_state: fun(): GhActionsState }
---@return GhActionsRender
function GhActionsRender.new(store)
  local self = setmetatable(
    {},
    { __index = setmetatable(GhActionsRender, { __index = Buffer }) }
  )
  ---@cast self GhActionsRender

  self.store = store

  return self
end

---@param bufnr integer
function GhActionsRender:render(bufnr)
  self._lines = {}

  local state = self.store:get_state()

  self:title(state)
  self:workflows(state)
  self:trim()

  Buffer.render(self, bufnr)
end

--- Render title of the split window
---@param state GhActionsState
function GhActionsRender:title(state)
  if not state.repo then
    self:append('Github Workflows'):nl():nl()
  else
    self:append(string.format('Github Workflows for %s', state.repo)):nl():nl()
  end
end

--- Render each workflow
---@param state GhActionsState
function GhActionsRender:workflows(state)
  local workflows = state.workflows
  local workflow_runs = state.workflow_runs

  local workflow_runs_by_workflow_id = utils.group_by(function(workflow_run)
    return workflow_run.workflow_id
  end, workflow_runs)

  for _, workflow in ipairs(workflows) do
    local runs = workflow_runs_by_workflow_id[workflow.id] or {}

    self:workflow(state, workflow, runs)
  end
end

---@param state GhActionsState
---@param workflow GhWorkflow
---@param runs GhWorkflowRun[]
function GhActionsRender:workflow(state, workflow, runs)
  local workflowline = self:get_current_line()
  local runs_n = math.min(5, #runs)

  self
    :status_icon(runs[1])
    :append(' ')
    :append(workflow.name, get_status_highlight(runs[1], 'run'))
    :append(
      state.workflow_configs[workflow.id]
          and state.workflow_configs[workflow.id].config.on.workflow_dispatch
          and (' ' .. Config.options.icons.workflow_dispatch)
        or ''
    )
    :nl()

  -- TODO cutting down on how many we list here, as we fetch 100 overall repo
  -- runs on opening the split. I guess we do want to have this configurable.
  for _, run in ipairs { unpack(runs, 1, runs_n) } do
    self:workflow_run(state, run)
  end

  self:append_location {
    kind = 'workflow',
    value = workflow,
    from = workflowline,
    to = self:get_current_line() - 1,
  }

  if #runs > 0 then
    self:nl()
  end
end

---@param state GhActionsState
---@param run GhWorkflowRun
function GhActionsRender:workflow_run(state, run)
  local runline = self:get_current_line()

  self
    :status_icon(run, { indent = 1 })
    :append(' ')
    :append(
      run.head_commit.message:gsub('\n.*', ''),
      get_status_highlight(run, 'run')
    )
    :nl()

  if run.conclusion ~= 'success' then
    for _, job in ipairs(state.workflow_jobs[run.id] or {}) do
      self:workflow_job(job)
    end
  end

  self:append_location {
    kind = 'workflow_run',
    value = run,
    from = runline,
    to = self:get_current_line() - 1,
  }
end

---@param job GhWorkflowRunJob
function GhActionsRender:workflow_job(job)
  local jobline = self:get_current_line()

  self
    :status_icon(job, { indent = 2 })
    :append(' ')
    :append(job.name, get_status_highlight(job, 'job'))
    :nl()

  if job.conclusion ~= 'success' then
    for _, step in ipairs(job.steps) do
      self:workflow_step(step)
    end
  end

  self:append_location {
    kind = 'workflow_job',
    value = job,
    from = jobline,
    to = self:get_current_line() - 1,
  }
end

---@param step GhWorkflowRunJobStep
function GhActionsRender:workflow_step(step)
  local stepline = self:get_current_line()

  self
    :status_icon(step, { indent = 3 })
    :append(' ')
    :append(step.name, get_status_highlight(step, 'step'))
    :nl()

  self:append_location {
    kind = 'workflow_step',
    value = step,
    from = stepline,
    to = self:get_current_line() - 1,
  }
end

---@param status { status: string, conclusion: string }
---@param opts? { indent?: number | nil }
function GhActionsRender:status_icon(status, opts)
  opts = opts or {}

  self:append(
    get_workflow_run_icon(status),
    get_status_highlight(status, 'RunIcon'),
    opts
  )

  return self
end

---@param location GhActionsRenderLocation
function GhActionsRender:append_location(location)
  table.insert(self.locations, location)
end

return GhActionsRender
