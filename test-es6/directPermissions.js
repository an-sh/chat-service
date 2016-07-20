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

  it('should check user permissions', function (done) {
    let txt = 'Test message.'
    let message = { textMessage: txt }
    chatService = startService({ enableDirectMessages: true })
    socket1 = clientConnect(user1)
    return socket1.on('loginConfirmed', function () {
      socket2 = clientConnect(user2)
      return socket2.on('loginConfirmed', () => socket2.emit('directAddToList', 'blacklist', [user1]
        , function (error, data) {
          expect(error).not.ok
          expect(data).null
          return socket1.emit('directMessage', user2, message
            , function (error, data) {
              expect(error).ok
              expect(data).null
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

  it('should check user permissions in whitelist mode', function (done) {
    let txt = 'Test message.'
    let message = { textMessage: txt }
    chatService = startService({ enableDirectMessages: true })
    socket1 = clientConnect(user1)
    return socket1.on('loginConfirmed', function () {
      socket2 = clientConnect(user2)
      return socket2.on('loginConfirmed', () => socket2.emit('directAddToList', 'whitelist', [user1]
        , function (error, data) {
          expect(error).not.ok
          expect(data).null
          return socket2.emit('directSetWhitelistMode', true, function (error, data) {
            expect(error).not.ok
            expect(data).null
            return socket1.emit('directMessage', user2, message
              , function (error, data) {
                expect(error).not.ok
                expect(data.textMessage).equal(txt)
                return socket2.emit('directRemoveFromList', 'whitelist', [user1]
                  , function (error, data) {
                    expect(error).not.ok
                    expect(data).null
                    return socket1.emit('directMessage', user2, message
                      , function (error, data) {
                        expect(error).ok
                        expect(data).null
                        return done()
                      }
                    )
                  }
                )
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

  it('should allow an user to modify own lists', function (done) {
    chatService = startService({ enableDirectMessages: true })
    socket1 = clientConnect(user1)
    return socket1.on('loginConfirmed', () => socket1.emit('directAddToList', 'blacklist', [user2]
      , function (error, data) {
        expect(error).not.ok
        expect(data).null
        return socket1.emit('directGetAccessList', 'blacklist'
          , function (error, data) {
            expect(error).not.ok
            expect(data).include(user2)
            return socket1.emit('directRemoveFromList', 'blacklist', [user2]
              , function (error, data) {
                expect(error).not.ok
                expect(data).null
                return socket1.emit('directGetAccessList', 'blacklist'
                  , function (error, data) {
                    expect(error).not.ok
                    expect(data).not.include(user2)
                    return done()
                  }
                )
              }
            )
          }
        )
      }
    )

    )
  }
  )

  it('should reject to add user to own lists', function (done) {
    chatService = startService({ enableDirectMessages: true })
    socket1 = clientConnect(user1)
    return socket1.on('loginConfirmed', () => socket1.emit('directAddToList', 'blacklist', [user1]
      , function (error, data) {
        expect(error).ok
        expect(data).null
        return done()
      }
    )

    )
  }
  )

  it('should check user list names', function (done) {
    chatService = startService({ enableDirectMessages: true })
    socket1 = clientConnect(user1)
    return socket1.on('loginConfirmed', () => socket1.emit('directAddToList', 'nolist', [user2]
      , function (error, data) {
        expect(error).ok
        expect(data).null
        return done()
      }
    )

    )
  }
  )

  it('should allow duplicate adding to lists' , function (done) {
    chatService = startService({ enableDirectMessages: true })
    socket1 = clientConnect(user1)
    return socket1.on('loginConfirmed', () => socket1.emit('directAddToList', 'blacklist', [user2]
      , function (error, data) {
        expect(error).not.ok
        expect(data).null
        return socket1.emit('directAddToList', 'blacklist', [user2]
          , function (error, data) {
            expect(error).not.ok
            expect(data).null
            return done()
          }
        )
      }
    )

    )
  }
  )

  it('should allow non-existing deleting from lists' , function (done) {
    chatService = startService({ enableDirectMessages: true })
    socket1 = clientConnect(user1)
    return socket1.on('loginConfirmed', () => socket1.emit('directRemoveFromList', 'blacklist', [user2]
      , function (error, data) {
        expect(error).not.ok
        expect(data).null
        return done()
      }
    )

    )
  }
  )

  return it('should allow an user to modify own mode', function (done) {
    chatService = startService({ enableDirectMessages: true })
    socket1 = clientConnect(user1)
    return socket1.on('loginConfirmed', () => socket1.emit('directSetWhitelistMode', true, function (error, data) {
      expect(error).not.ok
      expect(data).null
      return socket1.emit('directGetWhitelistMode', function (error, data) {
        expect(error).not.ok
        expect(data).true
        return done()
      }
      )
    }
    )

    )
  }
  )
}
