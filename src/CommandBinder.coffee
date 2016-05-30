
ChatServiceError = require './ChatServiceError'
Promise = require 'bluebird'
_ = require 'lodash'
ExecInfo = require './ExecInfo'

{ possiblyCallback } = require './utils'


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
      # if process.env.BLUEBIRD_DEBUG
      #   if error and not (error instanceof ChatServiceError)
      #     console.error error.stack || error.toString?() || error
      error = null unless error?
      data = null unless data?
      unless useRawErrorObjects
        error = error?.toString?()
      cb error, data, rest...

  # @private
  commandWatcher : (id, name) ->
    @server.runningCommands++
    Promise.resolve().disposer =>
      @server.runningCommands--
      if @transport.closed and @server.runningCommands <= 0
        @server.emit 'commandsFinished'

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
        validator.checkArguments name, execInfo.args...
        .then ->
          if beforeHook and not execInfo.bypassHooks
            Promise.fromCallback (cb) ->
              beforeHook execInfo, cb
            , {multiArgs: true}
        .then (results) ->
          if results?.length then return results
          fn.apply self, [execInfo.args..., execInfo]
          .then (result) ->
            execInfo.results = [result]
          , (error) ->
            execInfo.error = error
          .then ->
            if afterHook and not execInfo.bypassHooks
              Promise.fromCallback (cb) ->
                afterHook execInfo, cb
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
    @transport.bindHandler id, name, ->
      [args, cb] = possiblyCallback arguments
      cmd args..., info, cb


module.exports = CommandBinder
