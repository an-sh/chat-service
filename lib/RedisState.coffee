
ChatServiceError = require './ChatServiceError.coffee'
Redis = require 'ioredis'
Room = require './Room.coffee'
User = require './User.coffee'
_ = require 'lodash'
async = require 'async'

{ asyncLimit
  extend
  withEH
} = require './utils.coffee'


# @private
# @nodoc
namespace = 'chatservice'

# @private
# @nodoc
initSet = (redis, set, values, cb) ->
  redis.del set, withEH cb, ->
    unless values
      return process.nextTick -> cb()
    redis.sadd set, values, cb


# State init/remove operations.
# @mixin
# @private
# @nodoc
stateOperations =

  # @private
  initState : (state, cb) ->
    @redis.setnx @makeKeyName('exists'), 1, @withTE cb, (exists) =>
      if exists then return cb new ChatServiceError @exitsErrorName, name
      @stateReset state, @withTE cb, =>
        @redis.set @makeKeyName('exists'), 1, @withTE cb

  # @private
  removeState : (cb) ->
    @initState null, @withTE cb, =>
      @redis.set @makeKeyName('exists'), 0, @withTE cb


# Implements state API lists management.
# @private
# @nodoc
class ListsStateRedis

  # @private
  makeKeyName : (keyName) ->
    "#{namespace}:#{@prefix}:{#{@name}}:#{keyName}"

  # @private
  checkList : (listName, cb) ->
    unless @hasList listName
      error = new ChatServiceError 'noList', listName
    process.nextTick -> cb error

  # @private
  addToList : (listName, elems, cb) ->
    @checkList listName, withEH cb, =>
      @redis.sadd @makeKeyName(listName), elems, @withTE cb

  # @private
  removeFromList : (listName, elems, cb) ->
    @checkList listName, withEH cb, =>
      @redis.srem @makeKeyName(listName), elems, @withTE cb

  # @private
  getList : (listName, cb) ->
    @checkList listName, withEH cb, =>
      @redis.smembers @makeKeyName(listName), @withTE cb, (data) ->
        cb null, data

  # @private
  hasInList : (listName, elem, cb) ->
    @checkList listName, withEH cb, =>
      @redis.sismember @makeKeyName(listName), elem, @withTE cb, (data) ->
        data = if data then true else false
        cb null, data

  # @private
  whitelistOnlySet : (mode, cb) ->
    whitelistOnly = if mode then 1 else 0
    @redis.set @makeKeyName('whitelistMode'), whitelistOnly
    , @withTE cb

  # @private
  whitelistOnlyGet : (cb) ->
    @redis.get @makeKeyName('whitelistMode'), @name, @withTE cb
    , (data) ->
      result = if data then true else false
      cb null, result


# Implements room state API.
# @private
# @nodoc
class RoomStateRedis extends ListsStateRedis

  extend @, stateOperations

  # @private
  constructor : (@server, @name) ->
    @historyMaxGetMessages = @server.historyMaxGetMessages
    @historyMaxSize = @server.historyMaxSize
    @redis = @server.redis
    @exitsErrorName = 'roomExists'
    @prefix = 'rooms'

  # @private
  hasList : (listName) ->
    return listName in [ 'adminlist', 'whitelist', 'blacklist', 'userlist' ]

  # @private
  stateReset : (state = {}, cb) ->
    { whitelist, blacklist, adminlist
    , lastMessages, whitelistOnly, owner } = state
    async.parallel [
      (fn) =>
        initSet @redis, @makeKeyName('whitelist'), whitelist, fn
      (fn) =>
        initSet @redis, @makeKeyName('blacklist'), blacklist, fn
      (fn) =>
        initSet @redis, @makeKeyName('adminlist'), adminlist, fn
      (fn) =>
        initSet @redis, @makeKeyName('userlist'), null, fn
      (fn) =>
        redis.del @makeKeyName('messagesHistory'), fn
      (fn) =>
        redis.del @makeKeyName('messagesTimestamps'), fn
      (fn) =>
        redis.del @makeKeyName('messagesIds'), fn
      (fn) =>
        redis.set @makeKeyName('lastMessageId'), 0, fn
      (fn) =>
        whitelistOnly = if whitelistOnly then 1 else 0
        @redis.set @makeKeyName('whitelistMode'), whitelistOnly, fn
      (fn) =>
        owner = '' unless owner
        @redis.set @makeKeyName('owner'), owner, fn
    ] , cb

  # @private
  ownerGet : (cb) ->
    @redis.get @makeKeyName('owner'), @withTE cb

  # @private
  ownerSet : (owner, cb) ->
    @redis.set @makeKeyName('owner'), owner, @withTE cb

  # @private
  messageAdd : (msg, cb) ->
    #TODO

  # @private
  messagesGetRecent : (cb) ->
    #TODO

  messagesGetLastId : (cb) ->
    @redis.get @makeKeyName('lastMessageId'), @withTE cb

  messagesGetAfterId : (id, cb) ->
    #TODO

  # @private
  getCommonUsers : (cb) ->
    @redis.sdiff @makeKeyName('userlist'), @makeKeyName('whitelist')
    , @makeKeyName('adminlist'), @withTE cb


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
  resetState : (state = {}, cb) ->
    { whitelist, blacklist, whitelistOnly } = state
    async.parallel [
      (fn) =>
        initSet @redis, @makeKeyName('whitelist'), whitelist, fn
      (fn) =>
        initSet @redis, @makeKeyName('blacklist'), blacklist, fn
      (fn) =>
        whitelistOnly = if whitelistOnly then 1 else 0
        @redis.set @makeKeyName('whitelistMode'), whitelistOnly, fn
    ] , cb


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
  addSocket : (id, cb) ->
    #TODO

  # @private
  getAllSockets : (cb) ->
    #TODO

  # @private
  getSocketsToRooms: (cb) ->
    #TODO

  # @private
  addSocketToRoom : (id, roomName, cb) ->
    #TODO

  # @private
  removeSocketFromRoom : (id, roomName, cb) ->
    #TODO

  # @private
  removeAllSocketsFromRoom : (roomName, cb) ->
    #TODO

  # @private
  removeSocket : (id, cb) ->
    #TODO

  # @private
  lockToRoom : (id, roomName, cb) ->
    #TODO
    process.nextTick -> cb()

  # @private
  setSocketDisconnecting : (id, cb) ->
    #TODO
    process.nextTick -> cb()

   # @private
  bindUnlock : (lock, op, id, cb) ->
    #TODO
    (args...) ->
      process.nextTick -> cb args...


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

  # @private
  makeKeyName : (prefix, name, keyName) ->
    "#{namespace}:#{prefix}:{#{name}}:#{keyName}"

  # @private
  hasRoom : (name, cb) ->
    @redis.get @makeKeyName('rooms', name, 'exists'), @withTE cb

  # @private
  hasUser : (name, cb) ->
    @redis.get @makeKeyName('user', name, 'exists'), @withTE cb

  # @private
  close : (cb) ->
    @redis.disconnect()
    process.nextTick -> cb()

  # @private
  getRoom : (name, cb) ->
    @hasRoom name, withEH cb, (exists) =>
      unless exists then return cb new ChatServiceError 'noRoom', name
      room = new Room @server, name
      cb null, room

  # @private
  addRoom : (name, state, cb) ->
    room = new Room @server, name
    room.initState state, cb

  # @private
  removeRoom : (name, cb) ->
    @hasRoom name, withEH cb, (exists) =>
      unless exists then return cb new ChatServiceError 'noRoom', name
      room = new Room @server, name
      room.removeState cb

  # @private
  removeSocket : (uid, id, cb) ->
    #TODO

  # @private
  loginUserSocket : (uid, name, id, cb) ->
    user = new User @server, name
    user.initState null, ->
      user.registerSocket id, cb

  # @private
  getUser : (name, cb) ->
    user = new User @server, name
    @hasUser name, withEH cb, (exists) ->
      user.getAllSockets name, withEH cb, (sockets) ->
        unless exists then return cb new ChatServiceError 'noUser', name
        cb null, user, sockets

  # @private
  addUser : (name, state, cb) ->
    user = new User @server, name
    user.initState state, cb


module.exports = RedisState
