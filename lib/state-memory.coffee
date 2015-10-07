
async = require 'async'
FastSet = require 'collections/fast-set'
Deque = require 'collections/deque'
withEH = require('./errors.coffee').withEH


# @private
# @nodoc
initState = (state, values) ->
  if state
    state.clear()
    if values
      state.addEach values


# @private
# @nodoc
asyncLimit = 16


# Implements state API lists management.
# @private
# @nodoc
class ListsStateMemory

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
# @nodoc
class RoomStateMemory extends ListsStateMemory

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
  initState : (state = {}, cb) ->
    { whitelist, blacklist, adminlist
    , lastMessages, whitelistOnly, owner } = state
    initState @whitelist, whitelist
    initState @blacklist, blacklist
    initState @adminlist, adminlist
    initState @lastMessages, lastMessages
    @whitelistOnly = if whitelistOnly then true else false
    @owner = if owner then owner else null
    if cb then process.nextTick -> cb()

  # @private
  removeState : (cb) ->
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
    @lastMessages.unshift msg
    if @lastMessages.length > @historyMaxMessages
      @lastMessages.pop()
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
# @nodoc
class DirectMessagingStateMemory extends ListsStateMemory

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
    if cb then process.nextTick -> cb()

  # @private
  hasList : (listName) ->
    return listName in [ 'whitelist', 'blacklist' ]


# Implements user state API.
# @private
# @nodoc
class UserStateMemory

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
# @nodoc
class MemoryState

  # @private
  constructor : (@server, @options) ->
    @errorBuilder = @server.errorBuilder
    @usersOnline = {}
    @users = {}
    @rooms = {}
    @roomState = RoomStateMemory
    @userState = UserStateMemory
    @directMessagingState = DirectMessagingStateMemory

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
    process.nextTick ->
      if error then cb error else cb null, 1

  # @private
  removeRoom : (name, cb) ->
    if @rooms[name]
      delete @rooms[name]
    else
      error = @errorBuilder.makeError 'noRoom', name
    process.nextTick -> cb error

  # @private
  listRooms : (cb) ->
    process.nextTick => cb null, Object.keys @rooms

  # @private
  getOnlineUser : (name, cb) ->
    u = @usersOnline[name]
    unless u
      error = @errorBuilder.makeError 'noUserOnline', name
    process.nextTick -> cb error, u

  # @private
  lockUser : (name, cb) ->
    process.nextTick ->
      cb null, { unlock : -> }

  # @private
  getUser : (name, cb) ->
    isOnline = if @usersOnline[name] then true else false
    user = @users[name]
    unless user
      error = @errorBuilder.makeError 'noUser', name
    process.nextTick -> cb error, user, isOnline

  # @private
  loginUser : (name, socket, cb) ->
    currentUser = @usersOnline[name]
    returnedUser = @users[name] unless currentUser
    if currentUser
      currentUser.registerSocket socket, (error) ->
        cb error, currentUser
    else if returnedUser
      @usersOnline[name] = returnedUser
      returnedUser.registerSocket socket, (error) ->
        cb error, returnedUser
    else
      newUser = new @server.User name
      @usersOnline[name] = newUser
      @users[name] = newUser
      newUser.registerSocket socket, (error) ->
        cb error, newUser

  # @private
  logoutUser : (name, cb) ->
    unless @usersOnline[name]
      error = @errorBuilder.makeError 'noUserOnline', name
    else
      delete @usersOnline[name]
    process.nextTick -> cb error

  # @private
  addUser : (name, cb, state = null) ->
    user = @users[name]
    if user
      error = @errorBuilder.makeError 'userExists', name
      return process.nextTick -> cb error
    user = new @server.User name
    @users[name] = user
    if state
      user.initState state, cb
    else if cb
      process.nextTick -> cb()

  # @private
  removeUser : (name, cb) ->
    user = @usersOnline[name]
    fn = =>
      user = @users[name]
      unless user
        error = @errorBuilder.makeError 'noUser', name
      else
        delete @usersOnline[name]
        delete @users[name]
      cb error if cb
    if user then user.disconnectUser fn
    else process.nextTick -> fn()


module.exports = {
  MemoryState
}
