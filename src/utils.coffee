
ChatServiceError = require './ChatServiceError'
Promise = require 'bluebird'
_ = require 'lodash'
util = require 'util'

# @private
# @nodoc
debuglog = util.debuglog 'ChatService'

# @private
# @nodoc
asyncLimit = 32

# @private
# @nodoc
nameChecker = /^[^\u0000-\u001F:{}\u007F]+$/

# @private
# @nodoc
extend = (c, mixins...) ->
  for mixin in mixins
    for name, method of mixin
      unless c::[name]
        c::[name] = method

# @private
# @nodoc
possiblyCallback = (args) ->
  cb = _.last args
  if _.isFunction cb
    args = _.slice args, 0, -1
  else
    cb = null
  [args, cb]

# @private
# @nodoc
checkNameSymbols = (name) ->
  if (_.isString(name) and nameChecker.test(name))
    Promise.resolve()
  else
    Promise.reject new ChatServiceError 'invalidName', name

# @private
# @nodoc
execHook = (hook, args...) ->
  unless hook then return Promise.resolve()
  cb = null
  callbackData = null
  wrapper = (data...) ->
    callbackData = data
    cb data... if cb
  res = hook args..., wrapper
  if callbackData
    Promise.fromCallback (fn) ->
      fn callbackData...
    , {multiArgs : true}
  else if res? and typeof res.then is 'function'
    res
  else
    Promise.fromCallback (fn) ->
      cb = fn
    , {multiArgs : true}


module.exports = {
  asyncLimit
  checkNameSymbols
  debuglog
  execHook
  extend
  nameChecker
  possiblyCallback
}
