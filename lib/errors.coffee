
util = require 'util'


# Implements error formatting.
class ErrorBuilder

  # @nodoc
  constructor : (@useRawErrorObjects, @serverErrorHook) ->

  # server errors
  errorStrings :
    badArgument : 'Bad argument %s value %s'
    wrongArgumentsCount : 'Expected %s arguments, got %s'
    nameInList : 'Name %s is already in list %s'
    noList : 'No such list %s'
    noLogin : 'No login provided'
    noNameInList : 'No such name %s in list %s'
    noRoom : 'No such room %s'
    noStateStore : 'No such state stored %s'
    noUser : 'No such user %s'
    noUserOnline : 'No such user online %s'
    noValuesSupplied : 'No values supplied'
    notAllowed : 'Action is not allowed'
    notJoined : 'Not joined to room %s'
    roomExists : 'Room %s already exists'
    serverError : 'Server error %s'
    userExists : 'User %s already exists'

  # @nodoc
  getErrorString : (code) ->
    return @errorStrings[code] || "Unknown error: #{code}"

  # Error formating.
  # @param error [string] Error id in errorStrings
  # @param args [array of objects] Error data arguments
  makeError : (error, args...) ->
    if @useRawErrorObjects
      return { name : error, args : args }
    return util.format @getErrorString(error), args...

  # Server internal errors handling.
  # @param error [object]
  handleServerError : (error) ->
    if @serverErrorHook
      @serverErrorHook error


# @nodoc
withEH = (errorCallback, normallCallback) ->
  (error, args...) ->
    if error then return errorCallback error
    normallCallback args...


# @nodoc
withErrorLog = (errorBuilder ,normallCallback) ->
  (error, args...) ->
    if error
      errorBuilder.handleServerError error
    normallCallback args...


module.exports = {
  ErrorBuilder
  withEH
  withErrorLog
}
