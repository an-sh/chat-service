'use strict'

const ChatServiceError = require('./ChatServiceError')
const Promise = require('bluebird')
const _ = require('lodash')
const check = require('check-types')
const { execHook, possiblyCallback } = require('./utils')

// Commands arguments type and count validation.
class ArgumentsValidator {
  constructor (server) {
    this.server = server
    this.checkers = new Map()
    this.directMessagesChecker = this.server.directMessagesChecker
    this.roomMessagesChecker = this.server.roomMessagesChecker
    this.customCheckers = {
      directMessage: [null, this.directMessagesChecker],
      roomMessage: [null, this.roomMessagesChecker]
    }
    const commands = this.server.rpcRequestsNames
    for (const cmd of commands) {
      this.checkers.set(cmd, this[cmd]())
    }
  }

  checkArguments (name, ...args) {
    const [nargs, cb] = possiblyCallback(args)
    return Promise.try(() => {
      const checkers = this.checkers.get(name)
      if (!checkers) {
        const error = new ChatServiceError('noCommand', name)
        return Promise.reject(error)
      }
      const error = this.checkTypes(checkers, nargs)
      if (error) { return Promise.reject(error) }
      const customCheckers = this.customCheckers[name] || []
      return Promise.each(
        customCheckers, (checker, idx) => execHook(checker, nargs[idx])
      ).return()
    }).asCallback(cb)
  }

  getArgsCount (name) {
    const checker = this.checkers.get(name)
    return checker ? checker.length : 0
  }

  splitArguments (name, oargs) {
    const nargs = this.getArgsCount(name)
    const args = _.slice(oargs, 0, nargs)
    const restArgs = _.slice(oargs, nargs)
    return { args, restArgs }
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
      return new ChatServiceError(
        'wrongArgumentsCount', checkers.length, args.length)
    }
    for (let idx = 0; idx < checkers.length; idx++) {
      const checker = checkers[idx]
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

  roomNotificationsInfo (roomName) {
    return [
      check.string
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
