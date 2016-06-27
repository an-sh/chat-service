
ChatServiceError = require './ChatServiceError'
Promise = require 'bluebird'
Redis = require 'ioredis'
Room = require './Room'
User = require './User'
_ = require 'lodash'
promiseRetry = require 'promise-retry'
uid = require 'uid-safe'

{ extend } = require './utils'


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
      @redis.del @makeKeyName('exists'), @makeKeyName('isInit')

  # @private
  startRemoving : ->
    @redis.del @makeKeyName('isInit')


# Redis lock operations.
# @mixin
# @private
# @nodoc
lockOperations =

  # @private
  lock : (key, val, ttl) ->
    promiseRetry {minTimeout: 100, retries : 10, factor: 1.5, randomize : true}
    , (retry, n) =>
      @redis.set key, val, 'NX', 'PX', ttl
      .then (res) ->
        unless res
          err = new ChatServiceError 'timeout'
          retry err
      .catch retry

  # @private
  unlock : (key, val) ->
    @redis.unlock key, val


# Redis scripts.
# @private
# @nodoc
luaCommands =

  unlock:
    numberOfKeys: 1,
    lua: """
if redis.call("get",KEYS[1]) == ARGV[1] then
  return redis.call("del",KEYS[1])
else
  return 0
end
"""

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

  messagesGet:
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

  getSocketsToRooms:
    numberOfKeys: 1,
    lua: """
local result = {}
local sockets = KEYS[1]
local prefix = ARGV[1]
local ids = redis.call('HKEYS', sockets)

if table.getn(ids) == 0 then
  local jsonResult = cjson.encode(cjson.null)
  return {jsonResult}
end

for i, id in pairs(ids) do
  local joined = redis.call('SMEMBERS', prefix .. id)
  result[id] = joined
end

local jsonResult = cjson.encode(result)
return {jsonResult}
"""

  removeAllSocketsFromRoom:
    numberOfKeys: 1,
    lua: """
local room = KEYS[1]
local prefix = ARGV[1]
local roomName = ARGV[2]
local ids = redis.call('SMEMBERS', room)

if table.getn(ids) == 0 then
  local jsonResult = cjson.encode(cjson.null)
  return {jsonResult}
end

redis.call('DEL', room)

for i, id in pairs(ids) do
  redis.call('SREM', prefix .. id, roomName)
end

local jsonResult = cjson.encode(ids)
return {jsonResult}
"""

  removeSocket:
    numberOfKeys: 2,
    lua: """
local id = KEYS[1]
local sockets = KEYS[2]
local prefix = ARGV[1]
local socketid = ARGV[2]

local rooms = redis.call('SMEMBERS', id)
redis.call('DEL', id)

redis.call('HDEL', sockets, socketid)
local nconnected = redis.call('HLEN', sockets)

local removedRooms = {}
local joinedSockets = {}

for i, room in pairs(rooms) do
  local ismember = redis.call('SISMEMBER', prefix .. room, socketid)
  if ismember == 1 then
    redis.call('SREM', prefix .. room, socketid)
    local njoined = redis.call('SCARD', prefix .. room)
    table.insert(removedRooms, room)
    table.insert(joinedSockets, njoined)
  end
end

if table.getn(removedRooms) == 0 or table.getn(rooms) == 0 then
  local jsonResult = cjson.encode({cjson.null, cjson.null, nconnected})
  return {jsonResult}
end

local jsonResult = cjson.encode({removedRooms, joinedSockets, nconnected})
return {jsonResult}
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
  whitelistOnlyGet : ->
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
  constructor : (@server, @roomName) ->
    @name = @roomName
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
      @redis.del(@makeKeyName('usersseen'))
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
  ownerGet : ->
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
  historyInfo : ->
    @redis.multi()
    .get @makeKeyName('historyMaxSize')
    .llen @makeKeyName('messagesHistory')
    .get @makeKeyName('lastMessageId')
    .exec()
    .spread ([_0, historyMaxSize], [_1, historySize], [_2, lastMessageId]) =>
      historySize = parseInt historySize
      historyMaxSize = parseFloat historyMaxSize
      lastMessageId = parseInt lastMessageId
      info = { historySize, historyMaxSize
        , @historyMaxGetMessages, lastMessageId }
      Promise.resolve info

  # @private
  getCommonUsers : ->
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
      obj = JSON.parse msg, (key, val) ->
        if val?.type == 'Buffer' then Buffer.from(val.data) else val
      obj.timestamp = parseInt tss[idx]
      obj.id = parseInt ids[idx]
      data[idx] = obj
    Promise.resolve data

  # @private
  messagesGetRecent : ->
    if @historyMaxGetMessages <= 0 then return Promise.resolve []
    @redis.multi()
    .lrange @makeKeyName('messagesHistory'), 0, @historyMaxGetMessages - 1
    .lrange @makeKeyName('messagesTimestamps'), 0, @historyMaxGetMessages - 1
    .lrange @makeKeyName('messagesIds'), 0, @historyMaxGetMessages - 1
    .exec()
    .spread ([_0, msgs], [_1, tss], [_2, ids]) =>
      @convertMessages msgs, tss, ids

  # @private
  messagesGet : (id, maxMessages = @historyMaxGetMessages) ->
    if maxMessages <= 0 then return Promise.resolve []
    id = _.max [0, id]
    @redis.messagesGet @makeKeyName('lastMessageId')
    , @makeKeyName('historyMaxSize'), @makeKeyName('messagesIds')
    , @makeKeyName('messagesTimestamps'),  @makeKeyName('messagesHistory')
    , id, maxMessages
    .spread (msgs, tss, ids) =>
      @convertMessages msgs, tss, ids

  # @private
  userSeenGet : (userName) ->
    @redis.multi()
    .hget @makeKeyName('usersseen'), userName
    .sismember @makeKeyName('userlist'), userName
    .exec()
    .spread ([_1, ts], [_2, isjoined]) ->
      joined = if isjoined then true else false
      timestamp = if ts then parseInt ts else null
      { joined, timestamp }

  # @private
  userSeenUpdate : (userName) ->
    timestamp = _.now()
    @redis.hset @makeKeyName('usersseen'), userName, timestamp


# Implements direct messaging state API.
# @private
# @nodoc
class DirectMessagingStateRedis extends ListsStateRedis

  extend @, stateOperations

  # @private
  constructor : (@server, @userName) ->
    @name = @userName
    @prefix = 'users'
    @exitsErrorName = 'userExists'
    @redis = @server.redis

  # @private
  hasList : (listName) ->
    return listName in [ 'whitelist', 'blacklist' ]

  # @private
  stateReset : (state = {}) ->
    { whitelist, blacklist, whitelistOnly } = state
    whitelistOnly = if whitelistOnly then true else ''
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

  extend @, lockOperations

  # @private
  constructor : (@server, @userName) ->
    @name = @userName
    @prefix = 'users'
    @redis = @server.redis
    @echoChannel = @makeEchoChannelName @userName

  # @private
  makeKeyName : (keyName) ->
    "#{namespace}:#{@prefix}:{#{@name}}:#{keyName}"

  # @private
  makeSocketToRooms : (id = '') ->
    @makeKeyName "socketsToRooms:#{id}"

  # @private
  makeRoomToSockets : (room = '') ->
    @makeKeyName "roomsToSockets:#{room}"

  # @private
  makeRoomLock : (room = '') ->
    @makeKeyName "roomLock:#{room}"

  # @private
  makeEchoChannelName : (userName) ->
    "echo:#{userName}"

  # @private
  addSocket : (id, uid) ->
    @redis.multi()
    .hset @makeKeyName('sockets'), id, uid
    .hlen @makeKeyName('sockets')
    .exec()
    .spread (_0, [_1, nconnected]) ->
      Promise.resolve nconnected

  # @private
  getAllSockets : ->
    @redis.hkeys @makeKeyName('sockets')

  # @private
  getSocketsToRooms : ->
    @redis.getSocketsToRooms @makeKeyName('sockets'), @makeSocketToRooms()
    .spread (result) ->
      data = JSON.parse(result) || {}
      for k, v of data
        if _.isEmpty v
          data[k] = []
      Promise.resolve data

  # @private
  addSocketToRoom : (id, roomName) ->
    @redis.multi()
    .sadd @makeSocketToRooms(id), roomName
    .sadd @makeRoomToSockets(roomName), id
    .scard @makeRoomToSockets(roomName)
    .exec()
    .spread (_0, _1, [_2, njoined]) ->
      Promise.resolve njoined

  # @private
  removeSocketFromRoom : (id, roomName) ->
    @redis.multi()
    .srem @makeSocketToRooms(id), roomName
    .srem @makeRoomToSockets(roomName), id
    .scard @makeRoomToSockets(roomName)
    .exec()
    .spread (_0, _1, [_2, njoined]) ->
      Promise.resolve njoined

  # @private
  removeAllSocketsFromRoom : (roomName) ->
    @redis.removeAllSocketsFromRoom @makeRoomToSockets(roomName)
    , @makeSocketToRooms(), roomName
    .spread (result) ->
      Promise.resolve JSON.parse result

  # @private
  removeSocket : (id) ->
    @redis.removeSocket @makeSocketToRooms(id), @makeKeyName('sockets')
    , @makeRoomToSockets(), id
    .spread (result) ->
      Promise.resolve JSON.parse result

  # @private
  lockToRoom : (roomName, ttl) ->
    uid(18)
    .then (val) =>
      @lock @makeRoomLock(roomName), val, ttl
      .then =>
        Promise.resolve().disposer =>
          @unlock @makeRoomLock(roomName), val


# Implements global state API.
# @private
# @nodoc
class RedisState

  # @private
  constructor : (@server, @options = {}) ->
    @closed = false
    if @options.useCluster
      @redis = new Redis.Cluster @options.redisOptions...
    else
      redisOptions = _.castArray @options.redisOptions
      @redis = new Redis redisOptions...
    @RoomState = RoomStateRedis
    @UserState = UserStateRedis
    @DirectMessagingState = DirectMessagingStateRedis
    @lockTTL = @options.lockTTL || 10000
    @instanceUID = @server.instanceUID
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
  hasUser : (name) ->
    @redis.get @makeKeyName('users', name, 'isInit')

  # @private
  close : ->
    @closed = true
    @redis.quit()
    .return()

  # @private
  getRoom : (name, nocheck) ->
    room = new Room @server, name
    if nocheck then return Promise.resolve room
    @hasRoom name
    .then (exists) ->
      unless exists
        error = new ChatServiceError 'noRoom', name
        return Promise.reject error
      Promise.resolve room

  # @private
  addRoom : (name, state) ->
    room = new Room @server, name
    room.initState state
    .return room

  # @private
  removeRoom : (name) ->
    Promise.resolve()

  # @private
  addSocket : (id, userName) ->
    @redis.hset @makeKeyName('instances', @instanceUID, 'sockets'), id, userName

  # @private
  removeSocket : (id) ->
    @redis.hdel @makeKeyName('instances', @instanceUID, 'sockets'), id

  # @private
  getInstanceSockets : (uid = @instanceUID) ->
    @redis.hgetall @makeKeyName('instances', uid, 'sockets')

  # @private
  getOrAddUser : (name, state) ->
    user = new User @server, name
    @hasUser name
    .then (exists) ->
      unless exists then user.initState state
    .catch ChatServiceError, (e) ->
      user
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

  # @private
  removeUser : (name) ->
    Promise.resolve()


module.exports = RedisState
