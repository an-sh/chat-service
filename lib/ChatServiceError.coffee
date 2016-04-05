
util = require 'util'

# ChatService errors.
class ChatServiceError extends Error

  # @property [Object] Error strings.
  @::errorStrings =
    badArgument : 'Bad argument %s value %j'
    invalidName : 'String %s contains invalid characters'
    noCommand : 'No such command %s'
    noList : 'No such list %s'
    noLogin : 'No login provided'
    noRoom : 'No such room %s'
    noSocket : 'Command %s requires a valid socket'
    noUser : 'No such user %s'
    noUserOnline : 'No such user online %s'
    notAllowed : 'Action is not allowed'
    notJoined : 'Not joined to room %s'
    roomExists : 'Room %s already exists'
    serverError : 'Server error %s'
    unknownError : 'Unknown error %s occurred'
    userExists : 'User %s already exists'
    wrongArgumentsCount : 'Expected %s arguments, got %s'

  # @property [String] Error key in errorStrings.
  name: 'unknownError'

  # @property [Array<Objects>] Error arguments.
  args: []

  # @private
  # @nodoc
  constructor : (@name, @args...) ->

  # @private
  # @nodoc
  toString : () ->
    str = @errorStrings[@name] || @name.unknownError
    util.format "ChatServiceError: #{str}", @args...


module.exports = ChatServiceError
