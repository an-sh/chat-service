
Deque = require 'collections/deque'
FastSet = require 'collections/fast-set'
Map = require 'collections/fast-map'
_ = require 'lodash'
async = require 'async'
{ withEH, asyncLimit } = require './utils.coffee'


# @private
# @nodoc
initState = (state, values) ->
  if state
    state.clear()
    if values
      state.addEach values


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
  constructor : (@server, @name) ->
    @errorBuilder = @server.errorBuilder
    @historyMaxGetMessages = @server.historyMaxGetMessages
    @historyMaxMessages = @server.historyMaxMessages
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
    process.nextTick -> cb()

  # @private
  removeState : (cb) ->
    process.nextTick -> cb()

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
    process.nextTick -> cb()

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
    @socketrooms = @server.state.socketrooms
    @roomsockets = @server.state.roomsockets

  # @private
  addSocket : (id, cb) ->
    @sockets.add id
    process.nextTick -> cb null

  # @private
  removeSocket : (id, cb) ->
    @sockets.remove id
    process.nextTick -> cb null

  # @private
  getAllSockets : (cb) ->
    sockets = @sockets.toArray()
    process.nextTick -> cb null, sockets

  # @private
  getAllRooms : (cb) ->
    rooms = @roomslist.toArray()
    process.nextTick -> cb null, rooms

  # @private
  getRoomSocketsSync : (roomName) ->
    socketsset = @roomsockets.get roomName
    s = @sockets.intersection socketsset
    s.toArray()

  # @private
  getRoomSockets : (roomName, cb) ->
    sockets = @getRoomSocketsSync roomName
    process.nextTick -> cb null, sockets

  # @private
  addSocketToRoom : (roomName, id, cb) ->
    roomsset = @socketrooms.get id
    socketsset = @roomsockets.get roomName
    unless roomsset
      roomsset = new FastSet
      @socketrooms.set id, roomsset
    unless socketsset
      socketsset = new FastSet
      @roomsockets.set roomName, socketsset
    roomsset.add roomName
    socketsset.add id
    @roomslist.add roomName
    process.nextTick -> cb null

  # @private
  removeSocketFromRoom : (roomName, id, cb) ->
    roomsset = @socketrooms.get id
    socketsset = @roomsockets.get roomName
    roomsset?.remove roomName
    socketsset?.remove id
    unless @getRoomSocketsSync(roomName)?.length
      @roomslist.remove roomName
    process.nextTick -> cb null

  # @private
  removeAllSocketsFromRoom : (roomName, cb) ->
    sockets = @sockets.toArray()
    socketsset = @roomsockets.get roomName
    for id in socketsset?.toArray()
      roomsset = @socketrooms.get id
      roomsset?.remove roomName
    socketsset = socketsset?.difference sockets
    @roomsockets.set roomName, socketsset
    @roomslist.remove roomName
    process.nextTick -> cb null


# Implements global state API.
# @private
# @nodoc
class MemoryState

  # @private
  constructor : (@server, @options) ->
    @errorBuilder = @server.errorBuilder
    @users = {}
    @rooms = {}
    @socketrooms = new Map
    @roomsockets = new Map
    @RoomState = RoomStateMemory
    @UserState = UserStateMemory
    @DirectMessagingState = DirectMessagingStateMemory

  # @private
  getRoom : (name, cb) ->
    r = @rooms[name]
    unless r
      error = @errorBuilder.makeError 'noRoom', name
    process.nextTick -> cb error, r

  # @private
  addRoom : (name, state, cb) ->
    room = @server.makeRoom name
    unless @rooms[name]
      @rooms[name] = room
    else
      error = @errorBuilder.makeError 'roomExists', name
      return process.nextTick -> cb error
    if state
      room.initState state, cb
    else
      process.nextTick -> cb()

  # @private
  removeRoom : (name, cb) ->
    if @rooms[name]
      delete @rooms[name]
    else
      error = @errorBuilder.makeError 'noRoom', name
    process.nextTick -> cb error

  # @private
  listRooms : (cb) ->
    process.nextTick => cb null, _.keys @rooms

  # @private
  removeSocket : (uid, id, cb) ->
    process.nextTick ->
      cb null

  # @private
  lockUser : (name, cb) ->
    process.nextTick ->
      cb null, { unlock : -> }

  # @private
  loginUser : (uid, name, socket, cb) ->
    user = @users[name]
    if user
      user.registerSocket socket, cb
    else
      newUser = @server.makeUser name
      @users[name] = newUser
      newUser.registerSocket socket, cb

  # @private
  getUser : (name, cb) ->
    user = @users[name]
    unless user
      error = @errorBuilder.makeError 'noUser', name
    process.nextTick -> cb error, user

  # @private
  addUser : (name, state, cb) ->
    user = @users[name]
    if user
      error = @errorBuilder.makeError 'userExists', name
      return process.nextTick -> cb error
    user = @server.makeUser name
    @users[name] = user
    if state
      user.initState state, cb
    else
      process.nextTick -> cb()

  # @private
  removeUser : (name, cb) ->
    user = @users[name]
    unless user
      error = @errorBuilder.makeError 'noUser', name
      return process.nextTick -> cb error
    user.disconnectSockets withEH cb, =>
      delete @users[name]
      process.nextTick -> cb()


module.exports = MemoryState
