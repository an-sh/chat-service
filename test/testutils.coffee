
if process.env.TEST_ES6
  # require('babel-register')({presets: ['es2015']})
  console.log 'es6 testing...'
  ChatService = require('../src-es6/ChatService')
else
  ChatService = require('../src/ChatService.coffee')
Promise = require 'bluebird'
Redis = require 'ioredis'
_ = require 'lodash'
config = require './config.coffee'
io = require 'socket.io-client'


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
  io.connect url, params

startService = (opts, hooks) ->
  options = { port : config.port }
  _.assign options, state
  _.assign options, opts
  new ChatService options, hooks


if process.env.TEST_REDIS_CLUSTER
  redis = new Redis.Cluster config.redisClusterConnect
  checkDB = (done) ->
    Promise.map redis.nodes('master'), (node) ->
      node.dbsize().then (data) ->
        if data then throw new Error 'Unclean Redis DB'
    .asCallback done
  cleanDB = ->
    Promise.map redis.nodes('master'), (node) ->
      node.flushall()
else
  redis = new Redis config.redisConnect
  checkDB = (done) ->
    redis.dbsize().then (data) ->
      if data then throw new Error 'Unclean Redis DB'
    .asCallback done
  cleanDB = ->
    redis.flushall()


closeInstance = (service) ->
  unless service then return
  service.close()
  .timeout 2000
  .catch (e) ->
    console.log 'Service closing error: ', e
    Promise.try ->
      service.redis and service.redis.disconnect()
    .catchReturn()
    .then ->
      Promise.fromCallback (cb) ->
        service.io.httpServer.close cb
    .catchReturn()

cleanup = (services, sockets, done) ->
  services = _.castArray services
  sockets = _.castArray sockets
  Promise.try ->
    for socket in sockets
      socket and socket.disconnect()
    if customCleanup
      Promise.fromCallback customCleanup
    else
      Promise.map services, closeInstance
  .finally ->
    customCleanup = null
    cleanDB()
  .asCallback done

# fix for node 0.12
nextTick = (fn, args...) ->
  process.nextTick -> fn args...

parallel = (fns, cb) ->
  Promise.map(fns, Promise.fromCallback).asCallback(cb)

series = (fns, cb) ->
  Promise.mapSeries(fns, Promise.fromCallback).asCallback(cb)


module.exports = {
  ChatService
  checkDB
  cleanup
  clientConnect
  closeInstance
  nextTick
  parallel
  series
  setCustomCleanup
  setState
  startService
}
