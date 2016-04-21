
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
  redis.del set, ->
    unless values then return
    redis.sadd set, values


# State init/remove operations.
# @mixin
# @private
# @nodoc
stateOperations =

  # @private
  initState : (state) ->
    @redis.setnx @makeKeyName('exists'), 1
    .then (exists) =>
      if exists
        error = new ChatServiceError @exitsErrorName, name
        return Promise.reject error
    .then =>
      @stateReset state
    .then =>
      @redis.set @makeKeyName('exists'), 1

  # @private
  removeState : () ->
    @initState null
    .then =>
      @redis.set @makeKeyName('exists'), 0


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
    whitelistOnly = if mode then 1 else 0
    @redis.set @makeKeyName('whitelistMode'), whitelistOnly

  # @private
  whitelistOnlyGet : () ->
    @redis.get @makeKeyName('whitelistMode'), @name
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
    whitelistOnly = if whitelistOnly then 1 else 0
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
      info = { historySize, historyMaxSize
        , @historyMaxGetMessages, lastMessageId }
      Promise.resolve info

  # @private
  getCommonUsers : () ->
    @redis.sdiff @makeKeyName('userlist'), @makeKeyName('whitelist')
    , @makeKeyName('adminlist')

  # @private
  messageAdd : (msg) ->
    #TODO

  # @private
  messagesGetRecent : () ->
    #TODO

  messagesGetAfterId : (id) ->
    #TODO


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


module.exports = RedisState
