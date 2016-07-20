const _ = require('lodash')
const { expect } = require('chai')

const { ChatService, cleanup, clientConnect, nextTick, parallel, startService } = require('./testutils.coffee')

const { cleanupTimeout, port, user1, user2, user3, roomName1, roomName2 } = require('./config.coffee')

module.exports = function() {
  let chatService = null
  let socket1 = null
  let socket2 = null
  let socket3 = null

  afterEach(function (cb) {
    this.timeout(cleanupTimeout)
    cleanup(chatService, [socket1, socket2, socket3], cb)
    return chatService = socket1 = socket2 = socket3 = null
  })

  it('should send auth data with id', function (done) {
    chatService = startService()
    socket1 = clientConnect(user1)
    return socket1.on('loginConfirmed', function (u, data) {
      expect(u).equal(user1)
      expect(data).include.keys('id')
      return done()
    }
    )
  }
  )

  it('should reject an empty user query', function (done) {
    chatService = startService()
    socket1 = clientConnect()
    return socket1.on('loginRejected', () => done()
    )
  }
  )

  it('should reject user names with illegal characters', function (done) {
    chatService = startService()
    socket1 = clientConnect('user}1')
    return socket1.on('loginRejected', () => done()
    )
  }
  )

  it('should execute socket.io middleware', function (done) {
    let reason = 'some error'
    let auth = (socket, cb) => nextTick(cb, new Error(reason))
    chatService = startService(null, { middleware: auth })
    socket1 = clientConnect()
    return socket1.on('error', function (e) {
      expect(e).deep.equal(reason)
      return done()
    }
    )
  }
  )

  it('should use onConnect hook username and data', function (done) {
    let name = 'someUser'
    let data = { token: 'token' }
    let onConnect = function (server, id, cb) {
      expect(server).instanceof(ChatService)
      expect(id).a('string')
      return nextTick(cb, null, name, data)
    }
    chatService = startService(null, { onConnect})
    socket1 = clientConnect(user1)
    return socket1.on('loginConfirmed', function (u, d) {
      expect(u).equal(name)
      expect(d).include.keys('id')
      expect(d.token).equal(data.token)
      return done()
    }
    )
  }
  )

  it('should reject login if onConnect hook passes error', function (done) {
    let err = null
    let onConnect = function (server, id, cb) {
      expect(server).instanceof(ChatService)
      expect(id).a('string')
      err = new ChatService.ChatServiceError('some error')
      throw err
    }
    chatService = startService(null, { onConnect})
    socket1 = clientConnect(user1)
    return socket1.on('loginRejected', function (e) {
      expect(e).deep.equal(err.toString())
      return done()
    }
    )
  }
  )

  it('should support multiple sockets per user', function (done) {
    chatService = startService()
    socket1 = clientConnect(user1)
    return socket1.on('loginConfirmed', function () {
      socket2 = clientConnect(user1)
      let sid2 = null
      let sid2e = null
      return parallel([
        cb => socket1.on('socketConnectEcho', function (id, nconnected) {
          sid2e = id
          expect(nconnected).equal(2)
          return cb()
        }
        )
        ,
        cb => socket2.on('loginConfirmed', function (u, data) {
          sid2 = data.id
          return cb()
        }
        )

      ], function () {
        expect(sid2e).equal(sid2)
        socket2.disconnect()
        return socket1.on('socketDisconnectEcho', function (id, nconnected) {
          expect(id).equal(sid2)
          expect(nconnected).equal(1)
          return done()
        }
        )
      }
      )
    }
    )
  }
  )

  return it('should disconnect all users on a server shutdown', function (done) {
    let chatService1 = startService()
    socket1 = clientConnect(user1)
    return socket1.on('loginConfirmed', () => parallel([
      cb => chatService1.close(cb),
      cb => socket1.on('disconnect', () => cb())
    ], done)

    )
  }
  )
}
