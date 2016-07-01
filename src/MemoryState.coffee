
ChatServiceError = require './ChatServiceError'
FastMap = require 'collections/fast-map'
FastSet = require 'collections/fast-set'
List = require 'collections/list'
Promise = require 'bluebird'
Room = require './Room'
User = require './User'
_ = require 'lodash'
promiseRetry = require 'promise-retry'
uid = require 'uid-safe'

{ extend } = require './utils'


# @private
# @nodoc
initState = (state, values) ->
  if state
    state.clear()
    if values
      state.addEach values


# Memory lock operations.
# @mixin
# @private
# @nodoc
lockOperations =

  # @private
  lock : (key, val, ttl) ->
    promiseRetry {minTimeout: 100, retries : 10, factor: 1.5, randomize : true}
    , (retry, n) =>
      if @locks.has key
        err = new ChatServiceError 'timeout'
        retry err
      else
        @locks.set key, val
        Promise.resolve()

  # @private
  unlock : (key, val) ->
    currentVal = @locks.get key
    if currentVal == val
      @locks.delete key
    Promise.resolve()


# Implements state API lists management.
# @private
# @nodoc
class ListsStateMemory

  # @private
  checkList : (listName) ->
    unless @hasList listName
      error = new ChatServiceError 'noList', listName
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
  whitelistOnlyGet : ->
    wl = @whitelistOnly || false
    Promise.resolve @whitelistOnly


# Implements room state API.
# @private
# @nodoc
class RoomStateMemory extends ListsStateMemory

  # @private
  constructor : (@server, @name) ->
    @historyMaxGetMessages = @server.historyMaxGetMessages
    @historyMaxSize = @server.defaultHistoryLimit
    @whitelist = new FastSet
    @blacklist = new FastSet
    @adminlist = new FastSet
    @userlist = new FastSet
    @messagesHistory = new List
    @messagesTimestamps = new List
    @messagesIds = new List
    @usersseen = new FastMap
    @lastMessageId = 0
    @whitelistOnly = false
    @owner = null

  # @private
  initState : (state = {}) ->
    { whitelist, blacklist, adminlist
    , whitelistOnly, owner, historyMaxSize } = state
    initState @whitelist, whitelist
    initState @blacklist, blacklist
    initState @adminlist, adminlist
    initState @messagesHistory
    initState @messagesTimestamps
    initState @messagesIds
    initState @usersseen
    @whitelistOnly = if whitelistOnly then true else false
    @owner = if owner then owner else null
    @historyMaxSizeSet historyMaxSize

  # @private
  removeState : ->
    Promise.resolve()

  # @private
  startRemoving : ->
    Promise.resolve()

  # @private
  hasList : (listName) ->
    return listName in [ 'adminlist', 'whitelist', 'blacklist', 'userlist' ]

  # @private
  ownerGet : ->
    Promise.resolve @owner

  # @private
  ownerSet : (owner) ->
    @owner = owner
    Promise.resolve()

  # @private
  historyMaxSizeSet : (historyMaxSize) ->
    if _.isNumber(historyMaxSize) and historyMaxSize >= 0
      @historyMaxSize = historyMaxSize
    Promise.resolve()

  # @private
  historyInfo : ->
    historySize = @messagesHistory.length
    info = { historySize, @historyMaxSize
      , @historyMaxGetMessages, @lastMessageId }
    Promise.resolve info

  # @private
  getCommonUsers : ->
    diff = (@userlist.difference @whitelist).difference @adminlist
    data = diff.toArray()
    Promise.resolve data

  # @private
  messageAdd : (msg) ->
    timestamp = _.now()
    @lastMessageId++
    makeResult = =>
      msg.timestamp = timestamp
      msg.id = @lastMessageId
      Promise.resolve msg
    if @historyMaxSize <= 0
      return makeResult()
    @messagesHistory.unshift msg
    @messagesTimestamps.unshift timestamp
    @messagesIds.unshift @lastMessageId
    if @messagesHistory.length > @historyMaxSize
      @messagesHistory.pop()
      @messagesTimestamps.pop()
      @messagesIds.pop()
    makeResult()

  # @private
  messagesGetRecent : ->
    msgs = @messagesHistory.slice 0, @historyMaxGetMessages
    tss = @messagesTimestamps.slice 0, @historyMaxGetMessages
    ids = @messagesIds.slice 0, @historyMaxGetMessages
    data = []
    for msg, idx in msgs
      obj = _.cloneDeep msg
      obj.timestamp = tss[idx]
      obj.id = ids[idx]
      data[idx] = obj
    Promise.resolve data

  # @private
  messagesGet : (id, maxMessages = @historyMaxGetMessages) ->
    if maxMessages <= 0 then return Promise.resolve []
    id = _.max [0, id]
    nmessages = @messagesIds.length
    lastid = @lastMessageId
    id = _.min [ id, lastid ]
    end = lastid - id
    len = _.min [ maxMessages, end ]
    start = _.max [ 0, end - len ]
    msgs = @messagesHistory.slice start, end
    tss = @messagesTimestamps.slice start, end
    ids = @messagesIds.slice start, end
    data = []
    for msg, idx in msgs
      obj = _.cloneDeep msg
      msg.timestamp = tss[idx]
      msg.id = ids[idx]
      data[idx] = obj
    Promise.resolve msgs

  # @private
  userSeenGet : (userName) ->
    joined = if @userlist.get userName then true else false
    timestamp = @usersseen.get(userName) || null
    Promise.resolve { joined, timestamp }

  # @private
  userSeenUpdate : (userName) ->
    timestamp = _.now()
    @usersseen.set userName, timestamp
    Promise.resolve()


# Implements direct messaging state API.
# @private
# @nodoc
class DirectMessagingStateMemory extends ListsStateMemory

  # @private
  constructor : (@server, @userName) ->
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
  removeState : ->
    Promise.resolve()

  # @private
  hasList : (listName) ->
    return listName in [ 'whitelist', 'blacklist' ]


# Implements user state API.
# @private
# @nodoc
class UserStateMemory

  extend @, lockOperations

  # @private
  constructor : (@server, @userName) ->
    @socketsToRooms = new FastMap
    @socketsToInstances = new FastMap
    @roomsToSockets = new FastMap
    @locks = new FastMap
    @echoChannel = @makeEchoChannelName @userName

  # @private
  makeEchoChannelName : (userName) ->
    "echo:#{userName}"

  # @private
  addSocket : (id, uid) ->
    roomsset = new FastSet
    @socketsToRooms.set id, roomsset
    @socketsToInstances.set id, uid
    nconnected = @socketsToRooms.length
    Promise.resolve nconnected

  # @private
  getAllSockets : ->
    sockets = @socketsToRooms.keysArray()
    Promise.resolve sockets

  # @private
  getSocketsToInstance : ->
    data = @socketsToInstances.toObject()
    Promise.resolve data

  # @private
  getRoomToSockets : (roomName) ->
    socketsset = @roomsToSockets.get roomName
    data = socketsset?.toObject() || {}
    Promise.resolve data

  # @private
  getSocketsToRooms : ->
    result = {}
    sockets = @socketsToRooms.keysArray()
    for id in sockets
      socketsset = @socketsToRooms.get id
      result[id] = socketsset?.toArray() || []
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
    roomsset?.delete roomName
    socketsset?.delete id
    njoined = socketsset?.length || 0
    Promise.resolve njoined

  # @private
  removeAllSocketsFromRoom : (roomName) ->
    sockets = @socketsToRooms.keysArray()
    socketsset = @roomsToSockets.get roomName
    removedSockets = socketsset?.toArray() || []
    for id in removedSockets
      roomsset = @socketsToRooms.get id
      roomsset.delete roomName
    if socketsset
      socketsset = socketsset.difference sockets
      @roomsToSockets.set roomName, socketsset
    Promise.resolve removedSockets

  # @private
  removeSocket : (id) ->
    rooms = @roomsToSockets.toArray()
    roomsset = @socketsToRooms.get id
    removedRooms = roomsset?.toArray() || []
    joinedSockets = []
    for roomName, idx in removedRooms
      socketsset = @roomsToSockets.get roomName
      socketsset.delete id
      njoined = socketsset.length
      joinedSockets[idx] = njoined
    @socketsToRooms.delete id
    @socketsToInstances.delete id
    nconnected = @socketsToRooms.length
    Promise.resolve [ removedRooms, joinedSockets, nconnected ]

  # @private
  lockToRoom : (roomName, ttl) ->
    uid(18)
    .then (val) =>
      @lock roomName, val, ttl
      .then =>
        Promise.resolve().disposer =>
          @unlock roomName, val


# Implements global state API.
# @private
# @nodoc
class MemoryState

  # @private
  constructor : (@server, @options = {}) ->
    @closed = false
    @users = new FastMap
    @rooms = new FastMap
    @sockets = new FastMap
    @RoomState = RoomStateMemory
    @UserState = UserStateMemory
    @DirectMessagingState = DirectMessagingStateMemory
    @instanceUID = @server.instanceUID
    @heartbeatStamp = null
    @lockTTL = @options.lockTTL || 5000

  # @private
  close : ->
    @closed = true
    Promise.resolve()

  # @private
  getRoom : (name, nocheck) ->
    r = @rooms.get name
    unless r
      error = new ChatServiceError 'noRoom', name
      return Promise.reject error
    Promise.resolve r

  # @private
  addRoom : (name, state) ->
    room = new Room @server, name
    unless @rooms.get name
      @rooms.set name, room
    else
      error = new ChatServiceError 'roomExists', name
      return Promise.reject error
    if state
      room.initState state
      .return room
    else
      Promise.resolve room

  # @private
  removeRoom : (name) ->
    @rooms.delete name
    Promise.resolve()

  # @private
  addSocket : (id, userName) ->
    @sockets.set id, userName
    Promise.resolve()

  # @private
  removeSocket : (id) ->
    @sockets.delete id
    Promise.resolve()

  # @private
  getInstanceSockets : (uid) ->
    Promise.resolve @sockets.toObject()

  # @private
  updateHeartbeat : ->
    @heartbeatStamp = _.now()
    Promise.resolve()

  # @private
  getInstanceHeartbeat : (uid = @instanceUID) ->
    if uid != @instanceUID then return null
    Promise.resolve @heartbeatStamp

  # @private
  getOrAddUser : (name, state) ->
    user = @users.get name
    if user then return Promise.resolve user
    @addUser name, state

  # @private
  getUser : (name) ->
    user = @users.get name
    unless user
      error = new ChatServiceError 'noUser', name
      Promise.reject error
    else
      Promise.resolve user

  # @private
  addUser : (name, state) ->
    user = @users.get name
    if user
      error = new ChatServiceError 'userExists', name
      return Promise.reject error
    user = new User @server, name
    @users.set name, user
    if state
      user.initState state
      .return user
    else
      Promise.resolve user

  # @private
  removeUser : (name) ->
    @users.delete name
    Promise.resolve()


module.exports = MemoryState
