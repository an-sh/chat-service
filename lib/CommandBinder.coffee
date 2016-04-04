
ChatServiceError = require './ChatServiceError.coffee'
Promise = require 'bluebird'
_ = require 'lodash'

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
    (oargs..., info = {}, cb) =>
      args = oargs
      ack = @bindAck cb if cb
      callInfo = { @server, @userName }
      callInfo.id = info.id || null
      callInfo.bypassPermissions = info.bypassPermissions || false
      callInfo.bypassHooks = info.bypassHooks || false
      Promise.using @commandWatcher(info.id, name), (stop) ->
        if stop then return
        validator.checkArguments name, args...
        .then ->
          if beforeHook and not callInfo.bypassHooks
            Promise.fromCallback (cb) ->
              beforeHook callInfo, args, ensureMultipleArguments cb
            , {multiArgs: true}
        .then (results = []) ->
          [data, nargs...] = results
          if data then return data
          Promise.try ->
            if nargs?.length
              args = nargs
              validator.checkArguments name, args...
          .then ->
            fn.apply self, [args..., info]
          .then (data) ->
            [ null, data ]
          .catch (error) ->
            [error, null]
          .spread (error, data) ->
            if afterHook and not callInfo.bypassHooks
              Promise.fromCallback (cb) ->
                results = [error, data]
                afterHook callInfo, args, results, ensureMultipleArguments cb
              , {multiArgs: true}
            else if error
              Promise.reject error
            else
              [ data ]
      .asCallback ack, { spread : true }

  # @private
  bindCommand : (id, name, fn) ->
    cmd = @makeCommand name, fn
    info = { id : id }
    @transport.bind id, name, ->
      [args, cb] = possiblyCallback arguments
      cmd args..., info, cb


module.exports = CommandBinder
