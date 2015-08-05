
path = require 'path'
util = require 'util'
socketIO = require 'socket.io'
FastSet = require 'collections/fast-set'
Deque = require 'collections/deque'
async = require 'async'
# TODO messages arguments checking
check = require 'check-types'


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
  loginConfirmed: ''
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

# TODO log server errors function
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

  makeServerError : (err) ->
    return @makeError 'serverError', err.toString()

# TODO
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

processMessage = (author, msg) ->
  r = {}
  r.textMessage = msg?.textMessage?.toString() || ''
  r.timestamp = new Date().getTime()
  r.author = author
  return r

initState = (state, values) ->
  if state
    state.clear()
    if values
      state.addEach values


class RoomState
  constructor : (@name, @historyMaxMessages = 0) ->
    @whitelist = new FastSet
    @blacklist = new FastSet
    @adminlist = new FastSet
    @userlist = new FastSet
    @lastMessages = new Deque
    @whitelistOnly = false
    @owner = null

  initState : ( state = {}, cb ) ->
    { whitelist, blacklist, adminlist, userlist
    , lastMessages, whitelistOnly, owner } = state
    initState @whitelist, whitelist
    initState @blacklist, blacklist
    initState @adminlist, adminlist
    initState @userlist, userlist
    initState @lastMessages, lastMessages
    @whitelistOnly = if whitelistOnly then true else false
    @owner = if owner then owner else null
    if cb then process.nextTick -> cb()

  hasList : (listName) ->
    return listName in [ 'adminlist', 'whitelist', 'blacklist', 'userlist' ]

  checkList : (listName) ->
    unless @hasList listName then return "No list named #{listName}"
    return false

  addToList : (listName, elems, cb) ->
    error = @checkList listName
    if error then return process.nextTick -> cb error
    @[listName].addEach elems
    process.nextTick -> cb()

  removeFromList : (listName, elems, cb) ->
    error = @checkList listName
    if error then return process.nextTick -> cb error
    @[listName].deleteEach elems
    process.nextTick -> cb()

  getList : (listName, cb) ->
    error = @checkList listName
    if error then return process.nextTick -> cb error
    data = @[listName].toArray()
    process.nextTick -> cb null, data

  hasInList : (listName, elem, cb) ->
    error = @checkList listName
    if error then return process.nextTick -> cb error
    data = @[listName].has elem
    process.nextTick -> cb null, data

  whitelistOnlySet : (mode, cb) ->
    @whitelistOnly = if mode then true else false
    process.nextTick -> cb()

  whitelistOnlyGet : (cb) ->
    m = @whitelistOnly
    process.nextTick -> cb null, m

  ownerGet : (cb) ->
    owner = @owner
    process.nextTick -> cb null, owner

  ownerSet : (owner, cb) ->
    @owner = owner
    process.nextTick -> cb()

  messageAdd : (msg, cb) ->
    if @historyMaxMessages <= 0 then return process.nextTick -> cb()
    if @lastMessages.length >= @historyMaxMessages
      @lastMessages.pop()
    @lastMessages.unshift msg
    process.nextTick -> cb()

  messagesGet : (cb) ->
    data = @lastMessages.toArray()
    process.nextTick -> cb null, data

  getCommonUsers : (cb) ->
    diff = (@userlist.difference @whitelist).difference @adminlist
    data = diff.toArray()
    process.nextTick -> cb null, data


class Room

  constructor : (@server, @name, state = RoomState) ->
    @errorBuilder = @server.errorBuilder
    @roomState = new state @name, @server.historyMaxMessages

  initState : (state, cb) ->
    @roomState.initState state, cb

  ###
  # helpers
  ###

  isAdmin : (userName, cb) ->
    @roomState.ownerGet (error, owner) =>
      if error then return cb @errorBuilder.makeServerError error
      @roomState.hasInList 'adminlist', userName, (error, hasName) =>
        if error then return cb @errorBuilder.makeServerError error
        admin = owner == userName or hasName
        admin = if admin then true else false
        cb null, admin

  hasRemoveChangedCurrentAccess : (userName, listName, cb) ->
    @roomState.hasInList 'userlist', userName, (error, hasUser) =>
      if error then return cb @errorBuilder.makeServerError error
      unless hasUser then return cb null, false
      @isAdmin userName, (error, admin) =>
        if error then return cb error
        if admin then return cb null, false
        if listName == 'whitelist'
          @roomState.whitelistOnlyGet (error, whitelistOnly) =>
            if error then return cb @errorBuilder.makeServerError error
            cb null, true
        else
          cb null, false

  hasAddChangedCurrentAccess : (userName, listName, cb) ->
    @roomState.hasInList 'userlist', userName, (error, hasUser) =>
      if error then return cb @errorBuilder.makeServerError error
      unless hasUser then return cb null, false
      if listName == 'blacklist' then return cb null, true
      cb null, false

  getModeChangedCurrentAccess : (value, cb) ->
    unless value
      process.nextTick -> cb null, false
    else
      @roomState.getCommonUsers (error, users) =>
        if error then return cb @errorBuilder.makeServerError error
        cb null, users

  ###
  # access checking
  ###

  checkList : (author, listName, cb) ->
    @roomState.hasInList 'userlist', author, (error, hasAuthor) =>
      if error then return cb @errorBuilder.makeServerError error
      unless hasAuthor
        return cb @errorBuilder.makeError 'notJoined', @name
      unless @roomState.hasList listName
        return cb @errorBuilder.makeError 'noList', listName
      cb()

  checkListChange : (author, listName, name, cb) ->
    @checkList author, listName, (error) =>
      if error then return cb error
      @roomState.ownerGet (error, owner) =>
        if error then return cb @errorBuilder.makeServerError error
        if listName == 'userlist'
          return cb @errorBuilder.makeError 'notAllowed'
        if author == owner
          return cb()
        if name == owner
          return cb @errorBuilder.makeError 'notAllowed'
        @roomState.hasInList 'adminlist', name, (error, hasName) =>
          if error then return cb @errorBuilder.makeServerError error
          if hasName
            return cb @errorBuilder.makeError 'notAllowed'
          @roomState.hasInList 'adminlist', author, (error, hasAuthor) =>
            if error then return cb @errorBuilder.makeServerError error
            unless hasAuthor
              return cb @errorBuilder.makeError 'notAllowed'
            cb()

  checkListAdd : (author, listName, name, cb) ->
    @checkListChange author, listName, name, (error) =>
      if error then return cb error
      @roomState.hasInList listName, name, (error, hasName) =>
        if error then return cb @errorBuilder.makeServerError error
        if hasName
          return cb @errorBuilder.makeError 'nameInList', name, listName
        cb()

  checkListRemove : (author, listName, name, cb) ->
    @checkListChange author, listName, name, (error) =>
      if error then return cb error
      @roomState.hasInList listName, name, (error, hasName) =>
        unless hasName
          return cb @errorBuilder.makeError 'noNameInList', name, listName
        cb()

  checkModeChange : (author, value, cb) ->
    @isAdmin author, (error, admin) =>
      if error then return cb error
      unless admin
        return cb @errorBuilder.makeError 'notAllowed'
      cb()

  checkAcess : (userName, cb) ->
    @isAdmin userName, (error, admin) =>
      if error then return cb error
      if admin then return cb()
      @roomState.hasInList 'blacklist', userName, (error, inBlacklist) =>
        if error then return cb @errorBuilder.makeServerError error
        if inBlacklist
          return cb @errorBuilder.makeError 'notAllowed'
        @roomState.whitelistOnlyGet (error, whitelistOnly) =>
          if error then return cb @errorBuilder.makeServerError error
          @roomState.hasInList 'whitelist', userName, (error, inWhitelist) =>
            if error then return cb @errorBuilder.makeServerError error
            if whitelistOnly and not inWhitelist
              return cb @errorBuilder.makeError 'notAllowed'
            cb()

  checkIsOwner : (author, cb) ->
    @roomState.ownerGet (error, owner) =>
      unless owner == author
        return cb @errorBuilder.makeError 'notAllowed'
      cb()

  ###
  # actions execution
  ###

  leave : (userName, cb) ->
    @roomState.removeFromList 'userlist', [userName]
    , (error) =>
      if error then return cb @errorBuilder.makeServerError error
      cb()

  join : (userName, cb) ->
    @checkAcess userName, (error) =>
      if error then return cb error
      @roomState.addToList 'userlist', [userName]
      , (error) =>
        if error then return cb @errorBuilder.makeServerError error
        cb()

  message : (author, msg, cb) ->
    @roomState.hasInList 'userlist', author, (error, hasAuthor) =>
      if error then return cb @errorBuilder.makeServerError error
      unless hasAuthor
        return @errorBuilder.makeError 'notJoined', @name
      @roomState.messageAdd msg, (error) =>
        if error then return cb @errorBuilder.makeServerError error
        cb()

  getList : (author, listName, cb) ->
    @checkList author, listName, (error) =>
      if error then return cb error
      @roomState.getList listName, (error, list) =>
        if error then return cb @errorBuilder.makeServerError error
        cb null, list

  getLastMessages : (author, cb) ->
    @roomState.hasInList 'userlist', author, (error, hasAuthor) =>
      if error then return cb @errorBuilder.makeServerError error
      unless hasAuthor
        return cb @errorBuilder.makeError 'notJoined', @name
      @roomState.messagesGet (error, data) =>
        if error then return cb @errorBuilder.makeServerError error
        cb null, data

  addToList : (author, listName, values, cb) ->
    async.eachLimit values, asyncLimit, (val, fn) =>
      @checkListAdd author, listName, val, fn
    , (error) =>
      if error then return cb error
      data = []
      async.eachLimit values, asyncLimit
      , (val, fn) =>
        @hasAddChangedCurrentAccess val, listName, (error, changed) ->
          if error then return fn error
          if changed then data.push val
          fn()
      , (error) =>
        if error then return cb error
        @roomState.addToList listName, values, (error) =>
          if error then return cb @errorBuilder.makeServerError error
          cb null, data

  removeFromList : (author, listName, values, cb) ->
    async.eachLimit values, asyncLimit, (val, fn) =>
      @checkListRemove author, listName, val, fn
    , (error) =>
      if error then return cb error
      data = []
      async.eachLimit values, asyncLimit
      , (val, fn) =>
        @hasRemoveChangedCurrentAccess val, listName, (error, changed) ->
          if error then return fn error
          if changed then data.push val
          fn()
      , (error) =>
        if error then return cb error
        @roomState.removeFromList listName, values, (error) =>
          if error then return cb @errorBuilder.makeServerError error
          cb null, data

  getMode : (author, cb) ->
    @roomState.whitelistOnlyGet (error, data) =>
      if error then return cb @errorBuilder.makeServerError error
      cb null, data

  changeMode : (author, mode, cb) ->
    @checkModeChange author, mode, (error) =>
      if error then return cb error
      whitelistOnly = if mode then true else false
      @roomState.whitelistOnlySet whitelistOnly, (error) =>
        if error then return cb @errorBuilder.makeServerError error
        @getModeChangedCurrentAccess whitelistOnly, (error, data) ->
          cb error, data


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
    @enableRoomsManagement = @server.enableRoomsManagement
    @enableDirectMessages = @server.enableDirectMessages
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
    unless @enableDirectMessages
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
    msg = processMessage @username, msg
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
          async.eachLimit rooms, asyncLimit
          , (roomName, fn) =>
            room = @roomManager.getRoom roomName
            room.leave @username, () =>
              if @enableUserlistUpdates
                @server.nsp.in(roomName).emit 'roomUserLeave'
                , roomName, @username
              fn()
           , () =>
            @userManager.removeUser @username

  listRooms : (socket, idcmd, cb) ->
    @roomManager.listRooms @username, (error, data) ->
      return sendResult socket, idcmd, cb, error, data

  roomAddToList : (socket, idcmd, cb
  , roomName, listName, values) ->
    @withRoom roomName, (error, room) =>
      if error then sendResult socket, idcmd, cb, error
      room.addToList @username, listName, values, (error, data) =>
        if error then return sendResult socket, idcmd, cb, error
        @sendAccessRemoved data, roomName, (error) ->
          sendResult socket, idcmd, cb, error

  roomCreate : (socket, idcmd, cb
  , roomName, whitelistOnly) ->
    unless @enableRoomsManagement
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
    room = new Room @server, roomName
    room.initState { owner : @username, whitelistOnly : whitelistOnly }
    , (error) =>
      unless error
        @roomManager.addRoom room
      return sendResult socket, idcmd, cb, error

  roomDelete : (socket, idcmd, cb
  , roomName) ->
    unless @enableRoomsManagement
      err = @errorBuilder.makeError 'notAllowed'
      return sendResult socket, idcmd, cb, err
    @withRoom roomName, (error, room) =>
      if error then sendResult socket, idcmd, cb, error
      room.checkIsOwner @username, (error) =>
        if error then return sendResult socket, idcmd, cb, error
        @roomManager.removeRoom room.name
        room.roomState.getList 'userlist', (error, list) =>
          if error
            wrappedError = makeServerError @errorBuilder, error
            return sendResult socket, idcmd, cb, wrappedError
          @sendAccessRemoved list, roomName, (error) ->
            sendResult socket, idcmd, cb, error

  roomGetAccessList : (socket, idcmd, cb
  , roomName, listName) ->
    @withRoom roomName, (error, room) =>
      if error then return sendResult socket, idcmd, cb, error
      room.getList @username, listName, (error, data) ->
        sendResult socket, idcmd, cb, error, data

  roomGetWhitelistMode : (socket, idcmd, cb
  , roomName) ->
    @withRoom roomName, (error, room) =>
      if error then return sendResult socket, idcmd, cb, error
      room.getMode @username, (error, data) ->
        sendResult socket, idcmd, cb, error, data

  roomHistory : (socket, idcmd, cb
  , roomName) ->
    @withRoom roomName, (error, room) =>
      if error then return sendResult socket, idcmd, cb, error
      room.getLastMessages @username, (error, data) ->
        sendResult socket, idcmd, cb, error, data

  roomJoin : (socket, idcmd, cb
  , roomName) ->
    @withRoom roomName, (error, room) =>
      if error then return sendResult socket, idcmd, cb, error
      room.join @username, (error) =>
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
      if error then return sendResult socket, idcmd, cb, error
      room.leave @username, (error) =>
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
      if error then return sendResult socket, idcmd, cb, error
      room.message @username, msg, (error) =>
        unless error
          msg = processMessage @username, msg
          @send roomName, 'roomMessage', roomName, @username, msg
        return sendResult socket, idcmd, cb, error

  roomRemoveFromList : (socket, idcmd, cb
  , roomName, listName, values) ->
    @withRoom roomName, (error, room) =>
      if error then return sendResult socket, idcmd, cb, error
      room.removeFromList @username, listName, values, (error, data) =>
        if error then return sendResult socket, idcmd, cb, error
        @sendAccessRemoved data, roomName, (error) ->
          sendResult socket, idcmd, cb, error

  roomSetWhitelistMode : (socket, idcmd, cb
  , roomName, mode) ->
    @withRoom roomName, (error, room) =>
      if error then return sendResult socket, idcmd, cb, error
      room.changeMode @username, mode, (error, data) =>
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

  listRooms : (author, cb) ->
    list = []
    async.forEachOfLimit @rooms, asyncLimit
    , (room, name, fn) ->
      # TODO error handling
      room.getMode author, (error, isPrivate) ->
        unless isPrivate then list.push name
        fn()
    , ->
      list.sort()
      cb null, list


class ChatService
  constructor : (@options = {}, @hooks = {}) ->
    @io = @options.io
    @sharedIO = true if @io
    @http = @options.http unless @io

    # options, constant for a server instance
    @namespace = @options.namespace || '/chat-service'
    @historyMaxMessages = @options.historyMaxMessages || 100
    @useRawErrorObjects = @options.useRawErrorObjects || false
    @enableUserlistUpdates = @options.enableUserlistUpdates || false
    @enableRoomsManagement = @options.enableRoomsManagement || false
    @enableDirectMessages = @options.enableDirectMessages || false
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
