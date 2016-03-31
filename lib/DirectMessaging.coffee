
ChatServiceError = require './ChatServiceError.coffee'
Promise = require 'bluebird'

{ extend } = require './utils.coffee'


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
      return Promise.reject new ChatServiceError 'notAllowed'
    @directMessagingState.hasInList 'blacklist', userName
    .then (blacklisted) =>
      if blacklisted
        return Promise.reject new ChatServiceError 'notAllowed'
      @directMessagingState.whitelistOnlyGet()
      .then (whitelistOnly) =>
        unless whitelistOnly then return Promise.resolve()
        @directMessagingState.hasInList 'whitelist', userName
        .then (whitelisted) ->
          if whitelisted
            Promise.resolve()
          else
            Promise.reject new ChatServiceError 'notAllowed'


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
