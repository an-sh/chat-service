
async = require 'async'
Redis = require 'ioredis'
Redlock = require 'redlock'
ms = require './state-memory.coffee'

asyncLimit = 16

# @private
withTansformedError = (obj, callback, normallCallback) ->
  return (error, data) ->
    if error
      callback obj.errorBuilder.makeError 'serverError', error
    else if normallCallback
      normallCallback data
    else
      callback error, data

# @TODO
mix = (obj, mixin, args) ->
  for name, method of mixin.prototype
    unless obj[name]
      obj[name] = method
  mixin.apply obj, args


# Implements state API lists management.
# @private
class ListsStateRedis
  constructor : ->
    mix @, ms.ListsStateMemory, arguments


# Implements room state API.
# @private
class RoomStateRedis extends ListsStateRedis
  constructor : ->
    mix @, ms.RoomStateMemory, arguments


# Implements direct messaging state API.
# @private
class DirectMessagingStateRedis extends ListsStateRedis
  constructor : ->
    mix @, ms.DirectMessagingStateMemory, arguments


# Implements user state API.
# @private
class UserStateRedis
  constructor : ->
    mix @, ms.UserStateMemory, arguments


# Implements global state API.
# @private
class RedisState

  # @private
  constructor : (@server, @options) ->
    @errorBuilder = @server.errorBuilder
    @redis = new Redis @options
    @withTE = (args...) => withTansformedError @, args...
    mix @, ms.MemoryState, arguments

  # @private
  getRoom : (name, cb) ->
    @redis.sismember 'rooms', name, @withTE cb, (data) =>
      unless data
        error = @errorBuilder.makeError 'noRoom', name
        return cb error
      room = @rooms[name]
      cb null, room

  # @private
  addRoom : (room, cb) ->
    name = room.name
    @redis.sismember 'rooms', name, @withTE cb, (data) =>
      if data
        return cb @errorBuilder.makeError 'roomExists', name
      @rooms[name] = room
      @redis.sadd 'rooms', name, @withTE cb

  # @private
  removeRoom : (name, cb) ->
    @redis.sismember 'rooms', name, @withTE cb, (data) =>
      unless data
        return cb @errorBuilder.makeError 'noRoom', name
      delete @rooms[name]
      @redis.srem 'rooms', name, @withTE cb

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
          ], (error) ->
            if error then return cb error
            user.registerSocket socket, (error) ->
              cb error, user

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
      @redis.sadd 'users', name, @withTE cb, (data) ->
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
          ], (error) =>
            if error then return cb error
            delete @users[name]
            cb()
      if data then user.removeUser fn
      else fn()


module.exports = {
  RedisState
}
