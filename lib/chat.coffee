
path = require 'path'
util = require 'util'
socketIO = require 'socket.io'
FastSet = require 'collections/fast-set'
Deque = require 'collections/deque'


userCommands =
  directAddToList : ''
  directGetAccessList : ''
  directGetWhitelistMode : ''
  directMessage : ''
  directRemoveFromList : ''
  directSetWhitelistMode : ''
  disconnect : ''
  listRooms : ''
  roomAddToList : ''
  roomCreate : ''
  roomDelete : ''
  roomGetAccessList : ''
  roomGetWhitelistMode : ''
  roomHistory : ''
  roomJoin : ''
  roomLeave : ''
  roomMessage : ''
  roomRemoveFromList : ''
  roomSetWhitelistMode : ''

serverMessages =
  directMessage : ''
  directMessageEcho : ''
  fail : ''
  loginAccepted : ''
  loginRejected : ''
  roomAccessRemoved : ''
  roomJoined : ''
  roomLeft : ''
  roomMessage : ''
  roomUserJoin : ''
  roomUserLeave : ''
  success : ''

Object.freeze userCommands
Object.freeze serverMessages


class ErrorBuilder
  constructor : (@useRawErrorObjects) ->

  errorStrings :
    badArgument : 'Bad argument, named %s value %s'
    nameInList : 'Name %s is already in list %s'
    noList : 'No such list %s'
    noLogin : 'No login provided'
    noNameInList : 'No such name %s in list %s'
    noRoom : 'No such room %s'
    noStateStore : 'No such state stored %s'
    noUser : 'No such user %s'
    noUserOnline : 'No such user online %s'
    noValuesSupplied : 'No values supplied'
    notAllowed : 'Action is not allowed'
    notJoined : 'Not joined to room %s'
    roomExists : 'Room %s already exists'
    serverError : 'Server error %s'
    userExists : 'User %s already exists'

  getErrorString : (code) ->
    return @errorStrings[code] || "Unknown error: #{code}"

  makeError : (error, args...) ->
    if @useRawErrorObjects
      return { name : error, args : args }
    return util.format @getErrorString(error), args...


sendResult = (socket, idcmd, cb, error = null, data = null) ->
  # dispatch results to socket and callback
  if error
    if socket and idcmd then socket.emit 'fail', idcmd, error
  else
    if socket and idcmd then socket.emit 'success', idcmd, data
  if cb then cb error, data

wrapCommand = (obj, name, fn) ->
  # make hook names
  bname = name + 'Before'
  aname = name + 'After'
  # make actual command function
  cmd = (socket, idcmd, cb, oargs...) ->
    server = obj.server
    hooks = server.hooks
    beforeHook = hooks?[bname]
    afterHook = hooks?[aname]
    # command wrapper
    execCommand = (error, data, nargs...) ->
      # stop if before hook sets error/data
      if error or data
        return sendResult socket, idcmd, cb, error, data
      # check for argument changes made by before hook
      args = if nargs?.length then nargs else oargs
      # after hook wrapper
      afterCommand = (error, data) ->
        if afterHook
          afterHook server, socket, idcmd, (cb or ->), args...
        else if cb
          cb error, data
      # command main function
      fn.apply obj
      , [ socket
        , idcmd
        , afterCommand
        , args... ]
    process.nextTick ->
      # before hook checkin
      unless beforeHook
        execCommand()
      else
        beforeHook server, socket, idcmd, execCommand, oargs...
  return cmd

processMessage = (msg) ->
  msg.textMessage = msg?.textMessage?.toString() || ''
  msg.timestamp = new Date().getTime()

initState = (state, values) ->
  if values
    state.clear()
    state.addEach values


class Room

  ###
  # interface
  ###

  constructor : (@server, @name, @owner, @whitelistOnly) ->
    # STATE
    @errorBuilder = @server.errorBuilder
    @histSize = @server.histSize
    @whitelist = new FastSet
    @blacklist = new FastSet
    @adminlist = new FastSet
    @adminlist.add @owner
    @userlist = new FastSet
    @lastMessages = new Deque
    # END OF STATE

  setState : ( { whitelist, blacklist, adminlist, lastMessages } = {} ) ->
    initState @whitelist, whitelist
    initState @blacklist, blacklist
    initState @adminlist, adminlist
    @adminlist.add @owner
    initState @lastMessages, lastMessages

  ###
  # helpers
  ###

  hasList : (name) ->
    return name in [ 'adminlist', 'whitelist', 'blacklist', 'userlist' ]

  hasUser : (userName) ->
    return @userlist.get userName

  removeUser : (userName) ->
    @userlist.remove userName

  isOwner : (userName) ->
    return userName == @owner

  isAdmin : (userName) ->
    if @isOwner userName then return true
    return @adminlist.has userName and not @blacklist.has userName

  hasRemoveChangedCurrentAccess : (userName, listName) ->
    unless @hasUser userName then return false
    if listName == 'whitelist' and @whitelistOnly
      unless @isAdmin userName then return true
    return false

  hasAddChangedCurrentAccess : (userName, listName) ->
    unless @hasUser userName then return false
    if listName == 'blacklist' then return true
    return false

  getModeChangedCurrentAccess : (value) ->
    unless value then return []
    diff = (@userlist.difference @whitelist).difference @adminlist
    return diff.toArray()

  ###
  # access checking
  ###

  checkList : (author, listName) ->
    unless @hasUser author
      return @errorBuilder.makeError 'notJoined', @name
    unless @hasList listName
      return @errorBuilder.makeError 'noList', listName
    return null

  checkListOp : (author, listName, values) ->
    error = @checkList author, listName
    if error then return error
    unless values?.length and values instanceof Array
      return @errorBuilder.makeError 'noValuesSupplied'
    return null

  checkListChange : (author, listName, name) ->
    if name == @owner
      return @errorBuilder.makeError 'notAllowed'
    if listName == 'userlist'
      return @errorBuilder.makeError 'notAllowed'
    if author == @owner then return null
    if @adminlist.has name
      return @errorBuilder.makeError 'notAllowed'
    unless @adminlist.has author
      return @errorBuilder.makeError 'notAllowed'
    return null

  checkListAdd : (author, listName, name) ->
    error = @checkListChange author, listName, name
    if error then return error
    if @[listName].has name
      return @errorBuilder.makeError 'nameInList', name, listName
    return null

  checkListRemove : (author, listName, name) ->
    error = @checkListChange author, listName, name
    if error then return error
    unless @[listName].has name
      return @errorBuilder.makeError 'noNameInList', name, listName
    return null

  checkModeChange : (author, value) ->
    if @isAdmin author then return null
    return @errorBuilder.makeError 'notAllowed'

  checkAcess : (userName) ->
    if @isOwner userName then return null
    if @blacklist.has userName
      return @errorBuilder.makeError 'notAllowed'
    if @whitelistOnly and not
    (@whitelist.has userName or @adminlist.has userName)
      return @errorBuilder.makeError 'notAllowed'
    return null

  checkIsOwner : (author) ->
    if @isOwner author then return null
    return @errorBuilder.makeError 'notAllowed'

  forEach : (fn) ->
    @userlist.forEach fn

  ###
  # actions execution
  ###

  leave : (userName) ->
    @userlist.remove userName
    return null

  join : (userName) ->
    error = @checkAcess userName
    if error then return error
    @userlist.add userName
    return null

  message : (author, msg) ->
    unless @userlist.has author
      return @errorBuilder.makeError 'notJoined', @name
    unless @histSize then return null
    if @lastMessages.length >= @histSize
      @lastMessages.pop()
    @lastMessages.unshift { author : author, message : msg }
    return null

  getList : (author, listName) ->
    error = @checkList author, listName
    if error then return { error : error }
    data = @[listName].toArray()
    return { data : data }

  getLastMessages : (author) ->
    unless @hasUser author
      error =  @errorBuilder.makeError 'notJoined', @name
      return { error : error }
    data = @lastMessages.toArray()
    return { data : data }

  addToList : (author, listName, values) ->
    error = @checkListOp author, listName, values
    if error then return { error :  error }
    for val in values
      error = @checkListAdd author, listName, val
      if error then return { error :  error }
    data = []
    for val in values
      if @hasAddChangedCurrentAccess val, listName
        data.push val
    @[listName].addEach values
    return { data : data }

  removeFromList : (author, listName, values) ->
    error = @checkListOp author, listName, values
    if error then return { error :  error }
    for val in values
      error = @checkListRemove author, listName, val
      if error then return { error :  error }
    data = []
    for val in values
      if @hasRemoveChangedCurrentAccess val, listName
        data.push val
    @[listName].deleteEach values
    return { data : data }

  getMode : (author) ->
    return { data : @whitelistOnly }

  changeMode : (author, mode) ->
    error = @checkModeChange author, mode
    if error then return error
    @whitelistOnly = if mode then true else false
    data = @getModeChangedCurrentAccess @whitelistOnly
    return { data : data }


class UserDirectMessaging

  ###
  # interface
  ###

  constructor : (@errorBuilder, @username, @whitelistOnly) ->
    # STATE
    @whitelist = new FastSet
    @blacklist = new FastSet
    # END OF STATE

  setState : ( { whitelist, blacklist } = {} ) ->
    initState @whitelist, whitelist
    initState @blacklist, blacklist

  ###
  # helpers
  ###

  hasList : (listName) ->
    return listName in [ 'whitelist', 'blacklist' ]

  checkList : (author, listName) ->
    if author != @username
      return @errorBuilder.makeError 'notAllowed'
    unless @hasList listName
      return @errorBuilder.makeError 'noList', listName
    return null

  checkListOp : (author, listName, values) ->
    error = @checkList author, listName
    if error then return error
    unless values?.length and values instanceof Array
      return @errorBuilder.makeError 'noValuesSupplied'
    return null

  checkListAdd : (author, listName, name) ->
    if name == @username
      return @errorBuilder.makeError 'notAllowed'
    if @[listName].has name
      return @errorBuilder.makeError 'nameInList', name, listName
    return null

  checkListRemove : (author, listName, name) ->
    if name == @username
      return @errorBuilder.makeError 'notAllowed'
    unless @[listName].has name
      return @errorBuilder.makeError 'noNameInList', name, listName
    return null

  checkAcess : (userName) ->
    if userName == @username then return null
    if @blacklist.has userName
      return @errorBuilder.makeError 'noUserOnline'
    if @whitelistOnly and not @whitelist.has userName
      return @errorBuilder.makeError 'notAllowed'
    return null

  ###
  # actions
  ###

  message : (author, msg) ->
    error = @checkAcess author
    if error then return error
    return null

  getList : (author, listName) ->
    error = @checkList author, listName
    if error then return { error : error }
    data = @[listName].toArray()
    return { data : data }

  addToList : (author, listName, values) ->
    error = @checkListOp author, listName, values
    if error then return error
    for val in values
      error = @checkListAdd author, listName, val
      if error then return error
    @[listName].addEach values
    return null

  removeFromList : (author, listName, values) ->
    error = @checkListOp author, listName, values
    if error then return error
    for val in values
      error = @checkListRemove author, listName, val
      if error then return error
    @[listName].deleteEach values
    return null

  getMode : (author) ->
    if author != @username
      error = @errorBuilder.makeError 'notAllowed'
      return { error : error }
    data =  @whitelistOnly
    return { data : data }

  changeMode : (author, mode) ->
    if author != @username
      return @errorBuilder.makeError 'notAllowed'
    @whitelistOnly = if mode then true else false
    return null


class User extends UserDirectMessaging

  ###
  # interface
  ###

  constructor : (@server, @username, whitelistOnly = false) ->
    super(@server.errorBuilder, @username, whitelistOnly)
    @userManager = @server.userManager
    @roomManager = @server.roomManager
    @enableUserlistUpdates = @server.enableUserlistUpdates
    @allowRoomsManagement = @server.allowRoomsManagement
    @allowDirectMessages = @server.allowDirectMessages
    # STATE
    @roomslist = new FastSet
    @sockets = {}
    # END OF STATE

  setState : () ->
    super

  ###
  # helpers
  ###

  addSocket : (socket) ->
    @sockets[socket.id] = socket
    for own cmd of userCommands
      @bindCommand cmd, @[cmd], socket

  removeSocket : (id) ->
    s = @sockets[id]
    @sockets[id]?.disconnect()
    delete @sockets[id]

  hasSockets : () ->
    return Object.keys(@sockets).length

  addRoom : (roomName) ->
    @roomslist.add roomName

  removeRoom : (roomName) ->
    @roomslist.remove roomName

  withRoom : (roomName, fn) ->
    room = @roomManager.getRoom roomName
    error = @errorBuilder.makeError 'noRoom', roomName unless room
    fn error, room

  bindCommand : (name, fn, socket) ->
    cmd = wrapCommand @, name, fn
    socket.on name, (idcmd, args...) ->
      cmd socket, idcmd, null, args...

  sendAccessRemoved : (iterable, roomName) ->
    iterable.forEach (userName) =>
      user = @userManager.getUser userName
      if user
        user.removeRoom roomName
        for own id, toSocket of user.sockets
          toSocket.emit 'roomAccessRemoved', roomName

  broadcast : (socket, roomName, args...) ->
    socket.broadcast.to(roomName).emit args...

  ###
  # commands
  ###

  directAddToList : (socket, idcmd, cb
  , listName, values) ->
    error = @addToList @username, listName, values
    sendResult socket, idcmd, cb, error

  directGetAccessList : (socket, idcmd, cb
  , listName) ->
    { error, data } = @getList @username, listName
    sendResult socket, idcmd, cb, error, data

  directGetWhitelistMode: (socket, idcmd, cb) ->
    { error, data } = @getMode @username
    sendResult socket, idcmd, cb, error, data

  directMessage : (socket, idcmd, cb
  , toUserName, msg) ->
    unless @allowDirectMessages
      error = @errorBuilder.makeError 'notAllowed'
      return sendResult socket, idcmd, cb, error
    toUser = @userManager.getUser toUserName
    unless toUser
      error = @errorBuilder.makeError 'noUserOnline', toUserName
      return sendResult socket, idcmd, cb, error
    fromUser = @userManager.getUser @username
    unless fromUser
      error = @errorBuilder.makeError 'noUserOnline', @username
      return sendResult socket, idcmd, cb, error
    error = toUser.message @username, msg
    if error
      return sendResult socket, idcmd, cb, error
    processMessage msg
    for own id, fromSocket of fromUser.sockets
      if id != socket.id
        fromSocket.emit 'directMessageEcho', toUserName, msg
    for own id, toSocket of toUser.sockets
      toSocket.emit 'directMessage', @username, msg
    sendResult socket, idcmd, cb

  directRemoveFromList : (socket, idcmd, cb
  , listName, values) ->
    error = @removeFromList @username, listName, values
    return sendResult socket, idcmd, cb, error

  directSetWhitelistMode : (socket, idcmd, cb
  , mode) ->
    error = @changeMode @username, mode
    return sendResult socket, idcmd, cb, error

  disconnect : (socket) ->
    @removeSocket socket.id
    unless @hasSockets()
      @roomslist.forEach (roomName) =>
        room = @roomManager.getRoom roomName
        room.removeUser @username
        if @enableUserlistUpdates
          @server.nsp.in(roomName).emit 'roomUserLeave'
          , roomName, @username
      @userManager.removeUser @username

  listRooms : (socket, idcmd, cb) ->
    data = @roomManager.listRooms()
    return sendResult socket, idcmd, cb, null, data

  roomAddToList : (socket, idcmd, cb
  , roomName, listName, values) ->
    @withRoom roomName, (error, room) =>
      unless error
        { error, data } = room.addToList @username, listName, values
        unless error then @sendAccessRemoved data, roomName
      sendResult socket, idcmd, cb, error

  roomCreate : (socket, idcmd, cb
  , roomName, whitelistOnly) ->
    unless @allowRoomsManagement
      err = @errorBuilder.makeError 'notAllowed'
      return sendResult socket, idcmd, cb, err
    roomName = roomName?.toString()
    unless roomName
      error = @errorBuilder.makeError 'badArgument', 'roomName', roomName
      return sendResult socket, idcmd, cb, error
    room = @roomManager.getRoom roomName
    if room
      error = @errorBuilder.makeError 'roomExists', roomName
      return sendResult socket, idcmd, cb, error
    room = new Room @server, roomName, @username, whitelistOnly
    @roomManager.addRoom room
    return sendResult socket, idcmd, cb

  roomDelete : (socket, idcmd, cb
  , roomName) ->
    unless @allowRoomsManagement
      err = @errorBuilder.makeError 'notAllowed'
      return sendResult socket, idcmd, cb, err
    @withRoom roomName, (error, room) =>
      error = room.checkIsOwner @username unless error
      unless error
        @roomManager.removeRoom room.name
        @sendAccessRemoved room, roomName
      sendResult socket, idcmd, cb, error

  roomGetAccessList : (socket, idcmd, cb
  , roomName, listName) ->
    @withRoom roomName, (error, room) =>
      { error, data } = room.getList @username, listName unless error
      sendResult socket, idcmd, cb, error, data

  roomGetWhitelistMode : (socket, idcmd, cb
  , roomName) ->
    @withRoom roomName, (error, room) =>
      { error, data } = room.getMode @username unless error
      sendResult socket, idcmd, cb, error, data

  roomHistory : (socket, idcmd, cb
  , roomName) ->
    @withRoom roomName, (error, room) =>
      { error, data } = room.getLastMessages @username unless error
      sendResult socket, idcmd, cb, error, data

  roomJoin : (socket, idcmd, cb
  , roomName) ->
    @withRoom roomName, (error, room) =>
      error = room.join @username unless error
      unless error
        @addRoom roomName
        if @enableUserlistUpdates
          @broadcast socket, roomName, 'roomUserJoin', roomName, @username
        makeClosure = (toSocket, id) ->
          return (err) ->
            unless err
              if socket.id == id
                sendResult socket, idcmd, cb
              toSocket.emit 'roomJoined', roomName
            else
              sendResult socket, idcmd, cb, err
        for own id, toSocket of @sockets
          toSocket.join roomName, makeClosure toSocket, id
      else
        return sendResult socket, idcmd, cb, error

  roomLeave : (socket, idcmd, cb
  , roomName) ->
    @withRoom roomName, (error, room) =>
      error = room.leave @username unless error
      unless error
        @removeRoom roomName
        if @enableUserlistUpdates
          @broadcast socket, roomName, 'roomUserLeave', roomName, @username
        makeClosure = (toSocket, id) ->
          return (err) ->
            unless err
              if socket.id == id
                sendResult socket, idcmd, cb
              toSocket.emit 'roomLeft', roomName
            else
              sendResult socket, idcmd, cb, err
        for own id, toSocket of @sockets
          toSocket.leave roomName, makeClosure toSocket, id
      else
        return sendResult socket, idcmd, cb, error

  roomMessage : (socket, idcmd, cb
  , roomName, msg) ->
    @withRoom roomName, (error, room) =>
      error = room.message @username, msg unless error
      unless error
        processMessage msg
        @broadcast socket, roomName, 'roomMessage', roomName, @username, msg
        socket.emit 'roomMessage', roomName, @username, msg
      return sendResult socket, idcmd, cb, error

  roomRemoveFromList : (socket, idcmd, cb
  , roomName, listName, values) ->
    @withRoom roomName, (error, room) =>
      unless error
        { error, data } = room.removeFromList @username, listName, values
        unless error then @sendAccessRemoved data, roomName
      return sendResult socket, idcmd, cb, error

  roomSetWhitelistMode : (socket, idcmd, cb
  , roomName, mode) ->
    @withRoom roomName, (error, room) =>
      { error, data } = room.changeMode @username, mode unless error
      unless error then @sendAccessRemoved data, roomName
      return sendResult socket, idcmd, cb, error


class UserManager
  constructor : () ->
    # STATE
    @users = {}
    # END OF STATE

  getUser : (name) ->
    return @users[name]

  removeUser : (name) ->
    delete @users[name]

  addUser : (user, socket) ->
    name = user?.username
    currentUser = @users[name]
    if currentUser
      currentUser.addSocket socket
    else
      user.addSocket socket
      @users[name] = user


class RoomManager
  constructor : () ->
    # STATE
    @rooms = {}
    # END OF STATE

  getRoom : (name) ->
    return @rooms[name]

  removeRoom : (name) ->
    delete @rooms[name]

  addRoom : (room) ->
    name = room.name
    unless @rooms[name]
      @rooms[name] = room

  listRooms : ->
    list = []
    for own name, room of @rooms
      unless room.whitelistOnly
        list.push name
    list.sort()
    return list


class ChatService
  constructor : (@options = {}, @hooks = {}) ->
    @io = @options.io
    @sharedIO = true if @io
    @http = @options.http unless @io

    # options, constant for a server instance
    @namespace = @options.namespace || '/chat-service'
    @histSize = @options.histSize || 100
    @useRawErrorObjects = @options.useRawErrorObjects || false
    @enableUserlistUpdates = @options.enableUserlistUpdates || false
    @allowRoomsManagement = @options.allowRoomsManagement || false
    @allowDirectMessages = @options.allowDirectMessages || false
    @serverOptions = @options.serverOptions

    # public objects
    # TODO API
    @userManager = new UserManager
    @roomManager = new RoomManager

    @errorBuilder = new ErrorBuilder @useRawErrorObjects
    unless @io
      if @http
        @io = socketIO @http, @serverOptions
      else
        port = @options?.port || 8080
        @io = socketIO port, @serverOptions

    @nsp = @io.of @namespace
    if @hooks.onStart
      @hooks.onStart @, (err) =>
        if err then return @close null, err
        @setEvents()
    else
      @setEvents()

  setEvents : ->
    if @hooks.auth
      @nsp.use @hooks.auth
    if @hooks.onConnect
      @nsp.on 'connection', (socket) =>
        @hooks.onConnect @, socket, (err, data) =>
          @addClient err, data, socket
    else
      @nsp.on 'connection', (socket) =>
        @addClient null, null, socket

  addClient : (err, user, socket) ->
    if err then return socket.emit 'loginRejected', err
    unless user
      userName = socket.handshake.query?.user
      unless userName
        error = @errorBuilder.makeError 'noLogin'
        return socket.emit 'loginRejected', error
      user = new User @, userName
    else
      userName = user.username
    @userManager.addUser user, socket
    socket.emit 'loginConfirmed', userName

  close : (done, error) ->
    cb = (err) =>
      unless @sharedIO or @http then @io.close()
      if done then process.nextTick -> done err
    if @hooks.onClose
      @hooks.onClose @, error, cb
    else
      cb()

module.exports = {
  ChatService
  User
  Room
  userCommands
  serverMessages
}
