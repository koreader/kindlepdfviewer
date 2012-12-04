ReaderPaging = InputContainer:new{
	current_page = 0,
	number_of_pages = 0,
	visible_area = nil,
	page_area = nil,
}

function ReaderPaging:init()
	if Device:isTouchDevice() then
		self.ges_events = {
			TapForward = {
				GestureRange:new{
					ges = "tap",
					range = Geom:new{
						x = Screen:getWidth()/2,
						y = Screen:getHeight()/2,
						w = Screen:getWidth(),
						h = Screen:getHeight()
					}
				}
			},
			TapBackward = {
				GestureRange:new{
					ges = "tap",
					range = Geom:new{
						x = 0, 
						y = Screen:getHeight()/2,
						w = Screen:getWidth()/2,
						h = Screen:getHeight()/2,
					}
				}
			}
		}
	else
		self.key_events = {
			GotoNextPage = { 
				{Input.group.PgFwd}, doc = "go to next page",
				event = "GotoPageRel", args = 1 },
			GotoPrevPage = { 
				{Input.group.PgBack}, doc = "go to previous page",
				event = "GotoPageRel", args = -1 },

			GotoFirst = { 
				{"1"}, doc = "go to start", event = "GotoPercent", args = 0},
			Goto11 = { 
				{"2"}, doc = "go to 11%", event = "GotoPercent", args = 11},
			Goto22 = { 
				{"3"}, doc = "go to 22%", event = "GotoPercent", args = 22},
			Goto33 = { 
				{"4"}, doc = "go to 33%", event = "GotoPercent", args = 33},
			Goto44 = { 
				{"5"}, doc = "go to 44%", event = "GotoPercent", args = 44},
			Goto55 = { 
				{"6"}, doc = "go to 55%", event = "GotoPercent", args = 55},
			Goto66 = { 
				{"7"}, doc = "go to 66%", event = "GotoPercent", args = 66},
			Goto77 = { 
				{"8"}, doc = "go to 77%", event = "GotoPercent", args = 77},
			Goto88 = { 
				{"9"}, doc = "go to 88%", event = "GotoPercent", args = 88},
			GotoLast = { 
				{"0"}, doc = "go to end", event = "GotoPercent", args = 100},
		}
	end
	self.number_of_pages = self.ui.document.info.number_of_pages
end

function ReaderPaging:onReadSettings(config)
	self:gotoPage(config:readSetting("last_page") or 1)
end

function ReaderPaging:onCloseDocument()
	self.ui.doc_settings:saveSetting("last_page", self.current_page)
end

-- wrapper for bounds checking
function ReaderPaging:gotoPage(number)
	if number == self.current_page then
		return true
	end
	if number > self.number_of_pages
	or number < 1 then
		DEBUG("wrong page number: "..number.."!")
		return false
	end
	DEBUG("going to page number", number)

	-- this is an event to allow other controllers to be aware of this change
	self.ui:handleEvent(Event:new("PageUpdate", number))

	return true
end

function ReaderPaging:onZoomModeUpdate(new_mode)
	-- we need to remember zoom mode to handle page turn event
	self.zoom_mode = new_mode
end

function ReaderPaging:onPageUpdate(new_page_no)
	self.current_page = new_page_no
end

function ReaderPaging:onViewRecalculate(visible_area, page_area)
	-- we need to remember areas to handle page turn event
	self.visible_area = visible_area
	self.page_area = page_area
end

function ReaderPaging:onGotoPercent(percent)
	DEBUG("goto document offset in percent:", percent)
	local dest = math.floor(self.number_of_pages * percent / 100)
	if dest < 1 then dest = 1 end
	if dest > self.number_of_pages then
		dest = self.number_of_pages
	end
	self:gotoPage(dest)
	return true
end

function ReaderPaging:onGotoPageRel(diff)
	DEBUG("goto relative page:", diff)
	local new_va = self.visible_area:copy()
	local x_pan_off, y_pan_off = 0, 0

	if self.zoom_mode:find("width") then
		y_pan_off = self.visible_area.h * diff
	elseif self.zoom_mode:find("height") then
		x_pan_off = self.visible_area.w * diff
	else
		-- must be fit content or page zoom mode
		if self.visible_area.w == self.page_area.w then
			y_pan_off = self.visible_area.h * diff
		else
			x_pan_off = self.visible_area.w * diff
		end
	end

	-- adjust offset to help with page turn decision
	x_pan_off = math.roundAwayFromZero(x_pan_off)
	y_pan_off = math.roundAwayFromZero(y_pan_off)
	new_va.x = math.roundAwayFromZero(self.visible_area.x+x_pan_off)
	new_va.y = math.roundAwayFromZero(self.visible_area.y+y_pan_off)

	if (new_va:notIntersectWith(self.page_area)) then
		self:gotoPage(self.current_page + diff)
		-- if we are going back to previous page, reset
		-- view to bottom of previous page
		if x_pan_off < 0 then
			self.view:PanningUpdate(self.page_area.w, 0)
		elseif y_pan_off < 0 then
			self.view:PanningUpdate(0, self.page_area.h)
		end
	else
		-- fit new view area into page area
		new_va:offsetWithin(self.page_area, 0, 0)
		self.view:PanningUpdate(
			new_va.x - self.visible_area.x,
			new_va.y - self.visible_area.y)
		-- update self.visible_area
		self.visible_area = new_va
	end

	return true
end

function ReaderPaging:onTapForward()
	self:onGotoPageRel(1)
	return true
end

function ReaderPaging:onTapBackward()
	self:onGotoPageRel(-1)
	return true
end


