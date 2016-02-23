
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

withoutData = (fn) ->
  (error) -> fn error

module.exports = {
  asyncLimit
  bindTE
  bindUnlock
  extend
  withEH
  withoutData
}
