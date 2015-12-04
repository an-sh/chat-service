
async = require 'async'
Redis = require 'ioredis'
Redlock = require 'redlock'
_ = require 'lodash'
withEH = require('./errors.coffee').withEH
withTansformedError = require('./errors.coffee').withTansformedError


# @private
# @nodoc
asyncLimit = 16

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
  constructor : (@server, @name, @historyMaxMessages = 0) ->
    @errorBuilder = @server.errorBuilder
    @redis = @server.chatState.redis
    @withTE = (args...) => withTansformedError @errorBuilder, args...
    @prefix = 'room'

  # @private
  hasList : (listName) ->
    return listName in [ 'adminlist', 'whitelist', 'blacklist', 'userlist' ]

  # @private
  initState : (state = {}, cb = ->) ->
    { whitelist, blacklist, adminlist
    , lastMessages, whitelistOnly, owner } = state
    async.parallel [
      (fn) =>
        initState @redis, @makeDBListName('whitelist'), whitelist, fn
      , (fn) =>
        initState @redis, @makeDBListName('blacklist'), blacklist, fn
      , (fn) =>
        initState @redis, @makeDBListName('adminlist'), adminlist, fn
      , (fn) =>
        unless lastMessages then return fn()
        @redis.ltrim @makeDBListName('history'), 0, 0, withEH fn, =>
          msgs = _.map lastMessages, JSON.stringify
          @redis.lpush @makeDBListName('history'), msgs, fn
      , (fn) =>
        unless whitelistOnly then return fn()
        @redis.hset @makeDBHashName('whitelistmodes'), @name, whitelistOnly, fn
      , (fn) =>
        unless owner then return fn()
        @redis.hset @makeDBHashName('owners'), @name, owner, fn
    ] , @withTE cb

  # @private
  removeState : (cb = ->) ->
    async.parallel [
      (fn) =>
        @redis.del @makeDBListName('whitelist'), @makeDBListName('blacklist')
        , @makeDBListName('adminlist'), @makeDBListName('history')
        , fn
      , (fn) =>
        @redis.hdel @makeDBHashName('whitelistmodes'), @name, fn
      , (fn) =>
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
    @redis.lrange @makeDBListName('history'), 0, @historyMaxMessages - 1
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
    @redis = @server.chatState.redis
    @errorBuilder = @server.errorBuilder
    @withTE = (args...) => withTansformedError @errorBuilder, args...

  # @private
  hasList : (listName) ->
    return listName in [ 'whitelist', 'blacklist' ]

  # @private
  initState : (state = {}, cb = ->) ->
    { whitelist, blacklist, whitelistOnly } = state
    async.parallel [
      (fn) =>
        initState @redis, @makeDBListName('whitelist'), whitelist, fn
      , (fn) =>
        initState @redis, @makeDBListName('blacklist'), blacklist, fn
      , (fn) =>
        unless whitelistOnly then return fn()
        @redis.hset @makeDBHashName('whitelistmodes'), @name, whitelistOnly, fn
    ] , @withTE cb

  # @private
  removeState : (cb = ->) ->
    async.parallel [
      (fn) =>
        @redis.del @makeDBListName('whitelist'), @makeDBListName('blacklist')
        , fn
      , (fn) =>
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
    @redis = @server.chatState.redis
    @errorBuilder = @server.errorBuilder
    @withTE = (args...) => withTansformedError @errorBuilder, args...

  # @private
  makeDBListName : (listName) ->
    "#{namespace}:#{@prefix}:#{listName}:#{@name}"

  # @private
  socketAdd : (id, cb) ->
    @redis.sadd @makeDBListName('sockets'), id, @withTE cb

  # @private
  socketRemove : (id, cb) ->
    @redis.srem @makeDBListName('sockets'), id, @withTE cb

  # @private
  socketsGetAll : (cb) ->
    @redis.smembers @makeDBListName('sockets'), @withTE cb

  # @private
  roomAdd : (roomName, cb) ->
    @redis.sadd @makeDBListName('rooms') ,roomName, @withTE cb

  # @private
  roomRemove : (roomName, cb) ->
    @redis.srem @makeDBListName('rooms'), roomName, @withTE cb

  # @private
  roomsGetAll : (cb) ->
    @redis.smembers @makeDBListName('rooms'), @withTE cb


# Implements global state API.
# @private
# @nodoc
class RedisState

  # @private
  constructor : (@server, @options) ->
    @errorBuilder = @server.errorBuilder
    @redis = new Redis @options
    @withTE = (args...) => withTansformedError @errorBuilder, args...
    @roomState = RoomStateRedis
    @userState = UserStateRedis
    @directMessagingState = DirectMessagingStateRedis
    @lockTTL = @options?.lockTTL || 2000
    @lock = new Redlock [@redis], {}

  # @private
  makeDBHashName : (hashName) ->
    "#{namespace}:#{hashName}"

  makeLockName : (name) ->
    "#{namespace}:locks:#{name}"

  # @private
  getRoom : (name, cb) ->
    @redis.sismember @makeDBHashName('rooms'), name, @withTE cb, (data) =>
      unless data
        error = @errorBuilder.makeError 'noRoom', name
        return cb error
      room = new @server.Room name
      cb null, room

  # @private
  addRoom : (room, cb) ->
    name = room.name
    @redis.sismember @makeDBHashName('rooms'), name, @withTE cb, (data) =>
      if data
        return cb @errorBuilder.makeError 'roomExists', name
      @redis.sadd @makeDBHashName('rooms'), name, @withTE cb

  # @private
  removeRoom : (name, cb) ->
    @redis.sismember @makeDBHashName('rooms'), name, @withTE cb, (data) =>
      unless data
        return cb @errorBuilder.makeError 'noRoom', name
      @redis.srem @makeDBHashName('rooms'), name, @withTE cb

  # @private
  listRooms : (cb) ->
    @redis.smembers @makeDBHashName('rooms'), @withTE cb

  # @private
  getOnlineUser : (name, cb) ->
    @redis.sismember @makeDBHashName('usersOnline'), name, @withTE cb, (data) =>
      unless data
        return cb @errorBuilder.makeError 'noUserOnline', name
      user = new @server.User name
      cb null, user

  # @private
  lockUser : (name, cb) ->
    @lock.lock (@makeLockName name), @lockTTL, @withTE cb

  # @private
  getUser : (name, cb) ->
    user = new @server.User name
    @redis.sismember @makeDBHashName('usersOnline'), name, @withTE cb, (data) =>
      if data then return cb null, user, true
      @redis.sismember @makeDBHashName('users'), name, @withTE cb, (data) =>
        if data then return cb null, user, false
        else return cb @errorBuilder.makeError 'noUser', name

  # @private
  loginUser : (name, socket, cb) ->
    @lock.lock (@makeLockName name), @lockTTL, @withTE cb, (lock) =>
      unlock = (args...) ->
        lock.unlock()
        cb args...
      @redis.sismember @makeDBHashName('usersOnline'), name, @withTE unlock
      , (data) =>
        if data
          user = new @server.User name
          user.registerSocket socket, (error) -> unlock error, user
        else
          @redis.sismember @makeDBHashName('users'), name, @withTE unlock
          , (data) =>
            user = new @server.User name
            async.parallel [
              (fn) =>
                @redis.sadd @makeDBHashName('users'), name, fn
              (fn) =>
                @redis.sadd @makeDBHashName('usersOnline'), name, fn
            ], @withTE unlock, ->
              user.registerSocket socket, unlock

  # @private
  logoutUser : (name, cb) ->
    @redis.sismember @makeDBHashName('usersOnline'), name, @withTE cb, (data) =>
      unless data
        return cb @errorBuilder.makeError 'noUserOnline', name
      @redis.srem @makeDBHashName('usersOnline'), name, @withTE cb

  # @private
  addUser : (name, cb = (->), state = null) ->
    @redis.sismember @makeDBHashName('users'), name, @withTE cb, (data) =>
      if data
        return cb @errorBuilder.makeError 'userExists', name
      user = new @server.User name
      @redis.sadd @makeDBHashName('users'), name, @withTE cb, ->
        if state
          user.initState state, cb
        else
          cb()

  # @private
  removeUser : (name, cb = ->) ->
    user = new @server.User name
    @redis.sismember @makeDBHashName('usersOnline'), name, @withTE cb, (data) =>
      fn = =>
        @redis.sismember @makeDBHashName('users'), name, @withTE cb, (data) =>
          unless data
            return cb @errorBuilder.makeError 'noUser', name
          async.parallel [
              (fn) =>
                @redis.srem @makeDBHashName('users'), name, fn
              (fn) =>
                @redis.srem @makeDBHashName('usersOnline'), name, fn
              (fn) ->
                user.removeState fn
          ], @withTE cb
      if data then user.disconnectUser fn
      else fn()


module.exports = {
  RedisState
}
