
ChatServiceError = require './ChatServiceError'
Promise = require 'bluebird'

{ mix } = require './utils'


# @private
# @mixin
# @nodoc
#
# Implements direct messaging permissions checks. Required existence
# of userName, directMessagingState and in extented classes.
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
          return Promise.reject new ChatServiceError 'notAllowed'
      return

  # @private
  checkAcess : (userName, bypassPermissions) ->
    if userName == @userName
      return Promise.reject new ChatServiceError 'notAllowed'
    if bypassPermissions
      return Promise.resolve()
    @directMessagingState.hasInList 'blacklist', userName
    .then (blacklisted) =>
      if blacklisted
        return Promise.reject new ChatServiceError 'notAllowed'
      @directMessagingState.whitelistOnlyGet()
      .then (whitelistOnly) =>
        unless whitelistOnly then return
        @directMessagingState.hasInList 'whitelist', userName
        .then (whitelisted) ->
          unless whitelisted
            return Promise.reject new ChatServiceError 'notAllowed'


# @private
# @nodoc
#
# @extend DirectMessagingPermissions
# Implements direct messaging state manipulations with the respect to
# user's permissions.
class DirectMessaging

  # @private
  constructor : (server, userName) ->
    @server = server
    @userName = userName
    State = @server.state.DirectMessagingState
    @directMessagingState = new State @server, @userName

  # @private
  initState : (state) ->
    @directMessagingState.initState state

  removeState : ->
    @directMessagingState.removeState()

  # @private
  message : (author, msg, bypassPermissions) ->
    @checkAcess author, bypassPermissions

  # @private
  getList : (author, listName) ->
    @checkList author, listName
    .then =>
      @directMessagingState.getList listName

  # @private
  addToList : (author, listName, values) ->
    @checkListValues author, listName, values
    .then =>
      @directMessagingState.addToList listName, values

  # @private
  removeFromList : (author, listName, values) ->
    @checkListValues author, listName, values
    .then =>
      @directMessagingState.removeFromList listName, values

  # @private
  getMode : (author) ->
    @directMessagingState.whitelistOnlyGet()

  # @private
  changeMode : (author, mode) ->
    @directMessagingState.whitelistOnlySet mode

mix DirectMessaging, DirectMessagingPermissions


module.exports = DirectMessaging
