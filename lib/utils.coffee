
ChatServiceError = require './ChatServiceError.coffee'
Promise = require 'bluebird'
_ = require 'lodash'


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
ensureMultipleArguments = (cb) ->
  (error, data...) ->
    cb error, data...


module.exports = {
  asyncLimit
  checkNameSymbols
  ensureMultipleArguments
  extend
  nameChecker
  possiblyCallback
}
