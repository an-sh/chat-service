
async = require 'async'
{ withEH, extend, asyncLimit } =
  require './utils.coffee'

# @private
# @mixin
# @nodoc
#
# Implements room messaging permissions checks.
# Required existence of username, roomState and errorBuilder in
# extented classes.
RoomPermissions =

  # @private
  isAdmin : (userName, cb) ->
    @roomState.ownerGet withEH cb, (owner) =>
      if owner == userName
        return cb null, true
      @roomState.hasInList 'adminlist', userName, withEH cb, (hasName) ->
        if hasName
          return cb null, true
        cb null, false

  # @private
  hasRemoveChangedCurrentAccess : (userName, listName, cb) ->
    @roomState.hasInList 'userlist', userName, withEH cb, (hasUser) =>
      unless hasUser
        return cb null, false
      @isAdmin userName, withEH cb, (admin) =>
        if admin
          cb null, false
        else if listName == 'whitelist'
          @roomState.whitelistOnlyGet withEH cb, (whitelistOnly) ->
            cb null, whitelistOnly
        else
          cb null, false

  # @private
  hasAddChangedCurrentAccess : (userName, listName, cb) ->
    @roomState.hasInList 'userlist', userName, withEH cb, (hasUser) =>
      unless hasUser
        return cb null, false
      @isAdmin userName, withEH cb, (admin) ->
        if admin
          cb null, false
        else if listName == 'blacklist'
          cb null, true
        else
          cb null, false

  # @private
  getModeChangedCurrentAccess : (value, cb) ->
    unless value
      process.nextTick -> cb null, false
    else
      @roomState.getCommonUsers cb

  # @private
  checkList : (author, listName, cb) ->
    @roomState.hasInList 'userlist', author, withEH cb, (hasAuthor) =>
      unless hasAuthor
        return cb @errorBuilder.makeError 'notJoined', @name
      cb()

  # @private
  checkListChanges : (author, listName, values, cb) ->
    @checkList author, listName, withEH cb, =>
      @roomState.ownerGet withEH cb, (owner) =>
        if listName == 'userlist'
          return cb @errorBuilder.makeError 'notAllowed'
        if author == owner
          return cb()
        if listName == 'adminlist'
          return cb @errorBuilder.makeError 'notAllowed'
        @roomState.hasInList 'adminlist', author, withEH cb, (hasAuthor) =>
          unless hasAuthor
            return cb @errorBuilder.makeError 'notAllowed'
          for name in values
            if name == owner
              return cb @errorBuilder.makeError 'notAllowed'
          cb()

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
      @roomState.hasInList 'blacklist', userName, withEH cb, (inBlacklist) =>
        if inBlacklist
          return cb @errorBuilder.makeError 'notAllowed'
        @roomState.whitelistOnlyGet withEH cb, (whitelistOnly) =>
          @roomState.hasInList 'whitelist', userName
          , withEH cb, (inWhitelist) =>
            if whitelistOnly and not inWhitelist
              return cb @errorBuilder.makeError 'notAllowed'
            cb()

  # @private
  checkIsOwner : (author, cb) ->
    @roomState.ownerGet withEH cb, (owner) =>
      unless owner == author
        return cb @errorBuilder.makeError 'notAllowed'
      cb()

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
    @roomState.initState state, cb

  # @private
  removeState : (cb) ->
    @roomState.removeState cb

  # @private
  getUsers: (cb) ->
    @roomState.getList 'userlist', cb

  # @private
  leave : (userName, cb) ->
    @roomState.removeFromList 'userlist', [userName], cb

  # @private
  join : (userName, cb) ->
    @checkAcess userName, withEH cb, =>
      @roomState.addToList 'userlist', [userName], cb

  # @private
  message : (author, msg, cb) ->
    @roomState.hasInList 'userlist', author, withEH cb, (hasAuthor) =>
      unless hasAuthor
        return cb @errorBuilder.makeError 'notJoined', @name
      @roomState.messageAdd msg, cb

  # @private
  getList : (author, listName, cb) ->
    @checkList author, listName, withEH cb, =>
      @roomState.getList listName, cb

  # @private
  getLastMessages : (author, cb) ->
    @roomState.hasInList 'userlist', author, withEH cb, (hasAuthor) =>
      unless hasAuthor
        return cb @errorBuilder.makeError 'notJoined', @name
      @roomState.messagesGet cb

  # @private
  addToList : (author, listName, values, cb) ->
    @checkListAdd author, listName, values, withEH cb, =>
      @roomState.addToList listName, values, withEH cb, =>
        data = []
        async.eachLimit values, asyncLimit
        , (val, fn) =>
          @hasAddChangedCurrentAccess val, listName, withEH fn, (changed) ->
            if changed then data.push val
            fn()
        , (error) -> cb error, data

  # @private
  removeFromList : (author, listName, values, cb) ->
    @checkListRemove author, listName, values, withEH cb, =>
      @roomState.removeFromList listName, values, withEH cb, =>
        data = []
        async.eachLimit values, asyncLimit
        , (val, fn) =>
          @hasRemoveChangedCurrentAccess val, listName, withEH fn, (changed) ->
            if changed then data.push val
            fn()
        , (error) -> cb error, data

  # @private
  getMode : (author, cb) ->
    @roomState.whitelistOnlyGet cb

  # @private
  changeMode : (author, mode, cb) ->
    @checkModeChange author, mode, withEH cb, =>
      whitelistOnly = if mode then true else false
      @roomState.whitelistOnlySet whitelistOnly, withEH cb, =>
        @getModeChangedCurrentAccess whitelistOnly, cb


module.exports = Room
