
async = require 'async'
FastSet = require 'collections/fast-set'
Deque = require 'collections/deque'


ErrorBuilder = require('./errors.coffee').ErrorBuilder
withEH = require('./errors.coffee').withEH

# @private
initState = (state, values) ->
  if state
    state.clear()
    if values
      state.addEach values


asyncLimit = 16


# Implements state API lists management.
# @private
class ListsState

  # @private
  checkList : (listName, cb) ->
    unless @hasList listName
      error = @errorBuilder.makeError 'noList', listName
    process.nextTick -> cb error

  # @private
  addToList : (listName, elems, cb) ->
    @checkList listName, withEH cb, =>
      @[listName].addEach elems
      cb()

  # @private
  removeFromList : (listName, elems, cb) ->
    @checkList listName, withEH cb, =>
      @[listName].deleteEach elems
      cb()

  # @private
  getList : (listName, cb) ->
    @checkList listName, withEH cb, =>
      data = @[listName].toArray()
      cb null, data

  # @private
  hasInList : (listName, elem, cb) ->
    @checkList listName, withEH cb, =>
      data = @[listName].has elem
      data = if data then true else false
      cb null, data

  # @private
  whitelistOnlySet : (mode, cb) ->
    @whitelistOnly = if mode then true else false
    process.nextTick -> cb()

  # @private
  whitelistOnlyGet : (cb) ->
    m = @whitelistOnly
    process.nextTick -> cb null, m


# Implements room state API.
# @private
class RoomState extends ListsState

  # @private
  constructor : (@server, @name, @historyMaxMessages = 0) ->
    @errorBuilder = @server.errorBuilder
    @whitelist = new FastSet
    @blacklist = new FastSet
    @adminlist = new FastSet
    @userlist = new FastSet
    @lastMessages = new Deque
    @whitelistOnly = false
    @owner = null

  # @private
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

  # @private
  hasList : (listName) ->
    return listName in [ 'adminlist', 'whitelist', 'blacklist', 'userlist' ]

  # @private
  ownerGet : (cb) ->
    owner = @owner
    process.nextTick -> cb null, owner

  # @private
  ownerSet : (owner, cb) ->
    @owner = owner
    process.nextTick -> cb()

  # @private
  messageAdd : (msg, cb) ->
    if @historyMaxMessages <= 0 then return process.nextTick -> cb()
    if @lastMessages.length >= @historyMaxMessages
      @lastMessages.pop()
    @lastMessages.unshift msg
    process.nextTick -> cb()

  # @private
  messagesGet : (cb) ->
    data = @lastMessages.toArray()
    process.nextTick -> cb null, data

  # @private
  getCommonUsers : (cb) ->
    diff = (@userlist.difference @whitelist).difference @adminlist
    data = diff.toArray()
    process.nextTick -> cb null, data


# Implements direct messaging state API.
# @private
class DirectMessagingState extends ListsState

  # @private
  constructor : (@server, @username) ->
    @whitelistOnly
    @whitelist = new FastSet
    @blacklist = new FastSet

  # @private
  initState : ({ whitelist, blacklist, whitelistOnly } = {}, cb) ->
    initState @whitelist, whitelist
    initState @blacklist, blacklist
    @whitelistOnly = if whitelistOnly then true else false
    process.nextTick -> cb()

  # @private
  hasList : (listName) ->
    return listName in [ 'whitelist', 'blacklist' ]


# Implements user state API.
# @private
class UserState

  # @private
  constructor : (@server, @username) ->
    @roomslist = new FastSet
    @sockets = new FastSet

  # @private
  socketAdd : (id, cb) ->
    @sockets.add id
    process.nextTick -> cb null

  # @private
  socketRemove : (id, cb) ->
    @sockets.remove id
    process.nextTick -> cb null

  # @private
  socketsGetAll : (cb) ->
    sockets = @sockets.toArray()
    process.nextTick -> cb null, sockets

  # @private
  roomAdd : (roomName, cb) ->
    @roomslist.add roomName
    process.nextTick -> cb null

  # @private
  roomRemove : (roomName, cb) ->
    @roomslist.remove roomName
    process.nextTick -> cb null

  # @private
  roomsGetAll : (cb) ->
    rooms = @roomslist.toArray()
    process.nextTick -> cb null, rooms


# Implements global state API.
# @private
class MemoryState

  # @private
  constructor : (@server) ->
    @errorBuilder = @server.errorBuilder
    @usersOnline = {}
    @usersOffline = {}
    @rooms = {}
    @roomState = RoomState
    @userState = UserState
    @directMessagingState = DirectMessagingState

  # @private
  getRoom : (name, cb) ->
    r = @rooms[name]
    unless r
      error = @errorBuilder.makeError 'noRoom', name
    process.nextTick -> cb error, r

  # @private
  addRoom : (room, cb) ->
    name = room.name
    unless @rooms[name]
      @rooms[name] = room
    else
      error = @errorBuilder.makeError 'roomExists', name
    process.nextTick -> cb error

  # @private
  removeRoom : (name, cb) ->
    if @rooms[name]
      delete @rooms[name]
    else
      error = @errorBuilder.makeError 'noRoom', name
    process.nextTick -> cb error

  # @private
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

  # @private
  getOnlineUser : (name, cb) ->
    u = @usersOnline[name]
    unless u
      error = @errorBuilder.makeError 'noUserOnline', name
    process.nextTick -> cb error, u

  # @private
  getUser : (name, cb) ->
    isOnline = true
    u = @usersOnline[name]
    unless u
      u = @usersOffline[name]
      isOnline = false
    process.nextTick -> cb null, u, isOnline

  # @private
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

  # @private
  logoutUser : (name, cb) ->
    unless @usersOnline[name]
      error = @errorBuilder.makeError 'noUserOnline', name
    else
      @usersOffline[name] = @usersOnline[name]
      delete @usersOnline[name]
    process.nextTick -> cb error

  # @private
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

  # @private
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
