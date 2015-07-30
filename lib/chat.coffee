
path = require 'path'
util = require 'util'
socketIO = require 'socket.io'
FastSet = require 'collections/fast-set'
Deque = require 'collections/deque'
async = require 'async'


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

asyncLimit = 16

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


makeServerError = (errorBuilder, err) ->
  errorBuilder.makeError 'serverError', err.toString()

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
  if values and state
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


class DirectMessagingState
  constructor : (@username) ->
    @whitelistOnly
    @whitelist = new FastSet
    @blacklist = new FastSet

  initState : ({ whitelist, blacklist, whitelistOnly } = {}, cb) ->
    initState @whitelist, whitelist
    initState @blacklist, blacklist
    @whitelistOnly = if whitelistOnly then true else false
    process.nextTick -> cb()

  hasList : (listName) ->
    return listName in [ 'whitelist', 'blacklist' ]

  whitelistGet : (cb) ->
    data = @whitelist.toArray()
    process.nextTick -> cb null, data

  blacklistGet : (cb) ->
    data = @blacklist.toArray()
    process.nextTick -> cb null, data

  whitelistHas : (elem, cb) ->
    data = @whitelist.has elem
    process.nextTick -> cb null, data

  blacklistHas : (elem, cb) ->
    data = @blacklist.has elem
    process.nextTick -> cb null, data

  whitelistAdd : (elems, cb) ->
    @whitelist.addEach elems
    process.nextTick -> cb()

  blacklistAdd : (elems, cb) ->
    @blacklist.addEach elems
    process.nextTick -> cb()

  whitelistRemove : (elems, cb) ->
    @whitelist.deleteEach elems
    process.nextTick -> cb()

  blacklistRemove : (elems, cb) ->
    @blacklist.deleteEach elems
    process.nextTick -> cb()

  whitelistOnlySet : (mode, cb) ->
    @whitelistOnly = if mode then true else false
    process.nextTick -> cb()

  whitelistOnlyGet : (cb) ->
    m = @whitelistOnly
    process.nextTick -> cb null, m


class UserDirectMessaging

  constructor : (@errorBuilder, @username, state = DirectMessagingState) ->
    @directMessagingState = new state @username

  initState : (state, cb) ->
    @directMessagingState.initState state, cb

  ###
  # helpers
  ###

  checkList : (author, listName) ->
    if author != @username
      return @errorBuilder.makeError 'notAllowed'
    unless @directMessagingState.hasList listName
      return @errorBuilder.makeError 'noList', listName
    return null

  checkListOp : (author, listName, values) ->
    error = @checkList author, listName
    if error then return error
    unless values?.length and values instanceof Array
      return @errorBuilder.makeError 'noValuesSupplied'
    return null

  checkListChange : (author, listName, name, cb) ->
    if name == @username
      return cb @errorBuilder.makeError 'notAllowed'
    op = listName + 'Has'
    @directMessagingState[op] name, (error, hasName) =>
      if error
        return cb makeServerError @errorBuilder, error
      cb null, hasName

  checkListAdd : (author, listName, name, cb) ->
    @checkListChange author, listName, name, (error, hasName) =>
      if error then return cb error
      if hasName
        return cb @errorBuilder.makeError 'nameInList', name, listName
      cb()

  checkListRemove : (author, listName, name, cb) ->
    @checkListChange author, listName, name, (error, hasName) =>
      if error then return cb error
      unless hasName
        return cb @errorBuilder.makeError 'noNameInList', name, listName
      cb()

  checkAcess : (userName, cb) ->
    if userName == @username then return cb()
    @directMessagingState.blacklistHas userName, (error, blacklisted) =>
      if error
        return cb makeServerError @errorBuilder, error
      if blacklisted
        return cb @errorBuilder.makeError 'noUserOnline'
      @directMessagingState.whitelistOnlyGet (error, whitelistOnly) =>
        if error
          return cb makeServerError @errorBuilder, error
        @directMessagingState.whitelistHas userName, (error, hasWhitelist) =>
          if error
            return cb makeServerError @errorBuilder, error
          if whitelistOnly and not hasWhitelist
            return cb @errorBuilder.makeError 'notAllowed'
          cb()

  changeList : (author, listName, values, check, method, cb) ->
    error = @checkListOp author, listName, values
    if error then return cb error
    async.eachLimit values, asyncLimit
    , (val, fn) =>
      @[check] author, listName, val, fn
    , (error) =>
      if error then return cb error
      op = listName + method
      @directMessagingState[op] values, (error) ->
        if error then return cb error
        cb()

  ###
  # direct messaging actions
  ###

  message : (author, msg, cb) ->
    @checkAcess author, (error) ->
      if error then return cb error
      cb()

  getList : (author, listName, cb) ->
    error = @checkList author, listName
    if error then return cb error
    op = listName + 'Get'
    @directMessagingState[op] (error, list) =>
      if error
        return cb makeServerError @errorBuilder, error
      cb null, list

  addToList : (author, listName, values, cb) ->
    @changeList author, listName, values, 'checkListAdd', 'Add', cb

  removeFromList : (author, listName, values, cb) ->
    @changeList author, listName, values, 'checkListRemove', 'Remove', cb

  getMode : (author, cb) ->
    if author != @username
      return cb @errorBuilder.makeError 'notAllowed'
    @directMessagingState.whitelistOnlyGet (error, whitelistOnly) ->
      if error
        return cb makeServerError @errorBuilder, error
      cb null, whitelistOnly

  changeMode : (author, mode, cb) ->
    if author != @username
      return cb @errorBuilder.makeError 'notAllowed'
    m = if mode then true else false
    @directMessagingState.whitelistOnlySet m, (error) ->
      if error
        return cb makeServerError @errorBuilder, error
      cb()


class UserState
  constructor : (@username) ->
    @roomslist = new FastSet
    @sockets = new FastSet

  socketAdd : (id, cb) ->
    @sockets.add id
    process.nextTick -> cb null

  socketRemove : (id, cb) ->
    @sockets.remove id
    process.nextTick -> cb null

  socketsCount : (cb) ->
    nsockets = @sockets.length
    process.nextTick -> cb null, nsockets

  socketsGetAll : (cb) ->
    sockets = @sockets.toArray()
    process.nextTick -> cb null, sockets

  roomAdd : (roomName, cb) ->
    @roomslist.add roomName
    process.nextTick -> cb null

  roomRemove : (roomName, cb) ->
    @roomslist.remove roomName
    process.nextTick -> cb null

  roomsGetAll : (cb) ->
    rooms = @roomslist.toArray()
    process.nextTick -> cb null, rooms


class User extends UserDirectMessaging

  constructor : (@server, @username, state = UserState) ->
    super @server.errorBuilder, @username
    @userManager = @server.userManager
    @roomManager = @server.roomManager
    @enableUserlistUpdates = @server.enableUserlistUpdates
    @allowRoomsManagement = @server.allowRoomsManagement
    @allowDirectMessages = @server.allowDirectMessages
    @userState = new state @username

  ###
  # helpers
  ###

  registerSocket : (socket, cb) ->
    @userState.socketAdd socket.id, (error) =>
      if error
        return cb makeServerError @errorBuilder, error
      for own cmd of userCommands
        @bindCommand cmd, @[cmd], socket
      cb()

  withRoom : (roomName, fn) ->
    room = @roomManager.getRoom roomName
    error = @errorBuilder.makeError 'noRoom', roomName unless room
    fn error, room

  bindCommand : (name, fn, socket) ->
    cmd = wrapCommand @, name, fn
    socket.on name, (idcmd, args...) ->
      cmd socket, idcmd, null, args...

  send : (id, args...) ->
    @server.nsp.in(id).emit args...

  sendAccessRemoved : (userNames, roomName, cb) ->
    async.eachLimit userNames, asyncLimit
    , (userName, fn) =>
      user = @userManager.getUser userName
      unless user then return fn()
      user.userState.roomRemove roomName, (error) =>
        if error
          return fn makeServerError @errorBuilder, error
        user.userState.socketsGetAll (error, sockets) =>
          if error
            return fn makeServerError @errorBuilder, error
          for id in sockets
            @send id, 'roomAccessRemoved', roomName
          fn()
    , cb

  ###
  # commands
  ###

  directAddToList : (socket, idcmd, cb
  , listName, values) ->
    @addToList @username, listName, values, (error) ->
      sendResult socket, idcmd, cb, error

  directGetAccessList : (socket, idcmd, cb
  , listName) ->
    @getList @username, listName, (error, data) ->
      sendResult socket, idcmd, cb, error, data

  directGetWhitelistMode: (socket, idcmd, cb) ->
    @getMode @username, (error, data) ->
      sendResult socket, idcmd, cb, error, data

  directMessage : (socket, idcmd, cb
  , toUserName, msg) ->
    # TODO refactor checking logic
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
    processMessage msg
    toUser.message @username, msg, (error) =>
      if error
        return sendResult socket, idcmd, cb, error
      fromUser.userState.socketsGetAll (error, sockets) =>
        if error
          wrappedError = makeServerError @errorBuilder, error
          return sendResult socket, idcmd, cb, wrappedError
        for id in sockets
          if id != socket.id
            @send id, 'directMessageEcho', toUserName, msg
        toUser.userState.socketsGetAll (error, sockets) =>
          if error
            wrappedError = makeServerError @errorBuilder, error
            return sendResult socket, idcmd, cb, wrappedError
          for id in sockets
            @send id, 'directMessage', @username, msg
          sendResult socket, idcmd, cb

  directRemoveFromList : (socket, idcmd, cb
  , listName, values) ->
    @removeFromList @username, listName, values, (error) ->
      sendResult socket, idcmd, cb, error

  directSetWhitelistMode : (socket, idcmd, cb
  , mode) ->
    @changeMode @username, mode, (error) ->
      sendResult socket, idcmd, cb, error

  disconnect : (socket) ->
    # TODO lock user state
    @userState.socketRemove socket.id, (error) =>
      if error
        return makeServerError @errorBuilder, error
      @userState.socketsCount (error, nsockets) =>
        if error
          return makeServerError @errorBuilder, error
        if nsockets > 0 then return
        @userState.roomsGetAll (error, rooms) =>
          if error
            return makeServerError @errorBuilder, error
          for roomName in rooms
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
        if error then return sendResult socket, idcmd, cb, error
        @sendAccessRemoved data, roomName, (error) ->
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
      if error then return sendResult socket, idcmd, cb, error
      @roomManager.removeRoom room.name
      @sendAccessRemoved room, roomName, (error) ->
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
      if error then return sendResult socket, idcmd, cb, error
      @userState.roomAdd roomName, (error) =>
        if error
          wrappedError = makeServerError @errorBuilder, error
          return sendResult socket, idcmd, cb, wrappedError
        if @enableUserlistUpdates
          @send roomName, 'roomUserJoin', roomName, @username
        makeClosure = (id) =>
          return (error) =>
            # TODO other sockets errors handling
            if socket.id == id
              sendResult socket, idcmd, cb, error
            @send id, 'roomJoined', roomName
        # TODO lock user state
        @userState.socketsGetAll (error, sockets) =>
          if error
            wrappedError = makeServerError @errorBuilder, error
            return sendResult socket, idcmd, cb, wrappedError
          for id in sockets
            @server.nsp.adapter.add id, roomName, makeClosure id

  roomLeave : (socket, idcmd, cb
  , roomName) ->
    @withRoom roomName, (error, room) =>
      error = room.leave @username unless error
      if error
        wrappedError = makeServerError @errorBuilder, error
        return sendResult socket, idcmd, cb, wrappedError
      @userState.roomRemove roomName, (error) =>
        if error
          wrappedError = makeServerError @errorBuilder, error
          return sendResult socket, idcmd, cb, wrappedError
        if @enableUserlistUpdates
          @send roomName, 'roomUserLeave', roomName, @username
        makeClosure = (id) =>
          return (error) =>
            # TODO other sockets errors handling
            if socket.id == id
              sendResult socket, idcmd, cb, error
             @send id, 'roomLeft', roomName
        # TODO lock user state
        @userState.socketsGetAll (error, sockets) =>
          if error
            wrappedError = makeServerError @errorBuilder, error
            return sendResult socket, idcmd, cb, wrappedError
          for id in sockets
            @server.nsp.adapter.del id, roomName, makeClosure id

  roomMessage : (socket, idcmd, cb
  , roomName, msg) ->
    @withRoom roomName, (error, room) =>
      error = room.message @username, msg unless error
      unless error
        processMessage msg
        @send roomName, 'roomMessage', roomName, @username, msg
      return sendResult socket, idcmd, cb, error

  roomRemoveFromList : (socket, idcmd, cb
  , roomName, listName, values) ->
    @withRoom roomName, (error, room) =>
      if error then return sendResult socket, idcmd, cb, error
      { error, data } = room.removeFromList @username, listName, values
      if error then return sendResult socket, idcmd, cb, error
      @sendAccessRemoved data, roomName, (error) ->
        sendResult socket, idcmd, cb, error

  roomSetWhitelistMode : (socket, idcmd, cb
  , roomName, mode) ->
    @withRoom roomName, (error, room) =>
      if error then return sendResult socket, idcmd, cb, error
      { error, data } = room.changeMode @username, mode unless error
      if error then return sendResult socket, idcmd, cb, error
      @sendAccessRemoved data, roomName, (error) ->
        sendResult socket, idcmd, cb, error


class UserManager
  constructor : () ->
    # STATE
    @users = {}
    # END OF STATE

  getUser : (name) ->
    return @users[name]

  removeUser : (name) ->
    delete @users[name]

  # TODO async errors handling
  addUser : (user, socket, cb) ->
    name = user?.username
    currentUser = @users[name]
    if currentUser
      currentUser.registerSocket socket, cb
    else
      @users[name] = user
      user.registerSocket socket, cb


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
    # TODO error handling
    @userManager.addUser user, socket, ->
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
