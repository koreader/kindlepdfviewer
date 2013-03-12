require "ui/widget/base"


--[[
ProgressWidget shows a progress bar
--]]
ProgressWidget = Widget:new{
	width = nil,
	height = nil,
	margin_h = 3,
	margin_v = 1,
	radius = 2,
	bordersize = 1,
	bordercolor = 15,
	bgcolor = 0,
	rectcolor = 10,
	percentage = nil,
}

function ProgressWidget:getSize()
	return { w = self.width, h = self.height }
end

function ProgressWidget:paintTo(bb, x, y)
	local my_size = self:getSize()
	bb:paintRoundedRect(x, y, my_size.w, my_size.h, self.bgcolor, self.radius)
	bb:paintBorder(x, y, my_size.w, my_size.h,
					self.bordersize, self.bordercolor, self.radius)
	bb:paintRect(x+self.margin_h, y+self.margin_v+self.bordersize,
				(my_size.w-2*self.margin_h)*self.percentage,
				(my_size.h-2*(self.margin_v+self.bordersize)), self.rectcolor)
end

function ProgressWidget:setPercentage(percentage)
	self.percentage = percentage
end



