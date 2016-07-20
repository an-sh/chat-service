import Promise from 'bluebird'
import _ from 'lodash'
import { expect } from 'chai'

import { cleanup, clientConnect, closeInstance, nextTick, ChatService, startService } from './testutils.coffee'

import { cleanupTimeout, port, user1, user2, user3, roomName1, roomName2 } from './config.coffee'

export default function() {
  let chatService = null
  let socket1 = null
  let socket2 = null
  let socket3 = null

  afterEach(function (cb) {
    this.timeout(cleanupTimeout)
    cleanup(chatService, [socket1, socket2, socket3], cb)
    return chatService = socket1 = socket2 = socket3 = null
  })

  it('should execute onStart hook', function (done) {
    let onStart = function (server, cb) {
      expect(server).instanceof(ChatService)
      return server.addRoom(roomName1
        , { whitelist: [ user1 ], owner: user2 }
        , cb)
    }
    chatService = startService(null, { onStart})
    return chatService.on('ready', function () {
      socket1 = clientConnect(user1)
      return socket1.on('loginConfirmed', () => socket1.emit('roomJoin', roomName1, () => socket1.emit('roomGetAccessList', roomName1, 'whitelist'
        , function (error, list) {
          expect(error).not.ok
          expect(list).include(user1)
          return socket1.emit('roomGetOwner', roomName1, function (error, data) {
            expect(error).not.ok
            expect(data).equal(user2)
            return done()
          }
          )
        }
      )

      )

      )
    }
    )
  }
  )

  it('should exectute onClose hook', function (done) {
    let onClose = function (server, error, cb) {
      expect(server).instanceof(ChatService)
      expect(error).not.ok
      return nextTick(cb)
    }
    let chatService1 = startService(null, { onClose})
    return closeInstance(chatService1).asCallback(done)
  }
  )

  it('should execute before and after hooks', function (done) {
    let someData = 'data'
    let before = null
    let after = null
    let sid = null
    let roomCreateBefore = function (execInfo, cb) {
      let { server, userName, id, args } = execInfo
      let [name, mode] = args
      expect(server).instanceof(ChatService)
      expect(userName).equal(user1)
      expect(id).equal(sid)
      expect(args).instanceof(Array)
      expect(name).a('string')
      expect(mode).a('boolean')
      expect(cb).instanceof(Function)
      before = true
      return nextTick(cb)
    }
    let roomCreateAfter = function (execInfo, cb) {
      let { server, userName, id, args, results, error } = execInfo
      let [name, mode] = args
      expect(server).instanceof(ChatService)
      expect(userName).equal(user1)
      expect(id).equal(sid)
      expect(args).instanceof(Array)
      expect(name).a('string')
      expect(mode).a('boolean')
      expect(results).instanceof(Array)
      expect(error).null
      expect(cb).instanceof(Function)
      after = true
      return nextTick(cb, null, someData)
    }
    chatService = startService({ enableRoomsManagement: true }
      , { roomCreateBefore, roomCreateAfter})
    socket1 = clientConnect(user1)
    return socket1.on('loginConfirmed', function (u, data) {
      sid = data.id
      return socket1.emit('roomCreate', roomName1, true, function (error, data) {
        expect(error).not.ok
        expect(before).true
        expect(after).true
        expect(data).equal(someData)
        return done()
      }
      )
    }
    )
  }
  )

  it('should execute hooks with promises', function (done) {
    let someData = 'data'
    let before = null
    let after = null
    let sid = null
    let roomCreateBefore = function (execInfo) {
      before = true
      return Promise.resolve()
    }
    let roomCreateAfter = function (execInfo) {
      after = true
      return Promise.resolve(someData)
    }
    chatService = startService({ enableRoomsManagement: true }
      , { roomCreateBefore, roomCreateAfter})
    socket1 = clientConnect(user1)
    return socket1.on('loginConfirmed', function (u, data) {
      sid = data.id
      return socket1.emit('roomCreate', roomName1, true, function (error, data) {
        expect(error).not.ok
        expect(before).true
        expect(after).true
        expect(data).equal(someData)
        return done()
      }
      )
    }
    )
  }
  )

  it('should execute hooks with sync callbacks', function (done) {
    let someData = 'data'
    let before = null
    let after = null
    let sid = null
    let roomCreateBefore = function (execInfo, cb) {
      before = true
      return cb()
    }
    let roomCreateAfter = function (execInfo, cb) {
      after = true
      return cb(null, someData)
    }
    chatService = startService({ enableRoomsManagement: true }
      , { roomCreateBefore, roomCreateAfter})
    socket1 = clientConnect(user1)
    return socket1.on('loginConfirmed', function (u, data) {
      sid = data.id
      return socket1.emit('roomCreate', roomName1, true, function (error, data) {
        expect(error).not.ok
        expect(before).true
        expect(after).true
        expect(data).equal(someData)
        return done()
      }
      )
    }
    )
  }
  )

  it('should allow commands rest arguments', function (done) {
    let listOwnSocketsAfter = function (execInfo, cb) {
      let { restArgs } = execInfo
      expect(restArgs).instanceof(Array)
      expect(restArgs).lengthOf(1)
      expect(restArgs[0]).true
      return nextTick(cb)
    }
    chatService = startService(null, { listOwnSocketsAfter})
    socket1 = clientConnect(user1)
    return socket1.on('loginConfirmed', function (u, data) {
      let sid = data.id
      return socket1.emit('listOwnSockets', true, function (error, data) {
        expect(error).not.ok
        return done()
      }
      )
    }
    )
  }
  )

  it('should support changing arguments in before hooks', function (done) {
    let roomGetWhitelistModeBefore = function (execInfo, cb) {
      execInfo.args = [roomName2]
      return nextTick(cb)
    }
    chatService = startService({ enableRoomsManagement: true }
      , { roomGetWhitelistModeBefore})
    socket1 = clientConnect(user1)
    return socket1.on('loginConfirmed', () => socket1.emit('roomCreate', roomName2, false, () => socket1.emit('roomCreate', roomName1, true, () => socket1.emit('roomGetWhitelistMode', roomName1, function (error, data) {
      expect(error).not.ok
      expect(data).false
      return done()
    }
    )

    )

    )

    )
  }
  )

  it('should support more arguments in after hooks', function (done) {
    let listOwnSocketsAfter = (execInfo, cb) => nextTick(cb, null, ...execInfo.results, true)
    chatService = startService(null, { listOwnSocketsAfter})
    socket1 = clientConnect(user1)
    return socket1.on('loginConfirmed', function (u, data) {
      let sid = data.id
      return socket1.emit('listOwnSockets', function (error, data, moredata) {
        expect(error).not.ok
        expect(data[sid]).exits
        expect(data[sid]).empty
        expect(moredata).true
        return done()
      }
      )
    }
    )
  }
  )

  it('should execute disconnect Before and After hooks', function (done) {
    let before = false
    let disconnectBefore = function (execInfo, cb) {
      before = true
      return nextTick(cb)
    }
    let disconnectAfter = function (execInfo, cb) {
      expect(before).true
      return nextTick(function () {
        cb()
        return done()
      })
    }
    let chatService1 = startService(null, { disconnectAfter, disconnectBefore})
    socket1 = clientConnect(user1)
    return socket1.on('loginConfirmed', () => chatService1.close()
    )
  }
  )

  it('should stop commands on before hook data', function (done) {
    let val = 'asdf'
    let listOwnSocketsBefore = (execInfo, cb) => nextTick(cb, null, val)
    chatService = startService(null, { listOwnSocketsBefore})
    socket1 = clientConnect(user1)
    return socket1.on('loginConfirmed', () => socket1.emit('listOwnSockets', function (error, data) {
      expect(error).null
      expect(data).equal(val)
      return done()
    }
    )

    )
  }
  )

  it('should accept custom direct messages with a hook', function (done) {
    let html = '<b>HTML message.</b>'
    let message = { htmlMessage: html }
    let directMessagesChecker = (msg, cb) => nextTick(cb)
    chatService =
      startService({ enableDirectMessages: true }, { directMessagesChecker})
    socket1 = clientConnect(user1)
    return socket1.on('loginConfirmed', function () {
      socket2 = clientConnect(user2)
      return socket2.on('loginConfirmed', function () {
        socket1.emit('directMessage', user2, message)
        return socket2.on('directMessage', function (msg) {
          expect(msg).include.keys('htmlMessage', 'author', 'timestamp')
          expect(msg.htmlMessage).equal(html)
          expect(msg.author).equal(user1)
          expect(msg.timestamp).a('Number')
          return done()
        }
        )
      }
      )
    }
    )
  }
  )

  it('should accept custom room messages with a hook', function (done) {
    let html = '<b>HTML message.</b>'
    let message = { htmlMessage: html }
    let roomMessagesChecker = (msg, cb) => nextTick(cb)
    chatService = startService(null, { roomMessagesChecker})
    return chatService.addRoom(roomName1, null, function () {
      socket1 = clientConnect(user1)
      return socket1.on('loginConfirmed', () => socket1.emit('roomJoin', roomName1, function () {
        socket1.emit('roomMessage', roomName1, message)
        return socket1.on('roomMessage', function (room, msg) {
          expect(room).equal(roomName1)
          expect(msg).include.keys('htmlMessage', 'author'
            , 'timestamp', 'id')
          expect(msg.htmlMessage).equal(html)
          expect(msg.author).equal(user1)
          expect(msg.timestamp).a('Number')
          expect(msg.id).equal(1)
          return done()
        }
        )
      }
      )

      )
    }
    )
  }
  )

  return it('should correctly send room messages with binary data', function (done) {
    let data = new Buffer([5])
    let message = { data}
    let roomMessagesChecker = (msg, cb) => nextTick(cb)
    chatService = startService(null, { roomMessagesChecker})
    return chatService.addRoom(roomName1, null, function () {
      socket1 = clientConnect(user1)
      return socket1.on('loginConfirmed', () => socket1.emit('roomJoin', roomName1, function () {
        socket1.emit('roomMessage', roomName1, message)
        return socket1.on('roomMessage', function (room, msg) {
          expect(room).equal(roomName1)
          expect(msg).include.keys('data', 'author'
            , 'timestamp', 'id')
          expect(msg.data).deep.equal(data)
          expect(msg.author).equal(user1)
          expect(msg.timestamp).a('Number')
          expect(msg.id).equal(1)
          return socket1.emit('roomRecentHistory', roomName1, function (error, data) {
            expect(error).not.ok
            expect(data[0]).deep.equal(msg)
            return done()
          }
          )
        }
        )
      }
      )

      )
    }
    )
  }
  )
}
