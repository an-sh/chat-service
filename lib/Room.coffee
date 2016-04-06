
ChatServiceError = require './ChatServiceError.coffee'
Promise = require 'bluebird'

{ extend, asyncLimit } = require './utils.coffee'

# @private
# @mixin
# @nodoc
#
# Implements room messaging permissions checks.  Required existence of
# userName, roomState and in extented classes.
RoomPermissions =

  # @private
  isAdmin : (userName) ->
    @roomState.ownerGet()
    .then (owner) =>
      if owner == userName then return true
      @roomState.hasInList 'adminlist', userName

  # @private
  hasRemoveChangedCurrentAccess : (userName, listName) ->
    @roomState.hasInList 'userlist', userName
    .then (hasUser) =>
      unless hasUser then return false
      @isAdmin userName
      .then (admin) =>
        if admin or listName != 'whitelist'
          false
        else
          @roomState.whitelistOnlyGet()
    .catch (e) =>
      @consistencyFailure e, { userName, op : 'roomAccessCheck' }

  # @private
  hasAddChangedCurrentAccess : (userName, listName) ->
    @roomState.hasInList 'userlist', userName
    .then (hasUser) =>
      unless hasUser then return false
      @isAdmin userName
      .then (admin) ->
        if admin or listName != 'blacklist'
          false
        else
          true
    .catch (e) =>
      @consistencyFailure e, { userName, op : 'roomAccessCheck' }

  # @private
  getModeChangedCurrentAccess : (value) ->
    unless value
      []
    else
      @roomState.getCommonUsers()

  # @private
  checkListChanges : (author, listName, values, bypassPermissions) ->
    @roomState.ownerGet()
    .then (owner) =>
      if listName == 'userlist'
        return Promise.reject new ChatServiceError 'notAllowed'
      if author == owner or bypassPermissions
        return
      if listName == 'adminlist'
        return Promise.reject new ChatServiceError 'notAllowed'
      @roomState.hasInList 'adminlist', author
      .then (admin) ->
        unless admin
          return Promise.reject new ChatServiceError 'notAllowed'
        for name in values
          if name == owner
            return Promise.reject new ChatServiceError 'notAllowed'
        return

  # @private
  checkModeChange : (author, value, bypassPermissions) ->
    @isAdmin author
    .then (admin) ->
      unless admin or bypassPermissions
        Promise.reject new ChatServiceError 'notAllowed'

  # @private
  checkAcess : (userName) ->
    @isAdmin userName
    .then (admin) =>
      if admin then return
      @roomState.hasInList 'blacklist', userName
      .then (blacklisted) =>
        if blacklisted
          return Promise.reject new ChatServiceError 'notAllowed'
        @roomState.whitelistOnlyGet()
        .then (whitelistOnly) =>
          unless whitelistOnly then return
          @roomState.hasInList 'whitelist', userName
          .then (whitelisted) ->
            unless whitelisted
              return Promise.reject new ChatServiceError 'notAllowed'

  # @private
  checkRead : (author, bypassPermissions) ->
    if bypassPermissions then return Promise.resolve()
    @isAdmin author
    .then (admin) =>
      if admin then return
      @roomState.hasInList 'userlist', author
      .then (hasAuthor) =>
        unless hasAuthor
          Promise.reject new ChatServiceError 'notJoined', @name


# @private
# @nodoc
#
# @extend RoomPermissions
# Implements room messaging state manipulations with the respect to
# user's permissions.
class Room

  extend @, RoomPermissions

  # @private
  constructor : (@server, @name) ->
    State = @server.state.RoomState
    @roomState = new State @server, @name

  # @private
  initState : (state) ->
    @roomState.initState state

  # @private
  removeState : () ->
    @roomState.removeState()

  # @private
  consistencyFailure : (error, operationInfo = {}) ->
    operationInfo.roomName = @name
    @server.emit 'consistencyFailure', error, operationInfo
    return

  # @private
  getUsers: () ->
    @roomState.getList 'userlist'

  # @private
  checkIsOwner : (author, bypassPermissions) ->
    if bypassPermissions then return Promise.resolve()
    @roomState.ownerGet()
    .then (owner) ->
      if owner == author then return
      Promise.reject new ChatServiceError 'notAllowed'

  # @private
  leave : (userName) ->
    @roomState.removeFromList 'userlist', [userName]

  # @private
  join : (userName) ->
    @checkAcess userName
    .then =>
      @roomState.addToList 'userlist', [userName]

  # @private
  message : (author, msg, bypassPermissions) ->
    Promise.try =>
      unless bypassPermissions
        @roomState.hasInList 'userlist', author
        .then (hasAuthor) =>
          unless hasAuthor
            Promise.reject new ChatServiceError 'notJoined', @name
    .then =>
      @roomState.messageAdd msg

  # @private
  getList : (author, listName, bypassPermissions) ->
    @checkRead author, bypassPermissions
    .then =>
      @roomState.getList listName

  # @private
  getRecentMessages : (author, bypassPermissions) ->
    @checkRead author, bypassPermissions
    .then =>
      @roomState.messagesGetRecent()

  # @private
  getMessagesLastId : (author, bypassPermissions) ->
    @checkRead author, bypassPermissions
    .then =>
      @roomState.messagesGetLastId()

  # @private
  getMessagesAfterId : (author, id, bypassPermissions) ->
    @checkRead author, bypassPermissions
    .then =>
      @roomState.messagesGetAfterId id

  # @private
  addToList : (author, listName, values, bypassPermissions) ->
    @checkListChanges author, listName, values, bypassPermissions
    .then =>
      @roomState.addToList listName, values
    .then =>
      Promise.filter values, (val) =>
        @hasAddChangedCurrentAccess val, listName
      , { concurrency : asyncLimit }

  # @private
  removeFromList : (author, listName, values, bypassPermissions) ->
    @checkListChanges author, listName, values, bypassPermissions
    .then =>
      @roomState.removeFromList listName, values
    .then =>
      Promise.filter values, (val) =>
        @hasRemoveChangedCurrentAccess val, listName
      , { concurrency : asyncLimit }

  # @private
  getMode : (author, bypassPermissions) ->
    @checkRead author, bypassPermissions
    .then =>
      @roomState.whitelistOnlyGet()

  # @private
  getOwner : (author, bypassPermissions) ->
    @checkRead author, bypassPermissions
    .then =>
      @roomState.ownerGet()

  # @private
  changeMode : (author, mode, bypassPermissions) ->
    whitelistOnly = mode
    @checkModeChange author, mode, bypassPermissions
    .then =>
      @roomState.whitelistOnlySet whitelistOnly
    .then =>
      @getModeChangedCurrentAccess whitelistOnly
    .then (usernames) ->
      [ usernames, whitelistOnly ]

  # @private
  getHistoryMaxSize : (author, bypassPermissions) ->
    @checkRead author, bypassPermissions
    .then =>
      @roomState.historyMaxSizeGet()


module.exports = Room
