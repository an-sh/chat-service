'use strict'
/* eslint-env mocha */
/* eslint-disable no-unused-expressions */

const Promise = require('bluebird')
const _ = require('lodash')
const { expect } = require('chai')
const http = require('http')
const socketIO = require('socket.io')

const { cleanup, clientConnect, closeInstance, ChatService,
        setCustomCleanup, startService } = require('./testutils')

const { cleanupTimeout, port, user1, redisConnect } = require('./config')

module.exports = function () {
  let chatService, socket1, socket2, socket3

  afterEach(function (cb) {
    this.timeout(cleanupTimeout)
    cleanup(chatService, [socket1, socket2, socket3], cb)
    chatService = socket1 = socket2 = socket3 = null
  })

  it('should be able to spawn a server', function (done) {
    chatService = startService()
    socket1 = clientConnect(user1)
    socket1.on('loginConfirmed', u => {
      expect(u).equal(user1)
      done()
    })
  })

  it('should be able to spawn a server without options', function (done) {
    let chatService = new ChatService()
    chatService.on('ready', () => {
      chatService.close().asCallback(done)
    })
  })

  it('should be able to integrate with a http server', function (done) {
    let app = http.createServer((req, res) => res.end())
    let chatService1 = startService({ transportOptions: { http: app } })
    app.listen(port)
    setCustomCleanup(
      cb => closeInstance(chatService1)
        .finally(() =>
                 Promise.fromCallback(fn => app.close(fn)).catchReturn())
        .asCallback(cb))
    socket1 = clientConnect(user1)
    socket1.on('loginConfirmed', u => {
      expect(u).equal(user1)
      done()
    })
  })

  it('should be able to integrate with an io server', function (done) {
    let io = socketIO(port)
    let chatService1 = startService({ transportOptions: {io} })
    setCustomCleanup(cb => closeInstance(chatService1)
      .finally(() => io.close())
      .asCallback(cb))
    socket1 = clientConnect(user1)
    socket1.on('loginConfirmed', u => {
      expect(chatService1.transport.getServer()).equal(io)
      expect(u).equal(user1)
      done()
    })
  })

  it('should be able to use a custom state constructor', function (done) {
    this.timeout(5000)
    let MemoryState = require('../lib/MemoryState')
    chatService = startService({ state: MemoryState })
    socket1 = clientConnect(user1)
    socket1.on('loginConfirmed', u => {
      expect(u).equal(user1)
      done()
    })
  })

  it('should be able to use a custom transport constructor', function (done) {
    this.timeout(5000)
    let Transport = require('../lib/SocketIOTransport')
    chatService = startService({ transport: Transport })
    socket1 = clientConnect(user1)
    socket1.on('loginConfirmed', u => {
      expect(u).equal(user1)
      done()
    })
  })

  it('should be able to use a custom adapter constructor', function (done) {
    this.timeout(5000)
    let Adapter = require('socket.io-redis')
    chatService = startService(
      { adapter: Adapter, adapterOptions: redisConnect })
    socket1 = clientConnect(user1)
    socket1.on('loginConfirmed', u => {
      expect(u).equal(user1)
      done()
    })
  })

  it('should update an instance heartbeat', function (done) {
    this.timeout(4000)
    this.slow(2000)
    chatService = startService({ heartbeatRate: 500 })
    let start = _.now()
    setTimeout(() => {
      Promise.join(
        chatService.getInstanceHeartbeat(chatService.instanceUID),
        chatService.getInstanceHeartbeat(),
        (ts1, ts2) => {
          expect(ts1).within(start, start + 2000)
          expect(ts2).within(start, start + 2000)
          done()
        })
    }, 1000)
  })

  it('should return null heartbeat if instance is not found', function (done) {
    chatService = startService()
    chatService.getInstanceHeartbeat('instance').then(
      ts => {
        expect(ts).null
        done()
      })
  })
}
