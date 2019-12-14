'use strict'

const ChatServiceError = require('./ChatServiceError')
const Promise = require('bluebird')
const { mixin, run } = require('./utils')

class DirectMessagingPermissions {
  constructor (userName, directMessagingState) {
    this.userName = userName
    this.directMessagingState = directMessagingState
  }

  checkList (author, listName) {
    return this.directMessagingState.checkList(listName)
  }

  checkListValues (author, listName, values) {
    return this.checkList(author, listName).then(() => {
      for (const name of values) {
        if (name !== this.userName) { continue }
        return Promise.reject(new ChatServiceError('notAllowed'))
      }
    })
  }

  checkAcess (userName, bypassPermissions) {
    if (userName === this.userName) {
      return Promise.reject(new ChatServiceError('notAllowed'))
    }
    if (bypassPermissions) { return Promise.resolve() }
    return run(this, function * () {
      const blacklisted =
            yield this.directMessagingState.hasInList('blacklist', userName)
      if (blacklisted) {
        return Promise.reject(new ChatServiceError('notAllowed'))
      }
      const whitelistOnly = yield this.directMessagingState.whitelistOnlyGet()
      if (!whitelistOnly) { return }
      const whitelisted =
            yield this.directMessagingState.hasInList('whitelist', userName)
      if (whitelisted) { return }
      return Promise.reject(new ChatServiceError('notAllowed'))
    })
  }
}

// Implements direct messaging state manipulations with the respect to
// user's permissions.
class DirectMessaging {
  constructor (server, userName) {
    this.server = server
    this.userName = userName
    this.listSizeLimit = this.server.directListSizeLimit
    const State = this.server.state.DirectMessagingState
    this.directMessagingState = new State(this.server, this.userName)
    mixin(this, DirectMessagingPermissions,
      this.userName, this.directMessagingState)
  }

  initState (state) {
    return this.directMessagingState.initState(state)
  }

  removeState () {
    return this.directMessagingState.removeState()
  }

  message (author, msg, bypassPermissions) {
    return this.checkAcess(author, bypassPermissions)
  }

  getList (author, listName) {
    return this.checkList(author, listName)
      .then(() => this.directMessagingState.getList(listName))
  }

  addToList (author, listName, values) {
    return this.checkListValues(author, listName, values)
      .then(() => this.directMessagingState.addToList(
        listName, values, this.listSizeLimit))
  }

  removeFromList (author, listName, values) {
    return this.checkListValues(author, listName, values)
      .then(() => this.directMessagingState.removeFromList(listName, values))
  }

  hasInList (listName, item) {
    return this.directMessagingState.hasInList(listName, item)
  }

  getMode (author) {
    return this.directMessagingState.whitelistOnlyGet()
  }

  changeMode (author, mode) {
    return this.directMessagingState.whitelistOnlySet(mode)
  }
}

module.exports = DirectMessaging
