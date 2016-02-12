
util = require 'util'

# @private
# @nodoc
asyncLimit = 16

# @private
# @nodoc
extend = (c, mixins...) ->
  for mixin in mixins
    for name, method of mixin
      unless c::[name]
        c::[name] = method
  return

# Implements error formatting.
class ErrorBuilder

  # @private
  # @nodoc
  constructor : (@useRawErrorObjects) ->

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
  # @param args [Arguments<Object>] Error data arguments.
  # @return [String or Object] Formatted error, according to a
  #   {ChatService} `useRawErrorObjects` option.
  makeError : (error, args...) ->
    if @useRawErrorObjects
      return { name : error, args : args }
    return util.format @getErrorString(error), args...


# @private
# @nodoc
withEH = (errorCallback, normallCallback) ->
  (error, args...) ->
    if error then return errorCallback error
    normallCallback args...

# @private
# @nodoc
withTE = (errorBuilder, callback, normallCallback) ->
  return (error, data) ->
    if error
      callback errorBuilder.makeError 'serverError', 500
    else if normallCallback
      normallCallback data
    else
      callback error, data


# @private
# @nodoc
bindTE = (obj) ->
  obj.withTE = (args...) -> withTE obj.errorBuilder, args...


# @private
# @nodoc
bindUnlock = (lock, cb) ->
  return (args...) ->
    lock.unlock()
    cb args...

module.exports = {
  ErrorBuilder
  asyncLimit
  bindTE
  bindUnlock
  extend
  withEH
}