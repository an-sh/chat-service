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
  const params = {
    query: `user=${userName}`,
    multiplex: false,
    reconnection: false,
    transports: ['websocket']
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
  const url = makeURL(port)
  const params = makeParams(name)
  return io.connect(url, params)
}

function onConnect (server, id) {
  const { query } = server.transport.getHandshakeData(id)
  return Promise.resolve(query.user)
}

function startService (opts, _hooks) {
  const options = { port: config.port }
  const hooks = _.assign({ onConnect }, _hooks)
  _.merge(options, state, opts)
  return new ChatService(options, hooks)
}

let redis, checkDB, cleanDB

if (process.env.TEST_REDIS_CLUSTER) {
  redis = new Redis.Cluster(config.redisClusterConnect)
  checkDB = () => Promise.map(
    redis.nodes('master'),
    node => node.dbsize().then(data => {
      if (data) { throw new Error('Unclean Redis DB') }
    }))
  cleanDB = () => Promise.map(redis.nodes('master'), node => node.flushall())
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
    })
}

function cleanup (services, sockets, done) {
  services = _.castArray(services)
  sockets = _.castArray(sockets)
  return Promise.try(() => {
    for (let i = 0; i < sockets.length; i++) {
      const socket = sockets[i]
      socket && socket.disconnect()
    }
    if (customCleanup) {
      return Promise.fromCallback(customCleanup)
    } else {
      return Promise.map(services, closeInstance)
    }
  }).timeout(3000).catch(Promise.TimeoutError, e => {
    console.log('Service closing timeout: ', e)
  }).finally(() => {
    customCleanup = null
    return cleanDB()
  }).asCallback(done)
}

const parallel = (fns, cb) =>
  Promise.map(fns, Promise.fromCallback).asCallback(cb)

const series = (fns, cb) =>
  Promise.mapSeries(fns, Promise.fromCallback).asCallback(cb)

module.exports = {
  ChatService,
  checkDB,
  cleanup,
  clientConnect,
  closeInstance,
  parallel,
  redis,
  series,
  setCustomCleanup,
  setState,
  startService
}
