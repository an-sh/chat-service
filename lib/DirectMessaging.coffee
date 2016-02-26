
{ withEH, extend } = require './utils.coffee'


# @private
# @mixin
# @nodoc
#
# Implements direct messaging permissions checks.
# Required existence of username, directMessagingState and
# errorBuilder in extented classes.
DirectMessagingPermissions =

  # @private
  checkList : (author, listName, cb) ->
    unless @directMessagingState.hasList listName
      error = @errorBuilder.makeError 'noList', listName
    process.nextTick -> cb error

  # @private
  checkListValues : (author, listName, values, cb) ->
    @checkList author, listName, withEH cb, =>
      for name in values
        if name == @username
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
    if userName == @username
      return process.nextTick => cb @errorBuilder.makeError 'notAllowed'
    @directMessagingState.hasInList 'blacklist', userName
    , withEH cb, (blacklisted) =>
      if blacklisted
        return cb @errorBuilder.makeError 'notAllowed'
      @directMessagingState.whitelistOnlyGet withEH cb, (whitelistOnly) =>
        @directMessagingState.hasInList 'whitelist', userName
        , withEH cb, (hasInWhitelist) =>
          if whitelistOnly and not hasInWhitelist
            return cb @errorBuilder.makeError 'notAllowed'
          cb()


# @private
# @nodoc
#
# @extend DirectMessagingPermissions
# Implements direct messaging state manipulations with the respect to
# user's permissions.
class DirectMessaging

  extend @, DirectMessagingPermissions

  # @private
  constructor : (@server, @username) ->
    @errorBuilder = @server.errorBuilder
    State = @server.state.DirectMessagingState
    @directMessagingState = new State @server, @username

  # @private
  initState : (state, cb) ->
    @directMessagingState.initState state, cb

  # @private
  removeState : (cb) ->
    @directMessagingState.removeState cb

  # @private
  message : (author, msg, cb) ->
    @checkAcess author, cb

  # @private
  getList : (author, listName, cb) ->
    @checkList author, listName, withEH cb, =>
      @directMessagingState.getList listName, cb

  # @private
  addToList : (author, listName, values, cb) ->
    @checkListAdd author, listName, values, withEH cb, =>
      @directMessagingState.addToList listName, values, cb

  # @private
  removeFromList : (author, listName, values, cb) ->
    @checkListRemove author, listName, values, withEH cb, =>
      @directMessagingState.removeFromList listName, values, cb

  # @private
  getMode : (author, cb) ->
    @directMessagingState.whitelistOnlyGet cb

  # @private
  changeMode : (author, mode, cb) ->
    m = if mode then true else false
    @directMessagingState.whitelistOnlySet m, cb


module.exports = DirectMessaging
