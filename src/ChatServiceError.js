'use strict'

const util = require('util')

function ChatServiceError (code, ...args) {
  this.name = 'ChatServiceError'
  this.code = code
  this.args = args
}

// pretend to be an error
ChatServiceError.prototype = Object.create(Error.prototype)

/**
 * @constant
 * @default
 * @memberof rpc.datatypes
 */
const codeToFormat = {
  badArgument: 'Bad argument at position %d, value %j',
  internalError: '%s',
  invalidName: 'String %s contains invalid characters',
  invalidSocket: 'Socket %s is not connected',
  noCommand: 'No such command %s',
  listLimitExceeded: 'Exceeded %s size limit',
  noList: 'No such list %s',
  noLogin: 'No login provided',
  noRoom: 'No such room %s',
  noSocket: 'Command %s requires a valid socket',
  noUser: 'No such user %s',
  noUserOnline: 'No such user online %s',
  notAllowed: 'Action is not allowed',
  notJoined: 'Not joined to room %s',
  roomExists: 'Room %s already exists',
  timeout: 'Server operation timeout',
  userExists: 'User %s already exists',
  userOnline: 'User %s is online',
  wrongArgumentsCount: 'Expected %s arguments, got %s'
}

ChatServiceError.prototype.codeToFormat = codeToFormat

ChatServiceError.prototype.toString = function () {
  const str = this.codeToFormat[this.code]
  if (str) {
    return util.format(`ChatServiceError: ${str}`, ...this.args)
  } else {
    return util.format(`ChatServiceError: ${this.code}`)
  }
}

module.exports = ChatServiceError
