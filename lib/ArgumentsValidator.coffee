
Map = require 'collections/fast-map'
_ = require 'lodash'
async = require 'async'
check = require 'check-types'
{ asyncLimit } = require './utils.coffee'


# @private
# @nodoc
# Commands arguments type and count validation functions.
class ArgumentsValidator

  constructor : (@server) ->
    @checkers = new Map
    for name, fn of @server.userCommands
      @checkers.set name, _.bind @[name], @
    @directMessageChecker = @server.directMessageChecker
    @roomMessageChecker = @server.roomMessageChecker
    @customCheckers =
      directMessage : [ null, @directMessageChecker ]
      roomMessage : [ null, @roomMessageChecker ]

  # @private
  checkArguments : (name, args, cb) ->
    checkers = @checkers.get(name)()
    error = @checkTypes checkers, args
    if error
      return process.nextTick -> cb error
    customCheckers = @customCheckers[name]
    if customCheckers
      async.forEachOfLimit customCheckers, asyncLimit
      , (checker, idx, fn) ->
        unless checker then return fn()
        checker args[idx], fn
      , cb
    else
      process.nextTick -> cb()

  # @private
  checkMessage : (msg) ->
    passed = check.object msg
    unless passed then return false
    passed = check.string msg.textMessage
    unless passed then return false
    _.keys(msg).length == 1

  # @private
  checkObject : (obj) ->
    check.object obj

  # @private
  checkTypes : (checkers, args) ->
    if args.length != checkers.length
      return [ 'wrongArgumentsCount', checkers.length, args.length ]
    for checker, idx in checkers
      unless checker args[idx]
        return [ 'badArgument', idx, args[idx] ]
    return null

  # @private
  directAddToList : (listName, usernames) ->
    [
      check.string
      check.array.of.string
    ]

  # @private
  directGetAccessList : (listName) ->
    [
      check.string
    ]

  # @private
  directGetWhitelistMode : () ->
    []

  # @private
  directMessage : (toUser, msg) ->
    [
      check.string
      if @directMessageChecker then @checkObject else @checkMessage
    ]

  # @private
  directRemoveFromList : (listName, usernames) ->
    [
      check.string
      check.array.of.string
    ]

  # @private
  directSetWhitelistMode : (mode) ->
    [
      check.boolean
    ]

  # @private
  disconnect : (reason) ->
    [
      check.string
    ]

  # @private
  listJoinedSockets : () ->
    []

  # @private
  listRooms : () ->
    []

  # @private
  roomAddToList : (roomName, listName, usernames) ->
    [
      check.string
      check.string
      check.array.of.string
    ]

  # @private
  roomCreate : (roomName, mode) ->
    [
      check.string
      check.boolean
    ]

  # @private
  roomDelete : (roomName) ->
    [
      check.string
    ]

  # @private
  roomGetAccessList : (roomName, listName) ->
    [
      check.string
      check.string
    ]

  # @private
  roomGetOwner : (roomName) ->
    [
      check.string
    ]

  # @private
  roomGetWhitelistMode : (roomName) ->
    [
      check.string
    ]

  # @private
  roomHistory : (roomName)->
    [
      check.string
    ]

  # @private
  roomJoin : (roomName) ->
    [
      check.string
    ]

  # @private
  roomLeave : (roomName) ->
    [
      check.string
    ]

  # @private
  roomMessage : (roomName, msg) ->
    [
      check.string
      if @roomMessageChecker then @checkObject else @checkMessage
    ]

  # @private
  roomRemoveFromList : (roomName, listName, usernames) ->
    [
      check.string
      check.string
      check.array.of.string
    ]

  # @private
  roomSetWhitelistMode : (roomName, mode) ->
    [
      check.string
      check.boolean
    ]


module.exports = ArgumentsValidator
