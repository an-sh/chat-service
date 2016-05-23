
ChatService = require('../index.js')
Promise = require 'bluebird'
Redis = require 'ioredis'
_ = require 'lodash'
config = require './config.coffee'
ioClient = require 'socket.io-client'


url = "http://localhost:#{config.port}/chat-service"

makeParams = (userName) ->
  params =
    query : "user=#{userName}"
    multiplex : false
    reconnection : false
    transports : [ 'websocket' ]
  unless userName
    delete params.query
  return params


state = null
setState = (s) -> state = s

customCleanup = null
setCustomCleanup = (fn) -> customCleanup = fn


clientConnect = (name) ->
  ioClient.connect url, makeParams(name)

startService = (opts, hooks) ->
  options = { port : config.port }
  _.assign options, state
  _.assign options, opts
  new ChatService options, hooks


if process.env.TEST_REDIS_CLUSTER == 'true'
  redis = new Redis.Cluster config.redisClusterConnect
  checkDB = (done) ->
    redis.to('masters').call('dbsize').then (data) ->
      if data and data.length
        Promise.reject new Error 'Unclean Redis DB'
    .asCallback done
  cleanDB = ->
    redis.to('masters').call('flushdb')
else
  redis = new Redis config.redisConnect
  checkDB = (done) ->
    redis.dbsize (error, data) ->
      if error then return done error
      if data then return done new Error 'Unclean Redis DB'
      done()
  cleanDB = ->
    redis.flushall()


cleanup = (chatService, sockets, done) ->
  Promise.try ->
    for socket in sockets
      socket?.disconnect()
    if customCleanup
      Promise.fromCallback (cb) ->
        customCleanup cb
    else if chatService
      chatService.close()
  .finally ->
    customCleanup = null
    cleanDB()
  .asCallback done


module.exports = {
  checkDB
  cleanup
  clientConnect
  setCustomCleanup
  setState
  startService
}
