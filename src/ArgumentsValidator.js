
const ChatServiceError = require('./ChatServiceError')
const FastMap = require('collections/fast-map')
const Promise = require('bluebird')
const _ = require('lodash')
const check = require('check-types')
const { possiblyCallback } = require('./utils')

// Commands arguments type and count validation.
class ArgumentsValidator {

  constructor (server) {
    this.server = server
    this.checkers = new FastMap()
    this.directMessagesChecker = this.server.directMessagesChecker
    this.roomMessagesChecker = this.server.roomMessagesChecker
    this.customCheckers = {
      directMessage: [ null, this.directMessagesChecker ],
      roomMessage: [ null, this.roomMessagesChecker ]
    }
    let commands = this.server.rpcRequestsNames
    for (let cmd of commands) {
      this.checkers.set(cmd, this[cmd]())
    }
  }

  checkArguments (name, ...args) {
    let [nargs, cb] = possiblyCallback(args)
    return Promise.try(() => {
      let checkers = this.checkers.get(name)
      if (!checkers) {
        let error = new ChatServiceError('noCommand', name)
        return Promise.reject(error)
      }
      let error = this.checkTypes(checkers, nargs)
      if (error) { return Promise.reject(error) }
      let customCheckers = this.customCheckers[name] || []
      return Promise.each(customCheckers, (checker, idx) => {
        if (checker) {
          return Promise.fromCallback(fn => checker(nargs[idx], fn))
        } else {
          return Promise.resolve()
        }
      }).return()
    }).asCallback(cb)
  }

  getArgsCount (name) {
    let checker = this.checkers.get(name)
    return checker ? checker.length : 0
  }

  splitArguments (name, oargs) {
    let nargs = this.getArgsCount(name)
    let args = _.slice(oargs, 0, nargs)
    let restArgs = _.slice(oargs, nargs)
    return {args, restArgs}
  }

  checkMessage (msg) {
    return check.object(msg) &&
      check.string(msg.textMessage) &&
      _.keys(msg).length === 1
  }

  checkObject (obj) {
    return check.object(obj)
  }

  checkTypes (checkers, args) {
    if (args.length !== checkers.length) {
      return new ChatServiceError('wrongArgumentsCount'
        , checkers.length, args.length)
    }
    for (let idx = 0; idx < checkers.length; idx++) {
      let checker = checkers[idx]
      if (!checker(args[idx])) {
        return new ChatServiceError('badArgument', idx, args[idx])
      }
    }
    return null
  }

  directAddToList (listName, userNames) {
    return [
      check.string,
      check.array.of.string
    ]
  }

  directGetAccessList (listName) {
    return [
      check.string
    ]
  }

  directGetWhitelistMode () {
    return []
  }

  directMessage (toUser, msg) {
    return [
      check.string,
      this.directMessagesChecker ? this.checkObject : this.checkMessage
    ]
  }

  directRemoveFromList (listName, userNames) {
    return [
      check.string,
      check.array.of.string
    ]
  }

  directSetWhitelistMode (mode) {
    return [
      check.boolean
    ]
  }

  listOwnSockets () {
    return []
  }

  roomAddToList (roomName, listName, userNames) {
    return [
      check.string,
      check.string,
      check.array.of.string
    ]
  }

  roomCreate (roomName, mode) {
    return [
      check.string,
      check.boolean
    ]
  }

  roomDelete (roomName) {
    return [
      check.string
    ]
  }

  roomGetAccessList (roomName, listName) {
    return [
      check.string,
      check.string
    ]
  }

  roomGetOwner (roomName) {
    return [
      check.string
    ]
  }

  roomGetWhitelistMode (roomName) {
    return [
      check.string
    ]
  }

  roomRecentHistory (roomName) {
    return [
      check.string
    ]
  }

  roomHistoryGet (roomName, id, limit) {
    return [
      check.string,
      str => check.greaterOrEqual(str, 0),
      str => check.greaterOrEqual(str, 1)
    ]
  }

  roomHistoryInfo (roomName) {
    return [
      check.string
    ]
  }

  roomJoin (roomName) {
    return [
      check.string
    ]
  }

  roomLeave (roomName) {
    return [
      check.string
    ]
  }

  roomMessage (roomName, msg) {
    return [
      check.string,
      this.roomMessagesChecker ? this.checkObject : this.checkMessage
    ]
  }

  roomRemoveFromList (roomName, listName, userNames) {
    return [
      check.string,
      check.string,
      check.array.of.string
    ]
  }

  roomSetWhitelistMode (roomName, mode) {
    return [
      check.string,
      check.boolean
    ]
  }

  roomUserSeen (roomName, userName) {
    return [
      check.string,
      check.string
    ]
  }

  systemMessage (data) {
    return [
      () => true
    ]
  }
}

module.exports = ArgumentsValidator
