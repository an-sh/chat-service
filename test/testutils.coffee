
if process.env.COVERAGE
  ChatService = require('../src/ChatService.coffee')
else
  ChatService = require('../index.js')

Promise = require 'bluebird'
Redis = require 'ioredis'
_ = require 'lodash'
config = require './config.coffee'
ioClient = require 'socket.io-client'


makeURL = (port) ->
  port = port || config.port
  "#{config.host}:#{port}#{config.namespace}"

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


clientConnect = (name, port) ->
  url = makeURL port
  params = makeParams(name)
  ioClient.connect url, params

startService = (opts, hooks) ->
  options = { port : config.port }
  _.assign options, state
  _.assign options, opts
  new ChatService options, hooks


if process.env.TEST_REDIS_CLUSTER
  redis = new Redis.Cluster config.redisClusterConnect
  checkDB = (done) ->
    Promise.map redis.nodes('master'), (node) ->
      node.dbsize (error, data) ->
        if error then return done error
        if data then return done new Error 'Unclean Redis DB'
    .asCallback done
  cleanDB = ->
    Promise.map redis.nodes('master'), (node) ->
      node.flushall()
else
  redis = new Redis config.redisConnect
  checkDB = (done) ->
    redis.dbsize (error, data) ->
      if error then return done error
      if data then return done new Error 'Unclean Redis DB'
      done()
  cleanDB = ->
    redis.flushall()


cleanup = (services, sockets, done) ->
  services = _.castArray services
  sockets = _.castArray sockets
  Promise.try ->
    for socket in sockets
      socket?.disconnect()
    if customCleanup
      Promise.fromCallback (cb) ->
        customCleanup cb
    else
      Promise.each services, (service) ->
        service?.close()
  .finally ->
    customCleanup = null
    cleanDB()
  .asCallback done


module.exports = {
  ChatService
  checkDB
  cleanup
  clientConnect
  setCustomCleanup
  setState
  startService
}
