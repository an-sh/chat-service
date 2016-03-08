
util = require 'util'

# Implements errors formatting.
class ErrorBuilder

  # @private
  # @nodoc
  constructor : (@useRawErrorObjects) ->

  errorStrings:
    badArgument : 'Bad argument %s value %s'
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
    serverBusy : 'Server is busy with processing a concurrent command'
    serverError : 'Server error %s'
    unknownError : 'Unknown error %s occurred'
    userExists : 'User %s already exists'
    wrongArgumentsCount : 'Expected %s arguments, got %s'

  # Errors formatting.
  # @param error [String] Error key in {ErrorBuilder.errorStrings} object.
  # @param args [Arguments<Object>] Error data arguments.
  # @return [String or Object] Formatted error string or an object
  #   with an error as key and the description string as a value,
  #   according to a {ChatService} `useRawErrorObjects` option.
  makeError : (error, args...) ->
    if @useRawErrorObjects
      return { name : error, args : args }
    str = @errorStrings[error] || @errorStrings.unknownError
    return util.format error, args...


module.exports = ErrorBuilder
