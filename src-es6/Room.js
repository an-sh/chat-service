
const ChatServiceError = require('./ChatServiceError');
const Promise = require('bluebird');
const _ = require('lodash');

const { mix, asyncLimit } = require('./utils');

// @private
// @mixin
// @nodoc
//
// Implements room messaging permissions checks.  Required existence of
// userName, roomState and in extented classes.
let RoomPermissions = {

  // @private
  isAdmin(userName) {
    return this.roomState.ownerGet()
    .then(owner => {
      if (owner === userName) { return true; }
      return this.roomState.hasInList('adminlist', userName);
    }
    );
  },

  // @private
  hasRemoveChangedCurrentAccess(userName, listName) {
    return this.roomState.hasInList('userlist', userName)
    .then(hasUser => {
      if (!hasUser) { return false; }
      return this.isAdmin(userName)
      .then(admin => {
        if (admin || listName !== 'whitelist') {
          return false;
        } else {
          return this.roomState.whitelistOnlyGet();
        }
      }
      );
    }
    )
    .catch(e => {
      return this.consistencyFailure(e, { userName });
    }
    );
  },

  // @private
  hasAddChangedCurrentAccess(userName, listName) {
    return this.roomState.hasInList('userlist', userName)
    .then(hasUser => {
      if (!hasUser) { return false; }
      return this.isAdmin(userName)
      .then(function(admin) {
        if (admin || listName !== 'blacklist') {
          return false;
        } else {
          return true;
        }
      });
    }
    )
    .catch(e => {
      return this.consistencyFailure(e, { userName });
    }
    );
  },

  // @private
  getModeChangedCurrentAccess(value) {
    if (!value) {
      return [];
    } else {
      return this.roomState.getCommonUsers();
    }
  },

  // @private
  checkListChanges(author, listName, values, bypassPermissions) {
    return this.roomState.ownerGet()
    .then(owner => {
      if (listName === 'userlist') {
        return Promise.reject(new ChatServiceError('notAllowed'));
      }
      if (author === owner || bypassPermissions) {
        return;
      }
      if (listName === 'adminlist') {
        return Promise.reject(new ChatServiceError('notAllowed'));
      }
      return this.roomState.hasInList('adminlist', author)
      .then(function(admin) {
        if (!admin) {
          return Promise.reject(new ChatServiceError('notAllowed'));
        }
        for (let i = 0; i < values.length; i++) {
          let name = values[i];
          if (name === owner) {
            return Promise.reject(new ChatServiceError('notAllowed'));
          }
        }
      });
    }
    );
  },

  // @private
  checkModeChange(author, value, bypassPermissions) {
    return this.isAdmin(author)
    .then(function(admin) {
      if (!admin && !bypassPermissions) {
        return Promise.reject(new ChatServiceError('notAllowed'));
      }
    });
  },

  // @private
  checkAcess(userName) {
    return this.isAdmin(userName)
    .then(admin => {
      if (admin) { return; }
      return this.roomState.hasInList('blacklist', userName)
      .then(blacklisted => {
        if (blacklisted) {
          return Promise.reject(new ChatServiceError('notAllowed'));
        }
        return this.roomState.whitelistOnlyGet()
        .then(whitelistOnly => {
          if (!whitelistOnly) { return; }
          return this.roomState.hasInList('whitelist', userName)
          .then(function(whitelisted) {
            if (!whitelisted) {
              return Promise.reject(new ChatServiceError('notAllowed'));
            }
          });
        }
        );
      }
      );
    }
    );
  },

  // @private
  checkRead(author, bypassPermissions) {
    if (bypassPermissions) { return Promise.resolve(); }
    return this.isAdmin(author)
    .then(admin => {
      if (admin) { return; }
      return this.roomState.hasInList('userlist', author)
      .then(hasAuthor => {
        if (!hasAuthor) {
          return Promise.reject(new ChatServiceError('notJoined', this.roomName));
        }
      }
      );
    }
    );
  },

  // @private
  checkIsOwner(author, bypassPermissions) {
    if (bypassPermissions) { return Promise.resolve(); }
    return this.roomState.ownerGet()
    .then(function(owner) {
      if (owner === author) { return; }
      return Promise.reject(new ChatServiceError('notAllowed'));
    });
  }
};


// @private
// @nodoc
//
// @extend RoomPermissions
// Implements room messaging state manipulations with the respect to
// user's permissions.
class Room {

  // @private
  constructor(server, roomName) {
    this.server = server;
    this.roomName = roomName;
    let State = this.server.state.RoomState;
    this.roomState = new State(this.server, this.roomName);
  }

  // @private
  initState(state) {
    return this.roomState.initState(state);
  }

  // @private
  removeState() {
    return this.roomState.removeState();
  }

  // @private
  startRemoving() {
    return this.roomState.startRemoving();
  }

  // @private
  consistencyFailure(error, operationInfo = {}) {
    operationInfo.roomName = this.roomName;
    operationInfo.opType = 'roomUserlist';
    this.server.emit('storeConsistencyFailure', error, operationInfo);
  }

  // @private
  getUsers() {
    return this.roomState.getList('userlist');
  }

  // @private
  leave(author) {
    return this.roomState.hasInList('userlist', author)
    .then(hasAuthor => {
      if (hasAuthor) {
        return this.roomState.removeFromList('userlist', [author])
        .then(() => {
          return this.roomState.userSeenUpdate(author);
        }
        );
      }
    }
    );
  }

  // @private
  join(author) {
    return this.checkAcess(author)
    .then(() => {
      return this.roomState.hasInList('userlist', author);
    }
    )
    .then(hasAuthor => {
      if (!hasAuthor) {
        return this.roomState.userSeenUpdate(author)
        .then(() => {
          return this.roomState.addToList('userlist', [author]);
        }
        );
      }
    }
    );
  }

  // @private
  message(author, msg, bypassPermissions) {
    return Promise.try(() => {
      if (!bypassPermissions) {
        return this.roomState.hasInList('userlist', author)
        .then(hasAuthor => {
          if (!hasAuthor) {
            return Promise.reject(new ChatServiceError('notJoined', this.roomName));
          }
        }
        );
      }
    }
    )
    .then(() => {
      return this.roomState.messageAdd(msg);
    }
    );
  }

  // @private
  getList(author, listName, bypassPermissions) {
    return this.checkRead(author, bypassPermissions)
    .then(() => {
      return this.roomState.getList(listName);
    }
    );
  }

  // @private
  getRecentMessages(author, bypassPermissions) {
    return this.checkRead(author, bypassPermissions)
    .then(() => {
      return this.roomState.messagesGetRecent();
    }
    );
  }

  // @private
  getHistoryInfo(author, bypassPermissions) {
    return this.checkRead(author, bypassPermissions)
    .then(() => {
      return this.roomState.historyInfo();
    }
    );
  }

  // @private
  getMessages(author, id, limit, bypassPermissions) {
    return this.checkRead(author, bypassPermissions)
    .then(() => {
      if (!bypassPermissions) {
        limit = _.min([ limit, this.server.historyMaxGetMessages ]);
      }
      return this.roomState.messagesGet(id, limit);
    }
    );
  }

  // @private
  addToList(author, listName, values, bypassPermissions) {
    return this.checkListChanges(author, listName, values, bypassPermissions)
    .then(() => {
      return this.roomState.addToList(listName, values);
    }
    )
    .then(() => {
      return Promise.filter(values, val => {
        return this.hasAddChangedCurrentAccess(val, listName);
      }
      , { concurrency : asyncLimit });
    }
    );
  }

  // @private
  removeFromList(author, listName, values, bypassPermissions) {
    return this.checkListChanges(author, listName, values, bypassPermissions)
    .then(() => {
      return this.roomState.removeFromList(listName, values);
    }
    )
    .then(() => {
      return Promise.filter(values, val => {
        return this.hasRemoveChangedCurrentAccess(val, listName);
      }
      , { concurrency : asyncLimit });
    }
    );
  }

  // @private
  getMode(author, bypassPermissions) {
    return this.checkRead(author, bypassPermissions)
    .then(() => {
      return this.roomState.whitelistOnlyGet();
    }
    );
  }

  // @private
  getOwner(author, bypassPermissions) {
    return this.checkRead(author, bypassPermissions)
    .then(() => {
      return this.roomState.ownerGet();
    }
    );
  }

  // @private
  changeMode(author, mode, bypassPermissions) {
    let whitelistOnly = mode;
    return this.checkModeChange(author, mode, bypassPermissions)
    .then(() => {
      return this.roomState.whitelistOnlySet(whitelistOnly);
    }
    )
    .then(() => {
      return this.getModeChangedCurrentAccess(whitelistOnly);
    }
    )
    .then(usernames => [ usernames, whitelistOnly ]);
  }

  // @private
  userSeen(author, userName, bypassPermissions) {
    return this.checkRead(author, bypassPermissions)
    .then(() => {
      return this.roomState.userSeenGet(userName);
    }
    );
  }
}

mix(Room, RoomPermissions);


module.exports = Room;
