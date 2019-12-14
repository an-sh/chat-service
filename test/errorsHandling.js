'use strict'
/* eslint-env mocha */
/* eslint-disable no-unused-expressions */

const { expect } = require('chai')

const { ChatService, cleanup, clientConnect, startService } =
      require('./testutils')

const { cleanupTimeout, user1, roomName1 } = require('./config')

module.exports = function () {
  let chatService, socket1, socket2, socket3

  afterEach(function (cb) {
    this.timeout(cleanupTimeout)
    cleanup(chatService, [socket1, socket2, socket3], cb)
    chatService = socket1 = socket2 = socket3 = null
  })

  it('should check state constructor type', function (done) {
    try {
      chatService = startService({ state: {} })
    } catch (error) {
      expect(error).ok
      process.nextTick(done)
    }
  })

  it('should check transport constructor type', function (done) {
    try {
      chatService = startService({ transport: {} })
    } catch (error) {
      expect(error).ok
      process.nextTick(done)
    }
  })

  it('should rollback a failed room join', function (done) {
    chatService = startService()
    chatService.addRoom(roomName1, null, () => {
      socket1 = clientConnect(user1)
      socket1.on('loginConfirmed', () => {
        chatService.transport.joinChannel = function () {
          throw new Error('This is an error mockup for testing.')
        }
        socket1.emit('roomJoin', roomName1, error => {
          expect(error).ok
          chatService.execUserCommand(
            true, 'roomGetAccessList', roomName1, 'userlist', (error, data) => {
              expect(error).not.ok
              expect(data).an('Array')
              expect(data).lengthOf(0)
              done()
            })
        })
      })
    })
  })

  it('should rollback a failed socket connect', function (done) {
    chatService = startService()
    chatService.transport.joinChannel = function () {
      throw new Error('This is an error mockup for testing.')
    }
    socket1 = clientConnect(user1)
    socket1.on('loginRejected', error => {
      expect(error).ok
      chatService.execUserCommand(user1, 'listOwnSockets', (error, data) => {
        expect(error).not.ok
        expect(data).empty
        done()
      })
    })
  })

  it('should rollback a disconnected socket connection', function (done) {
    chatService = startService()
    const orig = chatService.state.addSocket
    chatService.state.addSocket = function (id) {
      return orig.apply(chatService.state, arguments)
        .finally(() => chatService.transport.disconnectSocket(id))
    }
    const tst = chatService.transport.rejectLogin
    chatService.transport.rejectLogin = function () {
      tst.apply(chatService.transport, arguments)
      chatService.execUserCommand(user1, 'listOwnSockets', (error, data) => {
        expect(error).not.ok
        expect(data).empty
        done()
      })
    }
    socket1 = clientConnect(user1)
  })

  it('should not join a disconnected socket', function (done) {
    chatService = startService()
    chatService.addRoom(roomName1, null, () => {
      socket1 = clientConnect(user1)
      socket1.on('loginConfirmed', () => {
        chatService.transport.getSocket = function () { return null }
        socket1.emit('roomJoin', roomName1, (error, data) => {
          expect(error).ok
          done()
        })
      })
    })
  })

  it('should emit closed on onStart hook error', function (done) {
    const onStart = (chatService, cb) => {
      expect(chatService).instanceof(ChatService)
      process.nextTick(cb, new Error())
    }
    chatService = startService(null, { onStart })
    chatService.on('closed', error => {
      expect(error).ok
      done()
    })
  })

  it('should propagate transport close errors', function (done) {
    chatService = startService()
    const orig = chatService.transport.close
    chatService.transport.close = function () {
      return orig.apply(chatService.transport, arguments)
        .then(() => { throw new Error() })
    }
    chatService.once('ready', () => {
      chatService.close().catch(error => {
        expect(error).ok
        done()
      })
    })
  })

  it('should propagate onClose errors', function (done) {
    const onClose = (chatService, error, cb) => {
      expect(chatService).instanceof(ChatService)
      expect(error).not.ok
      process.nextTick(cb, new Error())
    }
    chatService = startService(null, { onClose })
    chatService.once('ready', () => {
      chatService.close().catch(error => {
        expect(error).ok
        done()
      })
    })
  })

  it('should propagate transport close errors', function (done) {
    const onClose = (chatService, error, cb) => {
      expect(error).ok
      process.nextTick(cb, error)
    }
    chatService = startService(null, { onClose })
    const orig = chatService.transport.close
    chatService.transport.close = function () {
      return orig.apply(chatService.transport, arguments)
        .then(() => { throw new Error() })
    }
    chatService.once('ready', () => {
      chatService.close().catch(error => {
        expect(error).ok
        done()
      })
    })
  })

  it('should return converted internal error objects', function (done) {
    let msg
    const onConnect = (server, id, cb) => {
      const err = new Error('This is an error mockup for testing.')
      msg = err.toString()
      throw err
    }
    chatService = startService({ useRawErrorObjects: true }, { onConnect })
    socket1 = clientConnect(user1)
    socket1.on('loginRejected', e => {
      expect(e).to.be.an('object')
      expect(e.code).equal('internalError')
      expect(e.args[0]).equal(msg)
      done()
    })
  })

  it('should support extending ChatServiceError', function (done) {
    chatService = startService()
    chatService.once('ready', () => {
      const ChatServiceError = chatService.ChatServiceError
      class MyError extends ChatServiceError {}
      const error = new MyError()
      expect(error).instanceof(ChatServiceError)
      expect(error).instanceof(Error)
      done()
    })
  })
}
