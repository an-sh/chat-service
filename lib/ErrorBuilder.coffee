
util = require 'util'

# Implements error formatting.
class ErrorBuilder

  # @private
  # @nodoc
  constructor : (@useRawErrorObjects) ->

  # server errors
  errorStrings :
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
    serverError : 'Server error %s'
    userExists : 'User %s already exists'
    wrongArgumentsCount : 'Expected %s arguments, got %s'

  # @private
  # @nodoc
  getErrorString : (code) ->
    return @errorStrings[code] || "Unknown error: #{code}"

  # Error formatting.
  # @param error [String] Error key in {ErrorBuilder.errorStrings} object.
  # @param args [Arguments<Object>] Error data arguments.
  # @return [String or Object] Formatted error, according to a
  #   {ChatService} `useRawErrorObjects` option.
  makeError : (error, args...) ->
    if @useRawErrorObjects
      return { name : error, args : args }
    return util.format @getErrorString(error), args...


module.exports = ErrorBuilder
