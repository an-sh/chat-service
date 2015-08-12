
async = require 'async'
ErrorBuilder = require('./errors.coffee').ErrorBuilder
FastSet = require 'collections/fast-set'
Deque = require 'collections/deque'


initState = (state, values) ->
  if state
    state.clear()
    if values
      state.addEach values


asyncLimit = 16


class ListsStateHelper

  checkList : (listName) ->
    unless @hasList listName
      return @errorBuilder.makeError 'noList', listName

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


class RoomState extends ListsStateHelper

  constructor : (@server, @name, @historyMaxMessages = 0) ->
    @errorBuilder = @server.errorBuilder
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


class DirectMessagingState extends ListsStateHelper

  constructor : (@server, @username) ->
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


class UserState

  constructor : (@server, @username) ->
    @roomslist = new FastSet
    @sockets = new FastSet

  socketAdd : (id, cb) ->
    @sockets.add id
    process.nextTick -> cb null

  socketRemove : (id, cb) ->
    @sockets.remove id
    process.nextTick -> cb null

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


class MemoryState

  constructor : (@server) ->
    @errorBuilder = @server.errorBuilder
    @usersOnline = {}
    @usersOffline = {}
    @rooms = {}
    @roomState = RoomState
    @userState = UserState
    @directMessagingState = DirectMessagingState

  getRoom : (name, cb) ->
    r = @rooms[name]
    unless r
      error = @errorBuilder.makeError 'noRoom', name
    process.nextTick -> cb error, r

  addRoom : (room, cb) ->
    name = room.name
    unless @rooms[name]
      @rooms[name] = room
    else
      error = @errorBuilder.makeError 'roomExists', name
    process.nextTick -> cb error

  removeRoom : (name, cb) ->
    if @rooms[name]
      delete @rooms[name]
    else
      error = @errorBuilder.makeError 'noRoom', name
    process.nextTick -> cb error

  listRooms : (cb) ->
    list = []
    async.forEachOfLimit @rooms, asyncLimit
    , (room, name, fn) ->
      room.roomState.whitelistOnlyGet (error, isPrivate) ->
        unless error or isPrivate then list.push name
        fn()
    , ->
      list.sort()
      cb null, list

  getOnlineUser : (name, cb) ->
    u = @usersOnline[name]
    unless u
      error = @errorBuilder.makeError 'noUserOnline', name
    process.nextTick -> cb error, u

  getUser : (name, cb) ->
    isOnline = true
    u = @usersOnline[name]
    unless u
      u = @usersOffline[name]
      isOnline = false
    process.nextTick -> cb null, u, isOnline

  loginUser : (name, socket, cb) ->
    currentUser = @usersOnline[name]
    returnedUser = @usersOffline[name] unless currentUser
    if currentUser
      currentUser.registerSocket socket, (error) ->
        cb error, currentUser
    else if returnedUser
      @usersOnline[name] = returnedUser
      delete @usersOffline[name]
      returnedUser.registerSocket socket, (error) ->
        cb error, returnedUser
    else
      newUser = new @server.User @server, name
      @usersOnline[name] = newUser
      newUser.registerSocket socket, (error) ->
        cb error, newUser

  logoutUser : (name, cb) ->
    unless @usersOnline[name]
      error = @errorBuilder.makeError 'noUserOnline', name
    else
      @usersOffline[name] = @usersOnline[name]
      delete @usersOnline[name]
    process.nextTick -> cb error

  addUser : (name, cb, state = null) ->
    u1 = @usersOnline[name]
    u2 = @usersOffline[name]
    if u1 or u2
      error = @errorBuilder.makeError 'userExists', name
      return process.nextTick -> cb error
    user = new @server.User @server, name
    @usersOffline[name] = user
    if state
      user.initState state, cb
    else if cb then cb()

  removeUser : (name, cb) ->
    u1 = @usersOnline[name]
    fn = =>
      u2 = @usersOffline[name]
      delete @usersOnline[name]
      delete @usersOffline[name]
      unless u1 or u2
        error = @errorBuilder.makeError 'noUser', name
      cb error if cb
    if u1 then u1.removeUser fn
    else process.nextTick -> fn()


module.exports = {
  MemoryState
}
