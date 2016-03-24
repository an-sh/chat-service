
FastSet = require 'collections/fast-set'
List = require 'collections/list'
Map = require 'collections/fast-map'
Promise = require 'bluebird'
Room = require './Room.coffee'
User = require './User.coffee'
_ = require 'lodash'

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
  checkList : (listName) ->
    unless @hasList listName
      error = @errorBuilder.makeError 'noList', listName
      Promise.reject error
    else
      Promise.resolve()

  # @private
  addToList : (listName, elems) ->
    @checkList listName
    .then =>
      @[listName].addEach elems
      Promise.resolve()

  # @private
  removeFromList : (listName, elems) ->
    @checkList listName
    .then =>
      @[listName].deleteEach elems
      Promise.resolve()

  # @private
  getList : (listName) ->
    @checkList listName
    .then =>
      data = @[listName].toArray()
      Promise.resolve data

  # @private
  hasInList : (listName, elem) ->
    @checkList listName
    .then =>
      data = @[listName].has elem
      data = if data then true else false
      Promise.resolve data

  # @private
  whitelistOnlySet : (mode) ->
    @whitelistOnly = if mode then true else false
    Promise.resolve()

  # @private
  whitelistOnlyGet : () ->
    wl = @whitelistOnly || false
    Promise.resolve @whitelistOnly


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
  initState : (state = {}) ->
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
    Promise.resolve()

  # @private
  removeState : () ->
    Promise.resolve()

  # @private
  hasList : (listName) ->
    return listName in [ 'adminlist', 'whitelist', 'blacklist', 'userlist' ]

  # @private
  ownerGet : () ->
    Promise.resolve @owner

  # @private
  ownerSet : (owner) ->
    @owner = owner
    Promise.resolve()

  # @private
  messageAdd : (msg) ->
    timestamp = _.now()
    @lastMessageID++
    makeResult = =>
      msg.timestamp = timestamp
      msg.id = @lastMessageID
      Promise.resolve msg
    if @historyMaxMessages <= 0
      return makeResult()
    @messagesHistory.unshift msg
    @messagesTimestamps.unshift timestamp
    @messagesIDs.unshift @lastMessageID
    if @messagesHistory.length > @historyMaxMessages
      @messagesHistory.pop()
      @messagesTimestamps.pop()
      @messagesIDs.pop()
    makeResult()

  # @private
  messagesGetRecent : () ->
    msgs = @messagesHistory.slice 0, @historyMaxGetMessages
    tss = @messagesTimestamps.slice 0, @historyMaxGetMessages
    ids = @messagesIDs.slice 0, @historyMaxGetMessages
    data = []
    for msg, idx in msgs
      obj = _.cloneDeep msg
      obj.timestamp = tss[idx]
      obj.id = ids[idx]
      data[idx] = obj
    Promise.resolve data

  # @private
  messagesGetLastId : () ->
    id = @messagesIDs.peek() || 0
    Promise.resolve id

  # @private
  messagesGetAfterId : (id) ->
    nmessages = @messagesIDs.length
    maxlen = @historyMaxGetMessages
    lastid = @messagesIDs.peek()
    id = _.min [ id, lastid ]
    end = lastid - id
    len = _.min [ maxlen, lastid - id ]
    start = _.max [ 0, end - len ]
    msgs = @messagesHistory.slice start, end
    tss = @messagesTimestamps.slice start, end
    ids = @messagesIDs.slice start, end
    data = []
    for msg, idx in msgs
      obj = _.cloneDeep msg
      msg.timestamp = tss[idx]
      msg.id = ids[idx]
      data[idx] = obj
    Promise.resolve msgs

  # @private
  getCommonUsers : () ->
    diff = (@userlist.difference @whitelist).difference @adminlist
    data = diff.toArray()
    Promise.resolve data


# Implements direct messaging state API.
# @private
# @nodoc
class DirectMessagingStateMemory extends ListsStateMemory

  # @private
  constructor : (@server, @userName) ->
    @errorBuilder = @server.errorBuilder
    @whitelistOnly
    @whitelist = new FastSet
    @blacklist = new FastSet

  # @private
  initState : ({ whitelist, blacklist, whitelistOnly } = {}) ->
    initState @whitelist, whitelist
    initState @blacklist, blacklist
    @whitelistOnly = if whitelistOnly then true else false
    Promise.resolve()

  # @private
  hasList : (listName) ->
    return listName in [ 'whitelist', 'blacklist' ]


# Implements user state API.
# @private
# @nodoc
class UserStateMemory

  # @private
  constructor : (@server, @userName) ->
    @socketsToRooms = new Map
    @roomsToSockets = new Map
    @echoChannel = @makeEchoChannelName @userName

  # @private
  makeEchoChannelName : (userName) ->
    "echo:#{userName}"

  # @private
  addSocket : (id) ->
    roomsset = new FastSet
    @socketsToRooms.set id, roomsset
    nconnected = @socketsToRooms.length
    Promise.resolve nconnected

  # @private
  getAllSockets : () ->
    sockets = @socketsToRooms.keys()
    Promise.resolve sockets

  # @private
  getSocketsToRooms : () ->
    result = {}
    sockets = @socketsToRooms.keys()
    for id in sockets
      socketsset = @socketsToRooms.get id
      result[id] = socketsset.toArray()
    Promise.resolve result

  # @private
  addSocketToRoom : (id, roomName) ->
    roomsset = @socketsToRooms.get id
    socketsset = @roomsToSockets.get roomName
    unless socketsset
      socketsset = new FastSet
      @roomsToSockets.set roomName, socketsset
    roomsset.add roomName
    socketsset.add id
    njoined = socketsset.length
    Promise.resolve njoined

  # @private
  removeSocketFromRoom : (id, roomName) ->
    roomsset = @socketsToRooms.get id
    socketsset = @roomsToSockets.get roomName
    roomsset.delete roomName
    socketsset?.delete id
    njoined = socketsset?.length || 0
    Promise.resolve njoined

  # @private
  removeAllSocketsFromRoom : (roomName) ->
    sockets = @socketsToRooms.keys()
    socketsset = @roomsToSockets.get roomName
    removedSockets = socketsset.toArray()
    for id in removedSockets
      roomsset = @socketsToRooms.get id
      roomsset.delete roomName
    socketsset = socketsset.difference sockets
    @roomsToSockets.set roomName, socketsset
    Promise.resolve removedSockets

  # @private
  removeSocket : (id) ->
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
    Promise.resolve [ removedRooms, joinedSockets, nconnected ]

  # @private
  lockToRoom : (id, roomName) ->
    Promise.resolve()

  # @private
  setSocketDisconnecting : (id) ->
    Promise.resolve()

  # @private
  bindUnlock : (lock, op, id, cb) ->
    # TODO
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
  close : () ->
    Promise.resolve()

  # @private
  getRoom : (name) ->
    r = @rooms[name]
    unless r
      error = @errorBuilder.makeError 'noRoom', name
      return Promise.reject error
    Promise.resolve r

  # @private
  addRoom : (name, state) ->
    room = new Room @server, name
    unless @rooms[name]
      @rooms[name] = room
    else
      error = @errorBuilder.makeError 'roomExists', name
      return Promise.reject error
    if state
      room.initState state
    else
      Promise.resolve()

  # @private
  removeRoom : (name) ->
    if @rooms[name]
      delete @rooms[name]
      Promise.resolve()
    else
      error = @errorBuilder.makeError 'noRoom', name
      Promise.reject error

  # @private
  removeSocket : (uid, id) ->
    Promise.resolve()

  # @private
  loginUserSocket : (uid, name, id) ->
    user = @users[name]
    unless user
      user = new User @server, name
      @users[name] = user
    new Promise (resolve, reject) ->
      user.registerSocket id, (error, user, nconnected) ->
        if error
          reject error
        else
          resolve [user, nconnected]

  # @private
  getUser : (name) ->
    user = @users[name]
    unless user
      error = @errorBuilder.makeError 'noUser', name
      Promise.reject error
    else
      Promise.resolve user

  # @private
  addUser : (name, state) ->
    user = @users[name]
    if user
      error = @errorBuilder.makeError 'userExists', name
      return Promise.reject error
    user = new User @server, name
    @users[name] = user
    if state
      user.initState state
    else
      Promise.resolve()


module.exports = MemoryState
