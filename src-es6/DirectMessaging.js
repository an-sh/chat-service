
const ChatServiceError = require('./ChatServiceError')
const Promise = require('bluebird')
const { mix } = require('./utils')

// @mixin
//
// Implements direct messaging permissions checks. Required existence
// of userName, directMessagingState and in extented classes.
let DirectMessagingPermissions = {

  checkList (author, listName) {
    return this.directMessagingState.checkList(listName)
  },

  checkListValues (author, listName, values) {
    return this.checkList(author, listName).then(() => {
      for (let i = 0; i < values.length; i++) {
        let name = values[i]
        if (name === this.userName) {
          return Promise.reject(new ChatServiceError('notAllowed'))
        } else {
          return Promise.resolve()
        }
      }
    })
  },

  checkAcess (userName, bypassPermissions) {
    if (userName === this.userName) {
      return Promise.reject(new ChatServiceError('notAllowed'))
    }
    if (bypassPermissions) { return Promise.resolve() }
    return this.directMessagingState.hasInList('blacklist', userName)
      .then(blacklisted => {
        if (blacklisted) {
          return Promise.reject(new ChatServiceError('notAllowed'))
        }
        return this.directMessagingState.whitelistOnlyGet()
          .then(whitelistOnly => {
            if (!whitelistOnly) { return Promise.resolve() }
            return this.directMessagingState.hasInList('whitelist', userName)
              .then(whitelisted => {
                if (whitelisted) { return Promise.resolve() }
                return Promise.reject(new ChatServiceError('notAllowed'))
              })
          })
      })
  }
}

//
// @extend DirectMessagingPermissions
// Implements direct messaging state manipulations with the respect to
// user's permissions.
class DirectMessaging {

  constructor (server, userName) {
    this.server = server
    this.userName = userName
    let State = this.server.state.DirectMessagingState
    this.directMessagingState = new State(this.server, this.userName)
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
      .then(() => this.directMessagingState.addToList(listName, values))
  }

  removeFromList (author, listName, values) {
    return this.checkListValues(author, listName, values)
      .then(() => this.directMessagingState.removeFromList(listName, values))
  }

  getMode (author) {
    return this.directMessagingState.whitelistOnlyGet()
  }

  changeMode (author, mode) {
    return this.directMessagingState.whitelistOnlySet(mode)
  }
}

mix(DirectMessaging, DirectMessagingPermissions)

module.exports = DirectMessaging
