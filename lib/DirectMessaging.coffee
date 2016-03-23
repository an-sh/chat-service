
Promise = require 'bluebird'

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
  checkList : (author, listName) ->
    @directMessagingState.checkList listName

  # @private
  checkListValues : (author, listName, values) ->
    @checkList author, listName
    .then =>
      for name in values
        if name == @userName
          error = @errorBuilder.makeError 'notAllowed'
          return Promise.reject error
      Promise.resolve()

  # @private
  checkListAdd : (author, listName, values) ->
    @checkListValues author, listName, values

  # @private
  checkListRemove : (author, listName, values) ->
    @checkListValues author, listName, values

  # @private
  checkAcess : (userName) ->
    if userName == @userName
      error = @errorBuilder.makeError 'notAllowed'
      return Promise.reject error
    @directMessagingState.hasInList 'blacklist', userName
    .then (blacklisted) =>
      if blacklisted
        Promise.reject @errorBuilder.makeError 'notAllowed'
    .then =>
      Promise.join @directMessagingState.whitelistOnlyGet()
      , @directMessagingState.hasInList('whitelist', userName)
      , (whitelistOnly, hasInWhitelist) =>
        if whitelistOnly and not hasInWhitelist
          Promise.reject @errorBuilder.makeError 'notAllowed'
        else
          Promise.resolve()


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
  initState : (state) ->
    @directMessagingState.initState state

  # @private
  message : (author, msg) ->
    @checkAcess author

  # @private
  getList : (author, listName) ->
    @checkList author, listName
    .then =>
      @directMessagingState.getList listName

  # @private
  addToList : (author, listName, values) ->
    @checkListAdd author, listName, values
    .then =>
      @directMessagingState.addToList listName, values

  # @private
  removeFromList : (author, listName, values) ->
    @checkListRemove author, listName, values
    .then =>
      @directMessagingState.removeFromList listName, values

  # @private
  getMode : (author) ->
    @directMessagingState.whitelistOnlyGet()

  # @private
  changeMode : (author, mode) ->
    m = if mode then true else false
    @directMessagingState.whitelistOnlySet m


module.exports = DirectMessaging
