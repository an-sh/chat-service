
async = require 'async'
{ withEH, extend, asyncLimit } =
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
  isAdmin : (userName, cb) ->
    @roomState.ownerGet()
    .then (owner) =>
      if owner == userName
        return cb null, true
      @roomState.hasInList 'adminlist', userName
      .then (hasName) ->
        if hasName
          return cb null, true
        cb null, false
      , cb
    , cb

  # @private
  hasRemoveChangedCurrentAccess : (userName, listName, cb) ->
    @roomState.hasInList 'userlist', userName
    .then (hasUser) =>
      unless hasUser
        return cb null, false
      @isAdmin userName, withEH cb, (admin) =>
        if admin
          cb null, false
        else if listName == 'whitelist'
          @roomState.whitelistOnlyGet()
          .then (whitelistOnly) ->
            cb null, whitelistOnly
          , cb
        else
          cb null, false
    , cb

  # @private
  hasAddChangedCurrentAccess : (userName, listName, cb) ->
    @roomState.hasInList 'userlist', userName
    .then (hasUser) =>
      unless hasUser
        return cb null, false
      @isAdmin userName, withEH cb, (admin) ->
        if admin
          cb null, false
        else if listName == 'blacklist'
          cb null, true
        else
          cb null, false
    , cb

  # @private
  getModeChangedCurrentAccess : (value, cb) ->
    unless value
      process.nextTick -> cb null, false
    else
      @roomState.getCommonUsers()
      .then (data) ->
        cb null, data
      , cb

  # @private
  checkJoinedUser : (author, cb) ->
    @roomState.hasInList 'userlist', author
    .then (hasAuthor) =>
      unless hasAuthor
        return cb @errorBuilder.makeError 'notJoined', @name
      cb()
    , cb

  # @private
  checkListChanges : (author, listName, values, cb) ->
    @checkJoinedUser author, withEH cb, =>
      @roomState.ownerGet()
      .then (owner) =>
        if listName == 'userlist'
          return cb @errorBuilder.makeError 'notAllowed'
        if author == owner
          return cb()
        if listName == 'adminlist'
          return cb @errorBuilder.makeError 'notAllowed'
        @roomState.hasInList 'adminlist', author
        .then (hasAuthor) =>
          unless hasAuthor
            return cb @errorBuilder.makeError 'notAllowed'
          for name in values
            if name == owner
              return cb @errorBuilder.makeError 'notAllowed'
          cb()
        , cb
      , cb

  # @private
  checkListAdd : (author, listName, values, cb) ->
    @checkListChanges author, listName, values, cb

  # @private
  checkListRemove : (author, listName, values, cb) ->
    @checkListChanges author, listName, values, cb

  # @private
  checkModeChange : (author, value, cb) ->
    @isAdmin author, withEH cb, (admin) =>
      unless admin
        return cb @errorBuilder.makeError 'notAllowed'
      cb()

  # @private
  checkAcess : (userName, cb) ->
    @isAdmin userName, withEH cb, (admin) =>
      if admin
        return cb()
      @roomState.hasInList 'blacklist', userName
      .then (blacklisted) =>
        if blacklisted
          return cb @errorBuilder.makeError 'notAllowed'
        @roomState.whitelistOnlyGet()
        .then (whitelistOnly) =>
          @roomState.hasInList 'whitelist', userName
          .then (inWhitelist) =>
            if whitelistOnly and not inWhitelist
              return cb @errorBuilder.makeError 'notAllowed'
            cb()
          , cb
        , cb
      , cb

  # @private
  checkIsOwner : (author, cb) ->
    @roomState.ownerGet()
    .then (owner) =>
      unless owner == author
        return cb @errorBuilder.makeError 'notAllowed'
      cb()
    , cb

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
  initState : (state, cb) ->
    @roomState.initState state
    .then (data) ->
      cb null, data
    , cb

  # @private
  removeState : (cb) ->
    @roomState.removeState()
    .then (data) ->
      cb null, data
    , cb

  # @private
  getUsers: (cb) ->
    @roomState.getList 'userlist'
    .then (data) ->
      cb null, data
    , cb

  # @private
  leave : (userName, cb) ->
    @roomState.removeFromList 'userlist', [userName]
    .then (data) ->
      cb null, data
    , cb

  # @private
  join : (userName, cb) ->
    @checkAcess userName, withEH cb, =>
      @roomState.addToList 'userlist', [userName]
      .then (data) ->
        cb null, data
      , cb

  # @private
  message : (author, msg, cb) ->
    @roomState.hasInList 'userlist', author
    .then (hasAuthor) =>
      unless hasAuthor
        return cb @errorBuilder.makeError 'notJoined', @name
      @roomState.messageAdd msg
      .then (data) ->
        cb null, data
      , cb
    , cb

  # @private
  getList : (author, listName, cb) ->
    @checkJoinedUser author, withEH cb, =>
      @roomState.getList listName
      .then (data) ->
        cb null, data
      , cb

  # @private
  getRecentMessages : (author, cb) ->
    @checkJoinedUser author, withEH cb, =>
      @roomState.messagesGetRecent()
      .then (data) ->
        cb null, data
      , cb

  # @private
  getMessagesLastId : (author, cb) ->
    @checkJoinedUser author, withEH cb, =>
      @roomState.messagesGetLastId()
      .then (data) ->
        cb null, data
      , cb

  # @private
  getMessagesAfterId : (author, id, cb) ->
    @checkJoinedUser author, withEH cb, =>
      @roomState.messagesGetAfterId id
      .then (data) ->
        cb null, data
      , cb

  # @private
  addToList : (author, listName, values, cb) ->
    @checkListAdd author, listName, values, withEH cb, =>
      @roomState.addToList listName, values
      .then =>
        data = []
        async.eachLimit values, asyncLimit
        , (val, fn) =>
          @hasAddChangedCurrentAccess val, listName, withEH fn, (changed) ->
            if changed then data.push val
            fn()
        , (error) -> cb error, data
      , cb

  # @private
  removeFromList : (author, listName, values, cb) ->
    @checkListRemove author, listName, values, withEH cb, =>
      @roomState.removeFromList listName, values
      .then =>
        data = []
        async.eachLimit values, asyncLimit
        , (val, fn) =>
          @hasRemoveChangedCurrentAccess val, listName, withEH fn, (changed) ->
            if changed then data.push val
            fn()
        , (error) -> cb error, data
      , cb

  # @private
  getMode : (author, cb) ->
    @roomState.whitelistOnlyGet()
    .then (data) ->
      cb null, data
    , cb

  # @private
  getOwner : (author, cb) ->
    @checkJoinedUser author, withEH cb, =>
      @roomState.ownerGet()
      .then (data) ->
        cb null, data
      , cb

  # @private
  changeMode : (author, mode, cb) ->
    @checkModeChange author, mode, withEH cb, =>
      whitelistOnly = if mode then true else false
      @roomState.whitelistOnlySet whitelistOnly
      .then =>
        @getModeChangedCurrentAccess whitelistOnly, withEH cb
        , (userNames) ->
          cb null, userNames, mode
      , cb


module.exports = Room
