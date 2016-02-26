
Redis = require 'ioredis'
Redlock = require 'redlock'
_ = require 'lodash'
async = require 'async'
{ withEH, bindTE, bindUnlock, asyncLimit } = require './utils.coffee'


# @private
# @nodoc
namespace = 'chatservice'

# @private
# @nodoc
initState = (redis, state, values, cb) ->
  unless values
    return process.nextTick -> cb()
  redis.del state, withEH cb, ->
    redis.sadd state, values, cb


# Implements state API lists management.
# @private
# @nodoc
class ListsStateRedis

  # @private
  makeDBListName : (listName) ->
    "#{namespace}:#{@prefix}:#{listName}:#{@name}"

  # @private
  makeDBHashName : (hashName) ->
    "#{namespace}:#{@prefix}:#{hashName}"

  # @private
  checkList : (listName, cb) ->
    unless @hasList listName
      error = @errorBuilder.makeError 'noList', listName
    process.nextTick -> cb error

  # @private
  addToList : (listName, elems, cb) ->
    @checkList listName, withEH cb, =>
      @redis.sadd @makeDBListName(listName), elems, @withTE cb

  # @private
  removeFromList : (listName, elems, cb) ->
    @checkList listName, withEH cb, =>
      @redis.srem @makeDBListName(listName), elems, @withTE cb

  # @private
  getList : (listName, cb) ->
    @checkList listName, withEH cb, =>
      @redis.smembers @makeDBListName(listName), @withTE cb, (data) ->
        cb null, data

  # @private
  hasInList : (listName, elem, cb) ->
    @checkList listName, withEH cb, =>
      @redis.sismember @makeDBListName(listName), elem, @withTE cb, (data) ->
        data = if data then true else false
        cb null, data

  # @private
  whitelistOnlySet : (mode, cb) ->
    whitelistOnly = if mode then true else false
    @redis.hset @makeDBHashName('whitelistmodes'), @name, whitelistOnly
    , @withTE cb

  # @private
  whitelistOnlyGet : (cb) ->
    @redis.hget @makeDBHashName('whitelistmodes'), @name, @withTE cb
    , (data) ->
      cb null, JSON.parse data


# Implements room state API.
# @private
# @nodoc
class RoomStateRedis extends ListsStateRedis

  # @private
  constructor : (@server, @name) ->
    @errorBuilder = @server.errorBuilder
    bindTE @
    @historyMaxGetMessages = @server.historyMaxGetMessages
    @historyMaxMessages = @server.historyMaxMessages
    @redis = @server.state.redis
    @prefix = 'room'

  # @private
  hasList : (listName) ->
    return listName in [ 'adminlist', 'whitelist', 'blacklist', 'userlist' ]

  # @private
  initState : (state = {}, cb) ->
    { whitelist, blacklist, adminlist
    , lastMessages, whitelistOnly, owner } = state
    async.parallel [
      (fn) =>
        initState @redis, @makeDBListName('whitelist'), whitelist, fn
      (fn) =>
        initState @redis, @makeDBListName('blacklist'), blacklist, fn
      (fn) =>
        initState @redis, @makeDBListName('adminlist'), adminlist, fn
      (fn) =>
        unless lastMessages then return fn()
        @redis.ltrim @makeDBListName('history'), 0, 0, withEH fn, =>
          msgs = _.map lastMessages, JSON.stringify
          @redis.lpush @makeDBListName('history'), msgs, fn
      (fn) =>
        unless whitelistOnly then return fn()
        @redis.hset @makeDBHashName('whitelistmodes'), @name, whitelistOnly, fn
      (fn) =>
        unless owner then return fn()
        @redis.hset @makeDBHashName('owners'), @name, owner, fn
    ] , @withTE cb

  # @private
  removeState : (cb) ->
    async.parallel [
      (fn) =>
        @redis.del @makeDBListName('whitelist'), @makeDBListName('blacklist')
        , @makeDBListName('adminlist'), @makeDBListName('history')
        , fn
      (fn) =>
        @redis.hdel @makeDBHashName('whitelistmodes'), @name, fn
      (fn) =>
        @redis.hdel @makeDBHashName('owners'), @name, fn
    ] , @withTE cb

  # @private
  ownerGet : (cb) ->
    @redis.hget @makeDBHashName('owners'), @name, @withTE cb

  # @private
  ownerSet : (owner, cb) ->
    @redis.hset @makeDBHashName('owners'), @name, owner, @withTE cb

  # @private
  messageAdd : (msg, cb) ->
    if @historyMaxMessages <= 0 then return process.nextTick -> cb()
    val = JSON.stringify msg
    @redis.lpush @makeDBListName('history'), val, @withTE cb, =>
      @redis.ltrim @makeDBListName('history'), 0, @historyMaxMessages - 1
      , @withTE cb

  # @private
  messagesGet : (cb) ->
    @redis.lrange @makeDBListName('history'), 0, @historyMaxGetMessages - 1
    , @withTE cb, (data) ->
      messages = _.map data, JSON.parse
      cb null, messages

  # @private
  getCommonUsers : (cb) ->
    @redis.sdiff @makeDBListName('userlist'), @makeDBListName('whitelist')
    , @makeDBListName('adminlist'), @withTE cb


# Implements direct messaging state API.
# @private
# @nodoc
class DirectMessagingStateRedis extends ListsStateRedis

  # @private
  constructor : (@server, @username) ->
    @name = @username
    @prefix = 'direct'
    @redis = @server.state.redis
    @errorBuilder = @server.errorBuilder
    bindTE @

  # @private
  hasList : (listName) ->
    return listName in [ 'whitelist', 'blacklist' ]

  # @private
  initState : (state = {}, cb) ->
    { whitelist, blacklist, whitelistOnly } = state
    async.parallel [
      (fn) =>
        initState @redis, @makeDBListName('whitelist'), whitelist, fn
      (fn) =>
        initState @redis, @makeDBListName('blacklist'), blacklist, fn
      (fn) =>
        unless whitelistOnly then return fn()
        @redis.hset @makeDBHashName('whitelistmodes'), @name, whitelistOnly, fn
    ] , @withTE cb

  # @private
  removeState : (cb) ->
    async.parallel [
      (fn) =>
        @redis.del @makeDBListName('whitelist'), @makeDBListName('blacklist')
        , fn
      (fn) =>
        @redis.hdel @makeDBHashName('whitelistmodes'), @name, fn
    ] , @withTE cb


# Implements user state API.
# @private
# @nodoc
class UserStateRedis

  # @private
  constructor : (@server, @username) ->
    @name = @username
    @prefix = 'user'
    @redis = @server.state.redis
    @errorBuilder = @server.errorBuilder
    bindTE @

  # @private
  makeDBListName : (listName) ->
    "#{namespace}:#{@prefix}:#{listName}:#{@name}"

  # @private
  makeSocketToRoomsName : (id) ->
    "#{namespace}:#{@prefix}:socketrooms:#{id}"

  # @private
  makeRoomToSocketsName : (id) ->
    "#{namespace}:#{@prefix}:roomsockets:#{id}"

  # @private
  addSocket : (id, cb) ->
    @redis.sadd @makeDBListName('sockets'), id, @withTE cb

  # @private
  removeSocket : (id, cb) ->
    @redis.srem @makeDBListName('sockets'), id, @withTE cb

  # @private
  getAllSockets : (cb) ->
    @redis.smembers @makeDBListName('sockets'), @withTE cb

  # @private
  getAllRooms : (cb) ->
    @redis.smembers @makeDBListName('rooms'), @withTE cb

  # @private
  getRoomSockets : (roomName, cb) ->
    @redis.sinter @makeRoomToSocketsName(roomName), @makeDBListName('sockets')
    , @withTE cb

  # @private
  addSocketToRoom : (roomName, id, cb) ->
    @redis.multi()
    .sadd @makeDBListName('rooms'), roomName
    .sadd @makeSocketToRoomsName(id), roomName
    .sadd @makeRoomToSocketsName(roomName), id
    .exec @withTE cb

  # @private
  removeSocketFromRoom : (roomName, id, cb) ->
    @redis.multi()
    .srem @makeSocketToRoomsName(id), roomName
    .srem @makeRoomToSocketsName(roomName), id
    .exec @withTE cb, =>
      @getRoomSockets roomName, @withTE cb, (sockets) =>
        if sockets?.length == 0
          @redis.srem @makeDBListName('rooms'), roomName, @withTE cb
        else
          cb()

  # @private
  removeAllSocketsFromRoom : (roomName, cb) ->
    @getRoomSockets roomName, @withTE cb, (sockets) =>
      cmds = []
      for id in sockets
        cmds.push [ 'srem', @makeSocketToRoomsName(id), roomName ]
      @redis.multi cmds
      .srem @makeDBListName('rooms'), roomName
      .sdiffstore @makeRoomToSocketsName(roomName)
      ,@makeRoomToSocketsName(roomName), @makeDBListName('sockets')
      .exec @withTE cb


# Implements global state API.
# @private
# @nodoc
class RedisState

  # @private
  constructor : (@server, @options = {}) ->
    @errorBuilder = @server.errorBuilder
    bindTE @
    if @options.redisClusterHosts
      @redis = new Redis.Cluster @options.redisClusterHosts
      , @options.redisClusterOptions
    else
      @redis = new Redis @options.redisOptions
    @RoomState = RoomStateRedis
    @UserState = UserStateRedis
    @DirectMessagingState = DirectMessagingStateRedis
    @lockTTL = @options?.lockTTL || 2000
    @lock = new Redlock [@redis], @options.redlockOptions

  # @private
  makeDBListName : (hashName) ->
    "#{namespace}:#{hashName}"

  makeLockName : (name) ->
    "#{namespace}:locks:#{name}"

  makeDBSocketsName : (inst) ->
    "#{namespace}:instancesockets:#{inst}"

  # @private
  getRoom : (name, cb) ->
    @redis.sismember @makeDBListName('rooms'), name, @withTE cb, (data) =>
      unless data
        error = @errorBuilder.makeError 'noRoom', name
        return cb error
      room = @server.makeRoom name
      cb null, room

  # @private
  addRoom : (name, state, cb) ->
    room = @server.makeRoom name
    @redis.sadd @makeDBListName('rooms'), name, @withTE cb, (nadded) =>
      if nadded != 1
        return cb @errorBuilder.makeError 'roomExists', name
      if state
        room.initState state, cb
      else
        cb()

  # @private
  removeRoom : (name, cb) ->
    @redis.sismember @makeDBListName('rooms'), name, @withTE cb, (data) =>
      unless data
        return cb @errorBuilder.makeError 'noRoom', name
      @redis.srem @makeDBListName('rooms'), name, @withTE cb

  # @private
  listRooms : (cb) ->
    @redis.smembers @makeDBListName('rooms'), @withTE cb

  # @private
  removeSocket : (uid, id, cb) ->
    @redis.srem @makeDBSocketsName(uid), id, @withTE cb

  # @private
  lockUser : (name, cb) ->
    @lock.lock (@makeLockName name), @lockTTL, @withTE cb

  # @private
  loginUser : (uid, name, socket, cb) ->
    @lockUser name, @withTE cb, (lock) =>
      unlock = bindUnlock lock, cb
      @redis.sadd @makeDBSocketsName(uid), socket.id, @withTE unlock, =>
        user = @server.makeUser name
        @redis.sadd @makeDBListName('users'), name, @withTE unlock, ->
          user.registerSocket socket, unlock

  # @private
  getUser : (name, cb) ->
    user = @server.makeUser name
    @redis.sismember @makeDBListName('users'), name, @withTE cb, (data) =>
      if data then return cb null, user
      else return cb @errorBuilder.makeError 'noUser', name

  # @private
  addUser : (name, state, cb) ->
    @lockUser name, @withTE cb, (lock) =>
      unlock = bindUnlock lock, cb
      @redis.sismember @makeDBListName('users'), name, @withTE unlock
      , (hasUser) =>
        if hasUser
          return unlock @errorBuilder.makeError 'userExists', name
        user = @server.makeUser name
        @redis.sadd @makeDBListName('users'), name, @withTE unlock, ->
          if state
            user.initState state, unlock
          else
            unlock()

  # @private
  removeUser : (name, cb) ->
    user = @server.makeUser name
    @lockUser name, @withTE cb, (lock) =>
      unlock = bindUnlock lock, cb
      @redis.sismember @makeDBListName('users'), name, @withTE unlock, (data) =>
        unless data
          return unlock @errorBuilder.makeError 'noUser', name
        user.disconnectSockets @withTE unlock, =>
          user.removeState @withTE unlock, =>
            @redis.srem @makeDBListName('users'), name, unlock


module.exports = RedisState
