'use strict'

const ChatService = require('../index.js')

const Promise = require('bluebird')
const Redis = require('ioredis')
const _ = require('lodash')
const config = require('./config')
const io = require('socket.io-client')

function makeURL (port) {
  port = port || config.port
  return `${config.host}:${port}${config.namespace}`
}

function makeParams (userName) {
  let params = {
    query: `user=${userName}`,
    multiplex: false,
    reconnection: false,
    transports: [ 'websocket' ]
  }
  if (!userName) {
    delete params.query
  }
  return params
}

let state = null
function setState (s) { state = s }

let customCleanup = null
function setCustomCleanup (fn) { customCleanup = fn }

function clientConnect (name, port) {
  let url = makeURL(port)
  let params = makeParams(name)
  return io.connect(url, params)
}

function startService (opts, hooks) {
  let options = { port: config.port }
  _.assign(options, state)
  _.assign(options, opts)
  return new ChatService(options, hooks)
}

if (process.env.TEST_REDIS_CLUSTER) {
  var redis = new Redis.Cluster(config.redisClusterConnect)
  var checkDB = () => Promise.map(
    redis.nodes('master'),
    node => node.dbsize().then(data => {
      if (data) { throw new Error('Unclean Redis DB') }
    }))
  var cleanDB = () => Promise.map(redis.nodes('master'), node => node.flushall()
  )
} else {
  redis = new Redis(config.redisConnect)
  checkDB = () => redis.dbsize().then(data => {
    if (data) { throw new Error('Unclean Redis DB') }
  })
  cleanDB = () => redis.flushall()
}

function closeInstance (service) {
  if (!service) { return Promise.resolve() }
  return service.close()
    .timeout(2000)
    .catch(function (e) {
      console.log('Service closing error: ', e)
      return Promise.try(() => service.redis && service.redis.disconnect())
        .catchReturn()
        .then(() => Promise.fromCallback(cb => service.io.httpServer.close(cb)))
        .catchReturn()
    })
}

function cleanup (services, sockets, done) {
  services = _.castArray(services)
  sockets = _.castArray(sockets)
  return Promise.try(() => {
    for (let i = 0; i < sockets.length; i++) {
      let socket = sockets[i]
      socket && socket.disconnect()
    }
    if (customCleanup) {
      return Promise.fromCallback(customCleanup)
    } else {
      return Promise.map(services, closeInstance)
    }
  }).finally(() => {
    customCleanup = null
    return cleanDB()
  }).asCallback(done)
}

// fix for node 0.12
let nextTick = (fn, ...args) => process.nextTick(() => fn(...args))

let parallel = (fns, cb) =>
      Promise.map(fns, Promise.fromCallback).asCallback(cb)

let series = (fns, cb) =>
      Promise.mapSeries(fns, Promise.fromCallback).asCallback(cb)

module.exports = {
  ChatService,
  checkDB,
  cleanup,
  clientConnect,
  closeInstance,
  nextTick,
  parallel,
  series,
  setCustomCleanup,
  setState,
  startService
}
