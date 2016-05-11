
ChatServiceError = require './ChatServiceError.coffee'
Map = require 'collections/fast-map'
Promise = require 'bluebird'
_ = require 'lodash'
check = require 'check-types'

{ possiblyCallback } = require './utils.coffee'


# Commands arguments type and count validation.
class ArgumentsValidator

  # @private
  # @nodoc
  constructor : (@server) ->
    @checkers = new Map
    for name, fn of @server.userCommands
      @checkers.set name, _.bind @[name], @
    @directMessagesChecker = @server.directMessagesChecker
    @roomMessagesChecker = @server.roomMessagesChecker
    @customCheckers =
      directMessage : [ null, @directMessagesChecker ]
      roomMessage : [ null, @roomMessagesChecker ]

  # Check command arguments.
  #
  # @param name [String] Command name.
  # @param args [Rest...] Command arguments with an optional callback.
  #
  # @return [Promise]
  checkArguments : (name, args...) ->
    [args, cb] = possiblyCallback args
    Promise.try =>
      checkfn = @checkers.get name
      unless checkfn
        error = new ChatServiceError 'noCommand', name
        return Promise.reject error
      error = @checkTypes checkfn, args
      if error then return Promise.reject error
      customCheckers = @customCheckers[name] || []
      Promise.each customCheckers, (checker, idx) ->
        if checker
          Promise.fromCallback (fn) ->
            checker args[idx], fn
    .asCallback cb

  # @private
  # @nodoc
  getArgsCount : (name) ->
    checkfn = @checkers.get name
    unless checkfn then return 0
    return checkfn().length || 0

  # @private
  # @nodoc
  splitArguments : (name, oargs) ->
    nargs = @getArgsCount name
    args = _.slice oargs, 0, nargs
    restArgs = _.slice oargs, nargs
    { args, restArgs }

  # @private
  # @nodoc
  checkMessage : (msg) ->
    passed = check.object msg
    unless passed then return false
    passed = check.string msg.textMessage
    unless passed then return false
    _.keys(msg).length == 1

  # @private
  # @nodoc
  checkObject : (obj) ->
    check.object obj

  # @private
  # @nodoc
  checkTypes : (checkfn, args) ->
    checkers = checkfn()
    if args?.length != checkers.length
      return new ChatServiceError 'wrongArgumentsCount'
      , checkers.length, args.length
    for checker, idx in checkers
      unless checker args[idx]
        return new ChatServiceError 'badArgument', idx, args[idx]
    return null

  # @private
  # @nodoc
  directAddToList : (listName, userNames) ->
    [
      check.string
      check.array.of.string
    ]

  # @private
  # @nodoc
  directGetAccessList : (listName) ->
    [
      check.string
    ]

  # @private
  # @nodoc
  directGetWhitelistMode : () ->
    []

  # @private
  # @nodoc
  directMessage : (toUser, msg) ->
    [
      check.string
      if @directMessagesChecker then @checkObject else @checkMessage
    ]

  # @private
  # @nodoc
  directRemoveFromList : (listName, userNames) ->
    [
      check.string
      check.array.of.string
    ]

  # @private
  # @nodoc
  directSetWhitelistMode : (mode) ->
    [
      check.boolean
    ]

  # @private
  # @nodoc
  disconnect : (reason) ->
    [
      check.string
    ]

  # @private
  # @nodoc
  listOwnSockets : () ->
    []

  # @private
  # @nodoc
  roomAddToList : (roomName, listName, userNames) ->
    [
      check.string
      check.string
      check.array.of.string
    ]

  # @private
  # @nodoc
  roomCreate : (roomName, mode) ->
    [
      check.string
      check.boolean
    ]

  # @private
  # @nodoc
  roomDelete : (roomName) ->
    [
      check.string
    ]

  # @private
  # @nodoc
  roomGetAccessList : (roomName, listName) ->
    [
      check.string
      check.string
    ]

  # @private
  # @nodoc
  roomGetOwner : (roomName) ->
    [
      check.string
    ]

  # @private
  # @nodoc
  roomGetWhitelistMode : (roomName) ->
    [
      check.string
    ]

  # @private
  # @nodoc
  roomRecentHistory : (roomName)->
    [
      check.string
    ]

  # @private
  # @nodoc
  roomHistoryGet : (roomName, id, limit) ->
    [
      check.string
      (str) -> check.greaterOrEqual str, 0
      (str) -> check.greaterOrEqual str, 1
    ]

  # @private
  # @nodoc
  roomHistoryInfo : (roomName) ->
    [
      check.string
    ]

  # @private
  # @nodoc
  roomJoin : (roomName) ->
    [
      check.string
    ]

  # @private
  # @nodoc
  roomLeave : (roomName) ->
    [
      check.string
    ]

  # @private
  # @nodoc
  roomMessage : (roomName, msg) ->
    [
      check.string
      if @roomMessagesChecker then @checkObject else @checkMessage
    ]

  # @private
  # @nodoc
  roomRemoveFromList : (roomName, listName, userNames) ->
    [
      check.string
      check.string
      check.array.of.string
    ]

  # @private
  # @nodoc
  roomSetWhitelistMode : (roomName, mode) ->
    [
      check.string
      check.boolean
    ]

  # @private
  # @nodoc
  roomUserSeen : (roomName, userName) ->
    [
      check.string
      check.string
    ]

  # @private
  # @nodoc
  systemMessage : (data) ->
    [
      -> true
    ]


module.exports = ArgumentsValidator
