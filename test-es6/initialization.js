/* eslint-env mocha */

const Promise = require('bluebird')
const _ = require('lodash')
const { expect } = require('chai')
const http = require('http')
const socketIO = require('socket.io')

const { cleanup, clientConnect, closeInstance,
        setCustomCleanup, startService } = require('./testutils')

const { cleanupTimeout, port, user1, redisConnect } = require('./config')

module.exports = function () {
  let chatService = null
  let socket1 = null
  let socket2 = null
  let socket3 = null

  afterEach(function (cb) {
    this.timeout(cleanupTimeout)
    cleanup(chatService, [socket1, socket2, socket3], cb)
    chatService = socket1 = socket2 = socket3 = null
  })

  it('should spawn a server', function (done) {
    chatService = startService()
    socket1 = clientConnect(user1)
    socket1.on('loginConfirmed', (u) => {
      expect(u).equal(user1)
      done()
    })
  })

  it('should integrate with a provided http server', function (done) {
    let app = http.createServer((req, res) => res.end())
    let chatService1 = startService({ transportOptions: { http: app } })
    app.listen(port)
    setCustomCleanup(
      cb => closeInstance(chatService1)
        .finally(() =>
                 Promise.fromCallback(fn => app.close(fn)).catchReturn())
        .asCallback(cb))
    socket1 = clientConnect(user1)
    socket1.on('loginConfirmed', (u) => {
      expect(u).equal(user1)
      done()
    })
  })

  it('should integrate with a provided io server', function (done) {
    let io = socketIO(port)
    let chatService1 = startService({ transportOptions: {io} })
    setCustomCleanup(cb => closeInstance(chatService1)
      .finally(() => io.close())
      .asCallback(cb))
    socket1 = clientConnect(user1)
    socket1.on('loginConfirmed', (u) => {
      expect(u).equal(user1)
      done()
    })
  })

  it('should use a custom state constructor', function (done) {
    let MemoryState = require('../src-es6/MemoryState')
    chatService = startService({ state: MemoryState })
    socket1 = clientConnect(user1)
    socket1.on('loginConfirmed', (u) => {
      expect(u).equal(user1)
      done()
    })
  })

  it('should use a custom transport constructor', function (done) {
    let Transport = require('../src-es6/SocketIOTransport')
    chatService = startService({ transport: Transport })
    socket1 = clientConnect(user1)
    socket1.on('loginConfirmed', (u) => {
      expect(u).equal(user1)
      done()
    })
  })

  it('should use a custom adapter constructor', function (done) {
    let Adapter = require('socket.io-redis')
    chatService = startService(
      { adapter: Adapter, adapterOptions: redisConnect })
    socket1 = clientConnect(user1)
    socket1.on('loginConfirmed', (u) => {
      expect(u).equal(user1)
      done()
    })
  })

  it('should update an instance heartbeat', function (done) {
    this.timeout(4000)
    this.slow(2000)
    chatService = startService({ heartbeatRate: 500 })
    let start = _.now()
    setTimeout(() => chatService.getInstanceHeartbeat(chatService.instanceUID)
      .then((ts) => {
        expect(ts).within(start, start + 2000)
        done()
      }), 1000)
  })
}
