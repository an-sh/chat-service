
async = require 'async'
Redis = require 'ioredis'
Redlock = require 'redlock'
_ = require 'lodash'
ms = require './state-memory.coffee'

withEH = require('./errors.coffee').withEH
withTansformedError = require('./errors.coffee').withTansformedError

# @private
asyncLimit = 16


# @private
initState = (redis, state, values, cb) ->
  unless values
    return process.nextTick -> cb()
  redis.del state, withEH cb, ->
    redis.sadd state, values, cb


# @TODO
mix = (obj, mixin, args) ->
  for name, method of mixin.prototype
    unless obj[name]
      obj[name] = method
  mixin.apply obj, args


class ListsStateRedis

  # @private
  makeDBListName : (listName) ->
    "#{@prefix}_#{listName}_#{@name}"

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
    @redis.hset "#{@prefix}_whitelistmodes", @name, whitelistOnly, cb

  # @private
  whitelistOnlyGet : (cb) ->
    @redis.hget "#{@prefix}_whitelistmodes", @name, cb



# Implements room state API.
# @private
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
  initState : ( state = {}, cb ) ->
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
        @redis.ltrim @makeDBListName('lastMessages'), 0, 0, withEH fn, =>
          @redis.lpush @makeDBListName('lastMessages'), lastMessages, fn
      , (fn) =>
        unless whitelistOnly then return fn()
        @redis.hset "#{@prefix}_whitelistmodes", @name, whitelistOnly, fn
      , (fn) =>
        unless owner then return fn()
        @redis.hset "#{@prefix}_owners", @name, owner, fn
    ] , @withTE cb

  # @private
  ownerGet : (cb) ->
    @redis.hget "#{@prefix}_owners", @name, @withTE cb

  # @private
  ownerSet : (owner, cb) ->
    @redis.hset "#{@prefix}_owners", @name, owner, @withTE cb

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
class DirectMessagingStateRedis extends ListsStateRedis
  constructor : ->


# Implements user state API.
# @private
class UserStateRedis
  constructor : ->


# Implements global state API.
# @private
class RedisState

  # @private
  constructor : (@server, @options) ->
    @errorBuilder = @server.errorBuilder
    @redis = new Redis @options
    @withTE = (args...) => withTansformedError @errorBuilder, args...
    mix @, ms.MemoryState, arguments
    @roomState = RoomStateRedis

  # @private
  getRoom : (name, cb) ->
    @redis.sismember 'rooms', name, @withTE cb, (data) =>
      unless data
        error = @errorBuilder.makeError 'noRoom', name
        return cb error
      room = new @server.Room @server, name
      cb null, room

  # @private
  addRoom : (room, cb) ->
    name = room.name
    @redis.sismember 'rooms', name, @withTE cb, (data) =>
      if data
        return cb @errorBuilder.makeError 'roomExists', name
      @redis.sadd 'rooms', name, @withTE cb

  # @private
  removeRoom : (name, cb) ->
    @redis.sismember 'rooms', name, @withTE cb, (data) =>
      unless data
        return cb @errorBuilder.makeError 'noRoom', name
      @redis.srem 'rooms', name, @withTE cb

  # @private
  listRooms : (cb) ->
    @redis.smembers 'rooms', @withTE cb

  # @private
  getOnlineUser : (name, cb) ->
    @redis.sismember 'users_online', name, @withTE cb, (data) =>
      unless data
        return cb @errorBuilder.makeError 'noUserOnline', name
      user = @users[name]
      cb null, user

  # @private
  getUser : (name, cb) ->
    user = @users[name]
    @redis.sismember 'users_online', name, @withTE cb, (data) =>
      if data then return cb null, user, true
      @redis.sismember 'users', name, @withTE cb, (data) =>
        unless data
          return cb @errorBuilder.makeError 'noUser', name
        cb null, user, false

  # @private
  loginUser : (name, socket, cb) ->
    user = @users[name]
    @redis.sismember 'users_online', name, @withTE cb, (data) =>
      if data
        user.registerSocket socket, (error) -> cb error, user
      else
        @redis.sismember 'users', name, @withTE cb, (data) =>
          if data
            user = @users[name]
          else
            user = new @server.User @server, name
            @users[name] = user
          async.parallel [
            (fn) =>
              @redis.sadd 'users', name, @withTE fn
            (fn) =>
              @redis.sadd 'users_online', name, @withTE fn
          ], withEH cb, ->
            user.registerSocket socket, cb

  # @private
  logoutUser : (name, cb) ->
    @redis.sismember 'users_online', name, @withTE cb, (data) =>
      unless data
        return cb @errorBuilder.makeError 'noUserOnline', name
      @redis.srem 'users_online', name, @withTE cb

  # @private
  addUser : (name, cb = (->), state = null) ->
    @redis.sismember 'users', name, @withTE cb, (data) =>
      if data
        return cb @errorBuilder.makeError 'userExists', name
      user = new @server.User @server, name
      @users[name] = user
      @redis.sadd 'users', name, @withTE cb, ->
        if state
          user.initState state, cb
        else
          cb()

  # @private
  removeUser : (name, cb = ->) ->
    user = @users[name]
    @redis.sismember 'users_online', name, @withTE cb, (data) =>
      fn = =>
        @redis.sismember 'users', name, @withTE cb, (data) =>
          unless data
            return cb @errorBuilder.makeError 'noUser', name
          async.parallel [
              (fn) =>
                @redis.srem 'users', name, @withTE fn
              (fn) =>
                @redis.srem 'users_online', name, @withTE fn
          ], withEH cb, =>
            delete @users[name]
            cb()
      if data then user.removeUser fn
      else fn()


module.exports = {
  RedisState
}
