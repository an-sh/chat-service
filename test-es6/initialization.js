import Promise from 'bluebird'
import _ from 'lodash'
import { expect } from 'chai'
import http from 'http'
import socketIO from 'socket.io'

import { cleanup, clientConnect, closeInstance, setCustomCleanup, startService } from './testutils.coffee'

import { cleanupTimeout, port, user1, user2, user3, roomName1, roomName2, redisConnect } from './config.coffee'

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

  it('should integrate with a provided http server', function (done) {
    let app = http.createServer((req, res) => res.end())
    let chatService1 = startService({ transportOptions: { http: app } })
    app.listen(port)
    setCustomCleanup(cb => closeInstance(chatService1)
      .finally(() => Promise.fromCallback(fn => app.close(fn))
        .catchReturn()
    )
      .asCallback(cb)
    )
    socket1 = clientConnect(user1)
    return socket1.on('loginConfirmed', function (u) {
      expect(u).equal(user1)
      return done()
    }
    )
  }
  )

  it('should integrate with an existing io', function (done) {
    let io = socketIO(port)
    let chatService1 = startService({ transportOptions: { io} })
    setCustomCleanup(cb => closeInstance(chatService1)
      .finally(() => io.close())
      .asCallback(cb)
    )
    socket1 = clientConnect(user1)
    return socket1.on('loginConfirmed', function (u) {
      expect(u).equal(user1)
      return done()
    }
    )
  }
  )

  it('should spawn a new io server', function (done) {
    chatService = startService()
    socket1 = clientConnect(user1)
    return socket1.on('loginConfirmed', function (u) {
      expect(u).equal(user1)
      return done()
    }
    )
  }
  )

  it('should use a custom state constructor', function (done) {
    let MemoryState = require('../src/MemoryState')
    chatService = startService({ state: MemoryState })
    socket1 = clientConnect(user1)
    return socket1.on('loginConfirmed', function (u) {
      expect(u).equal(user1)
      return done()
    }
    )
  }
  )

  it('should use a custom transport constructor', function (done) {
    let Transport = require('../src/SocketIOTransport')
    chatService = startService({ transport: Transport })
    socket1 = clientConnect(user1)
    return socket1.on('loginConfirmed', function (u) {
      expect(u).equal(user1)
      return done()
    }
    )
  }
  )

  it('should use a custom adapter constructor', function (done) {
    let Adapter = require('socket.io-redis')
    chatService = startService({ adapter: Adapter,       adapterOptions: redisConnect }
    )
    socket1 = clientConnect(user1)
    return socket1.on('loginConfirmed', function (u) {
      expect(u).equal(user1)
      return done()
    }
    )
  }
  )

  return it('should update instance heartbeat', function (done) {
    this.timeout(4000)
    this.slow(2000)
    chatService = startService({ heartbeatRate: 500 })
    let start = _.now()
    return setTimeout(() => chatService.getInstanceHeartbeat(chatService.instanceUID)
      .then(function (ts) {
        expect(ts).within(start, start + 2000)
        return done()
      })

      , 1000)
  }
  )
}
