'use strict'
/* eslint-env mocha */
/* eslint-disable no-unused-expressions */

const { expect } = require('chai')

const { ChatService, cleanup, clientConnect, parallel, startService } =
      require('./testutils')

const { cleanupTimeout, user1 } = require('./config')

module.exports = function () {
  let chatService, socket1, socket2, socket3

  afterEach(function (cb) {
    this.timeout(cleanupTimeout)
    cleanup(chatService, [socket1, socket2, socket3], cb)
    chatService = socket1 = socket2 = socket3 = null
  })

  it('should send auth data with an id field', function (done) {
    chatService = startService()
    socket1 = clientConnect(user1)
    socket1.on('loginConfirmed', (u, data) => {
      expect(u).equal(user1)
      expect(data).include.keys('id')
      done()
    })
  })

  it('should reject logins without an onConnect hook', function (done) {
    chatService = startService(null, { onConnect: undefined })
    socket1 = clientConnect(user1)
    socket1.on('loginRejected', () => done())
  })

  it('should reject user names with illegal characters', function (done) {
    chatService = startService()
    socket1 = clientConnect('user}1')
    socket1.on('loginRejected', () => done())
  })

  it('should execute socket.io middleware', function (done) {
    const reason = 'some error'
    const auth = (socket, cb) => process.nextTick(cb, new Error(reason))
    chatService = startService({ transportOptions: { middleware: auth } })
    socket1 = clientConnect()
    socket1.on('error', e => {
      expect(e).deep.equal(reason)
      done()
    })
  })

  it('should store and return a handshake data', function (done) {
    const onConnect = (server, id, cb) => {
      const data = server.transport.getHandshakeData(id)
      expect(data).an('Object')
      expect(data.isConnected).true
      expect(data.query.user).equal(user1)
      process.nextTick(cb)
    }
    chatService = startService(null, { onConnect })
    socket1 = clientConnect(user1)
    socket1.on('loginRejected', () => {
      const data = chatService.transport.getHandshakeData('id')
      expect(data).an('Object')
      expect(data.isConnected).false
      done()
    })
  })

  it('should use an username and a data passed by onConnect', function (done) {
    const name = 'someUser'
    const data = { token: 'token' }
    const onConnect = (server, id, cb) => {
      expect(server).instanceof(ChatService)
      expect(id).a('string')
      process.nextTick(cb, null, name, data)
    }
    chatService = startService(null, { onConnect })
    socket1 = clientConnect(user1)
    socket1.on('loginConfirmed', (u, d) => {
      expect(u).equal(name)
      expect(d).include.keys('id')
      expect(d.token).equal(data.token)
      done()
    })
  })

  it('should reject a login if onConnect passes an error', function (done) {
    let err
    const onConnect = (server, id, cb) => {
      expect(server).instanceof(ChatService)
      expect(id).a('string')
      err = new ChatService.ChatServiceError('some error')
      throw err
    }
    chatService = startService(null, { onConnect })
    socket1 = clientConnect(user1)
    socket1.on('loginRejected', e => {
      expect(e).deep.equal(err.toString())
      done()
    })
  })

  it('should support multiple sockets per user', function (done) {
    chatService = startService()
    socket1 = clientConnect(user1)
    socket1.on('loginConfirmed', () => {
      socket2 = clientConnect(user1)
      let sid2, sid2e
      parallel([
        cb => socket1.on('socketConnectEcho', (id, nconnected) => {
          sid2e = id
          expect(nconnected).equal(2)
          cb()
        }),
        cb => socket2.on('loginConfirmed', (u, data) => {
          sid2 = data.id
          cb()
        })
      ], () => {
        expect(sid2e).equal(sid2)
        socket2.disconnect()
        socket1.on('socketDisconnectEcho', (id, nconnected) => {
          expect(id).equal(sid2)
          expect(nconnected).equal(1)
          done()
        })
      })
    })
  })

  it('should disconnect all users on a server shutdown', function (done) {
    const chatService1 = startService()
    socket1 = clientConnect(user1)
    socket1.on('loginConfirmed', () => parallel([
      cb => chatService1.close(cb),
      cb => socket1.on('disconnect', () => cb())
    ], done))
  })

  it('should be able to get instance sockets', function (done) {
    chatService = startService()
    socket1 = clientConnect(user1)
    socket1.on('loginConfirmed', (name, { id }) => parallel([
      cb => chatService.state.getInstanceSockets().asCallback(cb),
      cb => chatService.state.getInstanceSockets(chatService.instanceUID)
        .asCallback(cb)
    ], (error, [s1, s2]) => {
      expect(error).not.ok
      expect(s1).an('Object')
      expect(s2).an('Object')
      expect(Object.keys(s1)).lengthOf(1)
      expect(Object.keys(s2)).lengthOf(1)
      expect(s1).property(id, user1)
      expect(s2).property(id, user1)
      done()
    }))
  })
}
