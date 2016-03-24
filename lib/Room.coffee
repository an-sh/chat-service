
Promise = require 'bluebird'

{ extend, asyncLimit } =
  require './utils.coffee'

# @private
# @mixin
# @nodoc
#
# Implements room messaging permissions checks.
# Required existence of userName, roomState and errorBuilder in
# extented classes.
RoomPermissions =

  # @private
  isAdmin : (userName) ->
    @roomState.ownerGet()
    .then (owner) =>
      if owner == userName
        return Promise.resolve true
      @roomState.hasInList 'adminlist', userName
      .then (hasName) ->
        if hasName
          Promise.resolve true
        else
          Promise.resolve false

  # @private
  hasRemoveChangedCurrentAccess : (userName, listName) ->
    @roomState.hasInList 'userlist', userName
    .then (hasUser) =>
      unless hasUser
        return Promise.resolve false
      @isAdmin userName
      .then (admin) =>
        if admin
          Promise.resolve false
        else if listName == 'whitelist'
          @roomState.whitelistOnlyGet().then (whitelistOnly) ->
            if whitelistOnly
              Promise.resolve true
            else
              Promise.resolve false
        else
          Promise.resolve false
    .catch (error) ->
      # TODO log
      Promise.resolve false

  # @private
  hasAddChangedCurrentAccess : (userName, listName) ->
    @roomState.hasInList 'userlist', userName
    .then (hasUser) =>
      unless hasUser
        return Promise.resolve false
      @isAdmin userName
      .then (admin) ->
        if admin
          Promise.resolve false
        else if listName == 'blacklist'
          Promise.resolve true
        else
          Promise.resolve false
    .catch (error) ->
      # TODO log
      Promise.resolve false

  # @private
  getModeChangedCurrentAccess : (value) ->
    unless value
      Promise.resolve false
    else
      @roomState.getCommonUsers()

  # @private
  checkJoinedUser : (author) ->
    @roomState.hasInList 'userlist', author
    .then (hasAuthor) =>
      unless hasAuthor
        Promise.reject @errorBuilder.makeError 'notJoined', @name
      else
        Promise.resolve()

  # @private
  checkListChanges : (author, listName, values) ->
    @checkJoinedUser author
    .then =>
      @roomState.ownerGet()
    .then (owner) =>
      if listName == 'userlist'
        return Promise.reject @errorBuilder.makeError 'notAllowed'
      if author == owner
        return Promise.resolve()
      if listName == 'adminlist'
        return Promise.reject @errorBuilder.makeError 'notAllowed'
      @roomState.hasInList 'adminlist', author
      .then (admin) =>
        unless admin
          return Promise.reject @errorBuilder.makeError 'notAllowed'
        for name in values
          if name == owner
            return Promise.reject @errorBuilder.makeError 'notAllowed'
        Promise.resolve()

  # @private
  checkListAdd : (author, listName, values) ->
    @checkListChanges author, listName, values

  # @private
  checkListRemove : (author, listName, values) ->
    @checkListChanges author, listName, values

  # @private
  checkModeChange : (author, value, cb) ->
    @isAdmin author
    .then (admin) =>
      unless admin
        Promise.reject @errorBuilder.makeError 'notAllowed'
      else
        Promise.resolve()

  # @private
  checkAcess : (userName) ->
    @isAdmin userName
    .then (admin) =>
      if admin then return Promise.resolve()
      @roomState.hasInList 'blacklist', userName
      .then (blacklisted) =>
        if blacklisted
          return Promise.reject @errorBuilder.makeError 'notAllowed'
        @roomState.whitelistOnlyGet()
        .then (whitelistOnly) =>
          unless whitelistOnly then return Promise.resolve()
          @roomState.hasInList 'whitelist', userName
          .then (whitelisted) =>
            if whitelisted
              Promise.resolve()
            else
              Promise.reject @errorBuilder.makeError 'notAllowed'

  # @private
  checkIsOwner : (author) ->
    @roomState.ownerGet().then (owner) =>
      if owner == author
        Promise.resolve()
      else
        Promise.reject @errorBuilder.makeError 'notAllowed'


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
    @errorBuilder = @server.errorBuilder
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
  leave : (userName) ->
    @roomState.removeFromList 'userlist', [userName]

  # @private
  join : (userName) ->
    @checkAcess userName
    .then =>
      @roomState.addToList 'userlist', [userName]

  # @private
  message : (author, msg) ->
    @roomState.hasInList 'userlist', author
    .then (hasAuthor) =>
      unless hasAuthor
        return Promise.reject @errorBuilder.makeError 'notJoined', @name
      @roomState.messageAdd msg

  # @private
  getList : (author, listName) ->
    @checkJoinedUser author
    .then =>
      @roomState.getList listName

  # @private
  getRecentMessages : (author) ->
    @checkJoinedUser author
    .then =>
      @roomState.messagesGetRecent()

  # @private
  getMessagesLastId : (author) ->
    @checkJoinedUser author
    .then =>
      @roomState.messagesGetLastId()

  # @private
  getMessagesAfterId : (author, id) ->
    @checkJoinedUser author
    .then =>
      @roomState.messagesGetAfterId id

  # @private
  addToList : (author, listName, values) ->
    @checkListAdd author, listName, values
    .then =>
      @roomState.addToList listName, values
    .then =>
      Promise.filter values, (val) =>
        @hasAddChangedCurrentAccess val, listName
      , { concurrency : asyncLimit }

  # @private
  removeFromList : (author, listName, values) ->
    @checkListRemove author, listName, values
    .then =>
      @roomState.removeFromList listName, values
    .then =>
      Promise.filter values, (val) =>
        @hasRemoveChangedCurrentAccess val, listName
      , { concurrency : asyncLimit }

  # @private
  getMode : (author) ->
    @roomState.whitelistOnlyGet()

  # @private
  getOwner : (author) ->
    @checkJoinedUser author
    .then =>
      @roomState.ownerGet()

  # @private
  changeMode : (author, mode) ->
    whitelistOnly = if mode then true else false
    @checkModeChange author, mode
    .then =>
      @roomState.whitelistOnlySet whitelistOnly
    .then =>
      @getModeChangedCurrentAccess whitelistOnly
    .then (usernames) ->
      Promise.resolve [ usernames, whitelistOnly ]


module.exports = Room
