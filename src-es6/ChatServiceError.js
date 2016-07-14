
const util = require('util')

// ChatService errors, that are intended to be returned to clients as a
// part of a normal service functioning. {ChatServiceError} constructor
// is available as a static member of {ChatService} class. Can be used
// to create custom error subclasses.

// @private
// @nodoc
function ChatServiceError (name, ...args) {
  this.name = name
  this.args = args
}

util.inherits(ChatServiceError, Error)

// @property [Object] Error strings.
ChatServiceError.prototype.errorStrings = {
  badArgument: 'Bad argument at position %d, value %j',
  invalidName: 'String %s contains invalid characters',
  invalidSocket: 'Socket %s is not connected',
  noCommand: 'No such command %s',
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

// @private
// @nodoc
ChatServiceError.prototype.toString = function () {
  let str = this.errorStrings[this.name]
  if (str) {
    return util.format(`ChatServiceError: ${str}`, ...this.args)
  } else {
    return this.name
  }
}

module.exports = ChatServiceError
