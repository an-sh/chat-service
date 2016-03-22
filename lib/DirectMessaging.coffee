
{ withEH, extend } = require './utils.coffee'


# @private
# @mixin
# @nodoc
#
# Implements direct messaging permissions checks.
# Required existence of userName, directMessagingState and
# errorBuilder in extented classes.
DirectMessagingPermissions =

  # @private
  checkList : (author, listName, cb) ->
    @directMessagingState.checkList listName
    .then (data) ->
      cb null, data
    , cb

  # @private
  checkListValues : (author, listName, values, cb) ->
    @checkList author, listName, withEH cb, =>
      for name in values
        if name == @userName
          return cb @errorBuilder.makeError 'notAllowed'
      cb()

  # @private
  checkListAdd : (author, listName, values, cb) ->
    @checkListValues author, listName, values, cb

  # @private
  checkListRemove : (author, listName, values, cb) ->
    @checkListValues author, listName, values, cb

  # @private
  checkAcess : (userName, cb) ->
    if userName == @userName
      return process.nextTick => cb @errorBuilder.makeError 'notAllowed'
    @directMessagingState.hasInList 'blacklist', userName
    .then (blacklisted) =>
      if blacklisted
        return cb @errorBuilder.makeError 'notAllowed'
      @directMessagingState.whitelistOnlyGet()
      .then (whitelistOnly) =>
        @directMessagingState.hasInList 'whitelist', userName
        .then (hasInWhitelist) =>
          if whitelistOnly and not hasInWhitelist
            return cb @errorBuilder.makeError 'notAllowed'
          cb()
        , cb
      , cb
    , cb


# @private
# @nodoc
#
# @extend DirectMessagingPermissions
# Implements direct messaging state manipulations with the respect to
# user's permissions.
class DirectMessaging

  extend @, DirectMessagingPermissions

  # @private
  constructor : (@server, @userName) ->
    @errorBuilder = @server.errorBuilder
    State = @server.state.DirectMessagingState
    @directMessagingState = new State @server, @userName

  # @private
  initState : (state, cb) ->
    @directMessagingState.initState state, cb

  # @private
  message : (author, msg, cb) ->
    @checkAcess author, cb

  # @private
  getList : (author, listName, cb) ->
    @checkList author, listName, withEH cb, =>
      @directMessagingState.getList listName
      .then (data) ->
        cb null, data
      , cb

  # @private
  addToList : (author, listName, values, cb) ->
    @checkListAdd author, listName, values, withEH cb, =>
      @directMessagingState.addToList listName, values
      .then (data) ->
        cb null, data
      , cb

  # @private
  removeFromList : (author, listName, values, cb) ->
    @checkListRemove author, listName, values, withEH cb, =>
      @directMessagingState.removeFromList listName, values
      .then (data) ->
        cb null, data
      , cb

  # @private
  getMode : (author, cb) ->
    @directMessagingState.whitelistOnlyGet()
    .then (data) ->
      cb null, data
    , cb

  # @private
  changeMode : (author, mode, cb) ->
    m = if mode then true else false
    @directMessagingState.whitelistOnlySet m
    .then (data) ->
      cb null, data
    , cb


module.exports = DirectMessaging
