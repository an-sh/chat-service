
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
    errorBuilder = @server.errorBuilder
    cmd = (oargs..., cb, id) =>
      validator = @server.validator
      transport = @server.transport
      beforeHook = @server.hooks?["#{name}Before"]
      afterHook = @server.hooks?["#{name}After"]
      execCommand = (error, data, nargs...) =>
        if error or data
          return cb error, data
        args = if nargs.length then nargs else oargs
        if args.length != oargs.length
          return cb errorBuilder.makeError 'serverError', 'hook nargs error.'
        afterCommand = (error, data) =>
          reportResults = (nerror = error, ndata = data, moredata...) ->
            if name == 'disconnect'
              transport.endClientDisconnect()
            cb nerror, ndata, moredata...
          if afterHook
            results = _.slice arguments
            afterHook @server, @userName, id, args, results, reportResults
          else
            reportResults()
        fn.apply @, [ args..., afterCommand, id ]
      validator.checkArguments name, oargs..., (errors) =>
        if errors
          return cb errorBuilder.makeError errors...
        unless beforeHook
          execCommand()
        else
          beforeHook @server, @userName, id, oargs, execCommand
    return cmd

  # @private
  bindAck : (cb) ->
    (error, data, rest...) ->
      error = null unless error?
      data = null unless data?
      cb error, data, rest... if cb

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
      cmd args..., ack, id


module.exports = CommandBinder
