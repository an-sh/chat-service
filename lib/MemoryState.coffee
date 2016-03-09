
FastSet = require 'collections/fast-set'
List = require 'collections/list'
Map = require 'collections/fast-map'
Room = require './Room.coffee'
User = require './User.coffee'
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
    @messagesHistory = new List
    @messagesTimestamps = new List
    @messagesIDs = new List
    @lastMessageID = 0
    @whitelistOnly = false
    @owner = null

  # @private
  initState : (state = {}, cb) ->
    { whitelist, blacklist, adminlist
    , whitelistOnly, owner } = state
    initState @whitelist, whitelist
    initState @blacklist, blacklist
    initState @adminlist, adminlist
    initState @messagesHistory
    initState @messagesTimestamps
    initState @messagesIDs
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
    @messagesHistory.unshift msg
    timestamp = _.now()
    @messagesTimestamps.unshift timestamp
    @lastMessageID++
    id = @lastMessageID
    @messagesIDs.unshift id
    if @messagesHistory.length > @historyMaxMessages
      @messagesHistory.pop()
      @messagesTimestamps.pop()
      @messagesIDs.pop()
    msg.timestamp = timestamp
    msg.id = id
    process.nextTick -> cb null, msg

  # @private
  messagesGetRecent : (cb) ->
    msgs = @messagesHistory.slice 0, @historyMaxGetMessages
    tss = @messagesTimestamps.slice 0, @historyMaxGetMessages
    ids = @messagesIDs.slice 0, @historyMaxGetMessages
    data = []
    for msg, idx in msgs
      obj = _.cloneDeep msg
      obj.timestamp = tss[idx]
      obj.id = ids[idx]
      data[idx] = obj
    process.nextTick -> cb null, data

  # @private
  messagesGetLastId : (cb) ->
    id = @messagesIDs.peek()
    process.nextTick -> cb null, data

  # @private
  messagesGetAfterId : (id, cb) ->
    nmessages = @messageIDS.length
    maxlen = @historyMaxGetMessages
    lastid = @messagesIDs.peek()
    id = _.min [ id, lastid ]
    end = _.min [ maxlen, lastid - id ]
    start = _.min [ 0, end - maxlen ]
    if start == end
      return process.nextTick -> cb null, []
    msgs = @messagesHistory.slice start, end
    tss = @messagesTimestamps.slice start, end
    ids = @messagesIDs.slice start, end
    data = []
    for msg, idx in msgs
      obj = _.cloneDeep msg
      msg.timestamp = tss[idx]
      msg.id = ids[idx]
      data[idx] = obj
    process.nextTick -> cb null, msgs

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
    @socketsToRooms = new Map
    @roomsToSockets = new Map
    @echoChannel = @makeEchoChannelName @username

  # @private
  makeEchoChannelName : (userName) ->
    "echo:#{userName}"

  # @private
  addSocket : (id, cb) ->
    roomsset = new FastSet
    @socketsToRooms.set id, roomsset
    nconnected = @socketsToRooms.length
    process.nextTick -> cb null, nconnected

  # @private
  getAllSockets : (cb) ->
    sockets = @socketsToRooms.keys()
    process.nextTick -> cb null, sockets

  # @private
  getAllRooms : (cb) ->
    rooms = @roomsToSockets.keys()
    process.nextTick -> cb null, rooms

  # @private
  getSocketsToRooms : (cb) ->
    result = {}
    sockets = @socketsToRooms.keys()
    for id in sockets
      socketsset = @socketsToRooms.get id
      result[id] = socketsset.toArray()
    process.nextTick -> cb null, result

  # @private
  addSocketToRoom : (id, roomName, cb) ->
    roomsset = @socketsToRooms.get id
    socketsset = @roomsToSockets.get roomName
    unless socketsset
      socketsset = new FastSet
      @roomsToSockets.set roomName, socketsset
    roomsset.add roomName
    socketsset.add id
    njoined = socketsset.length
    process.nextTick -> cb null, njoined

  # @private
  removeSocketFromRoom : (id, roomName, cb) ->
    roomsset = @socketsToRooms.get id
    socketsset = @roomsToSockets.get roomName
    roomsset.delete roomName
    socketsset?.delete id
    njoined = socketsset?.length || 0
    process.nextTick -> cb null, njoined

  # @private
  removeAllSocketsFromRoom : (roomName, cb) ->
    sockets = @socketsToRooms.keys()
    socketsset = @roomsToSockets.get roomName
    removedSockets = socketsset.toArray()
    for id in removedSockets
      roomsset = @socketsToRooms.get id
      roomsset.delete roomName
    socketsset = socketsset.difference sockets
    @roomsToSockets.set roomName, socketsset
    process.nextTick -> cb null, removedSockets

  # @private
  removeSocket : (id, cb) ->
    rooms = @roomsToSockets.toArray()
    roomsset = @socketsToRooms.get id
    removedRooms = roomsset.toArray()
    joinedSockets = []
    for roomName, idx in removedRooms
      socketsset = @roomsToSockets.get roomName
      socketsset.delete id
      njoined = socketsset.length
      joinedSockets[idx] = njoined
    roomsset = roomsset.difference removedRooms
    @socketsToRooms.delete id
    nconnected = @socketsToRooms.length
    process.nextTick -> cb null, removedRooms, joinedSockets, nconnected

  # @private
  lockSocketRoom : (id, roomName, cb) ->
    process.nextTick -> cb()

  # @private
  setRoomAccessRemoved : (roomName, cb) ->
    process.nextTick -> cb()

  # @private
  setSocketDisconnecting : (id, cb) ->
    process.nextTick -> cb()

  # @private
  bindUnlockSelf : (lock, op, id, cb) ->
    (args...) ->
      process.nextTick -> cb args...

  # @private
  bindUnlockOthers : (lock, op, username, cb) ->
    (args...) ->
      process.nextTick -> cb args...


# Implements global state API.
# @private
# @nodoc
class MemoryState

  # @private
  constructor : (@server, @options = {}) ->
    @errorBuilder = @server.errorBuilder
    @users = {}
    @rooms = {}
    @RoomState = RoomStateMemory
    @UserState = UserStateMemory
    @DirectMessagingState = DirectMessagingStateMemory

  # @private
  close : (cb) ->
    process.nextTick -> cb()

  # @private
  getRoom : (name, cb) ->
    r = @rooms[name]
    unless r
      error = @errorBuilder.makeError 'noRoom', name
    process.nextTick -> cb error, r

  # @private
  addRoom : (name, state, cb) ->
    room = new Room @server, name
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
    rooms = _.keys @rooms
    process.nextTick > cb null, rooms

  # @private
  removeSocket : (uid, id, cb) ->
    process.nextTick -> cb()

  # @private
  loginUserSocket : (uid, name, id, cb) ->
    user = @users[name]
    if user
      process.nextTick ->
        user.registerSocket id, cb
    else
      newUser = new User @server, name
      @users[name] = newUser
      process.nextTick ->
        newUser.registerSocket id, cb

  # @private
  getUser : (name, cb) ->
    user = @users[name]
    unless user
      error = @errorBuilder.makeError 'noUser', name
    else
      sockets = user.userState.socketsToRooms.keys()
    process.nextTick -> cb error, user, sockets

  # @private
  addUser : (name, state, cb) ->
    user = @users[name]
    if user
      error = @errorBuilder.makeError 'userExists', name
      return process.nextTick -> cb error
    user = new User @server, name
    @users[name] = user
    if state
      user.initState state, cb
    else
      process.nextTick -> cb()

  # @private
  removeUserData : (name, cb) ->
    #TODO


module.exports = MemoryState
