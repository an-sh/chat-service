
ChatServiceError = require './ChatServiceError.coffee'
Promise = require 'bluebird'
_ = require 'lodash'
ExecInfo = require './ExecInfo.coffee'

{ ensureMultipleArguments, possiblyCallback } = require './utils.coffee'


# @private
# @mixin
# @nodoc
#
# Implements command implementation functions binding and wrapping.
# Required existence of server in extented classes.
CommandBinder =

  # @private
  bindAck : (cb) ->
    useRawErrorObjects = @server.useRawErrorObjects
    (error, data, rest...) ->
      error = null unless error?
      data = null unless data?
      unless useRawErrorObjects
        error = error?.toString()
      cb error, data, rest...

  # @private
  commandWatcher : (id, name) ->
    if name == 'disconnect'
      wasDisconnecting = @transport.startClientDisconnect id
      unless wasDisconnecting
        Promise.resolve(wasDisconnecting).disposer =>
          @transport.endClientDisconnect id
      else
        Promise.resolve(wasDisconnecting)

  # @private
  makeCommand : (name, fn) ->
    self = @
    validator = @server.validator
    beforeHook = @server.hooks?["#{name}Before"]
    afterHook = @server.hooks?["#{name}After"]
    (args..., info = {}, cb) =>
      ack = @bindAck cb if cb
      execInfo = new ExecInfo
      _.assignIn execInfo, { @server, @userName }
      _.assignIn execInfo, info
      _.assignIn execInfo, validator.splitArguments name, args
      Promise.using @commandWatcher(info.id, name), (stop) ->
        if stop then return []
        validator.checkArguments name, execInfo.args...
        .then ->
          if beforeHook and not execInfo.bypassHooks
            Promise.fromCallback (cb) ->
              beforeHook execInfo, ensureMultipleArguments cb
            , {multiArgs: true}
        .then (results) ->
          if results?.length then return results
          fn.apply self, [execInfo.args..., execInfo]
          .then (result) ->
            execInfo.results = [result]
          .catch (error) ->
            execInfo.error = error
          .then ->
            if afterHook and not execInfo.bypassHooks
              Promise.fromCallback (cb) ->
                afterHook execInfo, ensureMultipleArguments cb
              , {multiArgs: true}
          .then (results) ->
            if results?.length
              results
            else if execInfo.error
              Promise.reject execInfo.error
            else
              execInfo.results
      .asCallback ack, { spread : true }

  # @private
  bindCommand : (id, name, fn) ->
    cmd = @makeCommand name, fn
    info = { id : id }
    @transport.bind id, name, ->
      [args, cb] = possiblyCallback arguments
      cmd args..., info, cb


module.exports = CommandBinder
