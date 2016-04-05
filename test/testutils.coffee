
Promise = require 'bluebird'
Redis = require 'ioredis'
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

clientConnect = (name) ->
  ioClient.connect url, makeParams(name)

state = null
setState = (s) -> state = s
getState = -> state

customCleanup = null
redis = new Redis config.redisConnect

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
    redis.flushall()
  .asCallback done

setCustomCleanup = (fn) ->
  customCleanup = fn

checkDB = (done) ->
  redis.dbsize (error, data) ->
    if error then return done error
    if data then return done new Error 'Unclean Redis DB'
    done()

module.exports = {
  checkDB
  cleanup
  clientConnect
  getState
  redis
  setCustomCleanup
  setState
}
