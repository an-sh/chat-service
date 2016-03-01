
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
  bindTE
  extend
  withEH
  withoutData
}
