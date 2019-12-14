'use strict'

const ChatServiceError = require('./ChatServiceError')
const Promise = require('bluebird')
const _ = require('lodash')
const { asyncLimit, mixin, run } = require('./utils')

class RoomPermissions {
  constructor (roomName, roomState, emitFailure) {
    this.roomName = roomName
    this.roomState = roomState
    this.emitFailure = emitFailure
  }

  makeConsistencyReporter (userName) {
    return (error) => {
      const operationInfo = { userName }
      operationInfo.roomName = this.roomName
      operationInfo.opType = 'roomUserlist'
      this.emitFailure('storeConsistencyFailure', error, operationInfo)
    }
  }

  isAdmin (userName) {
    return this.roomState.ownerGet().then(owner => {
      if (owner === userName) { return true }
      return this.roomState.hasInList('adminlist', userName)
    })
  }

  hasRemoveChangedCurrentAccess (userName, listName) {
    return this.roomState.hasInList('userlist', userName).then(hasUser => {
      if (!hasUser) { return false }
      return this.isAdmin(userName).then(admin => {
        if (admin || listName !== 'whitelist') { return false }
        return this.roomState.whitelistOnlyGet()
      })
    }).catch(this.makeConsistencyReporter(userName))
  }

  hasAddChangedCurrentAccess (userName, listName) {
    return this.roomState.hasInList('userlist', userName).then(hasUser => {
      if (!hasUser) { return false }
      return this.isAdmin(userName)
        .then(admin => !(admin || listName !== 'blacklist'))
    }).catch(this.makeConsistencyReporter(userName))
  }

  getModeChangedCurrentAccess (value) {
    if (!value) {
      return []
    } else {
      return this.roomState.getCommonUsers()
    }
  }

  checkListChanges (author, listName, values, bypassPermissions) {
    if (listName === 'userlist') {
      return Promise.reject(new ChatServiceError('notAllowed'))
    }
    if (bypassPermissions) { return Promise.resolve() }
    return run(this, function * () {
      const owner = yield this.roomState.ownerGet()
      if (author === owner) { return }
      if (listName === 'adminlist') {
        return Promise.reject(new ChatServiceError('notAllowed'))
      }
      const admin = yield this.roomState.hasInList('adminlist', author)
      if (!admin) {
        return Promise.reject(new ChatServiceError('notAllowed'))
      }
      for (const name of values) {
        if (name !== owner) { continue }
        return Promise.reject(new ChatServiceError('notAllowed'))
      }
    })
  }

  checkModeChange (author, value, bypassPermissions) {
    return this.isAdmin(author).then(admin => {
      if (admin || bypassPermissions) { return }
      return Promise.reject(new ChatServiceError('notAllowed'))
    })
  }

  checkAcess (userName) {
    return run(this, function * () {
      const admin = yield this.isAdmin(userName)
      if (admin) { return }
      const blacklisted = yield this.roomState.hasInList('blacklist', userName)
      if (blacklisted) {
        return Promise.reject(new ChatServiceError('notAllowed'))
      }
      const whitelistOnly = yield this.roomState.whitelistOnlyGet()
      if (!whitelistOnly) { return }
      const whitelisted = yield this.roomState.hasInList('whitelist', userName)
      if (whitelisted) { return }
      return Promise.reject(new ChatServiceError('notAllowed'))
    })
  }

  checkRead (author, bypassPermissions) {
    if (bypassPermissions) { return Promise.resolve() }
    return run(this, function * () {
      const hasAuthor = yield this.roomState.hasInList('userlist', author)
      if (hasAuthor) { return }
      const admin = yield this.isAdmin(author)
      if (admin) { return }
      return Promise.reject(new ChatServiceError('notJoined', this.roomName))
    })
  }

  checkIsOwner (author, bypassPermissions) {
    if (bypassPermissions) { return Promise.resolve() }
    return this.roomState.ownerGet().then(owner => {
      if (owner === author) { return }
      return Promise.reject(new ChatServiceError('notAllowed'))
    })
  }
}

// Implements room messaging state manipulations with the respect to
// user's permissions.
class Room {
  constructor (server, roomName) {
    this.server = server
    this.roomName = roomName
    this.listSizeLimit = this.server.roomListSizeLimit
    const State = this.server.state.RoomState
    this.roomState = new State(this.server, this.roomName)
    mixin(this, RoomPermissions, this.roomName,
      this.roomState, this.server.emit.bind(this.server))
  }

  initState (state) {
    return this.roomState.initState(state)
  }

  removeState () {
    return this.roomState.removeState()
  }

  startRemoving () {
    return this.roomState.startRemoving()
  }

  getUsers () {
    return this.roomState.getList('userlist')
  }

  leave (author) {
    return this.roomState.hasInList('userlist', author).then(hasAuthor => {
      if (!hasAuthor) { return }
      return Promise.all([
        this.roomState.removeFromList('userlist', [author]),
        this.roomState.userSeenUpdate(author)])
    })
  }

  join (author) {
    return this.checkAcess(author)
      .then(() => this.roomState.hasInList('userlist', author))
      .then(hasAuthor => {
        if (hasAuthor) { return }
        return Promise.all([
          this.roomState.userSeenUpdate(author),
          this.roomState.addToList('userlist', [author])])
      })
  }

  message (author, msg, bypassPermissions) {
    return Promise.try(() => {
      if (bypassPermissions) { return }
      return this.roomState.hasInList('userlist', author).then(hasAuthor => {
        if (hasAuthor) { return }
        return Promise.reject(new ChatServiceError('notJoined', this.roomName))
      })
    }).then(() => this.roomState.messageAdd(msg))
  }

  getList (author, listName, bypassPermissions) {
    return this.checkRead(author, bypassPermissions)
      .then(() => this.roomState.getList(listName))
  }

  getRecentMessages (author, bypassPermissions) {
    return this.checkRead(author, bypassPermissions)
      .then(() => this.roomState.messagesGetRecent())
  }

  getHistoryInfo (author, bypassPermissions) {
    return this.checkRead(author, bypassPermissions)
      .then(() => this.roomState.historyInfo())
  }

  getNotificationsInfo (author, bypassPermissions) {
    return this.checkRead(author, bypassPermissions)
      .then(() => Promise.join(
        this.roomState.userlistUpdatesGet(),
        this.roomState.accessListsUpdatesGet(),
        (enableUserlistUpdates, enableAccessListsUpdates) =>
          ({ enableUserlistUpdates, enableAccessListsUpdates })))
  }

  getMessages (author, id, limit, bypassPermissions) {
    return this.checkRead(author, bypassPermissions).then(() => {
      if (!bypassPermissions) {
        limit = _.min([limit, this.server.historyMaxGetMessages])
      }
      return this.roomState.messagesGet(id, limit)
    })
  }

  addToList (author, listName, values, bypassPermissions) {
    return this.checkListChanges(author, listName, values, bypassPermissions)
      .then(() => this.roomState.addToList(
        listName, values, this.listSizeLimit))
      .then(() => Promise.filter(
        values,
        val => this.hasAddChangedCurrentAccess(val, listName),
        { concurrency: asyncLimit }))
  }

  removeFromList (author, listName, values, bypassPermissions) {
    return this.checkListChanges(author, listName, values, bypassPermissions)
      .then(() => this.roomState.removeFromList(listName, values))
      .then(() => Promise.filter(
        values,
        val => this.hasRemoveChangedCurrentAccess(val, listName),
        { concurrency: asyncLimit }))
  }

  getMode (author, bypassPermissions) {
    return this.checkRead(author, bypassPermissions)
      .then(() => this.roomState.whitelistOnlyGet())
  }

  getOwner (author, bypassPermissions) {
    return this.checkRead(author, bypassPermissions)
      .then(() => this.roomState.ownerGet())
  }

  changeMode (author, mode, bypassPermissions) {
    const whitelistOnly = mode
    return this.checkModeChange(author, mode, bypassPermissions)
      .then(() => this.roomState.whitelistOnlySet(whitelistOnly))
      .then(() => this.getModeChangedCurrentAccess(whitelistOnly))
      .then(usernames => [usernames, whitelistOnly])
  }

  userSeen (author, userName, bypassPermissions) {
    return this.checkRead(author, bypassPermissions)
      .then(() => this.roomState.userSeenGet(userName))
  }
}

module.exports = Room
