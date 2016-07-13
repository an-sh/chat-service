
import util from 'util';

// ChatService errors, that are intended to be returned to clients as a
// part of a normal service functioning. {ChatServiceError} constructor
// is available as a static member of {ChatService} class. Can be used
// to create custom error subclasses.
class ChatServiceError extends Error {

  // @property [Object] Error strings.
  errorStrings = {
    badArgument : 'Bad argument at position %d, value %j',
    invalidName : 'String %s contains invalid characters',
    invalidSocket : 'Socket %s is not connected',
    noCommand : 'No such command %s',
    noList : 'No such list %s',
    noLogin : 'No login provided',
    noRoom : 'No such room %s',
    noSocket : 'Command %s requires a valid socket',
    noUser : 'No such user %s',
    noUserOnline : 'No such user online %s',
    notAllowed : 'Action is not allowed',
    notJoined : 'Not joined to room %s',
    roomExists : 'Room %s already exists',
    timeout : 'Server operation timeout',
    userExists : 'User %s already exists',
    userOnline : 'User %s is online',
    wrongArgumentsCount : 'Expected %s arguments, got %s'
  };

  // @property [String] Error key in errorStrings.
  name = 'unknownError';

  // @property [Array<Object>] Error arguments.
  args = [];

  // @private
  // @nodoc
  constructor(name, ...args) {
    this.name = name;
    this.args = args;
  }

  // @private
  // @nodoc
  toString() {
    let str = this.errorStrings[this.name];
    if (str) {
      return util.format(`ChatServiceError: ${str}`, ...this.args);
    } else {
      return super.toString;
    }
  }
}


export default ChatServiceError;
