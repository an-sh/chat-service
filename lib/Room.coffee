
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
      if owner == userName then return Promise.resolve true
      @roomState.hasInList 'adminlist', userName

  # @private
  hasRemoveChangedCurrentAccess : (userName, listName) ->
    @roomState.hasInList 'userlist', userName
    .then (hasUser) =>
      unless hasUser  then return false
      @isAdmin userName
      .then (admin) =>
        if admin
          false
        else if listName == 'whitelist'
          @roomState.whitelistOnlyGet()
        else
          false
    .then (val) ->
      Promise.resolve val
    .catch (error) ->
      # TODO log
      Promise.resolve false

  # @private
  hasAddChangedCurrentAccess : (userName, listName) ->
    @roomState.hasInList 'userlist', userName
    .then (hasUser) =>
      unless hasUser
        return false
      @isAdmin userName
      .then (admin) ->
        if admin
          false
        else if listName == 'blacklist'
          true
        else
          false
    .then (val) ->
      Promise.resolve val
    .catch (error) ->
      # TODO log
      Promise.resolve false

  # @private
  getModeChangedCurrentAccess : (value) ->
    unless value
      Promise.resolve []
    else
      @roomState.getCommonUsers()

  # @private
  checkListChanges : (author, listName, values, bypassPermissions) ->
    @roomState.ownerGet()
    .then (owner) =>
      if listName == 'userlist'
        return Promise.reject new ChatServiceError 'notAllowed'
      if author == owner or bypassPermissions
        return Promise.resolve()
      if listName == 'adminlist'
        return Promise.reject new ChatServiceError 'notAllowed'
      @roomState.hasInList 'adminlist', author
      .then (admin) ->
        unless admin
          return Promise.reject new ChatServiceError 'notAllowed'
        for name in values
          if name == owner
            return Promise.reject new ChatServiceError 'notAllowed'
        Promise.resolve()

  # @private
  checkModeChange : (author, value, bypassPermissions) ->
    @isAdmin author
    .then (admin) ->
      if admin or bypassPermissions
        return Promise.resolve()
      Promise.reject new ChatServiceError 'notAllowed'

  # @private
  checkAcess : (userName) ->
    @isAdmin userName
    .then (admin) =>
      if admin then return Promise.resolve()
      @roomState.hasInList 'blacklist', userName
      .then (blacklisted) =>
        if blacklisted
          return Promise.reject new ChatServiceError 'notAllowed'
        @roomState.whitelistOnlyGet()
        .then (whitelistOnly) =>
          unless whitelistOnly then return Promise.resolve()
          @roomState.hasInList 'whitelist', userName
          .then (whitelisted) ->
            unless whitelisted
              return Promise.reject new ChatServiceError 'notAllowed'
            Promise.resolve()

  # @private
  checkRead : (author, bypassPermissions) ->
    if bypassPermissions then return Promise.resolve()
    @isAdmin author
    .then (admin) =>
      if admin then return Promise.resolve()
      @roomState.hasInList 'userlist', author
      .then (hasAuthor) =>
        if hasAuthor then return Promise.resolve()
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
  getUsers: () ->
    @roomState.getList 'userlist'

  # @private
  checkIsOwner : (author, bypassPermissions) ->
    if bypassPermissions then return Promise.resolve()
    @roomState.ownerGet()
    .then (owner) ->
      if owner == author then return Promise.resolve()
      Promise.reject new ChatServiceError 'notAllowed'

  # @private
  leave : (userName, bypassPermissions) ->
    @roomState.removeFromList 'userlist', [userName]

  # @private
  join : (userName, bypassPermissions) ->
    Promise.try =>
      unless bypassPermissions
        @checkAcess userName
    .then =>
      @roomState.addToList 'userlist', [userName]

  # @private
  message : (author, msg, bypassPermissions) ->
    Promise.try =>
      unless bypassPermissions
        @roomState.hasInList 'userlist', author
      else
        true
    .then (hasAuthor) =>
      unless hasAuthor
        return Promise.reject new ChatServiceError 'notJoined', @name
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
      Promise.resolve [ usernames, whitelistOnly ]


module.exports = Room
