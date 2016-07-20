import _ from 'lodash'
import { expect } from 'chai'

import { cleanup, clientConnect, startService } from './testutils.coffee'

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

  it('should return raw error objects', function (done) {
    chatService = startService({ useRawErrorObjects: true })
    socket1 = clientConnect(user1)
    return socket1.on('loginConfirmed', () => socket1.emit('roomGetAccessList', roomName1, 'nolist', function (error) {
      expect(error.name).equal('noRoom')
      expect(error.args).length.above(0)
      expect(error.args[0]).equal('room1')
      return done()
    }
    )

    )
  }
  )

  it('should validate message argument types', function (done) {
    chatService = startService({ enableRoomsManagement: true })
    socket1 = clientConnect(user1)
    return socket1.on('loginConfirmed', u => socket1.emit('roomCreate', null, false, function (error, data) {
      expect(error).ok
      expect(data).not.ok
      return done()
    }
    )

    )
  }
  )

  it('should have a message validator instance', function (done) {
    chatService = startService()
    return chatService.validator.checkArguments('roomGetAccessList'
      , roomName1, 'userlist', function (error) {
        expect(error).not.ok
        return done()
      }
    )
  }
  )

  it('should check for unknown commands', function (done) {
    chatService = startService()
    return chatService.validator.checkArguments('cmd', function (error) {
      expect(error).ok
      return done()
    }
    )
  }
  )

  it('should validate a message argument count', function (done) {
    chatService = startService({ enableRoomsManagement: true })
    socket1 = clientConnect(user1)
    return socket1.on('loginConfirmed', u => socket1.emit('roomCreate', function (error, data) {
      expect(error).ok
      expect(data).not.ok
      return done()
    }
    )

    )
  }
  )

  return it('should have a server messages and user commands fields', function (done) {
    chatService = startService()
    for (var k in chatService.serverMessages) {
      var fn = chatService.serverMessages[k]
      fn()
    }
    for (k in chatService.userCommands) {
      var fn = chatService.userCommands[k]
      fn()
    }
    for (k in chatService.HooksInterface) {
      var fn = chatService.HooksInterface[k]
      fn()
    }
    return process.nextTick(done)
  }
  )
}
