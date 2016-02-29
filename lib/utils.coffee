
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
withoutData = (fn) ->
  (error) -> fn error

# @private
# @nodoc
withFailLog = (log, data, cb) ->
  (error, args...) ->
    log error, data if error and log
    cb args... if cb

bindFailLog = (obj, errorsLogger) ->
  obj.withFailLog = (data, cb) -> withFailLog errorsLogger, data, cb

# @private
# @nodoc
withTE = (errorBuilder, callback, normallCallback) ->
  (error, data) ->
    if error
      callback errorBuilder.makeError 'serverError', 500
    else if normallCallback
      normallCallback data
    else
      callback error, data

# @private
# @nodoc
bindTE = (obj, errorBuilder) ->
  obj.withTE = (args...) -> withTE errorBuilder, args...


module.exports = {
  asyncLimit
  bindFailLog
  bindTE
  extend
  withEH
  withoutData
}
