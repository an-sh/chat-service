
chatServices = angular.module 'chatServices', []

class ChatClient
  constructor : (@_refresh = ->) ->
    @messages = {}
    @userlists = {}
    @blacklists = {}
    @rooms = []
    @adminRooms = []
    @historyLength = 50
    @isConnected = false

  _addMessage : (roomName, message, refresh = true) ->
    unless @messages[roomName]
      @messages[roomName] = [roomName]
    @messages[roomName].push message
    if refresh then @_refresh()

  _addError : (error) ->
    console.error error
    for room of @messages
      @_addMessage room
      , { textMessage : "Error: #{error}", isError : true }
      , false
    @_refresh error

  _addRoom : (roomName) ->
    @rooms.push roomName

  _removeRoom : (roomName) ->
    idx = @rooms.indexOf roomName
    if idx >= 0 then @rooms.splice idx, 1

  _registerEvents : (cb) ->
    errhndl = (error) =>
      @disconnect()
      cb error
    evhndl = (name) =>
      @isConnected = true
      @socket.removeListener 'error', errhndl
      @socket.removeListener 'loginRejected', errhndl
      @socket.on 'roomUserJoined', (room, user) =>
        @_addMessage room, { textMessage : "#{user} joined." }
      @socket.on 'roomUserLeft', (room, user) =>
        @_addMessage room, { textMessage : "#{user} left." }
      @socket.on 'roomJoinedEcho', (room, id, njoined) =>
        @_addMessage room
        , { textMessage : "Echo join #{room}, sockets #{njoined}." }
      @socket.on 'roomLeftEcho', (room, id, njoined) =>
        @_addMessage room
        , { textMessage : "Echo left #{room}, sockets #{njoined}." }
      @socket.on 'roomAccessRemoved', (room) =>
        @_removeRoom room
        @_addMessage room
        , { textMessage : "You have no longer access to #{room}." }
      @socket.on 'roomMessage', (room, msg) =>
        @_addMessage room, msg
      @socket.on 'error', (error) =>
        @disconnect()
        @_addError error
      @socket.on 'loginRejected', (error) =>
        @disconnect()
        @_addError error
      @socket.on 'disconnect', (reason) =>
        @disconnect()
        setTimeout => @_addError reason
      @_refresh()
      cb null, name
    @socket.on 'loginConfirmed', evhndl
    @socket.on 'loginRejected', errhndl
    @socket.on 'error', errhndl

  connect : (@userName, @token, @options = {}, cb = ->) ->
    if @isConnected then return cb()
    @options.connect ?= io.connect
    @options.host ?= 'localhost'
    @options.port ?= '8000'
    @options.namespace ?= '/chat-service'
    params = 'multiplex' : false
      , 'reconnection' : false
      , 'transports' : [ 'websocket' ]
    if @userName
      params.query = "user=#{@userName}&token=#{@token}"
    @socket =
      @options.connect "#{@options.host}:#{@options.port}#{@options.namespace}"
        , params
    @_registerEvents cb

  disconnect : () ->
    @isConnected = false
    @userlists = {}
    @rooms = []
    @adminRooms = []
    if @socket?.connected
      @socket.disconnect()
    @socket = null

  bindRefresh : (@_refresh) ->

  cleanOldMessages : (roomName) ->
    data = @messages[roomName]
    if data?.length > @historyLength
      data.splice 0, data.length - @historyLength

  isInRoom : (roomName) ->
    return (@rooms.indexOf roomName) >= 0

  isAdmin : (roomName) ->
    unless @isInRoom roomName then return false
    return (@adminRooms.indexOf roomName) >= 0

  roomMessage : (roomName, message, cb = ->) ->
    unless @isConnected
      return setTimeout -> cb 'Not connected.'
    @socket.emit 'roomMessage', roomName, { textMessage : message }, (error) =>
      if error
        @_addMessage roomName
          , {textMessage : "Error sending message: #{error}" }
      cb error

  roomJoin : (roomName, cb = ->) ->
    unless @isConnected
      return setTimeout -> cb 'Not connected.'
    if @isInRoom roomName
      return setTimeout -> cb 'Already in room.'
    @socket.emit 'roomJoin', roomName, (error, njoined) =>
      if error
        @_addMessage roomName
          , {textMessage : "Error joining room: #{error}" }
        return cb error
      @_addRoom roomName
      if njoined == 1
        @_addMessage roomName
          , {textMessage : "You have joined #{roomName}." }
      else
        @_addMessage roomName
          , {textMessage : "Now #{njoined} sockets are joined #{roomName}."}
      @socket.emit 'roomGetAccessList', roomName, 'adminlist', (error, data) =>
        if data?.indexOf and data.indexOf(@userName) >=0
          unless @isAdmin roomName
            @adminRooms.push roomName
          @_addMessage roomName
          , { textMessage : "You are a room administrator." }
      @socket.emit 'roomRecentHistory', roomName, (error, data) =>
        if data?.length
          unless @messages[roomName]
            @messages[roomName] = []
          rdata = data.reverse()
          @messages[roomName].unshift rdata...
          @_refresh()
      cb()

  roomLeave : (roomName, cb = ->) ->
    unless @isConnected
      return setTimeout -> cb 'Not connected.'
    unless @isInRoom roomName
      return setTimeout -> cb 'Not in room.'
    @socket.emit 'roomLeave', roomName, (error, njoined) =>
      if error
        @_addMessage roomName
        , {textMessage : "Error leaving room: #{error}" }
        return cb error
      @_removeRoom roomName
      if njoined == 0
        @_addMessage roomName
          , {textMessage : "You have left #{roomName}." }
      else
        @_addMessage roomName
          , {textMessage : "Now #{njoined} are sockets joined #{roomName}."}
      cb()

  getUsers : (roomName, cb = ->) ->
    unless @isConnected
      return setTimeout -> cb 'Not connected.'
    @socket.emit 'roomGetAccessList', roomName, 'userlist', (error, data) =>
      if error
        @_addMessage roomName
          , {textMessage : "Error getting userlist: #{error}"}
        @userlists[roomName] = []
      else
        @userlists[roomName] = data
      cb error

  getBlacklist : (roomName, cb = ->) ->
    unless @isConnected
      return setTimeout -> cb 'Not connected.'
    @socket.emit 'roomGetAccessList', roomName, 'blacklist', (error, data) =>
      if error
        @_addMessage roomName
          , {textMessage : "Error getting blacklist: #{error}"}
        @blacklists[roomName] = []
      else
        @blacklists[roomName] = data
      cb error

  banUser : (roomName, userName, cb = ->) ->
    unless @isConnected
      return setTimeout -> cb 'Not connected.'
    @socket.emit 'roomAddToList', roomName, 'blacklist', [userName]
    , (error, data) =>
      if error
        @_addMessage roomName
        , {textMessage : "Error baning #{userName}: #{error}"}
      else
        @_addMessage roomName
        , {textMessage : "#{userName} is now banned"}
      cb error

  unBanUser : (roomName, userName, cb = ->) ->
    unless @isConnected
      return setTimeout -> cb 'Not connected.'
    @socket.emit 'roomRemoveFromList', roomName, 'blacklist', [userName]
    , (error, data) =>
      if error
        @_addMessage roomName
        , {textMessage : "Error unbaning #{userName}: #{error}"}
      else
        @_addMessage roomName
        , {textMessage : "#{userName} is now unbanned"}
      cb error

chatServices.service 'chatService', [ChatClient]
