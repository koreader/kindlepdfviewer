require "inputevent"
require "widget"
require "screen"
require "dialog"
require "settings" -- for debug(), TODO: put debug() somewhere else


-- we also initialize the framebuffer

fb = einkfb.open("/dev/fb0")
G_width, G_height = fb:getSize()

-- and the input handling

Input:init()


-- there is only one instance of this
UIManager = {
	-- change this to set refresh type for next refresh
	refresh_type = 1, -- defaults to 1 initially but will be set to 0 after each refresh

	_running = true,
	_window_stack = {},
	_execution_stack = {},
	_dirty = {}
}

-- register & show a widget
function UIManager:show(widget, x, y)
	-- put widget on top of stack
	table.insert(self._window_stack, {x = x or 0, y = y or 0, widget = widget})
	-- and schedule it to be painted
	self:setDirty(widget)
	-- tell the widget that it is shown now
	widget:handleEvent(Event:new("Show"))
end

-- unregister a widget
function UIManager:close(widget)
	local dirty = false
	for i = #self._window_stack, 1, -1 do
		if self._window_stack[i].widget == widget then
			table.remove(self._window_stack, i)
			dirty = true
			break
		end
	end
	if dirty then
		-- schedule remaining widgets to be painted
		for i = 1, #self._window_stack do
			self:setDirty(self._window_stack[i].widget)
		end
	end
end

-- schedule an execution task
function UIManager:schedule(time, action)
	table.insert(self._execution_stack, { time = time, action = action })
end

-- schedule task in a certain amount of seconds (fractions allowed) from now
function UIManager:scheduleIn(seconds, action)
	local when = { util.gettime() }
	local s = math.floor(seconds)
	local usecs = (seconds - s) * 1000000
	when[1] = when[1] + s
	when[2] = when[2] + usecs
	if when[2] > 1000000 then
		when[1] = when[1] + 1
		when[2] = when[2] - 1000000
	end
	self:schedule(when, action)
end

-- register a widget to be repainted
function UIManager:setDirty(widget)
	self._dirty[widget] = true
end

-- signal to quit
function UIManager:quit()
	self._running = false
end

-- transmit an event to registered widgets
function UIManager:sendEvent(event)
	-- top level widget has first access to the event
	local consumed = self._window_stack[#self._window_stack].widget:handleEvent(event)

	-- if the event is not consumed, always-active widgets can access it
	for _, widget in ipairs(self._window_stack) do
		if consumed then
			break
		end
		if widget.widget.is_always_active then
			consumed = widget.widget:handleEvent(event)
		end
	end
end

-- this is the main loop of the UI controller
-- it is intended to manage input events and delegate
-- them to dialogs
function UIManager:run()
	self._running = true
	while self._running do
		local now = { util.gettime() }

		-- check if we have timed events in our queue and search next one
		local wait_until = nil
		local all_tasks_checked
		repeat
			all_tasks_checked = true
			for i = #self._execution_stack, 1, -1 do
				local task = self._execution_stack[i]
				if not task.time
					or task.time[1] < now[1]
					or task.time[1] == now[1] and task.time[2] < now[2] then
					-- task is pending to be executed right now. do it.
					task.action()
					-- and remove from table
					table.remove(self._execution_stack, i)
					-- start loop again, since new tasks might be on the
					-- queue now
					all_tasks_checked = false
				elseif not wait_until
					or wait_until[1] > task.time[1]
					or wait_until[1] == task.time[1] and wait_until[2] > task.time[2] then
					-- task is to be run in the future _and_ is scheduled
					-- earlier than the tasks we looked at already
					-- so adjust to the currently examined task instead.
					wait_until = task.time
				end
			end
		until all_tasks_checked

		--debug("---------------------------------------------------")
		--debug("exec stack", self._execution_stack)
		--debug("window stack", self._window_stack)
		--debug("dirty stack", self._dirty)
		--debug("---------------------------------------------------")

		-- stop when we have no window to show (bug)
		if #self._window_stack == 0 then
			error("no dialog left to show, would loop endlessly")
		end

		-- repaint dirty widgets
		local dirty = false
		for _, widget in ipairs(self._window_stack) do
			if self._dirty[widget.widget] then
				widget.widget:paintTo(fb.bb, widget.x, widget.y)
				-- and remove from list after painting
				self._dirty[widget.widget] = nil
				-- trigger repaint
				dirty = true
			end
		end

		if dirty then
			-- refresh FB
			fb:refresh(self.refresh_type) -- TODO: refresh explicitly only repainted area
			-- reset refresh_type
			self.refresh_type = 0
		end

		-- wait for next event
		-- note that we will skip that if in the meantime we have tasks that are ready to run
		local input_event = nil
		if not wait_until then
			-- no pending task, wait endlessly
			input_event = Input:waitEvent()
		elseif wait_until[1] > now[1]
		or wait_until[1] == now[1] and wait_until[2] > now[2] then
			local wait_for = { s = wait_until[1] - now[1], us = wait_until[2] - now[2] }
			if wait_for.us < 0 then
				wait_for.s = wait_for.s - 1
				wait_for.us = 1000000 + wait_for.us
			end
			-- wait until next task is pending
			input_event = Input:waitEvent(wait_for.us, wait_for.s)
		end

		-- delegate input_event to handler
		if input_event then
			self:sendEvent(input_event)
		end
	end
end
