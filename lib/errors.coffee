
util = require 'util'


# Implements error formatting.
class ErrorBuilder

  # @private
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

  # @private
  # @nodoc
  getErrorString : (code) ->
    return @errorStrings[code] || "Unknown error: #{code}"

  # Error formating.
  # @param error [String] Error key in {ErrorBuilder.errorStrings} object.
  # @param args [Array<Object>] Error data arguments.
  makeError : (error, args...) ->
    if @useRawErrorObjects
      return { name : error, args : args }
    return util.format @getErrorString(error), args...

  # Server internal errors handling.
  # @param error [Object]
  handleServerError : (error) ->
    if @serverErrorHook
      @serverErrorHook error


# @private
# @nodoc
withEH = (errorCallback, normallCallback) ->
  (error, args...) ->
    if error then return errorCallback error
    normallCallback args...


# @private
# @nodoc
withErrorLog = (errorBuilder, normallCallback) ->
  (error, args...) ->
    if error
      errorBuilder.handleServerError error
    normallCallback args...


# @private
# @nodoc
withTansformedError = (errorBuilder, callback, normallCallback) ->
  return (error, data) ->
    if error
      callback errorBuilder.makeError 'serverError', error
    else if normallCallback
      normallCallback data
    else
      callback error, data


module.exports = {
  ErrorBuilder
  withEH
  withErrorLog
  withTansformedError
}
