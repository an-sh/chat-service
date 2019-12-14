'use strict'

const ChatServiceError = require('./ChatServiceError')
const Promise = require('bluebird')
const Room = require('./Room')
const User = require('./User')
const _ = require('lodash')
const promiseRetry = require('promise-retry')
const uid = require('uid-safe')
const { mixin } = require('./utils')

function initState (state, values = []) {
  if (state instanceof Set) {
    state.clear()
    for (const val of values) {
      state.add(val)
    }
  } else if (state instanceof Map) {
    state.clear()
  } else if (state instanceof Array) {
    state.length = 0
  }
  return state
}

function mapToObject (m) {
  const res = {}
  for (const [k, v] of m) {
    res[k] = v
  }
  return res
}

function setDifference (s1, s2) {
  const res = new Set()
  for (const v of s1) {
    if (!s2.has(v)) { res.add(v) }
  }
  return res
}

// Memory lock operations.
// @mixin
class LockOperations {
  constructor (locks) {
    this.locks = locks
  }

  lock (key, val, ttl) {
    return promiseRetry(
      { minTimeout: 100, retries: 10, factor: 1.5, randomize: true },
      (retry, n) => {
        if (this.locks.has(key)) {
          const err = new ChatServiceError('timeout')
          retry(err)
        } else {
          this.locks.set(key, val)
        }
      })
  }

  unlock (key, val) {
    const currentVal = this.locks.get(key)
    if (currentVal === val) {
      this.locks.delete(key)
    }
    return Promise.resolve()
  }
}

// Implements state API lists management.
class ListsStateMemory {
  checkList (listName, num, limit) {
    if (!this.hasList(listName)) {
      const error = new ChatServiceError('noList', listName)
      return Promise.reject(error)
    }
    if (listName === 'userlist') {
      return Promise.resolve()
    }
    if (this[listName].size + num > limit) {
      const error = new ChatServiceError('listLimitExceeded', listName)
      return Promise.reject(error)
    } else {
      return Promise.resolve()
    }
  }

  addToList (listName, elems, limit) {
    const num = elems.length
    return this.checkList(listName, num, limit).then(() => {
      for (const elem of elems) {
        this[listName].add(elem)
      }
    })
  }

  removeFromList (listName, elems) {
    return this.checkList(listName).then(() => {
      for (const elem of elems) {
        this[listName].delete(elem)
      }
    })
  }

  getList (listName) {
    return this.checkList(listName).then(() => {
      const data = this[listName]
      return [...data]
    })
  }

  hasInList (listName, elem) {
    return this.checkList(listName).then(() => {
      let data = this[listName].has(elem)
      data = Boolean(data)
      return data
    })
  }

  whitelistOnlySet (mode) {
    this.whitelistOnly = Boolean(mode)
    return Promise.resolve()
  }

  whitelistOnlyGet () {
    return Promise.resolve(this.whitelistOnly)
  }
}

// Implements room state API.
class RoomStateMemory extends ListsStateMemory {
  constructor (server, name) {
    super()
    this.server = server
    this.name = name
    this.historyMaxGetMessages = this.server.historyMaxGetMessages
    this.historyMaxSize = this.server.historyMaxSize
    this.whitelist = new Set()
    this.blacklist = new Set()
    this.adminlist = new Set()
    this.userlist = new Set()
    this.messagesHistory = []
    this.messagesTimestamps = []
    this.messagesIds = []
    this.usersseen = new Map()
    this.lastMessageId = 0
    this.whitelistOnly = false
    this.owner = null
  }

  initState (state) {
    state = state || {}
    const {
      whitelist, blacklist, adminlist,
      whitelistOnly, owner, historyMaxSize,
      enableAccessListsUpdates = this.server.enableAccessListsUpdates,
      enableUserlistUpdates = this.server.enableUserlistUpdates
    } = state
    initState(this.whitelist, whitelist)
    initState(this.blacklist, blacklist)
    initState(this.adminlist, adminlist)
    initState(this.messagesHistory)
    initState(this.messagesTimestamps)
    initState(this.messagesIds)
    initState(this.usersseen)
    this.whitelistOnly = Boolean(whitelistOnly)
    this.enableAccessListsUpdates = Boolean(enableAccessListsUpdates)
    this.enableUserlistUpdates = Boolean(enableUserlistUpdates)
    this.owner = owner || null
    return this.historyMaxSizeSet(historyMaxSize)
  }

  removeState () {
    return Promise.resolve()
  }

  startRemoving () {
    return Promise.resolve()
  }

  hasList (listName) {
    return listName === 'adminlist' || listName === 'whitelist' ||
      listName === 'blacklist' || listName === 'userlist'
  }

  ownerGet () {
    return Promise.resolve(this.owner)
  }

  ownerSet (owner) {
    this.owner = owner
    return Promise.resolve()
  }

  accessListsUpdatesSet (enableAccessListsUpdates) {
    this.enableAccessListsUpdates = Boolean(enableAccessListsUpdates)
    return Promise.resolve()
  }

  accessListsUpdatesGet () {
    return Promise.resolve(this.enableAccessListsUpdates)
  }

  userlistUpdatesSet (enableUserlistUpdates) {
    this.enableUserlistUpdates = Boolean(enableUserlistUpdates)
    return Promise.resolve()
  }

  userlistUpdatesGet () {
    return Promise.resolve(this.enableUserlistUpdates)
  }

  historyMaxSizeSet (historyMaxSize) {
    if (_.isNumber(historyMaxSize) && historyMaxSize >= 0) {
      this.historyMaxSize = historyMaxSize
    }
    const limit = this.historyMaxSize
    this.messagesHistory = this.messagesHistory.slice(0, limit)
    this.messagesTimestamps = this.messagesTimestamps.slice(0, limit)
    this.messagesIds = this.messagesIds.slice(0, limit)
    return Promise.resolve()
  }

  historyInfo () {
    const historySize = this.messagesHistory.length
    const info = {
      historySize,
      historyMaxSize: this.historyMaxSize,
      historyMaxGetMessages: this.historyMaxGetMessages,
      lastMessageId: this.lastMessageId
    }
    return Promise.resolve(info)
  }

  getCommonUsers () {
    const nonWL = setDifference(this.userlist, this.whitelist)
    const nonAdmin = setDifference(nonWL, this.adminlist)
    return Promise.resolve([...nonAdmin])
  }

  messageAdd (msg) {
    const timestamp = _.now()
    this.lastMessageId++
    const makeResult = () => {
      msg.timestamp = timestamp
      msg.id = this.lastMessageId
      return Promise.resolve(msg)
    }
    if (this.historyMaxSize <= 0) {
      return makeResult()
    }
    this.messagesHistory.unshift(msg)
    this.messagesTimestamps.unshift(timestamp)
    this.messagesIds.unshift(this.lastMessageId)
    if (this.messagesHistory.length > this.historyMaxSize) {
      this.messagesHistory.pop()
      this.messagesTimestamps.pop()
      this.messagesIds.pop()
    }
    return makeResult()
  }

  messagesGetRecent () {
    const msgs = this.messagesHistory.slice(0, this.historyMaxGetMessages)
    const tss = this.messagesTimestamps.slice(0, this.historyMaxGetMessages)
    const ids = this.messagesIds.slice(0, this.historyMaxGetMessages)
    const data = []
    for (let idx = 0; idx < msgs.length; idx++) {
      const msg = msgs[idx]
      const obj = _.cloneDeep(msg)
      obj.timestamp = tss[idx]
      obj.id = ids[idx]
      data[idx] = obj
    }
    return Promise.resolve(data)
  }

  messagesGet (id, maxMessages = this.historyMaxGetMessages) {
    if (maxMessages <= 0) { return Promise.resolve([]) }
    id = _.max([0, id])
    const lastid = this.lastMessageId
    id = _.min([id, lastid])
    const end = lastid - id
    const len = _.min([maxMessages, end])
    const start = _.max([0, end - len])
    const msgs = this.messagesHistory.slice(start, end)
    const tss = this.messagesTimestamps.slice(start, end)
    const ids = this.messagesIds.slice(start, end)
    const data = []
    for (let idx = 0; idx < msgs.length; idx++) {
      const msg = msgs[idx]
      const obj = _.cloneDeep(msg)
      msg.timestamp = tss[idx]
      msg.id = ids[idx]
      data[idx] = obj
    }
    return Promise.resolve(msgs)
  }

  userSeenGet (userName) {
    const joined = Boolean(this.userlist.has(userName))
    const timestamp = this.usersseen.get(userName) || null
    return Promise.resolve({ joined, timestamp })
  }

  userSeenUpdate (userName) {
    const timestamp = _.now()
    this.usersseen.set(userName, timestamp)
    return Promise.resolve()
  }
}

// Implements direct messaging state API.
class DirectMessagingStateMemory extends ListsStateMemory {
  constructor (server, userName) {
    super()
    this.server = server
    this.userName = userName
    this.whitelistOnly = false
    this.whitelist = new Set()
    this.blacklist = new Set()
  }

  initState ({ whitelist, blacklist, whitelistOnly }) {
    initState(this.whitelist, whitelist)
    initState(this.blacklist, blacklist)
    this.whitelistOnly = Boolean(whitelistOnly)
    return Promise.resolve()
  }

  removeState () {
    return Promise.resolve()
  }

  hasList (listName) {
    return listName === 'whitelist' || listName === 'blacklist'
  }
}

// Implements user state API.
class UserStateMemory {
  constructor (server, userName) {
    this.server = server
    this.userName = userName
    this.socketsToRooms = new Map()
    this.socketsToInstances = new Map()
    this.roomsToSockets = new Map()
    this.locks = new Map()
    mixin(this, LockOperations, this.locks)
  }

  addSocket (id, uid) {
    const roomsset = new Set()
    this.socketsToRooms.set(id, roomsset)
    this.socketsToInstances.set(id, uid)
    const nconnected = this.socketsToRooms.size
    return Promise.resolve(nconnected)
  }

  getAllSockets () {
    const sockets = [...this.socketsToRooms.keys()]
    return Promise.resolve(sockets)
  }

  getSocketsToInstance () {
    const data = mapToObject(this.socketsToInstances)
    return Promise.resolve(data)
  }

  getRoomToSockets (roomName) {
    const socketsset = this.roomsToSockets.get(roomName)
    const data = socketsset ? mapToObject(socketsset) : {}
    return Promise.resolve(data)
  }

  getSocketsToRooms () {
    const result = {}
    for (const id of this.socketsToRooms.keys()) {
      const socketsset = this.socketsToRooms.get(id)
      result[id] = socketsset ? [...socketsset] : []
    }
    return Promise.resolve(result)
  }

  addSocketToRoom (id, roomName) {
    const roomsset = this.socketsToRooms.get(id)
    let socketsset = this.roomsToSockets.get(roomName)
    const wasjoined = (socketsset && socketsset.size) || 0
    if (!socketsset) {
      socketsset = new Set()
      this.roomsToSockets.set(roomName, socketsset)
    }
    roomsset.add(roomName)
    socketsset.add(id)
    const njoined = socketsset.size
    const hasChanged = njoined !== wasjoined
    return Promise.resolve([njoined, hasChanged])
  }

  removeSocketFromRoom (id, roomName) {
    const roomsset = this.socketsToRooms.get(id)
    const socketsset = this.roomsToSockets.get(roomName)
    const wasjoined = (socketsset && socketsset.size) || 0
    if (roomsset) {
      roomsset.delete(roomName)
    }
    if (socketsset) {
      socketsset.delete(id)
    }
    let njoined = 0
    if (wasjoined > 0) {
      njoined = socketsset.size
    }
    const hasChanged = njoined !== wasjoined
    return Promise.resolve([njoined, hasChanged])
  }

  removeAllSocketsFromRoom (roomName) {
    const sockets = [...this.socketsToRooms.keys()]
    let socketsset = this.roomsToSockets.get(roomName)
    const removedSockets = socketsset || []
    for (const id of removedSockets) {
      const roomsset = this.socketsToRooms.get(id)
      roomsset.delete(roomName)
    }
    if (socketsset) {
      socketsset = setDifference(socketsset, new Set(sockets))
      this.roomsToSockets.set(roomName, socketsset)
    }
    return Promise.resolve([...removedSockets])
  }

  removeSocket (id) {
    const roomsset = this.socketsToRooms.get(id)
    const removedRooms = roomsset || []
    const joinedSockets = []
    for (const roomName of removedRooms) {
      const socketsset = this.roomsToSockets.get(roomName)
      socketsset.delete(id)
      const njoined = socketsset.size
      joinedSockets.push(njoined)
    }
    this.socketsToRooms.delete(id)
    this.socketsToInstances.delete(id)
    const nconnected = this.socketsToRooms.size
    return Promise.resolve([[...removedRooms], joinedSockets, nconnected])
  }

  lockToRoom (roomName, ttl) {
    return uid(18).then(val => {
      const start = _.now()
      return this.lock(roomName, val, ttl).then(() => {
        return Promise.resolve().disposer(() => {
          if (start + ttl < _.now()) {
            this.server.emit(
              'lockTimeExceeded', val, { userName: this.userName, roomName })
          }
          return this.unlock(roomName, val)
        })
      })
    })
  }
}

// Implements global state API.
class MemoryState {
  constructor (server, options) {
    this.server = server
    this.options = options
    this.closed = false
    this.users = new Map()
    this.rooms = new Map()
    this.sockets = new Map()
    this.RoomState = RoomStateMemory
    this.UserState = UserStateMemory
    this.DirectMessagingState = DirectMessagingStateMemory
    this.instanceUID = this.server.instanceUID
    this.heartbeatStamp = null
    this.lockTTL = this.options.lockTTL || 5000
  }

  close () {
    this.closed = true
    return Promise.resolve()
  }

  getRoom (name, isPredicate = false) {
    const room = this.rooms.get(name)
    if (room) { return Promise.resolve(room) }
    if (isPredicate) {
      return Promise.resolve(null)
    } else {
      const error = new ChatServiceError('noRoom', name)
      return Promise.reject(error)
    }
  }

  addRoom (name, state) {
    const room = new Room(this.server, name)
    if (!this.rooms.get(name)) {
      this.rooms.set(name, room)
    } else {
      const error = new ChatServiceError('roomExists', name)
      return Promise.reject(error)
    }
    return room.initState(state).return(room)
  }

  removeRoom (name) {
    this.rooms.delete(name)
    return Promise.resolve()
  }

  addSocket (id, userName) {
    this.sockets.set(id, userName)
    return Promise.resolve()
  }

  removeSocket (id) {
    this.sockets.delete(id)
    return Promise.resolve()
  }

  getInstanceSockets (uid = this.instanceUID) {
    return Promise.resolve(mapToObject(this.sockets))
  }

  updateHeartbeat () {
    this.heartbeatStamp = _.now()
    return Promise.resolve()
  }

  getInstanceHeartbeat (uid = this.instanceUID) {
    if (uid !== this.instanceUID) { return Promise.resolve(null) }
    return Promise.resolve(this.heartbeatStamp)
  }

  getOrAddUser (name, state) {
    const user = this.users.get(name)
    if (user) { return Promise.resolve(user) }
    return this.addUser(name, state)
  }

  getUser (name, isPredicate = false) {
    const user = this.users.get(name)
    if (user) { return Promise.resolve(user) }
    if (isPredicate) {
      return Promise.resolve(null)
    } else {
      const error = new ChatServiceError('noUser', name)
      return Promise.reject(error)
    }
  }

  addUser (name, state) {
    let user = this.users.get(name)
    if (user) {
      const error = new ChatServiceError('userExists', name)
      return Promise.reject(error)
    }
    user = new User(this.server, name)
    this.users.set(name, user)
    if (state) {
      return user.initState(state).return(user)
    } else {
      return Promise.resolve(user)
    }
  }

  removeUser (name) {
    this.users.delete(name)
    return Promise.resolve()
  }
}

module.exports = MemoryState
