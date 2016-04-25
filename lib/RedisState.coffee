
ChatServiceError = require './ChatServiceError.coffee'
Promise = require 'bluebird'
Redis = require 'ioredis'
Room = require './Room.coffee'
User = require './User.coffee'
_ = require 'lodash'

{ extend } = require './utils.coffee'


# @private
# @nodoc
namespace = 'chatservice'

# @private
# @nodoc
initSet = (redis, set, values) ->
  redis.del set
  .then ->
    unless values
      return Promise.resolve()
    redis.sadd set, values


# State init/remove operations.
# @mixin
# @private
# @nodoc
stateOperations =

  # @private
  initState : (state) ->
    @redis.setnx @makeKeyName('exists'), true
    .then (isnew) =>
      unless isnew
        error = new ChatServiceError @exitsErrorName, @name
        return Promise.reject error
    .then =>
      @stateReset state
    .then =>
      @redis.setnx @makeKeyName('isInit'), true

  # @private
  removeState : ->
    @stateReset null
    .then =>
      @redis.del @makeKeyName('exists')

  # @private
  startRemoving : ->
    @redis.del @makeKeyName('isInit')


# Redis scripts.
# @private
# @nodoc
luaCommands =

  messageAdd:
    numberOfKeys: 5,
    lua: """
local msg = ARGV[1]
local ts = ARGV[2]

local lastMessageId = KEYS[1]
local historyMaxSize = KEYS[2]
local messagesIds = KEYS[3]
local messagesTimestamps = KEYS[4]
local messagesHistory = KEYS[5]

local id = tonumber(redis.call('INCR', lastMessageId))
local maxsz = tonumber(redis.call('GET', historyMaxSize))

redis.call('LPUSH', messagesIds, id)
redis.call('LPUSH', messagesTimestamps, ts)
redis.call('LPUSH', messagesHistory, msg)

local sz = tonumber(redis.call('LLEN', messagesHistory))

if sz > maxsz then
   redis.call('RPOP', messagesIds)
   redis.call('RPOP', messagesTimestamps)
   redis.call('RPOP', messagesHistory)
end

return {id}
"""

  messagesGetAfterId:
    numberOfKeys: 5,
    lua: """
local id = ARGV[1]
local maxlen = ARGV[2]

local lastMessageId = KEYS[1]
local historyMaxSize = KEYS[2]
local messagesIds = KEYS[3]
local messagesTimestamps = KEYS[4]
local messagesHistory = KEYS[5]

local lastid = tonumber(redis.call('GET', lastMessageId))
local maxsz = tonumber(redis.call('GET', historyMaxSize))
local id = math.min(id, lastid)
local endp = lastid - id
local len = math.min(maxlen, endp)
local start = math.max(0, endp - len)

if start >= endp then
   return {}
end

endp = endp - 1
local msgs = redis.call('LRANGE', messagesHistory, start, endp)
local tss = redis.call('LRANGE', messagesTimestamps, start, endp)
local ids = redis.call('LRANGE', messagesIds, start, endp)

return {msgs, tss, ids}
"""



# Implements state API lists management.
# @private
# @nodoc
class ListsStateRedis

  # @private
  makeKeyName : (keyName) ->
    "#{namespace}:#{@prefix}:{#{@name}}:#{keyName}"

  # @private
  checkList : (listName) ->
    unless @hasList listName
      error = new ChatServiceError 'noList', listName
      return Promise.reject error
    Promise.resolve()

  # @private
  addToList : (listName, elems) ->
    @checkList listName
    .then =>
      @redis.sadd @makeKeyName(listName), elems

  # @private
  removeFromList : (listName, elems) ->
    @checkList listName
    .then =>
      @redis.srem @makeKeyName(listName), elems

  # @private
  getList : (listName) ->
    @checkList listName
    .then =>
      @redis.smembers @makeKeyName(listName)

  # @private
  hasInList : (listName, elem) ->
    @checkList listName
    .then =>
      @redis.sismember @makeKeyName(listName), elem
    .then (data) ->
      result = if data then true else false
      Promise.resolve result

  # @private
  whitelistOnlySet : (mode) ->
    whitelistOnly = if mode then true else ''
    @redis.set @makeKeyName('whitelistMode'), whitelistOnly

  # @private
  whitelistOnlyGet : () ->
    @redis.get @makeKeyName('whitelistMode')
    .then (data) ->
      result = if data then true else false
      Promise.resolve result


# Implements room state API.
# @private
# @nodoc
class RoomStateRedis extends ListsStateRedis

  extend @, stateOperations

  # @private
  constructor : (@server, @name) ->
    @historyMaxGetMessages = @server.historyMaxGetMessages
    @redis = @server.redis
    @exitsErrorName = 'roomExists'
    @prefix = 'rooms'

  # @private
  stateReset : (state = {}) ->
    { whitelist, blacklist, adminlist
    , whitelistOnly, owner, historyMaxSize } = state
    whitelistOnly = if whitelistOnly then true else ''
    owner = '' unless owner
    Promise.all [
      initSet(@redis, @makeKeyName('whitelist'), whitelist)
      initSet(@redis, @makeKeyName('blacklist'), blacklist)
      initSet(@redis, @makeKeyName('adminlist'), adminlist)
      initSet(@redis, @makeKeyName('userlist'), null)
      @redis.del(@makeKeyName 'messagesHistory')
      @redis.del(@makeKeyName 'messagesTimestamps')
      @redis.del(@makeKeyName 'messagesIds')
      @redis.set(@makeKeyName('lastMessageId'), 0)
      @redis.set(@makeKeyName('whitelistMode'), whitelistOnly)
      @redis.set(@makeKeyName('owner'), owner)
      @historyMaxSizeSet(historyMaxSize)
    ]
    .return()

  # @private
  hasList : (listName) ->
    return listName in [ 'adminlist', 'whitelist', 'blacklist', 'userlist' ]

  # @private
  ownerGet : () ->
    @redis.get @makeKeyName('owner')

  # @private
  ownerSet : (owner) ->
    @redis.set @makeKeyName('owner'), owner

  # @private
  historyMaxSizeSet : (historyMaxSize) ->
    if _.isNumber(historyMaxSize) and historyMaxSize >= 0
      @redis.set(@makeKeyName('historyMaxSize'), historyMaxSize)
    else
      @redis.set(@makeKeyName('historyMaxSize'), @server.defaultHistoryLimit)

  # @private
  syncInfo : () ->
    @redis.multi()
    .get @makeKeyName('historyMaxSize')
    .llen @makeKeyName('messagesHistory')
    .get @makeKeyName('lastMessageId')
    .exec()
    .spread ([_0, historyMaxSize], [_1, historySize], [_2, lastMessageId]) =>
      historySize = parseInt historySize
      historyMaxSize = parseInt historyMaxSize
      lastMessageId = parseInt lastMessageId
      info = { historySize, historyMaxSize
        , @historyMaxGetMessages, lastMessageId }
      Promise.resolve info

  # @private
  getCommonUsers : () ->
    @redis.sdiff @makeKeyName('userlist'), @makeKeyName('whitelist')
    , @makeKeyName('adminlist')

  # @private
  messageAdd : (msg) ->
    timestamp = _.now()
    smsg = JSON.stringify msg
    @redis.messageAdd @makeKeyName('lastMessageId')
    , @makeKeyName('historyMaxSize'), @makeKeyName('messagesIds')
    , @makeKeyName('messagesTimestamps'),  @makeKeyName('messagesHistory')
    , smsg , timestamp
    .spread (id) ->
      msg.id = id
      msg.timestamp = timestamp
      Promise.resolve msg

  # @private
  convertMessages : (msgs, tss, ids) ->
    data = []
    if not msgs
      return Promise.resolve data
    for msg, idx in msgs
      obj = JSON.parse msg
      obj.timestamp = parseInt tss[idx]
      obj.id = parseInt ids[idx]
      data[idx] = obj
    Promise.resolve data

  # @private
  messagesGetRecent : () ->
    if @historyMaxGetMessages <= 0
      return Promise.resolve []
    @redis.multi()
    .lrange @makeKeyName('messagesHistory'), 0, @historyMaxGetMessages - 1
    .lrange @makeKeyName('messagesTimestamps'), 0, @historyMaxGetMessages - 1
    .lrange @makeKeyName('messagesIds'), 0, @historyMaxGetMessages - 1
    .exec()
    .spread ([_0, msgs], [_1, tss], [_2, ids]) =>
      @convertMessages msgs, tss, ids

  # @private
  messagesGetAfterId : (id, maxMessages = @historyMaxGetMessages) ->
    if maxMessages <= 0
      return Promise.resolve []
    @redis.messagesGetAfterId @makeKeyName('lastMessageId')
    , @makeKeyName('historyMaxSize'), @makeKeyName('messagesIds')
    , @makeKeyName('messagesTimestamps'),  @makeKeyName('messagesHistory')
    , id, maxMessages
    .spread (msgs, tss, ids) =>
      @convertMessages msgs, tss, ids


# Implements direct messaging state API.
# @private
# @nodoc
class DirectMessagingStateRedis extends ListsStateRedis

  extend @, stateOperations

  # @private
  constructor : (@server, @userName) ->
    @name = @userName
    @prefix = 'user'
    @exitsErrorName = 'userExists'
    @redis = @server.redis

  # @private
  hasList : (listName) ->
    return listName in [ 'whitelist', 'blacklist' ]

  # @private
  resetState : (state = {}) ->
    { whitelist, blacklist, whitelistOnly } = state
    whitelistOnly = if whitelistOnly then 1 else 0
    Promise.all [
      initSet(@redis, @makeKeyName('whitelist'), whitelist)
      initSet(@redis, @makeKeyName('blacklist'), blacklist)
      @redis.set(@makeKeyName('whitelistMode'), whitelistOnly)
    ]
    .return()


# Implements user state API.
# @private
# @nodoc
class UserStateRedis

  # @private
  constructor : (@server, @userName) ->
    @name = @userName
    @prefix = 'user'
    @redis = @server.redis
    @echoChannel = @makeEchoChannelName @userName

  # @private
  makeKeyName : (keyName) ->
    "#{namespace}:#{@prefix}:{#{@name}}:#{keyName}"

  # @private
  makeSocketToRoomsName : (id) ->
    "#{namespace}:#{@prefix}:{#{@name}}:socketsToRooms:#{id}"

  # @private
  makeRoomToSocketsName : (id) ->
    "#{namespace}:#{@prefix}:{#{@name}}:roomsToSockets:#{id}"

  # @private
  makeEchoChannelName : (userName) ->
    "echo:#{userName}"

  # @private
  addSocket : (id) ->
    @redis.multi()
    .sadd @makeKeyName('sockets'), id
    .scard @makeKeyName('sockets')
    .exec()
    .spread (_0, [_1, nconnected]) ->
      Promise.resolve nconnected

  # @private
  getAllSockets : () ->
    @redis.smembers @makeKeyName('sockets')

  # @private
  getSocketsToRooms: () ->
    #TODO

  # @private
  addSocketToRoom : (id, roomName) ->
    #TODO

  # @private
  removeSocketFromRoom : (id, roomName) ->
    #TODO

  # @private
  removeAllSocketsFromRoom : (roomName) ->
    #TODO

  # @private
  removeSocket : (id) ->
    #TODO

  # @private
  lockToRoom : (roomName, id = null) ->
    Promise.resolve().disposer ->
      #TODO
      Promise.resolve()

  # @private
  setSocketDisconnecting : (id) ->
    #TODO


# Implements global state API.
# @private
# @nodoc
class RedisState

  # @private
  constructor : (@server, @options = {}) ->
    redisOptions = _.castArray @options.redisOptions
    if @options.useCluster
      @redis = new Redis.Cluster redisOptions...
    else
      @redis = new Redis redisOptions...
    @RoomState = RoomStateRedis
    @UserState = UserStateRedis
    @DirectMessagingState = DirectMessagingStateRedis
    @lockTTL = @options.lockTTL || 5000
    @clockDrift = @options.clockDrift || 1000
    @server.redis = @redis
    for cmd, def of stateOperations
      @redis.defineCommand cmd,
        numberOfKeys: def.numberOfKeys
        lua: def.lua

  # @private
  makeKeyName : (prefix, name, keyName) ->
    "#{namespace}:#{prefix}:{#{name}}:#{keyName}"

  # @private
  hasRoom : (name) ->
    @redis.get @makeKeyName('rooms', name, 'exists')

  # @private
  hasUser : (name) ->
    @redis.get @makeKeyName('user', name, 'exists')

  # @private
  close : () ->
    @redis.disconnect()

  # @private
  getRoom : (name) ->
    @hasRoom name
    .then (exists) =>
      unless exists
        error = new ChatServiceError 'noRoom', name
        return Promise.reject error
      room = new Room @server, name
      Promise.resolve room

  # @private
  addRoom : (name, state) ->
    room = new Room @server, name
    room.initState state
    .return room

  # @private
  removeRoom : (name) ->
    @hasRoom name
    .then (exists) =>
      unless exists
        error = new ChatServiceError 'noRoom', name
        return Promise.reject error
      room = new Room @server, name
      room.removeState()

  # @private
  addSocket : (uid, id) ->
    #TODO

  # @private
  removeSocket : (uid, id) ->
    #TODO

  # @private
  getOrAddUser : (name, state) ->
    user = new User @server, name
    @hasUser name
    .then (exists) ->
      unless exists then user.initState()
    .return user

  # @private
  getUser : (name) ->
    user = new User @server, name
    @hasUser name
    .then (exists) ->
      unless exists
        error = new ChatServiceError 'noUser', name
        return Promise.reject error
      Promise.resolve user

  # @private
  addUser : (name, state) ->
    user = new User @server, name
    user.initState state
    .return user


MemoryState = require './MemoryState.coffee'

class TestState extends MemoryState

  constructor : (@server, @options = {}) ->
    super
    redisOptions = _.castArray @options.redisOptions
    if @options.useCluster
      @redis = new Redis.Cluster redisOptions...
    else
      @redis = new Redis redisOptions...
    @RoomState = RoomStateRedis
    @lockTTL = @options.lockTTL || 5000
    @clockDrift = @options.clockDrift || 1000
    @server.redis = @redis
    for cmd, def of luaCommands
      @redis.defineCommand cmd,
        numberOfKeys: def.numberOfKeys
        lua: def.lua

  # @private
  makeKeyName : (prefix, name, keyName) ->
    "#{namespace}:#{prefix}:{#{name}}:#{keyName}"

  # @private
  hasRoom : (name) ->
    @redis.get @makeKeyName('rooms', name, 'isInit')

  # @private
  close : () ->
    @redis.disconnect()

  # @private
  getRoom : (name) ->
    @hasRoom name
    .then (exists) =>
      unless exists
        error = new ChatServiceError 'noRoom', name
        return Promise.reject error
      room = new Room @server, name
      Promise.resolve room

  # @private
  addRoom : (name, state) ->
    room = new Room @server, name
    room.initState state
    .return room

  # @private
  removeRoom : (name) ->
    Promise.resolve()


module.exports = TestState
