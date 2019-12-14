'use strict'
/* eslint-env mocha */
/* eslint-disable no-unused-expressions */

const Promise = require('bluebird')
const _ = require('lodash')
const { expect } = require('chai')
const http = require('http')
const socketIO = require('socket.io')

const {
  cleanup, clientConnect,
  ChatService, startService
} = require('./testutils')

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
    const chatService = new ChatService()
    chatService.on('ready', () => {
      chatService.close().asCallback(done)
    })
  })

  it('should be able to integrate with a http server', function (done) {
    const app = http.createServer((req, res) => res.end())
    chatService = startService({ transportOptions: { http: app } })
    app.listen(port)
    socket1 = clientConnect(user1)
    socket1.on('loginConfirmed', u => {
      expect(u).equal(user1)
      done()
    })
  })

  it('should be able to integrate with an io server', function (done) {
    const io = socketIO(port)
    chatService = startService({ transportOptions: { io } })
    socket1 = clientConnect(user1)
    socket1.on('loginConfirmed', u => {
      expect(chatService.transport.getServer()).equal(io)
      expect(u).equal(user1)
      done()
    })
  })

  it('should be able to use a custom state constructor', function (done) {
    this.timeout(5000)
    const MemoryState = require('../src/MemoryState')
    chatService = startService({ state: MemoryState })
    socket1 = clientConnect(user1)
    socket1.on('loginConfirmed', u => {
      expect(u).equal(user1)
      done()
    })
  })

  it('should be able to use a custom transport constructor', function (done) {
    this.timeout(5000)
    const Transport = require('../src/SocketIOTransport')
    chatService = startService({ transport: Transport })
    socket1 = clientConnect(user1)
    socket1.on('loginConfirmed', u => {
      expect(u).equal(user1)
      done()
    })
  })

  it('should be able to use a custom adapter constructor', function (done) {
    this.timeout(5000)
    const Adapter = require('socket.io-redis')
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
    const start = _.now()
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
