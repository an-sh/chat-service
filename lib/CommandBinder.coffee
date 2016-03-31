
ChatServiceError = require './ChatServiceError.coffee'
_ = require 'lodash'

# @private
# @mixin
# @nodoc
#
# Implements command implementation functions binding and wrapping.
# Required existence of server in extented classes.
CommandBinder =

  # @private
  wrapCommand : (name, fn) ->
    cmd = (oargs..., id, cb) =>
      validator = @server.validator
      beforeHook = @server.hooks?["#{name}Before"]
      afterHook = @server.hooks?["#{name}After"]
      execCommand = (error, data, nargs...) =>
        if error or data
          return cb error, data
        args = if nargs.length then nargs else oargs
        if args.length != oargs.length
          return cb new ChatServiceError 'serverError', 'hook nargs error.'
        afterCommand = (error, data) =>
          reportResults = (nerror = error, ndata = data, moredata...) ->
            cb nerror, ndata, moredata...
          if afterHook
            results = _.slice arguments
            afterHook @server, @userName, id, args, results, reportResults
          else
            reportResults()
        p = fn.apply @, [ args..., id ]
        .asCallback afterCommand
      validator.checkArguments name, oargs..., (error) =>
        if error
          return cb error
        unless beforeHook
          execCommand()
        else
          beforeHook @server, @userName, id, oargs, execCommand
    return cmd

  # @private
  bindAck : (cb) ->
    (error, data, rest...) =>
      error = null unless error?
      if error and not @server.useRawErrorObjects
        error = error.toString()
      data = null unless data?
      cb error, data, rest... if cb

  # @private
  withDisconnectWatcher : (cmd, args..., id, ack) ->
    isDisconnecting = @transport.startClientDisconnect id
    unless isDisconnecting
      cmd args..., id, =>
        @transport.endClientDisconnect id
        ack()
    else
      ack()

  # @private
  bindCommand : (id, name, fn) ->
    cmd = @wrapCommand name, fn
    @transport.bind id, name, =>
      cb = _.last arguments
      if _.isFunction cb
        args = _.slice arguments, 0, -1
      else
        cb = null
        args = arguments
      ack = @bindAck cb
      if name == 'disconnect'
        @withDisconnectWatcher cmd, args..., id, ack
      else
        cmd args..., id, ack


module.exports = CommandBinder
