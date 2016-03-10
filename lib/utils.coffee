
_ = require 'lodash'

# @private
# @nodoc
asyncLimit = 32

# @private
# @nodoc
extend = (c, mixins...) ->
  for mixin in mixins
    for name, method of mixin
      unless c::[name]
        c::[name] = method

# @private
# @nodoc
withEH = (errorCallback, normallCallback) ->
  (error, args...) ->
    if error then return errorCallback error
    normallCallback args...

# @private
# @nodoc
bindTE = (obj) ->
  obj.withTE = (callback) ->
    (error, data) ->
      if error
        callback obj.errorBuilder.makeError 'serverError', 500
      else
        callback error, data

# @private
# @nodoc
withoutData = (fn) ->
  (error) -> fn error

# @private
# @nodoc
nameChecker = /^[^\u0000-\u001F:{}\u007F]+$/

# @private
# @nodoc
checkNameSymbols = (name) ->
  not (_.isString(name) and nameChecker.test(name))

module.exports = {
  asyncLimit
  bindTE
  checkNameSymbols
  extend
  withEH
  withoutData
}
