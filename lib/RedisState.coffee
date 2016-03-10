
Redis = require 'ioredis'
Room = require './Room.coffee'
User = require './User.coffee'
_ = require 'lodash'
async = require 'async'

{ bindTE, withEH, asyncLimit } = require './utils.coffee'


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
  messagesGetRecent : (cb) ->
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
  constructor : (@server, @userName) ->
    @name = @userName
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
  constructor : (@server, @userName) ->
    @name = @userName
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
    #TODO

  # @private
  getAllSockets : (cb) ->
    #TODO

  # @private
  getAllRooms : (cb) ->
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
  lockSocketRoom : (id, roomName, cb) ->
    #TODO
    process.nextTick -> cb()

  # @private
  setRoomAccessRemoved : (roomName, cb) ->
    #TODO
    process.nextTick -> cb()

  # @private
  setSocketDisconnecting : (id, cb) ->
    #TODO
    process.nextTick -> cb()

   # @private
  bindUnlockSelf : (lock, op, id, cb) ->
    (args...) ->
      process.nextTick -> cb args...

  # @private
  bindUnlockOthers : (lock, op, userName, cb) ->
    (args...) ->
      process.nextTick -> cb args...


# Implements global state API.
# @private
# @nodoc
class RedisState

  # @private
  constructor : (@server, @options = {}) ->
    @errorBuilder = @server.errorBuilder
    bindTE @
    redisOptions = _.castArray @options.redisOptions
    if @options.useCluster
      @redis = new Redis.Cluster redisOptions...
    else
      @redis = new Redis redisOptions...
    @RoomState = RoomStateRedis
    @UserState = UserStateRedis
    @DirectMessagingState = DirectMessagingStateRedis
    @lockTTL = @options.lockTTL || 5000
    @server.redis = @redis

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
      room = new Room @server, name
      cb null, room

  # @private
  addRoom : (name, state, cb) ->
    room = new Room @server, name
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
  loginUserSocket : (uid, name, id, cb) ->
    user = new User @server, name
    @redis.multi()
    .sadd @makeDBSocketsName(uid), id
    .sadd @makeDBListName('users'), name
    .exec @withTE cb, ->
      user.registerSocket id, cb

  # @private
  getUser : (name, cb) ->
    user = new User @server, name
    @redis.sismember @makeDBListName('users'), name, @withTE cb, (data) =>
      if data then return cb null, user
      else return cb @errorBuilder.makeError 'noUser', name

  # @private
  addUser : (name, state, cb) ->
    @redis.sadd @makeDBListName('users'), name, @withTE cb, (nadded) ->
      if nadded == 0
        return cb @errorBuilder.makeError 'userExists', name
      if state
        user = new User @server, name
        user.initState state, cb
      else
        cb()

  # @private
  removeUserData : (name, cb) ->
    #TODO


module.exports = RedisState
