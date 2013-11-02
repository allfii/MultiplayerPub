require "lib/pubnub"

Networking = Core.class(EventDispatcher)

Networking.LOG_TAG = "Networking"
local LOG_TAG = Networking.LOG_TAG

local MESSAGE_SEND = 1
local MESSAGE_RECEIVE = 2
local TIMEOUT_CONNECTION = 10 -- 10 seconds timeout then closed connection

--inisiasi module pubnub, dipanggil pas pertama kali sebelum fungsi2 dibawah
function Networking:init(channelName, func, param)
	self.server_pubnub = nil
	self.player_num = param._playerNumber

	self.connectionLostHandler = EventHandler.new(self)
	self.send_stack = {}
	self.rec_stack = {number=0}
	self.current_send_number = 0
	self.current_rec_number = 0
	self.max_time_out = 1 -- seconds
	self.current_time_out = 0 -- seconds
	self.counter_time_out_connection = 0
	
	self._func = func
	self._param = param
	
	self.server_pubnub = pubnub.new({
		publish_key   = "pub-2d07010f-99cd-421e-be4e-c9032c6eba06",             -- YOUR PUBLISH KEY (akun hilman09121991@gmail.com)
		subscribe_key = "sub-02d8fe14-261f-11e2-8635-d5c69a305cb2",             -- YOUR SUBSCRIBE KEY (akun hilman09121991@gmail.com)		
		ssl           = false,                -- ENABLE SSL?
		origin        = "pubsub.pubnub.com" -- PUBNUB CLOUD ORIGIN
	})
	self._gameFinish = false
	self.state = 0 -- awal mula
	self.stackMsg = {} -- stack tempat message yang akan dipublish
	self.updateTime = 500 -- durasi pengiriman 
	
	self.myPlayer = {}
	self.myPlayer.id = nil
	self.isReady = false
	self.server_pubnub:time({
		callback = function(time)
			if(time==nil)then
				self.myPlayer.id = "1."..math.random( 1, 99999999999 ).."e+"..math.random(1,999)..'-' .. math.random( 1, 999999 )
			else
				self.myPlayer.id = time .. '-' .. math.random( 1, 999999 )
			end
		end
	})
	self._channel = channelName
	local function callRespond()
		self:listen(func, param)
		self.isReady = true
	end
	local timer = Timer.new(500, 1)
	timer:addEventListener(Event.TIMER, callRespond, timer)
	timer:start()
		
	self.timer = Timer.new(self.updateTime, 1)
	self.timer:addEventListener(Event.TIMER, self.update, self)
	self.timer:start()
	
	local timer_time_out = Timer.new(1000, 1)
	timer_time_out:addEventListener(Event.TIMER, self.checkTimeOut, self)
	timer_time_out:start()
end

function Networking:_onConnectionLost()	
	self.connectionLostHandler:raiseEvent(nil)
	self:stopNetworking()			
end

function Networking:checkTimeOut()
	print("checktimeout")
	if self._gameFinish then return nil end
	if(self.current_time_out > self.max_time_out)then
		-- time out
		self.current_time_out = 0
		self:stopListen(self._channel)
		self.counter_time_out_connection = 	self.counter_time_out_connection +1
		Log.d(LOG_TAG, "timeout!", self.counter_time_out_connection)
		if 	self.counter_time_out_connection > TIMEOUT_CONNECTION then			
			self:_onConnectionLost()
			return nil
		end
		self:listen(self._func, self._param)
	else
		self.current_time_out = self.current_time_out + 1
	end
	
	local timer_time_out = Timer.new(1000, 1)
	timer_time_out:addEventListener(Event.TIMER, self.checkTimeOut, self)
	timer_time_out:start()
end

function Networking:printStack()
	Log.d(LOG_TAG,"rec:")
	if(self.rec_stack.number~=nil)then
		Log.d(LOG_TAG,self.current_rec_number)
	end
	Log.d(LOG_TAG,"send ("..#self.send_stack.."):")
	for i=1,#self.send_stack do
		Log.d(LOG_TAG,"stack send number:"..self.send_stack[i].number)
	end
end

function Networking:sendStack()
	if(self.isReady==false)then
		return
	end
	if(#self.send_stack>0)then
		if(self.send_stack[1].ID_PLAYER==nil)then
			self.send_stack[1].ID_PLAYER = self.myPlayer.id
		else
		end
		self.lastMessage = self.send_stack[1]
		self.server_pubnub:publish({
			channel = self._channel,
			message = self.send_stack[1]
		})
	else -- keep alive message
		Log.d(LOG_TAG,"Send Keep Alive")
		self.server_pubnub:publish({
			channel = self._channel,
			message = self.lastMessage
		})
	end
	
end

--fungsi untuk mengontrol message untuk dikirim dan ditangkap sekaligus mengatasi kegagalan pengiriman
function Networking:update()	
	print("update")
	if self._gameFinish then return nil end
	if(self.myPlayer.id==nil)then -- jangan mulai bila id belum didapatkan
		--Log.d(LOG_TAG,"Player ID null")
		self.myPlayer.id = "1."..math.random( 1, 99999999999 ).."e+"..math.random(1,999)..'-' .. math.random( 1, 999999 )
	end
	-- self:printStack() -- untuk debugging
	self:sendStack()
	
	self.timer = Timer.new(self.updateTime, 1)
	self.timer:addEventListener(Event.TIMER, self.update, self)
	self.timer:start()
end

function Networking:insertStack(aMessage)
	self.current_send_number = self.current_send_number+1
	aMessage.number = self.current_send_number
	aMessage.msg_type = MESSAGE_SEND
	if(#self.send_stack == 0) then
		self.send_stack[1] = aMessage
	else
		self.send_stack[#self.send_stack+1] = aMessage
	end
end

--mengirim pesan message ke channel dengan id tersebut
--hati2 menggunakan fungsi ini, karena jika aMessage adalah sebuah table dan jika table tersebut diedit di luar Networking, 
--maka pesan yang dikirimkan mungkin bisa berbeda karena terjadi perubahan tabel selagi pesan tersebut dicoba untuk dikirimkan
function Networking:send(aMessage)
	aMessage.ID_PLAYER = self.myPlayer.id
	self:insertStack(aMessage)
end

-- Sending ACK
function Networking:sendACK(number)
	if(self.isReady==false)then
		return
	end
	local msg = {}
	msg.ID_PLAYER = self.myPlayer.id
	msg.number = number
	msg.msg_type = MESSAGE_RECEIVE
	self.server_pubnub:publish({
		channel = self._channel,
		message = msg
	})	
end

function Networking:deleteMessageByNumber(number)
	for i=1,#self.send_stack do	
		if(self.send_stack[i].number == number)then
			--Log.d(LOG_TAG,"message number:"..number.." deleted")
			table.remove(self.send_stack,i)
			return
		end
	end
	return
end

--callback onListen akan dipanggil jika ada pesan masuk ke channel dengan id tersebut dengan parameter 
function Networking:listen(onListen, param)	
	self.server_pubnub:subscribe({
		channel  = self._channel,		
		param = param,
		callback = function(param,message)
			if message.ID_PLAYER == nil then return nil end
			if(message.ID_PLAYER == self.myPlayer.id) then
				return
			end
			self.current_time_out = 0
			self.counter_time_out_connection = 0			
			-- enemy reply
			Log.d(LOG_TAG,"Get enemy reply")
			
			if(message.msg_type == MESSAGE_SEND)then -- olah pesan
				self:sendACK(message.number)
				if(message.number > self.current_rec_number)then
					self.current_rec_number = message.number
					onListen(param, message)
				else
					-- same message number
				end
			else if(message.msg_type == MESSAGE_RECEIVE)then -- bales dengan ack
				self:deleteMessageByNumber(message.number)
			else
				Log.d(LOG_TAG,"message type error")
			end
		end
		end,
		errorback = function()
			Log.d(LOG_TAG,"Networking : Listen, Connection Lost")
		end
	})
end

--stop mendengarkan pesan masuk pada channel dengan id tersebut
function Networking:stopListen(channelId) 
	self.server_pubnub:unsubscribe({
		channel = channelId
	})
end

--fungsi ini ada kemungkinan dipanggil lebih dari satu kali, jadi pastikan aman kalo dipanggil lebih dari sekali
function Networking:stopNetworking()
	Log.d(LOG_TAG,"stop networking")
	self._gameFinish = true
	self:stopListen(self._channel)	
end

